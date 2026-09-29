import AppKit
import AVFoundation
import AVKit
import QuartzCore

final class DesktopWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class VideoSurface: NSView {
    let videoLayer: AVPlayerLayer
    init(player: AVPlayer) {
        videoLayer = AVPlayerLayer(player: player)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        videoLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(videoLayer)
    }
    required init?(coder: NSCoder) { fatalError("Not used") }
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.frame = bounds
        CATransaction.commit()
    }
}

final class DesktopPlayback {
    let window: DesktopWindow
    let player: AVQueuePlayer
    let looper: AVPlayerLooper
    let surface: VideoSurface
    var readiness: NSKeyValueObservation?

    init(screen: NSScreen, asset: AVAsset, time: CMTime?) {
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 3
        player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        looper = AVPlayerLooper(player: player, templateItem: item)
        surface = VideoSurface(player: player)
        window = DesktopWindow(contentRect: screen.frame, styleMask: .borderless,
                               backing: .buffered, defer: false, screen: screen)
        window.setFrame(screen.frame, display: true)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.isOpaque = true
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.title = "SpaceX Live Wallpaper"
        window.contentView = surface
        surface.frame = NSRect(origin: .zero, size: screen.frame.size)
        surface.layoutSubtreeIfNeeded()
        // Do not cover the existing wallpaper until a decoded frame is ready.
        readiness = surface.videoLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            if layer.isReadyForDisplay {
                DispatchQueue.main.async { self?.window.orderBack(nil) }
            }
        }
        if let time, time.seconds > 0 {
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    func close() {
        readiness = nil
        player.pause()
        looper.disableLooping()
        surface.videoLayer.player = nil
        player.removeAllItems()
        window.orderOut(nil)
        window.close()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var desktops: [DesktopPlayback] = []
    var statusItem: NSStatusItem?
    var pauseItem: NSMenuItem?
    var statusLabel: NSMenuItem?
    var asset: AVURLAsset?
    var paused = false
    var sleeping = false
    var locked = false
    var sessionInactive = false
    var preview: NSWindow?
    var previewPlayer: AVPlayer?
    var rebuildWork: DispatchWorkItem?
    let selfTest = CommandLine.arguments.contains("--self-test")
    let lowPowerPause = !CommandLine.arguments.contains("--ignore-low-power")
    var mediaURL: URL { Bundle.main.url(forResource: "SpaceX-4K-Loop", withExtension: "mp4")! }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !selfTest, let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        guard Bundle.main.url(forResource: "SpaceX-4K-Loop", withExtension: "mp4") != nil else {
            fail("The video is missing from the application bundle.")
            return
        }
        createMenu()
        observeLifecycle()
        let video = AVURLAsset(url: mediaURL)
        Task { @MainActor in
            do {
                let duration = try await video.load(.duration)
                guard duration.seconds.isFinite, duration.seconds > 1,
                      try await video.load(.isPlayable) else {
                    fail("The video could not be played.")
                    return
                }
                asset = video
                rebuildDisplays()
                if selfTest { runSelfTest(duration: duration.seconds) }
            } catch { fail(error.localizedDescription) }
        }
    }

    func createMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "SpaceX"
        statusItem?.button?.toolTip = "SpaceX Live Wallpaper"
        let menu = NSMenu()
        statusLabel = menu.addItem(withTitle: "4K · 30 fps · Silent loop", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        pauseItem = menu.addItem(withTitle: "Pause", action: #selector(togglePause), keyEquivalent: "p")
        menu.addItem(withTitle: "Preview Video…", action: #selector(showPreview), keyEquivalent: "")
        menu.addItem(withTitle: "Show Video in Finder", action: #selector(revealVideo), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit and Restore Wallpaper", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items where item.action != nil { item.target = self }
        statusItem?.menu = menu
    }

    func observeLifecycle() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(didWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(sessionResigned), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        ws.addObserver(self, selector: #selector(sessionActivated), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(powerChanged), name: .NSProcessInfoPowerStateDidChange, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(screenLocked), name: .init("com.apple.screenIsLocked"), object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(screenUnlocked), name: .init("com.apple.screenIsUnlocked"), object: nil)
    }

    @objc func screensChanged() {
        rebuildWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.rebuildDisplays() }
        rebuildWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func rebuildDisplays() {
        guard let asset else { return }
        let position = desktops.first?.player.currentTime()
        desktops.forEach { $0.close() }
        desktops = NSScreen.screens.map { DesktopPlayback(screen: $0, asset: asset, time: position) }
        applyPlaybackState()
    }

    func applyPlaybackState() {
        let savingPower = lowPowerPause && ProcessInfo.processInfo.isLowPowerModeEnabled
        let shouldPlay = !paused && !sleeping && !locked && !sessionInactive && !savingPower
        for desktop in desktops {
            shouldPlay ? desktop.player.play() : desktop.player.pause()
        }
        if shouldPlay { previewPlayer?.play() } else { previewPlayer?.pause() }
        pauseItem?.title = paused ? "Resume" : "Pause"
        statusLabel?.title = savingPower ? "Low Power Mode · Paused" : "4K · 30 fps · Silent loop"
    }

    @objc func togglePause() { paused.toggle(); applyPlaybackState() }
    @objc func willSleep() { sleeping = true; applyPlaybackState() }
    @objc func didWake() { sleeping = false; applyPlaybackState() }
    @objc func screenLocked() { locked = true; applyPlaybackState() }
    @objc func screenUnlocked() { locked = false; applyPlaybackState() }
    @objc func sessionResigned() { sessionInactive = true; applyPlaybackState() }
    @objc func sessionActivated() { sessionInactive = false; applyPlaybackState() }
    @objc func powerChanged() { applyPlaybackState() }
    @objc func revealVideo() { NSWorkspace.shared.activateFileViewerSelecting([mediaURL]) }
    @objc func quit() { NSApp.terminate(nil) }

    @objc func showPreview() {
        if let preview { preview.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 630),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "SpaceX · 29 September 2026"
        window.isReleasedWhenClosed = false
        window.aspectRatio = NSSize(width: 16, height: 9)
        let view = AVPlayerView()
        previewPlayer = AVPlayer(url: mediaURL)
        previewPlayer?.isMuted = true
        previewPlayer?.preventsDisplaySleepDuringVideoPlayback = false
        view.player = previewPlayer
        view.controlsStyle = .floating
        window.contentView = view
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        preview = window
        NotificationCenter.default.addObserver(self, selector: #selector(previewClosed), name: NSWindow.willCloseNotification, object: window)
        applyPlaybackState()
    }

    @objc func previewClosed() {
        previewPlayer?.pause()
        previewPlayer = nil
        preview = nil
    }

    func fail(_ message: String) {
        if selfTest { fputs("FAIL: \(message)\n", stderr); exit(1) }
        let alert = NSAlert()
        alert.messageText = "SpaceX Live Wallpaper"
        alert.informativeText = message
        alert.runModal()
        NSApp.terminate(nil)
    }

    // Integration test exercises the same players and desktop windows as the app.
    func runSelfTest(duration: Double) {
        Task { @MainActor in
            func wait(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
            var checks: [String: Bool] = [:]
            let original = NSScreen.screens.map { NSWorkspace.shared.desktopImageURL(for: $0)?.absoluteString ?? "" }
            await wait(3)
            checks["oneWindowPerScreen"] = !desktops.isEmpty && desktops.count == NSScreen.screens.count
            checks["allLayersDecoded"] = desktops.allSatisfy { $0.surface.videoLayer.isReadyForDisplay }
            checks["behindDesktopIcons"] = desktops.allSatisfy { $0.window.level.rawValue < Int(CGWindowLevelForKey(.desktopIconWindow)) }
            checks["ignoresMouse"] = desktops.allSatisfy { $0.window.ignoresMouseEvents }
            checks["mutedAllowsSleep"] = desktops.allSatisfy { $0.player.isMuted && !$0.player.preventsDisplaySleepDuringVideoPlayback }
            guard let first = desktops.first else { fail("No display was found."); return }
            checks["advances"] = first.player.currentTime().seconds > 0.1
            togglePause()
            let before = first.player.currentTime().seconds
            await wait(0.7)
            checks["pause"] = abs(first.player.currentTime().seconds - before) < 0.1
            togglePause()
            await wait(0.7)
            checks["resume"] = first.player.currentTime().seconds > before + 0.2
            togglePause()
            showPreview()
            await wait(0.5)
            checks["previewHonorsPause"] = previewPlayer?.rate == 0
            togglePause()
            await wait(1)
            checks["previewResumes"] = (previewPlayer?.currentTime().seconds ?? 0) > 0.1
            preview?.close()
            screenLocked()
            checks["lockPauses"] = desktops.allSatisfy { $0.player.rate == 0 }
            screenUnlocked()
            willSleep()
            checks["sleepPauses"] = desktops.allSatisfy { $0.player.rate == 0 }
            didWake()
            _ = await first.player.seek(to: CMTime(seconds: duration - 1, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            first.player.play()
            await wait(3)
            checks["loopsAtEnd"] = first.looper.loopCount >= 1 && first.player.currentTime().seconds < 5
            checks["noPlayerErrors"] = desktops.allSatisfy { $0.player.error == nil && $0.looper.status != .failed }
            rebuildDisplays()
            await wait(2)
            checks["rebuildDisplays"] = desktops.count == NSScreen.screens.count && desktops.allSatisfy { $0.surface.videoLayer.isReadyForDisplay }
            desktops.forEach { $0.close() }
            desktops.removeAll()
            checks["originalWallpaperPreserved"] = original == NSScreen.screens.map { NSWorkspace.shared.desktopImageURL(for: $0)?.absoluteString ?? "" }
            let result: [String: Any] = ["checks": checks, "passed": checks.values.allSatisfy { $0 },
                                         "os": ProcessInfo.processInfo.operatingSystemVersionString,
                                         "duration": duration, "screens": NSScreen.screens.count]
            let data = try! JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            print(String(data: data, encoding: .utf8)!)
            if let i = CommandLine.arguments.firstIndex(of: "--report"), CommandLine.arguments.count > i + 1 {
                try? data.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
            }
            exit(checks.values.allSatisfy { $0 } ? 0 : 1)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        rebuildWork?.cancel()
        desktops.forEach { $0.close() }
        previewPlayer?.pause()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()

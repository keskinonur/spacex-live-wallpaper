import AppKit
import AVFoundation

struct NativeWallpaperError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Isolates the undocumented macOS Aerial store from playback and UI.
struct NativeWallpaperStore {
    static let assetID = "85E727F2-2709-4C50-B503-27F886A7F203"
    static let categoryID = "49CBE28B-B24B-462B-AE52-C8EA3B299ACD"
    static let subcategoryID = "3A23F6AF-1166-494D-B939-9A91A6496382"
    let root: URL
    let backupRoot: URL
    var indexURL: URL { root.appendingPathComponent("Store/Index.plist") }
    var catalogURL: URL { root.appendingPathComponent("aerials/manifest/entries.json") }
    var movieURL: URL { root.appendingPathComponent("aerials/videos/\(Self.assetID).mov") }
    var thumbnailURL: URL { root.appendingPathComponent("aerials/thumbnails/\(Self.assetID).png") }
    var receiptURL: URL { backupRoot.appendingPathComponent("active-backup.txt") }

    static var current: Self {
        let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return Self(root: support.appendingPathComponent("com.apple.wallpaper"),
                    backupRoot: support.appendingPathComponent("SpaceX Live Wallpaper/Backups"))
    }

    private func dictionary(_ data: Data) throws -> [String: Any] {
        guard let value = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw NativeWallpaperError(message: "The system wallpaper settings could not be read.")
        }
        return value
    }

    func selectingMovie(in data: Data) throws -> Data {
        var index = try dictionary(data)
        // Refuse layouts whose per-display/per-Space choices would conflict with a global selection.
        guard let displays = index["Displays"] as? [String: Any], displays.isEmpty,
              let spaces = index["Spaces"] as? [String: Any], spaces.isEmpty else {
            throw NativeWallpaperError(message: "This wallpaper layout uses individual display or Space settings. Select one linked wallpaper for all displays in System Settings first, or use Desktop Only.")
        }
        for key in ["AllSpacesAndDisplays", "SystemDefault"] {
            guard var group = index[key] as? [String: Any], group["Type"] as? String == "linked",
                  var linked = group["Linked"] as? [String: Any],
                  var content = linked["Content"] as? [String: Any],
                  let choices = content["Choices"] as? [[String: Any]], choices.count == 1 else {
                throw NativeWallpaperError(message: "This macOS wallpaper layout is not supported. Select a linked Aerial wallpaper in System Settings first, or use Desktop Only.")
            }
            let config = try PropertyListSerialization.data(fromPropertyList: ["assetID": Self.assetID], format: .binary, options: 0)
            content["Choices"] = [["Provider": "com.apple.wallpaper.choice.aerials", "Files": [Any](), "Configuration": config]]
            content["Shuffle"] = "$null"
            content["EncodedOptionValues"] = "$null"
            linked["Content"] = content
            linked["LastSet"] = Date()
            linked["LastUse"] = Date()
            group["Linked"] = linked
            index[key] = group
        }
        return try PropertyListSerialization.data(fromPropertyList: index, format: .binary, options: 0)
    }

    /// Compare wallpaper choices and layout, excluding unrelated system metadata.
    func sameSelection(_ first: Data, _ second: Data) throws -> Bool {
        func selection(_ data: Data) throws -> NSDictionary {
            let value = try dictionary(data)
            var result: [String: Any] = [:]
            for key in ["AllSpacesAndDisplays", "SystemDefault"] {
                guard let group = value[key] as? [String: Any], let linked = group["Linked"] as? [String: Any],
                      let content = linked["Content"] as? [String: Any] else { return value as NSDictionary }
                result[key] = ["Type": group["Type"] ?? NSNull(), "Content": content]
            }
            result["Displays"] = value["Displays"] ?? NSNull()
            result["Spaces"] = value["Spaces"] ?? NSNull()
            return result as NSDictionary
        }
        return try selection(first).isEqual(selection(second))
    }

    func addingCatalogEntry(to data: Data) throws -> Data {
        guard var catalog = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var assets = catalog["assets"] as? [[String: Any]],
              var categories = catalog["categories"] as? [[String: Any]] else {
            throw NativeWallpaperError(message: "The macOS Aerial catalog is unavailable or has an unsupported format.")
        }
        assets.removeAll { $0["id"] as? String == Self.assetID }
        categories.removeAll { $0["id"] as? String == Self.categoryID }
        let name = "SpaceX Cinematic Launch"
        let preview = thumbnailURL.absoluteString
        assets.insert(["id": Self.assetID, "localizedNameKey": name, "accessibilityLabel": name,
                       "shotID": "SPACEX_CINEMATIC_50S", "showInTopLevel": true, "includeInShuffle": false,
                       "preferredOrder": 0, "categories": [Self.categoryID], "subcategories": [Self.subcategoryID],
                       "url-4K-SDR-240FPS": movieURL.absoluteString, "previewImage": preview,
                       "pointsOfInterest": [String: Any]()], at: 0)
        let subcategory: [String: Any] = ["id": Self.subcategoryID, "localizedNameKey": name,
            "localizedDescriptionKey": name, "preferredOrder": 0, "representativeAssetID": Self.assetID, "previewImage": preview]
        categories.insert(["id": Self.categoryID, "localizedNameKey": "SpaceX Live Wallpaper",
                           "localizedDescriptionKey": name, "preferredOrder": 0,
                           "representativeAssetID": Self.assetID, "previewImage": preview,
                           "subcategories": [subcategory]], at: 0)
        catalog["assets"] = assets
        catalog["categories"] = categories
        return try JSONSerialization.data(withJSONObject: catalog, options: [.sortedKeys])
    }

    private func activeBackup() throws -> URL? {
        guard FileManager.default.fileExists(atPath: receiptURL.path) else { return nil }
        let name = try String(contentsOf: receiptURL, encoding: .utf8)
        guard UUID(uuidString: name) != nil else { throw NativeWallpaperError(message: "The wallpaper backup receipt is invalid.") }
        return backupRoot.appendingPathComponent(name)
    }

    /// Assets must already be prepared. Selection is written last; backups precede all store writes.
    func apply() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: movieURL.path), fm.fileExists(atPath: thumbnailURL.path) else {
            throw NativeWallpaperError(message: "The native wallpaper media is missing.")
        }
        let original = try Data(contentsOf: indexURL)
        let catalog = try Data(contentsOf: catalogURL)
        let updated = try selectingMovie(in: original)
        let updatedCatalog = try addingCatalogEntry(to: catalog)
        if let backup = try activeBackup(),
           try sameSelection(original, Data(contentsOf: backup.appendingPathComponent("Applied.plist"))) {
            // Reapply after a catalog refresh without replacing the original restore point.
            guard try Data(contentsOf: indexURL) == original, try Data(contentsOf: catalogURL) == catalog else {
                throw NativeWallpaperError(message: "The system wallpaper changed during setup. Please try again.")
            }
            try updatedCatalog.write(to: catalogURL, options: .atomic)
            return
        }
        let backup = backupRoot.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: backup, withIntermediateDirectories: true)
        try original.write(to: backup.appendingPathComponent("Index.plist"), options: .atomic)
        try catalog.write(to: backup.appendingPathComponent("entries.json"), options: .atomic)
        try updated.write(to: backup.appendingPathComponent("Applied.plist"), options: .atomic)
        guard try Data(contentsOf: indexURL) == original, try Data(contentsOf: catalogURL) == catalog else {
            throw NativeWallpaperError(message: "The system wallpaper changed during setup. Please try again.")
        }
        let previousReceipt = try activeBackup()?.lastPathComponent
        // Publish the restore point before selection: a crash after the index write remains recoverable.
        try backup.lastPathComponent.write(to: receiptURL, atomically: true, encoding: .utf8)
        do {
            try updatedCatalog.write(to: catalogURL, options: .atomic)
            try updated.write(to: indexURL, options: .atomic)
        } catch {
            // Do not overwrite settings another process changed in the meantime.
            if (try? Data(contentsOf: indexURL)) == updated { try original.write(to: indexURL, options: .atomic) }
            if (try? Data(contentsOf: catalogURL)) == updatedCatalog { try catalog.write(to: catalogURL, options: .atomic) }
            if let previousReceipt { try previousReceipt.write(to: receiptURL, atomically: true, encoding: .utf8) }
            else { try fm.removeItem(at: receiptURL) }
            throw error
        }
    }

    func restore() throws {
        guard let backup = try activeBackup() else { throw NativeWallpaperError(message: "There is no previous wallpaper saved by this app.") }
        let current = try Data(contentsOf: indexURL)
        let original = try Data(contentsOf: backup.appendingPathComponent("Index.plist"))
        if try sameSelection(current, original) {
            // An interrupted apply may publish a receipt without ever changing selection.
            try FileManager.default.removeItem(at: receiptURL)
            return
        }
        guard try sameSelection(current, Data(contentsOf: backup.appendingPathComponent("Applied.plist"))) else {
            throw NativeWallpaperError(message: "Your wallpaper settings changed after SpaceX was applied. They have been left untouched. Select your preferred wallpaper in System Settings.")
        }
        let saved = try dictionary(original)
        var restored = try dictionary(current)
        for key in ["AllSpacesAndDisplays", "SystemDefault", "Displays", "Spaces"] { restored[key] = saved[key] }
        let restoredData = try PropertyListSerialization.data(fromPropertyList: restored, format: .binary, options: 0)
        guard try Data(contentsOf: indexURL) == current else { throw NativeWallpaperError(message: "The wallpaper changed during restore. Please try again.") }
        try restoredData.write(to: indexURL, options: .atomic)
        try FileManager.default.removeItem(at: receiptURL)
        // Keep catalog assets and backups: another Space may still refer to the media.
    }
}

final class NativeWallpaper {
    let store: NativeWallpaperStore
    init(store: NativeWallpaperStore = .current) { self.store = store }

    func apply(videoURL: URL) async throws {
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27 else {
            throw NativeWallpaperError(message: "Desktop & Lock Screen integration is currently supported only on macOS 27. Desktop Only playback remains available.")
        }
        // Validate before creating media or changing the store.
        _ = try store.selectingMovie(in: Data(contentsOf: store.indexURL))
        _ = try store.addingCatalogEntry(to: Data(contentsOf: store.catalogURL))
        try await prepareMedia(videoURL: videoURL)
        try store.apply()
        try reloadSystemWallpaper()
    }

    func prepareMedia(videoURL: URL) async throws {
        let fm = FileManager.default
        let stage = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: stage) }
        let asset = AVURLAsset(url: videoURL)
        let movie = stage.appendingPathComponent("wallpaper.mov")
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw NativeWallpaperError(message: "The native wallpaper video could not be prepared.")
        }
        export.shouldOptimizeForNetworkUse = true
        if #available(macOS 15, *) {
            try await export.export(to: movie, as: .mov)
        } else {
            export.outputURL = movie
            export.outputFileType = .mov
            await export.export()
            guard export.status == .completed else { throw export.error ?? NativeWallpaperError(message: "Video preparation failed.") }
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1920, height: 1080)
        let frame = try await generator.image(at: CMTime(seconds: 3, preferredTimescale: 600)).image
        guard let png = NSBitmapImageRep(cgImage: frame).representation(using: .png, properties: [:]) else {
            throw NativeWallpaperError(message: "The wallpaper thumbnail could not be prepared.")
        }
        try fm.createDirectory(at: store.movieURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: store.thumbnailURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Fixed app-owned identifiers never replace other wallpapers' media.
        try Data(contentsOf: movie, options: .mappedIfSafe).write(to: store.movieURL, options: .atomic)
        try png.write(to: store.thumbnailURL, options: .atomic)
    }

    func restore() throws { try store.restore(); try reloadSystemWallpaper() }

    private func reloadSystemWallpaper() throws {
        for name in ["WallpaperAerialsExtension", "WallpaperAgent"] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            process.arguments = ["-u", String(getuid()), "-x", name]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 || process.terminationStatus == 1 else {
                throw NativeWallpaperError(message: "The wallpaper settings were saved, but macOS could not reload them. Log out and back in to load the selected wallpaper.")
            }
        }
    }
}

import AppKit
import AVFoundation

@main
struct NativeWallpaperTests {
    @MainActor
    static func main() async throws {
        let fm = FileManager.default
        let temporary = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temporary) }
        let store = NativeWallpaperStore(root: temporary.appendingPathComponent("Aerial Store"), backupRoot: temporary.appendingPathComponent("Backups"))
        let oldConfig = try PropertyListSerialization.data(fromPropertyList: ["assetID": "OTHER-WALLPAPER"], format: .binary, options: 0)
        let group: [String: Any] = ["Type": "linked", "Linked": ["Content": ["Choices": [["Provider": "com.apple.wallpaper.choice.aerials", "Files": [], "Configuration": oldConfig]], "Shuffle": "$null", "EncodedOptionValues": "$null"], "LastSet": Date(), "LastUse": Date()]]
        let fixture: [String: Any] = ["AllSpacesAndDisplays": group, "SystemDefault": group, "Displays": [String: Any](), "Spaces": [String: Any](), "Unrelated": "preserved"]
        func plist(_ value: [String: Any]) throws -> Data { try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0) }
        let original = try plist(fixture)
        let catalog = try JSONSerialization.data(withJSONObject: ["assets": [["id": "OTHER-WALLPAPER"]], "categories": [["id": "OTHER-CATEGORY"]], "initialAssetCount": 4, "version": 1])
        try fm.createDirectory(at: store.indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: store.catalogURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try original.write(to: store.indexURL)
        try catalog.write(to: store.catalogURL)
        var checks: [String: Bool] = [:]
        func rejects(_ operation: () throws -> Void) -> Bool { do { try operation(); return false } catch { return true } }
        checks["missingMediaRejected"] = rejects { try store.apply() }
        checks["invalidCatalogRejected"] = rejects { _ = try store.addingCatalogEntry(to: Data("{}".utf8)) }
        var unsupported = fixture
        unsupported["Displays"] = ["display": group]
        checks["perDisplaySelectionRejected"] = rejects { _ = try store.selectingMovie(in: plist(unsupported)) }
        unsupported = fixture
        unsupported["AllSpacesAndDisplays"] = ["Type": "individual"]
        checks["unknownLayoutRejected"] = rejects { _ = try store.selectingMovie(in: plist(unsupported)) }
        checks["validationPreservesSettings"] = try Data(contentsOf: store.indexURL) == original && Data(contentsOf: store.catalogURL) == catalog
        let source = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("SpaceX-4K-Loop.mp4")
        try await NativeWallpaper(store: store).prepareMedia(videoURL: source)
        let nativeAsset = AVURLAsset(url: store.movieURL)
        let duration = try await nativeAsset.load(.duration).seconds
        checks["nativeMOVPlayable"] = try await nativeAsset.load(.isPlayable) && abs(duration - 50) < 0.05
        checks["nativeThumbnailReadable"] = NSImage(contentsOf: store.thumbnailURL) != nil
        try store.apply()
        let applied = try Data(contentsOf: store.indexURL)
        let appliedPlist = try PropertyListSerialization.propertyList(from: applied, format: nil) as! [String: Any]
        checks["unrelatedSettingsPreserved"] = appliedPlist["Unrelated"] as? String == "preserved"
        checks["bothSelectionsMatch"] = try ["AllSpacesAndDisplays", "SystemDefault"].allSatisfy { key in
            let g = appliedPlist[key] as! [String: Any]
            let linked = g["Linked"] as! [String: Any]
            let content = linked["Content"] as! [String: Any]
            let choice = (content["Choices"] as! [[String: Any]])[0]
            let config = try PropertyListSerialization.propertyList(from: choice["Configuration"] as! Data, format: nil) as! [String: Any]
            return config["assetID"] as? String == NativeWallpaperStore.assetID
        }
        let receipt = try Data(contentsOf: store.receiptURL)
        try store.apply()
        checks["reapplyPreservesBackup"] = try Data(contentsOf: store.receiptURL) == receipt
        let merged = try JSONSerialization.jsonObject(with: Data(contentsOf: store.catalogURL)) as! [String: Any]
        checks["catalogMergePreservesOthers"] = (merged["assets"] as! [[String: Any]]).count == 2 && (merged["categories"] as! [[String: Any]]).count == 2 && merged["initialAssetCount"] as? Int == 4
        let entry = (merged["assets"] as! [[String: Any]])[0]
        checks["fileURLsEscapeSpaces"] = (entry["url-4K-SDR-240FPS"] as? String)?.contains("Aerial%20Store") == true
        var used = appliedPlist
        for key in ["AllSpacesAndDisplays", "SystemDefault"] {
            var g = used[key] as! [String: Any]
            var linked = g["Linked"] as! [String: Any]
            linked["LastUse"] = Date(timeIntervalSinceNow: 200)
            g["Linked"] = linked
            used[key] = g
        }
        try plist(used).write(to: store.indexURL)
        try store.restore()
        checks["restoreIgnoresUsageTimestamps"] = try store.sameSelection(Data(contentsOf: store.indexURL), original)
        checks["restoreKeepsMedia"] = fm.fileExists(atPath: store.movieURL.path)
        checks["restoreClearsReceipt"] = !fm.fileExists(atPath: store.receiptURL.path)
        try store.apply()
        var other = fixture
        other["Spaces"] = ["new-space": group]
        let laterChoice = try plist(other)
        try laterChoice.write(to: store.indexURL)
        checks["laterUserChoiceProtected"] = rejects { try store.restore() }
        checks["laterUserChoiceUnchanged"] = try Data(contentsOf: store.indexURL) == laterChoice
        // A changed metadata field must not replace the true previous selection on reapply.
        try applied.write(to: store.indexURL)
        let beforeMetadata = try Data(contentsOf: store.receiptURL)
        var metadata = appliedPlist
        metadata["Unrelated"] = "updated by macOS"
        try plist(metadata).write(to: store.indexURL)
        try store.apply()
        checks["metadataChangePreservesRestorePoint"] = try Data(contentsOf: store.receiptURL) == beforeMetadata
        try store.restore()
        let restored = try PropertyListSerialization.propertyList(from: Data(contentsOf: store.indexURL), format: nil) as! [String: Any]
        checks["restorePreservesNewMetadata"] = restored["Unrelated"] as? String == "updated by macOS"
        checks["restorePreviousChoiceAfterMetadataChange"] = try store.sameSelection(Data(contentsOf: store.indexURL), original)
        // Simulate a crash after receipt publication and before the system selection write.
        try original.write(to: store.indexURL)
        try beforeMetadata.write(to: store.receiptURL)
        try store.restore()
        checks["interruptedApplyBeforeSelectionIsRecoverable"] = !fm.fileExists(atPath: store.receiptURL.path)
        // Simulate a crash after the system selection write: the receipt is already durable.
        try applied.write(to: store.indexURL)
        try beforeMetadata.write(to: store.receiptURL)
        try store.restore()
        checks["interruptedApplyAfterSelectionRestoresOriginal"] = try store.sameSelection(Data(contentsOf: store.indexURL), original)
        let report: [String: Any] = ["checks": checks, "passed": checks.values.allSatisfy { $0 }, "scope": "Temporary fixtures and real bundled-video MOV export; live system settings were not modified.", "os": ProcessInfo.processInfo.operatingSystemVersionString]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted])
        try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("Tests/native-wallpaper.json"))
        print(String(data: data, encoding: .utf8)!)
        exit(checks.values.allSatisfy { $0 } ? 0 : 1)
    }
}

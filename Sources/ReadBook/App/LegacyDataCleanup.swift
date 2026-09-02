import Foundation
import ReadBookCore

enum LegacyDataCleanup {
    static func run() {
        clearLegacyPreferences(in: .standard)
        let root = AppPaths().root
        _ = Task.detached(priority: .utility) {
            removeReadBookOwnedLegacyFiles(at: root)
        }
    }

    static func clearLegacyPreferences(in defaults: UserDefaults) {
        defaults.removeObject(forKey: "speechModelDownloadSourceMode")
        defaults.removeObject(forKey: "speechModelCustomMirrorURL")
    }

    static func removeReadBookOwnedLegacyFiles(
        at root: URL,
        fileManager: FileManager = .default
    ) {
        let legacyModelsRoot = root.appendingPathComponent("Models", isDirectory: true)
        guard fileManager.fileExists(atPath: legacyModelsRoot.path) else { return }
        try? fileManager.removeItem(at: legacyModelsRoot)
    }
}

import Foundation
import ReadBookCore

enum LegacyDataCleanup {
    static func run() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "speechModelDownloadSourceMode")
        defaults.removeObject(forKey: "speechModelCustomMirrorURL")

        let legacyModelsRoot = AppPaths().root.appendingPathComponent("Models", isDirectory: true)
        _ = Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: legacyModelsRoot.path) else { return }
            try? FileManager.default.removeItem(at: legacyModelsRoot)
        }
    }
}

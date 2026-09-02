import Foundation
import XCTest
@testable import ReadBook

final class LegacyDataCleanupTests: XCTestCase {
    func testCleanupRemovesReadBookOwnedModelsAndLegacyModelSettings() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadBookLegacyCleanupTests-\(UUID().uuidString)", isDirectory: true)
        let modelsRoot = root.appendingPathComponent("Models", isDirectory: true)
        try FileManager.default.createDirectory(at: modelsRoot, withIntermediateDirectories: true)
        try Data("legacy-model".utf8).write(to: modelsRoot.appendingPathComponent("weights.bin"))
        defer { try? FileManager.default.removeItem(at: root) }

        let suite = "ReadBookLegacyCleanupTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("customMirror", forKey: "speechModelDownloadSourceMode")
        defaults.set("https://example.invalid", forKey: "speechModelCustomMirrorURL")

        LegacyDataCleanup.clearLegacyPreferences(in: defaults)
        LegacyDataCleanup.removeReadBookOwnedLegacyFiles(at: root)

        XCTAssertFalse(FileManager.default.fileExists(atPath: modelsRoot.path))
        XCTAssertNil(defaults.object(forKey: "speechModelDownloadSourceMode"))
        XCTAssertNil(defaults.object(forKey: "speechModelCustomMirrorURL"))
    }
}

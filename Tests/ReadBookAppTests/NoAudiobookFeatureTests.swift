import Foundation
import XCTest

final class NoAudiobookFeatureTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testAudiobookImplementationIsAbsentFromProduct() throws {
        let forbiddenPaths = [
            "Sources/ReadBook/Speech",
            "Sources/ReadBookCore/Speech",
            "Sources/ReadBook/Reader/PagedAudiobookNavigation.swift",
            "DesignAssets/MLX",
            "docs/audiobook-handoff-2026-09-01.md",
            "docs/superpowers/specs/2026-09-01-audiobook-listening-design.md",
            "docs/superpowers/plans/2026-09-01-audiobook-listening.md",
        ]

        for path in forbiddenPaths {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: repositoryRoot.appendingPathComponent(path).path),
                "Audiobook-only path must not exist: \(path)"
            )
        }

        try assertFile("Package.swift", excludes: ["mlx-audio-swift", "MLXAudio"])
        try assertFile("Package.resolved", excludes: ["mlx-audio-swift", "mlx-swift", "swift-huggingface"])
        try assertFile("Scripts/build-app.sh", excludes: ["mlx.metallib", "MLX audio"])
        try assertFile("Sources/ReadBookCore/Storage/AppPaths.swift", excludes: ["modelsRoot", "modelDownloadsRoot"])
        try assertFile("Sources/ReadBook/App/AppModel.swift", excludes: ["Audiobook", "audiobook", "SpeechModel", "speechModel"])
        try assertFile("Sources/ReadBook/App/ReadBookApp.swift", excludes: ["audiobookController"])
        try assertFile("Sources/ReadBook/Reader/ReaderRootView.swift", excludes: ["Audiobook", "audiobook", "selectedSpeechRange", "headphones"])
        try assertFile("Sources/ReadBook/Reader/ReaderToolbar.swift", excludes: ["Audiobook", "audiobook", "speechRate", "headphones"])
        try assertFile("Sources/ReadBook/Reader/ContinuousTextView.swift", excludes: ["highlightedRange", "onSelectionChanged"])
        try assertFile("Sources/ReadBook/Reader/PagedTextView.swift", excludes: ["highlightedRange", "onSelectionChanged"])
        try assertFile("Sources/ReadBook/Settings/SettingsView.swift", excludes: ["听书", "SpeechModel", "speechModel", "Qwen", "Hugging Face"])
        try assertFile("Sources/ReadBookCore/Models/ReaderPreferences.swift", excludes: ["speechRate"])
    }

    private func assertFile(_ path: String, excludes forbiddenTerms: [String]) throws {
        let url = repositoryRoot.appendingPathComponent(path)
        let contents = try String(contentsOf: url, encoding: .utf8)
        for term in forbiddenTerms {
            XCTAssertFalse(contents.contains(term), "\(path) must not contain audiobook-only term: \(term)")
        }
    }
}

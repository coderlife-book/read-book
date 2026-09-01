#if os(macOS)
import Foundation
import XCTest
@testable import ReadBook

@MainActor
final class SpeechModelManagerTests: XCTestCase {
    func testExistingTTSOnlyReportsAlignerBytesMissing() async throws {
        let fixture = try SpeechManagerFixture(installedKinds: [.tts])
        let manager = SpeechModelManager(
            locator: fixture.locator,
            downloader: fixture.downloader,
            stopper: fixture.stopper,
            modelsRoot: fixture.modelsRoot
        )

        await manager.discover()

        XCTAssertEqual(
            manager.state,
            .notInstalled(missingBytes: SpeechModelCatalog.aligner.approximateBytes)
        )
    }

    func testDeleteStopsBeforeRemovingOwnedModels() async throws {
        let fixture = try SpeechManagerFixture(installedKinds: [.tts, .aligner])
        let manager = SpeechModelManager(
            locator: fixture.locator,
            downloader: fixture.downloader,
            stopper: fixture.stopper,
            modelsRoot: fixture.modelsRoot
        )

        try await manager.deleteInstalledModels()

        let stopCount = await fixture.stopper.stopCount
        XCTAssertEqual(stopCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.modelsRoot.path))
    }
}

private final class SpeechManagerFixture {
    let root: URL
    let modelsRoot: URL
    let locator: SpeechModelLocator
    let downloader = NoopSpeechModelDownloader()
    let stopper = RecordingSpeechPlaybackStopper()

    init(installedKinds: Set<SpeechModelKind>) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadBookSpeechManager-\(UUID().uuidString)", isDirectory: true)
        modelsRoot = root.appendingPathComponent("Models", isDirectory: true)
        locator = SpeechModelLocator(ownedRoot: modelsRoot, externalHubRoots: [])
        try FileManager.default.createDirectory(at: modelsRoot, withIntermediateDirectories: true)
        for descriptor in SpeechModelCatalog.all where installedKinds.contains(descriptor.kind) {
            try makeSnapshot(descriptor)
        }
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    private func makeSnapshot(_ descriptor: SpeechModelDescriptor) throws {
        let snapshot = modelsRoot
            .appendingPathComponent(descriptor.kind.rawValue, isDirectory: true)
            .appendingPathComponent(descriptor.revision, isDirectory: true)
        for relativePath in descriptor.requiredRelativePaths {
            let file = snapshot.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if relativePath == "model.safetensors.index.json" {
                try JSONSerialization.data(withJSONObject: ["weight_map": ["layer": "model.safetensors"]]).write(to: file)
            } else {
                try Data(relativePath.utf8).write(to: file)
            }
        }
    }
}

private actor NoopSpeechModelDownloader: SpeechModelDownloading {
    func download(
        _ descriptor: SpeechModelDescriptor,
        to modelsRoot: URL,
        progress: @Sendable (SpeechDownloadProgress) -> Void
    ) async throws -> URL {
        throw CancellationError()
    }
}

private actor RecordingSpeechPlaybackStopper: SpeechPlaybackStopping {
    private(set) var stopCount = 0
    func stopForModelDeletion() async { stopCount += 1 }
}
#endif

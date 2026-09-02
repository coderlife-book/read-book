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

    func testDiscoverTracksInstalledKinds() async throws {
        let fixture = try SpeechManagerFixture(installedKinds: [.tts])
        let manager = SpeechModelManager(
            locator: fixture.locator,
            downloader: fixture.downloader,
            stopper: fixture.stopper,
            modelsRoot: fixture.modelsRoot
        )

        await manager.discover()

        XCTAssertEqual(manager.installedKinds, [.tts])
    }

    func testPrepareMissingModelsInstallsMissingKindsAndTracksProgress() async throws {
        let fixture = try SpeechManagerFixture(installedKinds: [])
        let writingDownloader = SnapshotWritingSpeechModelDownloader(root: fixture.modelsRoot)
        let manager = SpeechModelManager(
            locator: fixture.locator,
            downloader: writingDownloader,
            stopper: fixture.stopper,
            modelsRoot: fixture.modelsRoot
        )

        await manager.prepareMissingModels()

        XCTAssertEqual(manager.installedKinds, [.tts, .aligner])
        if case .ready = manager.state {
            // expected
        } else {
            XCTFail("expected ready after downloads, got \(manager.state)")
        }
        let callCount = await writingDownloader.callCount
        XCTAssertEqual(callCount, 2)
    }

    func testOlderDownloadFinishingDoesNotClearNewerActiveDownload() async throws {
        let fixture = try SpeechManagerFixture(installedKinds: [])
        let overlappingDownloader = OverlappingSpeechModelDownloader()
        let manager = SpeechModelManager(
            locator: fixture.locator,
            downloader: overlappingDownloader,
            stopper: fixture.stopper,
            modelsRoot: fixture.modelsRoot
        )

        let ttsTask = Task { await manager.prepareModel(.tts) }
        await overlappingDownloader.waitUntilStarted(.tts)

        let alignerTask = Task { await manager.prepareModel(.aligner) }
        await overlappingDownloader.waitUntilStarted(.aligner)
        XCTAssertEqual(manager.downloadingKind, .aligner)

        await overlappingDownloader.finish(.tts)
        await ttsTask.value

        XCTAssertEqual(
            manager.downloadingKind,
            .aligner,
            "an older download finishing must not clear the newer active download badge"
        )

        await overlappingDownloader.finish(.aligner)
        await alignerTask.value
    }

    func testNewerDownloadFinishingRestoresOlderStillActiveDownload() async throws {
        let fixture = try SpeechManagerFixture(installedKinds: [])
        let overlappingDownloader = OverlappingSpeechModelDownloader()
        let manager = SpeechModelManager(
            locator: fixture.locator,
            downloader: overlappingDownloader,
            stopper: fixture.stopper,
            modelsRoot: fixture.modelsRoot
        )

        let ttsTask = Task { await manager.prepareModel(.tts) }
        await overlappingDownloader.waitUntilStarted(.tts)

        let alignerTask = Task { await manager.prepareModel(.aligner) }
        await overlappingDownloader.waitUntilStarted(.aligner)
        XCTAssertEqual(manager.downloadingKind, .aligner)

        await overlappingDownloader.finish(.aligner)
        await alignerTask.value

        XCTAssertEqual(
            manager.downloadingKind,
            .tts,
            "when the foreground download finishes, another still-active background download must remain visible"
        )

        await overlappingDownloader.finish(.tts)
        await ttsTask.value
    }

    func testDeleteClearsInstalledKinds() async throws {
        let fixture = try SpeechManagerFixture(installedKinds: [.tts, .aligner])
        let manager = SpeechModelManager(
            locator: fixture.locator,
            downloader: fixture.downloader,
            stopper: fixture.stopper,
            modelsRoot: fixture.modelsRoot
        )
        await manager.discover()
        XCTAssertEqual(manager.installedKinds, [.tts, .aligner])

        try await manager.deleteInstalledModels()

        XCTAssertTrue(manager.installedKinds.isEmpty)
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
        try writeSnapshot(descriptor, to: snapshot)
    }
}

private final class SnapshotWriteLock: @unchecked Sendable {
    private let lock = NSLock()

    func write(_ descriptor: SpeechModelDescriptor, to snapshot: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        try writeSnapshot(descriptor, to: snapshot)
    }
}

private func writeSnapshot(_ descriptor: SpeechModelDescriptor, to snapshot: URL) throws {
    for relativePath in descriptor.requiredRelativePaths {
        let file = snapshot.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if relativePath == "model.safetensors.index.json" {
            try JSONSerialization.data(
                withJSONObject: ["weight_map": ["layer": "model.safetensors"]]
            ).write(to: file)
        } else {
            try Data(relativePath.utf8).write(to: file)
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

private actor SnapshotWritingSpeechModelDownloader: SpeechModelDownloading {
    let root: URL
    private(set) var callCount = 0

    init(root: URL) {
        self.root = root
    }

    func download(
        _ descriptor: SpeechModelDescriptor,
        to modelsRoot: URL,
        progress: @Sendable (SpeechDownloadProgress) -> Void
    ) async throws -> URL {
        callCount += 1
        let snapshot = modelsRoot
            .appendingPathComponent(descriptor.kind.rawValue, isDirectory: true)
            .appendingPathComponent(descriptor.revision, isDirectory: true)
        try writeSnapshot(descriptor, to: snapshot)
        let total = descriptor.requiredRelativePaths.reduce(Int64(0)) { $0 + Int64($1.utf8.count) }
        progress(SpeechDownloadProgress(downloadedBytes: total, totalBytes: total))
        return snapshot
    }
}

private actor OverlappingSpeechModelDownloader: SpeechModelDownloading {
    private var startedKinds: Set<SpeechModelKind> = []
    private var finishContinuations: [SpeechModelKind: CheckedContinuation<Void, Never>] = [:]
    private let writeLock = SnapshotWriteLock()

    func download(
        _ descriptor: SpeechModelDescriptor,
        to modelsRoot: URL,
        progress: @Sendable (SpeechDownloadProgress) -> Void
    ) async throws -> URL {
        startedKinds.insert(descriptor.kind)
        progress(SpeechDownloadProgress(downloadedBytes: 25, totalBytes: 100))

        await withCheckedContinuation { continuation in
            finishContinuations[descriptor.kind] = continuation
        }

        let snapshot = modelsRoot
            .appendingPathComponent(descriptor.kind.rawValue, isDirectory: true)
            .appendingPathComponent(descriptor.revision, isDirectory: true)
        try writeLock.write(descriptor, to: snapshot)
        return snapshot
    }

    func waitUntilStarted(_ kind: SpeechModelKind) async {
        while !startedKinds.contains(kind) {
            await Task.yield()
        }
    }

    func finish(_ kind: SpeechModelKind) {
        finishContinuations.removeValue(forKey: kind)?.resume()
    }
}
#endif

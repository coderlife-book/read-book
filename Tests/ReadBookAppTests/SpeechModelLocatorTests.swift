#if os(macOS)
import Foundation
import XCTest
@testable import ReadBook

final class SpeechModelLocatorTests: XCTestCase {
    func testPrototypeHubContainsPinnedModelsWhenOptedIn() throws {
        guard let hubPath = ProcessInfo.processInfo.environment["READBOOK_PROTOTYPE_HUB"] else {
            throw XCTSkip("Set READBOOK_PROTOTYPE_HUB for the local cache diagnostic")
        }
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadBookEmptyOwned-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let locator = SpeechModelLocator(
            ownedRoot: fixtureRoot,
            externalHubRoots: [URL(fileURLWithPath: hubPath, isDirectory: true)]
        )

        XCTAssertTrue(try locator.locateAll().isReady)
    }

    func testOwnedModelsContainPinnedRevisionsWhenOptedIn() throws {
        guard let modelsPath = ProcessInfo.processInfo.environment["READBOOK_OWNED_MODELS"] else {
            throw XCTSkip("Set READBOOK_OWNED_MODELS for the installed-model diagnostic")
        }
        let locator = SpeechModelLocator(
            ownedRoot: URL(fileURLWithPath: modelsPath, isDirectory: true),
            externalHubRoots: []
        )

        XCTAssertTrue(try locator.locateAll().isReady)
    }

    func testReadBookSnapshotWinsOverExternalHuggingFaceCache() throws {
        let fixture = try SpeechModelFixture()
        let owned = try fixture.makeValidSnapshot(for: SpeechModelCatalog.tts, root: fixture.ownedRoot)
        _ = try fixture.makeValidSnapshot(for: SpeechModelCatalog.tts, root: fixture.externalHubRoot)
        let locator = SpeechModelLocator(
            ownedRoot: fixture.ownedRoot,
            externalHubRoots: [fixture.externalHubRoot]
        )

        XCTAssertEqual(try locator.locate(SpeechModelCatalog.tts), owned)
    }

    func testIncompleteSnapshotIsRejected() throws {
        let fixture = try SpeechModelFixture()
        let snapshot = try fixture.makeValidSnapshot(
            for: SpeechModelCatalog.aligner,
            root: fixture.externalHubRoot
        )
        try Data().write(to: snapshot.appendingPathComponent("download.incomplete"))

        XCTAssertNil(try fixture.locator.locate(SpeechModelCatalog.aligner))
    }

    func testMissingIndexedShardIsRejected() throws {
        let fixture = try SpeechModelFixture()
        let snapshot = try fixture.makeValidSnapshot(
            for: SpeechModelCatalog.aligner,
            root: fixture.externalHubRoot
        )
        let index = ["weight_map": ["layer": "missing-shard.safetensors"]]
        let data = try JSONSerialization.data(withJSONObject: index)
        try data.write(to: snapshot.appendingPathComponent("model.safetensors.index.json"))

        XCTAssertNil(try fixture.locator.locate(SpeechModelCatalog.aligner))
    }

    func testLocateAllReportsKindsIndependently() throws {
        let fixture = try SpeechModelFixture()
        let tts = try fixture.makeValidSnapshot(
            for: SpeechModelCatalog.tts,
            root: fixture.externalHubRoot
        )

        let result = try fixture.locator.locateAll()

        XCTAssertEqual(result.tts, tts)
        XCTAssertNil(result.aligner)
        XCTAssertFalse(result.isReady)
    }
}

private final class SpeechModelFixture {
    let root: URL
    let ownedRoot: URL
    let externalHubRoot: URL

    var locator: SpeechModelLocator {
        SpeechModelLocator(ownedRoot: ownedRoot, externalHubRoots: [externalHubRoot])
    }

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadBookSpeechLocator-\(UUID().uuidString)", isDirectory: true)
        ownedRoot = root.appendingPathComponent("owned", isDirectory: true)
        externalHubRoot = root.appendingPathComponent("hub", isDirectory: true)
        try FileManager.default.createDirectory(at: ownedRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalHubRoot, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func makeValidSnapshot(
        for descriptor: SpeechModelDescriptor,
        root: URL
    ) throws -> URL {
        let snapshot: URL
        if root == ownedRoot {
            snapshot = root
                .appendingPathComponent(descriptor.kind.rawValue, isDirectory: true)
                .appendingPathComponent(descriptor.revision, isDirectory: true)
        } else {
            snapshot = root
                .appendingPathComponent(descriptor.huggingFaceCacheName, isDirectory: true)
                .appendingPathComponent("snapshots", isDirectory: true)
                .appendingPathComponent(descriptor.revision, isDirectory: true)
        }

        for relativePath in descriptor.requiredRelativePaths {
            let file = snapshot.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if relativePath == "model.safetensors.index.json" {
                let index = ["weight_map": ["layer": "model.safetensors"]]
                try JSONSerialization.data(withJSONObject: index).write(to: file)
            } else {
                try Data(relativePath.utf8).write(to: file)
            }
        }
        return snapshot
    }
}
#endif

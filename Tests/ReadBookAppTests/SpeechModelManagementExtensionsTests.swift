#if os(macOS)
import Foundation
import XCTest
@testable import ReadBook

@MainActor
final class SpeechModelManagementExtensionsTests: XCTestCase {
    func testCustomDownloadSourceBuildsResolveURLFromConfiguredBase() async throws {
        let transport = ModelManagementRecordingTransport(total: 3, body: Data("abc".utf8))
        let downloader = SpeechModelDownloader(transport: transport)
        let descriptor = SpeechModelDescriptor(
            kind: .aligner,
            repoID: "example/test-model",
            revision: "test-revision",
            approximateBytes: 3,
            requiredRelativePaths: ["weights/model.safetensors"]
        )
        let root = temporaryDirectory(named: "ReadBookCustomSource")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = SpeechModelDownloadSource(
            baseURL: URL(string: "https://mirror.example/hf")!
        )

        _ = try await downloader.download(descriptor, source: source, to: root) { _ in }

        let urls = await transport.requestedURLs
        XCTAssertEqual(
            urls,
            [
                URL(string: "https://mirror.example/hf/example/test-model/resolve/test-revision/weights/model.safetensors")!,
                URL(string: "https://mirror.example/hf/example/test-model/resolve/test-revision/weights/model.safetensors")!,
            ]
        )
    }

    func testLocatorValidatesDirectSnapshotForManualImport() throws {
        let root = temporaryDirectory(named: "ReadBookDirectSnapshot")
        defer { try? FileManager.default.removeItem(at: root) }
        let descriptor = SpeechModelDescriptor(
            kind: .tts,
            repoID: "example/test-model",
            revision: "test-revision",
            approximateBytes: 3,
            requiredRelativePaths: ["config.json", "model.safetensors"]
        )
        try writeValidSnapshot(descriptor, to: root)
        let locator = SpeechModelLocator(ownedRoot: root.appendingPathComponent("owned"), externalHubRoots: [])

        XCTAssertTrue(try locator.validateSnapshot(root, descriptor: descriptor))
    }

    func testManagerImportsValidatedDirectoryIntoOwnedModels() async throws {
        let root = temporaryDirectory(named: "ReadBookManualImport")
        defer { try? FileManager.default.removeItem(at: root) }
        let modelsRoot = root.appendingPathComponent("Models", isDirectory: true)
        let source = root.appendingPathComponent("DownloadedTTS", isDirectory: true)
        try writeValidSnapshot(SpeechModelCatalog.tts, to: source)
        let manager = SpeechModelManager(
            locator: SpeechModelLocator(ownedRoot: modelsRoot, externalHubRoots: []),
            downloader: SpeechModelDownloader(transport: ModelManagementRecordingTransport(total: 1, body: Data())),
            stopper: ModelManagementStopper(),
            modelsRoot: modelsRoot
        )

        await manager.importModel(.tts, from: source)

        XCTAssertEqual(manager.installedKinds, [.tts])
        let installed = modelsRoot
            .appendingPathComponent("tts", isDirectory: true)
            .appendingPathComponent(SpeechModelCatalog.tts.revision, isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.appendingPathComponent("config.json").path))
        XCTAssertTrue(try manager.locatorForTesting.validateSnapshot(installed, descriptor: SpeechModelCatalog.tts))
    }

    func testManagerSurfacesTimeoutReason() async throws {
        let root = temporaryDirectory(named: "ReadBookTimeoutReason")
        defer { try? FileManager.default.removeItem(at: root) }
        let modelsRoot = root.appendingPathComponent("Models", isDirectory: true)
        let manager = SpeechModelManager(
            locator: SpeechModelLocator(ownedRoot: modelsRoot, externalHubRoots: []),
            downloader: SpeechModelDownloader(transport: ModelManagementTimeoutTransport()),
            stopper: ModelManagementStopper(),
            modelsRoot: modelsRoot
        )

        await manager.prepareModel(.tts, source: .huggingFace)

        XCTAssertEqual(manager.state, .failed("模型下载失败：网络连接超时。"))
    }

    private func temporaryDirectory(named name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    }

    private func writeValidSnapshot(_ descriptor: SpeechModelDescriptor, to snapshot: URL) throws {
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
    }
}

private actor ModelManagementRecordingTransport: SpeechDownloadTransport {
    let total: Int64
    let body: Data
    private(set) var requestedURLs: [URL] = []

    init(total: Int64, body: Data) {
        self.total = total
        self.body = body
    }

    func contentLength(for url: URL) async throws -> Int64 {
        requestedURLs.append(url)
        return total
    }

    func bytes(for url: URL, startingAt offset: Int64) async throws -> AsyncThrowingStream<Data, Error> {
        requestedURLs.append(url)
        return AsyncThrowingStream { continuation in
            continuation.yield(body)
            continuation.finish()
        }
    }
}

private actor ModelManagementTimeoutTransport: SpeechDownloadTransport {
    func contentLength(for url: URL) async throws -> Int64 {
        throw URLError(.timedOut)
    }

    func bytes(for url: URL, startingAt offset: Int64) async throws -> AsyncThrowingStream<Data, Error> {
        throw URLError(.timedOut)
    }
}

private actor ModelManagementStopper: SpeechPlaybackStopping {
    func stopForModelDeletion() async {}
}
#endif

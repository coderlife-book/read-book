#if os(macOS)
import Foundation
import XCTest
@testable import ReadBook

final class SpeechModelDownloaderTests: XCTestCase {
    func testResumeRequestsOnlyRemainingBytesAndAtomicallyInstalls() async throws {
        let transport = RecordingSpeechDownloadTransport(body: Data("def".utf8), total: 6)
        let fixture = try SpeechDownloadFixture(partialBytes: Data("abc".utf8))
        let downloader = SpeechModelDownloader(transport: transport)

        let installed = try await downloader.download(fixture.descriptor, to: fixture.modelsRoot) { _ in }

        let requestedOffsets = await transport.requestedOffsets
        XCTAssertEqual(requestedOffsets, [3])
        XCTAssertEqual(
            try Data(contentsOf: installed.appendingPathComponent("model.safetensors")),
            Data("abcdef".utf8)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.partialRoot.path))
    }

    func testMissingContentLengthKeepsResumeDownloadWorking() async throws {
        let transport = UnknownLengthSpeechDownloadTransport(body: Data("def".utf8))
        let fixture = try SpeechDownloadFixture(partialBytes: Data("abc".utf8))
        let downloader = SpeechModelDownloader(transport: transport)

        let installed = try await downloader.download(fixture.descriptor, to: fixture.modelsRoot) { _ in }

        let requestedOffsets = await transport.requestedOffsets
        XCTAssertEqual(requestedOffsets, [3])
        XCTAssertEqual(
            try Data(contentsOf: installed.appendingPathComponent("model.safetensors")),
            Data("abcdef".utf8)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.partialRoot.path))
    }

    func testCancellationLeavesPartialFileForResume() async throws {
        let transport = CancellingSpeechDownloadTransport()
        let fixture = try SpeechDownloadFixture(partialBytes: Data("abc".utf8))
        let downloader = SpeechModelDownloader(transport: transport)

        do {
            _ = try await downloader.download(fixture.descriptor, to: fixture.modelsRoot) { _ in }
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }

        XCTAssertEqual(try Data(contentsOf: fixture.partialFile), Data("abc".utf8))
    }
}

private final class SpeechDownloadFixture {
    let root: URL
    let modelsRoot: URL
    let descriptor: SpeechModelDescriptor
    let partialRoot: URL
    let partialFile: URL

    init(partialBytes: Data) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadBookSpeechDownload-\(UUID().uuidString)", isDirectory: true)
        modelsRoot = root.appendingPathComponent("Models", isDirectory: true)
        descriptor = SpeechModelDescriptor(
            kind: .aligner,
            repoID: "example/test-model",
            revision: "test-revision",
            approximateBytes: 6,
            requiredRelativePaths: ["model.safetensors"]
        )
        partialRoot = modelsRoot
            .appendingPathComponent(".partial", isDirectory: true)
            .appendingPathComponent("aligner", isDirectory: true)
            .appendingPathComponent("test-revision", isDirectory: true)
        partialFile = partialRoot.appendingPathComponent("model.safetensors")
        try FileManager.default.createDirectory(
            at: partialFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try partialBytes.write(to: partialFile)
    }

    deinit { try? FileManager.default.removeItem(at: root) }
}

private actor RecordingSpeechDownloadTransport: SpeechDownloadTransport {
    let body: Data
    let total: Int64
    private(set) var requestedOffsets: [Int64] = []

    init(body: Data, total: Int64) {
        self.body = body
        self.total = total
    }

    func contentLength(for url: URL) async throws -> Int64 { total }

    func bytes(for url: URL, startingAt offset: Int64) async throws -> AsyncThrowingStream<Data, Error> {
        requestedOffsets.append(offset)
        return AsyncThrowingStream { continuation in
            continuation.yield(body)
            continuation.finish()
        }
    }
}

private actor UnknownLengthSpeechDownloadTransport: SpeechDownloadTransport {
    let body: Data
    private(set) var requestedOffsets: [Int64] = []

    init(body: Data) {
        self.body = body
    }

    func contentLength(for url: URL) async throws -> Int64 {
        throw SpeechModelDownloadError.invalidContentLength(url.lastPathComponent)
    }

    func bytes(for url: URL, startingAt offset: Int64) async throws -> AsyncThrowingStream<Data, Error> {
        requestedOffsets.append(offset)
        return AsyncThrowingStream { continuation in
            continuation.yield(body)
            continuation.finish()
        }
    }
}

private actor CancellingSpeechDownloadTransport: SpeechDownloadTransport {
    func contentLength(for url: URL) async throws -> Int64 { 6 }

    func bytes(for url: URL, startingAt offset: Int64) async throws -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: CancellationError())
        }
    }
}
#endif

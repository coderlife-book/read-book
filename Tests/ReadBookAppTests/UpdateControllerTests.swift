#if os(macOS)
import Foundation
import XCTest
import ReadBookCore
@testable import ReadBook

@MainActor
final class UpdateControllerTests: XCTestCase {
    func testRuntimeOwnsInjectedUpdater() {
        let updater = UpdateController(
            client: FakeUpdateReleaseClient(release: Self.release(version: "0.1.3")),
            currentVersionProvider: { AppVersion("0.1.3")! },
            currentAppURLProvider: { URL(fileURLWithPath: "/tmp/ReadBook.app") }
        )
        let runtime = AppRuntime(updater: updater)
        XCTAssertTrue(runtime.updater === updater)
    }

    func testManualCheckReportsNewerRelease() async {
        let release = Self.release(version: "0.1.4")
        let sut = UpdateController(
            client: FakeUpdateReleaseClient(release: release),
            currentVersionProvider: { AppVersion("0.1.3")! },
            currentAppURLProvider: { URL(fileURLWithPath: "/tmp/ReadBook.app") }
        )

        await sut.check(manual: true)

        XCTAssertEqual(sut.state, .available(release))
        XCTAssertTrue(sut.isPresented)
    }

    func testBackgroundCheckStaysQuietWhenAlreadyCurrent() async {
        let release = Self.release(version: "0.1.3")
        let sut = UpdateController(
            client: FakeUpdateReleaseClient(release: release),
            currentVersionProvider: { AppVersion("0.1.3")! },
            currentAppURLProvider: { URL(fileURLWithPath: "/tmp/ReadBook.app") }
        )

        await sut.check(manual: false)

        XCTAssertEqual(sut.state, .idle)
        XCTAssertFalse(sut.isPresented)
    }

    func testBackgroundCheckFindsNewerReleaseWithoutPresentingWindow() async {
        let release = Self.release(version: "0.1.4")
        let sut = UpdateController(
            client: FakeUpdateReleaseClient(release: release),
            currentVersionProvider: { AppVersion("0.1.3")! },
            currentAppURLProvider: { URL(fileURLWithPath: "/tmp/ReadBook.app") }
        )

        await sut.check(manual: false)

        XCTAssertEqual(sut.state, .available(release))
        XCTAssertFalse(sut.isPresented)
    }

    func testFlushForUpdateTimesOutInsteadOfWaitingForever() async {
        let sut = UpdateController(
            client: FakeUpdateReleaseClient(release: Self.release(version: "0.1.4")),
            currentVersionProvider: { AppVersion("0.1.3")! },
            flushTimeout: .milliseconds(50)
        )
        sut.configureLifecycle {
            try? await Task.sleep(for: .seconds(5))
        }

        let start = ContinuousClock.now
        do {
            try await sut.flushForUpdate()
            XCTFail("Expected update flush timeout")
        } catch let error as UpdateControllerError {
            XCTAssertEqual(error, .flushTimedOut)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertLessThan(start.duration(to: .now), .seconds(1))
    }

    func testChecksumAcceptsKnownSHA256AndRejectsMismatch() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadBookChecksumTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("hello.txt")
        try Data("hello".utf8).write(to: file)

        let good = Data("2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824  ReadBook-macOS.zip\n".utf8)
        XCTAssertNoThrow(try UpdateChecksum.verify(fileURL: file, checksumData: good))

        let bad = Data((String(repeating: "0", count: 64) + "  ReadBook-macOS.zip\n").utf8)
        XCTAssertThrowsError(try UpdateChecksum.verify(fileURL: file, checksumData: bad))
    }

    private static func release(version: String) -> GitHubRelease {
        let json = """
        {"tag_name":"v\(version)","name":"ReadBook v\(version)","body":"release notes","assets":[
          {"name":"ReadBook-macOS.zip","browser_download_url":"https://github.com/coderlife-book/read-book/releases/download/v\(version)/ReadBook-macOS.zip"},
          {"name":"ReadBook-macOS.zip.sha256","browser_download_url":"https://github.com/coderlife-book/read-book/releases/download/v\(version)/ReadBook-macOS.zip.sha256"}
        ]}
        """
        return try! JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))
    }
}

@MainActor
private final class FakeUpdateReleaseClient: UpdateReleaseProviding {
    let release: GitHubRelease

    init(release: GitHubRelease) {
        self.release = release
    }

    func latestRelease() async throws -> GitHubRelease { release }
    func data(from assetURL: URL) async throws -> Data { Data() }
    func download(from assetURL: URL) async throws -> URL { assetURL }
}
#endif

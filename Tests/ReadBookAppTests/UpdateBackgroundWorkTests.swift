#if os(macOS)
import Foundation
import XCTest
@testable import ReadBook

@MainActor
final class UpdateBackgroundWorkTests: XCTestCase {
    func testSlowUpdaterSubprocessDoesNotBlockMainActor() async throws {
        let worker = UpdateBackgroundWorker()
        let clock = ContinuousClock()
        let start = clock.now

        let slowCommand = Task { @MainActor in
            try await worker.runProcess("/bin/sleep", ["0.35"])
        }

        try await Task.sleep(for: .milliseconds(40))
        let elapsed = start.duration(to: clock.now)
        XCTAssertLessThan(elapsed, .milliseconds(200))

        let result = try await slowCommand.value
        XCTAssertEqual(result.status, 0)
    }

    func testInstallerExtractionUsesInjectedAsyncCommandRunner() async throws {
        let runner = RecordingUpdateCommandRunner()
        let installer = UpdateInstaller(fileManager: .default, commandRunner: runner)
        let fakeArchive = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadBookFake-\(UUID().uuidString).zip")
        try Data().write(to: fakeArchive)
        defer { try? FileManager.default.removeItem(at: fakeArchive) }

        let candidate = try await installer.extractArchive(fakeArchive)

        XCTAssertEqual(candidate.lastPathComponent, "ReadBook.app")
        XCTAssertEqual(runner.executables, ["/usr/bin/ditto"])
    }
}

@MainActor
private final class RecordingUpdateCommandRunner: UpdateCommandRunning {
    var executables: [String] = []

    func runProcess(_ executable: String, _ arguments: [String]) async throws -> UpdateProcessResult {
        executables.append(executable)
        if executable == "/usr/bin/ditto", let destination = arguments.last {
            let app = URL(fileURLWithPath: destination, isDirectory: true)
                .appendingPathComponent("ReadBook.app", isDirectory: true)
            try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        }
        return UpdateProcessResult(status: 0, stderr: "")
    }
}
#endif

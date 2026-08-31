#if os(macOS)
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
}
#endif

#if os(macOS)
import AppKit
import XCTest
@testable import ReadBook

@MainActor
final class AppDelegateTerminationSafetyTests: XCTestCase {
    func testApplicationTerminationNeverDefersForPositionFlush() {
        _ = NSApplication.shared
        let delegate = AppDelegate()
        var cleanupCalled = false
        var flushCalled = false
        delegate.cleanupHandler = { cleanupCalled = true }
        delegate.flushHandler = { flushCalled = true }

        let reply = delegate.applicationShouldTerminate(NSApplication.shared)

        XCTAssertEqual(reply, .terminateNow)
        XCTAssertTrue(cleanupCalled)
        XCTAssertFalse(flushCalled)
    }
}
#endif

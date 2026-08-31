#if os(macOS)
import AppKit
import XCTest
@testable import ReadBook

final class WindowCoordinatorTests: XCTestCase {
    @MainActor
    func testConfigureRemovesTitledChromeButKeepsResizableWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 260),
            styleMask: [.titled, .resizable, .closable],
            backing: .buffered,
            defer: false
        )

        let coordinator = WindowCoordinator()
        coordinator.configure(window)

        XCTAssertFalse(window.styleMask.contains(.titled))
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertTrue(window.isMovableByWindowBackground)
    }
}
#endif

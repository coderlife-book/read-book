#if os(macOS)
import AppKit
import XCTest
@testable import ReadBook

@MainActor
final class ReaderWindowInteractionTests: XCTestCase {
    func testConfigureDoesNotOverlayReaderContentWithCustomResizeView() throws {
        let window = makeWindow()
        WindowCoordinator().configure(window)
        let contentView = try XCTUnwrap(window.contentView)

        XCTAssertTrue(contentView.subviews.isEmpty)
    }

    private func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 360, height: 260),
            styleMask: [.titled, .resizable, .closable],
            backing: .buffered,
            defer: false
        )
    }

}
#endif

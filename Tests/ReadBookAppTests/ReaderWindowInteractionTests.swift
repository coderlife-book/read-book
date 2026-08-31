#if os(macOS)
import AppKit
import XCTest
@testable import ReadBook

@MainActor
final class ReaderWindowInteractionTests: XCTestCase {
    func testConfigureDoesNotAddContentOverlay() throws {
        let window = makeWindow()
        let contentView = try XCTUnwrap(window.contentView)
        let before = contentView.subviews.count

        WindowCoordinator().configure(window)

        XCTAssertEqual(contentView.subviews.count, before)
    }

    func testTrafficLightButtonsAreHidden() throws {
        let window = makeWindow()

        WindowCoordinator().configure(window)

        for type in [
            NSWindow.ButtonType.closeButton,
            .miniaturizeButton,
            .zoomButton,
        ] {
            let button = try XCTUnwrap(window.standardWindowButton(type))
            XCTAssertTrue(button.isHidden)
        }
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

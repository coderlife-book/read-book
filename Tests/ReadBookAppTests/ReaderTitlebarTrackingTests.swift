#if os(macOS)
import AppKit
import XCTest
@testable import ReadBook

final class ReaderTitlebarTrackingTests: XCTestCase {
    @MainActor
    func testTrackingViewNeverConsumesTitlebarHits() {
        let view = ReaderTitlebarTrackingView(onEnter: {}, onExit: {})
        view.frame = NSRect(x: 0, y: 0, width: 300, height: 28)

        XCTAssertNil(view.hitTest(NSPoint(x: 100, y: 10)))
    }

    @MainActor
    func testTrackingViewForwardsEnterAndExit() throws {
        var events: [Bool] = []
        let view = ReaderTitlebarTrackingView(
            onEnter: { events.append(true) },
            onExit: { events.append(false) }
        )
        let event = try XCTUnwrap(NSEvent.otherEvent(
            with: .applicationDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 0,
            data1: 0,
            data2: 0
        ))

        view.mouseEntered(with: event)
        view.mouseExited(with: event)

        XCTAssertEqual(events, [true, false])
    }

    @MainActor
    func testNativeToolbarInstallsExactlyOneTitlebarTracker() {
        let window = makeWindow()
        WindowCoordinator().configure(window)
        let controller = ReaderNativeToolbarController()

        controller.install(
            on: window,
            state: ReaderTitlebarState(),
            chrome: ReaderChromeController()
        )

        let container = window.standardWindowButton(.closeButton)?.superview
        let trackers = container?.subviews.compactMap { $0 as? ReaderTitlebarTrackingView } ?? []
        XCTAssertEqual(trackers.count, 1)
    }

    @MainActor
    private func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 260),
            styleMask: [.titled, .resizable, .closable],
            backing: .buffered,
            defer: false
        )
    }
}
#endif

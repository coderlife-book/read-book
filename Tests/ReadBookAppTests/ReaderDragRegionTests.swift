#if os(macOS)
import AppKit
import ObjectiveC
import XCTest
@testable import ReadBook

@MainActor
final class ReaderDragRegionTests: XCTestCase {
    func testMouseDownStartsExplicitWindowDrag() throws {
        let window = TrackingWindow(
            contentRect: NSRect(x: 100, y: 100, width: 360, height: 260),
            styleMask: [.titled, .resizable, .closable],
            backing: .buffered,
            defer: false
        )
        let view = ReaderDragView(frame: NSRect(x: 20, y: 20, width: 200, height: 30))
        try XCTUnwrap(window.contentView).addSubview(view)

        let event = try mouseEvent(.leftMouseDown, at: NSPoint(x: 60, y: 35), in: window)
        view.mouseDown(with: event)

        XCTAssertEqual(window.performDragCallCount, 1)
    }

    func testDragViewOwnsCursorRectPolicy() throws {
        let dragMethod = try XCTUnwrap(
            class_getInstanceMethod(ReaderDragView.self, #selector(NSView.resetCursorRects))
        )
        let baseMethod = try XCTUnwrap(
            class_getInstanceMethod(NSView.self, #selector(NSView.resetCursorRects))
        )

        XCTAssertNotEqual(method_getImplementation(dragMethod), method_getImplementation(baseMethod))
    }

    func testCursorUpdateUsesArrowCursor() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 360, height: 260),
            styleMask: [.titled, .resizable, .closable],
            backing: .buffered,
            defer: false
        )
        let view = ReaderDragView(frame: NSRect(x: 20, y: 20, width: 200, height: 30))
        try XCTUnwrap(window.contentView).addSubview(view)
        let event = try mouseEvent(.mouseMoved, at: NSPoint(x: 60, y: 35), in: window)

        NSCursor.iBeam.set()
        view.cursorUpdate(with: event)

        XCTAssertTrue(NSCursor.current === NSCursor.arrow)
    }

    private func mouseEvent(_ type: NSEvent.EventType, at point: NSPoint, in window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        ))
    }
}

@MainActor
private final class TrackingWindow: NSWindow {
    private(set) var performDragCallCount = 0

    override func performDrag(with event: NSEvent) {
        performDragCallCount += 1
    }
}
#endif

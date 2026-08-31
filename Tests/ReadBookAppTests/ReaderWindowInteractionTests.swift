#if os(macOS)
import AppKit
import XCTest
@testable import ReadBook

@MainActor
final class ReaderWindowInteractionTests: XCTestCase {
    func testDraggingLeftResizeHitZoneChangesWindowWidth() throws {
        let window = makeWindow()
        WindowCoordinator().configure(window)
        let startFrame = window.frame
        let contentView = try XCTUnwrap(window.contentView)
        let y = contentView.bounds.midY
        let target = try XCTUnwrap(contentView.hitTest(NSPoint(x: 1, y: y)))

        target.mouseDown(with: try mouseEvent(.leftMouseDown, at: NSPoint(x: 1, y: y), in: window))
        target.mouseDragged(with: try mouseEvent(.leftMouseDragged, at: NSPoint(x: 41, y: y), in: window))

        XCTAssertEqual(window.frame.width, startFrame.width - 40, accuracy: 0.5)
        XCTAssertEqual(window.frame.minX, startFrame.minX + 40, accuracy: 0.5)
    }

    func testDraggingBottomResizeHitZoneChangesWindowHeight() throws {
        let window = makeWindow()
        WindowCoordinator().configure(window)
        let startFrame = window.frame
        let contentView = try XCTUnwrap(window.contentView)
        let x = contentView.bounds.midX
        let target = try XCTUnwrap(contentView.hitTest(NSPoint(x: x, y: 1)))

        target.mouseDown(with: try mouseEvent(.leftMouseDown, at: NSPoint(x: x, y: 1), in: window))
        target.mouseDragged(with: try mouseEvent(.leftMouseDragged, at: NSPoint(x: x, y: 31), in: window))

        XCTAssertEqual(window.frame.height, startFrame.height - 30, accuracy: 0.5)
        XCTAssertEqual(window.frame.minY, startFrame.minY + 30, accuracy: 0.5)
    }

    func testResizeHitZoneUsesResizeCursor() throws {
        let window = makeWindow()
        WindowCoordinator().configure(window)
        let contentView = try XCTUnwrap(window.contentView)
        let y = contentView.bounds.midY
        let target = try XCTUnwrap(contentView.hitTest(NSPoint(x: 1, y: y)))
        let event = try mouseEvent(.mouseMoved, at: NSPoint(x: 1, y: y), in: window)

        NSCursor.arrow.set()
        target.cursorUpdate(with: event)

        XCTAssertFalse(NSCursor.current === NSCursor.arrow)
    }

    private func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 360, height: 260),
            styleMask: [.titled, .resizable, .closable],
            backing: .buffered,
            defer: false
        )
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
#endif

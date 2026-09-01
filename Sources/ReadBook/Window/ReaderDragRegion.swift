import AppKit
import SwiftUI

struct ReaderDragRegion: NSViewRepresentable {
    var onHoverChanged: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> NSView {
        let view = ReaderDragView()
        view.onHoverChanged = onHoverChanged
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? ReaderDragView else { return }
        view.onHoverChanged = onHoverChanged
    }
}

final class ReaderDragView: NSView {
    var onHoverChanged: (Bool) -> Void = { _ in }

    override var acceptsFirstResponder: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged(false)
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }
}

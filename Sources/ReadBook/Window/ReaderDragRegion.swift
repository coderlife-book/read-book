import AppKit
import SwiftUI

struct ReaderDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ReaderDragView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

final class ReaderDragView: NSView {
    override var acceptsFirstResponder: Bool { false }

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

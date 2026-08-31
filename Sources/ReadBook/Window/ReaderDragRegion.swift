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

    // Let AppKit perform normal window movement. Do not call
    // NSWindow.performDrag(with:) ourselves: that starts an explicit event
    // tracking loop and is unnecessary for a simple draggable title region.
    override var mouseDownCanMoveWindow: Bool { true }
}

import AppKit

@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    func configure(_ window: NSWindow) {
        window.delegate = self
        window.minSize = NSSize(width: 280, height: 180)

        // Widget-style, borderless reader. Dragging is handled by an explicit
        // AppKit drag region so NSTextView/SwiftUI controls cannot steal it.
        window.styleMask.remove(.titled)
        window.styleMask.insert([.resizable, .closable])
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.setFrameAutosaveName("ReadBook.ReaderWindow")
        installResizeHitZones(in: window)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NotificationCenter.default.post(name: .readBookReaderWillHide, object: nil)
        sender.orderOut(nil)
        return false
    }

    private func installResizeHitZones(in window: NSWindow) {
        guard let contentView = window.contentView else { return }
        guard !contentView.subviews.contains(where: { $0 is ReaderResizeView }) else { return }

        let resizeView = ReaderResizeView(frame: contentView.bounds)
        resizeView.autoresizingMask = [.width, .height]
        contentView.addSubview(resizeView, positioned: .above, relativeTo: nil)
    }
}

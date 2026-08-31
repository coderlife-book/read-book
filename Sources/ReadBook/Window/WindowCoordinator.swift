import AppKit

@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    func configure(_ window: NSWindow) {
        window.delegate = self
        window.minSize = NSSize(width: 280, height: 180)

        // This is a widget-style reader, not a titled document window. Keeping
        // `.titled` reserves a native titlebar/safe-area strip on macOS 26 even
        // when the traffic-light buttons and title text are hidden.
        window.styleMask.remove(.titled)
        window.styleMask.insert([.resizable, .closable])
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.setFrameAutosaveName("ReadBook.ReaderWindow")
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NotificationCenter.default.post(name: .readBookReaderWillHide, object: nil)
        sender.orderOut(nil)
        return false
    }
}

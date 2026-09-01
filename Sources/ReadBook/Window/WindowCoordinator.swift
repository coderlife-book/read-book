import AppKit

@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    func configure(_ window: NSWindow) {
        window.delegate = self
        window.minSize = NSSize(width: 280, height: 180)

        window.styleMask.insert([.titled, .fullSizeContentView, .resizable, .closable])
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbar = nil
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        if let contentView = window.contentView {
            let systemTopInset = contentView.safeAreaInsets.top - contentView.additionalSafeAreaInsets.top
            var additionalInsets = contentView.additionalSafeAreaInsets
            additionalInsets.top = -systemTopInset
            contentView.additionalSafeAreaInsets = additionalInsets
        }
        window.setFrameAutosaveName("ReadBook.ReaderWindow")
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NotificationCenter.default.post(name: .readBookReaderWillHide, object: nil)
        sender.orderOut(nil)
        return false
    }
}

import AppKit
import ReadBookCore

@MainActor
final class WindowRegistry {
    private weak var readerWindow: NSWindow?
    private let coordinator = WindowCoordinator()

    func register(_ window: NSWindow) {
        guard readerWindow !== window else { return }
        readerWindow = window
        coordinator.configure(window)
    }

    func showReader() {
        guard let readerWindow else { return }
        readerWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hideReader() {
        NotificationCenter.default.post(name: .readBookReaderWillHide, object: nil)
        readerWindow?.orderOut(nil)
    }

    func toggleReader() {
        guard let readerWindow else { return }
        readerWindow.isVisible ? hideReader() : showReader()
    }

    func setAlwaysOnTop(_ enabled: Bool) {
        readerWindow?.level = enabled ? .floating : .normal
    }

    func setAppPresence(_ mode: AppPresenceMode) {
        NSApp.setActivationPolicy(mode == .widgetStyle ? .accessory : .regular)
        if mode == .normal {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func apply(_ preferences: ReaderPreferences) {
        setAlwaysOnTop(preferences.alwaysOnTop)
        setAppPresence(preferences.appPresenceMode)
    }
}

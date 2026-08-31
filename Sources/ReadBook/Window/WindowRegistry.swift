import AppKit
import ReadBookCore

@MainActor
final class WindowRegistry: ReaderWindowDriving {
    private weak var readerWindow: NSWindow?
    private let coordinator = WindowCoordinator()

    func register(_ window: NSWindow) {
        guard readerWindow !== window else { return }
        readerWindow = window
        coordinator.configure(window)
    }

    var readerFrameInScreen: CGRect? {
        guard let readerWindow else { return nil }
        let fixed = Self.revalidatedFrame(
            readerWindow.frame,
            visibleFrames: NSScreen.screens.map(\.visibleFrame)
        )
        if fixed != readerWindow.frame {
            readerWindow.setFrame(fixed, display: false)
        }
        return fixed
    }

    func showReader(activate: Bool = true) {
        guard let readerWindow else { return }
        _ = readerFrameInScreen
        readerWindow.makeKeyAndOrderFront(nil)
        if activate {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func showReader() {
        showReader(activate: true)
    }

    func hideReader() {
        NotificationCenter.default.post(name: .readBookReaderWillHide, object: nil)
        readerWindow?.orderOut(nil)
    }

    func toggleReader() {
        guard let readerWindow else { return }
        readerWindow.isVisible ? hideReader() : showReader()
    }

    func setPointerPassThrough(_ enabled: Bool) {
        readerWindow?.ignoresMouseEvents = enabled
    }

    func applyAppearance(_ appearance: ReaderWindowAppearance) {
        guard let readerWindow else { return }
        readerWindow.backgroundColor = .clear
        readerWindow.isOpaque = false
        switch appearance {
        case .card:
            readerWindow.hasShadow = true
        case .frameless, .transparent:
            readerWindow.hasShadow = false
        }
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
        applyAppearance(preferences.windowAppearance)
    }

    static func revalidatedFrame(_ frame: CGRect, visibleFrames: [CGRect]) -> CGRect {
        guard !visibleFrames.isEmpty else { return frame }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        if visibleFrames.contains(where: { $0.contains(center) }) {
            return frame
        }

        let target = visibleFrames.min { lhs, rhs in
            squaredDistance(from: center, to: lhs) < squaredDistance(from: center, to: rhs)
        } ?? visibleFrames[0]

        var result = frame
        if result.width > target.width { result.size.width = target.width }
        if result.height > target.height { result.size.height = target.height }
        result.origin.x = min(max(result.origin.x, target.minX), target.maxX - result.width)
        result.origin.y = min(max(result.origin.y, target.minY), target.maxY - result.height)
        return result
    }

    private static func squaredDistance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let x = min(max(point.x, rect.minX), rect.maxX)
        let y = min(max(point.y, rect.minY), rect.maxY)
        let dx = point.x - x
        let dy = point.y - y
        return dx * dx + dy * dy
    }
}

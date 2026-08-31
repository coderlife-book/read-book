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
        guard readerWindow?.ignoresMouseEvents != enabled else { return }
        readerWindow?.ignoresMouseEvents = enabled
    }

    func applyAppearance(_ appearance: ReaderWindowAppearance) {
        guard let readerWindow else { return }
        readerWindow.backgroundColor = .clear
        readerWindow.isOpaque = false
        switch appearance {
        case .card:
            if !readerWindow.hasShadow { readerWindow.hasShadow = true }
        case .frameless, .transparent:
            if readerWindow.hasShadow { readerWindow.hasShadow = false }
        }
    }

    func setAlwaysOnTop(_ enabled: Bool) {
        guard let readerWindow else { return }
        let target: NSWindow.Level = enabled ? .floating : .normal
        guard readerWindow.level != target else { return }
        readerWindow.level = target
    }

    static func desiredActivationPolicy(for mode: AppPresenceMode) -> NSApplication.ActivationPolicy {
        mode == .widgetStyle ? .accessory : .regular
    }

    static func needsActivationPolicyChange(
        current: NSApplication.ActivationPolicy,
        targetMode: AppPresenceMode
    ) -> Bool {
        current != desiredActivationPolicy(for: targetMode)
    }

    func setAppPresence(_ mode: AppPresenceMode) {
        let target = Self.desiredActivationPolicy(for: mode)
        guard Self.needsActivationPolicyChange(
            current: NSApp.activationPolicy,
            targetMode: mode
        ) else { return }

        NSApp.setActivationPolicy(target)
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

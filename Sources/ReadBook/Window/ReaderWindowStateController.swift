import AppKit
import Observation
import ReadBookCore

@MainActor
protocol ReaderWindowDriving: AnyObject {
    var readerFrameInScreen: CGRect? { get }
    func showReader(activate: Bool)
    func hideReader()
    func setPointerPassThrough(_ enabled: Bool)
}

enum ReaderHideReason: Equatable {
    case automaticPointerExit
    case explicitShortcut
    case explicitMenuAction
}

enum ReaderWindowState: Equatable {
    case normal
    case floatingText
    case interactiveStealth
    case hidden(ReaderHideReason)
}

@MainActor
@Observable
final class ReaderWindowStateController {
    private(set) var state: ReaderWindowState = .normal
    private(set) var lockInteractive = false

    private weak var driver: (any ReaderWindowDriving)?
    private let scheduler: any DelayScheduling
    private var preferences = ReaderPreferences.defaults
    private var lastVisibleState: ReaderWindowState = .normal
    private var hideDelay: (any DelayCancellation)?
    private var optionReleaseDelay: (any DelayCancellation)?
    private var optionDown = false
    private var lastPointerInside = false

    init(
        driver: any ReaderWindowDriving,
        scheduler: any DelayScheduling = TaskDelayScheduler()
    ) {
        self.driver = driver
        self.scheduler = scheduler
    }

    func applyPreferences(_ value: ReaderPreferences) {
        let bossModeChanged = preferences.bossModeEnabled != value.bossModeEnabled
        let preserveExplicitHide: Bool
        switch state {
        case .hidden(.explicitShortcut), .hidden(.explicitMenuAction):
            preserveExplicitHide = true
        default:
            preserveExplicitHide = false
        }

        preferences = value
        guard !preserveExplicitHide else { return }

        // Font, theme, always-on-top, appearance and app-presence changes are
        // handled by their own layers. They must not cause a visible reader to
        // be ordered front / activated again. Only turning boss mode on or off
        // changes this controller's visible-state contract.
        guard bossModeChanged else { return }

        cancelHide()
        if !value.bossModeEnabled {
            transition(to: .normal, show: true)
        } else {
            transition(to: lockInteractive ? .interactiveStealth : .floatingText, show: true)
        }
    }

    func pointerMoved(to screenPoint: CGPoint) {
        guard let frame = driver?.readerFrameInScreen else { return }
        let inside = frame.contains(screenPoint)
        lastPointerInside = inside

        if case .hidden(.automaticPointerExit) = state, inside {
            transition(to: restoredVisibleState(), show: true)
            return
        }

        guard preferences.bossModeEnabled,
              preferences.bossModeProfile == .concealed,
              !isExplicitlyHidden else { return }

        if inside {
            cancelHide()
        } else if !isHidden {
            scheduleAutomaticHide()
        }
    }

    func optionChanged(isDown: Bool) {
        optionDown = isDown
        optionReleaseDelay?.cancel()
        optionReleaseDelay = nil

        guard preferences.bossModeEnabled, !isHidden else { return }

        if isDown, lastPointerInside {
            transition(to: .interactiveStealth, show: true)
        } else if !isDown, !lockInteractive {
            optionReleaseDelay = scheduler.schedule(afterMilliseconds: 300) { [weak self] in
                guard let self, !self.optionDown, !self.lockInteractive, !self.isHidden else { return }
                self.transition(to: .floatingText, show: true)
            }
        }
    }

    func setLockInteractive(_ enabled: Bool) {
        lockInteractive = enabled
        optionReleaseDelay?.cancel()
        optionReleaseDelay = nil

        guard preferences.bossModeEnabled, !isHidden else { return }
        transition(to: enabled ? .interactiveStealth : .floatingText, show: true)
    }

    func toggleEmergencyShortcut() {
        if isHidden {
            cancelHide()
            transition(to: restoredVisibleState(), show: true)
        } else {
            lastVisibleState = state
            cancelHide()
            optionReleaseDelay?.cancel()
            optionReleaseDelay = nil
            transition(to: .hidden(.explicitShortcut), show: false)
        }
    }

    func showExplicitly() {
        cancelHide()
        optionReleaseDelay?.cancel()
        optionReleaseDelay = nil
        transition(to: restoredVisibleState(), show: true)
    }

    func hideExplicitly() {
        if !isHidden {
            lastVisibleState = state
        }
        cancelHide()
        optionReleaseDelay?.cancel()
        optionReleaseDelay = nil
        transition(to: .hidden(.explicitMenuAction), show: false)
    }

    private var isHidden: Bool {
        if case .hidden = state { return true }
        return false
    }

    private var isExplicitlyHidden: Bool {
        switch state {
        case .hidden(.explicitShortcut), .hidden(.explicitMenuAction):
            return true
        default:
            return false
        }
    }

    private func restoredVisibleState() -> ReaderWindowState {
        guard preferences.bossModeEnabled else { return .normal }
        if lockInteractive || (optionDown && lastPointerInside) {
            return .interactiveStealth
        }
        if case .interactiveStealth = lastVisibleState, lockInteractive {
            return .interactiveStealth
        }
        return .floatingText
    }

    private func scheduleAutomaticHide() {
        guard hideDelay == nil else { return }
        hideDelay = scheduler.schedule(afterMilliseconds: 300) { [weak self] in
            guard let self else { return }
            self.hideDelay = nil
            guard !self.lastPointerInside, !self.isHidden else { return }
            self.lastVisibleState = self.state
            self.transition(to: .hidden(.automaticPointerExit), show: false)
        }
    }

    private func cancelHide() {
        hideDelay?.cancel()
        hideDelay = nil
    }

    private func transition(to newState: ReaderWindowState, show: Bool) {
        state = newState
        if show {
            driver?.showReader(activate: newState == .normal)
        } else {
            driver?.hideReader()
        }
        driver?.setPointerPassThrough(newState == .floatingText && !lockInteractive)
    }
}

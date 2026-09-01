import AppKit
import Observation
import ReadBookCore

@MainActor
@Observable
final class AppRuntime {
    let windowRegistry: WindowRegistry
    let windowState: ReaderWindowStateController
    let chrome: ReaderChromeController
    let titlebar: ReaderTitlebarState
    let updater: UpdateController

    private(set) var systemInputHooksEnabled = false
    private var lastPreferences = ReaderPreferences.defaults
    private var started = false

    init(
        windowRegistry: WindowRegistry = WindowRegistry(),
        updater: UpdateController = UpdateController()
    ) {
        self.windowRegistry = windowRegistry
        self.windowState = ReaderWindowStateController(driver: windowRegistry)
        self.chrome = ReaderChromeController()
        self.titlebar = ReaderTitlebarState()
        self.updater = updater
    }

    func configureUpdater(flush: @escaping @MainActor () async -> Void) {
        updater.configureLifecycle(flush: flush)
    }

    func register(window: NSWindow) {
        windowRegistry.register(
            window,
            titlebarState: titlebar,
            chrome: chrome
        )
        applyPreferences(lastPreferences)
    }

    func start(preferences: ReaderPreferences) {
        lastPreferences = preferences
        applyPreferences(preferences)
        guard !started else { return }
        started = true

        // v0.1.4 safety policy: ReadBook does not install process-wide
        // keyboard, modifier-key, or mouse event monitors.
        systemInputHooksEnabled = false
        updater.scheduleAutomaticCheck()
    }

    func stop() {
        updater.cancelAutomaticCheck()
        systemInputHooksEnabled = false
        started = false
    }

    func applyPreferences(_ preferences: ReaderPreferences) {
        lastPreferences = preferences
        windowRegistry.apply(preferences)
        windowState.applyPreferences(preferences)
    }

    func toggleReaderFromMenu() {
        switch windowState.state {
        case .hidden:
            windowState.showExplicitly()
        default:
            windowState.hideExplicitly()
        }
    }

    func showReader() {
        windowState.showExplicitly()
    }

    func toggleBossMode(using model: AppModel) {
        model.updatePreferences { preferences in
            preferences.bossModeEnabled.toggle()
            if preferences.bossModeEnabled, preferences.windowAppearance == .card {
                preferences.windowAppearance = .transparent
            }
        }
        applyPreferences(model.preferences)
    }

    func setBossProfile(_ profile: BossModeProfile, using model: AppModel) {
        model.updatePreferences { $0.bossModeProfile = profile }
        applyPreferences(model.preferences)
    }

    func setAppearance(_ appearance: ReaderWindowAppearance, using model: AppModel) {
        model.updatePreferences { $0.windowAppearance = appearance }
        applyPreferences(model.preferences)
    }

    func setLockInteractive(_ enabled: Bool) {
        windowState.setLockInteractive(enabled)
    }
}

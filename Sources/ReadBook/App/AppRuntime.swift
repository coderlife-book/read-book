import AppKit
import Observation
import ReadBookCore

@MainActor
@Observable
final class AppRuntime {
    let windowRegistry: WindowRegistry
    let windowState: ReaderWindowStateController
    let chrome: ReaderChromeController
    let updater: UpdateController

    private let hotKeyService: any GlobalHotKeyServicing
    private let globalInputService: any ReaderGlobalInputServicing
    private(set) var hotKeyAvailable = false
    private(set) var globalPointerAvailable = false
    private var lastPreferences = ReaderPreferences.defaults
    private var started = false

    init(
        windowRegistry: WindowRegistry = WindowRegistry(),
        hotKeyService: any GlobalHotKeyServicing = GlobalHotKeyService(),
        globalInputService: any ReaderGlobalInputServicing = ReaderGlobalInputService(),
        updater: UpdateController = UpdateController()
    ) {
        self.windowRegistry = windowRegistry
        self.windowState = ReaderWindowStateController(driver: windowRegistry)
        self.chrome = ReaderChromeController()
        self.hotKeyService = hotKeyService
        self.globalInputService = globalInputService
        self.updater = updater
    }

    func configureUpdater(flush: @escaping @MainActor () async -> Void) {
        updater.configureLifecycle(flush: flush)
    }

    func register(window: NSWindow) {
        windowRegistry.register(window)
        applyPreferences(lastPreferences)
    }

    func start(preferences: ReaderPreferences) {
        lastPreferences = preferences
        applyPreferences(preferences)
        guard !started else { return }
        started = true

        // Safety policy for v0.1.4: do not install any process-wide keyboard,
        // modifier-key, or pointer monitors. A real-device v0.1.3 report showed
        // a system-wide input hang after launch, so global hooks stay disabled
        // until they can be reintroduced with isolated real-device validation.
        hotKeyAvailable = false
        globalPointerAvailable = false
        updater.scheduleAutomaticCheck()
    }

    func stop() {
        updater.cancelAutomaticCheck()
        // Defensive cleanup in case an older runtime instance had registered
        // hooks before being replaced during development.
        globalInputService.stop()
        hotKeyService.stop()
        hotKeyAvailable = false
        globalPointerAvailable = false
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

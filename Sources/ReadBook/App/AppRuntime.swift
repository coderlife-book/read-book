import AppKit
import Observation
import ReadBookCore

@MainActor
@Observable
final class AppRuntime {
    let windowRegistry: WindowRegistry
    let windowState: ReaderWindowStateController
    let chrome: ReaderChromeController

    private let hotKeyService: GlobalHotKeyService
    private let globalInputService: ReaderGlobalInputService
    private(set) var hotKeyAvailable = false
    private(set) var globalPointerAvailable = false
    private var lastPreferences = ReaderPreferences.defaults
    private var started = false

    init(
        windowRegistry: WindowRegistry = WindowRegistry(),
        hotKeyService: GlobalHotKeyService = GlobalHotKeyService(),
        globalInputService: ReaderGlobalInputService = ReaderGlobalInputService()
    ) {
        self.windowRegistry = windowRegistry
        self.windowState = ReaderWindowStateController(driver: windowRegistry)
        self.chrome = ReaderChromeController()
        self.hotKeyService = hotKeyService
        self.globalInputService = globalInputService
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

        hotKeyAvailable = hotKeyService.start { [weak self] in
            self?.windowState.toggleEmergencyShortcut()
        }
        globalPointerAvailable = globalInputService.start(
            onPointer: { [weak self] point in
                self?.windowState.pointerMoved(to: point)
            },
            onOption: { [weak self] isDown in
                guard let self else { return }
                self.windowState.optionChanged(isDown: isDown)
                if isDown {
                    self.chrome.revealAllImmediately()
                } else {
                    self.chrome.bodyEntered()
                }
            }
        )
    }

    func stop() {
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

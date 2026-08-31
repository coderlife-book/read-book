# ReadBook Stealth Reader / Boss Mode v1.3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build ReadBook v0.1.3 with a low-distraction reading surface, reliable borderless dragging, Boss Mode state machine, global emergency hide/show, transparent pointer-pass-through reading, and a real ReadBook application icon.

**Architecture:** Keep reading/layout state unchanged and add one AppKit-facing `ReaderWindowStateController` as the authority for visibility and interaction state. Keep durable appearance/Boss settings in `ReaderPreferences`, transient chrome timing in a separate `ReaderChromeController`, and raw global input registration in dedicated services that emit semantic events instead of mutating `NSWindow` directly. The SwiftUI root observes these controllers to render card/frameless/transparent surfaces and control scrims without making ordinary body hover or scrolling reveal UI.

**Tech Stack:** Swift 6, SwiftUI, AppKit, TextKit, Observation, Carbon `RegisterEventHotKey`, XCTest, SwiftPM, GitHub Actions macOS 26, `codesign`, `iconutil`.

**Spec:** `docs/superpowers/specs/2026-08-31-stealth-reader-boss-mode-design.md`

## Global Constraints

- Target macOS 26+.
- Preserve existing TXT import/storage semantics and canonical UTF-16 reading position.
- Preserve paginated and virtualized continuous reading engines; do not rework them in this feature.
- Body hover, wheel scrolling, trackpad scrolling, and ordinary page navigation must never reveal toolbar/footer.
- Top hot zone: exactly 20 pt with 250 ms dwell; bottom hot zone: exactly 16 pt with 250 ms dwell; body return dismisses chrome after 200 ms.
- Concealed profile auto-hide delay: exactly 300 ms.
- Option release returns from temporary interaction after exactly 300 ms unless Lock Interactive is on.
- V1.3 global emergency shortcut is fixed to `Control + Option + R` (`⌃⌥R`); no user shortcut editor in this release.
- Frameless default background opacity: 18%, user range 0%...60%.
- Transparent background opacity: 0%; window shadow off.
- Lock Interactive is session-only and must reset to off on launch.
- Do not add polling loops for hidden-window pointer restoration.
- No new network, account, cloud, Supabase, screen-capture hiding, process masquerading, fake editor UI, or foreground-app detection.
- Preserve existing strict ad-hoc bundle `codesign` verification; Developer ID/notarization remains out of scope.

---

## File Structure

### Core settings

- Modify `Sources/ReadBookCore/Models/ReaderPreferences.swift` — durable Boss Mode/profile/appearance preferences with backward-compatible Codable decoding.
- Modify `Tests/ReadBookCoreTests/PreferencesStoreTests.swift` — old-v0.1.2 JSON compatibility and new preference round-trip/default tests.

### Window behavior

- Create `Sources/ReadBook/Window/ReaderWindowStateController.swift` — behavioral state machine, delayed auto-hide, Option interaction, explicit hide lock semantics.
- Create `Sources/ReadBook/Window/DelayScheduler.swift` — cancellable main-actor delay abstraction used by state and chrome controllers.
- Modify `Sources/ReadBook/Window/WindowRegistry.swift` — AppKit driver methods for show/hide, current screen frame, pointer pass-through, window appearance.
- Modify `Sources/ReadBook/Window/WindowCoordinator.swift` — remove background-drag dependence; keep borderless/resizable baseline.
- Create `Tests/ReadBookAppTests/ReaderWindowStateControllerTests.swift` — state transition tests using fake driver/manual scheduler.
- Modify `Tests/ReadBookAppTests/WindowCoordinatorTests.swift` — appearance/pass-through/borderless regression tests.

### Global input

- Create `Sources/ReadBook/Input/GlobalHotKeyService.swift` — Carbon `RegisterEventHotKey` for `⌃⌥R`, with deterministic unregister.
- Create `Sources/ReadBook/Input/ReaderGlobalInputService.swift` — local/global mouse+modifier monitors; no polling.
- Create `Tests/ReadBookAppTests/ReaderGlobalInputServiceTests.swift` — semantic event routing tests without installing real global monitors.

### Pure-reading chrome + dragging

- Create `Sources/ReadBook/Reader/ReaderChromeController.swift` — top/bottom dwell state and 200 ms dismissal.
- Create `Sources/ReadBook/Window/ReaderDragRegion.swift` — explicit AppKit `performDrag(with:)` bridge.
- Modify `Sources/ReadBook/Reader/ReaderToolbar.swift` — title/empty-space drag region; button hit areas remain independent.
- Modify `Sources/ReadBook/Reader/ReaderRootView.swift` — remove generic hover rule, add scrim-backed edge chrome and appearance rendering.
- Create `Tests/ReadBookAppTests/ReaderChromeControllerTests.swift` — body/scroll/hot-zone timing tests.

### App integration

- Create `Sources/ReadBook/App/AppRuntime.swift` — owns registry/state/chrome/global-input/hotkey lifecycle and exposes hotkey availability.
- Modify `Sources/ReadBook/App/AppDelegate.swift` — cleanup callback before termination.
- Modify `Sources/ReadBook/App/AppModel.swift` — explicit preference setters for Boss Mode/profile/appearance.
- Modify `Sources/ReadBook/App/ReadBookApp.swift` — inject runtime into reader, wire menu-bar actions, start/stop services.
- Modify `Sources/ReadBook/Settings/SettingsView.swift` — Boss Mode/profile/appearance/opacity controls and shortcut availability text.

### Branding

- Create `DesignAssets/ReadBookMark.svg` — custom ReadBook vector master.
- Create `DesignAssets/Tabler/ghost-2.svg` — curated MIT-licensed visual reference.
- Create `DesignAssets/Tabler/eye-off.svg` — curated MIT-licensed visual reference.
- Create `DesignAssets/Tabler/border-none.svg` — curated MIT-licensed visual reference.
- Create `DesignAssets/Tabler/LICENSE` — Tabler MIT license/copyright notice.
- Create `Scripts/render-app-icon.swift` — rasterize custom SVG into a macOS iconset.
- Modify `Scripts/build-app.sh` — build `.icns`, set `CFBundleIconFile`, bump bundle version to 0.1.3 / build 4.
- Modify `.github/workflows/bootstrap-readbook.yml` — verify icon presence and upload a signed preview ZIP on PR runs; main publishing remains gated until manual acceptance.

### Acceptance/release

- Create `docs/qa/2026-08-31-stealth-reader-v1.3-checklist.md` — exact real-mac acceptance checklist.
- After acceptance, modify `.github/workflows/bootstrap-readbook.yml` — publish `v0.1.3` from `main`.

---

### Task 1: Add backward-compatible durable stealth preferences

**Files:**
- Modify: `Sources/ReadBookCore/Models/ReaderPreferences.swift`
- Modify: `Tests/ReadBookCoreTests/PreferencesStoreTests.swift`

**Interfaces:**
- Consumes: existing `ReadingMode`, `ReaderTheme`, `AppPresenceMode`, `PreferencesStore`.
- Produces: `BossModeProfile`, `ReaderWindowAppearance`, and new `ReaderPreferences` fields `bossModeEnabled`, `bossModeProfile`, `windowAppearance`, `framelessBackgroundOpacity`.

- [ ] **Step 1: Write failing compatibility/default tests**

Add these tests to `PreferencesStoreTests.swift`:

```swift
func testStealthDefaultsAreSafeForExistingUsers() {
    let value = ReaderPreferences.defaults
    XCTAssertFalse(value.bossModeEnabled)
    XCTAssertEqual(value.bossModeProfile, .floatingReading)
    XCTAssertEqual(value.windowAppearance, .card)
    XCTAssertEqual(value.framelessBackgroundOpacity, 0.18, accuracy: 0.0001)
}

func testLegacyV012PreferencesDecodeWithStealthDefaults() throws {
    let json = #"{"readingMode":"paginated","fontFamily":"PingFang SC","fontSize":17,"lineSpacing":8,"paragraphSpacing":9,"theme":"soft","alwaysOnTop":false,"appPresenceMode":"widgetStyle"}"#
    let value = try JSONDecoder().decode(ReaderPreferences.self, from: Data(json.utf8))

    XCTAssertFalse(value.bossModeEnabled)
    XCTAssertEqual(value.bossModeProfile, .floatingReading)
    XCTAssertEqual(value.windowAppearance, .card)
    XCTAssertEqual(value.framelessBackgroundOpacity, 0.18, accuracy: 0.0001)
}

func testStealthPreferencesRoundTrip() throws {
    let data = try JSONEncoder().encode(ReaderPreferences(
        readingMode: .continuous,
        fontFamily: "Songti SC",
        fontSize: 18,
        lineSpacing: 7,
        paragraphSpacing: 8,
        theme: .dark,
        alwaysOnTop: true,
        appPresenceMode: .widgetStyle,
        bossModeEnabled: true,
        bossModeProfile: .concealed,
        windowAppearance: .frameless,
        framelessBackgroundOpacity: 0.42
    ))
    let decoded = try JSONDecoder().decode(ReaderPreferences.self, from: data)
    XCTAssertTrue(decoded.bossModeEnabled)
    XCTAssertEqual(decoded.bossModeProfile, .concealed)
    XCTAssertEqual(decoded.windowAppearance, .frameless)
    XCTAssertEqual(decoded.framelessBackgroundOpacity, 0.42, accuracy: 0.0001)
}
```

- [ ] **Step 2: Run the focused tests and confirm RED**

Run:

```bash
swift test --filter PreferencesStoreTests
```

Expected: compile/test failure because stealth enums/properties/initializer parameters do not exist.

- [ ] **Step 3: Implement the new types and backward-compatible Codable**

In `ReaderPreferences.swift`, add:

```swift
public enum BossModeProfile: String, Codable, Sendable {
    case floatingReading
    case concealed
}

public enum ReaderWindowAppearance: String, Codable, Sendable {
    case card
    case frameless
    case transparent
}
```

Extend `ReaderPreferences` with:

```swift
public var bossModeEnabled: Bool
public var bossModeProfile: BossModeProfile
public var windowAppearance: ReaderWindowAppearance
public var framelessBackgroundOpacity: Double
```

Use these initializer defaults so existing call sites continue compiling:

```swift
bossModeEnabled: Bool = false,
bossModeProfile: BossModeProfile = .floatingReading,
windowAppearance: ReaderWindowAppearance = .card,
framelessBackgroundOpacity: Double = 0.18
```

Implement custom decoding with `decodeIfPresent` for the four new fields and preserve existing values for old data:

```swift
private enum CodingKeys: String, CodingKey {
    case readingMode, fontFamily, fontSize, lineSpacing, paragraphSpacing
    case theme, alwaysOnTop, appPresenceMode
    case bossModeEnabled, bossModeProfile, windowAppearance, framelessBackgroundOpacity
}

public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    readingMode = try c.decode(ReadingMode.self, forKey: .readingMode)
    fontFamily = try c.decode(String.self, forKey: .fontFamily)
    fontSize = try c.decode(Double.self, forKey: .fontSize)
    lineSpacing = try c.decode(Double.self, forKey: .lineSpacing)
    paragraphSpacing = try c.decode(Double.self, forKey: .paragraphSpacing)
    theme = try c.decode(ReaderTheme.self, forKey: .theme)
    alwaysOnTop = try c.decode(Bool.self, forKey: .alwaysOnTop)
    appPresenceMode = try c.decode(AppPresenceMode.self, forKey: .appPresenceMode)
    bossModeEnabled = try c.decodeIfPresent(Bool.self, forKey: .bossModeEnabled) ?? false
    bossModeProfile = try c.decodeIfPresent(BossModeProfile.self, forKey: .bossModeProfile) ?? .floatingReading
    windowAppearance = try c.decodeIfPresent(ReaderWindowAppearance.self, forKey: .windowAppearance) ?? .card
    framelessBackgroundOpacity = min(max(
        try c.decodeIfPresent(Double.self, forKey: .framelessBackgroundOpacity) ?? 0.18,
        0
    ), 0.60)
}
```

Keep synthesized `encode(to:)` by explicitly implementing it if Swift requires it after the custom decoder; encode all fields, including the four new ones.

Update `.defaults` to:

```swift
bossModeEnabled: false,
bossModeProfile: .floatingReading,
windowAppearance: .card,
framelessBackgroundOpacity: 0.18
```

- [ ] **Step 4: Run focused and full core tests**

Run:

```bash
swift test --filter PreferencesStoreTests
swift test --filter ReadBookCoreTests
```

Expected: PASS; legacy JSON decodes with new defaults and new values round-trip.

- [ ] **Step 5: Commit**

```bash
git add Sources/ReadBookCore/Models/ReaderPreferences.swift Tests/ReadBookCoreTests/PreferencesStoreTests.swift
git commit -m "feat: add stealth reader preferences"
```

---

### Task 2: Implement the window state controller with deterministic delays

**Files:**
- Create: `Sources/ReadBook/Window/DelayScheduler.swift`
- Create: `Sources/ReadBook/Window/ReaderWindowStateController.swift`
- Create: `Tests/ReadBookAppTests/ReaderWindowStateControllerTests.swift`

**Interfaces:**
- Consumes: `ReaderPreferences`, `BossModeProfile`, `CGRect`.
- Produces: `ReaderWindowState`, `ReaderHideReason`, `ReaderWindowDriving`, `ReaderWindowStateController`.

- [ ] **Step 1: Add the manual-scheduler/fake-driver tests**

Create `ReaderWindowStateControllerTests.swift` with a fake driver and manual scheduler:

```swift
import AppKit
import XCTest
@testable import ReadBook
@testable import ReadBookCore

@MainActor
final class ReaderWindowStateControllerTests: XCTestCase {
    final class Token: DelayCancellation {
        var cancelled = false
        func cancel() { cancelled = true }
    }

    final class ManualScheduler: DelayScheduling {
        struct Pending {
            let milliseconds: Int
            let token: Token
            let action: @MainActor () -> Void
        }
        var pending: [Pending] = []

        func schedule(afterMilliseconds milliseconds: Int, action: @escaping @MainActor () -> Void) -> any DelayCancellation {
            let token = Token()
            pending.append(Pending(milliseconds: milliseconds, token: token, action: action))
            return token
        }

        func fire(milliseconds: Int) {
            let matches = pending.filter { $0.milliseconds == milliseconds && !$0.token.cancelled }
            pending.removeAll { $0.milliseconds == milliseconds }
            matches.forEach { $0.action() }
        }
    }

    final class Driver: ReaderWindowDriving {
        var readerFrameInScreen: CGRect? = CGRect(x: 100, y: 100, width: 360, height: 260)
        var visible = true
        var ignoresMouseEvents = false
        func showReader(activate: Bool) { visible = true }
        func hideReader() { visible = false }
        func setPointerPassThrough(_ enabled: Bool) { ignoresMouseEvents = enabled }
    }

    func testConcealedPointerExitHidesAfter300msAndReentryRestores() {
        let driver = Driver()
        let scheduler = ManualScheduler()
        let sut = ReaderWindowStateController(driver: driver, scheduler: scheduler)
        var prefs = ReaderPreferences.defaults
        prefs.bossModeEnabled = true
        prefs.bossModeProfile = .concealed
        sut.applyPreferences(prefs)

        sut.pointerMoved(to: CGPoint(x: 50, y: 50))
        XCTAssertTrue(driver.visible)
        scheduler.fire(milliseconds: 300)
        XCTAssertEqual(sut.state, .hidden(.automaticPointerExit))
        XCTAssertFalse(driver.visible)

        sut.pointerMoved(to: CGPoint(x: 200, y: 200))
        XCTAssertEqual(sut.state, .floatingText)
        XCTAssertTrue(driver.visible)
    }

    func testReentryBefore300msCancelsAutomaticHide() {
        let driver = Driver()
        let scheduler = ManualScheduler()
        let sut = ReaderWindowStateController(driver: driver, scheduler: scheduler)
        var prefs = ReaderPreferences.defaults
        prefs.bossModeEnabled = true
        prefs.bossModeProfile = .concealed
        sut.applyPreferences(prefs)

        sut.pointerMoved(to: CGPoint(x: 50, y: 50))
        sut.pointerMoved(to: CGPoint(x: 200, y: 200))
        scheduler.fire(milliseconds: 300)
        XCTAssertNotEqual(sut.state, .hidden(.automaticPointerExit))
        XCTAssertTrue(driver.visible)
    }

    func testExplicitShortcutHideIsLockedAgainstPointerRestore() {
        let driver = Driver()
        let scheduler = ManualScheduler()
        let sut = ReaderWindowStateController(driver: driver, scheduler: scheduler)
        var prefs = ReaderPreferences.defaults
        prefs.bossModeEnabled = true
        sut.applyPreferences(prefs)

        sut.toggleEmergencyShortcut()
        XCTAssertEqual(sut.state, .hidden(.explicitShortcut))
        sut.pointerMoved(to: CGPoint(x: 200, y: 200))
        XCTAssertEqual(sut.state, .hidden(.explicitShortcut))
        XCTAssertFalse(driver.visible)

        sut.toggleEmergencyShortcut()
        XCTAssertEqual(sut.state, .floatingText)
        XCTAssertTrue(driver.visible)
    }

    func testOptionTemporarilyEnablesInteractionThenReturnsAfter300ms() {
        let driver = Driver()
        let scheduler = ManualScheduler()
        let sut = ReaderWindowStateController(driver: driver, scheduler: scheduler)
        var prefs = ReaderPreferences.defaults
        prefs.bossModeEnabled = true
        sut.applyPreferences(prefs)
        sut.pointerMoved(to: CGPoint(x: 200, y: 200))

        sut.optionChanged(isDown: true)
        XCTAssertEqual(sut.state, .interactiveStealth)
        XCTAssertFalse(driver.ignoresMouseEvents)

        sut.optionChanged(isDown: false)
        scheduler.fire(milliseconds: 300)
        XCTAssertEqual(sut.state, .floatingText)
        XCTAssertTrue(driver.ignoresMouseEvents)
    }

    func testLockInteractiveOverridesOptionRelease() {
        let driver = Driver()
        let scheduler = ManualScheduler()
        let sut = ReaderWindowStateController(driver: driver, scheduler: scheduler)
        var prefs = ReaderPreferences.defaults
        prefs.bossModeEnabled = true
        sut.applyPreferences(prefs)
        sut.setLockInteractive(true)
        sut.optionChanged(isDown: false)
        scheduler.fire(milliseconds: 300)
        XCTAssertEqual(sut.state, .interactiveStealth)
        XCTAssertFalse(driver.ignoresMouseEvents)
    }
}
```

- [ ] **Step 2: Run and confirm RED**

```bash
swift test --filter ReaderWindowStateControllerTests
```

Expected: compile failure because the state/controller/scheduler interfaces do not exist.

- [ ] **Step 3: Create the cancellable delay abstraction**

Create `DelayScheduler.swift`:

```swift
import Foundation

@MainActor
protocol DelayCancellation: AnyObject {
    func cancel()
}

@MainActor
protocol DelayScheduling: AnyObject {
    func schedule(
        afterMilliseconds milliseconds: Int,
        action: @escaping @MainActor () -> Void
    ) -> any DelayCancellation
}

@MainActor
final class TaskDelayCancellation: DelayCancellation {
    private var task: Task<Void, Never>?
    init(task: Task<Void, Never>) { self.task = task }
    func cancel() {
        task?.cancel()
        task = nil
    }
}

@MainActor
final class TaskDelayScheduler: DelayScheduling {
    func schedule(
        afterMilliseconds milliseconds: Int,
        action: @escaping @MainActor () -> Void
    ) -> any DelayCancellation {
        let task = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(milliseconds))
            guard !Task.isCancelled else { return }
            action()
        }
        return TaskDelayCancellation(task: task)
    }
}
```

- [ ] **Step 4: Implement the state controller**

Create `ReaderWindowStateController.swift` with these exact public/internal interfaces:

```swift
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
    private var hideDelay: (any DelayCancellation)?
    private var optionReleaseDelay: (any DelayCancellation)?
    private var preferences = ReaderPreferences.defaults
    private var lastVisibleState: ReaderWindowState = .normal
    private var lastPointerInside = false
    private var optionDown = false

    init(
        driver: any ReaderWindowDriving,
        scheduler: any DelayScheduling = TaskDelayScheduler()
    ) {
        self.driver = driver
        self.scheduler = scheduler
    }

    func applyPreferences(_ value: ReaderPreferences) {
        preferences = value
        cancelHide()
        if !value.bossModeEnabled {
            transition(to: .normal, show: true)
            return
        }
        let target: ReaderWindowState = lockInteractive ? .interactiveStealth : .floatingText
        transition(to: target, show: true)
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
                guard let self, !self.optionDown, !self.lockInteractive else { return }
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
        if case .hidden = state {
            transition(to: restoredVisibleState(), show: true)
        } else {
            lastVisibleState = state
            cancelHide()
            transition(to: .hidden(.explicitShortcut), show: false)
        }
    }

    func showExplicitly() {
        cancelHide()
        transition(to: preferences.bossModeEnabled ? restoredVisibleState() : .normal, show: true)
    }

    func hideExplicitly() {
        if !isHidden { lastVisibleState = state }
        cancelHide()
        transition(to: .hidden(.explicitMenuAction), show: false)
    }

    private var isHidden: Bool {
        if case .hidden = state { return true }
        return false
    }

    private var isExplicitlyHidden: Bool {
        switch state {
        case .hidden(.explicitShortcut), .hidden(.explicitMenuAction): true
        default: false
        }
    }

    private func restoredVisibleState() -> ReaderWindowState {
        if !preferences.bossModeEnabled { return .normal }
        if lockInteractive || (optionDown && lastPointerInside) { return .interactiveStealth }
        switch lastVisibleState {
        case .interactiveStealth where lockInteractive: return .interactiveStealth
        default: return .floatingText
        }
    }

    private func scheduleAutomaticHide() {
        guard hideDelay == nil else { return }
        hideDelay = scheduler.schedule(afterMilliseconds: 300) { [weak self] in
            guard let self, !self.lastPointerInside else { return }
            if !self.isHidden { self.lastVisibleState = self.state }
            self.transition(to: .hidden(.automaticPointerExit), show: false)
            self.hideDelay = nil
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
```

- [ ] **Step 5: Run controller tests**

```bash
swift test --filter ReaderWindowStateControllerTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/ReadBook/Window/DelayScheduler.swift Sources/ReadBook/Window/ReaderWindowStateController.swift Tests/ReadBookAppTests/ReaderWindowStateControllerTests.swift
git commit -m "feat: add reader window state machine"
```

---

### Task 3: Make WindowRegistry the AppKit execution layer

**Files:**
- Modify: `Sources/ReadBook/Window/WindowRegistry.swift`
- Modify: `Sources/ReadBook/Window/WindowCoordinator.swift`
- Modify: `Tests/ReadBookAppTests/WindowCoordinatorTests.swift`

**Interfaces:**
- Consumes: `ReaderWindowDriving`, `ReaderWindowAppearance`, `AppPresenceMode`.
- Produces: `WindowRegistry.readerFrameInScreen`, explicit show/hide/pass-through and appearance application.

- [ ] **Step 1: Add AppKit behavior tests**

Extend `WindowCoordinatorTests.swift`:

```swift
func testConfigureDoesNotDependOnMovableByBackground() {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 360, height: 260),
        styleMask: [.titled, .resizable],
        backing: .buffered,
        defer: false
    )
    WindowCoordinator().configure(window)
    XCTAssertFalse(window.styleMask.contains(.titled))
    XCTAssertTrue(window.styleMask.contains(.resizable))
    XCTAssertFalse(window.isMovableByWindowBackground)
}

func testRegistryAppliesTransparentAndFramelessWindowTraits() {
    let registry = WindowRegistry()
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 360, height: 260),
        styleMask: [.borderless, .resizable],
        backing: .buffered,
        defer: false
    )
    registry.register(window)

    registry.applyAppearance(.transparent)
    XCTAssertFalse(window.hasShadow)
    XCTAssertFalse(window.isOpaque)

    registry.applyAppearance(.frameless)
    XCTAssertFalse(window.hasShadow)

    registry.applyAppearance(.card)
    XCTAssertTrue(window.hasShadow)
}

func testRegistryPointerPassThroughMapsToNSWindow() {
    let registry = WindowRegistry()
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 360, height: 260),
        styleMask: [.borderless, .resizable],
        backing: .buffered,
        defer: false
    )
    registry.register(window)
    registry.setPointerPassThrough(true)
    XCTAssertTrue(window.ignoresMouseEvents)
    registry.setPointerPassThrough(false)
    XCTAssertFalse(window.ignoresMouseEvents)
}
```

- [ ] **Step 2: Run and confirm RED**

```bash
swift test --filter WindowCoordinatorTests
```

Expected: failure because current coordinator sets `isMovableByWindowBackground = true` and registry lacks appearance/driver methods.

- [ ] **Step 3: Update WindowCoordinator baseline**

Change `configure(_:)` so its relevant lines are:

```swift
window.styleMask.remove(.titled)
window.styleMask.insert([.resizable, .closable])
window.isMovableByWindowBackground = false
window.isReleasedWhenClosed = false
window.backgroundColor = .clear
window.isOpaque = false
window.hasShadow = true
window.setFrameAutosaveName("ReadBook.ReaderWindow")
```

Do not reintroduce a native titlebar.

- [ ] **Step 4: Make WindowRegistry conform to ReaderWindowDriving**

Use these exact methods/properties:

```swift
@MainActor
final class WindowRegistry: ReaderWindowDriving {
    private weak var readerWindow: NSWindow?
    private let coordinator = WindowCoordinator()

    var readerFrameInScreen: CGRect? { readerWindow?.frame }

    func register(_ window: NSWindow) {
        guard readerWindow !== window else { return }
        readerWindow = window
        coordinator.configure(window)
    }

    func showReader(activate: Bool = true) {
        guard let readerWindow else { return }
        readerWindow.makeKeyAndOrderFront(nil)
        if activate { NSApp.activate(ignoringOtherApps: true) }
    }

    func hideReader() {
        NotificationCenter.default.post(name: .readBookReaderWillHide, object: nil)
        readerWindow?.orderOut(nil)
    }

    func setPointerPassThrough(_ enabled: Bool) {
        readerWindow?.ignoresMouseEvents = enabled
    }

    func applyAppearance(_ appearance: ReaderWindowAppearance) {
        guard let readerWindow else { return }
        readerWindow.backgroundColor = .clear
        readerWindow.isOpaque = false
        readerWindow.hasShadow = appearance == .card
    }

    func setAlwaysOnTop(_ enabled: Bool) {
        readerWindow?.level = enabled ? .floating : .normal
    }

    func setAppPresence(_ mode: AppPresenceMode) {
        NSApp.setActivationPolicy(mode == .widgetStyle ? .accessory : .regular)
        if mode == .normal { NSApp.activate(ignoringOtherApps: true) }
    }
}
```

Retain `toggleReader()` only if another call site still uses it; route it through explicit show/hide semantics rather than creating a second state authority.

- [ ] **Step 5: Run AppKit tests**

```bash
swift test --filter WindowCoordinatorTests
swift test --filter ReaderWindowStateControllerTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/ReadBook/Window/WindowRegistry.swift Sources/ReadBook/Window/WindowCoordinator.swift Tests/ReadBookAppTests/WindowCoordinatorTests.swift
git commit -m "refactor: make window registry execute stealth state"
```

---

### Task 4: Add global emergency hotkey and global pointer/modifier routing

**Files:**
- Create: `Sources/ReadBook/Input/GlobalHotKeyService.swift`
- Create: `Sources/ReadBook/Input/ReaderGlobalInputService.swift`
- Create: `Tests/ReadBookAppTests/ReaderGlobalInputServiceTests.swift`

**Interfaces:**
- Consumes: `ReaderWindowStateController.pointerMoved(to:)`, `optionChanged(isDown:)`, `toggleEmergencyShortcut()`.
- Produces: `GlobalHotKeyService.start() -> Bool`, `stop()`, `ReaderGlobalInputService.start() -> Bool`, `stop()`.

- [ ] **Step 1: Write semantic routing tests**

Create `ReaderGlobalInputServiceTests.swift`:

```swift
import AppKit
import XCTest
@testable import ReadBook

@MainActor
final class ReaderGlobalInputServiceTests: XCTestCase {
    final class Sink: ReaderGlobalInputHandling {
        var points: [CGPoint] = []
        var optionStates: [Bool] = []
        func pointerMoved(to point: CGPoint) { points.append(point) }
        func optionChanged(isDown: Bool) { optionStates.append(isDown) }
    }

    func testSemanticInputRoutesPointerAndOptionState() {
        let sink = Sink()
        let sut = ReaderGlobalInputService(sink: sink)
        sut.consume(mouseLocation: CGPoint(x: 321, y: 456), modifierFlags: [.option])
        sut.consume(mouseLocation: CGPoint(x: 400, y: 500), modifierFlags: [])

        XCTAssertEqual(sink.points, [CGPoint(x: 321, y: 456), CGPoint(x: 400, y: 500)])
        XCTAssertEqual(sink.optionStates, [true, false])
    }
}
```

- [ ] **Step 2: Run and confirm RED**

```bash
swift test --filter ReaderGlobalInputServiceTests
```

Expected: compile failure because input interfaces/services do not exist.

- [ ] **Step 3: Add the semantic input service with local + global monitors**

Create `ReaderGlobalInputService.swift`:

```swift
import AppKit

@MainActor
protocol ReaderGlobalInputHandling: AnyObject {
    func pointerMoved(to point: CGPoint)
    func optionChanged(isDown: Bool)
}

extension ReaderWindowStateController: ReaderGlobalInputHandling {}

@MainActor
final class ReaderGlobalInputService {
    private weak var sink: (any ReaderGlobalInputHandling)?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastOptionDown: Bool?

    init(sink: any ReaderGlobalInputHandling) {
        self.sink = sink
    }

    @discardableResult
    func start() -> Bool {
        guard globalMonitor == nil, localMonitor == nil else { return true }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .flagsChanged]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.consume(mouseLocation: NSEvent.mouseLocation, modifierFlags: NSEvent.modifierFlags)
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .flagsChanged]) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.consume(mouseLocation: NSEvent.mouseLocation, modifierFlags: event.modifierFlags)
            }
            return event
        }

        return globalMonitor != nil && localMonitor != nil
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        lastOptionDown = nil
    }

    func consume(mouseLocation: CGPoint, modifierFlags: NSEvent.ModifierFlags) {
        sink?.pointerMoved(to: mouseLocation)
        let optionDown = modifierFlags.contains(.option)
        if optionDown != lastOptionDown {
            lastOptionDown = optionDown
            sink?.optionChanged(isDown: optionDown)
        }
    }
}
```

There is intentionally no timer/polling loop.

- [ ] **Step 4: Implement the Carbon hotkey service**

Create `GlobalHotKeyService.swift` using Carbon so `⌃⌥R` does not depend on the ReadBook window being frontmost:

```swift
import Carbon

@MainActor
final class GlobalHotKeyService {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    var onToggle: @MainActor () -> Void = {}

    @discardableResult
    func start() -> Bool {
        guard hotKeyRef == nil else { return true }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let opaqueSelf = Unmanaged.passUnretained(self).toOpaque()

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr, hotKeyID.id == 1 else { return status }
                let service = Unmanaged<GlobalHotKeyService>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated { service.onToggle() }
                return noErr
            },
            1,
            &eventType,
            opaqueSelf,
            &eventHandlerRef
        )
        guard handlerStatus == noErr else { return false }

        let hotKeyID = EventHotKeyID(signature: OSType(0x52424B31), id: 1) // RBK1
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_R),
            UInt32(controlKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if registerStatus != noErr {
            stop()
            return false
        }
        return true
    }

    func stop() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
        hotKeyRef = nil
        eventHandlerRef = nil
    }
}
```

If Swift 6 reports a Carbon callback type mismatch, keep the same API/behavior and fix only the callback type adaptation; do not replace this with a polling keyboard watcher or an Accessibility-dependent key-event tap.

- [ ] **Step 5: Run tests and build on macOS**

```bash
swift test --filter ReaderGlobalInputServiceTests
swift build
```

Expected: PASS/build succeeds with Carbon linked from the system SDK.

- [ ] **Step 6: Commit**

```bash
git add Sources/ReadBook/Input Tests/ReadBookAppTests/ReaderGlobalInputServiceTests.swift
git commit -m "feat: add global stealth input services"
```

---

### Task 5: Replace generic hover with explicit chrome-intent timing

**Files:**
- Create: `Sources/ReadBook/Reader/ReaderChromeController.swift`
- Create: `Tests/ReadBookAppTests/ReaderChromeControllerTests.swift`

**Interfaces:**
- Consumes: `DelayScheduling`.
- Produces: observable `topVisible`, `bottomVisible`, `attach(to:)`, `detach()`, `setOptionInteraction(_:)`, `beginControlInteraction()`, `endControlInteraction()`.

- [ ] **Step 1: Write chrome timing tests**

Create `ReaderChromeControllerTests.swift`:

```swift
import XCTest
@testable import ReadBook

@MainActor
final class ReaderChromeControllerTests: XCTestCase {
    final class Token: DelayCancellation {
        var cancelled = false
        func cancel() { cancelled = true }
    }

    final class ManualScheduler: DelayScheduling {
        struct Pending { let ms: Int; let token: Token; let action: @MainActor () -> Void }
        var pending: [Pending] = []
        func schedule(afterMilliseconds milliseconds: Int, action: @escaping @MainActor () -> Void) -> any DelayCancellation {
            let token = Token()
            pending.append(Pending(ms: milliseconds, token: token, action: action))
            return token
        }
        func fire(_ ms: Int) {
            let due = pending.filter { $0.ms == ms && !$0.token.cancelled }
            pending.removeAll { $0.ms == ms }
            due.forEach { $0.action() }
        }
    }

    func testBodyHoverAndScrollDoNotRevealChrome() {
        let scheduler = ManualScheduler()
        let sut = ReaderChromeController(scheduler: scheduler)
        sut.processPointer(localY: 100, contentHeight: 260)
        sut.processScroll()
        scheduler.fire(250)
        XCTAssertFalse(sut.topVisible)
        XCTAssertFalse(sut.bottomVisible)
    }

    func testTopAndBottomNeed250msDwell() {
        let scheduler = ManualScheduler()
        let sut = ReaderChromeController(scheduler: scheduler)

        sut.processPointer(localY: 250, contentHeight: 260)
        XCTAssertFalse(sut.topVisible)
        scheduler.fire(250)
        XCTAssertTrue(sut.topVisible)
        XCTAssertFalse(sut.bottomVisible)

        sut.processPointer(localY: 8, contentHeight: 260)
        scheduler.fire(250)
        XCTAssertTrue(sut.bottomVisible)
    }

    func testReturningToBodyDismissesAfter200ms() {
        let scheduler = ManualScheduler()
        let sut = ReaderChromeController(scheduler: scheduler)
        sut.processPointer(localY: 250, contentHeight: 260)
        scheduler.fire(250)
        XCTAssertTrue(sut.topVisible)

        sut.processPointer(localY: 100, contentHeight: 260)
        scheduler.fire(200)
        XCTAssertFalse(sut.topVisible)
        XCTAssertFalse(sut.bottomVisible)
    }

    func testOptionInteractionRevealsBothImmediately() {
        let sut = ReaderChromeController(scheduler: ManualScheduler())
        sut.setOptionInteraction(true)
        XCTAssertTrue(sut.topVisible)
        XCTAssertTrue(sut.bottomVisible)
    }
}
```

- [ ] **Step 2: Run and confirm RED**

```bash
swift test --filter ReaderChromeControllerTests
```

Expected: compile failure because `ReaderChromeController` does not exist.

- [ ] **Step 3: Implement the controller and local event monitor**

Create `ReaderChromeController.swift`. Its state/timing core must be:

```swift
import AppKit
import Observation

@MainActor
@Observable
final class ReaderChromeController {
    private(set) var topVisible = false
    private(set) var bottomVisible = false

    private let scheduler: any DelayScheduling
    private var topDwell: (any DelayCancellation)?
    private var bottomDwell: (any DelayCancellation)?
    private var dismissDelay: (any DelayCancellation)?
    private var localMonitor: Any?
    private var controlInteractionDepth = 0
    private var optionInteraction = false

    init(scheduler: any DelayScheduling = TaskDelayScheduler()) {
        self.scheduler = scheduler
    }

    func attach(to window: NSWindow) {
        detach()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .scrollWheel]) { [weak self, weak window] event in
            guard let self, let window, event.window === window else { return event }
            Task { @MainActor in
                if event.type == .scrollWheel {
                    self.processScroll()
                } else {
                    let height = window.contentView?.bounds.height ?? window.frame.height
                    self.processPointer(localY: event.locationInWindow.y, contentHeight: height)
                }
            }
            return event
        }
    }

    func detach() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        localMonitor = nil
        cancelAllDelays()
    }

    func processPointer(localY: CGFloat, contentHeight: CGFloat) {
        guard !optionInteraction, controlInteractionDepth == 0 else { return }
        let inTop = contentHeight - localY <= 20
        let inBottom = localY <= 16

        if inTop {
            dismissDelay?.cancel(); dismissDelay = nil
            bottomDwell?.cancel(); bottomDwell = nil
            if !topVisible, topDwell == nil {
                topDwell = scheduler.schedule(afterMilliseconds: 250) { [weak self] in
                    self?.topVisible = true
                    self?.topDwell = nil
                }
            }
            return
        }

        if inBottom {
            dismissDelay?.cancel(); dismissDelay = nil
            topDwell?.cancel(); topDwell = nil
            if !bottomVisible, bottomDwell == nil {
                bottomDwell = scheduler.schedule(afterMilliseconds: 250) { [weak self] in
                    self?.bottomVisible = true
                    self?.bottomDwell = nil
                }
            }
            return
        }

        topDwell?.cancel(); topDwell = nil
        bottomDwell?.cancel(); bottomDwell = nil
        scheduleDismiss()
    }

    func processScroll() {
        // Intentionally no reveal or timer reset.
    }

    func setOptionInteraction(_ enabled: Bool) {
        optionInteraction = enabled
        if enabled {
            cancelAllDelays()
            topVisible = true
            bottomVisible = true
        } else if controlInteractionDepth == 0 {
            scheduleDismiss()
        }
    }

    func beginControlInteraction() {
        controlInteractionDepth += 1
        cancelAllDelays()
    }

    func endControlInteraction() {
        controlInteractionDepth = max(0, controlInteractionDepth - 1)
        if controlInteractionDepth == 0, !optionInteraction { scheduleDismiss() }
    }

    private func scheduleDismiss() {
        guard dismissDelay == nil else { return }
        dismissDelay = scheduler.schedule(afterMilliseconds: 200) { [weak self] in
            guard let self, self.controlInteractionDepth == 0, !self.optionInteraction else { return }
            self.topVisible = false
            self.bottomVisible = false
            self.dismissDelay = nil
        }
    }

    private func cancelAllDelays() {
        topDwell?.cancel(); topDwell = nil
        bottomDwell?.cancel(); bottomDwell = nil
        dismissDelay?.cancel(); dismissDelay = nil
    }
}
```

- [ ] **Step 4: Run chrome tests**

```bash
swift test --filter ReaderChromeControllerTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ReadBook/Reader/ReaderChromeController.swift Tests/ReadBookAppTests/ReaderChromeControllerTests.swift
git commit -m "feat: add intent-based reader chrome"
```

---

### Task 6: Add reliable explicit drag region and scrim-backed pure-reading UI

**Files:**
- Create: `Sources/ReadBook/Window/ReaderDragRegion.swift`
- Modify: `Sources/ReadBook/Reader/ReaderToolbar.swift`
- Modify: `Sources/ReadBook/Reader/ReaderRootView.swift`

**Interfaces:**
- Consumes: `ReaderChromeController`, `ReaderWindowStateController`, `ReaderWindowAppearance`.
- Produces: drag-enabled top title region, 0%-background transparent mode, 18%-default frameless surface, separate top/bottom scrims.

- [ ] **Step 1: Create the explicit AppKit drag bridge**

Create `ReaderDragRegion.swift`:

```swift
import AppKit
import SwiftUI

struct ReaderDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override var acceptsFirstResponder: Bool { false }
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
```

Do not put this overlay over toolbar buttons.

- [ ] **Step 2: Restructure ReaderToolbar so title/empty space is the drag surface**

Replace the current plain title/spacer segment with:

```swift
HStack(spacing: 8) {
    Text(title)
        .font(.system(size: 12, weight: .medium))
        .lineLimit(1)
    Spacer(minLength: 8)
}
.contentShape(Rectangle())
.overlay { ReaderDragRegion() }
```

Keep the library, reading-mode, pin, and settings buttons outside this overlay so they remain normal button hit targets.

- [ ] **Step 3: Remove generic `hovering` state from ReaderRootView**

Change the root signature to:

```swift
struct ReaderRootView: View {
    @Bindable var model: AppModel
    @Bindable var windowState: ReaderWindowStateController
    @Bindable var chrome: ReaderChromeController
```

Delete:

```swift
@State private var hovering = false
.onHover { hovering = $0 }
.animation(.easeOut(duration: 0.14), value: hovering)
```

Delete all conditions that map ordinary body hover to toolbar/footer visibility.

- [ ] **Step 4: Render the surface according to appearance**

Add helpers:

```swift
private var surfaceOpacity: Double {
    switch model.preferences.windowAppearance {
    case .card: 1
    case .frameless: model.preferences.framelessBackgroundOpacity
    case .transparent: 0
    }
}

private var surfaceCornerRadius: CGFloat {
    model.preferences.windowAppearance == .card ? 26 : 0
}
```

Use:

```swift
Color(nsColor: palette.background)
    .opacity(surfaceOpacity)
```

and clip only with the computed corner radius. Transparent mode must not add a hidden solid layer behind the text.

- [ ] **Step 5: Render top/bottom controls only from ReaderChromeController with scrims**

Use a top overlay equivalent to:

```swift
if chrome.topVisible {
    ReaderToolbar(/* existing arguments */)
        .padding(.bottom, 10)
        .background(
            Color(nsColor: palette.background)
                .opacity(model.preferences.windowAppearance == .transparent ? 0.94 : 0.90)
        )
        .transition(.opacity)
}
```

Use a bottom status overlay equivalent to:

```swift
if chrome.bottomVisible {
    HStack {
        Text(model.currentChapter?.title ?? "").lineLimit(1)
        Spacer()
        Text("\(model.progressPercent)%").monospacedDigit()
    }
    .font(.system(size: 11))
    .foregroundStyle(Color(nsColor: palette.secondaryText))
    .padding(.horizontal, 16)
    .padding(.vertical, 9)
    .background(
        Color(nsColor: palette.background)
            .opacity(model.preferences.windowAppearance == .transparent ? 0.94 : 0.90)
    )
    .transition(.opacity)
}
```

The body text may remain laid out behind these overlays, but the scrim must make that body text visually invisible in the control region; there must be no visible title/body/footer stacking.

- [ ] **Step 6: Keep popover interaction from auto-dismissing chrome**

When opening the library popover:

```swift
onLibrary: {
    chrome.beginControlInteraction()
    showLibrary = true
}
```

Add:

```swift
.onChange(of: showLibrary) { _, shown in
    if !shown { chrome.endControlInteraction() }
}
```

- [ ] **Step 7: Build and run the existing reader tests**

```bash
swift test
swift build
```

Expected: all existing tests plus new controller tests pass; no call site still depends on the removed `hovering` state.

- [ ] **Step 8: Commit**

```bash
git add Sources/ReadBook/Window/ReaderDragRegion.swift Sources/ReadBook/Reader/ReaderToolbar.swift Sources/ReadBook/Reader/ReaderRootView.swift
git commit -m "feat: make reader chrome intentional and draggable"
```

---

### Task 7: Wire runtime lifecycle, Boss Mode menu controls, and Settings

**Files:**
- Create: `Sources/ReadBook/App/AppRuntime.swift`
- Modify: `Sources/ReadBook/App/AppDelegate.swift`
- Modify: `Sources/ReadBook/App/AppModel.swift`
- Modify: `Sources/ReadBook/App/ReadBookApp.swift`
- Modify: `Sources/ReadBook/Settings/SettingsView.swift`

**Interfaces:**
- Consumes: all controllers/services from Tasks 2–6.
- Produces: one `AppRuntime` lifecycle owner; menu/Settings actions that update durable preferences and immediately apply them.

- [ ] **Step 1: Add explicit AppModel preference setters**

Add to `AppModel`:

```swift
func setBossModeEnabled(_ enabled: Bool) {
    updatePreferences {
        $0.bossModeEnabled = enabled
        if enabled { $0.windowAppearance = .transparent }
    }
}

func setBossModeProfile(_ profile: BossModeProfile) {
    updatePreferences { $0.bossModeProfile = profile }
}

func setWindowAppearance(_ appearance: ReaderWindowAppearance) {
    updatePreferences { $0.windowAppearance = appearance }
}

func setFramelessBackgroundOpacity(_ value: Double) {
    updatePreferences { $0.framelessBackgroundOpacity = min(max(value, 0), 0.60) }
}
```

The deliberate `setBossModeEnabled(true)` behavior selects Transparent as the default stealth appearance each time Boss Mode is newly enabled; the user can then choose Frameless/Card explicitly while Boss Mode remains on.

- [ ] **Step 2: Create one AppRuntime owner**

Create `AppRuntime.swift`:

```swift
import AppKit
import Observation
import ReadBookCore

@MainActor
@Observable
final class AppRuntime {
    let windowRegistry: WindowRegistry
    let windowState: ReaderWindowStateController
    let chrome: ReaderChromeController
    let globalInput: ReaderGlobalInputService
    let hotKey: GlobalHotKeyService
    private(set) var hotKeyAvailable = true
    private var started = false

    init() {
        let registry = WindowRegistry()
        let state = ReaderWindowStateController(driver: registry)
        self.windowRegistry = registry
        self.windowState = state
        self.chrome = ReaderChromeController()
        self.globalInput = ReaderGlobalInputService(sink: state)
        self.hotKey = GlobalHotKeyService()
        hotKey.onToggle = { [weak state] in state?.toggleEmergencyShortcut() }
    }

    func register(window: NSWindow, preferences: ReaderPreferences) {
        windowRegistry.register(window)
        chrome.attach(to: window)
        apply(preferences)
        guard !started else { return }
        started = true
        _ = globalInput.start()
        hotKeyAvailable = hotKey.start()
    }

    func apply(_ preferences: ReaderPreferences) {
        windowRegistry.setAlwaysOnTop(preferences.alwaysOnTop)
        windowRegistry.setAppPresence(preferences.appPresenceMode)
        windowRegistry.applyAppearance(preferences.windowAppearance)
        windowState.applyPreferences(preferences)
    }

    func optionInteractionChanged(_ enabled: Bool) {
        chrome.setOptionInteraction(enabled)
    }

    func shutdown() {
        chrome.detach()
        globalInput.stop()
        hotKey.stop()
        started = false
    }
}
```

Wire Option chrome visibility from the same semantic input path instead of installing another global monitor. Extend `ReaderGlobalInputService` with optional `onOptionChanged` closure and call it whenever the option state changes; set it in `AppRuntime.init` to `chrome.setOptionInteraction` while still sending the state to `windowState`.

- [ ] **Step 3: Add termination cleanup**

In `AppDelegate` add:

```swift
var cleanupHandler: (@MainActor () -> Void)?
```

Before replying to termination, execute:

```swift
cleanupHandler?()
```

Also call it on the immediate `.terminateNow` path if a runtime was already installed. Ensure cleanup is invoked once.

- [ ] **Step 4: Inject AppRuntime from ReadBookApp**

Use:

```swift
@State private var model = AppModel()
@State private var runtime = AppRuntime()
```

Pass controllers into the root:

```swift
ReaderRootView(
    model: model,
    windowState: runtime.windowState,
    chrome: runtime.chrome
)
```

Inside `WindowAccessor`:

```swift
runtime.register(window: window, preferences: model.preferences)
```

On `.readBookWindowPreferencesChanged`:

```swift
runtime.apply(model.preferences)
```

In the existing `.task` where `flushHandler` is installed, also set:

```swift
appDelegate.cleanupHandler = { @MainActor in runtime.shutdown() }
```

- [ ] **Step 5: Replace menu show/hide with state-controller semantics**

Menu-bar actions must use:

```swift
Button("显示阅读器") { runtime.windowState.showExplicitly() }
Button("隐藏阅读器") { runtime.windowState.hideExplicitly() }
```

Use one dynamic label if desired, but do not call a direct `WindowRegistry.toggleReader()` that bypasses `ReaderWindowStateController`.

Add a Boss Mode toggle:

```swift
Toggle("老板模式", isOn: Binding(
    get: { model.preferences.bossModeEnabled },
    set: { value in
        model.setBossModeEnabled(value)
        runtime.apply(model.preferences)
    }
))
```

Add profile actions:

```swift
Picker("老板模式行为", selection: Binding(
    get: { model.preferences.bossModeProfile },
    set: { value in
        model.setBossModeProfile(value)
        runtime.apply(model.preferences)
    }
)) {
    Text("悬浮阅读").tag(BossModeProfile.floatingReading)
    Text("隐蔽：移出即隐藏").tag(BossModeProfile.concealed)
}
```

Add session-only interaction lock:

```swift
Toggle("锁定为可交互", isOn: Binding(
    get: { runtime.windowState.lockInteractive },
    set: { runtime.windowState.setLockInteractive($0) }
))
```

Add appearance picker actions for Card/Frameless/Transparent.

- [ ] **Step 6: Extend SettingsView**

Under a new `Section("老板模式")`, add the durable Boss toggle/profile. Under `Section("窗口")`, add appearance and opacity:

```swift
Picker("外观", selection: Binding(
    get: { model.preferences.windowAppearance },
    set: { value in
        model.setWindowAppearance(value)
        windowRegistry.applyAppearance(value)
    }
)) {
    Text("卡片").tag(ReaderWindowAppearance.card)
    Text("无边框").tag(ReaderWindowAppearance.frameless)
    Text("纯透明").tag(ReaderWindowAppearance.transparent)
}

if model.preferences.windowAppearance == .frameless {
    LabeledContent("背景透明度") {
        Slider(
            value: Binding(
                get: { model.preferences.framelessBackgroundOpacity },
                set: { model.setFramelessBackgroundOpacity($0) }
            ),
            in: 0...0.60,
            step: 0.01
        )
        Text("\(Int(model.preferences.framelessBackgroundOpacity * 100))%")
            .monospacedDigit()
            .frame(width: 42, alignment: .trailing)
    }
}
```

Show fixed shortcut status:

```swift
LabeledContent("紧急隐藏快捷键") {
    Text(runtime.hotKeyAvailable ? "⌃⌥R" : "⌃⌥R 注册失败，请使用菜单栏")
        .foregroundStyle(runtime.hotKeyAvailable ? .primary : .red)
}
```

Change `SettingsView` initializer from only `windowRegistry` to accept `runtime: AppRuntime`; use `runtime.windowRegistry` for existing always-on-top/app-presence operations.

- [ ] **Step 7: Run full tests/build**

```bash
swift test
swift build
```

Expected: PASS. Existing library/reader tests remain unchanged; the app compiles with the runtime lifecycle.

- [ ] **Step 8: Commit**

```bash
git add Sources/ReadBook/App Sources/ReadBook/Settings/SettingsView.swift Sources/ReadBook/Input/ReaderGlobalInputService.swift
git commit -m "feat: wire boss mode runtime and settings"
```

---

### Task 8: Add custom ReadBook branding and curated SVG references

**Files:**
- Create: `DesignAssets/ReadBookMark.svg`
- Create: `DesignAssets/Tabler/ghost-2.svg`
- Create: `DesignAssets/Tabler/eye-off.svg`
- Create: `DesignAssets/Tabler/border-none.svg`
- Create: `DesignAssets/Tabler/LICENSE`
- Create: `Scripts/render-app-icon.swift`
- Modify: `Scripts/build-app.sh`

**Interfaces:**
- Consumes: macOS AppKit SVG decoding, `iconutil`.
- Produces: `ReadBook.icns` in `ReadBook.app/Contents/Resources`, `CFBundleIconFile=ReadBook`.

- [ ] **Step 1: Add the custom vector master**

Create `DesignAssets/ReadBookMark.svg` exactly as a clean, original ReadBook mark:

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <rect x="64" y="64" width="896" height="896" rx="220" fill="#20242A"/>
  <path d="M258 250h300c112 0 208 78 208 202v322c-61-48-132-72-214-72H258z" fill="#F6F1E7"/>
  <path d="M552 250c118 0 214 78 214 202v322c-61-48-132-72-214-72z" fill="#DDE5EB"/>
  <path d="M386 365h177c83 0 137 45 137 116 0 55-33 94-86 109l101 121h-99l-84-106h-62v106h-84zm84 70v101h82c39 0 62-19 62-51 0-32-23-50-62-50z" fill="#20242A"/>
  <path d="M552 250v452" stroke="#BCC7CF" stroke-width="18" stroke-linecap="round"/>
</svg>
```

This is the canonical vector master. Do not substitute an off-the-shelf book icon for the App identity.

- [ ] **Step 2: Add the curated Tabler source SVGs and license**

Copy the exact upstream MIT-licensed source files from `tabler/tabler-icons`:

- `icons/outline/ghost-2.svg` -> `DesignAssets/Tabler/ghost-2.svg`
- `icons/outline/eye-off.svg` -> `DesignAssets/Tabler/eye-off.svg`
- `icons/outline/border-none.svg` -> `DesignAssets/Tabler/border-none.svg`
- upstream `LICENSE` -> `DesignAssets/Tabler/LICENSE`

These are curated design/reference assets. Keep native SF Symbols in shipping controls where they are already stronger; do not add an SVG rendering dependency solely to replace working SF Symbols.

- [ ] **Step 3: Create deterministic iconset rasterization**

Create `Scripts/render-app-icon.swift`:

```swift
#!/usr/bin/env swift
import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count == 3 else {
    fputs("usage: render-app-icon.swift <input.svg> <output.iconset>\n", stderr)
    exit(2)
}

let sourceURL = URL(fileURLWithPath: args[1])
let outputURL = URL(fileURLWithPath: args[2], isDirectory: true)
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

guard let source = NSImage(contentsOf: sourceURL) else {
    fputs("failed to load SVG: \(sourceURL.path)\n", stderr)
    exit(3)
}

let outputs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (name, pixels) in outputs {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { exit(4) }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    source.draw(
        in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
        from: .zero,
        operation: .copy,
        fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else { exit(5) }
    try png.write(to: outputURL.appendingPathComponent(name))
}
```

Mark it executable in git.

- [ ] **Step 4: Update app packaging for v0.1.3 and icon generation**

In `Scripts/build-app.sh`, change Info.plist version fields to:

```xml
<key>CFBundleShortVersionString</key><string>0.1.3</string>
<key>CFBundleVersion</key><string>4</string>
<key>CFBundleIconFile</key><string>ReadBook</string>
```

Before final `codesign`, add:

```bash
ICONSET="$ROOT/.build/ReadBook.iconset"
rm -rf "$ICONSET"
swift "$ROOT/Scripts/render-app-icon.swift" "$ROOT/DesignAssets/ReadBookMark.svg" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/ReadBook.icns"
rm -rf "$ICONSET"
```

Then keep the existing final bundle `codesign --force --sign - --timestamp=none "$APP"` after the icon is present so the icon resource is sealed into the signature.

- [ ] **Step 5: Verify packaging locally/on macOS runner**

Run:

```bash
Scripts/build-app.sh
plutil -extract CFBundleIconFile raw dist/ReadBook.app/Contents/Info.plist
test -s dist/ReadBook.app/Contents/Resources/ReadBook.icns
codesign --verify --deep --strict --verbose=4 dist/ReadBook.app
```

Expected output includes `ReadBook` for `CFBundleIconFile`, icon file exists/non-empty, and strict codesign succeeds.

- [ ] **Step 6: Commit**

```bash
git add DesignAssets Scripts/render-app-icon.swift Scripts/build-app.sh
git commit -m "feat: add ReadBook application branding"
```

---

### Task 9: Add CI preview artifact and full regression gates

**Files:**
- Modify: `.github/workflows/bootstrap-readbook.yml`
- Create: `docs/qa/2026-08-31-stealth-reader-v1.3-checklist.md`

**Interfaces:**
- Consumes: existing macOS CI test/build/package/signature steps.
- Produces: signed PR preview ZIP `ReadBook-stealth-preview`, icon verification, real-device acceptance checklist.

- [ ] **Step 1: Create an archive on every CI run after signature verification**

Replace the current main-only archive step with:

```yaml
      - name: Create app archive
        run: ditto -c -k --sequesterRsrc --keepParent dist/ReadBook.app dist/ReadBook-macOS.zip
```

- [ ] **Step 2: Add branding verification**

Add after packaging/signature:

```yaml
      - name: Verify app branding
        run: |
          test "$(plutil -extract CFBundleIconFile raw dist/ReadBook.app/Contents/Info.plist)" = "ReadBook"
          test -s dist/ReadBook.app/Contents/Resources/ReadBook.icns
```

- [ ] **Step 3: Upload PR preview ZIP**

Add:

```yaml
      - name: Upload stealth preview
        if: github.event_name == 'pull_request'
        uses: actions/upload-artifact@v4
        with:
          name: ReadBook-stealth-preview
          path: dist/ReadBook-macOS.zip
          if-no-files-found: error
          retention-days: 7
```

Do not publish `v0.1.3` from a feature/PR run.

- [ ] **Step 4: Create the real-mac acceptance checklist**

Create `docs/qa/2026-08-31-stealth-reader-v1.3-checklist.md` with these unchecked cases:

```markdown
# ReadBook v0.1.3 Stealth Reader Acceptance

- [ ] Open a multi-million-character TXT and confirm continuous scrolling remains smooth/bounded.
- [ ] Move the pointer over body text and scroll for at least 2 minutes; toolbar/footer never appear from body hover or scrolling.
- [ ] Hold the pointer in the top 20 pt zone for ~250 ms; only top controls appear with an opaque-enough theme scrim and no visible body-text overlap.
- [ ] Hold the pointer in the bottom 16 pt zone for ~250 ms; only chapter/progress status appears with its own scrim.
- [ ] Return to body; chrome fades after ~200 ms.
- [ ] Drag title/empty toolbar area; window moves. Click each toolbar button; buttons do not start a drag.
- [ ] Select Frameless; shadow disappears and default background opacity is 18%.
- [ ] Select Transparent; only text remains when chrome is hidden and window shadow is absent.
- [ ] Enable Boss Mode / Floating Reading; click and wheel actions pass through to VS Code/Chrome behind the reader.
- [ ] Hold Option inside the stored reader frame; reader becomes interactive immediately and full controls appear.
- [ ] Release Option; pass-through returns after ~300 ms.
- [ ] Turn on Lock Interactive; release Option and verify interaction remains enabled.
- [ ] Enable Boss Mode / Concealed; move pointer out and verify reader hides after ~300 ms.
- [ ] Re-enter old frame before 300 ms and verify hide is cancelled.
- [ ] Let automatic hide complete, then re-enter old frame and verify reader returns.
- [ ] Press ⌃⌥R from another foreground app; reader hides immediately.
- [ ] Move pointer into old frame while shortcut-hidden; reader stays hidden.
- [ ] Press ⌃⌥R again; reader restores.
- [ ] Quit/relaunch; Lock Interactive resets off while durable Boss/appearance preferences persist.
- [ ] Finder/Dock shows the custom ReadBook icon rather than a generic executable icon.
```

- [ ] **Step 5: Run final branch verification**

Run on macOS:

```bash
swift test
swift build
Scripts/build-app.sh
codesign --verify --deep --strict --verbose=4 dist/ReadBook.app
```

Expected: all tests pass, build/package/signature pass, and CI uploads `ReadBook-stealth-preview` for the PR.

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/bootstrap-readbook.yml docs/qa/2026-08-31-stealth-reader-v1.3-checklist.md
git commit -m "ci: add stealth reader preview and acceptance gates"
```

---

### Task 10: Review implementation against the approved spec before merging

**Files:**
- Review all changed files from Tasks 1–9.
- No new production file is required unless review finds a concrete defect.

**Interfaces:**
- Consumes: approved design spec and full branch diff.
- Produces: a review-clean implementation ready for real-device acceptance.

- [ ] **Step 1: Run the full suite with fresh evidence**

```bash
swift test
swift build
Scripts/build-app.sh
codesign -dv --verbose=4 dist/ReadBook.app
codesign --verify --deep --strict --verbose=4 dist/ReadBook.app
```

Expected: zero test failures, successful debug/release builds, strict bundle signature valid.

- [ ] **Step 2: Verify virtualized continuous rendering did not regress**

Run:

```bash
swift test --filter ContinuousTextViewTests
swift test --filter VirtualTextWindowTests
swift test --filter PaginationEngineTests
```

Expected: all bounded-layout/pagination tests pass.

- [ ] **Step 3: Inspect for state-authority violations**

Search:

```bash
grep -R "orderOut\|ignoresMouseEvents\|makeKeyAndOrderFront" -n Sources/ReadBook
```

Expected ownership:

- `WindowRegistry` contains the actual `NSWindow` show/hide/pass-through mutations.
- `ReaderWindowStateController` decides when those mutations happen through `ReaderWindowDriving`.
- No SwiftUI view independently hides the window or toggles mouse pass-through.

- [ ] **Step 4: Inspect for accidental generic-hover regression**

Search:

```bash
grep -R "onHover\|hovering" -n Sources/ReadBook/Reader
```

Expected: no reader-body `onHover` path controls toolbar/footer visibility. Any remaining hover usage must be unrelated to reader chrome and individually justified.

- [ ] **Step 5: Review external assets/license provenance**

Verify `DesignAssets/Tabler/LICENSE` contains the upstream MIT notice and the three curated SVG files match upstream source. Verify the App identity is `DesignAssets/ReadBookMark.svg`, not a Tabler/Lucide logo.

- [ ] **Step 6: Commit review fixes only if needed**

If review finds a specific defect, fix it with a regression test and commit using a precise message such as:

```bash
git commit -m "fix: preserve explicit stealth hide lock"
```

If no defect is found, do not create an empty review commit.

---

### Task 11: Real-device acceptance, merge, and publish v0.1.3

**Files:**
- Modify: `docs/qa/2026-08-31-stealth-reader-v1.3-checklist.md` only to record acceptance evidence if desired.
- Modify: `.github/workflows/bootstrap-readbook.yml` only if the workflow does not yet target `v0.1.3` on `main`.

**Interfaces:**
- Consumes: PR preview ZIP and Task 9 acceptance checklist.
- Produces: `main` at the accepted implementation and GitHub Release `v0.1.3` with `ReadBook-macOS.zip`.

- [ ] **Step 1: Download the PR preview artifact and test on the target Mac**

Use the `ReadBook-stealth-preview` artifact from the latest green PR workflow. Extract `ReadBook-macOS.zip`, launch the app, and execute every item in `docs/qa/2026-08-31-stealth-reader-v1.3-checklist.md`.

Expected: every acceptance item passes. If any item fails, return to the relevant task, add a regression test, fix it, rerun CI, and repeat this step. Do not publish while a checklist item is known to fail.

- [ ] **Step 2: Ensure the main-only release step targets v0.1.3**

The workflow release step must use:

```yaml
      - name: Publish v0.1.3
        if: github.ref == 'refs/heads/main'
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          if gh release view v0.1.3 >/dev/null 2>&1; then
            gh release upload v0.1.3 dist/ReadBook-macOS.zip --clobber
          else
            gh release create v0.1.3 \
              dist/ReadBook-macOS.zip \
              --target "$GITHUB_SHA" \
              --title "ReadBook v0.1.3" \
              --notes "新增老板模式与纯净阅读体验：正文 hover/滚动不再唤出控制栏；顶部/底部热区按需显示带背景的控制层；支持无边框与纯透明阅读；支持 Option 临时交互、鼠标穿透、隐蔽模式自动隐藏/恢复，以及全局 ⌃⌥R 紧急隐藏；新增 ReadBook 自有 App 图标。"
          fi
```

- [ ] **Step 3: Merge only the accepted feature branch into main**

Before merge:

```bash
git status --short
git log --oneline --decorate -5
```

Expected: clean feature worktree and latest green/accepted commit at HEAD.

Merge according to repository policy (fast-forward if the branch is strictly ahead and `main` has not diverged; otherwise merge through the reviewed PR).

- [ ] **Step 4: Verify main CI and release**

Wait for the `main` macOS CI run and verify every step is successful:

- Test
- Build
- Package local app bundle
- Verify packaged app signature
- Verify app branding
- Create app archive
- Publish v0.1.3

Then verify the GitHub Release has `ReadBook-macOS.zip` and its target commit equals the accepted `main` commit.

- [ ] **Step 5: Record final release evidence**

Capture:

```bash
shasum -a 256 dist/ReadBook-macOS.zip
```

Report the release URL, `main` commit SHA, CI run ID, test count, and archive SHA-256 to the user.

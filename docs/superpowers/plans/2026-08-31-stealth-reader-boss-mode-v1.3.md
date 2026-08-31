# ReadBook Stealth Reader / Boss Mode v1.3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship ReadBook v0.1.3 with pure-reading chrome, reliable borderless dragging, Boss Mode, transparent pointer pass-through, global emergency hide/show, automatic concealed-mode restoration, and a real ReadBook application/menu-bar identity.

**Architecture:** Preserve the existing TXT/library/reader engines. Add a single `ReaderWindowStateController` as the authority for visibility and interaction behavior, a separate `ReaderChromeController` for top/bottom control intent, and narrow AppKit services for window mutations and global input. Durable Boss/appearance choices live in `ReaderPreferences`; transient hide reason, Option interaction, Lock Interactive, and chrome timing never enter persisted book state.

**Tech Stack:** Swift 6, SwiftUI, AppKit, TextKit, Observation, Carbon `RegisterEventHotKey`, XCTest, SwiftPM, GitHub Actions macOS 26, `iconutil`, `codesign`.

**Spec:** `docs/superpowers/specs/2026-08-31-stealth-reader-boss-mode-design.md`

## Global Constraints

- macOS 26+ only.
- Preserve TXT import/storage semantics, canonical UTF-16 reading position, pagination, and virtualized continuous rendering.
- Body hover, wheel/trackpad scrolling, and normal page navigation never reveal toolbar/footer.
- Top hot zone = 20 pt / 250 ms dwell. Bottom hot zone = 16 pt / 250 ms dwell. Return-to-body dismiss = 200 ms.
- Concealed pointer-exit hide = 300 ms. Option-release pass-through restore = 300 ms unless Lock Interactive is on.
- Emergency shortcut is fixed to `⌃⌥R` in v1.3; no shortcut editor.
- Frameless background opacity default = 18%, range = 0%...60%. Transparent background = 0% and no window shadow.
- Lock Interactive is session-only and resets off on launch.
- No polling loop for pointer restoration. Use local/global event monitors; if global pointer monitoring is unavailable, restore through shortcut/menu only.
- Explicit shortcut/menu hide is lock-hidden: pointer re-entry and unrelated preference updates must not reveal the window.
- Revalidate the stored reader frame against current `NSScreen.visibleFrame` values so a disconnected display cannot leave the restore target permanently off-screen.
- No network/account/cloud/Supabase, screen-capture hiding, process masquerading, fake work UI, or foreground-app detection.
- Preserve the existing final-bundle ad-hoc `codesign`; Developer ID/notarization remains out of scope.

---

## File Map

- `Sources/ReadBookCore/Models/ReaderPreferences.swift` — durable Boss/profile/appearance fields with legacy decode defaults.
- `Sources/ReadBook/Window/DelayScheduler.swift` — cancellable deterministic delays.
- `Sources/ReadBook/Window/ReaderWindowStateController.swift` — one visibility/interaction state authority.
- `Sources/ReadBook/Window/WindowRegistry.swift` — only layer that mutates `NSWindow` visibility/mouse pass-through/appearance.
- `Sources/ReadBook/Window/WindowCoordinator.swift` — borderless/resizable baseline; no background-drag dependence.
- `Sources/ReadBook/Input/GlobalHotKeyService.swift` — Carbon `⌃⌥R` registration/unregistration.
- `Sources/ReadBook/Input/ReaderGlobalInputService.swift` — local/global mouse+modifier monitors, no polling.
- `Sources/ReadBook/Reader/ReaderChromeController.swift` — hot-zone dwell/dismiss state.
- `Sources/ReadBook/Window/ReaderDragRegion.swift` — `performDrag(with:)` bridge.
- `Sources/ReadBook/Reader/ReaderToolbar.swift` / `ReaderRootView.swift` — scrim-backed control chrome and pure reading surface.
- `Sources/ReadBook/App/AppRuntime.swift` — lifecycle owner for registry/state/chrome/input/hotkey.
- `Sources/ReadBook/App/AppModel.swift`, `ReadBookApp.swift`, `AppDelegate.swift`, `SettingsView.swift` — UI/settings/menu wiring.
- `DesignAssets/ReadBookMark.svg`, `ReadBookMark-Monochrome.svg` — original brand masters.
- `DesignAssets/Tabler/{ghost-2,eye-off,border-none}.svg`, `LICENSE` — curated MIT SVG references.
- `Scripts/render-branding.swift`, `Scripts/build-app.sh` — `.icns` + menu template generation/package integration.
- `docs/qa/2026-08-31-stealth-reader-v1.3-checklist.md` — real-device release gate.

---

### Task 1: Add backward-compatible durable stealth preferences

**Files:**
- Modify: `Sources/ReadBookCore/Models/ReaderPreferences.swift`
- Modify: `Tests/ReadBookCoreTests/PreferencesStoreTests.swift`

**Interfaces:**
- Produces `BossModeProfile`, `ReaderWindowAppearance` and `ReaderPreferences.{bossModeEnabled,bossModeProfile,windowAppearance,framelessBackgroundOpacity}`.

- [ ] **Step 1: Add failing tests**

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
    var value = ReaderPreferences.defaults
    value.bossModeEnabled = true
    value.bossModeProfile = .concealed
    value.windowAppearance = .frameless
    value.framelessBackgroundOpacity = 0.42
    let decoded = try JSONDecoder().decode(ReaderPreferences.self, from: JSONEncoder().encode(value))
    XCTAssertEqual(decoded, value)
}
```

- [ ] **Step 2: Verify RED**

```bash
swift test --filter PreferencesStoreTests
```

Expected: compile failure for missing enums/properties.

- [ ] **Step 3: Implement model + legacy decoding**

Add:

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

Add fields/initializer defaults:

```swift
public var bossModeEnabled: Bool
public var bossModeProfile: BossModeProfile
public var windowAppearance: ReaderWindowAppearance
public var framelessBackgroundOpacity: Double

// initializer defaults
bossModeEnabled: Bool = false,
bossModeProfile: BossModeProfile = .floatingReading,
windowAppearance: ReaderWindowAppearance = .card,
framelessBackgroundOpacity: Double = 0.18
```

Because old v0.1.2 JSON lacks these keys, implement custom `init(from:)` using existing-field `decode(...)` and:

```swift
bossModeEnabled = try c.decodeIfPresent(Bool.self, forKey: .bossModeEnabled) ?? false
bossModeProfile = try c.decodeIfPresent(BossModeProfile.self, forKey: .bossModeProfile) ?? .floatingReading
windowAppearance = try c.decodeIfPresent(ReaderWindowAppearance.self, forKey: .windowAppearance) ?? .card
framelessBackgroundOpacity = min(max(
    try c.decodeIfPresent(Double.self, forKey: .framelessBackgroundOpacity) ?? 0.18,
    0
), 0.60)
```

Implement `encode(to:)` with all old + new keys. Update `.defaults` with the four exact defaults above.

- [ ] **Step 4: Verify GREEN**

```bash
swift test --filter PreferencesStoreTests
swift test --filter ReadBookCoreTests
```

- [ ] **Step 5: Commit**

```bash
git add Sources/ReadBookCore/Models/ReaderPreferences.swift Tests/ReadBookCoreTests/PreferencesStoreTests.swift
git commit -m "feat: add stealth reader preferences"
```

---

### Task 2: Implement one window state authority with cancellable delays

**Files:**
- Create: `Sources/ReadBook/Window/DelayScheduler.swift`
- Create: `Sources/ReadBook/Window/ReaderWindowStateController.swift`
- Create: `Tests/ReadBookAppTests/ReaderWindowStateControllerTests.swift`

**Interfaces:**

```swift
@MainActor protocol ReaderWindowDriving: AnyObject {
    var readerFrameInScreen: CGRect? { get }
    func showReader(activate: Bool)
    func hideReader()
    func setPointerPassThrough(_ enabled: Bool)
}

enum ReaderHideReason: Equatable { case automaticPointerExit, explicitShortcut, explicitMenuAction }
enum ReaderWindowState: Equatable { case normal, floatingText, interactiveStealth, hidden(ReaderHideReason) }
```

- [ ] **Step 1: Add fake-driver/manual-delay tests**

Tests must cover all of these exact transitions:

```swift
func testConcealedExitFiresAutomaticHideAt300ms()
func testReentryBefore300msCancelsAutomaticHide()
func testAutomaticallyHiddenReaderRestoresWhenPointerReentersStoredFrame()
func testShortcutHiddenReaderDoesNotRestoreFromPointerReentry()
func testSecondShortcutRestoresLastVisibleStealthState()
func testOptionEntersInteractiveAndReleaseReturnsAfter300ms()
func testLockInteractiveOverridesOptionRelease()
func testPreferenceRefreshDoesNotRevealExplicitlyHiddenReader()
```

For the last regression:

```swift
sut.toggleEmergencyShortcut()
XCTAssertEqual(sut.state, .hidden(.explicitShortcut))
var changed = prefs
changed.fontSize = 22
sut.applyPreferences(changed)
XCTAssertEqual(sut.state, .hidden(.explicitShortcut))
XCTAssertFalse(driver.visible)
```

- [ ] **Step 2: Verify RED**

```bash
swift test --filter ReaderWindowStateControllerTests
```

- [ ] **Step 3: Add deterministic delay abstraction**

```swift
@MainActor
protocol DelayCancellation: AnyObject { func cancel() }

@MainActor
protocol DelayScheduling: AnyObject {
    func schedule(afterMilliseconds: Int, action: @escaping @MainActor () -> Void) -> any DelayCancellation
}

@MainActor
final class TaskDelayCancellation: DelayCancellation {
    private var task: Task<Void, Never>?
    init(_ task: Task<Void, Never>) { self.task = task }
    func cancel() { task?.cancel(); task = nil }
}

@MainActor
final class TaskDelayScheduler: DelayScheduling {
    func schedule(afterMilliseconds ms: Int, action: @escaping @MainActor () -> Void) -> any DelayCancellation {
        let task = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(ms))
            guard !Task.isCancelled else { return }
            action()
        }
        return TaskDelayCancellation(task)
    }
}
```

- [ ] **Step 4: Implement `ReaderWindowStateController`**

Required stored state:

```swift
@MainActor @Observable
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
```

`applyPreferences(_:)` must preserve explicit hidden state:

```swift
func applyPreferences(_ value: ReaderPreferences) {
    let preserveExplicitHide: Bool = {
        switch state {
        case .hidden(.explicitShortcut), .hidden(.explicitMenuAction): true
        default: false
        }
    }()
    preferences = value
    if preserveExplicitHide { return }
    cancelHide()
    if !value.bossModeEnabled {
        transition(to: .normal, show: true)
    } else {
        transition(to: lockInteractive ? .interactiveStealth : .floatingText, show: true)
    }
}
```

`pointerMoved(to:)` must use `driver.readerFrameInScreen`, restore only `.hidden(.automaticPointerExit)` on re-entry, schedule 300 ms hide only for visible Concealed profile outside the frame, and cancel it on re-entry.

`optionChanged(isDown:)` must enter `.interactiveStealth` only when Boss Mode is on, reader is visible, and pointer is inside; Option release schedules 300 ms return to `.floatingText` unless locked.

`toggleEmergencyShortcut()` must save visible state, hide immediately as `.hidden(.explicitShortcut)`, and on the second press restore `.normal` when Boss Mode is off or `.floatingText`/`.interactiveStealth` according to lock/Option state when Boss Mode is on.

`setLockInteractive(_:)`, `showExplicitly()`, `hideExplicitly()`, `scheduleAutomaticHide()`, `cancelHide()`, and `transition(to:show:)` must be the only transition helpers. `transition` calls `driver.showReader(activate:)`/`hideReader()` and sets pass-through only when final state is `.floatingText && !lockInteractive`.

- [ ] **Step 5: Verify GREEN**

```bash
swift test --filter ReaderWindowStateControllerTests
```

- [ ] **Step 6: Commit**

```bash
git add Sources/ReadBook/Window/DelayScheduler.swift Sources/ReadBook/Window/ReaderWindowStateController.swift Tests/ReadBookAppTests/ReaderWindowStateControllerTests.swift
git commit -m "feat: add reader window state machine"
```

---

### Task 3: Make WindowRegistry the only NSWindow mutation layer and revalidate off-screen frames

**Files:**
- Modify: `Sources/ReadBook/Window/WindowRegistry.swift`
- Modify: `Sources/ReadBook/Window/WindowCoordinator.swift`
- Modify: `Tests/ReadBookAppTests/WindowCoordinatorTests.swift`

- [ ] **Step 1: Add failing tests**

```swift
func testConfigureRemainsBorderlessResizableAndDisablesBackgroundDrag() {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 260),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    WindowCoordinator().configure(window)
    XCTAssertFalse(window.styleMask.contains(.titled))
    XCTAssertTrue(window.styleMask.contains(.resizable))
    XCTAssertFalse(window.isMovableByWindowBackground)
}

func testRevalidatedFrameClampsDisconnectedDisplayFrameIntoVisibleScreen() {
    let old = CGRect(x: 2500, y: 100, width: 360, height: 260)
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let fixed = WindowRegistry.revalidatedFrame(old, visibleFrames: [screen])
    XCTAssertTrue(screen.contains(CGPoint(x: fixed.midX, y: fixed.midY)))
    XCTAssertEqual(fixed.size, old.size)
}
```

Also test `.transparent`/`.frameless` disable shadow and `setPointerPassThrough` maps to `window.ignoresMouseEvents`.

- [ ] **Step 2: Verify RED**

```bash
swift test --filter WindowCoordinatorTests
```

- [ ] **Step 3: Remove background-drag dependency**

In `WindowCoordinator.configure` keep borderless/resizable and set:

```swift
window.isMovableByWindowBackground = false
window.backgroundColor = .clear
window.isOpaque = false
window.hasShadow = true
```

- [ ] **Step 4: Conform WindowRegistry to `ReaderWindowDriving`**

Required methods:

```swift
var readerFrameInScreen: CGRect? {
    guard let window = readerWindow else { return nil }
    let visibleFrames = NSScreen.screens.map(\.visibleFrame)
    let fixed = Self.revalidatedFrame(window.frame, visibleFrames: visibleFrames)
    if fixed != window.frame { window.setFrame(fixed, display: false) }
    return fixed
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

func setPointerPassThrough(_ enabled: Bool) { readerWindow?.ignoresMouseEvents = enabled }

func applyAppearance(_ appearance: ReaderWindowAppearance) {
    readerWindow?.backgroundColor = .clear
    readerWindow?.isOpaque = false
    readerWindow?.hasShadow = appearance == .card
}
```

Pure frame repair helper:

```swift
static func revalidatedFrame(_ frame: CGRect, visibleFrames: [CGRect]) -> CGRect {
    guard let target = visibleFrames.first else { return frame }
    if visibleFrames.contains(where: { $0.intersects(frame) }) { return frame }
    let width = min(frame.width, target.width)
    let height = min(frame.height, target.height)
    let x = min(max(frame.minX, target.minX), target.maxX - width)
    let y = min(max(frame.minY, target.minY), target.maxY - height)
    return CGRect(x: x, y: y, width: width, height: height)
}
```

Do not keep a direct `toggleReader()` call path in UI code after Task 7; state controller owns toggle semantics.

- [ ] **Step 5: Verify GREEN and commit**

```bash
swift test --filter WindowCoordinatorTests
swift test --filter ReaderWindowStateControllerTests
git add Sources/ReadBook/Window Tests/ReadBookAppTests/WindowCoordinatorTests.swift
git commit -m "refactor: centralize stealth window mutations"
```

---

### Task 4: Add global `⌃⌥R`, global pointer restoration, and Option routing

**Files:**
- Create: `Sources/ReadBook/Input/GlobalHotKeyService.swift`
- Create: `Sources/ReadBook/Input/ReaderGlobalInputService.swift`
- Create: `Tests/ReadBookAppTests/ReaderGlobalInputServiceTests.swift`

**Interfaces:**

```swift
@MainActor protocol ReaderGlobalInputHandling: AnyObject {
    func pointerMoved(to point: CGPoint)
    func optionChanged(isDown: Bool)
}
```

`ReaderWindowStateController` conforms.

- [ ] **Step 1: Add semantic routing test**

```swift
func testConsumeRoutesPointerAndOptionOnlyWhenModifierChanges() {
    let sink = Sink()
    let sut = ReaderGlobalInputService(sink: sink)
    sut.consume(mouseLocation: CGPoint(x: 20, y: 30), modifierFlags: [.option])
    sut.consume(mouseLocation: CGPoint(x: 21, y: 31), modifierFlags: [.option])
    sut.consume(mouseLocation: CGPoint(x: 22, y: 32), modifierFlags: [])
    XCTAssertEqual(sink.points.count, 3)
    XCTAssertEqual(sink.optionStates, [true, false])
}
```

- [ ] **Step 2: Verify RED**

```bash
swift test --filter ReaderGlobalInputServiceTests
```

- [ ] **Step 3: Implement global/local monitor service without polling**

Required shape:

```swift
@MainActor
final class ReaderGlobalInputService {
    private weak var sink: (any ReaderGlobalInputHandling)?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastOptionDown: Bool?
    var onOptionChanged: (@MainActor (Bool) -> Void)?

    init(sink: any ReaderGlobalInputHandling) { self.sink = sink }

    @discardableResult
    func start() -> Bool {
        guard globalMonitor == nil, localMonitor == nil else { return globalMonitor != nil }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .flagsChanged]) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.consume(mouseLocation: NSEvent.mouseLocation, modifierFlags: event.modifierFlags)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .flagsChanged]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.consume(mouseLocation: NSEvent.mouseLocation, modifierFlags: event.modifierFlags)
            }
            return event
        }
        return globalMonitor != nil
    }

    func consume(mouseLocation: CGPoint, modifierFlags: NSEvent.ModifierFlags) {
        sink?.pointerMoved(to: mouseLocation)
        let option = modifierFlags.contains(.option)
        if option != lastOptionDown {
            lastOptionDown = option
            sink?.optionChanged(isDown: option)
            onOptionChanged?(option)
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil; localMonitor = nil; lastOptionDown = nil
    }
}
```

The return value means **global pointer restoration is available**; local monitoring alone is not enough for a hidden window.

- [ ] **Step 4: Implement Carbon global hotkey**

`GlobalHotKeyService` must use `RegisterEventHotKey(UInt32(kVK_ANSI_R), UInt32(controlKey | optionKey), ...)`, install one `kEventHotKeyPressed` handler on `GetApplicationEventTarget()`, invoke `onToggle` only for its own `EventHotKeyID.id == 1`, and deterministically call both `UnregisterEventHotKey` and `RemoveEventHandler` in `stop()`.

Use `Unmanaged.passUnretained(self).toOpaque()` as the event-handler user data; recover it in the Carbon callback and call `MainActor.assumeIsolated { service.onToggle() }`. Do not replace this with a keyboard polling loop or an Accessibility-dependent CGEvent tap.

- [ ] **Step 5: Verify build + tests**

```bash
swift test --filter ReaderGlobalInputServiceTests
swift build
```

- [ ] **Step 6: Commit**

```bash
git add Sources/ReadBook/Input Tests/ReadBookAppTests/ReaderGlobalInputServiceTests.swift
git commit -m "feat: add global stealth input services"
```

---

### Task 5: Replace generic hover with explicit control intent

**Files:**
- Create: `Sources/ReadBook/Reader/ReaderChromeController.swift`
- Create: `Tests/ReadBookAppTests/ReaderChromeControllerTests.swift`

- [ ] **Step 1: Add failing tests**

Required cases:

```swift
func testBodyHoverAndScrollNeverRevealChrome()
func testTopNeeds250msDwellAndRevealsOnlyTop()
func testBottomNeeds250msDwellAndRevealsOnlyBottom()
func testReturningToBodyDismissesAfter200ms()
func testOptionInteractionRevealsBothImmediately()
func testActiveControlInteractionPreventsDismiss()
```

Use the same manual `DelayScheduling` pattern as Task 2.

- [ ] **Step 2: Verify RED**

```bash
swift test --filter ReaderChromeControllerTests
```

- [ ] **Step 3: Implement controller**

Required observable state:

```swift
@MainActor @Observable
final class ReaderChromeController {
    private(set) var topVisible = false
    private(set) var bottomVisible = false
```

`processPointer(localY:contentHeight:)` rules:

```swift
let inTop = contentHeight - localY <= 20
let inBottom = localY <= 16
```

- Top: cancel dismiss/bottom dwell, schedule top reveal at 250 ms.
- Bottom: cancel dismiss/top dwell, schedule bottom reveal at 250 ms.
- Body: cancel both dwell timers and schedule both hidden at 200 ms.
- `processScroll()` is intentionally a no-op: it does not reveal and does not reset timers.
- `setOptionInteraction(true)` cancels delays and immediately sets both visible; false schedules 200 ms dismissal when no active control interaction exists.
- `beginControlInteraction()` increments a depth counter and cancels dismissal; `endControlInteraction()` decrements and schedules dismissal when depth reaches zero.

`attach(to:)` installs a local `.mouseMoved`/`.scrollWheel` monitor filtered to that exact window; it calls `processPointer(event.locationInWindow.y, window.contentView.bounds.height)` or `processScroll()`. `detach()` removes the monitor and cancels all timers.

- [ ] **Step 4: Verify GREEN and commit**

```bash
swift test --filter ReaderChromeControllerTests
git add Sources/ReadBook/Reader/ReaderChromeController.swift Tests/ReadBookAppTests/ReaderChromeControllerTests.swift
git commit -m "feat: add intent-based reader chrome"
```

---

### Task 6: Add explicit drag handle and scrim-backed Card / Frameless / Transparent UI

**Files:**
- Create: `Sources/ReadBook/Window/ReaderDragRegion.swift`
- Modify: `Sources/ReadBook/Reader/ReaderToolbar.swift`
- Modify: `Sources/ReadBook/Reader/ReaderRootView.swift`

- [ ] **Step 1: Create explicit drag bridge**

```swift
struct ReaderDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override var acceptsFirstResponder: Bool { false }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}
```

- [ ] **Step 2: Make only title/empty toolbar space draggable**

In `ReaderToolbar`, keep all buttons outside the drag overlay. Wrap the title + spacer:

```swift
HStack(spacing: 8) {
    Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
    Spacer(minLength: 8)
}
.contentShape(Rectangle())
.overlay { ReaderDragRegion() }
```

- [ ] **Step 3: Remove body-hover chrome from ReaderRootView**

Change signature:

```swift
struct ReaderRootView: View {
    @Bindable var model: AppModel
    @Bindable var windowState: ReaderWindowStateController
    @Bindable var chrome: ReaderChromeController
```

Delete `hovering`, `.onHover`, and every `hovering ?` toolbar/footer condition.

- [ ] **Step 4: Render appearance**

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

Background is theme color at `surfaceOpacity`; only Card uses the 26 pt clip. No hidden opaque layer in Transparent mode.

- [ ] **Step 5: Add separate scrim-backed overlays**

Top chrome renders only when `chrome.topVisible`; bottom status only when `chrome.bottomVisible`. Both use theme background at 0.94 opacity in Transparent and 0.90 otherwise. The body may remain laid out beneath, but visible body glyphs must be fully separated by the scrim while controls are shown.

Bottom status retains current chapter/progress text but moves inside its own padded background. Top toolbar keeps library/mode/pin/settings actions.

When opening the library popover call `chrome.beginControlInteraction()`; when `showLibrary` changes to false call `chrome.endControlInteraction()`.

- [ ] **Step 6: Build full app**

```bash
swift test
swift build
```

Expected: no reader-body hover path controls chrome; all tests green.

- [ ] **Step 7: Commit**

```bash
git add Sources/ReadBook/Window/ReaderDragRegion.swift Sources/ReadBook/Reader/ReaderToolbar.swift Sources/ReadBook/Reader/ReaderRootView.swift
git commit -m "feat: add pure reading chrome and drag handle"
```

---

### Task 7: Wire runtime lifecycle, menu bar, Boss Mode, and Settings

**Files:**
- Create: `Sources/ReadBook/App/AppRuntime.swift`
- Modify: `Sources/ReadBook/App/AppDelegate.swift`
- Modify: `Sources/ReadBook/App/AppModel.swift`
- Modify: `Sources/ReadBook/App/ReadBookApp.swift`
- Modify: `Sources/ReadBook/Settings/SettingsView.swift`

- [ ] **Step 1: Add AppModel setters**

```swift
func setBossModeEnabled(_ enabled: Bool) {
    updatePreferences {
        $0.bossModeEnabled = enabled
        if enabled { $0.windowAppearance = .transparent }
    }
}
func setBossModeProfile(_ profile: BossModeProfile) { updatePreferences { $0.bossModeProfile = profile } }
func setWindowAppearance(_ appearance: ReaderWindowAppearance) { updatePreferences { $0.windowAppearance = appearance } }
func setFramelessBackgroundOpacity(_ value: Double) {
    updatePreferences { $0.framelessBackgroundOpacity = min(max(value, 0), 0.60) }
}
```

- [ ] **Step 2: Create `AppRuntime`**

Required ownership:

```swift
@MainActor @Observable
final class AppRuntime {
    let windowRegistry: WindowRegistry
    let windowState: ReaderWindowStateController
    let chrome: ReaderChromeController
    let globalInput: ReaderGlobalInputService
    let hotKey: GlobalHotKeyService
    private(set) var hotKeyAvailable = true
    private(set) var globalPointerAvailable = true
    private var started = false
```

Initializer creates registry -> state -> chrome -> input -> hotkey. Exact wiring after initialization:

```swift
globalInput.onOptionChanged = { [weak chrome] isDown in
    chrome?.setOptionInteraction(isDown)
}
hotKey.onToggle = { [weak state] in
    state?.toggleEmergencyShortcut()
}
```

`register(window:preferences:)` registers/configures the window, attaches chrome, applies preferences, and once per launch executes:

```swift
globalPointerAvailable = globalInput.start()
hotKeyAvailable = hotKey.start()
```

`apply(_:)` calls `windowRegistry.setAlwaysOnTop`, `setAppPresence`, `applyAppearance`, then `windowState.applyPreferences`.

`shutdown()` detaches chrome, stops global input/hotkey, and clears the started flag.

Add:

```swift
var menuBarImage: NSImage {
    if let url = Bundle.main.url(forResource: "ReadBookMenuBarTemplate", withExtension: "png"),
       let image = NSImage(contentsOf: url) {
        image.isTemplate = true
        return image
    }
    return NSImage(systemSymbolName: "book.closed", accessibilityDescription: "ReadBook")!
}
```

- [ ] **Step 3: Add deterministic cleanup to AppDelegate**

Add `cleanupHandler`. In `applicationShouldTerminate`, execute cleanup exactly once before final `reply(toApplicationShouldTerminate:)`; if there is no async flush handler, run cleanup then return `.terminateNow`.

- [ ] **Step 4: Inject runtime into ReadBookApp**

Use `@State private var runtime = AppRuntime()`. Pass `runtime.windowState` and `runtime.chrome` to `ReaderRootView`. `WindowAccessor` calls `runtime.register(window:preferences:)`. Preference-change notification calls `runtime.apply(model.preferences)`. Existing flush setup also assigns `appDelegate.cleanupHandler = { runtime.shutdown() }`.

Replace the current `MenuBarExtra("ReadBook", systemImage: "book.closed")` with the label form:

```swift
MenuBarExtra {
    // existing + new menu content
} label: {
    Image(nsImage: runtime.menuBarImage)
}
```

- [ ] **Step 5: Route menu show/hide only through the state controller**

Use `runtime.windowState.showExplicitly()` and `hideExplicitly()`; do not call a raw `WindowRegistry.toggleReader()`.

Add menu controls:

- Boss Mode toggle -> `model.setBossModeEnabled` + `runtime.apply`.
- Profile picker -> `.floatingReading` / `.concealed`.
- Appearance picker -> `.card` / `.frameless` / `.transparent`.
- Session-only `Toggle("锁定为可交互", ...)` -> `runtime.windowState.setLockInteractive`.
- Display fixed `⌃⌥R` and warning if `hotKeyAvailable == false`.
- In Concealed profile, if `globalPointerAvailable == false`, show `自动回显不可用；请用 ⌃⌥R 或菜单栏恢复`.

- [ ] **Step 6: Extend SettingsView**

Add `Section("老板模式")` with durable Boss toggle/profile and fixed shortcut status. Add Appearance picker under Window. Show a slider only for Frameless:

```swift
Slider(value: Binding(
    get: { model.preferences.framelessBackgroundOpacity },
    set: { model.setFramelessBackgroundOpacity($0) }
), in: 0...0.60, step: 0.01)
```

Label the numeric value as opacity (`背景不透明度`) to avoid reversing the meaning.

Settings receives `runtime: AppRuntime` instead of a bare `WindowRegistry`, so immediate window application and availability warnings share one lifecycle object.

- [ ] **Step 7: Verify and commit**

```bash
swift test
swift build
git add Sources/ReadBook/App Sources/ReadBook/Settings/SettingsView.swift Sources/ReadBook/Input/ReaderGlobalInputService.swift
git commit -m "feat: wire boss mode runtime and settings"
```

---

### Task 8: Add original app/menu-bar branding and curated SVG references

**Files:**
- Create: `DesignAssets/ReadBookMark.svg`
- Create: `DesignAssets/ReadBookMark-Monochrome.svg`
- Create: `DesignAssets/Tabler/ghost-2.svg`
- Create: `DesignAssets/Tabler/eye-off.svg`
- Create: `DesignAssets/Tabler/border-none.svg`
- Create: `DesignAssets/Tabler/LICENSE`
- Create: `Scripts/render-branding.swift`
- Modify: `Scripts/build-app.sh`

- [ ] **Step 1: Add original app vector master**

Create `DesignAssets/ReadBookMark.svg`:

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <rect x="64" y="64" width="896" height="896" rx="220" fill="#20242A"/>
  <path d="M258 250h300c112 0 208 78 208 202v322c-61-48-132-72-214-72H258z" fill="#F6F1E7"/>
  <path d="M552 250c118 0 214 78 214 202v322c-61-48-132-72-214-72z" fill="#DDE5EB"/>
  <path d="M386 365h177c83 0 137 45 137 116 0 55-33 94-86 109l101 121h-99l-84-106h-62v106h-84zm84 70v101h82c39 0 62-19 62-51 0-32-23-50-62-50z" fill="#20242A"/>
  <path d="M552 250v452" stroke="#BCC7CF" stroke-width="18" stroke-linecap="round"/>
</svg>
```

Create simplified template master `ReadBookMark-Monochrome.svg`:

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
  <path d="M4.5 4.5h7a4 4 0 0 1 4 4v11a7.7 7.7 0 0 0-4-1.1h-7z"/>
  <path d="M11.5 4.5a4 4 0 0 1 4 4v11a7.7 7.7 0 0 1 4-1.1V7.8a3.3 3.3 0 0 0-3.3-3.3z"/>
  <path d="M7.3 8.2h3.1c1.5 0 2.4.8 2.4 2 0 1-.6 1.7-1.6 2l1.8 2.2h-1.8l-1.5-1.9H9v1.9H7.3z"/>
</svg>
```

- [ ] **Step 2: Add curated upstream SVG sources + MIT notice**

Copy exact files from `tabler/tabler-icons`:

- `icons/outline/ghost-2.svg`
- `icons/outline/eye-off.svg`
- `icons/outline/border-none.svg`
- upstream `LICENSE` (MIT, copyright 2020-2026 Paweł Kuna)

Store under `DesignAssets/Tabler/`. These are curated references; shipping controls continue to prefer SF Symbols unless a non-native metaphor is materially better. The ReadBook identity remains original and does not reuse a Tabler logo.

- [ ] **Step 3: Create deterministic renderer**

`Scripts/render-branding.swift` takes four arguments: app SVG, monochrome SVG, output iconset directory, output menu PNG. It loads both with `NSImage(contentsOf:)`, renders macOS iconset PNGs at 16, 32, 128, 256, 512 points at 1x/2x using `NSBitmapImageRep`, and renders the monochrome mark into a 36×36 transparent PNG. Fail with non-zero exit if either SVG cannot load or PNG generation fails.

Required iconset filenames:

```text
icon_16x16.png
icon_16x16@2x.png
icon_32x32.png
icon_32x32@2x.png
icon_128x128.png
icon_128x128@2x.png
icon_256x256.png
icon_256x256@2x.png
icon_512x512.png
icon_512x512@2x.png
```

- [ ] **Step 4: Update `build-app.sh` before final codesign**

Set:

```xml
<key>CFBundleShortVersionString</key><string>0.1.3</string>
<key>CFBundleVersion</key><string>4</string>
<key>CFBundleIconFile</key><string>ReadBook</string>
```

Run:

```bash
ICONSET="$ROOT/.build/ReadBook.iconset"
MENU_ICON="$APP/Contents/Resources/ReadBookMenuBarTemplate.png"
rm -rf "$ICONSET"
swift "$ROOT/Scripts/render-branding.swift" \
  "$ROOT/DesignAssets/ReadBookMark.svg" \
  "$ROOT/DesignAssets/ReadBookMark-Monochrome.svg" \
  "$ICONSET" \
  "$MENU_ICON"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/ReadBook.icns"
rm -rf "$ICONSET"
```

Then run the existing final `codesign --force --sign - --timestamp=none "$APP"` so both branding resources are sealed.

- [ ] **Step 5: Verify packaging**

```bash
Scripts/build-app.sh
test "$(plutil -extract CFBundleIconFile raw dist/ReadBook.app/Contents/Info.plist)" = "ReadBook"
test -s dist/ReadBook.app/Contents/Resources/ReadBook.icns
test -s dist/ReadBook.app/Contents/Resources/ReadBookMenuBarTemplate.png
codesign --verify --deep --strict --verbose=4 dist/ReadBook.app
```

- [ ] **Step 6: Commit**

```bash
git add DesignAssets Scripts/render-branding.swift Scripts/build-app.sh
git commit -m "feat: add ReadBook application branding"
```

---

### Task 9: Add preview CI + exact real-device acceptance gate

**Files:**
- Modify: `.github/workflows/bootstrap-readbook.yml`
- Create: `docs/qa/2026-08-31-stealth-reader-v1.3-checklist.md`

- [ ] **Step 1: Archive on PR and main after signature validation**

```yaml
      - name: Create app archive
        run: ditto -c -k --sequesterRsrc --keepParent dist/ReadBook.app dist/ReadBook-macOS.zip
```

- [ ] **Step 2: Verify branding in CI**

```yaml
      - name: Verify app branding
        run: |
          test "$(plutil -extract CFBundleIconFile raw dist/ReadBook.app/Contents/Info.plist)" = "ReadBook"
          test -s dist/ReadBook.app/Contents/Resources/ReadBook.icns
          test -s dist/ReadBook.app/Contents/Resources/ReadBookMenuBarTemplate.png
```

- [ ] **Step 3: Upload PR preview**

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

- [ ] **Step 4: Prepare main-only v0.1.3 release step now**

Replace the old v0.1.2 publish step with `Publish v0.1.3`, still guarded by:

```yaml
if: github.ref == 'refs/heads/main'
```

Use `gh release create/upload v0.1.3` and title `ReadBook v0.1.3`. Because the feature remains on a PR until manual acceptance, this cannot publish early; merging the accepted PR is the release trigger.

- [ ] **Step 5: Create acceptance checklist**

`docs/qa/2026-08-31-stealth-reader-v1.3-checklist.md` must contain all of these unchecked cases:

```markdown
- [ ] Multi-million-character TXT remains smooth/bounded in continuous mode.
- [ ] Hover/scroll body for 2 minutes: no toolbar/footer appears.
- [ ] Top 20 pt dwell ~250 ms: only top chrome appears with scrim; no visible body overlap.
- [ ] Bottom 16 pt dwell ~250 ms: only chapter/progress chrome appears with scrim.
- [ ] Return to body: chrome dismisses ~200 ms later.
- [ ] Drag title/empty toolbar space moves window; buttons click without dragging.
- [ ] Frameless has no shadow and defaults to 18% background opacity.
- [ ] Transparent has 0% background and no shadow.
- [ ] Floating Reading passes click/wheel through to VS Code/Chrome behind it.
- [ ] Hold Option inside reader frame: interaction + full controls appear immediately.
- [ ] Release Option: pass-through returns ~300 ms later.
- [ ] Lock Interactive prevents pass-through from returning.
- [ ] Concealed pointer exit hides ~300 ms later.
- [ ] Re-entry before 300 ms cancels hide.
- [ ] After automatic hide, re-enter old frame: reader returns.
- [ ] Move reader to a secondary display, disconnect/reconfigure that display, then restore: frame is clamped to a visible screen.
- [ ] Press ⌃⌥R from another foreground app: immediate hide.
- [ ] Pointer re-entry while shortcut-hidden does not reveal it.
- [ ] Unrelated preference change while shortcut-hidden does not reveal it.
- [ ] Second ⌃⌥R restores it.
- [ ] Quit/relaunch: Lock Interactive resets off; durable Boss/appearance settings persist.
- [ ] Finder/Dock uses custom ReadBook icon; menu bar uses custom monochrome template mark.
```

- [ ] **Step 6: Run fresh branch verification**

```bash
swift test
swift build
Scripts/build-app.sh
codesign --verify --deep --strict --verbose=4 dist/ReadBook.app
```

- [ ] **Step 7: Commit and open preview PR**

```bash
git add .github/workflows/bootstrap-readbook.yml docs/qa/2026-08-31-stealth-reader-v1.3-checklist.md
git commit -m "ci: add stealth reader preview and release gates"
gh pr create --base main --head feature/stealth-reader-v1.3 --title "ReadBook v0.1.3 stealth reader" --body "Adds pure-reading chrome, Boss Mode, transparent pass-through, emergency hide/show, reliable dragging, and ReadBook branding. Release remains gated on the real-mac acceptance checklist."
```

Expected: PR macOS CI is green and exposes `ReadBook-stealth-preview`.

---

### Task 10: Spec review, real-Mac acceptance, merge, and release

**Files:**
- Review all files changed in Tasks 1-9.
- `docs/qa/2026-08-31-stealth-reader-v1.3-checklist.md` records acceptance evidence if desired.

- [ ] **Step 1: Fresh verification before any completion claim**

```bash
swift test
swift build
Scripts/build-app.sh
codesign -dv --verbose=4 dist/ReadBook.app
codesign --verify --deep --strict --verbose=4 dist/ReadBook.app
swift test --filter ContinuousTextViewTests
swift test --filter VirtualTextWindowTests
swift test --filter PaginationEngineTests
```

Expected: zero failures; virtualized reader remains bounded; bundle signature valid.

- [ ] **Step 2: Check state ownership and hover regression mechanically**

```bash
grep -R "orderOut\|ignoresMouseEvents\|makeKeyAndOrderFront" -n Sources/ReadBook
grep -R "onHover\|hovering" -n Sources/ReadBook/Reader
```

Expected: actual window visibility/pass-through mutations live in `WindowRegistry`; decisions live in `ReaderWindowStateController`; reader-body hover no longer drives toolbar/footer.

- [ ] **Step 3: Check asset provenance**

Verify `DesignAssets/Tabler/LICENSE` contains the upstream MIT notice and the three SVGs match upstream files. Verify application identity comes from original `ReadBookMark*.svg` masters.

- [ ] **Step 4: Test the latest PR artifact on the target Mac**

Download `ReadBook-stealth-preview`, execute every item in `docs/qa/2026-08-31-stealth-reader-v1.3-checklist.md`, and do not merge while any item is known to fail. A failure returns to the responsible task with a regression test, fix, new CI run, and new preview artifact.

- [ ] **Step 5: Merge only after acceptance**

Before merge confirm the feature branch is based on current `main` and CI is green. Fast-forward if `main` has not diverged; otherwise merge the reviewed PR normally. The `main` push then runs the already-prepared `Publish v0.1.3` step.

- [ ] **Step 6: Verify release evidence**

Verify main CI steps Test / Build / Package / strict codesign / branding / archive / Publish v0.1.3 all succeed. Verify release target commit equals accepted `main` and `ReadBook-macOS.zip` exists.

Report to user: `main` SHA, CI run ID, final test count, Release URL, and SHA-256 of `ReadBook-macOS.zip`.

---

## Plan Self-Review Result

- **Spec coverage:** every approved behavior is mapped to Tasks 1-10, including explicit-hide locking, multi-display frame repair, global monitor fallback, pure body hover, scrims, dragging, pass-through, Option interaction, Lock Interactive, custom App icon, monochrome menu mark, and release gating.
- **Placeholder scan:** no implementation step relies on an undefined “later” handler; external SVG copies name exact upstream repository paths and preserve the exact MIT license.
- **Type consistency:** `ReaderWindowStateController` is the `ReaderGlobalInputHandling` sink and consumes `ReaderWindowDriving`; `WindowRegistry` provides that driver; both state and chrome use the same `DelayScheduling`; `AppRuntime` is the only lifecycle owner passed to App/Settings.
- **Release safety:** v0.1.3 publish code is prepared on the feature branch but remains `main`-only, so the PR preview can be manually accepted before merge triggers the release.

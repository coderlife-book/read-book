# Native Titlebar Toolbar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the stacked SwiftUI header + empty native titlebar with one unified native macOS titlebar that contains ReadBook controls, stays auto-hidden until top hover, and preserves native window dragging/resizing.

**Architecture:** Keep the reader window as a native `.titled + .resizable` `NSWindow` with `.fullSizeContentView` disabled. Install a single `NSToolbar` in unified style, use narrow AppKit/SwiftUI host views for individual toolbar items, and keep blank titlebar space owned by AppKit for dragging. A small runtime titlebar state bridge mirrors only title/mode/pin/visibility and actions from `ReaderRootView`; a transparent non-hit-testing titlebar tracking view forwards pointer enter/exit into the existing `ReaderChromeController`.

**Tech Stack:** Swift 6, SwiftUI, AppKit (`NSWindow`, `NSToolbar`, `NSTrackingArea`, `NSHostingView`), Observation, XCTest, GitHub Actions macOS runner.

**Spec:** `docs/superpowers/specs/2026-09-01-native-titlebar-toolbar-design.md`

## Global Constraints

- Keep `.titled`, `.resizable`, and `.closable` native window behavior.
- Keep `.fullSizeContentView` disabled; reader content must not enter titlebar hit-testing space.
- Keep traffic-light buttons hidden and native title hidden.
- Set `window.titlebarSeparatorStyle = .none`.
- Do not reintroduce `ReaderDragRegion`, `ReaderResizeView`, local/global event monitors, or process-wide input hooks.
- Reuse `ReaderChromeController` timing: 90 ms reveal dwell and 200 ms dismiss delay.
- Remove the in-content `ReaderToolbar` row from `ReaderRootView`.
- Continuous scrolling production code must remain untouched unless a regression test proves this titlebar work broke it.
- Next RC packaging is marketing version `0.1.9`, build `11`; do not overwrite build 10 artifacts.
- Do not merge PR #12 to `main` until the build 11 artifact passes manual Mac smoke testing for single-header appearance, hover reveal, drag, resize, button clicks, and continuous scroll.

---

### Task 1: Lock the single-titlebar window contract

**Files:**
- Modify: `Tests/ReadBookAppTests/WindowCoordinatorTests.swift`
- Modify: `Sources/ReadBook/Window/WindowCoordinator.swift`

**Interfaces:**
- Consumes: existing `WindowCoordinator.configure(_ window: NSWindow)`.
- Produces: configured window with `titlebarSeparatorStyle == .none` and native titlebar/resize behavior unchanged.

- [ ] **Step 1: Write the failing separator test**

Extend `testConfigureKeepsNativeTitleAndResizeBehavior()` with:

```swift
XCTAssertEqual(window.titlebarSeparatorStyle, .none)
XCTAssertNil(window.toolbar)
```

The `XCTAssertNil(window.toolbar)` assertion is the pre-toolbar baseline for this task; Task 4 intentionally changes it after its own RED test.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
swift test --filter WindowCoordinatorTests/testConfigureKeepsNativeTitleAndResizeBehavior
```

Expected: FAIL because the current coordinator leaves the default titlebar separator style.

- [ ] **Step 3: Apply the minimal window fix**

In `WindowCoordinator.configure(_:)`, add:

```swift
window.titlebarSeparatorStyle = .none
```

Do not enable `.fullSizeContentView` and do not add any content overlay.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run:

```bash
swift test --filter WindowCoordinatorTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Tests/ReadBookAppTests/WindowCoordinatorTests.swift Sources/ReadBook/Window/WindowCoordinator.swift
git commit -m "fix: remove native titlebar separator"
```

---

### Task 2: Add a narrow observable titlebar state bridge

**Files:**
- Create: `Sources/ReadBook/Window/ReaderTitlebarState.swift`
- Create: `Tests/ReadBookAppTests/ReaderTitlebarStateTests.swift`
- Modify: `Sources/ReadBook/App/AppRuntime.swift`

**Interfaces:**
- Consumes: `ReadingMode`, `ReaderChromeController` visibility via synchronization from `ReaderRootView`.
- Produces:
  - `@MainActor @Observable final class ReaderTitlebarState`
  - properties `title: String`, `readingMode: ReadingMode`, `alwaysOnTop: Bool`, `isVisible: Bool`, `isLibraryPresented: Bool`
  - action closures `onModeChange: ((ReadingMode) -> Void)?`, `onPin: (() -> Void)?`
  - methods `toggleLibrary()`, `toggleReadingMode()`, `togglePin()`.
  - `AppRuntime.titlebar: ReaderTitlebarState`.

- [ ] **Step 1: Write failing state tests**

Create `ReaderTitlebarStateTests.swift`:

```swift
#if os(macOS)
import ReadBookCore
import XCTest
@testable import ReadBook

final class ReaderTitlebarStateTests: XCTestCase {
    @MainActor
    func testToggleReadingModeUsesBoundAction() {
        let state = ReaderTitlebarState()
        state.readingMode = .paginated
        var requested: ReadingMode?
        state.onModeChange = { requested = $0 }

        state.toggleReadingMode()

        XCTAssertEqual(requested, .continuous)
    }

    @MainActor
    func testToolbarVisibilityDoesNotMutateReadingState() {
        let state = ReaderTitlebarState()
        state.title = "Book"
        state.readingMode = .continuous
        state.alwaysOnTop = true

        state.isVisible = true
        state.isVisible = false

        XCTAssertEqual(state.title, "Book")
        XCTAssertEqual(state.readingMode, .continuous)
        XCTAssertTrue(state.alwaysOnTop)
    }

    @MainActor
    func testToggleLibraryOwnsPresentationBoolean() {
        let state = ReaderTitlebarState()
        XCTAssertFalse(state.isLibraryPresented)
        state.toggleLibrary()
        XCTAssertTrue(state.isLibraryPresented)
        state.toggleLibrary()
        XCTAssertFalse(state.isLibraryPresented)
    }
}
#endif
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
swift test --filter ReaderTitlebarStateTests
```

Expected: build/test FAIL because `ReaderTitlebarState` does not exist.

- [ ] **Step 3: Implement the state bridge**

Create `ReaderTitlebarState.swift`:

```swift
import Observation
import ReadBookCore

@MainActor
@Observable
final class ReaderTitlebarState {
    var title = "ReadBook"
    var readingMode: ReadingMode = .paginated
    var alwaysOnTop = false
    var isVisible = false
    var isLibraryPresented = false

    @ObservationIgnored var onModeChange: ((ReadingMode) -> Void)?
    @ObservationIgnored var onPin: (() -> Void)?

    func toggleLibrary() {
        isLibraryPresented.toggle()
    }

    func toggleReadingMode() {
        onModeChange?(readingMode == .paginated ? .continuous : .paginated)
    }

    func togglePin() {
        onPin?()
    }
}
```

Add to `AppRuntime`:

```swift
let titlebar: ReaderTitlebarState
```

and initialize it before window registration:

```swift
self.titlebar = ReaderTitlebarState()
```

- [ ] **Step 4: Run state and runtime tests**

Run:

```bash
swift test --filter ReaderTitlebarStateTests
swift test --filter AppRuntimeInputSafetyTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ReadBook/Window/ReaderTitlebarState.swift Sources/ReadBook/App/AppRuntime.swift Tests/ReadBookAppTests/ReaderTitlebarStateTests.swift
git commit -m "feat: add native titlebar state bridge"
```

---

### Task 3: Replace the in-content toolbar with titlebar state synchronization

**Files:**
- Modify: `Sources/ReadBook/Reader/ReaderRootView.swift`
- Modify: `Tests/ReadBookAppTests/V015InteractionRegressionTests.swift`

**Interfaces:**
- Consumes: `AppRuntime.titlebar`, `ReaderChromeController.topVisible`, `AppModel` title/mode/preferences.
- Produces: no `ReaderToolbar` in reader body; root view synchronizes current model state/actions into `runtime.titlebar`; library popover binds to `runtime.titlebar.isLibraryPresented`.

- [ ] **Step 1: Strengthen the source regression test**

Update the existing toolbar source test to assert both conditions:

```swift
func testReaderRootDoesNotRenderASecondTopToolbar() throws {
    let source = try sourceFile("Sources/ReadBook/Reader/ReaderRootView.swift")
    XCTAssertFalse(source.contains("ReaderToolbar("))
    XCTAssertFalse(source.contains("Color.clear\n                        .frame(height: 20)"))
}
```

Keep the existing assertion that `ReaderToolbar.swift` itself no longer embeds custom drag code.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
swift test --filter V015InteractionRegressionTests/testReaderRootDoesNotRenderASecondTopToolbar
```

Expected: FAIL because `ReaderRootView` still renders `ReaderToolbar` and owns the top 20-point hover strip.

- [ ] **Step 3: Remove the body toolbar and top hover strip**

In `ReaderRootView.body`:

1. Remove the `if topVisible { ReaderToolbar(...) }` block entirely.
2. Keep bottom chrome unchanged.
3. Remove only the top `Color.clear.frame(height: 20)` reveal zone; keep the bottom reveal zone.
4. Replace `@State private var showLibrary = false` with a binding to runtime state in the popover:

```swift
.popover(
    isPresented: Binding(
        get: { runtime.titlebar.isLibraryPresented },
        set: { runtime.titlebar.isLibraryPresented = $0 }
    ),
    arrowEdge: .top
) {
    LibraryPopoverView(model: model)
}
```

5. Update the existing popover `onChange` to observe `runtime.titlebar.isLibraryPresented`.

- [ ] **Step 4: Synchronize titlebar data and actions**

Add a focused helper inside `ReaderRootView`:

```swift
@MainActor
private func syncTitlebarState() {
    runtime.titlebar.title = model.currentBook?.title ?? "ReadBook"
    runtime.titlebar.readingMode = model.readingMode
    runtime.titlebar.alwaysOnTop = model.preferences.alwaysOnTop
    runtime.titlebar.isVisible = topVisible
    runtime.titlebar.onModeChange = { [model] mode in
        model.setMode(mode)
    }
    runtime.titlebar.onPin = { [model, runtime] in
        model.updatePreferences { $0.alwaysOnTop.toggle() }
        runtime.applyPreferences(model.preferences)
        NotificationCenter.default.post(
            name: .readBookWindowPreferencesChanged,
            object: nil
        )
    }
}
```

Call it on initial task and on changes to:

```swift
model.currentBook?.title
model.readingMode
model.preferences.alwaysOnTop
runtime.chrome.topVisible
runtime.windowState.state
```

Do not synchronize text, pagination, position, or chapter data into the titlebar bridge.

- [ ] **Step 5: Run focused and existing chrome tests**

Run:

```bash
swift test --filter V015InteractionRegressionTests
swift test --filter ReaderChromeControllerTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/ReadBook/Reader/ReaderRootView.swift Tests/ReadBookAppTests/V015InteractionRegressionTests.swift
git commit -m "refactor: remove duplicate reader header"
```

---

### Task 4: Install one unified native `NSToolbar`

**Files:**
- Create: `Sources/ReadBook/Window/ReaderNativeToolbarController.swift`
- Create: `Sources/ReadBook/Window/ReaderTitlebarItemViews.swift`
- Create: `Tests/ReadBookAppTests/ReaderNativeToolbarTests.swift`
- Modify: `Sources/ReadBook/Window/WindowRegistry.swift`
- Modify: `Sources/ReadBook/App/AppRuntime.swift`
- Modify: `Tests/ReadBookAppTests/WindowCoordinatorTests.swift`

**Interfaces:**
- Consumes: `ReaderTitlebarState`.
- Produces:
  - `@MainActor final class ReaderNativeToolbarController: NSObject, NSToolbarDelegate`
  - `install(on window: NSWindow, state: ReaderTitlebarState)`
  - exactly one toolbar with identifier `ReadBook.ReaderToolbar`
  - item identifiers `library`, `title`, `flexibleSpace`, `mode`, `pin`, `settings`
  - custom hosted items that fade via `state.isVisible` and only consume hits when visible.

- [ ] **Step 1: Write failing toolbar installation tests**

Create `ReaderNativeToolbarTests.swift`:

```swift
#if os(macOS)
import AppKit
import XCTest
@testable import ReadBook

final class ReaderNativeToolbarTests: XCTestCase {
    @MainActor
    func testInstallCreatesOneUnifiedNonCustomizableToolbar() {
        let window = makeWindow()
        let state = ReaderTitlebarState()
        let controller = ReaderNativeToolbarController()

        controller.install(on: window, state: state)

        XCTAssertEqual(window.toolbar?.identifier.rawValue, "ReadBook.ReaderToolbar")
        XCTAssertFalse(window.toolbar?.allowsUserCustomization ?? true)
        XCTAssertFalse(window.toolbar?.autosavesConfiguration ?? true)
        XCTAssertEqual(window.toolbarStyle, .unifiedCompact)
    }

    @MainActor
    func testHiddenButtonHostPassesHitTestingThroughToNativeTitlebar() {
        let state = ReaderTitlebarState()
        state.isVisible = false
        let host = ReaderTitlebarButtonHostView(state: state, rootView: AnyView(EmptyView()))
        host.frame = NSRect(x: 0, y: 0, width: 30, height: 30)

        XCTAssertNil(host.hitTest(NSPoint(x: 15, y: 15)))
    }

    @MainActor
    private func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 260),
            styleMask: [.titled, .resizable, .closable],
            backing: .buffered,
            defer: false
        )
    }
}
#endif
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
swift test --filter ReaderNativeToolbarTests
```

Expected: build/test FAIL because native toolbar controller/host types do not exist.

- [ ] **Step 3: Implement compact hosted item views**

Create `ReaderTitlebarItemViews.swift` with:

```swift
import AppKit
import SwiftUI

@MainActor
final class ReaderTitlebarButtonHostView: NSHostingView<AnyView> {
    private let state: ReaderTitlebarState

    init(state: ReaderTitlebarState, rootView: AnyView) {
        self.state = state
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init(rootView: AnyView) {
        fatalError("Use init(state:rootView:)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard state.isVisible else { return nil }
        return super.hitTest(point)
    }
}
```

Add SwiftUI item views that reuse the existing 30x30 circular hover treatment and read `ReaderTitlebarState` with `@Bindable`. Use `SettingsLink` for the settings item. The title item must have `.allowsHitTesting(false)` so title text behaves like draggable titlebar background.

- [ ] **Step 4: Implement `ReaderNativeToolbarController`**

Create an `NSToolbar` with:

```swift
let toolbar = NSToolbar(identifier: "ReadBook.ReaderToolbar")
toolbar.delegate = self
toolbar.allowsUserCustomization = false
toolbar.autosavesConfiguration = false
toolbar.displayMode = .iconOnly
window.toolbarStyle = .unifiedCompact
window.toolbar = toolbar
```

Return the default identifiers in this order:

```swift
[
    .readBookLibrary,
    .readBookTitle,
    .flexibleSpace,
    .readBookMode,
    .readBookPin,
    .readBookSettings,
]
```

Each custom item owns only its intrinsic view width. Do not create a full-width hosting view; unused titlebar space must remain native and draggable.

- [ ] **Step 5: Wire toolbar ownership into `WindowRegistry`**

Add:

```swift
private let toolbarController = ReaderNativeToolbarController()
```

Change registration to accept state:

```swift
func register(_ window: NSWindow, titlebarState: ReaderTitlebarState) {
    guard readerWindow !== window else { return }
    readerWindow = window
    coordinator.configure(window)
    toolbarController.install(on: window, state: titlebarState)
}
```

Update `AppRuntime.register(window:)` to call:

```swift
windowRegistry.register(window, titlebarState: titlebar)
```

- [ ] **Step 6: Update window test contract**

Remove the temporary `XCTAssertNil(window.toolbar)` assertion from Task 1 and add a registry-level assertion after registration:

```swift
XCTAssertEqual(window.toolbar?.identifier.rawValue, "ReadBook.ReaderToolbar")
XCTAssertEqual(window.toolbarStyle, .unifiedCompact)
```

- [ ] **Step 7: Run focused toolbar/window tests**

Run:

```bash
swift test --filter ReaderNativeToolbarTests
swift test --filter WindowCoordinatorTests
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Sources/ReadBook/Window/ReaderNativeToolbarController.swift Sources/ReadBook/Window/ReaderTitlebarItemViews.swift Sources/ReadBook/Window/WindowRegistry.swift Sources/ReadBook/App/AppRuntime.swift Tests/ReadBookAppTests/ReaderNativeToolbarTests.swift Tests/ReadBookAppTests/WindowCoordinatorTests.swift
git commit -m "feat: move reader controls into native titlebar"
```

---

### Task 5: Track native titlebar hover without stealing drag events

**Files:**
- Create: `Sources/ReadBook/Window/ReaderTitlebarTrackingView.swift`
- Modify: `Sources/ReadBook/Window/ReaderNativeToolbarController.swift`
- Create: `Tests/ReadBookAppTests/ReaderTitlebarTrackingTests.swift`
- Modify: `Sources/ReadBook/App/AppRuntime.swift`
- Modify: `Sources/ReadBook/Window/WindowRegistry.swift`

**Interfaces:**
- Consumes: `ReaderChromeController.topZoneChanged(inside:)` and `setControlInteractionHeld(_:)`.
- Produces: transparent tracking view attached to native titlebar container that reports enter/exit while `hitTest(_:)` always returns `nil`.

- [ ] **Step 1: Write failing tracking tests**

Create `ReaderTitlebarTrackingTests.swift`:

```swift
#if os(macOS)
import AppKit
import XCTest
@testable import ReadBook

final class ReaderTitlebarTrackingTests: XCTestCase {
    @MainActor
    func testTrackingViewNeverConsumesTitlebarHits() {
        let view = ReaderTitlebarTrackingView(
            onEnter: {},
            onExit: {}
        )
        view.frame = NSRect(x: 0, y: 0, width: 300, height: 28)
        XCTAssertNil(view.hitTest(NSPoint(x: 100, y: 10)))
    }

    @MainActor
    func testTrackingViewForwardsEnterAndExit() {
        var events: [Bool] = []
        let view = ReaderTitlebarTrackingView(
            onEnter: { events.append(true) },
            onExit: { events.append(false) }
        )

        view.mouseEntered(with: NSEvent())
        view.mouseExited(with: NSEvent())

        XCTAssertEqual(events, [true, false])
    }
}
#endif
```

If zero-argument `NSEvent()` is unavailable on the CI SDK, construct minimal `.mouseEntered` / `.mouseExited` events with `NSEvent.mouseEvent(...)` in the test; do not weaken the production contract.

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
swift test --filter ReaderTitlebarTrackingTests
```

Expected: FAIL because tracking view does not exist.

- [ ] **Step 3: Implement non-hit-testing tracking view**

Create `ReaderTitlebarTrackingView.swift`:

```swift
import AppKit

@MainActor
final class ReaderTitlebarTrackingView: NSView {
    private let onEnter: () -> Void
    private let onExit: () -> Void

    init(onEnter: @escaping () -> Void, onExit: @escaping () -> Void) {
        self.onEnter = onEnter
        self.onExit = onExit
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func mouseEntered(with event: NSEvent) { onEnter() }
    override func mouseExited(with event: NSEvent) { onExit() }
}
```

- [ ] **Step 4: Install the tracker into the native titlebar container**

Extend `ReaderNativeToolbarController.install` to accept `ReaderChromeController` and install exactly one tracking view into:

```swift
window.standardWindowButton(.closeButton)?.superview
```

The standard buttons remain hidden but their superview is the AppKit titlebar container. Set the tracker frame to that container’s bounds and autoresizing mask to `[.width, .height]`. Keep it positioned behind native toolbar item views and keep `hitTest` returning `nil`.

Forward:

```swift
onEnter: { chrome.topZoneChanged(inside: true) }
onExit: { chrome.topZoneChanged(inside: false) }
```

Update registration plumbing so `AppRuntime.register(window:)` provides both `titlebar` and `chrome` to `WindowRegistry.register`.

- [ ] **Step 5: Hold visibility while hovering actual controls**

In the visible SwiftUI button item roots, add:

```swift
.onHover { chrome.setControlInteractionHeld($0) }
```

Pass a small `onControlHover: (Bool) -> Void` closure into item-view construction rather than making item views depend directly on `AppRuntime`.

- [ ] **Step 6: Run tracking and chrome tests**

Run:

```bash
swift test --filter ReaderTitlebarTrackingTests
swift test --filter ReaderChromeControllerTests
swift test --filter ReaderNativeToolbarTests
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/ReadBook/Window/ReaderTitlebarTrackingView.swift Sources/ReadBook/Window/ReaderNativeToolbarController.swift Sources/ReadBook/Window/WindowRegistry.swift Sources/ReadBook/App/AppRuntime.swift Tests/ReadBookAppTests/ReaderTitlebarTrackingTests.swift
git commit -m "feat: reveal native toolbar from titlebar hover"
```

---

### Task 6: Validate appearance continuity and no duplicate header source path

**Files:**
- Modify: `Tests/ReadBookAppTests/ReaderWindowInteractionTests.swift`
- Modify: `Tests/ReadBookAppTests/V015InteractionRegressionTests.swift`
- Modify: `Sources/ReadBook/Window/WindowRegistry.swift` only if tests expose an appearance mismatch.

**Interfaces:**
- Consumes: current `WindowRegistry.applyAppearance(_:)` and unified native toolbar.
- Produces: card/frameless/transparent backgrounds continue to apply at window level; no separator; no reader-body header.

- [ ] **Step 1: Add appearance regression assertions**

Add tests that configure/register a window, apply `.soft` card appearance, and assert:

```swift
XCTAssertEqual(window.titlebarSeparatorStyle, .none)
XCTAssertTrue(window.backgroundColor.isEqual(ThemePalette.resolve(.soft).background))
XCTAssertNotNil(window.toolbar)
```

For transparent appearance assert:

```swift
XCTAssertTrue(window.backgroundColor.isEqual(.clear))
XCTAssertFalse(window.hasShadow)
```

Keep source-level assertion that `ReaderRootView.swift` has no `ReaderToolbar(`.

- [ ] **Step 2: Run focused appearance tests**

Run:

```bash
swift test --filter ReaderWindowInteractionTests
swift test --filter V015InteractionRegressionTests
```

Expected: PASS without production changes. If RED exposes that unified toolbar uses a mismatched system material, set toolbar/titlebar appearance from the existing window background only; do not add a second SwiftUI background strip.

- [ ] **Step 3: Commit only if tests changed**

```bash
git add Tests/ReadBookAppTests/ReaderWindowInteractionTests.swift Tests/ReadBookAppTests/V015InteractionRegressionTests.swift Sources/ReadBook/Window/WindowRegistry.swift
git commit -m "test: lock single-header appearance"
```

---

### Task 7: Run full regression suite and package v0.1.9 build 11 RC

**Files:**
- Modify: `Scripts/build-app.sh`
- Modify: `.github/workflows/bootstrap-readbook.yml`
- Modify: `docs/releases/v0.1.9-rc-smoke.md` if present; otherwise create/update the existing v0.1.9 RC smoke document used by PR #12.

**Interfaces:**
- Consumes: all titlebar/window/continuous-scroll changes above.
- Produces: installable `ReadBook v0.1.9 build 11` artifact with checksum, still on PR #12 and not published to `main`.

- [ ] **Step 1: Run full tests before version changes**

Run:

```bash
swift test
```

Expected: all tests PASS, including:

```text
ReaderNativeToolbarTests
ReaderTitlebarTrackingTests
ReaderChromeControllerTests
WindowCoordinatorTests
ReaderWindowInteractionTests
ContinuousTextViewTests
```

- [ ] **Step 2: Run debug build**

Run:

```bash
swift build
```

Expected: PASS.

- [ ] **Step 3: Bump only RC build number**

In `Scripts/build-app.sh` set defaults:

```bash
APP_VERSION="${READBOOK_VERSION:-0.1.9}"
APP_BUILD="${READBOOK_BUILD:-11}"
```

Keep marketing version `0.1.9`.

- [ ] **Step 4: Update release notes text**

Update the workflow release notes so v0.1.9 describes the final architecture, including:

```text
- reader controls now live in the single native macOS titlebar
- toolbar stays auto-hidden until top hover
- native titlebar dragging and native edge/corner resize remain enabled
- duplicate in-content header removed
- native continuous scrolling from the previous RC remains unchanged
```

Do not publish from the PR; the workflow publish job must remain gated to `push` on `main`.

- [ ] **Step 5: Commit RC metadata**

```bash
git add Scripts/build-app.sh .github/workflows/bootstrap-readbook.yml docs/releases
git commit -m "chore: prepare v0.1.9 build 11 rc"
```

- [ ] **Step 6: Verify exact-head GitHub Actions run**

Wait for the PR workflow triggered by the final commit and require all of these steps to succeed:

```text
Test
Build
Package local app bundle
Verify packaged app signature
Verify branding
Gatekeeper assessment
Create archive and checksum
Upload installable preview
```

Do not substitute an artifact from an earlier head SHA.

- [ ] **Step 7: Download and verify the exact artifact**

Download the workflow artifact named like:

```text
ReadBook-v0.1.9-<exact-head-sha>
```

Verify the inner `ReadBook-macOS.zip` against `ReadBook-macOS.zip.sha256` before handing it off.

- [ ] **Step 8: Manual Mac smoke gate**

Require the user to verify this exact build 11 package for:

```text
1. Only one header region is visible.
2. Toolbar controls are hidden while idle.
3. Hovering the native top area reveals the toolbar after ~90 ms.
4. Moving away hides it after ~200 ms.
5. Dragging unused titlebar/title text moves the window.
6. Clicking library/mode/pin/settings does not drag the window.
7. Edge/corner resize still works.
8. Continuous scroll still moves with wheel/trackpad and does not snap back.
9. Card/frameless/transparent appearance remains visually continuous.
```

Do not merge PR #12 until this manual gate is explicitly confirmed.

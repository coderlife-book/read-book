# Native Window and Continuous Scroll Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace ReadBook's custom drag/resize overlays and virtualized continuous-scroll path with native AppKit window movement/resizing and a conventional whole-document `NSScrollView`/`NSTextView`, while preserving the current clean card appearance.

**Architecture:** Keep the SwiftUI app shell and reader UI. Restore a real native `.titled + .resizable` `NSWindow`, visually hide its chrome, and leave its true titlebar area available to AppKit for dragging. Continuous mode becomes a whole-document native text scroll view; user scrolling owns the viewport and position updates flow outward without immediately driving the same scroll position back into the view.

**Tech Stack:** Swift 6, SwiftUI, AppKit (`NSWindow`, `NSScrollView`, `NSTextView`, TextKit), XCTest, Swift Package Manager, GitHub Actions macOS 26.

**Spec:** `docs/superpowers/specs/2026-08-31-native-window-scroll-redesign.md`

## Global Constraints

- Preserve the clean widget-like reader: no visible title text, no traffic-light buttons, no gray system titlebar, no visible scroll bar.
- Keep a real native titlebar drag surface. Do not use `.fullSizeContentView` in v0.1.9.
- Do not use `ReaderDragRegion`, `ReaderDragView`, `ReaderResizeView`, `performDrag(with:)`, custom edge resize tracking, or global/local `NSEvent` monitors for the new implementation.
- Continuous mode must use native vertical `NSScrollView` behavior.
- The native titlebar's visual fill must match the current reader appearance: theme background for card mode, theme background with configured opacity for frameless mode, clear for transparent mode.
- Keep themes, custom text color, font, line spacing, paragraph spacing, pagination, always-on-top, boss mode, library popover, settings, autosaved window frame, and persisted reading positions compatible.
- Whole-document continuous rendering is acceptable for this release; `VirtualTextWindowPlanner` must not participate in the production continuous-scroll path.
- Clamp invalid saved offsets to the current UTF-16 document length.
- CI success alone is not enough. The packaged PR artifact must pass the interaction smoke gate before merge/release.
- Target release is v0.1.9 unless that tag is occupied; if occupied, use the next unused patch version and increment the build number.

---

## File Structure

- `Sources/ReadBook/Window/WindowCoordinator.swift` — native window style/titlebar configuration only.
- `Sources/ReadBook/Window/WindowRegistry.swift` — applies reader appearance to the whole window, including the otherwise-transparent native titlebar area.
- `Sources/ReadBook/Reader/ReaderToolbar.swift` — toolbar controls/title display only; no window dragging.
- `Sources/ReadBook/Reader/ReaderRootView.swift` — reader composition and hover reveal zones only.
- `Sources/ReadBook/Reader/ContinuousTextView.swift` — whole-document AppKit scrolling and one-way position synchronization.
- `Tests/ReadBookAppTests/ReaderWindowInteractionTests.swift` — native window contract tests.
- `Tests/ReadBookAppTests/ContinuousTextViewTests.swift` — whole-document scroll and feedback-loop tests.
- `Tests/ReadBookAppTests/V015InteractionRegressionTests.swift` — source-level guard that retired custom drag code is not reintroduced.
- Delete `Sources/ReadBook/Window/ReaderDragRegion.swift`.
- Delete `Sources/ReadBook/Window/ReaderResizeView.swift`.
- Delete `Tests/ReadBookAppTests/ReaderDragRegionTests.swift`.
- `.github/workflows/bootstrap-readbook.yml` — release notes only.
- `Scripts/build-app.sh` — version/build bump only after implementation is GREEN.

---

### Task 1: Restore native window movement/resizing and preserve clean titlebar appearance

**Files:**
- Modify: `Tests/ReadBookAppTests/ReaderWindowInteractionTests.swift`
- Modify: `Sources/ReadBook/Window/WindowCoordinator.swift`
- Modify: `Sources/ReadBook/Window/WindowRegistry.swift`
- Delete after GREEN: `Sources/ReadBook/Window/ReaderResizeView.swift`

**Interfaces:**
- Consumes: `WindowCoordinator.configure(_:)` and `WindowRegistry.apply(_:)`.
- Produces: a `.titled + .resizable + .closable` reader window with invisible system chrome, no custom resize overlay, and a titlebar background that visually matches the selected reader appearance.

- [ ] **Step 1: Write failing native-window configuration tests**

Replace the existing custom resize tests with:

```swift
#if os(macOS)
import AppKit
import ReadBookCore
import XCTest
@testable import ReadBook

@MainActor
final class ReaderWindowInteractionTests: XCTestCase {
    func testWindowKeepsNativeTitleAndResizeContract() {
        let window = makeWindow()

        WindowCoordinator().configure(window)

        XCTAssertTrue(window.styleMask.contains(.titled))
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertTrue(window.styleMask.contains(.closable))
        XCTAssertFalse(window.styleMask.contains(.fullSizeContentView))
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertFalse(window.isMovableByWindowBackground)
    }

    func testWindowHidesTrafficLightButtons() {
        let window = makeWindow()
        WindowCoordinator().configure(window)

        for type in [
            NSWindow.ButtonType.closeButton,
            .miniaturizeButton,
            .zoomButton,
        ] {
            XCTAssertTrue(window.standardWindowButton(type)?.isHidden ?? true)
        }
    }

    func testConfigureDoesNotInstallContentOverlay() throws {
        let window = makeWindow()
        let contentView = try XCTUnwrap(window.contentView)
        let before = contentView.subviews.count

        WindowCoordinator().configure(window)

        XCTAssertEqual(contentView.subviews.count, before)
    }

    private func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 360, height: 260),
            styleMask: [.titled, .resizable, .closable],
            backing: .buffered,
            defer: false
        )
    }
}
#endif
```

- [ ] **Step 2: Run the focused test and verify RED**

```bash
swift test --filter ReaderWindowInteractionTests
```

Expected: FAIL because the current coordinator removes `.titled` and installs `ReaderResizeView`.

- [ ] **Step 3: Implement native window configuration**

Change `WindowCoordinator.configure(_:)` to this contract:

```swift
func configure(_ window: NSWindow) {
    window.delegate = self
    window.minSize = NSSize(width: 280, height: 180)

    window.styleMask.insert([.titled, .resizable, .closable])
    window.styleMask.remove(.fullSizeContentView)
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isMovableByWindowBackground = false
    window.isReleasedWhenClosed = false
    window.isOpaque = false
    window.setFrameAutosaveName("ReadBook.ReaderWindow")

    for type in [
        NSWindow.ButtonType.closeButton,
        .miniaturizeButton,
        .zoomButton,
    ] {
        window.standardWindowButton(type)?.isHidden = true
    }
}
```

Remove `installResizeHitZones(in:)` entirely. Do not add a replacement drag/resize view.

- [ ] **Step 4: Make the native titlebar background match the reader appearance**

Change `WindowRegistry.applyAppearance` to consume the whole preference set instead of only `ReaderWindowAppearance`:

```swift
func applyAppearance(_ preferences: ReaderPreferences) {
    guard let readerWindow else { return }

    let base = ThemePalette.resolve(preferences.theme).background
    readerWindow.isOpaque = false

    switch preferences.windowAppearance {
    case .card:
        readerWindow.backgroundColor = base
        readerWindow.hasShadow = true
    case .frameless:
        readerWindow.backgroundColor = base.withAlphaComponent(
            preferences.framelessBackgroundOpacity
        )
        readerWindow.hasShadow = false
    case .transparent:
        readerWindow.backgroundColor = .clear
        readerWindow.hasShadow = false
    }
}
```

Update `WindowRegistry.apply(_:)`:

```swift
func apply(_ preferences: ReaderPreferences) {
    setAlwaysOnTop(preferences.alwaysOnTop)
    setAppPresence(preferences.appPresenceMode)
    applyAppearance(preferences)
}
```

This is required because with a real non-full-size titlebar, `titlebarAppearsTransparent` reveals `NSWindow.backgroundColor`; leaving it always clear would create a visual gap above the SwiftUI reader surface.

- [ ] **Step 5: Run window tests and verify GREEN**

```bash
swift test --filter ReaderWindowInteractionTests
```

Expected: PASS.

- [ ] **Step 6: Delete the custom resize implementation and run the suite again**

Delete:

```text
Sources/ReadBook/Window/ReaderResizeView.swift
```

Run:

```bash
swift test --filter ReaderWindowInteractionTests
swift test
```

Expected: PASS and no production reference to `ReaderResizeView`.

- [ ] **Step 7: Commit Task 1**

```bash
git add Sources/ReadBook/Window/WindowCoordinator.swift \
        Sources/ReadBook/Window/WindowRegistry.swift \
        Sources/ReadBook/Window/ReaderResizeView.swift \
        Tests/ReadBookAppTests/ReaderWindowInteractionTests.swift
git commit -m "refactor: restore native reader window behavior"
```

---

### Task 2: Remove custom title dragging from the SwiftUI hierarchy

**Files:**
- Modify: `Sources/ReadBook/Reader/ReaderToolbar.swift`
- Modify only if needed: `Sources/ReadBook/Reader/ReaderRootView.swift`
- Modify: `Tests/ReadBookAppTests/V015InteractionRegressionTests.swift`
- Delete: `Sources/ReadBook/Window/ReaderDragRegion.swift`
- Delete: `Tests/ReadBookAppTests/ReaderDragRegionTests.swift`

**Interfaces:**
- Consumes: the native titlebar produced by Task 1.
- Produces: no custom drag view in the content hierarchy; window dragging is owned solely by AppKit's real titlebar region.

- [ ] **Step 1: Add a failing source regression test**

Add to `V015InteractionRegressionTests.swift`:

```swift
func testToolbarDoesNotEmbedCustomDragRegion() throws {
    let toolbar = try source("Sources/ReadBook/Reader/ReaderToolbar.swift")
    XCTAssertFalse(toolbar.contains("ReaderDragRegion("))
    XCTAssertFalse(toolbar.contains("performDrag(with:"))
}
```

If the file has no source helper, add:

```swift
private func source(_ relativePath: String) throws -> String {
    let fileURL = URL(fileURLWithPath: #filePath)
    let root = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(
        contentsOf: root.appendingPathComponent(relativePath),
        encoding: .utf8
    )
}
```

- [ ] **Step 2: Run the focused test and verify RED**

```bash
swift test --filter V015InteractionRegressionTests/testToolbarDoesNotEmbedCustomDragRegion
```

Expected: FAIL because `ReaderToolbar` currently embeds `ReaderDragRegion()`.

- [ ] **Step 3: Replace the title drag ZStack with display-only SwiftUI content**

Use:

```swift
HStack(spacing: 6) {
    Text(title)
        .font(.system(size: 12, weight: .medium))
        .lineLimit(1)
    Spacer(minLength: 4)
}
.frame(maxWidth: .infinity)
.frame(height: 30)
```

Do not add `.gesture`, `NSViewRepresentable`, `mouseDownCanMoveWindow`, `performDrag`, or cursor overrides.

- [ ] **Step 4: Keep hover controls inside the SwiftUI content area only**

Retain the current top hover zone only if it stays below the native titlebar:

```swift
Color.clear
    .frame(height: 20)
    .contentShape(Rectangle())
    .onHover { runtime.chrome.topZoneChanged(inside: $0) }
```

Do not move this into an `NSTitlebarAccessoryViewController` and do not create a full-window event monitor.

- [ ] **Step 5: Delete retired drag files**

Delete:

```text
Sources/ReadBook/Window/ReaderDragRegion.swift
Tests/ReadBookAppTests/ReaderDragRegionTests.swift
```

- [ ] **Step 6: Verify GREEN**

```bash
swift test --filter V015InteractionRegressionTests
swift test --filter ReaderWindowInteractionTests
```

Expected: PASS.

- [ ] **Step 7: Commit Task 2**

```bash
git add Sources/ReadBook/Reader/ReaderToolbar.swift \
        Sources/ReadBook/Reader/ReaderRootView.swift \
        Sources/ReadBook/Window/ReaderDragRegion.swift \
        Tests/ReadBookAppTests/ReaderDragRegionTests.swift \
        Tests/ReadBookAppTests/V015InteractionRegressionTests.swift
git commit -m "refactor: remove custom reader drag overlay"
```

---

### Task 3: Replace the virtual continuous reader with whole-document native scrolling

**Files:**
- Modify: `Tests/ReadBookAppTests/ContinuousTextViewTests.swift`
- Modify: `Sources/ReadBook/Reader/ContinuousTextView.swift`

**Interfaces:**
- Consumes: existing `ContinuousTextView(bookID:text:anchor:style:textColor:onPositionChanged:)` SwiftUI boundary.
- Produces: a native `NSScrollView` whose `NSTextView.string` equals the full book text and whose document view becomes taller than the viewport for long books.

- [ ] **Step 1: Replace the old bounded-window test with a failing whole-document test**

Use:

```swift
@MainActor
func testCoordinatorRendersWholeDocumentAndCreatesScrollableHeight() throws {
    let paragraph = String(repeating: "女巫种田正文", count: 40) + "\n"
    let text = String(repeating: paragraph, count: 400)
    let (scrollView, textView, coordinator) = makeReader()

    coordinator.update(
        bookID: UUID(),
        text: text,
        anchor: BookPosition(utf16Offset: 0),
        style: .default,
        textColor: .textColor
    )

    let container = try XCTUnwrap(textView.textContainer)
    textView.layoutManager?.ensureLayout(for: container)
    textView.sizeToFit()

    XCTAssertEqual(textView.string, text)
    XCTAssertGreaterThan(textView.frame.height, scrollView.contentSize.height)
    XCTAssertFalse(scrollView.hasVerticalScroller)
    XCTAssertFalse(scrollView.hasHorizontalScroller)
}

@MainActor
private func makeReader(
    onPositionChanged: @escaping (BookPosition) -> Void = { _ in }
) -> (NSScrollView, NSTextView, ContinuousTextView.Coordinator) {
    let scrollView = NSScrollView(
        frame: NSRect(x: 0, y: 0, width: 360, height: 260)
    )
    let textView = NSTextView(frame: scrollView.contentView.bounds)
    scrollView.documentView = textView

    let coordinator = ContinuousTextView.Coordinator(
        onPositionChanged: onPositionChanged
    )
    coordinator.attach(scrollView: scrollView, textView: textView)
    return (scrollView, textView, coordinator)
}
```

- [ ] **Step 2: Run the test and verify RED**

```bash
swift test --filter ContinuousTextViewTests/testCoordinatorRendersWholeDocumentAndCreatesScrollableHeight
```

Expected: FAIL because the current coordinator renders a bounded `VirtualTextWindow` rather than the entire source string.

- [ ] **Step 3: Remove virtual-window state from the production continuous path**

Delete these production dependencies from `ContinuousTextView.Coordinator`:

```swift
VirtualTextWindowPlanner
VirtualTextWindow
currentWindow
recenterScheduled
loadWindow(centeredAt:restoreGlobalOffset:)
scheduleRecenteringIfNeeded(at:)
```

Retain only:

```swift
private var sourceBookID: UUID?
private var sourceText = ""
private var currentStyle: ReaderTextStyle?
private var currentColor: NSColor?
private var lastReportedOffset: Int?
private var lastAppliedExternalAnchor: Int?
private var isApplyingProgrammaticChange = false
private var reportWorkItem: DispatchWorkItem?
```

Leave the planner/core tests in the repository if they are independently useful, but `ContinuousTextView.swift` must not instantiate or call them.

- [ ] **Step 4: Keep the AppKit text stack conventional and native**

`makeNSView` must create:

```swift
let scrollView = NSScrollView(frame: .zero)
scrollView.hasVerticalScroller = false
scrollView.hasHorizontalScroller = false
scrollView.drawsBackground = false
scrollView.contentView.postsBoundsChangedNotifications = true

let textView = NSTextView(frame: .zero)
textView.isEditable = false
textView.isSelectable = true
textView.drawsBackground = false
textView.isVerticallyResizable = true
textView.isHorizontallyResizable = false
textView.autoresizingMask = [.width]
textView.minSize = NSSize(width: 0, height: 0)
textView.maxSize = NSSize(
    width: CGFloat.greatestFiniteMagnitude,
    height: CGFloat.greatestFiniteMagnitude
)
textView.textContainer?.widthTracksTextView = true
textView.textContainer?.heightTracksTextView = false
textView.textContainer?.lineFragmentPadding = 0
textView.layoutManager?.allowsNonContiguousLayout = true
scrollView.documentView = textView
```

Do not override `scrollWheel(with:)` and do not install an event monitor.

- [ ] **Step 5: Render the full attributed source text**

Implement:

```swift
private func renderDocument(restoringGlobalOffset offset: Int) {
    guard let style = currentStyle,
          let color = currentColor,
          let textView else { return }

    let engine = PaginationEngine()
    let attributed = NSMutableAttributedString(
        attributedString: engine.attributedString(sourceText, style: style)
    )
    attributed.addAttribute(
        .foregroundColor,
        value: color,
        range: NSRange(location: 0, length: attributed.length)
    )

    isApplyingProgrammaticChange = true
    textView.textStorage?.setAttributedString(attributed)
    textView.textContainerInset = NSSize(
        width: style.horizontalPadding,
        height: style.verticalPadding
    )
    textView.layoutManager?.ensureLayout(for: textView.textContainer!)
    textView.sizeToFit()
    lastReportedOffset = nil
    scrollTo(globalOffset: offset)
    isApplyingProgrammaticChange = false
}
```

Clamp `offset` before this method is called.

- [ ] **Step 6: Run the focused test and verify GREEN**

```bash
swift test --filter ContinuousTextViewTests/testCoordinatorRendersWholeDocumentAndCreatesScrollableHeight
```

Expected: PASS.

- [ ] **Step 7: Commit Task 3**

```bash
git add Sources/ReadBook/Reader/ContinuousTextView.swift \
        Tests/ReadBookAppTests/ContinuousTextViewTests.swift
git commit -m "refactor: use whole-document native scrolling"
```

---

### Task 4: Prove scroll movement and eliminate position feedback snap-back

**Files:**
- Modify: `Tests/ReadBookAppTests/ContinuousTextViewTests.swift`
- Modify: `Sources/ReadBook/Reader/ContinuousTextView.swift`

**Interfaces:**
- Consumes: native whole-document scroll view from Task 3.
- Produces: debounced visible-position reporting and an external-anchor policy that never re-applies the exact position the coordinator just reported from user scrolling.

- [ ] **Step 1: Add a failing native viewport movement/report test**

```swift
@MainActor
func testNativeScrollAdvancesViewportAndReportsLaterPosition() throws {
    let paragraph = String(repeating: "滚动正文", count: 80) + "\n"
    let text = String(repeating: paragraph, count: 500)
    var reported: BookPosition?
    let (scrollView, textView, coordinator) = makeReader {
        reported = $0
    }

    coordinator.update(
        bookID: UUID(),
        text: text,
        anchor: .init(utf16Offset: 0),
        style: .default,
        textColor: .textColor
    )
    textView.layoutManager?.ensureLayout(for: try XCTUnwrap(textView.textContainer))
    textView.sizeToFit()

    let startY = scrollView.contentView.bounds.minY
    scrollView.contentView.scroll(to: NSPoint(x: 0, y: startY + 220))
    scrollView.reflectScrolledClipView(scrollView.contentView)
    NotificationCenter.default.post(
        name: NSView.boundsDidChangeNotification,
        object: scrollView.contentView
    )
    RunLoop.main.run(until: Date().addingTimeInterval(0.12))

    XCTAssertGreaterThan(scrollView.contentView.bounds.minY, startY)
    XCTAssertGreaterThan(reported?.utf16Offset ?? 0, 0)
}
```

- [ ] **Step 2: Add a failing snap-back test**

```swift
@MainActor
func testReportedPositionFedBackDoesNotSnapViewport() throws {
    let paragraph = String(repeating: "反馈回路正文", count: 80) + "\n"
    let text = String(repeating: paragraph, count: 500)
    let bookID = UUID()
    var reported = BookPosition(utf16Offset: 0)
    let (scrollView, textView, coordinator) = makeReader {
        reported = $0
    }

    coordinator.update(
        bookID: bookID,
        text: text,
        anchor: .init(utf16Offset: 0),
        style: .default,
        textColor: .textColor
    )
    textView.layoutManager?.ensureLayout(for: try XCTUnwrap(textView.textContainer))
    textView.sizeToFit()

    scrollView.contentView.scroll(to: NSPoint(x: 0, y: 220))
    scrollView.reflectScrolledClipView(scrollView.contentView)
    NotificationCenter.default.post(
        name: NSView.boundsDidChangeNotification,
        object: scrollView.contentView
    )
    RunLoop.main.run(until: Date().addingTimeInterval(0.12))

    let yAfterScroll = scrollView.contentView.bounds.minY
    XCTAssertGreaterThan(reported.utf16Offset, 0)

    coordinator.update(
        bookID: bookID,
        text: text,
        anchor: reported,
        style: .default,
        textColor: .textColor
    )

    XCTAssertEqual(
        scrollView.contentView.bounds.minY,
        yAfterScroll,
        accuracy: 1.0
    )
}
```

- [ ] **Step 3: Run both tests and verify RED where feedback ownership is incomplete**

```bash
swift test --filter ContinuousTextViewTests/testNativeScrollAdvancesViewportAndReportsLaterPosition
swift test --filter ContinuousTextViewTests/testReportedPositionFedBackDoesNotSnapViewport
```

Expected before implementation: at least one assertion fails.

- [ ] **Step 4: Debounce scroll-position reporting**

Use:

```swift
private func schedulePositionReport() {
    reportWorkItem?.cancel()
    let work = DispatchWorkItem { [weak self] in
        self?.reportTopVisiblePosition()
    }
    reportWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
}
```

The bounds-change observer calls `schedulePositionReport()`. `detach()` cancels `reportWorkItem` and unregisters the observer.

- [ ] **Step 5: Make the coordinator's own reported offset non-programmatic**

In `reportTopVisiblePosition()`:

```swift
let globalCharacter = min(
    max(localCharacter, 0),
    (sourceText as NSString).length
)

guard globalCharacter != lastReportedOffset else { return }
lastReportedOffset = globalCharacter
lastAppliedExternalAnchor = nil
onPositionChanged(BookPosition(utf16Offset: globalCharacter))
```

In `update(...)`:

```swift
let clampedAnchor = min(
    max(anchor.utf16Offset, 0),
    (text as NSString).length
)
let bookChanged = sourceBookID != bookID
let textChanged = sourceText != text
let styleChanged = currentStyle != style || currentColor != textColor

sourceBookID = bookID
sourceText = text
currentStyle = style
currentColor = textColor

if bookChanged || textChanged || styleChanged {
    renderDocument(restoringGlobalOffset: clampedAnchor)
    return
}

guard clampedAnchor != lastReportedOffset,
      clampedAnchor != lastAppliedExternalAnchor else { return }

isApplyingProgrammaticChange = true
scrollTo(globalOffset: clampedAnchor)
isApplyingProgrammaticChange = false
```

`scrollTo(globalOffset:)` must set `lastAppliedExternalAnchor` after changing the clip view.

- [ ] **Step 6: Add and verify an external saved-anchor test**

```swift
@MainActor
func testExternalSavedAnchorMovesViewport() throws {
    let paragraph = String(repeating: "恢复位置正文", count: 80) + "\n"
    let text = String(repeating: paragraph, count: 500)
    let target = (text as NSString).length / 2
    let bookID = UUID()
    let (scrollView, textView, coordinator) = makeReader()

    coordinator.update(
        bookID: bookID,
        text: text,
        anchor: .init(utf16Offset: 0),
        style: .default,
        textColor: .textColor
    )
    textView.layoutManager?.ensureLayout(for: try XCTUnwrap(textView.textContainer))
    textView.sizeToFit()

    let startY = scrollView.contentView.bounds.minY
    coordinator.update(
        bookID: bookID,
        text: text,
        anchor: .init(utf16Offset: target),
        style: .default,
        textColor: .textColor
    )

    XCTAssertGreaterThan(scrollView.contentView.bounds.minY, startY)
}
```

If this test fails because TextKit has not produced layout yet, allow exactly one deferred retry on the next main-loop turn. Do not add polling/timers.

- [ ] **Step 7: Run all continuous tests and verify GREEN**

```bash
swift test --filter ContinuousTextViewTests
```

Expected: PASS.

- [ ] **Step 8: Run the complete test suite**

```bash
swift test
```

Expected: PASS, including existing session/persistence tests. `AppModel.setMode(_:)` must continue to change only reading mode/preferences; it must not reset `session.position`.

- [ ] **Step 9: Commit Task 4**

```bash
git add Sources/ReadBook/Reader/ContinuousTextView.swift \
        Tests/ReadBookAppTests/ContinuousTextViewTests.swift
git commit -m "fix: keep native scroll viewport authoritative"
```

---

### Task 5: Release-candidate verification and packaging

**Files:**
- Modify: `Scripts/build-app.sh`
- Modify: `.github/workflows/bootstrap-readbook.yml`
- Create: `docs/superpowers/verification/2026-08-31-v0.1.9-interaction-smoke.md`

**Interfaces:**
- Consumes: Tasks 1-4.
- Produces: a versioned PR artifact for real packaged-app interaction verification. Main must remain unchanged until smoke passes.

- [ ] **Step 1: Run full pre-release verification**

```bash
swift test
swift build
Scripts/build-app.sh
codesign --verify --deep --strict --verbose=4 dist/ReadBook.app
```

Expected: all exit 0.

- [ ] **Step 2: Confirm the target version is unused**

Check GitHub releases/tags for `v0.1.9`. If unused, set:

```bash
APP_VERSION="${APP_VERSION:-0.1.9}"
APP_BUILD="${APP_BUILD:-10}"
```

If already occupied, use the next free patch version and increment the build number.

- [ ] **Step 3: Update release notes**

The workflow release notes must state:

```text
- 原生 macOS titlebar 拖动，视觉上继续隐藏系统标题栏/红黄绿按钮
- 原生窗口边缘与角落缩放，删除自制 resize overlay
- 连续阅读使用原生 NSScrollView + NSTextView 整本滚动
- 移除生产滚动链路中的虚拟窗口 recenter
- 修复 position 写回导致 viewport 反向跳转/回弹
- 保留隐藏滚动条、主题、字体/颜色、分页、老板模式与进度
```

Do not claim packaged dragging/scrolling was proven by unit tests.

- [ ] **Step 4: Create the smoke record**

Create:

```markdown
# ReadBook v0.1.9 interaction smoke verification

## Automated
- [ ] swift test
- [ ] swift build
- [ ] app packaging
- [ ] codesign verification
- [ ] PR macOS CI

## Packaged app
- [ ] Drag the reader from the invisible native titlebar; the window moves.
- [ ] Resize from one edge and one corner; native resizing works.
- [ ] Switch to continuous mode and scroll vertically at least three screens.
- [ ] Stop scrolling for two seconds; the viewport does not snap backward.
- [ ] Switch paginated -> continuous -> paginated; location stays near the same text.
- [ ] Reopen the reader/book; saved position is restored.
- [ ] No title text, traffic-light buttons, gray titlebar, or visible scroll bar appears.
- [ ] Card/frameless/transparent appearance remains visually acceptable.

## Release gate
Do not merge to main until every packaged-app checkbox is verified against the PR artifact.
```

- [ ] **Step 5: Commit release-candidate metadata**

```bash
git add Scripts/build-app.sh \
        .github/workflows/bootstrap-readbook.yml \
        docs/superpowers/verification/2026-08-31-v0.1.9-interaction-smoke.md
git commit -m "chore: prepare native interaction release candidate"
```

- [ ] **Step 6: Open the PR and require macOS CI GREEN**

Required steps:

```text
Test
Build
Package local app bundle
Verify packaged app signature
Verify branding
Create archive and checksum
Upload installable preview
```

All must succeed. Do not merge yet.

- [ ] **Step 7: Verify the exact PR artifact**

Use the artifact:

```text
ReadBook-v<version>-<PR-head-sha>
```

Verify its `.sha256`. If the execution environment cannot physically drive macOS pointer/trackpad interactions, provide this exact artifact to the user and wait for the user's smoke result before checking the packaged-app boxes or merging.

- [ ] **Step 8: Record the verified candidate**

After actual smoke PASS, append:

```markdown
## Verified candidate
- PR head SHA: `<exact sha>`
- Artifact SHA-256: `<exact digest>`
- Smoke result: PASS
```

Commit the completed record and let PR CI rerun on that exact head.

---

### Task 6: Final review, merge, and immutable release verification

**Files:**
- No production files unless review finds a defect.

**Interfaces:**
- Consumes: final PR head with GREEN CI and packaged smoke PASS.
- Produces: merged `main` and immutable GitHub release.

- [ ] **Step 1: Review the final diff for forbidden regressions**

The final production patch must contain no active use of:

```text
ReaderDragRegion
ReaderDragView
ReaderResizeView
window.styleMask.remove(.titled)
.fullSizeContentView
NSEvent.addGlobalMonitorForEvents
NSEvent.addLocalMonitorForEvents
VirtualTextWindowPlanner   // in ContinuousTextView production path
```

- [ ] **Step 2: Verify the exact merge candidate**

Required evidence for the exact head SHA:

```text
swift test: PASS
swift build: PASS
package: PASS
codesign verification: PASS
checksum verification: PASS
PR macOS CI: PASS
packaged-app smoke: PASS
```

- [ ] **Step 3: Merge only the verified head SHA**

Use an expected-head guard. If the branch changes after smoke verification, rerun CI and smoke as appropriate before merge.

- [ ] **Step 4: Verify main CI and publish**

Require:

```text
test-build-package: success
publish: success
```

- [ ] **Step 5: Verify the GitHub release assets**

Confirm:

```text
release tag = chosen version
release target = merged main commit
ReadBook-macOS.zip exists
ReadBook-macOS.zip.sha256 exists
published ZIP digest matches checksum asset
```

- [ ] **Step 6: Report completion with evidence**

Include:

```text
version/build
merge commit SHA
main CI result
release URL
published ZIP SHA-256
packaged smoke result
```

Do not claim dragging or scrolling is fixed unless the packaged-app smoke gate actually passed.

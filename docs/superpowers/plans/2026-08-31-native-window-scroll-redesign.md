# Native Window and Continuous Scroll Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace ReadBook's custom drag/resize overlays and virtualized continuous-scroll path with native AppKit window movement/resizing and a conventional whole-document `NSScrollView`/`NSTextView`, while preserving the current clean card appearance.

**Architecture:** Keep the SwiftUI app shell. Restore a real `.titled + .resizable` `NSWindow`, visually hide its chrome, and leave its true titlebar area to AppKit for dragging. Continuous mode becomes a whole-document native text scroll view; user scrolling owns the viewport, while model position updates flow outward without immediately re-driving the same viewport position.

**Tech Stack:** Swift 6, SwiftUI, AppKit (`NSWindow`, `NSScrollView`, `NSTextView`, TextKit), XCTest, Swift Package Manager, GitHub Actions macOS 26.

**Spec:** `docs/superpowers/specs/2026-08-31-native-window-scroll-redesign.md`

## Global Constraints

- Preserve the clean widget-like reader: no visible title text, traffic-light buttons, gray system titlebar, or visible scroll bar.
- Keep a real native titlebar drag surface. Do not use `.fullSizeContentView` in v0.1.9.
- Do not use `ReaderDragRegion`, `ReaderDragView`, `ReaderResizeView`, `performDrag(with:)`, custom edge resize tracking, or global/local `NSEvent` monitors for the new implementation.
- Continuous mode must use native vertical `NSScrollView` behavior.
- The titlebar visual fill must match current appearance: theme background for card, theme background with configured opacity for frameless, clear for transparent.
- Keep themes, custom text color, font, spacing, pagination, always-on-top, boss mode, library popover, settings, autosaved frame, and persisted reading positions compatible.
- Whole-document continuous rendering is acceptable; `VirtualTextWindowPlanner` must not participate in the production continuous-scroll path.
- Clamp invalid anchors to the UTF-16 document length.
- CI success alone is insufficient. The packaged PR artifact must pass the interaction smoke gate before merge/release.
- Target release: v0.1.9 unless occupied; if occupied, use the next unused patch version and increment build number.

---

## Task 1: Migrate window tests to the native-window contract

**Files:**
- Modify: `Tests/ReadBookAppTests/WindowCoordinatorTests.swift`
- Modify: `Tests/ReadBookAppTests/ReaderWindowInteractionTests.swift`

**Interfaces:**
- Consumes: current `WindowCoordinator.configure(_:)`, `WindowRegistry.applyAppearance(_:)`.
- Produces: failing tests that define the new `.titled`/native-resize/titlebar-appearance contract before production code changes.

- [ ] **Step 1: Replace the obsolete borderless expectation**

Change the old `WindowCoordinatorTests.testConfigureRemovesTitledChromeKeepsResizableAndDisablesBackgroundDrag` to:

```swift
@MainActor
func testConfigureKeepsNativeTitleAndResizeBehavior() {
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
```

Add a `makeWindow()` helper if needed:

```swift
@MainActor
private func makeWindow() -> NSWindow {
    NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 360, height: 260),
        styleMask: [.titled, .resizable, .closable],
        backing: .buffered,
        defer: false
    )
}
```

- [ ] **Step 2: Replace direct `applyAppearance(.case)` tests with preference-driven appearance tests**

Use:

```swift
@MainActor
func testRegistryAppliesAppearanceAndPointerPassThrough() {
    let registry = WindowRegistry()
    let window = makeWindow()
    registry.register(window)

    var preferences = ReaderPreferences.defaults
    preferences.theme = .soft

    preferences.windowAppearance = .transparent
    registry.applyAppearance(preferences)
    XCTAssertFalse(window.hasShadow)
    XCTAssertTrue(window.backgroundColor.isEqual(NSColor.clear))

    preferences.windowAppearance = .frameless
    preferences.framelessBackgroundOpacity = 0.18
    registry.applyAppearance(preferences)
    XCTAssertFalse(window.hasShadow)
    XCTAssertEqual(window.backgroundColor.alphaComponent, 0.18, accuracy: 0.01)

    preferences.windowAppearance = .card
    registry.applyAppearance(preferences)
    XCTAssertTrue(window.hasShadow)
    XCTAssertTrue(
        window.backgroundColor.isEqual(
            ThemePalette.resolve(.soft).background
        )
    )

    registry.setPointerPassThrough(true)
    XCTAssertTrue(window.ignoresMouseEvents)
    registry.setPointerPassThrough(false)
    XCTAssertFalse(window.ignoresMouseEvents)
}
```

- [ ] **Step 3: Replace custom resize-hit-zone tests**

In `ReaderWindowInteractionTests.swift`, remove tests that synthesize drags against `ReaderResizeView`. Add:

```swift
@MainActor
func testConfigureDoesNotAddContentOverlay() throws {
    let window = makeWindow()
    let contentView = try XCTUnwrap(window.contentView)
    let before = contentView.subviews.count

    WindowCoordinator().configure(window)

    XCTAssertEqual(contentView.subviews.count, before)
}

@MainActor
func testTrafficLightButtonsAreHidden() {
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
```

- [ ] **Step 4: Run focused tests and verify RED**

```bash
swift test --filter WindowCoordinatorTests
swift test --filter ReaderWindowInteractionTests
```

Expected: FAIL because current production code removes `.titled`, leaves appearance background clear, uses the old `applyAppearance` signature, and installs `ReaderResizeView`.

- [ ] **Step 5: Commit only the test migration**

```bash
git add Tests/ReadBookAppTests/WindowCoordinatorTests.swift \
        Tests/ReadBookAppTests/ReaderWindowInteractionTests.swift
git commit -m "test: define native reader window contract"
```

---

## Task 2: Restore native window movement/resizing and clean titlebar appearance

**Files:**
- Modify: `Sources/ReadBook/Window/WindowCoordinator.swift`
- Modify: `Sources/ReadBook/Window/WindowRegistry.swift`
- Delete: `Sources/ReadBook/Window/ReaderResizeView.swift`

**Interfaces:**
- Consumes: failing contract from Task 1.
- Produces: real native titlebar/resizing, hidden system buttons/title, no custom overlay, appearance-matched titlebar fill.

- [ ] **Step 1: Implement native window configuration**

`WindowCoordinator.configure(_:)` becomes:

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

Keep `windowShouldClose(_:)`; remove `installResizeHitZones(in:)` entirely.

- [ ] **Step 2: Make the window background follow reader appearance**

Change `WindowRegistry.applyAppearance` to:

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

Update:

```swift
func apply(_ preferences: ReaderPreferences) {
    setAlwaysOnTop(preferences.alwaysOnTop)
    setAppPresence(preferences.appPresenceMode)
    applyAppearance(preferences)
}
```

This ensures the native titlebar area does not become a transparent visual gap when `.fullSizeContentView` is intentionally absent.

- [ ] **Step 3: Delete custom resize implementation**

Delete:

```text
Sources/ReadBook/Window/ReaderResizeView.swift
```

Do not replace it with another `NSView` overlay.

- [ ] **Step 4: Run window tests and verify GREEN**

```bash
swift test --filter WindowCoordinatorTests
swift test --filter ReaderWindowInteractionTests
swift test
```

Expected: PASS.

- [ ] **Step 5: Commit Task 2**

```bash
git add Sources/ReadBook/Window/WindowCoordinator.swift \
        Sources/ReadBook/Window/WindowRegistry.swift \
        Sources/ReadBook/Window/ReaderResizeView.swift
git commit -m "refactor: restore native reader window behavior"
```

---

## Task 3: Remove custom title dragging from the SwiftUI hierarchy

**Files:**
- Modify: `Sources/ReadBook/Reader/ReaderToolbar.swift`
- Modify only if needed: `Sources/ReadBook/Reader/ReaderRootView.swift`
- Modify: `Tests/ReadBookAppTests/V015InteractionRegressionTests.swift`
- Delete: `Sources/ReadBook/Window/ReaderDragRegion.swift`
- Delete: `Tests/ReadBookAppTests/ReaderDragRegionTests.swift`

**Interfaces:**
- Consumes: native titlebar from Task 2.
- Produces: no custom drag path in reader content; AppKit owns dragging solely through the real titlebar area.

- [ ] **Step 1: Write a failing source regression test**

Add to `V015InteractionRegressionTests.swift`:

```swift
func testToolbarDoesNotEmbedCustomDragRegion() throws {
    let toolbar = try source("Sources/ReadBook/Reader/ReaderToolbar.swift")
    XCTAssertFalse(toolbar.contains("ReaderDragRegion("))
    XCTAssertFalse(toolbar.contains("performDrag(with:"))
}
```

Add helper:

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

- [ ] **Step 2: Run focused test and verify RED**

```bash
swift test --filter V015InteractionRegressionTests/testToolbarDoesNotEmbedCustomDragRegion
```

Expected: FAIL because `ReaderToolbar` currently embeds `ReaderDragRegion()`.

- [ ] **Step 3: Replace the drag ZStack with display-only title content**

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

- [ ] **Step 4: Keep hover reveal below the native titlebar**

Retain the existing top hover zone only inside SwiftUI content:

```swift
Color.clear
    .frame(height: 20)
    .contentShape(Rectangle())
    .onHover { runtime.chrome.topZoneChanged(inside: $0) }
```

Do not move it into a titlebar accessory and do not add window-wide event monitors.

- [ ] **Step 5: Delete retired drag files**

Delete:

```text
Sources/ReadBook/Window/ReaderDragRegion.swift
Tests/ReadBookAppTests/ReaderDragRegionTests.swift
```

- [ ] **Step 6: Verify GREEN**

```bash
swift test --filter V015InteractionRegressionTests
swift test --filter WindowCoordinatorTests
swift test --filter ReaderWindowInteractionTests
```

Expected: PASS.

- [ ] **Step 7: Commit Task 3**

```bash
git add Sources/ReadBook/Reader/ReaderToolbar.swift \
        Sources/ReadBook/Reader/ReaderRootView.swift \
        Sources/ReadBook/Window/ReaderDragRegion.swift \
        Tests/ReadBookAppTests/ReaderDragRegionTests.swift \
        Tests/ReadBookAppTests/V015InteractionRegressionTests.swift
git commit -m "refactor: remove custom reader drag overlay"
```

---

## Task 4: Replace virtual continuous scrolling with a whole-document native text view

**Files:**
- Modify: `Tests/ReadBookAppTests/ContinuousTextViewTests.swift`
- Modify: `Sources/ReadBook/Reader/ContinuousTextView.swift`

**Interfaces:**
- Consumes: existing `ContinuousTextView(bookID:text:anchor:style:textColor:onPositionChanged:)` boundary.
- Produces: a standard `NSScrollView`/`NSTextView` whose document contains the full book, with native vertical scrolling and no virtual recentering.

- [ ] **Step 1: Replace bounded-window test with a failing whole-document test**

```swift
@MainActor
func testCoordinatorRendersWholeDocumentAndCreatesScrollableHeight() throws {
    let paragraph = String(repeating: "女巫种田正文", count: 40) + "\n"
    let text = String(repeating: paragraph, count: 400)
    let (scrollView, textView, coordinator) = makeReader()

    coordinator.update(
        bookID: UUID(),
        text: text,
        anchor: .init(utf16Offset: 0),
        style: .default,
        textColor: .textColor
    )

    textView.layoutManager?.ensureLayout(for: try XCTUnwrap(textView.textContainer))
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

- [ ] **Step 2: Verify RED**

```bash
swift test --filter ContinuousTextViewTests/testCoordinatorRendersWholeDocumentAndCreatesScrollableHeight
```

Expected: FAIL because current production renders a bounded `VirtualTextWindow`.

- [ ] **Step 3: Remove virtual-window production state**

Remove from `ContinuousTextView.Coordinator`:

```swift
VirtualTextWindowPlanner
VirtualTextWindow
currentWindow
recenterScheduled
loadWindow(centeredAt:restoreGlobalOffset:)
scheduleRecenteringIfNeeded(at:)
```

Retain focused state:

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

- [ ] **Step 4: Keep a conventional native text stack**

`makeNSView` must configure:

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

Do not override `scrollWheel(with:)` or install an event monitor.

- [ ] **Step 5: Render the complete attributed text**

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

Clamp `offset` before calling.

- [ ] **Step 6: Verify GREEN**

```bash
swift test --filter ContinuousTextViewTests/testCoordinatorRendersWholeDocumentAndCreatesScrollableHeight
```

Expected: PASS.

- [ ] **Step 7: Commit Task 4**

```bash
git add Sources/ReadBook/Reader/ContinuousTextView.swift \
        Tests/ReadBookAppTests/ContinuousTextViewTests.swift
git commit -m "refactor: use whole-document native scrolling"
```

---

## Task 5: Prove viewport movement and prevent position feedback snap-back

**Files:**
- Modify: `Tests/ReadBookAppTests/ContinuousTextViewTests.swift`
- Modify: `Sources/ReadBook/Reader/ContinuousTextView.swift`

**Interfaces:**
- Consumes: whole-document scroll view from Task 4.
- Produces: debounced visible-position reporting; reported user offsets are never immediately re-applied as external navigation.

- [ ] **Step 1: Add native viewport movement/report test**

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

- [ ] **Step 2: Add feedback snap-back regression test**

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

- [ ] **Step 3: Run tests and verify RED where ownership is incomplete**

```bash
swift test --filter ContinuousTextViewTests/testNativeScrollAdvancesViewportAndReportsLaterPosition
swift test --filter ContinuousTextViewTests/testReportedPositionFedBackDoesNotSnapViewport
```

- [ ] **Step 4: Debounce position reporting**

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

The bounds-change observer calls this method. `detach()` cancels the pending work item and removes the observer.

- [ ] **Step 5: Enforce one-way feedback ownership**

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

`scrollTo(globalOffset:)` records `lastAppliedExternalAnchor` after changing the clip view.

- [ ] **Step 6: Add external saved-anchor restoration test**

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

If layout timing makes this fail, allow exactly one `DispatchQueue.main.async` retry; do not poll.

- [ ] **Step 7: Verify GREEN and full regression suite**

```bash
swift test --filter ContinuousTextViewTests
swift test
```

Expected: PASS. `AppModel.setMode(_:)` must continue to preserve `session.position`.

- [ ] **Step 8: Commit Task 5**

```bash
git add Sources/ReadBook/Reader/ContinuousTextView.swift \
        Tests/ReadBookAppTests/ContinuousTextViewTests.swift
git commit -m "fix: keep native scroll viewport authoritative"
```

---

## Task 6: Build the release candidate and enforce a packaged-app smoke gate

**Files:**
- Modify: `Scripts/build-app.sh`
- Modify: `.github/workflows/bootstrap-readbook.yml`
- Create: `docs/superpowers/verification/2026-08-31-v0.1.9-interaction-smoke.md`

**Interfaces:**
- Consumes: Tasks 1-5.
- Produces: a versioned PR artifact for real drag/resize/scroll verification; main stays unchanged until smoke passes.

- [ ] **Step 1: Run CI-equivalent verification before versioning**

```bash
swift test
swift build
Scripts/build-app.sh
codesign --verify --deep --strict --verbose=4 dist/ReadBook.app
```

Expected: all exit 0.

- [ ] **Step 2: Confirm version availability and bump candidate metadata**

If `v0.1.9` is unused:

```bash
APP_VERSION="${APP_VERSION:-0.1.9}"
APP_BUILD="${APP_BUILD:-10}"
```

Otherwise use the next unused patch version/build.

- [ ] **Step 3: Replace release notes with architecture-accurate notes**

They must mention:

```text
- 原生 macOS titlebar 拖动，视觉上隐藏系统标题栏和红黄绿按钮
- 原生边缘/角落 resize，删除自制 overlay
- 连续阅读使用 NSScrollView + NSTextView 整本滚动
- 生产滚动链路移除 virtual-window recenter
- position 写回不再反向驱动 viewport，避免回弹
- 保留隐藏滚动条、主题、字体/颜色、分页、老板模式与进度
```

Do not claim unit tests prove real pointer/trackpad interaction.

- [ ] **Step 4: Create smoke verification record**

```markdown
# ReadBook v0.1.9 interaction smoke verification

## Automated
- [ ] swift test
- [ ] swift build
- [ ] app packaging
- [ ] codesign verification
- [ ] PR macOS CI

## Packaged app
- [ ] Drag from the invisible native titlebar; window moves.
- [ ] Resize from one edge and one corner; native resizing works.
- [ ] Continuous mode scrolls vertically at least three screens.
- [ ] After stopping for two seconds, viewport does not snap backward.
- [ ] Paginated -> continuous -> paginated stays near the same text.
- [ ] Reopening reader/book restores saved position.
- [ ] No title text, traffic lights, gray titlebar, or visible scroll bar appears.
- [ ] Card/frameless/transparent appearances remain visually acceptable.

## Release gate
Do not merge to main until every packaged-app checkbox is verified against the exact PR artifact.
```

- [ ] **Step 5: Commit release-candidate metadata**

```bash
git add Scripts/build-app.sh \
        .github/workflows/bootstrap-readbook.yml \
        docs/superpowers/verification/2026-08-31-v0.1.9-interaction-smoke.md
git commit -m "chore: prepare native interaction release candidate"
```

- [ ] **Step 6: Open PR and require macOS CI GREEN**

Required CI steps:

```text
Test
Build
Package local app bundle
Verify packaged app signature
Verify branding
Create archive and checksum
Upload installable preview
```

All must succeed. Do not merge.

- [ ] **Step 7: Verify exact PR artifact and run smoke**

Artifact name:

```text
ReadBook-v<version>-<PR-head-sha>
```

Verify its `.sha256`. If this execution environment cannot physically drive macOS pointer/trackpad interaction, provide that exact artifact to the user and wait for the user's smoke result before marking packaged checks PASS or merging.

- [ ] **Step 8: Record verified candidate and rerun CI**

Append:

```markdown
## Verified candidate
- PR head SHA: `<exact sha>`
- Artifact SHA-256: `<exact digest>`
- Smoke result: PASS
```

Commit the completed record; require PR CI GREEN again on that exact final head.

---

## Task 7: Final review, merge, and immutable release verification

**Files:**
- No production files unless review finds a defect.

**Interfaces:**
- Consumes: exact PR head with GREEN CI and packaged smoke PASS.
- Produces: merged `main` and immutable GitHub release.

- [ ] **Step 1: Review final production diff for forbidden regressions**

No active production use of:

```text
ReaderDragRegion
ReaderDragView
ReaderResizeView
window.styleMask.remove(.titled)
.fullSizeContentView
NSEvent.addGlobalMonitorForEvents
NSEvent.addLocalMonitorForEvents
VirtualTextWindowPlanner   // inside ContinuousTextView production path
```

- [ ] **Step 2: Verify exact merge candidate evidence**

Required:

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

Use an expected-head guard. If head changes after smoke verification, rerun the relevant verification before merge.

- [ ] **Step 4: Verify main CI and publish**

Require:

```text
test-build-package: success
publish: success
```

- [ ] **Step 5: Verify release assets and digest**

Confirm:

```text
release tag = chosen version
release target = merged main commit
ReadBook-macOS.zip exists
ReadBook-macOS.zip.sha256 exists
ZIP digest matches checksum asset
```

- [ ] **Step 6: Completion report**

Include version/build, merge SHA, main CI result, release URL, published ZIP SHA-256, and packaged smoke result. Do not claim dragging/scrolling is fixed without packaged smoke PASS.

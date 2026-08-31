# Native Window and Continuous Scroll Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace ReadBook's custom drag/resize overlays and virtualized continuous-scroll path with native AppKit window movement/resizing and a native whole-document text scroll view, while preserving the current clean card appearance.

**Architecture:** Keep the SwiftUI app shell and reader composition. Restore a real `.titled + .resizable` `NSWindow`, visually hide its chrome, and leave its true titlebar region available to AppKit for dragging. Continuous mode is built from AppKit's own `NSTextView.scrollableTextView()` factory; scrolling owns the viewport locally, and model position updates flow outward without immediately re-driving the same viewport position.

**Tech Stack:** Swift 6, SwiftUI, AppKit (`NSWindow`, `NSScrollView`, `NSTextView`, TextKit), CoreGraphics for scroll-event tests, XCTest, Swift Package Manager, GitHub Actions macOS 26.

**Spec:** `docs/superpowers/specs/2026-08-31-native-window-scroll-redesign.md`

## Global Constraints

- Preserve the clean widget-like reader: no visible title text, traffic-light buttons, gray system titlebar, or visible scroll bar.
- Keep a real native titlebar drag surface. Do not use `.fullSizeContentView` in v0.1.9.
- Do not use `ReaderDragRegion`, `ReaderDragView`, `ReaderResizeView`, `performDrag(with:)`, custom edge resize tracking, or global/local `NSEvent` monitors in the new implementation.
- Continuous mode must use native `NSScrollView` vertical scrolling.
- The titlebar visual fill must match current appearance: theme background for card, theme background with configured opacity for frameless, clear for transparent.
- Keep themes, custom text color, font, spacing, pagination, always-on-top, boss mode, library popover, settings, autosaved frame, and persisted reading positions compatible.
- Whole-document continuous rendering is acceptable; `VirtualTextWindowPlanner` must not participate in the production continuous-scroll path.
- Do not force full-document TextKit layout merely to restore an anchor; only lay out the local target range needed for a jump.
- Clamp invalid anchors to the UTF-16 document length.
- CI success alone is insufficient. The packaged PR artifact must pass the interaction smoke gate before merge/release.
- Target release is v0.1.9 unless occupied; if occupied, use the next unused patch version and increment build number.

---

## Task 1: Migrate legacy tests to the native-window contract

**Files:**
- Modify: `Tests/ReadBookAppTests/WindowCoordinatorTests.swift`
- Modify: `Tests/ReadBookAppTests/ReaderWindowInteractionTests.swift`

**Interfaces:**
- Consumes: current `WindowCoordinator.configure(_:)` and `WindowRegistry.applyAppearance(_:)`.
- Produces: RED tests defining the new `.titled`/native-resize/titlebar-appearance contract before production changes.

- [ ] **Step 1: Replace the obsolete borderless expectation**

Replace the current test that requires `.titled` to be removed with:

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

Use this helper in the test file:

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

- [ ] **Step 2: Replace the old direct appearance-case test with preference-driven appearance tests**

Change the registry test to use the complete preference set:

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

- [ ] **Step 3: Replace custom resize-overlay behavior tests**

Remove tests that synthesize `mouseDragged` against `ReaderResizeView`. Add:

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

Expected: FAIL because production currently removes `.titled`, leaves the native titlebar fill clear, uses the old appearance API, and installs `ReaderResizeView`.

- [ ] **Step 5: Commit the RED contract**

```bash
git add Tests/ReadBookAppTests/WindowCoordinatorTests.swift \
        Tests/ReadBookAppTests/ReaderWindowInteractionTests.swift
git commit -m "test: define native reader window contract"
```

---

## Task 2: Restore native window movement/resizing and preserve the clean appearance

**Files:**
- Modify: `Sources/ReadBook/Window/WindowCoordinator.swift`
- Modify: `Sources/ReadBook/Window/WindowRegistry.swift`
- Delete: `Sources/ReadBook/Window/ReaderResizeView.swift`

**Interfaces:**
- Consumes: RED tests from Task 1.
- Produces: native titlebar dragging/resizing, hidden system chrome, no custom resize overlay, and a titlebar fill matching the reader theme/appearance.

- [ ] **Step 1: Implement native window configuration**

Change `WindowCoordinator.configure(_:)` to:

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

Keep `windowShouldClose(_:)`. Remove `installResizeHitZones(in:)` completely.

- [ ] **Step 2: Make the whole window background follow reader appearance**

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

Update `WindowRegistry.apply(_:)`:

```swift
func apply(_ preferences: ReaderPreferences) {
    setAlwaysOnTop(preferences.alwaysOnTop)
    setAppPresence(preferences.appPresenceMode)
    applyAppearance(preferences)
}
```

This fills the otherwise transparent native titlebar area with the same visual treatment as the reader body.

- [ ] **Step 3: Delete the custom resize overlay**

Delete `Sources/ReadBook/Window/ReaderResizeView.swift`. Do not add a replacement overlay.

- [ ] **Step 4: Verify GREEN**

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
- Modify only if the existing top hover region extends outside content bounds: `Sources/ReadBook/Reader/ReaderRootView.swift`
- Modify: `Tests/ReadBookAppTests/V015InteractionRegressionTests.swift`
- Delete: `Sources/ReadBook/Window/ReaderDragRegion.swift`
- Delete: `Tests/ReadBookAppTests/ReaderDragRegionTests.swift`

**Interfaces:**
- Consumes: native titlebar from Task 2.
- Produces: no custom drag path in reader content; AppKit owns dragging through the real titlebar region only.

- [ ] **Step 1: Write a failing source regression test**

Add to `V015InteractionRegressionTests.swift`:

```swift
func testToolbarDoesNotEmbedCustomDragRegion() throws {
    let toolbar = try source("Sources/ReadBook/Reader/ReaderToolbar.swift")
    XCTAssertFalse(toolbar.contains("ReaderDragRegion("))
    XCTAssertFalse(toolbar.contains("performDrag(with:"))
}
```

Add:

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

- [ ] **Step 2: Verify RED**

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

- [ ] **Step 4: Keep hover reveal below the titlebar**

The existing top hover zone may remain only inside SwiftUI content:

```swift
Color.clear
    .frame(height: 20)
    .contentShape(Rectangle())
    .onHover { runtime.chrome.topZoneChanged(inside: $0) }
```

Do not move it into a titlebar accessory and do not add window-wide event monitors.

- [ ] **Step 5: Delete retired drag implementation/tests**

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

## Task 4: Build continuous mode from AppKit's native scrollable text-view factory

**Files:**
- Modify: `Tests/ReadBookAppTests/ContinuousTextViewTests.swift`
- Modify: `Sources/ReadBook/Reader/ContinuousTextView.swift`

**Interfaces:**
- Consumes: unchanged SwiftUI boundary `ContinuousTextView(bookID:text:anchor:style:textColor:onPositionChanged:)`.
- Produces: `ContinuousTextView.makeNativeScrollView() -> NSScrollView`, used by production and tests; its document view is the configured `NSTextView` that owns the complete book.

- [ ] **Step 1: Write RED tests for the actual native factory and whole document**

Add `import CoreGraphics` to the test file and replace the old bounded-window test with:

```swift
@MainActor
func testNativeFactoryCreatesHiddenScrollerTextView() throws {
    let scrollView = ContinuousTextView.makeNativeScrollView()
    let textView = try XCTUnwrap(scrollView.documentView as? NSTextView)

    XCTAssertFalse(scrollView.hasVerticalScroller)
    XCTAssertFalse(scrollView.hasHorizontalScroller)
    XCTAssertFalse(scrollView.drawsBackground)
    XCTAssertFalse(textView.isEditable)
    XCTAssertTrue(textView.isSelectable)
    XCTAssertFalse(textView.drawsBackground)
    XCTAssertTrue(textView.layoutManager?.allowsNonContiguousLayout ?? false)
}

@MainActor
func testCoordinatorRendersWholeBookIntoNativeTextView() throws {
    let text = String(repeating: "正文内容。\n", count: 10_000)
    let (scrollView, textView, coordinator) = makeReader()

    coordinator.update(
        bookID: UUID(),
        text: text,
        anchor: .init(utf16Offset: 0),
        style: .default,
        textColor: .textColor
    )

    XCTAssertEqual(textView.string, text)
    XCTAssertEqual(textView.textStorage?.length, (text as NSString).length)
    XCTAssertTrue(scrollView.documentView === textView)
}
```

Use a helper that calls the same production factory:

```swift
@MainActor
private func makeReader(
    onPositionChanged: @escaping (BookPosition) -> Void = { _ in }
) -> (NSScrollView, NSTextView, ContinuousTextView.Coordinator) {
    let scrollView = ContinuousTextView.makeNativeScrollView()
    scrollView.frame = NSRect(x: 0, y: 0, width: 360, height: 260)
    let textView = scrollView.documentView as! NSTextView
    let coordinator = ContinuousTextView.Coordinator(
        onPositionChanged: onPositionChanged
    )
    coordinator.attach(scrollView: scrollView, textView: textView)
    return (scrollView, textView, coordinator)
}
```

- [ ] **Step 2: Verify RED**

```bash
swift test --filter ContinuousTextViewTests/testNativeFactoryCreatesHiddenScrollerTextView
swift test --filter ContinuousTextViewTests/testCoordinatorRendersWholeBookIntoNativeTextView
```

Expected: FAIL because `makeNativeScrollView()` does not exist and current production renders only a virtual window.

- [ ] **Step 3: Implement the shared native factory**

Add to `ContinuousTextView`:

```swift
@MainActor
static func makeNativeScrollView() -> NSScrollView {
    let scrollView = NSTextView.scrollableTextView()
    guard let textView = scrollView.documentView as? NSTextView else {
        preconditionFailure("NSTextView.scrollableTextView() must provide NSTextView")
    }

    scrollView.hasVerticalScroller = false
    scrollView.hasHorizontalScroller = false
    scrollView.drawsBackground = false
    scrollView.contentView.postsBoundsChangedNotifications = true

    textView.isEditable = false
    textView.isSelectable = true
    textView.drawsBackground = false
    textView.textContainer?.lineFragmentPadding = 0
    textView.layoutManager?.allowsNonContiguousLayout = true

    return scrollView
}
```

Make `makeNSView(context:)` call this factory, extract its `NSTextView`, attach the coordinator, and return the same scroll view.

- [ ] **Step 4: Remove virtual-window state from production continuous mode**

Remove from `ContinuousTextView.Coordinator`:

```swift
VirtualTextWindowPlanner
VirtualTextWindow
currentWindow
recenterScheduled
loadWindow(centeredAt:restoreGlobalOffset:)
scheduleRecenteringIfNeeded(at:)
```

Keep:

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

Do not delete the planner/core tests if they are independently useful; simply remove it from this production path.

- [ ] **Step 5: Render the complete attributed source without forcing whole-document layout**

Use:

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
    lastReportedOffset = nil
    applyExternalAnchor(offset)
    isApplyingProgrammaticChange = false
}
```

Do not call `sizeToFit()` or `ensureLayout(for:)` on the entire text container.

- [ ] **Step 6: Implement localized external-anchor movement**

Use the existing TextKit layout manager only around the target character:

```swift
private func applyExternalAnchor(_ requestedOffset: Int) {
    guard let scrollView,
          let textView,
          let layoutManager = textView.layoutManager,
          let textContainer = textView.textContainer else { return }

    let length = (textView.string as NSString).length
    guard length > 0 else {
        scrollView.contentView.scroll(to: .zero)
        lastAppliedExternalAnchor = 0
        return
    }

    let offset = min(max(requestedOffset, 0), length - 1)
    let characterRange = NSRange(location: offset, length: 1)
    let glyphRange = layoutManager.glyphRange(
        forCharacterRange: characterRange,
        actualCharacterRange: nil
    )
    let rect = layoutManager.boundingRect(
        forGlyphRange: glyphRange,
        in: textContainer
    )
    let targetY = max(
        rect.minY + textView.textContainerOrigin.y - textView.textContainerInset.height,
        0
    )

    scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
    scrollView.reflectScrolledClipView(scrollView.contentView)
    lastAppliedExternalAnchor = offset
}
```

- [ ] **Step 7: Verify GREEN**

```bash
swift test --filter ContinuousTextViewTests/testNativeFactoryCreatesHiddenScrollerTextView
swift test --filter ContinuousTextViewTests/testCoordinatorRendersWholeBookIntoNativeTextView
```

Expected: PASS.

- [ ] **Step 8: Commit Task 4**

```bash
git add Sources/ReadBook/Reader/ContinuousTextView.swift \
        Tests/ReadBookAppTests/ContinuousTextViewTests.swift
git commit -m "refactor: use native scrollable text view"
```

---

## Task 5: Prove actual scroll-wheel movement and eliminate snap-back feedback

**Files:**
- Modify: `Tests/ReadBookAppTests/ContinuousTextViewTests.swift`
- Modify: `Sources/ReadBook/Reader/ContinuousTextView.swift`

**Interfaces:**
- Consumes: native factory and whole-document text view from Task 4.
- Produces: real `NSScrollView.scrollWheel(with:)` movement, debounced visible-position reporting, and no immediate re-application of a coordinator-reported position.

- [ ] **Step 1: Add a test helper that hosts the scroll view in a real NSWindow**

```swift
@MainActor
private func host(_ scrollView: NSScrollView) -> NSWindow {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 360, height: 260),
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    scrollView.frame = window.contentView!.bounds
    scrollView.autoresizingMask = [.width, .height]
    window.contentView!.addSubview(scrollView)
    window.layoutIfNeeded()
    return window
}
```

- [ ] **Step 2: Add an actual scroll-wheel event test**

```swift
@MainActor
func testNativeScrollWheelChangesClipViewOrigin() throws {
    let text = String(repeating: "滚动正文内容。\n", count: 20_000)
    let (scrollView, _, coordinator) = makeReader()
    let window = host(scrollView)
    _ = window

    coordinator.update(
        bookID: UUID(),
        text: text,
        anchor: .init(utf16Offset: (text as NSString).length / 3),
        style: .default,
        textColor: .textColor
    )
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))

    let startY = scrollView.contentView.bounds.minY
    let cgEvent = try XCTUnwrap(
        CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: -180,
            wheel2: 0,
            wheel3: 0
        )
    )
    let event = try XCTUnwrap(NSEvent(cgEvent: cgEvent))

    scrollView.scrollWheel(with: event)
    RunLoop.main.run(until: Date().addingTimeInterval(0.08))

    XCTAssertNotEqual(scrollView.contentView.bounds.minY, startY)
}
```

The test begins away from the document edge so either wheel direction has room to move.

- [ ] **Step 3: Add position-report and snap-back tests**

```swift
@MainActor
func testScrollReportsLaterPosition() throws {
    let text = String(repeating: "报告位置正文。\n", count: 20_000)
    var reported: BookPosition?
    let (scrollView, _, coordinator) = makeReader {
        reported = $0
    }
    let window = host(scrollView)
    _ = window

    coordinator.update(
        bookID: UUID(),
        text: text,
        anchor: .init(utf16Offset: 0),
        style: .default,
        textColor: .textColor
    )

    scrollView.contentView.scroll(to: NSPoint(x: 0, y: 300))
    scrollView.reflectScrolledClipView(scrollView.contentView)
    NotificationCenter.default.post(
        name: NSView.boundsDidChangeNotification,
        object: scrollView.contentView
    )
    RunLoop.main.run(until: Date().addingTimeInterval(0.12))

    XCTAssertGreaterThan(reported?.utf16Offset ?? 0, 0)
}

@MainActor
func testReportedPositionFedBackDoesNotSnapViewport() throws {
    let text = String(repeating: "反馈回路正文。\n", count: 20_000)
    let bookID = UUID()
    var reported = BookPosition(utf16Offset: 0)
    let (scrollView, _, coordinator) = makeReader {
        reported = $0
    }
    let window = host(scrollView)
    _ = window

    coordinator.update(
        bookID: bookID,
        text: text,
        anchor: .init(utf16Offset: 0),
        style: .default,
        textColor: .textColor
    )

    scrollView.contentView.scroll(to: NSPoint(x: 0, y: 300))
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

    XCTAssertEqual(scrollView.contentView.bounds.minY, yAfterScroll, accuracy: 1.0)
}
```

- [ ] **Step 4: Run the three focused tests and verify RED where feedback behavior is incomplete**

```bash
swift test --filter ContinuousTextViewTests/testNativeScrollWheelChangesClipViewOrigin
swift test --filter ContinuousTextViewTests/testScrollReportsLaterPosition
swift test --filter ContinuousTextViewTests/testReportedPositionFedBackDoesNotSnapViewport
```

Expected before the feedback implementation: at least the report/snap-back contract fails. If the raw wheel event test fails, do not bypass it with a helper assertion; diagnose the native scroll view sizing/event path before continuing.

- [ ] **Step 5: Debounce scroll-position reporting**

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

The bounds-change observer calls `schedulePositionReport()`. `detach()` cancels the work item and unregisters the observer.

- [ ] **Step 6: Make coordinator-reported anchors non-programmatic**

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
let styleChanged = currentStyle != style || currentColor != textColor

sourceBookID = bookID
sourceText = text
currentStyle = style
currentColor = textColor

if bookChanged || styleChanged {
    renderDocument(restoringGlobalOffset: clampedAnchor)
    return
}

guard clampedAnchor != lastReportedOffset,
      clampedAnchor != lastAppliedExternalAnchor else { return }

isApplyingProgrammaticChange = true
applyExternalAnchor(clampedAnchor)
isApplyingProgrammaticChange = false
```

Imported book text is immutable for a fixed `bookID`, so do not compare the entire book `String` on every SwiftUI update.

- [ ] **Step 7: Add saved-anchor restoration coverage**

```swift
@MainActor
func testExternalSavedAnchorMovesViewport() throws {
    let text = String(repeating: "恢复位置正文。\n", count: 20_000)
    let target = (text as NSString).length / 2
    let bookID = UUID()
    let (scrollView, _, coordinator) = makeReader()
    let window = host(scrollView)
    _ = window

    coordinator.update(
        bookID: bookID,
        text: text,
        anchor: .init(utf16Offset: 0),
        style: .default,
        textColor: .textColor
    )
    let startY = scrollView.contentView.bounds.minY

    coordinator.update(
        bookID: bookID,
        text: text,
        anchor: .init(utf16Offset: target),
        style: .default,
        textColor: .textColor
    )
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))

    XCTAssertGreaterThan(scrollView.contentView.bounds.minY, startY)
}
```

If the first localized TextKit jump has not settled until the next run-loop turn, production may schedule exactly one main-queue retry for a true external anchor. Do not use polling or repeating timers.

- [ ] **Step 8: Verify GREEN and full regression suite**

```bash
swift test --filter ContinuousTextViewTests
swift test
```

Expected: PASS. `AppModel.setMode(_:)` must continue to preserve `session.position`.

- [ ] **Step 9: Commit Task 5**

```bash
git add Sources/ReadBook/Reader/ContinuousTextView.swift \
        Tests/ReadBookAppTests/ContinuousTextViewTests.swift
git commit -m "fix: keep native scroll viewport authoritative"
```

---

## Task 6: Build the release candidate and enforce packaged-app smoke verification

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

Expected: all commands exit 0.

- [ ] **Step 2: Confirm the release version is unused**

Check GitHub releases/tags. If v0.1.9 is unused, set defaults in `Scripts/build-app.sh` to version `0.1.9` and build `10`. If v0.1.9 already exists, select the next unused patch version and increment the build number by one.

- [ ] **Step 3: Update release notes accurately**

Release notes must state that this version:

```text
- 恢复原生 macOS titlebar 拖动，视觉上隐藏系统标题栏和红黄绿按钮
- 使用原生边缘/角落 resize，删除自制 overlay
- 连续阅读使用 NSTextView.scrollableTextView() 提供的原生滚动容器
- 生产滚动链路移除 virtual-window recenter
- position 写回不再反向驱动 viewport，避免回弹
- 保留隐藏滚动条、主题、字体/颜色、分页、老板模式与进度
```

Do not say unit tests alone proved real pointer/trackpad interaction.

- [ ] **Step 4: Create the smoke record**

Create a Markdown file containing these unchecked items:

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

If the candidate version is not v0.1.9, use the actual candidate version in the heading and filename.

- [ ] **Step 5: Commit release-candidate metadata**

```bash
git add Scripts/build-app.sh \
        .github/workflows/bootstrap-readbook.yml \
        docs/superpowers/verification/
git commit -m "chore: prepare native interaction release candidate"
```

- [ ] **Step 6: Open the implementation PR and require macOS CI GREEN**

Required successful steps:

```text
Test
Build
Package local app bundle
Verify packaged app signature
Verify branding
Create archive and checksum
Upload installable preview
```

Do not merge after CI alone.

- [ ] **Step 7: Verify the exact PR artifact**

Read the artifact name directly from the successful workflow run, download that artifact, verify the included `.sha256`, and record the actual PR head SHA plus computed ZIP SHA-256 in the smoke document.

If the execution environment cannot physically drive macOS pointer/trackpad interactions, hand that exact verified artifact to the user and wait for the user's smoke result before marking the packaged-app items PASS or merging.

- [ ] **Step 8: Record smoke PASS and rerun PR CI on the final head**

After actual smoke verification, check each completed item in the document and add three concrete lines containing the actual PR head SHA, the actual ZIP SHA-256, and `Smoke result: PASS`. Commit the document. Require PR CI GREEN again on that exact final commit.

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
VirtualTextWindowPlanner inside ContinuousTextView
```

- [ ] **Step 2: Verify the exact merge candidate**

Require evidence for the same head SHA:

```text
swift test: PASS
swift build: PASS
package: PASS
codesign verification: PASS
checksum verification: PASS
PR macOS CI: PASS
packaged-app smoke: PASS
```

- [ ] **Step 3: Merge only that verified head**

Use an expected-head guard. If the branch changes after smoke verification, rerun relevant verification before merge.

- [ ] **Step 4: Verify main CI and publish**

Require both `test-build-package` and `publish` to succeed.

- [ ] **Step 5: Verify release assets and checksum**

Fetch the actual release created from the merged commit. Confirm its tag matches the candidate version, its target is the merged main commit, both `ReadBook-macOS.zip` and `ReadBook-macOS.zip.sha256` exist, and the ZIP digest matches the checksum asset.

- [ ] **Step 6: Report completion with evidence**

The final report must include the actual version/build, merge commit SHA, main CI result, release URL, published ZIP SHA-256, and packaged smoke result. Do not claim dragging or scrolling is fixed without packaged smoke PASS.

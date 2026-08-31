# Native Window and Continuous Scroll Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace ReadBook's custom drag/resize overlays and virtualized continuous-scroll path with native AppKit window movement/resizing and a conventional whole-document `NSScrollView`/`NSTextView`, while preserving the current clean card appearance.

**Architecture:** Keep the SwiftUI app shell and reader UI, but restore a real native `.titled + .resizable` `NSWindow` whose titlebar is visually transparent and whose standard window buttons are hidden. Continuous mode becomes one native AppKit scroll view that owns the viewport during user scrolling; model position is reported outward without immediately re-applying the same anchor back into the scroll view.

**Tech Stack:** Swift 6, SwiftUI, AppKit (`NSWindow`, `NSScrollView`, `NSTextView`, TextKit), XCTest, Swift Package Manager, GitHub Actions macOS 26.

**Spec:** `docs/superpowers/specs/2026-08-31-native-window-scroll-redesign.md`

## Global Constraints

- Preserve the current clean, widget-like reader appearance: no visible title text, no traffic-light buttons, no traditional gray titlebar, no visible scroll bar.
- Keep a real native titlebar drag surface; do not use `.fullSizeContentView` in this release.
- Remove custom full-width drag handling from the SwiftUI hierarchy.
- Remove custom edge/corner resize hit zones from the production window.
- Continuous mode must use native vertical scrolling with no global keyboard or mouse event monitors.
- Keep themes, custom text color, font, line spacing, paragraph spacing, always-on-top, boss mode, library popover, settings, window frame autosave, pagination, and persisted reading positions compatible.
- Whole-document continuous rendering is acceptable for v0.1.9; virtual-window recentering must not participate in the production scroll path.
- Ordinary invalid anchors are clamped to the current UTF-16 document length.
- CI success does not substitute for the packaged-app smoke gate. The PR artifact must be exercised before merge/release.
- Target release is v0.1.9 unless that version is occupied before release; if occupied, bump to the next unused version without changing the architecture.

---

## File Structure

The implementation deliberately keeps responsibilities narrow:

- `Sources/ReadBook/Window/WindowCoordinator.swift` — native reader-window configuration only.
- `Sources/ReadBook/Reader/ReaderToolbar.swift` — transient toolbar controls and title display; no drag implementation.
- `Sources/ReadBook/Reader/ReaderRootView.swift` — reader composition and hover reveal zones; no window movement logic.
- `Sources/ReadBook/Reader/ContinuousTextView.swift` — native continuous-reader AppKit bridge and one-way position synchronization.
- `Tests/ReadBookAppTests/ReaderWindowInteractionTests.swift` — assertions about the configured native `NSWindow` contract.
- `Tests/ReadBookAppTests/ContinuousTextViewTests.swift` — whole-document scroll integration and feedback-loop regression coverage.
- `Sources/ReadBook/Window/ReaderDragRegion.swift` — delete after the native titlebar contract is established.
- `Sources/ReadBook/Window/ReaderResizeView.swift` — delete after native resize configuration is established.
- `Tests/ReadBookAppTests/ReaderDragRegionTests.swift` — delete because it tests the retired custom drag mechanism.
- `.github/workflows/bootstrap-readbook.yml` — v0.1.9 release notes only; publishing behavior remains main-only.
- `Scripts/build-app.sh` — release version/build bump after behavior is verified on the PR branch.

---

### Task 1: Restore native AppKit window movement and resizing

**Files:**
- Modify: `Tests/ReadBookAppTests/ReaderWindowInteractionTests.swift`
- Modify: `Sources/ReadBook/Window/WindowCoordinator.swift`
- Delete after GREEN: `Sources/ReadBook/Window/ReaderResizeView.swift`

**Interfaces:**
- Consumes: `WindowCoordinator.configure(_ window: NSWindow)` from the existing window registry.
- Produces: a configured `NSWindow` that retains `.titled`, `.resizable`, and `.closable`; has hidden title and transparent titlebar; has hidden standard window buttons; has no custom `ReaderResizeView` child.

- [ ] **Step 1: Replace custom-resize tests with failing native-window contract tests**

Replace the custom hit-zone behavior tests in `ReaderWindowInteractionTests.swift` with configuration assertions:

```swift
#if os(macOS)
import AppKit
import XCTest
@testable import ReadBook

@MainActor
final class ReaderWindowInteractionTests: XCTestCase {
    func testWindowConfigurationRetainsNativeTitleAndResizeBehavior() throws {
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

    func testWindowConfigurationHidesTrafficLightButtons() {
        let window = makeWindow()

        WindowCoordinator().configure(window)

        for type in [
            NSWindow.ButtonType.closeButton,
            .miniaturizeButton,
            .zoomButton,
        ] {
            let button = window.standardWindowButton(type)
            XCTAssertTrue(button?.isHidden ?? true)
        }
    }

    func testWindowConfigurationDoesNotInstallCustomResizeOverlay() throws {
        let window = makeWindow()

        WindowCoordinator().configure(window)

        let contentView = try XCTUnwrap(window.contentView)
        XCTAssertFalse(contentView.subviews.contains { $0 is ReaderResizeView })
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

Keep the `ReaderResizeView` type temporarily so the third assertion can compile and fail for the right reason.

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
swift test --filter ReaderWindowInteractionTests
```

Expected: FAIL because current `WindowCoordinator.configure` removes `.titled`, installs `ReaderResizeView`, and does not configure the native titlebar contract.

- [ ] **Step 3: Implement the minimal native-window configuration**

Change `WindowCoordinator.configure(_:)` to this shape:

```swift
@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    func configure(_ window: NSWindow) {
        window.delegate = self
        window.minSize = NSSize(width: 280, height: 180)

        window.styleMask.insert([.titled, .resizable, .closable])
        window.styleMask.remove(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.setFrameAutosaveName("ReadBook.ReaderWindow")

        hideStandardWindowButtons(in: window)
    }

    private func hideStandardWindowButtons(in window: NSWindow) {
        for type in [
            NSWindow.ButtonType.closeButton,
            .miniaturizeButton,
            .zoomButton,
        ] {
            window.standardWindowButton(type)?.isHidden = true
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NotificationCenter.default.post(name: .readBookReaderWillHide, object: nil)
        sender.orderOut(nil)
        return false
    }
}
```

Do not call `installResizeHitZones` and do not add any replacement overlay.

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run:

```bash
swift test --filter ReaderWindowInteractionTests
```

Expected: PASS.

- [ ] **Step 5: Delete the retired resize implementation and remove the temporary type assertion**

Delete:

```text
Sources/ReadBook/Window/ReaderResizeView.swift
```

Then replace the third test with a type-independent hierarchy assertion that ensures no extra overlay is installed:

```swift
func testWindowConfigurationDoesNotAddContentOverlay() throws {
    let window = makeWindow()
    let contentView = try XCTUnwrap(window.contentView)
    let subviewCountBefore = contentView.subviews.count

    WindowCoordinator().configure(window)

    XCTAssertEqual(contentView.subviews.count, subviewCountBefore)
}
```

- [ ] **Step 6: Run all window tests after deleting the type**

Run:

```bash
swift test --filter ReaderWindowInteractionTests
```

Expected: PASS and no compile reference to `ReaderResizeView` remains.

- [ ] **Step 7: Commit Task 1**

```bash
git add Sources/ReadBook/Window/WindowCoordinator.swift \
        Sources/ReadBook/Window/ReaderResizeView.swift \
        Tests/ReadBookAppTests/ReaderWindowInteractionTests.swift
git commit -m "refactor: restore native reader window chrome"
```

---

### Task 2: Remove custom title dragging from the SwiftUI reader hierarchy

**Files:**
- Modify: `Sources/ReadBook/Reader/ReaderToolbar.swift`
- Modify: `Sources/ReadBook/Reader/ReaderRootView.swift`
- Delete: `Sources/ReadBook/Window/ReaderDragRegion.swift`
- Delete: `Tests/ReadBookAppTests/ReaderDragRegionTests.swift`
- Test: `Tests/ReadBookAppTests/ReaderWindowInteractionTests.swift`

**Interfaces:**
- Consumes: the native titlebar contract produced by Task 1.
- Produces: a reader content hierarchy with no custom drag view and no full-width transparent hit-test surface intended to move the window.

- [ ] **Step 1: Add a failing regression test that the app target no longer defines custom drag behavior**

Add to `ReaderWindowInteractionTests.swift`:

```swift
func testConfiguredContentDoesNotNeedCustomWindowMovement() {
    let window = makeWindow()
    WindowCoordinator().configure(window)

    XCTAssertTrue(window.styleMask.contains(.titled))
    XCTAssertFalse(window.isMovableByWindowBackground)
}
```

Then add a source-level regression check to `Tests/ReadBookAppTests/V015InteractionRegressionTests.swift` using the repository source file fixture pattern already used by that test suite, asserting `ReaderToolbar.swift` does not contain `ReaderDragRegion(`. If that test file has no source-reading helper, add this focused helper inside the test file:

```swift
private func source(_ relativePath: String) throws -> String {
    let testsURL = URL(fileURLWithPath: #filePath)
    let root = testsURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
}
```

And the assertion:

```swift
func testToolbarDoesNotEmbedCustomDragRegion() throws {
    let toolbar = try source("Sources/ReadBook/Reader/ReaderToolbar.swift")
    XCTAssertFalse(toolbar.contains("ReaderDragRegion("))
}
```

- [ ] **Step 2: Run the regression test and verify RED**

Run:

```bash
swift test --filter V015InteractionRegressionTests/testToolbarDoesNotEmbedCustomDragRegion
```

Expected: FAIL because `ReaderToolbar` currently embeds `ReaderDragRegion()`.

- [ ] **Step 3: Remove `ReaderDragRegion` from `ReaderToolbar`**

Replace the title `ZStack` with a display-only title region:

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

Do not attach drag gestures, `NSViewRepresentable`, `performDrag`, `mouseDownCanMoveWindow`, or cursor manipulation to this title content.

- [ ] **Step 4: Keep hover reveal out of the native titlebar**

Do not convert the window to `.fullSizeContentView`. Keep the existing `ReaderRootView` top hover zone inside the SwiftUI content area only:

```swift
Color.clear
    .frame(height: 20)
    .contentShape(Rectangle())
    .onHover { runtime.chrome.topZoneChanged(inside: $0) }
```

Verify no code moves this zone into an AppKit titlebar accessory or adds a full-window event monitor. No production change to `ReaderRootView.swift` is required if the hierarchy remains content-only after Task 1; if implementation shows a hit-test modifier explicitly extending beyond content bounds, remove only that modifier.

- [ ] **Step 5: Delete the retired drag implementation and tests**

Delete:

```text
Sources/ReadBook/Window/ReaderDragRegion.swift
Tests/ReadBookAppTests/ReaderDragRegionTests.swift
```

- [ ] **Step 6: Run targeted interaction tests**

Run:

```bash
swift test --filter ReaderWindowInteractionTests
swift test --filter V015InteractionRegressionTests
```

Expected: PASS with no custom drag type compiled into the app target.

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

### Task 3: Replace virtual continuous scrolling with a whole-document native text view

**Files:**
- Modify: `Tests/ReadBookAppTests/ContinuousTextViewTests.swift`
- Modify: `Sources/ReadBook/Reader/ContinuousTextView.swift`
- Keep but remove from production path: any `VirtualTextWindowPlanner` implementation and its isolated core tests.

**Interfaces:**
- Consumes: `ContinuousTextView(bookID:text:anchor:style:textColor:onPositionChanged:)` unchanged at the SwiftUI boundary.
- Produces: `ContinuousTextView.Coordinator.update(bookID:text:anchor:style:textColor:)`, a native `NSScrollView` whose document view contains the complete book and whose viewport remains under AppKit control during user scrolling.

- [ ] **Step 1: Replace the bounded-window test with a failing whole-document test**

Replace `testCoordinatorRendersOnlyBoundedWindowForLargeBook` with:

```swift
@MainActor
func testCoordinatorRendersWholeDocumentAndCreatesScrollableHeight() throws {
    let paragraph = String(repeating: "女巫种田正文", count: 40) + "\n"
    let text = String(repeating: paragraph, count: 400)
    let (scrollView, textView, coordinator) = makeReader(text: text)

    coordinator.update(
        bookID: UUID(),
        text: text,
        anchor: BookPosition(utf16Offset: 0),
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
```

Add the helper:

```swift
@MainActor
private func makeReader(
    text: String,
    onPositionChanged: @escaping (BookPosition) -> Void = { _ in }
) -> (NSScrollView, NSTextView, ContinuousTextView.Coordinator) {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 260))
    let textView = NSTextView(frame: scrollView.contentView.bounds)
    let coordinator = ContinuousTextView.Coordinator(onPositionChanged: onPositionChanged)
    scrollView.documentView = textView
    coordinator.attach(scrollView: scrollView, textView: textView)
    return (scrollView, textView, coordinator)
}
```

- [ ] **Step 2: Run the whole-document test and verify RED**

Run:

```bash
swift test --filter ContinuousTextViewTests/testCoordinatorRendersWholeDocumentAndCreatesScrollableHeight
```

Expected: FAIL because current production code renders only a bounded virtual text window.

- [ ] **Step 3: Simplify `ContinuousTextView` state to whole-document ownership**

Remove production dependencies on:

```swift
VirtualTextWindowPlanner
VirtualTextWindow
currentWindow
recenterScheduled
scheduleRecenteringIfNeeded
loadWindow(centeredAt:restoreGlobalOffset:)
```

Keep coordinator state focused on source identity and feedback control:

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

- [ ] **Step 4: Configure the native scroll/text stack in `makeNSView`**

Use the existing `NSScrollView` and `NSTextView`, but make the whole-document sizing contract explicit:

```swift
let scrollView = NSScrollView(frame: .zero)
scrollView.hasVerticalScroller = false
scrollView.hasHorizontalScroller = false
scrollView.drawsBackground = false
scrollView.contentView.postsBoundsChangedNotifications = true

let textView = NSTextView(frame: scrollView.contentView.bounds)
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

Do not override `scrollWheel(with:)`; native `NSScrollView` must receive vertical input directly.

- [ ] **Step 5: Render the complete attributed document**

Implement a focused method with this behavior:

```swift
private func renderDocument(restoringGlobalOffset offset: Int) {
    guard let style = currentStyle,
          let textColor = currentColor,
          let textView else { return }

    let engine = PaginationEngine()
    let attributed = NSMutableAttributedString(
        attributedString: engine.attributedString(sourceText, style: style)
    )
    attributed.addAttribute(
        .foregroundColor,
        value: textColor,
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

Clamp `offset` against `(sourceText as NSString).length` before using it.

- [ ] **Step 6: Run the whole-document test and verify GREEN**

Run:

```bash
swift test --filter ContinuousTextViewTests/testCoordinatorRendersWholeDocumentAndCreatesScrollableHeight
```

Expected: PASS.

- [ ] **Step 7: Commit Task 3**

```bash
git add Sources/ReadBook/Reader/ContinuousTextView.swift \
        Tests/ReadBookAppTests/ContinuousTextViewTests.swift
git commit -m "refactor: use native whole-document scrolling"
```

---

### Task 4: Prove native vertical scrolling and prevent model feedback snap-back

**Files:**
- Modify: `Tests/ReadBookAppTests/ContinuousTextViewTests.swift`
- Modify: `Sources/ReadBook/Reader/ContinuousTextView.swift`

**Interfaces:**
- Consumes: the whole-document `NSScrollView`/`NSTextView` from Task 3.
- Produces: debounced `onPositionChanged(BookPosition)` reports for user-driven viewport movement and an external-anchor policy that ignores the coordinator's own last reported offset.

- [ ] **Step 1: Add a failing test that the native clip view can advance and report a later offset**

Add:

```swift
@MainActor
func testNativeVerticalScrollAdvancesViewportAndReportsPosition() throws {
    let paragraph = String(repeating: "滚动正文", count: 80) + "\n"
    let text = String(repeating: paragraph, count: 500)
    var reported: BookPosition?
    let (scrollView, textView, coordinator) = makeReader(text: text) {
        reported = $0
    }

    coordinator.update(
        bookID: UUID(),
        text: text,
        anchor: BookPosition(utf16Offset: 0),
        style: .default,
        textColor: .textColor
    )
    textView.layoutManager?.ensureLayout(for: try XCTUnwrap(textView.textContainer))
    textView.sizeToFit()

    let startY = scrollView.contentView.bounds.minY
    scrollView.contentView.scroll(to: NSPoint(x: 0, y: min(startY + 180, textView.frame.height - 1)))
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

This uses the native `NSClipView` scroll path in CI instead of testing only a helper method.

- [ ] **Step 2: Add a failing snap-back regression test**

Add:

```swift
@MainActor
func testFeedingReportedPositionBackDoesNotSnapViewport() throws {
    let paragraph = String(repeating: "反馈回路正文", count: 80) + "\n"
    let text = String(repeating: paragraph, count: 500)
    var reported = BookPosition(utf16Offset: 0)
    let bookID = UUID()
    let (scrollView, textView, coordinator) = makeReader(text: text) {
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

    let yAfterUserScroll = scrollView.contentView.bounds.minY
    XCTAssertGreaterThan(reported.utf16Offset, 0)

    coordinator.update(
        bookID: bookID,
        text: text,
        anchor: reported,
        style: .default,
        textColor: .textColor
    )

    XCTAssertEqual(scrollView.contentView.bounds.minY, yAfterUserScroll, accuracy: 1.0)
}
```

- [ ] **Step 3: Run both tests and verify RED where feedback behavior is still wrong**

Run:

```bash
swift test --filter ContinuousTextViewTests/testNativeVerticalScrollAdvancesViewportAndReportsPosition
swift test --filter ContinuousTextViewTests/testFeedingReportedPositionBackDoesNotSnapViewport
```

Expected before the feedback fix: at least the report/snap-back contract fails.

- [ ] **Step 4: Debounce visible-position reports**

Change the bounds notification callback to schedule a short report rather than synchronously mutating the model on every pixel:

```swift
private func schedulePositionReport() {
    reportWorkItem?.cancel()
    let workItem = DispatchWorkItem { [weak self] in
        self?.reportTopVisiblePosition()
    }
    reportWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: workItem)
}
```

In `attach`, call `schedulePositionReport()` from the bounds-change observer. In `detach`, cancel `reportWorkItem` and remove the observer.

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

In `update(...)`, distinguish the coordinator's own report from a true external navigation:

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

`scrollTo(globalOffset:)` records `lastAppliedExternalAnchor = clampedAnchor` after changing the clip view.

- [ ] **Step 6: Run the continuous-reader tests and verify GREEN**

Run:

```bash
swift test --filter ContinuousTextViewTests
```

Expected: PASS, including whole-document rendering, position advancement, and no snap-back when the reported position is fed back through `update`.

- [ ] **Step 7: Commit Task 4**

```bash
git add Sources/ReadBook/Reader/ContinuousTextView.swift \
        Tests/ReadBookAppTests/ContinuousTextViewTests.swift
git commit -m "fix: keep native scroll viewport authoritative"
```

---

### Task 5: Verify mode handoff and saved-position restoration

**Files:**
- Modify: `Tests/ReadBookAppTests/ContinuousTextViewTests.swift`
- Inspect and modify only if needed: `Sources/ReadBook/App/AppModel.swift`
- Inspect and modify only if needed: `Sources/ReadBook/Reader/ReaderRootView.swift`

**Interfaces:**
- Consumes: existing `AppModel.position`, `AppModel.setMode(_:)`, and `ContinuousTextView` anchor input.
- Produces: continuous mode applies a genuinely external saved anchor once; switching modes does not reset the model's shared `BookPosition`.

- [ ] **Step 1: Add a failing external-anchor restoration test**

Add:

```swift
@MainActor
func testExternalSavedAnchorMovesViewportOnce() throws {
    let paragraph = String(repeating: "恢复位置正文", count: 80) + "\n"
    let text = String(repeating: paragraph, count: 500)
    let target = (text as NSString).length / 2
    let bookID = UUID()
    let (scrollView, textView, coordinator) = makeReader(text: text)

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

- [ ] **Step 2: Run the focused restoration test and verify RED if anchor handling is incomplete**

Run:

```bash
swift test --filter ContinuousTextViewTests/testExternalSavedAnchorMovesViewportOnce
```

Expected: FAIL until external anchors are reliably applied after layout; if Task 4 already makes it pass, record that this acceptance criterion is already covered and do not add redundant production code.

- [ ] **Step 3: If needed, defer one external anchor application until TextKit layout is ready**

Only if Step 2 proves necessary, use a single main-queue retry, not an open-ended loop:

```swift
private func applyExternalAnchorWhenLayoutIsReady(_ offset: Int) {
    guard let textView, textView.layoutManager != nil else { return }

    textView.layoutManager?.ensureLayout(for: textView.textContainer!)
    scrollTo(globalOffset: offset)

    if scrollView?.contentView.bounds.minY == 0, offset > 0 {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.textView?.layoutManager?.ensureLayout(for: self.textView!.textContainer!)
            self.scrollTo(globalOffset: offset)
        }
    }
}
```

Do not add repeated timers or polling.

- [ ] **Step 4: Confirm `AppModel.setMode(_:)` preserves `session.position`**

Run the existing test suite first:

```bash
swift test
```

Inspect `AppModel.setMode(_:)`. The intended implementation remains:

```swift
func setMode(_ mode: ReadingMode) {
    preferences.readingMode = mode
    session.setReadingMode(mode)
    sessionRevision &+= 1
    persistPreferences()
}
```

Do not reset `session.position`. Only change this method if an existing or newly added session test demonstrates position loss.

- [ ] **Step 5: Run all tests and verify mode/position compatibility**

Run:

```bash
swift test
```

Expected: PASS. Existing session/repository tests continue to prove stored position persistence; the new continuous-reader test proves a saved external anchor is visually applied.

- [ ] **Step 6: Commit Task 5 only if code/tests changed**

```bash
git add Sources/ReadBook/App/AppModel.swift \
        Sources/ReadBook/Reader/ReaderRootView.swift \
        Sources/ReadBook/Reader/ContinuousTextView.swift \
        Tests/ReadBookAppTests/ContinuousTextViewTests.swift
git commit -m "test: cover continuous reader position restoration"
```

If no files changed because the criterion already passes, do not create an empty commit.

---

### Task 6: Full regression verification and release-candidate packaging

**Files:**
- Modify: `Scripts/build-app.sh`
- Modify: `.github/workflows/bootstrap-readbook.yml`
- Create: `docs/superpowers/verification/2026-08-31-v0.1.9-interaction-smoke.md`

**Interfaces:**
- Consumes: all production behavior from Tasks 1–5.
- Produces: a versioned PR artifact suitable for packaged-app smoke testing; main remains unchanged until smoke approval.

- [ ] **Step 1: Run the full local/CI-equivalent verification before versioning**

Run:

```bash
swift test
swift build
Scripts/build-app.sh
codesign --verify --deep --strict --verbose=4 dist/ReadBook.app
```

Expected: all commands exit 0.

- [ ] **Step 2: Bump the package version to v0.1.9 / next build**

In `Scripts/build-app.sh`, change the defaults from v0.1.8/build 9 to:

```bash
APP_VERSION="${APP_VERSION:-0.1.9}"
APP_BUILD="${APP_BUILD:-10}"
```

If GitHub already contains release/tag `v0.1.9`, choose the next unused patch version and increment the build number again.

- [ ] **Step 3: Update release notes to describe the architecture change accurately**

Replace the current title-drag patch notes in `.github/workflows/bootstrap-readbook.yml` with notes equivalent to:

```text
ReadBook v0.1.9 原生窗口与滚动重构。

- 恢复 macOS 原生标题栏拖动能力，标题栏视觉透明，继续保持纯净阅读外观
- 使用 macOS 原生窗口边缘/角落缩放，移除自制 resize overlay
- 连续阅读改为原生 NSScrollView + NSTextView 整本滚动，不再经过虚拟文本窗口 recenter 链路
- 修复滚动位置写回后反向驱动 viewport 的反馈回路，避免滚动后回弹
- 保留隐藏滚动条、主题、字体/颜色、分页模式、老板模式与阅读进度
- 增加窗口配置、真实 clip-view 位移和 scroll feedback 回归测试

说明：当前仍为 ad-hoc 签名，未使用 Apple Developer ID/notarization。
```

- [ ] **Step 4: Create a smoke-verification record with explicit pending manual checks**

Create `docs/superpowers/verification/2026-08-31-v0.1.9-interaction-smoke.md`:

```markdown
# ReadBook v0.1.9 interaction smoke verification

## Automated
- [ ] `swift test`
- [ ] `swift build`
- [ ] app bundle packaging
- [ ] codesign verification
- [ ] PR macOS CI

## Packaged app behavior
- [ ] Drag the reader from the invisible native top titlebar area; window moves.
- [ ] Resize from one edge and one corner; window resizes with native macOS behavior.
- [ ] Switch to continuous mode and vertically scroll at least three screens.
- [ ] Stop scrolling for at least two seconds; viewport does not snap backward.
- [ ] Switch paginated -> continuous -> paginated; reading location remains near the same text.
- [ ] Close/reopen the reader or reopen the book; saved position is restored.
- [ ] No title text, traffic-light buttons, gray system titlebar, or visible scroll bar is shown.
- [ ] Existing card/frameless/transparent appearance remains visually acceptable.

## Release gate
Do not merge the release PR to `main` until every packaged-app behavior checkbox above has been verified against the PR artifact. CI alone is not sufficient evidence for pointer/trackpad behavior.
```

- [ ] **Step 5: Commit release-candidate metadata**

```bash
git add Scripts/build-app.sh \
        .github/workflows/bootstrap-readbook.yml \
        docs/superpowers/verification/2026-08-31-v0.1.9-interaction-smoke.md
git commit -m "chore: prepare v0.1.9 native interaction candidate"
```

- [ ] **Step 6: Push/open a PR and wait for macOS CI**

Open the implementation PR against `main`. Required PR CI:

```text
Test: success
Build: success
Package local app bundle: success
Verify packaged app signature: success
Verify branding: success
Create archive and checksum: success
Upload installable preview: success
```

Do not merge yet.

- [ ] **Step 7: Obtain the exact PR artifact and perform the packaged-app smoke gate**

Use the workflow artifact named:

```text
ReadBook-v<version>-<PR-head-sha>
```

Verify its `.sha256`, unzip it, and exercise every packaged-app behavior checkbox from the smoke record. Record the exact PR head SHA and artifact checksum in the verification document.

If the execution environment cannot physically exercise macOS pointer/trackpad interaction, hand the exact verified PR artifact to the user and wait for the user's smoke result before checking those boxes or merging.

- [ ] **Step 8: Commit the completed smoke record**

After actual verification, update the checkboxes and append:

```markdown
## Verified candidate
- PR head SHA: `<exact sha>`
- Artifact SHA-256: `<exact digest>`
- Smoke result: PASS
```

Commit:

```bash
git add docs/superpowers/verification/2026-08-31-v0.1.9-interaction-smoke.md
git commit -m "test: record v0.1.9 packaged interaction smoke"
```

- [ ] **Step 9: Re-run PR CI after the smoke-record commit**

Expected: full PR macOS CI PASS again on the final head SHA.

- [ ] **Step 10: Commit Task 6 is complete only after the final PR head is GREEN and smoke is PASS**

No additional code change is made in this step. The deliverable is the verified release-candidate branch.

---

### Task 7: Review, merge, and verify immutable release

**Files:**
- No production files unless review finds a defect.

**Interfaces:**
- Consumes: final GREEN + smoke-PASS PR head from Task 6.
- Produces: merged `main` and immutable GitHub release `v0.1.9` (or the chosen unused version).

- [ ] **Step 1: Review the final PR diff for architectural regressions**

Confirm the final patch contains no:

```text
ReaderDragRegion
ReaderDragView
ReaderResizeView
window.styleMask.remove(.titled)
.fullSizeContentView
NSEvent.addGlobalMonitorForEvents
NSEvent.addLocalMonitorForEvents
```

Also confirm `ContinuousTextView` has no production reference to `VirtualTextWindowPlanner` or recenter scheduling.

- [ ] **Step 2: Run/fetch final verification for the exact PR head SHA**

Required evidence for the exact merge candidate:

```text
swift test: PASS
swift build: PASS
packaging: PASS
codesign verify: PASS
checksum creation/verification: PASS
packaged-app smoke: PASS
```

- [ ] **Step 3: Merge only the exact verified head**

Use the PR head SHA as the expected-head guard when merging. Do not merge if the branch changed after the smoke gate without re-running verification.

- [ ] **Step 4: Verify main CI publish job**

After merge, require both jobs to complete successfully:

```text
test-build-package: success
publish: success
```

- [ ] **Step 5: Verify the GitHub release and assets**

Fetch the release tag and confirm:

```text
release tag = v0.1.9 (or chosen unused version)
ReadBook-macOS.zip exists
ReadBook-macOS.zip.sha256 exists
release target = merged main commit
```

Reconcile the published ZIP digest with the checksum asset.

- [ ] **Step 6: Report completion with evidence, not assumptions**

The completion report must include:

```text
version/build
merge commit SHA
main CI result
release URL
published ZIP SHA-256
packaged smoke result
```

Do not claim window dragging or scrolling is fixed unless the packaged-app smoke gate has actually passed.

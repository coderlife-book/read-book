# ReadBook native window and continuous-scroll redesign

Date: 2026-08-31
Status: approved direction, pending implementation plan
Target release: v0.1.9

## Context

ReadBook has shipped several interaction fixes, but two core behaviors remain unreliable in the packaged app:

1. Dragging the window from the title area does not reliably move the window.
2. Continuous reading mode does not reliably scroll even though the existing unit tests pass.

The common problem is architectural rather than a missing event handler. The current reader removes the native titled-window behavior and reconstructs drag/resize hit regions inside the content hierarchy. Continuous scrolling also uses a virtual text window with position write-back and programmatic re-anchoring, creating an event feedback loop between AppKit, SwiftUI, and the model.

The redesign prioritizes observable user behavior and reliability over premature optimization.

## Goals

- Preserve the current clean, widget-like reader appearance.
- Restore window dragging using AppKit-owned window chrome instead of a SwiftUI drag overlay.
- Use native AppKit resizing instead of custom edge/corner resize hit zones.
- Make continuous mode a conventional native vertical scroll view that responds directly to mouse wheels and trackpads.
- Preserve reading position when switching modes, reopening the reader, and reopening a book.
- Keep scroll bars visually hidden while retaining native scrolling behavior.
- Keep existing themes, text color, font, line spacing, paragraph spacing, always-on-top behavior, boss mode, library popover, and settings.
- Add regression coverage that exercises end-user outcomes rather than only helper methods.

## Non-goals

- Do not add cloud sync or Supabase in this change.
- Do not redesign the library or settings UI.
- Do not add chapter parsing or EPUB support.
- Do not optimize for extremely large multi-hundred-megabyte TXT files in this release.
- Do not introduce global keyboard or mouse event monitors.

## Chosen architecture

### 1. Native titled NSWindow with visually hidden chrome

The reader window will retain AppKit's native titled-window capability instead of removing `.titled`.

The window will use these native capabilities:

- `.titled`
- `.resizable`
- `.closable`
- `.fullSizeContentView` when needed to keep the content visually edge-to-edge
- `titleVisibility = .hidden`
- `titlebarAppearsTransparent = true`
- hidden standard red/yellow/green window buttons
- transparent/clear window background where required by the existing card/frameless/transparent appearances

The titlebar will remain owned by AppKit. ReadBook will not place a full-width custom drag view over the SwiftUI content.

The visible result must remain a clean reading card: no visible system title, no traffic-light buttons, no permanent toolbar strip, and no traditional gray titlebar.

Toolbar controls may still appear on hover, but they must occupy explicit control hit regions. The remaining titlebar background must stay available to AppKit as draggable chrome.

### 2. Remove custom drag and resize overlays

The following interaction mechanisms are retired from the main reader window:

- `ReaderDragRegion`
- `ReaderDragView`
- custom title `performDrag` handling inside the SwiftUI hierarchy
- `ReaderResizeView` edge/corner hit zones

Window movement and resizing will be delegated to native `NSWindow` behavior.

This eliminates competing hit-testing layers between SwiftUI, NSTextView, hover zones, toolbar overlays, and custom AppKit views.

### 3. Native continuous reader

Continuous mode will use a standard AppKit text stack:

- `NSScrollView`
- `NSTextView`
- `NSTextStorage`
- TextKit layout

The complete book text will be assigned to the text view for this release. `allowsNonContiguousLayout` will remain enabled so TextKit can avoid eagerly laying out all glyphs.

The scroll view will:

- allow vertical scrolling
- suppress visible vertical and horizontal scrollers
- use a transparent background
- not intercept horizontal paging gestures because continuous mode owns vertical scrolling only

The current `VirtualTextWindowPlanner` recentering path will not participate in continuous reading in v0.1.9. It may remain in the repository temporarily if still referenced by tests or future experiments, but it will not sit on the production scroll path.

### 4. One-way position synchronization during user scrolling

The current feedback risk is:

`scroll -> visible offset -> model position -> SwiftUI update -> programmatic scroll -> bounds notification -> model position`

The redesign establishes a strict ownership rule:

- On initial load, book change, mode change, or explicit navigation, the model may provide an anchor that is applied once to the native text view.
- During normal user scrolling, the native scroll view owns the viewport.
- Visible-position updates are reported back to the model on a throttled/debounced basis, but those same reported offsets must not cause the view to scroll again.
- A programmatic anchor is applied only when the coordinator can distinguish it from the last position it reported itself.

This keeps persistence while preventing scroll feedback or snapping.

### 5. Pagination remains separate

Paginated mode remains independent from continuous mode.

Its existing page layout and previous/next navigation can stay unless implementation work reveals a direct conflict with the new window chrome. Switching between pagination and continuous mode will use the same persisted `BookPosition` as the handoff point.

## Visual behavior

The target appearance is the same clean card demonstrated by the current reader:

- rounded card or configured frameless/transparent appearance
- background and text colors unchanged
- no visible titlebar
- no visible system window buttons
- no visible scroll bar
- content visually fills the card
- top controls remain transient/hover-driven

The native titlebar is an implementation detail, not a visible design element.

## Event and data flow

### Window dragging

1. Pointer presses an uncovered portion of the native titlebar region.
2. AppKit performs standard window movement.
3. SwiftUI receives no synthetic drag gesture and does not own the drag lifecycle.

### Window resizing

1. Pointer reaches a native resizable edge/corner.
2. AppKit displays the standard resize cursor and performs native resize tracking.
3. Reader layout receives the new size through the normal window/content layout pass.

### Continuous scrolling

1. Mouse wheel or trackpad event reaches `NSScrollView`.
2. `NSClipView.bounds.origin.y` changes natively.
3. The coordinator computes the top visible character offset.
4. The offset is reported to `AppModel` for persistence.
5. The SwiftUI/model update does not re-apply the same offset to the scroll view.

## Component changes

Expected production files include:

- `Sources/ReadBook/Window/WindowCoordinator.swift`
  - restore and configure native titlebar behavior
  - remove custom resize hit-zone installation

- `Sources/ReadBook/Reader/ReaderToolbar.swift`
  - remove `ReaderDragRegion`
  - ensure toolbar controls have bounded hit regions and do not cover the full native drag surface

- `Sources/ReadBook/Reader/ReaderRootView.swift`
  - remove or reposition transparent top hover hit-testing that can block native titlebar interaction
  - preserve transient toolbar reveal behavior without covering draggable chrome

- `Sources/ReadBook/Reader/ContinuousTextView.swift`
  - simplify to a normal whole-document `NSScrollView` / `NSTextView`
  - remove virtual-window recentering from the production path
  - implement one-way user-scroll position reporting

Expected removals or retirement:

- `Sources/ReadBook/Window/ReaderDragRegion.swift`
- custom resize overlay installation and its production dependency

Existing pagination files should remain mostly unchanged.

## Testing strategy

### Automated window configuration tests

Tests must verify the configured reader window actually retains native behavior:

- `.titled` is present after configuration
- `.resizable` is present
- title is visually hidden
- titlebar is transparent
- standard window buttons are hidden
- custom `ReaderResizeView` is not installed
- `ReaderDragView` is not part of the reader hierarchy

These tests guard against accidentally returning to the borderless/custom-overlay architecture.

### Automated continuous-scroll integration tests

Create a real `NSScrollView`/`NSTextView` with enough content to exceed the viewport, then verify observable behavior:

- document height is larger than viewport height
- vertical scrolling is enabled even with the scroller visually hidden
- sending a vertical wheel event through the scroll view changes the clip view's Y origin, or, where direct event synthesis is unstable in CI, invoking the same native scroll path changes the clip view bounds and triggers position reporting
- the reported top-visible offset advances after scrolling
- feeding that reported offset back through `updateNSView` does not snap the clip view back
- switching to continuous mode at a saved offset applies the initial anchor once
- reopening the same book restores its position

### Regression tests

Existing tests for font styling, text color, pagination, boss mode, window persistence, and packaging remain required.

### Release smoke gate

CI success alone is not sufficient for this interaction release. Before publishing v0.1.9, the packaged `.app` must be exercised as an app-level smoke test for these exact behaviors:

1. Drag the window by the top non-control area.
2. Resize from at least one edge and one corner.
3. Switch to continuous mode and scroll several screens with vertical input.
4. Stop scrolling and confirm the viewport does not snap back.
5. Switch paginated -> continuous -> paginated and confirm the reading location stays close to the same text.
6. Confirm the titlebar and traffic-light buttons remain invisible.
7. Confirm the clean card appearance remains intact.

If an automated runner cannot faithfully synthesize macOS pointer dragging or trackpad input, the release notes and verification record must explicitly distinguish automated coverage from the required packaged-app smoke verification instead of claiming those interactions were proven by unit tests.

## Migration and compatibility

No data migration is required.

Existing persisted books, positions, themes, text colors, window settings, and reading mode preferences remain compatible.

Window frame autosave remains `ReadBook.ReaderWindow` unless testing shows the restored native titlebar changes frame interpretation enough to require a one-time frame revalidation.

## Performance trade-off

The redesign intentionally prefers a whole-document text view over the current virtual text window for continuous reading.

For ordinary web-novel TXT files, this is expected to be acceptable on modern Macs, especially with non-contiguous TextKit layout. Reliability is the release priority.

If profiling later shows unacceptable memory or startup cost for very large TXT files, virtualization will be revisited as a separate performance project with explicit scroll-behavior tests. It will not be reintroduced into v0.1.9 merely as a precaution.

## Failure handling

- Empty text produces an empty, scrollable reader without crashing.
- Invalid saved offsets are clamped to the document length.
- Programmatic anchor application must tolerate layout not being ready on the first pass and defer once to the next main-loop turn if necessary.
- Scroll-position persistence failures must not block scrolling.

## Acceptance criteria

The redesign is accepted only when all of the following are true:

- The reader can be moved by dragging the native top drag surface in the packaged app.
- The reader can be resized using native macOS edge/corner behavior.
- Continuous mode visibly scrolls with standard vertical mouse-wheel/trackpad input.
- Continuous scrolling does not snap back because of model feedback.
- Reading position survives mode switches and reopening.
- The user-facing window still looks like the clean card reader, not a conventional titled macOS window.
- No custom full-width drag overlay is present.
- No custom resize hit-zone overlay is present.
- No global keyboard or mouse event monitor is introduced.
- Automated regression tests pass and the packaged-app interaction smoke gate is recorded before release.

## Release scope

This work will ship as the next version after v0.1.8, expected to be v0.1.9 unless another release consumes that version first. If so, the build/version number will be bumped before publishing without changing this design.

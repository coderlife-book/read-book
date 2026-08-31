# ReadBook macOS Reader — Design Specification

Date: 2026-08-31
Status: Approved design
Target: Personal-use macOS desktop novel reader
Repository: `coderlife-book/read-book`

## 1. Product Goal

Build a native macOS reading app that visually behaves like a desktop widget while retaining the freedom of a normal app. The primary use case is importing local `.txt` novels and reading them comfortably in a small always-available desktop card.

The app must optimize for simplicity, low maintenance, fast launch, reliable local persistence, and comfortable long-form Chinese text reading.

The first release is intentionally local-only. It has no account system, no backend, no network dependency, and no cloud synchronization.

## 2. Platform and Technology

- Language: Swift
- UI: SwiftUI
- Native window and application behavior: AppKit / `NSWindow` / `NSApplication`
- Text layout and pagination: TextKit
- Persistence: JSON + `FileManager` + `UserDefaults`
- Minimum supported OS: macOS 26
- Primary test hardware: Apple Silicon MacBook Pro, Apple M3 Pro class hardware
- Backend: none
- Network: none

SwiftUI is the default UI layer. AppKit is used where SwiftUI does not provide sufficiently precise control, especially for window behavior, activation policy, and pagination/text measurement.

## 3. Product Shape

ReadBook is not a WidgetKit widget in V1. It is a native desktop application whose main window looks and behaves like a macOS widget.

Default window characteristics:

- Approximately 360 x 260 pt
- Minimum size approximately 280 x 180 pt
- Rounded corners
- No traditional title bar or toolbar chrome
- Light native shadow
- Draggable and resizable
- Controls remain visually minimal when the pointer is outside the reader
- Reading controls appear when the pointer enters the window

The window supports two user-selectable modes:

1. Desktop mode: behaves like a normal desktop window and may be covered by other apps.
2. Always-on-top mode: raises the reader to a floating window level.

## 4. Application Presence

The user can manually switch between two application-presence modes:

### Widget-style mode

- Dock icon hidden
- Menu bar item remains available
- Reader can be shown or hidden from the menu bar

### Normal app mode

- Dock icon visible
- App behaves as a normal macOS application

The implementation may switch `NSApplication.ActivationPolicy` between `.accessory` and `.regular` as appropriate.

The default mode is widget-style mode.

## 5. Core Reading Modes

ReadBook supports two manual reading modes. The user explicitly switches modes; gestures do not automatically change the reading mode.

### 5.1 Paginated mode

Paginated mode is the primary reading mode.

Supported interactions:

- Click left reading region: previous page
- Click right reading region: next page
- Left/right arrow keys
- Trackpad horizontal page gesture when practical and non-conflicting
- Pointer-hover previous/next controls

Pagination is layout-aware. A page is determined by actual available text container size, font, font size, line spacing, paragraph spacing, and padding. Fixed character-count pagination is explicitly prohibited.

### 5.2 Continuous scrolling mode

Continuous scrolling mode presents the novel as vertically continuous text.

Supported interactions:

- Trackpad scrolling
- Mouse wheel
- Up/down arrow keys
- Page Up / Page Down

The implementation must not require opening one chapter at a time. The reader should behave as a continuous document.

## 6. Unified Reading Position

Both reading modes share a single canonical reading coordinate.

```swift
struct BookPosition {
    var utf16Offset: Int
}
```

The canonical position is a UTF-16 offset into the normalized book text.

Reasons:

- TextKit and `NSRange` naturally use UTF-16 indexing.
- Window resizing does not invalidate the reading position.
- Font changes do not invalidate the reading position.
- Pagination changes do not invalidate the reading position.
- Paginated and scrolling modes can map to the same logical location.

The app must not persist a page number as the authoritative reading position.

When switching reading modes, the destination view should anchor at or as close as possible to the same `utf16Offset`.

## 7. Local Library

ReadBook supports multiple imported books and a lightweight recent-reading library.

Import semantics are copy-based: an imported `.txt` file is copied into the application's own local library. The source file may later be moved or deleted without breaking the imported book.

Recommended storage location:

```text
~/Library/Application Support/ReadBook/
├── library.json
├── Books/
│   ├── <book-id>/
│   │   ├── content.txt
│   │   └── metadata.json
│   └── ...
└── Cache/
```

All imported book content is normalized to UTF-8 during import. Encoding complexity must be resolved once, at import time, rather than propagated through the reading pipeline.

### 7.1 Library metadata

`library.json` stores lightweight book index data such as:

- Book ID
- Display title
- Import time
- Last-read time
- Reading progress
- Current `utf16Offset`
- Total UTF-16 length or equivalent normalized length
- Chapter count

Per-book metadata may additionally store chapter index and source import metadata.

## 8. TXT Import Pipeline

Import is available through:

- `Command + O`
- Drag and drop into the reader window
- Menu bar command
- Recent-books/library UI

Import pipeline:

1. Select or receive `.txt` file.
2. Detect text encoding.
3. Decode text.
4. Normalize line endings.
5. Normalize output to UTF-8.
6. Copy normalized content into the ReadBook local library.
7. Detect chapters.
8. Build metadata and chapter index.
9. Open the imported book immediately.

Encoding support should prioritize common Chinese novel sources:

- UTF-8
- UTF-8 BOM
- UTF-16
- GB18030 / GBK-compatible input
- Big5

If automatic detection is unreliable, the app must fail visibly rather than silently storing garbled text. A manual encoding override flow may be shown for failed imports.

## 9. Chapter Detection and Navigation

The app automatically recognizes common Chinese chapter headings, including representative forms such as:

- `第一章 ...`
- `第1章 ...`
- `第一百二十三章 ...`
- `第 502 章 ...`
- `第502回 ...`
- `第一卷 ...`
- `卷一 ...`
- `序章`
- `楔子`
- `番外`
- `后记`

Detected chapters are represented as:

```swift
struct Chapter {
    var title: String
    var utf16Offset: Int
}
```

Chapter scanning occurs during import and is persisted. Opening the table of contents must not rescan the entire novel.

The chapter panel supports:

- Chapter list
- Current-chapter indication
- Direct chapter jump
- Chapter-title search

Full-text search is out of scope for V1.

## 10. Reader UI

When idle, the main reader should primarily show text, with minimal persistent chrome.

Pointer entry reveals lightweight controls such as:

- Library / table of contents
- Current book title
- Reading-mode switch
- Pin / always-on-top control
- More/settings control
- Previous/next page affordances in paginated mode
- Current chapter and progress indicator

Controls must not consume a large permanent toolbar region.

### 10.1 Typography defaults

Recommended initial defaults:

- Font: PingFang SC
- Font size: approximately 17 pt
- Line spacing: approximately 8 pt
- Paragraph spacing: approximately 8–10 pt
- Horizontal padding: approximately 22 pt
- Vertical padding: approximately 20 pt

The reader respects the source text's paragraph/newline structure. It does not forcibly insert first-line indentation.

User-adjustable typography in V1:

- Font size
- Line spacing
- Font family

Initial font choices:

- PingFang SC
- Songti SC
- STKaiti
- System font

## 11. Themes

V1 includes three reading themes:

1. Soft — warm off-white background with dark gray text; default theme.
2. Light — near-white background with dark text.
3. Dark — dark gray background with light gray text.

Fully transparent reader backgrounds are out of scope for V1 because desktop wallpaper contrast can significantly reduce readability.

## 12. Recent Reading and Lightweight Library UI

The app does not include a large bookstore-style library screen in V1.

The lightweight library/recent-reading popover provides:

- Recent books
- Reading progress
- Current/last-read book
- Import TXT action
- Book switch
- Rename action
- Remove-from-library action

Removing a book deletes the ReadBook-managed local copy after user confirmation where appropriate.

## 13. Menu Bar

A menu bar item remains available in widget-style app mode.

Menu bar actions include:

- Show/hide reader
- Recent books
- Import TXT
- Settings
- Quit ReadBook

This provides a recovery/entry point when the Dock icon is hidden or the reader window is closed.

## 14. Persistence

Reading position updates are maintained in memory immediately and persisted with debounce to avoid excessive disk writes.

Recommended debounce range: approximately 0.5–1 second after user activity settles.

Persistence must be forced on important lifecycle transitions, including:

- Switching books
- Closing the reader window
- App termination
- Relevant application deactivation/background transitions

Persisted user settings include at least:

- Last-opened book
- Last reading position per book
- Reading mode
- Font family
- Font size
- Line spacing
- Theme
- Reader window size
- Reader window position
- Always-on-top state if desirable
- Dock/widget-style application mode

## 15. Pagination Architecture

Pagination uses TextKit-backed measurement and layout rather than character-count heuristics.

A layout signature concept should identify the parameters that make pagination valid, for example:

```text
book content identity
text container width
text container height
font family
font size
line spacing
paragraph spacing
reader padding
```

For a given layout signature, pagination metadata may map page ranges to UTF-16 ranges.

Example:

```text
Page 1: 0...471
Page 2: 472...947
Page 3: 948...1420
```

Changing a pagination-affecting setting invalidates the corresponding page-layout cache but does not change the canonical `BookPosition`.

After invalidation, the reader identifies the newly laid-out page containing the current `utf16Offset`.

## 16. Performance Strategy

The app must remain responsive for long Chinese novels, including multi-million-character files.

Opening a book must not require eagerly calculating every page before reading begins.

Priority order:

1. Current page or current visible scroll location
2. Next page
3. Previous page
4. Nearby pages
5. Optional incremental background expansion of pagination metadata

Any background pagination/indexing work must be cancellable or safely invalidated if layout settings change.

The UI must remain usable while non-essential pagination work continues.

## 17. Suggested Internal Boundaries

The initial architecture should remain deliberately small.

```text
AppState
├── LibraryStore
├── ReaderSession
├── ReaderSettings
└── WindowState
```

Responsibilities:

### LibraryStore

- Import books
- Manage local files
- Load/save library metadata
- Rename/remove books
- Provide recent-books ordering

### ReaderSession

- Current book
- Current `BookPosition`
- Current reading mode
- Current chapter
- Mode switching
- Reader lifecycle persistence triggers

### ReaderSettings

- Typography
- Theme
- Reading preferences

### WindowState

- Window dimensions and position
- Always-on-top state
- Dock/widget-style application presence state

### Pagination engine

- TextKit-backed text measurement
- Page-range generation
- Layout-signature caching
- Mapping UTF-16 offsets to pages

### Chapter parser

- Parse chapter headings from normalized text
- Persist chapter offsets
- Keep chapter logic independent from UI

These units should expose narrow interfaces and remain independently testable.

## 18. Error Handling

V1 must explicitly handle at least:

- Unsupported or unreadable input file
- Text decoding failure
- Encoding ambiguity that produces invalid output
- Failed library copy/write
- Missing or corrupt local book file
- Corrupt metadata JSON
- Empty TXT file
- No chapters detected

No-chapter detection is not an import failure; the book remains readable without a table of contents.

When metadata is corrupt but book content remains available, recovery should prefer rebuilding derived metadata over losing the book.

## 19. Testing Strategy

The project should include focused tests for logic that is easy to regress.

### Unit tests

- Chapter detection patterns
- UTF-16 position calculations
- Library metadata encode/decode
- Import normalization
- Reading-position persistence
- Layout-signature invalidation
- Pagination range continuity and bounds

### Integration/UI-level checks

- Import UTF-8 Chinese TXT
- Import GBK/GB18030 Chinese TXT
- Reopen last book and restore position
- Switch paginated -> scrolling -> paginated without significant position drift
- Resize window and preserve logical reading location
- Change font size and preserve logical reading location
- Switch books and restore independent positions
- Toggle always-on-top
- Toggle Dock/widget-style mode
- Drag-and-drop import

Performance tests should include a multi-million-character fixture to ensure startup and first-readable-content latency remain acceptable.

## 20. V1 Definition of Done

V1 is complete when all of the following are working reliably:

- Import local TXT through file picker
- Drag-and-drop TXT import
- Common Chinese encodings import without garbling
- Imported files are copied into ReadBook-managed storage
- Multiple books are supported
- Recent-reading list is available
- Per-book progress is persisted
- Automatic chapter recognition is available
- Chapter-title search and chapter jump work
- Paginated reading works
- Click-left / click-right page navigation works
- Keyboard previous/next navigation works
- Continuous vertical scrolling works
- Manual paginated/scrolling mode switching works
- Mode switching preserves logical position
- Font size can be changed
- Line spacing can be changed
- Font family can be changed
- Three reading themes are available
- Window size and position are restored
- Always-on-top can be toggled
- Dock icon visibility mode can be toggled
- Menu bar entry remains available in widget-style mode
- App restart restores the last book and reading position
- Books can be renamed and removed

## 21. Explicitly Out of Scope for V1

Do not add these features unless the scope is deliberately revised later:

- EPUB
- PDF
- MOBI
- Online novel scraping
- Accounts/login
- Backend services
- Supabase
- Cloud synchronization
- iCloud synchronization
- AI summaries
- AI character analysis
- Full-text search
- Notes
- Highlights
- TTS
- Cover management
- Categories/tags
- iPhone/iPad app
- WidgetKit extension
- Store/distribution work beyond what is necessary for local personal use

## 22. Design Principles

1. Reading first: the text is the product; chrome is secondary.
2. Local first: the app remains fully useful offline.
3. Position stability: layout changes must not lose the user's place.
4. Native behavior: prefer standard macOS input, typography, menu, window, and persistence conventions.
5. YAGNI: avoid frameworks and subsystems that do not directly improve the V1 reading workflow.
6. Fast path to reading: after import or launch, readable text appears before non-essential indexing work completes.
7. Recoverability: derived metadata may be rebuilt; imported novel content and reading position should be difficult to lose.

## 23. Future Extension Direction

The architecture should not implement future features now, but it should avoid blocking sensible later extensions such as:

- Full-text search
- TTS
- iCloud/CloudKit progress synchronization
- EPUB support
- Real WidgetKit companion widget

These remain future work and must not complicate V1 implementation unless a concrete V1 requirement depends on them.

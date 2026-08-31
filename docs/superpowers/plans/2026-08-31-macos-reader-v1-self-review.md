# ReadBook V1 Plan Self-Review Corrections

This file is the authoritative self-review companion to `2026-08-31-macos-reader-v1.md`. Executors must read both files. Where this file conflicts with the base plan, this file wins.

The design scope is unchanged. These corrections remove implementation ambiguities found during the required plan self-review.

## 1. Swift 6 Sendable boundaries

In Task 4, `JSONFileStore` must **not** conform to `Sendable`; `JSONEncoder` and `JSONDecoder` are implementation details used inside `LibraryRepository` actor isolation.

Use:

```swift
struct JSONFileStore {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    // same read/write implementation from the base plan
}
```

In Task 5, `PreferencesStore` must **not** conform to `Sendable`; it wraps `UserDefaults` and is consumed from the main-actor `AppModel`.

Use:

```swift
public struct PreferencesStore {
    private let defaults: UserDefaults
    private let key = "readerPreferences.v1"
    // same load/save implementation from the base plan
}
```

Do not silence Swift 6 concurrency errors with broad `@unchecked Sendable` unless a type has its own explicit synchronization. `PageCache` is the only planned type that qualifies because it owns an `NSLock`; see correction 3, which removes it from V1 entirely.

## 2. `library.json` recovery must write the recovered index back

The base Task 4 `loadIndex()` returned an empty index when `library.json` was missing and did not persist recovered state when the file was corrupt. Replace `loadIndex()` and `recoverIndex()` with:

```swift
private func loadIndex() throws -> LibraryIndex {
    if FileManager.default.fileExists(atPath: paths.libraryIndexURL.path),
       let valid = try? json.read(LibraryIndex.self, from: paths.libraryIndexURL) {
        return valid
    }

    let recovered = recoverIndex()
    try json.write(recovered, to: paths.libraryIndexURL)
    return recovered
}

private func recoverIndex() -> LibraryIndex {
    let directories = (try? FileManager.default.contentsOfDirectory(
        at: paths.booksRoot,
        includingPropertiesForKeys: nil
    )) ?? []

    let metadata = directories.compactMap { directory -> BookMetadata? in
        guard let id = UUID(uuidString: directory.lastPathComponent) else { return nil }
        return try? json.read(BookMetadata.self, from: paths.metadataURL(id))
    }
    .sorted { $0.lastReadAt > $1.lastReadAt }

    return LibraryIndex(
        schemaVersion: 1,
        bookIDs: metadata.map(\.id),
        lastOpenedBookID: metadata.first?.id
    )
}
```

This is required for the Task 11 recovery test. Recovery may rebuild indexes/metadata, but must never delete `content.txt` automatically.

## 3. Remove unused global `PageCache` from V1

The base plan created `PageCache.swift` but never integrated it into the reader. That violates the project's YAGNI constraint.

For V1:

- Do not create `Sources/ReadBookCore/Reader/PageCache.swift`.
- Remove it from the file map and Task 6 deliverables when executing.
- Keep `LayoutSignature`; it is used to determine when current pagination layout must be recomputed.
- `PaginatedReaderView` keeps only `currentRange` plus optionally one previous/next range as local view state.
- If profiling later proves a larger cache useful, add it as a separate post-V1 change.

Task 6 still must use bounded local TextKit probing so opening at a saved offset does not paginate from character zero.

## 4. Paginated view must re-layout on typography changes

The base Task 8 re-laid out on position and geometry changes but omitted style changes. Add:

```swift
.onChange(of: style) { _, _ in
    layout(width: innerWidth, height: innerHeight)
}
```

`ReaderTextStyle` is already `Equatable`. Font family, font size, line spacing, paragraph spacing, and padding changes therefore invalidate the visible page immediately while preserving `session.position`.

## 5. Trackpad horizontal paging uses a scoped local event monitor

Do not rely on an AppKit overlay with `.allowsHitTesting(false)` to receive `scrollWheel` events.

Implement `HorizontalScrollPager` with a Coordinator-owned local event monitor:

```swift
final class Coordinator {
    weak var view: NSView?
    var monitor: Any?
    var accumulatedX: CGFloat = 0
    var lockedUntil = Date.distantPast
    let onPrevious: () -> Void
    let onNext: () -> Void

    init(onPrevious: @escaping () -> Void, onNext: @escaping () -> Void) {
        self.onPrevious = onPrevious
        self.onNext = onNext
    }

    func install() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self,
                  let window = self.view?.window,
                  event.windowNumber == window.windowNumber,
                  event.hasPreciseScrollingDeltas,
                  Date() >= self.lockedUntil,
                  abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            else { return event }

            self.accumulatedX += event.scrollingDeltaX
            guard abs(self.accumulatedX) >= 60 else { return nil }

            if self.accumulatedX > 0 { self.onPrevious() }
            else { self.onNext() }
            self.accumulatedX = 0
            self.lockedUntil = Date().addingTimeInterval(0.25)
            return nil
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}
```

`HorizontalScrollPager` only needs a tiny transparent `NSViewRepresentable` so the Coordinator can identify the containing window. The monitor must be removed in dismantle/deinit. Vertical scrolling deltas must pass through untouched.

## 6. Keep current metadata in sync with the live position

In `ReaderSession.updatePosition`, update both canonical session position and the in-memory current-book metadata:

```swift
public func updatePosition(_ newPosition: BookPosition) {
    guard let book = currentBook else { return }
    position = newPosition.clamped(to: book.totalUTF16Length)
    currentBook?.position = position
    currentBook?.lastReadAt = .now
    currentChapter = chapter(at: position.utf16Offset, in: book.chapters)
    scheduleSave()
}
```

The recent-books UI should use `session.position` for the currently open book and persisted `book.position` for other books, avoiding visibly stale progress while reading.

## 7. Define the import request and failed-import state explicitly

The base Task 10 calls `model.requestImport()` without defining it. Add these members to `AppModel` in Task 9:

```swift
var isImporterPresented = false
var failedImportURL: URL?

func requestImport() {
    isImporterPresented = true
}
```

Bind `ReaderRootView.fileImporter` directly to `model.isImporterPresented`.

In `importBook`, retain the failed URL only for decoding failures:

```swift
func importBook(_ url: URL, override: ImportedTextEncoding? = nil) async {
    do {
        let book = try await repository.importBook(from: url, encodingOverride: override)
        failedImportURL = nil
        await reloadLibrary()
        try await open(book.id)
    } catch TextDecoderError.undecodable {
        failedImportURL = url
        lastErrorMessage = message(for: TextDecoderError.undecodable)
    } catch {
        lastErrorMessage = message(for: error)
    }
}
```

The manual-encoding sheet retries the exact `failedImportURL` with the selected `ImportedTextEncoding`.

## 8. Removal requires confirmation and current-book handling

Before deleting a library book, `LibraryPopoverView` must show a confirmation dialog naming the book. On confirmation:

```swift
Task {
    let wasCurrent = model.session.currentBook?.id == book.id
    if wasCurrent { await model.session.flush() }
    try? await model.repository.remove(bookID: book.id)
    await model.reloadLibrary()

    if wasCurrent, let next = model.books.first {
        try? await model.open(next.id)
    }
}
```

If no books remain, add this exact API to `ReaderSession`:

```swift
public func clear() async {
    await flush()
    currentBook = nil
    text = ""
    position = .zero
    currentChapter = nil
}
```

Call `await model.session.clear()` when removal leaves the library empty.

## 9. The widget window must actually be transparent outside the rounded reader surface

Add these properties to Task 10 `WindowCoordinator.configure(_:)`:

```swift
window.isOpaque = false
window.backgroundColor = .clear
window.hasShadow = true
```

Keep the SwiftUI root rounded rectangle as the only painted surface. Do not add a second AppKit background layer.

## 10. Continuous text view updates must not snap during ordinary scroll callbacks

`ContinuousTextView.Coordinator` must distinguish external anchor changes from positions it just reported.

Maintain:

```swift
var lastReportedOffset: Int?
var lastAppliedAnchor: Int?
```

When clip bounds change, set `lastReportedOffset = character` before invoking `onPositionChanged`.

During `updateNSView`, only programmatically scroll when:

```swift
anchor.utf16Offset != coordinator.lastReportedOffset &&
anchor.utf16Offset != coordinator.lastAppliedAnchor
```

After programmatic scrolling, set `lastAppliedAnchor = anchor.utf16Offset`.

This prevents the observable `session.position` update from feeding back into the text view and snapping the user's inertial scroll.

## 11. Reader text surfaces must apply style changes in place

Both `PagedTextView` and `ContinuousTextView` must rebuild their attributed text when any `ReaderTextStyle` value or text color changes. `ContinuousTextView` must preserve the current UTF-16 anchor across that rebuild and scroll back to the anchor after TextKit layout completes.

This is required for the V1 acceptance items:

- font size changes without losing logical position;
- line spacing changes without losing logical position;
- font family changes without losing logical position;
- theme changes without losing logical position.

## 12. Final self-review result

After these corrections:

- Spec coverage: complete across Tasks 1-11.
- Placeholder scan: no `TBD`, `TODO`, or deferred implementation instructions are required for V1.
- Type/interface consistency: `requestImport`, `clear`, live book position updates, recovery behavior, and style invalidation are now explicitly defined.
- Scope: unchanged; still one cohesive local macOS V1 and no excluded backend/cloud/AI/document formats are introduced.

# ReadBook V1 Implementation Alignment

Date: 2026-08-31
Status: Final implementation reconciliation
Applies to: `docs/superpowers/specs/2026-08-31-macos-reader-design.md`

This note records implementation-level refinements discovered during TDD, macOS 26 CI, and final code review. It does not change any user-visible V1 product requirement.

## 1. Local metadata ownership

The final V1 implementation uses a recoverable two-level storage model with only one owner for each mutable value:

- `library.json` is a lightweight, rebuildable library index. It stores ordered book IDs plus `lastOpenedBookID`.
- `Books/<book-id>/metadata.json` is the canonical per-book metadata record. It stores display title, import time, last-read time, canonical UTF-16 reading position, total UTF-16 length, detected source encoding, and persisted chapter index.
- `Books/<book-id>/content.txt` is the normalized UTF-8 novel content.
- Reader-wide preferences and window behavior remain in `UserDefaults`.

The canonical reading position is therefore persisted in exactly one place: the book's `metadata.json`. It is not duplicated into `library.json`, which preserves the original design goal of avoiding dual-write divergence.

If `library.json` is missing or corrupt, ReadBook rebuilds it from the managed `Books/` directory. If a book's `metadata.json` is corrupt but its normalized `content.txt` remains readable, ReadBook rebuilds the book metadata and chapter index without deleting the novel.

## 2. Pagination cache scope

V1 intentionally does not keep a global page cache. The reader performs bounded TextKit probing around the current UTF-16 offset and keeps only the current page range in view state.

`LayoutSignature` remains the canonical representation of pagination-affecting geometry and typography. A larger page cache may be added later only if profiling demonstrates a concrete need.

This keeps V1 within its YAGNI constraint while still providing bounded first-page/current-position layout for multi-million-character novels.

## 3. Legacy Chinese encoding detection

GB18030 and Big5 byte sequences can both decode successfully under the wrong codec. V1 therefore does not accept the first successful legacy decoder. It ranks successful GB18030 and Big5 decodes using Chinese-prose quality signals and rejects obviously garbled/private-use-heavy results.

Manual encoding override remains available when automatic detection cannot produce a trustworthy result.

## 4. Input interaction refinement

Paginated trackpad navigation uses a reader-window-scoped local macOS event monitor for precise horizontal gestures. Vertical wheel/trackpad events are passed through instead of being swallowed by the paging interaction layer.

Continuous scrolling separately tracks programmatically applied anchors and user-reported visible positions so session updates cannot feed back into the text view and snap inertial scrolling.

These refinements preserve the approved interaction model while making its AppKit implementation deterministic on macOS 26.

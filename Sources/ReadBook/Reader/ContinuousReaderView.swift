import AppKit
import ReadBookCore
import SwiftUI

struct ContinuousReaderView: View {
    let bookID: UUID
    let text: String
    let anchor: BookPosition
    let style: ReaderTextStyle
    let textColor: NSColor
    let onPositionChanged: (BookPosition) -> Void
    let highlightedRange: Range<Int>? = nil
    let onSelectionChanged: (NSRange) -> Void = { _ in }

    var body: some View {
        ContinuousTextView(
            bookID: bookID,
            text: text,
            anchor: anchor,
            style: style,
            textColor: textColor,
            onPositionChanged: onPositionChanged,
            highlightedRange: highlightedRange,
            onSelectionChanged: onSelectionChanged
        )
    }
}

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
    let highlightedRange: Range<Int>?
    let onSelectionChanged: (NSRange) -> Void

    init(
        bookID: UUID,
        text: String,
        anchor: BookPosition,
        style: ReaderTextStyle,
        textColor: NSColor,
        onPositionChanged: @escaping (BookPosition) -> Void,
        highlightedRange: Range<Int>? = nil,
        onSelectionChanged: @escaping (NSRange) -> Void = { _ in }
    ) {
        self.bookID = bookID
        self.text = text
        self.anchor = anchor
        self.style = style
        self.textColor = textColor
        self.onPositionChanged = onPositionChanged
        self.highlightedRange = highlightedRange
        self.onSelectionChanged = onSelectionChanged
    }

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

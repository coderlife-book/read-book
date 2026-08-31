import AppKit
import ReadBookCore
import SwiftUI

struct ContinuousReaderView: View {
    let text: String
    let anchor: BookPosition
    let style: ReaderTextStyle
    let textColor: NSColor
    let onPositionChanged: (BookPosition) -> Void

    var body: some View {
        ContinuousTextView(
            text: text,
            anchor: anchor,
            style: style,
            textColor: textColor,
            onPositionChanged: onPositionChanged
        )
    }
}

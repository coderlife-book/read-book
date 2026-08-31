import AppKit
import ReadBookCore
import SwiftUI

struct PagedTextView: NSViewRepresentable {
    let text: String
    let style: ReaderTextStyle
    let textColor: NSColor

    func makeNSView(context: Context) -> NSTextView {
        let view = NSTextView(frame: .zero)
        view.isEditable = false
        view.isSelectable = false
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        return view
    }

    func updateNSView(_ view: NSTextView, context: Context) {
        let engine = PaginationEngine()
        let attributed = NSMutableAttributedString(
            attributedString: engine.attributedString(text, style: style)
        )
        attributed.addAttribute(
            .foregroundColor,
            value: textColor,
            range: NSRange(location: 0, length: attributed.length)
        )
        view.textStorage?.setAttributedString(attributed)
    }
}

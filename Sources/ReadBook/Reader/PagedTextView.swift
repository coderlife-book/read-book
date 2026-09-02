@preconcurrency import AppKit
import ReadBookCore
import SwiftUI

struct PagedTextView: NSViewRepresentable {
    let text: String
    let style: ReaderTextStyle
    let textColor: NSColor

    func makeNSView(context: Context) -> NSTextView {
        let view = NSTextView(frame: .zero)
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        context.coordinator.attach(view)
        return view
    }

    func updateNSView(_ view: NSTextView, context: Context) {
        context.coordinator.updateLineSpacing(style.lineSpacing)
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

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject {
        private let textLayoutDelegate = ReaderTextLayoutDelegate()

        func attach(_ view: NSTextView) {
            view.layoutManager?.delegate = textLayoutDelegate
        }

        func updateLineSpacing(_ lineSpacing: Double) {
            textLayoutDelegate.lineSpacing = lineSpacing
        }
    }
}

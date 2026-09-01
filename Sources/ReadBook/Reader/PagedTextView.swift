@preconcurrency import AppKit
import ReadBookCore
import SwiftUI

struct PagedTextView: NSViewRepresentable {
    let text: String
    let style: ReaderTextStyle
    let textColor: NSColor
    let highlightedRange: NSRange?
    let onSelectionChanged: (NSRange) -> Void

    init(
        text: String,
        style: ReaderTextStyle,
        textColor: NSColor,
        highlightedRange: NSRange? = nil,
        onSelectionChanged: @escaping (NSRange) -> Void = { _ in }
    ) {
        self.text = text
        self.style = style
        self.textColor = textColor
        self.highlightedRange = highlightedRange
        self.onSelectionChanged = onSelectionChanged
    }

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
        if let highlightedRange, NSIntersectionRange(highlightedRange, NSRange(location: 0, length: attributed.length)).length > 0 {
            let local = NSIntersectionRange(highlightedRange, NSRange(location: 0, length: attributed.length))
            view.textStorage?.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.28), range: local)
        }
        context.coordinator.onSelectionChanged = onSelectionChanged
    }

    func makeCoordinator() -> Coordinator { Coordinator(onSelectionChanged: onSelectionChanged) }

    @MainActor
    final class Coordinator: NSObject {
        var onSelectionChanged: (NSRange) -> Void
        private weak var view: NSTextView?
        private var observer: NSObjectProtocol?

        init(onSelectionChanged: @escaping (NSRange) -> Void) {
            self.onSelectionChanged = onSelectionChanged
        }

        func attach(_ view: NSTextView) {
            self.view = view
            observer = NotificationCenter.default.addObserver(
                forName: NSTextView.didChangeSelectionNotification,
                object: view,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let range = self.view?.selectedRange(), range.length > 0 else { return }
                    self.onSelectionChanged(range)
                }
            }
        }

    }
}

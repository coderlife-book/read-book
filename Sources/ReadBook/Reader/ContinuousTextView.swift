import AppKit
import ReadBookCore
import SwiftUI

struct ContinuousTextView: NSViewRepresentable {
    let text: String
    let anchor: BookPosition
    let style: ReaderTextStyle
    let textColor: NSColor
    let onPositionChanged: (BookPosition) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPositionChanged: onPositionChanged)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView(frame: .zero)
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.contentView.postsBoundsChangedNotifications = true

        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.layoutManager?.allowsNonContiguousLayout = true
        scrollView.documentView = textView

        context.coordinator.attach(scrollView: scrollView, textView: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.onPositionChanged = onPositionChanged

        let needsTextUpdate = textView.string != text
            || context.coordinator.lastStyle != style
            || context.coordinator.lastColor != textColor

        if needsTextUpdate {
            let engine = PaginationEngine()
            let attributed = NSMutableAttributedString(
                attributedString: engine.attributedString(text, style: style)
            )
            attributed.addAttribute(
                .foregroundColor,
                value: textColor,
                range: NSRange(location: 0, length: attributed.length)
            )
            context.coordinator.isApplyingProgrammaticChange = true
            textView.textStorage?.setAttributedString(attributed)
            textView.textContainerInset = NSSize(
                width: style.horizontalPadding,
                height: style.verticalPadding
            )
            context.coordinator.lastStyle = style
            context.coordinator.lastColor = textColor
            context.coordinator.lastReportedOffset = nil
            context.coordinator.lastAppliedAnchor = nil
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            context.coordinator.isApplyingProgrammaticChange = false
        }

        context.coordinator.apply(anchor: anchor)
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject {
        var onPositionChanged: (BookPosition) -> Void
        weak var scrollView: NSScrollView?
        weak var textView: NSTextView?
        var lastReportedOffset: Int?
        var lastAppliedAnchor: Int?
        var lastStyle: ReaderTextStyle?
        var lastColor: NSColor?
        var isApplyingProgrammaticChange = false
        private var observer: NSObjectProtocol?

        init(onPositionChanged: @escaping (BookPosition) -> Void) {
            self.onPositionChanged = onPositionChanged
        }

        func attach(scrollView: NSScrollView, textView: NSTextView) {
            self.scrollView = scrollView
            self.textView = textView
            observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.reportTopVisiblePosition()
                }
            }
        }

        func detach() {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
        }

        func apply(anchor: BookPosition) {
            guard anchor.utf16Offset != lastReportedOffset,
                  anchor.utf16Offset != lastAppliedAnchor,
                  let scrollView,
                  let textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer,
                  !textView.string.isEmpty else { return }

            let length = (textView.string as NSString).length
            let character = min(max(anchor.utf16Offset, 0), max(length - 1, 0))
            let characterRange = NSRange(location: character, length: min(1, length - character))
            let glyphRange = layoutManager.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let targetY = max(rect.minY + textView.textContainerOrigin.y - styleTopInset(textView), 0)

            isApplyingProgrammaticChange = true
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            lastAppliedAnchor = anchor.utf16Offset
            isApplyingProgrammaticChange = false
        }

        private func reportTopVisiblePosition() {
            guard !isApplyingProgrammaticChange,
                  let scrollView,
                  let textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer,
                  !textView.string.isEmpty else { return }

            let point = NSPoint(
                x: max(scrollView.contentView.bounds.minX - textView.textContainerOrigin.x, 0),
                y: max(scrollView.contentView.bounds.minY - textView.textContainerOrigin.y, 0)
            )
            let glyph = layoutManager.glyphIndex(for: point, in: textContainer)
            let character = layoutManager.characterIndexForGlyph(at: glyph)

            // A bounds notification can trail a programmatic jump. Ignore that
            // exact location once; as soon as the user moves elsewhere, clear
            // the applied marker so scrolling back to it is reportable later.
            if character == lastAppliedAnchor { return }
            lastAppliedAnchor = nil

            guard character != lastReportedOffset else { return }
            lastReportedOffset = character
            onPositionChanged(BookPosition(utf16Offset: character))
        }

        private func styleTopInset(_ textView: NSTextView) -> CGFloat {
            textView.textContainerInset.height
        }
    }
}

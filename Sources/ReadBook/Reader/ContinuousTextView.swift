import AppKit
import ReadBookCore
import SwiftUI

struct ContinuousTextView: NSViewRepresentable {
    let bookID: UUID
    let text: String
    let anchor: BookPosition
    let style: ReaderTextStyle
    let textColor: NSColor
    let onPositionChanged: (BookPosition) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPositionChanged: onPositionChanged)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = Self.makeNativeScrollView()
        guard let textView = scrollView.documentView as? NSTextView else {
            preconditionFailure("NSTextView.scrollableTextView() must provide NSTextView")
        }

        context.coordinator.attach(scrollView: scrollView, textView: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onPositionChanged = onPositionChanged
        context.coordinator.update(
            bookID: bookID,
            text: text,
            anchor: anchor,
            style: style,
            textColor: textColor
        )
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    static func makeNativeScrollView() -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            preconditionFailure("NSTextView.scrollableTextView() must provide NSTextView")
        }

        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.contentView.postsBoundsChangedNotifications = true

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.layoutManager?.allowsNonContiguousLayout = true

        return scrollView
    }

    @MainActor
    final class Coordinator: NSObject {
        var onPositionChanged: (BookPosition) -> Void
        weak var scrollView: NSScrollView?
        weak var textView: NSTextView?

        private var sourceBookID: UUID?
        private var sourceText = ""
        private var currentStyle: ReaderTextStyle?
        private var currentColor: NSColor?
        private var observer: NSObjectProtocol?
        private var reportWorkItem: DispatchWorkItem?
        private var lastReportedOffset: Int?
        private var lastAppliedAnchor: Int?
        private var isApplyingProgrammaticChange = false

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
                    self?.schedulePositionReport()
                }
            }
        }

        func detach() {
            reportWorkItem?.cancel()
            reportWorkItem = nil
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
        }

        func update(
            bookID: UUID,
            text: String,
            anchor: BookPosition,
            style: ReaderTextStyle,
            textColor: NSColor
        ) {
            let bookChanged = sourceBookID != bookID
            let styleChanged = currentStyle != style || currentColor != textColor

            sourceBookID = bookID
            sourceText = text
            currentStyle = style
            currentColor = textColor

            guard !text.isEmpty else {
                clearText()
                return
            }

            let anchorOffset = min(max(anchor.utf16Offset, 0), (text as NSString).length)

            if bookChanged || styleChanged || textView?.string.isEmpty == true {
                renderDocument(restoringGlobalOffset: anchorOffset)
            } else {
                apply(globalOffset: anchorOffset)
            }
        }

        private func clearText() {
            guard let textView else { return }
            cancelPendingPositionReport()
            isApplyingProgrammaticChange = true
            textView.string = ""
            lastReportedOffset = nil
            lastAppliedAnchor = nil
            scrollView?.contentView.scroll(to: .zero)
            isApplyingProgrammaticChange = false
        }

        private func renderDocument(restoringGlobalOffset globalOffset: Int) {
            guard let style = currentStyle,
                  let textColor = currentColor,
                  let textView else { return }

            let engine = PaginationEngine()
            let attributed = NSMutableAttributedString(
                attributedString: engine.attributedString(sourceText, style: style)
            )
            attributed.addAttribute(
                .foregroundColor,
                value: textColor,
                range: NSRange(location: 0, length: attributed.length)
            )

            cancelPendingPositionReport()
            isApplyingProgrammaticChange = true
            textView.textStorage?.setAttributedString(attributed)
            textView.textContainerInset = NSSize(
                width: style.horizontalPadding,
                height: style.verticalPadding
            )
            lastReportedOffset = nil
            lastAppliedAnchor = nil
            scrollTo(globalOffset: globalOffset)
            isApplyingProgrammaticChange = false
        }

        private func apply(globalOffset: Int) {
            guard globalOffset != lastReportedOffset,
                  globalOffset != lastAppliedAnchor else { return }

            cancelPendingPositionReport()
            isApplyingProgrammaticChange = true
            scrollTo(globalOffset: globalOffset)
            isApplyingProgrammaticChange = false
        }

        private func scrollTo(globalOffset: Int) {
            guard let scrollView,
                  let textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer,
                  !textView.string.isEmpty else { return }

            let length = (textView.string as NSString).length
            let character = min(max(globalOffset, 0), max(length - 1, 0))
            let characterRange = NSRange(location: character, length: min(1, length - character))
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: characterRange,
                actualCharacterRange: nil
            )
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let targetY = max(
                rect.minY + textView.textContainerOrigin.y - textView.textContainerInset.height,
                0
            )

            scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            lastAppliedAnchor = character
        }

        private func schedulePositionReport() {
            reportWorkItem?.cancel()

            let workItem = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.reportWorkItem = nil
                    self.reportTopVisiblePosition()
                }
            }
            reportWorkItem = workItem
            DispatchQueue.main.asyncAfter(
                deadline: .now() + 0.06,
                execute: workItem
            )
        }

        private func cancelPendingPositionReport() {
            reportWorkItem?.cancel()
            reportWorkItem = nil
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
            let globalCharacter = min(max(character, 0), (sourceText as NSString).length)

            if globalCharacter == lastAppliedAnchor { return }
            lastAppliedAnchor = nil

            if globalCharacter != lastReportedOffset {
                lastReportedOffset = globalCharacter
                onPositionChanged(BookPosition(utf16Offset: globalCharacter))
            }
        }
    }
}

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

    func makeCoordinator() -> Coordinator {
        Coordinator(onPositionChanged: onPositionChanged, onSelectionChanged: onSelectionChanged)
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
        context.coordinator.onPositionChanged = onPositionChanged
        context.coordinator.onSelectionChanged = onSelectionChanged
        context.coordinator.update(
            bookID: bookID,
            text: text,
            anchor: anchor,
            style: style,
            textColor: textColor
        )
        context.coordinator.updateHighlight(highlightedRange)
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject {
        var onPositionChanged: (BookPosition) -> Void
        var onSelectionChanged: (NSRange) -> Void
        weak var scrollView: NSScrollView?
        weak var textView: NSTextView?

        private let planner = VirtualTextWindowPlanner()
        private let textLayoutDelegate = ReaderTextLayoutDelegate()
        private var sourceBookID: UUID?
        private var sourceText = ""
        private var currentWindow: VirtualTextWindow?
        private var currentStyle: ReaderTextStyle?
        private var currentColor: NSColor?
        private var observer: NSObjectProtocol?
        private var selectionObserver: NSObjectProtocol?
        private var highlightedRange: Range<Int>?
        private var lastReportedOffset: Int?
        private var lastAppliedAnchor: Int?
        private var isApplyingProgrammaticChange = false
        private var recenterScheduled = false

        init(
            onPositionChanged: @escaping (BookPosition) -> Void,
            onSelectionChanged: @escaping (NSRange) -> Void = { _ in }
        ) {
            self.onPositionChanged = onPositionChanged
            self.onSelectionChanged = onSelectionChanged
        }

        func attach(scrollView: NSScrollView, textView: NSTextView) {
            self.scrollView = scrollView
            self.textView = textView
            textView.layoutManager?.delegate = textLayoutDelegate
            observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.reportTopVisiblePosition()
                }
            }
            selectionObserver = NotificationCenter.default.addObserver(
                forName: NSTextView.didChangeSelectionNotification,
                object: textView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.reportSelection() }
            }
        }

        func detach() {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            if let selectionObserver { NotificationCenter.default.removeObserver(selectionObserver) }
            observer = nil
            selectionObserver = nil
        }

        func updateHighlight(_ globalRange: Range<Int>?) {
            highlightedRange = globalRange
            applyHighlight()
            scrollHighlightIntoViewIfNeeded()
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
            let anchorOutsideWindow = currentWindow?.contains(globalOffset: anchorOffset) != true

            if bookChanged || currentWindow == nil || anchorOutsideWindow {
                loadWindow(centeredAt: anchorOffset, restoreGlobalOffset: anchorOffset)
            } else if styleChanged {
                renderCurrentWindow(restoringGlobalOffset: anchorOffset)
            } else {
                apply(globalOffset: anchorOffset)
            }
        }

        private func clearText() {
            guard let textView else { return }
            isApplyingProgrammaticChange = true
            textView.string = ""
            currentWindow = nil
            lastReportedOffset = nil
            lastAppliedAnchor = nil
            isApplyingProgrammaticChange = false
        }

        private func loadWindow(centeredAt globalOffset: Int, restoreGlobalOffset: Int) {
            guard !sourceText.isEmpty else { return }
            currentWindow = planner.makeWindow(in: sourceText, centeredAt: globalOffset)
            renderCurrentWindow(restoringGlobalOffset: restoreGlobalOffset)
        }

        private func renderCurrentWindow(restoringGlobalOffset globalOffset: Int) {
            guard let window = currentWindow,
                  let style = currentStyle,
                  let textColor = currentColor,
                  let textView else { return }

            let engine = PaginationEngine()
            textLayoutDelegate.lineSpacing = style.lineSpacing
            let attributed = NSMutableAttributedString(
                attributedString: engine.attributedString(window.text, style: style)
            )
            attributed.addAttribute(
                .foregroundColor,
                value: textColor,
                range: NSRange(location: 0, length: attributed.length)
            )

            isApplyingProgrammaticChange = true
            textView.textStorage?.setAttributedString(attributed)
            applyHighlight()
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
                  globalOffset != lastAppliedAnchor,
                  let window = currentWindow,
                  window.contains(globalOffset: globalOffset) else { return }

            isApplyingProgrammaticChange = true
            scrollTo(globalOffset: globalOffset)
            isApplyingProgrammaticChange = false
        }

        private func scrollTo(globalOffset: Int) {
            guard let window = currentWindow,
                  let scrollView,
                  let textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer,
                  !textView.string.isEmpty else { return }

            let localOffset = window.localOffset(forGlobalOffset: globalOffset)
            let length = (textView.string as NSString).length
            let character = min(max(localOffset, 0), max(length - 1, 0))
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
            lastAppliedAnchor = window.globalOffset(forLocalOffset: character)
        }

        private func reportTopVisiblePosition() {
            guard !isApplyingProgrammaticChange,
                  let window = currentWindow,
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
            let localCharacter = layoutManager.characterIndexForGlyph(at: glyph)
            let globalCharacter = window.globalOffset(forLocalOffset: localCharacter)

            if globalCharacter == lastAppliedAnchor { return }
            lastAppliedAnchor = nil

            if globalCharacter != lastReportedOffset {
                lastReportedOffset = globalCharacter
                onPositionChanged(BookPosition(utf16Offset: globalCharacter))
            }

            scheduleRecenteringIfNeeded(at: globalCharacter)
        }

        private func reportSelection() {
            guard !isApplyingProgrammaticChange,
                  let range = textView?.selectedRange(),
                  range.length > 0,
                  let window = currentWindow else { return }
            let lower = window.globalOffset(forLocalOffset: range.location)
            let upper = window.globalOffset(forLocalOffset: NSMaxRange(range))
            onSelectionChanged(NSRange(location: lower, length: max(upper - lower, 0)))
        }

        private func applyHighlight() {
            guard let textView, let window = currentWindow else { return }
            let length = (textView.string as NSString).length
            guard length > 0 else { return }
            let fullRange = NSRange(location: 0, length: length)
            textView.textStorage?.removeAttribute(.backgroundColor, range: fullRange)
            guard let highlightedRange else { return }
            let lower = max(highlightedRange.lowerBound, window.utf16Range.lowerBound)
            let upper = min(highlightedRange.upperBound, window.utf16Range.upperBound)
            guard lower < upper else { return }
            let local = NSRange(location: lower - window.utf16Range.lowerBound, length: upper - lower)
            textView.textStorage?.addAttribute(
                .backgroundColor,
                value: NSColor.systemYellow.withAlphaComponent(0.28),
                range: local
            )
        }

        private func scrollHighlightIntoViewIfNeeded() {
            guard let highlightedRange,
                  let window = currentWindow,
                  window.contains(globalOffset: highlightedRange.lowerBound),
                  let scrollView,
                  let textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            let localOffset = window.localOffset(forGlobalOffset: highlightedRange.lowerBound)
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: NSRange(location: localOffset, length: 1),
                actualCharacterRange: nil
            )
            let glyphRect = layoutManager
                .boundingRect(forGlyphRange: glyphRange, in: textContainer)
                .offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
            guard !scrollView.contentView.bounds.intersects(glyphRect) else { return }
            scrollTo(globalOffset: highlightedRange.lowerBound)
        }

        private func scheduleRecenteringIfNeeded(at globalOffset: Int) {
            guard currentWindow?.needsRecentering(globalOffset: globalOffset) == true,
                  !recenterScheduled else { return }

            recenterScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.recenterScheduled = false
                guard self.currentWindow?.needsRecentering(globalOffset: globalOffset) == true else { return }
                self.loadWindow(centeredAt: globalOffset, restoreGlobalOffset: globalOffset)
            }
        }
    }
}

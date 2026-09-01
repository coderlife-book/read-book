import AppKit
import ReadBookCore
import SwiftUI

struct PaginatedReaderView: View {
    let text: String
    let anchor: BookPosition
    let style: ReaderTextStyle
    let textColor: NSColor
    let onPositionChanged: (BookPosition) -> Void
    let highlightedRange: Range<Int>?
    let onSelectionChanged: (NSRange) -> Void

    init(
        text: String,
        anchor: BookPosition,
        style: ReaderTextStyle,
        textColor: NSColor,
        onPositionChanged: @escaping (BookPosition) -> Void,
        highlightedRange: Range<Int>? = nil,
        onSelectionChanged: @escaping (NSRange) -> Void = { _ in }
    ) {
        self.text = text
        self.anchor = anchor
        self.style = style
        self.textColor = textColor
        self.onPositionChanged = onPositionChanged
        self.highlightedRange = highlightedRange
        self.onSelectionChanged = onSelectionChanged
    }

    @State private var currentRange: PageRange?
    @State private var hovering = false
    private let engine = PaginationEngine()

    var body: some View {
        GeometryReader { proxy in
            let innerWidth = max(proxy.size.width - style.horizontalPadding * 2, 1)
            let innerHeight = max(proxy.size.height - style.verticalPadding * 2, 1)

            ZStack {
                if let range = currentRange, range.length > 0 {
                    let pageRange = range.location..<(range.location + range.length)
                    let localHighlight: NSRange? = highlightedRange.flatMap { global in
                        let lower = max(global.lowerBound, pageRange.lowerBound)
                        let upper = min(global.upperBound, pageRange.upperBound)
                        guard lower < upper else { return nil }
                        return NSRange(location: lower - range.location, length: upper - lower)
                    }
                    PagedTextView(
                        text: (text as NSString).substring(
                            with: NSRange(location: range.location, length: range.length)
                        ),
                        style: style,
                        textColor: textColor,
                        highlightedRange: localHighlight,
                        onSelectionChanged: { local in
                            onSelectionChanged(NSRange(location: range.location + local.location, length: local.length))
                        }
                    )
                    .padding(.horizontal, style.horizontalPadding)
                    .padding(.vertical, style.verticalPadding)
                }

                HorizontalScrollPager(
                    onPrevious: { previous(width: innerWidth, height: innerHeight) },
                    onNext: { next(width: innerWidth, height: innerHeight) }
                )

                HStack {
                    Image(systemName: "chevron.left")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(nsColor: textColor))
                .padding(.horizontal, 10)
                .opacity(hovering ? 0.42 : 0)
                .allowsHitTesting(false)
            }
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onAppear { layout(width: innerWidth, height: innerHeight) }
            .onChange(of: anchor) { _, _ in
                if currentRange?.location != anchor.utf16Offset {
                    layout(width: innerWidth, height: innerHeight)
                }
            }
            .onChange(of: style) { _, _ in
                layout(width: innerWidth, height: innerHeight)
            }
            .onChange(of: proxy.size) { _, _ in
                layout(width: innerWidth, height: innerHeight)
            }
            .onChange(of: highlightedRange) { _, newRange in
                guard let newRange, let currentRange else { return }
                if let next = PagedAudiobookNavigation.pageIfNeeded(
                    currentRange: currentRange,
                    highlightedRange: newRange,
                    text: text as NSString,
                    width: innerWidth,
                    height: innerHeight,
                    style: style,
                    engine: engine
                ) {
                    self.currentRange = next
                    onPositionChanged(BookPosition(utf16Offset: next.location))
                }
            }
        }
    }

    private func layout(width: Double, height: Double) {
        currentRange = engine.pageForward(
            text: text as NSString,
            from: anchor.utf16Offset,
            width: width,
            height: height,
            style: style
        )
    }

    private func next(width: Double, height: Double) {
        guard let currentRange,
              let next = engine.pageForward(
                text: text as NSString,
                from: currentRange.upperBound,
                width: width,
                height: height,
                style: style
              ) else { return }
        self.currentRange = next
        onPositionChanged(BookPosition(utf16Offset: next.location))
    }

    private func previous(width: Double, height: Double) {
        guard let currentRange,
              let previous = engine.pageBackward(
                text: text as NSString,
                endingAt: currentRange.location,
                width: width,
                height: height,
                style: style
              ) else { return }
        self.currentRange = previous
        onPositionChanged(BookPosition(utf16Offset: previous.location))
    }
}

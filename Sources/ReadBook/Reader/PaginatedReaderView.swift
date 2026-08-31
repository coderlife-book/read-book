import AppKit
import ReadBookCore
import SwiftUI

struct PaginatedReaderView: View {
    let text: String
    let anchor: BookPosition
    let style: ReaderTextStyle
    let textColor: NSColor
    let onPositionChanged: (BookPosition) -> Void

    @State private var currentRange: PageRange?
    private let engine = PaginationEngine()

    var body: some View {
        GeometryReader { proxy in
            let innerWidth = max(proxy.size.width - style.horizontalPadding * 2, 1)
            let innerHeight = max(proxy.size.height - style.verticalPadding * 2, 1)

            ZStack {
                if let range = currentRange, range.length > 0 {
                    PagedTextView(
                        text: (text as NSString).substring(
                            with: NSRange(location: range.location, length: range.length)
                        ),
                        style: style,
                        textColor: textColor
                    )
                    .padding(.horizontal, style.horizontalPadding)
                    .padding(.vertical, style.verticalPadding)
                }

                HorizontalScrollPager(
                    onPrevious: { previous(width: innerWidth, height: innerHeight) },
                    onNext: { next(width: innerWidth, height: innerHeight) }
                )
            }
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

import Foundation
import ReadBookCore

enum PagedAudiobookNavigation {
    /// 高亮句仍在当前页时返回 nil；离开当前页时以句子起点重新分页。
    static func pageIfNeeded(
        currentRange: PageRange,
        highlightedRange: Range<Int>,
        text: NSString,
        width: Double,
        height: Double,
        style: ReaderTextStyle,
        engine: PaginationEngine
    ) -> PageRange? {
        let page = currentRange.location..<currentRange.upperBound
        let intersects = highlightedRange.lowerBound < page.upperBound
            && highlightedRange.upperBound > page.lowerBound
        guard !intersects else { return nil }
        return engine.pageForward(
            text: text,
            from: highlightedRange.lowerBound,
            width: width,
            height: height,
            style: style
        )
    }
}

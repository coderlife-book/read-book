#if os(macOS)
import AppKit
import ReadBookCore
import XCTest
@testable import ReadBook

final class ContinuousTextViewTests: XCTestCase {
    @MainActor
    func testCoordinatorRendersOnlyBoundedWindowForLargeBook() {
        let paragraph = String(repeating: "女巫种田正文", count: 40) + "\n"
        let text = String(repeating: paragraph, count: 5_000)
        let total = (text as NSString).length

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 260))
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 360, height: 260))
        scrollView.documentView = textView

        let coordinator = ContinuousTextView.Coordinator(onPositionChanged: { _ in })
        coordinator.attach(scrollView: scrollView, textView: textView)
        coordinator.update(
            bookID: UUID(),
            text: text,
            anchor: BookPosition(utf16Offset: total / 2),
            style: .default,
            textColor: .textColor
        )

        let renderedLength = (textView.string as NSString).length
        XCTAssertLessThan(renderedLength, total)
        XCTAssertLessThanOrEqual(renderedLength, 130_000)
    }
}
#endif

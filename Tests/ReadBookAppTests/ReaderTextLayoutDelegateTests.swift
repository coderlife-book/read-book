#if os(macOS)
import AppKit
import ReadBookCore
import XCTest
@testable import ReadBook

@MainActor
final class ReaderTextLayoutDelegateTests: XCTestCase {
    func testBalancedBaselineKeepsUsedHeightAndMovesGlyphDown() throws {
        let attributed = PaginationEngine().attributedString(
            "第一行\n第二行\n第三行",
            style: .default
        )
        let original = layoutMetrics(for: attributed, delegate: nil)
        let delegate = ReaderTextLayoutDelegate()
        delegate.lineSpacing = ReaderTextStyle.default.lineSpacing
        let balanced = layoutMetrics(for: attributed, delegate: delegate)

        XCTAssertEqual(balanced.usedHeight, original.usedHeight, accuracy: 0.001)
        XCTAssertEqual(
            balanced.firstBaseline,
            original.firstBaseline + ReaderTextStyle.default.lineSpacing / 2,
            accuracy: 0.001
        )
    }

    private func layoutMetrics(
        for attributed: NSAttributedString,
        delegate: NSLayoutManagerDelegate?
    ) -> (usedHeight: CGFloat, firstBaseline: CGFloat) {
        let storage = NSTextStorage(attributedString: attributed)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 316, height: 300))
        container.lineFragmentPadding = 0
        layout.delegate = delegate
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        return (
            layout.usedRect(for: container).height,
            layout.location(forGlyphAt: 0).y
        )
    }
}
#endif

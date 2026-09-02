#if os(macOS)
import Foundation
import XCTest
@testable import ReadBook
import ReadBookCore

final class PagedAudiobookNavigationTests: XCTestCase {
    private let text = NSString(string: String(repeating: "第一段正文，第二段正文，第三段正文。\n", count: 120))
    private let engine = PaginationEngine()

    func testHighlightInsideCurrentPageDoesNotRepage() throws {
        let first = try XCTUnwrap(
            engine.pageForward(text: text, from: 0, width: 316, height: 220, style: .default)
        )

        let result = PagedAudiobookNavigation.pageIfNeeded(
            currentRange: first,
            highlightedRange: first.location..<(first.location + 3),
            text: text,
            width: 316,
            height: 220,
            style: .default,
            engine: engine
        )

        XCTAssertNil(result)
    }

    func testHighlightOutsideCurrentPagePagesFromSentenceStart() throws {
        let first = try XCTUnwrap(
            engine.pageForward(text: text, from: 0, width: 316, height: 220, style: .default)
        )
        let target = first.upperBound + 10

        let result = try XCTUnwrap(
            PagedAudiobookNavigation.pageIfNeeded(
                currentRange: first,
                highlightedRange: target..<(target + 4),
                text: text,
                width: 316,
                height: 220,
                style: .default,
                engine: engine
            )
        )

        XCTAssertEqual(result.location, target)
        XCTAssertGreaterThan(result.length, 0)
    }

    func testHighlightStartingAtPageEndRepages() throws {
        let first = try XCTUnwrap(
            engine.pageForward(text: text, from: 0, width: 316, height: 220, style: .default)
        )

        let result = PagedAudiobookNavigation.pageIfNeeded(
            currentRange: first,
            highlightedRange: first.upperBound..<(first.upperBound + 1),
            text: text,
            width: 316,
            height: 220,
            style: .default,
            engine: engine
        )

        XCTAssertNotNil(result)
    }
}
#endif

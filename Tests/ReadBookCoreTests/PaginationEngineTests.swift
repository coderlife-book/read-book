import CoreFoundation
import Foundation
import XCTest
@testable import ReadBookCore

final class PaginationEngineTests: XCTestCase {
    func testPageRangeUpperBound() {
        XCTAssertEqual(PageRange(location: 12, length: 9).upperBound, 21)
    }

    #if canImport(AppKit)
    func testLineSpacingIsDistributedAroundTextBaseline() throws {
        let style = ReaderTextStyle(
            fontFamily: "PingFang SC",
            fontSize: 17,
            lineSpacing: 8,
            paragraphSpacing: 9,
            horizontalPadding: 22,
            verticalPadding: 20
        )

        let attributed = PaginationEngine().attributedString("正文", style: style)
        let attributes = attributed.attributes(at: 0, effectiveRange: nil)
        let paragraph = try XCTUnwrap(attributes[.paragraphStyle] as? NSParagraphStyle)
        let baselineOffset = try XCTUnwrap(attributes[.baselineOffset] as? NSNumber)

        XCTAssertEqual(paragraph.lineSpacing, 4, accuracy: 0.001)
        XCTAssertEqual(baselineOffset.doubleValue, -4, accuracy: 0.001)
    }

    func testForwardPagesAreContinuousAndBounded() throws {
        let text = NSString(string: String(repeating: "第一段文字。第二段文字。\n", count: 500))
        let engine = PaginationEngine()
        let first = try XCTUnwrap(engine.pageForward(text: text, from: 0, width: 316, height: 220, style: .default))
        let second = try XCTUnwrap(engine.pageForward(text: text, from: first.upperBound, width: 316, height: 220, style: .default))
        XCTAssertGreaterThan(first.length, 0)
        XCTAssertEqual(second.location, first.upperBound)
        XCTAssertLessThanOrEqual(second.upperBound, text.length)
    }

    func testFirstPageOfMultiMillionCharacterBookStaysBounded() throws {
        let text = NSString(string: String(repeating: "长篇小说正文。", count: 500_000))
        let engine = PaginationEngine()
        let started = CFAbsoluteTimeGetCurrent()
        let page = engine.pageForward(text: text, from: 0, width: 316, height: 220, style: .default)
        let elapsed = CFAbsoluteTimeGetCurrent() - started
        XCTAssertNotNil(page)
        XCTAssertLessThan(elapsed, 2.0)
    }

    func testBackwardPageEndsAtRequestedOffset() throws {
        let text = NSString(string: String(repeating: "正文🙂继续阅读。\n", count: 500))
        let engine = PaginationEngine()
        let first = try XCTUnwrap(engine.pageForward(text: text, from: 0, width: 316, height: 220, style: .default))
        let second = try XCTUnwrap(engine.pageForward(text: text, from: first.upperBound, width: 316, height: 220, style: .default))
        let previous = try XCTUnwrap(engine.pageBackward(text: text, endingAt: second.location, width: 316, height: 220, style: .default))
        XCTAssertEqual(previous.upperBound, second.location)
        XCTAssertGreaterThan(previous.length, 0)
    }
    #endif
}

import CoreFoundation
import Foundation
import XCTest
@testable import ReadBookCore

final class PaginationEngineTests: XCTestCase {
    func testPageRangeUpperBound() {
        XCTAssertEqual(PageRange(location: 12, length: 9).upperBound, 21)
    }

    #if canImport(AppKit)
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

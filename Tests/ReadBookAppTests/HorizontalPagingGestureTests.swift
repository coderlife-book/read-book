#if os(macOS)
import AppKit
import XCTest
@testable import ReadBook

@MainActor
final class HorizontalPagingGestureTests: XCTestCase {
    func testVerticalOrImpreciseScrollIsNotHandled() {
        var gesture = HorizontalPagingGesture()
        XCTAssertEqual(
            gesture.consume(deltaX: 5, deltaY: 30, precise: true, now: 1.0),
            .notHandled
        )
        XCTAssertEqual(
            gesture.consume(deltaX: 70, deltaY: 0, precise: false, now: 1.0),
            .notHandled
        )
    }

    func testHorizontalScrollAccumulatesAndPagesOncePerLockWindow() {
        var gesture = HorizontalPagingGesture()

        XCTAssertEqual(
            gesture.consume(deltaX: 35, deltaY: 2, precise: true, now: 1.0),
            .handled
        )
        XCTAssertEqual(
            gesture.consume(deltaX: 30, deltaY: 1, precise: true, now: 1.05),
            .previous
        )
        XCTAssertEqual(
            gesture.consume(deltaX: -90, deltaY: 0, precise: true, now: 1.10),
            .handled
        )
        XCTAssertEqual(
            gesture.consume(deltaX: -65, deltaY: 0, precise: true, now: 1.31),
            .next
        )
    }
}
#endif

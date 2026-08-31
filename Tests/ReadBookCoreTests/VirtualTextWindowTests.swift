import Foundation
import XCTest
@testable import ReadBookCore

final class VirtualTextWindowTests: XCTestCase {
    func testPlannerKeepsRenderedWindowBoundedAndMapsOffsets() {
        let paragraph = String(repeating: "女巫种田正文", count: 40) + "\n"
        let text = String(repeating: paragraph, count: 5_000)
        let total = (text as NSString).length
        let anchor = total / 2
        let planner = VirtualTextWindowPlanner(targetUTF16Length: 120_000, recenterMargin: 24_000)

        let window = planner.makeWindow(in: text, centeredAt: anchor)

        XCTAssertLessThanOrEqual(window.utf16Range.count, 130_000)
        XCTAssertTrue(window.utf16Range.contains(anchor))
        XCTAssertEqual(window.globalOffset(forLocalOffset: window.localOffset(forGlobalOffset: anchor)), anchor)
        XCTAssertLessThan((window.text as NSString).length, total)
    }

    func testPlannerPinsWindowToBookEdges() {
        let paragraph = String(repeating: "正文", count: 100) + "\n"
        let text = String(repeating: paragraph, count: 2_000)
        let total = (text as NSString).length
        let planner = VirtualTextWindowPlanner(targetUTF16Length: 80_000, recenterMargin: 16_000)

        let first = planner.makeWindow(in: text, centeredAt: 0)
        let last = planner.makeWindow(in: text, centeredAt: total)

        XCTAssertEqual(first.utf16Range.lowerBound, 0)
        XCTAssertEqual(last.utf16Range.upperBound, total)
    }

    func testWindowRequestsRecenteringOnlyNearAnUnloadedEdge() {
        let paragraph = String(repeating: "正文", count: 100) + "\n"
        let text = String(repeating: paragraph, count: 4_000)
        let total = (text as NSString).length
        let planner = VirtualTextWindowPlanner(targetUTF16Length: 100_000, recenterMargin: 20_000)
        let window = planner.makeWindow(in: text, centeredAt: total / 2)

        let middle = (window.utf16Range.lowerBound + window.utf16Range.upperBound) / 2
        XCTAssertFalse(window.needsRecentering(globalOffset: middle))
        XCTAssertTrue(window.needsRecentering(globalOffset: window.utf16Range.lowerBound + 1_000))
        XCTAssertTrue(window.needsRecentering(globalOffset: window.utf16Range.upperBound - 1_000))
    }
}

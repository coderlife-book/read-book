#if os(macOS)
import XCTest
@testable import ReadBook
import ReadBookCore

final class SpeechQueueTests: XCTestCase {
    func testQueueRefillsAtTenTargetsTwentyAndNeverExceedsThirty() async {
        let queue = SpeechQueue(lowWatermark: 10, targetCount: 20, hardLimit: 30)
        let generation = await queue.restart()

        await queue.append(makePreparedSentences(10), generation: generation)

        let needsRefillAtTen = await queue.needsRefill
        let requestedCapacity = await queue.requestedCapacity
        XCTAssertTrue(needsRefillAtTen)
        XCTAssertEqual(requestedCapacity, 10)

        await queue.append(makePreparedSentences(25, startingAt: 10), generation: generation)

        let count = await queue.count
        let needsRefillAtThirty = await queue.needsRefill
        XCTAssertEqual(count, 30)
        XCTAssertFalse(needsRefillAtThirty)
    }

    func testOldGenerationResultsAreDiscardedAfterJump() async {
        let queue = SpeechQueue()
        let old = await queue.restart()
        let current = await queue.restart()

        await queue.append(makePreparedSentences(5), generation: old)
        let countAfterOld = await queue.count
        XCTAssertEqual(countAfterOld, 0)

        await queue.append(makePreparedSentences(5), generation: current)
        let countAfterCurrent = await queue.count
        XCTAssertEqual(countAfterCurrent, 5)
    }

    func testPopConsumesInOrder() async {
        let queue = SpeechQueue()
        let generation = await queue.restart()
        await queue.append(makePreparedSentences(2), generation: generation)

        let first = await queue.popFirst()
        let second = await queue.popFirst()

        XCTAssertEqual(first?.sentence.utf16Range, 0..<1)
        XCTAssertEqual(second?.sentence.utf16Range, 1..<2)
    }

    private func makePreparedSentences(
        _ count: Int,
        startingAt start: Int = 0
    ) -> [PreparedSentence] {
        (start..<(start + count)).map { offset in
            PreparedSentence(
                sentence: SpeechSentence(text: "句", utf16Range: offset..<(offset + 1)),
                samples: [0],
                sampleRate: 24_000
            )
        }
    }
}
#endif

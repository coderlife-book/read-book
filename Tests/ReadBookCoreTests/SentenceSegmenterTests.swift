import Foundation
import XCTest
@testable import ReadBookCore

final class SentenceSegmenterTests: XCTestCase {
    func testSegmentsQuotedChineseAndPreservesUTF16Ranges() {
        let text = "“你不来了？喂，什么意思！”\n电话里传来吼声。🙂继续。"

        let result = SentenceSegmenter().sentences(
            in: text,
            startingAt: 0,
            policy: .containingSentence,
            limit: 20
        )

        XCTAssertEqual(
            result.map(\.text),
            ["“你不来了？", "喂，什么意思！”", "电话里传来吼声。", "🙂继续。"]
        )
        for sentence in result {
            XCTAssertEqual((text as NSString).substring(with: sentence.nsRange), sentence.text)
        }
    }

    func testExactOffsetStartsAtSelectedCharacter() {
        let text = "迟到那么久不说，你现在才告诉我？下一句。"
        let offset = (text as NSString).range(of: "现在").location

        let result = SentenceSegmenter().sentences(
            in: text,
            startingAt: offset,
            policy: .exactOffset,
            limit: 20
        )

        XCTAssertEqual(result.first?.text, "现在才告诉我？")
        XCTAssertEqual(result.first?.utf16Range.lowerBound, offset)
    }

    func testContainingSentenceMovesBackToSentenceStart() {
        let text = "第一句。第二句还在继续！第三句。"
        let offset = (text as NSString).range(of: "还在").location

        let result = SentenceSegmenter().sentences(
            in: text,
            startingAt: offset,
            policy: .containingSentence,
            limit: 1
        )

        XCTAssertEqual(result.first?.text, "第二句还在继续！")
    }

    func testEllipsisAndEmojiStayOnComposedCharacterBoundaries() {
        let text = "等等……真的？👨‍👩‍👧‍👦出发。"
        let emojiOffset = (text as NSString).range(of: "👨‍👩‍👧‍👦").location + 1

        let result = SentenceSegmenter().sentences(
            in: text,
            startingAt: emojiOffset,
            policy: .exactOffset,
            limit: 10
        )

        XCTAssertEqual(result.first?.text, "👨‍👩‍👧‍👦出发。")
        XCTAssertEqual(result.first?.utf16Range.lowerBound, (text as NSString).range(of: "👨‍👩‍👧‍👦").location)
    }

    func testNewlinesAndConsecutiveTerminatorsEndOneSentence() {
        let text = "没有标点的第一行\n第二行？！\n第三行！！"

        let result = SentenceSegmenter().sentences(
            in: text,
            startingAt: 0,
            policy: .containingSentence,
            limit: 10
        )

        XCTAssertEqual(result.map(\.text), ["没有标点的第一行", "第二行？！", "第三行！！"])
    }
}

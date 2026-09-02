#if os(macOS)
import XCTest
@testable import ReadBook
import ReadBookCore

final class SentenceTimingMapperTests: XCTestCase {
    func testChineseCharacterAlignmentMergesIntoSentenceFrameRanges() throws {
        let text = "你不来了？电话里传来吼声。"
        let sentences = SentenceSegmenter().sentences(
            in: text,
            startingAt: 0,
            policy: .exactOffset,
            limit: 20
        )
        let items = [
            TimedText(text: "你", start: 0.0, end: 0.2),
            TimedText(text: "不", start: 0.2, end: 0.4),
            TimedText(text: "来", start: 0.4, end: 0.6),
            TimedText(text: "了", start: 0.6, end: 0.8),
            TimedText(text: "电", start: 1.0, end: 1.2),
            TimedText(text: "话", start: 1.2, end: 1.4),
            TimedText(text: "里", start: 1.4, end: 1.6),
            TimedText(text: "传", start: 1.6, end: 1.8),
            TimedText(text: "来", start: 1.8, end: 2.0),
            TimedText(text: "吼", start: 2.0, end: 2.2),
            TimedText(text: "声", start: 2.2, end: 2.4),
        ]

        let result = try SentenceTimingMapper(sampleRate: 24_000).map(
            items,
            transcript: text,
            transcriptUTF16Offset: 0,
            sentences: sentences
        )

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].frameRange, 0..<19_200)
        XCTAssertEqual(result[1].frameRange, 24_000..<57_600)
        XCTAssertEqual(result.map(\.sentence), sentences)
    }

    func testGlobalSentenceRangesUseTranscriptOffset() throws {
        let text = "第一句。第二句。"
        let globalOffset = 100
        let local = SentenceSegmenter().sentences(in: text, startingAt: 0, policy: .exactOffset, limit: 20)
        let global = local.map { sentence in
            SpeechSentence(
                text: sentence.text,
                utf16Range: (sentence.utf16Range.lowerBound + globalOffset)..<(sentence.utf16Range.upperBound + globalOffset)
            )
        }
        let items = [
            TimedText(text: "第", start: 0, end: 0.1),
            TimedText(text: "一", start: 0.1, end: 0.2),
            TimedText(text: "句", start: 0.2, end: 0.3),
            TimedText(text: "第", start: 0.4, end: 0.5),
            TimedText(text: "二", start: 0.5, end: 0.6),
            TimedText(text: "句", start: 0.6, end: 0.7),
        ]

        let result = try SentenceTimingMapper(sampleRate: 24_000).map(
            items,
            transcript: text,
            transcriptUTF16Offset: globalOffset,
            sentences: global
        )

        XCTAssertEqual(result.map(\.sentence.utf16Range), global.map(\.utf16Range))
    }

    func testUnmappedSpokenSentenceThrows() {
        let text = "第一句。第二句。"
        let sentences = SentenceSegmenter().sentences(in: text, startingAt: 0, policy: .exactOffset, limit: 20)

        XCTAssertThrowsError(
            try SentenceTimingMapper(sampleRate: 24_000).map(
                [TimedText(text: "第一句", start: 0, end: 0.3)],
                transcript: text,
                transcriptUTF16Offset: 0,
                sentences: sentences
            )
        )
    }

    func testAlignmentWithinAudioPassesValidation() {
        let mapped = [
            AlignedSentence(
                sentence: SpeechSentence(text: "第一句", utf16Range: 0..<3),
                frameRange: 0..<24_000
            ),
            AlignedSentence(
                sentence: SpeechSentence(text: "第二句", utf16Range: 3..<6),
                frameRange: 24_000..<48_000
            ),
        ]

        XCTAssertTrue(SpeechAlignmentValidation.fitsInAudio(mapped, audioFrameCount: 48_000))
    }

    func testAlignmentOverrunningAudioFailsValidation() {
        let mapped = [
            AlignedSentence(
                sentence: SpeechSentence(text: "第一句", utf16Range: 0..<3),
                frameRange: 0..<24_000
            ),
            AlignedSentence(
                sentence: SpeechSentence(text: "第二句", utf16Range: 3..<6),
                frameRange: 24_000..<100_000
            ),
        ]

        XCTAssertFalse(SpeechAlignmentValidation.fitsInAudio(mapped, audioFrameCount: 48_000))
    }

    func testAlignmentStartingPastAudioEndFailsValidation() {
        let mapped = [
            AlignedSentence(
                sentence: SpeechSentence(text: "第一句", utf16Range: 0..<3),
                frameRange: 0..<24_000
            ),
            AlignedSentence(
                sentence: SpeechSentence(text: "第二句", utf16Range: 3..<6),
                frameRange: 60_000..<70_000
            ),
        ]

        XCTAssertFalse(SpeechAlignmentValidation.fitsInAudio(mapped, audioFrameCount: 48_000))
    }
}
#endif

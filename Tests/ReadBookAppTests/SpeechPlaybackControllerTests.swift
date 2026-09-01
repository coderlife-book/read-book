#if os(macOS)
import AVFoundation
import XCTest
@testable import ReadBook
import ReadBookCore

@MainActor
final class SpeechPlaybackControllerTests: XCTestCase {
    func testRateClampsWithoutChangingSourceFrameSentenceBoundaries() {
        let timeline = SentencePlaybackTimeline(sentences: [
            .init(range: 0..<10, sourceFrames: 0..<24_000),
            .init(range: 10..<20, sourceFrames: 24_000..<48_000),
        ])

        XCTAssertEqual(timeline.sentence(atSourceFrame: 30_000)?.range, 10..<20)
        XCTAssertEqual(SpeechPlaybackRate.clamp(2.0), 1.5)
        XCTAssertEqual(SpeechPlaybackRate.clamp(0.1), 0.5)
    }

    func testPauseAndResumeKeepSourceFrame() {
        let driver = FakeAudioPlaybackDriver()
        let controller = SpeechPlaybackController(driver: driver)
        controller.enqueue(makePreparedSentence(range: 0..<10, frames: 48_000))
        controller.play()
        driver.sourceFrame = 12_000

        controller.pause()
        controller.play()

        XCTAssertEqual(driver.lastScheduledStartFrame, 12_000)
        XCTAssertEqual(controller.state, .playing)
    }

    func testCompletionAdvancesSentenceThenBuffersWhenEmpty() {
        let driver = FakeAudioPlaybackDriver()
        let controller = SpeechPlaybackController(driver: driver)
        controller.enqueue(makePreparedSentence(range: 0..<10, frames: 24_000))
        controller.enqueue(makePreparedSentence(range: 10..<20, frames: 24_000))

        controller.play()
        driver.complete()
        XCTAssertEqual(controller.currentSentenceRange, 10..<20)

        driver.complete()
        XCTAssertEqual(controller.state, .buffering)
        XCTAssertNil(controller.currentSentenceRange)
    }

    func testRateChangesApplyImmediately() {
        let driver = FakeAudioPlaybackDriver()
        let controller = SpeechPlaybackController(driver: driver)

        controller.setRate(1.8)

        XCTAssertEqual(driver.rate, 1.5)
    }

    private func makePreparedSentence(
        range: Range<Int>,
        frames: Int
    ) -> PreparedSentence {
        PreparedSentence(
            sentence: SpeechSentence(text: "句子", utf16Range: range),
            samples: Array(repeating: 0, count: frames),
            sampleRate: 24_000
        )
    }
}

@MainActor
private final class FakeAudioPlaybackDriver: AudioPlaybackDriving {
    var sourceFrame: AVAudioFramePosition = 0
    var onCompletion: (() -> Void)?
    var lastScheduledStartFrame: AVAudioFramePosition = 0
    var rate: Float = 1.0

    func schedule(
        samples: [Float],
        sampleRate: Int,
        startingAt frame: AVAudioFramePosition
    ) {
        lastScheduledStartFrame = frame
        sourceFrame = frame
    }

    func play() {}
    func pause() {}
    func stop() { sourceFrame = 0 }
    func setRate(_ rate: Float) { self.rate = rate }
    func complete() { onCompletion?() }
}
#endif

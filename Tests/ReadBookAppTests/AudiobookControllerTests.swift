#if os(macOS)
import Foundation
import XCTest
@testable import ReadBook
import ReadBookCore

@MainActor
final class AudiobookControllerTests: XCTestCase {
    func testSelectionStartsAtFirstSelectedUTF16CharacterAndClearsOldGeneration() async throws {
        let fixture = AudiobookFixture(text: "迟到那么久不说，你现在才告诉我？下一句。")
        let selected = (fixture.text as NSString).range(of: "现在")

        await fixture.controller.startFromSelection(selected, text: fixture.text)

        let blocks = await fixture.preparer.blocks
        XCTAssertEqual(blocks.first?.sentences.first?.text, "现在才告诉我？")
        let generation = await fixture.queue.currentGeneration
        let preparedGeneration = await fixture.preparer.lastGeneration
        XCTAssertEqual(generation, preparedGeneration)
        XCTAssertEqual(fixture.playback.state, .playing)
    }

    func testRefillStartsAtTenTargetsTwentyAndStopsAtThirty() async throws {
        let fixture = AudiobookFixture(sentenceCount: 100)

        await fixture.controller.startFromReadingPosition(text: fixture.text)
        for _ in 0..<10 {
            fixture.playback.complete(sentences: 1)
            let advanced = await waitUntil {
                fixture.playback.currentSentenceRange != nil
            }
            XCTAssertTrue(advanced, "expected playback to advance before timeout")
        }

        let refilled = await waitUntil {
            let count = await fixture.queue.count
            let callCount = await fixture.preparer.callCount
            return callCount > 1 && (10...30).contains(count)
        }
        let count = await fixture.queue.count
        let callCount = await fixture.preparer.callCount
        XCTAssertTrue(refilled, "expected queue refill before timeout")
        XCTAssertTrue(callCount > 1)
        XCTAssertTrue((10...30).contains(count))
    }

    func testFirstSentenceStartsBeforeBackgroundRefill() async {
        let fixture = AudiobookFixture(sentenceCount: 20)

        await fixture.controller.startFromReadingPosition(text: fixture.text)

        let blocks = await fixture.preparer.blocks
        XCTAssertEqual(blocks.first?.sentences.count, 1)
        XCTAssertEqual(fixture.playback.state, .playing)
    }

    func testQueueExhaustionBuffersThenAutomaticallyResumes() async throws {
        let preparer = ControlledRefillPreparer()
        let playback = RecordingPlayback()
        let controller = AudiobookController(preparer: preparer, playback: playback)
        let text = "第一句。第二句。第三句。"

        await controller.startFromReadingPosition(text: text)
        playback.complete(sentences: 1)
        let buffered = await waitUntil { controller.state == .buffering }
        XCTAssertTrue(buffered, "expected playback to buffer before timeout")
        XCTAssertEqual(controller.state, .buffering)

        await preparer.releaseRefill()
        let resumed = await waitUntil { controller.state == .playing }
        XCTAssertTrue(resumed, "expected playback to resume before timeout")
        XCTAssertEqual(controller.state, .playing)
        XCTAssertNotNil(controller.highlightedRange)
    }

    func testFinishingLastSentenceClearsHighlightAndStops() async {
        let fixture = AudiobookFixture(text: "只有一句。")

        await fixture.controller.startFromReadingPosition(text: fixture.text)
        fixture.playback.complete(sentences: 1)
        for _ in 0..<8 { await Task.yield() }

        XCTAssertEqual(fixture.controller.state, .idle)
        XCTAssertNil(fixture.controller.highlightedRange)
        XCTAssertEqual(fixture.playback.state, .idle)
    }

    func testOlderSlowStartCannotOverwriteNewSelection() async throws {
        let preparer = OldSessionDelayedPreparer()
        let playback = RecordingPlayback()
        let controller = AudiobookController(preparer: preparer, playback: playback)
        let oldText = "旧会话第一句。旧会话第二句。"
        let newText = "新会话第一句。新会话第二句。"

        let oldStart = Task { await controller.startFromReadingPosition(text: oldText) }
        try await Task.sleep(for: .milliseconds(20))
        await controller.startFromReadingPosition(text: newText)
        await oldStart.value
        try await Task.sleep(for: .milliseconds(140))

        let newRange = (newText as NSString).range(of: "新会话第一句。")
        XCTAssertEqual(controller.highlightedRange, newRange.location..<NSMaxRange(newRange))
        XCTAssertEqual(playback.currentSentenceRange, newRange.location..<NSMaxRange(newRange))
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @MainActor () async -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !(await condition()) {
            guard clock.now < deadline else { return false }
            await Task.yield()
        }
        return true
    }
}

private actor ControlledRefillPreparer: SpeechPreparing {
    private var callCount = 0
    private var refillContinuation: CheckedContinuation<Void, Never>?
    private var refillReleased = false

    func prepare(_ block: SpeechBlock, generation: SpeechGenerationID) async throws -> PreparedSpeechBlock {
        callCount += 1
        if callCount > 1, !refillReleased {
            await withCheckedContinuation { refillContinuation = $0 }
        }
        return PreparedSpeechBlock(sentences: block.sentences.map {
            PreparedSentence(sentence: $0, samples: [0, 0, 0], sampleRate: 24_000)
        })
    }

    func releaseRefill() {
        refillReleased = true
        refillContinuation?.resume()
        refillContinuation = nil
    }
}

private actor OldSessionDelayedPreparer: SpeechPreparing {
    func prepare(_ block: SpeechBlock, generation: SpeechGenerationID) async throws -> PreparedSpeechBlock {
        if block.text.hasPrefix("旧会话") {
            try await Task.sleep(for: .milliseconds(100))
        }
        return PreparedSpeechBlock(sentences: block.sentences.map {
            PreparedSentence(sentence: $0, samples: [0, 0, 0], sampleRate: 24_000)
        })
    }
}

private actor RecordingPreparer: SpeechPreparing {
    private(set) var blocks: [SpeechBlock] = []
    private(set) var generations: [SpeechGenerationID] = []

    var callCount: Int { blocks.count }
    var lastGeneration: SpeechGenerationID? { generations.last }

    func prepare(_ block: SpeechBlock, generation: SpeechGenerationID) async throws -> PreparedSpeechBlock {
        blocks.append(block)
        generations.append(generation)
        return PreparedSpeechBlock(sentences: block.sentences.map {
            PreparedSentence(sentence: $0, samples: [0, 0, 0], sampleRate: 24_000)
        })
    }
}

@MainActor
private final class RecordingPlayback: AudiobookPlaybackControlling {
    private(set) var state: SpeechPlaybackState = .idle
    private(set) var currentSentenceRange: Range<Int>?
    var onSentenceFinished: (() -> Void)?

    private var queued: [PreparedSentence] = []

    func enqueue(_ sentence: PreparedSentence) {
        queued.append(sentence)
    }

    func play() {
        state = .playing
        currentSentenceRange = queued.first?.sentence.utf16Range
    }

    func pause() { state = .paused }
    func stop() { state = .idle; currentSentenceRange = nil; queued.removeAll() }
    func setRate(_: Double) {}

    func complete(sentences count: Int) {
        for _ in 0..<count {
            guard !queued.isEmpty else { return }
            queued.removeFirst()
            currentSentenceRange = nil
            onSentenceFinished?()
        }
    }
}

@MainActor
private final class AudiobookFixture {
    let text: String
    let preparer = RecordingPreparer()
    let queue = SpeechQueue()
    let playback = RecordingPlayback()
    lazy var controller = AudiobookController(
        preparer: preparer,
        queue: queue,
        playback: playback
    )

    init(text: String) { self.text = text }

    convenience init(sentenceCount: Int) {
        self.init(text: (1...sentenceCount).map { "第\($0)句。" }.joined())
    }
}
#endif

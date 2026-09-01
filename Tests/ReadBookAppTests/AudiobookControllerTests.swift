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
            for _ in 0..<4 { await Task.yield() }
        }

        let count = await fixture.queue.count
        let callCount = await fixture.preparer.callCount
        XCTAssertTrue(callCount > 1)
        XCTAssertTrue((10...30).contains(count))
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

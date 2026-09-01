import Foundation
import Observation
import ReadBookCore

@MainActor
protocol AudiobookPlaybackControlling: AnyObject {
    var state: SpeechPlaybackState { get }
    var currentSentenceRange: Range<Int>? { get }
    var onSentenceFinished: (() -> Void)? { get set }

    func enqueue(_ sentence: PreparedSentence)
    func play()
    func pause()
    func stop()
    func setRate(_ value: Double)
}

extension SpeechPlaybackController: AudiobookPlaybackControlling {
}

enum SpeechStopReason: Equatable, Sendable {
    case user
    case selectionJump
    case bookChanged
    case bookRemoved
    case modelDeleted
    case applicationTermination
}

@MainActor
@Observable
final class AudiobookController {
    private let preparer: any SpeechPreparing
    private let queue: SpeechQueue
    private let playback: any AudiobookPlaybackControlling
    private let segmenter = SentenceSegmenter()
    private var sourceText = ""
    private var nextSentenceIndex = 0
    private var generation: SpeechGenerationID?
    private var refillTask: Task<Void, Never>?

    private(set) var state: SpeechPlaybackState = .idle
    private(set) var highlightedRange: Range<Int>?
    private(set) var queuedSentenceCount = 0
    var onPositionChange: ((BookPosition) -> Void)?

    init(
        preparer: any SpeechPreparing,
        queue: SpeechQueue = SpeechQueue(),
        playback: any AudiobookPlaybackControlling
    ) {
        self.preparer = preparer
        self.queue = queue
        self.playback = playback
        playback.onSentenceFinished = { [weak self] in
            Task { @MainActor in await self?.sentenceFinished() }
        }
    }

    func startFromReadingPosition(text: String, position: BookPosition = .zero) async {
        await start(text: text, offset: position.utf16Offset, policy: .containingSentence)
    }

    func startFromSelection(_ range: NSRange, text: String) async {
        await start(text: text, offset: range.location, policy: .exactOffset)
    }

    func togglePlayback() async {
        switch state {
        case .playing:
            playback.pause()
            state = .paused
        case .paused, .buffering, .preparing:
            playback.play()
            state = .playing
        case .idle:
            playback.play()
            state = .playing
        case .failed:
            break
        }
    }

    func setRate(_ value: Double) {
        playback.setRate(value)
    }

    func stop(reason _: SpeechStopReason = .user) async {
        refillTask?.cancel()
        refillTask = nil
        _ = await queue.restart()
        generation = nil
        nextSentenceIndex = 0
        sourceText = ""
        playback.stop()
        state = .idle
        highlightedRange = nil
        queuedSentenceCount = 0
    }

    private func start(text: String, offset: Int, policy: SpeechStartPolicy) async {
        await stop(reason: .selectionJump)
        sourceText = text
        let sentences = segmenter.sentences(in: text, startingAt: offset, policy: policy, limit: text.utf16.count)
        guard !sentences.isEmpty else { return }
        nextSentenceIndex = 0
        generation = await queue.restart()
        state = .preparing
        await refill(sentences: sentences, generation: generation!)
        await playNextIfNeeded()
    }

    private func refill(sentences: [SpeechSentence], generation: SpeechGenerationID) async {
        while await queue.count < queue.targetCount, nextSentenceIndex < sentences.count {
            let count = await queue.count
            let remaining = min(queue.targetCount - count, queue.hardLimit - count)
            guard remaining > 0 else { break }
            let selected = Array(sentences[nextSentenceIndex..<min(nextSentenceIndex + remaining, sentences.count)])
            nextSentenceIndex += selected.count
            guard let first = selected.first, let last = selected.last else { break }
            let block = SpeechBlock(
                text: (sourceText as NSString).substring(with: NSRange(location: first.utf16Range.lowerBound, length: last.utf16Range.upperBound - first.utf16Range.lowerBound)),
                sentences: selected,
                utf16Range: first.utf16Range.lowerBound..<last.utf16Range.upperBound
            )
            do {
                let prepared = try await preparer.prepare(block, generation: generation)
                await queue.append(prepared.sentences, generation: generation)
            } catch is CancellationError {
                return
            } catch {
                state = .failed("听书生成失败，请稍后重试。")
                return
            }
            queuedSentenceCount = await queue.count
        }
        queuedSentenceCount = await queue.count
    }

    private func playNextIfNeeded() async {
        guard playback.currentSentenceRange == nil else { return }
        guard let sentence = await queue.popFirst() else { return }
        playback.enqueue(sentence)
        queuedSentenceCount = await queue.count
        highlightedRange = sentence.sentence.utf16Range
        onPositionChange?(BookPosition(utf16Offset: sentence.sentence.utf16Range.lowerBound))
        playback.play()
        state = .playing
    }

    private func sentenceFinished() async {
        await playNextIfNeeded()
        queuedSentenceCount = await queue.count
        guard state == .playing else { return }
        guard queuedSentenceCount <= queue.lowWatermark else { return }
        let text = sourceText
        let generation = generation
        let sentences = segmenter.sentences(in: text, startingAt: nextOffset, policy: .exactOffset, limit: text.utf16.count)
        guard let generation else { return }
        refillTask?.cancel()
        refillTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.refill(sentences: sentences, generation: generation)
        }
    }

    private var nextOffset: Int {
        guard nextSentenceIndex < segmenter.sentences(in: sourceText, startingAt: 0, policy: .exactOffset, limit: sourceText.utf16.count).count else {
            return sourceText.utf16.count
        }
        return segmenter.sentences(in: sourceText, startingAt: 0, policy: .exactOffset, limit: sourceText.utf16.count)[nextSentenceIndex].utf16Range.lowerBound
    }
}

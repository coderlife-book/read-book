@preconcurrency import AVFoundation
import Observation

@MainActor
protocol AudioPlaybackDriving: AnyObject {
    var sourceFrame: AVAudioFramePosition { get }
    var onCompletion: (() -> Void)? { get set }

    func schedule(
        samples: [Float],
        sampleRate: Int,
        startingAt frame: AVAudioFramePosition
    )
    func play()
    func pause()
    func stop()
    func setRate(_ rate: Float)
}

enum SpeechPlaybackState: Equatable, Sendable {
    case idle
    case preparing
    case playing
    case paused
    case buffering
    case failed(String)
}

enum SpeechPlaybackRate {
    static func clamp(_ value: Double) -> Double {
        min(max(value, 0.5), 1.5)
    }
}

struct SentencePlaybackTimeline {
    struct Entry: Equatable {
        let range: Range<Int>
        let sourceFrames: Range<Int64>
    }

    let sentences: [Entry]

    func sentence(atSourceFrame frame: Int64) -> Entry? {
        sentences.first { $0.sourceFrames.contains(frame) }
    }
}

@MainActor
@Observable
final class SpeechPlaybackController {
    private let driver: any AudioPlaybackDriving
    private var pending: [PreparedSentence] = []
    private var current: PreparedSentence?
    private var pausedFrame: AVAudioFramePosition = 0

    private(set) var state: SpeechPlaybackState = .idle
    private(set) var currentSentenceRange: Range<Int>?
    var onSentenceFinished: (() -> Void)?

    init(driver: any AudioPlaybackDriving = AVAudioPlaybackDriver()) {
        self.driver = driver
        self.driver.onCompletion = { [weak self] in
            self?.didFinishCurrentSentence()
        }
    }

    func enqueue(_ sentence: PreparedSentence) {
        pending.append(sentence)
    }

    func play() {
        if state == .paused, let current {
            schedule(current, startingAt: pausedFrame)
            driver.play()
            state = .playing
            return
        }

        if current == nil {
            guard startNextSentence() else {
                state = .buffering
                return
            }
        }

        driver.play()
        state = .playing
    }

    func pause() {
        guard state == .playing else { return }
        pausedFrame = driver.sourceFrame
        driver.pause()
        state = .paused
    }

    func stop() {
        driver.stop()
        pending.removeAll(keepingCapacity: false)
        current = nil
        pausedFrame = 0
        currentSentenceRange = nil
        state = .idle
    }

    func setRate(_ value: Double) {
        driver.setRate(Float(SpeechPlaybackRate.clamp(value)))
    }

    private func didFinishCurrentSentence() {
        onSentenceFinished?()
        current = nil
        pausedFrame = 0

        guard startNextSentence() else {
            currentSentenceRange = nil
            state = .buffering
            return
        }

        driver.play()
        state = .playing
    }

    @discardableResult
    private func startNextSentence() -> Bool {
        guard !pending.isEmpty else { return false }
        let sentence = pending.removeFirst()
        current = sentence
        currentSentenceRange = sentence.sentence.utf16Range
        schedule(sentence, startingAt: 0)
        return true
    }

    private func schedule(
        _ sentence: PreparedSentence,
        startingAt frame: AVAudioFramePosition
    ) {
        state = .preparing
        driver.schedule(
            samples: sentence.samples,
            sampleRate: sentence.sampleRate,
            startingAt: frame
        )
    }
}

@MainActor
final class AVAudioPlaybackDriver: AudioPlaybackDriving {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private var scheduledStartFrame: AVAudioFramePosition = 0
    private var configuredSampleRate: Double?
    private var scheduleID: UInt64 = 0

    var onCompletion: (() -> Void)?

    var sourceFrame: AVAudioFramePosition {
        guard
            let renderTime = player.lastRenderTime,
            let playerTime = player.playerTime(forNodeTime: renderTime)
        else {
            return scheduledStartFrame
        }
        return scheduledStartFrame + playerTime.sampleTime
    }

    init() {
        engine.attach(player)
        engine.attach(timePitch)
    }

    func schedule(
        samples: [Float],
        sampleRate: Int,
        startingAt frame: AVAudioFramePosition
    ) {
        scheduleID &+= 1
        let currentScheduleID = scheduleID
        player.stop()

        let safeStart = max(0, min(Int64(samples.count), frame))
        scheduledStartFrame = safeStart

        guard safeStart < samples.count else {
            onCompletion?()
            return
        }

        let rate = Double(sampleRate)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: rate,
            channels: 1,
            interleaved: false
        ) else {
            return
        }

        configureGraphIfNeeded(format: format)

        let remainingCount = samples.count - Int(safeStart)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(remainingCount)
        ) else {
            return
        }
        buffer.frameLength = AVAudioFrameCount(remainingCount)
        samples.withUnsafeBufferPointer { source in
            guard let destination = buffer.floatChannelData?[0] else { return }
            destination.update(
                from: source.baseAddress!.advanced(by: Int(safeStart)),
                count: remainingCount
            )
        }

        player.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.scheduleID == currentScheduleID else { return }
                self.onCompletion?()
            }
        }
    }

    func play() {
        do {
            if !engine.isRunning {
                try engine.start()
            }
            player.play()
        } catch {
            stop()
        }
    }

    func pause() {
        player.pause()
    }

    func stop() {
        scheduleID &+= 1
        player.stop()
        scheduledStartFrame = 0
    }

    func setRate(_ rate: Float) {
        timePitch.rate = rate
    }

    private func configureGraphIfNeeded(format: AVAudioFormat) {
        guard configuredSampleRate != format.sampleRate else { return }
        if engine.isRunning {
            engine.stop()
        }
        engine.disconnectNodeOutput(player)
        engine.disconnectNodeOutput(timePitch)
        engine.connect(player, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
        engine.prepare()
        configuredSampleRate = format.sampleRate
    }
}

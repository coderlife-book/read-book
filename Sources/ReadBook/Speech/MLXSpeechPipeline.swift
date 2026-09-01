import Foundation
import MLXAudioSTT
import MLXAudioTTS

protocol SpeechPreparing: Sendable {
    func prepare(
        _ block: SpeechBlock,
        generation: SpeechGenerationID
    ) async throws -> PreparedSpeechBlock
}

actor MLXSpeechPipeline: SpeechPreparing {
    static let serenaPrompt = "Serena, 使用清澈、干净、少气声、不沙哑的年轻女声，像专业有声书主播一样朗读。对白情绪自然，旁白克制沉浸，吐字清晰，停顿合理。"

    private let locations: SpeechModelLocations
    private var ttsModel: Qwen3TTSModel?
    private var alignerModel: Qwen3ForcedAlignerModel?

    init(locations: SpeechModelLocations) {
        self.locations = locations
    }

    func prepare(
        _ block: SpeechBlock,
        generation: SpeechGenerationID
    ) async throws -> PreparedSpeechBlock {
        let tts = try await loadTTS()
        let audio = try await tts.generate(
            text: block.text,
            voice: Self.serenaPrompt,
            refAudio: nil,
            refText: nil,
            language: "Chinese"
        )
        let samples = audio.asArray(Float.self)
        let aligner = try await loadAligner()
        let alignment = aligner.generate(audio: audio, text: block.text, language: "Chinese")

        do {
            let mapped = try SentenceTimingMapper(sampleRate: tts.sampleRate).map(
                alignment.items.map {
                    TimedText(text: $0.text, start: $0.startTime, end: $0.endTime)
                },
                transcript: block.text,
                transcriptUTF16Offset: block.utf16Range.lowerBound,
                sentences: block.sentences
            )
            return PreparedSpeechBlock(sentences: mapped.map { aligned in
                let lower = min(max(Int(aligned.frameRange.lowerBound), 0), samples.count)
                let upper = min(max(Int(aligned.frameRange.upperBound), lower), samples.count)
                return PreparedSentence(
                    sentence: aligned.sentence,
                    samples: Array(samples[lower..<upper]),
                    sampleRate: tts.sampleRate
                )
            })
        } catch is SpeechAlignmentError {
            return try await prepareSentenceFallback(block)
        }
    }

    private func prepareSentenceFallback(_ block: SpeechBlock) async throws -> PreparedSpeechBlock {
        let tts = try await loadTTS()
        var result: [PreparedSentence] = []
        for sentence in block.sentences {
            let audio = try await tts.generate(
                text: sentence.text,
                voice: Self.serenaPrompt,
                refAudio: nil,
                refText: nil,
                language: "Chinese"
            )
            result.append(PreparedSentence(
                sentence: sentence,
                samples: audio.asArray(Float.self),
                sampleRate: tts.sampleRate
            ))
        }
        return PreparedSpeechBlock(sentences: result)
    }

    private func loadTTS() async throws -> Qwen3TTSModel {
        if let ttsModel { return ttsModel }
        guard let directory = locations.tts else { throw SpeechPipelineError.missingTTSModel }
        let model = try await Qwen3TTSModel.fromModelDirectory(directory)
        ttsModel = model
        return model
    }

    private func loadAligner() async throws -> Qwen3ForcedAlignerModel {
        if let alignerModel { return alignerModel }
        guard let directory = locations.aligner else { throw SpeechPipelineError.missingAlignerModel }
        let model = try await Qwen3ForcedAlignerModel.fromModelDirectory(directory)
        alignerModel = model
        return model
    }
}

enum SpeechPipelineError: Error, Equatable {
    case missingTTSModel
    case missingAlignerModel
}

#if os(macOS)
import Foundation
import MLXAudioSTT
import MLXAudioTTS
import ReadBookCore
import XCTest
@testable import ReadBook

final class SpeechModelCompatibilityTests: XCTestCase {
    func testPinnedQwenModelsGenerateAndAlignChineseWhenOptedIn() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["READBOOK_RUN_SPEECH_MODEL_TESTS"] == "1" else {
            throw XCTSkip("Set READBOOK_RUN_SPEECH_MODEL_TESTS=1 for the local model test")
        }

        let ttsURL = URL(
            fileURLWithPath: try XCTUnwrap(environment["READBOOK_TTS_MODEL_DIR"]),
            isDirectory: true
        )
        let alignerURL = URL(
            fileURLWithPath: try XCTUnwrap(environment["READBOOK_ALIGNER_MODEL_DIR"]),
            isDirectory: true
        )
        let text = "你现在才告诉我？电话里传来一阵吼声。"

        let tts = try await Qwen3TTSModel.fromModelDirectory(ttsURL)
        let audio = try await tts.generate(
            text: text,
            voice: "Serena, 清澈、干净、少气声，像专业有声书主播一样朗读。",
            refAudio: nil,
            refText: nil,
            language: "Chinese"
        )
        XCTAssertGreaterThan(audio.size, 0)

        let aligner = try await Qwen3ForcedAlignerModel.fromModelDirectory(alignerURL)
        let result = aligner.generate(audio: audio, text: text, language: "Chinese")
        XCTAssertFalse(result.items.isEmpty)
        XCTAssertTrue(zip(result.items, result.items.dropFirst()).allSatisfy { pair in
            pair.0.endTime <= pair.1.startTime
        })
    }

    func testNativePipelinePreparesEverySentenceWhenOptedIn() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["READBOOK_RUN_SPEECH_MODEL_TESTS"] == "1" else {
            throw XCTSkip("Set READBOOK_RUN_SPEECH_MODEL_TESTS=1 for the local model test")
        }
        let ttsURL = URL(
            fileURLWithPath: try XCTUnwrap(environment["READBOOK_TTS_MODEL_DIR"]),
            isDirectory: true
        )
        let alignerURL = URL(
            fileURLWithPath: try XCTUnwrap(environment["READBOOK_ALIGNER_MODEL_DIR"]),
            isDirectory: true
        )
        let text = "你现在才告诉我？电话里传来一阵吼声。"
        let sentences = SentenceSegmenter().sentences(
            in: text,
            startingAt: 0,
            policy: .exactOffset,
            limit: 20
        )
        let pipeline = MLXSpeechPipeline(locations: SpeechModelLocations(
            tts: ttsURL,
            aligner: alignerURL
        ))

        let result = try await pipeline.prepare(
            SpeechBlock(text: text, sentences: sentences, utf16Range: 0..<(text as NSString).length),
            generation: SpeechGenerationID(rawValue: 1)
        )

        XCTAssertEqual(result.sentences.map(\.sentence), sentences)
        XCTAssertTrue(result.sentences.allSatisfy { !$0.samples.isEmpty })
    }
}
#endif

import Foundation
import ReadBookCore

struct SpeechBlock: Equatable, Sendable {
    let text: String
    let sentences: [SpeechSentence]
    let utf16Range: Range<Int>
}

struct PreparedSentence: Equatable, Sendable {
    let sentence: SpeechSentence
    let samples: [Float]
    let sampleRate: Int
}

struct PreparedSpeechBlock: Equatable, Sendable {
    let sentences: [PreparedSentence]
}

struct SpeechGenerationID: Hashable, Sendable {
    let rawValue: UInt64
}

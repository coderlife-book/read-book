import Foundation
import ReadBookCore

struct TimedText: Equatable, Sendable {
    let text: String
    let start: Double
    let end: Double
}

struct AlignedSentence: Equatable, Sendable {
    let sentence: SpeechSentence
    let frameRange: Range<Int64>
}

enum SpeechAlignmentError: Error, Equatable {
    case invalidSampleRate
    case tokenNotFound(String)
    case unmappedSentence(Range<Int>)
}

struct SentenceTimingMapper: Sendable {
    let sampleRate: Int

    func map(
        _ items: [TimedText],
        transcript: String,
        transcriptUTF16Offset: Int,
        sentences: [SpeechSentence]
    ) throws -> [AlignedSentence] {
        guard sampleRate > 0 else { throw SpeechAlignmentError.invalidSampleRate }
        let units = spokenUnits(in: transcript, globalOffset: transcriptUTF16Offset)
        var searchStart = 0
        var timings: [(start: Double, end: Double)?] = Array(repeating: nil, count: sentences.count)
        var matchedUnitIndices = Set<Int>()

        for item in items {
            let keys = normalizedCharacters(in: item.text)
            guard !keys.isEmpty else { continue }
            guard let matchStart = find(keys, in: units, startingAt: searchStart) else {
                throw SpeechAlignmentError.tokenNotFound(item.text)
            }

            for unitIndex in matchStart..<(matchStart + keys.count) {
                matchedUnitIndices.insert(unitIndex)
                let globalOffset = units[unitIndex].globalUTF16Offset
                guard let sentenceIndex = sentences.firstIndex(where: {
                    $0.utf16Range.contains(globalOffset)
                }) else { continue }
                if let current = timings[sentenceIndex] {
                    timings[sentenceIndex] = (
                        start: min(current.start, item.start),
                        end: max(current.end, item.end)
                    )
                } else {
                    timings[sentenceIndex] = (start: item.start, end: item.end)
                }
            }
            searchStart = matchStart + keys.count
        }

        for sentence in sentences {
            let expectedIndices = units.indices.filter {
                sentence.utf16Range.contains(units[$0].globalUTF16Offset)
            }
            if !expectedIndices.isEmpty,
               !expectedIndices.allSatisfy({ matchedUnitIndices.contains($0) }) {
                throw SpeechAlignmentError.unmappedSentence(sentence.utf16Range)
            }
        }

        return try sentences.enumerated().map { index, sentence in
            guard let timing = timings[index] else {
                throw SpeechAlignmentError.unmappedSentence(sentence.utf16Range)
            }
            let lower = Int64((timing.start * Double(sampleRate)).rounded())
            let upper = Int64((timing.end * Double(sampleRate)).rounded())
            return AlignedSentence(sentence: sentence, frameRange: lower..<max(upper, lower + 1))
        }
    }

    private struct SpokenUnit {
        let key: Character
        let globalUTF16Offset: Int
    }

    private func spokenUnits(in text: String, globalOffset: Int) -> [SpokenUnit] {
        let source = text as NSString
        var result: [SpokenUnit] = []
        var offset = 0
        while offset < source.length {
            let range = source.rangeOfComposedCharacterSequence(at: offset)
            let value = source.substring(with: range)
            for key in normalizedCharacters(in: value) {
                result.append(SpokenUnit(key: key, globalUTF16Offset: globalOffset + range.location))
            }
            offset = NSMaxRange(range)
        }
        return result
    }

    private func normalizedCharacters(in text: String) -> [Character] {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private func find(
        _ keys: [Character],
        in units: [SpokenUnit],
        startingAt start: Int
    ) -> Int? {
        guard !keys.isEmpty, keys.count <= units.count else { return nil }
        let finalStart = units.count - keys.count
        guard start <= finalStart else { return nil }
        for candidate in start...finalStart {
            if zip(keys.indices, keys).allSatisfy({ units[candidate + $0.0].key == $0.1 }) {
                return candidate
            }
        }
        return nil
    }
}

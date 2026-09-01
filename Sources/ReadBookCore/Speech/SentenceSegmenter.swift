import Foundation

public struct SentenceSegmenter: Sendable {
    private static let terminators: Set<unichar> = [
        0x3002, // 。
        0xFF01, // ！
        0xFF1F, // ？
        0x0021, // !
        0x003F, // ?
    ]

    private static let trailingClosers: Set<unichar> = [
        0x201D, // ”
        0x2019, // ’
        0x300D, // 」
        0x300F, // 』
        0x3011, // 】
        0x0029, // )
    ]

    public init() {}

    public func sentences(
        in text: String,
        startingAt rawOffset: Int,
        policy: SpeechStartPolicy,
        limit: Int
    ) -> [SpeechSentence] {
        guard limit > 0 else { return [] }
        let source = text as NSString
        guard source.length > 0 else { return [] }

        let offset = composedCharacterStart(in: source, at: rawOffset)
        let start: Int
        switch policy {
        case .exactOffset:
            start = offset
        case .containingSentence:
            let allRanges = segmentRanges(in: source, startingAt: 0)
            start = allRanges.first(where: { range in
                offset < range.upperBound
            })?.lowerBound ?? source.length
        }

        return segmentRanges(in: source, startingAt: start)
            .prefix(limit)
            .map { range in
                let nsRange = NSRange(location: range.lowerBound, length: range.count)
                return SpeechSentence(
                    text: source.substring(with: nsRange),
                    utf16Range: range
                )
            }
    }

    private func segmentRanges(in source: NSString, startingAt rawStart: Int) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var sentenceStart = skipWhitespace(in: source, from: rawStart)
        var cursor = sentenceStart

        while cursor < source.length {
            let unit = source.character(at: cursor)
            var sentenceEnd: Int?

            if Self.terminators.contains(unit) {
                sentenceEnd = cursor + 1
            } else if unit == 0x2026,
                      cursor + 1 < source.length,
                      source.character(at: cursor + 1) == 0x2026 {
                sentenceEnd = cursor + 2
            }

            if var end = sentenceEnd {
                while end < source.length, Self.trailingClosers.contains(source.character(at: end)) {
                    end += 1
                }
                if sentenceStart < end {
                    result.append(sentenceStart..<end)
                }
                sentenceStart = skipWhitespace(in: source, from: end)
                cursor = sentenceStart
            } else {
                cursor = NSMaxRange(source.rangeOfComposedCharacterSequence(at: cursor))
            }
        }

        if sentenceStart < source.length {
            result.append(sentenceStart..<source.length)
        }
        return result
    }

    private func composedCharacterStart(in source: NSString, at rawOffset: Int) -> Int {
        let clamped = min(max(rawOffset, 0), source.length)
        guard clamped < source.length else { return source.length }
        return source.rangeOfComposedCharacterSequence(at: clamped).location
    }

    private func skipWhitespace(in source: NSString, from rawOffset: Int) -> Int {
        var offset = min(max(rawOffset, 0), source.length)
        while offset < source.length {
            let unit = source.character(at: offset)
            guard let scalar = UnicodeScalar(unit),
                  CharacterSet.whitespacesAndNewlines.contains(scalar) else { break }
            offset += 1
        }
        return offset
    }
}

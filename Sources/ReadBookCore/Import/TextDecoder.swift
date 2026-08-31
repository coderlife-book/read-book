import CoreFoundation
import Foundation

public struct DecodedText: Equatable, Sendable {
    public let text: String
    public let encoding: ImportedTextEncoding

    public init(text: String, encoding: ImportedTextEncoding) {
        self.text = text
        self.encoding = encoding
    }
}

public enum TextDecoderError: Error, Equatable, Sendable {
    case emptyInput
    case undecodable
}

public struct TextDecoder: Sendable {
    public init() {}

    public func decode(_ data: Data, override: ImportedTextEncoding? = nil) throws -> DecodedText {
        guard !data.isEmpty else { throw TextDecoderError.emptyInput }

        if let override {
            guard let text = String(data: data, encoding: stringEncoding(for: override)) else {
                throw TextDecoderError.undecodable
            }
            return DecodedText(text: normalize(text), encoding: override)
        }

        if data.starts(with: [0xEF, 0xBB, 0xBF]),
           let text = String(data: Data(data.dropFirst(3)), encoding: .utf8) {
            return DecodedText(text: normalize(text), encoding: .utf8)
        }
        if data.starts(with: [0xFF, 0xFE]),
           let text = String(data: Data(data.dropFirst(2)), encoding: .utf16LittleEndian) {
            return DecodedText(text: normalize(text), encoding: .utf16LittleEndian)
        }
        if data.starts(with: [0xFE, 0xFF]),
           let text = String(data: Data(data.dropFirst(2)), encoding: .utf16BigEndian) {
            return DecodedText(text: normalize(text), encoding: .utf16BigEndian)
        }
        if let text = String(data: data, encoding: .utf8) {
            return DecodedText(text: normalize(text), encoding: .utf8)
        }

        let legacyCandidates: [ImportedTextEncoding] = [.gb18030, .big5]
        let decodedLegacy = legacyCandidates.compactMap { candidate -> (ImportedTextEncoding, String, Int)? in
            guard let raw = String(data: data, encoding: stringEncoding(for: candidate)) else { return nil }
            let text = normalize(raw)
            guard plausible(text) else { return nil }
            return (candidate, text, qualityScore(text))
        }

        if let best = decodedLegacy.max(by: { lhs, rhs in
            if lhs.2 == rhs.2 {
                // Simplified-Chinese GB18030 is more common for mainland TXT sources,
                // so only use it as a deterministic tie-breaker after quality scoring.
                return lhs.0 == .big5 && rhs.0 == .gb18030
            }
            return lhs.2 < rhs.2
        }), best.2 > 0 {
            return DecodedText(text: best.1, encoding: best.0)
        }

        // UTF-16 without a BOM is uncommon, but keep a conservative fallback.
        for candidate in [ImportedTextEncoding.utf16LittleEndian, .utf16BigEndian] {
            if let raw = String(data: data, encoding: stringEncoding(for: candidate)) {
                let text = normalize(raw)
                if plausible(text), qualityScore(text) > 0 {
                    return DecodedText(text: text, encoding: candidate)
                }
            }
        }

        throw TextDecoderError.undecodable
    }

    public func stringEncoding(for encoding: ImportedTextEncoding) -> String.Encoding {
        switch encoding {
        case .utf8:
            return .utf8
        case .utf16LittleEndian:
            return .utf16LittleEndian
        case .utf16BigEndian:
            return .utf16BigEndian
        case .gb18030:
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            ))
        case .big5:
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.big5.rawValue)
            ))
        }
    }

    private func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{0000}", with: "")
    }

    private func plausible(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let scalarCount = text.unicodeScalars.count
        let controls = text.unicodeScalars.reduce(into: 0) { count, scalar in
            if scalar.value < 0x20 && scalar.value != 0x0A && scalar.value != 0x09 {
                count += 1
            }
        }
        return controls * 100 < max(scalarCount, 1)
    }

    /// Legacy Chinese encodings overlap heavily: arbitrary Big5 bytes can often
    /// be decoded as GB18030 (and vice versa) without throwing. Rank successful
    /// decodes by how much they resemble ordinary Chinese prose instead of
    /// accepting the first decoder that returns a String.
    private func qualityScore(_ text: String) -> Int {
        let commonChinese = Set("的一是在不了有和人这中大为上个国我以要他时来用们生到作地于出就分对成会可主发年动同工也能下过子说产种面而方后多定行学法所民得经十三之进着等部度家电力里如水化高自二理起小物现实加量都两体制机当使点从业本去把性好应开它合还因由其些然前外天政四日那社义事平形相全表间样与關關與與後羅蘭夜鶯邊境鎮書讀章回卷第正文序楔番記")
        let prosePunctuation = Set("，。！？；：、“”‘’（）()《》…—,.!?;:\n\t ")

        var score = 0
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if value == 0xFFFD {
                score -= 120
            } else if (0xE000...0xF8FF).contains(value) {
                score -= 30
            } else if value < 0x20 && value != 0x0A && value != 0x09 {
                score -= 60
            } else if (0x4E00...0x9FFF).contains(value) {
                score += 2
            }
        }

        for character in text {
            if commonChinese.contains(character) { score += 3 }
            if prosePunctuation.contains(character) { score += 1 }
        }

        for marker in ["第", "章", "回", "卷", "正文", "序章", "楔子", "番外", "后记", "後記"] {
            score += occurrences(of: marker, in: text) * 12
        }

        return score
    }

    private func occurrences(of needle: String, in text: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: needle, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<text.endIndex
        }
        return count
    }
}

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

        for candidate in [ImportedTextEncoding.gb18030, .big5, .utf16LittleEndian, .utf16BigEndian] {
            if let text = String(data: data, encoding: stringEncoding(for: candidate)), plausible(text) {
                return DecodedText(text: normalize(text), encoding: candidate)
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
}

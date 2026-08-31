import Foundation

public struct ChapterParser: Sendable {
    private static let numeral = "零〇一二三四五六七八九十百千万两0-9０-９"
    private static let pattern = "(?m)^[\\t 　]*(?:(?:第[\(numeral) ]{1,12}[章回卷部篇节])|(?:卷[\(numeral)]{1,8})|(?:序章|楔子|番外[\(numeral)]{0,8}|后记))[^\\r\\n]{0,40}$"

    public init() {}

    public func parse(_ text: String) throws -> [Chapter] {
        let regex = try NSRegularExpression(pattern: Self.pattern)
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        return regex.matches(in: text, range: fullRange).compactMap { match in
            let raw = nsText.substring(with: match.range)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return nil }
            let leadingWhitespace = (nsText.substring(with: match.range) as NSString)
                .range(of: raw).location
            return Chapter(title: raw, utf16Offset: match.range.location + max(leadingWhitespace, 0))
        }
    }
}

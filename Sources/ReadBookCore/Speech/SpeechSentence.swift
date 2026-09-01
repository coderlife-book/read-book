import Foundation

public struct SpeechSentence: Equatable, Sendable {
    public let text: String
    public let utf16Range: Range<Int>

    public init(text: String, utf16Range: Range<Int>) {
        self.text = text
        self.utf16Range = utf16Range
    }

    public var nsRange: NSRange {
        NSRange(location: utf16Range.lowerBound, length: utf16Range.count)
    }
}

public enum SpeechStartPolicy: Sendable {
    case containingSentence
    case exactOffset
}

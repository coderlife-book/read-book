import Foundation

public struct BookPosition: Codable, Equatable, Sendable {
    public var utf16Offset: Int

    public init(utf16Offset: Int) {
        self.utf16Offset = utf16Offset
    }

    public static let zero = BookPosition(utf16Offset: 0)

    public func clamped(to utf16Length: Int) -> BookPosition {
        BookPosition(utf16Offset: min(max(utf16Offset, 0), max(utf16Length, 0)))
    }
}

import Foundation

public struct Chapter: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var utf16Offset: Int

    public init(id: UUID = UUID(), title: String, utf16Offset: Int) {
        self.id = id
        self.title = title
        self.utf16Offset = utf16Offset
    }
}

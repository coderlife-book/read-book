import Foundation

public enum ImportedTextEncoding: String, Codable, CaseIterable, Sendable {
    case utf8
    case utf16LittleEndian
    case utf16BigEndian
    case gb18030
    case big5
}

public struct BookMetadata: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public let importedAt: Date
    public var lastReadAt: Date
    public var position: BookPosition
    public let totalUTF16Length: Int
    public let sourceEncoding: ImportedTextEncoding
    public var chapters: [Chapter]

    public init(
        id: UUID = UUID(),
        title: String,
        importedAt: Date = .now,
        lastReadAt: Date = .now,
        position: BookPosition = .zero,
        totalUTF16Length: Int,
        sourceEncoding: ImportedTextEncoding,
        chapters: [Chapter]
    ) {
        self.id = id
        self.title = title
        self.importedAt = importedAt
        self.lastReadAt = lastReadAt
        self.position = position
        self.totalUTF16Length = totalUTF16Length
        self.sourceEncoding = sourceEncoding
        self.chapters = chapters
    }
}

public struct LibraryIndex: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var bookIDs: [UUID]
    public var lastOpenedBookID: UUID?

    public init(schemaVersion: Int = 1, bookIDs: [UUID] = [], lastOpenedBookID: UUID? = nil) {
        self.schemaVersion = schemaVersion
        self.bookIDs = bookIDs
        self.lastOpenedBookID = lastOpenedBookID
    }
}

import Foundation

public actor LibraryRepository {
    private let paths: AppPaths
    private let json = JSONFileStore()
    private let decoder = TextDecoder()
    private let chapterParser = ChapterParser()

    public init(paths: AppPaths = AppPaths()) {
        self.paths = paths
    }

    public func loadLibrary() throws -> [BookMetadata] {
        try ensureDirectories()
        let index = try loadIndex()
        return index.bookIDs.compactMap { id in
            if let metadata = try? json.read(BookMetadata.self, from: paths.metadataURL(id)) {
                return metadata
            }
            return try? recoverMetadata(id)
        }
    }

    public func importBook(
        from sourceURL: URL,
        encodingOverride: ImportedTextEncoding? = nil
    ) throws -> BookMetadata {
        try ensureDirectories()
        guard sourceURL.pathExtension.lowercased() == "txt" else {
            throw LibraryError.unsupportedFileType
        }

        let decoded = try decoder.decode(Data(contentsOf: sourceURL), override: encodingOverride)
        guard !decoded.text.isEmpty else { throw LibraryError.emptyBook }

        let id = UUID()
        let directory = paths.bookDirectory(id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        do {
            try Data(decoded.text.utf8).write(to: paths.contentURL(id), options: .atomic)
            let chapters = try chapterParser.parse(decoded.text)
            let now = Date()
            let metadata = BookMetadata(
                id: id,
                title: sourceURL.deletingPathExtension().lastPathComponent,
                importedAt: now,
                lastReadAt: now,
                totalUTF16Length: (decoded.text as NSString).length,
                sourceEncoding: decoded.encoding,
                chapters: chapters
            )
            try json.write(metadata, to: paths.metadataURL(id))

            var index = try loadIndex()
            index.bookIDs.removeAll { $0 == id }
            index.bookIDs.insert(id, at: 0)
            index.lastOpenedBookID = id
            try json.write(index, to: paths.libraryIndexURL)
            return metadata
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    public func loadText(bookID: UUID) throws -> String {
        do {
            return try String(contentsOf: paths.contentURL(bookID), encoding: .utf8)
        } catch {
            throw LibraryError.missingContent
        }
    }

    public func savePosition(
        bookID: UUID,
        position: BookPosition,
        lastReadAt: Date = .now
    ) throws {
        var metadata = try metadata(bookID)
        metadata.position = position.clamped(to: metadata.totalUTF16Length)
        metadata.lastReadAt = lastReadAt
        try json.write(metadata, to: paths.metadataURL(bookID))
    }

    public func rename(bookID: UUID, title: String) throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LibraryError.invalidTitle }
        var metadata = try metadata(bookID)
        metadata.title = trimmed
        try json.write(metadata, to: paths.metadataURL(bookID))
    }

    public func remove(bookID: UUID) throws {
        try ensureDirectories()
        if FileManager.default.fileExists(atPath: paths.bookDirectory(bookID).path) {
            try FileManager.default.removeItem(at: paths.bookDirectory(bookID))
        }
        var index = try loadIndex()
        index.bookIDs.removeAll { $0 == bookID }
        if index.lastOpenedBookID == bookID {
            index.lastOpenedBookID = index.bookIDs.first
        }
        try json.write(index, to: paths.libraryIndexURL)
    }

    public func setLastOpenedBook(_ id: UUID?) throws {
        try ensureDirectories()
        var index = try loadIndex()
        index.lastOpenedBookID = id
        try json.write(index, to: paths.libraryIndexURL)
    }

    public func lastOpenedBookID() throws -> UUID? {
        try ensureDirectories()
        return try loadIndex().lastOpenedBookID
    }

    private func metadata(_ id: UUID) throws -> BookMetadata {
        do {
            return try json.read(BookMetadata.self, from: paths.metadataURL(id))
        } catch {
            throw LibraryError.missingMetadata
        }
    }

    private func loadIndex() throws -> LibraryIndex {
        if FileManager.default.fileExists(atPath: paths.libraryIndexURL.path),
           let valid = try? json.read(LibraryIndex.self, from: paths.libraryIndexURL) {
            return valid
        }

        let recovered = recoverIndex()
        try json.write(recovered, to: paths.libraryIndexURL)
        return recovered
    }

    private func recoverIndex() -> LibraryIndex {
        let directories = (try? FileManager.default.contentsOfDirectory(
            at: paths.booksRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let entries = directories.compactMap { directory -> (UUID, Date)? in
            guard let id = UUID(uuidString: directory.lastPathComponent),
                  FileManager.default.fileExists(atPath: paths.contentURL(id).path) else { return nil }

            if let metadata = try? json.read(BookMetadata.self, from: paths.metadataURL(id)) {
                return (id, metadata.lastReadAt)
            }

            if let recovered = try? recoverMetadata(id) {
                return (id, recovered.lastReadAt)
            }

            return nil
        }
        .sorted { $0.1 > $1.1 }

        return LibraryIndex(
            bookIDs: entries.map(\.0),
            lastOpenedBookID: entries.first?.0
        )
    }

    private func recoverMetadata(_ id: UUID) throws -> BookMetadata {
        let contentURL = paths.contentURL(id)
        guard let text = try? String(contentsOf: contentURL, encoding: .utf8), !text.isEmpty else {
            throw LibraryError.missingContent
        }
        let chapters = try chapterParser.parse(text)
        let modifiedAt = (try? contentURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .now
        let metadata = BookMetadata(
            id: id,
            title: "恢复的小说-\(id.uuidString.prefix(8))",
            importedAt: modifiedAt,
            lastReadAt: modifiedAt,
            position: .zero,
            totalUTF16Length: (text as NSString).length,
            sourceEncoding: .utf8,
            chapters: chapters
        )
        try json.write(metadata, to: paths.metadataURL(id))
        return metadata
    }

    private func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: paths.booksRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.cacheRoot, withIntermediateDirectories: true)
    }
}

public enum LibraryError: Error, Equatable, Sendable {
    case unsupportedFileType
    case emptyBook
    case missingContent
    case missingMetadata
    case invalidTitle
}

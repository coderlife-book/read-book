import Foundation
@MainActor
public final class ReaderSession {
    public private(set) var currentBook: BookMetadata?
    public private(set) var text = ""
    public private(set) var position: BookPosition = .zero
    public private(set) var currentChapter: Chapter?
    public private(set) var readingMode: ReadingMode = .paginated

    private let repository: LibraryRepository
    private let saveDelayNanoseconds: UInt64
    private var saveTask: Task<Void, Never>?

    public init(
        repository: LibraryRepository,
        saveDelayNanoseconds: UInt64 = 700_000_000
    ) {
        self.repository = repository
        self.saveDelayNanoseconds = saveDelayNanoseconds
    }


    public func open(bookID: UUID) async throws {
        await flush()
        let library = try await repository.loadLibrary()
        guard let metadata = library.first(where: { $0.id == bookID }) else {
            throw ReaderSessionError.bookNotFound
        }
        let loadedText = try await repository.loadText(bookID: bookID)

        currentBook = metadata
        text = loadedText
        position = metadata.position.clamped(to: metadata.totalUTF16Length)
        currentChapter = chapter(at: position.utf16Offset, in: metadata.chapters)
        try await repository.setLastOpenedBook(bookID)
    }

    public func close() async {
        await flush()
        currentBook = nil
        text = ""
        position = .zero
        currentChapter = nil
    }

    public func updatePosition(_ newPosition: BookPosition) {
        guard var book = currentBook else { return }
        position = newPosition.clamped(to: book.totalUTF16Length)
        currentChapter = chapter(at: position.utf16Offset, in: book.chapters)
        book.position = position
        book.lastReadAt = .now
        currentBook = book
        scheduleSave()
    }

    public func jump(to chapter: Chapter) {
        updatePosition(BookPosition(utf16Offset: chapter.utf16Offset))
    }

    public func setReadingMode(_ mode: ReadingMode) {
        readingMode = mode
    }

    public func flush() async {
        saveTask?.cancel()
        saveTask = nil
        guard let id = currentBook?.id else { return }
        try? await repository.savePosition(bookID: id, position: position)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        guard let id = currentBook?.id else { return }
        let value = position
        let repository = repository
        let delay = saveDelayNanoseconds

        saveTask = Task {
            do {
                try await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                try await repository.savePosition(bookID: id, position: value)
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    private func chapter(at offset: Int, in chapters: [Chapter]) -> Chapter? {
        chapters.last { $0.utf16Offset <= offset }
    }
}

public enum ReaderSessionError: Error, Equatable, Sendable {
    case bookNotFound
}

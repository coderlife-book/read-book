import Foundation
import XCTest
@testable import ReadBookCore

@MainActor
final class ReaderSessionTests: XCTestCase {
    private func makeBook() async throws -> (root: URL, repo: LibraryRepository, book: BookMetadata) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("book.txt")
        try Data("第一章\n12345\n第二章\n67890".utf8).write(to: source)
        let repo = LibraryRepository(paths: AppPaths(root: root.appendingPathComponent("Library")))
        let book = try await repo.importBook(from: source)
        return (root, repo, book)
    }

    func testOpenRestoresBookTextPositionAndChapter() async throws {
        let fixture = try await makeBook()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let second = try XCTUnwrap(fixture.book.chapters.last)
        try await fixture.repo.savePosition(bookID: fixture.book.id, position: BookPosition(utf16Offset: second.utf16Offset))

        let session = ReaderSession(repository: fixture.repo, saveDelayNanoseconds: 20_000_000)
        try await session.open(bookID: fixture.book.id)

        XCTAssertEqual(session.position.utf16Offset, second.utf16Offset)
        XCTAssertEqual(session.currentChapter?.title, "第二章")
        XCTAssertTrue(session.text.contains("67890"))
    }

    func testFlushPersistsLatestPosition() async throws {
        let fixture = try await makeBook()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let session = ReaderSession(repository: fixture.repo, saveDelayNanoseconds: 20_000_000)
        try await session.open(bookID: fixture.book.id)
        session.updatePosition(BookPosition(utf16Offset: 8))
        await session.flush()

        let library = try await fixture.repo.loadLibrary()
        XCTAssertEqual(library.first?.position.utf16Offset, 8)
    }

    func testModeSwitchDoesNotChangeCanonicalPosition() async throws {
        let fixture = try await makeBook()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let session = ReaderSession(repository: fixture.repo, saveDelayNanoseconds: 20_000_000)
        try await session.open(bookID: fixture.book.id)
        session.updatePosition(BookPosition(utf16Offset: 7))
        session.setReadingMode(.continuous)
        XCTAssertEqual(session.readingMode, .continuous)
        XCTAssertEqual(session.position.utf16Offset, 7)
    }
}

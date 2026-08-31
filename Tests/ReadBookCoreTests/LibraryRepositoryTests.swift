import Foundation
import XCTest
@testable import ReadBookCore

final class LibraryRepositoryTests: XCTestCase {
    private func makeFixture() throws -> (root: URL, paths: AppPaths, source: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let paths = AppPaths(root: root.appendingPathComponent("Library"))
        let source = root.appendingPathComponent("放开那个女巫.txt")
        try Data("第一章\r\n正文🙂\r\n第二章\r\n继续".utf8).write(to: source)
        return (root, paths, source)
    }

    func testImportCopiesNormalizedContentAndPersistsChapterMetadata() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let repo = LibraryRepository(paths: fixture.paths)
        let book = try await repo.importBook(from: fixture.source)
        let text = try await repo.loadText(bookID: book.id)
        let library = try await repo.loadLibrary()

        XCTAssertEqual(text, "第一章\n正文🙂\n第二章\n继续")
        XCTAssertEqual(book.chapters.map(\.title), ["第一章", "第二章"])
        XCTAssertEqual(library.map(\.id), [book.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.paths.contentURL(book.id).path))
    }

    func testIndependentPositionSurvivesRepositoryReload() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let repo = LibraryRepository(paths: fixture.paths)
        let book = try await repo.importBook(from: fixture.source)
        try await repo.savePosition(bookID: book.id, position: BookPosition(utf16Offset: 5))

        let reopened = LibraryRepository(paths: fixture.paths)
        let library = try await reopened.loadLibrary()
        XCTAssertEqual(library.first?.position.utf16Offset, 5)
    }

    func testCorruptLibraryIndexIsRecoveredAndRewritten() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let repo = LibraryRepository(paths: fixture.paths)
        let book = try await repo.importBook(from: fixture.source)
        try Data("not-json".utf8).write(to: fixture.paths.libraryIndexURL, options: .atomic)

        let reopened = LibraryRepository(paths: fixture.paths)
        let recoveredLibrary = try await reopened.loadLibrary()
        XCTAssertEqual(recoveredLibrary.map(\.id), [book.id])

        let recoveredData = try Data(contentsOf: fixture.paths.libraryIndexURL)
        let recovered = try JSONDecoder().decode(LibraryIndex.self, from: recoveredData)
        XCTAssertEqual(recovered.bookIDs, [book.id])
    }

    func testCorruptBookMetadataIsRebuiltFromNormalizedContent() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let repo = LibraryRepository(paths: fixture.paths)
        let book = try await repo.importBook(from: fixture.source)
        try Data("broken-metadata".utf8).write(to: fixture.paths.metadataURL(book.id), options: .atomic)

        let reopened = LibraryRepository(paths: fixture.paths)
        let library = try await reopened.loadLibrary()
        let recovered = try XCTUnwrap(library.first)
        XCTAssertEqual(recovered.id, book.id)
        XCTAssertEqual(recovered.chapters.map(\.title), ["第一章", "第二章"])
        XCTAssertEqual(recovered.sourceEncoding, .utf8)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let persisted = try decoder.decode(
            BookMetadata.self,
            from: Data(contentsOf: fixture.paths.metadataURL(book.id))
        )
        XCTAssertEqual(persisted.id, book.id)
    }

    func testRenameAndRemoveUpdateManagedLibrary() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let repo = LibraryRepository(paths: fixture.paths)
        let book = try await repo.importBook(from: fixture.source)

        try await repo.rename(bookID: book.id, title: "女巫")
        let renamedLibrary = try await repo.loadLibrary()
        XCTAssertEqual(renamedLibrary.first?.title, "女巫")

        try await repo.remove(bookID: book.id)
        let emptyLibrary = try await repo.loadLibrary()
        XCTAssertTrue(emptyLibrary.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.paths.bookDirectory(book.id).path))
    }
}

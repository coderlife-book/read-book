import XCTest
@testable import ReadBookCore

final class ModelsTests: XCTestCase {
    func testBookPositionClampsIntoUTF16Bounds() {
        XCTAssertEqual(BookPosition(utf16Offset: -4).clamped(to: 10).utf16Offset, 0)
        XCTAssertEqual(BookPosition(utf16Offset: 7).clamped(to: 10).utf16Offset, 7)
        XCTAssertEqual(BookPosition(utf16Offset: 99).clamped(to: 10).utf16Offset, 10)
    }

    func testLibraryIndexRoundTripsThroughJSON() throws {
        let id = UUID()
        let value = LibraryIndex(schemaVersion: 1, bookIDs: [id], lastOpenedBookID: id)
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(LibraryIndex.self, from: data), value)
    }

    func testDefaultPreferencesMatchProductDefaults() {
        let p = ReaderPreferences.defaults
        XCTAssertEqual(p.readingMode, .paginated)
        XCTAssertEqual(p.fontFamily, "PingFang SC")
        XCTAssertEqual(p.fontSize, 17)
        XCTAssertEqual(p.lineSpacing, 8)
        XCTAssertEqual(p.paragraphSpacing, 9)
        XCTAssertEqual(p.theme, .soft)
        XCTAssertEqual(p.appPresenceMode, .normal)
    }
}

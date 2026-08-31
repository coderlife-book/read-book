import Foundation
import XCTest
@testable import ReadBookCore

final class PreferencesStoreTests: XCTestCase {
    func testPreferencesRoundTrip() throws {
        let suite = "ReadBookTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PreferencesStore(defaults: defaults)
        var value = ReaderPreferences.defaults
        value.theme = .dark
        value.alwaysOnTop = true
        try store.save(value)
        XCTAssertEqual(try store.load(), value)
    }

    func testMissingPreferencesReturnProductDefaults() throws {
        let suite = "ReadBookTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(try PreferencesStore(defaults: defaults).load(), .defaults)
    }

    func testLayoutSignatureChangesForPaginationAffectingSettings() {
        let a = LayoutSignature(width: 316, height: 220, style: .default)
        var changed = ReaderTextStyle.default
        changed.fontSize = 21
        let b = LayoutSignature(width: 316, height: 220, style: changed)
        XCTAssertNotEqual(a, b)
    }

    func testLayoutSignatureQuantizesTinyGeometryNoise() {
        let a = LayoutSignature(width: 316.01, height: 220.01, style: .default)
        let b = LayoutSignature(width: 316.02, height: 220.02, style: .default)
        XCTAssertEqual(a, b)
    }
}

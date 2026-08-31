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

    func testStealthDefaultsAreSafeForExistingUsers() {
        let value = ReaderPreferences.defaults
        XCTAssertFalse(value.bossModeEnabled)
        XCTAssertEqual(value.bossModeProfile, .floatingReading)
        XCTAssertEqual(value.windowAppearance, .card)
        XCTAssertEqual(value.framelessBackgroundOpacity, 0.18, accuracy: 0.0001)
    }

    func testLegacyV012PreferencesDecodeWithStealthDefaults() throws {
        let json = #"{"readingMode":"paginated","fontFamily":"PingFang SC","fontSize":17,"lineSpacing":8,"paragraphSpacing":9,"theme":"soft","alwaysOnTop":false,"appPresenceMode":"widgetStyle"}"#
        let value = try JSONDecoder().decode(ReaderPreferences.self, from: Data(json.utf8))
        XCTAssertFalse(value.bossModeEnabled)
        XCTAssertEqual(value.bossModeProfile, .floatingReading)
        XCTAssertEqual(value.windowAppearance, .card)
        XCTAssertEqual(value.framelessBackgroundOpacity, 0.18, accuracy: 0.0001)
    }

    func testStealthPreferencesRoundTrip() throws {
        var value = ReaderPreferences.defaults
        value.bossModeEnabled = true
        value.bossModeProfile = .concealed
        value.windowAppearance = .frameless
        value.framelessBackgroundOpacity = 0.42
        let decoded = try JSONDecoder().decode(ReaderPreferences.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(decoded, value)
    }

    func testCustomTextColorSurvivesPreferencesRoundTrip() throws {
        let json = ##"{"readingMode":"paginated","fontFamily":"PingFang SC","fontSize":17,"lineSpacing":8,"paragraphSpacing":9,"theme":"soft","alwaysOnTop":false,"appPresenceMode":"widgetStyle","textColorHex":"#336699"}"##
        let decoded = try JSONDecoder().decode(ReaderPreferences.self, from: Data(json.utf8))
        let encoded = try JSONEncoder().encode(decoded)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertEqual(object["textColorHex"] as? String, "#336699")
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

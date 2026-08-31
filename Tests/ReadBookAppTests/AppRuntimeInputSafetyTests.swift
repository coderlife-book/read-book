#if os(macOS)
import AppKit
import XCTest
import ReadBookCore
@testable import ReadBook

@MainActor
final class AppRuntimeInputSafetyTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
    }

    func testNormalStartupKeepsSystemInputHooksDisabled() {
        let runtime = AppRuntime()
        defer { runtime.stop() }

        runtime.start(preferences: ReaderPreferences.defaults)

        XCTAssertFalse(runtime.systemInputHooksEnabled)
    }

    func testBossModeKeepsSystemInputHooksDisabled() {
        let runtime = AppRuntime()
        defer { runtime.stop() }
        var preferences = ReaderPreferences.defaults
        preferences.bossModeEnabled = true

        runtime.start(preferences: preferences)
        runtime.applyPreferences(preferences)

        XCTAssertFalse(runtime.systemInputHooksEnabled)
    }
}
#endif

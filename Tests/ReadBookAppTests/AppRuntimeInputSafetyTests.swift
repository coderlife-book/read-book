#if os(macOS)
import AppKit
import XCTest
import ReadBookCore
@testable import ReadBook

@MainActor
final class AppRuntimeInputSafetyTests: XCTestCase {
    func testNormalStartupDoesNotInstallAnyGlobalInputHooks() {
        let hotKey = FakeHotKeyService()
        let globalInput = FakeReaderGlobalInputService()
        let runtime = AppRuntime(
            hotKeyService: hotKey,
            globalInputService: globalInput
        )
        defer { runtime.stop() }

        runtime.start(preferences: ReaderPreferences.defaults)

        XCTAssertEqual(hotKey.startCount, 0)
        XCTAssertEqual(globalInput.startCount, 0)
        XCTAssertFalse(runtime.hotKeyAvailable)
        XCTAssertFalse(runtime.globalPointerAvailable)
    }

    func testBossModeAlsoDoesNotInstallAnyGlobalInputHooks() {
        let hotKey = FakeHotKeyService()
        let globalInput = FakeReaderGlobalInputService()
        let runtime = AppRuntime(
            hotKeyService: hotKey,
            globalInputService: globalInput
        )
        defer { runtime.stop() }
        var preferences = ReaderPreferences.defaults
        preferences.bossModeEnabled = true

        runtime.start(preferences: preferences)

        XCTAssertEqual(hotKey.startCount, 0)
        XCTAssertEqual(globalInput.startCount, 0)
        XCTAssertFalse(runtime.hotKeyAvailable)
        XCTAssertFalse(runtime.globalPointerAvailable)
    }

    func testPreferenceChangesNeverInstallGlobalInputHooks() {
        let hotKey = FakeHotKeyService()
        let globalInput = FakeReaderGlobalInputService()
        let runtime = AppRuntime(
            hotKeyService: hotKey,
            globalInputService: globalInput
        )
        defer { runtime.stop() }
        runtime.start(preferences: ReaderPreferences.defaults)

        var preferences = ReaderPreferences.defaults
        preferences.bossModeEnabled = true
        runtime.applyPreferences(preferences)
        runtime.applyPreferences(ReaderPreferences.defaults)

        XCTAssertEqual(hotKey.startCount, 0)
        XCTAssertEqual(globalInput.startCount, 0)
    }
}

@MainActor
private final class FakeHotKeyService: GlobalHotKeyServicing {
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start(onPress: @escaping @MainActor () -> Void) -> Bool {
        startCount += 1
        return true
    }

    func stop() {
        stopCount += 1
    }
}

@MainActor
private final class FakeReaderGlobalInputService: ReaderGlobalInputServicing {
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start(
        onPointer: @escaping @MainActor (CGPoint) -> Void,
        onOption: @escaping @MainActor (Bool) -> Void
    ) -> Bool {
        startCount += 1
        return true
    }

    func stop() {
        stopCount += 1
    }
}
#endif

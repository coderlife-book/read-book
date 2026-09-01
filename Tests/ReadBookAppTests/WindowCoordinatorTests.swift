#if os(macOS)
import AppKit
import ReadBookCore
import XCTest
@testable import ReadBook

final class WindowCoordinatorTests: XCTestCase {
    @MainActor
    func testConfigureKeepsNativeTitleAndResizeBehavior() {
        let window = makeWindow()

        WindowCoordinator().configure(window)

        XCTAssertTrue(window.styleMask.contains(.titled))
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertTrue(window.styleMask.contains(.closable))
        XCTAssertFalse(window.styleMask.contains(.fullSizeContentView))
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titlebarSeparatorStyle, .none)
        XCTAssertFalse(window.isMovableByWindowBackground)
        XCTAssertNil(window.toolbar)
    }

    @MainActor
    func testRegistryAppliesAppearanceAndPointerPassThrough() {
        let registry = WindowRegistry()
        let window = makeWindow()
        registry.register(window)

        var preferences = ReaderPreferences.defaults
        preferences.appPresenceMode = .normal
        preferences.theme = .soft

        preferences.windowAppearance = .transparent
        registry.apply(preferences)
        XCTAssertFalse(window.hasShadow)
        XCTAssertTrue(window.backgroundColor.isEqual(NSColor.clear))

        preferences.windowAppearance = .frameless
        preferences.framelessBackgroundOpacity = 0.18
        registry.apply(preferences)
        XCTAssertFalse(window.hasShadow)
        XCTAssertEqual(window.backgroundColor.alphaComponent, 0.18, accuracy: 0.01)

        preferences.windowAppearance = .card
        registry.apply(preferences)
        XCTAssertTrue(window.hasShadow)
        XCTAssertTrue(
            window.backgroundColor.isEqual(
                ThemePalette.resolve(.soft).background
            )
        )

        registry.setPointerPassThrough(true)
        XCTAssertTrue(window.ignoresMouseEvents)
        registry.setPointerPassThrough(false)
        XCTAssertFalse(window.ignoresMouseEvents)
    }

    @MainActor
    func testAppPresenceOnlyTransitionsWhenActivationPolicyActuallyChanges() {
        XCTAssertFalse(
            WindowRegistry.needsActivationPolicyChange(
                current: .accessory,
                targetMode: .widgetStyle
            )
        )
        XCTAssertFalse(
            WindowRegistry.needsActivationPolicyChange(
                current: .regular,
                targetMode: .normal
            )
        )
        XCTAssertTrue(
            WindowRegistry.needsActivationPolicyChange(
                current: .accessory,
                targetMode: .normal
            )
        )
        XCTAssertTrue(
            WindowRegistry.needsActivationPolicyChange(
                current: .regular,
                targetMode: .widgetStyle
            )
        )
    }

    @MainActor
    func testRevalidatedFrameClampsDisconnectedDisplayFrameIntoVisibleScreen() {
        let old = CGRect(x: 2500, y: 100, width: 360, height: 260)
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

        let fixed = WindowRegistry.revalidatedFrame(old, visibleFrames: [screen])

        XCTAssertEqual(fixed.size, old.size)
        XCTAssertTrue(screen.contains(CGPoint(x: fixed.midX, y: fixed.midY)))
    }

    @MainActor
    func testRevalidatedFrameLeavesVisibleFrameUnchanged() {
        let frame = CGRect(x: 120, y: 140, width: 360, height: 260)
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        XCTAssertEqual(WindowRegistry.revalidatedFrame(frame, visibleFrames: [screen]), frame)
    }

    @MainActor
    private func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 260),
            styleMask: [.titled, .resizable, .closable],
            backing: .buffered,
            defer: false
        )
    }
}
#endif

#if os(macOS)
import AppKit
import ReadBookCore
import XCTest
@testable import ReadBook

final class WindowCoordinatorTests: XCTestCase {
    @MainActor
    func testConfigureRemovesTitledChromeKeepsResizableAndDisablesBackgroundDrag() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 260),
            styleMask: [.titled, .resizable, .closable],
            backing: .buffered,
            defer: false
        )

        let coordinator = WindowCoordinator()
        coordinator.configure(window)

        XCTAssertFalse(window.styleMask.contains(.titled))
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertFalse(window.isMovableByWindowBackground)
    }

    @MainActor
    func testRegistryAppliesAppearanceAndPointerPassThrough() {
        let registry = WindowRegistry()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 260),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        registry.register(window)

        registry.applyAppearance(.transparent)
        XCTAssertFalse(window.hasShadow)
        XCTAssertFalse(window.isOpaque)

        registry.setPointerPassThrough(true)
        XCTAssertTrue(window.ignoresMouseEvents)
        registry.setPointerPassThrough(false)
        XCTAssertFalse(window.ignoresMouseEvents)

        registry.applyAppearance(.frameless)
        XCTAssertFalse(window.hasShadow)
        registry.applyAppearance(.card)
        XCTAssertTrue(window.hasShadow)
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
}
#endif

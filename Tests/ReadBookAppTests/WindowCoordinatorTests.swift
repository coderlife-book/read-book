#if os(macOS)
import AppKit
import ReadBookCore
import XCTest
@testable import ReadBook

final class WindowCoordinatorTests: XCTestCase {
    @MainActor
    func testConfigureKeepsNativeResizableWindowWhileHidingSystemTitlebarContent() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 260),
            styleMask: [.titled, .resizable, .closable],
            backing: .buffered,
            defer: false
        )

        let coordinator = WindowCoordinator()
        coordinator.configure(window)
        coordinator.configure(window)

        XCTAssertTrue(window.styleMask.contains(.titled))
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertFalse(window.isMovableByWindowBackground)
        XCTAssertTrue(window.standardWindowButton(.closeButton)?.isHidden == true)
        XCTAssertTrue(window.standardWindowButton(.miniaturizeButton)?.isHidden == true)
        XCTAssertTrue(window.standardWindowButton(.zoomButton)?.isHidden == true)
        XCTAssertEqual(window.contentView?.safeAreaInsets.top, 0)
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
        XCTAssertFalse(window.hasShadow)
        XCTAssertEqual(window.contentView?.layer?.cornerRadius, 26)
        XCTAssertTrue(window.contentView?.layer?.masksToBounds == true)
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
}
#endif

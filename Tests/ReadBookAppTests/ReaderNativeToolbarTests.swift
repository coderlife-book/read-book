#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import ReadBook

final class ReaderNativeToolbarTests: XCTestCase {
    @MainActor
    func testInstallCreatesOneUnifiedNonCustomizableToolbar() {
        let window = makeWindow()
        let state = ReaderTitlebarState()
        let controller = ReaderNativeToolbarController()

        controller.install(on: window, state: state)

        XCTAssertEqual(window.toolbar?.identifier.rawValue, "ReadBook.ReaderToolbar")
        XCTAssertFalse(window.toolbar?.allowsUserCustomization ?? true)
        XCTAssertFalse(window.toolbar?.autosavesConfiguration ?? true)
        XCTAssertEqual(window.toolbarStyle, .unifiedCompact)
    }

    @MainActor
    func testHiddenButtonHostPassesHitTestingThroughToNativeTitlebar() {
        let state = ReaderTitlebarState()
        state.isVisible = false
        let host = ReaderTitlebarButtonHostView(
            state: state,
            rootView: AnyView(EmptyView())
        )
        host.frame = NSRect(x: 0, y: 0, width: 30, height: 30)

        XCTAssertNil(host.hitTest(NSPoint(x: 15, y: 15)))
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

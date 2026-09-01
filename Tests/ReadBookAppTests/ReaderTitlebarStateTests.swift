#if os(macOS)
import ReadBookCore
import XCTest
@testable import ReadBook

final class ReaderTitlebarStateTests: XCTestCase {
    @MainActor
    func testToggleReadingModeUsesBoundAction() {
        let state = ReaderTitlebarState()
        state.readingMode = .paginated
        var requested: ReadingMode?
        state.onModeChange = { requested = $0 }

        state.toggleReadingMode()

        XCTAssertEqual(requested, .continuous)
    }

    @MainActor
    func testToolbarVisibilityDoesNotMutateReadingState() {
        let state = ReaderTitlebarState()
        state.title = "Book"
        state.readingMode = .continuous
        state.alwaysOnTop = true

        state.isVisible = true
        state.isVisible = false

        XCTAssertEqual(state.title, "Book")
        XCTAssertEqual(state.readingMode, .continuous)
        XCTAssertTrue(state.alwaysOnTop)
    }

    @MainActor
    func testToggleLibraryOwnsPresentationBoolean() {
        let state = ReaderTitlebarState()
        XCTAssertFalse(state.isLibraryPresented)
        state.toggleLibrary()
        XCTAssertTrue(state.isLibraryPresented)
        state.toggleLibrary()
        XCTAssertFalse(state.isLibraryPresented)
    }
}
#endif

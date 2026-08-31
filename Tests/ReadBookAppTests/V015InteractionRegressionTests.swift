#if os(macOS)
import AppKit
import ReadBookCore
import XCTest
@testable import ReadBook

@MainActor
final class V015InteractionRegressionTests: XCTestCase {
    func testChromeEdgeRevealUses90msDwell() {
        let scheduler = V015ManualScheduler()
        let chrome = ReaderChromeController(scheduler: scheduler)

        chrome.topZoneChanged(inside: true)
        scheduler.fire(milliseconds: 89)
        XCTAssertFalse(chrome.topVisible)
        scheduler.fire(milliseconds: 90)
        XCTAssertTrue(chrome.topVisible)

        chrome.hideAllImmediately()
        chrome.bottomZoneChanged(inside: true)
        scheduler.fire(milliseconds: 90)
        XCTAssertTrue(chrome.bottomVisible)
    }

    func testChapterListInitialTargetIsCurrentChapter() {
        let first = Chapter(id: UUID(), title: "第一章", utf16Offset: 0)
        let current = Chapter(id: UUID(), title: "第二章", utf16Offset: 100)
        let chapters = [first, current]

        XCTAssertEqual(
            ChapterListView.initialScrollTarget(chapters: chapters, currentChapterID: current.id),
            current.id
        )
    }

    func testToolbarDoesNotEmbedCustomDragRegion() throws {
        let toolbar = try source("Sources/ReadBook/Reader/ReaderToolbar.swift")
        XCTAssertFalse(toolbar.contains("ReaderDragRegion("))
        XCTAssertFalse(toolbar.contains("performDrag(with:"))
    }

    private func source(_ relativePath: String) throws -> String {
        let fileURL = URL(fileURLWithPath: #filePath)
        let root = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}

@MainActor
private final class V015ManualScheduler: DelayScheduling {
    private final class Token: DelayCancellation {
        var cancelled = false
        func cancel() { cancelled = true }
    }

    private struct Entry {
        let milliseconds: Int
        let token: Token
        let action: @MainActor () -> Void
    }

    private var entries: [Entry] = []

    func schedule(afterMilliseconds: Int, action: @escaping @MainActor () -> Void) -> any DelayCancellation {
        let token = Token()
        entries.append(Entry(milliseconds: afterMilliseconds, token: token, action: action))
        return token
    }

    func fire(milliseconds: Int) {
        let matching = entries.filter { $0.milliseconds == milliseconds }
        entries.removeAll { $0.milliseconds == milliseconds }
        for entry in matching where !entry.token.cancelled { entry.action() }
    }
}
#endif

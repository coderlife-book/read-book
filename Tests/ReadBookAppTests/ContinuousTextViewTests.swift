#if os(macOS)
import AppKit
import ReadBookCore
import XCTest
@testable import ReadBook

final class ContinuousTextViewTests: XCTestCase {
    @MainActor
    func testCoordinatorRendersWholeBookIntoNativeTextView() {
        let text = String(repeating: "正文内容。\n", count: 10_000)
        let (scrollView, textView, coordinator) = makeReader()

        coordinator.update(
            bookID: UUID(),
            text: text,
            anchor: .init(utf16Offset: 0),
            style: .default,
            textColor: .textColor
        )

        XCTAssertEqual(textView.string, text)
        XCTAssertEqual(textView.textStorage?.length, (text as NSString).length)
        XCTAssertTrue(scrollView.documentView === textView)
    }

    func testProductionContinuousReaderDoesNotUseVirtualWindowPlanner() throws {
        let source = try sourceFile("Sources/ReadBook/Reader/ContinuousTextView.swift")

        XCTAssertFalse(source.contains("VirtualTextWindowPlanner"))
        XCTAssertFalse(source.contains("scheduleRecenteringIfNeeded"))
    }

    @MainActor
    private func makeReader(
        onPositionChanged: @escaping (BookPosition) -> Void = { _ in }
    ) -> (NSScrollView, NSTextView, ContinuousTextView.Coordinator) {
        let scrollView = NSScrollView(
            frame: NSRect(x: 0, y: 0, width: 360, height: 260)
        )
        scrollView.contentView.postsBoundsChangedNotifications = true
        let textView = NSTextView(
            frame: NSRect(x: 0, y: 0, width: 360, height: 260)
        )
        scrollView.documentView = textView
        let coordinator = ContinuousTextView.Coordinator(
            onPositionChanged: onPositionChanged
        )
        coordinator.attach(scrollView: scrollView, textView: textView)
        return (scrollView, textView, coordinator)
    }

    private func sourceFile(_ relativePath: String) throws -> String {
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
#endif

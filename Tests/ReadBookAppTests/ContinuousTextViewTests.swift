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
    func testRapidScrollPositionChangesAreReportedOnlyAfterIdle() {
        let text = String(repeating: "滚动位置正文。\n", count: 20_000)
        var reports: [BookPosition] = []
        let (scrollView, textView, coordinator) = makeReader {
            reports.append($0)
        }
        let window = host(scrollView)
        _ = window

        coordinator.update(
            bookID: UUID(),
            text: text,
            anchor: .init(utf16Offset: 0),
            style: .default,
            textColor: .textColor
        )

        RunLoop.main.run(until: Date().addingTimeInterval(0.12))

        coordinator.detach()
        scrollView.contentView.postsBoundsChangedNotifications = false
        coordinator.attach(scrollView: scrollView, textView: textView)
        reports.removeAll()

        for y in [120.0, 240.0, 360.0] {
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            NotificationCenter.default.post(
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )

            RunLoop.main.run(until: Date().addingTimeInterval(0.025))
            XCTAssertTrue(
                reports.isEmpty,
                "Position should not be written back while scrolling is still active"
            )
        }

        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        XCTAssertEqual(reports.count, 1)
        XCTAssertGreaterThan(reports[0].utf16Offset, 0)
    }

    @MainActor
    private func makeReader(
        onPositionChanged: @escaping (BookPosition) -> Void = { _ in }
    ) -> (NSScrollView, NSTextView, ContinuousTextView.Coordinator) {
        let scrollView = ContinuousTextView.makeNativeScrollView()
        scrollView.frame = NSRect(x: 0, y: 0, width: 360, height: 260)
        let textView = scrollView.documentView as! NSTextView
        let coordinator = ContinuousTextView.Coordinator(
            onPositionChanged: onPositionChanged
        )
        coordinator.attach(scrollView: scrollView, textView: textView)
        return (scrollView, textView, coordinator)
    }

    @MainActor
    private func host(_ scrollView: NSScrollView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 260),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        scrollView.frame = window.contentView!.bounds
        scrollView.autoresizingMask = [.width, .height]
        window.contentView!.addSubview(scrollView)
        window.layoutIfNeeded()
        return window
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

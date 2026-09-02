#if os(macOS)
import AppKit
import ReadBookCore
import XCTest
@testable import ReadBook

final class ContinuousTextViewTests: XCTestCase {
    @MainActor
    func testCoordinatorRendersOnlyBoundedWindowForLargeBook() {
        let paragraph = String(repeating: "女巫种田正文", count: 40) + "\n"
        let text = String(repeating: paragraph, count: 5_000)
        let total = (text as NSString).length

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 260))
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 360, height: 260))
        scrollView.documentView = textView

        let coordinator = ContinuousTextView.Coordinator(onPositionChanged: { _ in })
        coordinator.attach(scrollView: scrollView, textView: textView)
        coordinator.update(
            bookID: UUID(),
            text: text,
            anchor: BookPosition(utf16Offset: total / 2),
            style: .default,
            textColor: .textColor
        )

        let renderedLength = (textView.string as NSString).length
        XCTAssertLessThan(renderedLength, total)
        XCTAssertLessThanOrEqual(renderedLength, 130_000)
    }

    @MainActor
    func testUnchangedHighlightDoesNotEditTextStorageAgain() {
        let text = String(repeating: "连续滚动正文。", count: 1_000)
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 260))
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 360, height: 260))
        scrollView.documentView = textView

        let coordinator = ContinuousTextView.Coordinator(onPositionChanged: { _ in })
        coordinator.attach(scrollView: scrollView, textView: textView)
        coordinator.update(
            bookID: UUID(),
            text: text,
            anchor: .zero,
            style: .default,
            textColor: .textColor
        )

        let observer = TextStorageEditObserver()
        textView.textStorage?.delegate = observer

        coordinator.updateHighlight(10..<20)
        XCTAssertGreaterThan(observer.attributeEditCount, 0)

        observer.attributeEditCount = 0
        coordinator.updateHighlight(10..<20)

        XCTAssertEqual(
            observer.attributeEditCount,
            0,
            "SwiftUI position updates must not re-edit an unchanged speech highlight during scrolling"
        )
    }

    @MainActor
    func testNilHighlightDoesNotEditTextStorageDuringOrdinaryScrollUpdates() {
        let text = String(repeating: "普通阅读正文。", count: 1_000)
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 260))
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 360, height: 260))
        scrollView.documentView = textView

        let coordinator = ContinuousTextView.Coordinator(onPositionChanged: { _ in })
        coordinator.attach(scrollView: scrollView, textView: textView)
        coordinator.update(
            bookID: UUID(),
            text: text,
            anchor: .zero,
            style: .default,
            textColor: .textColor
        )

        let observer = TextStorageEditObserver()
        textView.textStorage?.delegate = observer

        coordinator.updateHighlight(nil)

        XCTAssertEqual(
            observer.attributeEditCount,
            0,
            "Ordinary scrolling with no audiobook highlight must not invalidate TextKit attributes"
        )
    }
}

private final class TextStorageEditObserver: NSObject, NSTextStorageDelegate {
    var attributeEditCount = 0

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        if editedMask.contains(.editedAttributes) {
            attributeEditCount += 1
        }
    }
}
#endif

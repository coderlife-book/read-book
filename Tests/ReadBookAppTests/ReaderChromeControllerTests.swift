#if os(macOS)
import XCTest
@testable import ReadBook

@MainActor
final class ReaderChromeControllerTests: XCTestCase {
    func testBodyHoverAndScrollDoNotRevealChrome() {
        let scheduler = ChromeManualScheduler()
        let sut = ReaderChromeController(scheduler: scheduler)
        sut.bodyEntered()
        sut.scrollOccurred()
        scheduler.fireAll()
        XCTAssertFalse(sut.topVisible)
        XCTAssertFalse(sut.bottomVisible)
    }

    func testTopDwellRevealsOnlyTopAfter90ms() {
        let scheduler = ChromeManualScheduler()
        let sut = ReaderChromeController(scheduler: scheduler)
        sut.topZoneChanged(inside: true)
        XCTAssertFalse(sut.topVisible)
        scheduler.fire(milliseconds: 90)
        XCTAssertTrue(sut.topVisible)
        XCTAssertFalse(sut.bottomVisible)
    }

    func testBottomDwellRevealsOnlyBottomAfter90ms() {
        let scheduler = ChromeManualScheduler()
        let sut = ReaderChromeController(scheduler: scheduler)
        sut.bottomZoneChanged(inside: true)
        scheduler.fire(milliseconds: 90)
        XCTAssertFalse(sut.topVisible)
        XCTAssertTrue(sut.bottomVisible)
    }

    func testReturningToBodyDismissesAfter200ms() {
        let scheduler = ChromeManualScheduler()
        let sut = ReaderChromeController(scheduler: scheduler)
        sut.revealAllImmediately()
        sut.bodyEntered()
        XCTAssertTrue(sut.topVisible)
        scheduler.fire(milliseconds: 200)
        XCTAssertFalse(sut.topVisible)
        XCTAssertFalse(sut.bottomVisible)
    }

    func testControlHoverPreventsDismiss() {
        let scheduler = ChromeManualScheduler()
        let sut = ReaderChromeController(scheduler: scheduler)
        sut.revealAllImmediately()
        sut.setControlInteractionHeld(true)
        sut.bodyEntered()
        scheduler.fireAll()
        XCTAssertTrue(sut.topVisible)
        XCTAssertTrue(sut.bottomVisible)
    }
}

@MainActor
private final class ChromeManualScheduler: DelayScheduling {
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

    func fireAll() {
        let pending = entries
        entries.removeAll()
        for entry in pending where !entry.token.cancelled { entry.action() }
    }
}
#endif

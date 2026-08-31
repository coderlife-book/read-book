import AppKit
import XCTest
@testable import ReadBook
@testable import ReadBookCore

@MainActor
final class ReaderWindowStateControllerTests: XCTestCase {
    final class Token: DelayCancellation {
        var cancelled = false
        func cancel() { cancelled = true }
    }

    final class ManualScheduler: DelayScheduling {
        struct Pending {
            let milliseconds: Int
            let token: Token
            let action: @MainActor () -> Void
        }

        var pending: [Pending] = []

        func schedule(
            afterMilliseconds milliseconds: Int,
            action: @escaping @MainActor () -> Void
        ) -> any DelayCancellation {
            let token = Token()
            pending.append(Pending(milliseconds: milliseconds, token: token, action: action))
            return token
        }

        func fire(_ milliseconds: Int) {
            let due = pending.filter { $0.milliseconds == milliseconds && !$0.token.cancelled }
            pending.removeAll { $0.milliseconds == milliseconds }
            due.forEach { $0.action() }
        }
    }

    final class Driver: ReaderWindowDriving {
        var readerFrameInScreen: CGRect? = CGRect(x: 100, y: 100, width: 360, height: 260)
        var visible = true
        var ignoresMouseEvents = false
        var showCount = 0

        func showReader(activate: Bool) {
            visible = true
            showCount += 1
        }
        func hideReader() { visible = false }
        func setPointerPassThrough(_ enabled: Bool) { ignoresMouseEvents = enabled }
    }

    private func concealedPreferences() -> ReaderPreferences {
        var value = ReaderPreferences.defaults
        value.bossModeEnabled = true
        value.bossModeProfile = .concealed
        return value
    }

    func testConcealedExitFiresAutomaticHideAt300ms() {
        let driver = Driver()
        let scheduler = ManualScheduler()
        let sut = ReaderWindowStateController(driver: driver, scheduler: scheduler)
        sut.applyPreferences(concealedPreferences())

        sut.pointerMoved(to: CGPoint(x: 20, y: 20))
        XCTAssertTrue(driver.visible)
        scheduler.fire(300)

        XCTAssertEqual(sut.state, .hidden(.automaticPointerExit))
        XCTAssertFalse(driver.visible)
    }

    func testReentryBefore300msCancelsAutomaticHide() {
        let driver = Driver()
        let scheduler = ManualScheduler()
        let sut = ReaderWindowStateController(driver: driver, scheduler: scheduler)
        sut.applyPreferences(concealedPreferences())

        sut.pointerMoved(to: CGPoint(x: 20, y: 20))
        sut.pointerMoved(to: CGPoint(x: 200, y: 200))
        scheduler.fire(300)

        XCTAssertEqual(sut.state, .floatingText)
        XCTAssertTrue(driver.visible)
    }

    func testAutomaticallyHiddenReaderRestoresWhenPointerReentersStoredFrame() {
        let driver = Driver()
        let scheduler = ManualScheduler()
        let sut = ReaderWindowStateController(driver: driver, scheduler: scheduler)
        sut.applyPreferences(concealedPreferences())

        sut.pointerMoved(to: CGPoint(x: 20, y: 20))
        scheduler.fire(300)
        sut.pointerMoved(to: CGPoint(x: 200, y: 200))

        XCTAssertEqual(sut.state, .floatingText)
        XCTAssertTrue(driver.visible)
        XCTAssertTrue(driver.ignoresMouseEvents)
    }

    func testShortcutHiddenReaderDoesNotRestoreFromPointerReentry() {
        let driver = Driver()
        let scheduler = ManualScheduler()
        let sut = ReaderWindowStateController(driver: driver, scheduler: scheduler)
        sut.applyPreferences(concealedPreferences())
        sut.pointerMoved(to: CGPoint(x: 200, y: 200))

        sut.toggleEmergencyShortcut()
        sut.pointerMoved(to: CGPoint(x: 200, y: 200))

        XCTAssertEqual(sut.state, .hidden(.explicitShortcut))
        XCTAssertFalse(driver.visible)
    }

    func testSecondShortcutRestoresLastVisibleStealthState() {
        let driver = Driver()
        let scheduler = ManualScheduler()
        let sut = ReaderWindowStateController(driver: driver, scheduler: scheduler)
        sut.applyPreferences(concealedPreferences())
        sut.pointerMoved(to: CGPoint(x: 200, y: 200))

        sut.toggleEmergencyShortcut()
        sut.toggleEmergencyShortcut()

        XCTAssertEqual(sut.state, .floatingText)
        XCTAssertTrue(driver.visible)
    }

    func testOptionEntersInteractiveAndReleaseReturnsAfter300ms() {
        let driver = Driver()
        let scheduler = ManualScheduler()
        let sut = ReaderWindowStateController(driver: driver, scheduler: scheduler)
        sut.applyPreferences(concealedPreferences())
        sut.pointerMoved(to: CGPoint(x: 200, y: 200))

        sut.optionChanged(isDown: true)
        XCTAssertEqual(sut.state, .interactiveStealth)
        XCTAssertFalse(driver.ignoresMouseEvents)

        sut.optionChanged(isDown: false)
        scheduler.fire(300)
        XCTAssertEqual(sut.state, .floatingText)
        XCTAssertTrue(driver.ignoresMouseEvents)
    }

    func testLockInteractiveOverridesOptionRelease() {
        let driver = Driver()
        let scheduler = ManualScheduler()
        let sut = ReaderWindowStateController(driver: driver, scheduler: scheduler)
        sut.applyPreferences(concealedPreferences())
        sut.pointerMoved(to: CGPoint(x: 200, y: 200))

        sut.setLockInteractive(true)
        sut.optionChanged(isDown: false)
        scheduler.fire(300)

        XCTAssertEqual(sut.state, .interactiveStealth)
        XCTAssertFalse(driver.ignoresMouseEvents)
    }

    func testPreferenceRefreshDoesNotRevealExplicitlyHiddenReader() {
        let driver = Driver()
        let scheduler = ManualScheduler()
        let sut = ReaderWindowStateController(driver: driver, scheduler: scheduler)
        let preferences = concealedPreferences()
        sut.applyPreferences(preferences)
        sut.toggleEmergencyShortcut()

        var changed = preferences
        changed.fontSize = 22
        sut.applyPreferences(changed)

        XCTAssertEqual(sut.state, .hidden(.explicitShortcut))
        XCTAssertFalse(driver.visible)
    }

    func testAlwaysOnTopRefreshDoesNotReshowVisibleReader() {
        let driver = Driver()
        let sut = ReaderWindowStateController(driver: driver)
        sut.applyPreferences(.defaults)
        let baselineShows = driver.showCount

        var changed = ReaderPreferences.defaults
        changed.alwaysOnTop = true
        sut.applyPreferences(changed)

        XCTAssertEqual(driver.showCount, baselineShows)
        XCTAssertEqual(sut.state, .normal)
    }
}

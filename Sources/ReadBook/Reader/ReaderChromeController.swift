import Observation

@MainActor
@Observable
final class ReaderChromeController {
    private(set) var topVisible = false
    private(set) var bottomVisible = false

    private let scheduler: any DelayScheduling
    private var topReveal: (any DelayCancellation)?
    private var bottomReveal: (any DelayCancellation)?
    private var dismiss: (any DelayCancellation)?
    private var controlInteractionHeld = false

    init(scheduler: any DelayScheduling = TaskDelayScheduler()) {
        self.scheduler = scheduler
    }

    func topZoneChanged(inside: Bool) {
        topReveal?.cancel()
        topReveal = nil
        if inside {
            dismiss?.cancel()
            dismiss = nil
            topReveal = scheduler.schedule(afterMilliseconds: 90) { [weak self] in
                self?.topVisible = true
            }
        } else {
            scheduleDismissIfAllowed()
        }
    }

    func bottomZoneChanged(inside: Bool) {
        bottomReveal?.cancel()
        bottomReveal = nil
        if inside {
            dismiss?.cancel()
            dismiss = nil
            bottomReveal = scheduler.schedule(afterMilliseconds: 90) { [weak self] in
                self?.bottomVisible = true
            }
        } else {
            scheduleDismissIfAllowed()
        }
    }

    func bodyEntered() {
        topReveal?.cancel()
        bottomReveal?.cancel()
        topReveal = nil
        bottomReveal = nil
        scheduleDismissIfAllowed()
    }

    func scrollOccurred() {
        // Reading interaction is intentionally not a chrome-reveal intent.
    }

    func revealAllImmediately() {
        topReveal?.cancel()
        bottomReveal?.cancel()
        dismiss?.cancel()
        topReveal = nil
        bottomReveal = nil
        dismiss = nil
        topVisible = true
        bottomVisible = true
    }

    func setControlInteractionHeld(_ held: Bool) {
        controlInteractionHeld = held
        if held {
            dismiss?.cancel()
            dismiss = nil
        } else {
            scheduleDismissIfAllowed()
        }
    }

    func hideAllImmediately() {
        topReveal?.cancel()
        bottomReveal?.cancel()
        dismiss?.cancel()
        topReveal = nil
        bottomReveal = nil
        dismiss = nil
        topVisible = false
        bottomVisible = false
    }

    private func scheduleDismissIfAllowed() {
        guard !controlInteractionHeld else { return }
        dismiss?.cancel()
        dismiss = scheduler.schedule(afterMilliseconds: 200) { [weak self] in
            guard let self, !self.controlInteractionHeld else { return }
            self.topVisible = false
            self.bottomVisible = false
        }
    }
}

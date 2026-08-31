import AppKit
import SwiftUI

/// Transparent interaction surface for paginated reading.
/// It owns click-half navigation, arrow keys, and horizontal trackpad paging
/// so those interactions do not compete with SwiftUI hit-testing layers.
struct HorizontalScrollPager: NSViewRepresentable {
    let onPrevious: () -> Void
    let onNext: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPrevious: onPrevious, onNext: onNext)
    }

    func makeNSView(context: Context) -> PagerEventView {
        let view = PagerEventView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ view: PagerEventView, context: Context) {
        context.coordinator.onPrevious = onPrevious
        context.coordinator.onNext = onNext
    }

    final class Coordinator {
        var onPrevious: () -> Void
        var onNext: () -> Void

        init(onPrevious: @escaping () -> Void, onNext: @escaping () -> Void) {
            self.onPrevious = onPrevious
            self.onNext = onNext
        }
    }
}

final class PagerEventView: NSView {
    weak var coordinator: HorizontalScrollPager.Coordinator?
    private var accumulatedX: CGFloat = 0
    private var lockedUntil: TimeInterval = 0

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        if point.x < bounds.midX {
            coordinator?.onPrevious()
        } else {
            coordinator?.onNext()
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123:
            coordinator?.onPrevious()
        case 124:
            coordinator?.onNext()
        default:
            super.keyDown(with: event)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard ProcessInfo.processInfo.systemUptime >= lockedUntil else { return }
        guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else {
            accumulatedX = 0
            return
        }

        accumulatedX += event.scrollingDeltaX
        guard abs(accumulatedX) >= 60 else { return }

        if accumulatedX > 0 {
            coordinator?.onPrevious()
        } else {
            coordinator?.onNext()
        }
        accumulatedX = 0
        lockedUntil = ProcessInfo.processInfo.systemUptime + 0.25
    }
}

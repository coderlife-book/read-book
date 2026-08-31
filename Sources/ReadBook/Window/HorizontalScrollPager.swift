import AppKit
import SwiftUI

/// Transparent interaction surface for paginated reading.
/// Click-half and arrow-key navigation stay on the local NSView. Horizontal
/// trackpad paging is observed with a window-scoped local event monitor so
/// vertical wheel/trackpad events are never swallowed accidentally.
@MainActor
struct HorizontalScrollPager: NSViewRepresentable {
    let onPrevious: () -> Void
    let onNext: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPrevious: onPrevious, onNext: onNext)
    }

    func makeNSView(context: Context) -> PagerEventView {
        let view = PagerEventView()
        view.coordinator = context.coordinator
        context.coordinator.view = view
        context.coordinator.install()
        return view
    }

    func updateNSView(_ view: PagerEventView, context: Context) {
        context.coordinator.onPrevious = onPrevious
        context.coordinator.onNext = onNext
        context.coordinator.view = view
    }

    static func dismantleNSView(_ nsView: PagerEventView, coordinator: Coordinator) {
        coordinator.uninstall()
        coordinator.view = nil
        nsView.coordinator = nil
    }

    @MainActor
    final class Coordinator: NSObject {
        weak var view: NSView?
        var onPrevious: () -> Void
        var onNext: () -> Void

        private var monitor: Any?
        private var accumulatedX: CGFloat = 0
        private var lockedUntil: TimeInterval = 0

        init(onPrevious: @escaping () -> Void, onNext: @escaping () -> Void) {
            self.onPrevious = onPrevious
            self.onNext = onNext
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self,
                      let window = self.view?.window,
                      event.windowNumber == window.windowNumber,
                      event.hasPreciseScrollingDeltas,
                      abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
                else {
                    return event
                }

                let now = ProcessInfo.processInfo.systemUptime
                guard now >= self.lockedUntil else { return nil }

                self.accumulatedX += event.scrollingDeltaX
                guard abs(self.accumulatedX) >= 60 else { return nil }

                if self.accumulatedX > 0 {
                    self.onPrevious()
                } else {
                    self.onNext()
                }
                self.accumulatedX = 0
                self.lockedUntil = now + 0.25
                return nil
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            accumulatedX = 0
            lockedUntil = 0
        }
    }
}

@MainActor
final class PagerEventView: NSView {
    weak var coordinator: HorizontalScrollPager.Coordinator?

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
}

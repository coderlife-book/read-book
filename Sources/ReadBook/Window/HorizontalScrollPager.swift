import AppKit
import SwiftUI

enum HorizontalPagingGestureResult: Equatable {
    case notHandled
    case handled
    case previous
    case next
}

struct HorizontalPagingGesture {
    private var accumulatedX: CGFloat = 0
    private var lockedUntil: TimeInterval = 0

    mutating func consume(
        deltaX: CGFloat,
        deltaY: CGFloat,
        precise: Bool,
        now: TimeInterval
    ) -> HorizontalPagingGestureResult {
        guard precise, abs(deltaX) > abs(deltaY) else {
            accumulatedX = 0
            return .notHandled
        }

        guard now >= lockedUntil else { return .handled }

        accumulatedX += deltaX
        guard abs(accumulatedX) >= 60 else { return .handled }

        let result: HorizontalPagingGestureResult = accumulatedX > 0 ? .previous : .next
        accumulatedX = 0
        lockedUntil = now + 0.25
        return result
    }
}

/// Transparent interaction surface for paginated reading.
/// All mouse, keyboard, and trackpad handling stays inside this NSView. There
/// are deliberately no NSEvent local/global monitors in the reader process.
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
        return view
    }

    func updateNSView(_ view: PagerEventView, context: Context) {
        context.coordinator.onPrevious = onPrevious
        context.coordinator.onNext = onNext
        view.coordinator = context.coordinator
    }

    static func dismantleNSView(_ nsView: PagerEventView, coordinator: Coordinator) {
        nsView.coordinator = nil
    }

    @MainActor
    final class Coordinator: NSObject {
        var onPrevious: () -> Void
        var onNext: () -> Void

        init(onPrevious: @escaping () -> Void, onNext: @escaping () -> Void) {
            self.onPrevious = onPrevious
            self.onNext = onNext
        }
    }
}

@MainActor
final class PagerEventView: NSView {
    weak var coordinator: HorizontalScrollPager.Coordinator?
    private var pagingGesture = HorizontalPagingGesture()

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
        let result = pagingGesture.consume(
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY,
            precise: event.hasPreciseScrollingDeltas,
            now: ProcessInfo.processInfo.systemUptime
        )

        switch result {
        case .notHandled:
            super.scrollWheel(with: event)
        case .handled:
            break
        case .previous:
            coordinator?.onPrevious()
        case .next:
            coordinator?.onNext()
        }
    }
}

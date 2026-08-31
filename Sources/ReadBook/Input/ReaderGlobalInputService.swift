import AppKit

@MainActor
final class ReaderGlobalInputService {
    private var globalPointerMonitor: Any?
    private var localPointerMonitor: Any?
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?

    private var onPointer: (@MainActor (CGPoint) -> Void)?
    private var onOption: (@MainActor (Bool) -> Void)?

    private static let pointerEvents: NSEvent.EventTypeMask = [
        .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged
    ]

    @discardableResult
    func start(
        onPointer: @escaping @MainActor (CGPoint) -> Void,
        onOption: @escaping @MainActor (Bool) -> Void
    ) -> Bool {
        stop()
        self.onPointer = onPointer
        self.onOption = onOption

        globalPointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: Self.pointerEvents) { [weak self] _ in
            let point = NSEvent.mouseLocation
            Task { @MainActor in self?.onPointer?(point) }
        }
        localPointerMonitor = NSEvent.addLocalMonitorForEvents(matching: Self.pointerEvents) { [weak self] event in
            let point = NSEvent.mouseLocation
            Task { @MainActor in self?.onPointer?(point) }
            return event
        }

        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let isDown = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.option)
            Task { @MainActor in self?.onOption?(isDown) }
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let isDown = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.option)
            Task { @MainActor in self?.onOption?(isDown) }
            return event
        }

        onPointer(NSEvent.mouseLocation)
        return globalPointerMonitor != nil && localPointerMonitor != nil
    }

    func stop() {
        if let token = globalPointerMonitor { NSEvent.removeMonitor(token) }
        if let token = localPointerMonitor { NSEvent.removeMonitor(token) }
        if let token = globalFlagsMonitor { NSEvent.removeMonitor(token) }
        if let token = localFlagsMonitor { NSEvent.removeMonitor(token) }
        globalPointerMonitor = nil
        localPointerMonitor = nil
        globalFlagsMonitor = nil
        localFlagsMonitor = nil
        onPointer = nil
        onOption = nil
    }
}

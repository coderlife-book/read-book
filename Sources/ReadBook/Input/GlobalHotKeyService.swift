import Carbon.HIToolbox
import Foundation

@MainActor
protocol GlobalHotKeyServicing: AnyObject {
    @discardableResult
    func start(onPress: @escaping @MainActor () -> Void) -> Bool
    func stop()
}

@MainActor
final class GlobalHotKeyService: GlobalHotKeyServicing {
    private static let signature: OSType = 0x5244424B // RDBK
    private static let identifier: UInt32 = 1

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var onPress: (@MainActor () -> Void)?

    var isRegistered: Bool { hotKeyRef != nil && handlerRef != nil }

    @discardableResult
    func start(onPress: @escaping @MainActor () -> Void) -> Bool {
        stop()
        self.onPress = onPress

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.eventHandler,
            1,
            &eventType,
            userData,
            &handlerRef
        )
        guard installStatus == noErr else {
            stop()
            return false
        }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.identifier)
        let modifiers = UInt32(controlKey | optionKey)
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_R),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            stop()
            return false
        }
        return true
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
        handlerRef = nil
        onPress = nil
    }

    private static let eventHandler: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }
        var hotKeyID = EventHotKeyID(signature: 0, id: 0)
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr,
              hotKeyID.signature == signature,
              hotKeyID.id == identifier else {
            return OSStatus(eventNotHandledErr)
        }

        let service = Unmanaged<GlobalHotKeyService>.fromOpaque(userData).takeUnretainedValue()
        Task { @MainActor in service.onPress?() }
        return noErr
    }
}

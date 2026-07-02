import Carbon
import Foundation

final class HotKeyController {
    enum RegistrationError: Error {
        case handlerInstallFailed(OSStatus)
        case hotKeyRegistrationFailed(OSStatus)
    }

    private static let hotKeySignature: OSType = 0x51414944
    private static let hotKeyID: UInt32 = 1

    private let callback: () -> Void
    private var eventHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    init(callback: @escaping () -> Void) {
        self.callback = callback
    }

    deinit {
        if let eventHotKeyRef {
            UnregisterEventHotKey(eventHotKeyRef)
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func register() throws {
        guard eventHotKeyRef == nil, eventHandlerRef == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        var handlerRef: EventHandlerRef?
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return noErr
                }

                var hotKeyID = EventHotKeyID()
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
                      hotKeyID.signature == HotKeyController.hotKeySignature,
                      hotKeyID.id == HotKeyController.hotKeyID
                else {
                    return noErr
                }

                let controller = Unmanaged<HotKeyController>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                controller.callback()

                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )

        guard handlerStatus == noErr, let handlerRef else {
            throw RegistrationError.handlerInstallFailed(handlerStatus)
        }

        eventHandlerRef = handlerRef

        let hotKeyID = EventHotKeyID(
            signature: Self.hotKeySignature,
            id: Self.hotKeyID
        )
        var hotKeyRef: EventHotKeyRef?
        let hotKeyStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(controlKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard hotKeyStatus == noErr, let hotKeyRef else {
            RemoveEventHandler(handlerRef)
            eventHandlerRef = nil
            throw RegistrationError.hotKeyRegistrationFailed(hotKeyStatus)
        }

        eventHotKeyRef = hotKeyRef
    }
}

import Carbon
import Foundation

/// A system-wide keyboard shortcut via Carbon's `RegisterEventHotKey`.
/// Works in the sandbox and needs no Accessibility permission.
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void
    private let identifier: UInt32

    /// - Parameters:
    ///   - keyCode: virtual key code, e.g. `kVK_ANSI_K`.
    ///   - modifiers: Carbon modifier mask, e.g. `cmdKey | optionKey`.
    ///   - identifier: unique per hot key; every handler sees every hot key, so each checks its own id.
    init?(keyCode: Int, modifiers: Int, identifier: UInt32 = 1, action: @escaping () -> Void) {
        self.action = action
        self.identifier = identifier

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let userData, let event else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                var pressed = EventHotKeyID()
                let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                               nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
                guard status == noErr, pressed.id == hotKey.identifier else { return OSStatus(eventNotHandledErr) }
                DispatchQueue.main.async { hotKey.action() }
                return noErr
            },
            1,
            &eventType,
            userData,
            &handlerRef
        )
        guard installStatus == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4153_494B), id: identifier) // 'ASIK'
        let registerStatus = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            if let handlerRef { RemoveEventHandler(handlerRef) }
            handlerRef = nil
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

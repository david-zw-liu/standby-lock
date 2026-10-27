import Carbon

final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let callback: () -> Void

    init(keyCode: UInt32, modifiers: UInt32, callback: @escaping () -> Void) {
        self.callback = callback

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
            guard let userData else { return noErr }
            Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().callback()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)

        let hotKeyID = EventHotKeyID(signature: OSType(0x5354_424C), id: 1)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

import Carbon.HIToolbox
import Foundation

struct GlobalHotKeyShortcut: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    static let optionSpace = GlobalHotKeyShortcut(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(optionKey)
    )
}

private let monkHotKeySignature: OSType = 0x4D4F4E4B // MONK
private let monkHotKeyIdentifier = EventHotKeyID(signature: monkHotKeySignature, id: 1)

private let monkHotKeyEventHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else {
        return OSStatus(eventNotHandledErr)
    }

    var identifier = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &identifier
    )

    guard status == noErr, identifier.signature == monkHotKeyIdentifier.signature,
          identifier.id == monkHotKeyIdentifier.id else {
        return OSStatus(eventNotHandledErr)
    }

    let controller = Unmanaged<GlobalHotKeyController>
        .fromOpaque(userData)
        .takeUnretainedValue()

    Task { @MainActor in
        controller.performAction()
    }
    return noErr
}

@MainActor
final class GlobalHotKeyController {
    private let shortcut: GlobalHotKeyShortcut
    private let action: () -> Void
    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?

    private(set) var isRegistered = false

    init(shortcut: GlobalHotKeyShortcut = .optionSpace, action: @escaping () -> Void) {
        self.shortcut = shortcut
        self.action = action
    }

    @discardableResult
    func register() -> Bool {
        guard !isRegistered else { return true }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            monkHotKeyEventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerReference
        )
        guard handlerStatus == noErr else { return false }

        let registrationStatus = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            monkHotKeyIdentifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )

        guard registrationStatus == noErr else {
            if let eventHandlerReference {
                RemoveEventHandler(eventHandlerReference)
                self.eventHandlerReference = nil
            }
            return false
        }

        isRegistered = true
        return true
    }

    func unregister() {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
            self.hotKeyReference = nil
        }
        if let eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
            self.eventHandlerReference = nil
        }
        isRegistered = false
    }

    func performAction() {
        action()
    }

    deinit {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
        }
        if let eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
        }
    }
}

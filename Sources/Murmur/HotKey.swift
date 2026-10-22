import AppKit
import Carbon.HIToolbox

struct HotKeySpec: Equatable {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let key: String
    let modifierFlags: NSEvent.ModifierFlags

    static let defaultValue = "ctrl+option+cmd+r"
    static let defaultMuteValue = "ctrl+option+cmd+m"

    private static let modifiers: [String: (carbon: Int, flag: NSEvent.ModifierFlags, order: Int)] = [
        "ctrl": (controlKey, .control, 0), "control": (controlKey, .control, 0),
        "option": (optionKey, .option, 1), "opt": (optionKey, .option, 1), "alt": (optionKey, .option, 1),
        "shift": (shiftKey, .shift, 2),
        "cmd": (cmdKey, .command, 3), "command": (cmdKey, .command, 3),
    ]

    private static let keyCodes: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
        "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
        "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z, "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
        "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
    ]

    static func parse(_ text: String) -> HotKeySpec? {
        let parts = text.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let key = parts.last, let keyCode = keyCodes[key] else { return nil }
        var carbon = 0
        var flags: NSEvent.ModifierFlags = []
        for part in parts.dropLast() {
            guard let modifier = modifiers[part] else { return nil }
            carbon |= modifier.carbon
            flags.insert(modifier.flag)
        }
        guard !flags.intersection([.command, .control, .option]).isEmpty else { return nil }
        return HotKeySpec(keyCode: UInt32(keyCode), carbonModifiers: UInt32(carbon), key: key, modifierFlags: flags)
    }

    var display: String {
        let symbols: [(NSEvent.ModifierFlags, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return symbols.filter { modifierFlags.contains($0.0) }.map(\.1).joined() + key.uppercased()
    }
}

/// Every shortcut's handler sees every shortcut press, so each one only acts on its own ID and
/// passes the others on down the handler chain.
final class GlobalHotKey {
    static let signature = OSType(0x4D524D52)

    let id: UInt32
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    init(_ spec: HotKeySpec, id: UInt32, setting: String, action: @escaping () -> Void) throws {
        self.id = id
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                var pressed = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed
                )
                guard status == noErr, GlobalHotKey.matches(pressed, id: hotKey.id) else { return OSStatus(eventNotHandledErr) }
                hotKey.action()
                return noErr
            },
            1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef
        )
        guard installStatus == noErr else { throw HotKeyError(spec: spec, setting: setting, status: installStatus) }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(spec.keyCode, spec.carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr else {
            if let handlerRef { RemoveEventHandler(handlerRef) }
            throw HotKeyError(spec: spec, setting: setting, status: status)
        }
    }

    static func matches(_ pressed: EventHotKeyID, id: UInt32) -> Bool {
        pressed.signature == signature && pressed.id == id
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

struct HotKeyError: LocalizedError {
    let spec: HotKeySpec
    let setting: String
    let status: OSStatus

    var errorDescription: String? {
        status == OSStatus(eventHotKeyExistsErr)
            ? "\(spec.display) is already used by another app. Set a different \(setting) in Settings (.env)."
            : "Couldn't register \(spec.display) (error \(status))."
    }
}

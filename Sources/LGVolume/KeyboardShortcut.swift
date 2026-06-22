import AppKit
import Carbon.HIToolbox

struct KeyboardShortcut: Equatable {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags
    let display: String

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, display: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.allowedModifiers)
        self.display = display
    }

    init?(event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(Self.allowedModifiers)
        let key = Self.keyName(for: event)
        guard !key.isEmpty,
              !Self.reservedKeyCodes.contains(event.keyCode),
              Self.isSafeGlobalShortcut(modifiers: modifiers, keyCode: event.keyCode) else {
            return nil
        }
        self.init(keyCode: event.keyCode, modifiers: modifiers, display: Self.display(modifiers: modifiers, key: key))
    }

    init?(storageValue: String) {
        let parts = storageValue.components(separatedBy: "|")
        guard parts.count == 3,
              let keyCode = UInt16(parts[0]),
              let modifierRaw = UInt(parts[1]) else {
            return nil
        }
        let modifiers = NSEvent.ModifierFlags(rawValue: modifierRaw).intersection(Self.allowedModifiers)
        let storedDisplay = parts[2]
        guard !Self.reservedKeyCodes.contains(keyCode),
              Self.isSafeGlobalShortcut(modifiers: modifiers, keyCode: keyCode) else {
            return nil
        }
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.display = storedDisplay
    }

    var storageValue: String {
        "\(keyCode)|\(modifiers.rawValue)|\(display)"
    }

    func matches(_ event: NSEvent) -> Bool {
        event.keyCode == keyCode && event.modifierFlags.intersection(Self.allowedModifiers) == modifiers
    }

    var carbonModifiers: UInt32 {
        var value: UInt32 = 0
        if modifiers.contains(.command) { value |= UInt32(cmdKey) }
        if modifiers.contains(.option) { value |= UInt32(optionKey) }
        if modifiers.contains(.control) { value |= UInt32(controlKey) }
        if modifiers.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }

    static func defaultHDMIShortcut(index: Int) -> KeyboardShortcut? {
        let keyCodes: [UInt16] = [123, 126, 125, 124]
        guard (1...4).contains(index) else {
            return nil
        }

        let keyCode = keyCodes[index - 1]
        let modifiers: NSEvent.ModifierFlags = [.control, .option, .command]
        let key = specialKeyName(keyCode) ?? ""
        return KeyboardShortcut(keyCode: keyCode, modifiers: modifiers, display: display(modifiers: modifiers, key: key))
    }

    private static let allowedModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
    private static let requiredModifiers: NSEvent.ModifierFlags = [.command, .option, .control]
    private static let reservedKeyCodes: Set<UInt16> = [103, 109, 111]

    private static func isSafeGlobalShortcut(modifiers: NSEvent.ModifierFlags, keyCode: UInt16) -> Bool {
        if !modifiers.intersection(requiredModifiers).isEmpty {
            return true
        }
        return functionKeyCodes.contains(keyCode)
    }

    private static let functionKeyCodes: Set<UInt16> = [
        96, 97, 98, 99, 100, 101, 103, 105, 106, 107, 109, 111, 113, 118, 120, 122
    ]

    private static func display(modifiers: NSEvent.ModifierFlags, key: String) -> String {
        var value = ""
        if modifiers.contains(.control) { value += "⌃" }
        if modifiers.contains(.option) { value += "⌥" }
        if modifiers.contains(.shift) { value += "⇧" }
        if modifiers.contains(.command) { value += "⌘" }
        return value + key
    }

    private static func keyName(for event: NSEvent) -> String {
        if let special = specialKeyName(event.keyCode) {
            return special
        }
        let chars = event.charactersIgnoringModifiers ?? ""
        return chars.uppercased()
    }

    private static func specialKeyName(_ keyCode: UInt16) -> String? {
        switch keyCode {
        case 36: return "↩"
        case 48: return "⇥"
        case 49: return "Space"
        case 51: return "⌫"
        case 53: return "Esc"
        case 71: return "Clear"
        case 76: return "⌤"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 105: return "F13"
        case 106: return "F16"
        case 107: return "F14"
        case 109: return "F10"
        case 111: return "F12"
        case 113: return "F15"
        case 114: return "Help"
        case 115: return "Home"
        case 116: return "PgUp"
        case 117: return "⌦"
        case 118: return "F4"
        case 119: return "End"
        case 120: return "F2"
        case 121: return "PgDn"
        case 122: return "F1"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return nil
        }
    }
}

final class ShortcutRecorderField: NSTextField {
    var recordingPlaceholder = "Press a shortcut"
    var emptyPlaceholder = "Not set"
    var invalidPlaceholder = "Add Command, Option, or Control"

    var shortcut: KeyboardShortcut? {
        didSet {
            stringValue = shortcut?.display ?? ""
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted, shortcut == nil {
            placeholderString = recordingPlaceholder
        }
        return accepted
    }

    override func keyDown(with event: NSEvent) {
        capture(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        capture(event)
        return true
    }

    private func capture(_ event: NSEvent) {
        if event.keyCode == 53 || event.keyCode == 51 || event.keyCode == 117 {
            shortcut = nil
            placeholderString = emptyPlaceholder
            return
        }

        guard let value = KeyboardShortcut(event: event) else {
            placeholderString = invalidPlaceholder
            NSSound.beep()
            return
        }
        shortcut = value
    }
}

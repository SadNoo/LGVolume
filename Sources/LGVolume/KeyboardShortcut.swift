import AppKit

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
        guard !key.isEmpty else {
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
        self.keyCode = keyCode
        self.modifiers = NSEvent.ModifierFlags(rawValue: modifierRaw).intersection(Self.allowedModifiers)
        self.display = parts[2]
    }

    var storageValue: String {
        "\(keyCode)|\(modifiers.rawValue)|\(display)"
    }

    func matches(_ event: NSEvent) -> Bool {
        event.keyCode == keyCode && event.modifierFlags.intersection(Self.allowedModifiers) == modifiers
    }

    private static let allowedModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

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
    var shortcut: KeyboardShortcut? {
        didSet {
            stringValue = shortcut?.display ?? ""
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted, shortcut == nil {
            placeholderString = "按下快捷键"
        }
        return accepted
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 || event.keyCode == 51 || event.keyCode == 117 {
            shortcut = nil
            placeholderString = "未设置"
            return
        }

        guard let value = KeyboardShortcut(event: event) else {
            NSSound.beep()
            return
        }
        shortcut = value
    }
}

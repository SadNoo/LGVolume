import Foundation

final class AppSettings {
    private let defaults = UserDefaults(suiteName: "local.codex.lgvolume") ?? .standard

    private enum Key {
        static let tvIP = "tvIP"
        static let tvName = "tvName"
        static let clientKey = "clientKey"
        static let volume = "volume"
        static let muted = "muted"
        static let hdmiNamePrefix = "hdmiName"
        static let hdmiShortcutPrefix = "hdmiShortcut"
        static let appearanceMode = "appearanceMode"
        static let launchAtLogin = "launchAtLogin"
        static let accessibilityPromptShown = "accessibilityPromptShown"
    }

    var tvIP: String {
        get { defaults.string(forKey: Key.tvIP) ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.tvIP) }
    }

    var tvName: String {
        get {
            let value = defaults.string(forKey: Key.tvName) ?? "LG TV"
            return value.isEmpty ? "LG TV" : value
        }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.tvName) }
    }

    var clientKey: String {
        get { defaults.string(forKey: Key.clientKey) ?? "" }
        set { defaults.set(newValue, forKey: Key.clientKey) }
    }

    var volume: Int {
        get {
            let stored = defaults.object(forKey: Key.volume) as? Int ?? 50
            return min(max(stored, 0), 100)
        }
        set { defaults.set(min(max(newValue, 0), 100), forKey: Key.volume) }
    }

    var muted: Bool {
        get { defaults.bool(forKey: Key.muted) }
        set { defaults.set(newValue, forKey: Key.muted) }
    }

    func hdmiName(_ index: Int) -> String {
        let fallback = "HDMI\(index)"
        let value = defaults.string(forKey: "\(Key.hdmiNamePrefix)\(index)") ?? fallback
        return value.isEmpty ? fallback : value
    }

    func setHDMIName(_ name: String, index: Int) {
        let fallback = "HDMI\(index)"
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(trimmed.isEmpty ? fallback : trimmed, forKey: "\(Key.hdmiNamePrefix)\(index)")
    }

    var hdmiNames: [String] {
        (1...4).map { hdmiName($0) }
    }

    func hdmiShortcut(_ index: Int) -> KeyboardShortcut? {
        guard let raw = defaults.string(forKey: "\(Key.hdmiShortcutPrefix)\(index)") else {
            return KeyboardShortcut.defaultHDMIShortcut(index: index)
        }
        return KeyboardShortcut(storageValue: raw) ?? KeyboardShortcut.defaultHDMIShortcut(index: index)
    }

    func setHDMIShortcut(_ shortcut: KeyboardShortcut?, index: Int) {
        let key = "\(Key.hdmiShortcutPrefix)\(index)"
        if let shortcut {
            defaults.set(shortcut.storageValue, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    var hdmiShortcuts: [KeyboardShortcut?] {
        (1...4).map { hdmiShortcut($0) }
    }

    func clearClientKey() {
        defaults.removeObject(forKey: Key.clientKey)
    }

    var appearanceMode: String {
        get {
            let value = defaults.string(forKey: Key.appearanceMode) ?? "auto"
            return ["auto", "light", "dark"].contains(value) ? value : "auto"
        }
        set {
            defaults.set(newValue, forKey: Key.appearanceMode)
        }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin) }
        set { defaults.set(newValue, forKey: Key.launchAtLogin) }
    }

    var accessibilityPromptShown: Bool {
        get { defaults.bool(forKey: Key.accessibilityPromptShown) }
        set { defaults.set(newValue, forKey: Key.accessibilityPromptShown) }
    }
}

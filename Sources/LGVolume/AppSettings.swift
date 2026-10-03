import Foundation

final class AppSettings {
    private let defaults: UserDefaults
    private let tokenStore: PairingTokenStoring

    init(
        defaults: UserDefaults = UserDefaults(suiteName: "local.codex.lgvolume") ?? .standard,
        tokenStore: PairingTokenStoring = FilePairingTokenStore()
    ) {
        self.defaults = defaults
        self.tokenStore = tokenStore
        migratePreferencesTokenIfNeeded()
    }

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
        static let languageMode = "languageMode"
        static let secureConnectionOnly = "secureConnectionOnly"
        static let useTVInputNames = "useTVInputNames"
        static let sleepTVWithMac = "sleepTVWithMac"
        static let macHDMIPortOverride = "macHDMIPortOverride"
        static let lastDetectedMacHDMIPort = "lastDetectedMacHDMIPort"
        static let pairingGrantsPower = "pairingGrantsPower"
        static let menuStyle = "menuStyle"
        static let deviceKindMode = "deviceKindMode"
        static let volumeKeysOnlyForTVAudio = "volumeKeysOnlyForTVAudio"
        static let standbyAction = "standbyAction"
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
        tokenStore.read()
    }

    @discardableResult
    func saveClientKey(_ value: String) -> Bool {
        tokenStore.save(value)
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
        if raw == "disabled" {
            return nil
        }
        return KeyboardShortcut(storageValue: raw) ?? KeyboardShortcut.defaultHDMIShortcut(index: index)
    }

    func setHDMIShortcut(_ shortcut: KeyboardShortcut?, index: Int) {
        let key = "\(Key.hdmiShortcutPrefix)\(index)"
        if let shortcut {
            defaults.set(shortcut.storageValue, forKey: key)
        } else {
            defaults.set("disabled", forKey: key)
        }
    }

    func resetHDMIShortcuts() {
        for index in 1...4 {
            defaults.removeObject(forKey: "\(Key.hdmiShortcutPrefix)\(index)")
        }
    }

    var hdmiShortcuts: [KeyboardShortcut?] {
        (1...4).map { hdmiShortcut($0) }
    }

    func clearClientKey() {
        tokenStore.clear()
        defaults.removeObject(forKey: Key.clientKey)
        pairingGrantsPower = false
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

    var languageMode: String {
        get {
            let value = defaults.string(forKey: Key.languageMode) ?? "auto"
            return ["auto", "zh-Hans", "en", "ja"].contains(value) ? value : "auto"
        }
        set {
            defaults.set(newValue, forKey: Key.languageMode)
        }
    }

    var secureConnectionOnly: Bool {
        get { defaults.bool(forKey: Key.secureConnectionOnly) }
        set { defaults.set(newValue, forKey: Key.secureConnectionOnly) }
    }

    var useTVInputNames: Bool {
        get { defaults.bool(forKey: Key.useTVInputNames) }
        set { defaults.set(newValue, forKey: Key.useTVInputNames) }
    }

    /// Put the TV in standby when the Mac goes to system sleep (only if it shows the Mac's input).
    var sleepTVWithMac: Bool {
        get { defaults.bool(forKey: Key.sleepTVWithMac) }
        set { defaults.set(newValue, forKey: Key.sleepTVWithMac) }
    }

    /// 0 means automatic detection from the TV's EDID; 1-4 forces an HDMI input.
    var macHDMIPortOverride: Int {
        get {
            let value = defaults.integer(forKey: Key.macHDMIPortOverride)
            return (1...4).contains(value) ? value : 0
        }
        set { defaults.set((1...4).contains(newValue) ? newValue : 0, forKey: Key.macHDMIPortOverride) }
    }

    /// Last port read from the EDID, kept for moments when the display is briefly unavailable.
    var lastDetectedMacHDMIPort: Int? {
        get {
            let value = defaults.integer(forKey: Key.lastDetectedMacHDMIPort)
            return (1...4).contains(value) ? value : nil
        }
        set { defaults.set(newValue ?? 0, forKey: Key.lastDetectedMacHDMIPort) }
    }

    /// Whether the saved pairing was registered with the power permission. Older pairings were
    /// not, and reconnecting with a different permission list could make the TV prompt again.
    var pairingGrantsPower: Bool {
        get { defaults.bool(forKey: Key.pairingGrantsPower) }
        set { defaults.set(newValue, forKey: Key.pairingGrantsPower) }
    }

    var deviceKindMode: DeviceKindMode {
        get { defaults.string(forKey: Key.deviceKindMode).flatMap(DeviceKindMode.init(rawValue:)) ?? .defaultMode }
        set { defaults.set(newValue.rawValue, forKey: Key.deviceKindMode) }
    }

    /// F10-F12 and the media volume keys control the TV only while the Mac's sound goes to it.
    var volumeKeysOnlyForTVAudio: Bool {
        get { defaults.object(forKey: Key.volumeKeysOnlyForTVAudio) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.volumeKeysOnlyForTVAudio) }
    }

    var standbyAction: StandbyAction {
        get { defaults.string(forKey: Key.standbyAction).flatMap(StandbyAction.init(rawValue:)) ?? .powerOff }
        set { defaults.set(newValue.rawValue, forKey: Key.standbyAction) }
    }

    var menuStyle: MenuPanelStyle {
        get { defaults.string(forKey: Key.menuStyle).flatMap(MenuPanelStyle.init(rawValue:)) ?? .defaultStyle }
        set { defaults.set(newValue.rawValue, forKey: Key.menuStyle) }
    }

    private func migratePreferencesTokenIfNeeded() {
        guard let legacyToken = defaults.string(forKey: Key.clientKey), !legacyToken.isEmpty else { return }
        if !tokenStore.read().isEmpty || tokenStore.save(legacyToken) {
            defaults.removeObject(forKey: Key.clientKey)
        }
    }
}

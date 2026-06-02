import AppKit
import Combine
import ServiceManagement

final class AppCoordinator: ObservableObject {
    private let settings = AppSettings()
    private let webOSClient = WebOSClient()
    private lazy var settingsWindowController = SettingsWindowController(settings: settings, coordinator: self)
    private lazy var keyboardVolumeMonitor = KeyboardVolumeMonitor(
        onVolumeDown: { [weak self] in DispatchQueue.main.async { self?.adjustVolumeByKeyboard(delta: -1) } },
        onVolumeUp: { [weak self] in DispatchQueue.main.async { self?.adjustVolumeByKeyboard(delta: 1) } },
        onMute: { [weak self] in DispatchQueue.main.async { self?.toggleMuteFromPanel() } },
        hdmiShortcuts: { [weak self] in self?.settings.hdmiShortcuts ?? [] },
        onHDMIShortcut: { [weak self] index in DispatchQueue.main.async { self?.switchHDMIFromPanel(index: index) } },
        shouldPromptForAccessibility: { [weak self] in self?.settings.accessibilityPromptShown == false },
        markAccessibilityPromptShown: { [weak self] in self?.settings.accessibilityPromptShown = true }
    )

    @Published private(set) var status = "" {
        didSet {
            settingsWindowController.updateStatus(status)
        }
    }
    @Published private(set) var menuTitle = "LG TV"
    @Published private(set) var menuVolume = 50
    @Published private(set) var menuMuted = false
    @Published private(set) var menuHDMINames = ["HDMI1", "HDMI2", "HDMI3", "HDMI4"]
    @Published private(set) var selectedHDMIIndex: Int?
    @Published private(set) var menuLanguageMode = "auto"

    var isMuted: Bool { menuMuted }
    var isConnected: Bool { webOSClient.isConnected }
    var currentVolume: Int { menuVolume }
    var currentTVIP: String { settings.tvIP }
    var launchAtLogin: Bool { settings.launchAtLogin }
    var hdmiShortcuts: [KeyboardShortcut?] { settings.hdmiShortcuts }

    init() {
        status = text(.currentDisconnected)
        syncMenuState()
    }

    func start() {
        applyAppearance()
        syncMenuState()
        keyboardVolumeMonitor.start()
        if !settings.tvIP.isEmpty {
            connect(showPairingPrompt: false)
        } else {
            discoverTV()
        }
    }

    func showSettings() {
        settingsWindowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController.refresh()
    }

    func quit() {
        NSApp.terminate(nil)
    }

    func text(_ key: L10n.Key) -> String {
        L10n.text(key, languageMode: settings.languageMode)
    }

    func discoverTV() {
        status = text(.scanNetwork)
        DiscoveryService().scan { [weak self] devices in
            DispatchQueue.main.async {
                guard let self else { return }
                self.settingsWindowController.updateDevices(devices)
                if let first = devices.first {
                    self.status = "\(self.text(.connected)) \(first.name) (\(first.ip))"
                    self.settingsWindowController.refresh()
                } else {
                    self.status = self.text(.currentDisconnected)
                }
            }
        }
    }

    func saveManualSettings(ip: String, name: String) {
        settings.tvIP = ip
        settings.tvName = name.isEmpty ? "LG TV" : name
        syncMenuState()
        status = text(.saveSuccess)
    }

    func saveHDMINames(_ names: [String]) {
        for (offset, name) in names.enumerated() {
            settings.setHDMIName(name, index: offset + 1)
        }
        syncMenuState()
        status = text(.saveSuccess)
        settingsWindowController.refresh()
    }

    func saveHDMIShortcuts(_ shortcuts: [KeyboardShortcut?]) {
        for (offset, shortcut) in shortcuts.enumerated() {
            settings.setHDMIShortcut(shortcut, index: offset + 1)
        }
        keyboardVolumeMonitor.updateHDMIShortcuts(settings.hdmiShortcuts)
        status = text(.saveSuccess)
        settingsWindowController.refresh()
    }

    func restoreDefaultHDMIShortcuts() {
        settings.resetHDMIShortcuts()
        keyboardVolumeMonitor.updateHDMIShortcuts(settings.hdmiShortcuts)
        status = text(.saveSuccess)
        settingsWindowController.refresh()
    }

    func pair() {
        settings.clearClientKey()
        connect(showPairingPrompt: true)
    }

    func disconnect() {
        webOSClient.disconnect()
        selectedHDMIIndex = nil
        status = text(.disconnected)
        settingsWindowController.refresh()
    }

    func setAppearanceMode(_ mode: String) {
        settings.appearanceMode = mode
        applyAppearance()
        syncMenuState()
        settingsWindowController.refresh()
    }

    func setLanguageMode(_ mode: String) {
        settings.languageMode = mode
        menuLanguageMode = mode
        status = webOSClient.isConnected ? "\(text(.connected)) \(settings.tvName)" : text(.currentDisconnected)
        syncMenuState()
        settingsWindowController.refreshLocalizedText()
        settingsWindowController.refresh()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        settings.launchAtLogin = enabled
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
                status = text(.save)
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
                status = text(.save)
            }
        } catch {
            settings.launchAtLogin = SMAppService.mainApp.status == .enabled
            status = "\(text(.launch)) \(error.localizedDescription)"
        }
        settingsWindowController.refresh()
    }

    func refreshVolume() {
        guard webOSClient.isConnected else {
            connect(showPairingPrompt: false)
            return
        }
        webOSClient.getVolume { [weak self] result in
            DispatchQueue.main.async {
                self?.handleVolumeResult(result)
            }
        }
    }

    func setVolumeFromPanel(_ volume: Int) {
        let previousVolume = settings.volume
        let delta = volume - previousVolume
        settings.volume = volume
        settings.muted = false
        syncMenuState()

        ensureConnectedThen { [weak self] in
            guard let self else { return }
            self.webOSClient.changeVolume(delta: delta) { stepResult in
                DispatchQueue.main.async {
                    switch stepResult {
                    case .success:
                        self.handleCommandResult(.success(()), success: "\(self.text(.volume)) \(volume)%")
                        self.refreshVolume()
                    case .failure:
                        self.webOSClient.setVolume(volume) { setResult in
                            DispatchQueue.main.async {
                                self.handleCommandResult(setResult, success: "\(self.text(.volume)) \(volume)%")
                                self.refreshVolume()
                            }
                        }
                    }
                }
            }
        }
    }

    func toggleMuteFromPanel() {
        settings.muted.toggle()
        syncMenuState()

        ensureConnectedThen { [weak self] in
            guard let self else { return }
            self.webOSClient.setMuted(self.settings.muted) { result in
                DispatchQueue.main.async {
                    self.handleCommandResult(result, success: self.settings.muted ? self.text(.turnMuteOn) : self.text(.turnMuteOff))
                }
            }
        }
    }

    func switchHDMIFromPanel(index: Int) {
        ensureConnectedThen { [weak self] in
            guard let self else { return }
            self.webOSClient.switchHDMI(index) { result in
                DispatchQueue.main.async {
                    let name = self.settings.hdmiName(index)
                    if case .success = result {
                        self.selectedHDMIIndex = index
                    }
                    self.handleCommandResult(result, success: name)
                }
            }
        }
    }

    private func connect(showPairingPrompt: Bool) {
        guard !settings.tvIP.isEmpty else {
            status = text(.currentDisconnected)
            showSettings()
            return
        }

        status = showPairingPrompt ? text(.connectPrompt) : "\(text(.startPairing)) \(settings.tvIP)..."
        webOSClient.connect(ip: settings.tvIP, clientKey: settings.clientKey, forcePairing: showPairingPrompt) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let clientKey):
                    self.settings.clientKey = clientKey
                    self.status = "\(self.text(.connected)) \(self.settings.tvName)"
                    self.refreshVolume()
                case .failure(let message):
                    self.selectedHDMIIndex = nil
                    self.status = message
                    self.settingsWindowController.updateOutput(message)
                }
            }
        }
    }

    private func ensureConnectedThen(_ action: @escaping () -> Void) {
        if webOSClient.isConnected {
            action()
            return
        }

        connect(showPairingPrompt: settings.clientKey.isEmpty)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if self.webOSClient.isConnected {
                action()
            }
        }
    }

    private func handleVolumeResult(_ result: LGResult<TVVolumeStatus>) {
        switch result {
        case .success(let volumeStatus):
            settings.volume = volumeStatus.volume
            settings.muted = volumeStatus.muted
            status = "\(text(.syncedVolume)) \(volumeStatus.volume)%"
            syncMenuState()
            settingsWindowController.updateOutput("volume=\(volumeStatus.volume), muted=\(volumeStatus.muted)")
        case .failure(let message):
            status = message
            settingsWindowController.updateOutput(message)
        }
    }

    private func handleCommandResult(_ result: LGResult<Void>, success: String) {
        switch result {
        case .success:
            status = success
        case .failure(let message):
            status = message
            settingsWindowController.updateOutput(message)
        }
    }

    private func adjustVolumeByKeyboard(delta: Int) {
        adjustVolumeFromPanel(delta: delta)
    }

    func adjustVolumeFromPanel(delta: Int) {
        let target = min(max(settings.volume + delta, 0), 100)
        setVolumeFromPanel(target)
    }

    private func applyAppearance() {
        switch settings.appearanceMode {
        case "light":
            NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        default:
            NSApp.appearance = nil
        }
    }

    private func syncMenuState() {
        menuTitle = settings.tvName
        menuVolume = settings.volume
        menuMuted = settings.muted
        menuHDMINames = settings.hdmiNames
        menuLanguageMode = settings.languageMode
    }
}

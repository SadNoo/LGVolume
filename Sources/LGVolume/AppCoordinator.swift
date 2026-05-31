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

    @Published private(set) var status = "未连接" {
        didSet {
            settingsWindowController.updateStatus(status)
        }
    }
    @Published private(set) var menuTitle = "LG TV"
    @Published private(set) var menuVolume = 50
    @Published private(set) var menuMuted = false
    @Published private(set) var menuHDMINames = ["HDMI1", "HDMI2", "HDMI3", "HDMI4"]

    var isMuted: Bool { menuMuted }
    var isConnected: Bool { webOSClient.isConnected }
    var currentVolume: Int { menuVolume }
    var currentTVIP: String { settings.tvIP }
    var launchAtLogin: Bool { settings.launchAtLogin }
    var hdmiShortcuts: [KeyboardShortcut?] { settings.hdmiShortcuts }

    init() {
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

    func discoverTV() {
        status = "正在扫描 LG webOS 电视..."
        DiscoveryService().scan { [weak self] devices in
            DispatchQueue.main.async {
                guard let self else { return }
                self.settingsWindowController.updateDevices(devices)
                if let first = devices.first {
                    self.status = "已发现 \(first.name)（\(first.ip)），请选择“使用”或手动填写 IP。"
                    self.settingsWindowController.refresh()
                } else {
                    self.status = "未发现电视，请确认 Mac 和 LG C2 在同一局域网，或手动填写 IP。"
                }
            }
        }
    }

    func saveManualSettings(ip: String, name: String) {
        settings.tvIP = ip
        settings.tvName = name.isEmpty ? "LG TV" : name
        syncMenuState()
        status = settings.tvIP.isEmpty ? "请填写 LG C2 IP" : "已保存 \(settings.tvIP)"
    }

    func saveHDMINames(_ names: [String]) {
        for (offset, name) in names.enumerated() {
            settings.setHDMIName(name, index: offset + 1)
        }
        syncMenuState()
        status = "已保存 HDMI 名称"
        settingsWindowController.refresh()
    }

    func saveHDMIShortcuts(_ shortcuts: [KeyboardShortcut?]) {
        for (offset, shortcut) in shortcuts.enumerated() {
            settings.setHDMIShortcut(shortcut, index: offset + 1)
        }
        keyboardVolumeMonitor.updateHDMIShortcuts(settings.hdmiShortcuts)
        status = "已保存 HDMI 快捷键"
        settingsWindowController.refresh()
    }

    func pair() {
        settings.clearClientKey()
        connect(showPairingPrompt: true)
    }

    func disconnect() {
        webOSClient.disconnect()
        status = "已断开"
        settingsWindowController.refresh()
    }

    func setAppearanceMode(_ mode: String) {
        settings.appearanceMode = mode
        applyAppearance()
        syncMenuState()
        settingsWindowController.refresh()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        settings.launchAtLogin = enabled
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
                status = "已开启随开机启动"
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
                status = "已关闭随开机启动"
            }
        } catch {
            settings.launchAtLogin = SMAppService.mainApp.status == .enabled
            status = "开机启动设置失败：\(error.localizedDescription)"
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
                        self.handleCommandResult(.success(()), success: "音量已调整到 \(volume)%")
                        self.refreshVolume()
                    case .failure:
                        self.webOSClient.setVolume(volume) { setResult in
                            DispatchQueue.main.async {
                                self.handleCommandResult(setResult, success: "音量已设为 \(volume)%")
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
                    self.handleCommandResult(result, success: self.settings.muted ? "已静音" : "已取消静音")
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
                    self.handleCommandResult(result, success: "已切换到 \(name)")
                }
            }
        }
    }

    private func connect(showPairingPrompt: Bool) {
        guard !settings.tvIP.isEmpty else {
            status = "请先扫描或填写 LG C2 IP"
            showSettings()
            return
        }

        status = showPairingPrompt ? "正在连接，请在电视上允许配对..." : "正在连接 \(settings.tvIP)..."
        webOSClient.connect(ip: settings.tvIP, clientKey: settings.clientKey, forcePairing: showPairingPrompt) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let clientKey):
                    self.settings.clientKey = clientKey
                    self.status = "已连接 \(self.settings.tvName)"
                    self.refreshVolume()
                case .failure(let message):
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
            status = "已同步音量 \(volumeStatus.volume)%"
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
    }
}

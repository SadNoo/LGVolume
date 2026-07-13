import AppKit
import Combine
import ServiceManagement

@MainActor
final class AppCoordinator: ObservableObject {
    private struct PendingConnectionAction {
        let run: () -> Void
        let fail: () -> Void
    }

    private let settings = AppSettings()
    private lazy var webOSClient = WebOSClient(
        languageMode: { [weak self] in
            self?.settings.languageMode ?? "auto"
        },
        connectionStateChanged: { [weak self] connected in
            self?.handleConnectionStateChanged(connected)
        }
    )
    private var settingsWindowController: SettingsWindowController?
    private var discoveredDevices: [DiscoveredTV] = []
    private lazy var keyboardVolumeMonitor = KeyboardVolumeMonitor(
        onVolumeDown: { [weak self] in self?.adjustVolumeByKeyboard(delta: -Self.keyboardVolumeStep) },
        onVolumeUp: { [weak self] in self?.adjustVolumeByKeyboard(delta: Self.keyboardVolumeStep) },
        onMute: { [weak self] in self?.toggleMuteFromPanel() },
        hdmiShortcuts: { [weak self] in self?.settings.hdmiShortcuts ?? [] },
        onHDMIShortcut: { [weak self] index in self?.switchHDMIFromPanel(index: index) },
        onShortcutRegistrationChanged: { [weak self] states in self?.shortcutRegistrationStates = states }
    )
    @Published private(set) var isConnecting = false
    private var pendingConnectionActions: [PendingConnectionAction] = []
    private var pendingVolumeTarget: Int?
    private var volumeCommandInFlight = false
    private var volumeCommandGeneration = 0
    private var activeVolumeCommandGeneration: Int?
    private var muteCommandGeneration = 0
    private var hdmiCommandGeneration = 0

    @Published private(set) var status = "" {
        didSet {
            settingsWindowController?.updateStatus()
        }
    }
    @Published private(set) var menuTitle = "LG TV"
    @Published private(set) var menuVolume = 50
    @Published private(set) var menuMuted = false
    @Published private(set) var connectionState = false
    @Published private(set) var menuHDMINames = ["HDMI1", "HDMI2", "HDMI3", "HDMI4"]
    @Published private(set) var selectedHDMIIndex: Int?
    @Published private(set) var menuLanguageMode = "auto"
    @Published private(set) var shortcutRegistrationStates = [true, true, true, true] {
        didSet { settingsWindowController?.updateShortcutStatus() }
    }

    var isMuted: Bool { menuMuted }
    var isConnected: Bool { connectionState }
    var currentVolume: Int { menuVolume }
    var launchAtLogin: Bool {
        let serviceStatus = SMAppService.mainApp.status
        return serviceStatus == .enabled
    }
    var launchAtLoginRequiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }
    var hdmiShortcuts: [KeyboardShortcut?] { settings.hdmiShortcuts }

    init() {
        status = text(.currentDisconnected)
        syncMenuState()
    }

    func start() {
        settings.launchAtLogin = launchAtLogin
        applyAppearance()
        syncMenuState()
        keyboardVolumeMonitor.start()
        if !settings.tvIP.isEmpty {
            connect(showPairingPrompt: settings.clientKey.isEmpty)
        } else {
            discoverTV()
        }
    }

    func showSettings() {
        keyboardVolumeMonitor.updateHDMIShortcuts(settings.hdmiShortcuts)
        let controller = getSettingsWindowController()
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.refresh()
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
                self.discoveredDevices = devices
                self.settingsWindowController?.updateDevices(devices)
                if !devices.isEmpty {
                    self.status = self.text(.currentDisconnected)
                    self.settingsWindowController?.refresh()
                } else {
                    self.status = self.text(.currentDisconnected)
                }
            }
        }
    }

    func saveSettings(
        ip: String,
        name: String,
        hdmiNames: [String],
        hdmiShortcuts: [KeyboardShortcut?],
        secureConnectionOnly: Bool
    ) {
        let normalizedIP = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        let ipChanged = settings.tvIP != normalizedIP
        let secureConnectionChanged = settings.secureConnectionOnly != secureConnectionOnly
        if ipChanged {
            resetActiveCommands()
            isConnecting = false
            webOSClient.disconnect()
            settings.clearClientKey()
            selectedHDMIIndex = nil
        } else if secureConnectionChanged, webOSClient.isConnected || isConnecting {
            resetActiveCommands()
            isConnecting = false
            webOSClient.disconnect()
            selectedHDMIIndex = nil
        }
        settings.tvIP = normalizedIP
        settings.tvName = name.isEmpty ? "LG TV" : name
        settings.secureConnectionOnly = secureConnectionOnly
        for (offset, name) in hdmiNames.enumerated() {
            settings.setHDMIName(name, index: offset + 1)
        }
        for (offset, shortcut) in hdmiShortcuts.enumerated() {
            settings.setHDMIShortcut(shortcut, index: offset + 1)
        }
        keyboardVolumeMonitor.updateHDMIShortcuts(settings.hdmiShortcuts)
        syncMenuState()
        status = text(.saveSuccess)
        settingsWindowController?.refresh()
    }

    func restoreDefaultHDMIShortcuts() {
        settings.resetHDMIShortcuts()
        keyboardVolumeMonitor.updateHDMIShortcuts(settings.hdmiShortcuts)
        status = text(.saveSuccess)
        settingsWindowController?.refresh()
    }

    func pair() {
        settings.clearClientKey()
        failPendingConnectionActions()
        resetActiveCommands()
        isConnecting = false
        webOSClient.disconnect()
        connect(showPairingPrompt: true)
    }

    func connectFromSettings() {
        connect(showPairingPrompt: settings.clientKey.isEmpty)
    }

    func disconnect() {
        failPendingConnectionActions()
        resetActiveCommands()
        isConnecting = false
        webOSClient.disconnect()
        selectedHDMIIndex = nil
        status = text(.disconnected)
        settingsWindowController?.refresh()
    }

    func setAppearanceMode(_ mode: String) {
        settings.appearanceMode = mode
        applyAppearance()
        syncMenuState()
        settingsWindowController?.refresh()
    }

    func setLanguageMode(_ mode: String) {
        settings.languageMode = mode
        menuLanguageMode = mode
        status = webOSClient.isConnected ? "\(text(.connected)) \(settings.tvName)" : text(.currentDisconnected)
        syncMenuState()
        settingsWindowController?.refresh()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status == .notRegistered {
                    try SMAppService.mainApp.register()
                }
                status = launchAtLoginRequiresApproval ? text(.launchRequiresApproval) : text(.saveSuccess)
            } else {
                if SMAppService.mainApp.status != .notRegistered {
                    try SMAppService.mainApp.unregister()
                }
                status = text(.saveSuccess)
            }
        } catch {
            settings.launchAtLogin = SMAppService.mainApp.status == .enabled
            status = "\(text(.launch)) \(error.localizedDescription)"
        }
        settings.launchAtLogin = launchAtLogin
        settingsWindowController?.refresh()
    }

    func refreshVolume() {
        refreshTVState()
    }

    func refreshTVState() {
        ensureConnectedThen { [weak self] in
            self?.requestVolume()
            self?.requestCurrentHDMI()
        }
    }

    func reconnect() {
        connect(showPairingPrompt: settings.clientKey.isEmpty)
    }

    private func requestVolume() {
        webOSClient.getVolume { [weak self] result in
            DispatchQueue.main.async {
                self?.handleVolumeResult(result)
            }
        }
    }

    func setVolumeFromPanel(_ volume: Int) {
        pendingVolumeTarget = min(max(volume, 0), 100)
        processPendingVolumeTarget()
    }

    func toggleMuteFromPanel() {
        ensureConnectedThen { [weak self] in
            guard let self else { return }
            let previousMuted = self.settings.muted
            let targetMuted = !previousMuted
            self.muteCommandGeneration += 1
            let generation = self.muteCommandGeneration
            self.settings.muted = targetMuted
            self.syncMenuState()
            self.webOSClient.setMuted(targetMuted) { result in
                DispatchQueue.main.async {
                    guard self.muteCommandGeneration == generation else { return }
                    if case .failure = result {
                        self.settings.muted = previousMuted
                        self.syncMenuState()
                    }
                    self.handleCommandResult(result, success: targetMuted ? self.text(.turnMuteOn) : self.text(.turnMuteOff))
                }
            }
        }
    }

    func switchHDMIFromPanel(index: Int) {
        ensureConnectedThen { [weak self] in
            guard let self else { return }
            self.hdmiCommandGeneration += 1
            let generation = self.hdmiCommandGeneration
            self.webOSClient.switchHDMI(index) { result in
                DispatchQueue.main.async {
                    guard self.hdmiCommandGeneration == generation else { return }
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
        if webOSClient.isConnected {
            runPendingConnectionActions()
            return
        }
        guard !isConnecting else {
            return
        }
        guard !settings.tvIP.isEmpty else {
            failPendingConnectionActions()
            status = text(.currentDisconnected)
            showSettings()
            return
        }

        isConnecting = true
        status = showPairingPrompt ? text(.connectPrompt) : "\(text(.startPairing)) \(settings.tvIP)..."
        webOSClient.connect(
            ip: settings.tvIP,
            clientKey: settings.clientKey,
            forcePairing: showPairingPrompt,
            secureConnectionOnly: settings.secureConnectionOnly
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isConnecting = false
                switch result {
                case .success(let clientKey):
                    self.settings.clientKey = clientKey
                    self.status = "\(self.text(.connected)) \(self.settings.tvName)"
                    self.requestCurrentHDMI()
                    if self.pendingConnectionActions.isEmpty {
                        self.requestVolume()
                    } else {
                        self.runPendingConnectionActions()
                    }
                case .failure(let message):
                    self.failPendingConnectionActions()
                    self.selectedHDMIIndex = nil
                    self.status = message
                }
            }
        }
    }

    private func ensureConnectedThen(_ action: @escaping () -> Void, onFailure: @escaping () -> Void = {}) {
        if webOSClient.isConnected {
            action()
            return
        }

        pendingConnectionActions.append(PendingConnectionAction(run: action, fail: onFailure))
        connect(showPairingPrompt: settings.clientKey.isEmpty)
    }

    private func runPendingConnectionActions() {
        let actions = pendingConnectionActions
        pendingConnectionActions.removeAll()
        for action in actions {
            action.run()
        }
    }

    private func failPendingConnectionActions() {
        let actions = pendingConnectionActions
        pendingConnectionActions.removeAll()
        for action in actions {
            action.fail()
        }
    }

    private func processPendingVolumeTarget() {
        guard !volumeCommandInFlight, let target = pendingVolumeTarget else {
            return
        }
        pendingVolumeTarget = nil
        volumeCommandInFlight = true
        volumeCommandGeneration += 1
        let generation = volumeCommandGeneration
        activeVolumeCommandGeneration = generation
        ensureConnectedThen({ [weak self] in
            self?.performVolumeCommand(target: target, generation: generation)
        }, onFailure: { [weak self] in
            self?.pendingVolumeTarget = nil
            self?.volumeCommandInFlight = false
            self?.activeVolumeCommandGeneration = nil
        })
    }

    private func performVolumeCommand(target: Int, generation: Int) {
        guard activeVolumeCommandGeneration == generation else {
            return
        }
        let delta = target - settings.volume
        settings.volume = target
        settings.muted = false
        syncMenuState()

        if abs(delta) > 5 {
            webOSClient.setVolume(target) { [weak self] directResult in
                guard let self else { return }
                guard self.activeVolumeCommandGeneration == generation else { return }
                if case .success = directResult {
                    DispatchQueue.main.async { self.finishVolumeCommand(directResult, target: target, generation: generation) }
                } else {
                    self.webOSClient.changeVolume(delta: delta) { stepResult in
                        DispatchQueue.main.async { self.finishVolumeCommand(stepResult, target: target, generation: generation) }
                    }
                }
            }
        } else {
            webOSClient.changeVolume(delta: delta) { [weak self] stepResult in
                guard let self else { return }
                guard self.activeVolumeCommandGeneration == generation else { return }
                if case .success = stepResult {
                    DispatchQueue.main.async { self.finishVolumeCommand(stepResult, target: target, generation: generation) }
                } else {
                    self.webOSClient.setVolume(target) { directResult in
                        DispatchQueue.main.async { self.finishVolumeCommand(directResult, target: target, generation: generation) }
                    }
                }
            }
        }
    }

    private func finishVolumeCommand(_ result: LGResult<Void>, target: Int, generation: Int) {
        guard activeVolumeCommandGeneration == generation else {
            return
        }
        handleCommandResult(result, success: "\(text(.volume)) \(target)%")
        volumeCommandInFlight = false
        activeVolumeCommandGeneration = nil
        if pendingVolumeTarget != nil {
            processPendingVolumeTarget()
        } else {
            requestVolume()
        }
    }

    private func handleVolumeResult(_ result: LGResult<TVVolumeStatus>) {
        switch result {
        case .success(let volumeStatus):
            settings.volume = volumeStatus.volume
            settings.muted = volumeStatus.muted
            status = "\(text(.syncedVolume)) \(volumeStatus.volume)%"
            syncMenuState()
        case .failure(let message):
            status = message
        }
    }

    private func handleCommandResult(_ result: LGResult<Void>, success: String) {
        switch result {
        case .success:
            status = success
        case .failure(let message):
            status = message
        }
    }

    private func handleConnectionStateChanged(_ connected: Bool) {
        connectionState = connected
        guard !connected, !isConnecting else {
            return
        }
        selectedHDMIIndex = nil
        resetActiveCommands()
        status = text(.currentDisconnected)
    }

    private func adjustVolumeByKeyboard(delta: Int) {
        adjustVolumeFromPanel(delta: delta)
    }

    func adjustVolumeFromPanel(delta: Int) {
        let baseVolume = pendingVolumeTarget ?? settings.volume
        let target = min(max(baseVolume + delta, 0), 100)
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

    private func requestCurrentHDMI() {
        webOSClient.getCurrentHDMI { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                if case .success(let index) = result {
                    self.selectedHDMIIndex = index
                }
            }
        }
    }

    private func resetActiveCommands() {
        pendingVolumeTarget = nil
        volumeCommandInFlight = false
        activeVolumeCommandGeneration = nil
        muteCommandGeneration += 1
        hdmiCommandGeneration += 1
    }

    private func getSettingsWindowController() -> SettingsWindowController {
        if let settingsWindowController {
            return settingsWindowController
        }
        let controller = SettingsWindowController(settings: settings, coordinator: self)
        controller.updateDevices(discoveredDevices)
        settingsWindowController = controller
        return controller
    }

    private static let keyboardVolumeStep = 5
}

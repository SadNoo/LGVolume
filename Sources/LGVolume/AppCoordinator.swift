import AppKit
import Combine
import ServiceManagement

@MainActor
final class AppCoordinator: ObservableObject {
    private struct PendingConnectionAction {
        let run: () -> Void
        let fail: () -> Void
    }

    private let settings: AppSettings
    private let logger: DiagnosticsLogger
    private lazy var webOSClient = WebOSClient(
        languageMode: { [weak self] in
            self?.settings.languageMode ?? "auto"
        },
        connectionStateChanged: { [weak self] connected in
            self?.handleConnectionStateChanged(connected)
        },
        logger: logger
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
    private lazy var volumeExecutor = VolumeCommandExecutor(
        controller: webOSClient,
        logger: logger,
        verificationFailure: { [weak self] in self?.text(.volumeNotApplied) ?? "Volume was not applied." }
    )
    @Published private(set) var isConnecting = false
    private var pendingConnectionActions: [PendingConnectionAction] = []
    private var pendingVolumeTarget: Int?
    private var volumeCommandInFlight = false
    private var volumeCommandGeneration = 0
    private var activeVolumeCommandGeneration: Int?
    private var muteCommandGeneration = 0
    private var hdmiCommandGeneration = 0
    private var externalInputs: [TVExternalInput] = []
    private var foregroundAppID = ""
    private var maintainConnection = false
    private var reconnectAttempt = 0
    private var reconnectWorkItem: DispatchWorkItem?
    private var unsupportedSoundOutputIDs: Set<String> = []

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
    @Published private(set) var currentSoundOutputID = ""
    @Published private(set) var soundOutputAvailable = false
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
    var useTVInputNames: Bool { settings.useTVInputNames }
    var soundOutputOptions: [TVSoundOutputOption] {
        var options = TVSoundOutputOption.common.filter { !unsupportedSoundOutputIDs.contains($0.id) }
        if !currentSoundOutputID.isEmpty, !options.contains(where: { $0.id == currentSoundOutputID }) {
            options.insert(TVSoundOutputOption(id: currentSoundOutputID, fallbackTitle: currentSoundOutputID), at: 0)
        }
        return options
    }
    var currentSoundOutputTitle: String {
        guard let option = soundOutputOptions.first(where: { $0.id == currentSoundOutputID }) else {
            return currentSoundOutputID.isEmpty ? text(.soundOutput) : currentSoundOutputID
        }
        return soundOutputTitle(option)
    }
    var menuPreferredWidth: CGFloat {
        let longest = ([menuTitle] + menuHDMINames + [currentSoundOutputTitle]).map(\.count).max() ?? 8
        return min(240, max(184, CGFloat(164 + max(0, longest - 8) * 4)))
    }

    func soundOutputTitle(_ option: TVSoundOutputOption) -> String {
        option.titleKey.map(text) ?? option.fallbackTitle
    }

    init(settings: AppSettings = AppSettings(), logger: DiagnosticsLogger = .shared) {
        self.settings = settings
        self.logger = logger
        status = text(.currentDisconnected)
        syncMenuState()
    }

    func start() {
        settings.launchAtLogin = launchAtLogin
        applyAppearance()
        syncMenuState()
        keyboardVolumeMonitor.start()
        if !settings.tvIP.isEmpty {
            maintainConnection = true
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

    func openDiagnosticsLog() {
        logger.reveal()
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
        secureConnectionOnly: Bool,
        useTVInputNames: Bool
    ) {
        let normalizedIP = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        let ipChanged = settings.tvIP != normalizedIP
        let secureConnectionChanged = settings.secureConnectionOnly != secureConnectionOnly
        if ipChanged {
            maintainConnection = false
            cancelReconnect()
            resetActiveCommands()
            isConnecting = false
            webOSClient.disconnect()
            settings.clearClientKey()
            selectedHDMIIndex = nil
            externalInputs = []
            foregroundAppID = ""
            currentSoundOutputID = ""
            soundOutputAvailable = false
            unsupportedSoundOutputIDs.removeAll()
        } else if secureConnectionChanged, webOSClient.isConnected || isConnecting {
            cancelReconnect()
            resetActiveCommands()
            isConnecting = false
            webOSClient.disconnect()
            selectedHDMIIndex = nil
        }
        settings.tvIP = normalizedIP
        settings.tvName = name.isEmpty ? "LG TV" : name
        settings.secureConnectionOnly = secureConnectionOnly
        settings.useTVInputNames = useTVInputNames
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
        maintainConnection = true
        cancelReconnect()
        webOSClient.forgetServerTrust(ip: settings.tvIP)
        settings.clearClientKey()
        failPendingConnectionActions()
        resetActiveCommands()
        isConnecting = false
        webOSClient.disconnect()
        connect(showPairingPrompt: true)
    }

    func connectFromSettings() {
        maintainConnection = true
        cancelReconnect()
        connect(showPairingPrompt: settings.clientKey.isEmpty)
    }

    func disconnect() {
        maintainConnection = false
        cancelReconnect()
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
            self?.requestVolume(updateStatus: true)
            self?.requestExternalInputs()
            self?.requestForegroundApp()
            self?.requestSoundOutput()
        }
    }

    func reconnect() {
        maintainConnection = true
        cancelReconnect()
        connect(showPairingPrompt: settings.clientKey.isEmpty)
    }

    private func requestVolume(updateStatus: Bool = false) {
        webOSClient.getVolume { [weak self] result in
            DispatchQueue.main.async {
                self?.handleVolumeResult(result, updateStatus: updateStatus)
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
            self.webOSClient.getMuted { [weak self] muteResult in
                DispatchQueue.main.async {
                    guard let self else { return }
                    let actualMuted: Bool
                    if case .success(let muted) = muteResult {
                        self.settings.muted = muted
                        actualMuted = muted
                    } else {
                        actualMuted = self.settings.muted
                    }
                    self.performMuteCommand(targetMuted: !actualMuted)
                }
            }
        }
    }

    private func performMuteCommand(targetMuted: Bool) {
        let previousMuted = settings.muted
        muteCommandGeneration += 1
        let generation = muteCommandGeneration
        settings.muted = targetMuted
        syncMenuState()
        webOSClient.setMuted(targetMuted) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.muteCommandGeneration == generation else { return }
                if case .failure = result {
                    self.settings.muted = previousMuted
                    self.syncMenuState()
                }
                self.handleCommandResult(result, success: targetMuted ? self.text(.turnMuteOn) : self.text(.turnMuteOff))
            }
        }
    }

    func switchHDMIFromPanel(index: Int) {
        ensureConnectedThen { [weak self] in
            guard let self else { return }
            self.hdmiCommandGeneration += 1
            let generation = self.hdmiCommandGeneration
            let inputID = self.externalInputs.first(where: { $0.hdmiIndex == index })?.id
            self.webOSClient.switchHDMI(index, inputID: inputID) { result in
                DispatchQueue.main.async {
                    guard self.hdmiCommandGeneration == generation else { return }
                    let name = self.menuHDMINames.indices.contains(index - 1)
                        ? self.menuHDMINames[index - 1]
                        : self.settings.hdmiName(index)
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
        logger.log("connection", "connect requested pairing=\(showPairingPrompt)")
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
                    self.cancelReconnect()
                    self.reconnectAttempt = 0
                    let saved = clientKey.isEmpty || self.settings.saveClientKey(clientKey)
                    self.status = saved
                        ? "\(self.text(.connected)) \(self.settings.tvName)"
                        : self.text(.pairingTokenSaveFailed)
                    self.logger.log("connection", "connected tokenSaved=\(saved)")
                    self.startStateSubscriptions()
                    self.requestVolume()
                    self.requestExternalInputs()
                    self.requestForegroundApp()
                    self.requestSoundOutput()
                    if !self.pendingConnectionActions.isEmpty {
                        self.runPendingConnectionActions()
                    }
                case .failure(let message):
                    self.logger.log("connection", "connect failed: \(message)")
                    self.failPendingConnectionActions()
                    self.selectedHDMIIndex = nil
                    self.status = message
                    if message == self.text(.certificateChanged) || message == self.text(.certificateSaveFailed) {
                        self.maintainConnection = false
                    } else if !showPairingPrompt {
                        self.scheduleReconnect()
                    }
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
        maintainConnection = true
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
        let current = settings.volume
        settings.volume = target
        settings.muted = false
        syncMenuState()

        volumeExecutor.execute(target: target, current: current) { [weak self] result in
            self?.finishVolumeCommand(result, target: target, generation: generation)
        }
    }

    private func finishVolumeCommand(_ result: LGResult<TVVolumeStatus>, target: Int, generation: Int) {
        guard activeVolumeCommandGeneration == generation else {
            return
        }
        switch result {
        case .success(let volumeStatus):
            settings.volume = volumeStatus.volume
            if let muted = volumeStatus.muted {
                settings.muted = muted
            }
            status = "\(text(.volume)) \(volumeStatus.volume)%"
        case .failure(let message):
            status = message
            logger.log("volume", "command failed after verification: \(message)")
        }
        syncMenuState()
        volumeCommandInFlight = false
        activeVolumeCommandGeneration = nil
        if pendingVolumeTarget != nil {
            processPendingVolumeTarget()
        } else {
            requestVolume(updateStatus: false)
        }
    }

    private func handleVolumeResult(_ result: LGResult<TVVolumeStatus>, updateStatus: Bool) {
        switch result {
        case .success(let volumeStatus):
            settings.volume = volumeStatus.volume
            if let muted = volumeStatus.muted {
                settings.muted = muted
            }
            if updateStatus {
                status = "\(text(.syncedVolume)) \(volumeStatus.volume)%"
            }
            syncMenuState()
        case .failure(let message):
            if updateStatus {
                status = message
            }
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
        if connected {
            cancelReconnect()
            reconnectAttempt = 0
            return
        }
        guard !connected, !isConnecting else {
            return
        }
        selectedHDMIIndex = nil
        currentSoundOutputID = ""
        soundOutputAvailable = false
        resetActiveCommands()
        status = text(.currentDisconnected)
        scheduleReconnect()
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
        if settings.useTVInputNames {
            menuHDMINames = (1...4).map { index in
                externalInputs.first(where: { $0.hdmiIndex == index })?.label ?? settings.hdmiName(index)
            }
        } else {
            menuHDMINames = settings.hdmiNames
        }
        menuLanguageMode = settings.languageMode
    }

    func detectedHDMIName(_ index: Int) -> String? {
        externalInputs.first(where: { $0.hdmiIndex == index })?.label
    }

    func changeSoundOutput(_ outputID: String) {
        ensureConnectedThen { [weak self] in
            guard let self else { return }
            self.webOSClient.changeSoundOutput(outputID) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        self.currentSoundOutputID = outputID
                        self.soundOutputAvailable = true
                        self.unsupportedSoundOutputIDs.remove(outputID)
                    case .failure(let message):
                        if self.isUnsupportedSoundOutputError(message) {
                            self.unsupportedSoundOutputIDs.insert(outputID)
                        }
                    }
                    let title = TVSoundOutputOption.common.first(where: { $0.id == outputID })
                        .map(self.soundOutputTitle) ?? outputID
                    self.handleCommandResult(result, success: "\(self.text(.soundOutput))：\(title)")
                }
            }
        }
    }

    private func startStateSubscriptions() {
        webOSClient.subscribeVolume { [weak self] result in
            self?.handleVolumeResult(result, updateStatus: false)
        }
        webOSClient.subscribeMuted { [weak self] result in
            self?.handleMuteResult(result)
        }
        webOSClient.subscribeExternalInputs { [weak self] result in
            self?.handleExternalInputsResult(result)
        }
        webOSClient.subscribeForegroundAppID { [weak self] result in
            self?.handleForegroundAppResult(result)
        }
        webOSClient.subscribeSoundOutput { [weak self] result in
            self?.handleSoundOutputResult(result)
        }
    }

    private func requestExternalInputs() {
        webOSClient.getExternalInputs { [weak self] result in
            self?.handleExternalInputsResult(result)
        }
    }

    private func handleExternalInputsResult(_ result: LGResult<[TVExternalInput]>) {
        guard case .success(let inputs) = result else { return }
        externalInputs = inputs.filter { $0.hdmiIndex != nil }
        syncMenuState()
        updateSelectedHDMI()
        settingsWindowController?.refresh()
    }

    private func requestForegroundApp() {
        webOSClient.getForegroundAppID { [weak self] result in
            self?.handleForegroundAppResult(result)
        }
    }

    private func handleForegroundAppResult(_ result: LGResult<String>) {
        guard case .success(let appID) = result else { return }
        foregroundAppID = appID
        updateSelectedHDMI()
    }

    private func updateSelectedHDMI() {
        let lower = foregroundAppID.lowercased()
        selectedHDMIIndex = externalInputs.first { input in
            !input.appID.isEmpty && lower == input.appID.lowercased()
        }?.hdmiIndex ?? WebOSClient.hdmiIndex(in: foregroundAppID)
    }

    private func requestSoundOutput() {
        webOSClient.getSoundOutput { [weak self] result in
            self?.handleSoundOutputResult(result)
        }
    }

    private func handleSoundOutputResult(_ result: LGResult<String>) {
        switch result {
        case .success(let outputID):
            soundOutputAvailable = true
            currentSoundOutputID = outputID
            unsupportedSoundOutputIDs.remove(outputID)
        case .failure:
            if currentSoundOutputID.isEmpty {
                soundOutputAvailable = false
            }
        }
    }

    private func isUnsupportedSoundOutputError(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("1013")
            || lower.contains("invalid")
            || lower.contains("unsupported")
            || lower.contains("not exist")
    }

    private func handleMuteResult(_ result: LGResult<Bool>) {
        guard case .success(let muted) = result else { return }
        settings.muted = muted
        syncMenuState()
    }

    private func scheduleReconnect() {
        guard maintainConnection,
              !settings.clientKey.isEmpty,
              !settings.tvIP.isEmpty,
              !isConnecting,
              reconnectWorkItem == nil else { return }

        let delay = min(pow(2.0, Double(reconnectAttempt)), 30)
        reconnectAttempt = min(reconnectAttempt + 1, 5)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.reconnectWorkItem = nil
            self.connect(showPairingPrompt: false)
        }
        reconnectWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func cancelReconnect() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
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

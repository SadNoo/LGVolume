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
    private lazy var systemSleepMonitor = SystemSleepMonitor(
        onWillSleep: { [weak self] done in
            guard let self else { return done() }
            self.handleSystemWillSleep(done: done)
        },
        onDidWake: { [weak self] in
            self?.handleSystemDidWake()
        }
    )
    private var screenParametersObserver: NSObjectProtocol?
    private var displaySleepObservers: [NSObjectProtocol] = []
    /// "Mac mini went to sleep" on a Mac whose system sleep is disabled: the picture to the TV
    /// stopped and stayed stopped (input-switch blips are filtered out by the gate).
    private lazy var displayOffGate = DisplayOffStandbyGate(
        log: { [weak self] message in self?.logger.log("power", message) },
        onElapsed: { [weak self] in
            self?.evaluateTVStandby(trigger: "monitor: picture off 60 s") {}
        }
    )
    private var screenLockObservers: [NSObjectProtocol] = []
    private lazy var audioOutputMonitor = AudioOutputMonitor { [weak self] _ in
        self?.applyVolumeKeyTakeover()
    }
    /// TV mode: the check scheduled after a lock; cancelled when the Mac is unlocked first.
    private var lockStandbyWorkItem: DispatchWorkItem?
    /// When the TV last switched to the Mac's input (nil while it shows another input).
    private var macInputSince: Date?
    @Published private(set) var isConnecting = false
    private var pendingConnectionActions: [PendingConnectionAction] = []
    private var pendingVolumeWork: VolumeWork?
    private var volumeCommandInFlight = false
    private var volumeCommandGeneration = 0
    private var activeVolumeCommandGeneration: Int?
    private var muteCommandGeneration = 0
    private var muteTargetInFlight: Bool?
    private var muteReadInFlight = false
    private var queuedMuteToggles = 0
    private var hdmiCommandGeneration = 0
    private var soundOutputCommandGeneration = 0
    private var pendingSoundOutputID: String?
    private var soundOutputConfirmationWorkItem: DispatchWorkItem?
    private var hdmiSwitchCooldownWorkItem: DispatchWorkItem?
    private var externalInputs: [TVExternalInput] = []
    private var foregroundAppID = ""
    private var maintainConnection = false
    private var reconnectAttempt = 0
    private var reconnectWorkItem: DispatchWorkItem?
    private var unsupportedSoundOutputIDs: Set<String> = []

    @Published private(set) var status = "" {
        didSet {
            statusIsError = false
            settingsWindowController?.updateStatus()
        }
    }
    /// True while `status` describes a failure the user should see and act on.
    @Published private(set) var statusIsError = false {
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
    @Published private(set) var isSwitchingHDMI = false
    @Published private(set) var currentSoundOutputID = ""
    @Published private(set) var soundOutputAvailable = false
    @Published private(set) var menuLanguageMode = "auto"
    @Published private(set) var menuStyle: MenuPanelStyle = .defaultStyle
    /// What macOS reports the LG device to be; nil until read or when it cannot tell.
    @Published private(set) var detectedDeviceKind: DeviceKind?
    /// The HDMI input read from the TV's EDID right now; nil while no LG TV EDID is visible.
    @Published private(set) var detectedMacHDMIPort: Int?
    @Published private(set) var shortcutRegistrationStates = Array(repeating: true, count: 7) {
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
    var sleepTVWithMac: Bool { settings.sleepTVWithMac }
    var macHDMIPortOverride: Int { settings.macHDMIPortOverride }
    var sleepTVNeedsRepair: Bool { settings.sleepTVWithMac && !settings.pairingGrantsPower }
    /// Manual choice first, then the live EDID reading, then the last EDID reading.
    var effectiveMacHDMIPort: Int? {
        let override = settings.macHDMIPortOverride
        if (1...4).contains(override) {
            return override
        }
        return detectedMacHDMIPort ?? settings.lastDetectedMacHDMIPort
    }
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
    /// Output name for rows that already carry a "Sound Output" label; "—" when unknown.
    var soundOutputValueText: String {
        currentSoundOutputID.isEmpty ? "—" : currentSoundOutputTitle
    }
        var menuPreferredWidth: CGFloat {
        menuStyle.width
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
        restoreLaunchAtLoginIfNeeded()
        applyAppearance()
        syncMenuState()
        audioOutputMonitor.start()
        applyVolumeKeyTakeover()
        keyboardVolumeMonitor.start()
        refreshMacHDMIPort()
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshMacHDMIPort()
                self?.refreshDeviceKind()
            }
        }
        systemSleepMonitor.start()
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        displaySleepObservers = [
            workspaceCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleDisplaysDidSleep() }
            },
            workspaceCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.displayOffGate.displaysDidWake() }
            }
        ]
        let distributedCenter = DistributedNotificationCenter.default()
        screenLockObservers = [
            distributedCenter.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleScreenLocked() }
            },
            distributedCenter.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleScreenUnlocked() }
            }
        ]
        refreshDeviceKind()
        if !settings.tvIP.isEmpty {
            maintainConnection = true
            connect(showPairingPrompt: settings.clientKey.isEmpty)
        } else {
            discoverTV()
        }
    }

    /// Set by the status item controller; closes the menu bar panel.
    var closeMenuPanel: (() -> Void)?

    func showSettings() {
        closeMenuPanel?()
        keyboardVolumeMonitor.updateHDMIShortcuts(settings.hdmiShortcuts)
        let controller = getSettingsWindowController()
        NSApp.activate()
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        controller.refresh()
    }

    var isSettingsWindowVisible: Bool {
        settingsWindowController?.window?.isVisible == true
    }

    /// Keeps the Settings window in front of other apps while the menu panel is used.
    func bringSettingsWindowForward() {
        guard let window = settingsWindowController?.window, window.isVisible else { return }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func quit() {
        closeMenuPanel?()
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
            failPendingConnectionActions()
            resetActiveCommands()
            isConnecting = false
            webOSClient.disconnect()
            settings.clearClientKey()
            selectedHDMIIndex = nil
            externalInputs = []
            foregroundAppID = ""
            macInputSince = nil
            currentSoundOutputID = ""
            soundOutputAvailable = false
            unsupportedSoundOutputIDs.removeAll()
        } else if secureConnectionChanged {
            dropConnectionForTransportChange()
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

    /// Applies only the transport preference, without committing other unsaved settings fields.
    func setSecureConnectionOnly(_ enabled: Bool) {
        guard settings.secureConnectionOnly != enabled else { return }
        dropConnectionForTransportChange()
        settings.secureConnectionOnly = enabled
        status = text(.saveSuccess)
        settingsWindowController?.refresh()
    }

    private func dropConnectionForTransportChange() {
        guard webOSClient.isConnected || isConnecting else { return }
        cancelReconnect()
        failPendingConnectionActions()
        resetActiveCommands()
        isConnecting = false
        webOSClient.disconnect()
        selectedHDMIIndex = nil
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

    /// Set when turning on launch at login did not take effect; Settings shows it with a way
    /// to open the Login Items pane.
    private(set) var launchAtLoginProblem: String?

    func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        logger.log("launch", "set enabled=\(enabled) status=\(Self.describe(service.status))")
        settings.launchAtLogin = enabled
        launchAtLoginProblem = nil
        var failure: Error?
        do {
            if enabled {
                if service.status != .enabled {
                    try service.register()
                }
            } else if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
        } catch {
            logger.log("launch", "\(enabled ? "register" : "unregister") failed: \(error)")
            failure = error
            if enabled {
                // A record left by an earlier build can block registration; clear it and retry.
                try? service.unregister()
                do {
                    try service.register()
                    failure = nil
                } catch {
                    logger.log("launch", "retry register failed: \(error)")
                    failure = error
                }
            }
        }
        logger.log("launch", "status after=\(Self.describe(service.status))")

        if let failure {
            launchAtLoginProblem = "\(text(.launch)) \(failure.localizedDescription)"
            showError(launchAtLoginProblem ?? "")
        } else if enabled && service.status == .requiresApproval {
            launchAtLoginProblem = text(.launchRequiresApproval)
            showError(text(.launchRequiresApproval))
        } else {
            status = text(.saveSuccess)
        }
        settingsWindowController?.refresh()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private static func describe(_ status: SMAppService.Status) -> String {
        switch status {
        case .notRegistered: return "notRegistered"
        case .enabled: return "enabled"
        case .requiresApproval: return "requiresApproval"
        case .notFound: return "notFound"
        @unknown default: return "unknown(\(status.rawValue))"
        }
    }

    /// An ad-hoc signed rebuild looks like a new app to Background Task Management, so the
    /// registration disappears after every update. Keep the user's choice and register again;
    /// `.requiresApproval` (switched off in System Settings) is left for the user to decide.
    private func restoreLaunchAtLoginIfNeeded() {
        let status = SMAppService.mainApp.status
        guard settings.launchAtLogin, status != .enabled, status != .requiresApproval else { return }
        do {
            try SMAppService.mainApp.register()
            logger.log("launch", "re-registered launch at login (was \(Self.describe(status)))")
        } catch {
            logger.log("launch", "re-register failed (was \(Self.describe(status))): \(error)")
        }
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
        pendingVolumeWork = .absolute(min(max(volume, 0), 100))
        processPendingVolumeWork()
    }

    func toggleMuteFromPanel() {
        ensureConnectedThen { [weak self] in
            self?.requestMuteToggle()
        }
    }

    /// Each toggle flips the most recent requested state. While the first read of the TV state is
    /// in flight, further presses are counted so two quick presses cancel out instead of both
    /// muting.
    private func requestMuteToggle() {
        if let targetInFlight = muteTargetInFlight {
            performMuteCommand(targetMuted: !targetInFlight)
            return
        }
        queuedMuteToggles += 1
        guard !muteReadInFlight else { return }
        muteReadInFlight = true
        let generation = muteCommandGeneration
        webOSClient.getMuted { [weak self] muteResult in
            DispatchQueue.main.async {
                guard let self, self.muteCommandGeneration == generation else { return }
                self.muteReadInFlight = false
                let actualMuted: Bool
                if case .success(let muted) = muteResult {
                    self.settings.muted = muted
                    actualMuted = muted
                } else {
                    actualMuted = self.settings.muted
                }
                let toggles = self.queuedMuteToggles
                self.queuedMuteToggles = 0
                if toggles % 2 == 1 {
                    self.performMuteCommand(targetMuted: !actualMuted)
                } else {
                    self.syncMenuState()
                }
            }
        }
    }

    private func performMuteCommand(targetMuted: Bool) {
        let previousMuted = settings.muted
        muteCommandGeneration += 1
        let generation = muteCommandGeneration
        muteTargetInFlight = targetMuted
        settings.muted = targetMuted
        syncMenuState()
        webOSClient.setMuted(targetMuted) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.muteCommandGeneration == generation else { return }
                self.muteTargetInFlight = nil
                if case .failure = result {
                    self.settings.muted = previousMuted
                    self.syncMenuState()
                }
                self.handleCommandResult(result, success: targetMuted ? self.text(.turnMuteOn) : self.text(.turnMuteOff))
            }
        }
    }

    func switchHDMIFromPanel(index: Int) {
        guard (1...4).contains(index) else { return }
        guard !isSwitchingHDMI else {
            logger.log("hdmi", "ignored overlapping switch index=\(index)")
            return
        }

        isSwitchingHDMI = true
        ensureConnectedThen({ [weak self] in
            guard let self else { return }
            self.hdmiCommandGeneration += 1
            let generation = self.hdmiCommandGeneration
            let inputID = self.externalInputs.first(where: { $0.hdmiIndex == index })?.id
            self.logger.log("hdmi", "switch requested index=\(index)")
            self.webOSClient.switchHDMI(index, inputID: inputID) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self, self.hdmiCommandGeneration == generation else { return }
                    let name = self.menuHDMINames.indices.contains(index - 1)
                        ? self.menuHDMINames[index - 1]
                        : self.settings.hdmiName(index)
                    if case .success = result {
                        self.selectedHDMIIndex = index
                    }
                    self.handleCommandResult(result, success: name)
                    self.finishHDMISwitch(generation: generation)
                }
            }
        }, onFailure: { [weak self] in
            self?.isSwitchingHDMI = false
        })
    }

    private func finishHDMISwitch(generation: Int) {
        guard hdmiCommandGeneration == generation else { return }
        hdmiSwitchCooldownWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.hdmiCommandGeneration == generation else { return }
            self.hdmiSwitchCooldownWorkItem = nil
            self.isSwitchingHDMI = false
            if self.webOSClient.isConnected {
                self.requestForegroundApp()
            }
        }
        hdmiSwitchCooldownWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: workItem)
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
            secureConnectionOnly: settings.secureConnectionOnly,
            // New pairings always ask for power control; existing pairings keep the permission
            // list they were approved with so reconnecting never triggers a new TV prompt.
            includePowerControl: showPairingPrompt || settings.pairingGrantsPower
        ) { [weak self] result in
            guard let self else { return }
            self.isConnecting = false
            switch result {
            case .success(let clientKey):
                let saved = clientKey.isEmpty || self.settings.saveClientKey(clientKey)
                guard self.webOSClient.isConnected else {
                    self.logger.log("connection", "registration completed after transport closed tokenSaved=\(saved)")
                    if !saved {
                        self.showError(self.text(.pairingTokenSaveFailed))
                        self.failPendingConnectionActions()
                        return
                    }
                    self.handleConnectionStateChanged(false)
                    return
                }
                self.cancelReconnect()
                self.reconnectAttempt = 0
                if saved && showPairingPrompt && !clientKey.isEmpty {
                    self.settings.pairingGrantsPower = true
                }
                if saved {
                    self.status = "\(self.text(.connected)) \(self.settings.tvName)"
                } else {
                    self.showError(self.text(.pairingTokenSaveFailed))
                }
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
                self.showError(message)
                if message == self.text(.certificateChanged) || message == self.text(.certificateSaveFailed) {
                    self.maintainConnection = false
                } else if !showPairingPrompt {
                    self.scheduleReconnect()
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

    private func processPendingVolumeWork() {
        guard !volumeCommandInFlight, let work = pendingVolumeWork else {
            return
        }
        let (batch, remainder) = VolumeWork.takeBatch(from: work)
        pendingVolumeWork = remainder
        volumeCommandInFlight = true
        volumeCommandGeneration += 1
        let generation = volumeCommandGeneration
        activeVolumeCommandGeneration = generation
        ensureConnectedThen({ [weak self] in
            self?.performVolumeCommand(batch, generation: generation)
        }, onFailure: { [weak self] in
            guard let self, self.activeVolumeCommandGeneration == generation else { return }
            self.pendingVolumeWork = nil
            self.volumeCommandInFlight = false
            self.activeVolumeCommandGeneration = nil
        })
    }

    private func performVolumeCommand(_ work: VolumeWork, generation: Int) {
        guard activeVolumeCommandGeneration == generation else {
            return
        }
        let current = settings.volume
        let completion: (LGResult<TVVolumeStatus>) -> Void = { [weak self] result in
            self?.finishVolumeCommand(result, work: work, generation: generation)
        }

        switch work {
        case .absolute(let target):
            volumeExecutor.execute(target: target, current: current, completion: completion)
        case .steps(let delta):
            volumeExecutor.executeSteps(delta, current: current, completion: completion)
        }
    }

    private func finishVolumeCommand(_ result: LGResult<TVVolumeStatus>, work: VolumeWork, generation: Int) {
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
            showError(message)
            logger.log("volume", "command failed after verification: \(message)")
            if case .steps = work, case .steps = pendingVolumeWork {
                // Do not keep firing native steps at a TV that just rejected one.
                pendingVolumeWork = nil
            }
        }
        syncMenuState()
        volumeCommandInFlight = false
        activeVolumeCommandGeneration = nil
        if pendingVolumeWork != nil {
            processPendingVolumeWork()
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
                showError(message)
            }
        }
    }

    private func handleCommandResult(_ result: LGResult<Void>, success: String) {
        switch result {
        case .success:
            status = success
        case .failure(let message):
            showError(message)
        }
    }

    private func showError(_ message: String) {
        status = message
        statusIsError = true
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
        // Forget the TV's input: after reconnecting, the time on the Mac input starts again.
        foregroundAppID = ""
        macInputSince = nil
        resetActiveCommands()
        status = text(.currentDisconnected)
        scheduleReconnect()
    }

    private func adjustVolumeByKeyboard(delta: Int) {
        adjustVolumeFromPanel(delta: delta)
    }

    /// Queues native TV volume steps; consecutive presses stay native steps rather than being
    /// folded into an absolute target.
    func adjustVolumeFromPanel(delta: Int) {
        pendingVolumeWork = VolumeWork.adding(steps: delta, to: pendingVolumeWork)
        processPendingVolumeWork()
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
        menuStyle = settings.menuStyle
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

    func setMenuStyle(_ style: MenuPanelStyle) {
        settings.menuStyle = style
        syncMenuState()
        settingsWindowController?.refresh()
    }

    /// Name of the input the TV is showing, when it is one of the four HDMI inputs.
    var selectedInputName: String? {
        selectedHDMIIndex.flatMap { menuHDMINames.indices.contains($0 - 1) ? menuHDMINames[$0 - 1] : nil }
    }

    func inputSymbol(_ index: Int) -> String {
        let input = externalInputs.first { $0.hdmiIndex == index }
        let label = menuHDMINames.indices.contains(index - 1) ? menuHDMINames[index - 1] : ""
        return InputSymbol.name(
            isMac: effectiveMacHDMIPort == index,
            label: "\(label) \(input?.label ?? "")",
            tvIconName: input?.iconName
        )
    }

    /// False only when the TV positively reports nothing plugged into that input.
    func isInputConnected(_ index: Int) -> Bool {
        externalInputs.first { $0.hdmiIndex == index }?.connected ?? true
    }

    func shortcutDisplay(_ index: Int) -> String? {
        let shortcuts = settings.hdmiShortcuts
        return shortcuts.indices.contains(index - 1) ? shortcuts[index - 1]?.display : nil
    }

    var deviceKindMode: DeviceKindMode { settings.deviceKindMode }
    var standbyAction: StandbyAction { settings.standbyAction }
    var volumeKeysOnlyForTVAudio: Bool { settings.volumeKeysOnlyForTVAudio }
    var macAudioOutputName: String { audioOutputMonitor.outputName }
    var macAudioGoesToTV: Bool { audioOutputMonitor.isTVOutput }

    func setStandbyAction(_ action: StandbyAction) {
        settings.standbyAction = action
        logger.log("power", "standby action=\(action.rawValue)")
        settingsWindowController?.refresh()
    }

    func setVolumeKeysOnlyForTVAudio(_ enabled: Bool) {
        settings.volumeKeysOnlyForTVAudio = enabled
        applyVolumeKeyTakeover()
        settingsWindowController?.refresh()
    }

    /// F10-F12 and the media volume keys go to the TV only while the Mac's sound goes to it,
    /// unless the user chose to always control the TV.
    private func applyVolumeKeyTakeover() {
        let enabled = !settings.volumeKeysOnlyForTVAudio || audioOutputMonitor.isTVOutput
        keyboardVolumeMonitor.setVolumeKeysEnabled(enabled)
        logger.log("keys", "volume keys control TV=\(enabled) output=\(audioOutputMonitor.isTVOutput ? "TV" : "other")")
        settingsWindowController?.updateShortcutStatus()
    }

    /// Manual choice first; otherwise what macOS reports; an unknown device is treated as a TV
    /// because TV mode never acts on picture interruptions.
    var effectiveDeviceKind: DeviceKind {
        switch settings.deviceKindMode {
        case .tv: return .tv
        case .monitor: return .monitor
        case .auto: return detectedDeviceKind ?? .tv
        }
    }

    func setDeviceKindMode(_ mode: DeviceKindMode) {
        settings.deviceKindMode = mode
        displayOffGate.reset()
        logger.log("power", "device kind mode=\(mode.rawValue) effective=\(effectiveDeviceKind.rawValue)")
        objectWillChange.send()
        settingsWindowController?.refresh()
    }

    private func refreshDeviceKind() {
        DeviceKindDetector.detect { [weak self] kind in
            Task { @MainActor in
                guard let self, kind != self.detectedDeviceKind else { return }
                self.detectedDeviceKind = kind
                self.logger.log("power", "device kind detected=\(kind?.rawValue ?? "unknown")")
                self.settingsWindowController?.refresh()
            }
        }
    }

    private func updateMacInputSince() {
        let port = TVSleepPolicy.hdmiPort(forForegroundAppID: foregroundAppID, inputs: externalInputs)
        if let port, port == effectiveMacHDMIPort {
            if macInputSince == nil {
                macInputSince = Date()
            }
        } else {
            macInputSince = nil
        }
    }

    /// TV mode trigger: the user locked the Mac (for example with the Touch ID key).
    /// Waits first: when the Mac is still the TV's CEC source, CEC turns the TV off within that
    /// time and the TV disconnects, so LGVolume only acts when CEC did not.
    private func handleScreenLocked() {
        guard effectiveDeviceKind == .tv else {
            logger.log("power", "screen lock: monitor mode, lock is not a trigger")
            return
        }
        lockStandbyWorkItem?.cancel()
        logger.log("power", "tv: screen locked, checking the TV in \(Int(Self.lockStandbyDelay)) s")
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.lockStandbyWorkItem = nil
                self.evaluateTVStandby(trigger: "tv: screen lock", requireStableMacInput: true) {}
            }
        }
        lockStandbyWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.lockStandbyDelay, execute: workItem)
    }

    private func handleScreenUnlocked() {
        guard let workItem = lockStandbyWorkItem else { return }
        workItem.cancel()
        lockStandbyWorkItem = nil
        logger.log("power", "tv: unlocked before the check, TV left on")
    }

    /// Monitor mode trigger: start the 60 s wait. In TV mode the picture going off is ignored,
    /// because switching the TV's input causes exactly that.
    private func handleDisplaysDidSleep() {
        guard effectiveDeviceKind == .monitor else { return }
        displayOffGate.displaysDidSleep()
    }

    func setSleepTVWithMac(_ enabled: Bool) {
        settings.sleepTVWithMac = enabled
        objectWillChange.send()
        logger.log("power", "sleep TV with Mac enabled=\(enabled) macPort=\(effectiveMacHDMIPort.map(String.init) ?? "none")")
        settingsWindowController?.refresh()
    }

    func setMacHDMIPortOverride(_ port: Int) {
        settings.macHDMIPortOverride = port
        objectWillChange.send()
        settingsWindowController?.refresh()
    }

    private func refreshMacHDMIPort() {
        let port = MacHDMIPortDetector.detectPort()
        if let port {
            settings.lastDetectedMacHDMIPort = port
        }
        guard port != detectedMacHDMIPort else { return }
        detectedMacHDMIPort = port
        logger.log("power", "mac HDMI port detected=\(port.map(String.init) ?? "none")")
        settingsWindowController?.refresh()
    }

    /// Called while macOS waits for this app before sleeping. `done` must be called once; the
    /// monitor also calls it after a timeout. The TV is only turned off when a fresh read shows
    /// it is displaying the Mac's input; every other case leaves the TV untouched.
    private func handleSystemWillSleep(done: @escaping @MainActor () -> Void) {
        displayOffGate.reset()
        evaluateTVStandby(trigger: "system sleep", done: done)
    }

    /// Powers off the TV only when a fresh read shows it displaying the Mac's input.
    /// `done` is called exactly once when the decision (and any command) has finished.
    private func evaluateTVStandby(
        trigger: String,
        requireStableMacInput: Bool = false,
        done: @escaping @MainActor () -> Void
    ) {
        guard settings.sleepTVWithMac else {
            logger.log("power", "\(trigger): turn off TV with Mac is off")
            return done()
        }
        guard webOSClient.isConnected else {
            logger.log("power", "\(trigger): TV not connected, leaving it alone")
            return done()
        }
        if requireStableMacInput && !TVSleepPolicy.macInputIsStable(since: macInputSince) {
            let held = macInputSince.map { "\(Int(Date().timeIntervalSince($0))) s" } ?? "not on the Mac input"
            logger.log("power", "\(trigger): leaving TV on (Mac input held \(held), needs \(Int(TVSleepPolicy.requiredStableMacInput)) s)")
            return done()
        }
        let macPort = effectiveMacHDMIPort
        let requestedAt = Date()
        webOSClient.getForegroundAppID { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return done() }
                let appID: String?
                if Date().timeIntervalSince(requestedAt) > Self.sleepReadFreshness {
                    // Too slow to trust: the input may have changed meanwhile.
                    appID = nil
                } else if case .success(let value) = result {
                    appID = value
                } else {
                    appID = nil
                }
                let decision = TVSleepPolicy.decide(
                    enabled: self.settings.sleepTVWithMac,
                    macPort: macPort,
                    foregroundAppID: appID,
                    inputs: self.externalInputs
                )
                guard decision == .turnOff else {
                    if case .skip(let reason) = decision {
                        self.logger.log("power", "\(trigger): leaving TV on (\(reason))")
                    }
                    return done()
                }
                self.performStandbyAction(trigger: trigger, done: done)
            }
        }
    }

    /// Powers the TV off, or turns only its screen off when chosen. If the TV refuses the
    /// screen-off command, it is powered off instead so it never stays on by mistake.
    private func performStandbyAction(trigger: String, done: @escaping @MainActor () -> Void) {
        let powerOff: () -> Void = { [weak self] in
            guard let self else { return done() }
            self.logger.log("power", "\(trigger): TV shows the Mac input, turning it off")
            self.webOSClient.turnOff { [weak self] result in
                DispatchQueue.main.async {
                    if case .failure(let message) = result {
                        self?.logger.log("power", "\(trigger): turn off failed: \(message)")
                        if self?.isPermissionError(message) == true {
                            self?.settings.pairingGrantsPower = false
                        }
                    }
                    done()
                }
            }
        }
        guard settings.standbyAction == .screenOff else {
            return powerOff()
        }
        logger.log("power", "\(trigger): TV shows the Mac input, turning its screen off")
        webOSClient.turnOffScreen { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return done() }
                if case .failure(let message) = result {
                    self.logger.log("power", "\(trigger): screen off refused (\(message)), powering off instead")
                    powerOff()
                } else {
                    done()
                }
            }
        }
    }

    /// Settings "Test" button: runs the same checks as a real trigger right now and describes
    /// the outcome, without sending any power command to the TV.
    func simulateTVStandby(completion: @escaping (String) -> Void) {
        let kind = effectiveDeviceKind
        let action = settings.standbyAction == .screenOff ? text(.testActionScreenOff) : text(.testActionPowerOff)
        logger.log("power", "test: simulating (\(kind.rawValue), \(settings.standbyAction.rawValue)), nothing is sent")
        guard settings.sleepTVWithMac else { return completion(text(.testNotOn)) }
        guard webOSClient.isConnected else { return completion(text(.testNotConnected)) }
        guard let macPort = effectiveMacHDMIPort else { return completion(text(.testNoMacPort)) }
        webOSClient.getForegroundAppID { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                guard case .success(let appID) = result else {
                    return completion(self.text(.testReadFailed))
                }
                let port = TVSleepPolicy.hdmiPort(forForegroundAppID: appID, inputs: self.externalInputs)
                guard port == macPort else {
                    let shown = port.flatMap { index in
                        self.menuHDMINames.indices.contains(index - 1) ? "HDMI\(index)（\(self.menuHDMINames[index - 1])）" : "HDMI\(index)"
                    } ?? (appID.isEmpty ? "?" : appID)
                    return completion(String(format: self.text(.testOtherInput), shown, macPort))
                }
                if kind == .tv, !TVSleepPolicy.macInputIsStable(since: self.macInputSince) {
                    let held = self.macInputSince.map { Int(Date().timeIntervalSince($0)) } ?? 0
                    return completion(String(format: self.text(.testNotStable), held))
                }
                completion(String(format: self.text(kind == .tv ? .testWouldTurnOffTV : .testWouldTurnOffMonitor), action))
            }
        }
    }

    private func handleSystemDidWake() {
        refreshMacHDMIPort()
        guard maintainConnection, !settings.tvIP.isEmpty, !settings.clientKey.isEmpty else { return }
        // The socket may look open after sleep while the TV has long dropped it; start fresh.
        logger.log("power", "wake: reconnecting")
        cancelReconnect()
        reconnectAttempt = 0
        if webOSClient.isConnected {
            webOSClient.disconnect()
        } else if !isConnecting {
            scheduleReconnect()
        }
    }

    private func isPermissionError(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("401") || lower.contains("permission") || lower.contains("not allowed")
    }

    func detectedHDMIName(_ index: Int) -> String? {
        externalInputs.first(where: { $0.hdmiIndex == index })?.label
    }

    func changeSoundOutput(_ outputID: String) {
        ensureConnectedThen { [weak self] in
            guard let self else { return }
            self.soundOutputCommandGeneration += 1
            let generation = self.soundOutputCommandGeneration
            self.pendingSoundOutputID = outputID
            self.webOSClient.changeSoundOutput(outputID) { result in
                DispatchQueue.main.async {
                    guard self.soundOutputCommandGeneration == generation else { return }
                    switch result {
                    case .success:
                        self.currentSoundOutputID = outputID
                        self.soundOutputAvailable = true
                        self.unsupportedSoundOutputIDs.remove(outputID)
                        self.scheduleSoundOutputConfirmationExpiry(generation: generation)
                    case .failure(let message):
                        self.soundOutputConfirmationWorkItem?.cancel()
                        self.soundOutputConfirmationWorkItem = nil
                        self.pendingSoundOutputID = nil
                        if self.isUnsupportedSoundOutputError(message) {
                            self.unsupportedSoundOutputIDs.insert(outputID)
                        }
                    }
                    let title = TVSoundOutputOption.common.first(where: { $0.id == outputID })
                        .map(self.soundOutputTitle) ?? outputID
                    self.handleCommandResult(result, success: "\(self.text(.soundOutput))\(L10n.labelSeparator(languageMode: self.settings.languageMode))\(title)")
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
        let hdmiInputs = inputs.filter { $0.hdmiIndex != nil }
        guard hdmiInputs != externalInputs else { return }
        externalInputs = hdmiInputs
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
        guard foregroundAppID != appID else { return }
        let hadInput = !foregroundAppID.isEmpty
        foregroundAppID = appID
        updateSelectedHDMI()
        updateMacInputSince()
        if hadInput {
            displayOffGate.tvInputChanged()
        }
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
            guard Self.shouldAcceptSoundOutputSubscription(
                reported: outputID,
                pending: pendingSoundOutputID
            ) else {
                return
            }
            soundOutputAvailable = true
            currentSoundOutputID = outputID
            unsupportedSoundOutputIDs.remove(outputID)
        case .failure:
            if currentSoundOutputID.isEmpty {
                soundOutputAvailable = false
            }
        }
    }

    static func shouldAcceptSoundOutputSubscription(reported: String, pending: String?) -> Bool {
        pending == nil || pending == reported
    }

    private func scheduleSoundOutputConfirmationExpiry(generation: Int) {
        soundOutputConfirmationWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.soundOutputCommandGeneration == generation else { return }
            self.soundOutputConfirmationWorkItem = nil
            self.pendingSoundOutputID = nil
        }
        soundOutputConfirmationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
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
        pendingVolumeWork = nil
        volumeCommandInFlight = false
        activeVolumeCommandGeneration = nil
        muteCommandGeneration += 1
        muteTargetInFlight = nil
        muteReadInFlight = false
        queuedMuteToggles = 0
        soundOutputCommandGeneration += 1
        soundOutputConfirmationWorkItem?.cancel()
        soundOutputConfirmationWorkItem = nil
        pendingSoundOutputID = nil
        hdmiSwitchCooldownWorkItem?.cancel()
        hdmiSwitchCooldownWorkItem = nil
        hdmiCommandGeneration += 1
        isSwitchingHDMI = false
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

    private static let keyboardVolumeStep = 1
    private static let sleepReadFreshness: TimeInterval = 3
    private static let lockStandbyDelay: TimeInterval = 10
}

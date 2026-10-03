import AppKit

final class SettingsWindowController: NSWindowController, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private enum SettingsPage: CaseIterable {
        case general
        case preferences
        case hdmi
        case shortcuts

        var titleKey: L10n.Key {
            switch self {
            case .general:
                return .general
            case .preferences:
                return .preferences
            case .hdmi:
                return .hdmi
            case .shortcuts:
                return .shortcuts
            }
        }

        var tabKey: L10n.Key {
            switch self {
            case .general:
                return .general
            case .preferences:
                return .preferences
            case .hdmi:
                return .hdmi
            case .shortcuts:
                return .shortcuts
            }
        }

        var subtitleKey: L10n.Key {
            switch self {
            case .general:
                return .generalSubtitle
            case .preferences:
                return .preferencesSubtitle
            case .hdmi:
                return .hdmiSubtitle
            case .shortcuts:
                return .shortcutsSubtitle
            }
        }

        var systemImageName: String {
            switch self {
            case .general:
                return "gearshape"
            case .preferences:
                return "switch.2"
            case .hdmi:
                return "display.2"
            case .shortcuts:
                return "command"
            }
        }
    }

    private let settings: AppSettings
    private weak var coordinator: AppCoordinator?

    private var selectedPage: SettingsPage = .general
    private let sidebarTable = NSTableView()
    private let sidebarScrollView = NSScrollView()
    private let sidebarEffectView = NSVisualEffectView()
    private let pageTitleLabel = NSTextField(labelWithString: "")
    private let pageSubtitleLabel = NSTextField(labelWithString: "")
    private let contentContainer = NSView()
    private let connectionNameLabel = NSTextField(labelWithString: "")
    private let volumeTitleLabel = NSTextField(labelWithString: "")
    private let volumePercentLabel = NSTextField(labelWithString: "")
    private let ipFeedbackLabel = NSTextField(labelWithString: "")
    private let statusMessageLabel = NSTextField(wrappingLabelWithString: "")
    private let saveFeedbackLabel = NSTextField(labelWithString: "")
    private let shortcutStateLabel = NSTextField(labelWithString: "")
    private let appearanceControl = NSSegmentedControl(labels: ["自动", "浅色", "深色"], trackingMode: .selectOne, target: nil, action: nil)
    private let languageControl = NSSegmentedControl(labels: ["自动", "中文", "English", "日本語"], trackingMode: .selectOne, target: nil, action: nil)
    private let launchAtLoginButton = NSButton(checkboxWithTitle: "登录时自动启动 LGVolume", target: nil, action: nil)
    private let secureConnectionButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let useTVInputNamesButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let sleepTVButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let powerHelpLabel = NSTextField(wrappingLabelWithString: "")
    private let macInputPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let menuStylePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let deviceKindPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let detectedInputNamesLabel = NSTextField(labelWithString: "")
    private let ipField = NSTextField()
    private let nameField = NSTextField()
    private let hdmiNameFields = (0..<4).map { _ in NSTextField() }
    private let hdmiShortcutFields = (0..<4).map { _ in ShortcutRecorderField() }
    private let connectButton = NSButton(title: "", target: nil, action: nil)
    private let repairButton = NSButton(title: "", target: nil, action: nil)
    private let saveButton = NSButton(title: "", target: nil, action: nil)
    private let syncVolumeButton = NSButton(title: "", target: nil, action: nil)
    private let restoreHDMIShortcutsButton = NSButton(title: "", target: nil, action: nil)
    private let diagnosticsButton = NSButton(title: "", target: nil, action: nil)
    private var renderedLanguageMode: String?
    private var hasLoadedEditableValues = false
    private var saveFeedbackWorkItem: DispatchWorkItem?
    private var isReloadingSidebar = false

    init(settings: AppSettings, coordinator: AppCoordinator) {
        self.settings = settings
        self.coordinator = coordinator
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 840, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "LGVolume \(L10n.text(.settings, languageMode: settings.languageMode))"
        window.minSize = NSSize(width: 760, height: 520)
        window.center()
        super.init(window: window)
        configureControls()
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refresh() {
        if !hasLoadedEditableValues {
            loadEditableValues()
        }
        launchAtLoginButton.state = coordinator?.launchAtLogin == true || coordinator?.launchAtLoginRequiresApproval == true
            ? .on : .off
        launchAtLoginButton.toolTip = coordinator?.launchAtLoginRequiresApproval == true ? t(.launchRequiresApproval) : nil
        secureConnectionButton.state = settings.secureConnectionOnly ? .on : .off
        useTVInputNamesButton.state = settings.useTVInputNames ? .on : .off
        updateAppearanceSelection()
        updateLanguageSelection()
        updateShortcutStatus()
        if renderedLanguageMode != settings.languageMode {
            refreshLocalizedText()
        } else {
            updateStatus()
        }
        updateIPFeedback()
        updateHDMIInputMode()
        updatePowerControls()
        updateMenuStyleSelection()
    }

    func refreshLocalizedText() {
        renderedLanguageMode = settings.languageMode
        window?.title = "LGVolume \(t(.settings))"
        pageSubtitleLabel.stringValue = t(selectedPage.subtitleKey)

        isReloadingSidebar = true
        sidebarTable.reloadData()
        isReloadingSidebar = false

        appearanceControl.setLabel(t(.auto), forSegment: 0)
        appearanceControl.setLabel(t(.light), forSegment: 1)
        appearanceControl.setLabel(t(.dark), forSegment: 2)

        languageControl.setLabel(t(.auto), forSegment: 0)
        languageControl.setLabel(t(.chinese), forSegment: 1)
        languageControl.setLabel(t(.english), forSegment: 2)
        languageControl.setLabel(t(.japanese), forSegment: 3)

        launchAtLoginButton.title = t(.launchAtLogin)
        secureConnectionButton.title = t(.secureConnectionOnly)
        useTVInputNamesButton.title = t(.useTVInputNames)
        sleepTVButton.title = t(.sleepTVWithMac)
        ipField.placeholderString = t(.inputIP)
        volumeTitleLabel.stringValue = formLabelText(t(.volume))
        shortcutStateLabel.stringValue = t(.shortcutsEnabled)
        connectButton.title = coordinator?.isConnected == true ? t(.disconnect) : t(.pairConnect)
        repairButton.title = t(.repairPairing)
        saveButton.title = t(.save)
        syncVolumeButton.title = t(.syncVolume)
        restoreHDMIShortcutsButton.title = t(.restoreHDMIShortcuts)
        diagnosticsButton.title = t(.openDiagnostics)
        updatePageSelection()
        for field in hdmiShortcutFields {
            field.recordingPlaceholder = t(.pressShortcut)
            field.emptyPlaceholder = t(.notSet)
            field.invalidPlaceholder = t(.shortcutNeedsModifier)
            field.placeholderString = t(.notSet)
        }
        updateShortcutStatus()

        renderCurrentPage()
        updateStatus()
    }

    func updateStatus() {
        let connected = coordinator?.isConnected == true
        let volume = coordinator?.currentVolume ?? settings.volume
        let muted = coordinator?.isMuted ?? settings.muted

        connectButton.title = connected ? t(.disconnect) : t(.pairConnect)
        volumePercentLabel.stringValue = volumeString(volume: volume, muted: muted)

        if connected {
            connectionNameLabel.attributedStringValue = connectionTitle(settings.tvName, connected: true)
        } else {
            connectionNameLabel.attributedStringValue = connectionTitle(t(.currentDisconnected), connected: false)
            volumePercentLabel.stringValue = "—"
        }

        let isError = coordinator?.statusIsError == true
        statusMessageLabel.stringValue = isError ? coordinator?.status ?? "" : ""
        statusMessageLabel.textColor = .systemOrange
        statusMessageLabel.isHidden = !isError
    }

    func updateDevices(_ devices: [DiscoveredTV]) {
        if let first = devices.first, ipField.stringValue.isEmpty {
            ipField.placeholderString = first.ip
        }
    }

    func updateShortcutStatus() {
        let shortcutsAvailable = coordinator?.shortcutRegistrationStates.allSatisfy { $0 } == true
        shortcutStateLabel.stringValue = t(shortcutsAvailable ? .shortcutsEnabled : .shortcutsUnavailable)
        shortcutStateLabel.textColor = shortcutsAvailable ? .secondaryLabelColor : .systemOrange
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        SettingsPage.allCases.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard SettingsPage.allCases.indices.contains(row) else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("settings.sidebar.cell")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier

            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            cell.imageView = imageView
            cell.addSubview(imageView)

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.font = .systemFont(ofSize: 13, weight: .medium)
            textField.lineBreakMode = .byTruncatingTail
            cell.textField = textField
            cell.addSubview(textField)

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 9),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 18),
                imageView.heightAnchor.constraint(equalToConstant: 18),
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        let page = SettingsPage.allCases[row]
        cell.imageView?.image = NSImage(systemSymbolName: page.systemImageName, accessibilityDescription: t(page.tabKey))
        cell.textField?.stringValue = t(page.tabKey)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        // reloadData() (for a language change) can reset the selection to the first row.
        guard !isReloadingSidebar else { return }
        let row = sidebarTable.selectedRow
        guard SettingsPage.allCases.indices.contains(row) else { return }
        let page = SettingsPage.allCases[row]
        guard selectedPage != page else { return }
        DiagnosticsLogger.shared.log(
            "settings",
            "sidebar page \(selectedPage) -> \(page) event=\(NSApp.currentEvent.map { String(describing: $0.type) } ?? "none")"
        )
        selectedPage = page
        renderCurrentPage()
    }

    func selectPage(_ index: Int) {
        guard SettingsPage.allCases.indices.contains(index) else { return }
        DiagnosticsLogger.shared.log("settings", "select page \(index) from \(selectedPage)")
        selectedPage = SettingsPage.allCases[index]
        updatePageSelection()
        renderCurrentPage()
    }

    func controlTextDidChange(_ obj: Notification) {
        if obj.object as? NSTextField === ipField {
            updateIPFeedback()
        }
    }

    private func configureControls() {
        connectionNameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        volumePercentLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        ipField.delegate = self
        ipField.identifier = NSUserInterfaceItemIdentifier("settings.ip")
        nameField.identifier = NSUserInterfaceItemIdentifier("settings.name")
        appearanceControl.identifier = NSUserInterfaceItemIdentifier("settings.appearance")
        languageControl.identifier = NSUserInterfaceItemIdentifier("settings.language")
        launchAtLoginButton.identifier = NSUserInterfaceItemIdentifier("settings.launchAtLogin")
        secureConnectionButton.identifier = NSUserInterfaceItemIdentifier("settings.secureConnection")
        diagnosticsButton.identifier = NSUserInterfaceItemIdentifier("settings.diagnostics")
        useTVInputNamesButton.identifier = NSUserInterfaceItemIdentifier("settings.useTVInputNames")
        detectedInputNamesLabel.identifier = NSUserInterfaceItemIdentifier("settings.detectedInputNames")
        ipFeedbackLabel.identifier = NSUserInterfaceItemIdentifier("settings.ipFeedback")
        restoreHDMIShortcutsButton.identifier = NSUserInterfaceItemIdentifier("settings.restoreHDMIShortcuts")
        saveButton.identifier = NSUserInterfaceItemIdentifier("settings.save")
        configureTextField(ipField)
        configureTextField(nameField)
        ipField.widthAnchor.constraint(equalToConstant: 420).isActive = true
        nameField.widthAnchor.constraint(equalToConstant: 420).isActive = true

        for field in hdmiNameFields {
            field.placeholderString = "HDMI"
            configureTextField(field)
            field.widthAnchor.constraint(equalToConstant: 420).isActive = true
        }
        for (index, field) in hdmiNameFields.enumerated() {
            field.identifier = NSUserInterfaceItemIdentifier("settings.hdmiName\(index + 1)")
        }

        for (index, field) in hdmiShortcutFields.enumerated() {
            field.identifier = NSUserInterfaceItemIdentifier("settings.hdmiShortcut\(index + 1)")
            field.alignment = .center
            field.widthAnchor.constraint(equalToConstant: 360).isActive = true
            field.heightAnchor.constraint(equalToConstant: Self.formControlHeight).isActive = true
        }

        sidebarTable.identifier = NSUserInterfaceItemIdentifier("settings.sidebar")
        sidebarTable.headerView = nil
        sidebarTable.backgroundColor = .clear
        sidebarTable.style = .sourceList
        sidebarTable.allowsEmptySelection = false
        sidebarTable.rowHeight = 36
        sidebarTable.intercellSpacing = NSSize(width: 0, height: 2)
        sidebarTable.dataSource = self
        sidebarTable.delegate = self
        let sidebarColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("settings.sidebar.column"))
        sidebarColumn.resizingMask = .autoresizingMask
        sidebarTable.addTableColumn(sidebarColumn)

        sidebarScrollView.documentView = sidebarTable
        sidebarScrollView.drawsBackground = false
        sidebarScrollView.hasVerticalScroller = false
        sidebarScrollView.hasHorizontalScroller = false

        sidebarEffectView.material = .sidebar
        sidebarEffectView.blendingMode = .behindWindow
        sidebarEffectView.state = .active

        appearanceControl.target = self
        appearanceControl.action = #selector(changeAppearance)
        appearanceControl.heightAnchor.constraint(equalToConstant: Self.formControlHeight).isActive = true
        languageControl.target = self
        languageControl.action = #selector(changeLanguage)
        languageControl.heightAnchor.constraint(equalToConstant: Self.formControlHeight).isActive = true
        launchAtLoginButton.target = self
        launchAtLoginButton.action = #selector(changeLaunchAtLogin)
        secureConnectionButton.target = self
        secureConnectionButton.action = #selector(changeSecureConnection)
        useTVInputNamesButton.target = self
        useTVInputNamesButton.action = #selector(changeHDMIInputMode)
        sleepTVButton.identifier = NSUserInterfaceItemIdentifier("settings.sleepTVWithMac")
        sleepTVButton.target = self
        sleepTVButton.action = #selector(changeSleepTVWithMac)
        powerHelpLabel.identifier = NSUserInterfaceItemIdentifier("settings.powerHelp")
        powerHelpLabel.font = .systemFont(ofSize: 12)
        powerHelpLabel.preferredMaxLayoutWidth = 420
        powerHelpLabel.widthAnchor.constraint(equalToConstant: 420).isActive = true
        deviceKindPopup.identifier = NSUserInterfaceItemIdentifier("settings.deviceKind")
        deviceKindPopup.target = self
        deviceKindPopup.action = #selector(changeDeviceKind)
        deviceKindPopup.font = Self.formFont
        deviceKindPopup.widthAnchor.constraint(equalToConstant: 300).isActive = true
        menuStylePopup.identifier = NSUserInterfaceItemIdentifier("settings.menuStyle")
        menuStylePopup.target = self
        menuStylePopup.action = #selector(changeMenuStyle)
        menuStylePopup.font = Self.formFont
        menuStylePopup.widthAnchor.constraint(equalToConstant: 220).isActive = true
        macInputPopup.identifier = NSUserInterfaceItemIdentifier("settings.macInput")
        macInputPopup.target = self
        macInputPopup.action = #selector(changeMacInput)
        macInputPopup.font = Self.formFont
        macInputPopup.widthAnchor.constraint(equalToConstant: 220).isActive = true

        connectButton.target = self
        connectButton.action = #selector(connectOrDisconnect)
        connectButton.bezelStyle = .rounded
        repairButton.target = self
        repairButton.action = #selector(repairPairing)
        repairButton.bezelStyle = .rounded
        syncVolumeButton.target = self
        syncVolumeButton.action = #selector(refreshVolume)
        syncVolumeButton.bezelStyle = .rounded
        restoreHDMIShortcutsButton.target = self
        restoreHDMIShortcutsButton.action = #selector(restoreHDMIShortcuts)
        restoreHDMIShortcutsButton.bezelStyle = .rounded
        diagnosticsButton.target = self
        diagnosticsButton.action = #selector(openDiagnostics)
        diagnosticsButton.bezelStyle = .rounded
        saveButton.target = self
        saveButton.action = #selector(save)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        sidebarEffectView.translatesAutoresizingMaskIntoConstraints = false
        sidebarScrollView.translatesAutoresizingMaskIntoConstraints = false
        sidebarEffectView.addSubview(sidebarScrollView)
        contentView.addSubview(sidebarEffectView)

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.distribution = .fill
        root.spacing = 0
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            sidebarEffectView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            sidebarEffectView.topAnchor.constraint(equalTo: contentView.topAnchor),
            sidebarEffectView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            sidebarEffectView.widthAnchor.constraint(equalToConstant: Self.sidebarWidth),

            sidebarScrollView.leadingAnchor.constraint(equalTo: sidebarEffectView.leadingAnchor, constant: 8),
            sidebarScrollView.trailingAnchor.constraint(equalTo: sidebarEffectView.trailingAnchor, constant: -8),
            sidebarScrollView.topAnchor.constraint(equalTo: sidebarEffectView.topAnchor, constant: 12),
            sidebarScrollView.bottomAnchor.constraint(equalTo: sidebarEffectView.bottomAnchor, constant: -12),

            root.leadingAnchor.constraint(equalTo: sidebarEffectView.trailingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        let header = NSStackView()
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 4
        header.edgeInsets = NSEdgeInsets(top: 16, left: 28, bottom: 10, right: 28)
        header.setContentHuggingPriority(.required, for: .vertical)
        pageTitleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        header.addArrangedSubview(pageTitleLabel)
        pageSubtitleLabel.textColor = .secondaryLabelColor
        pageSubtitleLabel.font = .systemFont(ofSize: 13)
        header.addArrangedSubview(pageSubtitleLabel)

        root.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        header.heightAnchor.constraint(equalToConstant: 72).isActive = true

        let separator = separatorLine()
        root.addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(contentContainer)
        NSLayoutConstraint.activate([
            contentContainer.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])

        let footerSeparator = separatorLine()
        root.addArrangedSubview(footerSeparator)
        footerSeparator.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        let footer = row()
        footer.edgeInsets = NSEdgeInsets(top: 9, left: 28, bottom: 11, right: 28)
        saveFeedbackLabel.font = .systemFont(ofSize: 12, weight: .medium)
        saveFeedbackLabel.textColor = .systemGreen
        saveFeedbackLabel.identifier = NSUserInterfaceItemIdentifier("settings.saveFeedback")
        footer.addArrangedSubview(spacer())
        footer.addArrangedSubview(saveFeedbackLabel)
        footer.addArrangedSubview(saveButton)
        root.addArrangedSubview(footer)
        footer.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        footer.heightAnchor.constraint(equalToConstant: 50).isActive = true

        sidebarTable.reloadData()
        sidebarTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        refresh()
    }

    private func renderCurrentPage() {
        pageTitleLabel.stringValue = t(selectedPage.titleKey)
        pageSubtitleLabel.stringValue = t(selectedPage.subtitleKey)
        updatePageSelection()

        contentContainer.subviews.forEach { $0.removeFromSuperview() }
        let pageView: NSView
        switch selectedPage {
        case .general:
            pageView = generalPage()
        case .preferences:
            pageView = preferencesPage()
        case .hdmi:
            pageView = hdmiPage()
        case .shortcuts:
            pageView = shortcutsPage()
        }

        contentContainer.addSubview(pageView)
        pageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pageView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 26),
            pageView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -26),
            pageView.topAnchor.constraint(equalTo: contentContainer.topAnchor, constant: 16),
            pageView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor, constant: -12)
        ])
    }

    private func updatePageSelection() {
        let index = SettingsPage.allCases.firstIndex(of: selectedPage) ?? 0
        if sidebarTable.selectedRow != index {
            sidebarTable.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
    }

    private func generalPage() -> NSView {
        let stack = pageStack()

        let statusRow = row()
        statusRow.alignment = .firstBaseline
        connectionNameLabel.font = .systemFont(ofSize: 22, weight: .bold)
        statusRow.addArrangedSubview(connectionNameLabel)
        statusRow.addArrangedSubview(spacer())

        let volumeStack = row(spacing: 8)
        volumeStack.alignment = .firstBaseline
        volumeTitleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        volumeTitleLabel.textColor = .secondaryLabelColor
        volumeStack.addArrangedSubview(volumeTitleLabel)
        volumePercentLabel.font = .systemFont(ofSize: 24, weight: .bold)
        volumeStack.addArrangedSubview(volumePercentLabel)
        statusRow.addArrangedSubview(volumeStack)
        stack.addArrangedSubview(statusRow)

        stack.addArrangedSubview(pageSeparatorLine())

        ipFeedbackLabel.font = .systemFont(ofSize: 12, weight: .medium)
        let actionRow = row()
        actionRow.identifier = NSUserInterfaceItemIdentifier("settings.generalActions")
        actionRow.addArrangedSubview(connectButton)
        actionRow.addArrangedSubview(repairButton)
        actionRow.addArrangedSubview(syncVolumeButton)

        stack.addArrangedSubview(formGrid([
            (fixedLabel("LG TV IP:"), ipField),
            (fixedLabel(.displayName), nameField),
            (nil, ipFeedbackLabel),
            (nil, actionRow)
        ]))

        statusMessageLabel.identifier = NSUserInterfaceItemIdentifier("settings.statusMessage")
        statusMessageLabel.font = .systemFont(ofSize: 12)
        statusMessageLabel.preferredMaxLayoutWidth = 560
        statusMessageLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 560).isActive = true
        stack.addArrangedSubview(statusMessageLabel)

        return pageBox(stack)
    }

    private func preferencesPage() -> NSView {
        let stack = pageStack()

        stack.addArrangedSubview(formGrid([
            (fixedLabel(.appearance), appearanceControl),
            (fixedLabel(.menuStyle), menuStylePopup),
            (fixedLabel(.language), languageControl),
            (fixedLabel(.launch), launchAtLoginButton),
            (fixedLabel(.connection), secureConnectionButton),
            (fixedLabel(.deviceKind), deviceKindPopup),
            (fixedLabel(.power), sleepTVButton),
            (nil, powerHelpLabel),
            (fixedLabel(.diagnostics), diagnosticsButton)
        ]))

        return pageBox(stack)
    }

    private func hdmiPage() -> NSView {
        let stack = pageStack()

        detectedInputNamesLabel.font = .systemFont(ofSize: 12)
        detectedInputNamesLabel.textColor = .secondaryLabelColor
        detectedInputNamesLabel.lineBreakMode = .byTruncatingMiddle
        detectedInputNamesLabel.toolTip = detectedInputNamesLabel.stringValue
        if detectedInputNamesLabel.constraints.first(where: { $0.firstAttribute == .width }) == nil {
            detectedInputNamesLabel.widthAnchor.constraint(equalToConstant: 420).isActive = true
        }
        stack.addArrangedSubview(formGrid([
            (fixedLabel(.macInput), macInputPopup),
            (fixedLabel(.inputNames), useTVInputNamesButton),
            (nil, detectedInputNamesLabel),
            (fixedLabel("HDMI1:"), hdmiNameFields[0]),
            (fixedLabel("HDMI2:"), hdmiNameFields[1]),
            (fixedLabel("HDMI3:"), hdmiNameFields[2]),
            (fixedLabel("HDMI4:"), hdmiNameFields[3])
        ]))
        return pageBox(stack)
    }

    private func shortcutsPage() -> NSView {
        let stack = pageStack()

        let summaryRow = row()
        let summary = label(t(.shortcutsSummary))
        summary.textColor = .secondaryLabelColor
        summaryRow.addArrangedSubview(summary)
        summaryRow.addArrangedSubview(spacer())
        shortcutStateLabel.textColor = .secondaryLabelColor
        shortcutStateLabel.font = .systemFont(ofSize: 13, weight: .medium)
        summaryRow.addArrangedSubview(shortcutStateLabel)
        stack.addArrangedSubview(summaryRow)

        stack.addArrangedSubview(pageSeparatorLine())

        stack.addArrangedSubview(formGrid([
            (fixedLabel(.hdmiShortcut1), hdmiShortcutFields[0]),
            (fixedLabel(.hdmiShortcut2), hdmiShortcutFields[1]),
            (fixedLabel(.hdmiShortcut3), hdmiShortcutFields[2]),
            (fixedLabel(.hdmiShortcut4), hdmiShortcutFields[3]),
            (nil, restoreHDMIShortcutsButton)
        ]))

        return pageBox(stack)
    }

    private func pageStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 18, bottom: 8, right: 18)
        return stack
    }

    private func pageBox(_ stack: NSStackView) -> NSView {
        let contentView = NSView()
        contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor)
        ])
        return contentView
    }

    private func row(spacing: CGFloat = 10) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = spacing
        return stack
    }

    private func formGrid(_ rows: [(label: NSTextField?, control: NSView)]) -> NSGridView {
        let grid = NSGridView(views: rows.map { row in
            [row.label ?? NSGridCell.emptyContentView, row.control]
        })
        grid.columnSpacing = 10
        grid.rowSpacing = 4
        grid.rowAlignment = .none
        grid.yPlacement = .center
        grid.column(at: 0).width = Self.labelColumnWidth
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 1).xPlacement = .leading
        for index in 0..<grid.numberOfRows {
            let row = grid.row(at: index)
            row.yPlacement = .center
            let control = rows[index].control
            if control === powerHelpLabel {
                row.height = Self.helpRowHeight
            } else {
                row.height = control === ipFeedbackLabel || control === detectedInputNamesLabel
                    ? Self.secondaryRowHeight
                    : Self.formRowHeight
            }
        }
        return grid
    }

    private func fixedLabel(_ key: L10n.Key) -> NSTextField {
        let field = label(formLabelText(t(key)))
        field.alignment = .left
        field.font = Self.formFont
        return field
    }

    private func fixedLabel(_ text: String) -> NSTextField {
        let field = label(formLabelText(text))
        field.alignment = .left
        field.font = Self.formFont
        return field
    }

    private func formLabelText(_ text: String) -> String {
        let base = text.trimmingCharacters(in: CharacterSet(charactersIn: " :："))
        let separator = L10n.resolvedLanguage(from: settings.languageMode) == "en" ? ":" : "："
        return base + separator
    }

    private func configureTextField(_ field: NSTextField) {
        field.font = Self.formFont
        field.controlSize = .regular
        field.cell?.controlSize = .regular
        field.cell?.font = Self.formFont
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.heightAnchor.constraint(equalToConstant: Self.formControlHeight).isActive = true
    }

    private func label(_ text: String) -> NSTextField {
        NSTextField(labelWithString: text)
    }

    private func separatorLine() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func pageSeparatorLine() -> NSBox {
        let box = separatorLine()
        box.widthAnchor.constraint(equalToConstant: 560).isActive = true
        return box
    }

    private func spacer(width: CGFloat? = nil) -> NSView {
        let view = NSView()
        if let width {
            view.widthAnchor.constraint(equalToConstant: width).isActive = true
            view.setContentHuggingPriority(.required, for: .horizontal)
            view.setContentCompressionResistancePriority(.required, for: .horizontal)
        } else {
            view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }
        return view
    }

    private func updateAppearanceSelection() {
        switch settings.appearanceMode {
        case "light":
            appearanceControl.selectedSegment = 1
        case "dark":
            appearanceControl.selectedSegment = 2
        default:
            appearanceControl.selectedSegment = 0
        }
    }

    private func updateLanguageSelection() {
        switch settings.languageMode {
        case "zh-Hans":
            languageControl.selectedSegment = 1
        case "en":
            languageControl.selectedSegment = 2
        case "ja":
            languageControl.selectedSegment = 3
        default:
            languageControl.selectedSegment = 0
        }
    }

    private func loadEditableValues() {
        ipField.stringValue = settings.tvIP
        nameField.stringValue = settings.tvName
        for (offset, field) in hdmiNameFields.enumerated() {
            field.stringValue = settings.hdmiName(offset + 1)
        }
        for (offset, field) in hdmiShortcutFields.enumerated() {
            field.shortcut = settings.hdmiShortcut(offset + 1)
        }
        hasLoadedEditableValues = true
    }

    /// Save feedback lives in the footer next to the Save button so it is visible on every page.
    private func showSaveFeedback() {
        saveFeedbackLabel.stringValue = t(.saveSuccess)
        saveFeedbackLabel.alphaValue = 1
        saveFeedbackWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.saveFeedbackLabel.stringValue = ""
        }
        saveFeedbackWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: workItem)
    }

    private func updateIPFeedback() {

        let ip = ipField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ip.isEmpty else {
            ipFeedbackLabel.stringValue = ""
            connectButton.isEnabled = coordinator?.isConnected == true
            repairButton.isEnabled = false
            saveButton.isEnabled = true
            return
        }

        let valid = LocalNetworkAddress.isAllowedIPv4(ip)
        connectButton.isEnabled = coordinator?.isConnected == true || valid
        repairButton.isEnabled = valid
        saveButton.isEnabled = ip.isEmpty || valid
        if valid {
            ipFeedbackLabel.stringValue = ""
        } else {
            ipFeedbackLabel.stringValue = t(.invalidIP)
            ipFeedbackLabel.textColor = .systemOrange
        }
    }

    private func updateHDMIInputMode() {
        let useTVNames = useTVInputNamesButton.state == .on
        for (offset, field) in hdmiNameFields.enumerated() {
            field.isEnabled = !useTVNames
            field.toolTip = coordinator?.detectedHDMIName(offset + 1)
        }

        let detectedNames = (1...4).compactMap { index in
            coordinator?.detectedHDMIName(index).map { "HDMI\(index): \($0)" }
        }
        detectedInputNamesLabel.stringValue = detectedNames.isEmpty
            ? t(.noInputsDetected)
            : "\(t(.detectedInputs)) \(detectedNames.joined(separator: "  ·  "))"
        detectedInputNamesLabel.toolTip = detectedInputNamesLabel.stringValue
    }

    private func updateMenuStyleSelection() {
        let titles = MenuPanelStyle.allCases.map { t($0.titleKey) }
        if menuStylePopup.itemTitles != titles {
            menuStylePopup.removeAllItems()
            menuStylePopup.addItems(withTitles: titles)
        }
        let style = coordinator?.menuStyle ?? settings.menuStyle
        menuStylePopup.selectItem(at: MenuPanelStyle.allCases.firstIndex(of: style) ?? 0)
    }

    private func updateDeviceKindSelection() {
        guard let coordinator else { return }
        let detected: String
        switch coordinator.detectedDeviceKind {
        case .tv: detected = t(.deviceKindTV)
        case .monitor: detected = t(.deviceKindMonitor)
        case nil: detected = t(.deviceKindUnknown)
        }
        let titles = ["\(t(.deviceKindAuto))（\(detected)）", t(.deviceKindTV), t(.deviceKindMonitor)]
        if deviceKindPopup.itemTitles != titles {
            deviceKindPopup.removeAllItems()
            deviceKindPopup.addItems(withTitles: titles)
        }
        deviceKindPopup.selectItem(at: DeviceKindMode.allCases.firstIndex(of: coordinator.deviceKindMode) ?? 0)
    }

    private func updatePowerControls() {
        guard let coordinator else { return }
        sleepTVButton.state = coordinator.sleepTVWithMac ? .on : .off

        let detected = coordinator.detectedMacHDMIPort
        let autoTitle = detected.map { "\(t(.macInputAuto)) (HDMI\($0))" } ?? t(.macInputAuto)
        let titles = [autoTitle] + (1...4).map { "HDMI\($0)" }
        if macInputPopup.itemTitles != titles {
            macInputPopup.removeAllItems()
            macInputPopup.addItems(withTitles: titles)
        }
        macInputPopup.selectItem(at: coordinator.macHDMIPortOverride)

        if coordinator.sleepTVNeedsRepair {
            powerHelpLabel.stringValue = t(.powerPermissionNeedsRepair)
            powerHelpLabel.textColor = .systemOrange
        } else if coordinator.sleepTVWithMac && coordinator.effectiveMacHDMIPort == nil {
            powerHelpLabel.stringValue = t(.macInputNotDetected)
            powerHelpLabel.textColor = .systemOrange
        } else {
            powerHelpLabel.stringValue = coordinator.effectiveDeviceKind == .monitor
                ? t(.sleepTVWithMacMonitorHelp)
                : t(.sleepTVWithMacHelp)
            powerHelpLabel.textColor = .secondaryLabelColor
        }
        updateDeviceKindSelection()
        macInputPopup.toolTip = detected == nil ? t(.macInputNotDetected) : nil
    }

    private func volumeString(volume: Int, muted: Bool) -> String {
        muted ? t(.muted) : "\(volume)%"
    }

    private func connectionTitle(_ title: String, connected: Bool) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 22, weight: .bold),
                .foregroundColor: NSColor.labelColor
            ]
        )
        result.append(NSAttributedString(string: "  "))
        result.append(NSAttributedString(
            string: "●",
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .bold),
                .foregroundColor: connected ? NSColor.systemGreen : NSColor.tertiaryLabelColor,
                .baselineOffset: 1
            ]
        ))
        return result
    }

    private func t(_ key: L10n.Key) -> String {
        L10n.text(key, languageMode: settings.languageMode)
    }

    @objc private func changeAppearance() {
        let modes = ["auto", "light", "dark"]
        let index = max(0, min(appearanceControl.selectedSegment, modes.count - 1))
        coordinator?.setAppearanceMode(modes[index])
    }

    @objc private func changeLanguage() {
        let modes = ["auto", "zh-Hans", "en", "ja"]
        let index = max(0, min(languageControl.selectedSegment, modes.count - 1))
        coordinator?.setLanguageMode(modes[index])
    }

    @objc private func changeHDMIInputMode() {
        updateHDMIInputMode()
    }

    @objc private func changeMenuStyle() {
        let styles = MenuPanelStyle.allCases
        let index = menuStylePopup.indexOfSelectedItem
        guard styles.indices.contains(index) else { return }
        coordinator?.setMenuStyle(styles[index])
        showSaveFeedback()
    }

    @objc private func changeDeviceKind() {
        let modes = DeviceKindMode.allCases
        let index = deviceKindPopup.indexOfSelectedItem
        guard modes.indices.contains(index) else { return }
        coordinator?.setDeviceKindMode(modes[index])
        updatePowerControls()
        showSaveFeedback()
    }

    @objc private func changeSleepTVWithMac() {
        coordinator?.setSleepTVWithMac(sleepTVButton.state == .on)
        updatePowerControls()
        showSaveFeedback()
    }

    @objc private func changeMacInput() {
        coordinator?.setMacHDMIPortOverride(max(0, macInputPopup.indexOfSelectedItem))
        updatePowerControls()
        showSaveFeedback()
    }

    @objc private func changeSecureConnection() {
        coordinator?.setSecureConnectionOnly(secureConnectionButton.state == .on)
        showSaveFeedback()
    }

    @objc private func changeLaunchAtLogin() {
        coordinator?.setLaunchAtLogin(launchAtLoginButton.state == .on)
        guard let problem = coordinator?.launchAtLoginProblem, let window else {
            showSaveFeedback()
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = t(.launchAtLogin)
        alert.informativeText = problem
        alert.addButton(withTitle: t(.openLoginItems))
        alert.addButton(withTitle: t(.ok))
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn {
                self?.coordinator?.openLoginItemsSettings()
            }
        }
    }

    @objc private func save() {
        _ = commitSettings()
    }

    private func commitSettings() -> Bool {
        let ip = ipField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ip.isEmpty || LocalNetworkAddress.isAllowedIPv4(ip) else {
            updateIPFeedback()
            if selectedPage != .general {
                selectPage(0)
            }
            window?.makeFirstResponder(ipField)
            NSSound.beep()
            return false
        }
        coordinator?.saveSettings(
            ip: ip,
            name: nameField.stringValue,
            hdmiNames: hdmiNameFields.map(\.stringValue),
            hdmiShortcuts: hdmiShortcutFields.map(\.shortcut),
            secureConnectionOnly: secureConnectionButton.state == .on,
            useTVInputNames: useTVInputNamesButton.state == .on
        )
        loadEditableValues()
        updateIPFeedback()
        showSaveFeedback()
        return true
    }

    @objc private func restoreHDMIShortcuts() {
        coordinator?.restoreDefaultHDMIShortcuts()
        for (offset, field) in hdmiShortcutFields.enumerated() {
            field.shortcut = settings.hdmiShortcut(offset + 1)
        }
        showSaveFeedback()
    }

    @objc private func connectOrDisconnect() {
        if coordinator?.isConnected == true {
            coordinator?.disconnect()
        } else {
            guard commitSettings() else { return }
            coordinator?.connectFromSettings()
        }
    }

    @objc private func repairPairing() {
        guard commitSettings() else { return }
        coordinator?.pair()
    }

    @objc private func refreshVolume() {
        guard commitSettings() else { return }
        coordinator?.refreshVolume()
    }

    @objc private func openDiagnostics() {
        coordinator?.openDiagnosticsLog()
    }

    private static let formFont = NSFont.systemFont(ofSize: 15)
    private static let labelColumnWidth: CGFloat = 120
    private static let formRowHeight: CGFloat = 30
    private static let secondaryRowHeight: CGFloat = 20
    private static let helpRowHeight: CGFloat = 66
    private static let formControlHeight: CGFloat = 28
    private static let sidebarWidth: CGFloat = 176
}

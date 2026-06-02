import AppKit

final class SettingsWindowController: NSWindowController {
    private let settings: AppSettings
    private weak var coordinator: AppCoordinator?

    private var localizedTextFields: [(NSTextField, L10n.Key)] = []
    private let statusLabel = NSTextField(labelWithString: "")
    private let volumeWaveLabel = NSTextField(labelWithString: "")
    private let appearanceControl = NSSegmentedControl(labels: ["自动", "浅色", "深色"], trackingMode: .selectOne, target: nil, action: nil)
    private let languageControl = NSSegmentedControl(labels: ["自动", "中文", "English", "日本語"], trackingMode: .selectOne, target: nil, action: nil)
    private let launchAtLoginButton = NSButton(checkboxWithTitle: "登录时自动启动 LGVolume", target: nil, action: nil)
    private let ipField = NSTextField()
    private let nameField = NSTextField()
    private let hdmiNameFields = (0..<4).map { _ in NSTextField() }
    private let hdmiShortcutFields = (0..<4).map { _ in ShortcutRecorderField() }
    private let connectButton = NSButton(title: "配对/连接", target: nil, action: nil)
    private let saveButton = NSButton(title: "", target: nil, action: nil)
    private let syncVolumeButton = NSButton(title: "", target: nil, action: nil)
    private let restoreHDMIShortcutsButton = NSButton(title: "", target: nil, action: nil)
    private var devices: [DiscoveredTV] = []

    init(settings: AppSettings, coordinator: AppCoordinator) {
        self.settings = settings
        self.coordinator = coordinator
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 650),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "LGVolume \(L10n.text(.settings, languageMode: settings.languageMode))"
        window.center()
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refresh() {
        ipField.stringValue = settings.tvIP
        nameField.stringValue = settings.tvName
        for (offset, field) in hdmiNameFields.enumerated() {
            field.stringValue = settings.hdmiName(offset + 1)
        }
        for (offset, field) in hdmiShortcutFields.enumerated() {
            field.shortcut = settings.hdmiShortcut(offset + 1)
            field.placeholderString = t(.notSet)
        }
        launchAtLoginButton.state = coordinator?.launchAtLogin == true ? .on : .off
        updateAppearanceSelection()
        updateLanguageSelection()
        refreshLocalizedText()
        updateStatus(coordinator?.status ?? t(.currentDisconnected))
    }

    func refreshLocalizedText() {
        window?.title = "LGVolume \(t(.settings))"
        for (field, key) in localizedTextFields {
            field.stringValue = t(key)
        }

        appearanceControl.setLabel(t(.auto), forSegment: 0)
        appearanceControl.setLabel(t(.light), forSegment: 1)
        appearanceControl.setLabel(t(.dark), forSegment: 2)

        languageControl.setLabel(t(.auto), forSegment: 0)
        languageControl.setLabel(t(.chinese), forSegment: 1)
        languageControl.setLabel(t(.english), forSegment: 2)
        languageControl.setLabel(t(.japanese), forSegment: 3)

        launchAtLoginButton.title = t(.launchAtLogin)
        ipField.placeholderString = t(.inputIP)
        saveButton.title = t(.save)
        syncVolumeButton.title = t(.syncVolume)
        restoreHDMIShortcutsButton.title = t(.restoreHDMIShortcuts)

        for field in hdmiShortcutFields {
            field.placeholderString = t(.notSet)
        }
        updateStatus(coordinator?.status ?? t(.currentDisconnected))
    }

    func updateStatus(_ status: String) {
        guard let coordinator else {
            statusLabel.stringValue = status
            return
        }

        if coordinator.isConnected {
            statusLabel.stringValue = "\(t(.matched)): \(settings.tvName)  \(coordinator.currentTVIP)"
            connectButton.title = t(.disconnect)
        } else {
            statusLabel.stringValue = status.isEmpty ? t(.noMatched) : status
            connectButton.title = t(.pairConnect)
        }
        volumeWaveLabel.stringValue = volumeString(volume: coordinator.currentVolume, muted: coordinator.isMuted)
    }

    func updateOutput(_ output: String) {
    }

    func updateDevices(_ devices: [DiscoveredTV]) {
        self.devices = devices
        if let first = devices.first, ipField.stringValue.isEmpty {
            ipField.placeholderString = first.ip
        }
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 0
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        let header = NSStackView()
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 8
        header.edgeInsets = NSEdgeInsets(top: 28, left: 32, bottom: 22, right: 32)
        header.translatesAutoresizingMaskIntoConstraints = false
        header.addArrangedSubview(titleLabel(.general))
        let subtitle = localizedLabel(.generalSubtitle)
        subtitle.textColor = .secondaryLabelColor
        header.addArrangedSubview(subtitle)
        root.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        let separator = NSBox()
        separator.boxType = .separator
        root.addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        let card = NSBox()
        card.boxType = .custom
        card.cornerRadius = 8
        card.borderColor = NSColor.separatorColor
        card.fillColor = NSColor.controlBackgroundColor
        card.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(card)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 32),
            card.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -32),
            card.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 20),
            card.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24)
        ])

        let form = NSStackView()
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 18
        form.edgeInsets = NSEdgeInsets(top: 22, left: 28, bottom: 22, right: 28)
        form.translatesAutoresizingMaskIntoConstraints = false
        card.contentView?.addSubview(form)

        NSLayoutConstraint.activate([
            form.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            form.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            form.topAnchor.constraint(equalTo: card.topAnchor),
            form.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor)
        ])

        let statusRow = row()
        statusRow.addArrangedSubview(fixedLabel(.matchStatus))
        statusLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        statusRow.addArrangedSubview(statusLabel)
        form.addArrangedSubview(statusRow)

        let volumeRow = row()
        volumeRow.addArrangedSubview(fixedLabel(.syncedVolume))
        volumeWaveLabel.font = .monospacedSystemFont(ofSize: 15, weight: .semibold)
        volumeRow.addArrangedSubview(volumeWaveLabel)
        form.addArrangedSubview(volumeRow)

        form.addArrangedSubview(separatorLine(width: 600))

        let appearanceRow = row()
        appearanceRow.addArrangedSubview(fixedLabel(.appearance))
        appearanceControl.target = self
        appearanceControl.action = #selector(changeAppearance)
        appearanceRow.addArrangedSubview(appearanceControl)
        form.addArrangedSubview(appearanceRow)

        let languageRow = row()
        languageRow.addArrangedSubview(fixedLabel(.language))
        languageControl.target = self
        languageControl.action = #selector(changeLanguage)
        languageRow.addArrangedSubview(languageControl)
        form.addArrangedSubview(languageRow)

        let loginRow = row()
        loginRow.addArrangedSubview(fixedLabel(.launch))
        launchAtLoginButton.target = self
        launchAtLoginButton.action = #selector(changeLaunchAtLogin)
        loginRow.addArrangedSubview(launchAtLoginButton)
        form.addArrangedSubview(loginRow)

        let ipRow = row()
        ipRow.addArrangedSubview(fixedLabel("LG TV IP:"))
        ipField.placeholderString = t(.inputIP)
        ipField.widthAnchor.constraint(equalToConstant: 390).isActive = true
        ipRow.addArrangedSubview(ipField)
        form.addArrangedSubview(ipRow)

        let nameRow = row()
        nameRow.addArrangedSubview(fixedLabel(.displayName))
        nameField.placeholderString = "LG TV"
        nameField.widthAnchor.constraint(equalToConstant: 390).isActive = true
        nameRow.addArrangedSubview(nameField)
        form.addArrangedSubview(nameRow)

        form.addArrangedSubview(separatorLine(width: 600))

        let hdmiGrid = NSGridView(views: [
            [fixedLabel("HDMI1："), hdmiNameFields[0], fixedLabel("HDMI2："), hdmiNameFields[1]],
            [fixedLabel("HDMI3："), hdmiNameFields[2], fixedLabel("HDMI4："), hdmiNameFields[3]]
        ])
        hdmiGrid.rowSpacing = 10
        hdmiGrid.columnSpacing = 12
        for field in hdmiNameFields {
            field.placeholderString = "HDMI"
            field.widthAnchor.constraint(equalToConstant: 165).isActive = true
        }
        form.addArrangedSubview(hdmiGrid)

        form.addArrangedSubview(separatorLine(width: 600))

        let shortcuts = localizedLabel(.shortcutsSummary)
        shortcuts.textColor = .secondaryLabelColor
        form.addArrangedSubview(shortcuts)

        let hdmiShortcutGrid = NSGridView(views: [
            [fixedLabel(.hdmiShortcut1), hdmiShortcutFields[0], fixedLabel(.hdmiShortcut2), hdmiShortcutFields[1]],
            [fixedLabel(.hdmiShortcut3), hdmiShortcutFields[2], fixedLabel(.hdmiShortcut4), hdmiShortcutFields[3]]
        ])
        hdmiShortcutGrid.rowSpacing = 10
        hdmiShortcutGrid.columnSpacing = 12
        for field in hdmiShortcutFields {
            field.placeholderString = t(.notSet)
            field.alignment = .center
            field.widthAnchor.constraint(equalToConstant: 165).isActive = true
        }
        form.addArrangedSubview(hdmiShortcutGrid)

        let restoreShortcutRow = row()
        restoreShortcutRow.addArrangedSubview(fixedLabel(""))
        restoreHDMIShortcutsButton.target = self
        restoreHDMIShortcutsButton.action = #selector(restoreHDMIShortcuts)
        restoreHDMIShortcutsButton.bezelStyle = .rounded
        restoreShortcutRow.addArrangedSubview(restoreHDMIShortcutsButton)
        form.addArrangedSubview(restoreShortcutRow)

        let actionRow = row()
        saveButton.target = self
        saveButton.action = #selector(save)
        saveButton.bezelStyle = .rounded
        actionRow.addArrangedSubview(saveButton)
        connectButton.target = self
        connectButton.action = #selector(connectOrDisconnect)
        connectButton.bezelStyle = .rounded
        actionRow.addArrangedSubview(connectButton)
        syncVolumeButton.target = self
        syncVolumeButton.action = #selector(refreshVolume)
        syncVolumeButton.bezelStyle = .rounded
        actionRow.addArrangedSubview(syncVolumeButton)
        form.addArrangedSubview(actionRow)

        refreshLocalizedText()
        refresh()
    }

    private func row() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        return stack
    }

    private func titleLabel(_ key: L10n.Key) -> NSTextField {
        let field = localizedLabel(key)
        field.font = .systemFont(ofSize: 22, weight: .bold)
        return field
    }

    private func fixedLabel(_ key: L10n.Key) -> NSTextField {
        let field = localizedLabel(key)
        field.alignment = .right
        field.widthAnchor.constraint(equalToConstant: 124).isActive = true
        return field
    }

    private func fixedLabel(_ text: String) -> NSTextField {
        let field = label(text)
        field.alignment = .right
        field.widthAnchor.constraint(equalToConstant: 124).isActive = true
        return field
    }

    private func label(_ text: String) -> NSTextField {
        NSTextField(labelWithString: text)
    }

    private func localizedLabel(_ key: L10n.Key) -> NSTextField {
        let field = label(t(key))
        localizedTextFields.append((field, key))
        return field
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    private func separatorLine(width: CGFloat) -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: width).isActive = true
        return box
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

    private func volumeString(volume: Int, muted: Bool) -> String {
        muted ? t(.muted) : "\(volume)%"
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
        refreshLocalizedText()
    }

    @objc private func changeLaunchAtLogin() {
        coordinator?.setLaunchAtLogin(launchAtLoginButton.state == .on)
    }

    @objc private func save() {
        coordinator?.saveManualSettings(ip: ipField.stringValue, name: nameField.stringValue)
        coordinator?.saveHDMINames(hdmiNameFields.map(\.stringValue))
        coordinator?.saveHDMIShortcuts(hdmiShortcutFields.map(\.shortcut))
    }

    @objc private func restoreHDMIShortcuts() {
        coordinator?.restoreDefaultHDMIShortcuts()
        for (offset, field) in hdmiShortcutFields.enumerated() {
            field.shortcut = settings.hdmiShortcut(offset + 1)
        }
    }

    @objc private func connectOrDisconnect() {
        save()
        if coordinator?.isConnected == true {
            coordinator?.disconnect()
        } else {
            coordinator?.pair()
        }
    }

    @objc private func refreshVolume() {
        save()
        coordinator?.refreshVolume()
    }
}

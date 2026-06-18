import AppKit

final class SettingsWindowController: NSWindowController, NSTextFieldDelegate {
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
                return .misc
            case .hdmi:
                return .hdmi
            case .shortcuts:
                return .shortcuts
            }
        }
    }

    private let settings: AppSettings
    private weak var coordinator: AppCoordinator?

    private var selectedPage: SettingsPage = .general
    private var pageButtons: [SettingsPage: NSButton] = [:]
    private let pageTitleLabel = NSTextField(labelWithString: "")
    private let pageSubtitleLabel = NSTextField(labelWithString: "")
    private let contentContainer = NSView()
    private let connectionNameLabel = NSTextField(labelWithString: "")
    private let volumeTitleLabel = NSTextField(labelWithString: "")
    private let volumePercentLabel = NSTextField(labelWithString: "")
    private let ipFeedbackLabel = NSTextField(labelWithString: "")
    private let shortcutStateLabel = NSTextField(labelWithString: "")
    private let appearanceControl = NSSegmentedControl(labels: ["自动", "浅色", "深色"], trackingMode: .selectOne, target: nil, action: nil)
    private let languageControl = NSSegmentedControl(labels: ["自动", "中文", "English", "日本語"], trackingMode: .selectOne, target: nil, action: nil)
    private let launchAtLoginButton = NSButton(checkboxWithTitle: "登录时自动启动 LGVolume", target: nil, action: nil)
    private let ipField = NSTextField()
    private let nameField = NSTextField()
    private let hdmiNameFields = (0..<4).map { _ in NSTextField() }
    private let hdmiShortcutFields = (0..<4).map { _ in ShortcutRecorderField() }
    private let connectButton = NSButton(title: "", target: nil, action: nil)
    private let saveButton = NSButton(title: "", target: nil, action: nil)
    private let syncVolumeButton = NSButton(title: "", target: nil, action: nil)
    private let restoreHDMIShortcutsButton = NSButton(title: "", target: nil, action: nil)
    private var devices: [DiscoveredTV] = []

    init(settings: AppSettings, coordinator: AppCoordinator) {
        self.settings = settings
        self.coordinator = coordinator
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 410),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "LGVolume \(L10n.text(.settings, languageMode: settings.languageMode))"
        window.center()
        super.init(window: window)
        configureControls()
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
        updateIPFeedback()
        updateStatus(coordinator?.status ?? t(.currentDisconnected))
    }

    func refreshLocalizedText() {
        window?.title = "LGVolume \(t(.settings))"
        pageSubtitleLabel.stringValue = t(.generalSubtitle)

        for page in SettingsPage.allCases {
            pageButtons[page]?.title = t(page.tabKey)
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
        volumeTitleLabel.stringValue = "\(t(.volume))："
        shortcutStateLabel.stringValue = t(.shortcutsEnabled)
        connectButton.title = coordinator?.isConnected == true ? t(.disconnect) : t(.pairConnect)
        saveButton.title = t(.save)
        syncVolumeButton.title = t(.syncVolume)
        restoreHDMIShortcutsButton.title = t(.restoreHDMIShortcuts)
        for field in hdmiShortcutFields {
            field.placeholderString = t(.notSet)
        }

        renderCurrentPage()
        updateStatus(coordinator?.status ?? t(.currentDisconnected))
    }

    func updateStatus(_ status: String) {
        let connected = coordinator?.isConnected == true
        let volume = coordinator?.currentVolume ?? settings.volume
        let muted = coordinator?.isMuted ?? settings.muted

        connectButton.title = connected ? t(.disconnect) : t(.pairConnect)
        volumePercentLabel.stringValue = volumeString(volume: volume, muted: muted)

        if connected {
            connectionNameLabel.attributedStringValue = connectionTitle(settings.tvName, connected: true)
        } else {
            connectionNameLabel.attributedStringValue = connectionTitle(t(.currentDisconnected), connected: false)
        }
    }

    func updateOutput(_ output: String) {
    }

    func updateDevices(_ devices: [DiscoveredTV]) {
        self.devices = devices
        if let first = devices.first, ipField.stringValue.isEmpty {
            ipField.placeholderString = first.ip
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        if obj.object as? NSTextField === ipField {
            updateIPFeedback()
        }
    }

    private func configureControls() {
        connectionNameLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true
        volumePercentLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true

        ipField.delegate = self
        configureTextField(ipField)
        configureTextField(nameField)
        ipField.widthAnchor.constraint(equalToConstant: 360).isActive = true
        ipField.heightAnchor.constraint(equalToConstant: 32).isActive = true
        nameField.widthAnchor.constraint(equalToConstant: 360).isActive = true
        nameField.heightAnchor.constraint(equalToConstant: 32).isActive = true

        for field in hdmiNameFields {
            field.placeholderString = "HDMI"
            configureTextField(field)
            field.widthAnchor.constraint(equalToConstant: 220).isActive = true
            field.heightAnchor.constraint(equalToConstant: 32).isActive = true
        }

        for field in hdmiShortcutFields {
            field.alignment = .center
            field.widthAnchor.constraint(equalToConstant: 220).isActive = true
        }

        appearanceControl.target = self
        appearanceControl.action = #selector(changeAppearance)
        languageControl.target = self
        languageControl.action = #selector(changeLanguage)
        launchAtLoginButton.target = self
        launchAtLoginButton.action = #selector(changeLaunchAtLogin)

        connectButton.target = self
        connectButton.action = #selector(connectOrDisconnect)
        connectButton.bezelStyle = .rounded
        syncVolumeButton.target = self
        syncVolumeButton.action = #selector(refreshVolume)
        syncVolumeButton.bezelStyle = .rounded
        restoreHDMIShortcutsButton.target = self
        restoreHDMIShortcutsButton.action = #selector(restoreHDMIShortcuts)
        restoreHDMIShortcutsButton.bezelStyle = .rounded
        saveButton.target = self
        saveButton.action = #selector(save)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.distribution = .fill
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
        header.edgeInsets = NSEdgeInsets(top: 20, left: 32, bottom: 12, right: 32)
        header.setContentHuggingPriority(.required, for: .vertical)
        pageTitleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        header.addArrangedSubview(pageTitleLabel)
        pageSubtitleLabel.textColor = .secondaryLabelColor
        pageSubtitleLabel.font = .systemFont(ofSize: 13)
        header.addArrangedSubview(pageSubtitleLabel)

        let tabs = NSStackView()
        tabs.orientation = .horizontal
        tabs.alignment = .centerY
        tabs.spacing = 10
        tabs.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0)
        for page in SettingsPage.allCases {
            let button = tabButton(page: page)
            pageButtons[page] = button
            tabs.addArrangedSubview(button)
        }
        header.addArrangedSubview(tabs)
        root.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        header.heightAnchor.constraint(equalToConstant: 128).isActive = true

        let separator = separatorLine()
        root.addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(contentContainer)
        NSLayoutConstraint.activate([
            contentContainer.widthAnchor.constraint(equalTo: root.widthAnchor),
            contentContainer.heightAnchor.constraint(equalToConstant: 222)
        ])

        let bottomSeparator = separatorLine()
        root.addArrangedSubview(bottomSeparator)
        bottomSeparator.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 10
        footer.edgeInsets = NSEdgeInsets(top: 8, left: 32, bottom: 10, right: 32)
        footer.addArrangedSubview(spacer())
        footer.addArrangedSubview(saveButton)
        root.addArrangedSubview(footer)
        footer.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        refreshLocalizedText()
        refresh()
    }

    private func tabButton(page: SettingsPage) -> NSButton {
        let button = NSButton(title: t(page.tabKey), target: self, action: #selector(changePage(_:)))
        button.tag = SettingsPage.allCases.firstIndex(of: page) ?? 0
        button.bezelStyle = .rounded
        button.setButtonType(.toggle)
        button.widthAnchor.constraint(equalToConstant: 150).isActive = true
        button.heightAnchor.constraint(equalToConstant: 34).isActive = true
        return button
    }

    private func renderCurrentPage() {
        pageTitleLabel.stringValue = t(selectedPage.titleKey)
        updatePageButtons()

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
            pageView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 32),
            pageView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -32),
            pageView.topAnchor.constraint(equalTo: contentContainer.topAnchor, constant: 10),
            pageView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor, constant: -10)
        ])
    }

    private func updatePageButtons() {
        for (page, button) in pageButtons {
            button.state = page == selectedPage ? .on : .off
            button.contentTintColor = page == selectedPage ? .controlAccentColor : .labelColor
        }
    }

    private func generalPage() -> NSView {
        let stack = pageStack()

        let statusRow = row()
        statusRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 42).isActive = true
        let titleStack = NSStackView()
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 4

        let nameRow = row(spacing: 8)
        connectionNameLabel.font = .systemFont(ofSize: 22, weight: .bold)
        nameRow.addArrangedSubview(connectionNameLabel)
        titleStack.addArrangedSubview(nameRow)

        statusRow.addArrangedSubview(titleStack)
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

        stack.addArrangedSubview(separatorLine(width: 660))

        let grid = NSGridView(views: [
            [fixedLabel("LG TV IP:"), ipField, ipFeedbackLabel],
            [fixedLabel(.displayName), nameField, NSView()]
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 10
        grid.row(at: 0).height = 36
        grid.row(at: 1).height = 36
        grid.row(at: 0).yPlacement = .center
        grid.row(at: 1).yPlacement = .center
        ipFeedbackLabel.font = .systemFont(ofSize: 12, weight: .medium)
        stack.addArrangedSubview(grid)

        let actionRow = row()
        actionRow.addArrangedSubview(spacer(width: 134))
        actionRow.addArrangedSubview(connectButton)
        actionRow.addArrangedSubview(syncVolumeButton)
        stack.addArrangedSubview(actionRow)

        return pageBox(stack)
    }

    private func preferencesPage() -> NSView {
        let stack = pageStack()

        let appearanceRow = row()
        appearanceRow.addArrangedSubview(fixedLabel(.appearance))
        appearanceRow.addArrangedSubview(appearanceControl)
        stack.addArrangedSubview(appearanceRow)

        let languageRow = row()
        languageRow.addArrangedSubview(fixedLabel(.language))
        languageRow.addArrangedSubview(languageControl)
        stack.addArrangedSubview(languageRow)

        let loginRow = row()
        loginRow.addArrangedSubview(fixedLabel(.launch))
        loginRow.addArrangedSubview(launchAtLoginButton)
        stack.addArrangedSubview(loginRow)

        return pageBox(stack)
    }

    private func hdmiPage() -> NSView {
        let stack = pageStack()
        let grid = NSGridView(views: [
            [fixedLabel("HDMI1:"), hdmiNameFields[0], fixedLabel("HDMI2:"), hdmiNameFields[1]],
            [fixedLabel("HDMI3:"), hdmiNameFields[2], fixedLabel("HDMI4:"), hdmiNameFields[3]]
        ])
        grid.rowSpacing = 14
        grid.columnSpacing = 12
        stack.addArrangedSubview(grid)
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

        stack.addArrangedSubview(separatorLine(width: 660))

        let grid = NSGridView(views: [
            [fixedLabel(.hdmiShortcut1), hdmiShortcutFields[0], fixedLabel(.hdmiShortcut2), hdmiShortcutFields[1]],
            [fixedLabel(.hdmiShortcut3), hdmiShortcutFields[2], fixedLabel(.hdmiShortcut4), hdmiShortcutFields[3]]
        ])
        grid.rowSpacing = 14
        grid.columnSpacing = 12
        stack.addArrangedSubview(grid)

        let restoreRow = row()
        restoreRow.addArrangedSubview(spacer(width: 134))
        restoreRow.addArrangedSubview(restoreHDMIShortcutsButton)
        stack.addArrangedSubview(restoreRow)

        return pageBox(stack)
    }

    private func pageStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 22, bottom: 18, right: 22)
        return stack
    }

    private func pageBox(_ stack: NSStackView) -> NSBox {
        let box = NSBox()
        box.boxType = .custom
        box.cornerRadius = 10
        box.borderColor = NSColor.separatorColor
        box.fillColor = NSColor.controlBackgroundColor
        guard let contentView = box.contentView else { return box }
        contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor)
        ])
        return box
    }

    private func row(spacing: CGFloat = 10) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = spacing
        return stack
    }

    private func fixedLabel(_ key: L10n.Key) -> NSTextField {
        let field = label(t(key))
        field.alignment = .right
        field.font = .systemFont(ofSize: 15, weight: .medium)
        field.widthAnchor.constraint(equalToConstant: 124).isActive = true
        field.heightAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true
        return field
    }

    private func fixedLabel(_ text: String) -> NSTextField {
        let field = label(text)
        field.alignment = .right
        field.font = .systemFont(ofSize: 15, weight: .medium)
        field.widthAnchor.constraint(equalToConstant: 124).isActive = true
        field.heightAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true
        return field
    }

    private func configureTextField(_ field: NSTextField) {
        let font = NSFont.systemFont(ofSize: 15)
        field.font = font
        field.controlSize = .regular
        field.cell?.controlSize = .regular
        field.cell?.font = font
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
    }

    private func label(_ text: String) -> NSTextField {
        NSTextField(labelWithString: text)
    }

    private func separatorLine(width: CGFloat? = nil) -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        if let width {
            box.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        return box
    }

    private func spacer(width: CGFloat? = nil) -> NSView {
        let view = NSView()
        if let width {
            view.widthAnchor.constraint(equalToConstant: width).isActive = true
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

    private func updateIPFeedback(text: String? = nil) {
        if let text {
            ipFeedbackLabel.stringValue = text
            ipFeedbackLabel.textColor = .systemGreen
            return
        }

        let ip = ipField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ip.isEmpty else {
            ipFeedbackLabel.stringValue = ""
            return
        }

        if isValidIPv4(ip) {
            ipFeedbackLabel.stringValue = ""
        } else {
            ipFeedbackLabel.stringValue = t(.invalidIP)
            ipFeedbackLabel.textColor = .systemOrange
        }
    }

    private func isValidIPv4(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let value = Int(part), value >= 0, value <= 255 else { return false }
            return String(value) == part || part == "0"
        }
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

    @objc private func changePage(_ sender: NSButton) {
        selectedPage = SettingsPage.allCases[max(0, min(sender.tag, SettingsPage.allCases.count - 1))]
        renderCurrentPage()
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

    @objc private func changeLaunchAtLogin() {
        coordinator?.setLaunchAtLogin(launchAtLoginButton.state == .on)
    }

    @objc private func save() {
        coordinator?.saveSettings(
            ip: ipField.stringValue,
            name: nameField.stringValue,
            hdmiNames: hdmiNameFields.map(\.stringValue),
            hdmiShortcuts: hdmiShortcutFields.map(\.shortcut)
        )
        updateIPFeedback(text: t(.saveSuccess))
    }

    @objc private func restoreHDMIShortcuts() {
        coordinator?.restoreDefaultHDMIShortcuts()
        for (offset, field) in hdmiShortcutFields.enumerated() {
            field.shortcut = settings.hdmiShortcut(offset + 1)
        }
        updateIPFeedback(text: t(.saveSuccess))
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

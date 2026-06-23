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
    }

    private let settings: AppSettings
    private weak var coordinator: AppCoordinator?

    private var selectedPage: SettingsPage = .general
    private let pageControl = NSSegmentedControl(labels: ["", "", "", ""], trackingMode: .selectOne, target: nil, action: nil)
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
    private var renderedLanguageMode: String?
    private var hasLoadedEditableValues = false

    init(settings: AppSettings, coordinator: AppCoordinator) {
        self.settings = settings
        self.coordinator = coordinator
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 390),
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
        if !hasLoadedEditableValues {
            loadEditableValues()
        }
        launchAtLoginButton.state = coordinator?.launchAtLogin == true ? .on : .off
        launchAtLoginButton.toolTip = coordinator?.launchAtLoginRequiresApproval == true ? t(.launchRequiresApproval) : nil
        updateAppearanceSelection()
        updateLanguageSelection()
        updateShortcutStatus()
        if renderedLanguageMode != settings.languageMode {
            refreshLocalizedText()
        } else {
            updateStatus()
        }
        updateIPFeedback()
    }

    func refreshLocalizedText() {
        renderedLanguageMode = settings.languageMode
        window?.title = "LGVolume \(t(.settings))"
        pageSubtitleLabel.stringValue = t(selectedPage.subtitleKey)

        for (offset, page) in SettingsPage.allCases.enumerated() {
            pageControl.setLabel(t(page.tabKey), forSegment: offset)
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
        }
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

    func controlTextDidChange(_ obj: Notification) {
        if obj.object as? NSTextField === ipField {
            updateIPFeedback()
        }
    }

    private func configureControls() {
        connectionNameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        volumePercentLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        ipField.delegate = self
        configureTextField(ipField)
        configureTextField(nameField)
        ipField.widthAnchor.constraint(equalToConstant: 420).isActive = true
        nameField.widthAnchor.constraint(equalToConstant: 420).isActive = true

        for field in hdmiNameFields {
            field.placeholderString = "HDMI"
            configureTextField(field)
            field.widthAnchor.constraint(equalToConstant: 420).isActive = true
        }

        for field in hdmiShortcutFields {
            field.alignment = .center
            field.widthAnchor.constraint(equalToConstant: 360).isActive = true
        }

        pageControl.target = self
        pageControl.action = #selector(changePage(_:))
        pageControl.segmentStyle = .rounded
        pageControl.controlSize = .small
        pageControl.font = .systemFont(ofSize: 12, weight: .medium)
        pageControl.selectedSegment = 0
        pageControl.widthAnchor.constraint(equalToConstant: 360).isActive = true

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
        header.spacing = 7
        header.edgeInsets = NSEdgeInsets(top: 18, left: 32, bottom: 10, right: 32)
        header.setContentHuggingPriority(.required, for: .vertical)
        pageTitleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        header.addArrangedSubview(pageTitleLabel)
        pageSubtitleLabel.textColor = .secondaryLabelColor
        pageSubtitleLabel.font = .systemFont(ofSize: 13)
        header.addArrangedSubview(pageSubtitleLabel)

        header.addArrangedSubview(pageControl)
        root.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        header.heightAnchor.constraint(equalToConstant: 104).isActive = true

        let separator = separatorLine()
        root.addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(contentContainer)
        NSLayoutConstraint.activate([
            contentContainer.widthAnchor.constraint(equalTo: root.widthAnchor),
            contentContainer.heightAnchor.constraint(equalToConstant: 270)
        ])

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
            pageView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 24),
            pageView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -24),
            pageView.topAnchor.constraint(equalTo: contentContainer.topAnchor, constant: 10),
            pageView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor, constant: -10)
        ])
    }

    private func updatePageSelection() {
        pageControl.selectedSegment = SettingsPage.allCases.firstIndex(of: selectedPage) ?? 0
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

        stack.addArrangedSubview(separatorLine())

        ipFeedbackLabel.font = .systemFont(ofSize: 12, weight: .medium)
        stack.addArrangedSubview(formRow(label: fixedLabel("LG TV IP:"), control: ipField))
        stack.addArrangedSubview(formRow(label: fixedLabel(.displayName), control: nameField))

        let feedbackRow = row()
        feedbackRow.addArrangedSubview(spacer(width: Self.labelColumnWidth + 10))
        feedbackRow.addArrangedSubview(ipFeedbackLabel)
        stack.addArrangedSubview(feedbackRow)

        let actionRow = row()
        actionRow.addArrangedSubview(spacer(width: Self.labelColumnWidth + 10))
        actionRow.addArrangedSubview(saveButton)
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
        stack.addArrangedSubview(formRow(label: fixedLabel("HDMI1:"), control: hdmiNameFields[0]))
        stack.addArrangedSubview(formRow(label: fixedLabel("HDMI2:"), control: hdmiNameFields[1]))
        stack.addArrangedSubview(formRow(label: fixedLabel("HDMI3:"), control: hdmiNameFields[2]))
        stack.addArrangedSubview(formRow(label: fixedLabel("HDMI4:"), control: hdmiNameFields[3]))
        let actionRow = row()
        actionRow.addArrangedSubview(spacer(width: Self.labelColumnWidth + 10))
        actionRow.addArrangedSubview(saveButton)
        stack.addArrangedSubview(actionRow)
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

        stack.addArrangedSubview(separatorLine())

        stack.addArrangedSubview(formRow(label: fixedLabel(.hdmiShortcut1), control: hdmiShortcutFields[0]))
        stack.addArrangedSubview(formRow(label: fixedLabel(.hdmiShortcut2), control: hdmiShortcutFields[1]))
        stack.addArrangedSubview(formRow(label: fixedLabel(.hdmiShortcut3), control: hdmiShortcutFields[2]))
        stack.addArrangedSubview(formRow(label: fixedLabel(.hdmiShortcut4), control: hdmiShortcutFields[3]))

        let restoreRow = row()
        restoreRow.addArrangedSubview(spacer(width: Self.labelColumnWidth + 10))
        restoreRow.addArrangedSubview(saveButton)
        restoreRow.addArrangedSubview(restoreHDMIShortcutsButton)
        stack.addArrangedSubview(restoreRow)

        return pageBox(stack)
    }

    private func pageStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 16, right: 18)
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

    private func formRow(label: NSTextField, control: NSView) -> NSStackView {
        let stack = row()
        stack.alignment = .firstBaseline
        stack.addArrangedSubview(label)
        stack.addArrangedSubview(control)
        return stack
    }

    private func fixedLabel(_ key: L10n.Key) -> NSTextField {
        let field = label(t(key))
        field.alignment = .right
        field.font = Self.formFont
        field.widthAnchor.constraint(equalToConstant: Self.labelColumnWidth).isActive = true
        return field
    }

    private func fixedLabel(_ text: String) -> NSTextField {
        let field = label(text)
        field.alignment = .right
        field.font = Self.formFont
        field.widthAnchor.constraint(equalToConstant: Self.labelColumnWidth).isActive = true
        return field
    }

    private func configureTextField(_ field: NSTextField) {
        field.font = Self.formFont
        field.controlSize = .regular
        field.cell?.controlSize = .regular
        field.cell?.font = Self.formFont
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
    }

    private func label(_ text: String) -> NSTextField {
        NSTextField(labelWithString: text)
    }

    private func separatorLine() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: 620).isActive = true
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

    private func updateIPFeedback(text: String? = nil) {
        if let text {
            ipFeedbackLabel.stringValue = text
            ipFeedbackLabel.textColor = .systemGreen
            return
        }

        let ip = ipField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ip.isEmpty else {
            ipFeedbackLabel.stringValue = ""
            connectButton.isEnabled = coordinator?.isConnected == true
            saveButton.isEnabled = true
            return
        }

        let valid = LocalNetworkAddress.isAllowedIPv4(ip)
        connectButton.isEnabled = coordinator?.isConnected == true || valid
        saveButton.isEnabled = ip.isEmpty || valid
        if valid {
            ipFeedbackLabel.stringValue = ""
        } else {
            ipFeedbackLabel.stringValue = t(.invalidIP)
            ipFeedbackLabel.textColor = .systemOrange
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

    @objc private func changePage(_ sender: NSSegmentedControl) {
        selectedPage = SettingsPage.allCases[max(0, min(sender.selectedSegment, SettingsPage.allCases.count - 1))]
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
        _ = commitSettings()
    }

    private func commitSettings() -> Bool {
        let ip = ipField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ip.isEmpty || LocalNetworkAddress.isAllowedIPv4(ip) else {
            updateIPFeedback()
            NSSound.beep()
            return false
        }
        coordinator?.saveSettings(
            ip: ip,
            name: nameField.stringValue,
            hdmiNames: hdmiNameFields.map(\.stringValue),
            hdmiShortcuts: hdmiShortcutFields.map(\.shortcut)
        )
        loadEditableValues()
        updateIPFeedback(text: t(.saveSuccess))
        return true
    }

    @objc private func restoreHDMIShortcuts() {
        coordinator?.restoreDefaultHDMIShortcuts()
        for (offset, field) in hdmiShortcutFields.enumerated() {
            field.shortcut = settings.hdmiShortcut(offset + 1)
        }
        updateIPFeedback(text: t(.saveSuccess))
    }

    @objc private func connectOrDisconnect() {
        guard commitSettings() else { return }
        if coordinator?.isConnected == true {
            coordinator?.disconnect()
        } else {
            coordinator?.connectFromSettings()
        }
    }

    @objc private func refreshVolume() {
        guard commitSettings() else { return }
        coordinator?.refreshVolume()
    }

    private static let formFont = NSFont.systemFont(ofSize: 15)
    private static let labelColumnWidth: CGFloat = 120
}

import AppKit

final class SettingsWindowController: NSWindowController {
    private let settings: AppSettings
    private weak var coordinator: AppCoordinator?

    private let statusLabel = NSTextField(labelWithString: "")
    private let volumeWaveLabel = NSTextField(labelWithString: "")
    private let appearanceControl = NSSegmentedControl(labels: ["自动", "浅色", "深色"], trackingMode: .selectOne, target: nil, action: nil)
    private let ipField = NSTextField()
    private let nameField = NSTextField()
    private let hdmiNameFields = (0..<4).map { _ in NSTextField() }
    private let connectButton = NSButton(title: "配对/连接", target: nil, action: nil)
    private var devices: [DiscoveredTV] = []

    init(settings: AppSettings, coordinator: AppCoordinator) {
        self.settings = settings
        self.coordinator = coordinator
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "LGVolume 设置"
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
        updateAppearanceSelection()
        updateStatus(coordinator?.status ?? "未连接")
    }

    func updateStatus(_ status: String) {
        guard let coordinator else {
            statusLabel.stringValue = status
            return
        }

        if coordinator.isConnected {
            statusLabel.stringValue = "已匹配成功：\(settings.tvName)  \(coordinator.currentTVIP)"
            connectButton.title = "断开"
        } else {
            statusLabel.stringValue = status.isEmpty ? "未匹配" : status
            connectButton.title = "配对/连接"
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
        header.addArrangedSubview(titleLabel("通用"))
        let subtitle = label("在这里配置 LG 电视连接、HDMI 输入和全局音量快捷键。")
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
        statusRow.addArrangedSubview(fixedLabel("匹配状态："))
        statusLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        statusRow.addArrangedSubview(statusLabel)
        form.addArrangedSubview(statusRow)

        let volumeRow = row()
        volumeRow.addArrangedSubview(fixedLabel("已同步音量："))
        volumeWaveLabel.font = .monospacedSystemFont(ofSize: 15, weight: .semibold)
        volumeRow.addArrangedSubview(volumeWaveLabel)
        form.addArrangedSubview(volumeRow)

        form.addArrangedSubview(separatorLine(width: 600))

        let appearanceRow = row()
        appearanceRow.addArrangedSubview(fixedLabel("外观："))
        appearanceControl.target = self
        appearanceControl.action = #selector(changeAppearance)
        appearanceRow.addArrangedSubview(appearanceControl)
        form.addArrangedSubview(appearanceRow)

        let ipRow = row()
        ipRow.addArrangedSubview(fixedLabel("LG C2 IP："))
        ipField.placeholderString = "例如：192.168.1.23"
        ipField.widthAnchor.constraint(equalToConstant: 390).isActive = true
        ipRow.addArrangedSubview(ipField)
        form.addArrangedSubview(ipRow)

        let nameRow = row()
        nameRow.addArrangedSubview(fixedLabel("显示名称："))
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

        let shortcuts = label("快捷键：F10 静音 / F11 减小音量 / F12 增加音量")
        shortcuts.textColor = .secondaryLabelColor
        form.addArrangedSubview(shortcuts)

        let actionRow = row()
        actionRow.addArrangedSubview(button("保存", action: #selector(save)))
        connectButton.target = self
        connectButton.action = #selector(connectOrDisconnect)
        connectButton.bezelStyle = .rounded
        actionRow.addArrangedSubview(connectButton)
        actionRow.addArrangedSubview(button("同步音量", action: #selector(refreshVolume)))
        form.addArrangedSubview(actionRow)

        refresh()
    }

    private func row() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        return stack
    }

    private func titleLabel(_ text: String) -> NSTextField {
        let field = label(text)
        field.font = .systemFont(ofSize: 22, weight: .bold)
        return field
    }

    private func fixedLabel(_ text: String) -> NSTextField {
        let field = label(text)
        field.alignment = .right
        field.widthAnchor.constraint(equalToConstant: 112).isActive = true
        return field
    }

    private func label(_ text: String) -> NSTextField {
        NSTextField(labelWithString: text)
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

    private func volumeString(volume: Int, muted: Bool) -> String {
        muted ? "静音" : "\(volume)%"
    }

    @objc private func changeAppearance() {
        let modes = ["auto", "light", "dark"]
        let index = max(0, min(appearanceControl.selectedSegment, modes.count - 1))
        coordinator?.setAppearanceMode(modes[index])
    }

    @objc private func save() {
        coordinator?.saveManualSettings(ip: ipField.stringValue, name: nameField.stringValue)
        coordinator?.saveHDMINames(hdmiNameFields.map(\.stringValue))
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

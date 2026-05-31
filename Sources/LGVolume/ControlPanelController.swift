import AppKit

final class ControlPanelController: NSWindowController {
    private static let panelSize = NSSize(width: 312, height: 252)

    private let visualEffectView = NSVisualEffectView()
    private let titleLabel = NSTextField(labelWithString: "LG TV")
    private let volumeLabel = NSTextField(labelWithString: "50%")
    private let muteButton = NSButton()
    private let hdmiButtons = (0..<4).map { _ in NSButton() }
    private weak var coordinator: AppCoordinator?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        super.init(window: panel)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func toggle(anchor: NSStatusBarButton, title: String, volume: Int, muted: Bool, hdmiNames: [String]) {
        if window?.isVisible == true {
            window?.orderOut(nil)
            return
        }
        update(title: title, volume: volume, muted: muted, hdmiNames: hdmiNames)
        position(anchor: anchor)
        window?.orderFrontRegardless()
    }

    func update(title: String, volume: Int, muted: Bool, hdmiNames: [String]) {
        titleLabel.stringValue = title.isEmpty ? "LG TV" : title
        volumeLabel.stringValue = muted ? "静音" : "\(volume)%"
        let symbolName = muted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        muteButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "静音")
        for (offset, button) in hdmiButtons.enumerated() {
            button.title = offset < hdmiNames.count ? hdmiNames[offset] : "HDMI\(offset + 1)"
        }
    }

    func refreshAppearance() {
        visualEffectView.needsDisplay = true
    }

    private func buildUI() {
        guard let window else { return }

        let container = RoundedVisualEffectView()
        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
        container.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.material = .hudWindow
        window.contentView = container

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 16, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        stack.addArrangedSubview(titleLabel)

        let volumeRow = NSStackView()
        volumeRow.orientation = .horizontal
        volumeRow.alignment = .centerY
        volumeRow.spacing = 10
        stack.addArrangedSubview(volumeRow)
        volumeRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -36).isActive = true

        muteButton.bezelStyle = .regularSquare
        muteButton.isBordered = false
        muteButton.target = self
        muteButton.action = #selector(toggleMute)
        muteButton.widthAnchor.constraint(equalToConstant: 30).isActive = true
        muteButton.heightAnchor.constraint(equalToConstant: 30).isActive = true
        volumeRow.addArrangedSubview(muteButton)

        let volumeTitle = NSTextField(labelWithString: "音量")
        volumeTitle.textColor = .secondaryLabelColor
        volumeRow.addArrangedSubview(volumeTitle)

        volumeRow.addArrangedSubview(NSView())
        volumeLabel.font = .monospacedDigitSystemFont(ofSize: 22, weight: .semibold)
        volumeRow.addArrangedSubview(volumeLabel)

        let volumeButtons = NSStackView()
        volumeButtons.orientation = .horizontal
        volumeButtons.spacing = 8
        volumeButtons.addArrangedSubview(symbolButton("minus", action: #selector(volumeDown)))
        volumeButtons.addArrangedSubview(symbolButton("plus", action: #selector(volumeUp)))
        volumeRow.addArrangedSubview(volumeButtons)

        let grid = NSGridView(views: [
            [hdmiButtons[0], hdmiButtons[1]],
            [hdmiButtons[2], hdmiButtons[3]]
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        for (offset, button) in hdmiButtons.enumerated() {
            button.tag = offset + 1
            button.target = self
            button.action = #selector(switchHDMI)
            button.bezelStyle = .rounded
            button.controlSize = .large
            button.font = .systemFont(ofSize: 14, weight: .semibold)
            button.widthAnchor.constraint(equalToConstant: 132).isActive = true
            button.heightAnchor.constraint(equalToConstant: 34).isActive = true
        }
        stack.addArrangedSubview(grid)

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 8
        stack.addArrangedSubview(footer)
        footer.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -36).isActive = true
        footer.addArrangedSubview(NSView())
        footer.addArrangedSubview(footerButton("设置", action: #selector(showSettings)))
        footer.addArrangedSubview(footerButton("退出", action: #selector(quit)))
    }

    private func position(anchor: NSStatusBarButton) {
        guard let window, let anchorWindow = anchor.window else { return }
        let anchorRect = anchor.convert(anchor.bounds, to: nil)
        let screenRect = anchorWindow.convertToScreen(anchorRect)
        let visible = (anchorWindow.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        var x = screenRect.midX - window.frame.width / 2
        x = min(max(x, visible.minX + 10), visible.maxX - window.frame.width - 10)
        let y = visible.maxY - window.frame.height - 8
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func symbolButton(_ symbolName: String, action: Selector) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        button.bezelStyle = .rounded
        button.target = self
        button.action = action
        button.widthAnchor.constraint(equalToConstant: 30).isActive = true
        return button
    }

    private func footerButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    @objc private func toggleMute() {
        coordinator?.toggleMuteFromPanel()
    }

    @objc private func volumeDown() {
        coordinator?.adjustVolumeFromPanel(delta: -1)
    }

    @objc private func volumeUp() {
        coordinator?.adjustVolumeFromPanel(delta: 1)
    }

    @objc private func switchHDMI(_ sender: NSButton) {
        coordinator?.switchHDMIFromPanel(index: sender.tag)
    }

    @objc private func showSettings() {
        window?.orderOut(nil)
        coordinator?.showSettings()
    }

    @objc private func quit() {
        coordinator?.quit()
    }
}

private final class RoundedVisualEffectView: NSVisualEffectView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.cornerRadius = 22
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 0.6
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.48).cgColor
    }
}

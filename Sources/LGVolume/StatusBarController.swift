import AppKit

final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private weak var coordinator: AppCoordinator?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        super.init()
        configure()
    }

    func refresh() {
        statusItem.button?.toolTip = coordinator?.status ?? "LGVolumeHDMI"
        let symbolName = coordinator?.isMuted == true ? "speaker.slash.fill" : "speaker.wave.2.fill"
        statusItem.button?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "LGVolumeHDMI")
    }

    private func configure() {
        statusItem.button?.image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "LGVolumeHDMI")
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.target = self
        statusItem.button?.action = #selector(clicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func clicked() {
        guard let button = statusItem.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu(from: button)
        } else {
            coordinator?.showVolumePanel(anchor: button)
        }
    }

    @objc private func settings() {
        coordinator?.showSettings()
    }

    @objc private func quit() {
        coordinator?.quit()
    }

    private func showMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "设置", action: #selector(settings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }
}

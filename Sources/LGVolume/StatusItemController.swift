import AppKit
import Combine
import SwiftUI

/// Owns the menu bar icon and the panel it opens.
///
/// This replaces SwiftUI's `MenuBarExtra(.window)`, which could stop opening after its panel
/// launched another window (Settings). Here every show and hide goes through one place: the panel
/// closes when it loses key status, on Escape, before Settings opens, and on a second click.
@MainActor
final class StatusItemController: NSObject, NSWindowDelegate {
    private let coordinator: AppCoordinator
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let panel: MenuPanelWindow
    private let hostingView: NSHostingView<MenuPanelRoot>
    private var changeSubscription: AnyCancellable?
    private var lastClosed = Date.distantPast

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        hostingView = NSHostingView(rootView: MenuPanelRoot(coordinator: coordinator))
        panel = MenuPanelWindow()
        super.init()

        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = Self.roundedMask(radius: Self.cornerRadius)
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = [.width, .height]
        background.addSubview(hostingView)
        panel.contentView = background
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.closePanel() }

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePanel)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("LGVolume")
        }
        coordinator.closeMenuPanel = { [weak self] in self?.closePanel() }
        changeSubscription = coordinator.objectWillChange.sink { [weak self] _ in
            // objectWillChange fires before the new value is stored.
            DispatchQueue.main.async {
                self?.updateButton()
                self?.resizePanelIfVisible()
            }
        }
        updateButton()
    }

    @objc private func togglePanel() {
        if panel.isVisible {
            closePanel()
            return
        }
        // A click on the icon first makes the open panel resign key (which closes it); do not
        // immediately reopen it from that same click.
        guard Date().timeIntervalSince(lastClosed) > 0.25 else { return }
        showPanel()
    }

    private func showPanel() {
        coordinator.refreshTVState()
        layoutPanel()
        panel.makeKeyAndOrderFront(nil)
        statusItem.button?.highlight(true)
    }

    func closePanel() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
        lastClosed = Date()
    }

    func windowDidResignKey(_ notification: Notification) {
        closePanel()
    }

    private func resizePanelIfVisible() {
        guard panel.isVisible else { return }
        layoutPanel()
    }

    /// Sizes the panel to its SwiftUI content and hangs it below the icon, inside the screen.
    private func layoutPanel() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let size = hostingView.fittingSize
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screenFrame = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame ?? buttonFrame
        var x = buttonFrame.midX - size.width / 2
        x = min(max(x, screenFrame.minX + 8), screenFrame.maxX - size.width - 8)
        let top = min(buttonFrame.minY - 5, screenFrame.maxY)
        let frame = NSRect(x: x, y: top - size.height, width: size.width, height: size.height)
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
        hostingView.frame = NSRect(origin: .zero, size: size)
    }

    private func updateButton() {
        guard let button = statusItem.button else { return }
        let symbol = coordinator.menuMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: coordinator.text(.volume))
        image?.isTemplate = true
        button.image = image
        button.appearsDisabled = !coordinator.isConnected
        button.toolTip = coordinator.status
    }

    private static let cornerRadius: CGFloat = 12

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// Borderless panel that can take keyboard focus (for ⌘, ⌘Q and Escape) without activating
/// the app, like a menu.
final class MenuPanelWindow: NSPanel {
    var onCancel: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Root view of the panel: follows the chosen style and its width.
struct MenuPanelRoot: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        MenuBarControlView(coordinator: coordinator)
            .frame(width: coordinator.menuPreferredWidth)
            .fixedSize(horizontal: false, vertical: true)
    }
}

import AppKit
import ApplicationServices

final class KeyboardVolumeMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let onVolumeDown: () -> Void
    private let onVolumeUp: () -> Void
    private let onMute: () -> Void
    private let hdmiShortcuts: () -> [KeyboardShortcut?]
    private let onHDMIShortcut: (Int) -> Void

    init(
        onVolumeDown: @escaping () -> Void,
        onVolumeUp: @escaping () -> Void,
        onMute: @escaping () -> Void,
        hdmiShortcuts: @escaping () -> [KeyboardShortcut?],
        onHDMIShortcut: @escaping (Int) -> Void
    ) {
        self.onVolumeDown = onVolumeDown
        self.onVolumeUp = onVolumeUp
        self.onMute = onMute
        self.hdmiShortcuts = hdmiShortcuts
        self.onHDMIShortcut = onHDMIShortcut
    }

    func start() {
        requestAccessibilityPermission()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .systemDefined]) { [weak self] event in
            if self?.handle(event) == true {
                return nil
            }
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .systemDefined]) { [weak self] event in
            _ = self?.handle(event)
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        if event.type == .systemDefined {
            return handleMediaKey(event)
        }

        for (offset, shortcut) in hdmiShortcuts().enumerated() {
            guard let shortcut, shortcut.matches(event) else {
                continue
            }
            onHDMIShortcut(offset + 1)
            return true
        }

        switch event.keyCode {
        case 109:
            onMute()
            return true
        case 103:
            onVolumeDown()
            return true
        case 111:
            onVolumeUp()
            return true
        default:
            return false
        }
    }

    private func handleMediaKey(_ event: NSEvent) -> Bool {
        guard event.subtype.rawValue == 8 else {
            return false
        }

        let keyCode = Int((event.data1 & 0xFFFF0000) >> 16)
        let keyFlags = Int(event.data1 & 0x0000FFFF)
        let keyState = (keyFlags & 0xFF00) >> 8
        guard keyState == 0x0A else {
            return false
        }

        switch keyCode {
        case 7:
            onMute()
            return true
        case 1:
            onVolumeDown()
            return true
        case 0:
            onVolumeUp()
            return true
        default:
            return false
        }
    }

    private func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

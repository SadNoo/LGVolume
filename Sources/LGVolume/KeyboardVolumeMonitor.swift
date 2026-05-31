import AppKit
import ApplicationServices
import Carbon.HIToolbox

final class KeyboardVolumeMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var eventHandlerRef: EventHandlerRef?
    private var activeHDMIShortcuts: [KeyboardShortcut?] = []
    private let onVolumeDown: () -> Void
    private let onVolumeUp: () -> Void
    private let onMute: () -> Void
    private let hdmiShortcuts: () -> [KeyboardShortcut?]
    private let onHDMIShortcut: (Int) -> Void
    private let shouldPromptForAccessibility: () -> Bool
    private let markAccessibilityPromptShown: () -> Void

    init(
        onVolumeDown: @escaping () -> Void,
        onVolumeUp: @escaping () -> Void,
        onMute: @escaping () -> Void,
        hdmiShortcuts: @escaping () -> [KeyboardShortcut?],
        onHDMIShortcut: @escaping (Int) -> Void,
        shouldPromptForAccessibility: @escaping () -> Bool,
        markAccessibilityPromptShown: @escaping () -> Void
    ) {
        self.onVolumeDown = onVolumeDown
        self.onVolumeUp = onVolumeUp
        self.onMute = onMute
        self.hdmiShortcuts = hdmiShortcuts
        self.onHDMIShortcut = onHDMIShortcut
        self.shouldPromptForAccessibility = shouldPromptForAccessibility
        self.markAccessibilityPromptShown = markAccessibilityPromptShown
    }

    func start() {
        requestAccessibilityPermission()
        installHotKeyHandler()
        updateHDMIShortcuts(hdmiShortcuts())

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

    func updateHDMIShortcuts(_ shortcuts: [KeyboardShortcut?]) {
        activeHDMIShortcuts = Array(shortcuts.prefix(4))
        while activeHDMIShortcuts.count < 4 {
            activeHDMIShortcuts.append(nil)
        }

        unregisterHDMIHotKeys()
        hotKeyRefs = Array(repeating: nil, count: activeHDMIShortcuts.count)

        for (offset, shortcut) in activeHDMIShortcuts.enumerated() {
            guard let shortcut else {
                continue
            }

            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: UInt32(offset + 1))
            let status = RegisterEventHotKey(
                UInt32(shortcut.keyCode),
                shortcut.carbonModifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )
            if status == noErr {
                hotKeyRefs[offset] = hotKeyRef
            }
        }
    }

    deinit {
        unregisterHDMIHotKeys()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        if event.type == .systemDefined {
            return handleMediaKey(event)
        }

        for (offset, shortcut) in activeHDMIShortcuts.enumerated() {
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
        guard !AXIsProcessTrusted() else {
            return
        }
        guard shouldPromptForAccessibility() else {
            return
        }

        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        markAccessibilityPromptShown()
    }

    private func installHotKeyHandler() {
        guard eventHandlerRef == nil else {
            return
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return noErr
                }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr, hotKeyID.signature == KeyboardVolumeMonitor.hotKeySignature else {
                    return noErr
                }

                let monitor = Unmanaged<KeyboardVolumeMonitor>.fromOpaque(userData).takeUnretainedValue()
                monitor.handleHDMIHotKey(id: hotKeyID.id)
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandlerRef
        )
    }

    private func handleHDMIHotKey(id: UInt32) {
        guard (1...4).contains(Int(id)) else {
            return
        }
        DispatchQueue.main.async {
            self.onHDMIShortcut(Int(id))
        }
    }

    private func unregisterHDMIHotKeys() {
        for hotKeyRef in hotKeyRefs {
            if let hotKeyRef {
                UnregisterEventHotKey(hotKeyRef)
            }
        }
        hotKeyRefs.removeAll()
    }

    private static let hotKeySignature: OSType = {
        let scalars = Array("LGVH".unicodeScalars)
        return scalars.reduce(0) { ($0 << 8) + OSType($1.value) }
    }()
}

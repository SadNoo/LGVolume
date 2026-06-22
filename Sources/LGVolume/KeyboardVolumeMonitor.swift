import AppKit
import Carbon.HIToolbox

final class KeyboardVolumeMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var volumeHotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?
    private var activeHDMIShortcuts: [KeyboardShortcut?] = []
    private var lastHDMITriggerTime = Date.distantPast
    private let onVolumeDown: () -> Void
    private let onVolumeUp: () -> Void
    private let onMute: () -> Void
    private let hdmiShortcuts: () -> [KeyboardShortcut?]
    private let onHDMIShortcut: (Int) -> Void
    private let onShortcutRegistrationChanged: ([Bool]) -> Void

    init(
        onVolumeDown: @escaping () -> Void,
        onVolumeUp: @escaping () -> Void,
        onMute: @escaping () -> Void,
        hdmiShortcuts: @escaping () -> [KeyboardShortcut?],
        onHDMIShortcut: @escaping (Int) -> Void,
        onShortcutRegistrationChanged: @escaping ([Bool]) -> Void
    ) {
        self.onVolumeDown = onVolumeDown
        self.onVolumeUp = onVolumeUp
        self.onMute = onMute
        self.hdmiShortcuts = hdmiShortcuts
        self.onHDMIShortcut = onHDMIShortcut
        self.onShortcutRegistrationChanged = onShortcutRegistrationChanged
    }

    func start() {
        guard globalMonitor == nil, localMonitor == nil else {
            return
        }
        installHotKeyHandler()
        registerVolumeHotKeys()
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
        unregisterVolumeHotKeys()
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

        let states = activeHDMIShortcuts.enumerated().map { offset, shortcut in
            shortcut == nil || hotKeyRefs[offset] != nil
        }
        onShortcutRegistrationChanged(states)
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
            if hotKeyRefs.indices.contains(offset), hotKeyRefs[offset] != nil {
                continue
            }
            guard let shortcut, shortcut.matches(event) else {
                continue
            }
            if event.isARepeat {
                return true
            }
            onHDMIShortcut(offset + 1)
            return true
        }

        let commandModifiers = event.modifierFlags.intersection([.command, .option, .control])
        guard commandModifiers.isEmpty else {
            return false
        }

        switch event.keyCode {
        case 109:
            if event.isARepeat {
                return true
            }
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
                monitor.handleRegisteredHotKey(id: hotKeyID.id)
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandlerRef
        )
    }

    private func handleRegisteredHotKey(id: UInt32) {
        switch id {
        case 10:
            DispatchQueue.main.async { self.onMute() }
            return
        case 11:
            DispatchQueue.main.async { self.onVolumeDown() }
            return
        case 12:
            DispatchQueue.main.async { self.onVolumeUp() }
            return
        default:
            break
        }
        guard (1...4).contains(Int(id)) else { return }
        let now = Date()
        guard now.timeIntervalSince(lastHDMITriggerTime) >= 0.25 else {
            return
        }
        lastHDMITriggerTime = now
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

    private func registerVolumeHotKeys() {
        unregisterVolumeHotKeys()
        for (id, keyCode) in [(10, 109), (11, 103), (12, 111)] {
            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: UInt32(id))
            if RegisterEventHotKey(
                UInt32(keyCode),
                0,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            ) == noErr, let hotKeyRef {
                volumeHotKeyRefs.append(hotKeyRef)
            }
        }
    }

    private func unregisterVolumeHotKeys() {
        for hotKeyRef in volumeHotKeyRefs {
            UnregisterEventHotKey(hotKeyRef)
        }
        volumeHotKeyRefs.removeAll()
    }

    private static let hotKeySignature: OSType = {
        let scalars = Array("LGVH".unicodeScalars)
        return scalars.reduce(0) { ($0 << 8) + OSType($1.value) }
    }()
}

import AppKit
import Carbon.HIToolbox

final class KeyboardVolumeMonitor: @unchecked Sendable {
    private enum VolumeAction {
        case mute
        case down
        case up
    }

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var volumeHotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?
    private var activeHDMIShortcuts: [KeyboardShortcut?] = []
    private var lastHDMITriggerTime = Date.distantPast
    private var lastVolumeTrigger: (action: VolumeAction, time: Date)?
    private var isStarted = false
    private let onVolumeDown: @MainActor () -> Void
    private let onVolumeUp: @MainActor () -> Void
    private let onMute: @MainActor () -> Void
    private let hdmiShortcuts: () -> [KeyboardShortcut?]
    private let onHDMIShortcut: @MainActor (Int) -> Void
    private let onShortcutRegistrationChanged: @MainActor ([Bool]) -> Void

    init(
        onVolumeDown: @escaping @MainActor () -> Void,
        onVolumeUp: @escaping @MainActor () -> Void,
        onMute: @escaping @MainActor () -> Void,
        hdmiShortcuts: @escaping () -> [KeyboardShortcut?],
        onHDMIShortcut: @escaping @MainActor (Int) -> Void,
        onShortcutRegistrationChanged: @escaping @MainActor ([Bool]) -> Void
    ) {
        self.onVolumeDown = onVolumeDown
        self.onVolumeUp = onVolumeUp
        self.onMute = onMute
        self.hdmiShortcuts = hdmiShortcuts
        self.onHDMIShortcut = onHDMIShortcut
        self.onShortcutRegistrationChanged = onShortcutRegistrationChanged
    }

    func start() {
        guard !isStarted else {
            return
        }
        isStarted = true
        installHotKeyHandler()
        registerVolumeHotKeys()
        updateHDMIShortcuts(hdmiShortcuts())
        installVolumeEventMonitors()
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

        let states = activeHDMIShortcuts.enumerated().map { offset, shortcut in
            shortcut == nil || hotKeyRefs[offset] != nil
        }
        Task { @MainActor in
            onShortcutRegistrationChanged(states)
        }
    }

    deinit {
        unregisterHDMIHotKeys()
        unregisterVolumeHotKeys()
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
                Task { @MainActor in
                    monitor.handleRegisteredHotKey(id: hotKeyID.id)
                }
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandlerRef
        )
    }

    @MainActor
    private func handleRegisteredHotKey(id: UInt32) {
        switch id {
        case 10:
            triggerVolumeAction(.mute)
            return
        case 11:
            triggerVolumeAction(.down)
            return
        case 12:
            triggerVolumeAction(.up)
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
        onHDMIShortcut(Int(id))
    }

    private func installVolumeEventMonitors() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .systemDefined]) { [weak self] event in
            if self?.handleVolumeEvent(event) == true {
                return nil
            }
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .systemDefined]) { [weak self] event in
            _ = self?.handleVolumeEvent(event)
        }
    }

    private func handleVolumeEvent(_ event: NSEvent) -> Bool {
        if event.type == .systemDefined {
            return handleMediaKey(event)
        }

        guard event.type == .keyDown else {
            return false
        }

        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard modifiers.isEmpty else {
            return false
        }

        switch event.keyCode {
        case Self.f10KeyCode:
            if event.isARepeat {
                return true
            }
            Task { @MainActor in self.triggerVolumeAction(.mute) }
            return true
        case Self.f11KeyCode:
            Task { @MainActor in self.triggerVolumeAction(.down) }
            return true
        case Self.f12KeyCode:
            Task { @MainActor in self.triggerVolumeAction(.up) }
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
        case Self.mediaMuteKeyCode:
            Task { @MainActor in self.triggerVolumeAction(.mute) }
            return true
        case Self.mediaVolumeDownKeyCode:
            Task { @MainActor in self.triggerVolumeAction(.down) }
            return true
        case Self.mediaVolumeUpKeyCode:
            Task { @MainActor in self.triggerVolumeAction(.up) }
            return true
        default:
            return false
        }
    }

    @MainActor
    private func triggerVolumeAction(_ action: VolumeAction) {
        let now = Date()
        if let lastVolumeTrigger,
           lastVolumeTrigger.action == action,
           now.timeIntervalSince(lastVolumeTrigger.time) < 0.05 {
            return
        }
        lastVolumeTrigger = (action, now)

        switch action {
        case .mute:
            onMute()
        case .down:
            onVolumeDown()
        case .up:
            onVolumeUp()
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
        for (id, keyCode) in [(10, Self.f10KeyCode), (11, Self.f11KeyCode), (12, Self.f12KeyCode)] {
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
    private static let f10KeyCode: UInt16 = 109
    private static let f11KeyCode: UInt16 = 103
    private static let f12KeyCode: UInt16 = 111
    private static let mediaVolumeUpKeyCode = 0
    private static let mediaVolumeDownKeyCode = 1
    private static let mediaMuteKeyCode = 7
}

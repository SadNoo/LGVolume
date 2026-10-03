import CoreAudio
import Foundation

/// Watches the Mac's default sound output and reports whether it is the LG TV, so the volume
/// keys only control the TV while the Mac's sound actually goes to it (headphones or other
/// speakers keep the normal Mac volume keys).
@MainActor
final class AudioOutputMonitor {
    private let onChange: (Bool) -> Void
    private var listener: AudioObjectPropertyListenerBlock?
    private(set) var isTVOutput = false
    private(set) var outputName = ""

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard listener == nil else { return }
        var address = Self.defaultOutputAddress
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
        listener = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        refresh()
    }

    func refresh() {
        let device = Self.defaultOutputDevice()
        let name = device.map(Self.name(of:)) ?? ""
        let transport = device.map(Self.transportType(of:)) ?? 0
        let isTV = Self.isTVOutput(name: name, transport: transport)
        outputName = name
        guard isTV != isTVOutput else { return }
        isTVOutput = isTV
        onChange(isTV)
    }

    /// HDMI or DisplayPort audio is the display's own audio (the TV); an LG-named device is too.
    nonisolated static func isTVOutput(name: String, transport: UInt32) -> Bool {
        transport == kAudioDeviceTransportTypeHDMI
            || transport == kAudioDeviceTransportTypeDisplayPort
            || name.range(of: "LG", options: [.caseInsensitive]) != nil
    }

    private static var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var address = defaultOutputAddress
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != 0 ? device : nil
    }

    private static func name(of device: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr, let name else {
            return ""
        }
        return name.takeRetainedValue() as String
    }

    private static func transportType(of device: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr ? transport : 0
    }
}

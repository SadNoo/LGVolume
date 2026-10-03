import Foundation

/// What the Mac's picture goes to. A TV (like an LG C2) has its own inputs and power, and
/// switching its input briefly interrupts the Mac's video, so it is handled differently from a
/// monitor that only shows the Mac.
enum DeviceKind: String {
    case tv
    case monitor
}

/// The user's choice in Settings: follow what macOS reports, or force one kind.
enum DeviceKindMode: String, CaseIterable {
    case auto
    case tv
    case monitor

    static let defaultMode: DeviceKindMode = .auto
}

/// Reads whether macOS reports the connected LG display as a television, using the same data
/// as System Information ("Television: Yes"). Runs `system_profiler`, which needs no privileges.
enum DeviceKindDetector {
    static let lgVendorID = "1e6d"

    static func detect(completion: @escaping @Sendable (DeviceKind?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPDisplaysDataType", "-json"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                completion(nil)
                return
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            completion(kind(fromSystemProfilerJSON: data))
        }
    }

    /// The kind of the first LG display (vendor 1e6d), or of the only display if none is LG.
    static func kind(fromSystemProfilerJSON data: Data) -> DeviceKind? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let gpus = root["SPDisplaysDataType"] as? [[String: Any]] else {
            return nil
        }
        let displays = gpus.flatMap { $0["spdisplays_ndrvs"] as? [[String: Any]] ?? [] }
        let chosen = displays.first { ($0["_spdisplays_display-vendor-id"] as? String)?.lowercased() == lgVendorID }
            ?? (displays.count == 1 ? displays.first : nil)
        guard let chosen else { return nil }
        return chosen["spdisplays_television"] as? String == "spdisplays_yes" ? .tv : .monitor
    }
}

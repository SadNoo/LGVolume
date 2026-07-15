import Foundation

struct TVVolumeStatus: Equatable {
    let volume: Int
    let muted: Bool?
}

enum WebOSResponseParser {
    static func volumeStatus(_ payload: [String: Any]) -> TVVolumeStatus? {
        let volumeStatus = payload["volumeStatus"] as? [String: Any]
        let source = volumeStatus ?? payload
        let volume = source["volume"] as? Int
            ?? (source["volume"] as? Double).map { Int($0.rounded()) }
            ?? Int(source["volume"] as? String ?? "")
        guard let volume else { return nil }
        let muted = source["muted"] as? Bool
            ?? source["mute"] as? Bool
            ?? source["muteStatus"] as? Bool
        return TVVolumeStatus(volume: min(max(volume, 0), 100), muted: muted)
    }

    static func muteStatus(_ payload: [String: Any]) -> Bool? {
        let source = payload["volumeStatus"] as? [String: Any] ?? payload
        return source["mute"] as? Bool
            ?? source["muted"] as? Bool
            ?? source["muteStatus"] as? Bool
    }

    static func externalInputs(_ payload: [String: Any]) -> [TVExternalInput] {
        let rawDevices = payload["devices"] as? [[String: Any]]
            ?? payload["inputs"] as? [[String: Any]]
            ?? []
        return rawDevices.compactMap { device in
            guard let id = device["id"] as? String, !id.isEmpty else { return nil }
            let port = device["port"] as? Int
                ?? (device["port"] as? NSNumber)?.intValue
                ?? Int(device["port"] as? String ?? "")
            return TVExternalInput(
                id: id,
                label: (device["label"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? id,
                appID: device["appId"] as? String ?? "",
                port: port,
                connected: device["connected"] as? Bool
            )
        }
    }

    static func soundOutput(_ payload: [String: Any]) -> String? {
        payload["soundOutput"] as? String
            ?? (payload["soundOutputStatus"] as? [String: Any])?["soundOutput"] as? String
            ?? payload["output"] as? String
    }

    static func hdmiIndex(in value: String) -> Int? {
        let lower = value.lowercased()
        return (1...4).first { lower.contains("hdmi\($0)") || lower.contains("hdmi_\($0)") }
    }
}

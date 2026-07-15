import Foundation

struct TVExternalInput: Identifiable, Equatable {
    let id: String
    let label: String
    let appID: String
    let port: Int?
    let connected: Bool?

    var hdmiIndex: Int? {
        if let port, (1...4).contains(port) {
            return port
        }

        let candidates = [id, appID, label].map { $0.lowercased() }
        return (1...4).first { index in
            candidates.contains { value in
                value.contains("hdmi_\(index)")
                    || value.contains("hdmi\(index)")
                    || value.contains("hdmi \(index)")
            }
        }
    }
}

struct TVSoundOutputOption: Identifiable, Equatable {
    let id: String
    let titleKey: L10n.Key?
    let fallbackTitle: String

    init(id: String, titleKey: L10n.Key, fallbackTitle: String = "") {
        self.id = id
        self.titleKey = titleKey
        self.fallbackTitle = fallbackTitle
    }

    init(id: String, fallbackTitle: String) {
        self.id = id
        self.titleKey = nil
        self.fallbackTitle = fallbackTitle
    }

    static let common: [TVSoundOutputOption] = [
        TVSoundOutputOption(id: "tv_speaker", titleKey: .soundOutputTVSpeaker),
        TVSoundOutputOption(id: "external_arc", titleKey: .soundOutputARC),
        TVSoundOutputOption(id: "external_optical", titleKey: .soundOutputOptical),
        TVSoundOutputOption(id: "bt_soundbar", titleKey: .soundOutputBluetooth)
    ]
}

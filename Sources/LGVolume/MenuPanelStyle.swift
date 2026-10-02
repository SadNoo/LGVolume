import CoreGraphics

/// The layouts available for the menu bar panel; chosen in Preferences.
enum MenuPanelStyle: String, CaseIterable, Identifiable {
    case cards
    case native
    case controlCenter
    case compact
    case remote
    case classic

    static let defaultStyle: MenuPanelStyle = .cards

    var id: String { rawValue }

    var titleKey: L10n.Key {
        switch self {
        case .cards: return .menuStyleCards
        case .native: return .menuStyleNative
        case .controlCenter: return .menuStyleControlCenter
        case .compact: return .menuStyleCompact
        case .remote: return .menuStyleRemote
        case .classic: return .menuStyleClassic
        }
    }

    var width: CGFloat {
        switch self {
        case .cards, .native: return 300
        case .controlCenter: return 320
        case .compact: return 252
        case .remote: return 304
        case .classic: return 220
        }
    }
}

/// Picks an SF Symbol for an HDMI input from what the TV reports and the user's names.
enum InputSymbol {
    static func name(isMac: Bool, label: String, tvIconName: String?) -> String {
        if isMac {
            return "macmini"
        }
        let haystack = "\(label) \(tvIconName ?? "")".lowercased()
        let rules: [([String], String)] = [
            (["switch", "nintendo", "playstation", "ps4", "ps5", "xbox", "game", "console", "游戏"], "gamecontroller"),
            (["apple tv", "appletv"], "appletv"),
            (["mac", "pc", "computer", "laptop", "电脑"], "desktopcomputer"),
            (["soundbar", "speaker", "receiver", "avr", "音箱", "功放"], "hifispeaker"),
            (["blu", "dvd", "disc", "光盘"], "opticaldisc"),
            (["camera", "camcorder"], "camera"),
            (["stb", "settop", "set-top", "box", "chromecast", "fire", "shield", "roku", "盒子"], "tv.and.mediabox")
        ]
        for (keywords, symbol) in rules where keywords.contains(where: haystack.contains) {
            return symbol
        }
        return "rectangle.connected.to.line.below"
    }
}

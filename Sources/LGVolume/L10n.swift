import Foundation

enum L10n {
    enum Key {
        case appearance
        case auto
        case chinese
        case connected
        case connectPrompt
        case connection
        case connectionHelp
        case currentDisconnected
        case dark
        case disconnect
        case disconnected
        case displayName
        case edit
        case english
        case general
        case generalSubtitle
        case hdmi
        case hdmiShortcut1
        case hdmiShortcut2
        case hdmiShortcut3
        case hdmiShortcut4
        case hide
        case inputIP
        case invalidIP
        case japanese
        case language
        case launch
        case launchAtLogin
        case light
        case matchStatus
        case matched
        case misc
        case muted
        case noMatched
        case notSet
        case pairConnect
        case preferences
        case quit
        case restoreHDMIShortcuts
        case save
        case saveSuccess
        case scanNetwork
        case settings
        case shortcuts
        case shortcutsEnabled
        case shortcutsSummary
        case startPairing
        case syncVolume
        case syncedVolume
        case turnMuteOff
        case turnMuteOn
        case volume
    }

    static func text(_ key: Key, languageMode: String) -> String {
        let language = resolvedLanguage(from: languageMode)
        switch language {
        case "en":
            return english[key] ?? simplifiedChinese[key] ?? ""
        case "ja":
            return japanese[key] ?? simplifiedChinese[key] ?? ""
        default:
            return simplifiedChinese[key] ?? ""
        }
    }

    static func resolvedLanguage(from mode: String) -> String {
        if ["zh-Hans", "en", "ja"].contains(mode) {
            return mode
        }

        let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
        if preferred.hasPrefix("ja") {
            return "ja"
        }
        if preferred.hasPrefix("en") {
            return "en"
        }
        return "zh-Hans"
    }

    private static let simplifiedChinese: [Key: String] = [
        .appearance: "外观：",
        .auto: "自动",
        .chinese: "中文",
        .connected: "已连接",
        .connectPrompt: "正在连接，请在电视上允许配对...",
        .connection: "连接",
        .connectionHelp: "配置电视 IP 和显示名称，连接成功后会保存授权。",
        .currentDisconnected: "当前未连接",
        .dark: "深色",
        .disconnect: "断开",
        .disconnected: "已断开",
        .displayName: "显示名称：",
        .edit: "编辑...",
        .english: "English",
        .general: "通用",
        .generalSubtitle: "在这里配置局域网内的 LG 电视连接、HDMI 输入和全局音量快捷键。",
        .hdmi: "HDMI 输入",
        .hdmiShortcut1: "HDMI1 快捷键：",
        .hdmiShortcut2: "HDMI2 快捷键：",
        .hdmiShortcut3: "HDMI3 快捷键：",
        .hdmiShortcut4: "HDMI4 快捷键：",
        .hide: "收起",
        .inputIP: "例如：192.168.1.23",
        .invalidIP: "IP 格式可能不正确",
        .japanese: "日本語",
        .language: "语言：",
        .launch: "启动：",
        .launchAtLogin: "登录时自动启动 LGVolume",
        .light: "浅色",
        .matchStatus: "匹配状态：",
        .matched: "已匹配成功",
        .misc: "杂项",
        .muted: "静音",
        .noMatched: "未匹配",
        .notSet: "未设置",
        .pairConnect: "配对/连接",
        .preferences: "偏好设置",
        .quit: "退出",
        .restoreHDMIShortcuts: "恢复 HDMI 快捷键",
        .save: "保存",
        .saveSuccess: "保存成功",
        .scanNetwork: "正在扫描 LG webOS 电视...",
        .settings: "设置",
        .shortcuts: "快捷键",
        .shortcutsEnabled: "已启用",
        .shortcutsSummary: "快捷键：F10 静音 / F11 减小音量 / F12 增加音量",
        .startPairing: "正在连接",
        .syncVolume: "同步音量",
        .syncedVolume: "已同步音量：",
        .turnMuteOff: "取消静音",
        .turnMuteOn: "静音",
        .volume: "音量"
    ]

    private static let english: [Key: String] = [
        .appearance: "Appearance:",
        .auto: "Auto",
        .chinese: "中文",
        .connected: "Connected",
        .connectPrompt: "Connecting. Allow pairing on your TV...",
        .connection: "Connection",
        .connectionHelp: "Set the TV IP and display name. Authorization is saved after pairing.",
        .currentDisconnected: "Not connected",
        .dark: "Dark",
        .disconnect: "Disconnect",
        .disconnected: "Disconnected",
        .displayName: "Display name:",
        .edit: "Edit...",
        .english: "English",
        .general: "General",
        .generalSubtitle: "Configure local LG TV connection, HDMI inputs, and global volume shortcuts.",
        .hdmi: "HDMI Inputs",
        .hdmiShortcut1: "HDMI1 shortcut:",
        .hdmiShortcut2: "HDMI2 shortcut:",
        .hdmiShortcut3: "HDMI3 shortcut:",
        .hdmiShortcut4: "HDMI4 shortcut:",
        .hide: "Hide",
        .inputIP: "Example: 192.168.1.23",
        .invalidIP: "The IP address may be invalid",
        .japanese: "日本語",
        .language: "Language:",
        .launch: "Launch:",
        .launchAtLogin: "Launch LGVolume at login",
        .light: "Light",
        .matchStatus: "Pairing:",
        .matched: "Paired",
        .misc: "Misc",
        .muted: "Muted",
        .noMatched: "Not paired",
        .notSet: "Not set",
        .pairConnect: "Pair / Connect",
        .preferences: "Preferences",
        .quit: "Quit",
        .restoreHDMIShortcuts: "Restore HDMI Shortcuts",
        .save: "Save",
        .saveSuccess: "Saved",
        .scanNetwork: "Scanning for LG webOS TV...",
        .settings: "Settings",
        .shortcuts: "Shortcuts",
        .shortcutsEnabled: "Enabled",
        .shortcutsSummary: "Shortcuts: F10 mute / F11 volume down / F12 volume up",
        .startPairing: "Connecting",
        .syncVolume: "Sync Volume",
        .syncedVolume: "Synced volume:",
        .turnMuteOff: "Unmute",
        .turnMuteOn: "Mute",
        .volume: "Volume"
    ]

    private static let japanese: [Key: String] = [
        .appearance: "外観：",
        .auto: "自動",
        .chinese: "中文",
        .connected: "接続済み",
        .connectPrompt: "接続中です。テレビ側でペアリングを許可してください...",
        .connection: "接続",
        .connectionHelp: "テレビの IP と表示名を設定します。ペアリング後に認証情報が保存されます。",
        .currentDisconnected: "未接続",
        .dark: "ダーク",
        .disconnect: "切断",
        .disconnected: "切断しました",
        .displayName: "表示名：",
        .edit: "編集...",
        .english: "English",
        .general: "一般",
        .generalSubtitle: "ローカルネットワーク内の LG TV 接続、HDMI 入力、グローバル音量ショートカットを設定します。",
        .hdmi: "HDMI 入力",
        .hdmiShortcut1: "HDMI1 ショートカット：",
        .hdmiShortcut2: "HDMI2 ショートカット：",
        .hdmiShortcut3: "HDMI3 ショートカット：",
        .hdmiShortcut4: "HDMI4 ショートカット：",
        .hide: "閉じる",
        .inputIP: "例：192.168.1.23",
        .invalidIP: "IP アドレスの形式を確認してください",
        .japanese: "日本語",
        .language: "言語：",
        .launch: "起動：",
        .launchAtLogin: "ログイン時に LGVolume を起動",
        .light: "ライト",
        .matchStatus: "ペアリング：",
        .matched: "ペアリング済み",
        .misc: "その他",
        .muted: "ミュート",
        .noMatched: "未ペアリング",
        .notSet: "未設定",
        .pairConnect: "ペアリング / 接続",
        .preferences: "環境設定",
        .quit: "終了",
        .restoreHDMIShortcuts: "HDMI ショートカットを復元",
        .save: "保存",
        .saveSuccess: "保存しました",
        .scanNetwork: "LG webOS TV をスキャン中...",
        .settings: "設定",
        .shortcuts: "ショートカット",
        .shortcutsEnabled: "有効",
        .shortcutsSummary: "ショートカット：F10 ミュート / F11 音量ダウン / F12 音量アップ",
        .startPairing: "接続中",
        .syncVolume: "音量を同期",
        .syncedVolume: "同期済み音量：",
        .turnMuteOff: "ミュート解除",
        .turnMuteOn: "ミュート",
        .volume: "音量"
    ]
}

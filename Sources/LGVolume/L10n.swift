import Foundation

enum L10n {
    enum Key: CaseIterable {
        case appearance
        case auto
        case chinese
        case commandRejected
        case certificateChanged
        case certificateSaveFailed
        case connected
        case connectPrompt
        case connection
        case connectionHelp
        case currentDisconnected
        case dark
        case disconnect
        case disconnected
        case displayName
        case detectedInputs
        case diagnostics
        case edit
        case english
        case externalInputsReadFailed
        case general
        case generalSubtitle
        case hdmiSubtitle
        case hdmi
        case hdmiShortcut1
        case hdmiShortcut2
        case hdmiShortcut3
        case hdmiShortcut4
        case hide
        case inputIP
        case inputNames
        case invalidIP
        case invalidIPAddress
        case japanese
        case language
        case launch
        case launchAtLogin
        case launchRequiresApproval
        case light
        case localNetworkOnly
        case matchStatus
        case matched
        case misc
        case muted
        case noMatched
        case noInputsDetected
        case openDiagnostics
        case notConnected
        case notSet
        case pairingFailed
        case pairingResponseInvalid
        case pairingTimeout
        case pairingTokenSaveFailed
        case pairConnect
        case preferences
        case pressShortcut
        case quit
        case requestTimedOut
        case repairPairing
        case restoreHDMIShortcuts
        case save
        case saveSuccess
        case scanNetwork
        case settings
        case secureConnectionOnly
        case sendFailed
        case shortcuts
        case shortcutsEnabled
        case shortcutsUnavailable
        case shortcutNeedsModifier
        case shortcutsSummary
        case shortcutsSubtitle
        case startPairing
        case soundOutput
        case soundOutputARC
        case soundOutputBluetooth
        case soundOutputOptical
        case soundOutputReadFailed
        case soundOutputTVSpeaker
        case syncVolume
        case syncedVolume
        case turnMuteOff
        case turnMuteOn
        case tvNoResponse
        case useTVInputNames
        case volume
        case volumeReadFailed
        case volumeNotApplied
        case preferencesSubtitle
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
        .commandRejected: "电视拒绝了命令。",
        .certificateChanged: "电视的安全证书已更改。为防止连接到错误设备，已停止连接；请确认电视 IP 后点击“重新配对”。",
        .certificateSaveFailed: "无法保存电视安全证书信息，请检查应用偏好设置权限。",
        .connected: "已连接",
        .connectPrompt: "正在连接，请在电视上允许配对...",
        .connection: "连接",
        .connectionHelp: "配置电视 IP 和显示名称，连接成功后会保存授权。",
        .currentDisconnected: "当前未连接",
        .dark: "深色",
        .disconnect: "断开",
        .disconnected: "已断开",
        .displayName: "显示名称：",
        .detectedInputs: "电视返回：",
        .diagnostics: "诊断：",
        .edit: "编辑...",
        .english: "English",
        .externalInputsReadFailed: "无法读取电视的外部输入列表。",
        .general: "通用",
        .generalSubtitle: "配置局域网内的 LG 电视连接并查看实时音量状态。",
        .hdmiSubtitle: "使用电视返回的输入名称，或编辑菜单中显示的四个 HDMI 名称。",
        .hdmi: "HDMI 输入",
        .hdmiShortcut1: "HDMI1 快捷键：",
        .hdmiShortcut2: "HDMI2 快捷键：",
        .hdmiShortcut3: "HDMI3 快捷键：",
        .hdmiShortcut4: "HDMI4 快捷键：",
        .hide: "收起",
        .inputIP: "例如：192.168.1.23",
        .inputNames: "名称来源：",
        .invalidIP: "IP 格式可能不正确",
        .invalidIPAddress: "IP 地址无效",
        .japanese: "日本語",
        .language: "语言：",
        .launch: "启动：",
        .launchAtLogin: "登录时自动启动 LGVolume",
        .launchRequiresApproval: "请在系统设置中允许 LGVolume 登录时启动。",
        .light: "浅色",
        .localNetworkOnly: "为保护隐私，LGVolume 仅允许连接局域网 IPv4 地址，例如 192.168.x.x、10.x.x.x 或 172.16-31.x.x。",
        .matchStatus: "匹配状态：",
        .matched: "已匹配成功",
        .misc: "杂项",
        .muted: "静音",
        .noMatched: "未匹配",
        .noInputsDetected: "连接电视后将显示检测到的 HDMI 名称。",
        .openDiagnostics: "在访达中显示日志",
        .notConnected: "尚未连接电视。",
        .notSet: "未设置",
        .pairingFailed: "配对失败，请在电视上允许 LGVolume。",
        .pairingResponseInvalid: "电视返回了无法解析的配对响应。",
        .pairingTimeout: "等待电视授权超时，请重新连接并在电视弹窗中选择允许。",
        .pairingTokenSaveFailed: "电视已连接，但授权信息无法保存到应用支持目录。",
        .pairConnect: "配对/连接",
        .preferences: "偏好设置",
        .pressShortcut: "按下快捷键",
        .quit: "退出",
        .requestTimedOut: "电视没有在规定时间内响应。",
        .repairPairing: "重新配对",
        .restoreHDMIShortcuts: "恢复 HDMI 快捷键",
        .save: "保存",
        .saveSuccess: "保存成功",
        .scanNetwork: "正在扫描 LG webOS 电视...",
        .settings: "设置",
        .secureConnectionOnly: "仅使用安全连接（WSS）",
        .sendFailed: "命令未能发送到电视。",
        .shortcuts: "快捷键",
        .shortcutsEnabled: "已启用",
        .shortcutsUnavailable: "部分快捷键不可用",
        .shortcutNeedsModifier: "请加入 Command、Option 或 Control",
        .shortcutsSummary: "快捷键：F10 静音 / F11 减小音量 / F12 增加音量",
        .shortcutsSubtitle: "录制 HDMI 全局快捷键；按 Delete 或 Escape 可禁用。",
        .startPairing: "正在连接",
        .soundOutput: "声音输出",
        .soundOutputARC: "HDMI ARC / eARC",
        .soundOutputBluetooth: "蓝牙",
        .soundOutputOptical: "光纤",
        .soundOutputReadFailed: "无法读取电视的声音输出。",
        .soundOutputTVSpeaker: "电视扬声器",
        .syncVolume: "同步音量",
        .syncedVolume: "已同步音量：",
        .turnMuteOff: "取消静音",
        .turnMuteOn: "静音",
        .tvNoResponse: "电视没有响应。请确认电视已开机、Mac 与电视位于同一局域网，并已允许 LGVolume 使用本地网络。",
        .useTVInputNames: "使用电视返回的 HDMI 名称",
        .volume: "音量",
        .volumeReadFailed: "无法读取电视音量。",
        .volumeNotApplied: "电视没有执行音量调整，请查看诊断日志。",
        .preferencesSubtitle: "调整外观、语言和登录启动。"
    ]

    private static let english: [Key: String] = [
        .appearance: "Appearance:",
        .auto: "Auto",
        .chinese: "中文",
        .commandRejected: "The TV rejected the command.",
        .certificateChanged: "The TV security certificate changed. Connection was blocked; verify the TV IP and choose Re-pair.",
        .certificateSaveFailed: "The TV security certificate could not be saved to app preferences.",
        .connected: "Connected",
        .connectPrompt: "Connecting. Allow pairing on your TV...",
        .connection: "Connection",
        .connectionHelp: "Set the TV IP and display name. Authorization is saved after pairing.",
        .currentDisconnected: "Not connected",
        .dark: "Dark",
        .disconnect: "Disconnect",
        .disconnected: "Disconnected",
        .displayName: "Display name:",
        .detectedInputs: "TV reports:",
        .diagnostics: "Diagnostics:",
        .edit: "Edit...",
        .english: "English",
        .externalInputsReadFailed: "Unable to read the TV external input list.",
        .general: "General",
        .generalSubtitle: "Configure the local LG TV connection and view its live volume state.",
        .hdmiSubtitle: "Use TV-provided input names or edit the four HDMI names shown in the menu.",
        .hdmi: "HDMI Inputs",
        .hdmiShortcut1: "HDMI1 shortcut:",
        .hdmiShortcut2: "HDMI2 shortcut:",
        .hdmiShortcut3: "HDMI3 shortcut:",
        .hdmiShortcut4: "HDMI4 shortcut:",
        .hide: "Hide",
        .inputIP: "Example: 192.168.1.23",
        .inputNames: "Name source:",
        .invalidIP: "The IP address may be invalid",
        .invalidIPAddress: "Invalid IP address",
        .japanese: "日本語",
        .language: "Language:",
        .launch: "Launch:",
        .launchAtLogin: "Launch LGVolume at login",
        .launchRequiresApproval: "Allow LGVolume to launch at login in System Settings.",
        .light: "Light",
        .localNetworkOnly: "For privacy, LGVolume only connects to private local-network IPv4 addresses such as 192.168.x.x, 10.x.x.x, or 172.16-31.x.x.",
        .matchStatus: "Pairing:",
        .matched: "Paired",
        .misc: "Misc",
        .muted: "Muted",
        .noMatched: "Not paired",
        .noInputsDetected: "Detected HDMI names appear after the TV connects.",
        .openDiagnostics: "Show Log in Finder",
        .notConnected: "The TV is not connected.",
        .notSet: "Not set",
        .pairingFailed: "Pairing failed. Allow LGVolume on the TV.",
        .pairingResponseInvalid: "The TV returned an invalid pairing response.",
        .pairingTimeout: "TV authorization timed out. Reconnect and choose Allow on the TV.",
        .pairingTokenSaveFailed: "The TV connected, but authorization could not be saved to Application Support.",
        .pairConnect: "Pair / Connect",
        .preferences: "Preferences",
        .pressShortcut: "Press a shortcut",
        .quit: "Quit",
        .requestTimedOut: "The TV did not respond in time.",
        .repairPairing: "Re-pair",
        .restoreHDMIShortcuts: "Restore HDMI Shortcuts",
        .save: "Save",
        .saveSuccess: "Saved",
        .scanNetwork: "Scanning for LG webOS TV...",
        .settings: "Settings",
        .secureConnectionOnly: "Use secure connection only (WSS)",
        .sendFailed: "The command could not be sent to the TV.",
        .shortcuts: "Shortcuts",
        .shortcutsEnabled: "Enabled",
        .shortcutsUnavailable: "Some shortcuts are unavailable",
        .shortcutNeedsModifier: "Add Command, Option, or Control",
        .shortcutsSummary: "Shortcuts: F10 mute / F11 volume down / F12 volume up",
        .shortcutsSubtitle: "Record global HDMI shortcuts; press Delete or Escape to disable one.",
        .startPairing: "Connecting",
        .soundOutput: "Sound Output",
        .soundOutputARC: "HDMI ARC / eARC",
        .soundOutputBluetooth: "Bluetooth",
        .soundOutputOptical: "Optical",
        .soundOutputReadFailed: "Unable to read the TV sound output.",
        .soundOutputTVSpeaker: "TV Speaker",
        .syncVolume: "Sync Volume",
        .syncedVolume: "Synced volume:",
        .turnMuteOff: "Unmute",
        .turnMuteOn: "Mute",
        .tvNoResponse: "The TV did not respond. Make sure it is on, connected to the same local network as the Mac, and that LGVolume has Local Network access.",
        .useTVInputNames: "Use HDMI names reported by the TV",
        .volume: "Volume",
        .volumeReadFailed: "Unable to read the TV volume.",
        .volumeNotApplied: "The TV did not apply the volume change. Check the diagnostics log.",
        .preferencesSubtitle: "Adjust appearance, language, and launch at login."
    ]

    private static let japanese: [Key: String] = [
        .appearance: "外観：",
        .auto: "自動",
        .chinese: "中文",
        .commandRejected: "テレビがコマンドを拒否しました。",
        .certificateChanged: "テレビのセキュリティ証明書が変更されました。接続を停止しました。IP を確認して「再ペアリング」を選択してください。",
        .certificateSaveFailed: "テレビのセキュリティ証明書情報をアプリ設定に保存できませんでした。",
        .connected: "接続済み",
        .connectPrompt: "接続中です。テレビ側でペアリングを許可してください...",
        .connection: "接続",
        .connectionHelp: "テレビの IP と表示名を設定します。ペアリング後に認証情報が保存されます。",
        .currentDisconnected: "未接続",
        .dark: "ダーク",
        .disconnect: "切断",
        .disconnected: "切断しました",
        .displayName: "表示名：",
        .detectedInputs: "テレビの入力名：",
        .diagnostics: "診断：",
        .edit: "編集...",
        .english: "English",
        .externalInputsReadFailed: "テレビの外部入力一覧を取得できませんでした。",
        .general: "一般",
        .generalSubtitle: "ローカル LG TV 接続を設定し、音量状態をリアルタイムで確認します。",
        .hdmiSubtitle: "テレビの入力名を使用するか、メニューに表示する 4 つの HDMI 名を編集します。",
        .hdmi: "HDMI 入力",
        .hdmiShortcut1: "HDMI1 ショートカット：",
        .hdmiShortcut2: "HDMI2 ショートカット：",
        .hdmiShortcut3: "HDMI3 ショートカット：",
        .hdmiShortcut4: "HDMI4 ショートカット：",
        .hide: "閉じる",
        .inputIP: "例：192.168.1.23",
        .inputNames: "名前の取得元：",
        .invalidIP: "IP アドレスの形式を確認してください",
        .invalidIPAddress: "IP アドレスが無効です",
        .japanese: "日本語",
        .language: "言語：",
        .launch: "起動：",
        .launchAtLogin: "ログイン時に LGVolume を起動",
        .launchRequiresApproval: "システム設定で LGVolume のログイン時起動を許可してください。",
        .light: "ライト",
        .localNetworkOnly: "プライバシー保護のため、LGVolume は 192.168.x.x、10.x.x.x、172.16-31.x.x などのローカル IPv4 アドレスにのみ接続します。",
        .matchStatus: "ペアリング：",
        .matched: "ペアリング済み",
        .misc: "その他",
        .muted: "ミュート",
        .noMatched: "未ペアリング",
        .noInputsDetected: "テレビ接続後に検出した HDMI 名が表示されます。",
        .openDiagnostics: "Finder でログを表示",
        .notConnected: "テレビに接続されていません。",
        .notSet: "未設定",
        .pairingFailed: "ペアリングに失敗しました。テレビ側で LGVolume を許可してください。",
        .pairingResponseInvalid: "テレビから無効なペアリング応答が返されました。",
        .pairingTimeout: "テレビの認証がタイムアウトしました。再接続してテレビ側で許可してください。",
        .pairingTokenSaveFailed: "テレビには接続しましたが、認証情報を Application Support に保存できませんでした。",
        .pairConnect: "ペアリング / 接続",
        .preferences: "環境設定",
        .pressShortcut: "ショートカットを入力",
        .quit: "終了",
        .requestTimedOut: "テレビから時間内に応答がありませんでした。",
        .repairPairing: "再ペアリング",
        .restoreHDMIShortcuts: "HDMI ショートカットを復元",
        .save: "保存",
        .saveSuccess: "保存しました",
        .scanNetwork: "LG webOS TV をスキャン中...",
        .settings: "設定",
        .secureConnectionOnly: "安全な接続のみ使用（WSS）",
        .sendFailed: "コマンドをテレビに送信できませんでした。",
        .shortcuts: "ショートカット",
        .shortcutsEnabled: "有効",
        .shortcutsUnavailable: "一部のショートカットは使用できません",
        .shortcutNeedsModifier: "Command、Option、Control のいずれかを追加",
        .shortcutsSummary: "ショートカット：F10 ミュート / F11 音量ダウン / F12 音量アップ",
        .shortcutsSubtitle: "HDMI のグローバルショートカットを記録します。Delete または Escape で無効にできます。",
        .startPairing: "接続中",
        .soundOutput: "音声出力",
        .soundOutputARC: "HDMI ARC / eARC",
        .soundOutputBluetooth: "Bluetooth",
        .soundOutputOptical: "光デジタル",
        .soundOutputReadFailed: "テレビの音声出力を取得できませんでした。",
        .soundOutputTVSpeaker: "テレビスピーカー",
        .syncVolume: "音量を同期",
        .syncedVolume: "同期済み音量：",
        .turnMuteOff: "ミュート解除",
        .turnMuteOn: "ミュート",
        .tvNoResponse: "テレビが応答しません。テレビの電源、Mac と同じローカルネットワークへの接続、および LGVolume のローカルネットワーク権限を確認してください。",
        .useTVInputNames: "テレビから取得した HDMI 名を使用",
        .volume: "音量",
        .volumeReadFailed: "テレビの音量を取得できませんでした。",
        .volumeNotApplied: "テレビで音量変更が実行されませんでした。診断ログを確認してください。",
        .preferencesSubtitle: "外観、言語、ログイン時の起動を設定します。"
    ]
}

# LGVolume

<p align="center">
  <img src="Resources/AppIcon-1024.png" width="144" alt="LGVolume icon">
</p>

<p align="center">
  A native macOS menu bar controller for LG webOS TVs.<br>
  一款通过局域网控制 LG webOS 电视的原生 macOS 菜单栏应用。
</p>

<p align="center">
  <a href="#简体中文">简体中文</a> · <a href="#english">English</a>
</p>

## 简体中文

LGVolume 通过 LG webOS 局域网 API，让 Apple Silicon Mac 可以直接在菜单栏调节电视音量、切换静音和选择 HDMI 输入。应用不会连接外部互联网服务，电视授权信息只保存在本机应用偏好中。

### 功能

- 菜单栏实时显示电视连接状态和音量百分比
- 拖动滑杆直接设置电视音量
- 点击喇叭图标静音或取消静音
- 切换 HDMI 1、HDMI 2、HDMI 3、HDMI 4
- 自动同步当前 HDMI 输入状态
- 自定义电视名称和四个 HDMI 输入名称
- 为每个 HDMI 输入录制或禁用全局快捷键
- `F10` 静音、`F11` 减小音量、`F12` 增加音量
- 登录时自动启动
- 自动、浅色和深色外观
- 简体中文、英语和日语界面

### 权限与隐私

LGVolume 仅接受以下私有或链路本地 IPv4 地址：

- `10.x.x.x`
- `172.16.x.x` 至 `172.31.x.x`
- `192.168.x.x`
- `169.254.x.x`

应用需要 macOS 的“本地网络”权限，用来连接同一局域网中的电视。它不需要辅助功能权限，不访问 macOS 钥匙串，也不会要求管理员密码。

全局快捷键通过 macOS Carbon Hot Key API 注册。若某个组合键已被其他应用占用，设置页会显示“部分快捷键不可用”。

### 首次连接

1. 确认 Mac 和 LG 电视连接到同一个局域网。
2. 在设置页填写电视的局域网 IP。
3. 点击“配对/连接”。
4. 在电视弹出的授权窗口中允许 LGVolume。

电视授权完成后，LGVolume 会在本机保存配对 token。修改电视 IP 会自动断开旧连接并清除旧 token，下一次连接需要在电视上重新允许。

### HDMI 切换

LGVolume 首先调用 webOS `switchInput` 接口；若电视固件拒绝该接口，会自动改用 HDMI 应用启动方式。升级旧版本后如果 HDMI 切换无效，请在设置页断开并重新配对，让电视重新授予 `LAUNCH` 和输入控制权限。

### 快捷键

默认 HDMI 快捷键：

| 输入 | 默认快捷键 |
| --- | --- |
| HDMI 1 | `Control + Option + Command + ←` |
| HDMI 2 | `Control + Option + Command + ↑` |
| HDMI 3 | `Control + Option + Command + ↓` |
| HDMI 4 | `Control + Option + Command + →` |

在快捷键输入框中按下新组合键即可修改；按 `Delete` 或 `Escape` 可禁用该项。普通按键必须搭配 `Command`、`Option` 或 `Control`，避免注册危险的裸键全局快捷键。

### 系统要求

- Apple Silicon Mac
- macOS 14 或更高版本
- 支持局域网控制的 LG webOS 电视

### 安装与构建

从 GitHub Releases 下载 Apple Silicon 版本，将 `LGVolume.app` 移入“应用程序”文件夹。

从源码构建和测试：

```bash
make build
make test
```

构建产物位于 `dist/LGVolume.app`。

Developer ID 签名与 Apple 公证：

```bash
DEVELOPER_ID_APPLICATION="Developer ID Application: ..." make build
NOTARY_PROFILE="LGVolume" ./Scripts/notarize_app.sh
```

### 故障排查

- **电视没有弹出授权：** 检查 IP、本地网络权限以及两台设备是否位于同一局域网，然后再次点击“配对/连接”。
- **HDMI 无法切换：** 断开并重新配对，以更新电视授予的权限。
- **快捷键无效：** 检查设置页状态，并更换与其他应用不冲突的组合键。
- **更换电视或 IP：** 保存新 IP 后重新配对；旧电视 token 会自动失效。

## English

LGVolume uses the local LG webOS API to control TV volume, mute, and HDMI inputs from the macOS menu bar. It never connects to external internet services, and the TV pairing token is stored only in the app's local preferences.

### Features

- Live TV connection state and volume percentage in the menu bar
- Direct percentage-based volume slider
- Mute and unmute from the speaker button
- HDMI 1–4 input switching
- Current HDMI input synchronization
- Custom TV and HDMI display names
- Editable or disabled global shortcuts for every HDMI input
- `F10` mute, `F11` volume down, and `F12` volume up
- Launch at login
- Auto, Light, and Dark appearances
- Simplified Chinese, English, and Japanese interfaces

### Permissions and Privacy

LGVolume only accepts private or link-local IPv4 addresses:

- `10.x.x.x`
- `172.16.x.x` through `172.31.x.x`
- `192.168.x.x`
- `169.254.x.x`

The app needs macOS Local Network permission to reach the TV. It does not require Accessibility permission, does not access the macOS Keychain, and does not request an administrator password.

Global shortcuts use the macOS Carbon Hot Key API. The settings window reports when another application prevents a shortcut from being registered.

### First Connection

1. Connect the Mac and LG TV to the same local network.
2. Enter the TV's local IP address in Settings.
3. Choose Pair / Connect.
4. Approve LGVolume in the authorization prompt shown on the TV.

LGVolume stores the resulting pairing token locally. Changing the TV IP disconnects the previous TV and clears its token, so the new TV must be authorized once.

### HDMI Switching

LGVolume first uses the webOS `switchInput` API and automatically falls back to launching the matching HDMI application when required by the TV firmware. If HDMI switching stops working after upgrading, disconnect and pair again so the TV can grant the updated `LAUNCH` and input-control permissions.

### Shortcuts

Default HDMI shortcuts:

| Input | Default shortcut |
| --- | --- |
| HDMI 1 | `Control + Option + Command + ←` |
| HDMI 2 | `Control + Option + Command + ↑` |
| HDMI 3 | `Control + Option + Command + ↓` |
| HDMI 4 | `Control + Option + Command + →` |

Press a new combination in a shortcut field to replace it. Press `Delete` or `Escape` to disable it. Ordinary keys must include `Command`, `Option`, or `Control` to prevent unsafe unmodified global shortcuts.

### Requirements

- Apple Silicon Mac
- macOS 14 or later
- LG webOS TV with local-network control support

### Install and Build

Download the Apple Silicon build from GitHub Releases and move `LGVolume.app` to Applications.

Build and test from source:

```bash
make build
make test
```

The app bundle is generated at `dist/LGVolume.app`.

Developer ID signing and Apple notarization:

```bash
DEVELOPER_ID_APPLICATION="Developer ID Application: ..." make build
NOTARY_PROFILE="LGVolume" ./Scripts/notarize_app.sh
```

### Troubleshooting

- **No authorization prompt on the TV:** verify the IP address, Local Network permission, and that both devices are on the same network, then pair again.
- **HDMI switching fails:** disconnect and pair again to refresh the TV permissions.
- **A shortcut does not work:** check its status in Settings and choose a combination not used by another application.
- **Changing the TV or IP:** save the new address and pair again; the old TV token is invalidated automatically.

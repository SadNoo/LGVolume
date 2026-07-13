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

LGVolume 通过 LG webOS 局域网 API，让 Apple Silicon Mac 可以在菜单栏查看电视音量、切换静音、切换 HDMI 输入，并使用全局快捷键控制 LG 电视。应用仅面向局域网使用，不连接外部互联网服务；电视授权 token 保存在本机 macOS Keychain 中。

### 当前版本

- 版本：`0.1.6`
- 架构：Apple Silicon / arm64
- 系统：macOS 14 或更高版本
- 电视：支持局域网控制的 LG webOS 电视

### 功能

- 菜单栏弹窗显示电视连接状态、静音状态和音量百分比
- 点击喇叭图标静音或取消静音
- `F10` 静音/取消静音
- `F11` 每次降低 `5%` 音量
- `F12` 每次增加 `5%` 音量
- 通过 LG webOS API 同步电视实际音量，返回小数时四舍五入为整数显示
- 切换 HDMI 1、HDMI 2、HDMI 3、HDMI 4
- 自动同步当前 HDMI 输入状态
- 自定义电视显示名称和四个 HDMI 输入名称
- 为每个 HDMI 输入录制或禁用全局快捷键
- 登录时自动启动
- 可选“仅使用安全连接（WSS）”
- 自动、浅色和深色外观
- 简体中文、英语和日语界面

### 快捷键

默认 HDMI 快捷键：

| 输入 | 默认快捷键 |
| --- | --- |
| HDMI 1 | `Control + Option + Command + ←` |
| HDMI 2 | `Control + Option + Command + ↑` |
| HDMI 3 | `Control + Option + Command + ↓` |
| HDMI 4 | `Control + Option + Command + →` |

在设置页的快捷键输入框中按下新组合键即可修改；按 `Delete` 或 `Escape` 可禁用该项。普通按键必须搭配 `Command`、`Option` 或 `Control`，避免注册危险的裸键全局快捷键。

### 权限与隐私

LGVolume 仅允许连接私有或链路本地 IPv4 地址：

- `10.x.x.x`
- `172.16.x.x` 至 `172.31.x.x`
- `192.168.x.x`
- `169.254.x.x`

应用需要 macOS 的“本地网络”权限，用来连接同一局域网中的电视。`F10`、`F11`、`F12` 在不同键盘和系统设置下可能以媒体键事件形式发出；如果 macOS 请求辅助功能或输入监听相关权限，请允许 LGVolume 后重新打开应用。

LGVolume 使用 macOS Keychain 保存电视授权 token，不要求管理员密码，也不会把电视授权信息上传到外部服务。

### 首次连接

1. 确认 Mac 和 LG 电视连接到同一个局域网。
2. 打开 LGVolume 设置页，填写 `LG TV IP`。
3. 点击“配对/连接”。
4. 在电视弹出的授权窗口中允许 LGVolume。

电视授权完成后，LGVolume 会在本机 Keychain 保存配对 token。修改电视 IP 会自动断开旧连接并清除旧 token，下一次连接需要在电视上重新允许。

### 换电脑使用

当前打包版本可以在其他 Apple Silicon Mac 上运行，但不是免设置迁移：

- 需要在新电脑上重新填写 LG TV IP
- 需要在电视上重新授权配对
- 需要重新允许 macOS 本地网络权限
- 如需全局 `F10/F11/F12`，可能需要重新允许辅助功能或输入监听权限
- 登录启动需要在新电脑上重新开启

当前包为本机 ad-hoc 签名版本，不是 Developer ID 公证版。其他电脑首次打开时，macOS 可能会拦截；可在“系统设置 > 隐私与安全性”中选择仍要打开。

### HDMI 切换

LGVolume 首先调用 webOS `switchInput` 接口；若电视固件拒绝该接口，会自动改用 HDMI 应用启动方式。升级旧版本后如果 HDMI 切换无效，请在设置页断开并重新配对，让电视重新授予 `LAUNCH` 和输入控制权限。

### 安全连接

默认情况下，LGVolume 会优先使用 `wss://电视IP:3001`，如果电视固件不响应，再回退到 `ws://电视IP:3000` 以保持兼容。若只想允许 WSS，可在“杂项”页打开“仅使用安全连接（WSS）”。打开或关闭该选项后，当前连接会断开，下一次连接会使用新的策略。

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
- **音量快捷键无效：** 确认正在运行的是最新版本；检查 macOS 是否要求辅助功能或输入监听权限；也确认键盘是否把 F10/F11/F12 作为媒体键发送。
- **HDMI 无法切换：** 断开并重新配对，以更新电视授予的权限。
- **更换电视或 IP：** 保存新 IP 后重新配对；旧电视 token 会自动失效。

## English

LGVolume uses the local LG webOS API to show TV volume, toggle mute, switch HDMI inputs, and control LG TVs from global shortcuts in the macOS menu bar. It is designed for local-network use only, never connects to external internet services, and stores the TV pairing token in the local macOS Keychain.

### Current Version

- Version: `0.1.6`
- Architecture: Apple Silicon / arm64
- System: macOS 14 or later
- TV: LG webOS TV with local-network control support

### Features

- Menu bar panel with connection state, mute state, and volume percentage
- Speaker button to mute or unmute
- `F10` mute / unmute
- `F11` lowers volume by `5%`
- `F12` raises volume by `5%`
- Volume is synchronized from the LG webOS API; fractional values are rounded to the nearest integer
- HDMI 1-4 input switching
- Current HDMI input synchronization
- Custom TV and HDMI display names
- Editable or disabled global shortcuts for every HDMI input
- Launch at login
- Optional WSS-only secure connection mode
- Auto, Light, and Dark appearances
- Simplified Chinese, English, and Japanese interfaces

### Shortcuts

Default HDMI shortcuts:

| Input | Default shortcut |
| --- | --- |
| HDMI 1 | `Control + Option + Command + ←` |
| HDMI 2 | `Control + Option + Command + ↑` |
| HDMI 3 | `Control + Option + Command + ↓` |
| HDMI 4 | `Control + Option + Command + →` |

Press a new combination in a shortcut field to replace it. Press `Delete` or `Escape` to disable it. Ordinary keys must include `Command`, `Option`, or `Control` to avoid unsafe unmodified global shortcuts.

### Permissions and Privacy

LGVolume only accepts private or link-local IPv4 addresses:

- `10.x.x.x`
- `172.16.x.x` through `172.31.x.x`
- `192.168.x.x`
- `169.254.x.x`

The app needs macOS Local Network permission to reach the TV. Depending on the keyboard and system settings, `F10`, `F11`, and `F12` may arrive as media-key events; if macOS asks for Accessibility or Input Monitoring permission, allow LGVolume and relaunch it.

LGVolume uses the macOS Keychain to store the TV authorization token. It does not request an administrator password and does not upload TV authorization data to external services.

### First Connection

1. Connect the Mac and LG TV to the same local network.
2. Open LGVolume Settings and enter the TV's local IP address.
3. Choose Pair / Connect.
4. Approve LGVolume in the authorization prompt shown on the TV.

LGVolume stores the resulting pairing token in the local Keychain. Changing the TV IP disconnects the previous TV and clears its token, so the new TV must be authorized once.

### Moving to Another Mac

The current package can run on another Apple Silicon Mac, but it is not a zero-setup migration:

- Enter the LG TV IP again on the new Mac
- Pair with the TV again
- Allow macOS Local Network permission again
- Allow Accessibility or Input Monitoring permission if macOS asks for global `F10/F11/F12` handling
- Re-enable launch at login if needed

The current package is ad-hoc signed locally, not Developer ID notarized. macOS may block the first launch on another Mac; use System Settings > Privacy & Security to allow it if needed.

### HDMI Switching

LGVolume first uses the webOS `switchInput` API and automatically falls back to launching the matching HDMI application when required by the TV firmware. If HDMI switching stops working after upgrading, disconnect and pair again so the TV can grant the updated `LAUNCH` and input-control permissions.

### Secure Connection

By default, LGVolume tries `wss://TV-IP:3001` first and falls back to `ws://TV-IP:3000` when a TV firmware needs it. Enable "Use secure connection only (WSS)" in Preferences to disable the fallback. Changing this option disconnects the current session so the next connection uses the new policy.

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
- **Volume shortcuts do not work:** make sure the latest version is running; check whether macOS asks for Accessibility or Input Monitoring permission; also check whether the keyboard sends F10/F11/F12 as media keys.
- **HDMI switching fails:** disconnect and pair again to refresh the TV permissions.
- **Changing the TV or IP:** save the new address and pair again; the old TV token is invalidated automatically.

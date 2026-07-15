# LG webOS API 可扩展功能清单

更新日期：2026-07-16

## 1. 范围与重要说明

LGVolume 当前通过电视局域网 WebSocket 端口连接 LG webOS TV，并使用 `ssap://` 请求完成音量、静音与 HDMI 控制。

需要区分两类接口：

- **LG 官方公开的 Luna Service API**：主要面向运行在电视内部的 webOS 应用。它能证明 webOS 平台具备相应能力，但不代表外部 Mac 客户端一定能通过 SSAP 获得同名能力。
- **电视对配对客户端开放的 SSAP 接口**：被 LG ThinQ、开源遥控器及 Home Assistant 等局域网客户端实际使用，但 LG 没有提供完整、稳定的公开协议规范。接口、权限名和返回结构可能随机型、地区及固件变化。

因此，下面按实际落地可靠性分级。新增功能前应在 LG C2 上实机探测服务并保留“不支持此功能”的正常降级路径。

## 2. 当前已经实现

| 能力 | 当前请求 | 当前权限 |
| --- | --- | --- |
| 读取/订阅音量 | `ssap://audio/getVolume` | `CONTROL_AUDIO` |
| 读取/订阅静音 | `ssap://audio/getStatus`，兼容回退 `audio/getMute` | `CONTROL_AUDIO` |
| 设置绝对音量 | `ssap://audio/setVolume` | `CONTROL_AUDIO` |
| 音量逐级增减 | `ssap://audio/volumeUp`、`audio/volumeDown` | `CONTROL_AUDIO` |
| 设置静音 | `ssap://audio/setMute` | `CONTROL_AUDIO` |
| 读取/订阅真实输入列表 | `ssap://tv/getExternalInputList` | `READ_INPUT_DEVICE_LIST` |
| 使用真实 input ID 切换 HDMI | `ssap://tv/switchInput` | `CONTROL_INPUT_TV` |
| HDMI 切换兼容回退 | `ssap://system.launcher/launch` | `LAUNCH` |
| 订阅当前 HDMI | `ssap://com.webos.applicationManager/getForegroundAppInfo` | `READ_RUNNING_APPS` |
| 读取/订阅声音输出 | `ssap://com.webos.service.apiadapter/audio/getSoundOutput` | `CONTROL_AUDIO` |
| 切换声音输出 | `ssap://com.webos.service.apiadapter/audio/changeSoundOutput` | `CONTROL_AUDIO` |

连接成功后会建立音量、静音、外部输入、前台输入和声音输出订阅。断线时统一取消请求，随后指数退避重连并重建订阅；一次性读取仍作为首次状态校准和兼容回退。

## 3. 推荐扩展功能

### A. 已实现：实时状态订阅

可对支持订阅的请求发送 `type: "subscribe"` 或协议要求的订阅形式，持续接收变化：

- 音量实时同步：`audio/getVolume`
- 静音实时同步：`audio/getStatus`，旧固件回退到 `audio/getMute`
- 当前前台应用或 HDMI 实时同步：`com.webos.applicationManager/getForegroundAppInfo`
- 外部输入名称与连接状态：`tv/getExternalInputList`
- 声音输出：`com.webos.service.apiadapter/audio/getSoundOutput`
- 当前频道与节目变化：`tv/getCurrentChannel`、`tv/getChannelProgramInfo`
- 电源状态：部分新固件支持 `com.webos.service.tvpower/power/getPowerState`

LGVolume 已实现上述订阅与断线重建。后续仍可增加电源、频道与播放状态订阅。

### B. 电源控制

| 功能 | 常见实现 | 可靠性 | 备注 |
| --- | --- | --- | --- |
| 关闭电视 | `ssap://system/turnOff` | 高 | 需要新增 `CONTROL_POWER` 权限并重新配对 |
| 开启电视 | Wake-on-LAN | 中 | 电视关机后 WebSocket 不存在；需保存电视 MAC，并在电视开启“通过 Wi-Fi/移动设备开机” |
| 仅关闭屏幕 | `com.webos.service.tvpower/power/turnOffScreen` | 中/低 | 新固件私有接口，部分型号拒绝 |
| 恢复屏幕 | `com.webos.service.tvpower/power/turnOnScreen` | 中/低 | 同上 |

建议产品形态：菜单中增加“关闭电视”；开机功能单独开关并在检测到 MAC 地址后启用，不把 Wake-on-LAN 误写成 webOS API 开机。

### C. 应用启动器

- 获取已安装应用/启动点：`com.webos.applicationManager/listLaunchPoints`
- 启动应用：`system.launcher/launch`
- 查询应用状态：`system.launcher/getAppState`
- 关闭应用：`system.launcher/close`
- 打开 URL：`system.launcher/open`

可以做成“常用应用”区域，让用户固定 Netflix、YouTube、Apple TV、Plex 等应用。应用 ID 应从电视返回的启动点动态保存，不能硬编码不同地区的 ID。打开 URL 可能让电视访问互联网，与 LGVolume 的“仅局域网”定位不一致，默认不建议加入。

### D. 播放控制

- 播放：`media.controls/play`
- 暂停：`media.controls/pause`
- 停止：`media.controls/stop`
- 快进：`media.controls/fastForward`
- 快退：`media.controls/rewind`

适合加入可选全局快捷键或菜单底部的小型播放控制。需要 `CONTROL_MEDIA_PLAYBACK` 权限；流媒体应用是否接受命令由应用本身决定。

### E. 完整遥控器与文字输入

通过 `com.webos.service.networkinput/getPointerInputSocket` 获取第二条输入 WebSocket 后，可以实现：

- 上、下、左、右、确定、返回、Home、菜单等遥控按键
- 鼠标指针移动、点击和滚动
- 播放类遥控按键
- 文本输入、删除字符、发送 Enter（IME 接口）

需要 `CONTROL_MOUSE_AND_KEYBOARD`、`CONTROL_INPUT_TEXT` 等权限。建议做成独立“遥控器”窗口，不要塞进当前窄菜单弹窗。按键名和部分行为会随固件变化，应采用白名单并提供实机能力检测。

### F. 已实现：HDMI 与外部输入增强

- 读取真实输入列表：`tv/getExternalInputList`
- 根据电视返回的 `inputId` 切换，而不是假定只有 `HDMI_1` 至 `HDMI_4`
- 显示电视保存的输入名称、图标、连接状态
- 支持 AV、组件、直播电视等非 HDMI 输入（仅在电视实际返回时显示）

设置页提供“使用电视返回的 HDMI 名称”选项；关闭时继续使用用户自定义名称。切换优先使用电视返回的 input ID，失败时才回退到 HDMI 应用启动方式。

### G. 已实现：声音输出设备

- 查询声音输出：`com.webos.service.apiadapter/audio/getSoundOutput`
- 切换声音输出：`com.webos.service.apiadapter/audio/changeSoundOutput`

菜单提供电视扬声器、HDMI ARC/eARC、光纤和蓝牙四类候选输出，并实时显示电视实际返回值。未知但真实返回的输出会动态加入；只有电视明确返回 invalid/unsupported 时，候选项才会在当前连接中隐藏。读取失败时控件会禁用，而不会把整台电视判定为连接失败。

### H. 电视直播频道

- 当前频道：`tv/getCurrentChannel`
- 频道列表：`tv/getChannelList`
- 上/下频道：`tv/channelUp`、`tv/channelDown`
- 打开频道：`tv/openChannel`
- 当前节目信息：`tv/getChannelProgramInfo`

适合使用天线、有线电视或地面数字电视的用户。频道 ID 与地区、调谐方式高度相关，应先读取频道列表，再使用返回的 channel ID，不能只传频道数字。

### I. 电视信息与诊断

可尝试读取：

- 型号、固件、webOS/SDK 版本、UHD 能力
- 当前软件版本
- 可用服务列表：`api/getServiceList`
- 网络连接状态

适合在设置页增加只读“设备信息”和“导出诊断”功能。日志必须过滤 client key、IP 地址等隐私信息。LG 官方的 TV Device Information API 明确提供型号、固件与 SDK 信息，但外部 SSAP 是否能访问应以电视服务探测结果为准。

### J. 电视通知

- Toast：`system.notifications/createToast`
- Alert/关闭 Alert：部分固件支持对应通知接口

可用于显示“已切换到 Mac mini”或自动化提醒。容易打扰观看，建议默认关闭，并限制频率。

## 4. 不建议默认加入的能力

### 画质、亮度、OLED 面板和工程设置

社区实现中存在读取或修改画质模式、亮度、OLED 像素亮度、色温、HDR、校准数据的 Luna/私有接口，但风险较高：

- LG 未承诺外部配对客户端可用
- 固件更新会改变权限或参数
- 错误参数可能破坏用户画质配置
- 某些校准接口面向专业工具，不适合作为普通菜单控制

如果未来开发，应放入“实验功能”，先只读、按型号白名单开放，并提供恢复前值的事务式操作。

### 任意 URI/命令控制台

不建议在正式版暴露可输入任意 `ssap://` 或 Luna URI 的控制台。它会扩大权限面，也容易绕过“仅局域网”和 UI 安全限制。开发调试版可通过编译开关启用。

## 5. 推荐开发顺序

1. **关机 + 可选 Wake-on-LAN**：补全日常电视控制闭环。
2. **应用启动器 + 播放控制**：增加高频、低风险功能。
3. **独立遥控器窗口**：导航、确认、返回和文本输入。
4. **频道与设备信息**：按用户需求逐步开放。
5. **能力探测**：根据电视实际服务进一步动态收敛声音输出和实验功能。

每一步都应先通过 `api/getServiceList` 或一次无副作用请求做能力探测，并把“固件不支持”视为正常状态，而不是连接失败。

## 6. 对 LGVolume 架构的要求

当前已经具备：

- request 与 subscribe 的统一请求管理
- 断线时取消请求、指数退避重连并恢复订阅
- 音量、输入和声音输出强类型模型
- 音量命令执行后读取真实值确认，失败时在绝对音量和逐级音量 API 之间重试一次
- `0600` 授权文件、脱敏轮转日志和显式真实电视诊断测试
- 只允许私有/链路本地 IPv4，SSDP 描述也限制在响应设备本身
- WSS 首次信任证书指纹绑定，证书变化时阻止连接

响应解析、注册清单和音量执行器已经从 WebSocket 连接器中拆分。下一步架构重点是继续扩展 `TVCapabilities`，由服务探测、当前返回值与明确拒绝结果共同生成。

## 7. 参考资料

- [LG webOS TV Luna Service API 概览](https://webostv.developer.lge.com/develop/references/luna-service-introduction)
- [LG webOS TV Audio API](https://webostv.developer.lge.com/develop/references/audio)
- [LG webOS TV Application Manager API](https://webostv.developer.lge.com/develop/references/application-manager)
- [LG webOS TV Device Information API](https://webostv.developer.lge.com/develop/references/tv-device-information)
- [LG webOS TV Connection Manager API](https://webostv.developer.lge.com/develop/references/connection-manager)
- [LG webOS TV Settings Service API](https://webostv.developer.lge.com/develop/references/settings-service)
- [Home Assistant webOS TV 通用命令说明](https://www.home-assistant.io/actions/webostv.command/)
- [aiowebostv 源代码仓库](https://github.com/home-assistant-libs/aiowebostv)
- [lgtv2 已知 SSAP 命令与订阅示例](https://github.com/merdok/lgtv2)

官方资料描述的是电视内部 Luna Service 能力；最后两项开源实现用于确认外部配对客户端中常见的 SSAP URI。两者不能互相等同，功能上线前仍需在目标电视和固件上验证。

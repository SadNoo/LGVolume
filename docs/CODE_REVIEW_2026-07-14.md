# LGVolume 代码修复复审

复审日期：2026-07-14

范围：`Sources/`、`Tests/`、`Scripts/`、`Resources/`、`Package.swift`、`Makefile` 与 Release 构建。

## 结论

上一轮发现的安全、状态一致性、错误反馈、测试隔离和设备发现问题已完成修复。当前 Release 构建通过，离线测试 22 项中 21 项通过、1 项真实电视测试按环境开关跳过，0 失败。

没有在 Git 跟踪文件或当前工作树中发现真实电视 IP、明文 webOS client key、GitHub token、私钥或密码。电视授权 token 保存在 Application Support 的 `0600` 文件中，WSS 证书指纹保存在应用偏好中；应用不执行任何 macOS Keychain 读写或删除操作。

## 已完成修复

| 原问题 | 修复方式 | 验证 |
| --- | --- | --- |
| WSS 接受任意证书 | 为每台电视加入 TOFU SHA-256 证书指纹绑定；证书变化时阻止连接并要求重新配对 | Release 构建、指纹存储测试 |
| 静音切换依赖缓存 | F10/菜单静音前先读取电视真实静音；独立订阅 `audio/getStatus`，旧固件回退 `audio/getMute` | 解析测试、订阅集成测试已编译 |
| 音量/输入状态会过期 | 连接后订阅音量、静音、外部输入、前台输入与声音输出；断线指数退避重连并重建订阅 | 请求管理测试、集成测试已编译 |
| WebSocket 发送错误被忽略 | send completion 立即结束对应请求并返回“发送失败”，不再只等待 8 秒超时 | Release/Debug 构建 |
| Keychain 可能弹出登录密码框 | 完全删除 Keychain client key 存储，授权 token 改存 `0600` Application Support 文件 | token 权限、迁移与清除测试 |
| 视觉测试读取真实设置 | AppCoordinator 支持注入 AppSettings；视觉测试使用临时 UserDefaults 和内存授权存储 | 视觉测试通过 |
| SSDP 只显示 LG TV | 受限访问响应设备的 LOCATION，用 XMLParser 读取 friendlyName；限制私有 IPv4、响应大小与超时 | XML 解析测试 |
| 视觉测试只检查 PNG 大小 | 增加关键控件可见范围、隐藏状态、图像尺寸和颜色内容断言 | 浅色/深色及四页截图通过 |

## 本轮新增能力

- 音量订阅与独立静音订阅，电视遥控器变化能实时回写菜单状态。
- 外部输入列表订阅，HDMI 切换优先使用电视返回的真实 input ID。
- 设置页可选择电视返回的 HDMI 名称，或继续使用四个自定义名称。
- 当前 HDMI 通过前台应用订阅实时更新。
- 声音输出读取、订阅与切换：电视扬声器、ARC/eARC、光纤、蓝牙。
- F11/F12 使用电视原生单步音量 API，并以电视回读值更新界面，不再预设 5% 或提前显示目标值。

## 额外修正

- `getVolume` 未返回静音字段时不再错误覆盖为“未静音”；只有明确返回的静音值才更新状态。
- SSDP 设备描述回调使用加锁容器，消除 URLSession 回调与超时路径之间的数据竞争。
- HDMI 设置页压缩垂直间距，新增选项和四个输入框在 720×390 窗口内完整显示。
- 声音输出菜单与 HDMI 按钮使用同一内容宽度。
- 授权 token 使用 `0600` 独立文件，证书指纹存应用偏好；LGVolume 不调用 `SecItemCopyMatching`、`SecItemAdd`、`SecItemUpdate` 或 `SecItemDelete`。

## 验证结果

- `make build`：通过
- `make test`：22 项执行，21 项通过，1 项真实电视测试按环境开关跳过，0 失败
- 视觉回归：通用浅色/深色、偏好设置、HDMI、快捷键、菜单栏截图均生成并通过关键控件可见性检查
- `codesign --verify --deep --strict`：由打包脚本验证通过
- `git diff --check`：通过
- 敏感信息扫描：未发现凭据、私钥、密码或真实电视 IP

## 仍需实机确认

真实电视集成测试默认关闭，避免自动操作用户电视。可通过环境变量显式提供电视 IP 和 client key 后运行，测试不会读取 macOS Keychain：

- 读取并写回当前音量
- 收到音量、静音、外部输入、当前前台输入和声音输出的首次订阅事件
- 切回当前 HDMI input ID
- 写回当前声音输出

声音输出枚举与订阅支持随机型和固件变化。当前读取失败会仅禁用声音输出控件，不影响音量、静音或 HDMI 主功能。

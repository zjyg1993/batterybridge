# 原生亮度接入（0.8.17）

已实现生产接入代码，**当前本地构建仍未在实机打通系统亮度滑块**。本轮阻塞已定位到虚拟 HID 签名能力，而不是显示器 DDC 开关。

## 控制链路

原有 DDC 扫描在唯一匹配显示器且取得有效亮度读数后，为开启“系统亮度与媒体键”的显示器创建一个原生亮度会话：

1. 校验真实 EDID 的长度、扩展数量、每块校验和、显示器身份；保留时序、HDR、色彩及原有扩展数据。
2. 读取并保存每台屏幕的 ContainerID；拒绝覆盖其他程序或显示器现有的不同 ContainerID。
3. 使用虚拟 HID Monitor Control / VESA Brightness Feature，声明 32 位亮度、0..60000 逻辑值与 0..600 cd/m² 物理值。HID 的 kUSBContainerID 与 DisplayID 2.0 ContainerID 扩展保持一致。
4. **先成功创建设备，再保存恢复检查点，最后应用 RAM 中的虚拟 EDID**。不写显示器 EEPROM。
5. EDID 和系统亮度能力均通过回读后才报告绑定可用。系统 Feature Set 转为百分比，进入现有串行 DDC 合并写队列，写 VCP 0x10 并回读确认；失败撤下绑定，不伪造物理亮度成功。
6. 显示器重新枚举时保留会话并更新 AV 通道，避免把短暂断开误判为用户停用。停止映射和退出应用移除 HID、恢复 EDID，并确认结果。退出使用 NSTerminateLater 等待恢复完成；恢复失败保留检查点并暂缓退出。

入口：`Sources/NativeBrightnessBridge.{h,m}`；集成：`Sources/Display.m`、`Sources/main.m`。`Sources/NativeBrightness.m` 仍是独立探针，不能替代生产链路。

## 当前签名阻塞

- 构建环境的 `security find-identity -v -p codesigning` 没有返回可用身份。
- 对测试程序加入 `com.apple.developer.hid.virtual.device` 并使用 ad-hoc 签名后，启动即被终止（退出码 137）。去掉该权限后可以运行，但无法创建虚拟亮度设备。
- 因此主 App 默认不携带未经授权的受限 entitlement，运行时先检查实际签名权限。缺少时停止原生绑定，**不修改 EDID**。辅助功能或设备控制授权不能替代有效的 HID 签名权限。

要继续实机验证，需在本机配置能够授予该虚拟 HID 能力、与 `local.batterybridge.agent` 对应的 Apple 签名身份和有效描述文件。不要把私钥、开发者账号密码发到聊天中。

```sh
DEVICEBRIDGE_SIGN_IDENTITY='已安装的签名身份名称' \
DEVICEBRIDGE_PROVISIONING_PROFILE='/本机/HID-enabled.provisionprofile' \
./release.sh
```

构建先解码描述文件，检查有效期、App ID 与 HID entitlement，再签名和打包；未满足时拒绝生成带受限权限的 App。此签名路径未在当前环境验证，因为缺少真实凭据。

## 已通过的验证

- EDID 原始身份、时序、CTA 扩展保留，新增 ContainerID 的双重校验和、重复应用和外部绑定保护。
- HID 亮度报告解码、越界拒绝、请求进入生产 DDC 队列、写入合并、回读确认和状态更新。
- HID 创建失败时不写 EDID；DDC 失败时撤下绑定。
- 正常退出恢复、恢复失败保留检查点及重试、上次未完成会话接管。
- AddressSanitizer / UndefinedBehaviorSanitizer 检查，以及原有协议、权限、界面和显示器测试。

尚未验证：系统实际成功创建受授权的 HID、实机 EDID 绑定、控制中心滑块驱动物理背光、插拔／休眠长期稳定性。强制终止不能运行退出清理，恢复检查点保留供下次接管。

## 后续复核：IOHID 与公开 CoreHID

补充了可重复运行的诊断：`/bin/zsh experiments/native-bridge/check-brightness-hid.sh`。两条路径使用 `DBBrightnessHIDDescriptor()` 导出的同一份 40 字节生产描述符；不经过主界面的 entitlement 预检，直接测量 API 是否创建设备。随机 ContainerID 不与任何屏幕关联，不调用 EDID 写入，不发送输入报告。

当前 macOS 27.2.1 执行环境的实测：

| 检查 | 结果 |
| --- | --- |
| `security find-identity -v -p codesigning` | 0 个有效身份 |
| IOHID 创建入口 / IOHIDResource | 均存在 |
| 诊断进程实际 HID entitlement | false |
| `IOHIDUserDeviceCreateWithProperties` | 未创建设备 |
| 公开 `CoreHID.HIDVirtualDevice(properties:)` | 未创建设备 |
| EDID 修改 | 未执行 |
| 系统滑块及物理背光验证 | 未通过，未生成 1.0.0 |

这些是受当前执行环境约束的独立 ad-hoc 诊断进程结果，不能仅凭返回 nil 断言唯一失败原因，也不能将其当作有授权签名后的实机测试。当前可确认的先决条件缺口仍是有效 HID 授权签名；尚未找到已验证可用的替代路径。独立工具不会继承主 App 的 entitlement。

已验证工具编译、运行与结果结构，并重新通过原生桥接协议和回退测试。生产主 App 保持 0.8.19，不把检测程序的编译通过视为原生亮度完成。

Apple 公开 CoreHID 接口说明：https://developer.apple.com/documentation/corehid/creatingvirtualdevices.md

下一步须在本机配置与 App ID 匹配且包含 HID entitlement 的有效签名身份和描述文件，使用上面的签名构建入口，再实测系统 Feature 请求 → DDC 写入 → 读回确认，以及插拔、休眠和退出恢复。满足之前不发布 1.0.0 正式版。

## 接口来源

- Apple IOHIDUserDeviceCreateWithProperties：https://developer.apple.com/documentation/iokit/3334952-iohiduserdevicecreatewithpropert
- Apple 虚拟 HID entitlement：https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.hid.virtual.device
- Candela 官方公开实现及开发说明，用于核实 ContainerID 配对和私有 AV API 行为：https://codeberg.org/livoni-software/candela （本地参考修订 f30635c1a8d616c97a42f4b402c5ca9b5a925478）。本项目使用独立的 Objective-C 会话、现有 DDC 队列与恢复机制，没有链接 Candela 产品。

IOAVService 和 DisplayServices 是私有接口，依赖运行时检测。当前 EDID 路径面向 Apple Silicon 的 AV 通道；Intel 保留原 DDC 控制，不猜测另一套 EDID 绑定接口。

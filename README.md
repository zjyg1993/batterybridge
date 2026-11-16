<p align="center"><img src="./docs/assets/logo.png" width="112" height="112" alt="BatteryBridge Logo"></p>

# BatteryBridge

让通过 **USB 2.4G 接收器**连接的无线键盘和鼠标，也能在 Mac 上直观看到电量。

当前版本：**0.5.9 Preview**，仍在进行设备兼容性验证。

## 1. 能力价值

BatteryBridge 是轻量的 macOS 原生菜单栏应用，专注于无线外设的电量读取与系统桥接。

- **查看外设电量**：在设备列表中查看电量、连接状态和设备支持的充电状态。
- **接入系统电池组件**：按设备开启映射，将有效电量发布到 macOS 外设电源列表；组件是否展示、刷新时机与图标由系统决定。
- **自动更新与手动刷新**：支持 30 分钟、1 小时、2 小时、3 小时更新周期，也可单独刷新设备；无有效读数时不显示为 0%。
- **后台常驻**：支持登录时启动，关闭主窗口后继续运行，通过菜单栏管理和退出。
- **本地独立运行**：无需保持网页驱动或官方客户端运行，无需 Python、Node.js；不上传设备状态，不记录按键输入。

本工具不替代官方驱动的 DPI、按键、宏、灯效、配对或固件管理功能。

## 2. 支持设备及型号

仅适用于已适配的 **USB 2.4G 接收器连接**。蓝牙、普通有线 USB 设备及未适配的接收器不在当前支持范围内。

| 品牌 | 型号 / 设备族 | 支持状态 |
| --- | --- | --- |
| Logitech / 罗技 | **G304 X LIGHTSPEED** | 已在本机读取电量并发布到系统电源列表 |
| MCHOSE / 迈从 | **K87 V3** | 已在本机读取电量并发布到系统电源列表 |
| XUNSHE / YJX | **USB Receiver（YJX）**，接收器 `A8A5:2255` | 实验性适配；此前版本已实测读取并发布电量，0.5.8 尚未重新实机验证；具体硬件型号未确认 |
| AULA / 狼蛛 | **F75**，接收器 `3554:FA09` | 预览适配，尚未实机验证；不包含 Max / Pro 等变体 |
| AULA / 狼蛛 | **SC580（3311 / 3315 传感器版）**，接收器 `089D:062F` | 预览适配，尚未实机验证；不包含 SE / Pro / Max 等变体 |
| Logitech / 罗技 | 部分支持 HID++ 2.0 电量功能 `0x1000 / 0x1004` 的键鼠 | 已实现通用探测，需逐设备验证 USB 接收器链路 |

罗技实验性候选包括 **G305（经典款）、MX Master 3 / 3S、MX Keys / Keys S、MX Mechanical**，均未完成本项目实机验证。经典 G304 / G305 不等同于已实测的 G304 X。

**同品牌或相近型号不代表兼容。** 迈从 G98 V3 当前未启用，其他迈从键鼠尚未适配；共享 USB 标识的接收器也可能使用不同协议。已实测设备仍需进一步验证长期运行、休眠唤醒及不同固件的表现。

适配细节：[AULA](docs/AULA.md) · [YJX / XUNSHE](docs/YJX-XUNSHE.md)。反馈兼容性问题时，请提供完整型号、接收器 VID / PID、macOS 版本及实际表现。

## 3. 系统要求

| 项目 | 要求 |
| --- | --- |
| macOS | 最低构建目标为 macOS 13；当前验证环境为 macOS 27，其他版本待验证 |
| 处理器 | 包含 Apple Silicon（arm64）与 Intel（x86_64）通用二进制；Intel 实机待验证 |
| 外设 | 上述支持范围内的键鼠，通过 USB 2.4G 接收器连接 |
| 权限 | 按系统提示允许输入监控；登录时启动可能需要批准登录项 |

打开 `BatteryBridge-0.5.9-preview.dmg`，将应用拖入 **应用程序**，再从访达启动。需要授权时，前往 **系统设置 → 隐私与安全性 → 输入监控** 允许 BatteryBridge，并按提示退出重开；随后开启设备行右侧的 **映射开关**，即可尝试接入系统电池组件。

预览版使用 ad-hoc 本地签名，尚未经过 Apple 公证，首次启动或更新后可能需要系统确认或重新授权。无需关闭 SIP 或安装内核扩展。系统电量发布使用 IOKit 私有 SPI，后续 macOS 更新可能影响兼容性。

从源码构建需安装 Xcode Command Line Tools：`./build.sh "$PWD/build.noindex"`。运行 `./release.sh` 打包，最终 DMG 输出到 `release/`（Git 忽略），临时打包文件使用 `release.noindex/`。

## 4. 参考资料

- [Logitech 官方 HID++ 2.0 文档](https://github.com/Logitech/cpg-docs/blob/master/hidpp20/README.rst)
- [Solaar：Logitech 设备协议与社区兼容性记录](https://github.com/pwr-Solaar/Solaar)
- [MCHOSE 官方 M HUB 说明](https://support.mchose.store/hc/en-us/articles/49078340935700-Getting-Started-with-MCHOSE-M-HUB)
- [MCHOSE 官方网页驱动](https://www.mchose.com.cn/)
- [XUNSHE 官方网页驱动](https://xunshe.yjx2012.com/?productName=USB%20Receiver)
- [YJX F0 主动电量查询实现](https://github.com/mimuruu/EWEADN-GS02-Pro-Control)
- [YJX 不同固件报文记录](https://github.com/HeyOkay/HaloBattery/blob/main/docs/protocols.md)

BatteryBridge 是独立项目，非上述品牌的官方驱动。

# 2.4G 接收器适配与覆盖范围

当前版本 **0.8.0 Preview**；项目现名 **DeviceBridge**。本页先列本轮新设备与限制，后附首批协议记录。

## 0.8.0：截至 2026 年 11 月的补充

本轮检索截止 **2026-11-16**，增加下表的接收器入口和只读查询。文末 0.6.0 章节是首批实现记录；本节更新其中“ASUS / Corsair / 其他迈从尚未支持”的旧范围。**所有本轮设备均未在本项目完成实机验证**，即使参考项目已有用户验证，也只标为预览适配。

### 本轮新增接收器

| 品牌 / 型号 | 2.4G 接收器 VID:PID | 路径及匹配条件 |
| --- | --- | --- |
| Razer Viper V4 Pro | `1532:00E6` | 接口 0，Razer 电源命令，事务 `1F` |
| Razer DeathAdder V4 Pro Carbon Fiber | `1532:00F0` | 同上 |
| Razer Basilisk V3 Pro / 35K / Phantom Green | `1532:00AB` / `00CD` / `00D7` | 同上 |
| Razer Cobra Pro / Viper Mini Signature Edition | `1532:00B0` / `009F` | 同上 |
| Logitech PRO X2 SUPERSTRIKE | `046D:C54D` | `FF00:0001`，声明 HID++ `10` Output；仅新增识别入口，功能须通过 HID++ 动态探测，不视为已验证兼容 |
| Pulsar 指定 X2 V2 / X2H / X2A / Xlite V3 接收器族 | `3554:F508` / `F509` | `FF02:0002`，`08` Input / Output 各 16 字节载荷；接收器共享，不凭 ID 猜具体鼠标型号 |
| Pulsar X2 CrazyLight Mini | `3710:5406` | 同上；其他 CrazyLight 尺寸及 SKU 未自动纳入 |
| ATK X1 Pro 1K / Fire X 8K / VXE R1 SE+ | `373B:101A` / `101B` / `1085` | 同上 |
| VXE R1 Pro Max / VGN Dragonfly 4K | `3554:F58A` / `F505` | 同上 |
| Corsair SABRE v2 PRO ULTRALIGHT | `1B1C:2B2A` | 同上；与 Corsair bragi / SLIPSTREAM 协议分开 |
| Hitscan Hyperlight / Teevolution Terra Pro | `3770:0200` / `3554:F523` | 同上 |
| MCHOSE L7 / M7 接收器族 | `5253:1020` | `FF01:0001`，声明 `11` 20 字节或 `12` 64 字节 Feature；不纳入有线 PID |
| MCHOSE A7 V2 Ultra | `3837:100B` | 同上；明确排除不同协议的 G3 系列 |
| MCHOSE A5 Pro Max 1K / 4K | `2023:F013` / `F015` | `FFFF`，64 字节无编号 Feature，电量查询 `83` |
| LAMZU Maya X 8K | `373E:001E` | 接口 2、`FFFF`，64 字节无编号 Feature |
| WLmouse Beast X / Max / Mini Pro | `36A7:A887` / `A880` / `A868` | `FFFF`，64 字节无编号 Feature |
| ATK V75X 键盘 | `320F:5088` | 产品名必须为 `ATK V75X 2.4G Dongle`，`FF1C:0092`，`04` Input / Output 各 31 字节载荷 |
| ROG Harpe II Ace / Harpe II Extreme | `0B05:1AD0` | 接口 2、`FF01:0003`，`03` Input / Output 各 63 字节载荷；显示设备族名称 |
| ROG OMNI 配对键盘 | `0B05:1ACE` | 接口 2 的 `FF02:0001` 查询配对表，再在同一个 LocationID 的 `FF00:0002` 查询键盘；缺少位置标识不路由 |

ROG OMNI 只读取已知配对型号，不对未知设备发送键盘命令。目前接受的配对 PID 分组如下；这些 PID 是**配对表里的外设标识**，不是全部允许直接打开的 USB 接收器 ID：

| 配对设备族 | 已知配对 PID |
| --- | --- |
| Azoth | `1A83` / `1A85` |
| Strix Scope II 96 Wireless | `1AAE` / `1AAF` / `1AB0` |
| Azoth Extreme | `1B3F` / `1B40` / `1B42` |
| Azoth 96 HE / Lite | `1C10` / `1C11` / `1C12` |
| Azoth X | `1C24` / `1C25` / `1C26` |
| Falcata | `1C2F` / `1C30` / `1C31` |
| Strix Morph 96 Wireless | `1CE8` / `1CE9` / `1CEA` |
| Azoth Extreme Special Edition | `1CEF` / `1CF0` / `1CF1` |

这些配对型号按公开型号目录及键盘电源布局实现；新型号的同布局兼容性仍属待实机验证。仅当配对表匹配且实时电量回复通过校验才发布。Falchion 的电量位置不同，本轮未套用此布局；OMNI 鼠标通道也未在本轮启用。

### 新协议的有效性约束

- **Compx / Pulsar**：17 字节完整报文，含 report ID `08`；命令 `03` 校验在线状态，在线才发 `04` 电量请求。验证命令、状态、偏移、长度、`0x55 - sum` 校验、电量范围和充电标记。休眠接收器即使缓存着一个百分比，也不能绕过在线检查。IOHID 载荷只传 16 字节，由传输层加入 report ID。
- **MCHOSE 新协议**：仅命令 `06`；整个载荷（包括填充）异或 `FF`，report ID 不反转。校验命令回显、回复厂商、在线位、百分比和充电标记。优先短报告；不发送模式、配置、DPI 或唤醒设置。
- **ATK V75X**：仅 `1A` 电量 getter，无配置握手；随机 16 位请求 ID，检查序号、零偏移及百分比 / 充电状态。序号不符的旧包不能成为本次结果。
- **ASUS**：鼠标 `12 07`、键盘 `12 01`，分别解析自己的字段。拒绝 `FF AA`、错误命令 / 偏移、超范围电量，以及未充电的待机零值。OMNI 先读取配对表 `A0`；两个接收器不能共用配对结果，配对结果不明确时不查询电量。
- **Feature 接口**：无编号报告不人为加零；有编号报告由传输层只加入一次 ID，并以实际报告长度读取。所有新通道仅接受其协议的回复 ID，不记录普通键盘、鼠标输入。

### 在售产品核对与剩余缺口

本轮重点不再局限于旧款：Razer 官方已发布 Viper V4 Pro，Corsair 官方在售 SABRE v2 PRO ULTRALIGHT，Pulsar 的 CrazyLight 驱动有 2026 年更新，ASUS 官方产品线包含 Azoth 96 HE 与 Falcata；这些产品对应的上述实现属于新增或扩展的预览路径。产品在售与电量协议可读是两个独立条件，发布支持仍按具体接收器及固件验证。

| 当前产品 / 系列 | 本版处理 |
| --- | --- |
| Logitech PRO X2 SUPERSTRIKE | 接收器识别入口已补充；须验证其 HID++ 电量、名称及设备类型功能，不将产品名加入名单等同于已兼容 |
| Logitech PRO X SUPERLIGHT 2、G915 X LIGHTSPEED、G515 LIGHTSPEED、MX Master 4、MX Keys S | 现有 HID++ 2.0 动态功能探测的验证候选；本版仅解析 `1000` / `1004`，其他电量特性不会被误当成百分比 |
| Keychron Q / V / K Max、Ultra、HE 键盘 | 不从 Keychron 鼠标协议推断兼容；Q6 Max、K8 HE 等公开研究记录了原厂接收器电量查询缺口，本版不刷固件、不生成估算电量 |
| Corsair K65 PLUS / K70 无线键盘 | 待逐型号适配；SABRE v2 使用 Compx 不代表所有 Corsair 设备使用该协议 |
| 雷柏、达尔优、黑爵、其他狼蛛 / 迈从键鼠 | 未列出的型号继续待适配；不按品牌整体放开，也不批量发送猜测命令 |
| Bluetooth-only 或有线型号 | 不在 2.4G 适配范围，不因“新款”而纳入 |

### 本轮来源

- [Razer 官方 Viper V4 Pro 发布](https://www.razer.com/newsroom/product-news/viper-v4-pro-gigantus-v2-pro)、[OpenMouse 设备目录](https://openmouse.app/supported)、[OpenRazer 设备与实现](https://github.com/openrazer/openrazer)：产品时点、RF / 有线标识及协议背景。
- [Logitech 官方 PRO X2 SUPERSTRIKE 规格](https://support.logi.com/hc/en-us/articles/35026563405591-Specification-PRO-X2-SUPERSTRIKE)：接收器 `046D:C54D`。
- [Corsair 官方 SABRE v2 PRO ULTRALIGHT](https://www.corsair.com/ww/en/p/gaming-mouse/ch-931g000-ww/sabre-v2-pro-ultralight-wireless-gaming-mouse-ch-931g000-ww)、[Pulsar 下载目录](https://www.pulsar.gg/pages/download)、[ASUS 当前键盘目录](https://rog.asus.com/uk/keyboards/keyboards-series/)：当前在售产品和 2026 年驱动记录。
- [python-pulsar-mouse-tool](https://github.com/andrewrabert/python-pulsar-mouse-tool)、[2026-09-04 Pulsar HID 驱动补丁](https://lists.openwall.net/linux-kernel/2026/09/04/2124)：Compx 帧、校验、在线与电量读取（独立实现协议，未复制驱动源码）。
- [MCHOSE 协议文档](https://github.com/alexfrih/mchose-linux/blob/main/PROTOCOL.md)：`06` Feature 命令、反转、状态布局及 G3 排除。
- [G-Helper](https://github.com/seerge/g-helper)、[ROG-Battery 型号目录](https://github.com/youmikk/ROG-Battery)、[rigstats 电源协议研究](https://github.com/dvalfrid/rigstats/blob/main/docs/control-architecture.md)：ROG 配对型号和按设备类型区分的电源布局。
- [HaloBattery 协议记录](https://github.com/HeyOkay/HaloBattery/blob/main/docs/protocols.md)：接收器 ID 及公开报文例子，特别是 Harpe II、V75X、CrazyLight 和新款 Corsair。
- [Keychron K8 HE 原厂固件调查](https://github.com/SPDG/inputscout)、[Q6 Max 接收器电量调查](https://github.com/SasiRawr/Keychron-Q6-Max-Battery-Widget)：不将估算或刷写自定义固件当成原厂兼容。

本地验证包含协议报文、离线时禁止电量请求、同一物理 OMNI 接收器路由、有线 / 蓝牙 / 错误集合排除及既有功能回归。硬件验收仍需设备所有者核对百分比、充电、休眠唤醒和固件差异。


---

# 首批协议记录（0.6.0 Preview）

本次增加只读电量查询，并接入现有单设备刷新、周期更新和 macOS 电量映射。以下设备均为**协议适配完成、本项目尚未实机验证**；自动化测试使用公开协议构造的报文及文档中的示例，不能代替硬件验证。未列出的同品牌设备不自动兼容。

## 接收器白名单

| 品牌 | 型号 | 接收器 VID:PID | 接口限制 |
| --- | --- | --- | --- |
| Razer | BlackWidow V3 Pro | `1532:025C` | USB 接口 2 |
| Razer | BlackWidow V3 Mini HyperSpeed | `1532:0271` | USB 接口 3 |
| Razer | BlackWidow V4 Mini HyperSpeed | `1532:02BA` | USB 接口 3 |
| Razer | BlackWidow V4 Tenkeyless HyperSpeed | `1532:02D5` | USB 接口 2 |
| Razer | DeathStalker V2 Pro | `1532:0290` | USB 接口 2 |
| Razer | DeathStalker V2 Pro TKL | `1532:0296` | USB 接口 2 |
| Razer | Viper V2 Pro | `1532:00A6` | USB 接口 0 |
| Razer | Viper V3 Pro | `1532:00C1` | USB 接口 0 |
| Razer | DeathAdder V3 Pro | `1532:00B7` | USB 接口 0；其他接收器变体未启用 |
| Razer | DeathAdder V3 HyperSpeed | `1532:00C5` | USB 接口 0 |
| Razer | DeathAdder V4 Pro | `1532:00BF` | USB 接口 0 |
| SteelSeries | Aerox 3 Wireless / CS2 Dragon Lore | `1038:1838` / `1038:1878` | `FFC0` 配置集合，64 字节无编号 Output |
| SteelSeries | Aerox 5 Wireless / Destiny 2 / Diablo IV | `1038:1852` / `1038:185C` / `1038:1860` | 同上 |
| SteelSeries | Aerox 9 Wireless / WoW | `1038:1858` / `1038:1874` | 同上 |
| Keychron | M5 / M6 8K，经 Ultra-Link 8K | `3434:D028` | 接口 4、厂商集合，`B3` Output / `B4` Input 各 63 字节载荷 |
| Glorious | Model O Wireless | `258A:2022` | `FFA0` / `FFFF` 集合，64 字节无编号 Feature |

蓝牙和各型号的有线 ID 均不进入上述白名单。Aerox Gen 2、Rival、其他 Keychron 接收器、Glorious 新型号以及通用 HyperPolling Dongle 均未启用；不依据名字或近似 USB ID 探测协议。Ultra-Link 共用接收器目前以设备族名称显示，不声称已识别配对的具体型号。

## 查询和校验

- **Razer**：90 字节 Feature，电源类 `07`；`80` 读取电量，`84` 读取充电状态。键盘事务 ID 为 `9F`，上述鼠标为 `1F`。验证成功状态、事务 ID、命令、长度和 XOR；电量从 0–255 换算为百分比。两次读取均成功才发布，失败不补造充电状态。
- **SteelSeries Aerox**：只发送接收器电量命令 `D2`，校验命令回显；低 7 位的 1–21 换算为 0–100%，分辨率为 5%，最高位为充电标记。0 视为离线或休眠；超出该档位范围不猜测其他尺度。
- **Keychron**：当前上游内核实现使用 `B3 06` Output 请求，回复 `B4 06`；含 ID 的字节 20 为电量，低 7 位为百分比，最高位为充电标记。部分较早文档写作 Feature，本版按实际 HID 描述符要求 Output，不对不同传输固件盲目发包。
- **Glorious**：Feature 载荷 `00 00 02 02 00 83`，等待无线往返后读取 Feature。只接受 `A1` 在线状态及电量命令回显；`A2` 唤醒中和 `A4` 休眠均不作为当前读数。充电时如果设备离开接收器链路，不从旧电量推算当前电量。

新增协议均限制重试次数。查询失败时撤销该设备的当前采样及系统发布，保留设备列表记录供再次刷新。仅打开命中的接口；Feature 查询通道不接收输入报文，其他通道只收各自的厂商回复 ID。不进行按键、宏、DPI、灯效、配对或固件写入。

## 来源与实现边界

查阅日期：2026-11-16。依据公开格式独立实现 Objective-C 编解码及 IOKit 传输，未引入上游运行时或复制上游驱动源码。

- [OpenRazer 键盘驱动](https://github.com/openrazer/openrazer/blob/master/driver/razerkbd_driver.c)：无线键盘事务 ID、接口及电量字段。
- [OpenRazer 鼠标驱动](https://github.com/openrazer/openrazer/blob/master/driver/razermouse_driver.c) 与 [设备目录](https://openrazer.github.io/)：鼠标设备及协议背景。
- [OpenMouse 支持设备](https://openmouse.app/supported)：Viper / DeathAdder 的无线与有线 ID 区分。
- [uncoil 协议说明](https://uncoil.justinthevoid.com/docs/protocol/)：Razer 报文结构和回复时序。
- [Rivalcfg 设备目录](https://rivalcfg.flozz.org/devices.html)：Aerox 无线与有线 ID。
- [alloyctl Aerox 3 协议](https://alloy.szymon-wilczek.me/protocol/steelseries-aerox3-wireless.html)：`FFC0`、接口及 64 字节传输结构。
- [SteelMouse](https://github.com/yurtemre7/steel-mouse)：Aerox 电量协议背景。
- [keychron-battery-dkms](https://github.com/csutcliff/keychron-battery-dkms/blob/main/keychron_battery.c)：当前 Output 请求、回复格式及充电位。
- [HaloBattery 协议记录](https://github.com/HeyOkay/HaloBattery/blob/main/docs/protocols.md)：Glorious 查询与状态、Aerox 电量示例、Razer 无线键盘协议交叉核对。

ASUS ROG、Corsair、HyperX、雷柏、达尔优、黑爵等尚未因此获得新支持。公开资料中部分型号需要多设备路由、与具体固件绑定的接口，或仍有冲突的报文记录；需要进一步逐型号适配，不以品牌名作兼容性承诺。

## 本地验证

运行 `./build.sh "$PWD/build.noindex"`：构建 arm64 / x86_64 通用应用，执行协议、刷新策略与界面测试并验证签名。硬件验收还需核对官方电量、充电切换、休眠唤醒、接收器拔插及同时连接多个设备。


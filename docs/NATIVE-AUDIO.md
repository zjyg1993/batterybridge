# Proxy Audio Device 接入来源

DeviceBridge 0.8.14 在 App 资源中以 ProxyAudioDevice.zip 封装从官方源码构建的驱动，首次打开应用自动提示安装，完成后等待驱动加载并配置输出。主窗口没有手动安装或“系统音量”按钮。驱动未安装到系统之前，控制中心的 HDMI 音量滑块不会因此启用。

- 上游：https://github.com/briankendall/proxy-audio-device
- 修订：`d3d8c8c0343845e03fd95e6764f0fa9853d88e10`（v1.1.0.1）
- 许可证：Unlicense，原文随驱动保存在 `Contents/Resources/ProxyAudioDevice-LICENSE.txt`。
- 源码位于 `Sources/ThirdParty/ProxyAudioDevice/`；构建脚本 `experiments/native-bridge/build-proxy-driver.sh`。按项目约定 Sources 被 Git 忽略，本地构建必须保留该目录。
- 本地修改：`CFStringToStdString` 中数组释放改用 `delete[]`，修正上游 `new[]` 与 `delete` 不匹配。
- 配置协议：通过 `ProxyAudioBox_UID` 获取 Box，Identify 写入当前 PID，Name 写入 `outputDevice=物理UID`，Identify 写入 `-1` 后读取 Name 核实目标 UID；随后切换并回读系统默认输出。
- 音量：上游驱动的软件增益；不发送 DDC 音量命令。左右声道音量及主静音均纳入属性检查。

安装需管理员授权，会短暂中断播放。安装脚本拒绝覆盖已有驱动；不改变 SIP，不安装内核扩展。构建使用 ad-hoc 本地签名，驱动在用户 macOS 上能否加载、播放和联动仍需验证。测试通过表示接入逻辑通过，不代表实机音频通过。

原生亮度只完成机制核查。Candela（https://codeberg.org/livoni-software/candela）修订 `f30635c1a8d616c97a42f4b402c5ca9b5a925478` 的开发文档说明共享 ContainerID、虚拟 EDID 与 HID entitlement 的绑定路径；其 GPL 代码没有复制或链接到 DeviceBridge。

0.8.14 安装修复：Finder 会给嵌套驱动添加 com.apple.FinderInfo，旧安装器在校验来源时因此失败。改为 ZIP 封装，安装时解包临时副本、清理 FinderInfo / ResourceFork 后验证原签名；不重新签名，不接受改动的受签名保护内容。回归测试覆盖元数据污染和篡改拒绝。安装失败下次启动重试；成功后保存输出 UID，并尊重用户后续切换设备的选择。

0.8.14：系统声音输出中已观察到 Proxy Audio Device，证明驱动加载成功。接入层增加 HAL TranslateBundleIDToPlugIn 与插件设备列表／所有权链的身份核实，不再仅依赖上游未实现的 BundleID 读取属性；输出声道可从 stream virtual format 回退获取。超时保留原始枚举诊断，不再提示必须重启。

本轮实机观察：系统声音设置已有 Proxy Audio Device，选中时输出音量（约 83%）及静音控件可用。修正版已运行，保存了物理输出 UID。接管已选中代理的会话不会再次切换默认输出，结束会话保留该选择。实际显示器出声、长时间稳定性及原生亮度仍未验证。

0.8.16：启动时不再要求当前默认输出与保存的显示器 UID 相同。自动选择可用显示器路由并切换到代理，记录启动瞬间的默认输出；正常退出恢复该设备。若启动时代理已经被选中，则使用上次记录的非代理输出或已核实的物理显示器作为恢复目标。窗口关闭继续遵循原来的后台运行规则，不触发退出恢复。

0.8.18：音量与亮度开关独立。音量开关依据 Core Audio 中唯一匹配的显示器音频输出决定是否可用；关闭最后一个音量桥接恢复原输出并撤下代理。撤下使用上游 Box 的 kAudioBoxPropertyAcquired=false，驱动保存该状态并通知 HAL 移除设备；下次启动重新设为 true。退出等待 HAL 列表中代理消失后完成，不每次卸载／重装驱动。关闭桥接、失败恢复、撤下顺序和再次注册已纳入测试。

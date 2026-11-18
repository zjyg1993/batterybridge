# 原生控制构建说明（0.8.17）

音量代理继续使用已有安装与自动切换逻辑。原生亮度的生产接入位于 Sources/NativeBrightnessBridge.m，并接入原有显示器发现、DDC 队列和退出流程。旧 brightness-probe 命令仍是独立诊断探针，不是生产接入入口。

**当前 ad-hoc 构建不具备获 Apple 授权的虚拟 HID 签名，不能开启原生亮度。** 初始化会明确报告缺少签名能力，且不修改 EDID。不能仅把受限 entitlement 写进本地签名：本轮测试中这种可执行程序启动即被终止，退出码 137。已改为默认保留安全的普通 ad-hoc 签名，仅在提供有效签名身份和 HID provisioning profile 时嵌入该权限。

生产接入实现了：完整 EDID 与 ContainerID 校验、共享 ContainerID 的 HID 绑定、系统请求到 DDC 的串行合并写入与回读确认、重连等待、恢复检查点及退出恢复。通过伪设备端到端测试和地址／未定义行为检查，不代表实机系统亮度已验证。

详细构建条件、恢复边界及来源见项目 docs/NATIVE-BRIGHTNESS.md。

## 对比 IOHID 与 CoreHID 的实际创建结果

macOS 15 以上、安装相应 Swift SDK 后运行：

```sh
/bin/zsh experiments/native-bridge/check-brightness-hid.sh
```

两个独立 ad-hoc 诊断程序使用同一份生产亮度描述符，直接调用 IOHID 和公开 CoreHID 创建设备，不受主 App 预检开关影响。ContainerID 随机生成，不与显示器匹配，不写 EDID、不发送输入报告，局部设备对象释放后移除。

结果保存在本目录 `build.noindex/hid-capability.json` 与 `corehid-capability.json`。这是诊断进程当前权限环境下的结果；主 App 的签名权限不会自动传递给这些独立程序。创建成功也不能证明系统滑块、屏幕绑定或物理背光已经成功，不能据此发布正式版。

`hid-capability` 另行打开并立即关闭 IOHIDResource 用户客户端，输出底层错误码，不提交设备描述符。打开失败可以定位到设备创建前的访问环节；不能把返回的通用错误码直接解释成签名权限错误。

只读检查原生亮度绑定的屏幕侧前提：

```sh
./experiments/native-bridge/build.noindex/native-bridge brightness-readiness
```

输出在线显示器、外部 AV 通道、完整 EDID 校验结果、现有 ContainerID 和虚拟 EDID API 可用性。不修改 EDID、不写 DDC、不证明系统滑块接入成功。Codex 沙箱可能看不到在线屏幕；须在宿主环境复核，不能将沙箱内空枚举当成未连接。

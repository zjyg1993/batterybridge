# 文档截图

运行 `./tools/preview-docs.sh` 构建独立的 `DocumentationPreview.app`，再通过访达打开。应用菜单的“状态栏菜单”可在窗口内展开生产代码使用的同一个 NSMenu，便于窗口级截图服务完整截取。此预览有独立应用标识，不安装正式应用，不开启 HID 工作线程、DDC 探测、系统电量发布或登录项；设备名称和数值均为明确的演示数据。

截图通过系统窗口截图保存到 `docs/assets/main-window.jpg` 和 `docs/assets/status-menu.jpg`，未经生成式工具重绘。`docs/assets/devicebridge-poster.png` 为宣传插画，与 `generated_images/` 中更新的宣传图一致。

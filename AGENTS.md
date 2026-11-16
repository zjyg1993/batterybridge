# BatteryBridge 项目约定

- DMG 安装包统一生成在项目根目录的 `release/` 文件夹下。
- `release/` 为本地发布产物目录，必须被 Git 忽略，不提交其中的文件。
- 打包临时文件继续使用 `release.noindex/`，不要混入最终发布目录。

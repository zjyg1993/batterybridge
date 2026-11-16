# DeviceBridge 项目约定

- DMG 安装包统一生成在项目根目录的 `release/` 文件夹下。
- `release/` 为本地发布产物目录，必须被 Git 忽略，不提交其中的文件。
- 打包临时文件继续使用 `release.noindex/`，不要混入最终发布目录。
- 发布时仅在 `release/` 输出 DMG，不额外生成独立 `.app`；构建中间 App 在打包校验后清理。

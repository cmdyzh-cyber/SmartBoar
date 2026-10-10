首个公开试用版：让老打印机在 Mac 上继续打印。

**预发布 / 试用版：新版安装包尚未完成实际安装和真实出纸验证，也未经过 Developer ID 签名与 Apple 公证。当前只有 HP Laser 108a 可自动设置。**

### 下载与使用

- `SmartBoar-0.2.0-arm64-unsigned.pkg`：普通用户安装包，适用 Apple Silicon / macOS 14+。
- `SmartBoar-0.2.0-source.zip`：完整项目源码，含修改后的 SpliX 对应源码和许可证。
- `SHA256SUMS.txt`：以上文件的 SHA-256 校验值。

GitHub 的 Source code 压缩包不是安装程序。

接好 USB、开机并装纸 → 双击 PKG 按系统提示授权 → 打开“聪明的野猪” → 选择设备自动设置 → 打印一页，确认真实完整出纸。普通用户不需要终端命令。

[安装与使用](https://github.com/cmdyzh-cyber/SmartBoar/blob/main/docs/安装与使用.md) · [常见问题](https://github.com/cmdyzh-cyber/SmartBoar/blob/main/docs/常见问题.md) · [反馈与新机型请求](https://github.com/cmdyzh-cyber/SmartBoar/issues/new/choose)

### 功能与注意事项

USB 自动识别、完整型号匹配、独立机型库与驱动模块、诊断本地保存、目标队列备份、失败恢复与回滚。保留 HP 108a ARM64 SpliX、纸张几何及设备限定 USB 修复。

安装不自动打印或取消旧任务。有旧任务先在应用中清除；打印机仍重复走纸时，关闭再开启以清除机内缓存。原配置有备份，可通过“恢复原设置”回滚；恢复不是完整卸载。

同一 HP 108a 驱动与修复方案已在 M3 / macOS 14.6 实际出纸，并验证 USB 重连后一页完整、无重复。新版安装器只完成原生编译、模拟配置/回滚、包与界面检查，**尚未真实安装验证**。

另 10 个 Samsung、Xerox、Dell 候选机型仅识别，不开放安装。没有在线驱动下载，不支持 Windows、Intel Mac、无线打印、扫描或传真。不承诺所有老打印机都可用。

未签名包下载后可能被 macOS 拦截，请先阅读安装说明；不需要关闭 SIP 或全局关闭安全检查。诊断不自动上传，公开反馈前检查隐私。

原创代码 MIT；SpliX、PPD 和第三方补丁保留上游许可，完整对应源码随包提供。项目不隶属于 HP 或 Apple。

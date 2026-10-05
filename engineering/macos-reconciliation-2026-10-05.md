# macOS 旧工作树归属与 PR #55 构建修复

审计日期：2026-10-05（America/Los_Angeles）。比对主线为
`cc1d31bc8b24b0103bc78dea2453768cb0c5a339`，PR #55 原始 head 为
`7cce2da1016c2adab8beb55da93f452ed1f9b5ae`。本次使用独立工作树，正常 merge
主线后修改；没有改写共享历史，没有修改或清理以下旧工作树。

## 旧稿逐文件归属

比较 tracked 修改与 untracked 文件的实际内容，仅规范化 CRLF/LF。
共 50 个工作树文件条目，35 个与主线完全一致，15 个属于格式或主线后续修正；
未发现仍需重新移植的独有运行功能。这个判断不能替代原现场备份。

| 工作树（均位于 E:/CodeWorkstation） | 一致 | 有差异 | 处理结论 |
| --- | ---: | ---: | --- |
| FlClashX-mac-mdm-xcode | 9 | 3 | 已吸收；pbxproj 仅顺序/缩进，主线文档更完整，MDM 生成器新增 signing identity 去重。 |
| FlClashX-macos-managed-host | 5 | 3 | 已吸收并修正；主线 token 使用 stdin，保留 connect-only、单 profile、quarantine 和后台登录恢复。 |
| FlClashX-macos-managed-provider | 5 | 3 | Provider 主体已吸收；主线以认证 FCXD 替换 SOCKS UDP ASSOCIATE，恢复快照上限为 4 MiB，补全说明。 |
| FlClashX-macos-strict-core | 15 | 1 | Core/Agent 全部一致；Swift 旧模型已移至公共模型文件并扩充。 |
| FlClashX-macos-strict-dev | 1 | 5 | 原始雏形已吸收或被替代；身份解析支持 app executable，模型增加 DNS/UDP/generation 约束。 |

主线证据：`lib/clash/service.dart` 的 `@stdin`，
`macos/Runner/ManagedStrictProxyController.swift` 的 `quarantineAll`、connect-only
与单 profile 检查，`macos/StrictProxy/StrictProxyModels.swift` 公共模型，
`StrictSOCKSConnection.swift` 的 HMAC 和 replay window，
`tools/macos/New-ManagedStrictProfile.py` 的 signing identity 去重。
不得通过覆盖整文件恢复旧稿，否则会回退这些安全或集成修正。
原始 HEAD、diff、untracked 与哈希由总控防丢归档保存，旧工作树不作为清理对象。

## PR #55 失败证据与修复范围

[原失败运行](https://github.com/Hao-Monster/FreedomCloud/actions/runs/36910391769)
创建了 `com.follow.clash.StrictProxy.systemextension`，Runner 却复制带 `.debug`
的扩展路径，最终退出 65。Release 流水线现在显式传递相同的 provider bundle ID，
归档前检查 Host/Provider Info.plist、扩展文件名和可执行文件的一致性。
保留全部 System Extension target、dependency、embed phase 和 entitlement。

同一日志的 Keychain 错误来自 LaunchAtLogin 固定 revision
`9a894d799269cb591037f9f9cb0961510d4dca81` 的复制脚本：无条件 codesign，
忽略 `CODE_SIGNING_ALLOWED=NO`，且签名错误没有成为脚本的非零退出码。
仓库脚本保留上游 helper ZIP SHA256、bundle ID、entitlement 和 hardened runtime；
只有显式 unsigned development 构建不调用签名，仍保留真实 helper。
signed 构建缺少身份、签名失败或验证失败均退出失败，不自动降级。

本次只处理开发包的构建和归档。unsigned 包仍不能证明 Apple 受限权限、签名、
公证、MDM 激活或严格流量可用；不要求关闭系统安全。已有正式签名流程不改动。

## 验证记录

- Windows / Python 3.13：`python -m unittest discover -s tools/macos/tests -p 'test_copy_login_helper.py' -v`，14 项 PASS，0 FAIL / SKIP；覆盖 unsigned 完整复制、signed 参数/验证、身份缺失、签名/验证失败、ZIP 完整性、entitlement 缺失、路径边界、Debug 身份、10.14.3/10.14.4 helper 分界、复制失败、CLI 非零错误与失败前保留已有 helper。
- workflow YAML 解析、4 个 Bash 步骤 `bash -n`、`git diff --check`：PASS。Bash 路径先尝试默认安装位置未找到，改用本机实际 `E:/Git/bin/bash.exe` 后通过；未执行这些构建步骤。
- 测试仅用临时构建目录和模拟 macOS 子进程；不访问 Keychain，不运行真实 codesign，不安装 helper。
- macOS Xcode 完整构建、签名证书、设备激活和真实转发：本机 NOT RUN；需以最终 PR head 的 macOS CI 和后续专机验收分别记录。

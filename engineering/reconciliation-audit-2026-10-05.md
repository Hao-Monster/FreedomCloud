# 本地开发成果归属核查（2026-10-05）

## 范围与基线

本记录用于安全整合前的来源核查，不是正式发布或平台验收报告。审计基线为当次已核实的自有远端主线 `freedomcloud/main`：`cc1d31bc8b24b0103bc78dea2453768cb0c5a339`。新集成分支 `codex/purchase-integration-20261005` 从该最新主线建立，购买功能按来源提交重新整合；旧分支、旧工作树和原稿保留，未执行删除、清理或 stash pop。

核查方法：读取 worktree/状态；逐文件计算经 Git 属性规则处理的 working blob，与主线及历史集成提交比较；对不完全相同的文件阅读差异和后续修正。历史提交均核实为审计基线的祖先。未提交文件、未合并提交、主线中已经存在的功能分别记录，不能把旧工作树显示 dirty 直接等同于遗漏功能。

首次清点为 40 个 worktree：21 个干净、18 个正常有改动、1 个初始化异常。18 个正常工作树共有 152 个变更文件项，其中 92 项内容与主线完全相同、50 项内容不同、10 项在主线无同路径。此数目是整合前快照，不是持续更新的工作树数量。

本记录逐项覆盖其中非 macOS 专项组的 34 个不同文件，以及签名更新目录的 2 个补丁草稿。macOS 专项工作树的完整核查由独立审计负责；本记录不以局部结果代替该专项结论。

## 逐组归属与反回退依据

表内工作树使用目录短名，文件路径均相对于各自仓库根目录。下列“已吸收”仅表示来源功能已进入代码主线，不表示真实设备或签名发布验收完成。

| 工作树 | 文件 | 分类与确证提交 | 整合处理 |
| --- | --- | --- | --- |
| `FlClashX-app-selector-dev` | `lib/views/connection/settings.dart` | working blob 精确等于 `c86cf48`；应用发现、选择器功能已吸收 | 保留主线后续版本，不覆盖整文件 |
| `FlClashX-identity-upgrade-dev` | `lib/clash/agent_protocol.dart`、`lib/clash/service.dart`、`services/agent/Cargo.lock`、`services/agent/Cargo.toml`、`services/agent/src/lib.rs`、`services/agent/src/protocol.rs`、`services/agent/src/runtime.rs`、`services/strict-broker/src/dispatch.rs`、`services/strict-broker/src/lib.rs`、`services/strict-contract/src/lib.rs` | 10 个 working blob 均精确等于 `c86cf48` | 身份迁移与持久恢复已吸收，保留后续主线改进 |
| 同上 | `lib/views/connection/settings.dart` | 相对 `c86cf48`，旧文件仅缺少同批整合的应用选择器、最近联网应用、符号链接解析及路径错误处理 | 被集成后的版本替代；回灌会丢失选择器功能 |
| `FlClashX-p2-config-rules` | `core/common.go`、`core/hub.go`、`lib/views/config/effective_config.dart` | working blob 精确等于 `6e22112`；`effective_config.dart` 后由 `3a0e56d` 补齐必要 import | 配置快照功能已吸收，保留主线 |
| 同上 | `lib/views/config/rules_editor.dart` | `6e22112` 在草稿基础上增加 `normalizeConfiguration` 及 JSON 对象规则编辑；`3a0e56d` 补齐必要 import | 旧稿被改进替代，不退回不支持 JSON 列表编辑的行为 |
| `FlClashX-p2-tray-route` | `lib/views/connection/settings.dart`、`macos/Runner/AppDelegate.swift` | working blob 精确等于 `3d592f3` | 托盘策略导航已吸收，保留后续平台集成 |
| `FlClashX-signed-update` | `macos/Runner/AppDelegate.swift` | 相对 `05ef3c9`，旧文件只缺少此前 `3d592f3` 引入的 `menuChannel`、`updateMenu`、`updateRates` | 签名及受保护 Core 功能已吸收，不能用旧文件删除托盘功能 |
| 同上 | `lib/common/signed_update.dart` | 相对 `05ef3c9` 仅旧“业务验收”文案；`d89f7df` 后续修复共享异步初始化 | 保留初始化并发修复；不为旧文案覆盖逻辑 |
| 同上 | `lib/common/signed_update_windows.dart` | 相对 `05ef3c9` 仅说明注释和缺少 `-WindowStyle Hidden` | 保留主线隐藏启动参数和真实安装行为说明 |
| 同上 | `lib/widgets/signed_update_dialog.dart` | 相对 `05ef3c9` 仅旧“业务验收”提示文案 | 无独有功能需补入 |
| 同上 | `macos-core-update.patch`、`macos-local-development.patch` | 补丁所含路径更新、签名验证、受保护 Core、ad-hoc 开发授权已应用于草稿且由 `05ef3c9` 吸收 | 保留补丁备份，不重复应用 |
| `FlClashX-strict-health-dev` | `core/common.go`、`core/strict_ingress.go`、`core/strict_proxy_route.go` | 相对 `3ab7416` 仅空白/缩进差异 | 严格转发与禁止直连回退已吸收，无需回灌格式草稿 |
| 同上 | `services/agent/src/runtime.rs` | working blob 精确等于 `3ab7416` | 保留主线后续恢复实现 |
| 同上 | `windows/strict-driver/src/driver.c` | working blob 精确等于 `3ab7416`；主线 `a80763e` 修复失败分配清理中的 canary 计数 | 禁止旧文件覆盖该修复 |
| `FlClashX-strict-integration` | `services/agent/src/runtime.rs`、`services/agent/src/strict_flow.rs` | broker 恢复监督、退避、`broker_lost`、`recover` 已被 `c86cf48` 吸收；集成版本另含意图持久化、恢复禁用状态、身份迁移、认证禁用确认、UI 状态推送 | 保留完整主线实现，旧整文件会删除这些保护 |
| 同上 | `setup.dart` | 旧稿缺少 `488aa6a` 的签名后计算 Core 哈希、组件签名、新 manifest 和禁止复用旧 broker 等步骤 | 保留主线签名构建链 |
| 同上 | `windows/packaging/exe/inno_setup.iss` | 旧稿缺少 `05ef3c9` 的 `/FCXUPDATE` 判断 | 保留受管更新安全退出，不恢复无条件强杀进程 |
| detached `m3-1-source-provenance-metadata-v2` | `engineering/test-package/BUILD-INFO.txt.in` | 内容与 `aaca0cf` 相同，来源功能来自已合并的 `b754f77` | 来源元数据已吸收 |
| 同上 | `setup.dart` | 相对 `aaca0cf` 仅环境变量空值处理写法不同；主线使用 `rawEnvState` 再规范化 | 没有遗漏来源字段，保留主线写法 |
| detached `m3-2-zip-v4` | `engineering/m3-test-package/New-DeterministicZip.ps1` | 比主线多出的写后时间戳设置实际失败，详见下节；正确实现来自 `9ddf175` | 错误草稿保留备份，拒绝整合 |

此组没有发现应补入主线的独有有效功能。结论来自历史归属和差异语义核查，而非仅根据文件存在或 diff 数量推断。

## ZIP 草稿失败证据

旧草稿比主线多出在 entry stream 写入、关闭后，再次设置 `LastWriteTime` 和 `ExternalAttributes` 的代码。主线 `9ddf175` 已在 `entry.Open()` 之前设置固定时间戳与属性。

在本机以纯内存 `MemoryStream` 和 `ZipArchive(Create)` 复现相同操作顺序，无磁盘文件写入。写完 entry 后再次设置 `LastWriteTime` 返回：

```text
System.IO.IOException
Cannot modify entry in Create mode after entry has been opened for writing.
```

因此不能把这段独有差异当成遗漏修复。仅保留备份和本记录，不合入源码。

## Stash 与待单独整合项

独立 stash 审计的结论由主代理提供：18 个文件的功能已被主线吸收，其中 15 个内容精确相同，3 个由主线后续改进替代。本文件未重复执行该专项审计，不将转述结论表述为本审计者独立验证。stash 当前保留，不执行 drop/pop。

`FlClashX-test-portable-20261002` 的 4 项真正未提交增量不在上述“已吸收”结论内：`lib/clash/service.dart`、`lib/clash/windows_agent_launch.dart`、`test/clash/windows_agent_launch_test.dart`、`engineering/test-package/Initialize-StrictTest.ps1`。按启动与权限单元单独追踪，不与购买功能混成一个逻辑变更。

`FlClashX-macos-test-package-20261002` 清点时工作树干净；其已提交代码是否整合由分支/提交台账另行记录。主工作树清点时仅有覆盖率、原生 QA 文档和测试探针未跟踪，无未提交生产代码；这些测试证据也应保留。

detached `m3-5-scm-lifecycle-v1` 显示 `locked initializing`，目录仅有 `.git`、index 不存在；其 HEAD 的 694 个文件因初始化不完整显示为 staged deletion。该状态不是 694 项业务删除，不自动恢复、清理或提交。

## 购买集成的独立静态复核

复核时购买来源 `7d02a94` 与集成分支中的 `lib/views/purchase.dart`、`lib/views/purchase/center.dart`、`lib/views/purchase/plan_catalog.dart`、`lib/manager/purchase_manager.dart`、`lib/services/xboard_api.dart`、`lib/models/xboard.dart` 无内容差异。新集成以最新主线为基线保留购买增量，而非以旧预览分支覆盖全仓。

- `setup.dart` 相对审计主线的购买差异仅涉及 Linux secure-storage 依赖和 AppImage 库打包。Windows 的组件签名、签名后 Core 哈希、manifest 生成及 broker 重建约束均保留。
- 套餐组件仍位于登录恢复和登录状态分支之前；公开套餐展示不被登录状态隐藏。
- 登录后仍调用账户、兑换查询/确认和历史区块；支持区块位于登录状态分支之外。两个原微信联系及复制入口仍在，礼品卡商店入口按既有渠道配置显示。
- 本复核没有发现购买整合造成的旧购买方式删除或签名链回退。没有运行 Flutter 命令、签名构建、系统服务操作或原生窗口测试；静态结论不替代集成分支的测试和后续运行验收。

## 保全与后续处理

原稿、旧分支、旧 worktree 和 stash 均保留。本次只建立功能归属依据，不构成清理授权。可恢复备份的目录、完整性和恢复演练由主代理的保全记录负责，本文不包含绝对用户路径、凭据或原始私有日志，也不宣称未经验证的备份已可恢复。

整合状态、来源到目标提交映射、PR、实际测试与剩余验收项统一更新到 `engineering/development-status.md`。不得通过回灌旧整文件删除主线后续修复。

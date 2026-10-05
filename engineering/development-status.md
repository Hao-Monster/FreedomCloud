# 开发、集成与预览台账

更新日期：2026-10-05。当前阶段是快速开发、快速迭代和部分功能预览。本文记录来源与验收边界；每次继续开发仍需核实实际 Git/PR/CI 状态，不能把历史报告视为当前通过证明。

## 基线与保全

- 自有远端为 `Hao-Monster/FreedomCloud`（通常是 `freedomcloud`）；上游为 `pluralplay/FlClashX`（通常是 `origin`）。本轮核实的自有主线为 `cc1d31bc8b24b0103bc78dea2453768cb0c5a339`。
- 本地 `main` 跟踪上游，旧 `development` 也落后于自有主线。它们被保留，不自动重置或用作新增量的默认基线。
- 原购买来源分支 `codex/m3-7-helper-diagnostics` 的提交保留；远端 `codex/purchase-source-snapshot-20261005` 另存其源历史。新的集成在独立工作树进行。
- 初始 40 个工作树、全部本地 refs、stash 及 detached HEAD 已归入私有离线 bundle 和逐工作树快照。未提交文件保存精确副本、SHA256 及暂存/未暂存二进制补丁；忽略文件另行保存，不能只依靠 Git bundle。
- 恢复演练：16 个实际有未提交内容的工作树从独立 bundle 恢复后，文件 hash、Git 状态及暂存内容一致；23 个干净工作树 HEAD 已验证；1 个初始化异常另行保全。初次审计与备份时刻的 dirty 数量因生成文件的换行规范化而不同，不混为同一快照。
- 忽略文件归档已完成：164,527 个文件、42,850,666,804 字节逐文件 SHA256 核验通过，0 错误，复制期间未发现源文件变化。Windows 长路径复制的首次失败已通过续传和重新核验解决。另复核了原快照的 137 个现有变更文件，原位置内容仍与整理前一致。
- `locked initializing` 工作树缺 index、仅有 `.git`，694 个缺失文件不视为有意删除。其 `9ca5644` HEAD 已从离线 bundle 在隔离目录成功检出 694 个跟踪文件，状态干净；原异常目录保持不动，未提交这些删除状态。
- 所有原工作树、旧预览包和唯一 autostash 仍保留。忽略文件的最终完整性、私有路径和恢复步骤以仓库外备份清单为准；不将原始日志、凭据或测试账户状态推到公开仓库。
- 私有快照当前只在本机，远端分支保存经审查的源码。它不是操作系统、证书库或异地灾备，不以“已备份”推导可以删除原稿。

## 来源与集成映射

| 工作单元 | 原始来源 | 整合提交或分支 | 远端追踪 |
| --- | --- | --- | --- |
| 原生礼品卡购买中心 | `43ed4e2` | `ac58869`，`codex/purchase-integration-20261005` | [PR #56](https://github.com/Hao-Monster/FreedomCloud/pull/56) |
| MSVC/Ninja 警告参数修复 | `622abe1`；便携包分支 `f8c2d6a` 为相同 patch-id | `c463c32`，只吸收一次 | PR #56 |
| 未登录套餐与价格展示 | `7d02a94` | `33a8de2` | PR #56 |
| 项目协作规则 | `04be72f` | `cafb7a7` | PR #56 |
| 非 macOS 旧工作树归属审计 | 逐文件与历史提交核查 | `e9057cc` | PR #56 |
| Windows 受保护 Agent 启动和严格模式测试初始化原稿 | `FlClashX-test-portable-20261002` 的 4 个未提交文件 | `eac3938` 运行时、`780b31c` 安装预检，分支 `codex/protected-launch-20261005` | [PR #57](https://github.com/Hao-Monster/FreedomCloud/pull/57) |
| macOS 构建与完整开发包 | PR #55 原 head `7cce2da` | `ddc6965` 正常合并主线，`82ac8a4` 修复 helper，`4de17bd` 修复测试路径别名，`62d53a7` 拆分嵌入文件引用以匹配当前配置 | [PR #55](https://github.com/Hao-Monster/FreedomCloud/pull/55) |

购买、Windows 启动/测试安装、macOS 打包分为独立 PR；本轮未自动合并主线。未来合并前检查最终 head 的 CI、冲突和剩余验收范围。禁止从旧预览工作树整文件覆盖当前主线。

## 旧稿归属结论

- 非 macOS 34 个不同文件与 2 份补丁草稿，均已吸收、被主线改进替代或属于无效草稿，未发现应重复移植的独有有效功能。逐项证据见 PR #56 的 `engineering/reconciliation-audit-2026-10-05.md`。
- macOS 5 个旧工作树共 50 个文件条目：35 个与主线一致，15 个属于格式或主线后续修正；无需用旧文件回灌。详见 PR #55 的 `engineering/macos-reconciliation-2026-10-05.md`。
- autostash 共 18 项：15 项已精确吸收，3 项由后续主线改进替代。保留 stash，不 pop/drop。
- 构建链 `47438c1`、连接性能 `b77972f`、诊断隐私 `2a50b01`/`63c0d57` 虽仍显示本地独有提交，`git cherry -v freedomcloud/main` 均为 `-`，等价补丁已在主线，不能当作四项遗漏再次合入。
- `m3-2-zip-v4` 的独有草稿在 ZIP entry 打开写入后设置时间戳，已在内存复现 IOException；主线在打开前设置正确。保留草稿备份，拒绝合入错误行为。
- 旧 UAC 提交 `f082792` 的等效防重复提示行为已被 `99df219`、`bbece1b`、`6eb440b` 吸收，不按提交 SHA 不同判断为遗漏。
- 主工作树原有覆盖率、原生 QA 报告和焦点探针保存在原目录及私有快照中；它们不是未经审查即可公开上传的生产代码。

## 实际验证与预览边界

| 工作单元 | 已有证据 | 未代表的能力 |
| --- | --- | --- |
| 购买集成 | 本地 Flutter 全量 261 PASS，0 FAIL/SKIP；目标 Dart analyze 无问题；3 个 M3 包工具/manifest/evidence 脚本 PASS；`e9057cc` 对应 [CI 37293130664](https://github.com/Hao-Monster/FreedomCloud/actions/runs/37293130664) 的 Flutter、Go、package 三项 PASS | 不代表已在最终集成 SHA 重新做本机完整业务验收、签名发行或后端部署 |
| Windows 受保护启动/测试安装 | 23 项 Dart 测试、68 项只读安装预检用例和 3 个既有包工具脚本 PASS；路径异常 mutation 按预期失败，恢复后回归 PASS；两项审查缺口均已关闭；`780b31c` 对应 [CI 37295298644](https://github.com/Hao-Monster/FreedomCloud/actions/runs/37295298644) 三项 PASS | 本机未运行安装器、修改服务、安装驱动或切换网络；需要隔离 VM 验收 |
| macOS 开发包 | 本地 19 项 helper/工程合同测试和两份上游 ZIP SHA256 核验 PASS；`62d53a7` 的 [质量门禁 37296920008](https://github.com/Hao-Monster/FreedomCloud/actions/runs/37296920008) 三项 PASS；[完整构建 37296914010](https://github.com/Hao-Monster/FreedomCloud/actions/runs/37296914010) 的 Xcode、归档及上传均 SUCCESS | 命令行覆盖曾未解决旧产品引用问题，已移除并保留失败记录；当前产物明确为 unsigned arm64 开发包，不等同于 Apple 签名、公证、激活或真实设备验收 |

本机 Flutter 3.47.4 / Dart 3.13.3；CI 使用仓库固定 Flutter 3.41.7。Windows 相关新 Dart 文件 analyze 无问题；包含既有 `service.dart` 时有 13 项原有提示（1 warning、12 info，exit 2），与独立检查的主线基线相同，没有以修改规则消除这些提示。安装器验证使用 PowerShell 7.6.5 和临时文件/签名替身，不能代替真实 Authenticode、服务或驱动验收。

2026-10-04 的原生测试结果对应原来源与当时包，不回写成当前集成分支的运行证明。本次没有消费新的礼品卡。

仍需单独追踪：此前原生测试发现的 Helper 修复/UAC 问题；Windows 严格模式 VM、真实流量及签名验收；macOS Apple 签名、公证、受管激活和设备流量。未签名 macOS 开发包只能如实标记 unsigned，不要求用户关闭系统安全。

## 后续开发顺序

1. 读取项目 `AGENTS.md`，核实自有最新主线及上述 PR 的最终 head；按任务依赖选择分支。新独立任务默认从最新自有主线建立 `codex/<topic>`。
2. 一次推进一个可测试增量；小范围相关门禁通过即可提供标明来源和缺口的部分预览，不把全平台正式发布门禁强加给每次 UI 迭代。
3. 对需共享的代码及时形成可审查提交和经授权的远端 PR；更新本台账，记录源提交、实际运行的检查、预览 hash 和未验收项。
4. 主线合并、正式发布和历史清理分别按授权执行。保全完成不是自动删除旧分支、工作树或 stash 的授权。

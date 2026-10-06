# 开发、集成与预览台账

更新日期：2026-10-06。当前阶段是快速开发、快速迭代和部分功能预览。本文记录来源与验收边界；每次继续开发仍需核实实际 Git/PR/CI 状态，不能把历史报告视为当前通过证明。

## 唯一开发入口（2026-10-06）

- 用户要求收敛为一个日常开发分支和受保护的 `main`。今后日常只在 `development` 开发，默认工作目录为 `E:\CodeWorkstation\FlClashX`；旧任务分支和工作树只保留追溯，不继续写入。详细流程、门禁、任务与回退见 `engineering/plans/single-development-2026-10-06.md`。
- 本地 `main`、`development` 已从各自祖先无 force 快进到自有主线 `4738293ea90ca9b90afcc201a5c9a09b729a86ad`，当前检出 `development`。本地 `main` 已由跟踪上游 `origin/main` 改为跟踪自有 `freedomcloud/main`；开发分支跟踪并推向 `freedomcloud/development`。
- 日常小提交正常推送开发分支；按验收批次创建一个 `development → main` PR。普通 merge 后同步 `main` 回开发分支，避免 squash/rebase 长期分支造成重复提交和冲突。主线合并和正式发布分别按当次授权执行。
- 迁移前新建私有全 refs bundle，并完成 verify、离线 mirror 恢复和 fsck；5 份原稿逐项复制/hash 一致，原来源分支和 stash 未改动。95,620 个忽略文件及 5 个未跟踪文件与目标的 798 个跟踪文件没有同名或父子路径覆盖；实际切换使用 `--no-overwrite-ignore`。此前大备份和全部旧工作树保留，异地副本仍另行安排。
- 云端保护于 2026-10-06 07:28 UTC 配置并回读确认：开发分支只移除接收提交前的必需 CI 状态，正常推送后仍运行 CI；主线新增必需 PR、0 个必需审批，保留原有三项 CI、严格更新、讨论解决、管理员适用和禁止强推删除。其余保护字段逐项比较不变，API 前后快照保存在私有恢复目录；后续开工仍需核实最新设置。
- 本次 CI 改动仅为 quality-gate 增加 `push main`，已有测试命令与固定工具版本不变。该修改进入 `main` 前，旧主线仍不监听 push main；进入后才会产生最终主线提交检查。开发分支推送不触发现有正式发行；macOS 预览仍可手动触发，不默认增加每次提交的全平台构建。
- 本轮不合并新的主线 PR、不创建标签、不发布版本、不运行本机代理程序；此前 Windows/macOS 运行验收边界保持原记录。推送后以开发 HEAD 对应的实际 Actions 结果及本次最终报告为准，不能沿用上一批次 CI 作为新提交通过证明。

## 本轮主线集成进展

用户已接受先研究方案、规划任务，再执行主线集成和 Windows 普通预览；异地备份单独安排。执行方案见 `engineering/plans/mainline-windows-preview-2026-10-05.md`。以下是 2026-10-05 的新结果，后文保留首次整理时的来源与验证记录。

| 工作单元 | 最终 PR head | 新组合验证 | 主线合并 |
| --- | --- | --- | --- |
| PR #56 购买中心/匿名套餐 | `eeaf6b0468177313bb98709eb421c01757a97fb5` | quality-gate `37298035201` 三项成功 | `1efc29fe4aaeb29d849a4cd7be4b0728f66ca528` |
| PR #57 受保护启动/安装预检 | `5b2d8a9e88414327174e8bf241c86da89cc338f8`，正常合入 #56 后重验 | quality-gate `37307123153` 三项成功 | `6b6d1532e55b5c0717986a588f25c4ec86d1d34f` |
| PR #55 macOS 开发包 | `0ce398967a0299a0b5bcb97ab8cbc5aed1727bf9`，正常合入 #56/#57 后重验 | quality-gate `37307467535`；完整 macOS 构建 `37307460810` 均成功 | `14571208a15c732b11522da6607212d559ee2695` |
| PR #58 购买焦点与操作进度 | `694cec8f2bfe2f614067b325fbb4542ac1582d53` | [quality-gate 37310446707](https://github.com/Hao-Monster/FreedomCloud/actions/runs/37310446707)：Flutter 290 PASS、Core Go、M3 package checks 成功 | `863298c7e3f44e821eb6df5dedeb97f95d31d987` |

前三项均以普通 merge commit 合并，没有改写历史或删除源分支。主线 `1457120` 已验证包含三个原始 PR head，其 tree `5407871e914f5f326ed1316208566b4c4c38b838` 与最后受检组合 `0ce3989` 完全一致。当前工作流不监听 push main，不能把合并前检查称为自动发生的主线检查。

随后 [PR #58](https://github.com/Hao-Monster/FreedomCloud/pull/58) 也以普通 merge commit 合并。Windows 预览的功能源码基线为 `863298c7e3f44e821eb6df5dedeb97f95d31d987`，tree `18d658d6f785518012f5bfa6cab437582531948e` 与最终受检 head `694cec8` 一致；后续仅记录交付证据的文档提交不改变该包的构建来源。

组合 macOS 产物经过本地 SHA256、ZIP CRC、host/provider/helper 标识和 arm64 二进制核对，PASS：55,252,135 字节，SHA256 `c4e9c5fa88af8f29b1b4dcf252982db7dc898a61bf93c63434e6fb78ff7433d0`，来源严格为 `0ce3989`。它仍为 UNSIGNED，签名、公证、激活和真实设备运行 NOT RUN。

集成前另做增量保全：169 个 refs、4 个关键 HEAD/tree、唯一 stash 在独立 bundle mirror 中恢复一致，5 份原始未跟踪文件逐项 hash 一致。新增 bundle SHA256 `e2709fe9ee3bb10068abc99d50b8a8aee010f3427b78c964fe705055cca6cce4`；原有大归档、旧工作树和原稿保留。私有证据留在仓库外，未上传账号、卡号、订阅内容或原始日志。

四项合并后再做增量保全：新 bundle 235,929,439 字节，SHA256 `b82cd392fc98f5e4399c9cd392aaab4d628489621d9d62797771027633fb95e4`；`git bundle verify`、离线 `clone --mirror` 和 `git fsck --full --strict` 均 exit 0，172/172 refs 完整恢复，7 个关键提交的 tree 一致。原 HEAD、5 份原稿、stash 和两份旧 bundle 的哈希不变。临时 `refs/codex/turn-diffs` 数量变化已逐对象核对，不是用户分支或源码丢失。此快照对应源码整合完成时刻，不包含随后构建缓存；异地副本按用户决定另行安排。

本轮 Windows 预览前已修复 QA001 登录焦点和 QA003 操作进度文案：生产购买正文隔离侧栏焦点遍历，查询/兑换分别显示本操作进度，保留全局互斥和原消费逻辑。真实宿主/manager 回归在修复前为 6 PASS/6 FAIL；扩充后的最终目标测试 15 PASS，购买模块 181 PASS，均 0 FAIL/SKIP。变更 Dart 文件 `analyze --fatal-infos` 与 format 检查通过；测试边界和后续运行结果分开记录，不能把组件测试当 Windows 实机验收。

匿名目录于 2026-10-05 12:37:51 UTC 实际执行一次无 Authorization/Cookie 的 GET，HTTP 200、TLS 校验通过；同一响应经生产解析器离线验证成功。返回 1 个套餐、200 GiB，`onetime` 整数金额 15000 按客户端规则显示为 150.00；接口没有币种字段，不推断币种。此证据不代表 Windows 新包页面已验收。

Helper 重连调查见 `engineering/testing/helper-reattach-investigation-2026-10-05.md`：已确定调用链与状态缺口，但历史唯一触发入口未证实，也没有以恢复布尔值绕过信任检查。完整 Helper 修复和严格模式仍需要隔离环境；本机 UI 验收与新 native 全栈运行分别记录。存在自动订阅更新时，单纯打开新 UI 仍可能触发配置应用和授权；不能从“先连接旧 Agent”推断后台绝对不变。

Windows 普通免安装包已从上述 `863298c7` 干净源码完成重编，交付 `dist/FreedomCloud-windows-amd64-preview-863298c7e3f4.zip`，139,359,772 字节，SHA256 `cae86090054186ed680e3467025f857badfca1a9f9670cfd6de9c98c4a0cafbd`。72 文件完整解压及交付副本逐文件校验通过；未运行该包，原生验收仍为 NOT RUN。环境适配、失败历史、实际命令结果和受控测试条件见 `engineering/testing/windows-preview-build-2026-10-05.md`。

## 基线与保全

- 自有远端为 `Hao-Monster/FreedomCloud`（通常是 `freedomcloud`）；上游为 `pluralplay/FlClashX`（通常是 `origin`）。首次保全时的自有主线为 `cc1d31bc8b24b0103bc78dea2453768cb0c5a339`；后续集成结果见本文开头。
- 2026-10-05 首次保全时，本地 `main` 跟踪上游，旧 `development` 也落后于自有主线；当时保持原状。2026-10-06 的无 force 快进与唯一开发入口见本文开头，旧提交仍在新基线的祖先历史中。
- 原购买来源分支 `codex/m3-7-helper-diagnostics` 的提交保留；远端 `codex/purchase-source-snapshot-20261005` 另存其源历史。2026-10-05 的集成在独立工作树进行，之后的日常开发遵循本文开头的唯一开发入口。
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

购买、Windows 启动/测试安装、macOS 打包分为独立 PR；首次整理时未合并，随后经用户接受执行方案后按本文开头的顺序集成。每次合并都检查最终 head 的 CI、冲突和剩余验收范围。禁止从旧预览工作树整文件覆盖当前主线。

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

1. 读取项目 `AGENTS.md`，核实 `development` 本地/远端进度、未提交内容及自有 `main`；在唯一开发分支继续任务，不为独立任务默认新建分支或工作树。
2. 一次推进一个可测试增量；小范围相关门禁通过即可提供标明来源和缺口的部分预览，不把全平台正式发布门禁强加给每次 UI 迭代。
3. 对需共享的代码及时形成可审查提交并经授权推送 `development`；CI 和预览达到批次验收标准后，再创建一个晋级 PR。更新本台账，记录源提交、实际检查、预览 hash 和未验收项。
4. 主线合并、正式发布和历史清理分别按授权执行。保全完成不是自动删除旧分支、工作树或 stash 的授权。

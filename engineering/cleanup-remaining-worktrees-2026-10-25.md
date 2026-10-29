# 剩余旧工作树归属核查与清理（2026-10-25）

用户授权继续检查上一轮剩余 22 个工作树，核实草稿已合并、重复或被后续修复替代，在备份和恢复验证后清理不再需要的工作树。

**结果：21 个旧工作树全部移除，失败/跳过 0，仅保留 `E:\CodeWorkstation\FlClashX` 的 `development` 主开发树。产品源码未修改、未回灌任何旧整文件；全部分支和 stash 保留。**

## 基线与核查方法

- 语义比对固定为已提交的 `591481f8a6ce41a3376b09054673350c7c28c69d`。开工时主树存在新的购买页改动，检查期间推进至 `cb68fb938ea82f2d1f04b09c8d5e8de6c7fc891d`；该新提交已纳入本轮 bundle 并保留。其 20 个改动路径与 154 个旧草稿文件项没有交集，没有使用未提交购买页修改证明旧稿已合并。
- fetch 后本地 development 领先自有远端 13 个提交、远端无新增；无打开的晋级 PR。本轮没有远端写入或新 CI。
- 对每个草稿按 Git 属性计算 working blob，比较当前固定提交及已集成历史；对不同文件逐 hunk 检查后续实现及安全修正。三组独立只读核查分别覆盖 Windows、macOS、构建工具/预览草稿，根代理单独核对 UAC 和初始化异常。
- 21 个旧树的 HEAD、状态、binary patches 和 untracked hash 与上一轮私有快照一致，没有新草稿漂移。HEAD ancestry 只用于提交归属，未用它代替未提交内容核查。

154 个普通草稿文件项的机器 blob 核对与独立逐 hunk 确认汇总如下，精确文件列表、blob、命中提交及语义分组见恢复目录的 `file-attribution.json`、`reconciliation-decisions.json`。下表按 blob 命中优先分类；后一个 JSON 保留人工语义分组，部分历史版本同时属于后续替代，两者分类口径不同、文件集一致。

| 分类 | 文件项 |
|---|---:|
| Git 属性归一化后与固定当前版本内容一致 | 76 |
| 精确对应已进入主线的历史版本，当前另有后续改进 | 47 |
| 经逐 hunk 确认已吸收或后续替代，含纯格式差异 | 28 |
| 内容已应用并吸收的重复补丁 | 2 |
| 已被正确实现替代的错误 ZIP 草稿 | 1 |
| unique / unknown | 0 / 0 |

## 逐树来源与结论

表中省略 `E:\CodeWorkstation\` 前缀；特殊位置明确列出。历史来源报告仍保留，本轮重新核对实际文件和提交，不把旧报告直接当作当前通过证明。

| 工作树 | 归属与反回退证据 |
|---|---|
| `.codex/worktrees/ordinary-preview-build-20261005/FlClashX`（用户目录下） | 7 个 generated plugin 文件均等于树 HEAD 和 `591481f`；binary patch 为空，是 CRLF/stat 状态。 |
| `FlClashX-app-selector-dev` | 应用发现/选择器已进入 `c86cf48`；当前保留最近联网应用、canonical path 和路径错误处理。 |
| `FlClashX-identity-upgrade-dev` | 身份迁移、strict store/retry 和持久恢复已进入 `c86cf48`；旧 settings 缺后续选择器功能。 |
| `FlClashX-installer-release` | 8 项 working blob 均等于自身 HEAD，未产生内容增量；旧 Core 版本由 `1f750b1` 固定版本取代，插件注册由 `ac58869` 补全。 |
| `FlClashX-m3` | 7 项 plugin working blob 均等于自身 HEAD；当前保留 `ac58869` 的 secure-storage 注册。 |
| `FlClashX-m3-test-signing` | 干净、HEAD 已进入固定基线；SDK/WDK、测试驱动和证据作为完整普通文件载荷归档，不丢弃离线输入。 |
| `FlClashX-mac-mdm-xcode` | `5826ba1` 已集成；Xcode 对象顺序/缩进无独有功能，保留 `82ac8a4` / `62d53a7` 的 helper 和 embed 修正。 |
| `FlClashX-macos-managed-host` | `5826ba1` 已吸收，保留私有 stdin token、单 profile/connect-only/quarantine、后台 Agent 与非可空 appRules 修正。 |
| `FlClashX-macos-managed-provider` | 当前 FCXD 的 generation/association/HMAC/replay 机制替代 UDP ASSOCIATE；Keychain 限额及错误文案已由 128 KiB 更新至 4 MiB。 |
| `FlClashX-macos-strict-core` | `5826ba1` / `cc1d31b` 已吸收；当前 `config_runtime.go` 绑定严格入口恢复并保留回滚，`879c0e1` 修正 journal guard 解引用。 |
| `FlClashX-macos-strict-dev` | `7a6417d` / `5826ba1` 已吸收模型、身份和流转发；公共模型移入 `StrictProxyModels.swift` 并增加 DNS/UDP/generation 约束。 |
| `FlClashX-p2-config-rules` | `6e22112` 已吸收快照；保留 JSON 对象规则编辑和 `3a0e56d` import 修正。 |
| `FlClashX-p2-tray-route` | `3d592f3` 已吸收；保留 AppDelegate menu channel 和 `71a07a9` 托盘资源/刷新串行修正。 |
| `FlClashX-signed-update` | `05ef3c9` 已吸收原稿及两份 patch；保留托盘、`d89f7df` 共享异步初始化和隐藏启动参数。 |
| `FlClashX-strict-health-dev` | `3ab7416` 已吸收；保留 `a80763e` 的 canary 失败分配清理修复，禁止用旧 driver 覆盖。 |
| `FlClashX-strict-integration` | 保留 `c86cf48` 的意图持久化、身份迁移和认证禁用确认，以及 `488aa6a` 签名后 Core hash/manifest 链和 `/FCXUPDATE` 退出保护。 |
| `FlClashX-test-portable-20261002` | 4 个草稿由 `eac3938` 的统一 Agent 启动错误边界和 `780b31c` 的严格 VM/Win11/AMD64/PE/JSON 门禁增强替代；`f8c2d6a` 对 `c463c32` 为精确重复补丁。 |
| `FlClashX-uac-retry-control` | `f082792` 的 controller 对已集成 `bbece1b` 只有 import 排序；`_requestAdmin` 和原测试与固定基线精确一致；Gate 仅由 `6eb440b` 增加 async/unawaited 修正。保留原分支。 |
| `m3-1-source-provenance-metadata-v2`（`E:\Tools\codex-antigravity-worktrees`） | 来源元数据由 `b754f77` / `aaca0cf` 吸收；env 空值规范化写法不代表功能遗漏。 |
| `m3-2-zip-v4`（同上） | 旧稿写 entry 后再次设时间戳/属性会触发 Create-mode 错误；当前保留 `9ddf175` 的写入前设置实现，错误稿归档而不合入。 |
| `m3-5-scm-lifecycle-v1`（同上） | 目录只有 73-byte `.git`，无 index，lock=`initializing`；694 项 staged deletion 是未完成 checkout。HEAD `9ca5644` 已独立恢复出 694 个文件且 status 干净，保全 admin 后解除锁并移除登记。 |

补充来源：[非 macOS 历史归属核查](reconciliation-audit-2026-10-05.md)、[macOS 历史归属核查](macos-reconciliation-2026-10-05.md)。这些源码归属结论不代表签名、MDM、驱动、真实网络或设备验收通过。

## 完整载荷保全与恢复门禁

私有恢复目录：`C:\Users\冯飏\AppData\Local\FlClashX-Recovery\cleanup-remaining-20261025`。该目录含原始草稿、配置和产出，只保存在本机。

- `repository-all.bundle`：236,895,760 bytes，SHA256 `2353fa836778a36402bc806ea3e3ba841eaed853bcbe968470a701ab523e221a`。22 个 HEAD 验证、独立 bundle clone、最终 bundle verify / `fsck --full` 均 PASS。19 个普通脏树的 staged/unstaged 二进制补丁、untracked 已完成恢复验证；初始化异常另行恢复 HEAD。
- 每个 `worktrees/NN` 保存原始状态、binary patches、untracked ZIP/hash，以及 **全部普通文件**的 `complete-payload.zip` 和 manifest。覆盖 tracked、untracked、ignored 的源码、依赖、组件和证据，共 **32,309 文件、5,179,543,944 bytes**；ZIP 合计 **2,191,086,505 bytes**，均实际解压并逐文件 SHA256 比对通过。
- 重要 ignored 内容包括旧 native 组件、SDK/WDK、`package_portable.dart`、`m3-signed-fixture.zip` 及 manifest、旧 runner Release 测试目录。旧 Release 缺完整 BUILD-INFO、Broker、驱动和成包清单，按历史不完整测试产出保存，不标为完整回退包。
- Git 共用 admin 单独保存为 `git-admin.zip`。根 `.git` 指针另记 hash；reparse 不遍历目标，保存链接路径、类型和目标。NTFS ACL、备用数据流与系统服务状态不属于此源码/产出恢复档，不宣称系统镜像。
- portable 的 `windows/strict-driver/packages` 是指向主开发树共享 SDK/WDK 的 junction；目标不在 21 个删除根内。该目录 **8,820 文件、1,544,993,900 bytes** 的前后完整 SHA256 核对 PASS。只移除了 junction 本身，目标保留。其他链接均为已核实 plugin 叶链接。
- 每次移除前再次核对 HEAD、branch、status、两份补丁、根 `.git`、完整普通文件集合及 SHA256、ZIP hash、链接集合和目标。全部链接预检后用无 `-Recurse` 的操作移除链接，再正规 `git worktree remove --force`；异常现场另断言根只含 `.git`、无 index、原 HEAD 和初始化锁。

删除后、写入本轮文档前：主树仍为 `cb68fb9`，购买页提交及 5 个原 QA/coverage/probe 未跟踪文件保持原样；全部 refs/stash 一致；最新和上一 ZIP、现役五个 EXE hash 一致；现役 UI/Agent/Helper/Core PID 集合一致。21 份载荷 ZIP 再次校验通过，共享 SDK 全文件 hash 一致。没有停止/重启组件、修改代理/TUN/节点/用户配置或运行候选。

上述验证通过后，4 个恢复演练副本已全部清理，共 6,602,137,282 bytes；保留 ZIP、bundle、manifest、来源矩阵和恢复结果。精确路径与执行结果记录于 `rehearsal-cleanup-plan.json` 和 `deletion-journal.jsonl`。清理窗口 C/E 可用空间观测净增 8,124,440,576 bytes，该值包含新归档开销及其他进程写盘影响，不能全部归因为删除旧树；旧树本身的普通文件长度为 5,179,543,944 bytes。最终计量及交付状态见私有目录 `cleanup-summary.json` / `delivery-record.json`。

本轮仅本报告和开发台账形成新的本地文档提交。未推送、未创建/合并 PR、未发布新预览或部署；产品代码没有移植或修改，编译与真实系统/业务验收 NOT RUN。所有旧分支仍可追踪，归档与恢复清单继续保留。

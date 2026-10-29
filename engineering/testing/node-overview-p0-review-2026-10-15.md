# P0 评审修复与复验

## 范围与测试基线

用户评审 `c8fa0a3` 后指出四项验收问题，本轮基于 `development@5a38b1a` 修复。fetch 后领先自有远端 3 / 落后 0，无开放 PR；最新远端 CI 仍对应 `2074cce`，不代表本轮通过。只做本地修改、测试及提交，不推送、不运行候选包、不连接现役 Core/Agent 或操作代理/TUN。

| 问题 | 修复验收 | 验证层级与失败场景 | 测试文件（`test/` 下） |
|---|---|---|---|
| R1 控制流覆盖健康结果 | 成功、真实单请求失败/超时可写，其余不覆盖时间/数值 | store + coordinator；取消/切配置/隐藏/批次截止/传输错误；旧缓存迁移 | `common/node_health_store_test.dart`、`common/delay_test_coordinator_test.dart`、`common/node_overview_integration_test.dart` |
| R2 单坏节点拖垮配置 | 单节点无法识别可见，其余目录与历史正常 | catalog + recorder；peers-only、非map节点、同名歧义、超限、脱敏 | `models/node_catalog_test.dart`、`common/node_catalog_service_test.dart`、`common/node_health_recorder_test.dart` |
| R3 折叠摘要为空 | 视口内配置及宽侧栏可见配置自动只读构建 | Widget；未展开摘要、滚动、离屏不加载、搜索与服务并发上限 | `views/node_overview_test.dart`、`common/node_catalog_service_test.dart` |
| R4 接管已有 Core 不写历史 | 现有 fcx://runtime 与选中配置的可识别节点身份完全一致才采信 | 纯管线 + Provider/controller；一致/不一致/同端点改名/超时/读取异常/切换与删除迟返 | `common/node_runtime_catalog_test.dart`、`common/node_runtime_no_start_test.dart`、`common/node_runtime_race_test.dart`、`common/node_overview_integration_test.dart` |
| 次要 UI 问题 | 入口回工具栏、统一色阶、活动来源只取运行目录 | Widget、合成宽窄渲染、运行/磁盘差异 | `views/node_overview_test.dart`、`views/node_overview_render_test.dart` |

`fcx://runtime` 已有实现从真正 ApplyConfig 的快照读取；本轮不新增 Core 协议。此前认为接管需新增协议的判断不准确。测试只注入 IO 边界，实际用户运行链保持 NOT RUN。

## 修复结果与边界

1. **R1**：store 与 controller 只接受成功、`testFailed`、单请求 `deadlineExceeded`。取消、切配置、隐藏、关闭、准入和传输失败不覆盖旧值或时间。协调器把批次截止分离为 `batchDeadlineExceeded`，原超时提示保留。内部缓存 schema 升为 2，文件名仍是 `node_health_v1.json`。v1 曾把未知错误映射成 `testFailed`，故全部旧负值均不能证明节点失败，迁移只保留成功；旧真实失败也变成未测，先前被覆盖的好值无法恢复。v2 两种真实失败可正常写回并重载。
2. **R2**：结构或端点无法识别的节点成为 `parseFailed` 占位，只保存白名单名称/类型与显示 ID，端点键为空，不写历史、不纳入“仅可用”。合法兄弟节点照常展示和记录；合法/非法节点同名时都排除历史映射。整体容器错误或超过 2000 节点仍使目录明确失败。
3. **R3**：视口内折叠配置及宽屏侧栏可见配置会调用既有目录服务，保留最多 2 个并发、8 配置 LRU。40 配置测试验证离屏仍惰性、滚动才加载；显式搜索可以加载全部。活动配置的磁盘错误与实时健康摘要同时展示。
4. **R4**：手动测速开始时共享一次新的只读运行配置读取（3 秒截止），与文件目录的可识别身份排序列表完全比较，名称、类型、端点、重复数量都必须一致，空集合不能证明归属。原始 map 不保存到状态/日志。每次请求捕获当次确切 Future，配置代次使用立即可撤销令牌，防止变化后旧测速借用新快照；覆盖同 ID 更新、删除并同 ID 重建、新读先完成和旧读迟返。连续批次仅刷新供后续使用的 Future，不撤销旧批次在途校验；配置变化才一并撤销。测速无需等待验证才发出，结果到达时间独立捕获，保存偏好会等待所有新增在途健康写入。
5. **次要项**：范围切换放回原工具栏，窄窗菜单、宽窗分段控件；色带使用 `utils.getDelayColor`（覆盖 599/600ms 边界）；活动来源只取可信运行目录，未知时显示“运行时节点”。活动卡片的历史时间按其有效组 URL 读取，摘要按首个可见组去重并使用同一 URL，避免默认 URL 时间串到自定义 URL 的延迟旁。四语言同步。

默认只读入口先检查 `ClashCore.existingInterface`，缺失时明确失败，不构造 Core/service 单例。此 Dart getter 是唯一 Core 包装类改动；Go Core、Agent、Helper、协议、依赖和锁文件未变。对现有 `sendMessage` 和 `fcx://runtime` 的只读审查确认此读取路径没有 apply/start/restart/TUN 操作。测试也验证无接口时不会初始化服务，以及接管记录时 apply 次数为 0。

## 最终验证

环境：Windows，Flutter 3.47.4 / Dart 3.13.3，SDK 为 `E:/CodeWorkstation/toolchains/flutter/bin`。CI 仍声明 Flutter 3.41.7；本轮没有升级依赖，也没有运行远端 CI。最终原始证据在 `E:/Temp/fcx-node-overview-review-20261015`，全部用合成配置及独立临时健康文件。

| 命令 / 验证 | 状态 / 退出码 | 通过 / 失败 / 跳过 | 耗时 | 证据 |
|---|---|---|---|---|
| 12 文件目标套件 + 行/分支覆盖率（下方完整命令） | PASS / 0 | 130 / 0 / 0 | 54.61s 墙钟 | `targeted-verified.log`、`lcov-verified.info` |
| `flutter test --no-pub --concurrency=2 --reporter expanded` | PASS / 0 | 732 / 0 / 0 | 69.86s 墙钟 | `flutter-verified.log`、对应 result JSON |
| `flutter analyze --no-pub --no-fatal-infos` | FAIL / 1 | 0 error、11 既有 warning、851 info | 36.63s 墙钟 | `analyze-verified.log`、对应 result JSON |
| Windows debug UI 资源编译 | PASS / 0 | 不适用 | 34.26s 墙钟 | `ui-build-verified.log`、对应 result JSON |
| UI 行为 + 真实 ProxiesView 的合成渲染 | PASS / 0 | 26 + 2 / 0 / 0 | 18.91s 墙钟 | `ui-url-green.log`；400×800、1200×900 PNG，已人工看图 |
| 四语言 `dart run intl_utils:generate` | PASS / 0 | 不适用 | 未独立计时 | `intl.log`；无模型 schema 变化，不需 Freezed 重生成 |
| diff 与原稿保护检查 | PASS / 0 | 原 5 文件 hash 无变化 | 未独立计时 | `protected-hashes.json`；stash/历史工作树清单核对无变化（本工作树 HEAD 随本地提交推进） |

11 条 warning 均位于本轮未改的既有文件，已以 `git diff --quiet` 核对：`analysis_options.yaml` 已移除 lint；`connection_diagnostics.dart` 的 try 内未 await；`stats_grid.dart` 两处无效 `!`；`profiles.dart` 未使用 import；`proxies/providers.dart` 无效 `?.`；tray_manager 的 lint include 缺失；`setup.dart` 三个未使用 helper 与一处无效 `!`。没有新增 error/warning，没有禁用诊断或调整门禁；异步 IO 等 info 保留。

可复现命令（以下 `flutter` / `dart` 指向上述 SDK，`<evidence>` 替换为独立证据目录）：

```powershell
flutter test --no-pub --concurrency=2 --reporter expanded
flutter test --no-pub --concurrency=1 --coverage --branch-coverage --coverage-path=<evidence>/lcov-verified.info --reporter expanded test/models/node_catalog_test.dart test/common/node_catalog_service_test.dart test/common/node_catalog_pipeline_test.dart test/common/node_health_store_test.dart test/common/node_health_recorder_test.dart test/common/node_overview_integration_test.dart test/common/node_overview_providers_test.dart test/common/delay_test_coordinator_test.dart test/common/node_runtime_catalog_test.dart test/common/node_runtime_no_start_test.dart test/common/node_runtime_race_test.dart test/views/node_overview_test.dart
flutter analyze --no-pub --no-fatal-infos
flutter assemble '-dTargetPlatform=windows-x64' '-dBuildMode=debug' '--output=<evidence>/ui-debug-verified' debug_bundle_windows-x64_assets
dart run intl_utils:generate
$env:NODE_OVERVIEW_RENDER_DIR = '<evidence>/render'
$env:NODE_OVERVIEW_RENDER_FONT = 'C:/Windows/Fonts/segoeui.ttf'
flutter test --no-pub test/views/node_overview_render_test.dart --concurrency=1 --reporter expanded
```

最终合成渲染输出位于本轮证据目录 `ui-url-render/overview-{400x800,1200x900}.png`。首轮 UI 修复截图另保留在 `E:/Temp/fcx-node-overview-p0-37012ea1f6a9464c8c840c4c1c32752a/render-review/`。本轮通过真实 `ProxiesView + CommonScaffold + PageMixin` 工具栏渲染，没有启动产品 main 或候选进程。未指定输出环境变量时渲染测试不注册用例，因此全量计数不包含这两项，也不计为 skip。

## 覆盖率

LCOV 按 DA、BRDA 计数（没有 BRF/BRH），范围为 P0 的七个手写模块，包含本轮新增运行目录校验。它不是整个仓库或全部 diff 的覆盖率，controller/coordinator 由集成测试另覆盖。

| 文件 | 行命中 / 可执行行 | 分支命中 / 分支 |
|---|---|---|
| `lib/models/node_catalog.dart` | 39 / 39 | 6 / 6 |
| `lib/common/node_catalog_service.dart` | 104 / 106 | 43 / 48 |
| `lib/common/node_health_recorder.dart` | 40 / 40 | 22 / 22 |
| `lib/common/node_health_store.dart` | 170 / 173 | 62 / 67 |
| `lib/common/node_runtime_catalog.dart` | 25 / 25 | 15 / 16 |
| `lib/providers/node_overview.dart` | 84 / 115 | 44 / 65 |
| `lib/views/proxies/overview/overview.dart` | 435 / 462 | 129 / 146 |
| **合计** | **897 / 960（93.44%）** | **321 / 370（86.76%）** |

主要缺口：实际用户路径、IPC、QuickJS 执行边界使用测试替身；健康文件损坏隔离遭 OS 拒绝、部分 provider 生命周期与 UI 导航/组合分支未覆盖。已有强制覆盖率门禁未更改。no-start 用例单独验证生产默认读取入口在没有 Core 接口时安全失败。

## Red → Green、失败与独立审查

- R1 目标命令 `flutter test --no-pub test/common/node_health_store_test.dart test/common/delay_test_coordinator_test.dart --reporter expanded`：修复前 **28 PASS / 19 FAIL / 0 SKIP，exit 1**；修复后 **47 PASS / 0 FAIL / 0 SKIP，exit 0**。当时仅保存工具输出，没有独立日志或精确墙钟记录；最终 130 套件包含这些场景并已落盘。
- R1 迁移补审：`flutter test --no-pub test/common/node_health_store_test.dart --plain-name 'v1 migration drops all ambiguous failures and preserves success' --reporter expanded` 在旧迁移逻辑上 **0 PASS / 1 FAIL，exit 1**，实际多保留了旧 `testFailed`（`migration-red.log`）；最终目标套件通过。
- R2：目录/记录器目标修复前 **15 PASS / 6 FAIL，exit 1**，模型/目录/管线/记录器修复后 **30 PASS / 0 FAIL / 0 SKIP，exit 0**。日志位于 `C:/Users/冯飏/AppData/Local/Temp/fcx-node-catalog-partial-{red,green,analyze}.log`；分析 No issues found。没有独立精确墙钟计时。
- R3 与工具栏/色阶/活动来源：`flutter test test/views/node_overview_test.dart --concurrency=1 --plain-name 'review:' --reporter expanded` 新增 6 项目标行为先 Red 后 Green；补审又复现活动磁盘错误遮挡摘要，修复后两种错误状态均通过。补充 URL 用例前 UI 文件 **24 PASS / 0 FAIL / 0 SKIP**。该阶段单独运行及渲染仅保留工具输出，没有独立日志；UI/渲染末尾进度时间为 8s/2s，不是命令总墙钟时间。最终目标套件与全量回归已重新覆盖 UI 并落盘。
- 组级 URL 时间补审：`flutter test --no-pub test/views/node_overview_test.dart --concurrency=1 --plain-name 'active URL history matches group and first-group summary' --reporter expanded` 两项有效行为 Red，exit 1、12.08s（`ui-url-red.log`）；默认历史错误出现在自定义组、真实自定义历史未展示。修复后整个 UI 26 项加渲染 2 项通过（`ui-url-green.log`）。最初新增测试的 import 位置错误单独存为 `ui-url-setup-error.log`，不计为行为 Red。
- 连续批次补审：`flutter test --no-pub test/common/node_overview_integration_test.dart --plain-name 'new batch preserves an earlier pending verification' --reporter expanded` 在旧逻辑上 **0 PASS / 1 FAIL，exit 1**，预期两节点历史、实际仅一条（`batch-read-red.log`）。修复将读取刷新与归属撤销分开；新增两项验证不同节点连续批次历史都保留、配置切换时两条均拒绝。测试逆序完成两次 runtime IO，不据此声称完整校验或落库也严格逆序。
- R4 新接口先建立骨架，再补纯校验、controller 接线和独立竞态测试；不宣称有效行为 Red。首次运行因并行修改的国际化 getter 尚未生成而编译失败（`runtime-tests.log`），生成后解决。首版使用 `FutureProvider.future` 导致配置切换测试等待被替换的 future，主动中断该测试进程（`runtime-tests-final.log`）；改用独立原始 Future + 立即失效令牌后通过，并补两个同 ID 竞态用例。未中断产品或服务。
- 独立审查分别覆盖目录与隐式初始化、健康迁移、UI/测试缺口。发现并修复原始 Future 归属、flush 等待期间新增写入、v1 假失败迁移、活动摘要遮挡、URL 时间串用和连续批次漏历史。最终复核未发现本轮未解决 Critical/High；不把此结论当作真实环境验收。

## 交付、恢复与未运行

- 源码/测试提交：`2ecb4ece674dd9668ac6cdde355f8088cdcca4c3`（`fix(proxies): address node overview P0 review findings`）；本报告、工程书纠正和开发台账随后单独文档提交。均只在本地 `development`，没有推送、PR、合并、发布或部署。源码提交含 33 个任务文件；原有未跟踪资料未纳入提交。
- `FCX_NODE_OVERVIEW=false` 仍可关闭功能；回退代码不改用户配置。健康文件是可丢弃缓存：旧版不能读内部 v2 时会按既有未知版本恢复策略重建，历史可能清空；未操作实际用户缓存。
- NOT RUN：真实 Windows 窗口、接管既有 Core 的真实 IPC/QuickJS、代理/TUN/服务、真实性能与长时运行；用户禁止候选运行和现役操作。合成窗口、单元测试及 debug 资源构建不能代替这些验收。
- NOT RUN：完整原生可执行包、其他平台构建、Go/Agent/Helper/race 测试；这些层没有代码改动。无新协议，无需借本轮变更重建 Core/Helper 来证明已运行。
- P1 非活动 provider 叶子与隔离测速、P2 跨配置切换/推荐仍未实施。无请求归属的自动广播、无法识别节点、运行与文件不一致的结果不新增历史，这是保守的归属边界。

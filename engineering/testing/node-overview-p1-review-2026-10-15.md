# 跨配置节点总览 P1：技术负责人审查清单

日期：2026-10-15。范围：界面去冗余、内联节点隔离测速、本地单元与组件验证。依据：[P1 工程书](../plans/cross-profile-node-overview-p1-and-ui-refactor-2026-10-15.md)。

## 交付状态与权限

- 基于实际工作树 `development@e3ab52bd1afc46b009907f0ee7386fd228914d8e`。工程书列出的 `f6dff78` 是设计来源，不是本轮实际起点。
- 经技术负责人独立复审通过后，本轮 **42 个源码与测试文件**已在 `development` 分支完成本地提交 `9c3986e150c8bfb5f2f5cace5cc950b1e0a00b18`（`feat(proxies): add cross-profile node overview P1 isolated delay tests and flat UI`）。未执行推送、PR、合并、reset、stash，也未触发远端 CI。
- 未构建或启动候选应用；没有操作现役代理、TUN、网卡、服务、系统权限或真实产品 IPC。测试使用临时文件、注入替身、内存/本地测试连接和 Widget harness，不探测真实订阅节点。
- 原有未跟踪 `coverage/`、旧 QA 文档和 `engineering/testing/probes/` 保留；本轮日志和覆盖率输出到私有目录 `E:/Temp/fcx-nodeoverview-p1-20261015`。
- 本机 Flutter 3.47.4 / Dart 3.13.3、Go 1.25.13、Windows amd64；现有 CI 声明 Flutter 3.41.7 / Go 1.26.0。未升级依赖或修改锁文件。Go race 使用已有 UCRT GCC。

## 评审修复补记（2026-10-15，以本节为当前结果）

针对外部评审的两项 Medium 与两项 Low，均已核对实际源码、修复并回归。以下首轮记录和旧私有证据保留为历史；本轮最终日志、覆盖率、截图与源码 SHA256 在 **`E:/Temp/fcx-nodeoverview-p1-reviewfix-20261015`**，没有覆盖上一轮 `final-source-manifest.json`。

### 修改清单与验收矩阵

| 问题 / 文件 | 最终行为 | 本轮验证 |
|---|---|---|
| Finding 1：`lib/providers/node_overview.dart` | 只为 HTTP provider 的有效 HTTP(S) URL 生成既有受管哈希缓存路径；忽略 file/custom、缺失或无效 URL 的原始 path。Core 的 IsSafePath、目录范围与链接拒绝保持。 | 新增 `test/common/node_catalog_provider_paths_test.dart`：调用真实 factory 的 callback，仅替换 path_provider 边界；9 类省略、HTTP/HTTPS 映射、两种混合配置共 13 PASS。合法内联节点可 prepare，不下载或创建缓存。 |
| Finding 2：`core/catalog.go`、`core/catalog_lifecycle_test.go` | 先正规化可信 HomeDir 或其最近存在祖先，再逐段检查 profiles/providers 及子路径。允许 HomeDir 祖先别名；内部目录链接仍拒绝，且不因目标缺失提前降级放行。 | 5 个 provider 顶层用例 / 9 个子例 PASS，含缓存存在、缺失、相对路径、HomeDir 多层缺目录与四层内部链接拒绝。 |
| Finding 3：`lib/models/node_catalog.dart`、`lib/common/node_catalog_service.dart` | 显式 `isolatedTest` 投影对齐 Core 协议/选项限制、大小写和下划线字段别名；只在 service load/prepare 启用。共享 identity、活动 runtime 核验与健康 recorder 保持原有语义。 | `test/models/node_catalog_test.dart` 新增 8 项；`test/common/node_catalog_prepare_test.dart` 新增首屏无需 Core 的用例；UI 使用真实投影确认受限节点首次展示即无测速按钮。 |
| Finding 4：`lib/views/proxies/overview/overview.dart`、`test/views/node_overview_test.dart` | 节点与左栏摘要统一复用现有 `nodeOverviewLastTest`（中文“最近测速”），保留过期提示，不再声称非活动结果来自活动测试。 | 原文案断言更新；实际 bind→finishCatalogTest→unbind 的结果进入非活动行，显示 42ms 和中性时间，活动配置与实时延迟不变。UI 43 PASS。 |
| 验证中发现的旧测试替身阻塞：`core/delay_tasks_test.go` | `blockingDelayProxy` 的启动通知可响应 ctx 取消；cleanup 有界等待全部 150 回调后恢复 lookup，防止失败污染后续用例。生产 `delay_tasks.go` 未在本轮评审修复中改变。 | 保留 50 执行、150 个 configChanged、active=0/slots=0 断言。同一两测试组合 race 连续 20 轮，40 次执行 PASS；再跑完整回归。 |

本轮新增/再修改合计 11 个源码与测试文件（上表涉及的文件），另更新本报告和开发台账。新 `final-source-manifest.json` 固定整个 P1 工作树范围 **42 个源码/测试文件**；它包含上一轮 39 个文件以及新增纳入的 model 测试、provider 路径测试和 delay 测试。技术负责人复审通过后，这 42 个文件已本地提交为 `9c3986e150c8bfb5f2f5cace5cc950b1e0a00b18`；未推送或操作远端。

### 最终验证

所有日志以下列新私有证据目录为基准；Go 数量按顶层用例，子例另列。

| 命令 / 范围 | 状态与数量 | 退出码 | 秒 | 日志 |
|---|---|---:|---:|---|
| `flutter test --no-pub --concurrency=1 --reporter expanded` | PASS：823 / FAIL 0 / SKIP 0 | 0 | 136.022 | `flutter-full.log` |
| model/provider-path/prepare/UI 四文件目标 | PASS：85 / FAIL 0 / SKIP 0 | 0 | 24.608 | `dart/green.log` |
| 17 文件目标，`--coverage --branch-coverage` | PASS：221 / FAIL 0 / SKIP 0 | 0 | 70.713 | `coverage.log`、`coverage.info` |
| 宽窄 Widget 合成渲染 | PASS：2 / FAIL 0 / SKIP 0，已查看两图 | 0 | 11.735 | `ui/render.log`、`ui/render/overview-*.png` |
| `dart analyze --format machine` | 0 error / 11 既有 warning / 857 info；非全绿 | 2 | 30.362 | `analyze-final.log`、`analyze-final-result.json` |
| Go CGO0 `./...`（含 coverage） | PASS：110，另 44 子例 / FAIL 0 / SKIP 0 | 0 | 19.454 | `core/r2-full-coverage.jsonl` |
| Go CGO0 `-tags=with_gvisor ./...` | PASS：110，另 44 子例 / FAIL 0 / SKIP 0 | 0 | 15.163 | `core/r2-gvisor.jsonl` |
| Go CGO1 `-race -timeout=30s -run '^(TestCatalog\|TestDelay)' .` | PASS：28，另 20 子例 / FAIL 0 / SKIP 0 | 0 | 21.839 | `core/r2-race.jsonl` |
| 两个取消测试 `-race -count=20 -timeout=15s` | PASS：40 次执行 / FAIL 0 / SKIP 0 | 0 | 19.559 | `core/green-delay-fixture.jsonl` |

Go 命令仍在 `core` 目录执行，使用 `'-modfile=.generated/go.mod' '-overlay=.generated/mihomo-overlay.json'`。Flutter SDK、Go、GCC 与 CI 版本差异同首轮记录，未升级依赖。全量之后仅整理测试 import 顺序与补充注释，最终 221 项目标覆盖率及渲染编译再次通过。11 条 warning 与上一轮逐条一致，比较结论在 `analyze-final-result.json`。没有 skip、降低断言或修改 lint 配置。

### Red → Green、覆盖率及限制

- Dart 联合 Red：**48 PASS / 19 FAIL**，exit 1，21.950 秒，`dart/red.log`；其中协议投影 7、provider 路径/混合配置 11、时间文案 1，均为目标断言失败，不是编译失败。修复后对应目标集及新增首屏、实际健康结果用例共 85 PASS。
- Go 路径 Red：3 顶层 PASS / 2 FAIL，子例 5 PASS / 4 FAIL，`core/red-home-alias.jsonl`；修复后 5 顶层和 9 子例全 PASS。除了评审中的误拒绝，还覆盖并修复了 profiles 是链接、其目标缺 providers 时旧实现提前返回 notCached 的边界。
- 首次 race 真实失败保留在 `core/final-race.jsonl`，随后停止的仅是本轮测试进程。无 catalog 前置的独立取消测试重复复现；`core/red-delay-fixture-stack.jsonl` 的超时栈明确落在旧替身的 `[chan send]`。取消遍历期间执行槽已释放，排队请求可能启动，原替身在满通知通道阻塞后无法响应取消。修复替身并隔离 cleanup 后，同组合重复及完整 race 均 PASS；不将失败藏作无说明重试。
- Dart 八个手写改动模块：行 **1456/1593 = 91.40%**，分支 **511/632 = 80.85%**。model 行 100%，service 行 95.24%，overview 行 93.02%；生产 provider 接线行 63.51%，真实 Core/QuickJS 组合仍是未覆盖边界。详见 `coverage-summary.json`，不是全仓覆盖率。
- Go 使用语句覆盖率：完整 profile 47.6%、Core 主包 49.7%、`catalog.go` **294/327 = 89.91%**；新增 `canonicalCatalogHome` 80%、`catalogProviderStatus` 83.7%。未生成分支覆盖率；最终 profile、函数明细及文件统计见 `core/final-summary.json`。特殊文件系统错误和真实短路径仍未穷尽。
- 独立只读复核覆盖四项修复与测试替身，未发现新增高置信缺陷或阻塞；真实 Windows 候选、代理/TUN、真实节点网络、macOS/Android 沙盒及 Windows 8.3 短名/Junction 的完整系统矩阵 **NOT RUN**。本机临时目录 symlink 正向/反向用例实际运行，0 skip；不把 Windows 单测宣称为各平台验收。
- 代码锚点按实际实现核对：当前使用 `canonicalCatalogHome`、`catalogIsolationUnsupportedReason` 与 service 的 `isolatedTest` 投影；页面代次仍由既有 expected-Future/epoch 机制处理。本轮没有增加评审文字中提及的 `acquireScope` / `AppController.prepareNodeCatalog` 等接口。

## 首轮修改与新增文件（以下为修复前历史记录）

| 文件 | 改动及理由 |
|---|---|
| `lib/views/proxies/overview/overview.dart` | 删除展开集合、折叠卡片和活动代理组 ProxyCard；宽屏左栏筛选、窄屏下拉选择、全部配置轻量吸顶标题、单配置平铺；活动叶子去重且只读；单节点、当前配置、可见筛选集测速与取消/进度/错误反馈。 |
| `lib/common/node_catalog_tester.dart`（新增） | 页面持有的批次编排；逐配置 prepare→test→等待健康写入→release，避免超过 Core 三目录上限；请求归属、窗口隐藏、销毁和取消门禁，隐藏后恢复不复活旧准备工作。 |
| `lib/common/node_catalog_service.dart` | 保留被动目录加载；新增显式短生命周期 prepare/release、文件和脚本代次核对、索引校验、脱敏投影；取消只撤销匹配 Future，旧页面不能释放新页面目录。 |
| `lib/providers/node_overview.dart` | 注入已有 Core interface、提供 tester；配置/脚本/版本变化撤销旧归属；prepare 后刷新安全展示缓存。 |
| `lib/controller.dart` | 仅增加 P1 健康 store 入口，并初始化既有 recorder 的删除/flush 生命周期。 |
| `lib/models/node_catalog.dart` | 将 AmneziaWG 与 WireGuard 同列为不支持的重型协议。 |
| `lib/enum/enum.dart`、`lib/models/generated/core.g.dart` | 三个 catalog action 的枚举与 JSON 映射。 |
| `lib/clash/interface.dart`、`lib/clash/core.dart` | 三个 bridge 方法、固定错误码、响应形状与超时校验；隔离入口仅使用已存在的 interface，不创建 Core。 |
| `lib/common/delay_test_coordinator.dart` | scope/index、作用域去重、进度与 activeBatchId、目录控制错误停止排队；现役与目录共用协调器。 |
| `lib/common/delay_tests.dart` | scoped 请求仅回写绑定的 NodeHealthStore；不调用 live setDelay 或修改活动延迟数据。 |
| `lib/common/node_health_store.dart` | 目录绑定 capability、待测内存状态、写入等待；释放/删除/重绑撤销旧请求；只保存成功、testFailed 和单请求 deadlineExceeded。 |
| `core/catalog.go`（新增） | 独立锁、最多三目录、每目录最多 2000 节点、LRU/10 分钟 TTL、协议与 provider 路径限制、引用计数与确定释放。 |
| `core/constant.go`、`core/action.go` | 注册并分派 prepare/test/release。 |
| `core/delay_tasks.go` | 现役与目录共享 150 任务槽和 50 执行信号量；统一期限、取消和完成；目录不广播 DelayMessage。 |
| `core/server.go`、`core/server_output.go` | IPC owner 归属；旧会话关闭仅清理自己的目录和请求；release 使用独立控制槽。 |
| `core/hub.go`、`core/strict_ingress.go` | shutdown 阻止新目录进入、成功 init 恢复；严格模式转换前阻止并取消目录，失败后恢复实际状态投影。属于目录生命周期必需接线。 |
| `arb/intl_en.arb`、`arb/intl_zh_CN.arb`、`arb/intl_ja.arb`、`arb/intl_ru.arb` | 测速动作、进度、错误和预览限制文案。 |
| `lib/l10n/l10n.dart`、`lib/l10n/intl/messages_en.dart`、`messages_zh_CN.dart`、`messages_ja.dart`、`messages_ru.dart` | 使用既有 intl_utils 生成的对应本地化产物。 |
| `core/catalog_test.go`、`core/catalog_lifecycle_test.go`（新增） | 协议解析、重型/链式拒绝、安全路径、LRU/TTL、槽位、owner、取消、strict、关闭预算及无广播。 |
| `test/clash/catalog_protocol_test.dart`、`test/common/catalog_delay_test.dart`（新增） | 协议和错误脱敏、路由隔离、健康绑定/加载竞态、释放/重绑/取消。 |
| `test/common/node_catalog_prepare_test.dart`、`test/common/node_catalog_tester_test.dart`（新增） | prepare 投影、身份/索引、缓存代次、跨配置编排、外部 live 批次与旧页面迟返竞态。 |
| `test/common/delay_test_coordinator_test.dart` | 去重键 fixture 类型由二元组同步为三元组，未弱化原断言。 |
| `test/views/node_overview_test.dart`、`test/views/node_overview_render_test.dart` | 更新平铺断言；覆盖单测/批测/筛选集/取消；合成宽窄渲染。 |
| 本报告、`engineering/development-status.md` | 本轮交接、证据与未验收边界，不回写旧 P0 历史结果。 |

## 验收与测试矩阵

| 验收标准或风险 | 测试层级与用例 | 证据 |
|---|---|---|
| 删除折叠、左右筛选和窄屏直出 | Widget：全部与单配置切换、无展开操作、搜索排序、活动叶子去重、只读点击；全局宽 1200 / 父容器宽 400 时按实际约束切换 | `test/views/node_overview_test.dart`，41 PASS |
| 实际渲染和尺寸 | 400×800、1200×900 的真实 ProxiesView harness，检查截图 | `test/views/node_overview_render_test.dart`，2 PASS；`ui/render-final/*.png` |
| 单节点/当前配置/可见筛选集 | Widget + tester：包括离屏筛选匹配项，现役使用 unscoped 请求 | UI 套件与 `node_catalog_tester_test.dart` |
| 多于三个配置不提前淘汰待测目录 | service/tester 集成：逐配置准备、测速、释放 | `node_catalog_tester_test.dart` |
| 旧页面迟返不能释放新页面目录 | 两 tester 共享 service，新批次先开始、旧响应后返回 | `node_catalog_tester_test.dart` |
| 目录准备期间外部 live 批次启动 | 返回 busy，释放自己的目录，不取消 live | `node_catalog_tester_test.dart` |
| 隐藏窗口时尚未进入协调器的工作 | collect/prepare 中隐藏并恢复，再返回旧结果，仍不得开始；三个入口在隐藏状态拒绝新批次 | `node_catalog_tester_test.dart`，3 项行为 Red→Green |
| 同名节点跨配置/URL不串写，控制流不覆盖好值 | coordinator/router/store：scope 去重、绑定与撤销、延迟加载、取消/重绑/删除 | 72 项 Dart 目标回归及最终全量 |
| 不能污染活动节点实时结果 | fake bridge/store 端到端；Go 成功结果不广播，故意打开广播变异必失败 | `catalog_delay_test.dart`、`core/catalog_lifecycle_test.go` |
| 配置变化、旧会话、strict、shutdown 拒绝旧资源 | Dart 代次门禁与 Go owner/lease/strict/shutdown 测试 | 目标与 race 日志 |
| 资源上限与确定关闭 | 三目录、2000 节点、LRU、TTL、占用中的 Close 仍计预算 | Go catalog 两测试文件 |
| provider 路径只读且不逃逸 | 正常缓存、不存在、越界、符号链接和特殊路径拒绝 | Go catalog 测试；无网络下载 |
| 异常与日志隐私 | 错误白名单、无效 JSON/索引/类型、原始密码/端点不进入展示和健康缓存 | bridge 与 prepare 测试 |

## 实际执行记录

证据根目录：`E:/Temp/fcx-nodeoverview-p1-20261015`。下表时间为命令墙钟时间，Go 数量为顶层用例数。

| 验证 | PASS / FAIL / SKIP | 退出码 | 秒 | 日志 |
|---|---:|---:|---:|---|
| Flutter 最终全量 | 799 / 0 / 0 | 0 | 108.268 | `flutter-r3-full.log`、`flutter-r3-full-result.json` |
| service/prepare/tester/provider 最终目标回归 | 47 / 0 / 0 | 0 | 12.722 | `catalog-r3-target.log` |
| Dart bridge/coordinator/store 目标回归 | 72 / 0 / 0 | 0 | 14.754 | `dart/green-2.log` |
| UI 最终行为 | 41 / 0 / 0 | 0 | 15.504 | `ui/constraints-green.log` |
| 最终合成宽窄渲染 | 2 / 0 / 0 | 0 | 10.089 | `ui/render-final.log` |
| Flutter 最终目标覆盖率采集 | 197 / 0 / 0 | 0 | 59.306 | `flutter-r3-coverage.log`、`lcov-r3-final.info` |
| 全仓最终 `dart analyze` | 0 error / 11 warning / 857 info | 2 | 31.973 | `analyze-r3-final.log` |
| Go CGO0 目录目标 | 26 / 0 / 0 | 0 | 12.439 | `core/r2-final-target.jsonl` |
| Go CGO0 全量 | 107 / 0 / 0 | 0 | 17.630 | `core/r2-final-server.jsonl` |
| Go CGO0 `with_gvisor` 全量 | 107 / 0 / 0 | 0 | 16.716 | `core/r2-final-server-gvisor.jsonl` |
| Go CGO1 目录/测速 race | 25 / 0 / 0 | 0 | 44.560 | `core/r2-final-race.jsonl` |
| Go CGO0 覆盖率全量 | 107 / 0 / 0 | 0 | 13.836 | `core/r2-final-coverage.jsonl` |

全仓 analyze 不是全绿：11 条 warning 与本轮初始扫描逐条完全一致，比较文件为 `analyze-r3-warning-comparison.json`。所在文件为 `analysis_options.yaml`、`connection_diagnostics.dart`、`stats_grid.dart`、`profiles.dart`、`proxies/providers.dart`、`plugins/tray_manager/analysis_options.yaml` 和 `setup.dart`，本轮未修改这些文件。未通过降低 lint 或更改这些无关代码消除基线 warning。`final-source-manifest.json` 固定本轮 39 个源码/测试文件的 SHA256；暂存区为空，HEAD/分支未变，`git diff --check` 退出 0。

### 可复现命令

仓库根目录，使用 `E:/CodeWorkstation/toolchains/flutter/bin/` 中现有 SDK：

```powershell
flutter test --no-pub --concurrency=1 --reporter expanded
flutter test --no-pub --concurrency=1 --reporter expanded test/views/node_overview_test.dart
dart analyze --format machine
```

渲染文件默认不注册用例，必须单独设定输出目录；因此上述全量 799 项不包含这两项，不将它们计作 skip。最终另外执行并查看两图：

```powershell
$env:NODE_OVERVIEW_RENDER_DIR='E:/Temp/fcx-nodeoverview-p1-20261015/ui/render-final'
$env:NODE_OVERVIEW_RENDER_FONT='C:/Windows/Fonts/segoeui.ttf'
flutter test --no-pub --concurrency=1 --reporter expanded test/views/node_overview_render_test.dart
```

覆盖率命令是在下列 16 个目标文件上增加 `--coverage --branch-coverage --coverage-path=E:/Temp/fcx-nodeoverview-p1-20261015/lcov-r3-final.info`，其余参数同上：

```text
test/models/node_catalog_test.dart
test/clash/catalog_protocol_test.dart
test/common/catalog_delay_test.dart
test/common/node_catalog_service_test.dart
test/common/node_catalog_prepare_test.dart
test/common/node_catalog_tester_test.dart
test/common/node_catalog_pipeline_test.dart
test/common/node_health_store_test.dart
test/common/node_health_recorder_test.dart
test/common/node_overview_integration_test.dart
test/common/node_overview_providers_test.dart
test/common/delay_test_coordinator_test.dart
test/common/node_runtime_catalog_test.dart
test/common/node_runtime_no_start_test.dart
test/common/node_runtime_race_test.dart
test/views/node_overview_test.dart
```

Go module 实际位于 `core/go.mod`。在 `core` 目录执行 `./...`；不能在该目录机械照抄 `./core/...`，否则指向不存在的子目录。现有 overlay 生成器已运行成功：

```powershell
go run ./tools/mihomo-overlay
$env:CGO_ENABLED='0'
go test '-modfile=.generated/go.mod' '-overlay=.generated/mihomo-overlay.json' -json ./...
go test '-modfile=.generated/go.mod' '-overlay=.generated/mihomo-overlay.json' -tags=with_gvisor -json ./...
$env:CGO_ENABLED='1'
$env:CC='C:/msys64/ucrt64/bin/gcc.exe'
go test '-modfile=.generated/go.mod' '-overlay=.generated/mihomo-overlay.json' -race -run '^(TestCatalog|TestDelay)' -json .
```

CGO=0 覆盖 Windows server/IPC 专属测试；CGO=1 race 覆盖公共目录与共享运行器，不能把两者说成相同测试集。

## Red → Green 与失败记录

- UI 重构：4 个目标行为 Red → 30 PASS；测速入口：9 个目标行为 Red → 该阶段 40 PASS。吸顶标题高度问题已修复。
- UI 实际约束：父容器宽 400 / 全局宽 1200 的 1 个目标行为 Red（错误显示侧栏和布局异常，11.157 秒）→ 41 PASS（15.504 秒）。日志 `ui/constraints-red.log`、`ui/constraints-green.log`。
- Dart 生命周期：销毁待测状态、目录致命错误停止排队、取消传输异常、不可编码 prepare 输入共 4 个目标 Red → 72 PASS。最早因缺新 API 的加载失败单独记录，不冒充行为复现。
- Go：缺少动作 5 个 Red；链式字段别名与缺类型分类 2 个 Red；底层 Close 尚未完成时资源预算提前释放 1 个 Red。无广播另以 `false→true` 变异确认断言会失败，已恢复。
- Go 真实适配器资源审查：TUIC/Snell 2、AnyTLS 1、Hysteria v1 1、kcptun/realm 7 个子例，修复前均因“不应构造的 adapter 仍被构造”失败；最终 107 项全量覆盖拒绝行为。分类与固定源码类链依据见私有证据 `core/r2-adapter-resource-review.md`。
- 最终独立复核补修旧页面与新页面共用 prepare Future 的归属竞态；新增双 tester 测试及准备期间 live 抢先测试，44 项目标与 795 项全量均 PASS。这两项是审查后回归，未伪称有修复前 Red。
- 隐藏时撤销尚未进入协调器的工作：3 个目标行为实际 Red，exit 1、10.092 秒，`visibility-red.log`；同步监听 activity 后整个 service/tester/provider 目标集 47 PASS。独立复核确认不会误取消外部 live，隐藏后恢复不能复活旧代次。
- `catalog-target.log` 的 provider 循环类型推断导致 4 个加载失败，已加显式 provider 类型；`catalog-target-2.log` 的 3 个加载失败来自 UI 修改与编译交错，之后冻结所有 Dart 文件再验证。`ui/render` 首轮失败是 fixture 缺少只读 controller，补齐后 2 PASS。失败日志均保留，未跳过断言。

## 覆盖率与证明边界

Flutter 197 项覆盖率套件覆盖八个改动的手写模块（model、service、tester、store、coordinator、router、provider、overview）：行 **1431/1574 = 90.91%**，分支 **503/624 = 80.61%**。这不是全仓覆盖率，也不包含生成代码；逐文件明细见 `coverage-r3-summary.json`。

- 新 `node_catalog_tester.dart`：行 93.88%，分支 83.93%。
- `node_catalog_service.dart`：行 95.17%，分支 83.52%。
- `overview.dart`：行 93.03%，分支 83.50%。
- provider 生产接线：行 59.18%，分支 54.76%；真实文件/QuickJS/Core IPC 组合仍未执行，测试使用注入边界，不能以覆盖率冒充产品运行。

Go 最终覆盖率为**语句覆盖率**：完整 profile 47.3%、Core 主包 49.5%、`catalog.go` 275/303 = 90.76%、`delay_tasks.go` 109/126 = 86.51%。`go tool cover -func` 退出 0，耗时 3.274 秒。Go 未提供本轮分支覆盖率。未覆盖部分包含部分端口格式、特殊文件系统失败、无效 release 与极端并发退出分支。TTL 到期逻辑用控制时钟输入验证，未等待实际十分钟 AfterFunc 调度。详见 `core/r2-final-coverage-functions.txt` 和 `core/r2-final-summary.json`。

## 已知限制与审查重点

1. 本期只测速内联节点。Provider 仅检查安全本地路径与文件状态，返回 `providerPending` / `notCached`；UI 明示该预览不支持本地 provider 叶子测速，绝不下载订阅。
2. 隔离测速支持的独立协议限定为 `ss/ssr/socks5/http/vmess/vless/trojan/hysteria2/ssh`。以下预解析限制只作用于新 catalog 入口，现役协议行为不变；没有扩大到修改上游依赖：
   - `dialer-proxy`（包含解码别名）返回 `chainUnsupported`；WireGuard/AmneziaWG 等重型协议返回 `typeUnsupported`。
   - TUIC、Snell：固定上游 adapter 继承无实际释放效果的 Base.Close，复用池不能在 release 时确定关闭。
   - AnyTLS：后台清理任务使用不可被取消打断的 Sleep，间隔可由配置增大，Close 后仍可能持有资源。
   - Hysteria v1：控制握手使用 Background context，ReadServerHello 缺截止且 Close 与重连共锁，异常对端下不能保证取消与任务槽回收。
   - SS `plugin=kcptun`：Close 只取消清理任务，未关闭持有的 smux 会话；普通 SS 保留。
   - Hysteria2 含 `realm-opts`（含大小写/下划线别名，即使设置为 disabled）：控制 HTTP Transport 没有确定关闭路径；普通 Hysteria2 保留。
   - `smux`：固定上游在 mux 构建失败时可能不归还已分配 adapter，当前无法保证事务式释放。
   上述上游资源问题来自源码检查，不宣称已做真实远端故障复现。新增回归证明受限配置在 adapter 构造之前被拒绝。
3. 目录内部 runner 在工程书示例签名上增加 owner、entry 和引用释放回调，用于精确生命周期。仍共用原任务槽位与信号量。无 request-id 的 legacy stream 先投递再完成 action 回调，使回调成为可验证完成点；显式请求和目录请求均无广播。
4. 全仓分析仍有 11 条原有 warning。真实候选启动、实际节点网络连通性、Windows IPC/QuickJS、现役代理/TUN、长时压力、跨平台及远端 CI 均 **NOT RUN**，因为本轮仅授权代码和单元验证。
5. 这是一份本地实现与单测审查交付，不是打包、发布或真实设备验收。技术负责人复审通过后已将 42 个源码与测试文件本地提交为 `9c3986e150c8bfb5f2f5cace5cc950b1e0a00b18`，本报告与台账单独提交；未推送远端。

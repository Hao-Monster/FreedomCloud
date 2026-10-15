# 跨配置节点总览 P0 测试与交付记录

## 范围与基线

- 授权：按工程书实现 P0、测试和本地提交；不推送、不运行候选包、不操作现役代理、TUN 或服务。
- 开工：`development@c7166fe97c63f48795f71cb53626f5b0c6956ee5`。2026-10-15 fetch 自有远端后领先 1 / 落后 0；相对工程书 `2074cce` 仅增加工程书与台账，无产品代码变化。无开放 PR；远端 CI 38684682264 对应 `2074cce`，不是本次验证。
- 保留既有未跟踪 coverage、QA 文档、probes、stash 与历史工作树；仅本任务文件提交。
- P0 实施范围：FR-1～FR-7；FR-4 在可信运行快照下保存显式测速，接管已有 Core 的限制见下文，不能称完整运行验收。订阅源叶子仍需激活后可见；隔离测速和跨配置切换属于 P1/P2。
- 本机工具：Flutter 3.47.4 / Dart 3.13.3，路径 `E:/CodeWorkstation/toolchains/flutter/bin`；CI 声明 Flutter 3.41.7。沿用锁文件与现有依赖。

## 实现前冻结的测试矩阵

| 验收点 / 风险 | 层级 | 可执行场景 | 预期 |
|---|---|---|---|
| 白名单与稳定键 | Dart | 敏感夹具、同名异端点、字段顺序、版本前缀、非法结构 | 状态/JSON/日志不带原始凭据或地址；键稳定且区分来源 |
| 目录一致性与只读 | Dart | 实际解析/脚本管线替身；与运行配置节点集合比较；缺失文件 | 不创建文件、不更新订阅、不调用 setup/TUN；节点集合一致 |
| 目录缓存与竞态 | Dart | 指纹变化、更新中、失败、并发合并、并发上限、LRU、在途失效 | 无旧结果覆盖，无无界构建 |
| 健康文件 | Dart + 临时目录 | TTL、5000 上限、URL 隔离、损坏/未知版本、原子覆盖、加载/删除/写入竞态 | 只保存哈希与数值/原因码；正确恢复、淘汰和清理 |
| 活动结果归属 | Provider/controller | 重复相同延迟、异步目录加载时切配置/删除、清空实时表 | 到达时间更新；历史保留；不串到其他配置、不复活已删除配置 |
| 入口与回退 | Widget | 默认当前、少于2配置、构建开关关闭 | 原有入口保持；关闭后不触发目录/健康功能 |
| 全部配置视图 | Widget | 宽/窄、懒加载、空/缺失/解析失败/过期/更新中 | 布局不溢出、错误如实显示、复用已有订阅管理入口 |
| 搜索/排序/筛选 | Widget | 跨配置、同名节点、未测/失败/过时、名称/延迟排序、仅可用 | 正确显示隔离结果与文本时间，非活动节点无切换/测速动作 |
| 活动节点交互 | Widget | 实时组、真实 ProxyCard 参数与交互 | 复用既有按组选择/测速路径 |
| 回归 | Flutter | 新增目标测试、现有全量测试、analyze、生成文件与 diff 检查 | 无新增失败、错误、警告或无关差异 |

## 实现中的必要细化

- 目录元数据使用只读 `File.stat`，不使用会创建缺失文件的 `Profile.getFile/profileLastModified`。
- 对外解析错误仅返回固定原因码，避免仅移除 URL 后仍泄漏凭据或服务器地址。
- 显式测速开始时捕获已应用运行配置的节点哈希，结果到达时捕获时间；仅监听 DelayMap 会漏掉相同数值重复测试的时间更新，也不能区分切配置后的迟返结果。删除代次拒绝旧请求复活已删除配置的历史。
- 未携带请求归属的 Core DelayMessage 仍按原路径更新实时 UI，但不保存历史。只凭当前选中配置或磁盘文件推断运行节点会造成错误归属。
- **FR-4 尚有限制**：新 UI 进程只接管已有 Core 时，`lastRuntimeConfig/lastRuntimeProfileId` 为空；实时值和已有历史可见，新结果暂不写历史。直到本会话按既有流程实际应用配置、取得可信快照后，显式测速才记录。没有通过 setup、重启或修改现役配置补建快照。完整接管场景需后续只读运行身份契约；本次不扩展 Core/Agent 协议。
- 目录采用 2000 节点上限、最多 2 个并发构建、8 配置 LRU；指纹包括文件时间/长度及脚本摘要。非空搜索会只读加载全部配置，清空搜索恢复原展开状态。
- 健康文件保留 7 天、最多 5000 条、10 分钟新鲜度、2 秒合并写入，按配置/节点哈希/测试 URL 哈希隔离；损坏文件最多保留一份，写入失败保留已有文件。
- 活动节点按实际组复用 ProxyCard 和组级 testUrl；同节点在不同组保留各自交互。摘要按首个可见组去重。非活动历史按当前默认测试 URL 展示，不混合不同 URL 的结果。
- P0 非活动 proxy-provider 仅显示名称和“激活后可见”；活动源归属未知时标明“运行时订阅源”，摘要明示仅统计已加载节点。缺少顶层 server/port 的 peers-only WireGuard 配置按冻结键规则明确解析失败，不猜身份。

## 执行结果

所有命令在 Windows 的本仓库执行，Flutter/Dart 版本见基线。原始证据目录为 `E:/Temp/fcx-node-overview-p0-37012ea1f6a9464c8c840c4c1c32752a`（仓库外；无需也未上传）。新增用例均为合成配置，未读取用户真实订阅。

| 验证 | 状态 / 退出码 | 通过 / 失败 / 跳过 | 时间 | 证据 |
|---|---|---|---|---|
| 目标测试 + 行/分支覆盖率 | PASS / 0 | 64 / 0 / 0 | 墙钟 37.13s | `coverage-targeted.log`、`lcov-targeted.info` |
| 全量 Flutter 回归 | PASS / 0 | 674 / 0 / 0 | 墙钟 83.52s | `flutter-full-final.log` |
| 配置协议回归（恢复懒回调后） | PASS / 0 | 5 / 0 / 0 | 未单独计墙钟 | `protocol-regression-final.log` |
| 合成渲染：400×800、1200×900 | PASS / 0 | 2 / 0 / 0 | 最终墙钟 12.51s | `render-final.log`、`render/overview-*.png`，已人工看图 |
| Windows 目标 debug UI 资源编译 | PASS / 0 | 不适用 | 墙钟 33.54s | `ui-build-final.log`、`ui-build-final-result.json` |
| 全仓 analyze | FAIL / 1 | 0 error，11 既有 warning，850 info | 墙钟 32.34s | `analyze-final.log` |
| Freezed/JSON、四语言生成 | PASS / 0 | 不适用 | 模型约 32s，国际化未计时 | `codegen.log`、`intl.log` |
| diff/原稿保留检查 | PASS / 0 | 原有未跟踪文件 hash 无变化 | 未计时 | 初始清单与最终 Git 复核 |

最终仅整理了 controller import 位置和删除渲染测试多余 import，不改变上述已测产品行为。合成渲染是独立可选测试：未设置 `NODE_OVERVIEW_RENDER_DIR` 时不注册测试，674 全量计数不包含这 2 项，也不把它们算作 skip。

可复现命令（`flutter` / `dart` 指向上述 SDK；`<evidence>` 替换为独立证据目录）：

```powershell
flutter test --no-pub --concurrency=2 --reporter expanded
flutter test --no-pub --concurrency=1 --coverage --branch-coverage --coverage-path=<evidence>/lcov-targeted.info test/models/node_catalog_test.dart test/common/node_catalog_service_test.dart test/common/node_catalog_pipeline_test.dart test/common/node_health_store_test.dart test/common/node_health_recorder_test.dart test/common/node_overview_integration_test.dart test/common/node_overview_providers_test.dart test/views/node_overview_test.dart --reporter expanded
flutter test --no-pub test/clash/controller_config_protocol_test.dart --reporter expanded
flutter analyze --no-pub --no-fatal-infos
flutter assemble '-dTargetPlatform=windows-x64' '-dBuildMode=debug' '--output=<evidence>/ui-debug' debug_bundle_windows-x64_assets
dart run build_runner build --build-filter='lib/models/generated/node_catalog*'
dart run intl_utils:generate
$env:NODE_OVERVIEW_RENDER_DIR = '<evidence>/render'
$env:NODE_OVERVIEW_RENDER_FONT = 'C:/Windows/Fonts/segoeui.ttf'
flutter test --no-pub test/views/node_overview_render_test.dart --concurrency=1 --reporter expanded
```

矩阵映射：模型/目录/管线 17 项，健康文件 21 项，记录器与 controller/provider 集成 12 项，UI 14 项，共 64 项。FR-1/2/3/5/6/7 的本地自动化场景通过；FR-4 可信快照下的持久化、切换、重复值和删除迟返通过，接管限制由专项测试验证为“不伪造归属”，不能用该测试宣称完整 FR-4 已实现。

全仓 analyze 的 11 条 warning 均在本次未修改文件中，已用 `git diff --quiet` 核对：`analysis_options.yaml` 的已移除 lint，`connection_diagnostics.dart` 的 try 内未 await，`stats_grid.dart` 两处无效 !，`profiles.dart` 未使用 import，`proxies/providers.dart` 无效 ?.，tray_manager 既有 lint include 缺失，以及 `setup.dart` 三个未使用 helper 和一处 !。本次手写新文件无 error/warning；保留异步文件 IO 的 info（避免阻塞 UI），生成器的 null-check info 亦未手改。

## 覆盖率与缺口

LCOV 的 BRDA 逐项计数（工具未输出 BRF/BRH）。这里只统计新增六个手写产品模块，不用全仓、生成代码或旧 controller 的大量未执行行稀释结果；也不是全部 diff 行覆盖率。

| 文件 | 行命中 / 可执行行 | 分支命中 / 分支 |
|---|---|---|
| `lib/models/node_catalog.dart` | 30 / 30 | 5 / 5 |
| `lib/common/node_catalog_service.dart` | 98 / 101 | 42 / 48 |
| `lib/common/node_health_recorder.dart` | 31 / 31 | 16 / 17 |
| `lib/common/node_health_store.dart` | 164 / 167 | 61 / 65 |
| `lib/providers/node_overview.dart` | 56 / 81 | 26 / 41 |
| `lib/views/proxies/overview/overview.dart` | 347 / 377 | 90 / 106 |
| **合计** | **726 / 787（92.25%）** | **240 / 282（85.11%）** |

主要未覆盖：损坏文件隔离本身遭 OS 拒绝的错误路径；实际应用路径/运行脚本/底层解析边界（测试注入 IO）；部分活动列表排序/筛选分支与空态、管理页面导航。新 controller 归属与删除入口有集成测试，但全局 delayTests 回调连接真实 Core 的运行链未执行。管线测试使用实际 patchRawConfig 和受控 evaluate 结果，不代表已运行真实 QuickJS 或 IPC。模型生成 JSON 文件 45/46 行、6/8 分支，单列而不纳入上述手写覆盖率。

## Red → Green、失败与审查

- 新功能：记录器最初用例因接口尚不存在而编译失败（`recorder-red.log`），实现后通过。其余新用例没有有效的行为 Red，不伪造测试先行证据。
- 实际回归：清理 lint 时把 Core 取消回调改为方法 tear-off，导致配置失败回归提前初始化桌面服务，`Binding has not yet been initialized`。恢复原懒闭包并说明其必要性；原协议套件 5/5 和最终全量 674/674 通过。失败日志 `flutter-full.log` 保留。
- 首轮全量带分支覆盖率在上述失败后又发生 Dart VM `zone.cc:95 Out of memory`，进程退出 `-1073740791`。不能把该轮全部失败解释为环境问题；产品回归已修复，之后把全量（并发 2）与目标覆盖率（并发 1）分开，均成功。
- build_runner 的限定生成首次同时删除了无关既有生成文件；依据开工 tracked 干净证据逐项恢复到 HEAD，最终相关原文件 Git blob hash 与 HEAD 一致，没有把无关重新生成或删除提交。
- 独立只读复核已修正冷态搜索遗漏、宽栏搜索受选中配置限制、活动摘要忽略组级 URL、折叠异常被隐藏四类问题，并增加回归。最终复核未发现本次未解决 Critical/High；接管历史限制、provider 范围及协议兼容缺口保持公开。

## 本地交付与回退

- 源码/测试本地提交 `c8fa0a3f55386778a4d1f17c7ce4845a03980449`（`feat(proxies): add cross-profile node overview P0`）；本记录、工程书补记、开发台账另作本地文档提交。本轮不推送、不创建 PR、不打可执行预览包。
- 入口构建开关为 `FCX_NODE_OVERVIEW=false`，关闭后回到既有当前配置 UI，且不启动历史/目录功能；删除 `node_health_v1.json` 只会清空历史。实际用户目录清理未执行。
- 调试资源只证明 Flutter UI 可编译，不含可运行的完整原生客户端，也未改变 Core/Agent/Helper 的 hash 或构建输入。

## 明确未运行

- 真实 Windows 窗口、候选包运行、现役代理/TUN/服务操作：用户明确禁止，NOT RUN。
- 原生首帧 ≤300ms、单配置 ≤1.5s、真机滚动/长时占用、实际 QuickJS/IPC：NOT RUN；Sliver 合成用例仅证明按视口构建，不代替性能实测。
- Core/Agent/Helper、Go vet/race、其他平台构建与真机验收：本次无此类代码变更，NOT RUN。
- P1/P2 Core、隔离测速、VM/TUN、不回环、切换推荐：本阶段不实现。
- 远端 CI、推送、PR、合并、发布：未授权，不执行。

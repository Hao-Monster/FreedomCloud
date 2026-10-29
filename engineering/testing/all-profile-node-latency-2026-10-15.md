# 全配置节点延迟测试与批次修复交付（2026-10-15）

## 需求与交付边界

本轮在 `development@e3ab52bd1afc46b009907f0ee7386fd228914d8e` 的既有 P1 脏工作树上增量实现。需求已确认：保留“测试当前配置”独立入口并修复点击未开始/中途停止；将“测试可见节点”改为“测试全部节点延迟”；全量入口覆盖所有导入配置，包含活动配置，忽略搜索、选中配置、视口与“只看可用”；仅测延迟，不测带宽。单节点或配置失败不能阻断后续正常配置。历史保留至下一次有效测量覆盖。用户选择 B：显式全量测试时允许读取 provider 列表，缓存缺失时下载到内存，禁止应用配置或切换活动代理。

实现及自动化验证完成，代码留工作树；**未提交、未推送、未 fetch、未切换分支、未暂存、未重置**。未打新包，未启动任何候选，未操作现役代理、TUN、网卡、服务、权限或真实产品 IPC。现有 WIP 包仍对应此前快照，不包含本轮变更，不得将其作为本轮源码的验收对象。

## 实现结果

- 全量入口直接遍历全部 profiles，与展示筛选完全解耦。按配置解析、按节点数与消息字节数分块、准备、测延迟、等待历史写入、释放；异常配置、普通节点失败、无法识别节点及本地目录失效均如实归集，后续正常配置继续。用户取消、窗口失活、会话/Core 失效等全局控制条件停止当前批次。
- 当前入口保留既有运行组/URL 解析。批次预算由节点数、并发数和单请求超时计算，避免旧 30 秒总预算截断大批次；按实际请求去重，进度分母不重复。配置展示元数据变化不再误取消批次，实际定义/文件/脚本变化仍撤销归属。
- provider 支持 inline、受管 HTTP 缓存、可信 HomeDir 内的本地 file；缺少 HTTP(S) 缓存才由显式全量入口下载。仅只读/内存处理，不写 provider 缓存、不更新现役 provider。保留配置本身的 filter/exclude 与安全 override 语义；这些不是页面的展示过滤器。
- 新增纯 `catalogParseProvider` 动作，复用固定版本 Mihomo 的解析/格式转换，禁止创建适配器、下载器、健康检查或读取现役配置。独立静默 URI 转换入口避免错误日志包含原始节点 URI，原转换入口行为保持。固定上游源 hash 和 overlay 来源纳入生成器校验。
- 解析消息使用有界 gzip/base64；prepare 同时按 2000 节点及实际双重 JSON UTF-8 字节分块，不提高现有共享 IPC 消息上限。单条超限、解析失败及不支持协议明确计入未测与原因，不伪装成已测。
- 历史默认无时间 TTL；旧结果不会因取消、切配置、UI 隐藏等控制原因被失败值替换。容量已满时保留旧记录、拒绝新增身份并如实提示；已有身份可覆盖。超容量/超文件大小旧快照不被部分内存视图覆盖。拒存告警按本目录实际事件计数，不污染后续正常保存配置。
- 活动行值、时间、来源统一选择。可信运行时身份优先；明确标识独立测试及文件 provider 的历史，不将文件端点当运行态证明。纯展示/运行身份投影上限与每个 Core catalog 2000 上限分离，第 2001 个节点的验证与历史展示有回归。

## 本轮文件清单（不包含原 P1 已有但本轮未修改的文件）

| 区域 | 修改/新增文件 | 作用 |
|---|---|---|
| UI | `lib/views/proxies/overview/overview.dart` | 全量按钮、汇总及历史来源一致性，保留当前入口/原布局/显示筛选 |
| 编排/历史 | `lib/common/delay_test_coordinator.dart`、`node_catalog_tester.dart`、`node_health_store.dart`、`node_runtime_catalog.dart` | 请求计数、局部失败隔离、动态预算、永久保留、归属校验 |
| 目录领域 | `lib/common/node_catalog_service.dart`；新增 `node_catalog_test_plan.dart`、`node_catalog_provider_resolver.dart`、`node_catalog_codec.dart` | 短期计划、provider 只读解析/显式下载、大小限制与释放 |
| 领域接线 | `lib/models/node_catalog.dart`、`lib/providers/node_overview.dart` | provider 来源/坏节点投影、当前定义判断与 resolver 接线 |
| Core 桥接 | `lib/clash/core.dart`、`lib/clash/interface.dart`、`lib/enum/enum.dart`、`lib/models/generated/core.g.dart` | 纯解析动作、受控错误和有界编码 |
| Go/overlay | `core/action.go`、`core/constant.go`、`core/tools/mihomo-overlay/main.go`；新增 `core/catalog_provider.go`、`core/catalog_provider_test.go`、`core/tools/mihomo-overlay/patches/catalog_provider_fcx.go.txt` | 纯解析协议及固定上游补丁；不改现役测速/隧道 |
| 本地化 | `arb/intl_{en,ja,ru,zh_CN}.arb`、`lib/l10n/l10n.dart`、`lib/l10n/intl/messages_{en,ja,ru,zh_CN}.dart` | 四语言入口、进度汇总、原因和历史说明 |
| Dart 回归 | `test/clash/catalog_protocol_test.dart`；`test/common/{catalog_delay,node_catalog_service,node_catalog_tester,node_health_store,node_overview_providers,node_runtime_catalog}_test.dart`；新增 `test/common/{node_catalog_all,node_catalog_codec,node_catalog_provider_resolver}_test.dart`；`test/views/{node_overview,node_overview_render}_test.dart` | 真实领域/路由/组件与合成渲染回归 |

共 42 个源码/测试/本地化文件，另本报告和 `engineering/development-status.md` 两份交付文档。逐文件最终 SHA256、与本轮开始时脏工作树的差异及恢复来源见私有 `final-source-manifest.json`。旧 QA、coverage、probes 和旧包保留。

## 测试矩阵

| 验收/风险 | 验证 | 结果 |
|---|---|---|
| 全配置、活动配置、不可见/过滤节点均入批 | tester 五配置、UI 搜索/选中/可用过滤穿透 | PASS |
| 一配置解析/准备失败，其他仍继续 | 合成坏配置、坏 provider、prepare 错误、普通单请求失败、局部 catalog 失效 | PASS |
| 当前批次不在 30 秒被截断 | fake clock：70 个每个 4.9 秒请求、并发 10；去重与不同 URL | PASS |
| >2000 节点与大消息 | 2001 节点跨块、转义后的真实消息长度、单节点过大、运行身份与末节点 UI | PASS |
| B：缓存缺失显式获取 | resolver 缓存命中不下载、inline/file 不下载、缺缓存获取、同源重定向/大小/取消 | PASS；网络用例仅本地 loopback |
| 历史长期保留与覆盖 | 跨百年模拟时钟后重载、有效新测量覆盖、取消保留、满额旧记录不丢 | PASS |
| 不串配置/生命周期 | scope 能力、晚返回释放、profile 变化撤销、异步 load 后取消、旧页与新页 | PASS |
| 不污染活动延迟 | 真实目录路由 + store，live 回调计数保持；文件 provider 明确来源 | PASS |
| 存储失败不假成功 | 拒存/flush 失败汇总、后配置继续、后续覆盖不误报、跨入口不串告警 | PASS |
| 数据与资源边界 | gzip 解压上限、源/总量上限、坏 YAML/URI、静默日志、正则放大提前拒绝 | PASS |
| 可视布局 | 400×800、1200×900 合成渲染，图片已查看 | PASS；不代表真实 Windows 候选 |

## 最终执行证据

环境：本机 Windows、Flutter **3.47.4**、Dart **3.13.3**、Go **1.25.13**。CI 声明 Flutter 3.41.7/Go 1.26.0，本轮没有更改工具版本/依赖锁，也没有运行远端 CI。

| 命令/证据 | 状态/退出码 | 通过/失败/跳过 | 时间 |
|---|---|---|---|
| `flutter test --no-pub --concurrency=2 --coverage --branch-coverage --coverage-path E:/Temp/fcx-node-latency-all-20261015/coverage-final.info --reporter=json` | PASS / 0 | **886 / 0 / 0** | 158.404s |
| `flutter test --no-pub test/views/node_overview_render_test.dart --reporter expanded`，设置私有输出目录及系统字体 | PASS / 0 | 2 / 0 / 0 | 13.788s |
| `dart analyze --format machine` | 非全绿 / 2 | **0 error / 11 既有 warning / 886 info**；11 warning 逐条与评审基线一致，无新增 warning | 32.475s |
| Core `go run ./tools/mihomo-overlay` 后 `go test '-modfile=.generated/go.mod' '-overlay=.generated/mihomo-overlay.json' -p 2 -timeout=90s -coverprofile=<private>/core-coverage-r2.out -json ./...`，CGO=0 | PASS / 0 | 120 顶层、含子例 164 / 0 / 0 | 14.336s |
| 同 Core 参数，`-tags=with_gvisor -timeout=90s -json ./...`，CGO=0 | PASS / 0 | 120 顶层、含子例 164 / 0 / 0 | 16.384s |
| Core `go test '-modfile=.generated/go.mod' '-overlay=.generated/mihomo-overlay.json' -p 2 -race -timeout=60s -json -run '^(TestCatalog\|TestDelay)' .`，CGO=1 | PASS / 0 | 38 顶层、含子例 58 / 0 / 0 | 44.899s |
| `git --no-optional-locks diff --check` | PASS / 0 | 无空白错误；存在 Git 既有换行转换提示 | — |

各 Go 命令在 `core` 目录执行，`GOMAXPROCS=2`；race 使用现有 `C:/msys64/ucrt64/bin/gcc.exe`。没有安装服务或驱动。完整 JSON/text 输出可追溯；重叠目标套件不相加作为总用例数。

覆盖率：全部本轮改动可执行 Dart 行 **691/835=82.75%**，对应分支 **210/357=58.82%**（包含本地化生成代码）；剔除生成代码后，本轮手写改动行 **604/669=90.28%**、分支 **191/274=69.71%**。这是针对本轮前备份逐行 diff 与最终 LCOV 的交集，不是整个仓库覆盖率。重要未覆盖包括真实 Core 获取/IPC 桥接、部分文件系统/HTTP 平台错误组合及非英语全部动态文案分支。Go 官方总体语句覆盖 **47.9%**，新增 `catalog_provider.go` **61/74=82.4%**；Go 工具未提供分支率。

## Red → Green 与失败保留

- 当前入口：70 个慢请求原本仅完成 60；重复节点总数原为 4、应为 2。目标 Red 为 1 PASS/2 FAIL，修复后全部通过。
- 全量解析：坏 YAML/inline 条目吞掉合法同伴、profile 总 payload 无界、过大节点无消息分块、错误 URI 输出原文，均有真实失败后修复证据。缺新 API 的初次编译失败单独标记，未冒充行为 Red。
- 历史：初始容量/期限等 37 PASS/4 FAIL；默认无 TTL、容量保护后通过。容量告警归属穿透 Red 预期仅 b，实际误报 b/c；修复后 store+tester+catalog 86 PASS，15.458s。
- 运行身份：加入 provider 投影后原返回 null，修复后通过；2001 inline runtime 原返回 null，拆分上限后全文件 11 PASS。2001 UI 在领域修复后新增，只记录 Green，不伪造 Red。
- UI 来源：4 个目标失败/10 个保护用例通过后修复；来源、URL、唯一身份、筛选/排序/摘要与已测时间统一。最终 UI 文件 64 项全部包含在最终 886 项中。
- 首次全量为 **882 PASS/1 FAIL，exit 1，85.485s**：运行期间遇到新加入的 profile 元数据误取消回归，而对应修复尚未落盘。此失败保留；全文件冻结后最终重新运行得到 886/0/0。
- 单独追加 overlay helper 覆盖率采集 **FAIL，exit 1，9.643s**：本机 Go cover.exe 无法定位 overlay-only 新增源文件。真实 overlay 功能/full/gVisor/race 均通过，但不宣称 helper 的覆盖率百分比；未修改模块缓存或伪造验证源绕过。

## 已知边界与未运行项

1. “全部”是完整配置节点候选范围；既有隔离器禁止的协议/传输仍明确未测：wireguard/amneziawg、链式 dialer-proxy、smux、tuic、snell、anytls、hysteria v1、SS kcptun、Hysteria2 realm 等。没有擅自放开可能影响现役资源的实现，不把这些计为通过。
2. provider 的非空 `proxy-name`/`override-expr`、缓存缺失且要求具名代理下载、依赖现役全局 Age key 的加密源，明确 `providerOptionsUnsupported`；其余配置继续。显式 provider key 可纯内存解析。
3. 边界不静默截断：每来源原始/解析输出 8 MiB，单 provider 20000 节点，配置 100000 节点/32 MiB 原始映射，压缩帧 512 KiB/解压 12 MiB；超限报告原因。未知节点数的整源失败只能统计受影响配置/原因，不能杜撰未测节点数。
4. 历史仍有既有 **5000 条 / 4 MiB 文件**资源限制。不会为新结果淘汰旧结果；满额明确拒存并提示，旧身份仍可更新。超大旧文件保持只读保护。不是无限容量存储。
5. 活动列表继续展示既有运行时叶子，不新增未经要求的列表结构。文件 provider 没有相应运行时叶子时不新增活动行；provider 投影在重启或目录缓存淘汰后缺失时，仅凭散列历史不能重建节点行。记录本身不按时间过期，但此时需再次解析目录才能关联展示。
6. **NOT RUN**：真实候选窗口、真实节点/外网订阅、Windows 产品 IPC/QuickJS、服务/代理/TUN、跨平台设备、长时资源峰值、远端 CI、新包构建及用户业务验收。单元测试使用合成输入与临时目录，HTTP 用例仅 loopback。未将静态 hash/合成图/无错误日志作为实机验收。

独立审查发现并关闭了错误日志泄露、正则替换分配放大、消息超限关闭连接、总量边界、2001 投影失效和拒存告警串配置；本范围无剩余高置信 Critical/High。部分成功+基础设施失效+跨块组合仅有分项覆盖，真实环境风险以上述 NOT RUN 为准。

## 证据与恢复位置

- 本轮主证据：`E:/Temp/fcx-node-latency-all-20261015`，含 `final-test-summary.json`、`final-source-manifest.json`、`coverage-summary.json`、`protected-source-check.json`、完整日志及 `ui-render-final` 两张合成图。
- 领域/Go：`E:/Temp/fcx-nodeoverview-alltest-20261015/catalog`，含精确命令/计数、源码双方 hash、失败与修复日志。
- 31 文件初始清单及后续只读核对备份：主证据目录 `before/`；既有 P1 完整可恢复源码：`E:/Temp/flclashx-nodeoverview-p1-wip-source-20261015/source-tree`，此前 WIP snapshot `4c1df825fcf3641bb17e29443e6e6b66ea1b36b58c659186e61fca33472dc0e1`。
- 本轮逐 hash 核对控制器、现役 delay router/Core runner、catalog 生命周期、server/strict/hub、pubspec 与 Go 依赖文件、CI 文件，与此前 WIP 均相同。Git HEAD 未变、暂存区为空。后续提交/推送由技术负责人统一处理。

# FlClashX 性能、资源生命周期与可靠性 TODO

创建/修复日期：2026-10-09（Asia/Singapore）。用户随后授权逐项修复并统一打包。本清单现记录源码修复、隔离自动化与剩余平台验收，历史问题与原始证据保留。

补充复核：2026-10-09，对用户提供的另一位程序员的六项排查逐条核实。补充 F11 编码子问题、新增 F16/F17 与 P02，完善 F06/F09/P01 边界；详见 [外部报告逐项核验](evidence/external-review-verification-2026-10-09.md)。

## 1. 来源、状态与执行边界

- 排查源码：`E:\CodeWorkstation\FlClashX`，`development@c5c5ae4400d225cf2abefccb92184d29c1b81bcd`。下列行号对应该源码基线；实施前重新核对当前版本。
- 完整证据：[原始审查报告快照](evidence/performance-resource-audit-2026-10-09.md)。原输出文件：`C:\Users\冯飏\Documents\Codex\2026-10-08\new-chat\outputs\flclashx-performance-resource-audit-2026-10-09.md`。
- F01–F17 的**源码修复及对应隔离回归已完成**；真实窗口、SCM/TUN、Android JNI、网络匹配与长时性能验收按下方未勾项保留，不能解释为全部平台验收关闭。修复基线为 `development@a52907c2d4425f6c1679792f64a3129ae4c562d7`，方案见 [实施计划](remediation-plan-2026-10-09.md)，最终提交/构建来源见 [修复汇总](remediation-results-2026-10-09.md)。原新增项核验基线为 `3227a863f5bdbb4ca7dc1f8caa5b7708d1f104dc`。
- P01 仍为 **待测量的优化候选**；P02 的同步释放范围已实现，收益/压力测量待执行。V01–V05 为 **尚未完成的性能/系统验收任务**。H01 为此前已修代码的历史记录，仍有长期验收待办；S01 为系统恢复待办，不冒充产品代码缺陷。
- 证据等级：**隔离复现**（真实类/函数、合成输入）；**源码确认**（完整失败路径已核对）；**优化候选**（需要基准数据）。不要混淆这三者。
- 优先级：P1＝下一批优先处理的高影响问题；P2＝随后稳定性/资源修复；P3＝测量后再决定的优化。优先级不表示本机此刻正在触发。
- 本轮未改变运行中的客户端、代理、TUN、服务、Windows Shell 或用户配置；没有把这些发现作为此前任务栏故障的完整因果证明。
- 本清单保持原 F01–F15 编号，后续确认的新问题顺延为 F16/F17；附加优化/验收使用 P/V/H/S 前缀，同一根因的补充并入原项，避免重复计数。

## 2. 总待办清单

F 编号的总框只表示本轮代码修复及隔离回归，完整关闭仍须满足第 11 节及各项未勾验收。各节的“位置/问题/已有证据”为**修复前历史记录**；当前实现与执行命令见以下对应记录。

| 编号 | 本轮实现与自动化记录 | 剩余主要验收 |
|---|---|---|
| F01/F05 | [Core](evidence/remediation-core-2026-10-09.md)、[Dart](evidence/remediation-dart-2026-10-09.md)：完整 controller、失败保留有效配置、profile 快照一致性 | 真实 TLS/多 transport 重建、策略/TUN 与 UI 完整链路 |
| F02/F11/F16/F17 | [下载及原生资源](evidence/remediation-native-ui-2026-10-09.md)：受限 ZIP、RAII/UTF-8、受管托盘生命周期、图像 finally | 真实 WinINet IDN/菜单交互、磁盘故障、图标压力与视觉 |
| F03/F04/F13/F14 | [Services](evidence/remediation-services-2026-10-09.md)、[Core](evidence/remediation-core-2026-10-09.md)：有界 IPC、真实停止结果、认证限额、有界日志 | 全链路慢 UI、SCM/端口/TUN 与长时句柄收敛 |
| F06/F07/F08/F09/F12 | [Dart](evidence/remediation-dart-2026-10-09.md)：及时释放 RPC、代际轮询、活动消费者、日志预算 | 真实前后台、heap/GC、磁盘/权限与 Android 生命周期 |
| F10 | [Dart](evidence/remediation-dart-2026-10-09.md)、[Core](evidence/remediation-core-2026-10-09.md)：全局 worker/去重、端到端 deadline/cancel、取消结果不写 history | 大订阅/真实测速及跨组件压力 |
| F15 | [Core](evidence/remediation-core-2026-10-09.md)：retired lease 所有权与 Android 编译 | Android JNI/Binder 实机 |

- [x] **F01 · P1** 完整保留外部控制接口认证与控制器配置。
- [x] **F02 · P1** 约束面板 ZIP 写入路径及下载/解压资源预算。
- [x] **F03 · P1** 阻断慢 UI 的 IPC 背压向 Core 控制链传播。
- [x] **F04 · P1** Helper 确认真正停止 Core 后再退出，保留失败所有权。
- [x] **F05 · P1** 配置失败时保留最后有效运行配置。
- [x] **F06 · P2** RPC 完成后及时释放 pending 状态与响应引用。
- [x] **F07 · P2** 修复 ConnectionManager 在途请求遇 stop/start 后停更。
- [x] **F08 · P2** 修复流量轮询 Timer 所有权竞态和停止后复活。
- [x] **F09 · P2** 按真实前后台可见性控制 UI 取样与 Core 事件生成。
- [x] **F10 · P2** 为测速建立真实并发/排队上限和端到端取消超时。
- [x] **F11 · P2** 修复 Windows 代理插件错误路径泄漏、恒报成功及 Unicode 排除域名编码损坏。
- [x] **F12 · P2** 修复日志数量、跨日滚动和清理所有权。
- [x] **F13 · P2** 限制 Agent 认证前连接数量及等待时间。
- [x] **F14 · P2** 对 Core stdout/stderr 使用有界行读取。
- [x] **F15 · P2** Android retired TUN handler 的 JNI 引用安全迟后回收。
- [x] **F16 · P2** Windows 托盘菜单操作校验所有权并修正主题监视时机。
- [x] **F17 · P2** 图标 PNG 编码异常时保证 `ui.Image` 显式释放。
- [ ] **P01 · P3** 测量 NORMAL/HIGH 进程优先级后决定是否调整。
- [ ] **P02 · P3** 缩短图标提取原生资源跨异步编码的持有时间，测量队列与资源峰值。
- [ ] **V01–V05** 完成第 7 节的五组性能、生命周期与故障恢复验收。
- [ ] **H01** 补此前托盘修复的长期与真实交互验收。
- [ ] **S01** 按独立系统恢复范围验证开始按钮/搜索宿主恢复。

## 3. P1：安全与控制可靠性

### F01：外部控制接口重建遗漏 secret、TLS/CORS 等配置

**状态**：源码修复/隔离回归完成；未勾平台验收继续跟踪。**平台/范围**：Go Core 外控重建路径。**原审查证据**：源码确认 + 实际固定依赖 router 的内存 HTTP 验证。

**位置**：`core/common.go:366,436`；`lib/state.dart:521–533`；默认值见 `lib/models/clash_config.dart:502`、`lib/enum/enum.dart:169–173`。Mihomo 固定源为 `core/.generated/mihomo-v1.19.32-source-adb2170dcce92d63d9da0102eb6669bf8b719c6d9ed33b985c3d0a3aa9c1dd7a/hub/route/server.go:60,92,119,162,181`，由 `.generated/go.mod:158` 指向。

**问题/触发**：两处 `route.ReCreateServer` 只构造 Addr，secret 被置空；实际依赖不会沿用旧 secret。启用外控，或 profile 携带外控地址/密钥后，setup 或 UI 更新路径可丢失认证。默认外控关闭，开启默认绑定 `127.0.0.1:9090`；profile 地址优先，通配/LAN 绑定时风险扩大，不能称默认公网暴露。

**已有证据**：真实 router、合成配置、内存请求 `/version`：仅地址时匿名 200，保留合成 secret 时匿名 401。没有启动监听或验证当前运行实例。

**修复 TODO**：

- [x] 审查两个重建调用点及全部调用面，统一完整 controller config 的构造，保留 Secret、TLS、CORS 和其他适用字段。
- [x] 保持 UI 开关与订阅地址优先的现有语义；关闭接口时不得意外新增监听或扩大绑定地址。
- [x] 配置重载/开关后实际监听端点与认证状态一致，失败必须被上层感知，不能无认证回退。

**验收 TODO**：

- [ ] 无凭据、错误凭据返回 401；合法凭据成功；覆盖初次 setup、重载、updateConfig、关闭后开启。
- [ ] 验证 TLS/CORS 字段在对应启用配置下不丢失，外控关闭时没有意外监听。
- [ ] 在隔离进程/环境验证重建路径真正使用完整配置；不能只重复当前 router 单元探针。
- [ ] 记录修复提交、测试命令和结果；复核两个调用点均覆盖。

### F02：面板 ZIP 路径越界及资源预算缺失

**状态**：源码修复/隔离回归完成；未勾平台验收继续跟踪。**范围**：第三方面板下载/解压。**原审查证据**：路径越界已由真实函数隔离复现；资源预算问题为源码确认。

**位置**：`lib/common/zashboard.dart:29–65`，直接路径拼接/写入位于 60–62 行；固定下载地址常量位于 16–17 行。

**问题/触发**：剥离 `dist/` 前缀后直接拼接并写入，未校验归一化结果是否留在解压目录。收到异常/恶意 ZIP 可在当前用户权限范围内越界写文件；没有证据表明当前上游包恶意。完整 bytes 下载/解压还缺少总大小、条目数、deadline 与并发单飞约束。

**已有证据**：合成 ZIP 中 `dist/index.html` 正常，`dist/../escaped-audit-marker.txt` 被写到 panel 目录外，函数仍返回 true。真实 `ensureZashboardUi` 运行于聊天 work 的独立目录，没有访问真实网络或用户文件。

**修复 TODO**：

- [x] 对每个条目规范化并验证目录包含关系；拒绝路径回退、绝对/盘符/UNC 路径及其他危险条目，兼顾 Windows 分隔符。
- [x] 在独立临时目录完整解压并验证后再切换，失败保留已有可用面板，清理本次拥有的临时数据。
- [x] 限制下载 bytes、单文件及总解压量、文件数；限制放在大分配/写入之前，而非事后统计。
- [x] 设置下载/解压总超时、取消和同一目标的单飞，避免重复点击并行下载、竞态写入或半成品被当作 ready。

**验收 TODO**：

- [x] 将原越界 probe 转为保护性回归：存在合法 index.html 的恶意包也不得在目标外产生任何文件。
- [x] 覆盖嵌套前缀、正反斜杠、`..`、绝对路径、无 index、损坏包、重复条目和危险链接（按实际 archive 支持能力）。
- [ ] 在受控限额下测试超大下载、过量条目、解压超限、超时、取消、磁盘写入失败；失败不得损坏旧面板。
  - 下载/条目/实际解压预算、deadline、取消、已有无关文件/完整面板保留已由 21 项用例覆盖；真实磁盘满、权限拒绝和安装中途 I/O 故障未注入。
- [x] 并发调用只执行一套下载/安装，返回值反映真实 ready 状态；不需要真实 ZIP bomb 或外部下载。

### F03：慢 UI 的阻塞可拖住 Core 停止、重启及重配置

**状态**：源码修复/隔离回归完成；未勾平台验收继续跟踪。**范围**：Dart UI ↔ Rust Agent ↔ Go Core。**原审查证据**：Go/Rust 两侧及取消反例已交叉源码确认；未做动态冻结。

**位置**：`services/agent/src/runtime.rs:1191–1193,1212–1214,1307,1332,1349,1372,1651,1660,2332–2348`；`core/server.go:34–40,122`；`core/hub.go:221–228,531–558`。

**问题/触发**：UI 保持 socket 但停止读取，写缓冲和 256 条队列填满后，一条普通响应/生命周期消息使 send().await 阻塞；Core supervisor 分支体里的 await 不能被命令分支抢占。Core 持 connMu 无 deadline 写网络，requestMu 内也会发送；停止路径持 runLock 等 requestMu，控制链可能一起卡住，新请求 goroutine 继续积压。

**必须保留的反例**：仅 stream 消息走 try_send，会丢弃无法入队的样本，不能单独形成该链。取消主要包住 read，writer.abort 依赖循环与后续调用退出，不能保证解开已阻塞的发送。恢复读取/断开连接通常能解堵，但不是自动保证。未将此项认定为当前任务栏故障原因。

**修复 TODO**：

- [x] UI writer 与可靠响应入队有有限 deadline，并定义慢消费者的会话失败/断连与 pending 请求失败传播。
- [x] supervisor 的 stop/restart/cancel 不依赖 UI 输出队列畅通；所有可能阻塞的发送也响应会话取消。
- [x] writer 的失败被会话监督及时发现；替换旧 UI 时旧 handler/writer/队列在有限时间内退出。
- [x] Go 网络写出移出 requestMu/runLock 等业务锁；采用有界、可取消的输出管理，并设置写 deadline。
- [x] 关闭连接/终止流程不能先等待同一个已经阻塞的写锁；限制入口并发/排队，失败不伪装为成功。
- [x] 保持 stream 可丢样与可靠响应必须明确成功/失败的区别，禁止简单吞掉响应来消除阻塞。

**验收 TODO**：

- [ ] 隔离模拟不读但不关 socket 的 UI，填满队列后送普通响应；stop/restart/配置操作均按约定时限完成或明确失败。
- [ ] 覆盖仅 stream、恢复读取、连接断开、writer 报错、新会话替换、handler 已堵在发送中的取消。
- [ ] 检查锁等待、goroutine、task、队列和句柄最终收敛；普通响应没有静默丢失或重复完成。
- [ ] 验证正常吞吐与重连兼容，避免超时设置导致正常大响应反复断连；系统级故障注入使用可恢复环境。
  - 已完成 Go net.Pipe、输出字节/队列/入场上限与并发关闭 race；Agent 满队列 Stop/Restart 确认、stream 预算、256KiB 完整响应、writer 超时/错误、断连重连、替换取消、已接受 strict 事务收尾均 PASS。完整跨组件链路和长时 OS 句柄/吞吐仍按 V05 待验收。

### F04：Helper 丢弃 Core 停止失败后无条件退出

**状态**：源码修复/隔离回归完成；未勾平台验收继续跟踪。**平台**：Windows Helper 服务。**原审查证据**：源码确认，未在本机注入停服务失败。

**位置**：`services/helper/src/service/windows.rs:62–64`；`services/helper/src/service/hub.rs:288–299,320–332`；`services/helper/src/service/process_stop.rs:123,134–135`。

**问题/触发**：SCM Stop 调用 stop_process，忽略其非空错误，立即 process::exit(0)。kill 失败或 3 秒未确认退出时，普通 Command 子进程不保证随父进程退出，可能遗留 SYSTEM Core/端口/TUN，丢失进程内 ManagedCore/owner 信息。

**修复 TODO**：

- [x] SCM 回调投递停止请求，工作线程正确报告 StopPending/checkpoint/wait hint，确认 Core 真退出后才报告成功并退出。
- [x] kill 失败/等待超时保留 handle 与 owner，明确记录/反馈失败，并支持可追踪的后续重试。
- [x] 审查退出、修复、更新等调用面，统一使用真实停止结果，不能只修 stop_process 内部。
- [x] 评估 Job Object 能否提供所有权保证，并核对既有后台存活语义；不把当前源码假定为已有 Job Object。

**验收 TODO**：

- [x] 覆盖正常退出、已退出、kill 失败、延迟退出、等待超时与重复停止；失败时所有权可供重试且不报成功。
- [ ] 隔离 Windows 验证服务停止/更新后无意外残留 Core、端口和 TUN，成功/失败 SCM 状态准确。
- [x] 记录有界等待和恢复路径，避免在 SCM 回调线程长时间阻塞或退出前丢日志。

### F05：配置报错前先覆盖最后有效运行配置

**状态**：源码修复/隔离回归完成；未勾平台验收继续跟踪。**范围**：Core setup、配置保存与脚本输出。**原审查证据**：源码确认 + 纯解析可达性探针。

**位置**：`core/common.go:398–458`，尤其 413–425；`core/hub.go:597–602,1099–1105`；`lib/models/profile.dart:272–291`；`lib/state.dart:397–410,468,781,791–820`。

**问题/触发**：ParseRawConfig 失败先套默认配置并 ApplyConfig，最后才返回错误；setup 参数反序列化失败也会调用默认 setup。保存校验只用 UnmarshalRawConfig，合法结构但语义错误可通过，脚本之后也缺少最终语义校验。界面显示失败时旧规则/监听/TUN 可能已经改变。

**已有证据**：规则 `MATCH,__audit_missing_group__` 通过 raw 校验，但真实 ParseRawConfig 拒绝不存在的代理目标；没有调用 ApplyConfig，运行态替换来自源码证据。

**修复 TODO**：

- [x] 解析到局部 candidate；完整成功后才替换 currentConfig、appliedRawConfig 和运行态。
- [x] 原始参数解析失败、语义失败、merge/script 输出失败均返回错误并保留最后有效配置，不通过默认配置掩盖失败。
- [x] 核对失败前已改动的 strict ingress、描述、健康检查状态、test URL 等相关状态，避免仅延后 currentConfig 赋值却仍有前置副作用。
- [x] 对最终合并/脚本结果做语义验证；初始化没有旧有效配置与更新失败分别处理，保持已确认启动/TUN 意图规则。
- [x] 成功应用后才更新“已应用配置”的 UI/时间戳记录，保留准确错误与可重试语义。

**验收 TODO**：

- [ ] 已运行有效配置下送结构错误、非法 JSON/YAML、不存在组/规则目标以及脚本产生的坏配置；错误返回且旧行为保持。
- [ ] 对比失败前后规则、选组、监听、TUN、外控认证及相关元数据，避免运行策略悄然改变。
- [x] 覆盖无旧配置的首次启动、合法更新、失败后重试及并发/串行应用边界。
- [ ] 在隔离测试/VM 验证真实应用层结果；现有纯 parser probe 不足以关闭该项。
  - 当前已超出原 parser probe：测试实际事务函数、注入 apply/strict 边界、首次后置失败清理、回滚与并发提交；Dart 对 profile 快照、应用成功后的状态投影建立回归。真实监听/TUN 与脚本运行后的系统行为仍未验收。

## 4. P2：日常性能与异步生命周期

### F06：完成 RPC 的响应与 bookkeeping 延迟释放

**状态**：源码修复/隔离回归完成；未勾平台验收继续跟踪。**范围**：Dart Core RPC。**原审查证据**：真实 ClashHandlerInterface 隔离复现。

**位置**：`lib/clash/interface.dart:104–139,148–190,338`；`lib/common/future.dart:13–18`；`lib/manager/connection_manager.dart:80`。

**问题/触发**：handleResult 完成 Completer 后仍将其保留在 map，清理由独立的 timeout + commonDuration Timer 执行。连接快照默认 30 秒 timeout、默认 500ms（最低 100ms）轮询会滞留多份已完成响应。这是有界滞留，不是永久泄漏。

**已有证据**：60 个成功回复后 retainedCompleters=60，响应共 6,000,170 字符；虚拟 31 秒后清零。字符数不是 heap 字节数或当前进程测量。

**外部报告补充复核**：默认 30 秒之外，`lib/clash/interface.dart:237–270` 的 updateConfig/getConfig/setupConfig 使用 2 分钟 timeout，对应 cleanup Timer 和已完成状态也会等待约 2 分钟。Timer 最终会执行，故称为“与 timeout 绑定的多余 Timer/响应滞留”，不能据此称永久孤儿或无界内存泄漏。外部报告与本项为同一根因。

**修复 TODO**：

- [x] 成功、错误、超时、断连/销毁路径统一及时删除 pending/default 状态并释放响应引用。
- [x] 在本地变量保存 Completer，避免提前 remove 后 invoke 再取 map 产生竞态；覆盖同步回调/发送失败。
- [x] 请求结束后取消不再需要的 cleanup Timer，确保迟到/重复回包不能重复完成或复活状态。

**验收 TODO**：

- [x] 原 60 回复 probe 在完成后立即观测到零 pending；不依靠推进 31 秒才能通过。
- [x] 同时覆盖默认 30 秒和自定义 2 分钟 timeout：提前完成后 cleanup Timer 取消、pending 立即释放，不改变真正未完成请求的超时合同。
- [x] 覆盖成功/类型错误/remote error/超时/断连、同步失败与迟到重复回包，默认值与调用方契约保持正确。
- [ ] 大快照持续轮询后 pending 与 timer 数有界，停止后回到基线；按 V02 测量真实 heap/GC，不只断言 map 大小。

### F07：连接页 stop/start 期间丢失自动刷新

**状态**：源码修复/隔离回归完成；未勾平台验收继续跟踪。**原审查证据**：真实 ConnectionManager 隔离复现。

**位置**：`lib/manager/connection_manager.dart:176–206,242–246`；入口 `lib/manager/clash_manager.dart:67`。

**问题/触发**：旧 snapshot 在途时 running=false→true，新 timer 因 _polling 被吞掉；旧 finally 因 generation 不匹配也不再排下一轮，导致一直 loading/旧列表。

**已有证据**：重启并推进虚拟 1 秒后 requestsAfterRestart=1，running=true、visible=true、loading=true，仍只有旧请求。

**修复 TODO**：

- [x] 保留最新运行代的 pending refresh，旧请求退出时按当前状态安排一次新请求。
- [x] 继续丢弃旧代结果，保持单请求在途；不能删掉 generation 防护使旧快照污染新状态。
- [x] 核对手动刷新、可见性、间隔变化与 dispose/stop 的调度一致性。

**验收 TODO**：

- [x] 原 stop/start probe 旧请求结束后自动发出新请求并继续刷新，loading 最终结束。
- [ ] 覆盖旧请求成功、失败、超时，多次启停及隐藏/显示交错；停用或 dispose 后无新请求。
- [x] 验证旧快照不覆盖新代数据、并发请求数不超过设计值、手动刷新仍有效。

### F08：流量轮询 Timer 所有权竞态导致停止后复活

**状态**：源码修复/隔离回归完成；未勾平台验收继续跟踪。**原审查证据**：真实 GlobalState 隔离复现；Android pause/resume 为实际入口之一。

**位置**：`lib/state.dart:171–208`；`lib/manager/app_state_manager.dart:142,182`；`lib/controller.dart:1662`。

**问题/触发**：已有 epoch 保护但没有 executor single-flight；旧 executor 在 stop→resume 后完成，无条件 timer=null，丢失新 Timer 引用。再次 stop 无法取消孤儿 Timer，回调也不校验创建时 epoch。

**已有证据**：lostTimerReference=true；停止后预期请求数=2，实际=3。

**修复 TODO**：

- [x] executor single-flight 与 epoch/Timer 所有权配合，旧完成只能处理自己拥有的状态。
- [x] Timer 回调执行前验证创建时 epoch；stop 同时失效在途与已排任务，避免复活。
- [x] 保留失败隔离与后续恢复能力，不能靠永远停掉轮询掩盖竞态。

**验收 TODO**：

- [x] 原 probe 停止后请求数保持 2，进一步推进多个周期仍不增长。
- [ ] 覆盖快慢请求、任务异常、连续 start、stop/resume 及 Android 生命周期交错；最多一个执行周期在途。
- [x] 验证新的有效恢复正常取样，旧请求完成不能取消/清空当前代 Timer。

### F09：最小化与隐藏窗口仍保留不必要的数据采集

**状态**：源码修复/隔离回归完成；未勾平台验收继续跟踪。**平台**：重点 Windows/Desktop。**原审查证据**：源码确认，未做真实 CPU profile。

**位置**：`lib/manager/window_manager.dart:98–102`；`lib/views/connection/connections.dart:135–137`；`lib/common/window.dart:95`；`lib/manager/app_state_manager.dart:141–155`；`core/hub.go:114,518`。

**问题/触发**：两条路径必须分别处理：① 最小化只 pause renderer，不改 window.visible，连接页仍可每 100–500ms 获取/解码全量 snapshot；② 隐藏到托盘虽停连接页 snapshot，但 desktop 未发送 setUiActive(false)，Core 仍约每 4 秒扫描活动连接并转发请求事件。

**外部报告补充复核与边界**：`lib/controller.dart:56–65` 的 TUN 状态观察为 3 秒，`lib/state.dart:173–186` 的流量周期为上一轮结束后再等 3 秒，`lib/controller.dart:335–340` 的运行时显示为 1 秒；桌面 hidden 未统一暂停这些工作。`lib/state.dart:214–221` 的组刷新是 60 秒 Timer 后再等待 post-frame callback，渲染暂停时不保证仍按墙钟每 60 秒请求。`core/hub.go:544–558` 每轮扫描活动连接，但 requestSeen 会去重，只发送新增 ID，不能写成“每轮全量 IPC 发送”。UI 隐藏且保持连接时活跃标记可能维持 true；`lib/clash/service.dart:1009–1014` 的 detach 和 `services/agent/src/runtime.rs:1368–1369` 的会话退出已有 false 路径，不能写成“Core 永远 true”。TUN/托盘状态一致性有必要的后台消费者，不能一律停止。

**修复 TODO**：

- [x] 统一实际可见、最小化、应用生命周期、当前页面与数据订阅者的活跃信号。
- [x] 非必要连接快照、解码、tracker 更新在后台暂停/合理降频；Core 的 UI 事件生成由有效消费者驱动。
- [x] 按消费者分别核对 TUN 3 秒观察、流量 3 秒周期、运行时 1 秒 Timer、组刷新 60 秒加 post-frame 的必要性；保留托盘状态、后台代理和诊断所需更新。
- [x] 显示/恢复时及时补最新数据；诊断记录等合法后台消费者单独计入，避免误停。
- [x] 仅约束 UI 采集，保持代理/TUN 转发、已确认后台运行与手动停止语义。

**验收 TODO**：

- [ ] 分别验证连接页前台、其他页面、最小化、托盘隐藏、恢复显示，记录请求频率与 Core 事件数量。
- [ ] 按 V01 对比 CPU、分配率、IPC bytes、帧耗时；没有数据不承诺百分比收益。
- [ ] 后台代理流量不断、恢复不显示永久旧数据，正常诊断订阅不丢失约定信息。
  - 源码/隔离测试已覆盖桌面焦点与隐藏/最小化区别、连接页组合信号、Core 活跃状态重申以及 Android resume 迟返代际校验。桌面保留托盘确实消费的 3 秒流量/TUN 与 60 秒组刷新，仅停非必要 1 秒运行时 UI /连接快照；没有测量 CPU 收益。

### F10：测速并发限制形同分批等待，排队不受超时约束

**状态**：源码修复/隔离回归完成；未勾平台验收继续跟踪。**范围**：Dart 发起与 Go Core 队列。**原审查证据**：源码 + 真实生产函数隔离验证。

**位置**：`lib/views/proxies/common.dart:62–102`；`lib/views/proxies/proxies.dart:39–40,55–57`；`lib/clash/interface.dart:396–415`；`lib/common/constant.dart:28`；`core/hub.go:698–720`。

**问题/触发**：先 map(async).toList 启动全部请求，再 batch(100) 只是分批等待；全部分组再并行扇出，相同节点/URL 跨组可重复，按钮无忙状态保护。Core 每项起 goroutine，Background semaphore 排队无总上限/取消，拿到 50 槽之一才开始超时；UI 6 秒超时不取消 Core 工作。

**已有证据**：持有全部槽位，提交 1,000 个 timeout=10ms 请求；100ms 后 1,000 个等待 goroutine、0 callback；释放槽后全部回调。使用不存在代理，没有 URLTest/网络访问。证实积压，不是释放后永久泄漏。

**修复 TODO**：

- [x] 发起端使用未启动任务批次/固定 worker，形成跨分组的全局预算；按 `(节点, URL)` 去重。
- [x] 处理重复点击与忙状态/取消，不重复追加相同批次。
- [x] Core 限制执行并发和等待队列长度，在创建无界 goroutine 前施加资源限制。
- [x] 总 deadline 覆盖排队和执行；UI 超时、取消、配置/会话更换可取消对应 Core 工作。
- [x] 过期结果不得覆盖新批次状态；过载、取消与失败均有明确用户反馈。

**验收 TODO**：

- [x] 原 1,000 请求场景改为验证数量有界且等待包含在总超时内；新保护性断言不能沿用“保留 1,000 个即 PASS”。
- [x] 覆盖跨组重复、空节点、大订阅、连续点击、取消、超时、配置更换与释放槽位。
- [ ] 记录峰值 goroutine/队列/RPC 数和收敛时间，按 V03 验证合法批量测速仍完成且不存在饥饿。

## 5. P2：原生资源、日志与平台失败路径

### F11：Windows 普通系统代理失败路径与 Unicode 排除域名编码

**状态**：源码修复/隔离回归完成；未勾平台验收继续跟踪。**平台**：Windows C++ proxy 插件。**原审查证据**：A/B 为源码确认；C 已用原表达式隔离复现，未动态更改真实系统代理。

**位置**：`plugins/proxy/windows/proxy_plugin.cpp:34,46,50,66,81–96,107,115,130–141,214–225`；Dart 调用/错误处理 `lib/manager/proxy_manager.dart:27–45`。

**子问题 A**：Start 的 fullAddr、bypassAddr、options 三块 new[] 在 RAS 枚举失败时提前 return 泄漏；Stop 的 options 同理，重复失败可累计小块 heap。

**子问题 B**：InternetSetOption 返回值被忽略，RAS 提前返回还跳过广播刷新；普通 StartProxy/StopProxy wrapper 无论结果都 Success(true)，界面无法区分全部/部分失败。PAC 分支已有错误传播，不能回退它。

**子问题 C（本次补充）**：`proxy_plugin.cpp:43` 直接用 `std::wstring(std::string.begin(), end())` 逐字节扩宽，未按 UTF-8 解码。排除列表允许 Unicode：`lib/views/config/network.dart:338–348` → `lib/widgets/input.dart:207–240,497–509,559–570` → `lib/providers/state.dart:156–175` → `lib/manager/proxy_manager.dart:37–43` → `plugins/proxy/lib/proxy_method_channel.dart:19–23`，没有提前转 ASCII/Punycode。Flutter MethodChannel 向 C++ std::string 交付 UTF-8，Windows 插件以 Unicode API 使用该损坏结果。该项是配置正确性缺陷，独立于 heap 泄漏。

**C 的隔离证据**：真实 Flutter EncodableValue 加源码第 43 行原表达式，4 项检查中 ASCII/Punycode 2 PASS，`例子.测试`、`*.例子.测试` 2 个目标 FAIL，exit 1。Unicode 正确 UTF-16 应为 `4F8B 5B50 002E 6D4B 8BD5`，实际出现 `FFE4 FFBE FF8B ...`；CP_UTF8 对照正确。未运行 InternetSetOption、RAS 或实际 IDN bypass 匹配，不能宣称本机已观察到错误路由。SetPac 在同文件 153–158 行已有严格 UTF-8 转换范例。

**修复 TODO**：

- [x] 用字符串自身存储、栈数组或 RAII 管理原生内存，覆盖每个早退/异常路径。
- [x] 检查每个 Windows API 返回值，按 API 契约记录错误码/阶段，向 Dart 传播失败。
- [x] 定义部分应用后失败的清理、必要通知与重试语义，不能让 UI 假成功或残留错误系统代理。
- [x] 保持 PAC 行为与普通代理设置兼容；不能只改一个 Start/Stop 分支。
- [x] 排除项执行严格 UTF-8 → UTF-16 转换，转换失败向 Dart 传播；复用/统一现有 SetPac 编码方式，避免逐字节扩宽。
- [x] 明确普通域名、IDN/Punycode、通配符、`<local>` 等排除项的规范化与匹配合同，保留现有模式语义；是否需 ASCII IDN 标签依据 WinINet 验证决定。
  - 已定义提交参数合同：严格 UTF-8→UTF-16，保留 Unicode/Punycode/通配符原意，拒绝非法编码/NUL。最终 Windows IDN 匹配待实测，不擅自改写成另一套域名规则。

**验收 TODO**：

- [x] 通过可控原生边界模拟第一次/重试 RAS 失败、普通连接及拨号连接设置失败、通知失败；2000次失败循环确认错误码与零设置调用，结合RAII源码复核释放路径。
- [ ] 对上述失败循环实际采集heap/分配计数，确认不存在分配单调增长；本轮没有采集分配趋势，不以调用次数代替内存证据。
- [ ] Start/Stop 成功返回成功，失败传到 UI，部分失败可正确重试；检查实际系统设置与展示一致。
- [ ] 实际更改系统代理仅在获准隔离环境执行，不把小块 heap 问题等同于旧托盘 USER 泄漏。
- [x] 对 ASCII、Punycode、Unicode 域名/通配符、非法编码与分号列表做编码回归；原 2 个 Unicode 失败断言应转绿，ASCII 行为保持。
- [ ] 在获准隔离环境验证 WinINet 实际设置值与 IDN/通配符匹配结果；参数正确不能直接替代网络匹配验收。

### F12：日志文件数量、跨日与删除范围不完整

**状态**：源码修复/隔离回归完成；未勾平台验收继续跟踪。**范围**：Dart FileLogger。**原审查证据**：源码确认，当时未动态验证；本轮已增加受控日志/轮转/清理失败回归，见Dart修复记录。

**位置**：`lib/common/file_logger.dart:79–104,112–143,146–171`。

**子问题 A**：同日满 10MiB 后只关 sink，保留 _currentLogFilePath，选择新 index 时不执行 _rotateLogs；maxLogFiles=7 无法持续约束数量。

**子问题 B**：已打开 sink 未满时不检查日期，跨日继续写昨天日期的文件。

**子问题 C**：当前清理匹配所有 `.log`，没有限制 FileLogger 自身命名，修复滚动时必须避免删除独立 `connections_diagnostic.log` 或其他日志。

**修复 TODO**：

- [x] 每次换文件/创建新文件后保持明确的数量或总量约束，包括同日滚动；避免清理时机导致多留一份。
- [x] 写入/确保 sink 时检查日期，跨日切换正确命名文件。
- [x] 清理只匹配自身文件名，排除当前打开文件、独立诊断日志与外来文件。
- [x] 删除/关闭失败可诊断，保留有界内存队列与现有退避，避免磁盘异常热循环。

**验收 TODO**：

- [x] 使用临时目录、小阈值或受控文件长度验证一天内超过 7 份滚动后上限仍成立。
- [x] 用可控时间覆盖跨日未满/已满、重启继续写、日期切换；不依赖真实等待跨天。
- [x] 放入独立/外来 `.log` 验证不删除，当前打开文件安全，权限/磁盘异常时无无限重试。
- [x] 不误报现有 2,048 条、单条 16Ki 字符队列为无界内存泄漏。

### F13：Agent 认证前 socket/task 可无限保留

**状态**：源码修复/隔离回归完成；未勾平台验收继续跟踪。**范围**：localhost UI IPC。**原审查证据**：源码确认。

**位置**：`services/agent/src/runtime.rs:1136–1143,1161–1165`；对比已有 deadline 的 Core accept 路径 2053 行以后。

**问题/触发**：每次 accept 立即 spawn，认证首行仅限制 4,096 bytes，没有总读取时限或待认证数量限制。本地进程无需 token，连接后不发完整行/不关闭即可长时间保留 socket、task、BufReader、token 与 Arc；重复连接资源无界。

**修复 TODO**：

- [x] 认证首行设置总超时，逐字节慢发送不能无限重置时限。
- [x] 在 spawn/分配前限制待认证连接并发，定义超过限额的拒绝/关闭行为。
- [x] Agent 关闭时取消并收拢未认证 task；保留合法认证、loopback 限制和单 UI 会话替换。

**验收 TODO**：

- [x] 空首行、半行、慢滴流、超长行、错误 token、大量连接、Agent 退出均在限额/时限内收敛。
- [ ] 合法客户端在容量允许时正常认证，过载后恢复可用；任务/句柄不随重复失败增长。
  - 合法认证、8 槽耗尽后的恢复、handler/shared 引用收拢已 PASS；真实 OS 句柄长期曲线未采集。
- [x] 测试只创建隔离 Agent/临时监听，不能冲击运行中的客户端。

### F14：日志完整行读取阶段可发生无界内存分配

**状态**：源码修复/隔离回归完成；未勾平台验收继续跟踪。**范围**：Agent/Helper 读取 Core stdout、stderr。**原审查证据**：源码确认，正常日志通常有换行。

**位置**：`services/agent/src/runtime.rs:1983–1989`；`services/helper/src/service/hub.rs:336–350`；可含配置字符串的 Core 日志示例 `core/hub.go:1024`。

**问题/触发**：read_line(&mut String)/BufRead.lines 先完整读取，再 format 与 logger 截断。异常超长或无换行输出在截断前已大分配；Agent clear 不缩小 capacity，可长期保留峰值。已有日志队列/文件上限不能限制这一步。

**修复 TODO**：

- [x] 有界分块/行读取限制分配，达到阈值后保留有限前缀并继续丢弃至换行。
- [x] 明确截断标记与 UTF-8 边界/错误处理，避免超长 capacity 永久保留或重复完整复制。
- [x] 始终继续排空 stdout/stderr，不能直接停止读取导致 Core 写管道反向阻塞。
- [x] Agent 与 Helper 两处一致处理，并保留原脱敏、队列及滚动保护。

**验收 TODO**：

- [x] 超长有换行、连续无换行、分块 UTF-8、EOF、读取错误与正常后续行；buffer 上界明确且后续日志仍可读取。
- [x] 用内存流/隔离子进程验证两条管道同时排空，不必让真实 Core 产生异常输出。
- [ ] 记录最大分配/缓冲量，确认异常结束后资源收敛。
  - 已验证原始缓冲 len/cap≤16KiB、UTF-8/读取失败及双输出流排空；损坏 UTF-8 解码后的替代字符串最多约 3 倍原始上限，不等同于整个进程分配峰值，后者待压力测量。

### F15：Android TUN 停止超时保留 JNI 引用且缺少迟后回收

**状态**：源码修复/隔离回归完成；未勾平台验收继续跟踪。**平台**：仅 Android。**原审查证据**：源码确认，无 Android 实机复现。

**位置**：`core/lib_android.go:30–105`，尤其 close 37–73、调用 permit 76–89。

**问题/触发**：Binder Protect/ResolveProcess 在途超过 3 秒，drain 超时为避免 use-after-free 故意不 releaseObject(callback)。新 handler 取代旧 handler 后，迟到调用只释放 permit，没有最终安全回收旧 global ref 的路径，可能保留服务对象引用图。

**修复 TODO**：

- [x] handler generation + 引用计数/等价所有权协议管理 retired handler；停止后拒绝新调用。
- [x] 最后一个在途调用结束后仅回收一次旧 JNI global ref，避免旧调用访问新 handler、重复释放或竞态置空。
- [x] 对长期卡住的 Binder 调用提供 pending retired generations 诊断与明确恢复策略。
- [x] 保持停止等待有界；不能直接在超时分支强制释放 callback，也不能恢复成无界等待。

**验收 TODO**：

- [ ] 覆盖及时完成、3 秒后迟返、长期不返、重复停止、快速重启与多代 handler；迟返最终回收，持续在途不发生 UAF。
  - 纯 Go lease 测试已覆盖超时不提前释放、最后迟返恰好释放一次、并发与多代；race 通过、Android arm64 c-shared 编译通过。JNI/Binder 真实 3 秒场景仍为 NOT RUN。
- [ ] Android 模拟/实机验证 JNI 引用及服务对象收敛，检测重复释放和数据竞争。
- [x] 不把此项写成 Windows 内存原因；没有 Android 证据前保持实机验收未完成。

### F16：Windows 托盘菜单按全桌面类名查找，缺少所有权与生命周期校验

**状态**：源码修复/隔离回归完成，平台验收待执行，P2。**平台**：Windows 托盘。**原审查证据**：当前源码与生产调用链确认；未操作真实外部应用菜单。

**位置**：`lib/manager/tray_manager.dart:34–50,53–91,152–170`；`lib/common/windows.dart:134–155`；`plugins/tray_manager/windows/tray_manager_plugin.cpp:211–219,417–424`；`plugins/tray_manager/lib/src/tray_manager.dart:53–73,270–275`；挂载入口 `lib/application.dart:88–98`。

**子问题 A：目标不属于本进程也会尝试关闭/改主题**。`FindWindow('#32768', nullptr)` 在桌面查找第一个菜单窗口，没有 PID、线程或本次 popup 校验。左键托盘事件触发 `_closeWindowsPopupMenu` 并发出 WM_CLOSE；当前原生 TPM_RETURNCMD 菜单返回选中 ID 后，Dart `_dispatchMenuClick` 仍触发同一关闭函数。每 100ms 的主题监视也只检查非零/可见后调用 SetWindowTheme。此前 HMENU 资源修复没有移除这些入口。

**子问题 B：监视启动时机错误**。`_openContextMenu` 等待 popUpContextMenu 返回后才启动监视；当前原生 TrackPopupMenu 已结束，自己的 popup 已关闭，此时全局查找可命中其他菜单。监视也可能跟随外部菜单存续，而非绑定自己的展示周期。

**边界**：确认的是会选错对象并尝试操作；最终是否关闭/变主题取决于消息处理、UIPI 权限和时序。并非所有应用菜单都使用 #32768，正常外部点击本来就可能关闭菜单，不能仅凭菜单消失归因。本轮没有证明它造成 Explorer 崩溃或永久 USER 泄漏。

**修复 TODO**：

- [x] 将关闭/主题处理收敛到原生端受管 popup 的 owner、创建线程和展示生命周期，移除全桌面按类名查找后操作的方式。
- [x] 若暂保留句柄调用，至少验证 PID、创建线程、本次 popup 身份及有效性；外部、陈旧或复用句柄不得操作，仅 PID 相同也不能代替 popup 所有权。
  - 实际方案为删除全桌面 HWND 查找与相关调用，没有保留需要二次校验的外部句柄操作入口。
- [x] 主题在正确的菜单创建/显示阶段应用，结束后停止监视；不要在 TrackPopupMenu 已返回后全局寻找新菜单。
- [x] 覆盖左键托盘、菜单项回调和右键展示三个入口；保持此前多级菜单、选中快照与展示期间资源保护。
- [x] popup 结束、错误、owner 销毁与组件 dispose 都释放监视器，避免额外 100ms 轮询跟随外部窗口。

**验收 TODO**：

- [ ] 隔离 Win32/API 替身覆盖 own/foreign/no-menu/stale/reused HWND，外部目标的关闭/主题调用必须为零。
  - 原拟句柄矩阵改为删除入口的源码核查，主题在本应用菜单展示前设置，native 仅操作自己的 owner；popup widget 与既有 8 组 native/200 次 USER 1→1 回归通过。外部多程序实际交互仍留待下一项。
- [x] 验证菜单选择与取消返回后不启动错位监视，dispose/错误后无残留 Timer。
- [ ] 隔离桌面/VM 验证自己多级菜单、同时存在的外部菜单及不同权限边界，区分 Windows 自然关闭与本应用消息造成的效果。
- [ ] 复跑此前托盘资源回归，确认 USER/GDI 和菜单项回调没有回退；不在当前用户其他应用上发送测试 WM_CLOSE。

### F17：PNG 编码失败会跳过 ui.Image 的显式释放

**状态**：源码修复/隔离回归完成，平台验收待执行，P2。**平台/范围**：Windows 进程图标的 Flutter 图像编码。**原审查证据**：源码及SDK/API契约确认，当时未注入编码失败；本轮真实ui.Image编码故障已建立Red→Green，见原生资源修复记录。

**位置**：`lib/common/process_icon.dart:172–182,267–286`，具体错误出口为 276 行，dispose 位于 277 行；本机 SDK `E:\flutter\bin\cache\pkg\sky_engine\lib\ui\painting.dart:2057–2065,2104–2112`。

**问题/触发**：`Image.toByteData` 合同允许编码失败时 Future 以错误完成。若 await image.toByteData 抛错，后续 image.dispose 被跳过；外层 finally 只释放 Win32/FFI 资源，`_loadWindowsIcon` 将异常降级为 null，也不会补偿释放 ui.Image。

**性质与边界**：已创建图像的异常路径遗漏显式 dispose，资源回收时机失控；这不是 HDC/位图没有 finally，也不能据此宣称已测得永久无限内存或 GDI 增长。它是核查外部第 6 项时新发现的独立问题，与 P02 的正常路径持有时间优化分开跟踪。

**修复 TODO**：

- [x] 对取得的 ui.Image 建立独立 try/finally/等价所有权，成功、null 与编码异常都 dispose 恰好一次。
- [x] 保持现有 Win32/FFI 成对释放，不能为修 Flutter 图像资源而移除底层 finally。
- [x] 编码失败返回约定降级结果，同时后续串行图标任务可继续处理；错误记录按既有日志/脱敏模式。
- [x] 检查解码错误/回调不返回的恢复策略并补证据；目前只作为待验证健壮性边界，不将其标成已动态复现的队列死锁。

**验收 TODO**：

- [x] 隔离注入编码成功、返回 null、Future 报错，验证 ui.Image 的释放次数均为一次，无 double-dispose。
- [ ] 编码失败后后续不同图标仍能提取；Win32 资源最终释放，缓存仍保持已有上限。
- [ ] 分别记录 Flutter 引擎图像资源与 GDI 指标，未做压力采样前不填写资源增长数量或事故因果。

## 6. 单列优化候选

### P01：对比 UI 进程 NORMAL 与 HIGH 优先级

**状态**：待测量，P3。**位置**：`windows/runner/main.cpp:16` 的 HIGH_PRIORITY_CLASS。

**外部报告核验**：设置事实存在，本机只读采样亦见 FlClashX 为 High、BasePriority=13。微软文档警告高优先级 CPU 密集工作可能抢占低优先级线程，值得测量；调度还取决于线程相对/动态优先级、ready 状态和 CPU 负载。没有调度跟踪或对照实验证明其导致本次 Explorer 崩溃、任务栏卡死或输入法故障，不能直接升级为已确认 P0。外部报告把 DWM/输入相关进程一概称为 8–10 也不准确：2026-10-09 本轮采样 dwm/ctfmon 均为 BasePriority=13。上述只读进程快照不等于所有线程动态优先级或饥饿证明。

- [ ] 同机器、同包源码、同配置分别测 NORMAL/HIGH，固定前台、后台和 CPU 竞争场景。
- [ ] 记录 UI 帧耗时、Core 吞吐、桌面/任务栏交互延迟、CPU 与工作集，避免用单个瞬时值决定。
- [ ] 根据数据决定是否改优先级并记录取舍；没有收益证据时不以“优化”名义直接修改。
- [ ] 不宣称该设置已被证实导致开始菜单失灵，不保证修改优先级会降低 CPU 或内存。

### P02：缩短图标原生资源持有范围并测量提取队列

**状态**：同步释放范围已实现，P3；收益/队列/压力测量待执行，持续泄漏/事故因果未证实。**位置**：以下为修复前 `lib/common/process_icon.dart:13–33,167–207,211–286`。

**事实**：239 行取得 HDC，240–251 行 GetDIBits 已读取并复制像素；HDC/HBITMAP/FFI buffer 仍留到 275/276 两次 await 后的 finally，HICON 在外层 finally 释放。正常结束或编码异常均有 Win32 释放路径。当前 `_extractQueue` 串行等待完整提取/编码，同一 UI isolate 最多一组正在提取的原生图标资源；LRU 缓存上限为 64，因此不能从“列表很多进程”直接推断同时占用大量 DC。

**官方契约边界**：GetDC/ReleaseDC 要求同一线程、common DC 用后释放，Common Display Device Contexts 建议尽快释放；官方文档没有外部报告所称的“严禁跨消息循环”原文，await 本身也不能证明发生跨 OS 线程释放。源码未把此 HDC 交给其他 isolate/thread。F17 针对另外一类 Flutter 图像显式释放缺口。

- [x] 复制完 BGRA 后，在进入异步解码/编码前结束原生提取作用域，释放 HDC/HBITMAP/原始 buffer/HICON；保证失败路径成对释放且无双重释放。
- [ ] 延迟解码/编码的隔离验证中观测原生资源已释放；正常图标、透明度处理与 PNG 内容不回退。
- [ ] 连续不同图标压力测试记录 USER/GDI、原生内存和持有时长，核对单个 isolate 串行保证与所有调用面。
- [ ] 单独测量待提取队列长度、缓存淘汰后仍运行的任务；64 项 LRU 不等于排队上限。是否增加队列预算/取消依测量决定，未把该候选夸大成已复现无界 GDI 泄漏。
- [x] 保留有界缓存与串行提取，不用扩大并发来掩盖慢编码，收益与残余风险记录到 V04。

## 7. 待执行的性能与恢复验收

以下五组来自原审查报告，均为 NOT RUN。每组固定源码/包 hash、机器、系统、配置规模、采样频率和持续时长，分别记录 UI、Agent、Core、Helper；不要只看单进程工作集。具体规模/预算在实施时冻结，不能事后为结果放宽。

### V01：空闲、前台连接页、最小化、托盘

- [ ] 固定连接规模，对四种状态及互相切换采样 CPU、分配率、IPC 次数/bytes、snapshot 频率和 Core 事件频率。
- [ ] 对照 F09 修复前后，确认后台非必要高频工作减少，前台恢复及时且代理流量不受影响。
- [ ] 记录实际持续时间、均值/峰值和可重复性，不承诺未测百分比。

### V02：连接快照规模与 RPC/GC

- [ ] 小/中/大连接规模分别以 500ms、100ms 刷新，采集 Dart heap、分配率、GC、frame time、pending RPC/timer 数。
- [ ] F06 修复后完成响应及时释放，停止刷新后回到稳定水平；把缓存驻留与泄漏趋势分开判断。
- [ ] 对 F07/F08 添加启停交错，确认没有停更、旧结果覆盖或停止后复活。

### V03：批量测速、重复触发与取消

- [ ] 大订阅、跨组重复、重复点击、取消/超时/配置更新，采集 goroutine、队列、RPC 数及总回调时间。
- [ ] F10 修复后执行和排队均有界、排队计入 deadline，过期任务停止，正常批次不饥饿。
- [ ] 如需真实测速，先固定获准测试端点和负载，记录请求量/时长；隔离队列 probe 不代表真实网络性能。

### V04：反复启停、断连/重连与窗口/托盘交互

- [ ] 在固定循环次数/长时窗口记录 USER/GDI、句柄、线程、子进程、内存、Timer，不出现随循环单调增长。
- [ ] 覆盖菜单重建、菜单显示期间刷新/销毁、窗口隐藏恢复、连接页切换、失败后重试。
- [ ] 覆盖 F16 外部菜单所有权与结束后的监视收拢，以及 F17/P02 图标编码失败、缓慢编码与原生资源持有时长。
- [ ] 结合 H01 托盘旧问题复验；新缺陷与旧已修回归分别记录，保留原包与原证据。

### V05：慢消费者、停止失败与 Android Binder 迟返

- [ ] 可恢复隔离环境制造慢 UI、队列填满、断连与取消，确认 F03 在限时内失败/恢复且资源收敛。
- [ ] 注入 Core kill/退出确认失败，验证 F04 所有权与 SCM 状态、无假成功和不可追踪孤儿。
- [ ] Android 验证 F15 迟返的安全回收，长期不返时有明确诊断/恢复，不发生 UAF。
- [ ] 系统/服务/路由故障注入按对应环境授权执行，不能因本 TODO 已登记而在开发工作站自动执行。

## 8. 历史修复与系统恢复边界

### H01：此前托盘 USER/HMENU 泄漏——代码已修，补充验收待办

这是历史问题，不重复计入 F01–F15，也不再次列成“尚未修复的源码泄漏”。

- [x] 已确认旧 tray_manager 用 RemoveMenu 脱挂但未释放菜单树，频繁观察触发重复重建；旧 UI 曾达到 USER=10,000。
- [x] 已有修复提交 `71a07a9d7ad0502d4a3eef1527e499460542b026`，涵盖菜单所有权/失败清理/展示期替换及 UI 刷新串行合并；证据见 `engineering/testing/tray-menu-resources-2026-10-08.md`。
- [x] 已产出 trayfix 预览包并经用户授权切换；历史 2026-10-09 00:53:48 采样修复版 USER=105、GDI=67，此前 20 次采样 USER=102–103、GDI=67。仅为当时观测，不代表当前/长期状态。
- [ ] 按 V04 完成长时、多层菜单、显示期间更新、owner dispose/reset 与窗口恢复实机验收；记录 USER/GDI 趋势和交互结果。
- [ ] 如更新历史台账，在新增记录说明后续授权与实测，保留当时 NOT RUN 的历史事实，不回写旧记录冒充当时已完成。

### S01：开始按钮无反应——独立系统恢复待办

**状态**：诊断已记录，恢复与恢复后验收未完成。**范围**：当前 Windows 登录会话 Shell；不计入产品源码缺陷数量。

证据文件：`C:\Users\冯飏\Documents\Codex\2026-10-08\new-chat\outputs\windows-start-menu-diagnosis-2026-10-09.md`。以下均为该时点的历史记录，执行前重新采样：

- Explorer 消息循环响应，但 8 个 StartMenuExperienceHost、5 个 SearchHost 条目均为 0 线程/0 句柄；相关进程状态查询受 ACL 限制，不能断言其内核终止状态。
- 2026-10-09 00:54:19 Ctrl+Esc 未激活菜单；历史 StartMenu 崩溃 180 次、SearchHost 203 次，均早于退出旧客户端；曾有 0x80070008 资源不足与 COM 激活失败。
- 注册包/manifest 与可执行文件存在、签名有效、关键服务运行；没有据此确认包健康，也没有证实第三方模块是原因。

**后续 TODO**：

- [ ] 恢复操作前重新确认 Shell 宿主、USER/GDI、日志和当前会话状态，保留恢复前证据。
- [ ] 在对应恢复范围明确后恢复 Explorer/开始菜单组件，优先可逆方式；本次文档任务不执行系统操作。
- [ ] 分别验证鼠标开始按钮、Ctrl+Esc、搜索及新宿主线程/句柄；复查 Application/System/TWinUI 等日志。
- [ ] 如仍失败，根据新错误调查用户包激活/数据或独立原因，不把无新日志、Explorer 响应、FlClashX USER 下降等同于菜单恢复。

## 9. 历史验证记录与复现入口

### 9.1 已执行结果

测试环境：Flutter 3.47.4 / Dart 3.13.3；Go 1.25.13 windows/amd64；源码为本文基线。全部为隔离测试/合成数据，没有测试当前运行 Core API，没有网络测速或真实监听。

| 编号 | 对应任务 | 断言/观察 | 历史结果 |
|---|---|---|---|
| T01 | F06 | 完成后释放 pending | FAIL；60 条仍保留，6,000,170 字符，31 秒后清零 |
| T02 | F07 | 旧请求遇启停后自动继续刷新 | FAIL；请求数仍为 1，loading=true |
| T03 | F08 | 停止后不再发起流量取样 | FAIL；预期 2，实际 3，丢失 Timer 引用 |
| T04 | F02 | 解压不得写出目标目录 | FAIL；返回 true 且目录外出现标记 |
| T05 | F05 | raw/semantic 校验对照 | 观察性探针 exit 0；raw 通过，semantic 拒绝不存在组 |
| T06 | F10 | 排队超出声明 timeout 的行为 | 观察性测试 1 PASS；等待 1,000 goroutine，释放槽后排空 |
| T07 | F01 | 真实 router 有/无 secret | 观察性测试 1 PASS；匿名 200/401 对照 |
| T08 | F11-C | UTF-8 排除项到 UTF-16 参数的保真 | C++ 表达式隔离 probe：2 PASS / 2 目标 FAIL，exit 1；未改系统代理 |

**解释**：四个 Flutter FAIL 是缺陷复现，不能写成修复成功；Go PASS 仅表示观察探针证实描述的行为，不能替代修复后的保护性断言。

T08 为本次外部报告复核新增证据，使用实际 Flutter EncodableValue、原 C++ 转换表达式和独立 UTF-16 期望值；不等同于执行完整插件或 WinINet 匹配。g++ 16.1.0 构建成功，主代理重跑 166ms，2 个 ASCII/Punycode 检查通过、2 个 Unicode 检查因目标缺陷失败，0 SKIP。源代码、命令、完整边界见 [补充核验记录](evidence/external-review-verification-2026-10-09.md)；F16/F17/P02 仍为源码/契约证据，没有宣称动态跨进程或图像编码故障测试已运行。

Flutter 最终合并重跑：0 PASS / 4 FAIL / 0 SKIP，exit 1，6.665 秒。

```powershell
# 工作目录：E:\CodeWorkstation\FlClashX
& 'E:\flutter\bin\flutter.bat' test --no-pub 'C:\Users\冯飏\Documents\Codex\2026-10-08\new-chat\work\performance-audit\dart_lifecycle_probe_test.dart' 'C:\Users\冯飏\Documents\Codex\2026-10-08\new-chat\work\performance-audit\zashboard_archive_probe_test.dart' --reporter expanded
```

Flutter 输出：`C:\Users\冯飏\Documents\Codex\2026-10-08\new-chat\work\performance-audit\flutter-audit-result.txt`。

Go 共同环境仅作用于测试 shell/子进程，使用已有固定依赖与 overlay：

```powershell
# 工作目录：E:\CodeWorkstation\FlClashX\core
$env:GOPROXY='off'
$env:GOSUMDB='off'
$env:GOTOOLCHAIN='local'
$env:CGO_ENABLED='0'

go run '-modfile=.generated/go.mod' '-overlay=.generated/mihomo-overlay.json' 'C:\Users\冯飏\Documents\Codex\2026-10-08\new-chat\work\core-audit-probe\main.go'

go test '-modfile=.generated/go.mod' '-overlay=C:\Users\冯飏\Documents\Codex\2026-10-08\new-chat\work\core-audit-probe\audit-overlay.json' -run '^TestAuditQueuedDelayIgnoresDeclaredTimeout$' -count=1 -timeout=10s -v .

go test '-modfile=.generated/go.mod' '-overlay=C:\Users\冯飏\Documents\Codex\2026-10-08\new-chat\work\core-audit-probe\audit-overlay.json' -run '^TestAuditControllerSecretRequired$' -count=1 -timeout=10s -v github.com/metacubex/mihomo/hub/route
```

- Parser：1 合成场景，exit 0，4.338 秒；没有调用 ApplyConfig。
- 排队：1 PASS / 0 FAIL / 0 SKIP，exit 0，5.896 秒，用例 0.11 秒；没有 URLTest。
- Router：1 PASS / 0 FAIL / 0 SKIP，exit 0，5.231 秒，用例 0.00 秒；没有真实 HTTP listener。
- Go 源探针与输出：聊天 `work/core-audit-probe/` 下 `main.go`、`queued_delay_audit_test.go`、`controller_auth_audit_test.go`、`audit-overlay.json`、`results.md`。完整根路径为 `C:\Users\冯飏\Documents\Codex\2026-10-08\new-chat\work\core-audit-probe`。
- 首次 Flutter harness Timer.zero 推进不足、Go parser 缺 linkname 提供者、router httptest 类型不匹配均已在隔离 harness 修正；最终上述输出来自修正后运行，没有改产品源码来让 probe 通过。

### 9.2 修复与回归执行状态

- [x] 把有价值的保护性断言迁入仓库正式测试，移除聊天绝对路径依赖；原始 probe/历史结果保留。
- [x] Go 已新增完整配置/失败事务、有界排队及实际依赖认证/history 合同断言，未沿用不安全行为出现即 PASS 的旧探针作为门禁。
- [x] 各模块补齐实际 Red → Green、源码确认及所属回归；无法安全动态 Red 的系统路径单独说明，没有伪造先红后绿。
- [x] 修复范围 Flutter/Go/Agent/Helper、原生测试和静态检查已执行，命令/exit/数量与环境见四份 evidence；Windows 构建结果见修复汇总。Agent clippy 和 Dart analyze 的基线诊断如实保留。
- [x] 最终 Flutter 457 项全量测试收集行/分支覆盖率至聊天独立目录，未覆盖原 coverage/。改动且有 LCOV 记录的可执行行 535/706（75.78%）、分支 182/291（62.54%）；两个 manager 文件未载入 LCOV，真实平台/入口缺口见修复汇总。Core 语句覆盖40.5%，标准Go不提供分支率；overlay依赖coverage受工具限制，Rust覆盖率未采集。
- [ ] 按 V01–V05 补长时 profile、原生失败路径与 Android 实机证据；本次均 NOT RUN。
- [x] 独立复核取消事务、配置快照、Android resume 迟返、测速 history 提交、ZIP 预检和打包来源；具体发现均修复并重跑相关验证，平台证据边界继续保留。

## 10. 排除项与防误报清单

以下作为审查边界保存，不删除也不转为已证实缺陷：

- 托盘旧 RemoveMenu/HMENU 问题已有修复，见 H01；新的普通代理 RAS 小块 heap 泄漏不能与其混为一谈。
- 进程图标缓存已有 BoundedCache 上限，HICON/HBITMAP/HDC 的 Win32 finally 释放路径仍成立；异步持有时间见 P02，Flutter ui.Image 编码异常释放见 F17，不能把这两类问题混为 Win32 句柄永久泄漏。图片缓存已有数量/内存上限；Agent replay journal 有 128 条上限。
- Dart 日志内存队列已有 2,048 条/单条 16Ki 字符保护；Rust 日志队列 256 条、单条 16Ki 字符，文件 8MiB 加三个轮转文件。F12/F14 针对其他缺口。
- QuickJS runtime 已通过 try/finally dispose，不能重复报告旧的未释放问题。
- ConnectionFlag 的缓存候选没有找到实际实例化调用点，本轮不认定为运行泄漏；将来接入时应重新评估。
- MemoryInfo dispose 后旧 await 可能多排一个 timer，下一轮 mounted 门禁拦住；现有证据不支持无限循环/永久泄漏。
- 未发现可新增认定为正常高频 USER/GDI 泄漏的另一处证据，但不宣称全仓无其他资源问题。
- RPC 的约 30 秒滞留、测速的无界排队、异常日志峰值、条件性 JNI/heap 泄漏分别表述，不能统称已经发生的永久内存泄漏。
- 没有长期 profile 或真实系统恢复证据前，不承诺提升比例、不断言任务栏/开始菜单已恢复、不把所有缺陷都归因于当前电脑故障。

## 11. 执行顺序与关闭标准

建议顺序：F01–F05 → F06–F10 → F11–F17；P01/P02 依赖测量，V01–V05 随对应修复批次执行；H01/S01 保持独立状态。

每项完成时在对应章节追加以下记录，未满足的验收框保持未勾选：

- 修复提交/分支与涉及文件。
- 原缺陷复现、修复后目标测试、相关回归的命令、结果与证据位置。
- 真实平台/长时验证的范围；NOT RUN 项及其原因。
- 独立复核结论、残余风险与后续行动。
- 若交付包：源码/组件来源与 hash、安装/运行/回滚证据；源码已修、包已构建、实机已验收分别标记。

关闭条件：修复 TODO 与适用验收均有证据；不能以文档已写、单个探针 PASS、一次构建成功或短时资源下降关闭产品问题。

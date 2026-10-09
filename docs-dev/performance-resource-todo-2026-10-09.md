# FlClashX 性能、资源生命周期与可靠性 TODO

创建日期：2026-10-09（Asia/Singapore）。本次交付：记录与交接待办，不实施本清单中的产品修复。

## 1. 来源、状态与执行边界

- 排查源码：`E:\CodeWorkstation\FlClashX`，`development@c5c5ae4400d225cf2abefccb92184d29c1b81bcd`。下列行号对应该源码基线；实施前重新核对当前版本。
- 完整证据：[原始审查报告快照](evidence/performance-resource-audit-2026-10-09.md)。原输出文件：`C:\Users\冯飏\Documents\Codex\2026-10-08\new-chat\outputs\flclashx-performance-resource-audit-2026-10-09.md`。
- F01–F15 均为 **OPEN / 待修复**，没有因整理文档而完成；其中 F11/F12 等包含多个必须一起跟踪的子问题。
- P01 为 **待测量的优化候选**；V01–V05 为 **尚未运行的性能/系统验收任务**。H01 为此前已修代码的历史记录，仍有长期验收待办；S01 为系统恢复待办，不冒充产品代码缺陷。
- 证据等级：**隔离复现**（真实类/函数、合成输入）；**源码确认**（完整失败路径已核对）；**优化候选**（需要基准数据）。不要混淆这三者。
- 优先级：P1＝下一批优先处理的高影响问题；P2＝随后稳定性/资源修复；P3＝测量后再决定的优化。优先级不表示本机此刻正在触发。
- 本轮未改变运行中的客户端、代理、TUN、服务、Windows Shell 或用户配置；没有把这些发现作为此前任务栏故障的完整因果证明。
- 本清单保持原 15 项编号，附加项使用 P/V/H/S 前缀，便于一一核对、不重复计数。

## 2. 总待办清单

- [ ] **F01 · P1** 完整保留外部控制接口认证与控制器配置。
- [ ] **F02 · P1** 约束面板 ZIP 写入路径及下载/解压资源预算。
- [ ] **F03 · P1** 阻断慢 UI 的 IPC 背压向 Core 控制链传播。
- [ ] **F04 · P1** Helper 确认真正停止 Core 后再退出，保留失败所有权。
- [ ] **F05 · P1** 配置失败时保留最后有效运行配置。
- [ ] **F06 · P2** RPC 完成后及时释放 pending 状态与响应引用。
- [ ] **F07 · P2** 修复 ConnectionManager 在途请求遇 stop/start 后停更。
- [ ] **F08 · P2** 修复流量轮询 Timer 所有权竞态和停止后复活。
- [ ] **F09 · P2** 按真实前后台可见性控制 UI 取样与 Core 事件生成。
- [ ] **F10 · P2** 为测速建立真实并发/排队上限和端到端取消超时。
- [ ] **F11 · P2** 修复 Windows 代理插件错误路径泄漏及恒报成功。
- [ ] **F12 · P2** 修复日志数量、跨日滚动和清理所有权。
- [ ] **F13 · P2** 限制 Agent 认证前连接数量及等待时间。
- [ ] **F14 · P2** 对 Core stdout/stderr 使用有界行读取。
- [ ] **F15 · P2** Android retired TUN handler 的 JNI 引用安全迟后回收。
- [ ] **P01 · P3** 测量 NORMAL/HIGH 进程优先级后决定是否调整。
- [ ] **V01–V05** 完成第 7 节的五组性能、生命周期与故障恢复验收。
- [ ] **H01** 补此前托盘修复的长期与真实交互验收。
- [ ] **S01** 按独立系统恢复范围验证开始按钮/搜索宿主恢复。

## 3. P1：安全与控制可靠性

### F01：外部控制接口重建遗漏 secret、TLS/CORS 等配置

**状态**：OPEN。**平台/范围**：Go Core 外控重建路径。**证据**：源码确认 + 实际固定依赖 router 的内存 HTTP 验证。

**位置**：`core/common.go:366,436`；`lib/state.dart:521–533`；默认值见 `lib/models/clash_config.dart:502`、`lib/enum/enum.dart:169–173`。Mihomo 固定源为 `core/.generated/mihomo-v1.19.32-source-adb2170dcce92d63d9da0102eb6669bf8b719c6d9ed33b985c3d0a3aa9c1dd7a/hub/route/server.go:60,92,119,162,181`，由 `.generated/go.mod:158` 指向。

**问题/触发**：两处 `route.ReCreateServer` 只构造 Addr，secret 被置空；实际依赖不会沿用旧 secret。启用外控，或 profile 携带外控地址/密钥后，setup 或 UI 更新路径可丢失认证。默认外控关闭，开启默认绑定 `127.0.0.1:9090`；profile 地址优先，通配/LAN 绑定时风险扩大，不能称默认公网暴露。

**已有证据**：真实 router、合成配置、内存请求 `/version`：仅地址时匿名 200，保留合成 secret 时匿名 401。没有启动监听或验证当前运行实例。

**修复 TODO**：

- [ ] 审查两个重建调用点及全部调用面，统一完整 controller config 的构造，保留 Secret、TLS、CORS 和其他适用字段。
- [ ] 保持 UI 开关与订阅地址优先的现有语义；关闭接口时不得意外新增监听或扩大绑定地址。
- [ ] 配置重载/开关后实际监听端点与认证状态一致，失败必须被上层感知，不能无认证回退。

**验收 TODO**：

- [ ] 无凭据、错误凭据返回 401；合法凭据成功；覆盖初次 setup、重载、updateConfig、关闭后开启。
- [ ] 验证 TLS/CORS 字段在对应启用配置下不丢失，外控关闭时没有意外监听。
- [ ] 在隔离进程/环境验证重建路径真正使用完整配置；不能只重复当前 router 单元探针。
- [ ] 记录修复提交、测试命令和结果；复核两个调用点均覆盖。

### F02：面板 ZIP 路径越界及资源预算缺失

**状态**：OPEN。**范围**：第三方面板下载/解压。**证据**：路径越界已由真实函数隔离复现；资源预算问题为源码确认。

**位置**：`lib/common/zashboard.dart:29–65`，直接路径拼接/写入位于 60–62 行；固定下载地址常量位于 16–17 行。

**问题/触发**：剥离 `dist/` 前缀后直接拼接并写入，未校验归一化结果是否留在解压目录。收到异常/恶意 ZIP 可在当前用户权限范围内越界写文件；没有证据表明当前上游包恶意。完整 bytes 下载/解压还缺少总大小、条目数、deadline 与并发单飞约束。

**已有证据**：合成 ZIP 中 `dist/index.html` 正常，`dist/../escaped-audit-marker.txt` 被写到 panel 目录外，函数仍返回 true。真实 `ensureZashboardUi` 运行于聊天 work 的独立目录，没有访问真实网络或用户文件。

**修复 TODO**：

- [ ] 对每个条目规范化并验证目录包含关系；拒绝路径回退、绝对/盘符/UNC 路径及其他危险条目，兼顾 Windows 分隔符。
- [ ] 在独立临时目录完整解压并验证后再切换，失败保留已有可用面板，清理本次拥有的临时数据。
- [ ] 限制下载 bytes、单文件及总解压量、文件数；限制放在大分配/写入之前，而非事后统计。
- [ ] 设置下载/解压总超时、取消和同一目标的单飞，避免重复点击并行下载、竞态写入或半成品被当作 ready。

**验收 TODO**：

- [ ] 将原越界 probe 转为保护性回归：存在合法 index.html 的恶意包也不得在目标外产生任何文件。
- [ ] 覆盖嵌套前缀、正反斜杠、`..`、绝对路径、无 index、损坏包、重复条目和危险链接（按实际 archive 支持能力）。
- [ ] 在受控限额下测试超大下载、过量条目、解压超限、超时、取消、磁盘写入失败；失败不得损坏旧面板。
- [ ] 并发调用只执行一套下载/安装，返回值反映真实 ready 状态；不需要真实 ZIP bomb 或外部下载。

### F03：慢 UI 的阻塞可拖住 Core 停止、重启及重配置

**状态**：OPEN。**范围**：Dart UI ↔ Rust Agent ↔ Go Core。**证据**：Go/Rust 两侧及取消反例已交叉源码确认；未做动态冻结。

**位置**：`services/agent/src/runtime.rs:1191–1193,1212–1214,1307,1332,1349,1372,1651,1660,2332–2348`；`core/server.go:34–40,122`；`core/hub.go:221–228,531–558`。

**问题/触发**：UI 保持 socket 但停止读取，写缓冲和 256 条队列填满后，一条普通响应/生命周期消息使 send().await 阻塞；Core supervisor 分支体里的 await 不能被命令分支抢占。Core 持 connMu 无 deadline 写网络，requestMu 内也会发送；停止路径持 runLock 等 requestMu，控制链可能一起卡住，新请求 goroutine 继续积压。

**必须保留的反例**：仅 stream 消息走 try_send，会丢弃无法入队的样本，不能单独形成该链。取消主要包住 read，writer.abort 依赖循环与后续调用退出，不能保证解开已阻塞的发送。恢复读取/断开连接通常能解堵，但不是自动保证。未将此项认定为当前任务栏故障原因。

**修复 TODO**：

- [ ] UI writer 与可靠响应入队有有限 deadline，并定义慢消费者的会话失败/断连与 pending 请求失败传播。
- [ ] supervisor 的 stop/restart/cancel 不依赖 UI 输出队列畅通；所有可能阻塞的发送也响应会话取消。
- [ ] writer 的失败被会话监督及时发现；替换旧 UI 时旧 handler/writer/队列在有限时间内退出。
- [ ] Go 网络写出移出 requestMu/runLock 等业务锁；采用有界、可取消的输出管理，并设置写 deadline。
- [ ] 关闭连接/终止流程不能先等待同一个已经阻塞的写锁；限制入口并发/排队，失败不伪装为成功。
- [ ] 保持 stream 可丢样与可靠响应必须明确成功/失败的区别，禁止简单吞掉响应来消除阻塞。

**验收 TODO**：

- [ ] 隔离模拟不读但不关 socket 的 UI，填满队列后送普通响应；stop/restart/配置操作均按约定时限完成或明确失败。
- [ ] 覆盖仅 stream、恢复读取、连接断开、writer 报错、新会话替换、handler 已堵在发送中的取消。
- [ ] 检查锁等待、goroutine、task、队列和句柄最终收敛；普通响应没有静默丢失或重复完成。
- [ ] 验证正常吞吐与重连兼容，避免超时设置导致正常大响应反复断连；系统级故障注入使用可恢复环境。

### F04：Helper 丢弃 Core 停止失败后无条件退出

**状态**：OPEN。**平台**：Windows Helper 服务。**证据**：源码确认，未在本机注入停服务失败。

**位置**：`services/helper/src/service/windows.rs:62–64`；`services/helper/src/service/hub.rs:288–299,320–332`；`services/helper/src/service/process_stop.rs:123,134–135`。

**问题/触发**：SCM Stop 调用 stop_process，忽略其非空错误，立即 process::exit(0)。kill 失败或 3 秒未确认退出时，普通 Command 子进程不保证随父进程退出，可能遗留 SYSTEM Core/端口/TUN，丢失进程内 ManagedCore/owner 信息。

**修复 TODO**：

- [ ] SCM 回调投递停止请求，工作线程正确报告 StopPending/checkpoint/wait hint，确认 Core 真退出后才报告成功并退出。
- [ ] kill 失败/等待超时保留 handle 与 owner，明确记录/反馈失败，并支持可追踪的后续重试。
- [ ] 审查退出、修复、更新等调用面，统一使用真实停止结果，不能只修 stop_process 内部。
- [ ] 评估 Job Object 能否提供所有权保证，并核对既有后台存活语义；不把当前源码假定为已有 Job Object。

**验收 TODO**：

- [ ] 覆盖正常退出、已退出、kill 失败、延迟退出、等待超时与重复停止；失败时所有权可供重试且不报成功。
- [ ] 隔离 Windows 验证服务停止/更新后无意外残留 Core、端口和 TUN，成功/失败 SCM 状态准确。
- [ ] 记录有界等待和恢复路径，避免在 SCM 回调线程长时间阻塞或退出前丢日志。

### F05：配置报错前先覆盖最后有效运行配置

**状态**：OPEN。**范围**：Core setup、配置保存与脚本输出。**证据**：源码确认 + 纯解析可达性探针。

**位置**：`core/common.go:398–458`，尤其 413–425；`core/hub.go:597–602,1099–1105`；`lib/models/profile.dart:272–291`；`lib/state.dart:397–410,468,781,791–820`。

**问题/触发**：ParseRawConfig 失败先套默认配置并 ApplyConfig，最后才返回错误；setup 参数反序列化失败也会调用默认 setup。保存校验只用 UnmarshalRawConfig，合法结构但语义错误可通过，脚本之后也缺少最终语义校验。界面显示失败时旧规则/监听/TUN 可能已经改变。

**已有证据**：规则 `MATCH,__audit_missing_group__` 通过 raw 校验，但真实 ParseRawConfig 拒绝不存在的代理目标；没有调用 ApplyConfig，运行态替换来自源码证据。

**修复 TODO**：

- [ ] 解析到局部 candidate；完整成功后才替换 currentConfig、appliedRawConfig 和运行态。
- [ ] 原始参数解析失败、语义失败、merge/script 输出失败均返回错误并保留最后有效配置，不通过默认配置掩盖失败。
- [ ] 核对失败前已改动的 strict ingress、描述、健康检查状态、test URL 等相关状态，避免仅延后 currentConfig 赋值却仍有前置副作用。
- [ ] 对最终合并/脚本结果做语义验证；初始化没有旧有效配置与更新失败分别处理，保持已确认启动/TUN 意图规则。
- [ ] 成功应用后才更新“已应用配置”的 UI/时间戳记录，保留准确错误与可重试语义。

**验收 TODO**：

- [ ] 已运行有效配置下送结构错误、非法 JSON/YAML、不存在组/规则目标以及脚本产生的坏配置；错误返回且旧行为保持。
- [ ] 对比失败前后规则、选组、监听、TUN、外控认证及相关元数据，避免运行策略悄然改变。
- [ ] 覆盖无旧配置的首次启动、合法更新、失败后重试及并发/串行应用边界。
- [ ] 在隔离测试/VM 验证真实应用层结果；现有纯 parser probe 不足以关闭该项。

## 4. P2：日常性能与异步生命周期

### F06：完成 RPC 的响应与 bookkeeping 延迟释放

**状态**：OPEN。**范围**：Dart Core RPC。**证据**：真实 ClashHandlerInterface 隔离复现。

**位置**：`lib/clash/interface.dart:104–139,148–190,338`；`lib/common/future.dart:13–18`；`lib/manager/connection_manager.dart:80`。

**问题/触发**：handleResult 完成 Completer 后仍将其保留在 map，清理由独立的 timeout + commonDuration Timer 执行。连接快照默认 30 秒 timeout、默认 500ms（最低 100ms）轮询会滞留多份已完成响应。这是有界滞留，不是永久泄漏。

**已有证据**：60 个成功回复后 retainedCompleters=60，响应共 6,000,170 字符；虚拟 31 秒后清零。字符数不是 heap 字节数或当前进程测量。

**修复 TODO**：

- [ ] 成功、错误、超时、断连/销毁路径统一及时删除 pending/default 状态并释放响应引用。
- [ ] 在本地变量保存 Completer，避免提前 remove 后 invoke 再取 map 产生竞态；覆盖同步回调/发送失败。
- [ ] 请求结束后取消不再需要的 cleanup Timer，确保迟到/重复回包不能重复完成或复活状态。

**验收 TODO**：

- [ ] 原 60 回复 probe 在完成后立即观测到零 pending；不依靠推进 31 秒才能通过。
- [ ] 覆盖成功/类型错误/remote error/超时/断连、同步失败与迟到重复回包，默认值与调用方契约保持正确。
- [ ] 大快照持续轮询后 pending 与 timer 数有界，停止后回到基线；按 V02 测量真实 heap/GC，不只断言 map 大小。

### F07：连接页 stop/start 期间丢失自动刷新

**状态**：OPEN。**证据**：真实 ConnectionManager 隔离复现。

**位置**：`lib/manager/connection_manager.dart:176–206,242–246`；入口 `lib/manager/clash_manager.dart:67`。

**问题/触发**：旧 snapshot 在途时 running=false→true，新 timer 因 _polling 被吞掉；旧 finally 因 generation 不匹配也不再排下一轮，导致一直 loading/旧列表。

**已有证据**：重启并推进虚拟 1 秒后 requestsAfterRestart=1，running=true、visible=true、loading=true，仍只有旧请求。

**修复 TODO**：

- [ ] 保留最新运行代的 pending refresh，旧请求退出时按当前状态安排一次新请求。
- [ ] 继续丢弃旧代结果，保持单请求在途；不能删掉 generation 防护使旧快照污染新状态。
- [ ] 核对手动刷新、可见性、间隔变化与 dispose/stop 的调度一致性。

**验收 TODO**：

- [ ] 原 stop/start probe 旧请求结束后自动发出新请求并继续刷新，loading 最终结束。
- [ ] 覆盖旧请求成功、失败、超时，多次启停及隐藏/显示交错；停用或 dispose 后无新请求。
- [ ] 验证旧快照不覆盖新代数据、并发请求数不超过设计值、手动刷新仍有效。

### F08：流量轮询 Timer 所有权竞态导致停止后复活

**状态**：OPEN。**证据**：真实 GlobalState 隔离复现；Android pause/resume 为实际入口之一。

**位置**：`lib/state.dart:171–208`；`lib/manager/app_state_manager.dart:142,182`；`lib/controller.dart:1662`。

**问题/触发**：已有 epoch 保护但没有 executor single-flight；旧 executor 在 stop→resume 后完成，无条件 timer=null，丢失新 Timer 引用。再次 stop 无法取消孤儿 Timer，回调也不校验创建时 epoch。

**已有证据**：lostTimerReference=true；停止后预期请求数=2，实际=3。

**修复 TODO**：

- [ ] executor single-flight 与 epoch/Timer 所有权配合，旧完成只能处理自己拥有的状态。
- [ ] Timer 回调执行前验证创建时 epoch；stop 同时失效在途与已排任务，避免复活。
- [ ] 保留失败隔离与后续恢复能力，不能靠永远停掉轮询掩盖竞态。

**验收 TODO**：

- [ ] 原 probe 停止后请求数保持 2，进一步推进多个周期仍不增长。
- [ ] 覆盖快慢请求、任务异常、连续 start、stop/resume 及 Android 生命周期交错；最多一个执行周期在途。
- [ ] 验证新的有效恢复正常取样，旧请求完成不能取消/清空当前代 Timer。

### F09：最小化与隐藏窗口仍保留不必要的数据采集

**状态**：OPEN。**平台**：重点 Windows/Desktop。**证据**：源码确认，未做真实 CPU profile。

**位置**：`lib/manager/window_manager.dart:98–102`；`lib/views/connection/connections.dart:135–137`；`lib/common/window.dart:95`；`lib/manager/app_state_manager.dart:141–155`；`core/hub.go:114,518`。

**问题/触发**：两条路径必须分别处理：① 最小化只 pause renderer，不改 window.visible，连接页仍可每 100–500ms 获取/解码全量 snapshot；② 隐藏到托盘虽停连接页 snapshot，但 desktop 未发送 setUiActive(false)，Core 仍约每 4 秒扫描活动连接并转发请求事件。

**修复 TODO**：

- [ ] 统一实际可见、最小化、应用生命周期、当前页面与数据订阅者的活跃信号。
- [ ] 非必要连接快照、解码、tracker 更新在后台暂停/合理降频；Core 的 UI 事件生成由有效消费者驱动。
- [ ] 显示/恢复时及时补最新数据；诊断记录等合法后台消费者单独计入，避免误停。
- [ ] 仅约束 UI 采集，保持代理/TUN 转发、已确认后台运行与手动停止语义。

**验收 TODO**：

- [ ] 分别验证连接页前台、其他页面、最小化、托盘隐藏、恢复显示，记录请求频率与 Core 事件数量。
- [ ] 按 V01 对比 CPU、分配率、IPC bytes、帧耗时；没有数据不承诺百分比收益。
- [ ] 后台代理流量不断、恢复不显示永久旧数据，正常诊断订阅不丢失约定信息。

### F10：测速并发限制形同分批等待，排队不受超时约束

**状态**：OPEN。**范围**：Dart 发起与 Go Core 队列。**证据**：源码 + 真实生产函数隔离验证。

**位置**：`lib/views/proxies/common.dart:62–102`；`lib/views/proxies/proxies.dart:39–40,55–57`；`lib/clash/interface.dart:396–415`；`lib/common/constant.dart:28`；`core/hub.go:698–720`。

**问题/触发**：先 map(async).toList 启动全部请求，再 batch(100) 只是分批等待；全部分组再并行扇出，相同节点/URL 跨组可重复，按钮无忙状态保护。Core 每项起 goroutine，Background semaphore 排队无总上限/取消，拿到 50 槽之一才开始超时；UI 6 秒超时不取消 Core 工作。

**已有证据**：持有全部槽位，提交 1,000 个 timeout=10ms 请求；100ms 后 1,000 个等待 goroutine、0 callback；释放槽后全部回调。使用不存在代理，没有 URLTest/网络访问。证实积压，不是释放后永久泄漏。

**修复 TODO**：

- [ ] 发起端使用未启动任务批次/固定 worker，形成跨分组的全局预算；按 `(节点, URL)` 去重。
- [ ] 处理重复点击与忙状态/取消，不重复追加相同批次。
- [ ] Core 限制执行并发和等待队列长度，在创建无界 goroutine 前施加资源限制。
- [ ] 总 deadline 覆盖排队和执行；UI 超时、取消、配置/会话更换可取消对应 Core 工作。
- [ ] 过期结果不得覆盖新批次状态；过载、取消与失败均有明确用户反馈。

**验收 TODO**：

- [ ] 原 1,000 请求场景改为验证数量有界且等待包含在总超时内；新保护性断言不能沿用“保留 1,000 个即 PASS”。
- [ ] 覆盖跨组重复、空节点、大订阅、连续点击、取消、超时、配置更换与释放槽位。
- [ ] 记录峰值 goroutine/队列/RPC 数和收敛时间，按 V03 验证合法批量测速仍完成且不存在饥饿。

## 5. P2：原生资源、日志与平台失败路径

### F11：Windows 普通系统代理错误路径泄漏且恒报成功

**状态**：OPEN。**平台**：Windows C++ proxy 插件。**证据**：源码确认；非当前机器动态复现。

**位置**：`plugins/proxy/windows/proxy_plugin.cpp:34,46,50,66,81–96,107,115,130–141,214–225`；Dart 调用/错误处理 `lib/manager/proxy_manager.dart:27–45`。

**子问题 A**：Start 的 fullAddr、bypassAddr、options 三块 new[] 在 RAS 枚举失败时提前 return 泄漏；Stop 的 options 同理，重复失败可累计小块 heap。

**子问题 B**：InternetSetOption 返回值被忽略，RAS 提前返回还跳过广播刷新；普通 StartProxy/StopProxy wrapper 无论结果都 Success(true)，界面无法区分全部/部分失败。PAC 分支已有错误传播，不能回退它。

**修复 TODO**：

- [ ] 用字符串自身存储、栈数组或 RAII 管理原生内存，覆盖每个早退/异常路径。
- [ ] 检查每个 Windows API 返回值，按 API 契约记录错误码/阶段，向 Dart 传播失败。
- [ ] 定义部分应用后失败的清理、必要通知与重试语义，不能让 UI 假成功或残留错误系统代理。
- [ ] 保持 PAC 行为与普通代理设置兼容；不能只改一个 Start/Stop 分支。

**验收 TODO**：

- [ ] 通过可控原生边界模拟第一次/重试 RAS 失败、普通连接及拨号连接设置失败、通知失败；重复循环无分配单调增长。
- [ ] Start/Stop 成功返回成功，失败传到 UI，部分失败可正确重试；检查实际系统设置与展示一致。
- [ ] 实际更改系统代理仅在获准隔离环境执行，不把小块 heap 问题等同于旧托盘 USER 泄漏。

### F12：日志文件数量、跨日与删除范围不完整

**状态**：OPEN。**范围**：Dart FileLogger。**证据**：源码确认；未生成大量日志动态验证。

**位置**：`lib/common/file_logger.dart:79–104,112–143,146–171`。

**子问题 A**：同日满 10MiB 后只关 sink，保留 _currentLogFilePath，选择新 index 时不执行 _rotateLogs；maxLogFiles=7 无法持续约束数量。

**子问题 B**：已打开 sink 未满时不检查日期，跨日继续写昨天日期的文件。

**子问题 C**：当前清理匹配所有 `.log`，没有限制 FileLogger 自身命名，修复滚动时必须避免删除独立 `connections_diagnostic.log` 或其他日志。

**修复 TODO**：

- [ ] 每次换文件/创建新文件后保持明确的数量或总量约束，包括同日滚动；避免清理时机导致多留一份。
- [ ] 写入/确保 sink 时检查日期，跨日切换正确命名文件。
- [ ] 清理只匹配自身文件名，排除当前打开文件、独立诊断日志与外来文件。
- [ ] 删除/关闭失败可诊断，保留有界内存队列与现有退避，避免磁盘异常热循环。

**验收 TODO**：

- [ ] 使用临时目录、小阈值或受控文件长度验证一天内超过 7 份滚动后上限仍成立。
- [ ] 用可控时间覆盖跨日未满/已满、重启继续写、日期切换；不依赖真实等待跨天。
- [ ] 放入独立/外来 `.log` 验证不删除，当前打开文件安全，权限/磁盘异常时无无限重试。
- [ ] 不误报现有 2,048 条、单条 16Ki 字符队列为无界内存泄漏。

### F13：Agent 认证前 socket/task 可无限保留

**状态**：OPEN。**范围**：localhost UI IPC。**证据**：源码确认。

**位置**：`services/agent/src/runtime.rs:1136–1143,1161–1165`；对比已有 deadline 的 Core accept 路径 2053 行以后。

**问题/触发**：每次 accept 立即 spawn，认证首行仅限制 4,096 bytes，没有总读取时限或待认证数量限制。本地进程无需 token，连接后不发完整行/不关闭即可长时间保留 socket、task、BufReader、token 与 Arc；重复连接资源无界。

**修复 TODO**：

- [ ] 认证首行设置总超时，逐字节慢发送不能无限重置时限。
- [ ] 在 spawn/分配前限制待认证连接并发，定义超过限额的拒绝/关闭行为。
- [ ] Agent 关闭时取消并收拢未认证 task；保留合法认证、loopback 限制和单 UI 会话替换。

**验收 TODO**：

- [ ] 空首行、半行、慢滴流、超长行、错误 token、大量连接、Agent 退出均在限额/时限内收敛。
- [ ] 合法客户端在容量允许时正常认证，过载后恢复可用；任务/句柄不随重复失败增长。
- [ ] 测试只创建隔离 Agent/临时监听，不能冲击运行中的客户端。

### F14：日志完整行读取阶段可发生无界内存分配

**状态**：OPEN。**范围**：Agent/Helper 读取 Core stdout、stderr。**证据**：源码确认，正常日志通常有换行。

**位置**：`services/agent/src/runtime.rs:1983–1989`；`services/helper/src/service/hub.rs:336–350`；可含配置字符串的 Core 日志示例 `core/hub.go:1024`。

**问题/触发**：read_line(&mut String)/BufRead.lines 先完整读取，再 format 与 logger 截断。异常超长或无换行输出在截断前已大分配；Agent clear 不缩小 capacity，可长期保留峰值。已有日志队列/文件上限不能限制这一步。

**修复 TODO**：

- [ ] 有界分块/行读取限制分配，达到阈值后保留有限前缀并继续丢弃至换行。
- [ ] 明确截断标记与 UTF-8 边界/错误处理，避免超长 capacity 永久保留或重复完整复制。
- [ ] 始终继续排空 stdout/stderr，不能直接停止读取导致 Core 写管道反向阻塞。
- [ ] Agent 与 Helper 两处一致处理，并保留原脱敏、队列及滚动保护。

**验收 TODO**：

- [ ] 超长有换行、连续无换行、分块 UTF-8、EOF、读取错误与正常后续行；buffer 上界明确且后续日志仍可读取。
- [ ] 用内存流/隔离子进程验证两条管道同时排空，不必让真实 Core 产生异常输出。
- [ ] 记录最大分配/缓冲量，确认异常结束后资源收敛。

### F15：Android TUN 停止超时保留 JNI 引用且缺少迟后回收

**状态**：OPEN。**平台**：仅 Android。**证据**：源码确认，无 Android 实机复现。

**位置**：`core/lib_android.go:30–105`，尤其 close 37–73、调用 permit 76–89。

**问题/触发**：Binder Protect/ResolveProcess 在途超过 3 秒，drain 超时为避免 use-after-free 故意不 releaseObject(callback)。新 handler 取代旧 handler 后，迟到调用只释放 permit，没有最终安全回收旧 global ref 的路径，可能保留服务对象引用图。

**修复 TODO**：

- [ ] handler generation + 引用计数/等价所有权协议管理 retired handler；停止后拒绝新调用。
- [ ] 最后一个在途调用结束后仅回收一次旧 JNI global ref，避免旧调用访问新 handler、重复释放或竞态置空。
- [ ] 对长期卡住的 Binder 调用提供 pending retired generations 诊断与明确恢复策略。
- [ ] 保持停止等待有界；不能直接在超时分支强制释放 callback，也不能恢复成无界等待。

**验收 TODO**：

- [ ] 覆盖及时完成、3 秒后迟返、长期不返、重复停止、快速重启与多代 handler；迟返最终回收，持续在途不发生 UAF。
- [ ] Android 模拟/实机验证 JNI 引用及服务对象收敛，检测重复释放和数据竞争。
- [ ] 不把此项写成 Windows 内存原因；没有 Android 证据前保持实机验收未完成。

## 6. 单列优化候选

### P01：对比 UI 进程 NORMAL 与 HIGH 优先级

**状态**：待测量，P3。**位置**：`windows/runner/main.cpp:16` 的 HIGH_PRIORITY_CLASS。

- [ ] 同机器、同包源码、同配置分别测 NORMAL/HIGH，固定前台、后台和 CPU 竞争场景。
- [ ] 记录 UI 帧耗时、Core 吞吐、桌面/任务栏交互延迟、CPU 与工作集，避免用单个瞬时值决定。
- [ ] 根据数据决定是否改优先级并记录取舍；没有收益证据时不以“优化”名义直接修改。
- [ ] 不宣称该设置已被证实导致开始菜单失灵，不保证修改优先级会降低 CPU 或内存。

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

**解释**：四个 Flutter FAIL 是缺陷复现，不能写成修复成功；Go PASS 仅表示观察探针证实描述的行为，不能替代修复后的保护性断言。

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

### 9.2 实施前的证据与回归 TODO

- [ ] 把上述一次性 probe 中有价值的保护性断言迁入正式测试，并移除聊天绝对路径依赖，保留可追溯原始输入与结果。
- [ ] 对观察性 Go probe 增加修复后用户契约断言；不能以旧“不安全行为出现即 PASS”作为修复门禁。
- [ ] 每项补 Red → Green 与所属模块相关回归。只有文档记录已完成，本清单没有 Green。
- [ ] 对修复范围运行适用的 Flutter/Go/Agent/Helper 测试、静态检查和构建，记录命令、exit、通过/失败/跳过数与环境。
- [ ] 采集适用的新增/修改代码覆盖率，说明分支缺口；本次审查未采集覆盖率。
- [ ] 按 V01–V05 补长时 profile、原生失败路径与 Android 实机证据；本次均 NOT RUN。
- [ ] 每批独立复核安全、竞态、退出/取消与失败路径，发现问题修复后重跑相关验证。

## 10. 排除项与防误报清单

以下作为审查边界保存，不删除也不转为已证实缺陷：

- 托盘旧 RemoveMenu/HMENU 问题已有修复，见 H01；新的普通代理 RAS 小块 heap 泄漏不能与其混为一谈。
- 进程图标缓存已有 BoundedCache 上限，HICON/HBITMAP/HDC 释放路径已检查；图片缓存已有数量/内存上限；Agent replay journal 有 128 条上限。
- Dart 日志内存队列已有 2,048 条/单条 16Ki 字符保护；Rust 日志队列 256 条、单条 16Ki 字符，文件 8MiB 加三个轮转文件。F12/F14 针对其他缺口。
- QuickJS runtime 已通过 try/finally dispose，不能重复报告旧的未释放问题。
- ConnectionFlag 的缓存候选没有找到实际实例化调用点，本轮不认定为运行泄漏；将来接入时应重新评估。
- MemoryInfo dispose 后旧 await 可能多排一个 timer，下一轮 mounted 门禁拦住；现有证据不支持无限循环/永久泄漏。
- 未发现可新增认定为正常高频 USER/GDI 泄漏的另一处证据，但不宣称全仓无其他资源问题。
- RPC 的约 30 秒滞留、测速的无界排队、异常日志峰值、条件性 JNI/heap 泄漏分别表述，不能统称已经发生的永久内存泄漏。
- 没有长期 profile 或真实系统恢复证据前，不承诺提升比例、不断言任务栏/开始菜单已恢复、不把所有缺陷都归因于当前电脑故障。

## 11. 执行顺序与关闭标准

建议顺序：F01–F05 → F06–F10 → F11–F15；P01 依赖测量，V01–V05 随对应修复批次执行；H01/S01 保持独立状态。

每项完成时在对应章节追加以下记录，未满足的验收框保持未勾选：

- 修复提交/分支与涉及文件。
- 原缺陷复现、修复后目标测试、相关回归的命令、结果与证据位置。
- 真实平台/长时验证的范围；NOT RUN 项及其原因。
- 独立复核结论、残余风险与后续行动。
- 若交付包：源码/组件来源与 hash、安装/运行/回滚证据；源码已修、包已构建、实机已验收分别标记。

关闭条件：修复 TODO 与适用验收均有证据；不能以文档已写、单个探针 PASS、一次构建成功或短时资源下降关闭产品问题。

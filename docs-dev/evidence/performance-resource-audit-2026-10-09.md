> 历史证据快照：原审查日期 2026-10-09，源码基线 c5c5ae4400d225cf2abefccb92184d29c1b81bcd。以下结果保持原文，记录的是审查时点；TODO 进展以 docs-dev/performance-resource-todo-2026-10-09.md 为准。

# FlClashX 性能、资源生命周期与缺陷审查

日期：2026-10-09，Asia/Singapore。模式：只读审查，使用隔离探针核实部分行为。

## 结论

还有明确的性能提升空间，也存在新的资源泄漏和可靠性问题。最值得先做的是：修复控制接口认证与 ZIP 写入边界，保证 IPC 和进程停止能够收敛，然后消除 RPC 响应滞留、后台无效刷新和测速任务积压。

本报告列出 15 个可行动问题。它们的性质不同：有条件性堆/JNI 引用泄漏、有界内存滞留、无上限排队、磁盘增长，也有功能与安全缺陷。没有把它们全部称为“内存泄漏”，也没有将它们直接归因于此前的 Windows 任务栏故障。

本轮 4 个 Flutter 保护性断言均因目标缺陷失败；另有 2 个 Go 观察性测试和 1 个纯解析探针确认相关机制。没有修改产品源码、安装新包、重启应用或服务、切换代理/TUN，也没有进行真实网络故障注入。

## 基线与证据等级

- 仓库：`E:\CodeWorkstation\FlClashX`。
- 分支：`development`；HEAD：`c5c5ae4400d225cf2abefccb92184d29c1b81bcd`。
- 范围：Dart/Flutter 生命周期与刷新、Windows C++ 插件、Rust Agent/Helper、Go Core；补充 Android JNI 失败路径。
- Flutter 3.47.4、Dart 3.13.3；Go 1.25.13 windows/amd64。
- Go 使用项目已有 `.generated/go.mod` 与 Mihomo overlay。审查测试只通过仓库外 overlay 注入，没有修改模块缓存或产品源码。
- **隔离复现**：调用真实类/函数，替换网络等外部边界或控制调度；不等于运行中的客户端已发生同样故障。
- **源码确认**：分配、释放、调用与失败路径已核对；没有在本机进行动态故障注入。
- **优化候选**：需要基准测试后决定，不能承诺收益比例。

## 优先级总览

P1 表示建议下一批优先修复的高影响问题；P2 表示应纳入随后稳定性/性能修复的问题。优先级不表示当前机器必然正在触发。

| 编号 | 优先级 | 问题 | 证据 |
|---|---|---|---|
| F01 | P1 | 重建外部控制接口时丢弃 secret | 源码确认 + 实际依赖 router 内存验证 |
| F02 | P1 | 面板 ZIP 可写出解压目录 | 真实函数隔离复现 |
| F03 | P1 | 慢 UI 的 IPC 阻塞可传播至停止/重启 | Go/Rust 交叉源码确认 |
| F04 | P1 | Helper 忽略 Core 停止失败后退出 | 源码确认 |
| F05 | P1 | 配置报错前先用默认配置覆盖运行态 | 源码确认 + 语义校验可达性探针 |
| F06 | P2 | 已完成 RPC 响应继续保留约 30 秒 | 真实类隔离复现 |
| F07 | P2 | 在途连接请求遇到 stop/start 后永久停更 | 真实类隔离复现 |
| F08 | P2 | 流量轮询旧请求丢失新 Timer 引用，停止后复活 | 真实类隔离复现 |
| F09 | P2 | 最小化/隐藏时仍做不必要的数据采集 | 源码确认；未测量 CPU 收益 |
| F10 | P2 | 测速分批没有限制启动量，排队不计超时 | 源码确认 + 真实 Core 函数隔离验证 |
| F11 | P2 | Windows 代理插件错误路径泄漏，并恒报成功 | 源码确认 |
| F12 | P2 | 同日日志滚动绕过文件数量上限 | 源码确认 |
| F13 | P2 | Agent 未认证连接无超时及数量限制 | 源码确认 |
| F14 | P2 | Core 日志读取阶段没有行长度上限 | 源码确认 |
| F15 | P2 | Android TUN 超时后 JNI 全局引用没有迟后回收 | 源码确认；Android 特定 |

## 高优先级问题

### F01：外部控制接口重建丢弃认证密钥

**位置**：[common.go:366](E:/CodeWorkstation/FlClashX/core/common.go:366)、[common.go:436](E:/CodeWorkstation/FlClashX/core/common.go:436)、[state.dart:521](E:/CodeWorkstation/FlClashX/lib/state.dart:521)。

两处 `route.ReCreateServer` 只传 `Addr`，没有传 `currentConfig.Controller.Secret`，也遗漏 TLS/CORS 等控制器字段。固定 Mihomo 依赖在重建时关闭原 HTTP server，使用本次传入的配置创建新 router；`Secret` 为空时不安装认证中间件，没有自动沿用旧密钥。

实际依赖位置：`E:\CodeWorkstation\FlClashX\core\.generated\mihomo-v1.19.32-source-adb2170dcce92d63d9da0102eb6669bf8b719c6d9ed33b985c3d0a3aa9c1dd7a\hub\route\server.go`，相关行为位于 60、92、119、162、181 行。

**验证**：用真实 router 处理内存 HTTP 请求。仅传地址时，匿名 `/version` 返回 200；加入合成 secret 后返回 401。未启动监听，也未探测当前 Core 的实际外控接口。

**触发与影响**：用户启用外控或订阅携带外控地址/secret 时，重建可能失去期望的认证。UI 默认关闭外控，开启的默认地址是 `127.0.0.1:9090`；订阅地址优先，若配置成 `:9090` 或 `0.0.0.0:9090`，风险可扩大到能访问该端口的设备。不能据此声称默认公网暴露。

**建议**：统一构造完整 controller config。回归覆盖匿名 401、正确凭据成功、配置重载与 UI 开关后密钥不丢失，以及对应 TLS/CORS 行为。

### F02：面板 ZIP 解压缺少路径边界检查

**位置**：[zashboard.dart:29](E:/CodeWorkstation/FlClashX/lib/common/zashboard.dart:29)，直接写入位于 [zashboard.dart:60](E:/CodeWorkstation/FlClashX/lib/common/zashboard.dart:60)。

下载 ZIP 后，代码移除 `dist/` 等前缀，直接执行 `File(p.join(dir, name))`。没有拒绝路径回退、绝对路径或检查归一化后的目标是否仍在解压目录中。

**验证**：真实 `ensureZashboardUi` 接收合成 ZIP，里面有正常 `dist/index.html` 和 `dist/../escaped-audit-marker.txt`。函数返回 true，标记文件实际写到了 panel 目录之外，保护性断言失败。整个测试只写入聊天 `work` 下的独立测试目录，没有触碰用户文件或访问真实下载源。

**触发与影响**：需要下载到含异常或恶意条目的第三方面板包；没有证据表明当前上游包含恶意内容。若触发，可在当前用户权限范围内写出预期解压目录。

**建议**：验证每个归一化路径的目录包含关系，拒绝越界与危险条目；在独立临时目录解压验证后切换。此流程也应添加下载、解压总大小、条目数量、超时和单次下载并发限制。大小限制缺失为源码风险，本轮没有做 ZIP bomb 压测。

### F03：UI 不消费数据时可能堵住 Core 控制链

**位置**：[runtime.rs:1191](E:/CodeWorkstation/FlClashX/services/agent/src/runtime.rs:1191)、[runtime.rs:1651](E:/CodeWorkstation/FlClashX/services/agent/src/runtime.rs:1651)、[runtime.rs:2348](E:/CodeWorkstation/FlClashX/services/agent/src/runtime.rs:2348)、[server.go:34](E:/CodeWorkstation/FlClashX/core/server.go:34)、[hub.go:545](E:/CodeWorkstation/FlClashX/core/hub.go:545)。

传播路径：

1. UI 保持 socket 连接但停止读取，Agent writer 无写 deadline。
2. 写缓冲和 256 条 UI 输出队列填满后，普通响应的 `output.send(...).await` 阻塞。
3. Core supervisor 已进入 `select!` 分支体，在该 await 内停止继续读取 Core；停止/重启命令分支不能抢占它。
4. Core 持 `connMu` 执行无 deadline 的 `conn.Write`；部分请求事件同时持 `requestMu`。
5. 停止监听路径持 `runLock` 等待 `requestMu`，可把停止及重配置一起拖住。新请求还会继续创建 goroutine，可能进一步积压。

**取消机制复核**：现有 session cancellation 主要包住 read；writer abort 要等 session 主循环及后续流程返回，不能保证取消一个已经堵在发送中的 handler。

**边界**：只有 stream 消息时，`try_send` 会丢样本，不会单独触发这条阻塞链；必须有需要可靠入队的普通响应/生命周期消息。UI 恢复读取或连接断开通常能解堵，源码没有保证自动发生这些条件。本轮没有动态冻结 UI，不把它认定为当前故障原因。

**建议**：为写入和可靠响应入队设置有限超时及会话故障处理；让 supervisor 的停止/重启独立于 UI 输出。Core 避免持业务锁等待网络写出，并通过有界 writer/写 deadline 保证关闭与取消能执行。

### F04：Helper 停服务时忽略 Core 停止失败

**位置**：[windows.rs:62](E:/CodeWorkstation/FlClashX/services/helper/src/service/windows.rs:62)、[hub.rs:320](E:/CodeWorkstation/FlClashX/services/helper/src/service/hub.rs:320)、[hub.rs:288](E:/CodeWorkstation/FlClashX/services/helper/src/service/hub.rs:288)。

SCM Stop 调用 `stop_process` 后直接 `process::exit(0)`，丢弃 kill 失败或 3 秒内未确认退出的返回值。Core 通过普通 `Command` 启动，没有 Job Object 保证父进程退出时终止子进程。

**影响**：在失败条件下可能遗留 SYSTEM Core、端口或 TUN，而 Helper 的进程内所有权信息已经丢失，干扰后续停止、更新与修复。未在本机制造停止失败。

**建议**：SCM 回调投递停止请求，由工作线程报告 StopPending 并等待确认；失败保留进程所有权并如实报告，成功后再退出。另评估 Job Object 与既定后台存活语义的兼容性。

### F05：配置加载报错前已改变运行配置

**位置**：[common.go:413](E:/CodeWorkstation/FlClashX/core/common.go:413)、[common.go:425](E:/CodeWorkstation/FlClashX/core/common.go:425)、[hub.go:1099](E:/CodeWorkstation/FlClashX/core/hub.go:1099)、[hub.go:597](E:/CodeWorkstation/FlClashX/core/hub.go:597)。

`ParseRawConfig` 失败后会先解析并应用默认配置，然后才返回原错误；setup 参数反序列化失败时也会应用默认配置。因此界面报告失败时，先前运行的规则、监听、TUN 状态可能已经被替换。

**可达性验证**：保存配置的校验使用 `UnmarshalRawConfig`，只覆盖原始结构。合成规则 `MATCH,__audit_missing_group__` 通过该步骤，却被真实 `ParseRawConfig` 拒绝。脚本修改后的最终配置也缺少统一的最终语义校验。探针没有调用 ApplyConfig，运行态覆盖结论来自实际失败分支源码。

**建议**：先解析局部 candidate，完整校验成功后才替换全局状态和应用；失败保留最后一份有效运行配置，并返回准确错误。初始化无旧配置的情形另行处理。

## 性能与生命周期

### F06：成功 RPC 响应约 30 秒后才释放管理引用

**位置**：[interface.dart:105](E:/CodeWorkstation/FlClashX/lib/clash/interface.dart:105)、[interface.dart:181](E:/CodeWorkstation/FlClashX/lib/clash/interface.dart:181)、[future.dart:13](E:/CodeWorkstation/FlClashX/lib/common/future.dart:13)。

完成 Completer 后没有从 map 移除；清理仅由 `timeout + commonDuration` 的独立 Timer 执行。Future 继续持有已经交付给调用方的 response。

**验证**：60 个请求全部成功后，map 仍保留 60 个 Completer，响应合计 6,000,170 字符；推进虚拟时间 31 秒后才清零。这是有界滞留，不是永久无界泄漏，也不是对进程 heap 字节数的实测。

**影响**：连接页默认 500ms 刷新、可调至 100ms，可能同时滞留几十至数百份大 JSON 快照，增加内存和 GC 压力。

**建议**：成功、错误、超时统一立即清理 pending/default bookkeeping；保留局部 Completer 引用，以 finally/完成回调管理生命周期。覆盖断连、重复/迟到回包和同步发送失败，避免“提前 remove”引入新的取 map 竞态。

### F07：连接页启停竞态会丢失后续轮询

**位置**：[connection_manager.dart:179](E:/CodeWorkstation/FlClashX/lib/manager/connection_manager.dart:179)、[connection_manager.dart:206](E:/CodeWorkstation/FlClashX/lib/manager/connection_manager.dart:206)、[connection_manager.dart:244](E:/CodeWorkstation/FlClashX/lib/manager/connection_manager.dart:244)。

旧请求在途时执行 running=false→true，新定时任务被 `_polling` 门禁吞掉；旧请求结束后因 generation 不同，也不安排下一轮。

**验证**：真实 ConnectionManager 重启后推进虚拟时间 1 秒，仍只有 1 次旧请求，状态为 `running=true visible=true loading=true`。自动刷新没有恢复。

**建议**：记住当前代的待刷新请求；旧请求退出后按最新状态补发，继续丢弃旧代结果。不能仅移除 generation 检查。

### F08：流量轮询停止后可被遗失引用的 Timer 复活

**位置**：[state.dart:173](E:/CodeWorkstation/FlClashX/lib/state.dart:173)、[state.dart:184](E:/CodeWorkstation/FlClashX/lib/state.dart:184)、[state.dart:199](E:/CodeWorkstation/FlClashX/lib/state.dart:199)。

代码已有 epoch，但 executor 结束仍无条件 `timer=null`，且没有限制在途 executor 只能有一个。旧请求在 stop→resume 后完成，可以清掉新一代 Timer 的引用；下一次 stop 因而无法取消该 Timer，Timer 回调也没有验证创建时 epoch。

**验证**：真实 GlobalState 调度中观测到 `lostTimerReference=true`；停止后本应保持 2 次请求，推进时间后变为 3 次。Android pause/resume 是真实调用入口之一。

**建议**：single-flight 与代际/Timer 所有权共同约束，旧 executor 不修改新 Timer，回调执行前再次校验代际。

### F09：Windows 最小化/隐藏时仍有不必要取样

**位置**：[window_manager.dart:98](E:/CodeWorkstation/FlClashX/lib/manager/window_manager.dart:98)、[connections.dart:135](E:/CodeWorkstation/FlClashX/lib/views/connection/connections.dart:135)、[app_state_manager.dart:150](E:/CodeWorkstation/FlClashX/lib/manager/app_state_manager.dart:150)、[hub.go:518](E:/CodeWorkstation/FlClashX/core/hub.go:518)。

最小化只暂停 renderer，没有改变 `window.visible`；连接页轮询依赖当前页与 visible，因此可能继续每 100–500ms 拉取全量快照、传输 JSON、isolate 解码和更新 tracker。隐藏到托盘会停止连接页快照，但 desktop hidden 没有像 Android 一样发送 `setUiActive(false)`，Core 仍维持约每 4 秒一次的活动连接扫描及请求事件转发。

**建议**：统一实际可见/最小化/应用生命周期/当前页信号，按需驱动 UI 采集。必须保持代理和 TUN 数据转发运行；诊断订阅等确实需要的后台消费者应单独计入。没有实际 CPU profile，不能给出节电或降 CPU 百分比。

### F10：测速只分批等待，排队没有总上限和总时限

**位置**：[common.dart:62](E:/CodeWorkstation/FlClashX/lib/views/proxies/common.dart:62)、[proxies.dart:39](E:/CodeWorkstation/FlClashX/lib/views/proxies/proxies.dart:39)、[hub.go:703](E:/CodeWorkstation/FlClashX/core/hub.go:703)。

Dart 先创建全部 async Future，再 batch(100)，所以没有限制启动量；多个分组还会并行扇出。Core 为每项创建 goroutine，等待 50 槽 semaphore 使用 Background context，拿到槽位后才计算测试 timeout。UI 超时不会取消已排队的 Core 任务。

**验证**：真实 `handleAsyncTestDelay` 中先持有 50 个槽位，再提交 1,000 个 timeout=10ms 的合成请求。100ms 后仍有 1,000 个等待 goroutine、0 回调；释放槽后全部完成。使用不存在的代理，未发起 URLTest 或网络访问。

**影响**：大订阅和重复点击造成内存、goroutine、IPC 及过期结果积压。释放后可回收，因此本轮证明的是积压与排队超时缺口，不是永久泄漏。

**建议**：固定 worker 数或按未启动任务分批，全局限制队列长度；按节点/URL 去重；端到端 deadline 覆盖排队与执行，并取消旧配置/过期任务。

## 原生资源、日志与平台问题

### F11：Windows 系统代理插件失败路径泄漏，并错误报告成功

**位置**：[proxy_plugin.cpp:34](E:/CodeWorkstation/FlClashX/plugins/proxy/windows/proxy_plugin.cpp:34)、[proxy_plugin.cpp:81](E:/CodeWorkstation/FlClashX/plugins/proxy/windows/proxy_plugin.cpp:81)、[proxy_plugin.cpp:130](E:/CodeWorkstation/FlClashX/plugins/proxy/windows/proxy_plugin.cpp:130)、[proxy_plugin.cpp:214](E:/CodeWorkstation/FlClashX/plugins/proxy/windows/proxy_plugin.cpp:214)。

Start 分配地址、bypass 字符串和 options 三块内存；RAS 枚举失败提前 return，跳过 delete[]。Stop 同样会漏 options。提前返回还跳过设置刷新通知。

各处 `InternetSetOption` 返回值被忽略，MethodChannel 的 StartProxy/StopProxy 始终 `Success(true)`，Dart 无法得知 Windows 设置失败或只完成了一部分。

**性质**：条件性的小块 heap 泄漏，加上用户可见状态与系统实际状态不一致。没有证据说明它正触发本机故障，不能等同于此前托盘 USER 对象泄漏。

**建议**：栈上数组/RAII 替代裸 new[]；传播失败阶段和 Win32 错误，保证清理与必要通知，并验证部分失败后的重试行为。

### F12：日志同日滚动绕过文件数限制

**位置**：[file_logger.dart:112](E:/CodeWorkstation/FlClashX/lib/common/file_logger.dart:112)、[file_logger.dart:146](E:/CodeWorkstation/FlClashX/lib/common/file_logger.dart:146)、[file_logger.dart:155](E:/CodeWorkstation/FlClashX/lib/common/file_logger.dart:155)。

`_rotateLogs()` 只在日期变化或路径为空时调用；同一天满 10MiB 后关闭 sink，但保留旧路径，再选下一个 index，跳过清理。`maxLogFiles=7` 不能形成持续的文件数上限。已有 sink 未满时也不检查日期，跨日仍会写旧日期文件。

**影响**：高日志量可持续占用磁盘；这是磁盘保留策略问题。内存写队列已有 2,048 条与单条 16Ki 字符上限，不将其误报为无界队列。

**建议**：每次切换文件都进行限定范围的清理，并检查日期；只匹配本 logger 命名的文件，排除当前文件与独立诊断日志。当前清理匹配所有 `.log`，修复时也应收窄所有权。未制造大量日志验证。

### F13：Agent 未认证连接可无限等待

**位置**：[runtime.rs:1136](E:/CodeWorkstation/FlClashX/services/agent/src/runtime.rs:1136)、[runtime.rs:1161](E:/CodeWorkstation/FlClashX/services/agent/src/runtime.rs:1161)。

每个 localhost accept 立即 spawn；第一行认证虽然限制 4,096 bytes，却没有完成时限或待认证连接数量上限。本地进程连接后不发完整首行也不关闭，便可保留 socket、task、BufReader 与共享引用；重复连接可持续增加占用。

**性质**：认证前资源耗尽缺口，无需知道 token；不是证实正常客户端已发生泄漏。

**建议**：短认证总超时、待认证连接 semaphore、关闭时取消并收拢未认证任务。保持合法单 UI 会话替换语义。

### F14：日志截断发生在无界行读取之后

**位置**：[runtime.rs:1983](E:/CodeWorkstation/FlClashX/services/agent/src/runtime.rs:1983)、[hub.rs:340](E:/CodeWorkstation/FlClashX/services/helper/src/service/hub.rs:340)。

Agent 的 `read_line(&mut String)` 与 Helper 的 `BufRead::lines()` 先完整读取一行，再交给 logger 截断。异常超长或一直没有换行的输出会先造成大分配；Agent 的 `String.clear()` 还会保留已经增长的 capacity。

**性质**：输入缓冲缺少上限的健壮性问题。正常日志一般有换行，未在当前实例复现。Rust 日志队列本身已有 256 条、单条 16Ki 字符和文件 8MiB × 4 的限制。

**建议**：有界分块读取；超过长度后保留前 N 字节并丢弃到换行，继续排空管道。不能简单停止读取，否则可能反过来堵住 Core stdout/stderr。

### F15：Android 停止超时后 JNI 全局引用没有迟后回收

**位置**：[lib_android.go:37](E:/CodeWorkstation/FlClashX/core/lib_android.go:37)、[lib_android.go:64](E:/CodeWorkstation/FlClashX/core/lib_android.go:64)。

Protect/ResolveProcess 的 Binder 调用超过 3 秒时，drain 超时路径故意不 `releaseObject(callback)`，防止在途调用 use-after-free。新 handler 替换旧 handler 后，迟到调用只释放 permit，没有最后一个调用完成后回收旧 JNI global ref 的机制，可能继续保留旧对象引用图。

**性质**：明确的条件性引用泄漏，但这是为避免更严重内存安全问题而保留的现有折中；仅适用于 Android，不能解释 Windows 进程内存。本轮未运行 Android 测试。

**建议**：用 handler 代际和引用计数管理 retired handler，停止后拒绝新调用，最后一个在途调用完成时安全回收；记录长期未回收代际。不能直接在超时分支强制释放 callback。

## 推荐实施顺序与性能验收

1. **安全与控制可靠性**：F01–F05。保护 secret、文件写入边界、最后有效配置，以及停止/恢复能力。
2. **日常内存与响应**：F06–F10。先减少无效工作与滞留，再做进一步算法优化。
3. **错误路径与长期运行**：F11–F15。补资源所有权、输入/磁盘上限和失败回收。

另一项优化候选是 [main.cpp:16](E:/CodeWorkstation/FlClashX/windows/runner/main.cpp:16) 的 `HIGH_PRIORITY_CLASS`。建议对比 NORMAL 与 HIGH 的 UI 帧耗时、Core 吞吐、桌面交互延迟；没有数据证明高优先级是任务栏失灵原因，也不能保证降低优先级就降低内存/CPU。

后续性能验收应固定同一包、同一机器和数据规模，分别记录 UI、Agent、Core、Helper，避免只看一个工作集数字：

| 场景 | 主要指标 | 修复后需证明 |
|---|---|---|
| 空闲、连接页前台、最小化、托盘，各保持稳定窗口 | CPU、分配率、IPC 次数/字节、快照频率 | 最小化/隐藏后不继续非必要高频采样 |
| 小/中/大连接快照，500ms 与 100ms 刷新 | Dart heap、完成 RPC 保留数、GC、帧耗时 | 已完成响应及时释放，停止请求后回到稳定水平 |
| 大订阅批量测速、重复触发、取消/超时 | 队列长度、goroutine、回调耗时 | 队列与执行并发均有上限，过期任务停止 |
| 多次启停、断连、重连及窗口切换 | USER/GDI/句柄/线程、子进程、Timer | 资源不随循环单调增长，刷新与停止可恢复 |
| 慢消费者、Core 停止失败、Android Binder 迟返 | 退出时限、孤儿进程、retired refs | 在隔离环境验证有界失败与回收 |

最后一行涉及故障注入，应在可恢复测试环境执行。本轮未运行这些长时或系统级验收，因此不提供性能提升百分比，不声称已经找完所有泄漏。

## 验证记录

### 矩阵与结果

| 验证 | 涉及项 | 结果 | 实际观察 |
|---|---|---|---|
| 成功 RPC 立即释放 pending 状态 | F06 | FAIL：目标缺陷复现 | 60 条完成后仍保留 60 条；31 秒后清空 |
| 在途请求期间 stop/start 后继续刷新 | F07 | FAIL：目标缺陷复现 | 仍只有 1 次旧请求，loading 保持 true |
| stop 后不被旧请求恢复取样 | F08 | FAIL：目标缺陷复现 | 预期请求数 2，实际 3 |
| ZIP 条目不得越出解压目录 | F02 | FAIL：目标缺陷复现 | 返回 true，同时目录外出现标记文件 |
| raw 与 semantic parser 比较 | F05 | PASS：观察性探针 | 原始结构通过，语义因不存在目标组被拒绝 |
| Core 排队是否超出声明 timeout | F10 | PASS：观察性测试 | 100ms 后仍等待 1,000 个 goroutine |
| 实际 router 有/无 secret 的认证行为 | F01 | PASS：观察性测试 | 匿名请求分别返回 200/401，无监听 |
| 原生失败路径、IPC 取消反例交叉复核 | F03/F04/F11–F15 | 源码确认 | 未进行运行端故障注入 |

观察性探针 PASS 表示证实了描述的行为，**不表示产品已经修复**。

### 实际执行命令

Flutter 工作目录：`E:\CodeWorkstation\FlClashX`。

```powershell
& 'E:\flutter\bin\flutter.bat' test --no-pub 'C:\Users\冯飏\Documents\Codex\2026-10-08\new-chat\work\performance-audit\dart_lifecycle_probe_test.dart' 'C:\Users\冯飏\Documents\Codex\2026-10-08\new-chat\work\performance-audit\zashboard_archive_probe_test.dart' --reporter expanded
```

最终合并重跑：**0 PASS / 4 FAIL / 0 SKIP，exit 1，总耗时 6.665 秒**。失败均为目标保护性断言。输出保存在 `C:\Users\冯飏\Documents\Codex\2026-10-08\new-chat\work\performance-audit\flutter-audit-result.txt`。

Go 工作目录：`E:\CodeWorkstation\FlClashX\core`；仅在测试进程中设置：

```powershell
$env:GOPROXY='off'
$env:GOSUMDB='off'
$env:GOTOOLCHAIN='local'
$env:CGO_ENABLED='0'

go run '-modfile=.generated/go.mod' '-overlay=.generated/mihomo-overlay.json' 'C:\Users\冯飏\Documents\Codex\2026-10-08\new-chat\work\core-audit-probe\main.go'

go test '-modfile=.generated/go.mod' '-overlay=C:\Users\冯飏\Documents\Codex\2026-10-08\new-chat\work\core-audit-probe\audit-overlay.json' -run '^TestAuditQueuedDelayIgnoresDeclaredTimeout$' -count=1 -timeout=10s -v .

go test '-modfile=.generated/go.mod' '-overlay=C:\Users\冯飏\Documents\Codex\2026-10-08\new-chat\work\core-audit-probe\audit-overlay.json' -run '^TestAuditControllerSecretRequired$' -count=1 -timeout=10s -v github.com/metacubex/mihomo/hub/route
```

- Parser：1 个合成场景确认，exit 0，4.338 秒；不是 `go test` 用例统计。
- 排队：1 PASS / 0 FAIL / 0 SKIP，exit 0，总耗时 5.896 秒，用例 0.11 秒。
- Router：1 PASS / 0 FAIL / 0 SKIP，exit 0，总耗时 5.231 秒，用例 0.00 秒。
- 命令与输出记录：`C:\Users\冯飏\Documents\Codex\2026-10-08\new-chat\work\core-audit-probe\results.md`。

### 首次搭建错误、覆盖率与未运行项

- Flutter 首次竞态 probe 的 Timer.zero 推进不足，修正为 pump(1ms) 后重跑；最终四项结果来自修正后的测试。
- Parser 初次 harness 缺少提供 `temporaryUpdateGeneral` linkname 的 executor import，exit 1；在 work 中修正后 exit 0。
- Router 初次 harness 使用标准库 httptest，与 Mihomo 自有 HTTP 类型不匹配，exit 1；改为真实依赖对应的测试类型后 exit 0。以上都没有修改产品代码或弱化保护性断言。
- Red → Green：Red 证据已获得；**Green NOT RUN，本轮仅分析，未实施修复**。
- 覆盖率：本轮未采集行/分支覆盖率；不据探针推断全仓覆盖。
- 完整 Flutter/Go/Rust 回归、lint、发布构建：NOT RUN。此次没有生产代码变更，所运行的是目标机制的隔离验证。
- 当前运行进程的长时 heap/profile、Windows 原生故障注入、Android JNI 实机验收：NOT RUN；对应结论已分别标为源码确认或优化候选。

## 排除项与仓库状态

- 此前修复的托盘菜单 USER 对象泄漏不重复列为新缺陷。
- 已有上限的图标缓存、图片缓存、Agent replay journal、日志队列不报告为无界缓存。
- QuickJS runtime 已有 try/finally 释放；没有再次报告旧的释放问题。
- `ConnectionFlag` 的候选缓存问题没有找到实际实例化调用点，本轮不计入运行缺陷。
- 未发现足以新增认定为正常高频 USER/GDI 泄漏的另一处证据；这不等于穷尽所有路径。

最终复核：tracked/staged diff 均为空；原有 5 个未跟踪项保留（`coverage/` 及四项既存测试材料/目录）。无本轮产品代码提交、推送或发布。报告与隔离探针位于聊天目录；本轮确认的问题仍待修复。

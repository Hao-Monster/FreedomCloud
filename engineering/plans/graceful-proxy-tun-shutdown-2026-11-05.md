# FlClashX 代理与虚拟网卡优雅关闭架构方案（2026-11-05）

## 1. 背景与根因清单

点击仪表盘绿色运行按钮（`StartButton`）或连接按钮关闭代理（`updateStatus(false)`），以及托盘退出应用（`handleExit()`）时，现有链路存在以下 6 处结构性缺陷：

| 编号 | 模块与源码位置 | 根因缺陷 | 用户侧症状 |
| --- | --- | --- | --- |
| `GS-01` | `core/common.go:stopListeners`、`core/hub.go:handleStopListener` | 停止监听器时未先清空自定义 `inboundListeners` 与 `tunnels`，未在拆卸 `Wintun` 前主动关闭 `statistic.DefaultManager` 活跃连接与上游 DNS 连接，未停止 `HealthCheckForwarder`，且连续调用 `ReCreateTun(LC.Tun{})` 与 `Cleanup()` 双重关停 TUN | 长连接（HTTP/2、QUIC、WebSocket、微信/Telegram）僵死超时，`Wintun` 关闭被底层数据包读写协程拖慢甚至触发 `closeFailed`，停止后后台仍周期性唤醒节点拨号测速 |
| `GS-02` | `lib/controller.dart:_updateStatus(false)`、`lib/manager/proxy_manager.dart` | 先执行 `globalState.handleStop()` 关闭本地 `MixedPort`（如 `7890`），最后置空 `runTimeProvider` 才异步触发 `ProxyManager` 调用 WinInet `stopProxy()` | 停止瞬间系统代理仍指向已关闭的 `127.0.0.1:7890`，浏览器与系统请求出现 `ERR_PROXY_CONNECTION_FAILED` 断网黑洞窗口；状态栏图标更在停机前提前置灰 |
| `GS-03` | `lib/common/windows.dart`、`lib/controller.dart` | TUN（`enhanced-mode: fake-ip`，`198.18.0.0/16`）关闭后未刷新 Windows 系统 DNS 缓存 | 关闭虚拟网卡后数分钟内，客户端仍将域名解析到失效的 `198.18.x.x` Fake-IP，导致本地直连网络瘫痪 |
| `GS-04` | `lib/controller.dart:_handleExit` | 退出时直接调用 `clashCore.shutdown()`（Windows Agent 模式下直连 Helper `/stop` 执行 `TerminateProcess` 强杀 `FlClashCore.exe`），跳过 `stopListener` 优雅排空与 DNS 缓存清理 | 退出软件瞬间活跃 TCP 连接无 `FIN`/`RST` 通知、Fake-IP 池未落盘、系统残留 Fake-IP DNS 缓存 |
| `GS-05` | `lib/common/tun_runtime.dart`、`lib/controller.dart:updateStatus` | `updateStatus(false)` 先调用 `cancelPendingIntent()` 将 `operation` 置为 `idle`，随后 `invalidate()` 清空 `_status`，且对 `closeFailed` 无免 UAC 自愈回收 | 关闭期间虚拟网卡卡片闪现“状态未知”及误导性的 `×` 按钮；若驱动句柄偶发 `closeFailed`，残留网卡既未自动重启 Core 回收也未锁定失败态 |
| `GS-06` | `start_button.dart`、`hero_connect.dart`、`quick_options.dart` | `StartButton` 使用 400ms 防抖且提前翻转本地 `isStart` 假状态；`TUNButton` 非响应式读取 `globalState.appState.runTime`；`SystemProxyButton` 仅绑定配置布尔值而非实际生效态 | 点击关闭立刻变灰但后台 400ms 后才开始停机，系统代理开关在代理已停时仍显示开启（绿/蓝），仪表盘三处状态撕裂 |

---

## 2. 跨层契约与不变量

1. **`FlClashAgent` `ReplayJournal` 契约不可破坏**（`services/agent/src/journal.rs:140-142`）：
   - `Agent` 仅在 `stopListener` IPC 返回 `data == true` 时将日志覆盖为 `"stopListener"`；若返回 `false`，后续 Core 重启会重放旧的 `"startListener"` 导致代理幽灵自启。
   - 因此 `handleStopListener()` 必须保持返回 `true` 表示 Core 已接受停止意图（`isRunning = false`），而物理网卡是否彻底消失由 Flutter 侧 `refreshWindowsTunStatus(fresh: true)` 权威观测验证。
2. **偏好与运行态严格分离**（`AGENTS.md`）：
   - 点击绿色按钮关闭总代理（`updateStatus(false)`）只停止代理与虚拟网卡运行态，**不篡改**用户持久化的 `tun.enable` 与 `networkSetting.systemProxy` 偏好，停机完成后卡片如实显示“等待代理启动”并提供 `×` 快捷取消入口。
3. **测试隔离与零本机副作用**：
   - `SystemProxyCoordinator` 未挂载 `ProxyManager` 时 `disarmBeforeStop()` 为零开销空操作；Win32 `DnsFlushResolverCache` 通过 `AppController` 可注入 `flushSystemDnsCache` 回调隔离，注入 `windowsStartupEffects` 的单元测试绝不触碰宿主机真实系统代理或 DNS 缓存。

---

## 3. 分层高性能修复方案

### 3.1 `GS-01`：Go Core 优雅排空与单次确定性 TUN 拆卸（`core/common.go`、`core/hub.go`）
在 `handleStopListener()`（持有 `runLock`）与 `stopListeners()` 中按严格物理时序执行：
1. **切断后台周期任务**：`isRunning = false` → `cancelAllDelayTasks("cancelled")` → `stopHealthCheckForwarder()`（防止停机后 `touchProviders()` 后台唤醒节点 URLTest 拨号；下次 `handleStartListener()` 已内置重启该协程）→ `stopRequestForwarder()`。
2. **关闭全部入站接收器（含自定义入站与隧道）**：
   - `clearStrictIngressForConfigChangeLocked()`
   - `listener.PatchInboundListeners(nil, tunnel.Tunnel, true)`
   - `listener.PatchTunnel(nil, tunnel.Tunnel)`
   - 将 `HTTP` / `Socks` / `Redir` / `TProxy` / `Mixed` / `ShadowSocks` / `Vmess` / `Tuic` 监听端口全部归零关闭，阻止新连接进入。
3. **在 `Wintun` 仍存活时主动排空活跃连接与上游解析器**：
   - 调用 `closeConnections()` 遍历 `statistic.DefaultManager` 立即关闭全部 TCP/UDP 追踪连接，使 `gVisor`/`system` 协议栈向本地应用发出干净的 `FIN`/`RST` 并立即断开远端代理隧道，消除与 `sing_tun.Listener.Close()` 争抢读写环的活跃泵协程。
   - 调用 `resolver.ResetConnection()` 释放上游 DoH/DoT/UDP 连接池。
4. **单次原子关闭 `Wintun` + 尾包清扫 + Fake-IP 持久化**：
   - 移除 `listener.Cleanup()` 前冗余的 `listener.ReCreateTun(LC.Tun{}, tunnel.Tunnel)`，统一由补丁后的 `listener.Cleanup()` 单次加锁递增 `Revision`、更新 `RequestedEnabled=false` / `LastTunConf.Enable=false` 并调用 `closeTunListener()` 销毁 `Wintun` 设备与路由。
   - 紧接执行一次尾包 `closeConnections()`（空表耗时纳秒级）与 `resolver.StoreFakePoolState()`。

### 3.2 `GS-02`：零黑洞系统代理同步前置摘除（`lib/manager/proxy_manager.dart`、`lib/controller.dart`）
1. 新增进程内单例协调器 `SystemProxyCoordinator`（`systemProxyCoordinator`），与挂载后的 `ProxyManager` 共享串行 `_pending` 队列与 `_lastApplied` 签名。
2. 提供 `Future<void> disarmBeforeStop()`：
   - 若 `ProxyManager` 已挂载且当前系统代理处于启用签名，先进入同一 `_pending` 串行队列调用原生 `proxy?.stopProxy()`（底层 C++ `ProxyPlugin` 的 `CoalescingStateRunner` 工作线程无阻塞执行 WinInet `InternetSetOptionW`），并将 `_lastApplied` 置为 `(false, false, '', 0, '')`。
3. 在 `AppController` 停机链路中，**严格在 `globalState.handleStop()` 关闭 Core `MixedPort` 之前** `await systemProxyCoordinator.disarmBeforeStop()`：
   - 切换期间本地 `127.0.0.1:7890` 仍在正常转发，彻底消灭 `ERR_PROXY_CONNECTION_FAILED` 黑洞窗口。
   - 停机完成后 `runTimeProvider = null` 触发 `ProxyManager` 监听时，命中 `_lastApplied == (false, false, '', 0, '')` $O(1)$ 短路返回，避免二次重复调用 WinInet 广播。
   - `StatusBarManager.updateIcon(isConnected: false)` 移至 `handleStop()` 完成之后更新。

### 3.3 `GS-03`：亚毫秒级 Win32 FFI `DnsFlushResolverCache`（`lib/common/windows.dart`、`lib/controller.dart`）
1. 在 `Windows` 类中惰性加载 `dnsapi.dll` 导出函数 `DnsFlushResolverCache`（`Int32 Function()`），实现进程内 `< 1ms` 零子进程、零黑框的系统 DNS 解析缓存刷新 `tryFlushDnsResolverCache()`。
2. 在 `AppController` 注入可选回调 `Future<void> Function()? flushSystemDnsCache`（生产环境默认在 Windows 且非测试 fake 模式下调用 `windows?.tryFlushDnsResolverCache()`）。
3. 当停机前 TUN 处于启用/未知或用户偏好开启（Fake-IP 可能曾写入系统缓存），在 `updateStatus(false)`、`setTunEnabled(false)` 及 `_handleExit()` 完成网卡关闭后立即刷新系统 DNS 缓存，使直连域名即刻重新向物理网卡真实 DNS 发起解析。

### 3.4 `GS-04`：托盘/窗口退出全链路优雅停机（`lib/controller.dart:_handleExit`）
在 `_handleExit()` 的 8 秒总超时保护内重构退出顺序：
1. `savePreferences()` 持久化配置；
2. `system.setMacOSDns(true)` 恢复 macOS DNS；
3. `systemProxyCoordinator.disarmBeforeStop()`（未挂载时回退 `proxy?.stopProxy()`）率先摘除系统代理；
4. **新增优雅停核步骤**：以 3 秒有界超时调用 `clashCore.stopListener()`，让 `FlClashCore` 在进程被销毁前主动排空连接、卸载 `Wintun` 网卡与路由并落盘 Fake-IP 池；
5. 调用 `_flushSystemDnsCache()` 清除残留 Fake-IP DNS 缓存；
6. 最后执行 `clashCore.shutdown()` 与 `clashService?.destroy()` 回收后台进程并退出。

### 3.5 `GS-05` & `GS-06`：`TunRuntimeController` 停机状态机、`closeFailed` 免 UAC 自愈与仪表盘诚实 UI
1. **`TunRuntimeController` 停机事务**（`lib/common/tun_runtime.dart`）：
   - 保留 `cancelPendingIntent()` 原有语义兼容既有调用方；
   - 新增 `int beginProxyStop()` 与 `void endProxyStop(int intent)`：在保持 `desiredEnabled` 不变的前提下递增 `_intent` 撤销任何挂起的启动授权，并在 `observed != TunObservedState.off || operation == TunOperation.enabling` 时将 `operation` 设为 `TunOperation.disabling`。
   - 由于 `tunStatusLabel` 优先判断 `operation == TunOperation.disabling` 返回 `"正在关闭..."`，且 `TunStatusSwitch` 在 `runtime.busy` 时隐藏 `×` 并禁用开关，停机过程中执行 `invalidate()` 推进观测纪元不会再引发 `"状态未知"` 闪烁。
2. **`closeFailed` 免 UAC 自愈回收**（`lib/controller.dart:updateStatus`）：
   - `stopProxy()` 后立即执行 `refreshWindowsTunStatus(fresh: true)`；若返回 `status?.errorCode == 'closeFailed'`，自动通过已授权 Helper/Agent 执行免 UAC `effects.restartCore()` + `effects.initialize(...)` 让操作系统内核强制回收卡死的 `Wintun` 句柄，随后再次 `refreshWindowsTunStatus(fresh: true)`。若仍为 `closeFailed` 或 `observed == TunObservedState.on`，调用 `_tunRuntime.fail('closeFailed')` 如实暴露故障与诊断按钮。
3. **消除 400ms 防抖与三处 UI 撕裂**（`lib/providers/tun.dart`、`start_button.dart`、`hero_connect.dart`、`quick_options.dart`）：
   - 新增 `statusSwitchPendingProvider`（`bool?`：`null` 空闲、`true` 正在开启、`false` 正在关闭），由 `AppController.updateStatus` 精确驱动。
   - `StartButton` 移除 400ms `debouncer` 与本地提前篡改的假状态，点击 `0ms` 立即触发 `updateStatus(!isStart)`，过渡态禁用重复点击并展示紧凑 `CircularProgressIndicator` + `"正在关闭..."` / `"正在开启..."`，待真实 `runTimeProvider` 变更后平滑切换色彩与图标；`HeroConnect` 同步展示过渡态防重入。
   - `TUNButton` 改为响应式 `ref.watch(runTimeProvider.select((s) => s == null))`，停机完成瞬间更新为 `"等待代理启动"`。
   - `SystemProxyButton` 对齐 `TUNButton` 诚实展示语义：开关值绑定真实生效态 `isStart && systemProxy && mixedPort > 0`，副标题动态显示 `"正在关闭..."` / `"已启动"` / `"等待代理启动"` / `"已关闭"`；代理未启动但保留系统代理偏好时提供 `×` 取消偏好按钮，代理停止时拨动开关开启则自动设置偏好并联动启动代理。

---

## 4. TDD 验证与全量 `.exe` 交付计划

1. **Red 阶段**：
   - 新增 Go 单元测试 `core/graceful_stop_test.go`（验证活跃 Tracker 关闭、自定义 `inboundListeners` / `tunnels` 端口释放、`HealthCheckForwarder` 停止、`Cleanup` 单次修订递增）。
   - 新增 Flutter 单元与组件测试 `test/clash/graceful_shutdown_test.dart`（验证系统代理先于 Core 停机且零重复调用、DNS 缓存刷新触发、停机过程 `"正在关闭..."` 无未知闪烁、`closeFailed` 免 UAC 重启 Core 回收、`StartButton` 零防抖即刻响应、`TUNButton` 与 `SystemProxyButton` 停机后诚实状态切换）。
   - 先运行新测试确认预期失败（Red）。
2. **Green & 回归阶段**：
   - 实施上述全部生产代码修复，运行新测试转绿（Green），并跑通 Go（`-tags=with_gvisor` 与 `-race`）、Flutter 核心与 UI 回归测试集、Windows C++ `ProxyPlugin` 测试、`dart analyze` 与 `git diff --check`。
3. **提交与全栈 Windows x64 Release 构建**：
   - 仅暂存本任务文件提交至本地 `development` 分支。
   - 基于最新干净提交在隔离目录全量重编 `FlClashCore.exe`、绑定最新 `CORE_SHA256` 的 `FlClashHelperService.exe`、`FlClashAgent.exe`、`windows_strict_broker.exe`、`proxy_plugin.dll` 与 `FlClashX.exe`，产出可直接测试目录 `dist/FreedomCloud-windows-amd64-graceful-stop-<shortsha>/FlClashX.exe` 及 `.zip` / `.sha256` / `BUILD-INFO.txt`，保留历史构建产物并更新 `engineering/development-status.md`。

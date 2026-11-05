# 优雅停止（Graceful Stop）Code Review 修复方案二阶审查与定稿（2026-11-05）

- **审查对象**：针对提交 `a73a13c31b7c8565f816dbb3f89b2a0610595537` Code Review 提出的 `CR-GS-01`～`CR-GS-06` 六项初始修复建议。
- **审查原则**：逐项对标现有源码、Mihomo `v1.19.32` 内部契约、Android/Windows 双平台生命周期以及存量测试套件。初始方案完备且无副作用的按原方案执行；存在回归风险或盲区的立即升级为更优工程方案后再按严格 TDD（Red → Green）落地。

---

## 一、初始修复建议二阶审查结论总览

| 编号 | 级别 | 初始方案结论 | 发现的二阶隐患 / 升级点摘要 |
| --- | --- | --- | --- |
| `CR-GS-01` | `P1` | **需升级** | 初始方案在 `_disarmDepth` 归零时无条件执行 `_reconcileAfterStopDisarm()`，若在 `_handleExit` / `_handleRestart` / `_handleClear` 进程退出前释放租约且 `runTimeProvider` 尚未置空，会在退出瞬间把 Windows 系统代理重新打开。升级为带 `release({bool reconcile = true})` 的引用计数幂等租约，并在全部退出/清理路径显式置空运行态且以 `reconcile: false` 释放。 |
| `CR-GS-02` | `P1` | **需升级** | 初始方案允许在 `pending == true`（`正在开启...`）的 `0ms` 立即再次点击触发取消，会导致用户鼠标误双击（间隔 `80–180ms`）把刚发起的启动当场取消；且若使用 `DateTime.now()` 计时无法兼容 Flutter `WidgetTester` 的 `FakeAsync` 时钟。升级为基于 `Timer(const Duration(milliseconds: 500), ...)` 驱动的 `statusStartCancelableProvider`（`<500ms` 屏蔽误双击，`>=500ms` 允许一键中止慢启动/卡死启动），同时在 `_tunRuntime.serialize` 内部全覆盖 `_applyingWindowsConfigDepth` 与最新 Fake-IP 观测快照。 |
| `CR-GS-03` | `P2` | **需升级** | 发现三处上游/平台契约陷阱：<br>1. `core/healthcheck_forwarder_test.go` 的 `TestHealthCheckCacheProviderUpdatesRemainBounded` 在 `!isRunning && !tunUp.Load()` 下直接调用 `forwardHealthCheckDelays()` 并断言 `provider.touches == 2001`，不能直接修改 `forwardHealthCheckDelaysForRun` 默认行为；<br>2. Mihomo `listener/inbound`（`Socks`/`HTTP`/`Mixed` 等）的 `Close()` 不会清空内部切片 `stl`/`l`，若 `stopListeners()` 关闭后在 `handleStartListener()` 直接复用同一 `C.InboundListener` 实例调 `Listen()`，会累积已关闭句柄并在二次关闭时报 `use of closed network connection`；<br>3. Android 无界面磁贴/开机自启通过 `handleStartTun` 启动且不调用 `handleStartListener`（`isRunning == false`），因此门控 `startRuntimeHealthChecks` 与抑制停机端口绑定时必须兼容 Android `tunUp` 生命周期。 |
| `CR-GS-04` | `P2` | **确认可行（细化）** | 原方案方向正确；进一步细化：`closeFailed` 自愈重启后仅在非 Agent 直连模式补跑停机态 `_setupClashConfigImpl`（Agent 已由 `ReplayJournal` 自动重放配置），避免重复 `setupConfig`；退出路径仅在 `!usesAgent || agentCoreReady` 时调用带超时的 `stopListener()`，消除 Core 已停机时的 `3s` 空等。 |
| `CR-GS-05` | `P2` | **确认可行** | 原方案无副作用：`StartButton` 补齐 `_pressController.reverse()` 与 `isBusy ? !pendingTarget : effectiveStart` 配色稳定化；`SystemProxyButton` 补齐紧凑 `IconButton`、`mixedPort <= 0` 禁用态及 `hasProfile` 门控。 |
| `CR-GS-06` | `P3` | **确认可行** | 将上述全部边界写入 `core/graceful_stop_test.go` 与 `test/clash/graceful_shutdown_test.dart`，严格先跑出确定性 Red 失败再转 Green。 |

---

## 二、逐项定稿设计方案

### 1. `CR-GS-01`：`SystemProxyCoordinator` 引用计数租约与异常恢复对账（`lib/manager/proxy_manager.dart`、`lib/controller.dart`）
- 将布尔锁存 `_disarmingForStop` 替换为引用计数 `int _disarmDepth = 0`（`bool get isDisarmingForStop => _disarmDepth > 0`）。
- 提供 `Future<void Function({bool reconcile})> acquireStopDisarm()`：
  - 未挂载 `ProxyManager` 时返回空操作回调；
  - 挂载时先递增 `_disarmDepth`，再等待 `manager._disarmNow()`（`try/catch` 异常时回滚计数并重抛，`_disarmNow()` 在 `_lastApplied == _disarmedProxySignature` 时 `O(1)` 短路跳过重复 IPC）；
  - 返回单次幂等释放闭包 `release({bool reconcile = true})`：递减 `_disarmDepth`，当计数归零且 `reconcile == true` 时调用 `manager._reconcileAfterStopDisarm()`。
- `_reconcileAfterStopDisarm()`：若当前 `ref.read(proxyStateProvider).isStart` 仍为 `true`（说明 `stopProxy()` 在清除 `runTimeProvider` 前抛错中止），或 `_lastApplied != _disarmedProxySignature`（说明此前卸除失败），立即触发 `_scheduleUpdate()` 自动重挂或重试清理系统代理。
- `AppController.updateStatus(false)` 与 `AppController._updateStatus(false)` 均使用 `final releaseDisarm = await systemProxyCoordinator.acquireStopDisarm(); try { ... } finally { releaseDisarm(); }`，保证直接调用 `effects.stopProxy()` 同样无泄漏；进程退出/重启/清理路径统一以 `releaseDisarm(reconcile: false)` 释放。

### 2. `CR-GS-02`：并发启停门控闭环与防误触可取消启动（`lib/providers/tun.dart`、`lib/controller.dart`、`start_button.dart`、`hero_connect.dart`）
- 新增 `statusStartCancelableProvider = StateProvider<bool>((ref) => false)`。
- `AppController._setStatusSwitchPending(bool? pending)`：
  - 每次切换取消旧 `_startCancelableTimer` 并先将 `statusStartCancelableProvider` 置 `false`；
  - 当 `pending == true` 时启动 `Timer(const Duration(milliseconds: 500), ...)`（兼容 `FakeAsync`），若仍在同一 `_statusEpoch` 且仍处于 `pending == true`，将 `statusStartCancelableProvider` 置 `true`。
- `StartButton` 与 `HeroConnect` 的 `_ConnectButton`：
  - `pending == false`（正在关闭）：屏蔽重复点击；
  - `pending == true && !cancelable`（`<500ms` 误双击窗口）：屏蔽误触；
  - `pending == true && cancelable`（`>=500ms` 慢启动/卡死）：允许点击并立即派发 `updateStatus(false)` 中止启动。
- `AppController.updateStatus` Windows 分支：
  - 在 `_tunRuntime.serialize` 内，于 `_tunRuntime.invalidate()` 前读取最新 `_tunRuntime.observed != TunObservedState.off || _tunRuntime.desiredEnabled` 与入队前快照合并计算 `shouldFlushFakeIpDns`；
  - 在 `isStart` 与 `!isStart` 全程包裹 `_applyingWindowsConfigDepth++ / --`（在末尾 `!observedAfterStop` 的 `refreshWindowsTunStatus` 之前递减），彻底阻断停机中途后台观测误触发 `_repairVanishedAdapter`。

### 3. `CR-GS-03`：Go Core 停机态零端口重绑、自定义 `InboundListener` 重建与 Provider 静默唤醒修复（`core/common.go`、`core/config_runtime.go`、`core/hub.go`、`core/lib_android.go`）
- **自定义 `InboundListener` 停启重建**：
  - 在 `core/common.go` 保存 `currentRawListeners []map[string]any` 与 `currentListenersClosed bool`；
  - `stopListeners()` 关闭 `InboundListeners` 后标记 `currentListenersClosed = true`；
  - `updateListeners()` 在 `isRunning && currentListenersClosed` 且存在 `currentRawListeners` 时，通过 `listener.ParseListener` 重新构造全新的 `constant.InboundListener` 映射赋给 `currentConfig.Listeners`，避免复用已关闭的 `Socks`/`HTTP`/`Mixed` 实例。
- **桌面端 `!isRunning` 下 `setupConfig` 零端口绑定**：
  - 新增 `applyConfigForRuntimeStateLocked(cfg *config.Config)`：在 `runtime.GOOS == "android" || !isRunning` 时临时置 `Tun.Enable = false`；在 `runtime.GOOS != "android" && !isRunning` 时临时将 `Port`、`SocksPort`、`RedirPort`、`TProxyPort`、`MixedPort`、`ShadowSocksConfig`、`VmessConfig`、`TuicServer`、`Listeners`、`Tunnels` 清零后调用 `applyRuntimeConfigLocked(cfg, true)`，调用完成后立即恢复 `cfg` 字段原值（含严苛模式失败回滚分支），确保停机态加载配置不监听任何系统端口，而后续 `handleStartListener() -> updateListeners()` 完整恢复全部监听；同时保留 Android 无界面磁贴 `setupConfig -> handleStartTun` 所需的端口行为。
- **停机态禁止唤醒 Provider 拨测**：
  - `startRuntimeHealthChecks`（`core/config_runtime.go`）：当 `!isRunning && !tunUp.Load()` 时调用 `stopHealthCheckForwarder()` 并直接返回，不触发 `runInitialProviderHealthChecks()` 或启动后台协程；
  - `handleStartListener()`（`core/hub.go`）在持锁确认 `isRunning && currentConfig != nil` 后调用 `runInitialProviderHealthChecks()` + `startHealthCheckForwarder()`；
  - `handleStartTun` / `handleStopTun`（`core/lib_android.go`）：`handleStartTun` 在 `tunUp.Store(true)` 后（若 `!isRunning && currentConfig != nil`）启动 `runInitialProviderHealthChecks()` + `startHealthCheckForwarder()`；`handleStopTun` 在 `!isRunning` 时停止 `stopHealthCheckForwarder()` 与 `stopRequestForwarder()`；
  - `forwardHealthCheckDelaysWithTouch(stopCh, shouldTouch)`（`core/hub.go`）：保持 `forwardHealthCheckDelays()` / `forwardHealthCheckDelaysForRun(stopCh)` 默认 `shouldTouch = true`（100% 兼容存量测试），仅在 `handleSetUiActive(true)` 中传入 `shouldTouch = running || tunUp.Load()`，在 `handleSetScreenActive(true)` 中增加 `running || tunUp.Load()` 门控，使停机切回前台只刷新已有延迟缓存而不唤醒任何 Provider。

### 4. `CR-GS-04`：`closeFailed` 自愈后投影恢复与退出/重启/清理对称优雅停机（`lib/controller.dart`）
- `updateStatus(false)` 在 `closeFailed` 触发 `effects.restartCore()` + `effects.initialize(...)` 后（当 `epoch == _statusEpoch && _windowsStartupEffects == null`）：恢复 `clashCore.setUiActive(uiActivity.value)`、日志订阅开关，若 `clashService?.usesAgent != true` 则在停机态补跑 `_setupClashConfigImpl(isCurrent: () => epoch == _statusEpoch)`，随后刷新 `updateGroups()`、`updateProviders()`、`initForegroundCache()`。
- 抽取 `AppController._gracefulStopBeforeShutdown({Duration listenerTimeout = const Duration(seconds: 3)})` 并在 `_handleExit`、`_handleRestart`（非 Agent 分支，`2s` 超时）、`_handleClear` 复用：
  - 置空 `globalState.startTime = null` 并停止定时任务；
  - 通过 `acquireStopDisarm()`（`finally` 中 `release(reconcile: false)`）或 `proxy?.stopProxy()` 先卸除系统代理；
  - 仅在 `clashService?.usesAgent != true || clashService?.agentCoreReady == true` 时调用 `clashCore.stopListener().timeout(listenerTimeout)`；
  - 调用 `service?.stopVpn()`（补齐 Android 显式退出 VPN 清理）与 `_flushSystemDnsCache()`。

### 5. `CR-GS-05`：`StartButton` 与 `SystemProxyButton` 交互边界加固（`start_button.dart`、`quick_options.dart`）
- `StartButton`：在 `handleSwitchStart()` 入口调用 `_pressController.reverse()` 防止按压缩放卡在 `0.95`；将 `showActivePalette` 修正为 `isBusy ? !pendingTarget : effectiveStart`，使 `"正在关闭..."` 全程保持一致的绿色背景与白色文字/Spinner。
- `SystemProxyButton`：等待态 `×` 按钮采用紧凑尺寸（`visualDensity: VisualDensity.compact`、`minWidth/minHeight: 32`、`padding: EdgeInsets.all(4)`）；`Switch` 在 `pending != null || mixedPort <= 0` 时置为禁用（`onChanged: null`）；在 `!isStart` 下打开开关时，仅当存在有效选中配置（`hasProfile`）才调用 `updateStatus(true)`。

### 6. `CR-GS-06`：TDD 回归测试矩阵（`core/graceful_stop_test.go`、`test/clash/graceful_shutdown_test.dart`）
- Go Core 新增测试：
  1. `TestHandleStopAndStartListenerRestoresCustomInboundsAndHealthChecks`：验证 `handleStopListener -> handleStartListener` 往返重建自定义 `InboundListener`（无已关闭句柄残留、端口重新可连、二次 `handleStopListener` 无报错）并重启 `healthCheckForwarder`。
  2. `TestStoppedSetupConfigSuppressesPortBindsAndUiActiveSkipsProviderTouch`：验证 `!isRunning` 下 `setupConfig` 不绑定 `MixedPort`/自定义 `Listeners`、不启动 `healthCheckForwarder`，且 `handleSetUiActive(true)` 仅推送已有延迟历史而不调用 `provider.Touch()`；随后调用 `handleStartListener()` 立即绑定端口。
- Flutter 新增测试：
  1. `CR-GS-01`：`effects.stopProxy()` 抛错且未清除 `runTimeProvider` 时，`SystemProxyCoordinator` 释放租约后自动重新挂载系统代理（`plugin:startProxy`）。
  2. `CR-GS-02`：`StartButton` 在启动 `<500ms` 内忽略误双击，在 `>=500ms` 后允许点击立即派发 `updateStatus(false)` 取消慢启动。
  3. `CR-GS-04`：`handleExit` 在 `usesAgent && !agentCoreReady` 时跳过 `stopListener` `3s` 空等；`handleClear` 先卸除系统代理并刷新 DNS 缓存。
  4. `CR-GS-05`：`SystemProxyButton` 在 `mixedPort == 0` 时禁用 `Switch`，无 Profile 时开启偏好不误调 `updateStatus(true)`；`StartButton` 在 `"正在关闭..."` 期间 `runTimeProvider` 提前置空仍保持绿色激活调色板且缩放恢复 `1.0`。

# 性能重构 Code Review 全量收口工程方案（`CR-PERF-01`–`CR-PERF-08`）

日期：2026-11-05  
基线分支：`development@80d5eee78e23`（代码基线 `a0f1c82902092ef0fc991263bcf6ac8e0a8802aa`）  
方法论：严格 TDD（先编写覆盖全部 8 个问题的失败复现用例验证 Red，再实施高性能靶向修复验证 Green）。

---

## 1. `[CR-PERF-01 / P1]` Go Core 双锁写者/快读者模型闭环与独立 `mmdbMu` 隔离

- **根因**：Mihomo 的 `tunnel.Proxies()` 直接返回包级 `proxies` map 引用（读侧不持 `configMux`），而 `installStrictProxyRoutes` / `revokeStrictProxyRoutes` 仅在 `runLock` 下调用 `tunnel.UpdateProxies(...)`，未加 `proxyStateMu.Lock()`；`patchSelectGroup` 修改策略组选中项与无 `runLock` 的 `handleChangeProxy` 并发交叠；`handleHealthCheck` / `handleHealthProbe` 异步 goroutine 无锁读取 `tunnel.Proxies()`；`updater.UpdateMMDB()` 关闭 mmap 并重置 `sync.Once` 时未与 `handleGetCountryCode` 同步，且若直接共用 `proxyStateMu` 会在 HTTP 下载阶段阻塞节点查询。
- **高性能方案**：
  1. **严格锁序 `runLock -> proxyStateMu`（Two-Lock Writer / Single-Lock Fast Reader）**：所有写代理表或重置策略组的路径（`applyRuntimeConfigLocked`、`handleShutdown`、`installStrictProxyRoutes`、`revokeStrictProxyRoutes`、`patchSelectGroup`）在微秒级临界区内获取 `proxyStateMu.Lock()`；快读者（`handleGetProxies`、`handleChangeProxy`、`handleHealthCheck` 浅拷贝快照、`handleHealthProbe` 单键读取）仅获取 `proxyStateMu.RLock()`，并在发起网络 `URLTest` 前立即释放锁。
  2. **独立 `mmdbMu sync.RWMutex`**：将 `mmdb.IPInstance().LookupCode`（`mmdbMu.RLock()`）与 `updater.UpdateMMDB()`（`mmdbMu.Lock()`）从 `proxyStateMu` 剥离，既根除 mmap `Close()`/`ReloadIP()` 竞态，又确保 MMDB 远端下载期间对 `handleGetProxies` / `handleChangeProxy` 零锁争用。
- **TDD 用例**：`core/perf_concurrency_test.go` 新增 `TestStrictRoutesAndHealthProbeAreRaceFreeUnderConcurrentProxyReads`，在 `go test -race` 下并发执行 `installStrictProxyRoutes`、`revokeStrictProxyRoutes`、`handleGetProxies`、`handleChangeProxy`、`handleHealthProbe`。

---

## 2. `[CR-PERF-02 / P1]` Win32 `QS_SENDMESSAGE` 非阻塞排空等待 + 代理状态最后写入者合并（State Coalescing）

- **根因**：Windows `InternetSetOptionW(INTERNET_OPTION_SETTINGS_CHANGED / REFRESH)` 向所有顶层窗口同步执行 `SendMessageTimeoutW(HWND_BROADCAST, WM_SETTINGCHANGE, ..., 5000)`；`ProxyPlugin::~ProxyPlugin()` 在 UI 线程直接 `worker_.join()` 会停止泵送本线程的跨线程 `SendMessage` 队列（`QS_SENDMESSAGE`），造成 `~10s` 自锁；同时高频连续切换系统代理若逐条广播会将第三方慢窗口延迟线性放大 $N$ 倍。
- **高性能方案**：
  1. **内核事件 + `MsgWaitForMultipleObjects(..., QS_SENDMESSAGE)`**：`SerialTaskRunner` 惰性创建手动复位事件 `done_event_`（零任务零内核句柄分配），工作线程退出前 `SetEvent(done_event_)`；`Shutdown()` 在主线程通过 `MsgWaitForMultipleObjects(1, &done_event_, FALSE, INFINITE, QS_SENDMESSAGE)` 等待，仅在收到 `QS_SENDMESSAGE` 时调用 `PeekMessageW(&msg, nullptr, 0, 0, PM_NOREMOVE | PM_QS_SENDMESSAGE)` 派发跨线程同步 `SendMessage`，不消费任何输入/绘制队列消息，响应延迟 `< 0.1ms`。
  2. **`ProxyPlugin` 待执行状态槽位合并（$O(1)$ 队列深度）**：在 `ProxyPlugin` 层引入单槽位待定状态合并器，当后台线程正忙于上一次广播时，后续连续到达的 `StartProxy` / `StopProxy` / `StartPac` 自动覆盖待执行目标状态并聚合所有挂起的 `MethodResult`，合并完成后一次性回填全部 `MethodResult`，将最坏广播耗时从 $O(N \cdot T)$ 压缩至 $O(1 \cdot T)$ 且零悬挂 Future。
- **TDD 用例**：`plugins/proxy/windows/tests/proxy_settings_test.cpp` 新增真实同线程隐藏 `HWND` + 后台 `SendMessageTimeoutW(hwnd, WM_SETTINGCHANGE, ..., SMTO_NORMAL, 1500, ...)` + 主线程 `Shutdown()` 测试，断言耗时 `< 250ms` 且 `SendMessageTimeoutW` 成功返回（当前实现必定超时 `1500ms` 失败）。

---

## 3. `[CR-PERF-03 / P1]` 窗口常规边界双层守卫（零 IPC 内存态短路 + 采样后几何校验）

- **根因**：Windows 最小化触发 `WM_MOVE(-32000, -32000)` 与 `WM_SIZE(160×28)`，最大化触发全屏显示器矩形与隐形边框负偏移，`250ms` 防抖回调在窗口最小化/最大化后采样并覆盖 `windowSettingProvider`。
- **高性能方案**：
  1. **第一层（零 IPC 短路）**：在 `_WindowContainerState` 维护 `_isMinimized` / `_isMaximized` / `_isFullScreen`，在 `onWindowMinimize`、`onWindowMaximize`、`onWindowEnterFullScreen`、`onWindowClose` 时立即 `debouncer.cancel(FunctionTag.windowBounds)`，非普通窗口态下的 `onWindowMoved`/`onWindowResized` 直接在内存短路返回，零平台通道开销。
  2. **第二层（纯函数后置几何校验 `shouldPersistNormalWindowBounds`）**：防抖触发时通过单次 `Future.wait` 批量读取位置、尺寸与窗口状态，过滤最小化/最大化/全屏、Win32 图标化哨兵坐标（`<= -16000`）及低于最小窗口约束（`< 380×600`）的异常矩形，且值未变化时不触发 Riverpod `updateState`。
- **TDD 用例**：新增 `test/manager/window_bounds_sync_test.dart`，验证最小化 `(-32000, -32000, 160×28)`、最大化全屏尺寸与关闭窗口均不会污染已保存的常规窗口位置与尺寸。

---

## 4. `[CR-PERF-04 / P2]` `proxyDescriptions` 无锁 `atomic.Pointer` 快照与 `setupConfig` 零窗口原子提交

- **根因**：`setupConfig` 在 `refreshRuntimeListeners()` 之后才更新 `proxyDescriptions` 与 `FindProcessMode`，导致建卡数秒窗口内新节点混配旧描述、后台静默启动短暂退回 `FindProcessAlways`，且 Strict 回滚分支未恢复旧描述；`proxiesWithDescriptions` 在节点循环内逐次获取读写锁。
- **高性能方案**：
  1. 将 `proxyDescriptions` 改为不可变 map 的 `atomic.Pointer[map[string]string]`，彻底移除 `proxyDescMu`；`proxiesWithDescriptions` 在循环外单次原子读取指针（无缓存行写争用），空表直接走 `json.RawMessage` 快路径。
  2. 在 `setupConfig` 中预先纯函数构建 `candidateDescriptions`，紧随 `applyRuntimeConfigLocked`（在 `refreshRuntimeListeners()` 之前）同步提交 `proxyDescriptions`、`configuredFindProcessMode`、`externalControllerListening` 与 `syncEffectiveFindProcessMode()`，并在两处回滚分支与 `handleShutdown` 中严格恢复/清空。
- **TDD 用例**：`core/perf_concurrency_test.go` 新增测试验证在 `refreshRuntimeListeners` 阻塞期间，`handleGetProxies` 已立即观测到新 `serverDescription` 且后台 `FindProcessMode` 已处于降级后的 `FindProcessStrict`，同时验证 Strict 回滚恢复旧描述。

---

## 5. `[CR-PERF-05 / P2]` 前后台切换自适应重整 `groupsUpdateTimer` 与台账修正

- **根因**：`startGroupsUpdateTask` 在定时器激活时直接返回，导致窗口从隐藏（`180s`）恢复前台后仍沿用旧 `180s` 定时器；工程台账误将 `stopUpdateTasks` 记作 `pauseUpdateTasks`。
- **高性能方案**：在 `GlobalState` 记录当前激活定时器的 `_groupsUpdateInterval`，仅当目标周期（前台 `60s` / 后台 `180s`）与在途周期不一致时才取消并重设（相同周期幂等零重置，防止焦点切换饥饿），并在 `_AppStateManagerState._syncUiActivity` 中调用 `rebalanceGroupsUpdateTask()`；同步修正 `engineering/development-status.md`。
- **TDD 用例**：`test/common/update_tasks_test.dart` 新增 `fakeAsync` 用例，断言隐藏态 `180s` 定时器在切回前台后立即切换为 `60s` 周期触发。

---

## 6. `[CR-PERF-06 / P2]` `Preferences` 世代纪元（`_epoch`）与在途落盘线性化清空

- **根因**：`clearPreferences()` 未隔离正挂起于异步 `setString` 的 `_drainPendingSaves()`，在途写入完成后会复活 `_lastSavedConfig` 或覆盖刚清空的底层存储。
- **高性能方案**：引入单调递增 `_epoch`；`clearPreferences()` 递增 `_epoch`、清空内存缓存、等待快照到的在途 `_activeSave` 落盘收尾后再执行 `sharedPreferencesIns?.clear()`；`_drainPendingSaves(saveEpoch)` 与 `getConfig()` 在异步挂起前后校验 `_epoch`，失配则立即放弃回填。
- **TDD 用例**：`test/common/preferences_save_test.dart` 新增挂起存储后端下的并发 `saveConfig` + `clearPreferences` 用例，验证清空后内存脏检查与底层存储均保持干净，后续保存相同 `Config` 正常触发写盘。

---

## 7. `[CR-PERF-07 / P3]` `FileSha256Cache` 前后双 `stat` 无撕裂一致性校验

- **根因**：流式哈希期间若文件在磁盘上被原地覆盖，单次前置 `stat` 会把撕裂字节流的哈希缓存到旧元数据键下。
- **高性能方案**：在 `_computeDigest` 完成后执行后置 `stat` 复核 `(type, size, modifiedMicros)`；若前后一致则安全写入 `_cache`，若不一致则严禁污染缓存并自动执行一次干净重算。
- **TDD 用例**：`test/common/file_digest_test.dart` 新增流式计算中途覆写文件的复现测试，断言撕裂摘要不被缓存且返回最新文件内容摘要。

---

## 8. `[CR-PERF-08 / P3]` `DetectionState._checkIp` 热身重试窗口连续加载态

- **根因**：首测返回空结果并排入 `1.5s` `_warmupRetryTimer` 时提前将 `isLoading`/`isTesting` 置 `false`，造成 UI 闪现 `1.5s` 超时失败态。
- **高性能方案**：当已排入 `_warmupRetryTimer` 时保持 `isLoading: true, isTesting: true, ipInfo: null` 直至热身重试收敛；若热身等待期间发生 `notifyRoutingChanged()` 取消重试，则同步复位 `isTesting: false`。
- **TDD 用例**：`test/common/dashboard_ip_probe_test.dart` 断言首测落空进入热身重试等待期时 `isLoading` 与 `isTesting` 保持 `true`，重试仍落空后才置为 `false`。

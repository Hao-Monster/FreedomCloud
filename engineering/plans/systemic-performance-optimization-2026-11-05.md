# FlClashX 全栈系统级性能优化方案（2026-11-05）

日期：2026-11-05  
基线分支与提交：`development` @ `8bb1197`（已包含第一轮 WinInet 系统代理异步化、`FileSha256Cache` 哈希缓存、主题注册表 FFI 读取、`Fake-IP` 系统探测白名单与桌面端 `bypassPrivate` 规则）  
状态：方案研究冻结，按 P1→P6 顺序开发并通过单元/竞态验证后打包 Windows x64 Release 普通预览包。

---

## 一、问题总览与根因矩阵

| 编号 | 问题域 | 实测/源码根因 | 影响层级 |
|---|---|---|---|
| **P1** | `savePreferences` 全量 JSON 序列化风暴 | `WindowManager.onWindowMoved/Resized` 逐像素写 `windowSettingProvider` 击穿 13 路聚合的 `configStateProvider`；`AppStateManager` 在桌面端每次窗口失焦（`AppLifecycleState.inactive`）无防抖、无脏检查直接调 `Preferences.saveConfig`，在 UI 主线程对全量 `Config` 同步 `json.encode` 写盘 | Dart UI 主线程卡顿、磁盘 I/O 抖动 |
| **P2** | `Logs` / `Requests` 逐事件 $O(N)$ 数组拷贝与正则写盘风暴 | Core `forwardNewRequests` 每轮集中推送数十至数百条连接；`ClashManager.onLog/onRequest` 逐条触发 `FixedList.copyWith()`（拷贝 1000 元素数组）+ `AppState.copyWith` + `nodeCountryResolver` 重算；`FileLogger` 每行重复编译 `DateFormat` 且无快速跳过直接跑 3 组脱敏正则 | Dart UI 帧率抖动、GC 压力 |
| **P3** | 全局强制 `find-process-mode: always` 扫描系统连接表 | `ClashConfig` 与 `effectiveConnectionFindProcessMode` 常驻强制 `always`；Mihomo 在 `tunnel.go:394` 对每个新建 TCP/UDP 包无条件调 `GetExtendedTcpTable` / `GetExtendedUdpTable` 全表扫描 + `QueryFullProcessImageNameW`，即使窗口隐藏或无进程规则命中 | 本机浏览器/微信/IDE 短连接首包延迟与内核态开销 |
| **P4** | Windows 窗口隐藏/最小化后后台轮询永不休眠 | `AppStateManager` 仅在 Android 端停止 `updateTasks`；Windows 隐藏到托盘后仍每 3s 发两次流量 IPC + 刷 `Shell_NotifyIconW` Tooltip、每 3s 轮询 `refreshWindowsTunStatus`、每 60s 全量拉取节点组 | 后台常驻 CPU、IPC 与 Explorer 交互开销 |
| **P5** | Core `runLock` 全局粗锁阻塞代理查询/切换与冗余序列化 | `handleStartListener` 持有 `runLock` 执行 `updateListeners`（Windows Wintun 初始化耗时约 5.0–5.5s），期间 `handleGetProxies`、`handleChangeProxy`、`handleGetConnections` 等只读/统计操作全部阻塞排队；`proxiesWithDescriptions` 对无描述节点仍执行 `Marshal → Unmarshal → Marshal` 双重转换；`updateConfig` 在仅修改 `Mode`/`LogLevel`/`FindProcessMode` 时也无条件重跑 `refreshRuntimeListeners` | 启动/重连窗口期 UI 操作冻结、Core 内存分配 |
| **P6** | `Windows.checkService` 串行拉起 `sc.exe` 子进程 | `checkService` 与 `_waitForServiceState` 反复通过 `Process.run('sc', ...)` 创建控制台子进程（每次 2～10 个进程），受 Windows Defender / EDR 进程创建钩子放大至 `80–300ms` | 启动检测、权限探测与恢复耗时 |

---

## 二、逐项工程方案设计

### P1：`savePreferences` 脏检查幂等化 + 窗口几何防抖 + 异步编码合并
1. **窗口位置/尺寸防抖（`lib/manager/window_manager.dart`、`lib/enum/enum.dart`）**：
   - 新增 `FunctionTag.windowBounds`，在 `onWindowMoved` 与 `onWindowResized` 中以 `250ms` 防抖合并窗口几何状态写入，消除拖动/缩放过程中的逐帧 `configStateProvider` 重建。
2. **`Preferences` 快照脏检查与单飞合并（`lib/common/preferences.dart`）**：
   - 维护 `_lastSavedConfig`（在 `getConfig()` 成功读取时初始化，`clearPreferences()` 时清空）。
   - `saveConfig(Config config)` 先做结构相等判断（`config == _lastSavedConfig`，利用 `@freezed` 引用短路与值相等）：未变化时直接 $O(1)$ 返回 `true`，跳过 `json.encode` 与磁盘写入。
   - 配置确实变化时，使用单飞队列（`_pendingConfig` + `_savingLoop`）串行化写盘，并将大型 JSON 字符串编码在超过阈值或常规保存路径下避免重复编码同一快照。
3. **桌面失焦生命周期收敛（`lib/manager/app_state_manager.dart`、`lib/controller.dart`）**：
   - 桌面端 `AppLifecycleState.inactive`（仅失去键盘焦点，并非移动端进程挂起）改为调用防抖或仅在存在未落盘配置变更时落盘；移动端保持 `paused/inactive` 立即落盘语义。`AppController.savePreferences()` 仅在实际发生配置持久化或存在待刷健康记录时输出日志，彻底消除每 0.6s–2s 的空转刷盘。

### P2：`Logs` / `Requests` 微批合并刷新 + `FixedList` 只读视图缓存 + `FileLogger` 热路径优化
1. **`FixedList<T>` 批量追加与只读快照缓存（`lib/common/fixed.dart`）**：
   - 新增 `addAll(Iterable<T> items)` 与 `copyWithAdded(Iterable<T> items)`，一次拷贝完成多元素追加与 `truncate(maxLength)`。
   - 缓存 `_unmodifiableView`（变更时失效），使 `state.list` 多次读取保持 $O(1)$ 且引用稳定（优化 Riverpod `.select((s) => s.list)` 等价比较）。
2. **`Logs` / `Requests` 批量接口与 `ClashManager` 帧级微批合并（`lib/providers/app.dart`、`lib/manager/clash_manager.dart`）**：
   - 保留 `addLog` / `addRequest` 同步语义（确保既有单元测试 100% 兼容），新增 `addLogs(List<Log>)` / `addRequests(List<Connection>)`。
   - `ClashManager` 对来自 Core 事件流的实时 `onLog` / `onRequest` 采用 `64ms` 微批缓冲（首条事件启动单次 `Timer`，上限批量满 128 条立即刷出，`dispose` 时同步清空），将 `forwardNewRequests` 单次突发 200 条连接的数组克隆、Riverpod 广播与 `nodeCountryResolver.onConnectionsUpdated` 重算从 200 次压缩为 **1 次**。
3. **`FileLogger` 与日志脱敏快速路径（`lib/common/log_redaction.dart`、`lib/common/file_logger.dart`）**：
   - `redactSensitiveLogData` 增加轻量字符预筛：若文本不含 `:`、`=` 且不含 `Bearer`/`Basic`（大小写无关子串检查），直接原样返回，跳过全部 3 组回溯正则匹配；包含候选字符时保持原有完整脱敏语义不变。
   - `FileLogger` 复用静态/成员变量 `DateFormat`（或直接整数拼接固定格式 `yyyy-MM-dd` 与 `yyyy-MM-dd HH:mm:ss.SSS`），消除每行日志 2 次 `DateFormat` 语法树构造。

### P3：基于 UI 活跃态与外部控制器状态的动态 `FindProcessMode` 降级
1. **约束分析**：
   - 不能把 `updateParamsProvider` 绑定到页面切换（否则每次点击“连接”页会触发 `ClashConfigUpdateListener` → `loadingRun` 全屏转圈与 `_tunRuntime.serialize`）。
   - 不能降为 `FindProcessOff`（会破坏订阅中的 `PROCESS-NAME` / `PROCESS-PATH` 分流规则）。
   - Mihomo 的 `tunnel.SetFindProcessMode` 是纯原子内存写（`atomic.Int32Enum.Store`），无锁且不重建任何 Listener；`FindProcessStrict` 完整支持所有 `PROCESS-NAME` / `PROCESS-PATH` 规则，仅跳过非进程规则连接的全表扫描。
2. **实施方案（`core/hub.go`、`core/common.go`）**：
   - 新增 `syncEffectiveFindProcessModeLocked()`（及原子读取配置期望模式 `configuredFindProcessMode`）：
     - 当 `configured == FindProcessAlways` 时：若 `uiActive.Load() == false`（窗口最小化或隐藏到托盘）且外部控制器未开启监听（无外部 Web 面板消费进程字段），自动调用 `tunnel.SetFindProcessMode(process.FindProcessStrict)`；
     - 一旦窗口恢复可见（`handleSetUiActive(true)`）或外部控制器开启，立即恢复 `tunnel.SetFindProcessMode(process.FindProcessAlways)`。
   - 保持 `effectiveConnectionFindProcessMode` 与既有测试契约 100% 兼容，同时让后台日常使用（95% 场景）彻底免除每包 `GetExtendedTcpTable` / `GetExtendedUdpTable` 扫描。

### P4：桌面端窗口隐藏/最小化（`!uiActivity.value`）时的后台轮询分级休眠
1. **流量采样任务休眠（`lib/manager/app_state_manager.dart`、`lib/state.dart`）**：
   - macOS 状态栏开启速率显示时仍需流量更新；在 **Windows / Linux / Android** 上，当 `uiActivity.value == false` 时统一调用 `globalState.stopUpdateTasks()` 暂停 3s 一次的 `getTraffic` + `getTotalTraffic` IPC 与 `Shell_NotifyIconW` 刷新（保留 `globalState.tasks` 注册列表不丢失，兼容 `silentLaunch` 冷启动隐藏窗口）；当 `uiActivity.value == true` 且 `globalState.isStart` 时立即调用 `globalState.startUpdateTasks()` 恢复采样。
2. **Windows TUN 状态观察自适应周期（`lib/controller.dart`）**：
   - 将固定 `3s` 的 `_tunObservationTimer` 改为自适应调度：窗口可见（`uiActivity.value`）或 TUN 处于非稳态（`busy` / `closing` / `observed != TunObservedState.on` / 正在修复）时保持 `3s` 快速检测；窗口隐藏且 TUN 已稳定运行时放宽至 `15s`（保留 `onTunTransportChanged`、系统唤醒与网络变更时的即时触发，自愈能力零退化，稳态后台轮询降低 80%）。
3. **后台节点组同步自适应周期（`lib/state.dart`）**：
   - `startGroupsUpdateTask` 在 `uiActivity.value == true` 时维持 `60s`，在桌面端隐藏窗口（`!uiActivity.value`）时放宽至 `180s`（窗口恢复时 `_syncUiActivity` 原本即立即触发 `updateGroupsDebounce()`）。

### P5：Core 读写锁解耦（消除 Wintun 启动 5.5s 锁阻塞）、`proxiesWithDescriptions` 零冗余反序列化与按需刷新 Listener
1. **代理表读写锁 `proxyStateMu` 解耦（`core/common.go`、`core/hub.go`）**：
   - 引入 `proxyStateMu sync.RWMutex`，仅在真正替换 Mihomo 全局代理/MMDB 指针的边界（`applyRuntimeConfig` 与 `executor.Shutdown`）加写锁 `proxyStateMu.Lock()`。
   - `handleGetProxies`、`handleChangeProxy`、`handleGetCountryCode` 改为持有读锁 `proxyStateMu.RLock()`，不再阻塞于 `handleStartListener` 耗时 5.5s 的 Wintun 创建锁 `runLock`；同时对 `setupConfig` 中的 `ApplyConfig` 保持严格互斥，确保 `go test -race` 零数据竞争。
   - `handleGetConnections`、`handleCloseConnections`、`handleCloseConnection` 直接访问内部已并发安全的 `statistic.DefaultManager`，移除多余的 `runLock`。
2. **`proxiesWithDescriptions` 原生 `json.RawMessage` 直通（`core/common.go`）**：
   - 先持 `proxyDescMu.RLock()` 检查节点是否存在非空 `serverDescription`；若无（绝大多数节点），直接将 `json.Marshal(proxy)` 包装为 `json.RawMessage(data)` 存入返回表，省去逐节点 `json.Unmarshal` 到 `map[string]interface{}` 再二次 `json.Marshal` 的双倍 CPU 与堆分配。
3. **`updateConfig` 按需重建 Listener（`core/common.go`）**：
   - 比较更新前后的入站监听与 TUN 参数（`MixedPort`、`AllowLan`、`Tun` 各字段）：仅当入站监听或 TUN 配置实际发生变化（或存在活动 `strictIngress` 需要对齐）时才调用 `refreshRuntimeListeners()`，使切换 `Mode`（规则/全局/直连）、`LogLevel`、`FindProcessMode`、`UnifiedDelay`、`TCPConcurrent`、`IPv6` 成为纯内存毫秒级操作。

### P6：Windows 服务巡检改用 `advapi32.dll` SCM FFI（保留 `sc.exe` 兜底）
1. **Win32 SCM 原生查询（`lib/common/windows.dart`）**：
   - 通过 `DynamicLibrary.open('advapi32.dll')` 绑定 `OpenSCManagerW`、`OpenServiceW`、`QueryServiceStatus`、`QueryServiceConfigW`、`CloseServiceHandle` 及 `kernel32.dll` `GetLastError`。
   - 新增 `tryQueryHelperServiceNative(String expectedHelperPath)`：
     - 若 `OpenServiceW` 返回 `ERROR_SERVICE_DOES_NOT_EXIST (1060)`，直接判定 `WindowsHelperServiceStatus.none`（0 子进程、`< 0.1ms`）。
     - 读取 `SERVICE_STATUS.dwCurrentState` 与 `QUERY_SERVICE_CONFIGW.lpBinaryPathName`，复用既有 `windowsServiceConfigReferencesHelper` 校验路径匹配，若 `dwCurrentState == SERVICE_RUNNING (4)` 则配合 `request.pingHelper()` 返回 `running` 或 `presence`。
     - `_waitForServiceState` 优先使用原生 `tryQueryServiceStateCode` 查询状态码，将最多 10 次的 `sc query` 子进程风暴降至零子进程。
   - 若 FFI 打开 SCM 因非 `1060` 异常错误返回 `null`，自动平滑回退原有 `Process.run('sc', ...)` 逻辑，确保兼容性与安全性零退化。

---

## 三、组件兼容与预览打包策略

1. 本轮同时修改了 Dart UI、`plugins/proxy/windows`（已在 `8bb1197` 修改 C++ 源码）与 `core/`（Go 源码）。
2. 若只更新 `app.so` 而不重编 `FlClashCore.exe` / `FlClashHelperService.exe` / `proxy_plugin.dll`，则 Core 侧 P3/P5 优化和 `8bb1197` 的 C++ 异步系统代理均不会进入产物；若只换 `FlClashCore.exe` 而不重编 `FlClashHelperService.exe`，则会违反 `AGENTS.md` 中 Helper 绑定 `CORE_SHA256` 的安全门禁。
3. 因此本轮在全部代码验证通过并提交干净 commit 后，使用本机完整工具链从该提交重编全部配套组件：
   - `FlClashCore.exe`（经 `go run ./tools/mihomo-overlay` 生成补丁与 `CORE-PATCH.json`，带 `-tags=with_gvisor`）
   - `FlClashHelperService.exe`（以新 `FlClashCore.exe` 的 `SHA256` 作为 `TOKEN` 编译 `--features windows-service`）
   - `FlClashAgent.exe`（`cargo build --release --locked`）
   - Windows Runner + `proxy_plugin.dll` + Flutter Release AOT 产物（`FlClashX.exe`、`data/app.so`、`flutter_assets` 及 MSVC 运行库）
4. 输出到全新独立目录 `dist/FreedomCloud-windows-amd64-perf-overhaul-<shortsha>`（普通预览模式，调用 `prepareWindowsPackageMode(..., strict: false)` 不混入未重签名的旧 Strict 驱动二进制，并生成完整 `BUILD-INFO.txt`、`PREVIEW-README.txt`、`SHA256SUMS.txt` 与确定性 `.zip` + `.sha256`），完整保留 `dist/` 内所有历史可用包，且不触碰当前工作站正在运行的旧代理进程。

---

## 四、验证门禁矩阵

1. **Dart 单元与组件回归**：新增/更新以下专项测试并跑通既有相关测试套件：
   - `test/common/preferences_save_test.dart`（P1：相同 `Config` 跳过 `json.encode`/写盘、变更合并写盘）
   - `test/common/fixed_list_batch_test.dart`（P2：`FixedList.addAll`/`copyWithAdded`、只读视图缓存引用稳定性、`redactSensitiveLogData` 快速路径与敏感凭据脱敏一致性）
   - `test/common/windows_scm_ffi_test.dart`（P6：Windows 本机 SCM FFI 查询已知系统服务状态与不存在服务 `1060` 判定）
   - 既有回归：`file_digest_test.dart`、`local_network_protection_test.dart`、`dashboard_ip_probe_test.dart`、`connection_process_mode_test.dart`、`windows_service_command_test.dart`、`windows_startup_controller_test.dart`、`node_country_test.dart`、`file_logger_test.dart`。
2. **Go Core 单元与 `-race` 竞态回归**：
   - 在 `core/` 执行 `go run ./tools/mihomo-overlay` 后运行 `go test -modfile=.generated/go.mod -overlay=.generated/mihomo-overlay.json -tags=with_gvisor ./...` 及并发竞态专项测试（验证 `handleStartListener` 持 `runLock` 阻塞期间 `handleGetProxies` / `handleChangeProxy` / `handleGetConnections` 不阻塞且无竞态、`updateConfig` 非监听变更不触发 `refreshRuntimeListeners`、`uiActive` 切换动态调整 `FindProcessMode`）。
3. **Native C++ 插件测试与静态分析**：
   - `plugins/proxy/windows/tests/Run-Tests.ps1`（Regression + NativeCompile）与变更 Dart 文件 `dart analyze` 零错误。

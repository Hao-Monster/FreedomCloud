# 运行诊断后续资源修复方案与任务

日期：2026-10-09（Asia/Singapore）。模式：明确缺陷的快速执行；先完成方案研究和测试设计，再实施。用户已授权“先研究……然后再开始修复”，不新增业务行为或再次等待开发许可。

## 事实、目标与范围

- 起点：唯一开发分支 `development@13b0ea05dfca6840e402a1f29d543705e30382e4`；本轮 fetch 后领先自有远端 6、落后 0，无开放 PR。保留既有 coverage、QA 草稿、stash、历史工作树和所有旧包。
- 前一轮真实运行观察覆盖约 11 分钟，未复现持续资源增长或资源耗尽。这不是长期无泄漏证明。以下三项由源码生命周期审查确认，本轮不将其表述为已导致用户机器故障。
- R1：Helper 的服务入口和 HTTP/Core 输出路径各自创建 logger，可能同时写入和轮转同一文件；服务停止只 flush 其中一个，并未确认 Core 输出线程读完管道尾部。
- R2：Windows 进程图标提取虽然串行，但 Future 链的排队和过期请求没有容量/消费者生命周期约束。
- R3：健康检查去重状态保留已删除的节点/测试 URL；清理还须处理配置重置、前台 flush 与后台轮询并发。
- 完成条件：三项生产调用链修复、可复现的目标缺陷证据、失败/并发/生命周期回归、相关完整测试、独立审查、构建和本地提交；分别记录源码完成与真实平台未验收。

不做：更改日志等级或进程优先级、升级 Mihomo/依赖、改购买行为、代理/TUN/权限策略、启动或替换当前客户端、操作 SCM/驱动/防火墙/节点、连接第二个 Agent UI 会话、推送/合并/发布。当前运行版本与网络保持不动。不得靠清理用户配置、强制 GC 或重启掩盖缺陷。

## R1：一个日志所有者与有界输出收尾

### 设计

1. 在正常进程入口构造一个 `Arc<ServiceLogger>`，由 Windows service 或普通 main 注入 `run_service`、HTTP routes 与 stdout/stderr reader。dispatcher 启动失败属于独立错误路径，可独立构造 logger。
2. 用 `Mutex` 计数和 `Condvar` 跟踪输出 producer。每条读取线程在 spawn 前取得 guard；EOF、读取失败、panic unwind、spawn 失败均释放。先销毁 reader/管道，再释放 guard。只计输出 producer，不计 writer，不积累已结束的 JoinHandle。
3. Core 退出已经确认且新启动入口关闭后：结束 HTTP server → 有界等待输出 producer 归零（总 2 秒）→ 写最后生命周期诊断 → flush 同一个 writer（总 500 毫秒）→ 报告 SCM Stopped。等待放入 blocking worker。
4. 日志收尾失败不能撤销 Core 已退出的事实，也不能无期限停在 StopPending；报告明确的日志错误和非零停止结果。reader 未排空时仍尝试 flush 已入队数据，但不能声称完整收尾成功。
5. flush 使用 typed Result，区分队列满、writer 断开、ack 超时、文件不可用/I/O 失败。文件写入丢失必须保持可观测，不能被重新打开后的成功 flush 掩盖。
6. 保留非阻塞 producer、256 槽队列、8 MiB 文件、3 份轮转和 16 KiB 输出分帧；不承诺 fsync 或断电持久化，不引入新日志框架。

### 文件边界

`services/helper/src/main.rs`、`services/helper/src/service/{windows,hub,logging}.rs` 及其中的隔离测试。默认不改 Agent、process_stop 或 shared/core_output。

### 测试矩阵

| ID | 场景/方法 | 可观察预期 |
|---|---|---|
| L01 | 受控 Read 阻塞 stdout/stderr 尾部；调用真实收尾入口再释放 | 不得在 producer 未结束时提前报告成功；文件含两个尾部 sentinel |
| L02 | EOF 无换行、读取错误、重复两路读取 | 尾部/错误有记录；每轮计数归零，无历史线程表累积 |
| L03 | 一路永久阻塞至短测试期限 | 有界返回且报告未排空；随后释放测试线程并清理 |
| L04 | 共享 Arc 的生命周期/Core 交错写入与小阈值轮转 | 单一 writer，正常容量内无重复或丢失 |
| L05 | 满队列、断开 consumer、不回应 ack | 区分错误，等待不超预算 |
| L06 | 普通文件占据父目录；注入写失败后重新打开成功 | 失败不能伪成功；恢复不能抹除已发生的数据丢失 |
| L07 | 纯状态/注入报告，不注册服务 | Core 停止失败仍保留 owner；Core 已退出而日志失败仍结束服务且报告失败 |

Red 使用原直接 flush 的真实行为与受控延迟尾部/不可写日志，不能以新增函数未定义的编译错误冒充。文件全部使用本轮独立临时目录。

## R2：有界图标队列与可见消费者生命周期

### 设计

1. Windows 提取服务至多 1 个实际执行、64 个等待 key、64 个成功缓存项。成功缓存和 pending/in-flight 任务分离；Windows 路径 trim、分隔符、大小写规范化，等价 key 共享一次提取。
2. 使用由 `ProcessIcon` 持有的 lease。最后一个消费者释放时移除未开始任务；执行中的同步 Win32 调用不能被强杀，仍占唯一槽直至实际完成。晚到结果不能写回已销毁或换路径的 widget。
3. 队满返回明确的 retryLater；组件显示原通用图标，并监听合并的容量释放事件后重新申请。监听由仍挂载的组件持有，成功申请、disable、换路径、离页、dispose 时撤销。不增加 Timer 轮询或另一条全局无界候补任务队列。
4. 仅成功图标进入 LRU；拒绝、取消、null、error 不缓存为永久 null。同 widget 的失败稳定显示 fallback，不因连接刷新重试；重进或新请求可重试。
5. 连接页由 KeepScope 保活，离页不一定 dispose。用小型 `ProcessIconActivityScope` 包装 `ConnectionsView`，复用已有 `_isCurrentPage && uiActivity` 信号；活动恢复重新申请，不修改全局导航生命周期。其他消费入口保留共享 widget 行为。
6. 保留 HICON/HBITMAP/HDC 与 Image/codec/descriptor/buffer 的 finally，不改变 Linux/Android 路径，不新增生产依赖。

### 文件边界

`lib/common/process_icon.dart`、新增专用 `process_icon_queue.dart`、`lib/views/connection/item.dart`、`lib/views/connection/connections.dart`，必要的小型 activity scope；`test/common/process_icon{,_queue,_widget}_test.dart`。不修改 home/global navigation。

### 测试矩阵

| ID | 场景/方法 | 可观察预期 |
|---|---|---|
| I01 | 阻塞首任务，提交 130 个不同 key | 恰至多 1 running + 64 waiting；其余明确可重试 |
| I02 | 等价路径、多消费者、历史成功项超过 64 | pending 独立去重，无第二次在途提取 |
| I03 | 排队的最后/部分消费者释放；执行中取消 | 无人等待的 queued 不执行；共享消费者不误取消；执行槽不提前释放 |
| I04 | 66 个可见 widget、随后释放容量 | 最后一个不需父级重建也可从 fallback 加载成功，无永久 null |
| I05 | null、error、缓存淘汰后重进 | 无未处理异步错误，队列继续；同 widget 不轮询重试，新请求可恢复 |
| I06 | A 换 B 后 A 迟返、disable、unmount | 无过期图标、残留监听/排队或 setState-after-dispose |
| I07 | 保活页面离开、窗口不可见、恢复 | 仍 mounted 时撤销消费者；恢复正确重取 |
| I08 | 真实 PNG 成功/null/编码错误既有用例 | 字节与所有图像资源释放保持正确 |

Red：先加入行为不变的 loader 注入点，阻塞首任务、挂载超过容量图标后卸载；旧 Future 链继续执行无人消费的任务，新实现仅完成已执行任务。缺失 API/编译失败不算 Red。

## R3：健康检查缓存跟随有效快照并隔离代际

### 设计

1. `healthCheckSweepMu` 串行完整的快照、dedup/prune 和发送，避免前台 flush 与定时 tick 交错提交过期集合。
2. 在 `runLock` 下捕获当前 proxies/config 与 generation。历史读取和消息发送不持 runLock；generation/reset/cache 仅用 `healthCheckMu` 保护。
3. 从当前 proxy 对象收集非空 default/extra URL 最新历史；提交时验证 generation，并将缓存替换为当前有效快照的新 map。结构化 `(proxyName,testURL)` key 防碰撞，结构化 `(UnixNano,Delay)` 签名保持去重语义。替换 map 也释放历史 bucket 容量，不设会截断大订阅的任意硬上限。
4. 配置 reset 和 stop 清空缓存并递增 generation；即使没有定时 channel，stop 也清理。旧快照不能在 reset 后回填或裁剪新状态。
5. 定时 goroutine 调用带 run stopCh 的内部入口；snapshot 捕获时检查该 run 已关闭，避免 stop 和 tick 同时 ready 后旧循环获得新 generation 再写入。前台 flush 保持现有入口语义。
6. 同一 provider 对象动态替换 `Proxies()` 的节点，在下一次 sweep 清理旧节点。发送在状态锁外，协议不变；已经提交/入队的旧事件不追溯取消。

锁顺序：sweepMu → runLock → healthCheckMu（捕获）；sweepMu → healthCheckMu（提交）；reset 只持 healthCheckMu；start/stop 可持 chMu 和 healthCheckMu，禁止反向获取 sweepMu。不在 runLock/healthCheckMu 内调用 native callback 或 IPC。

### 文件边界

`core/hub.go`，新增 `healthcheck_forwarder_test.go` 和 `healthcheck_forwarder_output_test.go`（真实 in-memory output 的 `!cgo` 测试）。不改模块缓存、协议、Mihomo 固定版本或 common.go。

### 测试矩阵

| ID | 场景/方法 | 可观察预期 |
|---|---|---|
| H01 | 默认/extra 历史、重复/时间/延迟变化、delay0 | 精确 dedup；真实消息契约仍 0→-1 |
| H02 | A,B→B,C→empty；删除后同签名重加 | map 跟随当前集合；重加可重新发出 |
| H03 | 同名节点替换无历史；extra URL 移除/空历史 | 不保留失效 key |
| H04 | 同一 provider 对象更新 2000 批×8 节点×3 历史 | 常态 24 live entries，不累积旧批次 |
| H05 | 9000 live 节点，缩至 1→0 | 大订阅不被截断；缩容后状态收敛 |
| H06 | channel 阻塞历史采样，reset 后提交新代 | 旧代不回填/删除新状态；并发 race 通过 |
| H07 | 并发前台 flush/定时 sweep | 不重复发出相同历史，无数据竞态 |
| H08 | 没有 channel 的 stop；已关闭旧 run；在途 stop | 清空并失效旧代；旧 run 不访问 provider/回填 |
| H09 | reset 后同历史 | 保留重新上报语义 |
| H10 | 节点/URL 包含分隔符 | 不发生 key 碰撞 |
| H11 | 无 currentConfig | 不访问 provider，不发网络请求 |

Red 在现有生产入口用隔离 proxy/history fixture 复现删除残留和 key 碰撞；随后同用例 Green。race 使用测试对象，禁止连接现役 Agent 或真实代理端口。

## 执行任务与门禁

1. **研究完成/方案冻结**：本文件记录实施前合同；偏差须记录原因，不降低验收标准。
2. **R1/R2/R3 分别实现**：代理按上述互不重叠文件分工；每项保留 Red、Green、失败路径、完整模块回归和环境日志。Git 写操作仅由主负责人执行。
3. **整合与独立审查**：交叉审查资源所有权、错误结果、并发/锁顺序、widget 可见性与测试是否可被错误实现通过；发现问题先补证据并修复再复跑。
4. **统一验证**：完整 Flutter 回归和独立 LCOV；Helper 两种 feature tests/clippy；Core 普通/with_gvisor 全量、目标 race 与相关 overlay 合同；变更范围 analyze、diff 检查与构建。
5. **文档和保全**：写本轮结果与模块 evidence，更新开发台账，验证仅暂存本任务文件后创建本地提交。现役包及既有原稿保持不变。新产物若构建，必须完整匹配 Core hash 绑定并放独立路径，不启动。

主要命令（真实执行时记录 exit、数量和时长）：

```powershell
E:\flutter\bin\flutter.bat test --no-pub --reporter expanded test/common/process_icon_queue_test.dart test/common/process_icon_widget_test.dart test/common/process_icon_test.dart
E:\flutter\bin\flutter.bat test --no-pub --coverage --branch-coverage --coverage-path=<本轮私有目录>/flutter-lcov.info --reporter expanded
cargo +stable test --locked --offline --features windows-service --manifest-path services/helper/Cargo.toml
cargo +stable test --locked --offline --manifest-path services/helper/Cargo.toml
cargo +stable clippy --locked --offline --features windows-service --all-targets --manifest-path services/helper/Cargo.toml -- -D warnings
# core 目录，先生成并校验 overlay
go run ./tools/mihomo-overlay
go test '-modfile=.generated/go.mod' '-overlay=.generated/mihomo-overlay.json' ./...
go test '-modfile=.generated/go.mod' '-overlay=.generated/mihomo-overlay.json' '-tags=with_gvisor' ./...
go test '-modfile=.generated/go.mod' '-overlay=.generated/mihomo-overlay.json' -race -run '^TestHealthCheck' .
```

本机 Flutter 3.47.4 / Dart 3.13.3、Go 1.25.13、Rust 1.98.1；CI Flutter 3.41.7 / Go 1.26.0 不同，需披露。本轮不把旧远端绿色 CI 当本轮验证。

## 残余风险、验证边界与恢复

- 同步 Win32 取图标若系统调用永不返回，本轮保持单槽不并发扩大损失；进程隔离与强制取消属于另一个架构任务。
- 本地测试不能证明 SCM/SYSTEM 退出时完整日志、长时 RSS/USER/GDI 曲线、所有平台图标效果或真实网络转发。未执行项目必须明确 NOT RUN。
- 新测试使用私有 evidence 目录与独立临时文件，不覆盖现役 ProgramData/AppData/日志，不额外注册服务。覆盖率只说明已执行路径；Rust 无现成 coverage 时不编造比例。
- 回滚点为上述起始提交；修复按独立提交保留，不改写历史。如后续授权运行新包，必须保留并使用完整匹配的旧包回退，不能只替换 Core/Helper 单文件。
- 原始日志/测试输出：`C:\Users\冯飏\Documents\Codex\2026-10-09\resource-followup-184840`。不得将账号、令牌、私有运行日志推至仓库。

# 性能、资源与可靠性修复汇总

日期：2026-10-09（Asia/Singapore）。修复基线：`development@a52907c2d4425f6c1679792f64a3129ae4c562d7`。

用户授权：逐项研究 TODO 的修复方案、拆解任务并实施，完成后统一打包，由用户进行本机测试。本轮按明确缺陷的快速执行模式推进；源码、隔离自动化、编译、真实平台验收分别记录。

## 结果与范围

- F01–F17 已实施源码修复并完成对应的隔离回归；P02 同步缩短原生资源持有范围。P01 仍待 NORMAL/HIGH 对照测量，没有修改进程优先级。
- [实施计划](remediation-plan-2026-10-09.md) 包含方案/任务矩阵；[完整 TODO](performance-resource-todo-2026-10-09.md) 保留所有编号、原始问题、验收要求及剩余未勾项目。
- 本轮没有运行候选客户端、替换现役版本、修改当前代理/TUN/SCM/驱动、重启 Shell 或改变用户配置。普通 Windows 预览与实机验收分别交付；未推送、未发布。
- 历史审查报告、旧包、原有 `coverage/` 和四项 QA 草稿保持保留。测试覆盖率输出写入聊天 work 的独立文件。

## 修复与验证矩阵

| 编号 | 关键实现 | 实际验证 | 主要剩余边界 |
|---|---|---|---|
| F01 | 完整 controller config、可感知重建/回滚、关闭全部 transport、清理退休 WebSocket | 完整字段、真实 router 401/200、TLS 配置、net.Pipe WebSocket、Dart 开关协议 | OS TCP/TLS/Unix/pipe 与 TLS 握手/HTTP2 |
| F02 | 下载32MiB、单文件16MiB、总128MiB/4096条、60s；原始 ZIP 预检、受限解压、同目标单飞与暂存安装 | 21项 ZIP/路径/预算/取消/损坏/已有文件保护 | 真实磁盘满、安装中途 I/O 故障 |
| F03 | Go/Rust 有界队列、写/入队期限、独立控制入场与会话所有权 | 满队列、慢读/断连、旧会话、正常大响应、并发关闭 race | 完整跨组件吞吐、长时 OS 句柄 |
| F04 | SCM 回调只入队；确认 Core 退出才停止服务，失败保留 owner/handle | stop policy、checkpoint、失败重试、start gate、日志 flush 有界 | 真实 SCM/SYSTEM Core/端口/TUN |
| F05 | 完整候选语义校验、成功提交 metadata、首次失败清理、Profile 快照一致 | 7个 Go 事务场景、Dart 快照/状态投影 | 真实监听/TUN 与上游 ApplyConfig 内部 OS 失败 |
| F06 | 请求完成立即释放 pending/default/Timer，局部 Completer 避免同步回调竞态 | 60回复、30s/2min、同步/错误/超时/迟返/断连 | 长时大快照 heap/GC |
| F07 | 当前代待刷新意图与单请求在途 | 在途启停、旧成功/失败、隐藏/恢复、dispose | 真实连接页高负载 |
| F08 | 轮询 single-flight、epoch 和 Timer 所有权 | 停止不复活、异常、恢复与交错 | Android 生命周期实机 |
| F09 | 可见/最小化/生命周期与消费者组合；保留托盘必要轮询 | UI activity、后台 snapshot、重连重申；resume 迟返代际回归 | CPU/IPC/帧耗时与真实后台流量连续性 |
| F10 | UI全局10worker去重；Core50执行+100等待；总期限/取消及history提交保护 | 大批次/忙状态/取消、6个Core场景、5个adapter合同、race | 真实大订阅网络测速和饥饿/吞吐测量 |
| F11 | RAS枚举前置、RAII、API错误与通知、严格UTF-8→UTF-16 | 2000次失败循环、启停8个错误点、Unicode/非法编码、原生编译 | 实际WinINet设置与IDN匹配 |
| F12 | UTF-8 bytes计量、10MiB/文件、最多7个、自有命名/跨日/失败退避 | 同日/跨日/旧超大文件/大队列/外来文件/确定性清理失败 | 真实磁盘或权限长时故障 |
| F13 | 认证前8连接、3s总期限、spawn前入场、退出收拢 | 隔离loopback滴流/超限/失败/恢复/收拢 | OS句柄长期趋势 |
| F14 | 两组件共享16KiB原始bytes分帧，超限持续排空、明确截断 | 巨行/无换行/UTF-8/EOF/错误/两输出流 | RSS/allocator实际峰值 |
| F15 | Android retired lease，最后迟返恰好释放JNI，停止有界 | 5项ownership及race、Android arm64 c-shared编译 | JNI/Binder实机；永不返回时不能强制free |
| F16 | 移除全桌面菜单HWND查找和100ms监视，native受管popup | widget、8组native、200次Win32菜单替换USER 1→1 | 多程序/不同权限/深浅主题真实交互 |
| F17/P02 | 取像素后同步释放Win32；Image/codec/descriptor/buffer独立finally | PNG成功/null/error释放、后续编码；新API编译 | 图标视觉、延迟编码时GDI与队列压力 |

详细方案、Red → Green 与完整命令：

- [Core](evidence/remediation-core-2026-10-09.md)
- [Agent / Helper](evidence/remediation-services-2026-10-09.md)
- [Dart 生命周期](evidence/remediation-dart-2026-10-09.md)
- [ZIP / Windows 原生 / 图像](evidence/remediation-native-ui-2026-10-09.md)

## 最终自动化执行

本地环境：Windows amd64；Flutter 3.47.4 / Dart 3.13.3；Go 1.25.13；Rust/Cargo 1.98.1；MSVC 14.44.35207 / Windows SDK 10.0.26100.0。CI 的 Flutter 3.41.7 / Go 1.26.0 与本机不同，尚未推送触发本轮远端 CI。

| 命令/范围 | 状态 / exit | 通过 / 失败 / 跳过 | 时间与说明 |
|---|---|---|---|
| `flutter test --no-pub --coverage --branch-coverage --coverage-path=<聊天work独立lcov> --reporter expanded` | PASS / 0 | 457 / 0 / 0 | 墙钟49.995s，最终完整源码 |
| 四文件ZIP/图像/托盘目标测试 | PASS / 0 | 43 / 0 / 0 | 21/3/9/10项，执行段约1s；随后包含于457全量 |
| Core `go test -modfile=... -overlay=... -coverprofile=... -json ./...` | PASS / 0 | 75 / 0 / 0 | core3.196s、tools0.342s，package时间 |
| Core 同命令 `-tags=with_gvisor` | PASS / 0 | 75 / 0 / 0 | core2.438s、tools0.237s |
| Core/route/listener/adapter 目标 `-race` | PASS / 0 | 38 / 0 / 0 | core3.293s、route1.658s、其余各1.442s |
| 独立IPC / JNI ownership `-race` | PASS / 0 | 1 / 0 / 0；5 / 0 / 0 | 2.067s；2.076s |
| Agent `cargo +stable test --locked --offline --manifest-path services/agent/Cargo.toml` | PASS / 0 | 83 / 0 / 0 | 测试3.03s |
| Helper 同类命令，`--features windows-service` | PASS / 0 | 37 / 0 / 0 | 测试1.11s |
| proxy `Run-Tests.ps1 -Mode Regression` / `NativeCompile` | PASS / 0 | 原生场景全部通过 | 1.379s / 1.649s，`/W4 /WX` |
| tray `Regression` / `NativeCompile` / `Win32` | PASS / 0 | 8组；200次替换 | 1.568s / 1.968s / 1.320s，USER 1→1 |
| M3 package tools / manifest assembly / evidence validator | PASS / 0 | 三个脚本成功 | 分别执行，未采集统一数量/时间 |
| `Test-StrictTestValidation.ps1` | PASS / 0 | 68项检查通过 | 只验包装逻辑，未执行驱动/服务安装 |
| Android arm64 `go build -tags=with_gvisor,cmfa -buildmode=c-shared` | PASS / 0 | 编译 | 不是APK或JNI设备验收 |
| Darwin arm64 `go build -tags=with_gvisor` | PASS / 0 | 交叉编译 | 没有运行产物 |

未以额外重跑覆盖旧失败记录。早期 harness、SDK/linker 路径、脚本枚举及互斥测试缓存问题均在各 evidence 中说明；目标缺陷 Red 与环境/测试自身失败分别记录。

### 静态检查与基线诊断

- 根负责的8个Dart文件：`dart analyze --format=machine ...` exit0，0 error / 0 warning / 29 info。
- Dart生命周期范围：exit2，0 error / 1 warning / 214 info。warning 为未修改的 `lib/views/proxies/providers.dart:45` 的 `invalid_null_aware_operator`；未为了变绿改无关文件或降低规则。
- Helper clippy `-D warnings` PASS；Agent clippy exit1，基线 `broker.rs:69` needless_return 与 `strict_store.rs:170` manual_div_ceil。源码基线核对证实不是本轮新增；strict-broker 依赖的既有 dead-code 警告亦保留。
- `git diff --check` PASS。新增两个dev依赖原本已在锁文件中，版本/hash不变；没有新增生产依赖。Mihomo固定版本及源hash校验保留。

### 覆盖率

最终LCOV：聊天 `work/performance-audit/remediation-final-lcov.info`，SHA256 `f50cb8e3be53659770d56dfb5c9ef549c31f9d4569ed9e8502586a132267042d`。

- 相对修复基线 diff 的**有LCOV记录的修改/新增生产Dart可执行行**：535/706 = **75.78%**；分支182/291 = **62.54%**。生成代码排除。统计脚本和逐文件未覆盖行见同目录 `Summarize-RemediationCoverage.ps1`、`remediation-final-lcov.changed.json`。
- `app_state_manager.dart`、`window_manager.dart` 没有LCOV记录，未纳入分母；上述比例不能叫做“所有改动行覆盖率”。主要缺口为实际窗口事件桥接、真实controller/UI入口、代理分组页面及Win32图标提取；widget/纯逻辑证据不替代这些平台入口。
- 全加载package口径（含generated和未涉及入口）：行5767/27947 =20.64%，分支1637/9606 =17.04%。SDK未输出BRF/BRH，分支由BRDA计数；不以全仓或局部数字相互替代。
- Core包语句40.5%，合并coverprofile语句38.3%；Go标准工具不提供分支率。ownership helper各函数100%、测速入口88.6%、IPC dispatch94.7%、writeLoop92.3%；真实平台导出路径未覆盖。
- Go1.25对overlay新增依赖文件的coverage采集报原路径缺失；依赖的测试/race通过，但其coverage为NOT AVAILABLE。Rust本机无cargo-llvm-cov，未采集覆盖率。

## 独立复核

复核后修正并验证：已接受strict事务不能因UI替换丢失结果；controller关闭须释放hijacked连接；首次setup后置失败须清理candidate；取消测速不能经共享history重新出现；Android resume迟返不能复活后台轮询；配置构造使用捕获的Profile；ZIP伪EOCD/超长名称须在decoder前拒绝；第三方插件与预置二进制来源不能标成仓库源码。

源码复核没有剩余的已确认本轮新增阻塞问题。真实OS、网络、长期资源指标仍有下述证据缺口，不能由单元测试推导为无缺陷。

## 本机验收与恢复

1. 完整解压新包到独立新目录，保留完整旧包及配置备份；免安装包仍使用既有用户配置，不是独立配置沙箱。
2. 由用户按测试安排退出当前客户端、运行新包，检查启动/停止、已保存TUN偏好、配置切换和合法外控认证。
3. 检查连接页启停/隐藏恢复、重复测速/取消/配置切换、托盘选择/取消/主题、开始按钮及其他应用菜单。
4. 按 V01–V05 固定机器/配置规模/时长，记录CPU、heap/GC、IPC、USER/GDI、句柄、goroutine；没有测量前不承诺性能百分比。
5. 回退时退出新包，从保留的完整旧包启动，保持各包内部Core/Agent/Helper/DLL配套；不删除用户数据。

NOT RUN：真实Windows交互/SCM故障/IDN匹配、长时资源曲线、Android JNI/Binder、TLS socket/HTTP2互操作、真实跨组件压力。S01开始菜单系统恢复保持独立任务；本次不宣称任务栏或开始菜单已经恢复。

## 构建与来源记录

源码修复提交后，从该精确Git archive在聊天新的构建目录完整重编Core、Agent、Helper、UI及仓库插件。第三方插件从锁定依赖重编，Flutter/QuickJS/CRT/EnableLoopback预置输入单独记录。构建脚本：聊天 `work/remediation-build-tools/Build-Remediation.ps1`，成功产物的提交、大小、hash、逐文件核验和独立产物审查在构建完成后追加。

# 运行诊断后续资源修复结果

日期：2026-10-09（Asia/Singapore）。源码基线：`development@13b0ea05dfca6840e402a1f29d543705e30382e4`。

## 结果与范围

按用户“先研究方案，再开始修复”的授权，先冻结 [方案和验收矩阵](resource-followup-plan-2026-10-09.md)，再完成 R1–R3、缺陷复现、回归和交叉审查。三项源码修复及相关隔离验证已完成；新的真实运行验收尚未执行。

| 项目 | 已实现行为 | 验证证据 |
|---|---|---|
| R1 Helper 日志 | 入口统一一个 writer；Core 退出后等待输出 producer，有限期限内 flush；I/O、排队丢失和收尾失败如实报告 | 两项有效 Red→Green、两种 feature 完整测试、service clippy；[模块报告](evidence/resource-followup-helper-2026-10-09.md) |
| R2 Windows 图标 | 1 个执行、64 个等待 key、64 个成功缓存；按消费者生命周期取消、队满自动恢复、晚结果隔离；保留 UNC 前缀避免错误共用 | 实际共享 widget 卸载 Red、UNC 碰撞 Red、22 项目标测试及完整 Flutter；[模块报告](evidence/resource-followup-icons-2026-10-09.md) |
| R3 健康检查 | 缓存跟随当前活跃节点/URL，替换旧 map；generation、stopCh 和串行 sweep 防止旧任务回填 | 15 项目标、完整 Core/gVisor/race、代际变异测试；[模块报告](evidence/resource-followup-core-2026-10-09.md) |

没有更改日志等级、进程优先级、Mihomo 固定版本、购买行为或代理/TUN策略；没有新生产依赖。原覆盖率、QA 草稿、历史工作树和旧包保留。未启动或替换当前 UI/Core/Agent/Helper，未连接第二个 UI 会话或操作 SCM/驱动/防火墙。

本轮修复的依据是源码生命周期缺陷与隔离复现。此前约11分钟运行观察未复现持续资源泄漏；它不能证明长期无泄漏，也不能将本轮缺陷直接认定为用户机器故障的原因。

## 最终执行结果

本机：Windows amd64，Flutter 3.47.4 / Dart 3.13.3、Go 1.25.13、Rust 1.98.1，MSVC 14.44.35207 / Windows SDK 10.0.26100.0。CI Flutter 3.41.7 / Go 1.26.0 与本机不同。本轮未推送，旧远端 CI 不作为当前修复证据。

原始日志：`C:\Users\冯飏\Documents\Codex\2026-10-09\resource-followup-184840`。完整命令和模块用例映射见上述三个报告；以下数量对应实际执行，不合并不同模式为一个虚构总数。

| 执行命令/范围 | 状态 / exit | PASS / FAIL / SKIP | 时间 |
|---|---|---|---|
| `flutter test --no-pub --coverage --branch-coverage --coverage-path=<evidence>/flutter-final-lcov.info --reporter expanded` | PASS / 0 | 476 / 0 / 0 | wall 122.783s；测试报告约99s |
| 三个 process_icon 目标测试文件 | PASS / 0 | 22 / 0 / 0 | wall 9.795s，随后包含于476全量 |
| 本轮 Dart 文件 `dart analyze --format=machine` | PASS / 0 | 0 error / 0 warning / 22 info | wall 15.957s |
| Helper `cargo +stable test --locked --offline --features windows-service --manifest-path services/helper/Cargo.toml` | PASS / 0 | 48 / 0 / 0 | wall 2.095s，测试1.11s |
| Helper 同命令默认 feature | PASS / 0 | 45 / 0 / 0 | wall 42.682s，测试0.25s |
| Helper service `cargo +stable clippy --locked --offline --features windows-service --all-targets --manifest-path services/helper/Cargo.toml -- -D warnings` | PASS / 0 | 静态检查 | wall 3.438s |
| Helper 额外默认 feature clippy | FAIL / 101，原有诊断 | `process_stop.rs:39` dead_code | wall 17.334s |
| Core `go test -modfile=… -overlay=… -count=1 -timeout=90s -coverprofile=… -json ./...` | PASS / 0 | 90 / 0 / 0 | core2.707s，tools0.222s |
| Core 同命令 `-tags=with_gvisor` | PASS / 0 | 90 / 0 / 0 | core2.524s，tools0.199s |
| Core `-race -run '^(TestHealthCheck\|TestConfig\|TestController)'` | PASS / 0 | 22 / 0 / 0 | core2.878s |
| 固定 overlay listener/route/adapter `-race -run '^TestFCX(Tun\|Controller\|URLTest)'` | PASS / 0 | 14 / 0 / 0 | wall12.497s |
| Windows amd64 with_gvisor 独立 Core 编译 | PASS / 0 | 编译，未运行 | 未单独计时 |
| `git diff --check` | PASS / 0 | whitespace检查 | 未单独计时 |

Go 完整命令必须从 core 目录执行，先 `go run ./tools/mihomo-overlay`；本轮生成器校验 PASS，未修改模块缓存。普通/with_gvisor 用 `CGO_ENABLED=0`，race 用 `CGO_ENABLED=1` 与 `CC=C:\msys64\ucrt64\bin\gcc.exe`。`core/state` 无测试 package 不计作 skipped 用例；`!cgo` 消息输出用例未进入 cgo race。

### 失败、修正及 Red → Green

- R1：编译成功后两个目标缺陷失败；修复后同用例及11项专用用例通过。没有将缺函数或编译失败称为 Red。
- R2：旧队列在80个组件全部卸载后仍提取80次，期望仅完成已开始的1次；修复后通过。独立审查又复现旧 UNC/rooted key 碰撞（期望2个独立加载、实际1个），修复后通过。该碰撞原本已存在，不是本轮引入的回归。
- R3：旧实现11项中8项因目标缺陷失败，3项已有契约通过；最终15项通过。临时 overlay 去掉 generation 判断后，新增消息断言按预期失败，证明测试能识别旧代事件外泄；变异没有写回生产文件或模块缓存。
- R2首次编译缺 foundation import、R3首次编译残留 unused import，均在完整回归前修复，原失败日志保留。R2恢复用例原来错误假设兄弟组件的重新请求顺序；改为各 key 恰一次和实际图标恢复，仍保留全部取消/监听释放断言，没有按 flaky 重试或降低用户行为要求。
- 默认 feature clippy 的未使用 `stop_for_service` 在修复基线已存在，本轮未修改该文件。服务模式 clippy 和两种模式的测试通过；未加 allow、降低检查或扩大范围隐藏基线诊断。
- Dart 22个 info 包含原有 native 常量弃用/IO 与部分新测试风格提示，完整列表保留，没有 error/warning 或新 discarded-future 提示。

## 覆盖率与证据边界

本轮独立 LCOV SHA256：`52eaca6e6838ce97a60126e400cfc682d5eca0653fcc89791d33dfe300514c6f`。没有覆盖原 `coverage/`。

相对基线文本 diff、含新增 lib 文件的可执行 Dart 行：**173/271（63.84%）**，分支 **74/96（77.08%）**。此口径包含 ConnectionsView 外层包装引起的既有代码缩进变化，不把它说成所有数字均为新业务逻辑。逐文件与未覆盖行见 `flutter-final-lcov.changed.json`。

| 本轮 Dart 文件 | 覆盖行/记录行 | 覆盖分支/记录分支 |
|---|---|---|
| process_icon_queue.dart | 79/79 | 42/42 |
| process_icon_activity.dart | 6/6 | 2/2 |
| process_icon.dart | 15/19 | 8/11 |
| connection/item.dart | 73/81 | 22/25 |
| connection/connections.dart | 0/86 | 0/16 |

缺口为真实 ConnectionsView 整页与窗口桥接、Win32 提取及部分平台失败入口。widget 用例直接使用共享 ProcessIcon 和 activity scope，不将其冒充真实整页/操作系统验收。

Core statement coverage 为 package42.9%、完整profile40.5%；新增 forwarder/collect/reset/touchForRun 关键函数100%，stop 函数66.7%。Go标准工具不提供本轮独立行/分支率。Rust未配置coverage工具，本轮未采集，不以用例数量代替。

## 独立审查

三模块均经非作者审查；主负责人复核最终调用链和差异。审查补强并验证了：后台 Touch 同样检查旧 run、reset旧快照在新代提交前不得发送消息、满队列取消与窗口监听释放、UNC/rooted分离、恢复测试不依赖未承诺的兄弟顺序。

未发现尚未解决的本轮 Critical/High/Medium 源码阻塞问题。已知默认 feature clippy 基线诊断、info提示和平台验收缺口保留，不等于系统已被证明无其他缺陷。

## 源码、构建与后续验收

- 本轮源码已保存为唯一 development 分支的本地提交 `485abf4d2e8664b8e03fb17ed63add2a3b2359c8`（`fix: bound residual resource lifecycles`）；本节及构建证据以后续文档提交保存，不改变包对应的源码。不创建新开发分支，不推送、不创建或合并PR、不发布。
- 精确 Git archive 完整重编 Core、Agent、Helper、UI 与原生插件，Windows 构建 exit0；独立静态产物审查8组PASS，Helper/Core hash和UI编译定义匹配。完整步骤、已知VS发现限制及组件来源见 [构建与交付证据](evidence/resource-followup-build-2026-10-09.md)。
- [Windows免安装包](../dist/FreedomCloud-windows-amd64-resourcefix-485abf4d2e86.zip) 152,994,092 bytes，73文件；[校验文件](../dist/FreedomCloud-windows-amd64-resourcefix-485abf4d2e86.zip.sha256)，SHA256 `050695fe6ad62e64f4efcb4985fd9c65f75cbf4b61b9276820087a66a1f318c5`。dist和聊天outputs副本重新计算hash一致，旧包保留；本报告此前的隔离Core WIP不作为交付整包。
- 当前运行版本没有被替换。真实SCM/SYSTEM退出、Win32压力、窗口/导航、长时RSS/USER/GDI/句柄曲线和其他平台实机：**NOT RUN**。
- 同步Win32系统调用若永不返回，本轮不能强杀；唯一执行槽仍被占用，从而不再并发扩大任务。真正强制取消需要进程隔离，不纳入此次修复。
- 运行新预览前保留完整旧包和配置；免安装包仍共享用户配置，启动具有代理/TUN副作用。由用户安排完整退出与切换，回退使用完整匹配的旧包，不混用单独Core或Helper，不删除用户数据。

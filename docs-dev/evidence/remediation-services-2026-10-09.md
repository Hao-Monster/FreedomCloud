# Agent / Helper 资源与控制可靠性修复

日期：2026-10-09。基线：`development@a52907c2d4425f6c1679792f64a3129ae4c562d7`。

本记录负责 F03 的 Agent 侧、F04、F13、F14。只修改 `services/**` 与本记录；Core 侧 F03 由并行工作负责。未运行真实客户端/服务，未操作 SCM、UAC、代理、TUN 或用户配置。原有五项未跟踪材料保持不动；提交与打包由主代理串行完成。

## 方案与任务

1. **F03**：UI socket writer 单次完整输出设置 5 秒上限；writer 故障或会话替换取消整个 handler，取消覆盖在途发送/控制等待。Core→UI relay 不等待满队列：为可靠消息保留 32/256 槽，stream 按预算丢样；可靠消息无法立即入队时记录慢消费者并终止对应 UI 会话，使未完成 RPC 通过断连明确失败，supervisor 可继续停止/重启。UI→Core 与 supervisor 入队设置 2 秒期限。先结束 writer/释放队列，再做有界后台活动通知，避免清理再次被输出阻塞。
2. **F13**：认证首行总期限 3 秒（滴流不延长）；待认证并发 8，在 spawn 前获取 permit，超额立即关闭连接；认证成功释放 permit。使用 JoinSet 收拢 handler，Agent 退出时取消并等待所有会话，writer 必须跟随 handler 释放。合法 loopback/token/单 UI 语义不变。
3. **F04**：SCM 回调仅向容量 1 的停止队列投递；异步工作循环报告 StopPending，在线程池等待实际 Core 退出。失败恢复 Running、保留进程 handle 与 owner，记录失败并支持下一次 Stop；成功关闭服务 HTTP 并报告 Stopped。停止流程持有进程状态锁并建立停止闸门，避免停止确认与新 start 竞态。不采用 Job Object：本次保留现有 Agent/Helper 后台存活语义，不能用父退出杀子掩盖未确认停止。
4. **F14**：Agent/Helper 共享有界行累积器（最多保留 16 KiB 原始 bytes），按 reader 可用片段消费，超额持续排空到换行并标记截断；UTF-8 分块不损坏合法字符，截断/非法 bytes 以替代字符处理。EOF 最后一行仍输出，读取错误交给既有日志路径；不持有整条异常日志。

## 可执行测试矩阵（实施前冻结）

| 编号 | 验收/风险 | 测试入口 | Red / Green 预期 |
|---|---|---|---|
| S03-1 | 满 UI 队列不堵可靠状态/停止流程 | Agent runtime fixture，真实 bounded mpsc | 原版可靠 relay timeout；修复版及时返回并取消旧会话 |
| S03-2 | stream 丢样不导致会话失败，正常可靠响应交付 | Agent runtime fixture | 正常入队、预留可靠容量、不重复完成 |
| S03-3 | writer 错误/写不出/替换时释放会话与队列 | 内存 duplex / 隔离 loopback | 截止时间或取消结束，旧 socket/task 收拢，新 UI 可用 |
| S03-4 | handler 在 Core queue send 中仍可被替换取消 | 隔离 loopback + 填满 Core channel | 原版旧 handler 无法结束；修复有限时间退出 |
| S13-1 | 空/半行/滴流认证在总期限结束 | 隔离 loopback | 原版仍等待；修复超时拒绝且 permit 释放 |
| S13-2 | 超额不创建无界任务；退出取消认证；错误/过长 token | 生产 accept/admission 辅助函数 + loopback | 并发≤8，过载恢复、无放宽认证 |
| S04-1 | 正常/已退出/kill错误/超时/迟后重试所有权 | ManagedProcess fixture + 实际 stop policy | 失败不报告停止成功、不丢 owner；成功才允许服务退出 |
| S04-2 | SCM 工作循环状态与重复停止 | 可注入状态/停止执行器，无 SCM 注册 | StopPending→Running(error)→StopPending→Stopped |
| S14-1 | 超长行、无换行、UTF-8跨块、EOF、错误后报告 | 共享有界累积器 + Agent async/Helper sync reader | 保留量≤16KiB、继续排空、下一行可读 |
| S14-2 | 两条输出管道同时排空 | 内存流，不启动真实 Core | 都读到后续 sentinel，有限内存 |

命令采用项目 CI：`cargo +1.98.1 test --locked --manifest-path services/agent/Cargo.toml`；`cargo +1.98.1 test --locked --features windows-service --manifest-path services/helper/Cargo.toml`。先过滤目标，再完整回归。仅新增模块定向 rustfmt，避免无关历史格式变化。平台/长时验收明确 NOT RUN。

## 执行证据

### 环境与范围

- Windows amd64；`rustc 1.98.1 (48a229cea 2026-09-01)`，`cargo 1.98.1 (797e8a9bc 2026-08-05)`。`stable` 实际指向同一 1.98.1 版本。测试均使用 `--locked --offline`；未升级依赖或锁文件。
- 初次执行 `cargo +1.98.1` 时 rustup 自动安装了具名 1.98.1 工具链（已有 stable 同版本）；随后用已验证的 `+stable` 执行。这是本轮工具链的环境变化，未操作已运行的客户端、Core、Agent 或 Helper。
- 初次链接失败是 PATH 选中了 Cygwin `link.exe`（`missing operand after ...`），不是目标测试 Red；另一个 SDK 28000 安装缺少 `um/x64/kernel32.lib`。后续仅为测试子进程指定既有 MSVC 14.44.35207 与完整 SDK 10.0.26100.0：

```powershell
$env:PATH='C:\Program Files\Microsoft Visual Studio\18\Insiders\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64;'+$env:PATH
$env:LIB='C:\Program Files\Microsoft Visual Studio\18\Insiders\VC\Tools\MSVC\14.44.35207\lib\x64;C:\Program Files (x86)\Windows Kits\10\Lib\10.0.26100.0\ucrt\x64;C:\Program Files (x86)\Windows Kits\10\Lib\10.0.26100.0\um\x64'
```

### Red → Green

| 阶段 | 命令（仓库根目录） | 状态 / 退出码 | 通过 / 失败 / 忽略 | 实际耗时与关键结果 |
|---|---|---|---|---|
| 原版 Agent 目标复现 | `cargo +stable test --locked --offline --manifest-path services/agent/Cargo.toml resource_ -- --nocapture` | FAIL / 1 | 0 / 3 / 0 | 编译 3.18s，测试 4.01s；满 UI 队列使停止状态超时；空认证等候超过 4s；日志行保留 1,048,577 bytes |
| 原版 Helper 日志复现 | `cargo +stable test --locked --offline --features windows-service --manifest-path services/helper/Cargo.toml resource_core_output -- --nocapture` | FAIL / 1 | 0 / 1 / 0 | 编译 10.05s，测试 0.01s；日志行保留 1,048,577 bytes |
| 复核发现的事务取消回归 | `cargo +stable test --locked --offline --manifest-path services/agent/Cargo.toml resource_ui_replacement_keeps_accepted_strict_mutation_consistent -- --nocapture` | FAIL / 1 | 0 / 1 / 0 | 编译 7.45s，测试 1.01s；隔离 Helper 已接受变更后换 UI，旧 handler 退出但结果未调和到 `strict_blocks` |
| 最终 Agent 目标 | `cargo +stable test --locked --offline --manifest-path services/agent/Cargo.toml resource_ -- --nocapture` | PASS / 0 | 19 / 0 / 0 | 编译 20.14s，测试 3.06s；64 个非目标测试仅因本命令过滤，完整回归见下行 |
| 最终 Agent 完整回归 | `cargo +stable test --locked --offline --manifest-path services/agent/Cargo.toml` | PASS / 0 | 83 / 0 / 0 | 编译 0.42s，测试 3.03s；main/doc tests 各 0，无忽略 |
| Helper 资源目标 | `cargo +stable test --locked --offline --features windows-service --manifest-path services/helper/Cargo.toml resource_ -- --nocapture` | PASS / 0 | 8 / 0 / 0 | 编译 9.52s，测试 1.10s |
| 最终 Helper 完整回归 | `cargo +stable test --locked --offline --features windows-service --manifest-path services/helper/Cargo.toml` | PASS / 0 | 37 / 0 / 0 | 编译 8.64s，测试 1.11s；包括最终共享缓冲容量限制 |

日志 Red 在原 reader 上仅提取同等行为测试入口，不先应用有界算法。F04 原 SCM callback 会调用 `process::exit`，没有在本机注入真实服务停止失败，也没有伪造该 callback 的动态 Red；原忽略错误后退出的路径来自源码，Green 验证提取出的实际停止策略、状态报告和所有权逻辑。

### 最终测试矩阵与覆盖边界

| 验收编号 | 实际验证 | 结果 |
|---|---|---|
| S03-1 | 满队列时 `set_status` 及时返回；`apply_supervisor_end` 的 Stop/Restart 实际 oneshot acknowledgement 完成；慢 UI 会话取消 | PASS |
| S03-2 | 大量 stream 保留 32 槽；可靠响应只交付一次；256 KiB 响应在读取正常时完整写出 | PASS |
| S03-3 | 内存 duplex writer 写超时、写错误不发送成功回执；隔离 socket 断连后可重接；队列释放 | PASS |
| S03-4 | handler 已等待满 Core channel 时换 UI，旧 handler 在 1s 内退出；首条 command 与 auth 同包不丢字节 | PASS |
| S03-5（复核新增） | 隔离 Helper 已接收 applyStrictBlock，旧 UI 被替换，旧 handler 退出后事务仍写回已确认结果；32 次后续尝试被拒绝而不创建并发变更；结束/失败后槽可重用 | PASS |
| S13-1 | 空认证和 200ms 滴流均服从 3s 总期限 | PASS |
| S13-2 | 第九个未认证连接关闭；八个名额释放后可恢复；错误/过长认证失败；关闭 accept loop 收拢全部 handler，测试确认 shared 引用收敛 | PASS |
| S04-1 | 正常、已退出、失败 kill、超时、观察失败、迟后重试；失败保留 process 与 owner，成功后 start gate 拒绝再启动 | PASS |
| S04-2 | StopPending → Running(error) → 再次 StopPending；迟后完成期间 checkpoint 增长；未确认不报告 Stopped；日志 flush 在满/关闭队列时有界返回 | PASS（无 SCM 注册） |
| S14-1 | 1 MiB 异常行及约 10 MB 无换行输入；原始缓冲 len/cap≤16 KiB，UTF-8 跨块、CRLF、空行、EOF、非法 bytes、reader 错误 | PASS |
| S14-2 | 两个异步输出流同时写过长行并保留后续 sentinel；分别排空并结束 | PASS |

### 复核修正与实现边界

- 自审发现整段 handler 取消会中断已发出的 strict apply/clear/migrate。先运行上述 Red，再把五个有副作用的 strict UI 控制统一放入**最多一个在途、无排队**的执行槽。工作项独立于 UI socket 完成既有状态调和；换 UI 不丢弃它，后续并发变更明确返回失败。Core ingress 入队同样改为 2s 上限。Helper HTTP、Broker pipe 保留原有 I/O deadline；Broker commit 原契约可等待至 300s，不能将这些需要确认的变更强行取消来制造快速成功。
- 普通会话取消仍立即释放读写 socket 与队列。可靠消息不能入队时断开对应会话，依赖 Dart 的 socket done/error 路径明确失败 pending RPC；与 Dart/Go 的集成复核由总负责人完成。本记录不单独声称端到端 UI 已验收。
- 共享日志累积器以 256 bytes 起步，按需扩容到最多 16 KiB；先分帧再解码。不把任意非法 UTF-8 的最终 String 声称为≤16 KiB：损坏字节替换最多约 3 倍原始上限，仍为固定有界。`[truncated]` 放行首，避免下游日志截断去掉标记。
- Helper 的 SCM 回调只入队。工作线程确认 Core 退出后，在同一个所有权锁设置 start gate，才终止 HTTP 与报告 Stopped；失败保留 handle/owner 并留在 Running 供重试。最终日志 flush 最多等 500ms，磁盘失败/堵塞不会被称为已落盘。
- 未引入 Job Object、网络协议变更或外部依赖；未放宽 token、loopback、owner、Helper Core hash 或 strict 认证约束。

### 静态检查

| 命令 | 结果 | 说明 |
|---|---|---|
| `cargo +stable clippy --locked --offline --features windows-service --all-targets --manifest-path services/helper/Cargo.toml -- -D warnings` | PASS / 0 | 编译检查 2.47s；测试工具总耗时 3.36s |
| `cargo +stable clippy --locked --offline --all-targets --manifest-path services/agent/Cargo.toml -- -D warnings` | FAIL / 1 | 两项基线诊断：`broker.rs:69` needless_return、`strict_store.rs:170` manual_div_ceil；均以 `git show a52907c:<path>` 核对为既有代码。没有为了变绿修改无关文件或降低门禁 |
| `git diff --check -- services` | PASS / 0 | 仅 Git 的 LF→CRLF 提示，不是 diff whitespace 错误 |

四条来自 strict-broker 依赖的既有 dead-code 警告保留并披露。只对新增共享文件和本次重写的 SCM 文件执行定向 rustfmt，没有全仓格式化。

### NOT RUN / 未证实

- 行覆盖率、分支覆盖率：NOT RUN；本机未发现 `cargo-llvm-cov`，未为本轮安装覆盖率工具。测试包含正常、失败、截止时间、并发和释放断言，不把用例数量等同覆盖率。
- 真实 Windows SCM 注册/停止、SYSTEM Core、TUN/WFP/Broker、磁盘卡死故障注入：NOT RUN；需要可恢复 VM 或单独授权环境。fixture 不证明真实 OS 服务状态。
- 真实慢 UI 与完整 Dart↔Agent↔Core 压测、长时任务/句柄/内存收敛、断网/休眠恢复：NOT RUN；本轮仅隔离 socket、duplex、state fixture 验证。
- macOS/Linux 编译运行：NOT RUN；Windows release/package 由总负责人后续统一构建，不能据此记录为本子任务已通过。
- Git：本子任务不暂存/提交/推送，由总负责人复核合并。新增 `services/shared/core_output.rs` 必须与两个 `#[path]` 引用一同进入最终提交和源包。

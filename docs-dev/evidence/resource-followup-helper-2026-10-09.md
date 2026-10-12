# R1：Helper 日志所有权与输出收尾

日期：2026-10-09（Asia/Singapore）。开发基线：`development@13b0ea05dfca6840e402a1f29d543705e30382e4`。
范围按 [冻结方案](../resource-followup-plan-2026-10-09.md) R1；本子任务仅修改 Helper 的 `main.rs`、`service/{windows,hub,logging}.rs` 及内嵌测试。

## 实现

- Windows `service_main` 和普通 `main` 各在对应进程入口创建一个 `Arc<ServiceLogger>`，通过 `run_service(logger)` 注入 HTTP routes 和 Core 输出。正常运行不再有第二个 writer。dispatcher 启动失败是独立错误路径，不与正常服务共享运行；该分支保留单独创建 logger。
- Core stdout/stderr 在线程创建前登记 producer guard。reader/管道先销毁，再归还活动计数；读取错误、unwind、未启动 closure 被丢弃都会释放计数。`thread::Builder::spawn` 失败明确记录。只保存活动计数和固定诊断状态，没有历史 JoinHandle 列表。
- 保留原 Core 退出确认与 start gate；退出确认后结束 HTTP，然后在 blocking worker 最多等输出 producer 2 秒，再写终止诊断并最多等 flush 500 毫秒。输出未排空仍尝试 flush 已排队日志，但返回明确不完整结果。
- 日志错误不撤销已经确认的 Core 退出。SCM 仍报告 Stopped，错误 exit code 和 stderr 诊断保留。Core 退出确认、失败保留 owner 的停止策略及权限保持不变。
- flush 区分队列满、writer 断开、ack 超时、文件 I/O 和已丢弃队列行。文件错误保留首个错误，队列丢失保留计数；后续文件重开或队列恢复不会使之前丢失伪装成完整成功。读取线程错误也保持可观测。
- 保持 256 槽非阻塞队列、8 MiB 文件、3 份轮转和共享 16 KiB 输出分帧。不增加依赖，不承诺 fsync/断电持久化。

## Red → Green

先将现有“写停止诊断后立即 flush”提取为生产收尾入口，保留其行为；增加独立日志路径注入点和两项测试后执行 Red。没有先实现等待算法，也没有用编译错误冒充缺陷复现。

1. 两个受控 reader 均停在输出尾部前时，原收尾返回成功：`shutdown flush completed while both Core output readers still held their tails`。
2. 普通文件占据日志父目录造成输出丢失，恢复目录后原 flush 返回成功：`reopening the file hid earlier lost output`。

Red 编译成功，测试 **0 PASS / 2 FAIL / 0 ignored**，exit **101**。实现后相同两项 **2 PASS / 0 FAIL**。补充用例后 R1 共 **11 PASS / 0 FAIL / 0 ignored**。

## 测试矩阵

| ID | 实际场景 | 结果 |
|---|---|---|
| L01 | 两个受控 Read 阻塞尾部，收尾等待；释放后 stdout/stderr sentinel 均出现在终止诊断前 | PASS |
| L02 | 无换行 EOF；20 轮两条真实 reader 线程；40 个尾部各一次、每轮结束计数归零；读取失败明确记录并归还 guard | PASS |
| L03 | 活动 guard 超过短期限：有界返回 pending=1，仍 flush 已入队日志；释放后可完成 | PASS |
| L04 | 同一个 Arc 的 service/Core 来源交错写；180-byte 测试阈值实际轮转；8条记录均恰好一次、文件不超阈值 | PASS |
| L05 | 队列满、consumer关闭、ack超时各有明确类型；发生队列丢弃后连续两次成功屏障仍报告丢失 | PASS |
| L06 | 不可用父目录恢复；真实 File 以只读方式打开造成 write 失败，随后生产 writer 重新打开成功；原丢失保持报告 | PASS |
| L07 | 既有 stop fixture 验证 Core失败仍Running并保留owner；新的纯状态用例验证日志失败仍Stopped且failed=true | PASS（无SCM注册） |
| guard异常 | panic unwind 与线程未创建时 closure被丢弃，均归还活动计数；unwind记录reader失败 | PASS（测试unwind profile） |

单 logger 的原始问题来自已核实的入口调用链，未为了动态重现运行旧服务。运行中的 SCM/SYSTEM Core 不在本组测试中。

## 命令、时间与环境

Windows amd64；`rustc 1.98.1 (48a229cea 2026-09-01)`，`cargo 1.98.1 (797e8a9bc 2026-08-05)`，`+stable` 对应上述版本。
仅测试子进程设置既有 MSVC 14.44.35207 和 Windows SDK 10.0.26100.0，未安装工具链：

```powershell
$env:PATH='C:\Program Files\Microsoft Visual Studio\18\Insiders\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64;'+$env:PATH
$env:LIB='C:\Program Files\Microsoft Visual Studio\18\Insiders\VC\Tools\MSVC\14.44.35207\lib\x64;C:\Program Files (x86)\Windows Kits\10\Lib\10.0.26100.0\ucrt\x64;C:\Program Files (x86)\Windows Kits\10\Lib\10.0.26100.0\um\x64'
```

工作目录：仓库根目录。下列 wall 时间含编译；原始输出与 `*-result.json` 位于 `C:\Users\冯飏\Documents\Codex\2026-10-09\resource-followup-184840`。

| 命令 | 状态 / exit | PASS / FAIL / ignored | wall / 测试执行 | 原始日志 |
|---|---|---|---|---|
| `cargo +stable test --locked --offline --features windows-service --manifest-path services/helper/Cargo.toml resource_r1_ -- --nocapture`（Red） | FAIL / 101 | 0 / 2 / 0 | 12.195s / 0.01s | `helper-r1-red.log` |
| 同目标命令（初次Green） | PASS / 0 | 2 / 0 / 0 | 18.283s / 0.11s | `helper-r1-green-initial.log` |
| 同目标命令（完整R1） | PASS / 0 | 11 / 0 / 0 | 12.479s / 0.12s | `helper-r1-green.log` |
| `cargo +stable test --locked --offline --features windows-service --manifest-path services/helper/Cargo.toml` | PASS / 0 | 48 / 0 / 0 | 2.095s / 1.11s | `helper-r1-full-service.log` |
| `cargo +stable test --locked --offline --manifest-path services/helper/Cargo.toml` | PASS / 0 | 45 / 0 / 0 | 42.682s / 0.25s | `helper-r1-full-default.log` |
| `cargo +stable clippy --locked --offline --features windows-service --all-targets --manifest-path services/helper/Cargo.toml -- -D warnings` | PASS / 0 | 静态检查 | 3.438s | `helper-r1-clippy-service.log` |
| `cargo +stable clippy --locked --offline --all-targets --manifest-path services/helper/Cargo.toml -- -D warnings` | FAIL / 101 | 基线dead_code | 17.334s | `helper-r1-clippy-default.log` |
| `git diff --check -- services/helper` | PASS / 0 | whitespace检查 | 未单独采集 | 仅Git LF→CRLF提示 |

默认 feature clippy 的唯一错误为未修改的 `service/process_stop.rs:39`：`stop_for_service` 在普通非service二进制中没有调用。已通过 `git show 13b0ea0:services/helper/src/service/process_stop.rs` 核对为原有代码；未扩大范围修改它、添加allow或降低 `-D warnings`。两种feature实际测试均完成。strict-broker依赖输出的4项既有dead-code warnings不是测试失败。

本轮没有环境编译失败。guard unwind用例的预期panic由catch_unwind捕获，目标 `--nocapture` 日志会打印panic hook；用例成功，不是隐藏失败。

格式化限于三个本轮文件及 hub新增段落，没有 cargo fmt 整仓修改。最后的 hub格式调整仅换行/等价match block；其后diff检查通过。

## 边界、审查与交接

- 文件测试使用 `%TEMP%/flclashx-helper-r1-*` 与既有 `%TEMP%/flclashx-helper-test-*` 独立目录；没有重定向 ProgramData/AppData、改服务配置、连接现役IPC或执行真实Core。测试释放受控reader后清理临时目录。
- logger保持单一writer；queue丢失/I/O失败状态固定大小；guard计数没有永久任务列表。自行复核未发现本次范围新增Critical/High问题，后续独立审查由主负责人安排。
- NOT RUN：真实SCM停止、SYSTEM进程/管道/继承句柄异常、真实线程创建资源耗尽、磁盘卡死、长时RSS/句柄曲线。测试模拟未启动closure的所有权释放，没有在工作站耗尽线程。release为panic=abort，异常中止不承诺清理；guard unwind证据仅覆盖可展开栈的路径。
- 行/分支覆盖率：NOT RUN；本机无已配置Rust覆盖率工具，本轮没有安装，不以用例数量充当覆盖率。
- 构建产物与现役预览不由本子任务替换。Git暂存/提交/推送由主负责人处理；本子任务没有Git写操作。

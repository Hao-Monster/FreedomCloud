# 内核升级与 TUN 可靠性验证记录

日期：2026-10-06。开发基线为 `2b587a80ad187995194608ffcd0f9f8cfa6695cd`，唯一开发分支 `development`。对应范围与任务见 `engineering/plans/kernel-tun-reliability-2026-10-06.md`。本记录随最终验证更新；隔离 Windows 运行验收尚未执行，不能称为正式发行或本机 IDE 流量问题已经解决。

## 环境与证据位置

- 本机 Windows；Flutter 3.47.4 / Dart 3.13.3，Go 1.25.13，Rust 1.98.1。CI 固定 Flutter 3.41.7、Go 1.26.0；本机通过不能替代尚未触发的云端 CI。
- Windows 编译使用既有 MSVC 14.44.35207、SDK 10.0.26100.0；race 使用既有 UCRT64 GCC。没有安装或启动代理服务、驱动，没有修改 SCM、防火墙或路由。
- 私有证据根：`C:\Users\冯飏\AppData\Local\FlClashX-Recovery\20261006-193202-kernel-tun-baseline`。原始日志与构建缓存不提交。
- 开工全 refs bundle SHA256：`7a0e04c24f1d0ff50671d0ab1ac7f0e9a1743935b4ca11457043eb876f57dcc7`。离线 mirror 恢复、`git fsck --full --strict`、开发基线与原始未跟踪文件 hash 核对通过。原有 coverage、购买测试原稿、stash、分支、工作树及旧预览包均保留。

## 测试矩阵

| 验收标准或风险 | 生产区域 | 自动化验证 | 运行验收 |
|---|---|---|---|
| 保存开启意图不等于真实开启 | Mihomo listener、Core、TunRuntime | 生命周期 fixture、Core 序列化、状态解析、组件显示 | 隔离 VM：NOT RUN |
| 创建失败、接口缺失/查询失败 | Core、应用状态 | 失败/unknown/权限 fixture，不把配置接受当成功 | 非管理员真实创建失败：NOT RUN |
| Cleanup、重复关闭、关闭失败 | listener overlay | 实际 Cleanup、错误 latch、重复清理、无假 off | 真实设备关闭故障：NOT RUN |
| 外部 PATCH 与读取并发 | listener 锁、GetTunConf | 深复制、并发 race、revision 变化 | 真实外部控制器场景：NOT RUN |
| IPC 超时/错误/无响应 | Dart IPC、Agent journal | 非空失败默认、格式错误、listener false 拒绝入 journal | 真实进程断线：NOT RUN |
| 授权取消和旧组件 | Windows prepare、Helper 兼容门禁 | 无 UAC 的依赖注入、取消后无延迟配置、hash/协议不匹配 | 用户操作 UAC、混合安装版本：NOT RUN |
| 旧回复与退出/迁移竞态 | TunRuntime、AgentConnectionCoordinator | 排队、撤销、过期响应、实际生产协调器 | 真实窗口退出/重启：NOT RUN |
| 后台只读挂接 | Agent reconcile | 已失败/停止 Core 不自动 restart；显式恢复另测 | 重开 UI 挂接已有服务：NOT RUN |
| Helper 重启后归属丢失 | Agent/Helper owned start/stop | 会话合同、真实 loopback/HTTP 路由；最终结果见下文 | SCM/Helper 重启：NOT RUN |
| 各入口与旧购买流程 | 网络设置、快捷入口、托盘、热键、购买 | 全量 Flutter，状态组件及既有购买/套餐用例 | 原生窄窗、托盘、热键：NOT RUN |
| 用户原栈和旧配置 | Core/Dart config | 保留 raw gvisor 与应用 mixed 默认，mips 解析 | 真实栈流量：NOT RUN |
| 固定依赖、补丁、同源组件 | generator、setup、CI | 输入 hash、模块校验、缓存污染拒绝、跨平台编译、包 manifest | 签名/设备安装：NOT RUN |
| 代理实际效果 | OS 路由与应用流量 | 单元测试不提供此证据 | TCP/UDP/DNS/IPv4/IPv6/Antigravity：NOT RUN |

## 已执行命令与结果

以下 Core 命令在 `core` 目录执行，先运行 `go run ./tools/mihomo-overlay`。PowerShell 对 modfile/overlay 参数整体加引号。所有 listener fixture 使用内存实现，不创建实际网卡。

| 命令/验证 | 结果 | 退出码 | 数量/耗时 |
|---|---|---:|---|
| `go test -modfile=.generated/go.mod -overlay=.generated/mihomo-overlay.json -json -count=1 ./...` | PASS | 0 | 46 个用例含子用例，35 个顶层用例；0 FAIL/0 SKIP；JSON 中无测试的包级 skip 不计为跳过用例 |
| `go test -modfile=.generated/go.mod -overlay=.generated/mihomo-overlay.json -race -run '^TestFCXTun' -count=1 github.com/metacubex/mihomo/listener` | PASS | 0 | 5 个顶层用例，3.434 秒 |
| `go test -modfile=.generated/go.mod -overlay=.generated/mihomo-overlay.json -race -run '^Test(Tun\|Core)' -count=1 .` | PASS | 0 | 2.921 秒 |
| `go build -mod=readonly -modfile=.generated/go.mod -overlay=.generated/mihomo-overlay.json -tags=with_gvisor -trimpath -o <独立输出> .`，CGO=0 | PASS | 0 | Windows amd64 11.34 秒、Windows arm64 10.51 秒、Linux amd64 9.73 秒、Darwin arm64 10.71 秒 |
| Android arm64 `go build`，CGO=1、NDK 28.0.13004108/API 21、`-buildmode=c-shared -tags=with_gvisor,cmfa` | PASS | 0 | 131.766 秒；ELF64/AArch64/DYN；18 个必需导出，20 条 extern 与现有头文件一致 |
| `flutter test --no-pub --coverage --branch-coverage --coverage-path=<私有证据>/tun-lcov.info` | PASS | 0 | 342 PASS / 0 FAIL / 0 SKIP；52 秒 |
| `dart analyze lib/controller.dart lib/common/windows_helper_compatibility.dart test/common/windows_helper_compatibility_test.dart` | PASS（有 info） | 0 | 0 error / 0 warning / 76 info；更早的全变更范围扫描同样无 error/warning，有 168 info |
| Agent 目录 `cargo test --locked --offline` | PASS | 0 | 64 PASS / 0 FAIL / 0 ignored；10.41 秒 |
| Helper 目录 `cargo test --locked --offline --features windows-service` | PASS | 0 | 29 PASS / 0 FAIL / 0 ignored；1.14 秒 |
| Helper `cargo clippy --locked --offline --all-targets --features windows-service -- -D warnings` | PASS | 0 | 3.38 秒；依赖 strict-broker 仍有 4 个既有 dead-code warnings |
| Agent `cargo clippy --locked --offline --all-targets -- -D warnings` | FAIL，既有基线 | 101 | 4.88 秒；未修改的 `broker.rs:69` needless_return、`strict_store.rs:170` manual_div_ceil |
| 两个 Rust crate `cargo fmt --all -- --check` | FAIL，既有格式差异 | 1 / 1 | 1.82 / 1.41 秒；未全仓重排格式或屏蔽规则 |
| `pwsh -File engineering/m3-test-package/tests/Test-M3PackageTools.ps1` | PASS | 0 | 2.01 秒 |
| `pwsh -File engineering/m3-test-package/tests/Test-M3ManifestAssemblyOrder.ps1` | PASS | 0 | 1.07 秒 |
| `pwsh -File engineering/m3-test-package/tests/Test-M3EvidenceValidator.ps1` | PASS | 0 | 0.86 秒 |
| `pwsh -File engineering/test-package/tests/Test-StrictTestValidation.ps1` | PASS | 0 | 68 项，3.53 秒 |
| 私有 `Test-PreviewBuildTools.ps1` | PASS | 0 | 56/56；仅临时文件 fixture |
| `go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.7 -shellcheck= -pyflakes= <三个变更 workflow>` | PASS | 0 | 外部 Shellcheck/Pyflakes 未安装，没有把它们算为通过 |
| `dart analyze setup.dart` | FAIL，既有基线 | 2 | 4 warnings + 83 infos；与基线诊断文本规范化比较 87/87 一致，新增 0 |

Core 的最终 JSON、跨平台结果保存在私有证据根。Android 证据在 `core/.generated/android-arm64-bridge-659b02dd7b7646f19e70511b79dcf1c2`，共享库 SHA256 `628e754104fbbbfd6efd7e6026cbe12806429bda12263332cbcc4670086074d2`；它是编译验证产物，不是已验收 APK。

Agent/Helper 原始命令日志和 `RESULTS.json` 位于 `services/agent/target/tun-reliability-results/`，包含 Red 记录 `listener-rejection-red.log`、`helper-capabilities-red.log`、`owned-stop-red.log`。Windows 完整包结果在构建后填入。之前的中间轮次不作为最终源码的通过证明。

## 覆盖率与证明边界

最终 `tun-lcov.info` 与机器可读 `dart-tun-verification.json` 保存于私有证据根；没有覆盖用户原有 `coverage/`。Flutter 全局行覆盖 **4507/27224 = 16.56%**，分支覆盖 **1172/9277 = 12.63%**。没有改动既有覆盖率门禁；本批没有测量 Go/Rust 覆盖率，不能将未测值当 0% 或已达标。

| 本批关键文件 | 行覆盖 | 分支覆盖 |
|---|---:|---:|
| `lib/common/tun_runtime.dart` | 93.64% | 83.93% |
| `lib/clash/agent_lifecycle.dart` | 90.91% | 83.33% |
| `lib/common/windows_helper_compatibility.dart` | 100% | 100% |
| `lib/common/windows_tun_prepare.dart` | 75% | 64.71% |
| `lib/common/tun_config_update.dart` | 100% | 66.67% |
| `lib/widgets/tun_status.dart` | 82.05% | 57.89% |
| `lib/clash/interface.dart` | 28.23% | 27.59% |

`lib/controller.dart`、`lib/clash/service.dart` 和 `lib/common/request.dart` 的真实 OS 入口在该 Flutter 测试执行中为 **0%**；`lib/state.dart` 仅 0.93%/1.97%。对抽出的生产协调器和边界函数的单测不能冒充这些入口的端到端覆盖。剩余重点是实际进程/服务连接、窗口退出重启、安装兼容检查和真实权限/路由路径；必须由后续隔离 Windows 验收补证。本次自动化通过不满足正式发布的完整运行门禁。

## Red → Green 与失败处理

- Core：真实 Cleanup 路径中配置仍 enabled 但 listener 已不存在，回归先失败，生命周期补丁后通过。默认栈回归先得到 mips，恢复原 raw gvisor 默认后通过。缺 overlay 时新增 API 无法编译；被改动或新增的生成依赖文件会触发 inventory 校验失败，不偷偷使用缓存污染后的代码。
- Agent：`startListener/stopListener` 的 `data=false` 原先仍可入 journal，目标回归先失败，严格接受条件后通过。配置接受与 listener 运行保持分离。
- Helper：真实 Warp `/capabilities` 路由从 404 的 Red 到 JSON 协议的 Green；停止确认必须等待实际子进程结束。`owned-stop-red.log` 记录重启后空 PROCESS 被误当停止成功的 Red，最终匹配归属才确认的合同 Green。Agent 真实 loopback 覆盖旧 HTTP 空 body、错误 owner、确定拒绝可重试、网络丢失保留归属、Helper 重启 unconfirmed、正确 ack 重试；无能力/缺本地凭据不发送启动或无归属关闭。

## 独立审查

跨层独立审查发现并修复：退出/清除/重启绕过 TUN 队列、自动重连与后端交接并发、只读挂接仍触发 restart、旧 Agent 在缺可靠停止合同时进入迁移、Helper 能力预检提前返回旁路、取消授权后的偏好回调再次提交、listener false 未传播、Helper 重启丢归属仍确认停止，以及会话途中换成旧 Helper 的空响应旁路。最终功能源码复核未发现剩余已知 High；这不等于未执行的实际服务/网络场景已通过。

没有关闭 TLS 校验、修改 IPC 认证、放宽文件权限、安装驱动或改动支付行为。变更源码的有限凭据模式检查未发现私钥块、GitHub/AWS/OpenAI 密钥模式；这不是完整安全扫描的替代。未运行在线依赖漏洞服务或真实网络渗透测试。
- Flutter：`tun_ipc_failure_test.dart` 的 3 个 setupConfig 失败返回空成功用例、`tun_stack_compatibility_test.dart` 的 mips 解析、`tun_runtime_test.dart` 的关闭失败被错判 off 曾实际观察到 Red，最终全量 Green。最初 Red 在工具输出中，没有另存独立原始日志，不能把后来生成的说明当原始日志。新增生命周期协调测试使用生产协调器。全量运行曾暴露日志插件未初始化及已有清理 timer 的测试环境问题，修复 fixture 后重跑；未降低业务断言或添加 skip。

## 运行验收与交付限制

没有可用且获准操作的隔离 Windows VM 信息；只读检查显示 VMware 当时没有运行中的 VM。请求已发出，未收到答复不能当授权。真实 TUN、UAC、服务交接、Helper 崩溃恢复、路由和应用流量统一为 NOT RUN。自动化证明状态机和合同的已覆盖路径，不证明所有实际网络条件。

本批完整交付目标仅为 Windows amd64 普通预览。macOS/Linux 的 Core 编译通过、Android 桥接通过不等于对应应用已构建/运行；通用 setup 的非 Windows 最终应用包还需后续补齐补丁 manifest 的最终分发位置。专用 macOS workflow 已附 manifest，但本次没有执行。未涉及正式签名、WFP 驱动或生产后端。

旧 Agent 不支持新生命周期/归属合同时拒绝自动交接，需要在批准的测试环境中退出旧后台后成套启动新版。Helper 重启丢失归属时明确报错，当前没有实现自动寻找或强制结束未知孤儿进程。

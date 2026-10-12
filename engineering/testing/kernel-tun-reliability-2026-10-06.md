# 内核升级与 TUN 可靠性验证记录

日期：2026-10-06。开发基线为 `2b587a80ad187995194608ffcd0f9f8cfa6695cd`，唯一开发分支 `development`，Windows 构建源码固定为 `f0b1b7eba271b2402a9a82809bec0ea53d9a3e8e`。对应范围与任务见 `engineering/plans/kernel-tun-reliability-2026-10-06.md`。隔离 Windows 运行验收尚未执行，不能称为正式发行或本机 IDE 流量问题已经解决。

## 环境与证据位置

- 本机 Windows；Flutter 3.47.4 / Dart 3.13.3，Go 1.25.13，Rust 1.98.1。CI 固定 Flutter 3.41.7、Go 1.26.0；本机通过不能替代尚未触发的云端 CI。
- Windows 编译使用既有 MSVC 14.44.35207、SDK 10.0.26100.0；race 使用既有 UCRT64 GCC。没有安装或启动代理服务、驱动，没有修改 SCM、防火墙或路由。
- 私有证据根：`C:\Users\冯飏\AppData\Local\FlClashX-Recovery\20261006-193202-kernel-tun-baseline`。原始日志与构建缓存不提交。
- 开工全 refs bundle SHA256：`7a0e04c24f1d0ff50671d0ab1ac7f0e9a1743935b4ca11457043eb876f57dcc7`。离线 mirror 恢复、`git fsck --full --strict`、开发基线与原始未跟踪文件 hash 核对通过。原有 coverage、购买测试原稿、stash、分支、工作树及旧预览包均保留。
- 新源码 `source-f0b1b7eba271.bundle` SHA256：`d6c11db51cf451307cfae06190dfcceea548aa9fc53b4ae9626c40b685ac2b1f`。bundle verify、离线克隆、指定 SHA detached checkout、完整 fsck 均通过。新克隆仅为构建快照，不是第二个开发分支；其本地 `core.autocrlf=false` 使用 Git 中的原始源码字节，没有更改全局 Git 设置。

## 本地提交映射

| 提交 | 范围 |
|---|---|
| `1f750b1c9e88685f0df92a92a4c0ea3bb372e379` | Mihomo 固定升级、生命周期 overlay、Core 合同、构建和 CI |
| `8bbdfc753ddb2a2dee9adc45dfe6ab1c9d687eb4` | Agent/Helper 实例、停止确认、归属协议及 Rust 回归 |
| `b3f83bbe91f880a411c795e716fc52aab63c8bad` | Flutter 状态、协调、入口和兼容门禁、组件与单元测试 |
| `f0b1b7eba271b2402a9a82809bec0ea53d9a3e8e` | 方案、测试记录和项目规则；完整包采用此干净提交 |

本批未推送、未创建或合并 PR，未改主线/远端保护，未触发共享 CI 或部署。后续仅补录构建证据的文档提交不改变包来源。

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

Agent/Helper 原始命令日志和 `RESULTS.json` 位于 `services/agent/target/tun-reliability-results/`，包含 Red 记录 `listener-rejection-red.log`、`helper-capabilities-red.log`、`owned-stop-red.log`；已另存私有证据根 `rust-tests-final/` 并核对 hash。Android 六份实际元数据另存 `android-bridge-verification/`；成功编译未生成独立 build.log，不声称存在该日志。之前的中间轮次不作为最终源码的通过证明。

## 同源码 Windows 完整预览

构建与交付：**PASS**。运行验收：**NOT RUN**。文件：

- `dist/FreedomCloud-windows-amd64-preview-f0b1b7eba271.zip`
- `dist/FreedomCloud-windows-amd64-preview-f0b1b7eba271.zip.sha256`
- `dist/FreedomCloud-windows-amd64-preview-f0b1b7eba271/`，已解压的相同内容。

ZIP 为 **152,707,168 字节**，SHA256 **`b45cf6f4f7a6e72499baedbb7e23893c694b4d9441d5ed79e966b99bdb41defb`**。73 文件的 ZIP 内容、构建目录、完整解压目录及 dist 交付副本逐文件 hash 一致；SHA256SUMS.txt 精确覆盖其余 72 文件，自身除外。旧 `863298c7e3f4` 包未覆盖。

使用私有、已验证的 `build-tools/Build-OrdinaryPreview.ps1 -Repo <干净快照> -ExpectedSha f0b1b7eba271b2402a9a82809bec0ea53d9a3e8e -Output <全新输出目录> -StandaloneClone`。它调用已提交的 setup.dart 原生构建入口；不安装或运行服务。输出日志在私有证据根 `windows-preview-f0b1b7eba271-r1/logs/steps.jsonl`，build-result.json 与 delivery-verification.json 都为 PASS。

| 实际构建步骤 | 退出码/结果 | 耗时 |
|---|---|---:|
| Core / Agent / Helper 重新编译 | 0 / PASS，各组件均来自固定源码 | 31.88 / 57.84 / 90.15 秒 |
| Flutter `--config-only` | 1 / EXPECTED_VS_DISCOVERY_FAILURE | 5.41 秒 |
| CMake configure | 0 / PASS | 6.59 秒 |
| Flutter assemble | 0 / PASS | 85.48 秒 |
| Windows 原生编译与链接 | 0 / PASS | 46.86 秒 |
| bundle-copy / package / zip-roundtrip | 0 / PASS | 1.61 / 14.71 / 13.81 秒 |

18 个步骤中 17 个 exit 0，另一个是本机已知的 VS Insiders 识别失败。保留原始失败日志，使用既有且经过检查的 CMake 3.31.6 / Ninja 流程完成配置、编译、链接和打包；没有把失败改标 exit 0，没有安装/替换 SDK 或修改源码绕过检查。完整构建来源、工具版本、输入 manifest 与时间均记录于包和私有日志中。

| 组件 | SHA256 |
|---|---|
| FlClashX.exe | `01af1b6cef4c0c11b52f2d1720fd94731c679f1740823de776412e4e6bed4679` |
| FlClashCore.exe | `743a14d0e1b9a793a83850b201d4efb6d6361eb0e34a8f98957597850235c994` |
| FlClashAgent.exe | `bd1a13f48bedf9c62c7f14bfea9301ebc7f5884bfd1ea6d2259e91c75eb3e511` |
| FlClashHelperService.exe | `13d52ee0da90021569dea45383561617304bf0d8a3515f48562fb6d2d51331da` |

Core 嵌入 `vcs.revision=f0b1b7eba271b2402a9a82809bec0ea53d9a3e8e`、`vcs.modified=false`；Helper 编译时绑定上述 Core hash，独立只读二进制检查一致。UI 的 Dart 代码 `data/app.so` 同样在完整包 SHA256 清单内。CORE-PATCH.json hash 为 `761dbdf9d3064a011c524078eab137f0edf1fa2da9aed24652344b972c08b945`；上游提交、模块 checksum、1011 个有效模块文件、6 个补丁、2 个替换源、generator/go.mod 的 hash 独立复算通过，有效模块 aggregate 为 `c316c60c9b11cc8f494749c6907a51168dba9bacfc7e5ae9a685d7dd67d26cd5`。

包是 unsigned ordinary preview，没有严格 WFP 驱动/Broker。它携带来源、补丁、组件清单、README、hash 和诊断脚本，没有打入用户配置/账号/兑换码。二进制可重现性仍需要匹配工具链与全部输入；本次只证明来源、构建及产物完整性，未声称重复构建字节完全相同。

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

后续逐项执行 `engineering/testing/kernel-tun-vm-acceptance-2026-10-06.md` 的 W01–W20，记录失败、缺环境与恢复证据。原生验收和用户业务验收未完成之前不晋级正式发行，也不能宣布 Antigravity 流量问题已解决。

本批完整交付目标仅为 Windows amd64 普通预览。macOS/Linux 的 Core 编译通过、Android 桥接通过不等于对应应用已构建/运行；通用 setup 的非 Windows 最终应用包还需后续补齐补丁 manifest 的最终分发位置。专用 macOS workflow 已附 manifest，但本次没有执行。未涉及正式签名、WFP 驱动或生产后端。

旧 Agent 不支持新生命周期/归属合同时拒绝自动交接，需要在批准的测试环境中退出旧后台后成套启动新版。Helper 重启丢失归属时明确报错，当前没有实现自动寻找或强制结束未知孤儿进程。

# Windows DoH 静默连接恢复：dohfix 预览交付

日期：2026-10-15（UTC+08）。本报告记录固定源码提交的构建、产物审计和交付；文档另行提交，不改变包内源码。前一版修复和预览仅作历史背景，见[上一份交付报告](windows-tun-wechat-preview-2026-10-14.md)。

## 交付结论与边界

- 源码固定为 `335911106ea827ae9776789c8563d0409f227a4a`，包含 `4fdf293` 的 DoH 静默连接退役修复和 `3359111` 文档。已 fetch 自有远端并回读 `freedomcloud/development`，与打包 SHA 一致；构建前 ahead/behind 为 `0/0`，没有开放的 development 晋级 PR。
- 从该提交的干净 tracked Git archive 完整新编 Core、Agent、Helper、UI AOT、runner 和仓库原生插件；第三方原生插件按锁定依赖重编。engine、QuickJS、MSVC CRT、EnableLoopback 为单独核对来源/hash 的预置输入，不声称包内全部文件从源码重建。
- r2 构建 **PASS / exit 0**；构建内 ZIP roundtrip、交付目录安全解压与逐项校验、独立静态审计 **8/8 PASS**、新增 health 补丁专项检查均通过。Helper 实际内嵌的新 Core hash 与 UI 编译输入一致，不能与旧 Core/Helper 混包。
- [CI run 38671805210](https://github.com/Hao-Monster/FreedomCloud/actions/runs/38671805210) 对应上述完整 SHA，4/4 作业 success；**Linux DoH race PASS，本机 Windows race NOT RUN**，两者不能混为一谈。
- **普通未签名 Windows amd64 预览，不含 strict WFP 驱动/Broker。候选未运行，现役客户端、服务、代理、TUN、节点选择及用户配置未操作；真实微信长时、TUN 切网/休眠和换包验收均 NOT RUN。** 静态产物通过不等于实机恢复已验收。

## 交付文件与组件

- ZIP：[FreedomCloud-windows-amd64-dohfix-335911106ea8.zip](../../dist/FreedomCloud-windows-amd64-dohfix-335911106ea8.zip)
- 校验：[同名 ZIP SHA256](../../dist/FreedomCloud-windows-amd64-dohfix-335911106ea8.zip.sha256)
- 已完整解压且校验的目录：`E:\CodeWorkstation\FlClashX\dist\FreedomCloud-windows-amd64-dohfix-335911106ea8`
- ZIP 大小：**153,567,226 bytes**。
- ZIP SHA256：`20fb8fe5c6b61515a92c444360d11b8410e4435484da620b865399982c5e7199`。
- 包共 **73 文件**；`SHA256SUMS.txt` 覆盖除自身以外的 **72 文件**。
- 应用标识 `dohfix-335911106ea8`，`APP_ENV=pre`，Core `v1.19.32`。
- Git tree：`18d4464f4adec69c037dbc3135a9b1056734664c`；源码归档 SHA256：`006576a28c0fd59ea08f1c423ec6e884cb34eb33e36bd8c43ce742006db10422`。

| 组件 | bytes | SHA256 |
| --- | ---: | --- |
| `FlClashX.exe` | 134144 | `23306cf68db81af2bd574e9b2cd894a634c04f1b7a93ef126071a9fda70b53c0` |
| `data/app.so`（Dart AOT） | 15631240 | `6ca3fddc7446bd3f1747e92b3664b08675a6e029bb6ae3e5c3352fcc1acf2155` |
| `FlClashCore.exe` | 60723712 | `821ce859950e0c33761902daa51439c3372dded01e5506c06f3fa6e8e96b7d6d` |
| `FlClashAgent.exe` | 1026048 | `9a17ef8f0df3884aff57dabde71c9fb792871922a60699babe1db0d2edcf4e8b` |
| `FlClashHelperService.exe` | 1031168 | `7b34ddd0a243a24dc4d36dea2e65ce1504822881736db667b77201562c0b5e67` |
| `CORE-PATCH.json` | 109131 | `d0ecb01482c19cfb58c812415cd0b5241e0801515fcccfe7e678c320d3e4a2d2` |

Helper 二进制实际包含上述 Core hash 1 次；UI 的 `CORE_SHA256` 编译参数与新 AOT 对应。此为构建输入和静态字节证据，没有运行 UI 读取定义值，也未据磁盘 hash 推定当前后台映像已换新。四个主 EXE 的 PE certificate table 均为空；不据此推断其他文件或外部 catalog 的信任状态。

没有覆盖旧产物。旧 `tunwechat-4e4a146513c9` ZIP 和完整目录仍在；本次 dist 清单中 `tunfix-fb6f5d43e204` 仅见校验 sidecar，不将其当作已核实可用的回退整包。既有 coverage、QA 文档/probes、stash 和历史工作树未改动。

## 构建来源与失败记录

成功工作目录：`E:\Temp\flclashx-dohfix-preview-20261015-335911106ea8-r2`，以下简称 r2。开始 `2026-10-15T03:02:11.0641022Z`，完成 `2026-10-15T03:08:59.7265651Z`，总墙钟约 **408.66s**。逐步完整命令、参数、exit、耗时见 r2 的 `build-report.json`、`logs\steps.jsonl`；dist 另有 `dohfix-build-335911106ea8.json`。

```powershell
& 'E:\Temp\flclashx-tools-pwsh-7.6.7\pwsh\pwsh.exe' -NoProfile -File `
  'E:\Temp\flclashx-tunwechat-preview-tools-20261014\Build-Remediation.ps1' `
  -ExpectedSha '335911106ea827ae9776789c8563d0409f227a4a' `
  -WorkRoot 'E:\Temp\flclashx-dohfix-preview-20261015-335911106ea8-r2' `
  -PreviewLabel 'dohfix'
```

以上是本次实际命令；脚本拒绝覆盖目录、ZIP、sidecar 和构建报告。再次重建必须另选 WorkRoot，并使用未占用的产物名称，不能原样重跑覆盖已交付包。

首次 r1：`E:\Temp\flclashx-dohfix-preview-20261015-335911106ea8-r1`，失败记录保留，未复用其输出。`backend-build` PASS / 222.047s，`flutter-assemble` FAIL / exit 1 / 133.452s，原日志为 `zone.cc: 95: error: Out of memory`、AOT snapshotter exit `-1073740791`。这属于构建环境内存不足，非产品测试断言失败；同一源码、同一工具脚本在内存改善后 r2 AOT 与完整构建通过。

接手时实测可用物理内存约 1 GiB，PID 55944 的 `uia_helper.ps1` 私有内存约 8.45 GiB。用户表示内存已足够后，再测可用物理内存 5.16 GiB、可用提交空间 7.93 GiB，随后开始 r2。未由本任务结束进程、重启插件或更改系统内存设置。r1 OOM 原因与证据如实保留，不将 r1 记为成功构建。

| r2 实际步骤 | 结果 / exit | 秒 |
| --- | --- | ---: |
| `source-archive` | PASS / 0 | 3.997 |
| `go-version` | PASS / 0 | 0.804 |
| `rust-version` | PASS / 0 | 0.227 |
| `cmake-version` | PASS / 0 | 0.155 |
| `ninja-version` | PASS / 0 | 0.025 |
| `flutter-version` | PASS / 0 | 1.888 |
| `flutter-pub-get`（offline，锁文件不变） | PASS / 0 | 56.779 |
| `backend-build`（Core → hash → Agent → 绑定 hash 的 Helper） | PASS / 0 | 129.010 |
| `flutter-config-only` | 已知 VS discovery FAIL / 1 | 2.716 |
| `cmake-configure` | PASS / 0 | 3.234 |
| `flutter-assemble`（真实 AOT） | PASS / 0 | 70.780 |
| `windows-build`（Release runner 与原生插件） | PASS / 0 | 44.222 |
| `bundle-copy`（文件组装，不是服务安装） | PASS / 0 | 2.015 |
| `tray-imports`（包含 DestroyMenu） | PASS / 0 | 0.291 |
| `package` | PASS / 0 | 18.283 |
| 构建内 `Test-ZipRoundTrip` | PASS，73 文件逐项一致 | 包含于总墙钟，未单独计时 |
| `pwsh -NoProfile -File r2\extract-delivery.ps1` | PASS / 0，73 文件逐项一致 | 函数 5.465 |
| 独立 `audit_portable_artifact.py` | PASS / 0，8/8 组，0 失败/跳过 | 4.290 |
| `python r2\verify-dohfix.py` | PASS / 0，health 映射与四 EXE 证书表 | 0.010 |

15 个构建步骤中 14 个 exit 0，1 个为原脚本精确允许的 VS discovery exit 1；无其他跳过或忽略错误。该配置错误是 `Unable to find suitable Visual Studio toolchain`，之后使用已有 MSVC/CMake/Ninja 完成真实 AOT 与 Windows 编译，不是跳过编译。第三方构建警告和四项既有 strict-broker dead_code 警告保留原日志，没有改源码压制警告。

## 工具版本与来源

本机实际版本：Flutter **3.47.4** / Dart **3.13.3**、Go **1.25.13**、Rust **1.98.1**、CMake **3.31.6**、Ninja **1.11.1.git.kitware.jobserver-1**、MSVC 工具目录 **14.44.35207**（CMake 识别 compiler **19.44.35229.0**）、Windows SDK **10.0.26100.0**、已核对 manifest 的 ATL **14.51.36237**。

- 使用便携 PowerShell **7.6.7**；ZIP `PowerShell-7.6.7-win-x64.zip` 为 106,364,316 bytes，SHA256 `d2f952ebdbf24386cb8923553aa58e41a846db35a6155ea04c58142a4b16dbb7`，本次通过 GitHub API 与[官方 release](https://github.com/PowerShell/PowerShell/releases/tag/v7.6.7) 的 asset digest 重新匹配。证据 r2 `portable-pwsh-provenance.json`。
- 本次 CI 日志实际为 Flutter **3.41.7**、Go **1.26.0**、Rust **1.98.1**。准确 Windows runner 映像 `20261007.264.1` 的[工具清单](https://github.com/actions/runner-images/blob/win25-vs2026/20261007.264/images/windows/Windows2025-VS2026-Readme.md)列 PowerShell **7.6.6**，CI 没有直接打印 `$PSVersionTable`，不将映像清单冒充运行时采样。原始依据保存在 r2 `ci-runner-powershell-image.txt`。
- 未升级项目 SDK/依赖或锁文件来抹平本机和 CI 差异。
- `Build-Remediation.ps1` SHA256：`2017fdabf73f5831c8fcc0009ed94b6c675341f143f1a26c2fd5f6a7bf7debb8`。构建工具全部文件清单在 r2 `build-tools-inventory.json`。

## 独立审计与验证矩阵

审计目录：`E:\Temp\flclashx-dohfix-artifact-audit-20261015-335911106ea8-r2`。原审计脚本保真复制，SHA256 `f2a263dd11b36199b6cc010a127a34beaf0aa0fc5dd9f24df628c6c2b8fc1d57`；结果 `artifact-audit.json`。运行环境为本机 Windows / Python 3.13，仅读取文件和 Git 对象，不执行包内二进制。

```powershell
& 'C:\Users\冯飏\AppData\Local\Programs\Python\Python313\python.exe' `
  'E:\Temp\flclashx-dohfix-artifact-audit-20261015-335911106ea8-r2\audit_portable_artifact.py' `
  --repo 'E:\CodeWorkstation\FlClashX' `
  --expected-sha '335911106ea827ae9776789c8563d0409f227a4a' `
  --build-root 'E:\Temp\flclashx-dohfix-preview-20261015-335911106ea8-r2' `
  --zip 'E:\CodeWorkstation\FlClashX\dist\FreedomCloud-windows-amd64-dohfix-335911106ea8.zip' `
  --output-json 'E:\Temp\flclashx-dohfix-artifact-audit-20261015-335911106ea8-r2\artifact-audit.json'
```

| 验收标准 / 风险 | 验证层级与用例 | 结果 |
| --- | --- | --- |
| 固定 SHA、ZIP 与 checksum 身份 | 独立静态身份/ZIP 组 | PASS：73 文件 / 72 checksum |
| 不夹带草稿或旧源码 | Git archive / blob 比对 | PASS：957 blobs、901 归档 CRLF 规范化、7 registrant 仅换行变化、0 语义源码变化 |
| 完整新编，避免混包 | 新编输出逐字节比对 | PASS：32 组件记录、4 后端产物、15 原生组件与新 AOT |
| Helper 与 UI 绑定实际新 Core | 二进制 hash 字串、UI 编译参数/AOT | PASS：Helper 内嵌 1 次，输入一致；runtime 定义值 NOT RUN |
| 第三方与预置依赖来源 | 插件输入/预置 hash | PASS：14 插件、111 输入、9 CRT 输入及 engine/QuickJS/loopback |
| 固定 Mihomo 和全部 overlay | 模板、映射、有效模块清单 | PASS：15 模板、13 映射、1017 有效模块文件 |
| 包范围与 PE/导入安全 | 静态 PE、导入和文件清单 | PASS：30 PE；仅已核对来源的 EnableLoopback 为 x86，其余 x64；无 strict 产物/用户状态文件 |
| 披露预览能力与未运行范围 | 构建步骤及包内声明 | PASS：15 步，普通未签名、配置共用/启动副作用/回退/runtime NOT RUN 明确 |
| 新 health 源文件确实进入产物 | `verify-dohfix.py` 独立补充 | PASS：模板、manifest、唯一映射、生成文件 hash 与规范化文本一致 |
| 安全解压后可交付 | `extract-delivery.ps1` | PASS：先检查路径/大小/集合再创建新目录，73 文件 hash 与 bundle 一致 |
| 静默连接恢复及并发正确性 | 固定 SHA 的 Linux CI DoH race | PASS，DNS 包 2.198s；精确命令见下文 |
| 微信长时、真实 TUN/SCM/切网/休眠 | 用户实机/隔离 VM | NOT RUN；未运行候选，未改现役环境 |

固定 Mihomo `v1.19.32` / `88dcbf7f1614a67c3b36b848ee3592dfa92ada36`。包内有效模块聚合 SHA256：`1523327a0af096901f01539594551d5d8af213547a5e9c9e41b1a96f8596f87f`。

新增 `dns/doh_health_fcx.go` 的有效文件 SHA256 为 `58451e140e0dad92916fdb57b26604e5b048a99c5be09f794df0d99dd4fbe0ad`，模板 `dns_doh_health_fcx.go.txt` SHA256 为 `cac81a4e9b11afa9c4ade79a5d8fc3b3681390fda6d00936ebe753ffc933e9f0`。两者因 CRLF/LF 字节不同，换行规范化后文本一致；manifest 中分别使用对应 hash。补充结果见 r2 `dohfix-supplemental.json`，交付解压结果见 `delivery-extraction.json`。

包内 `BUILD-INFO.txt` / `PREVIEW-README.txt` 沿用已审计模板的通用“TUN 稳定性”标题；实际本轮增量是 DoH 静默连接退役恢复，不代表修改了 TUN 驱动/栈或已证明所有微信间歇故障根因。静态审计不证明无漏洞、无资源泄漏或网络性能。

## CI、本地历史验证与未运行项

本次重新读取 CI 的 JSON 与四个作业日志，保存在 r2 的 `ci-38671805210.json`、`ci-core-116216410793.log`、`ci-windows-116216410836.log`、`ci-flutter-116216411011.log`、`ci-m3-116216410971.log`。

| 环境 / 命令 | 结果 | 数量、耗时与限制 |
| --- | --- | --- |
| Linux CI：Core 默认、`with_gvisor` 与 Tun/Controller/URLTest/DoH 四组 race | PASS | 非 verbose 包级日志，不臆造个案总数；作业约 245s |
| Linux CI：`go test -modfile=.generated/go.mod -overlay=.generated/mihomo-overlay.json -race -run '^TestFCXDoH' github.com/metacubex/mihomo/dns` | PASS | DNS 包 2.198s；Core 日志 202、221 行 |
| Windows CI：Core `with_gvisor` 和四组专项（未带 race） | PASS | DoH 包 1.244s；不创建 TUN、不安装服务 |
| Windows CI：`cargo +1.98.1 test --locked --manifest-path services/agent/Cargo.toml` | PASS | 83 通过 / 0 失败 / 0 ignored；测试 3.08s |
| Windows CI：`cargo +1.98.1 test --locked --features windows-service --manifest-path services/helper/Cargo.toml` | PASS | 48 通过 / 0 失败 / 0 ignored；测试 1.17s |
| Ubuntu CI：`flutter test` | PASS | 609 通过 / 1 跳过；run-tests 步骤约 62s |
| Windows CI：M3 四脚本 | PASS | package-tools、manifest-order、evidence 三组 PASS；Strict validation 68 cases PASS；Run PowerShell package checks 步骤约 5s |
| 本机 Windows race | NOT RUN | 交接记录的 UCRT 链接限制；本打包任务未修复工具或重跑 |
| 本机完整单测再跑 | NOT RUN | 本次为同 SHA 打包任务，读取该 SHA 已成功 CI，不将历史本地结果冒充本次执行 |

CI success 证明命令成功完成，但日志没有逐条打印数值 exit code，表中不虚构该字段。Flutter 跳过 `repair still copies binaries when its directories already exist`，原因是 Linux runner 无 `cmd.exe`（Flutter 日志 1050–1052、1062 行），不是本轮新增 skip。

交接记录及[开发台账](../development-status.md)已有本地 DoH 24 组 ×10 轮、真实 TLS/H2 黑洞探针、Core with_gvisor 和 vet PASS；本次没有重新执行这些测试。既有真实 H2 探针曾检出时间戳方案误判，改为应答计数后 PASS。该历史 Red → Green 属于源码修复阶段，本报告不把构建 OOM → 成功当作产品缺陷的 Red → Green。

本次仅新增交付文档，未改变产品源码，未采集新增 health 代码行/分支覆盖率；不能沿用前一版三方法的 87.9% 语句覆盖作为新补丁覆盖率。Go 标准覆盖工具也不直接提供分支覆盖。

## 用户换包与观察清单

1. 保留完整旧包与现有配置备份，使用上述完整新目录。免安装不等于配置隔离；完整启动会启动或接管代理，并按已保存 `tun.enable` 执行。不要单独替换 Core、Helper、Agent 或 DLL。
2. 由用户自行通过托盘“退出”旧客户端、启动新包并处理 UAC。关闭窗口不等于退出；本次自动化没有执行这些操作。
3. 开始计时前核实实际运行 UI/Core/Agent/Helper 均与新包匹配：路径、版本/PID、启动时间、服务身份及安装文件相互印证。磁盘 hash 或 UI 版本单独不足以证明后台已换新；权限不足记 unavailable，不放宽权限，也不通过 Agent IPC 补证。
4. 连续正常使用微信至少覆盖以前出现故障的时长，记录开始/异常/恢复时间、消息/图片/文件功能、TUN 状态和其他应用是否同时异常。不要记录联系人、聊天正文、账号、订阅或凭据。
5. Helper 的 Core debug 输出位于 `C:\ProgramData\FlClashX\logs\FlClashHelperService.log`，带 `Core stdout:` 前缀；关注 `[DNS][DoH] <host>`。退役之后下一次 DNS 很快成功，是恢复有效的证据；若退役次数持续快速增长，应继续调查上游/网络/节点，单凭计数不能定论。
6. 若出现组件不匹配、权限失败、反复授权或再次断网，停止本次验收并保留时间与现象。用户自行开关 TUN 或切网后，从最后一次干预后重新计时，不把干预恢复计为此前连续观察通过。切网/休眠与长时微信分别记录。
7. 回退由用户退出新包后启动已保留的完整旧 `tunwechat` 包，并再次核对后台组件；不手动覆盖系统目录单文件、不删除用户数据。若服务组件不能匹配则停止并保留证据。回退不等于旧版本没有已知问题。

| 关键日志 | 级别 | 判读 |
| --- | --- | --- |
| `retiring it, the next query reconnects (retired so far: N)` | Warn | 本轮核心信号：静默连接停止分发，下一查询重连 |
| `re-creating connection pool due to:` | Info | 传输错误触发重建 |
| `creating connection pool failed` / `re-creating connection pool failed` | Warn | 建连失败，继续检查网络与上游 |
| `answered other queries meanwhile; kept` | Debug | 请求慢，但连接同期服务了其他查询，保留 |
| `retrying on a new connection` / `reset skipped` / `failure from a replaced connection ignored` / `retired connection pool closed` | Debug | 重试、代次保护与延迟关闭的诊断细节 |

交接中的 `observe-dohfix.ps1` 本轮未启动、未修改；其 `ReadToEnd` 增量读取在大流量日志下可能占较多内存，长时观察前应改为按行流式处理或使用 `Get-Content -Wait -Tail 0 | Select-String`，并控制输出保留量。日志观察不等于微信业务验收；本次未开始任何计时观察。

## 收尾状态

源码已在自有远端且 CI 已通过；预览已构建、静态审计和完整解压校验。交付报告与台账单独本地提交，实际提交 hash 以 Git 历史为准；本任务未推送文档、未创建/合并 PR、未发布或部署。真实运行与业务验收仍待用户实测。

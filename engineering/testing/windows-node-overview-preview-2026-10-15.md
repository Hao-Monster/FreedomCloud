# 跨配置节点总览 P0：Windows 预览交付

日期：2026-10-15。本文记录推送、精确源码打包与静态验证；产品修复和本地测试详见 [P0 评审修复记录](node-overview-p0-review-2026-10-15.md)。

## 源码与交付

- 用户授权正常推送 development、打包，由用户在本机启动测试，观察方只读看日志。
- `2074cce → f6dff78c762654af1f77adfa46eed697a1492626` 的 5 个提交已推送自有 `freedomcloud/development`，远端 SHA 回读一致。未向上游 origin 推送、未晋级 main、未创建 PR/tag/release。
- 包的源提交固定为 `f6dff78c762654af1f77adfa46eed697a1492626`；Git tree `2c8eac872b965f7746b9c7dfc5d95b691615d570`。本交付文档另行提交，不改变包内源码。
- ZIP：[FreedomCloud-windows-amd64-nodeoverview-f6dff78c7626.zip](../../dist/FreedomCloud-windows-amd64-nodeoverview-f6dff78c7626.zip)，**153,831,212 bytes**。
- ZIP SHA256：`30793c99108b69fdd040253d7ea1dea4dd4dc618d870aa584080d33f0b3ffc46`，另有 [校验 sidecar](../../dist/FreedomCloud-windows-amd64-nodeoverview-f6dff78c7626.zip.sha256)。
- 完整解压目录：`E:\CodeWorkstation\FlClashX\dist\FreedomCloud-windows-amd64-nodeoverview-f6dff78c7626`；入口 `FlClashX.exe`。共 **73 文件 / 72 checksum entries**（校验清单不包含自身），交付目录已逐项核对。
- 应用标识 `nodeoverview-f6dff78c7626`，`APP_ENV=pre`，Core `v1.19.32`。普通未签名 Windows amd64 预览，不含 strict WFP 驱动/Broker。
- Core、Agent、Helper、UI AOT、runner 与仓库插件均从同一干净 tracked Git archive 新编；第三方插件从锁定依赖新编。engine、QuickJS、CRT、EnableLoopback 为独立记录来源/hash 的预置输入。逐组件证据见包内 `COMPONENTS.json`、`CORE-PATCH.json`、`BUILD-INFO.txt`。

| 关键组件 | SHA256 |
| --- | --- |
| Core | `821ce859950e0c33761902daa51439c3372dded01e5506c06f3fa6e8e96b7d6d` |
| Agent | `9dbb22553eb23f89d5f54c990f3b1b1615dee208168678ebe540732174b62e0b` |
| Helper | `ea1ccab92527a05e03365c3eca2039eb9bb101d1ec91cd38e7d4120ae9cb7226` |
| Dart AOT `data/app.so` | `5055780ec5855451c0f29f3e19f5cc175259e1ae5b7ce45a357748dbcdfb99bd` |

Core 内容与上一 DoH 包相同，仍由本轮源码新编，未复用旧包输出。Helper 二进制实际包含该 Core hash 1 次；UI 编译输入采用同一 hash。静态字节证据不等于现役后台映像已换新。

## 构建与验证矩阵

成功构建目录：`E:\Temp\flclashx-nodeoverview-preview-20261015-f6dff78c7626-r1`。开始 `2026-10-15T09:37:19.7453457Z`，完成 `2026-10-15T09:43:05.1854024Z`，约 **345.44 秒**，主命令 exit 0。逐步命令、exit、耗时见 `build-report.json`、`logs/steps.jsonl`；dist 保留 `nodeoverview-build-f6dff78c7626.json`。

```powershell
& 'E:\Temp\flclashx-tools-pwsh-7.6.7\pwsh\pwsh.exe' -NoProfile -File `
  'E:\Temp\flclashx-nodeoverview-preview-tools-20261015\Build-Remediation.ps1' `
  -ExpectedSha 'f6dff78c762654af1f77adfa46eed697a1492626' `
  -WorkRoot 'E:\Temp\flclashx-nodeoverview-preview-20261015-f6dff78c7626-r1' `
  -PreviewLabel 'nodeoverview' -FlutterRoot 'E:\CodeWorkstation\toolchains\flutter'
```

脚本拒绝覆盖既有工作目录、包与报告，重建需另选输出。复用已审计构建脚本，SHA256 `2017fdabf73f5831c8fcc0009ed94b6c675341f143f1a26c2fd5f6a7bf7debb8`；只在新工具副本中将包内标题和验收步骤改为节点总览，没有修改旧工具。源码归档 SHA256 `0863f83110c912be22986b89b7b7e7eb4e2f129d88fde813f39e6e236fdb57bd`。

| 验收标准 / 风险 | 实际验证 | 结果 |
| --- | --- | --- |
| 固定提交、不夹带草稿 | archive、Git blobs、构建后源码核对 | PASS：982 blobs；926 归档换行转换、7 registrant 仅换行、0 语义变化 |
| 完整新编与 Helper/Core 绑定 | backend-build、AOT、Windows Release、静态 hash | PASS / exit 0；130.13s、57.33s、31.67s；32 组件记录、新 AOT 与新输出一致 |
| 不混用依赖与 overlay | 独立输入来源核对 | PASS：14 插件 / 111 输入、9 CRT；15 模板 / 13 映射 / 1017 有效模块文件 |
| ZIP 可完整交付 | 构建内 roundtrip + `extract-delivery.ps1` | PASS / exit 0；73 文件逐项一致，安全解压到新目录 |
| 独立静态安全与范围 | `audit_portable_artifact.py --repo ... --expected-sha f6dff78... --build-root ... --zip ... --output-json ...` | PASS / exit 0，8/8 组、0 失败、0 跳过，4.253s；30 PE，无 strict 或用户状态文件 |
| 同提交 Linux Flutter | CI `flutter test` | PASS，731 通过 / 0 失败 / 1 跳过；job 134s |
| 同提交 Linux Core | CI 普通、with_gvisor 全量及四组 race | PASS；job 193s，包级日志不虚构个案总数 |
| 同提交 Windows Core/服务 | CI with_gvisor、四组专项、Agent/Helper contracts | PASS；Agent 83 / Helper 48，均 0 失败 / 0 ignored；job 403s |
| 同提交包工具门禁 | CI M3 四脚本 | PASS；strict validation 68 cases；job 21s |
| 现役资源与草稿保护 | 私有基线 hash、旧 ZIP hash、Git diff | PASS；5 个原始文件 hash 未变，旧 DoH ZIP hash 未变，未操作旧工作树/stash |
| 真实 Windows 窗口、接管与用户网络 | 用户实机测试 | NOT RUN（打包方未启动候选）；不能由静态包或 CI 代替 |

独立审计目录：`E:\Temp\flclashx-nodeoverview-artifact-audit-20261015-f6dff78c7626-r1`，脚本 SHA256 `f2a263dd11b36199b6cc010a127a34beaf0aa0fc5dd9f24df628c6c2b8fc1d57`，结果 `artifact-audit.json`。审计只读 Git 对象、文件和 ZIP，不执行包内程序。

固定源 [CI run 38713589918](https://github.com/Hao-Monster/FreedomCloud/actions/runs/38713589918) **4/4 jobs success**，head 完整匹配。状态及四份 job 日志保存在构建目录 `ci-evidence`。CI 未逐项打印数字 exit code，不虚构该值。唯一 Flutter skip 是 Linux 无 `cmd.exe` 的既有 `repair still copies binaries when its directories already exist`；此前本机完整 732 项无 skip 的证据见产品修复报告。Linux race 与 Windows 非 race 专项分别记录，不能混称 Windows race 已通过。

本地工具：Flutter 3.47.4 / Dart 3.13.3、Go 1.25.13、Rust 1.98.1、CMake 3.31.6、Ninja 1.11.1.git.kitware.jobserver-1、MSVC 工具目录 14.44.35207、SDK 10.0.26100.0、ATL 14.51.36237、便携 PowerShell 7.6.7。CI 明确打印 Flutter 3.41.7、Go 1.26.0；未升级依赖或锁文件抹平差异。

### 失败与未运行边界

- 15 个构建步骤中 14 个 exit 0；`flutter-config-only` 为已有 `Unable to find suitable Visual Studio toolchain` / exit 1。审计脚本精确识别该环境错误后，显式 MSVC/CMake/Ninja 配置、真实 AOT 和原生 Release 均通过，没有跳过编译。
- 开工内存不足时未运行重型编译；用户自行释放后实测可用物理内存约 6 GiB 才启动。此次 r1 全流程成功，没有 OOM 重试；上一 DoH 包的 OOM 仍为历史记录。
- 本轮没有修改产品源码，未新增产品测试/覆盖率采集，也没有把打包成功当作产品 Red→Green。既有 analyze 0 error / 11 warning / 851 info 的 exit 1 仍保留，详见产品修复报告。
- 未运行候选程序、未安装/重启服务、未改代理/TUN/节点/用户配置、未触发 UAC、未执行主动网络或 DNS 探针。未部署或正式发布。

## 用户测试与只读观察

1. 使用完整新目录；保留旧 `dohfix-335911106ea8` 整包。免安装不等于配置隔离，完整启动会启动或接管代理，并按已保存 TUN 偏好工作。由用户自行退出旧客户端、启动新包并处理必要权限。
2. 两个以上配置时检查工具栏范围切换、折叠配置摘要、宽/窄窗口、搜索/排序/只看可用；非活动配置只显示历史结果。
3. 测得成功值后取消下一次测速、隐藏窗口，确认旧好值不变；按自己的测试安排切换配置，核对结果归属和历史时间。单个无法识别节点不能拖垮其他节点。
4. 接管已有 Core 时，只有运行节点与文件可识别节点完全匹配才写历史。无可信归属或未应用更新时不写新历史。日志没有错误不能替代这项界面检查。
5. 发生异常时记录操作和时间；不收集节点、域名、订阅 URL、凭据或完整私有日志。恢复由用户退出新包后启动保留的完整旧包，不混换单个组件。

观察工具保存在 `E:\Temp\flclashx-nodeoverview-monitor-20261015-f6dff78c7626`，与产品包及 Git 源码分开。只读采样 UI / Agent / Helper 已有日志；从 EOF 建立新基线，后续按文件身份和偏移读增量，只输出固定原因、时间和计数。运行身份另用 `read-runtime.ps1` 只读查询 PID/父 PID/创建时间及路径分类，不调用产品 IPC，不用路径代替已加载二进制版本证明。

- `python -B -m unittest -v test_sample_logs.py`：本机 Windows / Python 3.13，**21 PASS / 0 FAIL / 0 SKIP，exit 0，runner 0.191s**。覆盖 EOF、增量、轮转、截断、半行、超长行、脱敏、总预算、三来源公平性、历史文件上限、失败恢复及 checkpoint 校验。观察工具没有采集覆盖率；这不是产品测试的替代。
- 基线 `2026-10-15T09:45:54.265655Z`：15 个允许日志从 EOF 起步，0 读取错误/缺口，没有回放历史日志。证据 `baseline-20261015T094554Z.json`；后续 `checkpoint.json` 与 `last-sample.json` 为有界可更新私有状态。
- 基线 UI PID19672 / Agent75972 仍来自旧 DoH 包；Helper60020 / Core56716 路径不可读。只记录该限制，不推断后台版本、不调整权限补证。
- 本对话已启用“只读观察节点总览本机测试”心跳（`automation-2`），每 5 分钟采样；有意义的变化才通知。旧 DoH 心跳已暂停，保持不动。用户结束测试或要求停止后暂停本轮观察；当前是否继续运行以应用中的自动化状态及后续对话为准。

真实运行验收仍由用户完成；静态审计不证明网络、性能、长时稳定性或全部业务路径正确。

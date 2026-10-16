# 跨配置节点总览 P1 Windows WIP 预览交付

日期：2026-10-15。用户批准完整重建；原有 Git 分工继续有效，所有成果留在工作树，没有提交、推送、fetch、切分支、暂存或重置。没有启动候选程序、调用产品 IPC，或操作现役代理、TUN、网卡、服务和权限。

## 来源与产物

- 基线：`development@e3ab52bd1afc46b009907f0ee7386fd228914d8e`，tree `73800e7f69b9c1a655386973834c9d5f8dcf4230`。基线提交不代表完整 P1 源码。
- 包类型：**WIP，普通未签名 Windows amd64 预览**。Core、Agent、Helper、Dart AOT、runner 和仓库原生插件从同一冻结工作树快照新编，第三方插件从锁定依赖重编；Flutter engine、QuickJS、CRT、EnableLoopback 是单独验证的预置输入。
- 快照 ID / inventory SHA256：`4c1df825fcf3641bb17e29443e6e6b66ea1b36b58c659186e61fca33472dc0e1`。994 文件，61,711,325 字节；984 tracked、9 个复审新增文件、1 份复审报告。42 项最终源码/测试清单全部匹配。
- 复审清单 SHA256：`aab803d18c5dbd21f85f348adc736c65c91090400d32a6647b9d4af1331ac3f8`。未将旧 QA、coverage、probes、dist、缓存或 Git 元数据纳入源码快照。
- [应用 ZIP](../../dist/FreedomCloud-windows-amd64-nodeoverview-p1-wip-4c1df825fcf3.zip)：153,961,998 字节（146.8 MiB），SHA256 **`d6139a074e46613291c7a30746d2054122061cfd0bccd76897c4a072fa2afa37`**。
- [完整解压目录](../../dist/FreedomCloud-windows-amd64-nodeoverview-p1-wip-4c1df825fcf3/)：74 文件，73 条 checksum；启动文件为该目录的 `FlClashX.exe`。必须完整使用此目录，不能混用旧 Core、Helper、Agent 或 DLL。
- [可恢复源码 ZIP](../../dist/FreedomCloud-source-nodeoverview-p1-wip-4c1df825fcf3.zip)：25,259,133 字节，SHA256 `48e0dd71c042ca2dac11504c32fa8a4d40c4866e7410f6c9407c25c8484724a8`。源码副本和安全解压恢复副本的集合、长度与 SHA256 全部一致。
- [源码证据](../../dist/nodeoverview-p1-wip-source-evidence-4c1df825fcf3/README.md)：inventory、provenance、恢复验证、快照脚本及 42 项复审清单。证据含本机路径，只作本机交接；源码 ZIP 不包含 Git 历史。
- 包内 `SOURCE-SNAPSHOT.json`、`BUILD-INFO.txt`、`COMPONENTS.json` 和 README 明确 WIP 身份；兼容字段 `sourceCommit` 仅表示基线，实际源码身份由 `sourceSnapshotId` 固定。

## 本轮构建与验证

最终构建根 `E:/Temp/fcx-p1-4c1df825-r2`，工具副本 `E:/Temp/flclashx-nodeoverview-p1-wip-tools-20261015`。2026-10-15 13:50:16.808Z 至 14:00:15.980Z，599.17 秒，主进程退出码 0；旧工具和预览没有覆盖。

构建命令（PowerShell 7.6.7）：

```powershell
& 'E:\Temp\flclashx-tools-pwsh-7.6.7\pwsh\pwsh.exe' -NoLogo -NoProfile -NonInteractive `
  -File 'E:\Temp\flclashx-nodeoverview-p1-wip-tools-20261015\Build-Remediation.ps1' `
  -ExpectedSha e3ab52bd1afc46b009907f0ee7386fd228914d8e `
  -ExpectedSnapshotId 4c1df825fcf3641bb17e29443e6e6b66ea1b36b58c659186e61fca33472dc0e1 `
  -SnapshotRoot 'E:\Temp\flclashx-nodeoverview-p1-wip-source-20261015' `
  -PreviewLabel nodeoverview-p1-wip -WorkRoot 'E:\Temp\fcx-p1-4c1df825-r2' `
  -FlutterRoot 'E:\CodeWorkstation\toolchains\flutter'
```

| 检查 | 实际结果 | 退出码 / 时间 |
|---|---|---|
| 构建脚本静态检查 | PowerShell 三文件解析 PASS；两份 Dart driver analyze 无问题；Python AST PASS；独立工具审查无阻塞 | 0 |
| 快照与恢复 | 994 文件逐项一致，42 项复审 hash 一致 | 0 / 21.379s |
| `flutter pub get --offline` | PASS，锁文件未变 | 0 / 57.122s |
| Core / Agent / Helper | PASS，全部新编；Go overlay + `-mod=readonly`，Cargo `--release --locked` 且离线 | 0 / 236.599s |
| Flutter config-only | 已知 VS 发现失败，严格匹配原有唯一错误后使用便携 CMake/MSVC 路线 | 1 / 3.253s |
| CMake configure | PASS | 0 / 5.641s |
| Flutter AOT | PASS | 0 / 92.477s |
| Native Release | PASS，runner 和插件为本次编译 | 0 / 65.553s |
| 组包 | PASS | 0 / 13.528s |
| ZIP roundtrip 与交付目录再解压 | PASS，74 文件集合/长度/hash 全部一致 | 0 |
| 独立产物静态审计 | PASS：8/8；审计 guard 8/8 | 0 / 8.424s（审计）；guard 0.037s |
| Git diff whitespace | `git --no-optional-locks diff --check` PASS；暂存区为空 | 0 |

15 个构建步骤中 14 PASS，1 个精确识别的 VS discovery 例外；后续真实 CMake/AOT/native 编译均成功，不能把 config-only 本身称为 PASS。Rust/MSVC 编译 warning 保留在日志，不声称零 warning。

本机工具链：Flutter 3.47.4 / Dart 3.13.3、Go 1.25.13、Rust 1.98.1、MSVC 14.44.35207、SDK 10.0.26100.0、ATL manifest 14.51.36237。编译并发限制为 2，没有关闭其他进程、修改权限或注册表、升级依赖。构建前后冻结输入复核通过。

### 保留的失败与比较修正

1. 首次构建 `E:/Temp/flclashx-nodeoverview-p1-wip-preview-20261015-4c1df825fcf3-r1` 在 overlay 生成目录重命名处返回 `Access is denied`，backend exit 255；Core 编译尚未开始。目标目录不存在、暂存目录为普通目录，最长目标路径 240 字符，具体拒绝原因未确定。保留全部失败证据，使用同一源码/工具在新的短路径重试成功，没有修改产品源码或系统设置；不将重试成功当作已确定根因。
2. 首次独立审计 7/8 PASS、1 FAIL：PowerShell JSON 往返把快照时间 `13:41:06.170539+00:00` 序列化为等价的 `06:41:06.170539-07:00`。审计的字符串相等判断误拒绝同一时刻。审计改为严格解析带时区时间并比较 UTC 微秒，其他字段保持精确比较；原包没有改动，首轮失败证据保留。新增 guard 证明等价时区通过，不同微秒和无时区值拒绝。
3. 增强的源码成员检查在 r2/r3 审计中分别误拒绝 Flutter 生成的跨平台文件和 Linux 插件链接。经 SDK writer 和实际集合核对，仅增加 5 个精确生成文件及 `linux/flutter/ephemeral/.plugin_symlinks` 子树识别，未放开源码目录；未知 `core/unexpected.go` 与其他链接仍拒绝。全部审计失败日志保留，最终 r4 8/8 PASS；应用 ZIP 和构建输入没有修改。

## 组件绑定与静态范围

| 组件 | SHA256 |
|---|---|
| Core | `4332fe073eb40eca2bb570ab0e442c65a49501304023348a4066133fa6a7c8e8` |
| Agent | `f02714c519ffb1b50be64aa6d09fc71e6fc2f8b06d711a692ac2d7f273244db6` |
| Helper | `6c7de7e55f652a009e831b38ee5686900353960c8dda898894c764a0ce7b89f8` |
| UI runner | `afe02479de7e5c433e297d09d9fdabae54f95f71919661cd66cf865a8d591ddc` |
| Dart AOT | `00e8b596f1dc134d5dc62420865063643fb3f0347b95fe1d5bf2ae8a436084a3` |

审计读取实际 Helper 二进制中的 Core hash，并核对 UI 实际生成编译参数及对应 AOT 输出；没有执行任何产物来查询版本。14 个插件/111 个原生输入、9 个 CRT、30 个 PE、15 个 patch 模板/13 个 overlay 映射/1017 个有效 Mihomo 模块文件均单独核验。PE 为 x64，保留与来源逐字节一致的 x86 EnableLoopback 工具；strict 驱动/Broker 不在包内。

构建、审计、日志、来源目录、运行边界是不同证据：磁盘 hash 和生成参数不能证明用户实际加载了哪些组件，也不能证明 UI 业务已验收。

最终源码审计：994 文件在构建过程中逐字节未变，0 语义变化、0 额外编译源码；对 Git base 比较时有 649 文件仅 CRLF 归一化差异，这不属于构建期间改变。生成元数据为既有 `.flutter-plugins-dependencies` 加 5 个经 SDK 确认的 Android/macOS 文件；Linux 20 个插件链接在单独的生成子树内，未纳入 Windows 编译输入。恢复 ZIP、完整源码清单与源码附件 hash 均独立复核。

## 回归证据与用户验收

产品源码本轮未改变，继续引用固定 42 文件的[复审修复报告](node-overview-p1-review-2026-10-15.md)：Flutter 全量 823 PASS、Go CGO0/gVisor 各 110 顶层+44 子例、race 28 顶层+20 子例；analyze 0 error/11 既有 warning/857 info，exit 2。**这些是打包前的复审证据，本轮没有重跑全套测试或 analyze。** 构建前后源码 hash 与这份清单一致。

用户自行测试：宽窄配置筛选和节点平铺、活动叶子只读实时延迟、非活动单节点/批量隔离测速、进度/取消、取消不覆盖历史、混合 provider 配置内联节点、受限协议提示及“最近测速”文案。P1 仅测内联节点，不下载/展开 provider；链式、重型、smux 及无法可靠回收的协议选项仍受限，严格模式不支持隔离测速。

**NOT RUN**：候选启动、真实 Windows 窗口/IPC/QuickJS、网络节点、代理/TUN、长时资源、其他平台和远端 CI。启动新包会按保存设置启动或接管代理/TUN，权限由用户自行处理。静态审计通过不是这些项目的 PASS。

旧 P0 完整包保留，ZIP SHA256 仍为 `30793c99108b69fdd040253d7ea1dea4dd4dc618d870aa584080d33f0b3ffc46`；旧 DoH 包也未改。回退使用保留的完整旧目录，不混换 DLL/Core，不删除用户数据。

## 本机证据位置

- 最终构建：[build report](../../dist/nodeoverview-p1-wip-build-4c1df825fcf3.json)；完整日志 `E:/Temp/fcx-p1-4c1df825-r2/logs`，交付解压 `delivery-extraction.json`。
- 独立审计：`E:/Temp/flclashx-nodeoverview-p1-wip-audit-20261015`，最终结果 `artifact-audit-r4.json`、`artifact-audit-r4-run-result.json` 和 `audit-guards-r7.log`；各次失败文件保持原名。[交付审计 JSON](../../dist/nodeoverview-p1-wip-artifact-audit-4c1df825fcf3.json)。
- 源快照与恢复：`E:/Temp/flclashx-nodeoverview-p1-wip-source-20261015`；已另交付源码 ZIP 与证据目录。
- 打包交付报告和开发台账是在快照冻结之后编写，不在本次构建快照内；产品源码和测试仍与 42 项复审清单一致。所有 Git 写操作继续留给技术负责人。

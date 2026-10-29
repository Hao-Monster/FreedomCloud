# Windows 微信间歇断网：DoH 恢复修复预览交付

日期：2026-10-14（UTC+08）。本报告是打包后的交付记录，不改变包内源码提交。修复范围与因果限制见[计划](../plans/windows-tun-wechat-reliability-2026-10-14.md)，Red → Green、完整命令和未运行项见[回归报告](windows-tun-wechat-reliability-2026-10-14.md)。

## 交付结论与边界

- 源码：`4e4a146513c90e18090fe87a7f9eeada501e5a71`，本地提交 `fix(core): isolate DoH recovery from expired and stale requests`；从 `development@3c48432a77971a3e0c18a26ca1c55d1632df04e6` 继续。本轮未推送、未创建 PR、未合并、未发布，因此没有本轮新 SHA 的远端 CI 结果。
- 修复两个已用相同断言重现并验证的 DoH 共享 HTTP client 恢复缺陷：请求自身过期不得销毁共享 client；旧请求迟到错误不得关闭或替换新代次。它们可能放大短暂网络故障，但尚未证明能解释全部微信公网连接超时。
- 从干净 tracked 提交的 Git archive 完整重编 Core、Agent、Helper、UI、runner 和仓库原生插件；第三方原生插件按锁定依赖重编。Flutter engine、QuickJS bridge、MSVC CRT 和 EnableLoopback 是分别记录来源/hash 的预置输入，不声称全部从源码重建。
- 构建最终 exit 0，独立静态产物审计 **8/8 PASS**。完整解压目录逐文件校验通过，原有预览、草稿、stash、历史工作树与用户配置未覆盖。
- **普通未签名 Windows amd64 预览；不含 strict WFP 驱动/Broker。候选未运行，现役 UI/Core/Agent/Helper、服务及网络配置未操作。微信长时业务、真实 TUN/SCM、切网/休眠验收均 NOT RUN。** 包内通用“TUN 稳定性”标题不表示本轮修改了 TUN 驱动/栈，也不表示微信根因已完全闭环。

## 可交付文件

完整 ZIP：

`E:\CodeWorkstation\FlClashX\dist\FreedomCloud-windows-amd64-tunwechat-4e4a146513c9.zip`

完整且已校验的解压目录：

`E:\CodeWorkstation\FlClashX\dist\FreedomCloud-windows-amd64-tunwechat-4e4a146513c9`

- ZIP 大小：**153,556,800 bytes**。
- ZIP SHA256：`db4a47bafceb0af6981c496e4d407e59ccadbdd5673af9416732dba3ef604a1f`。
- 同名 `.zip.sha256` 保留；包内 `SHA256SUMS.txt` 覆盖除自身以外的 72 个文件，共 73 个文件。
- 应用标识：`tunwechat-4e4a146513c9`；`APP_ENV=pre`，Core `v1.19.32`。
- Git tree：`7cd56ef403c76afb8c7734176f5bb507ef841a0a`。
- 源归档 SHA256：`410ceeb18a4c075fd9f05bbebe53100ddd652475baf6e2bf15a4d28d21f83e56`。

| 组件 | bytes | SHA256 |
| --- | ---: | --- |
| `FlClashX.exe` | 134144 | `46e96d8e7b293a27e3b623c4f22380328eb373651188be208e4395e40a2fb4da` |
| `data/app.so`（Dart AOT） | 15631240 | `a60a767a170a9dc7bb5dd3bd9fad6a2dda326fe5dd2b7efb1e09b43bdf903fae` |
| `FlClashCore.exe` | 60711936 | `7e7f64a63c7298595e0fda424d6b626a6c142aa350d13ecad2e934dbd37033b6` |
| `FlClashAgent.exe` | 1027072 | `6d6f81587e5fa87a3ecafeabd186705f97e281ee27987eef8a08ae9a52c28b3c` |
| `FlClashHelperService.exe` | 1031680 | `55e525266e33811f9eef4a117a2f4e3e726013cf9448e36a75f80bbd1b5e6d47` |
| `CORE-PATCH.json` | 108933 | `dad2c32f7fb26137e0153c3fa7a953d13689e67b3c1b8dcfcbce1fc815cbf0dc` |

Helper 二进制中实际嵌入的新 Core hash、UI 的 `CORE_SHA256` 编译输入及后端 manifest 一致。UI AOT 与本轮新构建输出匹配；没有运行 AOT 读取定义值，也没有据磁盘 hash 推定当前运行映像已换新。

## 构建来源、工具与过程

构建目录：`E:\Temp\flclashx-tunwechat-preview-20261014-4e4a146513c9-r1`。开始 `2026-10-14T13:21:15.0265659Z`，完成 `2026-10-14T13:32:36.004301Z`。完整命令/各步耗时/exit 在其 `build-report.json` 与 `logs\steps.jsonl`；dist 另有 `tunwechat-build-4e4a146513c9.json`。

交付解压校验结果记录在同一构建目录的 `delivery-extraction-20261014T133416.json`；使用已审查的 `Test-ZipRoundTrip` 拒绝覆盖旧目录，校验 ZIP 路径/大小/集合后解压，再逐文件比较 hash。交付文档的 7 项相关链接、6 项组件大小/hash 与工作树 whitespace 检查均通过，独立文档复核未发现必要修正。

```powershell
& 'E:\Temp\flclashx-tunwechat-preview-tools-20261014\Build-Remediation.ps1' `
  -ExpectedSha '4e4a146513c90e18090fe87a7f9eeada501e5a71' `
  -WorkRoot 'E:\Temp\flclashx-tunwechat-preview-20261014-4e4a146513c9-r1' `
  -PreviewLabel 'tunwechat'
```

工具为 Flutter 3.47.4 / Dart 3.13.3、Go 1.25.13、Rust 1.98.1、CMake 3.31.6、Ninja 1.11.1.git.kitware.jobserver-1、MSVC 工具目录 14.44.35207（CMake 识别 compiler 19.44.35229.0）、Windows SDK 10.0.26100.0、已核对 manifest 的 ATL 14.51.36237。CI 声明 Flutter 3.41.7 / Go 1.26.0；本机版本差异保留披露，没有升级 SDK/依赖或改锁文件冒充 CI 环境。

私有工具与原审计脚本均保留完整来源与 hash；本轮 `Build-Remediation.ps1` SHA256 为 `2017fdabf73f5831c8fcc0009ed94b6c675341f143f1a26c2fd5f6a7bf7debb8`，`package_driver.dart.template` 为 `5a58e4bbfcf651c1c0f00515978490d7bab80c776ead05f995e2a7dd2e82f712`。工具拒绝覆盖旧目录，并在构建期间核对源提交和 tracked 文件不变。包内来源记录见 `BUILD-INFO.txt`、`COMPONENTS.json` 和 `CORE-PATCH.json`。

| 实际步骤 | 结果 / exit | 耗时 |
| --- | --- | ---: |
| `git archive` 固定 SHA、源码清单 | PASS / 0 | 5.812s |
| `flutter pub get --offline`，锁文件未变 | PASS / 0 | 89.042s |
| Core → hash → Agent → 绑定该 hash 的 Helper | PASS / 0 | 230.950s |
| `flutter build windows --release --config-only --no-pub` | 已知 VS discovery FAIL / 1 | 3.743s |
| CMake + Ninja Multi-Config 配置 | PASS / 0 | 5.431s |
| `flutter_assemble` | PASS / 0 | 123.249s |
| Windows Release runner / 原生插件编译 | PASS / 0 | 70.219s |
| `cmake --install` 到私有 bundle（文件组装，不是服务安装） | PASS / 0 | 6.618s |
| `dumpbin /imports` 托盘销毁菜单导入 | PASS / 0 | 0.191s |
| 组件清单、文件 checksum 与 ZIP 打包 | PASS / 0 | 20.373s |
| 构建内 ZIP roundtrip | PASS | 73 文件逐项匹配 |
| 交付目录再次安全解压并逐项校验 | PASS / 0 | 73 文件逐项匹配 |
| 独立原脚本静态产物审计 | PASS / 0 | 12.36s，8/8 组 |

配置失败原文仅为 `Unable to find suitable Visual Studio toolchain. Please run flutter doctor for more details.`。脚本只对这条已审查的配置识别失败允许后续使用现有 MSVC/CMake/Ninja；真正的 Flutter AOT 和 Windows 原生编译均已执行并通过，不是跳过编译。日志保留第三方原生构建的 `/W3` 被 `/W4` 覆盖提示及四项既有 strict-broker dead_code 警告，没有为消除警告改变源码。

## 独立产物审计

证据：`E:\Temp\flclashx-tunwechat-artifact-audit-4e4a146513c9-32c56e3fe7b74da7aff5b9c93a7d7a83\artifact-audit.json`。原脚本保真复制，SHA256 `f2a263dd11b36199b6cc010a127a34beaf0aa0fc5dd9f24df628c6c2b8fc1d57`，没有执行候选程序。

| 核验组 | 结果与范围 |
| --- | --- |
| 身份 / ZIP / checksum | PASS，源 SHA/tree、73 文件、72 checksum 与 ZIP hash 一致 |
| Git archive 源码 | PASS，955 blobs；899 项归档 CRLF 规范化，7 项 registrant 仅换行变化，0 项语义源码变化 |
| 新编译输出 | PASS，32 个组件记录，4 个后端输出记录，15 个新编译原生组件及新 AOT 匹配 |
| Helper / Core / UI 绑定 | PASS，Helper 中新 Core hash 出现 1 次；UI 编译输入和对应 AOT 匹配 |
| 插件 / 预置输入来源 | PASS，14 插件 / 111 输入；9 个 CRT 输入及 engine/QuickJS/loopback 来源一致 |
| Mihomo overlay | PASS，14 模板、12 映射、1016 有效模块文件；含本轮 DoH 生产补丁及测试 |
| PE / 导入 / 包范围 | PASS，30 个 PE；只有来源一致的 EnableLoopback 为 x86，其余 x64；无 strict 产物、无用户状态文件 |
| 构建与预览声明 | PASS，15 步记录、普通未签名、共享配置/启动副作用/回退及 runtime NOT RUN 明确 |

Mihomo 固定 `v1.19.32` / `88dcbf7f1614a67c3b36b848ee3592dfa92ada36`。`dns/doh.go` 上游原 hash 为 `1ba0170bed4aabf6b295471f9fddb03da20122d339526a97170dff537fbde57b`；有效模块聚合 hash `8accf3ce58e1c9593541208294187e413a1fae34c04df0c681a65461be72bd94`。模板、生成器、上游文件及有效文件 hash 均记录，没有修改模块缓存。

静态审计证明所列身份、来源和文件一致性，不证明无漏洞/泄漏，也不能证明网络性能、当前后台映像或真实业务已经正常。

## 回归证据与未运行项

- 原始 5 项探针相同断言：2 FAIL / 3 PASS → 5 PASS。
- DNS 新回归：17 顶层组 + 2 子例通过；随机顺序重复 100 轮，共 1700 顶层组 + 200 子例执行，0 fail/skip。
- overlay 生成器 6 组 + 6 子例；Core 普通与 gVisor 各 81 组 + 17 子例；既有 TUN/controller/URLTest 专项 17 组 + 2 子例；Core/DNS vet；Agent 83 项和 Helper 48 项均通过。
- 独立源码/测试审查未发现本轮新增高置信阻塞；隔离变异删除身份 guard 或锁内取消保护后，目标测试按预期失败。
- 三个替换方法语句覆盖 51/58（87.9%），不是行/分支覆盖。覆盖率使用 1016 文件逐 hash 匹配的隔离 effective-source，规避已复现的本机 Go 1.25 overlay 插桩缺陷；未覆盖路径在回归报告逐项披露。
- Windows `-race` 两次均在现有 UCRT 链接器依赖加载阶段失败，未进入测试，故 race **NOT RUN**。本轮未修复系统工具或用重试把失败记成通过；Linux/race CI 入口已加入源码，但未推送执行。
- Flutter 源码未改，整套 Flutter 单测本轮 **NOT RUN**；本轮 UI/runner/插件的完整 Release 编译已通过，不能代替行为测试。
- Windows 实际服务更换、权限、TUN 开关/慢关闭、切网、休眠与微信长时使用，以及其他平台设备验收均 **NOT RUN**。

## 用户自行验收、停止与回退

1. 保留完整旧包和现有配置备份，使用上述完整新目录，不将单个 Core、Agent、Helper 或 DLL 混入旧目录。免安装不代表配置隔离；完整启动会启动或接管代理，并按保存的 TUN 偏好处理权限。
2. 在你决定开始时，由你通过托盘“退出”旧客户端再启动新包；关闭窗口不等于完整退出。必要的 UAC 由你处理。本轮自动化没有替你执行这些操作。
3. **计时前确认实际运行组件已匹配**：UI 的路径/版本、AOT、Core/Agent 的路径与 PID/启动时间、Helper 的服务状态/安装文件及运行身份应能互相印证。UI 版本或磁盘文件 hash 单独不足以证明后台已换新；若权限不足则记 unavailable，不放宽权限、不连接 Agent IPC 来补证。
4. 保持 TUN 开启，连续正常使用微信至少覆盖此前出现故障的时长；记录新版本、开始/结束/异常时间、消息/图片/文件功能及其他应用是否同时受影响。仅记录功能与时间，不提供聊天正文、联系人、账号、凭据、订阅或节点地址。
5. 再次断网、组件不匹配、权限失败或重复授权提示时，停止本次验收并保留现象。若你自行开关 TUN 恢复联网，分别记录操作和恢复时间；该次故障不能算通过，连续观察从最后一次干预后重新计时。不要删除网卡、强杀 Core、切驱动或制造 closeFailed。
6. 包内既有 TUN 开关/保存偏好步骤可另作功能回归，与连续微信观察分开计时。一次短时成功、网卡 Up 或自然字节增长不等于微信长时验收。
7. 如需回退，由你退出新包并使用保留的完整旧包，回退后同样核对后台组件匹配；不手动覆盖系统目录中的单文件、不删除用户数据。若服务组件不能匹配则停止并保留证据。回退仅恢复旧版本，不表示旧问题已消失。

只有在记录的运行时长和场景内完成实际测试后，才可表述“本次观察未复现”；本报告不作“微信问题彻底修复”或“实机验收通过”的结论。

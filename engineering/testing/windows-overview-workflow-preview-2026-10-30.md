# Windows 跨配置快捷工作流、订阅同步与窄窗配置选择器全组件预览交付（含 Strict WFP 驱动与 Broker）

日期：2026-10-30（Asia/Shanghai）。本报告在批次 PR 合并及预览构建完成后编写，不改变包内源码身份。

## 1. 全组件 Windows amd64 预览包（含测试签名 Strict WFP 驱动 + Broker + 客户端全栈，主推测试包）

- 源码：`main` / `development` 合并提交 `189e85f33d457fee5b736e1fe1fb1c3aa828dd2e`（PR [#62](https://github.com/Hao-Monster/FreedomCloud/pull/62)，合并范围 `842b43fea4c1a6b3fd28cbd76c00324f96916ee2..c1b1e2fa83d29ccf1f75817273cca20b505fe4eb` 共 7 个提交），Git tree `c87a43ae01264739426baa5f558d3e6db7f66eec`。从干净 tracked Git archive 构建；工作树未跟踪的 `coverage/`、QA 记录与 `probes/` 未纳入。
- 类型：**零裁剪全组件 Windows amd64（64 位）预览包**；`APP_ENV=pre`、`APP_VERSION=overview-workflow-full-189e85f33d45`、`packageVersion=0.4.2-pre+189e85f33d45`、`driverBuildId=189e85f33d457fee5b736e1fe1fb1c3a`、Core `v1.19.32`。完整包含全新编译并使用项目固定测试证书（`CN=FreedomCloud Strict WFP Test 2026`，指纹 `F48C72AD4E3D344DCCDC56107DE546CD957FC47D`，公钥 DER SHA256 `f51a4b3a8e2250b209339f852ff13c3df14a05c682de25815aafbb8731d83c36`）完成 SHA-256 Authenticode 签名的 `FlClashStrictCallout.sys`、`FlClashStrictBroker.exe`、`strict-package-manifest.json`、`FlClashCore.exe`、`FlClashAgent.exe`、`FlClashHelperService.exe`、`FlClashX.exe`，以及全部 14 个原生插件 DLL、Dart AOT、12 个严格模式部署与 M3 验收工具脚本/指南及仅含公钥的 `FreedomCloud-Strict-WFP-Test-2026.cer`（注意：测试证书签名用于完整功能/回归验证，不等同于微软 HLK/WHQL 正式商业发布门禁）。
- [全组件预览 ZIP](../../dist/FreedomCloud-windows-amd64-overview-workflow-full-189e85f33d45.zip)：167,290,816 bytes（159.54 MiB）；[SHA256 文件](../../dist/FreedomCloud-windows-amd64-overview-workflow-full-189e85f33d45.zip.sha256)。
- ZIP SHA256：`d5f19b4e62da8c042f6f3e6cd59b22087a288c90825b0be96a2cdebd52ad5194`。
- [已安全解压并校验的全组件目录](../../dist/FreedomCloud-windows-amd64-overview-workflow-full-189e85f33d45/)，入口 `FlClashX.exe`；共 87 文件，`SHA256SUMS.txt` 覆盖除自身外的 86 文件。
- [包内手工测试说明](../../dist/FreedomCloud-windows-amd64-overview-workflow-full-189e85f33d45/PREVIEW-README.txt)；[交付证据](../../dist/overview-workflow-full-189e85f33d45-evidence/delivery-summary.json)；[9 项静态审计明细](../../dist/overview-workflow-full-189e85f33d45-evidence/artifact-audit.json)。

| 组件 | bytes | 签名后 SHA256（未签名产物 SHA256 见 `COMPONENTS.json`） |
| --- | ---: | --- |
| Strict WFP 内核驱动 / `FlClashStrictCallout.sys` | 37,808 | `36639b419b05e39b93b6769ea3dd55152e56eae4e66cba65dcd94ecd9f6f2926` |
| Strict Broker 服务 / `FlClashStrictBroker.exe` | 894,896 | `41744a1831c133cefe53e75c6947711647b37da305a1ee2bbd7a6a8b23453f41` |
| 严格模式清单 / `strict-package-manifest.json` | 741 | `c67d150418e87b279cdbb85bc3dd3eb3d23bcc36b10f0bc5aee38ba66a10e43f` |
| UI runner / `FlClashX.exe` | 135,600 | `be768fcfb204b6dfc8ed80244b4e07c237bca7b8f593ffee7ce9b6fb17d776dd` |
| Dart AOT / `data/app.so` | 16,647,048 | `5ab9c1e3c79871130b3715c623cc3cb4ed3a0429afda180fdb4b155c3beed938` |
| Core / `FlClashCore.exe` | 72,388,016 | `5e3987dc5ae1b316827edc67e8e5cae12d86ed8ab78a93b2f4f9c95b3d5c5229` |
| Agent / `FlClashAgent.exe` | 1,027,504 | `d1558a8893fe220e211411f87353989d5dc2cd0a28bab312f00b399ee90bf7ca` |
| Helper / `FlClashHelperService.exe` | 1,032,624 | `a6477770dbc600ded2bac0affe71ad20f8df1bffe433059942d80d9a1d92d66b` |
| Core 补丁清单 / `CORE-PATCH.json` | 109,453 | `63b20e52be07e62864a9f318063d59c01284156b04a9a300f8648c72d212c045` |
| 测试公钥证书 / `FreedomCloud-Strict-WFP-Test-2026.cer` | 812 | `f51a4b3a8e2250b209339f852ff13c3df14a05c682de25815aafbb8731d83c36` |

静态一致性证明：
1. `FlClashCore.exe` 在编译后**先执行 Authenticode 签名**再计算 SHA256（`5e3987dc5ae1b316827edc67e8e5cae12d86ed8ab78a93b2f4f9c95b3d5c5229`），`FlClashHelperService.exe` 内嵌 `TOKEN`、Flutter UI 编译宏 `CORE_SHA256` 与 `strict-package-manifest.json` 的 `coreFileSha256` 三者与签名后的 `FlClashCore.exe` 100% 一致。
2. 6 个签名二进制（`FlClashStrictCallout.sys`、`FlClashStrictBroker.exe`、`FlClashCore.exe`、`FlClashAgent.exe`、`FlClashHelperService.exe`、`FlClashX.exe`）的所有 PE 节区原始字节与同次新鲜编译的未签名产物逐节 100% 相等，Authenticode 签名均为 `Valid`。
3. `FlClashStrictBroker.exe` 内嵌精确的 `strict-package-manifest.json` 741 字节序列，`FlClashStrictCallout.sys` 内嵌精确的 16 字节二进制 `driverBuildId`，仓库只读校验器 `Read-StrictTestPackage` 对构建目录及 `dist/` 解压目录均返回 **PASS**。

## 2. 实际构建与验证

- 全组件构建根：`E:\Temp\fcx-overview-workflow-full-189e85f3-r1`；工具：`E:\Temp\fcx-overview-strict-tools-20261030`；静态审计根：`E:\Temp\fcx-overview-strict-audit-20261030`。开始 UTC `2026-10-30T13:47:46.6299251Z`，完成 UTC `2026-10-30T14:05:41.4325470Z`，主进程 exit `0` / **PASS**。
- 源归档：`source-189e85f33d457fee5b736e1fe1fb1c3aa828dd2e.zip`，SHA256 `0adb6aba9c94bd40fec46577a533e8635380dc049a9f3f618752b4a946dc6f98`。同提交早期构建的不含驱动普通包 [`FreedomCloud-windows-amd64-overview-workflow-189e85f33d45.zip`](../../dist/FreedomCloud-windows-amd64-overview-workflow-189e85f33d45.zip)（SHA256 `048c849c80f0045f0ae0a72925ca66b69cfef0d1708acc603b9e5799fb601d43`）及所有历史预览包均保留未删改。
- 工具链：Flutter 3.47.4 / Dart 3.13.3、Go 1.26.9、Rust 1.98.1、MSBuild 17.14.60.43110（`v180` `WindowsKernelModeDriver10.0`）、MSVC 14.44.35207（含 Spectre 库）、WDK/SDK 10.0.28000.0 + NuGet 固定包 `10.0.28000.2526`（8,820 文件已盘点 hash）、用户态 Windows SDK 10.0.26100.0、SignTool 10.0.26100.0、CMake 3.31.6、Ninja 1.11.1.git.kitware.jobserver-1、ATL manifest 14.51.36237。与 CI 的 Flutter 3.41.7 / Go 1.26.0 存在版本差异并已通过两端门禁验证。
- 构建限制：MSBuild `/m:1`、CMake `parallel=1`、Cargo `jobs=1`、`GOMAXPROCS=2`、`GOFLAGS=-p=1`；依赖离线读取。未停止现役进程、未安装任何服务或内核驱动、未修改系统证书库或引导项；构建前后现役四进程 PID（`70580:FlClashAgent`、`41268:FlClashCore`、`68600:FlClashHelperService`、`69904:FlClashX`）保持一致。

实际构建命令（该 WorkRoot 和输出已存在，复建需使用新的目录和产物名）：

```powershell
& 'E:\Temp\flclashx-tools-pwsh-7.6.7\pwsh\pwsh.exe' -NoLogo -NoProfile -NonInteractive -File 'E:\Temp\fcx-overview-strict-tools-20261030\Build-FullStrictPreview.ps1' -ExpectedSha '189e85f33d457fee5b736e1fe1fb1c3aa828dd2e' -PreviewLabel 'overview-workflow-full' -WorkRoot 'E:\Temp\fcx-overview-workflow-full-189e85f3-r1'
```

| 检查 | 结果与边界 |
| --- | --- |
| 远端 PR 与合并后 GitHub Actions CI | **PASS**（PR [#62](https://github.com/Hao-Monster/FreedomCloud/pull/62) head `c1b1e2f`：[push `41057617527`](https://github.com/Hao-Monster/FreedomCloud/actions/runs/41057617527) / [PR `41057630162`](https://github.com/Hao-Monster/FreedomCloud/actions/runs/41057630162) 4/4 PASS；合并提交 `189e85f33d45`：[main `41058460352`](https://github.com/Hao-Monster/FreedomCloud/actions/runs/41058460352) / [development `41058476276`](https://github.com/Hao-Monster/FreedomCloud/actions/runs/41058476276) 4/4 PASS） |
| 独立代码与治理审查 | **PASS / APPROVE**（晋级前独立审查覆盖全量 diff 及 `Flutter 3.41.7` 标签源码 API 对照，`0 P1 / 0 P2 / 3 P3`） |
| Strict WFP 内核驱动编译与静态规则门禁 | **PASS**（8.40s；`/W4 /WX`、`/Qspectre`、`/guard:cf`、`/INTEGRITYCHECK`、`KMDF 1.21`、`DriverMinimumRules` + `ApiValidator` 0 警告 0 错误，测试证书签名 Valid） |
| Core 编译签名 → Agent/Helper 编译签名 → Manifest → StrictBroker 编译签名 | **PASS**（Core 49.49s + 签名 1.78s；Agent/Helper 412.90s + 签名 2.59s；`New-M3PackageManifest.ps1` 1.98s；StrictBroker 94.90s + 签名 1.40s） |
| Flutter Dart AOT + Windows runner / 14 个原生插件 + UI 签名 | **PASS**（AOT 98.27s；C++ Release 118.02s；`FlClashX.exe` 签名 1.34s） |
| 组包、`Read-StrictTestPackage` 只读门禁、ZIP roundtrip 与 `dist/` 解压校验 | **PASS**（87 文件逐项一致，`Read-StrictTestPackage` 构建态与解压态双 **PASS**） |
| 独立 9 项全组件静态产物审计 | **PASS / 9/9**（1,017 Git blobs、8,820 WDK 包文件、6 个签名二进制 PE 节区逐字节比对、Authenticode 与九字段清单契约、Helper/UI Core 绑定、Mihomo `v1.19.32` overlay、32 个 PE/驱动子系统/托盘 `DestroyMenu` 导入、12 个支持脚本及披露） |
| 同源码本地测试与静态分析 | 节点总览套件 144/144 PASS（含 `440x820 @ 2x` 合成渲染 3/3 PASS）；全仓 1,012/1,012 PASS；M3 包门禁 68/68 PASS；`dart analyze` 0 error / 0 warning |
| 真实窗口/IPC、系统凭据库、代理/TUN/严格驱动加载与流量、真实发卡消费 | **NOT RUN**；由用户手工测试，不能用单元/CI/静态通过替代 |

## 3. 两种手工测试模式、范围与已知限制

- **模式 A（直接免安装启动：测试 UI、跨配置订阅更新、三步工作流、窄窗配置选择器、普通代理与 TUN）**：当本机未注册 `C:\Program Files\FlClashX Service\FlClashStrictBroker.exe` 时，先从现役旧客户端托盘选择“退出”，再直接启动新解压目录的 [`FlClashX.exe`](../../dist/FreedomCloud-windows-amd64-overview-workflow-full-189e85f33d45/FlClashX.exe)，客户端会自动调用同目录已签名且哈希匹配的 `FlClashAgent.exe` + `FlClashCore.exe` 运行，无需开启 Windows `testsigning` 或安装内核驱动即可在当前 Windows 64 位电脑上测试全部 UI、节点测速、TUN 与购买兑换流程。
- **模式 B（Strict WFP 内核驱动 `FlClashStrictCallout.sys` + `FlClashStrictBroker` 完整测试）**：包内已完整附带 `FlClashStrictCallout.sys`、`FlClashStrictBroker.exe`、`strict-package-manifest.json`、`Initialize-StrictTest.ps1`、`StrictTest.Validation.ps1`、`FreedomCloud-Strict-WFP-Test-2026.cer` 及 M3 验收脚本。由于驱动采用测试证书签名（非微软 HLK 商业发布签名），Windows 内核要求在**预先拍好可恢复快照的 Windows 11 x64 虚拟机**（或做好完整系统备份并显式传入 `-ConfirmTestMachine -AllowPhysicalTestHost` 的专用实体测试机；切勿在无快照备份的日常开发机直接执行，因 `Initialize-StrictTest.ps1` 失败时不会自动破坏性回滚系统目录）中先导入 `FreedomCloud-Strict-WFP-Test-2026.cer` 至 `Cert:\LocalMachine\Root` 与 `Cert:\LocalMachine\TrustedPublisher`，开启 `bcdedit /set testsigning on` 重启后，以管理员 PowerShell 7.2+ 运行 `.\Initialize-StrictTest.ps1 -ConfirmTestMachine` 注册启动内核驱动与 Broker 服务，再启动同目录 `FlClashX.exe` 按 [`REAL-WINDOWS11-TEST-GUIDE.md`](../../dist/FreedomCloud-windows-amd64-overview-workflow-full-189e85f33d45/REAL-WINDOWS11-TEST-GUIDE.md) 验收。
- **已知限制**：生产 HTTP CONNECT 路径仍继承全局 `badCertificateCallback => true`，未信任或主机名不匹配证书会被接受；这是已有行为，本包未修复，也不声明生产 CONNECT 完整 TLS 安全验收通过。
- **回退**：模式 A 直接从托盘退出新包并启动保留的完整旧包；模式 B 测试结束后直接恢复测试机快照或备份，不混换单个 EXE/DLL/SYS。

历史可用包 [`FreedomCloud-windows-amd64-overview-sub-a8dc8bfc102e.zip`](../../dist/FreedomCloud-windows-amd64-overview-sub-a8dc8bfc102e.zip)（SHA256 `9fa38b8fe63df2fc133ae77b57f6c5339b4e43c2a6eea9a4b7a168a3f0074c95`）、[`FreedomCloud-windows-amd64-purchase-v2-8a666bb01005.zip`](../../dist/FreedomCloud-windows-amd64-purchase-v2-8a666bb01005.zip)（SHA256 `1fd3a06fdc360b2185d1bacde4186158250d27b1a6415ff899c45a1c0552c2ad`）与 [`FreedomCloud-windows-amd64-country-tls-159f16eecc78.zip`](../../dist/FreedomCloud-windows-amd64-country-tls-159f16eecc78.zip)（SHA256 `98d8a7a9ef7160af5f3148d5dfe8a260d78441968750cea5e6ae6825f966c2b8`）及对应解压目录完整保留。

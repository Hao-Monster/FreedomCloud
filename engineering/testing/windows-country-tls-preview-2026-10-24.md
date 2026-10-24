# Windows 国家筛选与 TLS 清理预览交付

日期：2026-10-24（Asia/Singapore）。本报告在构建完成后编写，不改变包内源码身份。

## 交付与来源

- 源码：`development@159f16eecc7863f163cf22b0eec4ad0e86fb321b`，Git tree `17f50d97eafbad3cffde3ebeff09984fc2c0f22c`。从干净 tracked Git archive 构建；现有 coverage、QA、probes 未纳入。构建前 fetch 后领先 `freedomcloud/development` 10 个提交，落后 0，无开放 PR；未推送、未创建 PR。
- 类型：普通未签名 Windows amd64 免安装预览；`APP_ENV=pre`、`APP_VERSION=country-tls-159f16eecc78`、Core `v1.19.32`。不包含 strict WFP 驱动/Broker。
- [预览 ZIP](../../dist/FreedomCloud-windows-amd64-country-tls-159f16eecc78.zip)：165,987,494 bytes（158.3 MiB）；[SHA256 文件](../../dist/FreedomCloud-windows-amd64-country-tls-159f16eecc78.zip.sha256)。
- ZIP SHA256：`98d8a7a9ef7160af5f3148d5dfe8a260d78441968750cea5e6ae6825f966c2b8`。
- [已安全解压并校验的完整目录](../../dist/FreedomCloud-windows-amd64-country-tls-159f16eecc78/)，入口 `FlClashX.exe`；共 73 文件，`SHA256SUMS.txt` 覆盖除自身外的 72 文件。
- [包内手工测试说明](../../dist/FreedomCloud-windows-amd64-country-tls-159f16eecc78/PREVIEW-README.txt)；[交付证据](../../dist/country-tls-159f16eecc78-evidence/delivery-summary.json)。

UI、Core、Agent、Helper 与仓库原生插件从同一提交新编。第三方插件从锁定依赖重编；Flutter engine、QuickJS、MSVC CRT 和 EnableLoopback 为核对来源及 hash 的预置输入，不声称所有文件从源码重建。

| 组件 | bytes | SHA256 |
| --- | ---: | --- |
| UI runner / `FlClashX.exe` | 134,144 | `363c94dfd2d20e4d27f1fd8ef8ac3bbe41d21217578c706ac3f95fa76382817b` |
| Dart AOT / `data/app.so` | 16,384,904 | `929f30c9d2625f5988fa68e499f738ba8013ff070c0344fb4d0e9c2e09534918` |
| Core / `FlClashCore.exe` | 72,386,560 | `59dbcacc38720b7ea004bbb77e7aa45ddabc14648afb1cda3c7c8c1b52f98a2a` |
| Agent / `FlClashAgent.exe` | 1,026,048 | `e52347d98d3509fec55484ebac229572e0ae384139d57f9bf5df8aa7dad0146a` |
| Helper / `FlClashHelperService.exe` | 1,031,168 | `1012eeb6e288340959d4a6e6eb20e7ec755554ba930a5252185e031dff2f2c34` |

Helper 实际二进制包含本次 Core hash 1 次；UI 实际生成编译参数 `CORE_SHA256` 与新 AOT 对应。该结论是静态绑定证据，不是运行时组件接管验收。

## 实际构建与验证

- 构建根：`E:\Temp\fcx-country-159f16e-r1`；工具：`E:\Temp\fcx-country-tools-20261024`。开始 UTC `2026-10-24T08:28:09.1034897Z`，完成 UTC `2026-10-24T08:51:54.3450887Z`，主进程 exit 0 / PASS。
- 源归档：`source-159f16eecc7863f163cf22b0eec4ad0e86fb321b.zip`，SHA256 `2099d109041ab74161a1d60eeba54caff8ee6c95627d95756e0be75e72c05b81`，保存在构建根。所有旧 WorkRoot 和旧包保留。
- 工具链：Flutter 3.47.4 / Dart 3.13.3、Go 1.26.9、Rust 1.98.1、CMake 3.31.6、Ninja 1.11.1.git.kitware.jobserver-1、MSVC 14.44.35207、Windows SDK 10.0.26100.0、ATL manifest 14.51.36237。与 CI 的 Flutter 3.41.7 不同。
- 构建限制：CMake parallel=1、Cargo jobs=1、GOMAXPROCS=2、GOFLAGS=-p=1；依赖离线读取、锁文件不变。未停止其他进程、升级依赖或修改系统设置。

实际构建命令（该 WorkRoot 和输出已存在，复建需使用新的目录和产物名）：

```powershell
& 'E:\Temp\flclashx-tools-pwsh-7.6.7\pwsh\pwsh.exe' -NoLogo -NoProfile -NonInteractive -File 'E:\Temp\fcx-country-tools-20261024\Build-Remediation.ps1' -ExpectedSha '159f16eecc7863f163cf22b0eec4ad0e86fb321b' -WorkRoot 'E:\Temp\fcx-country-159f16e-r1' -PreviewLabel 'country-tls' -FlutterRoot 'E:\flutter'
```

| 检查 | 结果与边界 |
| --- | --- |
| Core → Agent → Helper | PASS / exit 0，853.16s；包含 verified Mihomo overlay |
| Flutter config-only | 已知 VS discovery FAIL / exit 1，仅精确匹配允许的既有提示；保留日志 |
| 明确指定 MSVC/CMake 配置 | PASS / exit 0 |
| Flutter Dart AOT | PASS / exit 0，145.26s |
| Windows runner / native plugins | PASS / exit 0，157.43s；编译警告保留 |
| 组包、构建内 ZIP roundtrip | PASS / 73 文件逐项一致 |
| 交付目录再安全解压 | PASS / 73 文件长度和 hash 一致 |
| 独立静态产物审计 | PASS / 8/8；源码、组件来源、Helper/UI 绑定、补丁 manifest、预置依赖、PE、披露逐项核对 |
| 运行库与字体补充静态检查 | PASS；30 PE / 61 常规 DLL imports，本机未解析非 API-set 依赖 0；Twemoji 字体与声明匹配 |
| 前一轮同 SHA 定向回归 | 141/141 PASS；网络专项 11/11 PASS；2 文件 analyze 为 0 error / 0 warning / 3 既有 info。本轮打包未重跑这些用例；日志归入证据目录 |
| 全量 962 项 | 来自开发者先前报告，本轮审查/打包未重新执行 |
| 远端 CI、真实窗口/IPC、代理/TUN/服务、切网/休眠/长时运行 | NOT RUN；由用户手工测试，不能用静态通过替代 |

15 个构建步骤中 14 个 exit 0，1 个为精确识别的 VS discovery 例外；实际 AOT 与原生编译成功。独立 audit 副本只让 README 断言接受“首次及每次完整启动会启动或接管代理”的精确同义表达，其他断言未变，diff/hash 留存。

## 范围、已知限制与手工验收

本包包含国家筛选胶囊/徽标、跨配置国家索引、配置版本与探测连接归属修复，以及 TLS 握手停滞超时/取消清理。无关产品源码未修改。

**已知限制：生产 CONNECT 路径仍继承全局 `badCertificateCallback => true`，未信任或主机名不匹配证书会被接受；这是已有行为，本包未修复，也不声明生产 CONNECT 完整 TLS 安全验收通过。** 连接清理单测验证的是在 1 秒检查窗口内观察关闭，不夸大为所有环境毫秒级保证。

1. 保留当前完整旧包及配置备份，记录配置、节点与 TUN 偏好。从旧客户端托盘选择“退出”，再启动新目录 `FlClashX.exe`；窗口 X 可能仅隐藏/关闭 UI。
2. 新目录仍共享应用数据。完整启动会启动/接管代理并按保存的 TUN 设置执行；必要的权限提示由用户处理。
3. 进入“代理 → 全部配置”，检查彩色国旗、国家数量、屏外配置国家索引；点击国家/再次点击、切单配置、搜索/仅可用/排序和窄窗行为正常。
4. 切换可用节点或配置并刷新仪表盘 IP，新节点不应继承旧节点国家；无关策略组不应统一被一次出口结果覆盖。证据不足允许名称或“其他”兜底。
5. 反复正常刷新 IP 查询并重开总览，失败后仍可重试；本会话手动关闭 TUN 后不应自行重开。购买、微信联系、礼品卡入口应保留。
6. 记录异常步骤、准确时间、提示、窗口尺寸与模式/TUN 状态，避免在截图/普通日志中暴露凭据或订阅 URL。

回退：托盘退出新包，再启动保留的完整旧包；不混换 EXE/DLL，不删除用户数据或手工拼装服务组件。本次没有启动候选程序，也没有改动现役客户端、代理、TUN、后台服务、节点选择或用户配置。

打包前核验的旧 `oneclick-wip-0aa11746b863` ZIP 仍保留，SHA256 `17996f72c95461baafe72485e6635eec8c84988fddb153855c0f7b2205d574e7`；这不是对其当前运行状态的断言。产品提交 `159f16e` 已本地提交，交付报告/台账另行本地记录；未推送、未合并、未启动候选、未实机验收。

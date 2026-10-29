# Windows 跨配置节点总览订阅详情与协议栈预览交付

日期：2026-10-29（Asia/Shanghai）。本报告在批次 PR 合并及预览构建完成后编写，不改变包内源码身份。

## 交付与来源

- 源码：`main` / `development` 合并提交 `a8dc8bfc102e54e404f792d2602939854e9a9128`（PR [#61](https://github.com/Hao-Monster/FreedomCloud/pull/61)，合并范围 `f08fedb2cd2cd3590362fe6135bb7c5aa97b510c..694ce1c0ef40a767306393f76e1b08763626c1c4` 共 51 个产品与文档提交），Git tree `3ccf124a06dfe2f41bb3dfebaaed2288aa6954e4`。从干净 tracked Git archive 构建；工作树未跟踪的 `coverage/`、QA 记录与 `probes/` 未纳入。
- 类型：普通未签名 Windows amd64 免安装预览；`APP_ENV=pre`、`APP_VERSION=overview-sub-a8dc8bfc102e`、Core `v1.19.32`。不包含 strict WFP 驱动/Broker。
- [预览 ZIP](../../dist/FreedomCloud-windows-amd64-overview-sub-a8dc8bfc102e.zip)：166,142,005 bytes（158.45 MiB）；[SHA256 文件](../../dist/FreedomCloud-windows-amd64-overview-sub-a8dc8bfc102e.zip.sha256)。
- ZIP SHA256：`9fa38b8fe63df2fc133ae77b57f6c5339b4e43c2a6eea9a4b7a168a3f0074c95`。
- [已安全解压并校验的完整目录](../../dist/FreedomCloud-windows-amd64-overview-sub-a8dc8bfc102e/)，入口 `FlClashX.exe`；共 73 文件，`SHA256SUMS.txt` 覆盖除自身外的 72 文件。
- [包内手工测试说明](../../dist/FreedomCloud-windows-amd64-overview-sub-a8dc8bfc102e/PREVIEW-README.txt)；[交付证据](../../dist/overview-sub-a8dc8bfc102e-evidence/delivery-summary.json)；[静态审计明细](../../dist/overview-sub-a8dc8bfc102e-evidence/artifact-audit.json)。

UI、Core、Agent、Helper 与仓库原生插件（`proxy`、`tray_manager`、`window_ext`）从同一合并提交新编。第三方插件从 `pubspec.lock` 锁定依赖重编；Flutter engine、QuickJS、MSVC CRT 和 `EnableLoopback.exe` 为核对来源及 hash 的预置输入，不声称所有文件从源码重建。

| 组件 | bytes | SHA256 |
| --- | ---: | --- |
| UI runner / `FlClashX.exe` | 134,144 | `a4d3c92037ba00cd1721b87f7447aaeb6fb1ba4453ee6b82944669c128cd2e36` |
| Dart AOT / `data/app.so` | 16,532,360 | `2334c38f159c5d5917ffa7ead991e490c3456b087b04e01c9eaf304f2be85ad4` |
| Core / `FlClashCore.exe` | 72,386,560 | `59dbcacc38720b7ea004bbb77e7aa45ddabc14648afb1cda3c7c8c1b52f98a2a` |
| Agent / `FlClashAgent.exe` | 1,026,048 | `f82a10d185a13a66cd190640a1454e1d43d317e02a05aec2d158dc941c5fe0fd` |
| Helper / `FlClashHelperService.exe` | 1,031,168 | `b5bc7a5ca82010da3739f4d5094050f2a69b66f09f26a2567a8252ee487ec404` |
| Core 补丁清单 / `CORE-PATCH.json` | 109,453 | `63b20e52be07e62864a9f318063d59c01284156b04a9a300f8648c72d212c045` |

Helper 实际二进制包含本次 Core hash 1 次；UI 实际生成编译参数 `CORE_SHA256` 与新 AOT `data/app.so` 对应。该结论是静态绑定证据，不是运行时组件接管验收。

## 实际构建与验证

- 构建根：`E:\Temp\fcx-overview-sub-a8dc8bfc-r1`；工具：`E:\Temp\fcx-overview-tools-20261029`；静态审计根：`E:\Temp\fcx-overview-audit-20261029`。开始 UTC `2026-10-29T03:29:31.9695701Z`，完成 UTC `2026-10-29T03:45:15.3958979Z`，主进程 exit `0` / **PASS**。
- 源归档：`source-a8dc8bfc102e54e404f792d2602939854e9a9128.zip`，SHA256 `e9acedf9d1371b2a327f8d8efd975ad53b0df958566b3802d936586e7d98182e`，保存在构建根。所有旧 WorkRoot 与旧预览包完整保留。
- 工具链：Flutter 3.47.4 / Dart 3.13.3、Go 1.26.9、Rust 1.98.1、CMake 3.31.6、Ninja 1.11.1.git.kitware.jobserver-1、MSVC 14.44.35207、Windows SDK 10.0.26100.0、ATL manifest 14.51.36237。与 CI 的 Flutter 3.41.7 / Go 1.26.0 存在版本差异并已通过两端门禁验证。
- 构建限制：CMake `parallel=1`、Cargo `jobs=1`、`GOMAXPROCS=2`、`GOFLAGS=-p=1`；依赖离线读取（`pubspec.lock` SHA256 `4c315285dc10f572b3a89a314d7aaab3942cb64254b01fe6c459be8ab0e9eae8` 不变）。未停止其他进程、升级依赖或修改系统设置；构建前后现役四进程 PID（`39648:FlClashHelperService`、`67152:FlClashX`、`54840:FlClashAgent`、`42840:FlClashCore`）保持一致。

实际构建命令（该 WorkRoot 和输出已存在，复建需使用新的目录和产物名）：

```powershell
& 'E:\Temp\flclashx-tools-pwsh-7.6.7\pwsh\pwsh.exe' -NoLogo -NoProfile -NonInteractive -File 'E:\Temp\fcx-overview-tools-20261029\Build-Remediation.ps1' -ExpectedSha 'a8dc8bfc102e54e404f792d2602939854e9a9128' -WorkRoot 'E:\Temp\fcx-overview-sub-a8dc8bfc-r1' -PreviewLabel 'overview-sub' -FlutterRoot 'E:\flutter'
```

| 检查 | 结果与边界 |
| --- | --- |
| 远端 PR 与合并后 GitHub Actions CI | **PASS**（PR [#61](https://github.com/Hao-Monster/FreedomCloud/pull/61) head `694ce1c`：[push `40811835890`](https://github.com/Hao-Monster/FreedomCloud/actions/runs/40811835890) / [PR `40811842381`](https://github.com/Hao-Monster/FreedomCloud/actions/runs/40811842381) 4/4 PASS；合并提交 `a8dc8bfc102e`：[main `40812322068`](https://github.com/Hao-Monster/FreedomCloud/actions/runs/40812322068) / [development `40812388471`](https://github.com/Hao-Monster/FreedomCloud/actions/runs/40812388471) 4/4 PASS） |
| 独立代码与治理审查 | **PASS / APPROVE**（两轮独立审查，首轮检出 2 项 `P1` 与 2 项 `P3` 已在 `694ce1c` 闭环修复并复审放行，`0 P1 / 0 P2`） |
| Core → Agent → Helper | PASS / exit 0，485.72s；包含 verified Mihomo `v1.19.32` overlay（`effectiveModuleSha256` `b3b5103a6816710a9ebc0bbb74d83b5954c829d89cbf1d4d345fd6b83e5a2603`） |
| Flutter config-only | 已知 VS discovery FAIL / exit 1（3.89s），精确匹配允许的既有提示；保留日志 |
| 明确指定 MSVC/CMake 配置 | PASS / exit 0，6.99s |
| Flutter Dart AOT | PASS / exit 0，122.27s |
| Windows runner / native plugins | PASS / exit 0，143.35s |
| 组包、构建内 ZIP roundtrip | PASS / 73 文件逐项一致（17.30s） |
| 交付目录再安全解压 | PASS / 73 文件长度和 hash 一致 |
| 独立静态产物审计 | PASS / 8/8；源码（1015 Git blobs）、组件来源、Helper/UI 绑定、补丁 manifest、预置依赖、30 个 PE/imports、披露逐项核对 |
| 同源码本地测试与静态分析 | 节点总览套件 125/125 PASS（`node_overview_test.dart` 96/96 PASS）；全仓 996/996 PASS；`dart analyze` 0 issues |
| 真实窗口/IPC、系统凭据库、代理/TUN/服务、真实发卡消费 | **NOT RUN**；由用户手工测试，不能用单元/CI/静态通过替代 |

## 范围、已知限制与手工验收

本包包含跨配置节点总览增量开发及两轮深度 Code Review 加固（单节点显式“延迟测试”文字按钮覆盖活动/非活动行并防取消与后台广播污染、配置列表默认按可用节点数降序排列且测速中冻结不跳动、“仅显示可用”胶囊与非遮挡锚定排序菜单支持 `1.8x` 大字号无溢出、订阅配置卡片全量展示剩余流量/百分比胶囊/三级告警色进度条/上下行明细/到期倒计时/最近同步时间/安全解码服务名与公告、节点协议栈闭世界白名单完整展示并移除“内联”标签），同时完整保留仅兑换码购买与核销工作台 v2、三级国家筛选与探针超时关闭、跨配置一键切换节点、Windows TUN 两阶段自愈及 DoH 静默连接恢复。

**已知限制：生产 HTTP CONNECT 路径仍继承全局 `badCertificateCallback => true`，未信任或主机名不匹配证书会被接受；这是已有行为，本包未修复，也不声明生产 CONNECT 完整 TLS 安全验收通过。**

1. 保留当前完整旧包及配置备份，记录配置、节点与 TUN 偏好。从旧客户端托盘选择“退出”，再启动新目录 `FlClashX.exe`；窗口 `X` 可能仅隐藏/关闭 UI。
2. 新目录仍共享应用数据。完整启动会启动/接管代理并按保存的 TUN 设置执行；必要的权限提示由用户处理。
3. 进入“代理 → 全部配置”：确认左侧配置卡片默认按可用节点数量从多到少排列；核对 URL 订阅卡片展示剩余流量、百分比、进度条、上行/下行、到期时间及最近同步时间，右侧分组吸顶头展示精简摘要；本地 YAML 配置不误显示 `0 B` 占位条。
4. 检查顶部“仅显示可用”筛选按钮与“默认 / 名称 / 延迟”排序下拉菜单：展开菜单不应遮挡左侧筛选按钮或右侧测速按钮，切换排序与筛选立即生效。
5. 检查节点行协议信息与单点测速：确认原 `Vless · 内联` 已变为完整协议栈特征（如 `VLESS · TCP · REALITY · xtls-rprx-vision` 等）；分别对活动配置节点（含 Provider 节点）与非活动配置节点点击右侧“延迟测试”按钮，确认测速状态与延迟数值正常刷新，点击“使用”可一键切换。
6. 抽检“购买”页：确认公开套餐浏览、两个微信号复制与兑换码查询核验流程保持正常。
7. 记录异常步骤、准确时间、提示、窗口尺寸与模式/TUN 状态，避免在截图或普通日志中暴露账号、密码、订阅 URL 或完整兑换码。

回退：托盘退出新包，再启动保留的完整旧包；不混换单个 EXE/DLL，不删除用户数据或手工覆盖系统服务文件。本次没有启动候选程序，也没有改动现役客户端、代理、TUN、后台服务、节点选择或用户配置。

上一可用包 [`FreedomCloud-windows-amd64-purchase-v2-8a666bb01005.zip`](../../dist/FreedomCloud-windows-amd64-purchase-v2-8a666bb01005.zip)（SHA256 `1fd3a06fdc360b2185d1bacde4186158250d27b1a6415ff899c45a1c0552c2ad`）与 [`FreedomCloud-windows-amd64-country-tls-159f16eecc78.zip`](../../dist/FreedomCloud-windows-amd64-country-tls-159f16eecc78.zip)（SHA256 `98d8a7a9ef7160af5f3148d5dfe8a260d78441968750cea5e6ae6825f966c2b8`）及对应解压目录完整保留。

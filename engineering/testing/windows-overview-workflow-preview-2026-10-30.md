# Windows 跨配置快捷工作流、订阅同步与窄窗配置选择器预览交付

日期：2026-10-30（Asia/Shanghai）。本报告在批次 PR 合并及预览构建完成后编写，不改变包内源码身份。

## 交付与来源

- 源码：`main` / `development` 合并提交 `189e85f33d457fee5b736e1fe1fb1c3aa828dd2e`（PR [#62](https://github.com/Hao-Monster/FreedomCloud/pull/62)，合并范围 `842b43fea4c1a6b3fd28cbd76c00324f96916ee2..c1b1e2fa83d29ccf1f75817273cca20b505fe4eb` 共 7 个提交），Git tree `c87a43ae01264739426baa5f558d3e6db7f66eec`。从干净 tracked Git archive 构建；工作树未跟踪的 `coverage/`、QA 记录与 `probes/` 未纳入。
- 类型：普通未签名 Windows amd64 免安装预览；`APP_ENV=pre`、`APP_VERSION=overview-workflow-189e85f33d45`、Core `v1.19.32`。不包含 strict WFP 驱动/Broker。
- [预览 ZIP](../../dist/FreedomCloud-windows-amd64-overview-workflow-189e85f33d45.zip)：166,258,044 bytes（158.56 MiB）；[SHA256 文件](../../dist/FreedomCloud-windows-amd64-overview-workflow-189e85f33d45.zip.sha256)。
- ZIP SHA256：`048c849c80f0045f0ae0a72925ca66b69cfef0d1708acc603b9e5799fb601d43`。
- [已安全解压并校验的完整目录](../../dist/FreedomCloud-windows-amd64-overview-workflow-189e85f33d45/)，入口 `FlClashX.exe`；共 73 文件，`SHA256SUMS.txt` 覆盖除自身外的 72 文件。
- [包内手工测试说明](../../dist/FreedomCloud-windows-amd64-overview-workflow-189e85f33d45/PREVIEW-README.txt)；[交付证据](../../dist/overview-workflow-189e85f33d45-evidence/delivery-summary.json)；[静态审计明细](../../dist/overview-workflow-189e85f33d45-evidence/artifact-audit.json)。

UI、Core、Agent、Helper 与仓库原生插件（`proxy`、`tray_manager`、`window_ext`）从同一合并提交新编。第三方插件从 `pubspec.lock` 锁定依赖重编；Flutter engine、QuickJS、MSVC CRT 和 `EnableLoopback.exe` 为核对来源及 hash 的预置输入，不声称所有文件从源码重建。

| 组件 | bytes | SHA256 |
| --- | ---: | --- |
| UI runner / `FlClashX.exe` | 134,144 | `48ac5e834f8e82ed1fc7ebf588b59daaf7f24480c8eabc0a63fb8219d7795fd2` |
| Dart AOT / `data/app.so` | 16,647,048 | `060f9b641c79cc2b68d24886041ba557b196f2b874c84bc530e5fd83811c1375` |
| Core / `FlClashCore.exe` | 72,386,560 | `59dbcacc38720b7ea004bbb77e7aa45ddabc14648afb1cda3c7c8c1b52f98a2a` |
| Agent / `FlClashAgent.exe` | 1,026,048 | `9638fdb8c011353e2091f7e3d8b7b1bf7b983c6db0c08de62b7a6ea72778fba6` |
| Helper / `FlClashHelperService.exe` | 1,031,168 | `dcfed357fd9613b80ab5370f35fb7a9355bc715a38c7f870cede531ec6bfc5d1` |
| Core 补丁清单 / `CORE-PATCH.json` | 109,453 | `63b20e52be07e62864a9f318063d59c01284156b04a9a300f8648c72d212c045` |

Helper 实际二进制包含本次 Core hash 1 次；UI 实际生成编译参数 `CORE_SHA256` 与新 AOT `data/app.so` 对应。该结论是静态绑定证据，不是运行时组件接管验收。

## 实际构建与验证

- 构建根：`E:\Temp\fcx-overview-workflow-189e85f3-r1`；工具：`E:\Temp\fcx-overview-tools-20261030`；静态审计根：`E:\Temp\fcx-overview-audit-20261030`。开始 UTC `2026-10-30T12:51:24.9501023Z`，完成 UTC `2026-10-30T13:02:11.6217822Z`，主进程 exit `0` / **PASS**。
- 源归档：`source-189e85f33d457fee5b736e1fe1fb1c3aa828dd2e.zip`，SHA256 `0adb6aba9c94bd40fec46577a533e8635380dc049a9f3f618752b4a946dc6f98`，保存在构建根。所有旧 WorkRoot 与旧预览包完整保留。
- 工具链：Flutter 3.47.4 / Dart 3.13.3、Go 1.26.9、Rust 1.98.1、CMake 3.31.6、Ninja 1.11.1.git.kitware.jobserver-1、MSVC 14.44.35207、Windows SDK 10.0.26100.0、ATL manifest 14.51.36237。与 CI 的 Flutter 3.41.7 / Go 1.26.0 存在版本差异并已通过两端门禁验证。
- 构建限制：CMake `parallel=1`、Cargo `jobs=1`、`GOMAXPROCS=2`、`GOFLAGS=-p=1`；依赖离线读取（`pubspec.lock` SHA256 `4c315285dc10f572b3a89a314d7aaab3942cb64254b01fe6c459be8ab0e9eae8` 不变）。未停止其他进程、升级依赖或修改系统设置；构建前后现役四进程 PID（`70580:FlClashAgent`、`41268:FlClashCore`、`68600:FlClashHelperService`、`69904:FlClashX`）保持一致。

实际构建命令（该 WorkRoot 和输出已存在，复建需使用新的目录和产物名）：

```powershell
& 'E:\Temp\flclashx-tools-pwsh-7.6.7\pwsh\pwsh.exe' -NoLogo -NoProfile -NonInteractive -File 'E:\Temp\fcx-overview-tools-20261030\Build-Remediation.ps1' -ExpectedSha '189e85f33d457fee5b736e1fe1fb1c3aa828dd2e' -WorkRoot 'E:\Temp\fcx-overview-workflow-189e85f3-r1' -PreviewLabel 'overview-workflow' -FlutterRoot 'E:\flutter'
```

| 检查 | 结果与边界 |
| --- | --- |
| 远端 PR 与合并后 GitHub Actions CI | **PASS**（PR [#62](https://github.com/Hao-Monster/FreedomCloud/pull/62) head `c1b1e2f`：[push `41057617527`](https://github.com/Hao-Monster/FreedomCloud/actions/runs/41057617527) / [PR `41057630162`](https://github.com/Hao-Monster/FreedomCloud/actions/runs/41057630162) 4/4 PASS；合并提交 `189e85f33d45`：[main `41058460352`](https://github.com/Hao-Monster/FreedomCloud/actions/runs/41058460352) / [development `41058476276`](https://github.com/Hao-Monster/FreedomCloud/actions/runs/41058476276) 4/4 PASS） |
| 独立代码与治理审查 | **PASS / APPROVE**（晋级前独立审查覆盖全量 diff 及 `Flutter 3.41.7` 标签源码 API 对照，`0 P1 / 0 P2 / 3 P3`） |
| Core → Agent → Helper | PASS / exit 0，352.79s；包含 verified Mihomo `v1.19.32` overlay（`effectiveModuleSha256` `b3b5103a6816710a9ebc0bbb74d83b5954c829d89cbf1d4d345fd6b83e5a2603`） |
| Flutter config-only | 已知 VS discovery FAIL / exit 1（2.51s），精确匹配允许的既有提示；保留日志 |
| 明确指定 MSVC/CMake 配置 | PASS / exit 0，3.06s |
| Flutter Dart AOT | PASS / exit 0，92.98s |
| Windows runner / native plugins | PASS / exit 0，93.17s |
| 组包、构建内 ZIP roundtrip | PASS / 73 文件逐项一致（10.91s） |
| 交付目录再安全解压 | PASS / 73 文件长度和 hash 一致 |
| 独立静态产物审计 | PASS / 8/8；源码（1017 Git blobs）、组件来源、Helper/UI 绑定、补丁 manifest、预置依赖、30 个 PE/imports、披露逐项核对 |
| 同源码本地测试与静态分析 | 节点总览套件 144/144 PASS（含 `440x820 @ 2x` 合成渲染 3/3 PASS）；全仓 1,012/1,012 PASS；M3 包门禁 68/68 PASS；`dart analyze` 0 error / 0 warning |
| 真实窗口/IPC、系统凭据库、代理/TUN/服务、真实发卡消费 | **NOT RUN**；由用户手工测试，不能用单元/CI/静态通过替代 |

## 范围、已知限制与手工验收

本包包含跨配置节点总览三项核心增强及三轮深度 Code Review 加固（URL 订阅配置卡片右上角“更新订阅”按钮及 `updateProfile` 同源并发合并/防复活/瞬态告警头清理、右侧顶部 **`添加订阅` → `测试当前配置` → `点击使用`** 三步引导工作流栏与全局默认 `O(N)` 稳定延迟排序、窄窗 `<= 840px` 等高配置选择胶囊与展示“可用节点数 + 订阅到期胶囊 + 活动配置徽标”的富卡片浮层及 `profile_selector.dart` 模块拆分），同时完整保留跨配置订阅流量详情与节点安全协议栈展示、仅兑换码购买与核销工作台 v2、三级国家筛选与探针超时关闭、Windows TUN 两阶段自愈及 DoH 静默连接恢复。

**已知限制：生产 HTTP CONNECT 路径仍继承全局 `badCertificateCallback => true`，未信任或主机名不匹配证书会被接受；这是已有行为，本包未修复，也不声明生产 CONNECT 完整 TLS 安全验收通过。**

1. 保留当前完整旧包及配置备份，记录配置、节点与 TUN 偏好。从旧客户端托盘选择“退出”，再启动新目录 `FlClashX.exe`；窗口 `X` 可能仅隐藏/关闭 UI。
2. 新目录仍共享应用数据。完整启动会启动/接管代理并按保存的 TUN 设置执行；必要的权限提示由用户处理。
3. 进入“代理 → 全部配置”（宽窗）：确认 URL 订阅卡片右上角展示“更新订阅”按钮（活动配置与“活动配置”徽标并列），点击后显示“更新中”进度并刷新订阅流量/到期元数据，侧边栏排序不跳动；本地文件配置不展示该按钮。
4. 检查顶部排序与三步工作流栏：确认排序默认选中“延迟”；点击第 1 步“添加订阅”直接打开“从URL导入”弹窗；点击第 2 步“测试当前配置”正常完成延迟测试且低延迟可用节点置顶；点击第 3 步“点击使用”自动启用排在首位的低延迟可用节点。
5. 将客户端窗口拖窄（宽度 `<= 840px`）：确认左上角配置选择胶囊与右侧“仅显示可用 / 排序”按钮 `36px` 等高对齐；点击展开浮层，核对置顶“全部配置”汇总卡与各配置卡片的“可用 X / Y”节点数量、到期日期/剩余天数（或长期有效/本地配置）、“活动配置”徽标及键盘 `↑ / ↓ / Enter` 切换体验。
6. 抽检“购买”页：确认公开套餐浏览、两个微信号复制与兑换码查询核验流程保持正常。
7. 记录异常步骤、准确时间、提示、窗口尺寸与模式/TUN 状态，避免在截图或普通日志中暴露账号、密码、订阅 URL 或完整兑换码。

回退：托盘退出新包，再启动保留的完整旧包；不混换单个 EXE/DLL，不删除用户数据或手工覆盖系统服务文件。本次没有启动候选程序，也没有改动现役客户端、代理、TUN、后台服务、节点选择或用户配置。

上一可用包 [`FreedomCloud-windows-amd64-overview-sub-a8dc8bfc102e.zip`](../../dist/FreedomCloud-windows-amd64-overview-sub-a8dc8bfc102e.zip)（SHA256 `9fa38b8fe63df2fc133ae77b57f6c5339b4e43c2a6eea9a4b7a168a3f0074c95`）、[`FreedomCloud-windows-amd64-purchase-v2-8a666bb01005.zip`](../../dist/FreedomCloud-windows-amd64-purchase-v2-8a666bb01005.zip)（SHA256 `1fd3a06fdc360b2185d1bacde4186158250d27b1a6415ff899c45a1c0552c2ad`）与 [`FreedomCloud-windows-amd64-country-tls-159f16eecc78.zip`](../../dist/FreedomCloud-windows-amd64-country-tls-159f16eecc78.zip)（SHA256 `98d8a7a9ef7160af5f3148d5dfe8a260d78441968750cea5e6ae6825f966c2b8`）及对应解压目录完整保留。

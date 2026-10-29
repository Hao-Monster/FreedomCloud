# Windows 仅兑换码购买与核销工作台 v2 预览交付

日期：2026-10-26（Asia/Shanghai）。本报告在构建完成后编写，不改变包内源码身份。

## 交付与来源

- 源码：`development@8a666bb0100503848010d7d565e42e61d9c2320b`，Git tree `e4cb32b3164b17bf262d6b70f844c735569c7304`。从干净 tracked Git archive 构建；工作树未跟踪的 `coverage/`、QA 记录与 `probes/` 未纳入。构建前 fetch 核对领先 `freedomcloud/development` 16 个提交，落后 0；未推送、未创建 PR。
- 类型：普通未签名 Windows amd64 免安装预览；`APP_ENV=pre`、`APP_VERSION=purchase-v2-8a666bb01005`、Core `v1.19.32`。不包含 strict WFP 驱动/Broker。
- [预览 ZIP](../../dist/FreedomCloud-windows-amd64-purchase-v2-8a666bb01005.zip)：166,041,571 bytes（158.35 MiB）；[SHA256 文件](../../dist/FreedomCloud-windows-amd64-purchase-v2-8a666bb01005.zip.sha256)。
- ZIP SHA256：`1fd3a06fdc360b2185d1bacde4186158250d27b1a6415ff899c45a1c0552c2ad`。
- [已安全解压并校验的完整目录](../../dist/FreedomCloud-windows-amd64-purchase-v2-8a666bb01005/)，入口 `FlClashX.exe`；共 73 文件，`SHA256SUMS.txt` 覆盖除自身外的 72 文件。
- [包内手工测试说明](../../dist/FreedomCloud-windows-amd64-purchase-v2-8a666bb01005/PREVIEW-README.txt)；[交付证据](../../dist/purchase-v2-8a666bb01005-evidence/delivery-summary.json)。

UI、Core、Agent、Helper 与仓库原生插件（`proxy`、`tray_manager`、`window_ext`）从同一提交新编。第三方插件从 `pubspec.lock` 锁定依赖重编；Flutter engine、QuickJS、MSVC CRT 和 `EnableLoopback.exe` 为核对来源及 hash 的预置输入，不声称所有文件从源码重建。

| 组件 | bytes | SHA256 |
| --- | ---: | --- |
| UI runner / `FlClashX.exe` | 134,144 | `b3fe18fddced7223a09568df0661adfacf9a2555ff4d3c9f133283496c805532` |
| Dart AOT / `data/app.so` | 16,434,056 | `ca2c9cfbe8161a109ccec6b2babc9139b0285f00bccc9dde54c8c240465859bb` |
| Core / `FlClashCore.exe` | 72,386,560 | `59dbcacc38720b7ea004bbb77e7aa45ddabc14648afb1cda3c7c8c1b52f98a2a` |
| Agent / `FlClashAgent.exe` | 1,026,048 | `fa99eefed472d4de75756b5dc0164a0957d0a3d6bcb9d1166b1853661fcb39e8` |
| Helper / `FlClashHelperService.exe` | 1,031,680 | `8fcfaaf2f61715d38f6b6282ce9e770e43cc4f20a7a21e70263d857718750c1c` |
| Core 补丁清单 / `CORE-PATCH.json` | 109,453 | `63b20e52be07e62864a9f318063d59c01284156b04a9a300f8648c72d212c045` |

Helper 实际二进制包含本次 Core hash 1 次；UI 实际生成编译参数 `CORE_SHA256` 与新 AOT `data/app.so` 对应。该结论是静态绑定证据，不是运行时组件接管验收。

## 实际构建与验证

- 构建根：`E:\Temp\fcx-purchase-v2-8a666bb0-r1`；工具：`E:\Temp\fcx-purchase-v2-tools-20261026`；静态审计根：`E:\Temp\fcx-purchase-v2-audit-20261026`。开始 UTC `2026-10-25T16:02:25.6842716Z`，完成 UTC `2026-10-25T16:13:43.0542203Z`，主进程 exit `0` / **PASS**。
- 源归档：`source-8a666bb0100503848010d7d565e42e61d9c2320b.zip`，SHA256 `4fc573c4d64b467241ddc27f2e61d52ea519f55f54502d3cb4fe2d72fe0f0253`，保存在构建根。所有旧 WorkRoot 与旧预览包完整保留。
- 工具链：Flutter 3.47.4 / Dart 3.13.3、Go 1.26.9、Rust 1.98.1、CMake 3.31.6、Ninja 1.11.1.git.kitware.jobserver-1、MSVC 14.44.35207、Windows SDK 10.0.26100.0、ATL manifest 14.51.36237。与 CI 的 Flutter 3.41.7 不同。
- 构建限制：CMake `parallel=1`、Cargo `jobs=1`、`GOMAXPROCS=2`、`GOFLAGS=-p=1`；依赖离线读取（`pubspec.lock` SHA256 `4c315285dc10f572b3a89a314d7aaab3942cb64254b01fe6c459be8ab0e9eae8` 不变）。未停止其他进程、升级依赖或修改系统设置；构建前后现役四进程 PID（`5344:FlClashHelperService`、`8904:FlClashX`、`19472:FlClashAgent`、`25704:FlClashCore`）保持一致。

实际构建命令（该 WorkRoot 和输出已存在，复建需使用新的目录和产物名）：

```powershell
& 'E:\Temp\flclashx-tools-pwsh-7.6.7\pwsh\pwsh.exe' -NoLogo -NoProfile -NonInteractive -File 'E:\Temp\fcx-purchase-v2-tools-20261026\Build-Remediation.ps1' -ExpectedSha '8a666bb0100503848010d7d565e42e61d9c2320b' -WorkRoot 'E:\Temp\fcx-purchase-v2-8a666bb0-r1' -PreviewLabel 'purchase-v2' -FlutterRoot 'E:\flutter'
```

| 检查 | 结果与边界 |
| --- | --- |
| Core → Agent → Helper | PASS / exit 0，348.27s；包含 verified Mihomo `v1.19.32` overlay（`effectiveModuleSha256` `b3b5103a6816710a9ebc0bbb74d83b5954c829d89cbf1d4d345fd6b83e5a2603`） |
| Flutter config-only | 已知 VS discovery FAIL / exit 1（2.82s），精确匹配允许的既有提示；保留日志 |
| 明确指定 MSVC/CMake 配置 | PASS / exit 0，3.77s |
| Flutter Dart AOT | PASS / exit 0，81.23s |
| Windows runner / native plugins | PASS / exit 0，103.84s |
| 组包、构建内 ZIP roundtrip | PASS / 73 文件逐项一致（16.66s） |
| 交付目录再安全解压 | PASS / 73 文件长度和 hash 一致 |
| 独立静态产物审计 | PASS / 8/8；源码、组件来源、Helper/UI 绑定、补丁 manifest、预置依赖、30 个 PE/imports、披露逐项核对 |
| 同 SHA 本地测试与静态分析 | `test/purchase` 315/315 PASS；全仓 `flutter test --no-pub -j 4` 981/981 PASS；`dart analyze` 0 issues；`dart format` 0 diff（详见证 [`purchase-redemption-2026-10-11.md`](purchase-redemption-2026-10-11.md)） |
| 远端 CI、真实窗口/IPC、系统凭据库、代理/TUN/服务、真实发卡消费 | NOT RUN；由用户手工测试，不能用单元/静态通过替代 |

## 范围、已知限制与手工验收

本包包含仅兑换码购买与核销工作台 v2 重构及两轮 Code Review 加固（宽窗“左套餐橱窗 + 右核销工作台”双栏布局、窄窗“直达核销”锚点、公开套餐周期/按量筛选、彩色国旗徽标与长 Markdown 结构感知渐进展开、不建单的“获取此套餐兑换码”咨询口令/双微信号复制/商店抽屉、剪贴板智能清洗与 `Ctrl+V` 连字符规整、原地大写不跳光标且兼容 IME 组合态、`兑换前 → 兑换后` 核验对比卡、默认折叠兑换记录、品牌去 `Xboard` 化），同时保留此前已集成的跨配置节点国家筛选与 TUN 自愈修复。

**已知限制：生产 HTTP CONNECT 路径仍继承全局 `badCertificateCallback => true`，未信任或主机名不匹配证书会被接受；这是已有行为，本包未修复，也不声明生产 CONNECT 完整 TLS 安全验收通过。**

1. 保留当前完整旧包及配置备份，记录配置、节点与 TUN 偏好。从旧客户端托盘选择“退出”，再启动新目录 `FlClashX.exe`；窗口 `X` 可能仅隐藏/关闭 UI。
2. 新目录仍共享应用数据。完整启动会启动/接管代理并按保存的 TUN 设置执行；必要的权限提示由用户处理。
3. 未登录进入购买/礼品卡兑换页：检查宽窗左右双栏无留白黑洞、界面无 `Xboard` 字样；核对套餐卡片彩色国旗、周期标价、`全部套餐 / 周期订阅 / 按量流量包` 筛选及长说明展开/收起；缩放窗口跨越 `860px` 断点时已选筛选与展开态保留，窄窗顶部“已有兑换码？直达核销”可一键滚至工作台。
4. 点击任一套餐“获取此套餐兑换码”：确认一键复制咨询口令带套餐名/流量/标价，两个微信号（`ChasingDream_2021` / `dxm_qa`）复制内联提示正常，商店链接与右上角关闭按钮可用，且无任何建单或兑码副作用。
5. 登录账户（确认切换密码显隐在退出登录后自动恢复掩码）：测试从多行客服消息智能粘贴兑换码、`Ctrl+V` 粘贴带连字符卡密及在中间插入小写字母（光标不跳尾）；点击查询权益核对 `兑换前 → 兑换后` 对比卡，仅在使用获准测试卡时执行确认兑换、订阅同步与“查看配置与节点”跳转；检查默认折叠的兑换记录展开与分页。
6. 记录异常步骤、准确时间、提示、窗口尺寸与模式/TUN 状态，避免在截图或普通日志中暴露账号、密码、订阅 URL 或完整兑换码。

回退：托盘退出新包，再启动保留的完整旧包；不混换单个 EXE/DLL，不删除用户数据或手工覆盖系统服务文件。本次没有启动候选程序，也没有改动现役客户端、代理、TUN、后台服务、节点选择或用户配置。

上一可用包 [`FreedomCloud-windows-amd64-country-tls-159f16eecc78.zip`](../../dist/FreedomCloud-windows-amd64-country-tls-159f16eecc78.zip)（SHA256 `98d8a7a9ef7160af5f3148d5dfe8a260d78441968750cea5e6ae6825f966c2b8`）及对应解压目录完整保留。产品提交 `8a666bb` 已本地提交，本交付报告与台账另行本地记录；未推送、未合并、未启动候选、未实机验收。

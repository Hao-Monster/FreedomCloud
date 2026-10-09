# 运行诊断后续修复：Windows 构建与交付证据

日期：2026-10-09（Asia/Singapore）。源码提交：`485abf4d2e8664b8e03fb17ed63add2a3b2359c8`，分支 `development`，提交说明 `fix: bound residual resource lifecycles`。本报告为构建后的交付记录，不改变包内源码提交。

## 产物与范围

- [Windows amd64 免安装包](../../dist/FreedomCloud-windows-amd64-resourcefix-485abf4d2e86.zip)：**152,994,092 bytes**，73 个文件。
- [外部 SHA256 校验文件](../../dist/FreedomCloud-windows-amd64-resourcefix-485abf4d2e86.zip.sha256)。ZIP SHA256：`050695fe6ad62e64f4efcb4985fd9c65f75cbf4b61b9276820087a66a1f318c5`。
- 主交付位于 `E:\CodeWorkstation\FlClashX\dist`；同名、同 hash 副本位于 `C:\Users\冯飏\Documents\Codex\2026-10-08\new-chat\outputs`。两个位置均有校验文件，使用拒绝覆盖复制，复制后重新计算 hash 一致，旧包保留。
- 普通未签名预览；不包含严格 WFP 驱动/Broker。Core、Agent、Helper、UI 和原生插件完整重编，修复范围为 R1 日志收尾、R2 图标请求生命周期、R3 健康检查缓存，详见 [结果报告](../resource-followup-results-2026-10-09.md)。
- **运行验收 NOT RUN**。没有启动候选程序，没有退出或替换现役客户端/服务，没有操作代理、TUN、SCM、驱动或用户配置。

## 源码与输入

独立构建目录：`C:\Users\冯飏\Documents\Codex\2026-10-08\new-chat\work\rf2-485abf4d2e86`。目录中的 `source` 来自精确 Git archive，`native-build`、`bundle`、`zip-roundtrip` 均为新目录。

| 输入 | 已核对值 |
|---|---|
| Git commit | `485abf4d2e8664b8e03fb17ed63add2a3b2359c8` |
| Git tree | `cbbaa3be6aabb39fa107687dc8f34b3324ab0d0c` |
| source archive SHA256 | `ef072b9d70cb36a718142bc0f58aa3808914fb79942d2f6d78019c88eeff9a7d` |
| source inventory SHA256 | `fbb15f58e287a49bea898053a2755ba5e3f2fbe6ebc568dcee5964c9ad537b31` |
| source 文件数 / 解压 bytes | 931 / 60,806,860 |

独立审查将 931 个文件与 Git blob 核对。875 个归档文本文件使用 CRLF，归一行尾后对应 Git blob；其余按原字节核对。构建后的 7 个 registrant 仅行尾变化，语义源码变化为 0。没有将源 ZIP 声称为所有字节均与 Git blob 原文一致。

14 个 Windows 原生插件的锁条目与 111 个原生输入文件均核对。仓库内 proxy/tray_manager/window_ext 插件关联本次提交；第三方插件从锁定依赖重编。Flutter engine、QuickJS、9 个 MSVC CRT 文件和 EnableLoopback 为核验来源的预置输入，没有宣称全部第三方二进制均从源码重编。

## 实际构建与环境限制

执行时 HEAD 等于源码提交，tracked tree 干净：

```powershell
& 'C:\Users\冯飏\Documents\Codex\2026-10-08\new-chat\work\remediation-build-tools\Build-Remediation.ps1' -ExpectedSha '485abf4d2e8664b8e03fb17ed63add2a3b2359c8' -WorkRoot 'C:\Users\冯飏\Documents\Codex\2026-10-08\new-chat\work\rf2-485abf4d2e86'
```

构建脚本拒绝已有目录/产物、tracked 源码变化及 HEAD 变化，收尾再次验证来源。保留该目录作为证据；重新构建须使用新的路径。

- 开始 2026-10-09 19:28:07 +08:00，完成 19:36:38；wrapper **exit 0，512.152 秒**。
- Flutter 3.47.4 / Dart 3.13.3、Go 1.25.13、Rust 1.98.1、MSVC 14.44.35207、SDK 10.0.26100.0、经 hash 校验的 ATL 14.51.36237。
- 使用项目 `setup.dart` 和固定 Mihomo overlay；新 Core 编译并计算 hash 后再构建绑定该 hash 的 Helper。Rust 依赖 locked/offline，未改模块缓存或升级锁定依赖。

| 步骤 | 状态 / exit | 秒 |
|---|---|---|
| Git source archive | PASS / 0 | 4.34 |
| Flutter offline pub get | PASS / 0 | 32.76 |
| Core + Agent + Helper release | PASS / 0 | 146.58 |
| Flutter config-only | 已知环境失败 / 1 | 2.62 |
| CMake configure | PASS / 0 | 4.04 |
| Flutter release AOT | PASS / 0 | 62.84 |
| Windows runner / 原生插件 | PASS / 0 | 38.34 |
| Bundle install | PASS / 0 | 1.44 |
| tray DLL imports | PASS / 0 | 0.07 |
| 包元数据、checksums 与 ZIP | PASS / 0 | 11.51 |
| 73 文件 ZIP roundtrip / 输出复制 | PASS | 含在整体时间，未单独计时 |
| 独立静态产物审查 | PASS / 0，8 组通过 | 4.286 |
| dist 副本及校验文件核对 | PASS / 0 | 未单独计时 |

config-only 的唯一错误为 `Unable to find suitable Visual Studio toolchain`。构建工具只允许这一已知发现失败，随后使用已核验的 MSVC/CMake/Ninja 完成真实编译，没有跳过 Windows 构建或忽略未知错误。保留 strict-broker 依赖的既有 4 项 dead-code 警告和 MSVC `/W3` 被 `/W4` 覆盖提示。本次构建通过不覆盖结果报告中额外 default Helper clippy 的既有失败。

## 关键组件与绑定

| 组件 | bytes | SHA256 |
|---|---|---|
| FlClashCore.exe | 60,708,352 | `4732f223c9c783e6d9a1fe64ff52401f901b864ffa7b454d6554296fd886601e` |
| FlClashAgent.exe | 1,026,048 | `736a2bab2184fb2c6259dbe9323e7de3fa4de7c39699c963cfdade6b786dc95c` |
| FlClashHelperService.exe | 1,031,680 | `8fce9dc50e70d1d788b986d2d39dcdfb4d3157a3ebf0468eef898c8e73cb5a1b` |
| FlClashX.exe | 134,144 | `70a8d4a6ca3db11a52d2d684c6b75cd5346ef93d672f782fa4a7c6c1645bdd56` |
| data/app.so | 15,074,184 | `0a556b36f87357a2c6fa9a02b0ae05fc0361ce4a2e388c2ddd270ba41f5675ab` |
| tray_manager_plugin.dll | 116,736 | `0d2021a479db31f9e013c40edc454663c0008391bad43529dd3a43e28acc6e83` |
| proxy_plugin.dll | 98,304 | `12547911fbf762102ca84a40193abae09ea81c266f7d09f42bb30d1780b8ccf9` |

Helper 中完整 Core hash 出现 1 次，且与 UI 的实际编译配置一致：`APP_ENV=pre`、`APP_VERSION=resourcefix-485abf4d2e86`、`CORE_VERSION=v1.19.32`、`CORE_SHA256=4732f223c9c783e6d9a1fe64ff52401f901b864ffa7b454d6554296fd886601e`。核对的是生成配置及对应 AOT 输出，没有执行 UI 或声称从运行态读取编译值。

`go version -m` 静态读取 Core 确认固定 v1.19.32、本次 `.generated` 替换目录、with_gvisor、CGO=0、windows/amd64。`CORE-PATCH.json` 的 10 个模板、10 项 overlay 映射、1015 个有效模块文件一致，有效模块聚合 hash 为 `129ccaab30a64fb785e3ca5f5c626d3180fcfd172cfacf156e729b63f92e436c`。

## 独立审查、证据与验收边界

非构建作者执行只读审查，8 组 PASS，无产物阻塞发现：

- 73 个 ZIP/bundle 文件的路径、长度、hash 一致，72 项内部校验覆盖除清单自身外的全部文件；外部校验与构建报告一致。
- 32 项组件描述、4 个 backend 输出、15 个 native 输出及 AOT 与本次编译输出一致；插件与预置输入来源一致。
- 30 个 PE 中 29 个 x64；唯一 x86 是来源已记录的 EnableLoopback。托盘 DLL 导入 DestroyMenu，未导入 RemoveMenu。
- 包内集合没有 strict 驱动/Broker、用户配置、订阅、安全存储、用户数据库、密钥或运行日志；包含正常运行所需的静态 ASN.mmdb、geoip.metadb。README 如实说明普通未签名、共享配置、启动副作用和回退。

私有证据目录：`C:\Users\冯飏\Documents\Codex\2026-10-09\resource-followup-184840`，包含 `windows-build-console.log`、`windows-build-result.json`、`artifact-audit-485abf4d2e86.json`、`artifact-static-details-485abf4d2e86.json` 和 `artifact-delivery-485abf4d2e86.json`。构建根目录另有 `build-report.json`、`logs/steps.jsonl`、源码清单与插件输入清单；outputs 有 `resourcefix-build-485abf4d2e86.json`。包内保留 BUILD-INFO、COMPONENTS、CORE-PATCH、SHA256SUMS 和 PREVIEW-README。

真实 UI/页面导航、Win32 提取压力、SCM/SYSTEM 退出、代理/TUN、真实网络和长时间 RSS/USER/GDI/句柄曲线仍 **NOT RUN**。静态产物审查和隔离回归不能证明长期无泄漏，当前正在运行的版本未收到本轮修复。

用户测试时完整解压到新目录，保留旧包与配置备份，按自己的测试时间完整退出当前客户端再切换。免安装包共享用户配置，启动会按产品规则启动/接管代理并按保存的 TUN 设置请求权限。回退使用完整匹配的旧包，不单独混换 Core/Helper，不删除用户数据。本轮仅本地提交和交付，无推送、PR、合并或发布。

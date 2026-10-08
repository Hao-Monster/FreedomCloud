# Windows 托盘菜单资源修复：测试基线

日期：2026-10-08。任务：修复托盘菜单资源泄漏并构建 Windows amd64 预览包。保持当前运行客户端、代理、TUN 和服务不变；保留旧包和用户已有 QA 文件。

## 验收矩阵（实现前固定）

| 验收标准 / 风险 | 验证层级与场景 | 预期 |
|---|---|---|
| 多次菜单刷新泄漏 | 原生菜单生命周期回归；多层子菜单重复替换 | 原路径遗留旧子菜单；修复后所有旧菜单树释放，资源数量有界 |
| 菜单展示时刷新 | 原生回归；展示期间多次提交新菜单 | 当前展示树始终有效，只保留最新待应用树，结束展示后替换 |
| 创建/挂接失败 | 原生失败注入；根、嵌套菜单创建及 Append 失败 | 新树回滚、旧树保留、真实错误返回，无未挂接菜单遗留 |
| 生命周期结束 | 原生回归；销毁插件及待应用菜单 | 所有自有菜单释放，重复清理不重复销毁 |
| 稳定 TUN 观察 | Dart 回归；多次相同状态观察 | 保留 TUN 观察，完整菜单不因稳态轮询重复刷新 |
| TUN 状态显示 | Dart 回归；observed、desired、busy、failure 变化 | 菜单及时反映必要显示变化，不丢失忙碌、错误及恢复状态 |
| 更新等待与交错 | Dart 回归；多入口刷新、force/focus 请求、失败 | 等待真实更新完成，更新串行且待更新可合并，最新状态与 force 保留，失败不伪装成功 |
| 可见菜单点击映射 | Windows 插件通道回归；展示 A 期间成功提交 B/C、更新失败、在途更新与 popup 交错 | 点击准确分发到实际展示的菜单快照；失败更新保留旧映射；没有延迟 WM_COMMAND 对最新菜单的误查 |
| popup 中插件结束生命周期 | 原生回归；tracking 时释放 owner | 当前树保留至 tracking 返回；不访问已释放插件或向已结束引擎回调 |
| 托盘注册失败 | 原生失败注入；Shell 图标注册/修改失败后重试 | 返回真实失败，回收多余图标并保留唯一恢复资源；后续更新能够重新注册 |
| 原功能回归 | Flutter 相关模块与全套测试、目标 analyze | 无本次新增失败；保留选择节点、配置、tooltip、TUN/代理启动等既有行为 |
| 原生组件确实修复 | 新 DLL 导入表、hash 和编译日志 | 新 DLL 包含菜单释放路径，不能复用旧有缺陷 DLL |
| 组件兼容与来源 | Core/Agent/Helper hash、Git 差异、构建 defines | 未改后端复用来源明确、hash 匹配，Core hash 与 UI/Helper 绑定一致 |
| 打包完整 | 构建、清单、ZIP 解压逐文件核验 | 新包命名不覆盖旧包；文件集、长度、hash 一致；不携带用户配置或凭据 |

## 验证约束

- 不启动完整候选客户端，不操作当前网络、服务或 UAC。
- 原生资源测试限于测试进程自有菜单，使用独立桌面或测试替身，不能向当前客户端注入故障。
- Windows 真实菜单 USER 计数若受执行环境限制，准确记录失败原因和替代证据；不能把替身测试称为实机验收。
- 缺陷回归尽力建立 Red → Green。源级测试与实际新 DLL 编译证据分别记录。
- 不运行无关 Go/Rust 后端全量测试；本次不修改后端，复用组件逐文件核验。
- 本次未授权远端推送、发布或本机客户端切换。

## 执行记录

执行跨至本地 2026-10-09。环境：Windows x64；Flutter 3.47.4 / Dart 3.13.3；MSVC 14.44.35207；Windows SDK 10.0.26100.0。CI 固定 Flutter 3.41.7，本轮未推送或触发新 CI。

### 实现与独立审查

- 仓库内 `plugins/tray_manager` 持有菜单树：成功构建后替换，失败回滚；挂接成功才转移子菜单所有权，根释放使用 `DestroyMenu`。展示期间只保留当前与最新 pending 菜单树。
- Windows popup 通过 `TPM_RETURNCMD | TPM_NONOTIFY` 返回选中项。Dart 在 FIFO 的短操作中等待此前 setter、捕获已安装菜单并发送 popup；后续更新不阻塞，点击分发使用实际展示快照。setter 成功后才更新映射，旧 checkbox 不覆盖最新菜单。
- 局部共享 `MenuLifetime` 保护 popup 内 owner 销毁；disposed 时拒绝新菜单，tracking 返回后不访问插件成员、不回复已结束引擎。
- 原生图标保持唯一自有 HICON；ADD/MODIFY 失败如实返回，保留可恢复资源；Explorer/恢复事件按自有资源重试。公开 `destroy()` 保留只移除图标的语义。
- TUN 显示快照变化才触发菜单刷新；完整更新串行合并并等待真实成功或错误，tooltip 仍独立。非 Windows 原生事件的既有逐 listener/checkbox 回调语义保留。
- 两名独立代理审查后，已修复其指出的可见菜单映射、owner 销毁和图标失败恢复问题；最终无剩余已知中/高风险源码发现。动态验收缺口见下文。

### 实际执行

所有命令在 `E:\CodeWorkstation\FlClashX` 执行；新覆盖率/全量日志位于本次聊天 `work/tray-tests`，原生/插件日志位于被忽略的 `plugins/tray_manager/windows/tests/build`。用户已有 `coverage/` 和 QA 文件未纳入提交。

| 命令 / 阶段 | 结果 | Exit | PASS / FAIL / SKIP | 耗时 |
| --- | --- | --- | --- | --- |
| `flutter test --no-pub test/common/tray_refresh_test.dart` 修复前有效目标测试 | RED；状态/等待/并发回归失败 | 1 | 1 / 4 / 0 | 未单独采集 |
| 该目标与 5 个既有 TUN/启动套件 | PASS | 0 | 53 / 0 / 0 | 8.205 s |
| `flutter test test/common/tray_plugin_menu_test.dart --reporter expanded` 跨层修复前 | RED；旧菜单点击、失败映射、顺序、popup guard | 1 | 2 / 5 / 0 | 未单独采集 |
| 同文件 `--plain-name 'legacy checkbox callback refreshes the latest replaced menu per listener'` 兼容修正前 | RED；旧菜单重装且第二 listener 重复动作 | 1 | 0 / 1 / 0 | 未单独采集 |
| 最终 `flutter test test/common/tray_plugin_menu_test.dart --reporter expanded` | PASS | 0 | 10 / 0 / 0 | 未单独采集 |
| `flutter test --no-pub --coverage --branch-coverage --coverage-package=flclashx --coverage-package=tray_manager --coverage-path=<chat work/tray-tests/lcov-final.info> --reporter expanded` | PASS；最终冻结源码全量 | 0 | 388 / 0 / 0 | 34.711 s |
| `./plugins/tray_manager/windows/tests/Run-Tests.ps1 -Mode LegacyProbe` | 预期旧操作失败：脱挂子菜单后销毁根，子/孙菜单仍有效 | 子进程 2，命令包装 1 | 预期失败 1 | 1227 ms |
| `... -Mode Regression` | PASS；全部 3 个创建、7 个 Append 失败点，owner 结束生命周期及 7 个图标注册序列 | 0 | 8 组 / 0 / 0 | 979 ms |
| `... -Mode Win32` | PASS；私有未显示 desktop 内 200 次真实多层菜单替换、owner dispose/reset、late 更新拒绝，USER 1 → 1 | 0 | 1 进程 / 0 / 0 | 1351 ms |
| `... -Mode NativeCompile` | PASS；生产插件 `/W4 /WX /EHsc /D_HAS_EXCEPTIONS=0` 编译 | 0 | 编译通过 | 1334 ms |
| `flutter analyze --no-pub` 7 个受影响 Dart/测试文件 | 0 error、0 warning、85 个既有 info；原始 exit 仍为 1，未降低规则 | 1 | 非测试统计 | 见 `analyze-final-result.json` |
| `git diff --check`（主包原已跟踪变更） | PASS | 0 | 不适用 | 未单独采集 |
| 完整 `git diff --cached --check` | FAIL：复制的上游 Linux/macOS 和 Windows 旧空行有 trailing whitespace；Windows 两处已清理 | 非零 | 不适用 | 未单独采集 |
| `git diff --cached --check -- . ':(exclude)plugins/tray_manager/linux/CMakeLists.txt' ':(exclude)plugins/tray_manager/macos/Classes'` | PASS；本轮修改/新增文件检查；4 个被排除的上游文件与本地 cache 逐个 hash 相同，保留其原始字节 | 0 | 不适用 | 未单独采集 |

原生旧 probe 与修复后生产 builder 使用不同程序；这是旧操作泄漏复现与新实现资源回归，不是完整客户端同一用例的二进制 Red → Green。旧 probe 退出前释放演示的孤儿菜单。初次全量覆盖率参数使用带 `|` 的正则时，Windows `.bat` 入口发生 shell 参数错误（exit 255，测试未运行）；改用官方支持的两个 `--coverage-package` 参数后得到上表最终结果。初次分析中的 4 个新增测试 info 已修正，最终剩余 85 个存量 info。

### 覆盖率

最终 LCOV 含主包及 tray_manager，共 232 个文件。行覆盖 5079/27637（18.38%）；分支覆盖 1410/9481（14.87%）。这是包含大量未触及功能的全仓数据，不代表完整业务或系统验收。

| 受影响文件 | 文件行覆盖 | 文件分支覆盖 | 本次主包新增/修改可执行行 |
| --- | --- | --- | --- |
| `lib/common/tray.dart` | 117/173 | 26/54 | 25/25 |
| `lib/common/tun_runtime.dart` | 117/120 | 52/59 | 5/5 |
| `lib/controller.dart` | 50/1180 | 26/556 | 1/1 |
| `lib/manager/tray_manager.dart` | 29/82 | 10/39 | 5/8 |
| `plugins/tray_manager/lib/src/tray_manager.dart` | 79/110 | 34/49 | vendored 源另列，不将复制的上游代码算作全部新增逻辑 |

主包修改可执行行共 36/39（92.31%）；未命中的是 manager 121、134、140 的既有 trayState/亮度/恢复入口，逻辑仅改为明确 `unawaited`。实际 Windows 亮度/恢复事件与 popup 鼠标交互未运行。原生 C++ 未启用覆盖率 instrumentation；创建/Append 失败点、生命周期和图标注册分支由明确的生产 helper 回归覆盖，不编造 C++ 覆盖百分比。

### 打包来源与边界

新包使用本轮修复的精确本地提交 `git archive` 源码快照，完整重编 Windows runner、所有原生插件、Dart AOT 和 assets。不复用旧托盘 DLL。新 DLL 必须含 `DestroyMenu` 导入且 SHA256 与旧包不同；包内清单和 ZIP 解压逐文件集合/长度/hash 均须通过。

Core/Agent/Helper 未修改；`b2cccee7303d4d5e0f0a2d94d03fab367814bd6a..本轮提交` 的 `core/services/libclash/include` 无差异。逐文件重验旧包后复用其三组件与 CORE-PATCH manifest，并在 COMPONENTS.json 逐项声明来源。Core v1.19.32、SHA256 `6caa426bb583547d9123bfe3f746893ffbff9719ecadf972aee93259d24add64` 必须同时匹配 UI define 和 Helper 绑定。实际构建、产物 SHA256 和最终解压结果在新包交付报告及 BUILD-INFO 中追加；此节是构建来源要求。

NOT RUN：完整候选应用运行、真实鼠标 popup、真实 Flutter engine 在 popup 内销毁、当前 Explorer 恢复前后对照、长时 USER/GDI、实际 Shell 故障/重启/睡眠、代理/TUN/UAC/服务及路由验收、Linux/macOS 构建。普通包未签名，不包含严格 WFP 驱动/Broker。不改变当前运行客户端或网络，不将资源回归、源码审查、完整构建等同于本机故障已恢复。

## 最终构建与封装结果（2026-10-09 本地时间）

- 源码提交 `71a07a9d7ad0502d4a3eef1527e499460542b026`，tree `6395c5a9fb28fbf33155daeb744dd7836b32508e`。Git archive SHA256 `50b4bc244f85aa224d5fb996f7758b1476a6613a618171d07f081c2016c97a5a`；未创建 clone/分支/worktree，也未修改旧构建目录。
- `Build-TrayPreview.ps1 -ExpectedSha 71a07a9... -WorkRoot <chat work/tray-build-retry1>`：source archive、离线 pub get、CMake/Ninja fresh configure、Dart AOT/assets、64 个原生编译/链接步骤及 install PASS。Flutter config-only 的 exit 1 是已知且唯一的 VS 发现限制，精确门禁通过后转用 CMake/Ninja；完整原生 build exit 0，26.39 s。
- 包装工具的准备阶段先修复了 Git 正/反斜杠比较和 PowerShell 大小写同名 typed-string 参数问题；失败目录和证据保留。首次 package 因 treeState 字符串不属于 `clean/dirty/unknown` 而 exit 255，未发布失败产物。改为 `clean` 后，`Finish-TrayPreview.ps1` 从完整原生成功 bundle 逐文件验证并复制到新目录，只重做封装；原 FAIL 报告/日志/source/bundle hash 全部保留。最终 driver analyze、package、DLL imports、ZIP roundtrip exit 0。
- 新 `tray_manager_plugin.dll` SHA256 `39625c5e0630fd718bdfcafa4f7574bc3715835b4d9f9999fac16656c21db428`，确认有 `DestroyMenu` 导入；旧 DLL SHA256 `d4a0a1dfc73d35edc777c8ed37d95b2ffe82343e3822be7045ec88bef402b04e`，无该导入。新 `data/app.so` SHA256 `974602488db84ba5a9bb6b4dda015582fdde809a4050b111df45f5cdd14dc758`。
- Core/Agent/Helper 和 CORE-PATCH 固定 hash 验证通过；Helper 实际二进制内嵌 Core SHA256 与所打包 Core 一致。UI 的 CORE_VERSION/CORE_SHA256 构建 define 校验通过；不把原始 AOT 字符串搜索当作绑定证明。
- 交付 `FreedomCloud-windows-amd64-trayfix-71a07a9d7ad0.zip`：152,755,710 字节，SHA256 `11dc19f930ebbe90e266bdd3d39611e8cdb9bd8ecb7c4f32d3ac3f75e7a2302d`；73 文件 ZIP/解压/交付集合、长度、hash 全部 PASS。最终 JSON 构建报告明确保留原生 build 成功与首轮 package 失败/恢复记录。
- Native 构建实际开始 UTC `2026-10-08T16:06:51.7502717Z`，最终 package 元数据 UTC `2026-10-08T16:25:49.703501Z`；源码 commit UTC `2026-10-08T16:05:07Z` 单独记录，没有把 commit 时间冒充实际 build 时间。
- 包放在本次聊天 outputs，并准备仓库 dist 同名无覆盖副本。原 coverage/QA 5 文件逐项长度/hash 一致；旧预览保留。当前旧客户端、代理/TUN/服务未操作；真实应用验收边界保持 NOT RUN。
- 独立只读产物审查 PASS：bundle/ZIP 73 文件、SHA256SUMS 72 项及 COMPONENTS 31 项逐项匹配；源码 commit/tree 与 Git 实值一致，新 DLL 含 DestroyMenu/CreatePopupMenu/TrackPopupMenu 且无 RemoveMenu。Core/Agent/Helper 与旧包固定来源一致，Helper 内嵌 Core hash 匹配；文件清单无用户配置、订阅、数据库或密钥凭据文件。Runner/托盘 DLL/Core/Agent/Helper 实测 NotSigned，无 strict 驱动/Broker，README 正确披露实机 NOT RUN。审查未启动任何组件，未发现打包阻塞问题。

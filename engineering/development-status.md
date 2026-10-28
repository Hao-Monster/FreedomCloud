# 开发、集成与预览台账

更新日期：2026-10-28。当前阶段是快速开发、快速迭代和部分功能预览。本文记录来源与验收边界；每次继续开发仍需核实实际 Git/PR/CI 状态，不能把历史报告视为当前通过证明。

## 跨配置节点总览订阅列表默认按可用节点数降序排列（2026-10-28）

- 来源：针对“代理 → 全部配置”（[`NodeOverviewView`](file:///E:/CodeWorkstation/FlClashX/lib/views/proxies/overview/overview.dart#L151-L156)）左侧配置栏、窄屏配置筛选下拉框及右侧全部配置平铺分区仍按原始导入顺序排列导致可用节点多的配置被 `0` 可用配置埋没的问题，从基线 `development@d051a12` 实现按配置可用节点数（`delay > 0`）默认降序排列。
- 核心实现：
  1. **与 [`_HealthSummary`](file:///E:/CodeWorkstation/FlClashX/lib/views/proxies/overview/overview.dart#L2224-L2289) 口径一致的可用节点数统计与稳定降序排序**：在 [`_NodeOverviewViewState.build`](file:///E:/CodeWorkstation/FlClashX/lib/views/proxies/overview/overview.dart#L723-L869) 中单次遍历 `profiles`，活动配置按 [`_activeDisplays`](file:///E:/CodeWorkstation/FlClashX/lib/views/proxies/overview/overview.dart#L1715-L1779) 统计 `(entry.delay ?? -1) > 0` 数量，非活动配置结合已加载/缓存 `ProfileCatalog` 或后台索引摘要 [`_IndexedProfileCountrySummary`](file:///E:/CodeWorkstation/FlClashX/lib/views/proxies/overview/overview.dart#L185-L210) 与 `nodeHealthEntriesProvider` 统计有效节点（排除 `loading` / `fileMissing` / `parseFailed` 目录与单节点 `parseFailed`）的 `delayMs > 0` 数量，生成降序排列且相同可用数按原始顺序稳定兜底的 `orderedProfiles`。
  2. **三处展示统一与既有契约保全**：宽屏侧边栏（[`overview-sidebar`](file:///E:/CodeWorkstation/FlClashX/lib/views/proxies/overview/overview.dart#L1030-L1058)，补充卡片 `ValueKey('overview-sidebar-card-${profile.id}')`）、窄屏下拉框（[`overview-profile-filter`](file:///E:/CodeWorkstation/FlClashX/lib/views/proxies/overview/overview.dart#L910-L929)）及右侧“全部配置”分区列表（[`overview-nodes`](file:///E:/CodeWorkstation/FlClashX/lib/views/proxies/overview/overview.dart#L1062-L1082)）统一接入 `orderedProfiles`；点击侧边栏切换单个配置时侧边栏排序保持稳定不跳动；`overview-test-all` 保持传入原始 `profiles` 顺序不变；未选中屏外 `0` 可用配置继续保持按需加载与 `profileCatalogProvider` 的 `autoDispose` 内存边界，屏外高可用数配置在有界后台索引完成后自动晋升置顶。
- 验证记录（本机 `Flutter 3.47.4` / `Dart 3.13.3`，CI 配置 `3.41.7`）：
  - 前置有效 Red（[`test/views/node_overview_test.dart`](file:///E:/CodeWorkstation/FlClashX/test/views/node_overview_test.dart#L3478-L3746)）：退出码 `1`（`85 PASS / 2 FAIL`）；
  - 组件与回归测试（`flutter test --no-pub test/views/node_overview_test.dart`，含活动/非活动混排、同分稳定兜底、单配置选中侧栏稳定、窄屏下拉框顺序、屏外高可用数配置索引置顶及 `autoDispose` 断言）：**PASS（87 PASS / 0 FAIL）**；
  - 静态检查（`dart analyze lib/views/proxies/overview/overview.dart test/views/node_overview_test.dart`）：**PASS（0 error / 0 warning / 0 新增 info）**；`git diff --check` 通过；`pubspec.lock` 未改动。
- 交付状态：**已实现 / 已本地验证并提交至本地 `development`**；未推送远端（未经推送授权，当前工作树位于 `E:\CodeWorkstation\FlClashX`） / 未创建或合并 PR / 远端 CI **NOT RUN** / 未重打静态预览包 / 未启动候选窗口（未触碰本机运行中代理、TUN 及后台服务） / 后端部署与业务验收 **NOT RUN**。下一步：如需预览包或推送 `freedomcloud/development` 可按授权继续执行。

## 跨配置节点总览单节点“延迟测试”文字按钮统一与活动配置补齐（2026-10-28）

- 来源：针对“代理 → 全部配置”（[`NodeOverviewView`](file:///E:/CodeWorkstation/FlClashX/lib/views/proxies/overview/overview.dart#L151-L156)）单节点测速闪电按钮（`Icons.bolt`）在活动配置节点行缺失及图标语义不直观的问题，从基线 `development@3656c4e` 将单节点测速入口统一改为文字按钮 **`延迟测试`**（`nodeOverviewTestNode`），并同时覆盖活动配置与非活动配置节点行。
- 核心实现：
  1. **单节点文字按钮替换闪电图标**：新增 [`_buildTestButton`](file:///E:/CodeWorkstation/FlClashX/lib/views/proxies/overview/overview.dart#L1509-L1528) 与自适应头部行布局 [`_buildNodeHeaderLayout`](file:///E:/CodeWorkstation/FlClashX/lib/views/proxies/overview/overview.dart#L1560-L1606)（宽屏单行并排、窄屏 `< 460 * textScale` 自动折行防溢出），替换 [`_InactiveNodeRow`](file:///E:/CodeWorkstation/FlClashX/lib/views/proxies/overview/overview.dart#L2044-L2091) 原 `IconButton(icon: Icons.bolt)`，保持 P1 隔离测速不支持项（`parseFailed` / `chainUnsupported` / `typeUnsupported` / `strictModeUnsupported`）不暴露隔离测速按钮的安全边界不变；四语种 `arb/intl_*.arb` 与 `lib/l10n/*` 同步更新（`zh_CN`：`延迟测试`、`en`：`Delay test`、`ja`：`遅延テスト`、`ru`：`Тест задержки`）。
  2. **活动配置节点行补齐单节点“延迟测试”**：在 [`_ActiveDisplay`](file:///E:/CodeWorkstation/FlClashX/lib/views/proxies/overview/overview.dart#L1622-L1632) 保留代理组有效 `testUrl`，新增 [`_NodeOverviewViewState._testActiveNode`](file:///E:/CodeWorkstation/FlClashX/lib/views/proxies/overview/overview.dart#L528-L537) 接入共享协调器 `_tester.testCurrent`，并在 [`_ActiveNodes`](file:///E:/CodeWorkstation/FlClashX/lib/views/proxies/overview/overview.dart#L1700-L1817) / [`_ActiveNodeRow`](file:///E:/CodeWorkstation/FlClashX/lib/views/proxies/overview/overview.dart#L1819-L1928) 渲染 `ValueKey('overview-test-${profile.id}-${entry.proxy.name}')` 的 `延迟测试` 按钮（在 `tester.busy || entry.delay == 0 || profile.isUpdating` 时自动禁用），消除切换活动配置后测速按钮消失的问题。
- 验证记录（本机 `Flutter 3.47.4` / `Dart 3.13.3`，CI 配置 `3.41.7`）：
  - 前置有效 Red（`test/views/node_overview_test.dart`）：退出码 `1`（`82 PASS / 3 FAIL`）；
  - 组件与回归测试（`test/views/node_overview_test.dart`，含新增中英文双态单节点测速断言）：**PASS（85 PASS / 0 FAIL）**；
  - 静态检查（`dart analyze lib/views/proxies/overview/overview.dart lib/l10n test/views/node_overview_test.dart`）：**PASS（0 error / 0 warning / 0 新增 info）**；`git diff --check` 通过；`pubspec.lock` 未改动。
- 交付状态：**已实现 / 已本地验证并提交至本地 `development`**；未推送远端（因未经推送授权，当前本地 `development` 位于 `E:\CodeWorkstation\FlClashX`） / 未创建或合并 PR / 远端 CI **NOT RUN** / 未重打静态预览包 / 未启动候选窗口（未触碰本机运行中代理、TUN 及后台服务） / 后端部署与业务验收 **NOT RUN**。下一步：如需预览包或推送 `freedomcloud/development` 可按授权继续执行。

## Windows 仅兑换码购买与核销工作台 v2 预览交付（2026-10-26）

- 固定源码：`development@8a666bb0100503848010d7d565e42e61d9c2320b`（Git tree `e4cb32b3164b17bf262d6b70f844c735569c7304`），干净 tracked Git archive；UI/Core/Agent/Helper 与仓库原生插件同批新编，来源与 SHA256 绑定已核对。
- [Windows amd64 预览包](../dist/FreedomCloud-windows-amd64-purchase-v2-8a666bb01005.zip)：166,041,571 bytes；SHA256 `1fd3a06fdc360b2185d1bacde4186158250d27b1a6415ff899c45a1c0552c2ad`。已安全解压目录 [`FreedomCloud-windows-amd64-purchase-v2-8a666bb01005`](../dist/FreedomCloud-windows-amd64-purchase-v2-8a666bb01005/)，启动入口 `FlClashX.exe`。
- 构建 PASS、两次 ZIP/解压逐文件校验 PASS（73 文件 / 72 checksum）、独立静态审计 8/8 PASS；同提交单测 `test/purchase` 315/315 PASS、全仓 981/981 PASS。工具版本（本机 Flutter `3.47.4` vs CI `3.41.7`）与全部边界见[交付报告](testing/windows-purchase-v2-preview-2026-10-26.md)。
- 普通未签名预览，不含 strict WFP 驱动/Broker；现有生产 HTTP CONNECT 证书放行行为保留并已披露。上一可用包 `country-tls-159f16eecc78`（SHA256 `98d8a7a9ef7160af5f3148d5dfe8a260d78441968750cea5e6ae6825f966c2b8`）、现役四进程 PID（`5344`/`8904`/`19472`/`25704`）、覆盖率、QA、probes 和 `stash@{0}` 均完整保留。
- 已构建 / 已交付静态预览包；未推送 / 未创建 PR / 远端 CI NOT RUN / 候选未启动 / 真实代理、TUN、服务及线上发卡消费业务验收 NOT RUN。下一步：用户按包内 `PREVIEW-README.txt` 手工验证。

## 剩余旧工作树归属核查与清理（2026-10-25）

- 来源：用户授权继续检查上一轮剩余 22 个工作树，核实草稿合并/重复/替代关系后，完成备份恢复并继续清理。固定语义基线 `591481f`；调查期间形成的购买页提交 `cb68fb9` 已保全，其 20 个改动路径与本轮旧草稿无交集。
- 154 个普通草稿文件项逐文件/逐 hunk 核查：76 当前内容一致、47 精确对应已集成历史、28 已吸收或后续替代（含格式差异）、2 重复补丁、1 错误 ZIP 草稿；unique/unknown=0。UAC `f082792` 另核实已由 `bbece1b` / `6eb440b` 吸收；初始化异常 HEAD 已恢复 694 个文件且干净。
- 21 个旧工作树全部正规移除，失败/跳过 0；登记数 **22 → 1**，仅保留主开发树。全部分支/stash、现役/上一包、购买页新提交、主树共享 SDK 和原 QA/probes/coverage 保留；没有回灌旧整文件。
- 新 bundle / 22 HEAD、19 个普通脏树恢复、21 树全部普通文件载荷（32,309 文件 / 5,179,543,944 bytes；ZIP 共 2,191,086,505 bytes）实际恢复和 SHA256 均 PASS。移除后 refs/stash、主树状态/untracked、关键包/EXE、共享 SDK 的 8,820 文件 hash 及现役 PID 核对 PASS。
- 私有恢复位置：`C:\Users\冯飏\AppData\Local\FlClashX-Recovery\cleanup-remaining-20261025`；来源矩阵、完整载荷、排除项与恢复边界见[剩余工作树清理记录](cleanup-remaining-worktrees-2026-10-25.md)。本轮 4 个演练副本在最终验证后已清理，ZIP/bundle/恢复记录保留。
- 已清理 / 已本地验证；仅文档本地提交，未推送 / 未创建或合并 PR / 未构建新预览 / 未部署。编译、真实系统与业务验收 NOT RUN。

## 仅兑换码购买页 UI/UE 工作台重构与体验优化（2026-10-25）

- 来源：基于购买页方案 [`purchase-redemption-2026-10-11.md`](file:///E:/CodeWorkstation/FlClashX/engineering/plans/purchase-redemption-2026-10-11.md)（仅兑换码 v2）与产品/UX 优化规范，从基线 `development@591481f` 完成 `D1`–`D5` 客户端购买页重构，严格保持“外部渠道获码 + 客户端核销 `type4` 套餐码/兼容 `type1–3` 旧卡 + 自动同步订阅”的唯一业务主线，未引入钱包、余额、报价、选支付方式或在线订单，未改动 `Xboard-Go` 后端及其他客户端页面。
- 核心实现：
  1. **桌面双栏“左橱窗 + 右工作台”与窄窗直达核销架构**：重写 [`PurchaseCenter`](file:///E:/CodeWorkstation/FlClashX/lib/views/purchase/center.dart#L15-L416)，在 `>= 860 * textScale` 宽窗采用左侧自适应套餐橱窗 + 右侧 `356–420px` 核销/账户工作台并排布局（彻底消除单套餐右半屏留白黑洞与多套餐下有码用户滚屏痛点），窄窗自动回退纵向单列并在顶部提供跳过 `Tab` 陷阱的“已有兑换码？直达核销”锚点按钮（`purchase-jump-workbench`）。
  2. **高信息密度套餐卡片、国旗徽标与不建单购码抽屉**：重写 [`PurchasePlanCatalog`](file:///E:/CodeWorkstation/FlClashX/lib/views/purchase/plan_catalog.dart#L14-L600)，单套餐自动通栏展开、多套餐响应式双列网格；复用 [`inferCountryCodeFromText`](file:///E:/CodeWorkstation/FlClashX/lib/common/node_country.dart) + `Twemoji` 渲染国家国旗徽标，支持混合目录 `全部套餐 / 周期订阅 / 按量流量包` 筛选胶囊、余量稀缺/售罄角标、长 Markdown 说明渐进展开，以及卡片底部“获取此套餐兑换码”抽屉（支持一键复制带套餐名/流量/标价的客服咨询话术、复制两个微信号与打开礼品卡商店，零建单/零兑码副作用）。
  3. **品牌去 `Xboard` 化、支票级权益核验卡与默认折叠历史**：更新四语种 `arb/intl_*.arb` 与 `lib/l10n/*` 清理界面暴露的 `Xboard` 字样，并将 [`PurchaseProfileSynchronizer.synchronize`](file:///E:/CodeWorkstation/FlClashX/lib/services/purchase_profile_sync.dart#L56-L58) 新建托管配置默认标签改为 `'FreedomCloud · ${account.email}'`（保留 `xboard-$ownership` ID 与安全请求头标记）；兑换码输入框内置智能清洗粘贴与清空按钮，核验后呈现含 `兑换前 → 兑换后` 对比及新开通/续费徽标的确认卡；成功回执置顶并附一键查看配置与节点入口（`purchase-open-profiles`）；兑换记录默认收起并展示总数角标，按需展开分页；所有 `JetBrainsMono` 混排文本均补齐 `_cjkMonoFallback` 中文字体回退链。
- 验证记录（本机 `Flutter 3.47.4` / `Dart 3.13.3`，CI 配置 `3.41.7`）：
  - 基线测试 `test/purchase`：**PASS（296 PASS / 0 FAIL）**；`D1` 新目标用例前置验证：**有效 Red（退出码 1，24 PASS / 10 FAIL）**；
  - 购买模块全量测试（含新增 [`purchase_v2_ux_test.dart`](file:///E:/CodeWorkstation/FlClashX/test/purchase/purchase_v2_ux_test.dart) 覆盖 `R01`–`R12`）：**PASS（302 PASS / 0 FAIL）**；
  - 全仓 Flutter 回归测试（`flutter test --no-pub -j 4`）：**PASS（968 PASS / 0 FAIL）**；
  - 静态检查（`dart analyze`）：**PASS（0 error / 0 warning / 0 info）**；`git diff --check` 通过；`pubspec.lock` 未改动；
  - 离线真实 Widget 合成数据渲染与逐图视觉复核：**PASS**（产物位于 `build/purchase-preview/*.png` 与 `build/plan-card-rich-content-preview/*.png`，详细记录见 [`engineering/testing/purchase-redemption-2026-10-11.md`](file:///E:/CodeWorkstation/FlClashX/engineering/testing/purchase-redemption-2026-10-11.md) 与 [`engineering/tasks/purchase-redemption-2026-10-11.md`](file:///E:/CodeWorkstation/FlClashX/engineering/tasks/purchase-redemption-2026-10-11.md)）。
- Code Review 复核与修复（针对 `development@cb68fb9` 的 `CR-01`–`CR-07` 共 `2 P1 / 3 P2 / 2 P3`）：
  1. **[CR-01 / P1] 修复长 Markdown 渐进折叠按物理行硬切破坏 GFM 表格与围栏代码块**：在 [`summarizePlanMarkdown`](file:///E:/CodeWorkstation/FlClashX/lib/views/purchase/plan_catalog.dart#L329-L433) 中改为块级结构感知摘要，跳过前导空行并保证 GFM 表格结构、围栏代码块及 `<u>` 标签成对闭合。
  2. **[CR-02 / P1] 修复剪贴板智能粘贴误取时间戳/URL 端口及超长码 32 位静默截断**：新增 [`extractRedemptionCodeFromClipboard`](file:///E:/CodeWorkstation/FlClashX/lib/views/purchase/center.dart#L12-L55)，剥离 URL 与时间格式后优先提取标签卡密，并移除 `substring(0, 32)` 与输入框 `maxLength: 32`，确保超长无效串交由本地 `gift_code_format` 报错拦截。
  3. **[CR-03 / P2] 修复获码弹窗微信按钮误标“微信号”、遮罩下弹条遮挡与非响应式状态**：抽离 [`_AcquirePlanSheet`](file:///E:/CodeWorkstation/FlClashX/lib/views/purchase/center.dart#L1364-L1570)，微信复制按钮修正为 `l.copy`（“复制”），改为弹窗内联即时反馈条并监听 `manager` 动态更新商店入口。
  4. **[CR-04 / P2] 修复多国套餐只显示单国旗及英文营销词误判国家徽章**：新增 [`resolvePlanRegionBadge`](file:///E:/CodeWorkstation/FlClashX/lib/views/purchase/plan_catalog.dart#L265-L327)，按出现顺序渲染双国旗（`🇯🇵 🇸🇬`）、全球/多国渲染 `🌐`，剔除 `MY`/`IN` 等营销词冲突。
  5. **[CR-05 & CR-06 & CR-07 / P2–P3] 修复混合套餐筛选显隐、纯空格清空按钮联动、登出失败状态保护、键盘焦点可达性、手风琴无障碍语义与代码格式**：新增 6 组 TDD 回归测试（前置有效 Red：`6 PASS / 6 FAIL`），修复后 `test/purchase` **308 PASS / 0 FAIL**、全仓 **974 PASS / 0 FAIL**、`dart analyze` `No issues found!`、`dart format` 零差异。
- 二轮深度 Code Review 复核与修复（针对 `cb68fb9..0631995` 的 `CR2-01`–`CR2-06` 共 `2 P1 / 3 P2 / 1 P3`）：
  1. **[CR2-01 / P1] 修复剪贴板误抓日期/邮箱/状态码及键盘 `Ctrl+V` 带连字符兑换码本地校验误杀**：在 [`extractRedemptionCodeFromClipboard`](file:///E:/CodeWorkstation/FlClashX/lib/views/purchase/center.dart#L12-L58) 剥离 ASCII URL、邮箱、`YYYY-MM-DD` 日期与时间戳，补齐英文标签词边界与反引号/方括号包裹支持，收紧无标签词边界；同步升级 [`PurchaseManager.setCode`](file:///E:/CodeWorkstation/FlClashX/lib/manager/purchase_manager.dart#L230-L242) 剥离空白与横线分隔符，保持非法符号与超长串由 `gift_code_format` 拦截。
  2. **[CR2-02 / P1] 修复中间插入小写字母光标强制跳尾与 IME 组合态打断**：在 [`center.dart`](file:///E:/CodeWorkstation/FlClashX/lib/views/purchase/center.dart#L60-L170) 新增 [`_UpperCaseCodeFormatter`](file:///E:/CodeWorkstation/FlClashX/lib/views/purchase/center.dart#L60-L85)（保护 `isComposingRangeValid` 原样放行，原地转换 ASCII 小写并保持光标偏移）与 `_updatingCodeFromInput` 重入守卫。
  3. **[CR2-03 / P2] 修复 `summarizePlanMarkdown` 行首三反引号行内代码吞噬全文及 `` `<u>` `` 误补闭合标签**：在 [`plan_catalog.dart`](file:///E:/CodeWorkstation/FlClashX/lib/views/purchase/plan_catalog.dart#L349-L553) 按 CommonMark §4.5 要求反引号围栏 info string 不含反引号，补齐 ATX 标题/分割线边界，新增块内同构扫描 `_closeTruncatedUnderlines` 忽略转义与反引号代码跨度。
  4. **[CR2-04 / P2] 修复 `resolvePlanRegionBadge` 繁体港澳、North Korea 重叠与大写词 `/MO`、`CAN`、`ARE` 误判**：补齐 `'中國香港'`/`'中國澳門'`、英文命中后打空格掩码、移除大写冲突缩写，并区分显式全域覆盖词（`全球`/`多国`/`全节点`/`Worldwide` → `🌐`）与普通 `Global` 前缀。
  5. **[CR2-05 & CR2-06 / P2–P3] 修复密码显隐跨会话残留、401 保全回执详情丢失、跨 `860px` 断点目录状态重置与获码弹窗体验缺口**：登出/401 过期自动重置 `_obscurePassword = true`，抽离 [`_receiptCard`](file:///E:/CodeWorkstation/FlClashX/lib/views/purchase/center.dart#L973-L1029) 在 401 保全态完整保留订单号与权益明细；为 `catalogPane` 绑定 `_catalogAnchor = GlobalKey()`，并在 [`_AcquirePlanSheet`](file:///E:/CodeWorkstation/FlClashX/lib/views/purchase/center.dart#L1510-L1575) 增加 `channelError` 降级提示与显式关闭按钮 `purchase-acquire-close`。新增 7 组 TDD 回归测试（前置有效 Red：`31 PASS / 7 FAIL`），修复后 `test/purchase` **315 PASS / 0 FAIL**、全仓 **981 PASS / 0 FAIL**、`dart analyze` `No issues found!`、`dart format` 零差异。
- 交付状态：**已实现 / 已完成两轮 Code Review 修复并本地提交**；未推送远端 / 未创建或合并 PR / 远端 CI **NOT RUN** / 离线 Widget 截图已复核（未启动真实客户端窗口，未触碰本机运行中代理、TUN 及服务） / 服务端部署与线上真实发卡消费业务验收 **NOT RUN**。

## 本机历史产出清理（2026-10-25）

- 来源：用户授权先检查、制定方案并清理；固定产品源码 `development@a47738de808913ffac9ec148330fd5086b566f81`，开工领先自有远端 11 个提交。清理对象为编译缓存、旧备份内缓存副本及已集成/补丁等效的干净工作树。
- 已删除 196 个白名单目录和 25 个干净旧工作树，原有产出逻辑文件长度共 81,330,597,341 bytes；失败/跳过 0。工作树 47 → 22，所有分支/stash、18 个历史脏树、初始化异常、UAC 原始来源、离线依赖和交付证据保留。本轮恢复演练副本在验证后已另行清理，审计至结束 C/E 可用空间实测净增约 78.72 GB。
- 新 bundle / 47 HEAD、19 个普通脏树恢复、移除树重要 ignored 归档、原 137 份源码快照及清理后的 HEAD/status/补丁/未跟踪文件/包 hash 均 PASS；现役四组件 PID 集合一致。缓存不承诺按字节恢复。
- 私有恢复目录：`C:\Users\冯飏\AppData\Local\FlClashX-Recovery\cleanup-20261025`。旧归档已增加当前范围说明；原始历史报告不回写为新测试结果。完整清单、空间计量、保留项和边界见[清理记录](cleanup-2026-10-25.md)。
- 已清理 / 已本地验证；仅文档本地提交，未推送 / 未创建或合并 PR / 未构建新预览 / 未部署。编译、应用交互、真实网络与业务验收 NOT RUN；后续构建按需重建缓存。


## Windows 国家筛选与 TLS 清理预览交付（2026-10-24）

- 固定源码：`development@159f16eecc7863f163cf22b0eec4ad0e86fb321b`，干净 tracked Git archive；UI/Core/Agent/Helper 同批新编，来源和绑定已核对。
- [Windows amd64 预览包](../dist/FreedomCloud-windows-amd64-country-tls-159f16eecc78.zip)：165,987,494 bytes；SHA256 `98d8a7a9ef7160af5f3148d5dfe8a260d78441968750cea5e6ae6825f966c2b8`。完整解压目录同名（去掉 `.zip`），启动 `FlClashX.exe`。
- 构建 PASS、两次 ZIP/解压逐文件校验 PASS（73 文件/72 checksum）、独立静态审计 8/8 PASS；已知 VS discovery 预检例外后实际 CMake/AOT/native 编译均成功。工具版本与全部边界见[交付报告](testing/windows-country-tls-preview-2026-10-24.md)。
- 普通未签名预览，不含 strict WFP 驱动/Broker；现有生产 CONNECT 证书放行行为保留并已披露。原预览包、覆盖率、QA、probes 和 stash 均保留。
- 已构建 / 已交付静态包；未推送 / 未创建 PR / 远端 CI NOT RUN / 候选未启动 / 真实代理、TUN、服务及业务验收 NOT RUN。下一步：用户按包内 PREVIEW-README 手工测试。

## 跨配置节点总览按国家筛选与三级国家识别流水线（2026-10-22 ~ 2026-10-24）

- 来源：用户提出在“代理 → 全部配置”（[`NodeOverviewView`](file:///E:/CodeWorkstation/FlClashX/lib/views/proxies/overview/overview.dart#L151-L779)）顶部工具栏“测试全部节点延迟”右侧区域增加按国家筛选代理配置的能力，并通过对齐确认四项设计决策：
  1. **三级混合国家识别流水线**：
     - **第一级（使用中节点真实出口 IP 校准）**：复用仪表盘“您的 IP 地址”现成的出口探测数据源（`detectionState` / [`request.checkIp`](file:///E:/CodeWorkstation/FlClashX/lib/common/request.dart#L157)），对当前 `inUse` 节点校准其真实出口国家并按节点/端点缓存，同时在节点切换窗口期设置防抖守卫（`markSwitchingNode` / `syncActiveNode`），防止新切换节点误继承上一节点的旧出口 IP；
     - **第二级（节点配置 `server` 离线 GeoIP 解析与公网 IP 边界加固）**：在不把原始 `server` 域名/IP 写入 [`CatalogNode`](file:///E:/CodeWorkstation/FlClashX/lib/models/node_catalog.dart#L68) 或 [`ProfileCatalog`](file:///E:/CodeWorkstation/FlClashX/lib/models/node_catalog.dart#L89) 序列化与 `toString()` 的隐私边界前提下，由 [`NodeCatalogService.onProxiesEvaluated`](file:///E:/CodeWorkstation/FlClashX/lib/common/node_catalog_service.dart#L1651) 与经归属校验后的 [`nodeRuntimeReadProvider`](file:///E:/CodeWorkstation/FlClashX/lib/providers/node_overview.dart#L79-L95) 将代理映射注册到 [`NodeCountryResolver`](file:///E:/CodeWorkstation/FlClashX/lib/common/node_country.dart#L990)，通过 [`isPublicRoutableIp`](file:///E:/CodeWorkstation/FlClashX/lib/common/node_country.dart#L890) 严格拦截 TUN Fake-IP（`198.18.0.0/15`、`fc00::/7`）、RFC1918 私网、CGNAT（`100.64.0.0/10`）、回环与保留地址，有界异步调用 Core 离线 GeoIP 库 [`clashCore.getCountryCode`](file:///E:/CodeWorkstation/FlClashX/lib/clash/core.dart#L406)（`geoip.metadb`），仅缓存有效 ISO 国家码并在后续求值时允许瞬态失败立即重试；当 `server` 为国内 `CN` 中转入口时优先让位于节点/配置名中的海外落地国家；
     - **第三级（节点名称与订阅配置名语义兜底）**：从节点名称提取国旗 Emoji、中英文国家/城市名、大写 ISO/机场三字码（自动剔除 `128 GB` / `500 MB` 等流量单位避免与英国代码 `GB` 冲突），若节点名称无国家特征则回退提取所属订阅配置名称（如订阅名 `伦敦` → `GB`、`美国` → `US`），仍无法识别归入 `🌐 其他`（`OTHER`）。
  2. **动态生成国家筛选胶囊、节点卡片国家徽标与 Windows 彩色国旗字体（`Twemoji`）适配**：
     - 在顶部工具栏 `Wrap` 紧接 `overview-test-all` 右侧动态渲染当前作用范围内实际存在的国家 `FilterChip`（`ValueKey('overview-country-$code')`），格式为 `🇺🇸 美国 (5)`，按节点数量降序排列（`🌐 其他` 固定排在末尾）；
     - 在右侧每个节点卡片（[`_ActiveNodeRow`](file:///E:/CodeWorkstation/FlClashX/lib/views/proxies/overview/overview.dart#L1483) 与 [`_InactiveNodeRow`](file:///E:/CodeWorkstation/FlClashX/lib/views/proxies/overview/overview.dart#L1645)）副标题行展示紧凑国家徽标（[`_CountryBadge`](file:///E:/CodeWorkstation/FlClashX/lib/views/proxies/overview/overview.dart#L1606)，如 `🇺🇸 美国`），并对胶囊与徽标的国旗 `TextSpan` 显式绑定 `FontFamily.twEmoji.value`（`Twemoji.Mozilla.ttf`），解决 Windows 默认字体将区域指示符国旗渲染成双字母框的问题，同时保持 `Text.rich` 文本节点语义与既有协议/来源文本查找契约。
  3. **单选切换交互与配置切换幽灵状态清理**：点击国家胶囊筛选对应国家节点，再次点击已选中胶囊取消筛选恢复显示全部；跟踪当前范围国家集合 `scopeCountries`，当切换到不包含该国家的单个订阅配置时立即自动清理失效的 `_selectedCountry`，防止切回“全部配置”或切换“仅可用”时旧筛选幽灵复活；订阅更新/删除或脚本变更时同步调用 `invalidateProfile` / `clearProfiles` 清理过期缓存。
  4. **“全部配置”下自动隐藏无匹配节点的空订阅配置分组**：当左侧选中“全部配置”且激活国家筛选时，自动隐藏该国家下匹配节点数为 0 的订阅配置分组标题与空占位，仅展示包含该国家节点的订阅配置及其节点；当左侧选中单个配置时，国家胶囊与节点列表自动收敛至该配置范围。
- 外部审查（针对 `development@0f0af1c` 的 7 项 P2 边界问题）复核与修复（2026-10-23）：
  1. **[P2 #1] 修复已有出口 IP 时打开总览在 `build()` 期间修改 Provider 抛异常**：移除 [`NodeOverviewView.build`](file:///E:/CodeWorkstation/FlClashX/lib/views/proxies/overview/overview.dart#L662-L760) 中的同步 `countryResolver.syncActiveNode(...)` 调用；改由 [`nodeCountryResolverProvider`](file:///E:/CodeWorkstation/FlClashX/lib/providers/node_overview.dart#L296-L401) 初始化时以 `notify: false` 静默种子化当前出站目标，并通过 `ref.listen` 在构建期外响应状态变更，消除 `Tried to modify a provider while the widget tree was building`。
  2. **[P2 #2] 修复多个 `Selector` 策略组将同一全局出口国家错误扩散至无关组节点**：移除 [`NodeCountryResolver.resolveCountryCode`](file:///E:/CodeWorkstation/FlClashX/lib/common/node_country.dart#L1413-L1477) 中按 `inUse` 广播全局出口的逻辑；在 [`nodeCountryResolverProvider`](file:///E:/CodeWorkstation/FlClashX/lib/providers/node_overview.dart#L116-L249) 中建立三级出站归属证明（优先匹配 `requestsProvider` 中命中 [`detectionState.lastMatchedHost`](file:///E:/CodeWorkstation/FlClashX/lib/state.dart#L978) 的 Core 真实 `Connection` 链路叶子节点并剔除 `DIRECT`/`REJECT`，其次 `Mode.global` 单一叶子，最后 `Mode.rule` 仅当所有可见 `Selector` 组收敛至唯一真实叶子节点时才认定无歧义目标），多策略组指向不同节点（如 `Primary → US node`、`Media → Japan node`）且无连接证据时绝不交叉覆写。
  3. **[P2 #3] 修复离开总览后通过经典卡片（`ProxyCard`）等入口切节点将新出口写回旧节点**：在 [`DetectionState`](file:///E:/CodeWorkstation/FlClashX/lib/state.dart#L962-L1092) 引入单调递增的路由代数 `_routingEpoch` 与请求代数 `_requestGeneration`（通过 [`request.checkIpWithHost`](file:///E:/CodeWorkstation/FlClashX/lib/common/request.dart#L157-L185) 记录命中的探测域名并在跨路由代数返回时失效），在 [`AppController`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L622-L645) 切节点/切配置/切模式以及 [`ProxyCard._changeProxy`](file:///E:/CodeWorkstation/FlClashX/lib/views/proxies/card.dart#L132-L152)（调用 [`notifyProxyCardSelection`](file:///E:/CodeWorkstation/FlClashX/lib/providers/node_overview.dart#L251-L294)）时同步推进路由代数并撤回/更新中央出站目标，即使 `NodeOverviewView` 已卸载也不会把新节点出口覆写到旧节点。
  4. **[P2 #4] 修复同名节点更换服务器端点后仍命中旧端点出口国家**：在 [`NodeCountryResolver`](file:///E:/CodeWorkstation/FlClashX/lib/common/node_country.dart#L981-L1030) 中将 `_exitCountryByNodeKey` 绑定 [`ExitCalibrationEntry`](file:///E:/CodeWorkstation/FlClashX/lib/common/node_country.dart#L981-L985)（含 `endpointKey` 与标准化 `server`）；当订阅更新使同名节点的 `endpointKey` 或 `server` 变化时，[`registerProxyMaps`](file:///E:/CodeWorkstation/FlClashX/lib/common/node_country.dart#L1316-L1379) 立即驱逐旧出口校准并按新端点重新解析。
  5. **[P2 #5] 修复“全部配置”窄窗/多配置下遗漏屏外订阅独有国家胶囊**：在 [`_NodeOverviewViewState`](file:///E:/CodeWorkstation/FlClashX/lib/views/proxies/overview/overview.dart#L211-L355) 新增有界后台国家索引扫描（`_scheduleCountryIndexScan`，最大并发 2，首帧可见 Sliver 挂载后启动避免重复加载，通过临时 `ref.listenManual` 读取完成后立即在 `finally` 中 `close()` 释放），将轻量级 [`_IndexedProfileCountrySummary`](file:///E:/CodeWorkstation/FlClashX/lib/views/proxies/overview/overview.dart#L185-L209) 纳入国家统计；无需手动滚动即可发现屏外配置独有国家（如第 21 个配置的 `JP`），同时保持屏外 Sliver 节点行不提前渲染、`profileCatalogProvider` 自动释放（`autoDispose`）以及 `cachedProfileCatalogsProvider` 最多保留 8 份完整目录的既有内存边界（同步更新 [`test/views/node_overview_test.dart`](file:///E:/CodeWorkstation/FlClashX/test/views/node_overview_test.dart#L1185-L1343) 中原 P1 仅按 `onLoad` 计数断言屏外未读取的 2 处旧契约，改为断言屏外节点 Widget 未构建且 `profileCatalogProvider` 已 `autoDispose`）。
  6. **[P2 #6] 修复瞬态 DNS／Core GeoIP 未就绪导致后续重评估无法立即重试**：移除阻塞重新评估的负缓存抑制，[`_serverCountryCache`](file:///E:/CodeWorkstation/FlClashX/lib/common/node_country.dart#L1022) 仅缓存有效 ISO 国家码，并发在途请求由 `_pendingServers` 去重；Core 就绪或订阅重新求值时立即重试解析。
  7. **[P2 #7] 修复中文国家关键词按子串首命中导致“印度尼西亚→IN、罗马尼亚→IT”误判**：在 [`_sortedZhKeywords`](file:///E:/CodeWorkstation/FlClashX/lib/common/node_country.dart#L539-L553) 中将全部中文国家/地区/城市关键词按字符长度降序排列优先匹配完整长词（如 `印度尼西亚` 先于 `印度`、`罗马尼亚` 先于 `罗马`、`内蒙古` 先于 `蒙古`），并补齐 `KP`（`朝鲜`/`平壤`/`North Korea` 先于 `KR`）及多国英文全称正则。
- 二轮外部复审（针对 `development@235b075` 的 4 项 P2 边界与回归问题）复核与修复（2026-10-23）：
  1. **[二轮 P2 #1] 修复停止代理后直连出口 IP 仍会覆盖原代理节点国家**：
     - 在 [`DetectionState._checkIp`](file:///E:/CodeWorkstation/FlClashX/lib/state.dart#L1045-L1115) 记录探测完成时刻 `_lastCheckCompletedAt` 与代理资格标记 `_lastCheckProxyEligible`（仅当探测起止全程 `runTime != null`、非 `Mode.direct` 且未跨 `_routingEpoch` 时才具备代理校准资格），并在 [`AppController.updateStatus`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L883-L936) 启停代理与启动回滚时同步推进 `detectionState.notifyRoutingChanged()`；
     - 在 [`nodeCountryResolverProvider`](file:///E:/CodeWorkstation/FlClashX/lib/providers/node_overview.dart#L317-L438) 与 [`notifyProxyCardSelection`](file:///E:/CodeWorkstation/FlClashX/lib/providers/node_overview.dart#L268-L315) 中统一要求 `ref.read(runTimeProvider) != null`，并监听 `runTimeProvider.select((s) => s != null)` 与 `Mode.direct` 切换：停止代理时立即通过 [`NodeCountryResolver.onProxyRunningChanged`](file:///E:/CodeWorkstation/FlClashX/lib/common/node_country.dart#L1121-L1140) 撤销 `_activeTarget`，并将停机/直连期间收到的 `IpInfo` 记入 `_directIneligibleIpInfo`，杜绝停机期间或刚重启尚未刷新前的直连 IP 覆写代理节点。
  2. **[二轮 P2 #2] 修复后续无关同域连接错误绑定旧 IP 检测结果**：
     - 在 [`resolveObservedConnectionTarget`](file:///E:/CodeWorkstation/FlClashX/lib/providers/node_overview.dart#L116-L191) 为连接时间窗口同时施加下界（`checkStartedAt - 2s`）与上界（`checkCompletedAt + 1s`），并在同一窗口内出现不同出站叶子节点并发命中同一探测域名时按歧义拒绝（返回 `null`）；
     - 在 [`NodeCountryResolver`](file:///E:/CodeWorkstation/FlClashX/lib/common/node_country.dart#L1294-L1442) 将连接延迟归属收敛为绑定单次未归属检测令牌（`_pendingConnectionAttributionToken`）的一次性（one-shot）+ 5 秒宽限窗口（`connectionAttributionGraceWindow`）：已在 `_onDetectionChanged` 完成归属或超过 5 秒宽限期后，`onConnectionsUpdated` 立即短路返回，后续无关同域请求绝不会复用旧 `IpInfo`。
  3. **[二轮 P2 #3] 修复共享 `type/server/port` 端点的不同节点丢失各自出口国家及 `clearProfiles` 残留**：
     - 移除跨节点无条件优先命中的全局 `_exitCountryByEndpointKey`；在 [`NodeCountryResolver`](file:///E:/CodeWorkstation/FlClashX/lib/common/node_country.dart#L981-L1032) 计算不保留明文凭据的规范化配置指纹 `_computeProxyConfigFingerprint`（剔除 `name` 后的规范化代理参数 SHA-256 摘要），[`resolveCountryCode`](file:///E:/CodeWorkstation/FlClashX/lib/common/node_country.dart#L1531-L1606) 优先返回身份校验通过（`endpointKey`、`server`、`configFingerprint` 一致）的节点独立校准 `_exitCountryByNodeKey`，仅在同配置内全部出站参数完全一致且无冲突时才允许通过 `_exitCountryByProfileConfig` 跨重命名复用；
     - 同名节点变更端口（`80 → 443`）、服务器或认证参数时立即驱逐旧校准；`invalidateProfile` 与 `clearProfiles` 同步彻底清理两级出口校准缓存。
  4. **[二轮 P2 #4] 修复国家索引后台扫描期间切换覆写脚本导致后续屏外扫描停滞**：
     - 在 [`_NodeOverviewViewState`](file:///E:/CodeWorkstation/FlClashX/lib/views/proxies/overview/overview.dart#L212-L458) 将每轮扫描的并发计数 `activeWorkers`、在途集合 `indexingProfileIds`、`dirty` 标记与订阅集合封装进按代隔离的 [`_IndexScanEpochState`](file:///E:/CodeWorkstation/FlClashX/lib/views/proxies/overview/overview.dart#L212-L234)；切换 `scriptStateProvider` 时取消旧代并创建零并发计数的新代实例，旧代挂起任务完成后不会篡改新代计数或阻塞新代继续调度，同时校验单配置加载前后的 `Profile` 快照一致性。
- 三轮外部复审（针对 `development@dac796d` 的 2 项 P2 出站归属边界问题）复核与修复（2026-10-24）：
  1. **[三轮 P2 #1] 修复规则模式（`Mode.rule`）下缺失或有歧义的连接证据仍回退触发错误静态归属**：
     - 在 [`_computeUnambiguousStaticTarget`](file:///E:/CodeWorkstation/FlClashX/lib/providers/node_overview.dart#L230-L276) 中移除 `Mode.rule` 的静态可见 `Selector` 推断分支：规则模式下分流规则（如 `DOMAIN,api-ipv4.ip.sb,DIRECT`、隐藏组或内联节点）可使探测域名绕过可见 `Selector`，因此仅在 Mihomo 跳过规则表直达 `GLOBAL` 的 `Mode.global` 下才产出静态目标（通过 `isGlobalStaticTarget: true` 显式标记）；
     - 新增三态连接证据模型 [`ConnectionEvidenceStatus`](file:///E:/CodeWorkstation/FlClashX/lib/common/node_country.dart#L981-L990)（`matched` / `missing` / `ambiguous`）与 [`evaluateObservedConnectionEvidence`](file:///E:/CodeWorkstation/FlClashX/lib/providers/node_overview.dart#L116-L202)（保留 [`resolveObservedConnectionTarget`](file:///E:/CodeWorkstation/FlClashX/lib/providers/node_overview.dart#L204-L228) 作为仅在 `matched` 时返回目标的兼容包装）：缺证（`missing`，例如 Core 4 秒连接轮询尚未送达）时在非全局模式下进入有界 `pending` 等待真实连接证据而不回退静态猜测，迟到的 `DIRECT`/`REJECT` 证据到达后直接封存终态且不污染代理节点；歧义（`ambiguous`，探测窗口内同域名命中多个不同出站叶子）时即使在 `Mode.global` 下也立即拒绝静态回退并封存终态（`finalized`），杜绝环形缓冲淘汰部分连接后把残余单条连接误判为唯一证据。
  2. **[三轮 P2 #2] 修复一次性消费与 5 秒时限未覆盖中央同步入口（`syncActiveNode`）导致有界连接历史淘汰后旧检测结果重放绑定至其他节点**：
     - 在 [`NodeCountryResolver`](file:///E:/CodeWorkstation/FlClashX/lib/common/node_country.dart#L999-L1165) 中引入由 `_onDetectionChanged`、`onConnectionsUpdated`、`syncActiveNode` 与 `seedInitialDetection` 全部归属入口共享的单次检测归属记录 `_DetectionAttributionRecord`（绑定 `ipInfo` 实例、`generation`、`routingEpoch`、`deadline` 与 `pending | finalized` 状态，并接入 [`detectionState.lastCheckCompletedAt`](file:///E:/CodeWorkstation/FlClashX/lib/state.dart#L990-L993) 计算真实截止时刻）；
     - 任一检测一旦完成节点校准、命中 `DIRECT`/`REJECT`、判定为 `ambiguous`、发生切节点/停机/路由代数变更或超过 5 秒宽限窗口，立即转移并锁存为 `finalized`（墓碑态）；后续 `cachedProfileCatalogsProvider`、`groupsProvider`、`profilesProvider` 更新触发的 `syncActiveNode` 或 `onConnectionsUpdated` 均在入口处 O(1) 短路返回，即使 `FixedList(150)` 已淘汰原探测连接并保留窗口内其他节点的同域连接，也绝不会重放已消费或已过期的 `IpInfo`。
- 四轮外部复审（针对 `development@9468093` 的 3 项 P2 出站归属与身份绑定问题）复核与修复（2026-10-24）：
  1. **[四轮 P2 #1] 修复规则模式下订阅更新未撤销待归属旧检测导致迟到连接日志把旧出口写入新端点**：
     - 在 [`NodeCountryResolver`](file:///E:/CodeWorkstation/FlClashX/lib/common/node_country.dart#L999-L1242) 为每条配置维护单调递增的配置修订代数 `_profileConfigRevision`、全局清空代数 `_clearAllEpoch` 与可选的活动配置身份读取器 `readActiveProfileScope`（绑定 `profileId | url | lastUpdateDate | isUpdating | scriptId`），并在创建 `_DetectionAttributionRecord` 时冻结 `clearAllEpoch`、`profileScope` 与 `profileRevisions` 快照；
     - [`invalidateProfile`](file:///E:/CodeWorkstation/FlClashX/lib/common/node_country.dart#L1278-L1324) 调用 [`revokePendingDetectionForProfile`](file:///E:/CodeWorkstation/FlClashX/lib/common/node_country.dart#L1224-L1242) 无条件递增对应 `profileId` 的 `_profileConfigRevision`（不再依赖 `_activeTarget` 非空），[`registerProxyMaps`](file:///E:/CodeWorkstation/FlClashX/lib/common/node_country.dart#L1687-L1760) 在已注册同名节点的 `server`、`endpointKey` 或 `configFingerprint` 变更时同步递增修订代数，且在写入 [`recordExitCountry`](file:///E:/CodeWorkstation/FlClashX/lib/common/node_country.dart#L1381) 前由 [`_isRecordValidForProfile`](file:///E:/CodeWorkstation/FlClashX/lib/common/node_country.dart#L1206-L1222) 二次核验配置身份未变（同时保证无关后台非活动配置更新不会误取消当前活动配置的待归属探测）；[`nodeCountryResolverProvider`](file:///E:/CodeWorkstation/FlClashX/lib/providers/node_overview.dart#L498-L527) 在 `currentProfileIdProvider`、`profilesProvider`（含 `isUpdating` 开始时刻）及 `scriptStateProvider` 变化时同步推进 `routingEpoch` 并撤销对应待归属探测。
  2. **[四轮 P2 #2] 修复首次冷启动初始化跳过 5 秒时限与连接证据直接将旧检测写给自动故障转移后的全局叶子节点**：
     - 在 [`NodeCountryResolver._tryAttributeCurrentDetection`](file:///E:/CodeWorkstation/FlClashX/lib/common/node_country.dart#L1562-L1682) 中彻底移除绕过截止时间与连接归属评估的 `allowColdStaticSeed` 后门分支，使 `seedInitialDetection`、`syncActiveNode`、`onConnectionsUpdated` 与 `_onDetectionChanged` 统一遵循 5 秒宽限窗口（`!withinGrace` 立即封存为 `finalized`）及优先核验连接归属证据的不变量；
     - 在 [`_resolveGroupToLeafProxy`](file:///E:/CodeWorkstation/FlClashX/lib/providers/node_overview.dart#L83-L114) 中将静态无歧义解析严格收敛至 `GroupType.Selector`，禁止将 Core 内部自主切换但不推进 `routingEpoch` 的 `URLTest` / `Fallback` / `Relay` / `LoadBalance` 自动组视为确定性静态目标；并在 [`AppStateManager.initState`](file:///E:/CodeWorkstation/FlClashX/lib/manager/app_state_manager.dart#L86-L88) 启动阶段提前激活 `nodeCountryResolverProvider`，确保真实运行态探测在完成当下即绑定具体节点身份落入 `_exitCountryByNodeKey` 持久化保留，后续打开总览直接复用已绑定节点身份的校准记录。
  3. **[四轮 P2 #3] 修复同域名、同时间窗口的其他进程（如 `chrome.exe`）或非探测套接字连接被误认为本次探测证据**：
     - 在 [`Request.checkIpWithHost`](file:///E:/CodeWorkstation/FlClashX/lib/common/request.dart#L172-L286) 为每次探测创建独立 `HttpClient`，通过 `connectionFactory`（直连 HTTPS 使用 `SecureSocket.startConnect` 保持完整系统 CA 证书与主机名校验，其余走 `Socket.startConnect`）精确记录本次探测发起的本地 TCP 源端口集合 `sourcePorts` 与是否经由 Clash 入站/TUN 捕获的 `routedViaClash` 标记（当 `mixedPort == 0 && !tunHandlesTraffic` 走系统直连旁路时由 [`DetectionState._checkIp`](file:///E:/CodeWorkstation/FlClashX/lib/state.dart#L1104-L1120) 标记 `proxyEligible = false`），并在探测命中的 keep-alive 连接上短暂保留 `4.5s`（随 `cancelToken` 立即释放），覆盖 Core `forwardNewRequests()` 的 4 秒采样周期；
     - 在 [`evaluateObservedConnectionEvidence`](file:///E:/CodeWorkstation/FlClashX/lib/providers/node_overview.dart#L166-L250) 中新增进程与套接字双重归属校验 [`_isConnectionOwnedByProbe`](file:///E:/CodeWorkstation/FlClashX/lib/providers/node_overview.dart#L148-L164)：任何携带非本应用进程名或路径（如 `chrome.exe`、`FlClashCore.exe` 等）的连接一律拒绝；当传入 [`detectionState.lastProbeSourcePorts`](file:///E:/CodeWorkstation/FlClashX/lib/state.dart#L987-L990) 时进一步要求 `metadata.sourcePort` 精确命中本次 HTTP 探测套接字端口（即使 `FindProcessMode.off` 进程字段为空也能精确区分进程内外连接），未传入端口集合时要求具备本应用进程身份证明，无法证明归属时保持 `ConnectionEvidenceStatus.missing`。
- 五轮外部复审（针对 `development@72f7dde` 补充测试暴露的 TLS 握手停滞连接清理异常）复核与修复（2026-10-24）：
  1. **根因确认（Dart SDK `dart:io` 上游缺陷导致普通 `Dio`/`HttpClient` 对照同样泄漏底层 TCP 套接字）**：
     - 直连 HTTPS 路径下，`RawSecureSocket.startConnect`（`dart:io/secure_socket.dart:334-347`）将 `ConnectionTask` 的取消回调直接绑定到 `RawSocket.startConnect` 的 `rawState._onCancel`；而 `_NativeSocket.startConnect`（`socket_patch.dart:1087, 1131`）在三次握手刚建立（`<1ms`）时即执行 `connecting.remove(socket)`。一旦对端在随后的 TLS 握手中停滞不回 `ServerHello`，`HttpClient.connectionTimeout` 与 `dio.close(force: true)` 触发的 `task.cancel()` 遍历空的 `connecting` 集合而完全空转，底层 TCP 连接持续悬挂；
     - 代理 `CONNECT` HTTPS 及 `SecureSocket.secure(socket)` 升级路径下，`socket._detachRaw()`（`socket_patch.dart:2847-2856`、`http_impl.dart:2520`）会将原 `Socket._raw` 置为 `null` 移交 `_RawSecureSocket`，使外部持有的 `Socket.destroy()` 在进入 TLS 握手后同样失效，且 `CancelToken` 若在 `ClientHello` 发出后取消也会在 `io_adapter.dart` 挂起于 `openUrl` 期间遗留半开连接。
  2. **修复方案（[`Request.checkIpWithHost`](file:///E:/CodeWorkstation/FlClashX/lib/common/request.dart#L177-L497) 可取消 TLS 桥接与全生命周期确定性销毁）**：
     - 新增 [`Request._openCancellableProbeConnection`](file:///E:/CodeWorkstation/FlClashX/lib/common/request.dart#L291-L390) 与单次进程内回环桥接 [`Request._bridgeSocketForTls`](file:///E:/CodeWorkstation/FlClashX/lib/common/request.dart#L392-L497)：真实出站 TCP 连接统一通过 `Socket.startConnect` 建立并立即将真实客户端端口记入 `attemptPorts`（绝不混入内部回环桥接端口）；对 HTTPS（含直连 HTTPS 与代理 `CONNECT` HTTPS）将 `SecureSocket.secure(..., host: uri.host)` 运行在一对一次性 `127.0.0.1` 回环套接字上，保持完整系统 `SecurityContext.defaultContext` CA 证书链、SNI 与主机名/IP SAN 校验不变，同时使真实出站 `outboundSocket` 始终不被 `_detachRaw()` 剥离句柄；
     - 正常 EOF 采用 `flush().then((_) => close())` 平滑排空避免 `TCP RST` 截断 TLS 响应体；一旦触发 `ConnectionTask.onCancel`（`connectionTimeout`）、`CancelToken` 取消、TLS 握手异常、`finally` 退出（`!holdForTelemetry`）或 `keepAliveHold` 到期，`abortConnection` / `abortAllAttemptSockets` 立即同步销毁 `outboundSocket`、`bridgePeer` 与 `localClient`，毫秒级关闭远端与代理隧道 TCP 套接字并唤醒挂起的 `_RawSecureSocket`。
- 单测与验证：
  - [`test/common/node_country_test.dart`](file:///E:/CodeWorkstation/FlClashX/test/common/node_country_test.dart)（22 项单测，五轮新增覆盖直连 HTTPS 对端接收 `ClientHello` 后停滞超时毫秒级关闭远端套接字并回退 HTTP、`ClientHello` 发出后中途 `CancelToken` 取消立即关闭远端套接字、以及代理 `CONNECT 200` 建立后上游 TLS 握手停滞超时立即关闭代理隧道套接字并回退下一来源）与 [`test/views/node_overview_test.dart`](file:///E:/CodeWorkstation/FlClashX/test/views/node_overview_test.dart#L3316-L3374)（84 项组件测试）；
  - 全仓 Flutter 单元与组件测试（`flutter test -j 4`）：**PASS（962 PASS，0 FAIL）**；五轮外部审查脚本（`request_https_connect_72f7dde_review_test.dart` 全部 5 项含 1s 严苛关闭时限的 TLS 超时回退测试、`request_tls_timeout_diagnosis_72f7dde_review_test.dart` 中 `Request` 诊断项、`country_foreign_process_72f7dde_review_test.dart` 共 7 项）全部 **PASS**；本机 Flutter 版本为 `3.47.4`（CI 配置为 `3.41.7`）；
  - 变更 Dart 文件（`lib/common/request.dart`、`test/common/node_country_test.dart`）`dart analyze`：**PASS（0 error，0 warning，0 新增 info）**；`git diff --check` 通过；
  - 远端 CI / 真实窗口预览 / 后端部署 / 业务验收：**NOT RUN**（尚未推送远端，未触碰本机运行中代理、TUN 及服务状态）。
- 交付状态：已在 `development` 分支完成四轮共 16 项 P2 缺陷及第五轮 TLS 握手超时/取消底层连接泄漏修复、回归测试验证与本地提交（未推送至 `freedomcloud/development`，未创建 PR）。


## Windows 跨配置切换虚拟网卡（TUN）重启失败自愈与自动重启补丁（2026-10-17）

- 来源：用户在手动测试预览包 `FreedomCloud-windows-amd64-oneclick-wip-0aa11746b863` 时发现跨配置切换节点会导致虚拟网卡启动失败。经对运行日志 `FlClashX_2026-10-17.log`（`14:47:53`–`14:48:27`）与本地配置文件核查，定位根因为不同配置 `ipv6` 设置差异使 Core `ReCreateTun` 中 `tunConf.Equal(LastTunConf)` 为 `false`，触发同进程内立刻销毁并重建同名 `Meta` Wintun 网卡，导致新网卡在 Windows NDIS 异步释放/初始化窗口期落入 `interfaceDown`、`startFailed` 或 `closeFailed` 状态，而原 [`_repairVanishedAdapter`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L129-L212) 仅处理 `interfaceMissing`，且后续跨配置切换在 [`applyWindowsTunConfiguration`](file:///E:/CodeWorkstation/FlClashX/lib/common/windows_tun_prepare.dart#L34-L88) 遇到 `TunObservedState.unknown` 时直接抛出 `TUN: statusUnavailable` 中断配置切换。用户确认采用小步、低风险的虚拟网卡失败自愈与自动重启方案。
- 实现项（仅修改 Dart 控制层，保持 `FlClashCore.exe` 二进制与已安装 `FlClashHelperService.exe` 的 SHA256 绑定不变）：
  1. 扩展 [`_isRepairableTunFailure`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L109-L120) 与 [`_repairVanishedAdapter`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L129-L212) 自愈范围与两级恢复流水线：
     - 在已授权（`privilege == 'elevated'`）、用户期望开启（`desiredEnabled == true`）且未处于手动关闭或已锁定请求失败时，除原有的 `listenerActive && errorCode == 'interfaceMissing'` 外，新增识别 `listenerActive && errorCode == 'interfaceDown'`，以及代理运行中出现的 `!listenerActive && state == 'failed' && ((requestedEnabled && errorCode == 'startFailed') || errorCode == 'closeFailed')`；
     - **第一级（延迟等待 + 增量重建）**：非 `closeFailed` 场景下，若存在 `_tunSettleDelay`（生产环境 500ms）先等待 NDIS 完成过渡（`interfaceDown` 若已自行恢复为 `on` 则直接收敛），否则通过 `applyConfiguration(full: false)` 触发 Core `ReCreateTun` 重新创建 `Meta` 网卡并轮询等待状态稳定；
     - **第二级（无 UAC 自动重启 Core 恢复）**：当错误为 `closeFailed`（旧 listener 无法在同进程内关闭）或第一级增量重建后仍未恢复为 `on` 时，在单实例最大自愈预算（`_maxTunRepairAttempts = 2`）内自动调用 `effects.restartCore()`（通过已提权 Helper/Agent 重启 `FlClashCore.exe`，**零 UAC 弹窗**），随后依次执行 `initialize`、`applyConfiguration(full: true)`、`startListener`、状态稳定轮询与 `reflectRunning`，完整恢复虚拟网卡与代理组运行态；
     - 保持严格有界与手动偏好不变量：若两级自愈均失败，记录 `requestFailure` 停止后台无限重试；用户手动关闭 TUN（`desiredEnabled == false`）时绝不自动重开。
  2. 修复 [`applyWindowsTunConfiguration`](file:///E:/CodeWorkstation/FlClashX/lib/common/windows_tun_prepare.dart#L60-L73) 在自愈失败后的跨配置切换阻断：
     - 当非显式 TUN 开关操作（`!explicitOperation()`，如切换配置/节点）且此前自愈或请求已记录失败（`failedRequest() == true`）时，只要当前状态尚未恢复为 `on`（`status.observed != TunObservedState.on`，涵盖 `TunObservedState.off` 以及 `interfaceMissing`、`interfaceDown`、`interfaceUnknown`、`closeFailed`、`starting` 等所有 `TunObservedState.unknown` 状态），统一自动降级本次配置应用的 `enabled = false`（不改写用户保存的 `tun.enable` 偏好），不再抛出 `statusUnavailable` 阻断跨配置节点切换。
  3. **多轮 Code Review 与 Double Check 自审发现与加固（41 项）**：
     - **消除跨配置切换同步 `ipv6` 等网络设置触发的二次冗余 `updateClashConfigDebounce` 竞态**：[`_setupClashConfigImpl`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L1452-L1614) 在调用 `clashCore.setupConfig` 前会将目标配置的 `ipv6`/`allowLan`/`mixedPort`/`findProcessMode`/`tun.stack` 写回 `patchClashConfigProvider`；原先该同步写回会触发 `ClashConfigUpdateListener` 在 600ms 后（恰处于耗时 1~3s 的 `setupConfig` 执行中途）额外入队一次 `_updateClashConfig()`，不仅造成同一次切换重复调用 `ReCreateTun`，还会抢在 `_repairVanishedAdapter` 自愈任务之前执行并在 `unknown` 过渡态下抛出 `statusUnavailable` 弹窗。
     - **Double Check 与第七次审查修正 Riverpod 派生 Provider 异步通知时序**：`ClashConfigUpdateListener` 监听的是派生 Provider `updateParamsProvider`（内部 `watch(patchClashConfigProvider)`），Riverpod 对派生 Provider 的 `listenManual` 回调会在下一个微任务/帧才异步触发，简单的同步 `try/finally` 清理会在回调触发前（特别是前置 `observe()` 抛出 `statusUnavailable` 快速返回时）被提前复位。现改为记录快照 [`_syncingProfileUpdateParams`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L59)，在 [`updateClashConfigDebounce`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L525-L533) 收到通知且当前 `updateParamsProvider == _syncingProfileUpdateParams` 时精准消费并跳过冗余调度（若期间用户发生了真实并发修改导致参数不等则正常放行），并在 `_setupClashConfigImpl` 外层 `finally` 通过事件队列 `unawaited(Future(...))` 延迟兜底清理，确保待刷新的微任务监听先观察并消费该快照；
     - **二次 Code Review 修复配置应用期间 `observe()` 与 3 秒定时轮询提前触发自愈及篡改 `explicitOperation` 的时序隐患**：
       - 在 [`applyWindowsTunConfiguration`](file:///E:/CodeWorkstation/FlClashX/lib/common/windows_tun_prepare.dart#L46-L47) 入口处（调用 `observe()` 之前）预先快照 `isExplicitStop` 与 `isExplicitOperation`，防止 `observe()` 内部副作用改变 `explicitOperation()` 的判定结果；
       - 在 [`AppController._applyWindowsConfig`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L451-L477) 引入 `_applyingWindowsConfigDepth` 深度守卫：在配置下发未完成期间（含前置 `observe()`、耗时 1~3s 的 `setupConfig` 执行中途触发的 3 秒定时轮询，以及 `message.isNotEmpty` 即将抛错前的后置 `observe()`）抑制提前触发 `_repairVanishedAdapter`，仅在 `_applyWindowsConfig` 完整成功返回且深度归零后，对最终 `status` 执行一次 `_recoverRunningProjection` 与 `_repairVanishedAdapter` 检查；
     - **三次 Code Review 加固第二级 `restartCore()` 进程替换后的初始化不变量与运行态缓存失效**：
       - 在 [`_repairVanishedAdapter`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L329-L333) 第二级执行 `await effects.restartCore()` 替换 Core 进程后，即使期间用户点击了关闭/停止使 `current()` 变为 `false`，也先执行 `await effects.initialize(() => true)` 完成新 Core 进程的基础初始化（`init` + `setState`）再退出队列（不执行后续 `applyConfiguration` 与 `startListener`），与 `prepareWindowsTunBackend` 保持同一进程替换不变量，避免把未初始化的新 Core 留给队列中的后续指令；
       - 当第二级在 `restartCore()` 后因配置或启动异常抛错时，同步将新 Core 的 `instanceId`（`observed?.instanceId ?? _tunRuntime.status?.instanceId`）记满 `_maxTunRepairAttempts`；
       - 在 [`_ControllerWindowsTunStartupEffects.restartCore`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L3137-L3146) 中同步调用 `controller._ref.invalidate(nodeRuntimeReadProvider)`，确保替换 Core 进程后立即失效旧 Core 的运行态目录缓存；
     - **四次 Code Review 修复异步快照间隙、连续快速切配置跳过后置观测及前置 `statusUnavailable` 漏触发自愈（3 项）**：
       - 在 [`_setupClashConfigImpl`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L1486-L1526) 中将 `beforeProfileSync = _ref.read(updateParamsProvider)` 移至 `await globalState.syncNetworkSettingsFromProvider(...)` 之后（紧邻同步 `updateState` 之前），使 `beforeProfileSync` → `updateState` → `afterProfileSync` 在同一个无 `await` 的同步时间片内完成，杜绝磁盘读取挂起期间用户的无关并发修改被误记入 `_syncingProfileUpdateParams`；
       - 在 [`_setupClashConfigImpl`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L1536-L1566) 中在进入 `_applyWindowsConfig` 的 `apply` 回调（`invalidate()` 已执行）后保持 `isCurrent` 与 TUN 意图一致，防止在 `getSetupParams` 或 `setupConfig` 期间因切向第三个配置跳过后置 `observe()` 而留下 `_tunRuntime.status == null` 空窗；
       - 在 [`_repairVanishedAdapter`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L225-L257) 排队闭包开始执行时读取最新 `_tunRuntime.status ?? status` 决定 Stage 1 / Stage 2 分支；
     - **五次 Code Review 深度排查与方案设计加固（4 项）**：
       - **修复前置观测 `statusUnavailable` 导致跨配置切换/配置更新弹窗报错并中断应用的问题**：当网卡已处于可自愈异常态（如 `interfaceDown`/`interfaceMissing`/`closeFailed`，`observed == unknown` 且尚未记入 `requestFailure`）时，若用户发起切换配置（[`_setupClashConfig`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L1372-L1450)）或更新配置（[`_updateClashConfig`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L1194-L1284)），前置 `observe()` 会抛出 `TunFailure('statusUnavailable')`；若直接 `rethrow` 会触发 `loadingRun` 弹出 `TUN: statusUnavailable` 错误弹窗且目标配置未生效。现改为：检测到 [`_canRepairVanishedAdapter(status)`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L132-L145) 为真时，先退出当前 `serialize` 块（避免队列自锁），直接 `await _repairVanishedAdapter(preApplyRepairStatus!, fullConfiguration: ..., applyPendingConfig: true)` 在自愈流程中一并完成目标配置下发；若两级自愈均未能恢复网卡（已锁存 `requestFailure`）或存在显式 `controllerAddress`/`controllerEnabled` 参数，再追加一次 `serialize` 调用自动走 `downgradeFailedAdapter` 降级（`tun.enable: false`）完成配置切换，全程无报错弹窗中断；
       - **扩展 `_applyingWindowsConfigDepth` 覆盖复合串行操作与 `explicitTunOperation` 精确绑定**：将 [`restartCore`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L594-L609)、[`updateStatus`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L635-L682)（特别是 `updateStatus(false)` 停止代理及其 `finally` 刷新阶段）以及 [`_setupClashConfigImpl`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L1452-L1614) 前置异步阶段统一纳入 `_applyingWindowsConfigDepth` 保护，防止复合操作半途被 3 秒轮询插入自愈任务或停止代理时误触发自愈；同时在 [`_applyWindowsConfig`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L451-L473) 中增加 `explicitTunOperation: isCurrent != null`，确保后台 `serialize` 任务不会因队列后方新排入 `request()`（使 `_tunRuntime.busy` 变为 `true`）而被误判为显式修复操作；
       - **排队自愈任务被取消时回滚自愈预算（`rollbackAttemptsIfCancelled`）与 Stage 2 错误原因隔离**：若 `_repairVanishedAdapter` 在排队或等待期间因用户操作使 `!current()` 提前退出（未形成终态结果 `terminalOutcome`），在 `whenComplete` 中回滚预先递增的 `_tunRepairAttempts[status.instanceId]`，避免浪费该 Core 实例的 2 次自愈配额；进入 Stage 2 重启 Core 时清空旧进程的 `stageOneFailure`，确保新进程异常时报告真实原因；
     - **六次 Code Review 深度排查与方案设计加固（3 项）**：
       - **修复排队自愈任务在等待队列期间状态已恢复或变为不可自愈时仍继承旧 `status.errorCode` 误执行修复/重启的问题**：在 [`_repairVanishedAdapter`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L225-L257) 排队闭包出队时复核最新 `currentStatus = _tunRuntime.status`，若已恢复为 `TunObservedState.on` 且 `errorCode == null` 或变为不可自愈状态，直接跳过修复并回滚未消耗的预算；同时当 `activeStatus.observed == TunObservedState.on && activeStatus.errorCode == null` 时不再用 `?? status.errorCode` 回退继承入队前过期的 `'closeFailed'` / `'interfaceDown'`；
       - **消除后置观测触发自愈（`postApplyRepair`）与 `_applyProfile` 后续 `updateGroups()` / `updateProviders()` 及外部控制器覆盖参数之间的并发竞态**：抽出 [`_handlePostConfigTunStatus`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L443-L449)，在 `_applyWindowsConfig` / `_setupClashConfigImpl` 完成且 `_applyingWindowsConfigDepth == 0` 时（仍处于 `serialize` 同步块内）同步启动并记录 `_lastTriggeredTunRepair = _repairVanishedAdapter(status)`（立即置 `_tunRuntime.busy = true`，零时间窗间隙），随后在 [`_setupClashConfig`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L1372-L1450) 与 [`_updateClashConfig`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L1194-L1284) 退出 `serialize` 后 `await postApplyRepair`，避免自愈 Stage 2 `restartCore()` 与 `_applyProfile` 的 `updateGroups()` / `updateProviders()` 并发冲突，并在 `_updateClashConfig` 携带 `controllerAddress`/`controllerEnabled` 且触发了 `postApplyRepair` 时在自愈后补齐外部控制器覆盖参数；
       - **修复前置自愈中途被取消时后续降级应用缺少 `requestFailure` 标记的问题**：在 `_setupClashConfig` 与 `_updateClashConfig` 的后续降级 `serialize` 块中，若前置自愈因取消退出使 `_tunRuntime.observed == TunObservedState.unknown && _tunRuntime.requestFailure == null`，先调用 `_tunRuntime.fail(...)` 锁存失败状态，确保后续 `_setupClashConfigImpl` / `_updateWindowsConfig` 稳定走 `downgradeFailedAdapter` 降级而不抛 `statusUnavailable`；
     - **七次 Code Review（技术负责人 + 极客视角）并发队列交错、微任务时序与终态降级深度加固（4 项）**：
       - **修复并发排队配置操作与后方入队自愈任务交错时因 `_tunRuntime.busy == true` 漏判自愈并抛 `TUN: statusUnavailable` 的问题**：`_tunRuntime.request(true, ...)` 在被调用时就会同步置 `_tunRuntime.busy = true`；若配置操作 B 已排在 `_tunRuntime._queue` 前方、而后方刚入队了前序操作或轮询触发的 `_repairVanishedAdapter`（记录于 [`_activeTunRepair`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L56)），B 执行前置 `observe()` 抛出 `statusUnavailable` 时 `_canRepairVanishedAdapter(status)` 会因 `busy == true` 返回 `false`。现改为：当检测到 `_activeTunRepair != null` 时，B 先捕获 `pendingRepair = _activeTunRepair` 并退出当前 `serialize` 块让出队列，使已入队的 `pendingRepair` 立即执行，待 `await pendingRepair` 完成后再执行跟进 `serialize` 块完成配置下发（若自愈成功直接以 `tun.enable: true` 应用，若失败则走 `downgradeFailedAdapter` 降级），彻底消除交错排队下的 `statusUnavailable` 报错；
       - **修复 `_repairVanishedAdapter(applyPendingConfig: true)` 排队期间状态已恢复或变为 clean `off` 时误跑修复甚至误升 Stage 2 重启的问题**：移除 `if (currentStatus != null)` 对 `!applyPendingConfig` 的限制——当 `applyPendingConfig: true` 在队列等待期间 `currentStatus` 已恢复为 `on`（置 `repairedAndApplied = false`）或变为不可自愈状态（如 `off`）时，同样直接提前返回并回滚未消耗的自愈预算，交由调用方的跟进 `serialize` 块正常完成待应用配置，避免在 `explicitTunOperation: true` 下把已变为 `off` 的状态误判为 Stage 1 失败而触发无意义的 Stage 2 `restartCore()`；
       - **修复后置自愈（`postApplyRepair`）与 Stage 2 重启 Core 终态失败后的 Core 配置降级与运行态恢复缺口**：当 `postApplyRepair` 耗尽两级自愈仍失败（`!applied && _tunRuntime.desiredEnabled && _tunRuntime.requestFailure != null`）时，触发跟进 `serialize` 块通过 `downgradeFailedAdapter` 将 Core 配置同步降级为 `tun.enable: false`；同时当生产环境（`_windowsStartupEffects == null`）Stage 2 `restartCore()` + `startListener()` 后网卡仍未就绪导致跳过 `reflectRunning` 时，主动恢复新 Core 进程的 `setUiActive`、日志订阅、`updateGroups`、`updateProviders` 与前台缓存，防止新 Core 进程丢失代理会话状态；
     - **八次 Code Review（技术负责人 + 极客视角）停止代理同步取消窗口、队列出栈同步清理、自愈中途切配置与设置保护深度加固（5 项）**：
       - **消除 `updateStatus(false)` 同步调用 `cancelPendingIntent()` 与进入 `serialize` 停止代理之间的自愈重入时间窗**：[`updateStatus(false)`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L635-L682) 会在进入 `_statusOp` / `_tunRuntime.serialize` 之前**同步**调用 `_tunRuntime.cancelPendingIntent()` 将 `_tunRuntime.busy` 置为 `false`（而此时 `desiredEnabled` 与 `proxyRunning` 仍为 `true`）；原先 `_applyingWindowsConfigDepth` 直到进入 `serialize` 块才递增，导致在 `cancelPendingIntent()` 之后、`stopProxy()` 执行之前的窗口期内完成的轮询或配置后置观测会看到 `busy == false && _applyingWindowsConfigDepth == 0`，进而在 `cancelPendingIntent()` 之后重新入队一个新的 `_repairVanishedAdapter`。现改为在调用 `_tunRuntime.cancelPendingIntent()` **之前**同步开启停止保护，直至 `op` 外层 `finally`（完成 `stopProxy()` 与停止后状态刷新后）才复位，彻底封死停止代理窗口期的自愈重入；
       - **消除 `_activeTunRepair` 清理与 `_tunRuntime._queue` 下一任务出队之间的微任务延迟**：在 [`_repairVanishedAdapter`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L204-L212) 中抽出幂等 `finishRepair()`，同时在 `request` 闭包的 `finally` 块（在 `operation = TunOperation.idle` 及 `_tunRuntime._queue` 唤醒下一 `serialize` 任务之前同步执行）与外层 `.whenComplete()`（兜底未进入闭包即取消的情形）中调用，确保任何后续排队任务开始执行时 `_activeTunRepair` 与预算回滚均已同步就绪；
       - **修复显式 TUN 启动/自愈期间（`isCurrent != null`）并发切换配置导致 `_setupClashConfigImpl` 静默跳过 `clashCore.setupConfig` 及漏补发新配置的问题**：当 `WindowsTunStartupEffects.applyConfiguration(full: true, isCurrent: current)` 调用 [`_setupClashConfigImpl`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L1452-L1614) 时，若在磁盘读取/预处理挂起期间用户切换了配置（`_ref.read(currentProfileProvider)?.id != applyingProfileId`）而 TUN 意图 `isCurrent()` 仍有效，不再静默 `return` 跳过 `clashCore.setupConfig`（否则会导致 Stage 1 未重建网卡就误升 Stage 2，或 Stage 2 重启 Core 后在空配置上调用 `startListener()` 误报 `startFailed`），而是自动循环重读最新 `currentProfileProvider` 完成下发；同时通过 [`isPendingConfigSatisfied`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L190-L202) 校验自愈完成时的最新 `currentProfileIdProvider` / `updateParamsProvider` 是否与已下发快照一致，若在 `setupConfig` 或 `observeSettled()` 期间再次发生变更则令 `repairedAndApplied = false`，驱动调用方跟进 `serialize` 块补发最新配置；
       - **防止非配置切换触发的 Stage 2 重启 Core 覆盖用户在设置页修改的网络参数**：当 `_repairVanishedAdapter` 由 `_updateClashConfig` 或后台轮询触发（`fullConfiguration == false`）并升级至 Stage 2 `restartCore()` 时，向 [`_ControllerWindowsTunStartupEffects`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L3074-L3120) 传入 `syncProviderSettings: fullConfiguration`（`false`），避免 Stage 2 调用 `_setupClashConfigImpl` 时重新从配置文件 YAML 同步覆盖用户刚刚在设置页修改的 `ipv6`/`allowLan`/`mixedPort`/`findProcessMode`/`tun.stack`；
       - **泛化 `downgradeFailedAdapter` 覆盖所有非 `on` 状态并支持跟进应用后的链式降级**：在 [`applyWindowsTunConfiguration`](file:///E:/CodeWorkstation/FlClashX/lib/common/windows_tun_prepare.dart#L62-L65) 中将 `downgradeFailedAdapter` 泛化为 `enabled && !isExplicitOperation && failedRequest() && status.observed != TunObservedState.on`（额外覆盖 `interfaceUnknown` 与卡在 `starting` 导致的请求失败），并在 `_setupClashConfig` / `_updateClashConfig` 中支持“前序 `pendingRepair` 恢复后跟进应用新配置再次触发 `postApplyRepair` 且最终失败”时的二次降级；
     - **九次 Code Review（技术负责人 + 极客视角）`serialize` 同步入队零微任务间隙、统一 3 趟状态机循环、预算回滚单调性与 `closeFailed` 启动重启初始化不变量深度加固（5 项）**：
       - **消除前置 `statusUnavailable` 捕获到启动 `preApplyRepair` 之间的 1 个微任务时间窗及 `startFailed` 交错排队漏等自愈的问题**：原先在 `_setupClashConfig` / `_updateClashConfig` 的 `serialize` 块捕获 `statusUnavailable` 时只记录 `preApplyRepairStatus = status` 并退出 `serialize`，待外层 `await _tunRuntime.serialize` 恢复时才调用 `_repairVanishedAdapter`（此时 `_applyingWindowsConfigDepth` 已归零而 `_tunRuntime.busy` 仍为 `false`）；同时若入队时已有针对 `startFailed`（其 `status.observed` 为 `TunObservedState.off` 而非 `unknown`）的 `_activeTunRepair` 排在后方，配置操作不会抛 `statusUnavailable` 而是直接对故障 Core 执行配置下发并在结束后因 `busy == true` 漏等 `_activeTunRepair`。现改为：在进入 `serialize` 块伊始若 `!repairFailedOrCancelled && _activeTunRepair != null` 立即记录 `pendingRepair = _activeTunRepair` 并让出队列；在捕获 `statusUnavailable` 且 `_canRepairVanishedAdapter(status)` 为真时，**在 `serialize` 的 `catch` 块内同步发起** `preApplyRepair = _repairVanishedAdapter(..., applyPendingConfig: true)`（零微任务间隙置 `busy = true` 与 `_activeTunRepair`），并在外层 `await preApplyRepair`；
       - **将 `_setupClashConfig` 与 `_updateClashConfig` 初始尝试与跟进重试统一为有界 3 趟状态机循环，区分“前序自愈成功补发”与“前序自愈失败/取消降级”**：引入 `repairFailedOrCancelled` 标志（仅在前序等待的自愈返回 `false` 且 `_tunRuntime.observed != TunObservedState.on` 时置为 `true`）；当前序 `pendingRepair` / `preApplyRepair` 已成功将网卡恢复至 `on`、仅因待补发新配置或 `hasControllerOverride` 进入下一趟时，`repairFailedOrCancelled` 保持 `false`，不会误调 `_tunRuntime.fail(...)` 污染健康 Core 的请求状态，且若补发新配置再次遇到可自愈的 `statusUnavailable` 仍可正常触发自愈；
       - **保证 `rollbackAttemptsIfCancelled()` 预算回滚的单调性，防止取消时复活已被健康 `on` 观测清零的计数**：在 [`rollbackAttemptsIfCancelled`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L180-L202) 中仅当 `(_tunRepairAttempts[id] ?? 0) > baseline` 时才执行回滚；若自愈排队或 `observeSettled()` 期间已有健康 `TunObservedState.on`（且 `errorCode == null`）观测将该实例从 `_tunRepairAttempts` 移除（当前计数 `0 <= attempts`），随后发生的意图取消不会将旧的 `attempts > 0` 重新写回 Map；同时在显式用户重试边界 [`setTunEnabled`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L504-L509) 中同步清空 `_tunRepairAttempts.clear()`；
       - **解耦 `updateStatus(false)` 停止代理挂起标志 `_pendingWindowsProxyStop` 与 `startWindowsTunOnLaunch` 的 `closeFailed` 进程替换初始化不变量**：用专门的 `_pendingWindowsProxyStop` 标志替代 `updateStatus(false)` 在 `_statusOp` 排队前的 `_applyingWindowsConfigDepth++`，使快速连续点击 `start -> stop -> start` 时后一个 `updateStatus(true)` 能立即同步解除停止抑制而不受前一个排队中的 `stop` 阻塞；同时在 [`startWindowsTunOnLaunch`](file:///E:/CodeWorkstation/FlClashX/lib/common/windows_tun_startup.dart#L96-L104) 处理 `initial?.errorCode == 'closeFailed'` 调用 `await effects.restartCore()` 后，立即执行 `await effects.initialize(() => true)` 再检查 `if (!current()) return;`，与 `prepareWindowsTunBackend` 及 `_repairVanishedAdapter` Stage 2 保持完全一致的 Core 进程替换初始化不变量；
       - **保证 `_setupClashConfigImpl` 在 `apply` 回调中读取最新 `patchClashConfigProvider`**：在同步配置网络字段后及 `_applyWindowsConfig` 的 `apply` 闭包内重读 `_ref.read(patchClashConfigProvider)`，并使用布尔标志 `_hasAppliedWindowsProfile` 配合 `_lastAppliedWindowsProfileId` 校验配置下发完成态，消除跨 `await` 快照过期及 `applyingProfileId == null` 边界；
     - **第一级增量重建抛出可恢复异常时支持升级到第二级重启 Core**：在 [`_repairVanishedAdapter`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L325-L336) 中捕获第一级 `applyConfiguration` 的非权限/非组件不匹配 `TunFailure`（如旧 Core 卡死导致的 `configurationFailed` 或 `statusUnavailable`），继续升级至第二级 `restartCore()` 自愈；
     - **自愈完成后同步系统托盘状态**：在 `_repairVanishedAdapter` 的 `request` 结束时触发 `updateTray()`，确保后台自愈结果及时反映到托盘菜单。
     - **十次 Code Review（技术负责人 + 极客视角）排队自愈终态错误保留、Core 重启状态清理、配置代数（`runtimeConfigEpoch`）防过期覆写与跨配置防抖隔离（5 项）**：
       - **修复 `_repairVanishedAdapter` 在队列等待期间状态转为不可自愈故障（如 `interfaceUnknown`/`permissionDenied`）或新实例配额已满时直接 `return` 抹除 `failure` / `requestFailure` 的问题**：`_tunRuntime.request(true, ...)` 入口会同步清空 `failure = _requestFailure = null`；若在等待队列期间 `currentStatus` 变为不可自愈的非 `off` 故障或已耗尽配额的实例，直接 `return` 会使 `request` 正常结束并把 `failure`/`requestFailure` 留在 `null`。现改为在非停止/非正常 `off` 场景下先调用 `rollbackAttemptsIfCancelled()` 回滚未使用的预算、置 `terminalOutcome = true`，再抛出对应 `TunFailure(...)` 锁存终态错误；同时在 `_setupClashConfig` / `_updateClashConfig` 跟进降级判断中将 `_tunRuntime.observed == TunObservedState.unknown` 泛化为 `!_pendingWindowsProxyStop && _tunRuntime.observed != TunObservedState.on`；
       - **修复 `TunRuntimeController.accept` 在健康 `on` 观测下漏清 `closeFailed`/`configurationFailed`/`operationFailed` 以及 `restartCore` / `recoverCoreForUser` 残留旧 Core 失败状态的问题**：在 [`TunRuntimeController.accept`](file:///E:/CodeWorkstation/FlClashX/lib/common/tun_runtime.dart#L141-L170) 观测到 `errorCode == null && observed == TunObservedState.on` 时补充清理 `closeFailed`、`configurationFailed`、`operationFailed`；新增 [`clearCoreRuntimeFailure()`](file:///E:/CodeWorkstation/FlClashX/lib/common/tun_runtime.dart#L180-L192)（清除 Core 级运行时错误但保留 `authorizationRequired`/`permissionDenied`/`componentsMismatch`/`legacyAgent` 环境门禁），并在 `AppController.restartCore()`、`recoverCoreForUser()` 及 `_ControllerWindowsTunStartupEffects.restartCore()` 中同步调用；
       - **引入 `GlobalState.runtimeConfigEpoch` 与 `clearRuntimeSetup()`，防止 Core 重启/关闭残留旧 `lastRuntimeProfileId` 及异步在途 `updateGroups()` 跨配置覆写**：在 [`GlobalState`](file:///E:/CodeWorkstation/FlClashX/lib/state.dart#L62-L64) 中维护单调递增的 `runtimeConfigEpoch`（每次 `commitRuntimeSetup` 与 `clearRuntimeSetup` 递增），在 Core 重启/恢复/关闭时调用 `clearRuntimeSetup()` 清空 `lastRuntimeConfig` 与 `lastRuntimeProfileId`；在 [`updateGroups()`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L1891-L1918) 中捕获调用时的 `configEpoch` 与 `profileId`，若 `getProxiesGroups()` 返回时配置代数或当前配置已变则丢弃过期结果，杜绝旧配置的异步 `updateGroups()` 覆盖新配置节点组或提前递增 `versionProvider` 结束节点总览的 `_pendingSwitchProfileId` 过渡态；
       - **隔离跨配置切换时的待执行 `changeProxyDebounce` 与 `updateGroupsDebounce`**：在 [`handleChangeProfile()`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L1724-L1726) 入口立即取消 `FunctionTag.changeProxy` 与 `FunctionTag.updateGroups` 防抖定时器，并在 [`changeProxyDebounce`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L600-L624) 中绑定 `expectedProfileId` 与 `expectedConfigEpoch`，防止用户在活动配置点击节点后立即跨配置切换时旧配置的 `changeProxy` 在新配置上延后触发；
       - **消除切向 `flclashx-globalmode: false` 配置时 `AppStateManager` 帧后回调触发的 600ms 延迟 `updateClashConfigDebounce`**：在 [`_setupClashConfigImpl`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L1574-L1584) 的 `beforeProfileSync` ... `afterProfileSync` 同步块内提前将 `flclashx-globalmode: false` 配置下的 `Mode.global` 收敛为 `Mode.rule`（纳入 `_syncingProfileUpdateParams` 抑制范围），并在调用 `clashCore.setupConfig` 前若 `patchClashConfigProvider` 未发生新的并发变更则取消待执行的 `FunctionTag.updateClashConfig` 定时器；同时在 [`_activeLeaves`](file:///E:/CodeWorkstation/FlClashX/lib/views/proxies/overview/overview.dart#L858-L866) 中对齐 `globalModeEnabledProvider` 判定。
     - **十一次 Code Review（技术负责人 + 极客视角）`accept` 瞬态失效恢复保真、被取代进程替换完整恢复闭环、`serialize` 跨趟恢复感知与外部 Provider 代数防覆写（5 项）**：
       - **修复 `TunRuntimeController.accept` 在 `desiredEnabled == true` 且存在锁存 `_requestFailure` 时因瞬态 `statusUnavailable` 恢复为 `off` 观测而把 `failure` 清成 `null` 的问题**：在 [`TunRuntimeController.accept`](file:///E:/CodeWorkstation/FlClashX/lib/common/tun_runtime.dart#L148-L177) 中，当观测到 `value.errorCode == null && (failure == 'statusUnavailable' || failure == 'invalidStatus')` 时，将 `failure` 恢复为 `_requestFailure` 而非无条件置 `null`（若当前观测已满足 `desiredEnabled` 或为健康 `on` 则 `_requestFailure` 已先一步清零，否则保留原 `_requestFailure`），杜绝出现 `_requestFailure != null`（阻止后台重开）而 UI `failure == null`（隐藏失败原因）的不一致状态；
       - **补齐生产环境 Stage 2 / `closeFailed` 重启或后端迁移替换 Core 后被 `setTunEnabled(false)` 等操作中途取代时的完整 Profile 与代理监听器恢复闭环**：新增 [`_needsWindowsCoreRestore`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L60) 与 [`_restoreReplacedWindowsCoreIfNeeded`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L536-L583)；当 `_ControllerWindowsTunStartupEffects.restartCore()` 或 `ensureBackend()` 替换了 Core 进程但因并发手动关闭 TUN（`setTunEnabled(false)`）或后续配置更新在 `applyConfiguration(full: true)` + `startListener()` 完成前被取代，或 `applyConfiguration(full: true)` 在降级为 `tun.enable: false` 后抛出 `TunFailure` 时，确保接手的 `setTunEnabled(false)` / `_updateClashConfig` / `_setupClashConfig` 完整补跑 `_setupClashConfigImpl`（加载 Profile）并在 `globalState.isStart` 为真时调用 `clashCore.startListener()` 及恢复 `setUiActive`/日志/`updateGroups`/`updateProviders`/前台缓存，防止新 Core 仅收到 `updateConfig(tun.enable: false)` 而处于无 Profile、无代理监听器的断流状态；
       - **修复 `_updateClashConfig` 与 `_setupClashConfig` 在前序自愈被用户显式 `setTunEnabled(true)` 取代且随后恢复成功时仍保留 `repairFailedOrCancelled = true` 的问题，并补齐 `closeFailed` Stage 2 失败配额标记**：在每趟进入 `_tunRuntime.serialize` 闭包时，若 `_tunRuntime.observed == TunObservedState.on && _tunRuntime.requestFailure == null` 则自动复位 `repairFailedOrCancelled = false`；同时在 `_repairVanishedAdapter` Stage 2 失败路径中将 `status.instanceId` 与 `activeStatus.instanceId` 一并记满 `_maxTunRepairAttempts`；
       - **允许同一配置在跨配置 `setupConfig` 落地后执行期间新点击节点的 `changeProxyDebounce`**：在 [`changeProxyDebounce`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L622-L645) 中校验 `currentProfileIdProvider == expectedProfileId` 且当前配置的 `selectedMap[groupName]` 仍为目标 `proxyName`，仅在 `await changeProxy(...)` 执行期间发生 `runtimeConfigEpoch` 变更时才跳过 `updateGroups()`，确保用户在跨配置切换 `setupConfig` 执行中途又点击了同一目标配置下的新节点时，新节点选择不会因首个 `setupConfig` 完成递增 `runtimeConfigEpoch` 而被防抖回调丢弃；
       - **为 `updateProviders()` 与 `ClashManager.onLoaded()` 补齐 `runtimeConfigEpoch` 及 `currentProfileIdProvider` 跨异步边界守卫**：在 [`updateProviders()`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L950-L959) 与 [`ClashManager.onLoaded()`](file:///E:/CodeWorkstation/FlClashX/lib/manager/clash_manager.dart#L143-L157) 等待 `getExternalProviders()` / `getExternalProvider()` 返回后校验配置代数与当前配置 ID（以及 `mounted`），防止旧配置或重启前 Core 的外部 Provider 异步返回覆写新配置状态。
     - **外部独立审查 `30e6884` 发现的 P1 修复（Stage 2 在途 `setupConfig(tun: true)` 被 `setTunEnabled(false)` 取代时丢失关闭配置写入）**：
       - **根因**：Stage 2 重启新 Core 后，若 `setupConfig(tun: true)` 已发出（在 Go Core 中置 `pendingTunEnable = true`），用户在等待返回期间通过热键触发 `setTunEnabled(false)`，旧修复虽被取消，但在途 `setupConfig(tun: true)` 完成时仍将 `_hasAppliedWindowsProfile` 置为 `true`。随后 `setTunEnabled(false)` 进入 `_restoreReplacedWindowsCoreIfNeeded` 分支，因 `_hasAppliedWindowsProfile == true` 跳过配置写入而直接调用 `startListener()`（将 `pendingTunEnable == true` 写入 `currentConfig.General.Tun.Enable`），导致关闭操作未向 Core 发送 `tun: false`，TUN 保持开启并报错 `closeFailed`；
       - **修复**：在 [`setTunEnabled`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L596-L622) 与 [`_updateClashConfig`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L1265-L1291) 中区分“新 Core 尚未加载 Profile（`!_hasAppliedWindowsProfile`）”与“在途 `setupConfig(tun: true)` 已落地但尚未 `startListener`（`_hasAppliedWindowsProfile == true`）”：后者先执行 `_updateWindowsConfig(...)` 向 Core 发送最新 `tun: false`（将 Go Core 的 `pendingTunEnable` 清为 `false`），再在 `finally` 中调用 [`_restoreReplacedWindowsCoreIfNeeded(..., applyProfileIfMissing: false)`](file:///E:/CodeWorkstation/FlClashX/lib/controller.dart#L550-L607) 补齐 `startListener()` 与代理会话恢复；同时新增 `_TrackedWindowsTunStartupEffects` 使注入 `windowsStartupEffects` 的测试同样覆盖 `controller.setTunEnabled(false)` 生产恢复分支。
- 单测与验证：
  - Windows TUN 专项测试套件（`test/clash/windows_startup_controller_test.dart`、`test/common/windows_tun_startup_stability_test.dart`、`test/clash/windows_tun_prepare_test.dart`、`test/clash/tun_config_scheduling_test.dart`、`test/clash/tun_runtime_test.dart`）：**80 PASS，0 FAIL**（含 `controller.setTunEnabled(false)` 在 Stage 2 `setupConfig(tun: true)` 在途及 `restartCore` 阶段中途取代的 2 项生产入口回归测试，以及 18 项跨配置自愈、重启、队列交错与降级回归测试）。
  - 节点总览与目录回归测试（`test/views/node_overview_test.dart`、`test/common/node_catalog_service_test.dart`）：**96 PASS，0 FAIL**（7 个目标测试文件合计 **176 PASS，0 FAIL**）。
  - 修改文件 `dart analyze`：**0 error，0 warning**；`git diff --check` 通过。
- 交付状态：已在 `development` 分支完成修复与验证；未触碰用户正在运行的预览进程与现役代理/TUN/服务。


## 跨配置节点总览“一键使用”开发、审查修复与单测（2026-10-16）

- 来源：用户确认在跨配置节点总览每个节点行增加“使用 / 使用中”按钮，并明确选择“直接一键切换（无二次确认弹窗）+ 自动写入首个包含该节点的 `select` 主选择组 + 当前命中节点显示 `使用中`”；完成初版开发、针对外部独立审查 r1 / r2 / r3 / r4 / r5 及 `30e6884` / `2e1ff5f` / `db24f45` / `cf5b329` 独立审查指出的边界问题完成修复后，再次执行验证。
- 实现、自审与外部审查收敛项：
  1. 目录构建与全量解析统一收集 `select` 组归属（[`_SelectGroupIndex`](file:///E:/CodeWorkstation/FlClashX/lib/common/node_catalog_service.dart#L36-L1310)）：
     - 严格保留 `proxy-groups` 原始声明顺序；过滤 `hidden: true` 的 `select` 组；
     - **修复外部审查 Finding 2（`exclude-type` 协议名称对齐 Core）**：新增 [`_canonicalAdapterType`](file:///E:/CodeWorkstation/FlClashX/lib/common/node_catalog_service.dart#L36-L50)，将 YAML `type` 别名（如 `ss`→`shadowsocks`、`ssr`→`shadowsocksr`、`gost-relay`→`gostrelay` 等）映射对齐至 Mihomo `AdapterType.String()`，确保 `exclude-type: Shadowsocks` 等规则与 Core `GroupBase.GetProxies` 行为一致；
     - **修复外部审查 Finding 3、r2、r3、r4、r5 及二次自审加固（正则语义保真、运算符保留、Go 15.0.0 Unicode 字符类/大小写等价、换行锚点对齐与 fail-closed）**：新增 [`_compileClashRegex`](file:///E:/CodeWorkstation/FlClashX/lib/common/node_catalog_service.dart#L794-L1076) 与 [`_parseGroupFilter`](file:///E:/CodeWorkstation/FlClashX/lib/common/node_catalog_service.dart#L1084-L1105)：
       - 保留未转义分支与量词运算符（`|`、`*`、`+`、`?` 及合法 `{m,n}` 量词），支持大小写内联标志（`(?i)`/`(?I)`、`(?m)`/`(?M)`、`(?s)`/`(?S)`），同时确保反斜杠转义（如 `\|`、`\*`）按字面字符处理；
       - **对齐 Go 15.0.0 Unicode 字符分类表（r5 Finding 1）**：移除对 Dart `\p{L}`、`\p{Mn}`、`\p{Nd}`、`\p{Pc}` 属性转义（基于新版本 Unicode 表，会把 `U+1C89`、`U+10D40`、`U+1CCF0` 等 Go 15.0.0 未收录码点误判为 word/digit）的依赖，直接内嵌由 Core 所用 Go 1.25.13（Unicode 15.0.0）`unicode.Nd` 与 `regexp2` word 类别生成的精确码点区间表（[`_goDigitRangeDeltas`](file:///E:/CodeWorkstation/FlClashX/lib/common/node_catalog_service.dart#L291-L304)、[`_goWordRangeDeltas`](file:///E:/CodeWorkstation/FlClashX/lib/common/node_catalog_service.dart#L307-L454)、[`_GoCaseTables`](file:///E:/CodeWorkstation/FlClashX/lib/common/node_catalog_service.dart#L611-L661)），统一展开字符类内外的 `\w`/`\W`、`\d`/`\D`、`\b`/`\B`；
       - **对齐 `regexp2.None` 大小写等价关系（r4 Finding 1）**：移除对 Dart `toLowerCase()`/`toUpperCase()` 及 ECMAScript `caseSensitive: false` 的依赖，统一以 `RegExp(..., caseSensitive: true, multiLine: false, unicode: true)` 编译，并使用与 Go `unicode.ToLower` 及 `regexp2/syntax/charclass.go` `lcTable` 完全一致的大小写等价表（[`_GoCaseTables`](file:///E:/CodeWorkstation/FlClashX/lib/common/node_catalog_service.dart#L611-L661)、[`_expandIgnoreCaseClassRanges`](file:///E:/CodeWorkstation/FlClashX/lib/common/node_catalog_service.dart#L743-L792)）展开 `(?i)` 下的单字符与字符类区间（正确处理 `İstanbul`/`i`、`ß`/`ẞ`、`K`/`k`、`ſ`≠`s`、`ς`≠`σ`、`ı`≠`i` 等全部 Unicode 边界）；
       - **对齐 `regexp2.None` 普通与多行锚点边界（r4 Finding 2）**：按 `regexp2` 的 `Beginning`/`End`/`EndZ`/`Bol`/`Eol` 语义精确转换锚点——`\A` 与非多行 `^` 映射为 `^`，`\z` 映射为 `$`，`\Z` 与非多行 `$` 映射为 `(?=\n?$)`（匹配末尾或末尾单个 `\n` 之前），`(?m)` 多行 `^` 映射为 `(?:^|(?<=\n))`，`(?m)` 多行 `$` 映射为 `(?=\n|$)`（仅以 `\n` 为行分隔符，不将 `\r` 误判为行边界）；
       - **源码级对抗自审加固**：对原子组 `(?>...)`、字符类内负向多区间简写（`[\W]`/`[\S]`）、字符类内 `\D` 与其他简写组合（如 `[\D\w]`/`[\D\d]`，规避 `regexp2` `CharSet.CharIn` 负向类别提前跳出循环/取反异常）、字符类内以转义连字符 `\-` 作为区间端点（如 `[\--0]`/`[!-\-]`，规避 `regexp2` `scanCharSet` 对 `\-` 直接 `continue` 不参与区间构建的差异）、同组同时声明 `proxies` 与非法 `filter`、未知/不等价转义、字符类差集及任何解析异常严格按 **fail-closed（禁用依赖该规则的候选 `select` 组）** 处理，杜绝因 Dart 编译通过而误把 Core 排除的节点判入可选组；
     - **修复 `30e6884`、`2e1ff5f` 及 `db24f45` 外部审查 P2（`select` 组分组成员为空时的完整成员集 `empty-fallback` 推断）**：新增 [`_isValidNonEndpointCoreProxy`](file:///E:/CodeWorkstation/FlClashX/lib/common/node_catalog_service.dart#L1151-L1203)，在 [`_SelectGroupIndex.resolveForCandidates`](file:///E:/CodeWorkstation/FlClashX/lib/common/node_catalog_service.dart#L1350-L1435) 中把“可展示叶子节点（`validLeaf`）”与“Core 合法成员（`validMember`）”彻底解耦——除自定义 `direct`/`reject`/`dns` 外，将 `rematch`（含 `target-rematch-name` 或 `target-sub-rule`）、`tailscale`、`easytier`、`zerotier`、仅含 `peers` 的 `wireguard`、配置 `port-range` 的 `mieru`、配置 `ports` 的 `hysteria`/`hysteria2` 一并作为 `validMember: true, validLeaf: false` 纳入过滤与空组判定，并对未能确认成员合法性的条目增加 `hasUncertainMatch` 守卫（无法确认组为空时绝不放行 `empty-fallback`），与 Mihomo `parseProxyGroups` + `GroupBase.GetProxies` 行为严格一致；
     - `Mode.rule` 下在 [`_targetGroupForCatalogNode`](file:///E:/CodeWorkstation/FlClashX/lib/views/proxies/overview/overview.dart#L920-L936) 排除 YAML 中显式声明的 `GLOBAL` 组。
  2. 节点总览行级一键使用与状态流转（[`overview.dart`](file:///E:/CodeWorkstation/FlClashX/lib/views/proxies/overview/overview.dart#L179-L380)）：
     - 活动配置节点点击“使用”：调用 `updateCurrentSelectedMap` + `changeProxyDebounce` 切换该节点所属主选择组，并确保 `currentGroupName` 在 `isAppControllerReady == true` 时同样写回 `profilesProvider`；
     - `Mode.global` 下 [`_activeLeaves`](file:///E:/CodeWorkstation/FlClashX/lib/views/proxies/overview/overview.dart#L968-L1012) 与 `Mode.rule` 分支严格互斥；
     - **修复外部审查 Finding 1 及 `30e6884` / `2e1ff5f` / `db24f45` / `cf5b329` 外部审查 P2（跨配置切换失败后目标节点仍标为“使用中”不可重试、重建总览或隐藏期间完成旧组刷新或首次冷挂载总览导致旧配置实时节点挂到目标配置下、以及版本更新覆盖原始组列表引用导致首次打开总览退回目录行）**：
       - 在 [`GlobalState`](file:///E:/CodeWorkstation/FlClashX/lib/state.dart#L46-L120) 中将 `AppState.groups` 规范化为稳定的 `EqualUnmodifiableListView` 实例，同时分离 [`recordGroupsSnapshot`](file:///E:/CodeWorkstation/FlClashX/lib/state.dart#L72-L88)（由 `Groups` 调用，记录原始列表引用 `_rawGroupsSnapshot`、规范化包装 `_groupsSnapshot` 及归属 `_groupsSnapshotProfileId`）与 [`recordGroupsVersion`](file:///E:/CodeWorkstation/FlClashX/lib/state.dart#L90-L98)（由 `Version` 调用，仅更新版本号而保留 `_rawGroupsSnapshot` 与 `_groupsSnapshotProfileId`），并提供 [`isSameGroupsList`](file:///E:/CodeWorkstation/FlClashX/lib/state.dart#L58-L66) 与 [`matchesGroupsSnapshot`](file:///E:/CodeWorkstation/FlClashX/lib/state.dart#L68-L71)，杜绝 `runTimeProvider` 无关更新篡改快照归属，也杜绝 `Version` 更新把 `_rawGroupsSnapshot` 覆盖为包装列表；
       - 在 [`_overviewSwitchTrackerProvider`](file:///E:/CodeWorkstation/FlClashX/lib/views/proxies/overview/overview.dart#L114-L148) 中移除核验失败回退到 `currentRuntimeProfileId()` 的分支，仅在 `globalState.matchesGroupsSnapshot` 校验通过时继承 `globalState.groupsSnapshotProfileId`；在 [`_isSnapshotLiveForProfile`](file:///E:/CodeWorkstation/FlClashX/lib/views/proxies/overview/overview.dart#L179-L190) 中要求非空组快照必须通过校验且归属当前运行配置，确保首次打开总览或隐藏期间完成旧组刷新时绝不把旧 A 节点渲染到 B 下，同时单配置刷新后新增第二配置首次打开总览时准确保留当前活动配置的实时 `In use` 行；
       - 将“已保存的选择（`selectedMap`/`currentProfileId`）”与“运行态已确认生效（`liveActive`）”解耦：非运行态配置行（[`_InactiveNodeRow`](file:///E:/CodeWorkstation/FlClashX/lib/views/proxies/overview/overview.dart#L700-L716)）始终保持 `inUse: false`（显示“使用”且可点击重试），失败或未生效时不提前显示“已切换到 ...”或禁用按钮；用户点击重试时重新触发 `applyProfileDebounce(silence: true)` 与 `changeProxyDebounce(targetGroup, node.name)`，待运行态确认切到目标配置且发布归属目标配置的组快照后再转为 `In use` 并展示成功反馈。
  3. 四语言文案补齐（`arb/intl_*.arb` 及生成的 `lib/l10n/`）：新增 `nodeOverviewUseNode`、`nodeOverviewInUse`、`nodeOverviewSwitchedToNode`。
- 单测与验证：
  - `test/common/node_catalog_service_test.dart`：**22 PASS**（含 `empty-fallback` 命中、自定义 `direct` 及 `rematch` 代理命中阻止回退、显式自定义 `direct` 及 `rematch` 代理被排除允许回退、非空组忽略 `empty-fallback`、含未解析 `use` provider 时 fail-closed 回归测试）。
  - `test/views/node_overview_test.dart`：**74 PASS**（含跨配置切换失败保持目标节点可点击重试且不误标 `In use`、总览卸载隐藏期间完成旧配置组刷新、无关 `runTimeProvider` 更新及首次冷挂载总览绝不将旧配置实时节点渲染到目标配置下、单配置 `groups + version` 发布后新增配置首次进入总览保留实时 `In use` 状态 4 项回归测试；目标单测合计 **96 PASS，0 FAIL**）。
  - 外部审查 r1 + r2 + r3 + r4 + r5 及 `30e6884` / `2e1ff5f` / `db24f45` / `cf5b329` 复现套件与 31,488 项扩展语义对照矩阵（123 规则 × 128 合成节点名 × `filter`/`exclude-filter`）：**全部 PASS，0 次错误放行（0 unsafe admissions，0 mismatches）**。
  - 修改文件 `dart analyze`：**0 error，0 warning**（exit 0）；`git diff --check` 通过。
- 交付状态：已在 `development` 分支完成修复与验证；未启动候选程序，未触碰现役代理/TUN/服务。



## 节点延迟漏测与所选配置修复预览及 P1 源码本地提交（2026-10-16，仅本地）

- 用户真实反馈：全量测试遗漏末尾配置，选中配置后当前配置入口无效。已复现普通60秒代理组刷新递增version被误当成会话失效，以及当前按钮忽略所选profileId。仅修改overview.dart与node_overview.dart两处产品文件，保留其他P1 WIP。
- 新增8项回归：2项页面选择、2项16配置/170节点跨刷新完成并逐配置存储、4项真实配置/脚本失效反例。目标66+6+53 PASS；全Flutter894 PASS/0FAIL/SKIP；analyze0error/11既有warning/889info（exit2）；diff-check通过。Go本轮无改动，未重复运行。
- 完整预览 `FreedomCloud-windows-amd64-latency-fix-wip-69d7ea5b117c.zip`，SHA256 `addf26b9e47e8374f3216fdfcbe2190c0d516e5f58a6dc6418ede39e64550501`；WIP快照 `69d7ea5b117c2d0334a8c1ac1d579bdf34a116008a757aa456c4d98d20d9ebd1`，1007文件，完整重编exit0，静态审计8/8与解压逐文件核验PASS。源码ZIP及证据目录一并交付，旧包保留。
- 技术负责人复审通过后，已将 P1 隔离测速、全配置延迟与批次修复的 **58 个源码与测试文件**在 `development` 分支完成本地提交 `9c3986e150c8bfb5f2f5cace5cc950b1e0a00b18`（`feat(proxies): add cross-profile node overview P1 isolated delay tests and flat UI`），配套工程文档单独本地提交；未推送远端、无候选启动、无现役代理/TUN/服务/配置操作。用户自行验收新包；旧窗口截图和有缺口的日志不能替代新候选验收。详见 [修复与交付报告](testing/node-latency-batch-fix-2026-10-16.md)。


## 全配置节点延迟 Windows 预览复审与交付（2026-10-15）

- 本轮只复审和打包，未修改产品代码，未发现新增阻塞项。44项本轮交付与此前P1清单核验后固定59项变更、1004文件快照 `1509079d76b5eb7887db1013a334aeadcc2ca6350a1605f502e4bf06b22fe914`；HEAD仍为 `e3ab52bd1afc46b009907f0ee7386fd228914d8e`，暂存区空，未执行Git写操作。
- 新包 `dist/FreedomCloud-windows-amd64-all-delay-wip-1509079d76b5.zip`，154,097,799 bytes，SHA256 `892e73f7948a775c11df548d5dfacda10081505b040d1f4804eee2dd28f554a8`；同名完整解压目录与源码附件、证据目录已交付。旧P1包hash复核一致，未覆盖。
- Core/Agent/Helper/UI 同源码完整重编，exit0 / 598.417秒；Helper/Core/UI编译绑定一致。74文件解压校验、独立静态审计8/8、审计guard8/8均PASS。既有VS自动发现例外后的实际CMake/AOT/native均通过。
- 本轮重跑Dart目标105 PASS、Go全套120顶层/含子测试164 PASS，0fail/skip；相同源码的Flutter全套886 PASS与analyze 0error/11既有warning/886info（exit2）证据已按hash核对。没有把静态分析写成零告警，也没有把构建写成实机验收。
- 未启动候选或操作现役代理/TUN/服务/网卡/权限；由用户测试。已知不支持协议/provider边界和历史5000条/4MiB容量保留。详见 [本次复审与预览交付](testing/windows-all-profile-latency-preview-2026-10-15.md)。本条为打包后文档，以下“未打新包”为此前阶段历史记录。

## 全配置节点延迟测试与批次修复（2026-10-15，留工作树）

- 用户收敛需求：保留“测试当前配置”独立入口并修复点击未开始/中途停止；将“测试可见节点”改为“测试全部节点延迟”，包含活动配置、忽略所有展示过滤，仅测 ms 延迟；坏配置不能阻断后续配置。历史保留至下一次有效测试覆盖；选择 B，显式全量测试可读取 provider/下载缺失列表，内存使用，不应用配置或切节点。
- 本轮在既有 P1 WIP 上增量修改 42 个源码/测试/本地化文件，新增只读 provider resolver、纯 Core parser、受限压缩/分块；继续沿用共享测速预算、目录资源释放及协议安全限制。修复当前入口 30 秒截断、重复计数、元数据误取消、provider 混合失败、2001 节点投影、历史到期删除与容量告警串配置。没有重构其他功能。
- 最终 Flutter **886 PASS/0 FAIL/0 SKIP**（含 coverage，158.404s）；UI 文件 64 项包含其中，另宽窄合成渲染 2 PASS且已看图。Go default/gVisor 各 **120 顶层/含子例164 PASS**，catalog/delay race **38 顶层/含子例58 PASS**。Analyze **0 error/11既有warning/886info，exit2**，warning 与此前评审逐条一致；不是全绿。
- 真实 Red→Green、首次全量 882/1 失败、overlay helper 单独 coverage 编译失败均保留。Dart 本轮手写变更行 **90.28%**、分支 **69.71%**；含生成代码改动行82.75%、分支58.82%。Go总体语句47.9%、新provider边界82.4%；不声称 overlay helper 或 Go 分支覆盖率。
- 历史默认无 TTL，但仍有5000条/4MiB保护，满额保留旧记录并明确拒存新身份。隔离器不支持协议、危险 provider override/具名代理缺缓存、大小与节点总量超限会明确未测，其他配置继续。活动列表不新增运行态不存在的叶子，provider投影缺失时不能仅凭散列历史重建行。详见 [本轮交付与限制](testing/all-profile-node-latency-2026-10-15.md)。
- HEAD仍为 `development@e3ab52bd1afc46b009907f0ee7386fd228914d8e`、暂存区为空。没有Git写操作、候选构建/启动、真实IPC/节点测试或现役代理/TUN/服务操作。控制器、现役Core运行器/生命周期与依赖锁逐hash保持；前一WIP包不含本轮修改。提交/推送由技术负责人执行，真实验收 NOT RUN。
- 主证据 `E:/Temp/fcx-node-latency-all-20261015`（含最终源码SHA、完整输出、覆盖率与渲染图），领域/Go证据 `E:/Temp/fcx-nodeoverview-alltest-20261015/catalog`。本轮前文件保存在 `before/` 及此前 `flclashx-nodeoverview-p1-wip-source-20261015/source-tree`，原草稿与旧包保留。

## 跨配置节点总览 P1 Windows WIP 重建（2026-10-15）

- 用户批准完整重建，沿用技术负责人管理 Git 写操作的边界。HEAD 仍为 `development@e3ab52bd1afc46b009907f0ee7386fd228914d8e`、暂存区为空，没有提交、推送、fetch 或分支操作；没有启动候选或触碰现役代理/TUN/网卡/服务/权限。
- 从冻结的 994 文件 WIP 快照完整新编 Core、Agent、Helper、Dart AOT、runner 和原生插件。快照 ID `4c1df825fcf3641bb17e29443e6e6b66ea1b36b58c659186e61fca33472dc0e1`；42 项复审文件全匹配，构建前后 994 文件逐字节未变。基线提交只表示来源起点，不能将此包当作 e3ab52b 的纯净产物。
- 已交付 `dist/FreedomCloud-windows-amd64-nodeoverview-p1-wip-4c1df825fcf3.zip` 与同名完整解压目录：153,961,998 bytes，SHA256 `d6139a074e46613291c7a30746d2054122061cfd0bccd76897c4a072fa2afa37`。另交付可恢复源码 ZIP 和 source-evidence 清单，旧 P0/DoH 包保留。
- r2 完整构建 exit0，599.17 秒；74 文件/73 checksum，ZIP 和交付目录解压校验 PASS；独立静态审计 8/8 PASS、guard 8/8 PASS。Helper 实际绑定新 Core hash，UI 实际编译输入一致。15 步中包含原有 VS discovery 精确例外，后续 CMake/AOT/native 均成功；首次 overlay 目录重命名失败及审计范围适配失败均保留记录，没有隐去。
- 本轮未改产品源码，未重跑全套测试；下方复审的 Flutter 823、Go/race 与 analyze 既有 warning 证据通过 42 文件 hash 关联。普通未签名 Windows 预览不含 strict 驱动/Broker；真实窗口、IPC、网络节点、代理/TUN 和长时验收仍 NOT RUN，由用户自行操作。
- 构建、组件哈希、失败/重试、独立审计、工具版本及用户测试边界详见 [P1 WIP 预览交付报告](testing/windows-node-overview-p1-preview-2026-10-15.md)。本条及报告为打包后的交付文档，不改变已冻结源码包；下方“未构建”描述保留为对应阶段的历史状态。

## 跨配置节点总览 P1 评审修复（2026-10-15，阶段历史记录）

- 在同一 `development@e3ab52bd1afc46b009907f0ee7386fd228914d8e` 工作树收敛外部评审的 2 个 Medium 与 2 个 Low。经技术负责人独立复审通过，并随后续全配置延迟与批次修复一并归入本地提交 `9c3986e150c8bfb5f2f5cace5cc950b1e0a00b18`。
- Provider 只传有效 HTTP(S) URL 映射的受管缓存路径，file/custom/缺失或无效 URL 不再阻断内联准备；Core 正规化可信 HomeDir，再逐段拒绝 profiles/providers 内部链接，兼容父目录别名并堵住缺目录提前返回边界。
- 非活动目录首屏协议预筛与 Core 对齐，限制通过显式 `isolatedTest` 投影启用，活动 runtime 身份/历史记录保持；节点和左栏统一“最近测速”时间，不再误称活动测试。
- 本轮最终验证：Flutter **823 PASS/0 FAIL/0 SKIP**；4 文件目标 85 PASS（含 UI 43），覆盖率目标 221 PASS，宽窄合成渲染 2 PASS且已看图。Go CGO0 全量与 gVisor 各 **110 顶层+44 子例 PASS**，CGO1 catalog/测速 race **28 顶层+20 子例 PASS**。Analyze **0 error/11 既有 warning/857 info，exit 2**，warning 与首轮逐条一致；非全绿。
- Race 首次捕获旧取消测试替身阻塞：独立复现及超时栈证明通知通道满后无法响应 ctx。仅修 `delay_tasks_test.go` 的通知取消与 cleanup 等待，原 150 个结果、执行预算与资源释放断言全部保留；同两测试连续 20 轮 / 40 次执行及完整回归通过。失败与后续证据均保留。
- 最新证据 `E:/Temp/fcx-nodeoverview-p1-reviewfix-20261015`，`final-source-manifest.json` 固定 **42 个源码/测试文件**。Dart 八模块行 91.40% / 分支 80.85%；Go 语句总体 47.6%、catalog 89.91%，不混称分支覆盖。首轮 39 文件清单、799 项结果与旧截图不回写，下面条目保留为历史。
- 修改清单、矩阵、命令/退出码/时间、Red→Green 与证据链接见 [审查清单的评审修复补记](testing/node-overview-p1-review-2026-10-15.md)。真实候选、网络节点、Windows IPC/QuickJS、代理/TUN、跨平台完整路径矩阵及远端 CI 均 NOT RUN。

## 跨配置节点总览 P1 实现交接（2026-10-15，评审前历史记录）

- 实际起点 `development@e3ab52bd1afc46b009907f0ee7386fd228914d8e`；用户本轮明确将所有 Git 写操作交由技术负责人。实现与测试留在工作树，没有暂存、提交、推送、fetch、分支切换或重置，HEAD 未改变。未生成或启动 P1 候选，未操作现役代理/TUN/网卡/服务/权限。
- UI 去除折叠外壳与活动代理组卡片，宽屏左侧筛选、窄屏下拉、全部配置轻量吸顶标题、单配置平铺、活动节点只读且展示实时延迟；宽窄布局依据实际父约束。新增单节点、当前配置和完整筛选集测速、进度与取消。
- Core/Dart 三个 catalog 动作贯通：独立目录锁、三目录/2000 节点/10 分钟 TTL、共享 150 任务槽与 50 执行预算、目录结果不广播；作用域健康绑定、配置代次、会话 owner 和引用释放。目录按配置依次准备/测速/释放；页面退出或隐藏同步撤销未完成 prepare，迟返不能释放新页面资源或启动隐藏窗口的测试。
- 最终本机验证：Flutter 全量 **799 PASS/0 FAIL/0 SKIP**（108.268s），UI **41 PASS**，合成宽窄渲染 2 PASS且看图；Go CGO0 全量与 `with_gvisor` 各 **107 PASS**，目录/共享测速 race **25 PASS**。`dart analyze --format machine` 为 **0 error、11 既有 warning、857 info，exit 2**，11 条 warning 与本轮初始扫描逐条一致，不声称全绿。Flutter 3.47.4 / Dart 3.13.3 / Go 1.25.13 与 CI 声明版本差异保留披露；未运行远端 CI。
- 预览限制：仅内联节点，provider 缓存仅安全路径/stat；链式、重型、smux 和不能可靠释放/取消的 TUIC、Snell、AnyTLS、Hysteria v1、SS kcptun、Hysteria2 realm 配置暂不支持隔离测速，普通 SS/VMess/VLESS/Trojan/Hysteria2 等保留。限制只作用于新入口，现役协议实现未变。真实节点/Windows IPC/QuickJS/候选启动/TUN/长时验收均 NOT RUN。
- 完整修改清单、矩阵、Red→Green、覆盖率、最终日志、限制和适配器资源链依据见 [P1 技术负责人审查清单](testing/node-overview-p1-review-2026-10-15.md)。私有证据 `E:/Temp/fcx-nodeoverview-p1-20261015`；`final-source-manifest.json` 固定 39 个源码/测试文件 hash。旧 QA、coverage、probes 和 P0 预览包保留。下一步由技术负责人审查并统一处理 Git 写操作；此处不代表已提交、发布或实机验收。

## 跨配置节点总览 P1 隔离测速与界面层级重构排期（2026-10-15）

- 用户明确反馈当前总览中存在严重的视觉与逻辑重复（左侧选配置后右侧依然存在折叠卡片，活动配置嵌套展示代理组卡片与当前视图重复），并要求落地非活动配置节点的后台测速（P1 隔离测速）。
- 方案已由技术负责人完成详细工程设计，详见 [P1 隔离测速与界面层级重构工程书](plans/cross-profile-node-overview-p1-and-ui-refactor-2026-10-15.md)。
- 关键重构点：
  1. 彻底废除手风琴折叠（移除 `_expanded` 状态与外层折叠卡片）：左侧栏专注作为配置筛选器（“全部配置”及各配置），右侧为平铺节点列表直出；“全部配置”时由轻量吸顶标题分段，选中单个配置时仅直出该配置节点。
  2. 活动配置叶子节点扁平化：移除代理组嵌套与 `ProxyCard`，统一渲染为扁平节点行，绑定实时延迟与色彩；节点选择逻辑严格留在“当前配置”视图。
  3. P1 隔离测速：Go Core 新增 `catalogPrepare`、`catalogTestDelay`、`catalogRelease`，利用独立出站适配器在后台测速，不切换配置、不影响 TUN、不打断现有连接；Dart 协调器扩展 `scope` 统一并发调度。
- 任务拆解与提示词已整理完备，已向开发人员（Dev）派发执行。技术负责人负责代码审查与门禁质量把关。

## 跨配置节点总览 P0 推送与 Windows 预览（2026-10-15）

- 用户新授权推送、打包，由用户在本机测试，观察方只读看日志。`2074cce → f6dff78c762654af1f77adfa46eed697a1492626` 共 5 提交已正常推送自有 `freedomcloud/development`，远端 SHA 回读一致；未晋级 main、未 PR/tag/release。下方“仅本地”是上一阶段历史状态。
- 固定源 [CI 38713589918](https://github.com/Hao-Monster/FreedomCloud/actions/runs/38713589918) 4/4 success：Flutter 731 PASS/1 既有 Linux cmd.exe skip，Core Linux 默认/with_gvisor/四组 race、Windows Core 专项、Agent83/Helper48、M3 四脚本均通过。本机此前732项无skip结果保持为修复阶段证据。
- 从干净 tracked Git archive 完整新编并交付 `dist/FreedomCloud-windows-amd64-nodeoverview-f6dff78c7626.zip` 及同名完整解压目录；153,831,212 bytes，SHA256 `30793c99108b69fdd040253d7ea1dea4dd4dc618d870aa584080d33f0b3ffc46`。构建 r1 exit0、约345.44s；73文件/72checksum，独立静态审计8/8 PASS，Helper实际绑定Core hash、UI编译输入一致。普通未签名预览，无strict驱动/Broker，旧DoH包及原始草稿保留。
- 本轮没有产品源码改动；交付文档单独提交，不改变固定包源码。完整命令、工具差异、已知VS发现exit1与后续实际编译、测试矩阵、组件hash及用户验收见 [节点总览预览交付](testing/windows-node-overview-preview-2026-10-15.md)。
- 只读观察工具私有目录 `E:\Temp\flclashx-nodeoverview-monitor-20261015-f6dff78c7626`，21项合成测试PASS；09:45:54Z从15个日志EOF建立新基线，0读取错误/缺口，现役UI/Agent仍是旧DoH包。已启用本对话每5分钟心跳，关注node.health原因、UI异常、组件生命周期和DNS失败，仅读增量并脱敏计数。候选启动和操作由用户执行；打包方未启动候选、未改代理/TUN/节点/服务/配置。真实Windows接管、UI/IPC、网络与长时验收仍待用户，不以静态包或无错误日志代替。

## 跨配置节点总览 P0 评审修复（2026-10-15，仅本地）

- 来源：用户对 `c8fa0a3` 的复评明确该版不能按 P0 验收。修复起点 `development@5a38b1a`，fetch 后领先自有远端 3、落后 0，无开放 PR；最新远端 CI 仍只对应 `2074cce`。本轮沿用本地实施/测试/提交授权，不推送、不运行候选、不操作现役代理/TUN。
- 四项修复：控制流取消不覆盖健康结果；单坏节点仅自身显示无法识别；可见折叠配置与宽侧栏自动构建摘要；接管通过已有只读 `fcx://runtime` 与文件的可识别节点集合核对，匹配后可记录显式测速。先前“需新增只读协议”的判断已纠正。原始 Future 与可撤销归属令牌防止配置切换/同 ID 更新及删除重建的迟返串写；缺失 Core 接口时读取不构造单例。
- 同轮调整：范围入口回到工具栏、色带沿用现有色阶、活动来源只取可信运行目录；活动时间使用实际组级 URL，不串用默认 URL 历史。后续批次刷新读取不再撤销前一批未完成的校验。缓存内部 schema 2 迁移只保留 v1 成功值，旧负值均变未测（旧版错误码存在歧义）；无法恢复此前已被覆盖的好值。Go Core、Agent、Helper、协议和锁文件未变。
- 源码/测试已本地提交 `2ecb4ece674dd9668ac6cdde355f8088cdcca4c3`（`fix(proxies): address node overview P0 review findings`）。最终目标 130 PASS、全 Flutter 732 PASS/0 FAIL/0 SKIP、UI 行为 26 + 合成宽窄渲染 2 PASS且看图、Windows debug UI 资源编译 PASS。七个手写模块行覆盖 897/960（93.44%）、分支 321/370（86.76%）；全仓 analyze 0 error、11 既有 warning、851 info，exit 1，无新增 error/warning。独立审查发现的相关问题均已补修并回归。完整矩阵、命令、Red→Green、覆盖率及失败记录见 [P0 评审修复记录](testing/node-overview-p0-review-2026-10-15.md)。下方首轮计数保持为历史证据，不代表复评通过。
- 交付边界：未推送、未 PR/合并、未部署、未生成或启动可执行候选；真实 Windows 接管/IPC/QuickJS、代理/TUN、性能与长时验收 NOT RUN。P1/P2 未实施，无请求归属广播及无法证明运行归属时不写新历史。原 coverage/QA/probes 5 文件 hash、stash、历史工作树保持原状。

## 跨配置节点总览 P0（2026-10-15，首轮历史记录，已被上方复评修复替代）

- 来源：[工程书](plans/cross-profile-node-overview-2026-10-15.md) 设计基线 `2074cce`，实际开工 `development@c7166fe`（仅增加工程书/台账，fetch 后领先自有远端 1、落后 0，无开放 PR）。用户明确授权从 P0 实施、测试和本地提交；不推送、不运行候选包、不影响现役代理/TUN。
- 源码与测试已本地提交 `c8fa0a3f55386778a4d1f17c7ce4845a03980449`（`feat(proxies): add cross-profile node overview P0`）。实现脱敏目录/稳定键、受限并发与 LRU、跨会话健康文件、按请求捕获归属、宽窄总览/搜索/排序/筛选/异常卡、活动 ProxyCard 复用和四语言文案。`FCX_NODE_OVERVIEW=false` 可关闭；当前配置仍默认，少于两个配置隐藏范围入口。Core/Agent/Helper 未改动。
- 验证：新增目标 64 PASS，全 Flutter 674 PASS/0 FAIL/0 SKIP；合成渲染 400×800、1200×900 两项 PASS 且看图；Windows debug UI 资源编译 PASS（非可执行预览包）。新增六个手写模块行覆盖率 726/787（92.25%）、分支 240/282（85.11%）。全仓 analyze 0 error、11 既有 warning，退出 1，未冒充全绿；最终独立复核未发现未解决 Critical/High。首次提前初始化回归和 coverage 内存崩溃均保留失败证据，前者已修复并重跑，后者以分离/降低并发采集成功。完整矩阵、命令、覆盖缺口见 [P0 测试记录](testing/node-overview-p0-2026-10-15.md)。本机 Flutter 3.47.4 / Dart 3.13.3，CI 仍声明 Flutter 3.41.7，未升级依赖。
- **验收限制**：FR-4 只记录可绑定到已应用快照的显式测速；接管已有 Core 且本会话未应用配置时缺少可信快照，保留实时值/旧历史，不新写历史；无归属自动广播同样不写。UI 有说明，未用 setup/重启补救。因此 P0 本地实现已交付，完整接管历史与真实运行验收尚未完成。非活动 provider 叶子属 P1；peers-only WireGuard 缺顶层 server/port 时目录明确解析失败。
- 交付状态：仅本地源码和本地文档提交；未推送、未 PR/合并、未生成可执行预览、未部署、未启动候选。真实窗口、性能、QuickJS/IPC 与现役代理/TUN 验收 NOT RUN。原 coverage/QA/probes 文件 hash、stash、历史工作树保持原状。后续先补可信只读运行身份契约或明确接管限制，再按授权构建预览和运行验收；P1/P2 未实施，P1 改 Core 时仍须整包重建、Helper/Core hash 绑定及 VM 证据。

## DoH 静默连接恢复回归修复（2026-10-14）

- 来源：两份独立审查对 `4e4a146` 的同一 P2——调用方 5s 截止（`DefaultDNSTimeout`）总先于 `http.Client.Timeout`（5s）到期，“调用方已过期即返回”跳过恢复，静默的 HTTP/2/HTTP/3 连接留在池中，后续查询继续复用并再次超时，只能等 H2 ping（约 30–45s）/QUIC idle 或切网 `ResetConnection`。两项发现为同一根因。
- 修复（本地提交 `4fdf293`，基于 `fa758a6`）：新增 `dns/doh_health_fcx.go` 按客户端代次统计应答。调用方截止且该代次在整个请求期间**没有任何应答**时，立即停止分发该代次（`doh.client=nil`，下一次查询懒建新连接），延迟 `fcxDoHRetireGrace`（默认 5s）再关闭，避免切断仍在途的并发请求。取消、旧代次、锁竞争（`TryLock`）一律不计；保留代次保护、显式重置不被撤销、0-RTT 与最多两次重试。健康判断用单调应答计数而非墙钟时间戳——首版时间戳在 Windows 粗粒度时钟下被真实 H2 探针抓到误判“期间有应答”。
- 新增日志 `[DNS][DoH] <host>`：重试（Debug）、旧代次失败忽略/重置跳过（Debug）、重建连接池及原因（Info）、静默连接退役（Warn，含时长/末次错误/累计次数）、延迟关闭结果（Debug/Warn）、建池失败（Warn）、截止但期间有应答而保留（Debug）。仅记录 host，错误文本中的 DoH 路径/查询串被替换，避免账号标识进日志。
- 验证：overlay 生成器 PASS；DoH 专项 24 组 + 2 子例 PASS，重复 10 轮 PASS（原“截止即保留 client”断言已按新语义改写）；审查者真实 TLS/HTTP/2 黑洞探针 **时间戳版 FAIL → 最终 PASS**（下一次查询新建 TCP、7ms 成功）；内存静默探针 PASS；dns 包 vet PASS；Core `-tags=with_gvisor ./...` PASS；`git diff --check` PASS。本机 Go 1.25.13（CI 1.26.0）。
- 2026-10-15 交付补记：源码 `335911106ea827ae9776789c8563d0409f227a4a`（含 `4fdf293` 修复及 `3359111` 文档）已在自有 `freedomcloud/development`，本轮 fetch/远端回读一致；[CI 38671805210](https://github.com/Hao-Monster/FreedomCloud/actions/runs/38671805210) 对应该 SHA，4/4 success。Linux DoH `-race` 实际 PASS（2.198s），Windows Core 专项 PASS，Agent 83/Helper 48 PASS；Flutter 609 PASS/1 SKIP（Linux 无 cmd.exe 的既有用例），M3 四脚本 PASS。本机 Windows race 仍因 UCRT 链接限制 NOT RUN，不能将其误写为 CI race 未运行。
- 同 SHA 完整新编 Core/Agent/Helper/UI 的普通未签名包：`dist/FreedomCloud-windows-amd64-dohfix-335911106ea8.zip`，153,567,226 bytes，SHA256 `20fb8fe5c6b61515a92c444360d11b8410e4435484da620b865399982c5e7199`；同名完整解压目录已逐项核对。构建 r2 exit 0，73 文件/72 checksum、独立静态审计 8/8 PASS，Helper 实际内嵌的新 Core hash 与 UI 编译输入一致；新增 `dns/doh_health_fcx.go` 在包内 manifest/唯一 overlay 映射/生成文件的专项核验 PASS。未覆盖旧产物，未混用旧 Core/Helper。
- r1 构建失败证据保留：`E:\Temp\flclashx-dohfix-preview-20261015-335911106ea8-r1` 的 AOT `zone.cc: 95: error: Out of memory`，snapshotter exit `-1073740791`。用户表示内存已改善后在全新 r2 重建；同源码/同脚本的 AOT 70.780s PASS、完整构建约 408.66s。便携 pwsh 7.6.7 的 ZIP digest 已核对官方 release；本地 Flutter 3.47.4/Go1.25.13 与 CI 3.41.7/1.26.0 的差异及已知 VS config-only exit 1 均保留披露。
- 详细组件 hash、15 步构建、独立审计、CI 证据、r1 失败、观察信号及换包/回退见[DoH 静默连接修复预览交付](testing/windows-dohfix-preview-2026-10-15.md)。交付文档单独本地提交，本任务未推送文档、未 PR/合并/发布/部署。真实微信长时、TUN/SCM/切网/休眠实机及候选运行仍 NOT RUN；未操作本机客户端、代理/TUN/服务、UAC，未启动或修改观察脚本。
- 已知取舍：空闲连接上单个慢查询（>5s 且无其他应答）会触发一次重连；上游完全不可达时每个超时查询各退役一个代次，Warn 日志随之增加（含累计计数便于识别）。

## 微信间歇断网调查与 DoH 恢复修复（2026-10-14）

- 用户确认微信长时运行后显示网络不可用、微信不重启而关闭 TUN 即恢复，授权定位、修复、回归及独立新预览。本轮从 `development@3c48432a77971a3e0c18a26ca1c55d1632df04e6` 继续，仅本地提交，未授权推送/PR/合并/发布；当前客户端、服务及网络保持不动，旧包/草稿/stash/历史工作树保留。
- 现场被动证据仍来自旧 `resourcefix-485abf4d2e86`，20:35–20:37 双栈公网 DIRECT 与 DoH 暂时性故障，之后同 PID 恢复部分新连接。用户微信业务是否恢复及关闭 TUN 精确时间未由自动化观察确认。不能把此缩减为“网卡 Up 即正常”，或认定今天旧候选已被实机测试。
- 固定 Mihomo v1.19.32 overlay 仅替换三个 DoH 方法：请求到期/取消不重置共享 client，迟到错误仅允许作用于原失败代次，锁等待后重新检查 context。保留有效 transport timeout、0-RTT、显式 ResetConnection 与最多两次重试。未改 DNS/TLS/分流默认值、TUN 栈或依赖版本。此修复消除已重现的 DNS 恢复放大器，尚不能独立解释全部公网 IP 超时。
- 原始同一 5 项内存探针 **2 FAIL/3 PASS → 5 PASS**；新增 17 组 + 2 子例随机重复 100 轮全部通过；Core 普通与 gVisor 各 81 组 + 17 子例、既有补丁专项 17 组 + 2 子例、vet、Agent83/Helper48 均通过。独立审查无本轮新增高置信阻塞，移除身份/锁内取消保护的隔离变异被测试检出。三方法语句覆盖 51/58（87.9%），无 Go 分支率。
- 环境限制：Helper 首次链接器路径误选，子进程使用既有 MSVC 后全套通过；Go1.25 coverage+overlay 编译限制由逐文件匹配 manifest 的隔离 effective-source 副本补测；Windows race 因现有 UCRT ld 依赖加载失败未执行。DNS Windows/Linux-race CI 命令已加入，但新提交尚未推送，不能借用旧 CI 结果。
- 源码已本地提交为 `4e4a146513c90e18090fe87a7f9eeada501e5a71`（`fix(core): isolate DoH recovery from expired and stale requests`），从该干净 tracked SHA 完整重编 Core/Agent/Helper/UI/原生插件。普通未签名包 `dist/FreedomCloud-windows-amd64-tunwechat-4e4a146513c9.zip` 为 153,556,800 bytes，SHA256 `db4a47bafceb0af6981c496e4d407e59ccadbdd5673af9416732dba3ef604a1f`；同名完整解压目录已校验，旧包未覆盖。
- 独立产物审计 8/8 PASS：73 文件/72 checksum、955 源 blob、32 组件、14 插件/111 输入；Helper 实际新 Core hash、UI 编译输入/AOT与包含 DoH 补丁的 14 模板/12 映射一致。Flutter config-only 的已知 VS 识别失败如实保留，后续完整 CMake/Ninja/AOT/Windows 编译通过；未运行候选。
- 详细范围/矩阵见 [计划](plans/windows-tun-wechat-reliability-2026-10-14.md)，命令、计数、失败记录、覆盖率及未验证项见 [回归报告](testing/windows-tun-wechat-reliability-2026-10-14.md)，产物来源/hash/构建与用户验收见 [新预览交付](testing/windows-tun-wechat-preview-2026-10-14.md)。交付文档另作本地提交，不改变包的 `4e4a146` 源码；本轮源码与交付文档均未推送。真实微信长时、TUN/SCM/切网/休眠验收仍 NOT RUN，须先确认实际运行组件匹配，不将静态文件 hash 当作运行验收。

## TUN 修复源码推送与 Windows 预览（2026-10-14）

- 用户授权正常推送全部开发代码并重打预览，由用户自行测试、观察方只读看日志/运行。`f08fedb → fb6f5d43e204b1cc47278b8916ecae2ebc1dcccf` 共 9 提交已推送自有 `freedomcloud/development`，远端 SHA 回读一致；未晋级 main、未建 PR/tag/release。原 coverage、QA/probes、stash、47 历史工作树及旧包保留未动。
- 精确源码 [CI 38525761829](https://github.com/Hao-Monster/FreedomCloud/actions/runs/38525761829) 四项全通过：Flutter 609 PASS/0 FAIL/1 Linux 平台 skip（Windows cmd.exe）；本机对应 11 项补跑全通过。Core 按预览 CGO=0/with_gvisor 全量 91 PASS，CI Linux/race 和 Windows Core/Agent 83/Helper 48 通过。未把此前 CGO=1 环境编译失败记为修复。
- 从干净 tracked HEAD 的 Git archive 完整重编 Core/Agent/Helper/UI/原生插件；普通未签名包 `dist/FreedomCloud-windows-amd64-tunfix-fb6f5d43e204.zip`，153,552,555 bytes，SHA256 `4c70e5cba8d9afb1b13de47fcf674232a82318c5070b88295040cd7096393055`。同名解压目录已准备并校验，旧包未覆盖。
- 独立产物审计 8/8 PASS：73 文件/72 校验、948 源 blob、14 插件/111 输入、Helper 实际新 Core hash、UI 编译定义及固定 overlay 一致；无用户配置/凭据/私密日志和 strict 驱动/Broker。构建工具适配与只读观察脚本另做审查。
- 详细矩阵、构建命令、组件 hash、工具版本漂移及用户验收见 [Windows TUN 预览报告](testing/windows-tun-preview-2026-10-14.md)。本条为打包后文档，不改变包对应的 `fb6f5d4` 源码。
- 交付时现役仍为旧 `resourcefix-485abf4d2e86`；候选未启动，未操作当前代理/TUN/服务。用户真实开关、权限、慢关闭、切网/休眠与长时稳定性仍 NOT RUN；观察不连接 Agent IPC，不将静态构建或网卡 Up 当作运行验收。

## TUN 启动与状态同步稳定性修复（2026-10-13，第一批）

- 来源：对 `resourcefix-485abf4d2e86` 现场“Core 已建卡、UI 报 statusUnavailable/TUN 未开启”及外部只读排查的复核。起点 `development@f08fedb`（与 `freedomcloud/development` 领先0/落后0）。原 coverage、QA 草稿、probes、stash、历史工作树均保留未动。
- Core overlay：`GetTunLifecycleStatus` 改为读取原子发布的快照，不再等待建卡持有的 `tunMux`；`ReCreateTun` 在建卡前发布 `starting`，结束和 `Cleanup` 时发布终态。新增 `TestFCXTunStatusReadableDuringSlowCreation`。Mihomo 固定版本/上游 hash 未变，仅补丁内容变化（manifest 中补丁 hash 会随之变化，Helper 绑定的 Core hash 需随新包重建）。
- Dart：① Agent 只在 Core 状态切换时推送 `proxyRunning`，现由 `ClashService` 在同一 Core 确认 start/stopListener 后同步缓存，TUN 重开不再误判为全量重载；② 启动最终验证对 null/unknown 做有界等待（默认 8 次×500ms），并接受观察器已采纳的新鲜读数，不再因并发轮询失效 epoch 而误报；③ 轮询之后读到同一 Core TUN 已开且运行投影缺失时补做一次 `reflectRunning`；④ `TunRuntimeController.requestFailure` 与观察失败分离，后台配置刷新的降级只看真实请求失败；⑤ `_setupClashConfigImpl` 只合并订阅同步字段，不再整份回写旧快照覆盖 TUN 开关。
- 验证：Core overlay `TestFCXTun*` PASS；Core `-tags=with_gvisor ./...` PASS（本机 Go 1.25.13，CI 为 1.26.0）。Flutter 3.47.4（与已提交 `pubspec.lock` 一致）全量 **599 PASS/0 FAIL**，锁文件未变化。另用 CI 声明的 3.41.7 跑过：TUN/Agent 相关 9 个文件 77 PASS/0 FAIL，全量 592 PASS/7 FAIL，7 项均为 `ink_sparkle.frag` 着色器资源版本不兼容（未修改模块），该 SDK 改写的 `pubspec.lock` 已还原。定向 analyze 无 error/warning。新增用例依赖新 API，未在修复前代码上执行 Red。
- NOT RUN：race 用例、ClashService 监听缓存的单元测试（需真实 Agent 连接）、真实 Windows 开关/切网/休眠恢复/长时运行、预览包构建、CI。未推送、未 PR、未打包、未改动本机代理/TUN/服务。
- 待处理（第二批）：网卡消失（interfaceMissing/listener 仍在）时用户无法直接重开且 `ReCreateTun` 同配置不重建；`closeFailed` 锁存无自动恢复；全量路径内 `checkAndUpdate` 联网拉订阅；订阅 `tun.stack` 覆盖导致重建网卡；网卡名精确匹配与 Up 判定在真机的可靠性。

## TUN 网卡消失与 closeFailed 恢复（2026-10-13，第二批）

- 起点：第一批本地提交 `f0aa190` 之上，同一 `development` 工作树。
- Core overlay：`ReCreateTun` 同配置快速路径增加 `fcxTunInterfaceUsable(device)`；Windows 上网卡缺失或非 Up 时关闭并重建，枚举失败或非 Windows 保持原行为。新增 `TestFCXTunIdenticalReloadRebuildsVanishedAdapter`。`tun_status.go` 网卡名改为大小写不敏感匹配（`matchTunInterface`，新增 `TestTunInterfaceMatchIsCaseInsensitive`）。补丁 hash 再次变化，Core 与 Helper 必须一同重建。
- Dart：① 用户显式开启时，已提权 Core 返回 unknown（如 interfaceMissing）也允许下发配置以触发重建；后台刷新仍不对 unknown 动作，未提权仍拒绝。② 启动/显式开启读到 `closeFailed` 时先在同一后端重启 Core（不提权、不重入 TUN 队列），再强制走全量配置与监听。③ 轮询发现同一 Core listener 仍在而网卡 `interfaceMissing` 且偏好开启、无请求失败、已提权时，自动走增量路径重建；不请求 UAC，失败记为请求失败并停止重试，每个 Core 实例最多 2 次，读到 on 后清零。`interfaceDown`（可能是用户禁用网卡）只在用户显式开启时修复，不后台自动修复。
- 复核后不改：`checkAndUpdate` 只在配置文件缺失时下载，而启动前已要求可读配置，原先“全量路径联网拉订阅”的判断夸大；订阅覆盖 `tun.stack` 属既有设计（`overrideNetworkSettings=false`），栈变化本就需要重建网卡。
- 验证：Core overlay `TestFCXTun*` PASS；Core `-tags=with_gvisor ./...` PASS（Go 1.25.13，CI 为 1.26.0）。Flutter 3.47.4 全量 **607 PASS/0 FAIL**（新增 8 项），`pubspec.lock` 未变化；定向 analyze 无 error/warning。新增 Dart 用例依赖新接口，未在修复前代码执行 Red。
- NOT RUN：真实 Windows 网卡删除/禁用、驱动重置、closeFailed 现场、切网/休眠/长时运行、race 用例、CI 3.41.7 复跑、预览包构建。未推送、未 PR、未打包、未改动本机代理/TUN/服务。

## TUN 交叉审查补修（2026-10-13，第二批之后）

- 来源：对 `f08fedb → 315274c` 的外部交叉审查，2 项 P2，均复核属实。
- P2-1 慢关闭期间仍报告旧 `on`：`closeTunListener` 已清除内部 listener 并进入可能阻塞的 `Close()`，但快照只在函数返回时发布。现于 `Close()` 前发布 `state=unknown / ListenerActive=false` 过渡快照并推进 revision，关闭结束后由调用方发布真实终态（off 或 closeFailed），不提前宣称关闭成功；`starting` 过渡同样改为独立 revision（`fcxPublishTunTransition`）。新增 `TestFCXTunStatusNotReadyDuringSlowClose`（Cleanup 与 ReCreateTun(disable) 两个子场景）。**Red**：用 HEAD 的 `close_tun.txt` 运行，两个子场景均返回旧 `on`，与审查一致；恢复修复后 Green。
- P2-2 `proxyRunning` 缓存被不含该字段的 Agent 事件清空：Agent `publish_strict_status` 与 `commandResult` 报文不带 `proxyRunning`，原解析为 null 后无条件覆盖。现 `AgentEvent.proxyRunningReported` 区分“未提供字段”和“显式 null”；`mergeAgentProxyRunning` 仅在同一 ready Core 上对缺字段事件保留缓存，显式 null 仍清空，换 Core 或非 ready 清空。回归测试使用 `runtime.rs` 实际报文形状。Agent 未改动。该 Dart 用例依赖新 API，未执行 Red。
- 验证：Core overlay `TestFCXTun*` 8 项 PASS；Core `-tags=with_gvisor ./...` PASS（Go 1.25.13）。Flutter 3.47.4 全量 **610 PASS/0 FAIL**，`pubspec.lock` 未变。审查方报告的主 Core `TestTun*` cgo 编译失败本机未复现（本机全量 Core 通过）。
- NOT RUN：真实 Windows 慢关闭/切网/休眠/长时运行、race、CI、预览包。未推送、未打包、未改动本机代理/TUN/服务。

## 开发分支累计源码晋级（2026-10-12，合并前快照）

- 用户明确授权本次正常推送 `development` 并通过 PR 合并 `main`，暂不生成可执行客户端包。只做源码集成和质量检查；不创建版本标签、不运行候选客户端、不修改当前代理/TUN/服务、不部署。
- 开工 fetch 后：本地 `development@a97e42d860b40e4918d9310328e4582ac445d2d8`，远端 `development@6ce68d86e855573c1d1e42cdaf4af3073b58005b`，自有 `main@4738293ea90ca9b90afcc201a5c9a09b729a86ad`；本地领先开发远端11个、领先主线31个提交，均无落后，无开放 PR。晋级范围包含此前 Core/TUN、Windows 启动、托盘及资源生命周期修复，不仅是本轮购买卡片。
- 将已经确认的仅兑换码 v2 方案/任务/测试矩阵与 v1 作废标记作为独立文档提交保存，避免主线继续把余额结算当作当前需求。套餐目录及富文本展示已实现；v2 四区域布局整理仍是未执行任务，不据此宣称完整新版购买页已交付。
- 最新本地产品验证对应 `a97e42d`：全 Flutter 591 PASS/0 FAIL/0 SKIP，购买目标58项通过，定向 analyze 无问题；详见[卡片富文本测试报告](testing/plan-card-rich-content-2026-10-11.md)。其他批次沿用各自历史证据，最终 head 的远端 CI 尚待本轮推送后核实。
- 已回读主线保护：必需 PR、三项指定 Actions 检查、严格更新、讨论解决、管理员适用，禁止强推/删除；本次另等待 Windows Core and service tests，采用普通 merge commit，再把主线合并提交快进同步回 `development`。不改保护设置。
- 已核对全部 workflow 触发器：普通 `development`/`main` push 与 PR 只触发 `quality-gate`；可执行包构建要求版本标签、独立旧预览分支或手动触发，本轮均不执行。M3 package integrity checks 只是现有工具/清单测试，不是客户端发行包。
- 原 coverage、原生 QA/probes、stash、旧工作树和已有预览包保持原位，不混入提交。系统/真实兑换/实机验收边界维持各报告的 NOT RUN；合并不代表打包、部署或正式发布。
- `a92e3ec` 已正常推送，单一晋级 [PR #60](https://github.com/Hao-Monster/FreedomCloud/pull/60) 已建立。三个独立只读审查覆盖累计产品范围；CI 在 Linux 复现两条托盘测试错误平台预期，Core/Windows service/M3 检查通过。仅修正测试的真实宿主调用顺序/tooltip断言，不改产品代码、不新增skip，最终head重新通过全部检查前不合并。
- 本轮具体 Red、Windows 回归、静态检查、历史空白诊断及 NOT RUN 边界见[源码晋级验证](testing/source-promotion-2026-10-12.md)。最终合并SHA、最终head CI和两分支同步结果以同一 PR 的实际记录为准；不为记录自身合并SHA再追加造成分叉的文档提交。

## 购买页重新设计：只用兑换码（2026-10-11）

- 用户明确排除钱包、余额支付、第三方支付、金额补差和余额结算：通过微信或其他渠道取得兑换码，再兑换套餐。2026-10-10的v1方案/开发任务/测试矩阵已标记作废；不再等待或申请其中的后端扩展。
- 当前development@c2fe8c5；fetch freedomcloud成功，本地领先10/落后0。无开放development PR；最新CI仍对应旧6ce68d8，不是本轮验证。原coverage、QA/probes、stash和旧工作树保持不动。
- 客户端及Xboard-Go本地07476e0只读核实：现有查码/兑换/历史和type4套餐购买码已能支持主链；套餐取自兑换码，浏览目录不创建订单。旧卡类型保留原规则，不改成余额支付。
- v2方案、5项开发任务、12组测试任务已整理到engineering/plans/purchase-redemption-2026-10-11.md、engineering/tasks/purchase-redemption-2026-10-11.md、engineering/testing/purchase-redemption-2026-10-11.md。
- 独立只读复核通过；文档git diff --check通过，6份新旧方案文档的13个相对链接有效，无行尾空白。文档修订保留在当前工作树，本轮重新设计未创建新提交。
- 本轮只重新设计和更新文档，尚未实现新版布局或执行功能测试；未改产品/后端代码，未真实兑换、修改模板、启动客户端、推送或部署。

## 历史：完整购买流程v1（2026-10-10，已由2026-10-11用户纠正作废）

- 用户要求先研究方案、拆开发任务，再开发和测试；仍保留仅购买页的范围限制。当前研究基线development@70c4643；Xboard-Go本地07476e0不等于线上部署版本。两次Git fetch因网络失败，另用GitHub API核实远端development为6ce68d8，本地领先9/落后0；无开放development PR，旧CI成功不是本轮验证。
- 源码与已打开网页只读核实：余额扣款基础存在，但普通用户接口缺购买上下文余额/币种组合与完整报价；创建订单会立即抵扣余额，且无请求幂等键。不能只串客户端接口就承诺可靠完整结算。当前后台可见模板未见余额型通用卡，本轮未新增/修改。
- 推荐仅改客户端购买页，并新增Xboard-Go必要购买上下文、无消费报价、原子余额型购买和精确恢复接口/防重记录；旧页面、旧兑换与订单合同保留。type4快照码和标准onetime订单权益规则不同，不能统一成相同叠加。
- 已编制方案、开发任务、30组测试矩阵：engineering/plans/purchase-checkout-2026-10-10.md、engineering/tasks/purchase-checkout-2026-10-10.md、engineering/testing/purchase-checkout-plan-2026-10-10.md。状态为等待用户确认后端范围和业务基线，产品实现未开始。
- 已完成后端合同与文档独立审查，补入报价时间派生字段、单报价执行绑定、不同请求争用有限资源，以及邀请奖励/佣金/折抵旧单共同回滚的验收条件；这是方案审查，不是新功能测试通过。
- 文档检查：git diff --check通过；3份新增文档的5个相对链接均有效，无行尾空白；修订后的独立文档复核通过。方案文档作为独立本地成果保存，产品开发任务仍等待G0确认。
- 本轮未运行新的购买功能测试，全部新用例NOT RUN；未真实下单/兑换、未启动完整客户端、未推送/部署。现有coverage/QA/probes/stash/工作树和后台未跟踪文档均保留。

## 购买页公开套餐展示补全（2026-10-10）

- 用户授权“先研究一个方案，然后进行开发”，仅补全购买页套餐信息。起点 `development@b565b33da5cf4d95baa9a2e752b5884f26fa57dd`；fetch自有远端后领先8、落后0，无开放development PR；最近CI成功对应旧 `6ce68d8`，不是本轮证据。原coverage、QA原稿、stash、历史工作树与旧包保留。
- 本轮匿名GET和Xboard-Go本地源码确认公开字段已存在，客户端原解析丢弃。现保留并呈现正文Markdown、标签、明确限额、流量重置规则、销售剩余名额和单列重置标价；不猜测币种，不改变匿名可见集合、七新购周期、价格精度或礼品卡兑换行为。账号左下角入口、其他页面、在线支付、后端、代理/TUN均未修改。
- 正文使用原生 `flutter_markdown_plus 1.0.12` / `markdown 7.3.1`（只新增两项依赖，BSD许可）；仅无属性u可扩展，其余HTML保持原文，图片以alt占位不加载外部资源；仅显式HTTPS链接经购买页原有外跳和失败提示。4语言既有ARB键值未变。
- 有效宿主Red 0/2→Green；审查期间修正HTML根文本丢失、linked-image alt、复合下划线、未闭合u扫描和多字体列表缩进，并补入口异常/段落隔离/实际文字盒断言。最终购买模块 **268 PASS/0 FAIL/0 SKIP**；全Flutter带行/分支coverage **563 PASS/0 FAIL/0 SKIP**，墙钟95.44秒；定向analyze无error/warning/info；Windows目标debug UI资源编译exit0（非可运行包）。
- 本轮LCOV记录的可执行diff行161/162（99.38%），分支43/43（100%）；默认父样式兜底未命中，新增const字段无LCOV可执行行记录。真实Widget树4张中文浅/深/窄窗/2x截图已查看，保存在 `build/plan-catalog-completeness-preview`，均为合成套餐，不是真实客户端运行。独立只读复核最后无新增阻塞。
- 方案与本轮详细证据：`engineering/plans/plan-catalog-completeness-2026-10-10.md`、`engineering/testing/plan-catalog-completeness-2026-10-10.md`。目标分支为development，源码和本节随同一可追溯本地提交保存；未推送、未PR/合并、未打新可执行包、未部署。
- NOT RUN：真实Windows窗口/外部浏览器、真实账户/兑换/支付、各平台设备、Core/Agent/Helper新验证、代理/TUN与系统服务、CI。下一步如需预览包，须从本轮精确提交单独构建并标明组件来源，完整启动/网络验收须另获环境授权。

## 运行诊断后续资源修复（2026-10-09）

- 用户授权先研究再修复，起点 `development@13b0ea05dfca6840e402a1f29d543705e30382e4`。方案先冻结到 `docs-dev/resource-followup-plan-2026-10-09.md`，再实施 R1 Helper日志所有权/输出收尾、R2 Windows图标有界队列/消费者释放、R3健康检查缓存清理/代际隔离。旧coverage、QA草稿、分支/工作树和预览包均保留。
- 三项均有有效Red→Green；交叉审查补充修复既有UNC/rooted图标key碰撞并加强失效快照消息与活动监听释放断言。汇总及三个模块证据见 `docs-dev/resource-followup-results-2026-10-09.md`。没有改变日志级别、进程优先级、Mihomo固定版本、购买或代理/TUN产品行为，没有新生产依赖。
- 最终完整Flutter 476 PASS/0 FAIL/0 SKIP；图标目标22项；Helper service48/default45项；Core普通90/with_gvisor90项、health/config/controller race22项、overlay合同race14项全部通过。Dart定向analyze 0error/0warning/22info，service clippy通过；额外default clippy保留未修改process_stop.rs:39的既有dead_code错误。
- 本轮Dart文本diff可执行行173/271（63.84%）、分支74/96（77.08%），含整页包装缩进；新队列与activity scope在LCOV中的行/分支100%。真实ConnectionsView整页/Win32平台入口未覆盖。Core package statement42.9%，Rust未采集coverage，范围和缺口已披露。
- 三模块非作者复核无剩余本轮源码阻塞。源码已保存为本地提交 `485abf4d2e8664b8e03fb17ed63add2a3b2359c8`（`fix: bound residual resource lifecycles`）；当前客户端/服务/网络保持不动，真实SCM/SYSTEM、窗口/导航、长时资源及其他平台验收NOT RUN。不推送、不合并、不发布。
- 从485abf4的精确Git archive完整重编Core/Agent/Helper/UI/原生插件，Windows构建exit0；新普通未签名包 `dist/FreedomCloud-windows-amd64-resourcefix-485abf4d2e86.zip`，152,994,092 bytes，SHA256 `050695fe6ad62e64f4efcb4985fd9c65f75cbf4b61b9276820087a66a1f318c5`。dist及聊天outputs副本/hash一致，旧包未覆盖；构建与交付见 `docs-dev/evidence/resource-followup-build-2026-10-09.md`。
- 独立产物审查8组PASS：73文件/72内部校验、931源blob、32组件、14插件/111输入、Helper/Core绑定、UI编译定义及1015有效overlay文件一致。唯一x86为既有EnableLoopback，其他29个PE为x64；运行NOT RUN和配置共享/启动副作用声明保留。交付文档单独本地提交，未运行候选版本，未把静态审查认定为长期无泄漏。

## 性能、资源与可靠性17项修复（2026-10-09）

- 用户授权在唯一 `development` 分支逐项修复、统一打包后自行本机测试。修复基线 `a52907c2d4425f6c1679792f64a3129ae4c562d7`；未推送/发布，未启动候选客户端或修改现役代理/TUN/SCM/驱动/Shell。原coverage/QA草稿及旧包保留。
- F01–F17源码与对应隔离回归完成，详见 `docs-dev/remediation-plan-2026-10-09.md`、`docs-dev/remediation-results-2026-10-09.md` 和四份模块evidence；TODO区分代码/自动化与平台验收。P02原生资源作用域已优化；P01优先级对照测量仍待办，没有修改HIGH_PRIORITY_CLASS。
- 最终Flutter带行/分支coverage全量457 PASS/0 FAIL/0 SKIP；Core75项、with_gvisor75项、目标race38项，Agent83项、Helper37项均PASS。proxy故障/UTF-8、tray原生8组/200次USER 1→1、包装工具与68项strict包装检查PASS；Android arm64 c-shared及Darwin arm64仅编译通过。
- 修改且有LCOV记录的Dart行覆盖535/706（75.78%）、分支182/291（62.54%），两个窗口/lifecycle manager未载入LCOV；Core语句40.5%。平台入口与真实系统验收缺口见汇总。Dart analyze保留1条未修改文件warning，Agent clippy保留2条既有诊断，未弱化规则。
- 独立复核发现的事务取消、WebSocket退休、首次配置失败清理、测速history、Android迟返、Profile快照、ZIP预检及组件来源问题已逐一处理。真实Windows/SCM/TUN/IDN/长时资源及Android设备验收仍NOT RUN，交由用户或隔离环境完成。
- 本地修复提交 `7d0a00777342ab4503e2ae20d4f4435742538d60`；从精确Git archive完整重编Core/Agent/Helper/UI/原生插件，Windows Release与73文件ZIP roundtrip PASS。普通未签名包 `dist/FreedomCloud-windows-amd64-resourcefix-7d0a00777342.zip`，152,946,986 bytes，SHA256 `f0aae7982964e9e29c22022b76fb8f8996f8d2507f0db77aaa2964bcc78fea40`。聊天outputs有同hash副本，旧包保留；构建及组件证据见 `docs-dev/evidence/remediation-build-2026-10-09.md`。候选客户端未启动。
- 最终独立产物审查PASS：ZIP/bundle73文件、72项内部校验、32项组件描述、14插件/111输入、Helper实际Core绑定、UI编译定义及CORE-PATCH一致；预置输入和普通未签名/运行NOT RUN声明准确，无夹带用户配置或凭据。EnableLoopback为既有x86工具，其余29个PE为x64。交付文档后续提交，不改变包对应的7d0a007源码。

## 外部程序员报告复核与 TODO 补充（2026-10-09）

- 按用户要求在 `development@3227a863f5bdbb4ca7dc1f8caa5b7708d1f104dc` 核验外部六项主张，详细结论见 `docs-dev/evidence/external-review-verification-2026-10-09.md`。产品源码与原审查基线相同，本次仍仅调查/文档，不实施修复。
- F11 补充 Unicode 排除域名错误编码；新增 F16 托盘菜单全桌面查找缺少所有权且主题监视启动过晚、F17 PNG 编码异常遗漏 ui.Image 显式释放。DC 跨异步持有确认但有 Win32 finally 与串行提取，作为 P02 优化候选；HIGH 优先级保留 P01，未采纳“已证明 P0/Explorer 崩溃根因”的推断。
- 对 F06 补充 2 分钟 timeout 请求的滞留；对 F09 补充后台 Timer 清单及边界：Core 只发送新增请求，组刷新依赖 post-frame，detach/会话退出已有 setUiActive(false)，不能把正常托盘状态观察全部停掉。
- Unicode C++ 隔离表达式 probe：4 项中 2 PASS / 2 目标 FAIL / 0 SKIP，exit 1；使用真实 Flutter EncodableValue 和严格 UTF-8 对照，未更改代理/注册表。菜单和图像失败路径为源码/契约确认，动态跨程序/PNG 故障验收未运行。原覆盖率/QA 草稿和历史报告保留；本轮无推送、发布或服务/系统设置变更。
- 文档完整性检查 PASS：17 项均为 OPEN、原 15 项保留，9 个辅助章节/8 个本地链接/27 个源码路径及 probe 附录一致性通过；历史快照和产品源码未改。独立只读复核无阻塞，`git diff --check` 通过。本轮交付仅四份文档，所有产品修复/性能与真实系统验收仍按 TODO 跟踪。

## 性能、资源生命周期与可靠性审查待办（2026-10-09）

- 用户要求将本轮发现完整登记到 `docs-dev`；清单见 `docs-dev/performance-resource-todo-2026-10-09.md`，原始报告快照见 `docs-dev/evidence/performance-resource-audit-2026-10-09.md`。源码基线为 `development@c5c5ae4400d225cf2abefccb92184d29c1b81bcd`，本次仅文档整理，未实施其中的产品修复。
- F01–F15 覆盖外控认证、ZIP 路径边界、IPC 阻塞、Helper 停止失败、无效配置覆盖运行态、RPC 滞留、两类轮询竞态、后台取样、测速排队、Windows 代理失败路径、日志滚动、认证前连接、日志读取及 Android JNI 回收。另列 P01 优先级测量、V01–V05 长期/系统验收，以及 H01 托盘历史修复与 S01 开始菜单恢复边界，均保留独立状态。
- 历史隔离验证：Flutter 0 PASS / 4 目标 FAIL / 0 SKIP，表示四项缺陷复现；Go 两个观察性测试各 1 PASS、一个纯解析探针 exit 0，证明所述机制，不表示产品已修。Green、完整回归、发布构建、覆盖率、长时 profile、原生故障注入和 Android 实机验收均未因此完成。
- 本轮不更改客户端/代理/TUN/服务/Windows Shell，原有 coverage/QA 草稿保留；没有推送或发布。后续按清单逐项补修复提交、目标/回归测试及平台验收证据，不把记录 TODO 视为修复完成。

## Windows 托盘菜单泄漏与任务栏异常（2026-10-08–09）

- 用户先要求只读系统日志/源码分析，再授权修复并打包。基线为唯一 `development@6ce68d86e855573c1d1e42cdaf4af3073b58005b`；开工 fetch 自有远端后无 ahead/behind、无开放 PR。保留旧预览与原 coverage/QA 草稿；本轮未授权推送、发布或当前工作站客户端/网络切换。
- 确认旧运行 UI 的 USER 对象达到 10000，系统 Win32k 桌面堆失败与 Explorer 连续退出。托盘插件 `RemoveMenu` 脱挂旧子树但未销毁，TUN 3 秒观察又无条件重建菜单；这是已确认的客户端资源缺陷，当前 Explorer 故障的完整退出/替换对照仍未执行。
- 修复使用仓库内 tray_manager：整树所有权/失败回滚/展示期间延迟替换、popup 选中 ID 与已显示菜单快照、shared lifetime 保护 owner 销毁、图标注册失败与恢复。主包仅显示状态变化触发刷新，更新等待真实完成并串行合并；保留 tooltip、force 图标重建和非 Windows legacy 回调。
- 最终全量 Flutter 388 PASS / 0 FAIL / 0 SKIP；主包修改可执行行 36/39，Native 8 组 PASS，真实 Win32 200 次多层替换及 owner dispose/reset USER 1 → 1，生产插件警告视为错误编译 PASS。定向 analyze 0 error/warning，85 个既有 info（原始 exit 1）；独立源码复审无剩余已知中/高风险。详见 `engineering/testing/tray-menu-resources-2026-10-08.md`。
- 从修复的精确本地提交归档准备新 Windows amd64 普通免安装包，完整重编 runner/全部插件/UI；未改 Core/Agent/Helper 逐 hash 复用 `b2cccee7303d` 来源并记录兼容证据，不复用旧托盘 DLL。实际构建提交、ZIP/hash 与核验结果在交付后追加；所有旧包保留。
- 真实应用、鼠标 popup、当前 Explorer 恢复、Shell 故障/恢复、长时 USER/GDI、TUN/UAC/服务/流量验收 NOT RUN。本轮未运行候选客户端，不把本地测试和构建声明为本机任务栏已恢复。尚未推送、未合并、未发布。
- 本地修复提交为 `71a07a9d7ad0502d4a3eef1527e499460542b026`，精确 Git archive 源构建完成 Windows runner/全部插件/UI 重编；新托盘 DLL SHA256 `39625c5e0630fd718bdfcafa4f7574bc3715835b4d9f9999fac16656c21db428`，包含 DestroyMenu，与旧 DLL 不同。Core/Agent/Helper byte-identical 复用来源和 Core define/Helper 内嵌绑定均核验。
- 新包 `FreedomCloud-windows-amd64-trayfix-71a07a9d7ad0.zip`，152,755,710 字节，SHA256 `11dc19f930ebbe90e266bdd3d39611e8cdb9bd8ecb7c4f32d3ac3f75e7a2302d`；73 文件完整 ZIP/解压/交付核验 PASS。构建准备/包装元数据错误已在包装工具修复，完整原生 build 成功后只在新目录副本重封装，原失败记录保留。交付在本次聊天 outputs，dist 同名副本不覆盖旧包；后续证据文档不改变该包源码来源。
- 独立只读产物审查 PASS：ZIP/bundle 全文件、31 项组件元数据、commit/tree、菜单释放导入、后端固定来源及 Helper/Core hash 绑定一致；清单无用户配置或凭据，普通未签名和实机 NOT RUN 边界准确，未发现打包阻塞问题。

## 非管理员启动 UAC 后仍无法开启 TUN（2026-10-07）

- 用户实测（预览包 `136546fd19c4`，非管理员启动）：自动开启失败；手动点 TUN 弹出 UAC 并同意，仍失败。应用日志：`windows runas ... resultCode:42`（提权进程已启动）后 `helper install/repair timed out`；`%ProgramData%\FlClashX\logs\helper-install.log` 自 2026-09-16 后无任何新记录，Helper 服务 PID 未变化 → 提权修复命令一条都未执行。
- 根因（已复现）：cmd 中 `if not exist X mkdir X & 其余…` 把整条 `&` 链都当作 IF 主体；日志目录（或服务目录）存在后，整段修复（停服务/复制/配置/启动）被静默跳过。用相同命令、临时路径和不存在的服务名非提权重放：目录不存在时正常执行，预先建好目录时不产生任何输出。
- 修复提交 `68716be`：两处 IF 加括号；停服务改为同步 `net stop`，再替换二进制；服务 SDDL 给 SY/BA 完整权限（旧值缺 DC/SD/WD/WO，09-16 日志中管理员 `sc config`/`sc sdset` 返回 5；IU 权限不变）；修复后健康等待从 4.5 s 增至 30 s。新增 Windows 用例真实执行该命令（假服务名、预建目录），对旧写法确认失败。
- 验证：专项 11 PASS；全量 Flutter 370 PASS / 0 FAIL；改动文件 analyze 0 error/warning（4 条既有 info）。真实 UAC → 服务修复 → TUN 开启 NOT RUN。已被旧 SDDL 锁定的现有服务：管理员仍无法 `sc config/sdset`（binPath 不变时不影响修复），需卸载重装或用 SYSTEM 修复，未处理。
- 用户授权后 `development` 推送 `af7ee28..5a41421`（正常快进，无强推）。GitHub Actions quality-gate run `37578112377`（head `5a41421`）全部 PASS：Core Go tests、Flutter tests、M3 package integrity checks、Windows Core and service tests。未建 PR，`main` 未变。
- 用户要求后产出新预览包 `dist/FreedomCloud-windows-amd64-preview-5a414210319a.zip`，59,112,074 字节，SHA256 `dba968033ef9b2469e6e82bc937e77eb1248ebf82730b9a3b935f51ed88a8a7a`，73 文件，ZIP 解压逐文件校验通过。构建方式为“仅 UI 重打包”：在 `5a41421` 干净 detached 快照用 `flutter assemble` 重编 `data/app.so`（SHA256 `3b8da58e45469653072ccce047df111670e8a7ec9c256ab05581c13c8c653c5a`）与 flutter_assets；Runner/插件/Core/Agent/Helper/运行库逐字节复用已校验的 `b2cccee7303d` 包（依据：`b2cccee..5a41421` 未改 windows/core/services/libclash/setup.dart/pubspec/assets/arb，复用前重验 hash；engine 文件一致）。旧包均保留未变。未在开发工作站启动；真实 UAC 提权修复服务及 TUN 开启等待隔离 VM 验收。构建脚本与日志保存在会话私有 scratch（`Build-UiRepackPreview.ps1`、`build-5a414210319a.log`）。

## Windows 缺陷修复批次（2026-10-07）

- 同一 `feature/tun-default-on` 分支，用户批准后修复 4 个确认问题，各自独立提交：`7b89ae2` 主窗口在运行时启动（UAC/后端交接）前显示；`b07e493` 自启动注册表写入 await 并记录失败；`cbcc5e0` HKCU Run 值给可执行路径加引号（已开启用户下次启动自动改写为带引号值，关闭时总是移除含旧值的条目）；`be46c97` 标题栏最大化图标跟随 Win+↑/贴靠。
- 疑似未改：安装后 `runascurrentuser` 提权启动、退出等待挂起的 UAC 队列、最大化尺寸被保存、`SetProcessDPIAware` 与清单重复/UI 高优先级。Go Core、Agent/Helper 本轮未审查。
- 三文件 analyze 0 error/warning（info 为既有或随代码移动）；真实窗口/注册表/UAC 行为 NOT RUN。未推送、未建 PR。
- 用户要求后，本地 `development` 从 `8089f66` 无冲突快进到 `136546fd19c404767ee3a1a140e807dbe311614f`（含 TUN 默认开启与本批修复），领先 `freedomcloud/development` 14 个提交；`feature/tun-default-on` 保留。未推送。
- 预览包 `dist/FreedomCloud-windows-amd64-preview-136546fd19c4.zip`，59,111,599 字节，SHA256 `b148337c83c4704250bbfa0273b976a6eec1115df7a04fd0739135a278656cf3`，73 文件，ZIP 解压逐文件校验通过。构建方式为“仅 UI 重打包”：在 `136546f` 干净 detached 快照用 `flutter assemble`（Flutter 3.47.4）重编 `data/app.so`（SHA256 `89b5506c528844ac7e5776d4bd692a1050df55dc89cc783f092e2d63df94e4a2`）与 flutter_assets；Runner/插件/Core/Agent/Helper/运行库逐字节复用已校验的 `b2cccee7303d` 包。依据：`b2cccee..136546f` 未改 windows/core/services/libclash/setup.dart/pubspec/assets/arb；复用前重验旧包 72 项 hash；assemble 生成的 flutter_windows.dll、icudtl.dat 与复用件一致；与旧包相比仅 app.so、NOTICES.Z 及 4 个元数据文件不同。ZIP 采用 Optimal 压缩，体积小于旧包不代表内容缺失。旧包 SHA256 `a04fa740…c6bb97b` 未变。未在工作站启动；TD01–TD06、B1/B3 系统验收 NOT RUN。构建脚本与日志保存在会话私有 scratch（`Build-UiRepackPreview.ps1`、`build-136546fd19c4.log`）。
- 用户授权后 `development` 正常推送 `2b587a8..9d6b406`（快进，无强推）。quality-gate run `37507619436`（head `9d6b406`）全部 PASS：Flutter tests、Core Go tests、Windows Core and service tests、M3 package integrity checks。未建 PR，`main` 未变；预览包仍为 `136546f` 源码（`136546f..9d6b406` 仅台账文档）。

## TUN 默认开启并尊重保存偏好（2026-10-07）

- 用户选择 A2/B2/C1：全新安装默认开启 TUN、保存的关闭不被覆盖；本任务在 `feature/tun-default-on`（自 `development@8089f66`）上进行，为用户授权的一次性分支例外；仅自动化验证。
- 源码提交 `b64e0d5`：保存 `tun.enable=false` 时 Windows 启动只启动/接管代理且不请求权限；`true`/无保存配置沿用 `b2cccee` 完整流程；启动结果与降级原因写日志。专项 24、全量 Flutter 366 PASS，0 FAIL；三文件 analyze 0 error/warning，info 不在改动行。
- 未改 Go/原生代码、未出新包；真实 UAC/网卡/流量/退出清理 TD01–TD06 NOT RUN。未推送、未建 PR。详见 `engineering/plans/tun-default-on-2026-10-07.md`。

## Windows 启动交互修正（2026-10-06）

- 用户明确要求完整启动软件即启动代理与虚拟网卡，替代上一批应用启动只读接管的产品策略。生产入口需完成一次完整流程，实际运行才显示开启；本会话手动关闭后，后台刷新、重连和恢复窗口不自动重开。`autoLaunch` 的 Windows 登录启动含义不变。
- 方案、任务与验收边界见 `engineering/plans/windows-startup-tun-2026-10-06.md`，本轮结果见 `engineering/testing/windows-startup-tun-2026-10-06.md`。旧 VM 清单 W01/W05 的启动预期仅适用于旧包；新候选按 WS01–WS08 及仍适用的原系统用例验收。
- 基线 `development@d2708be491c8002400a657b66bde93eda6a16ce3`，fetch 后领先远端 5 个本地提交、无落后、无开放 PR；最近 development CI 37430048151 对应旧基线 `2b587a8`，不是本轮通过证据。旧包 `f0b1b7eba271`、历史 worktree/stash 和 coverage/QA 原稿均保留。
- 本轮仅本地修复、测试、提交与独立新包；未授权远端推送、主线合并或部署。真实 Windows TUN/UAC/服务/网络验收仍等待获准隔离环境，不在开发工作站启动候选程序。
- 修复源码已本地提交为 `b2cccee7303d4d5e0f0a2d94d03fab367814bd6a`：Windows 一次完整启动、取消后明确重试、同步撤销旧开启意图、断线过期观测保护，以及 derived provider 延迟通知的配置去重。保留日志/代理组/provider 投影和旧购买功能。最终专项 27、全量 Flutter 365 PASS，均 0 FAIL/SKIP；定向分析 exit 0，0 error/warning，134 条 info 的源码对照和覆盖缺口详见报告。独立审查无剩余已知 Critical/High 代码问题；系统验收未完成。
- 新免安装包为 `dist/FreedomCloud-windows-amd64-preview-b2cccee7303d.zip`，152,707,659 字节，SHA256 `a04fa7408baa4a0fb8ce866ccc66189f06ca0b2594691b0828153cb38bd6c97b`。四组件从该干净源码重编、73 文件 ZIP/解压及交付副本 hash 检查通过；上一包未覆盖。构建仍使用已验证 CMake/Ninja 处理本机 VS 发现限制，阶段结果在本轮报告单列。
- 独立产物审查 PASS：四组件来源、Helper 实际内嵌 Core 绑定、全部 73 文件、清单覆盖、1,011 个有效模块文件及补丁输入均通过；未发现新的高风险产物问题。包未在工作站启动，不把包完整性或本地测试等同于 UAC/TUN/路由/Antigravity 实机验收。
- 新增源码 bundle 已 verify、独立 clone/检出精确 SHA、fsck 验证；SHA256 `0dfe6ac23aa4dd6a45c4a4788747f286d6736f854164d8d3ed0f750962af0fa0`。本轮原始 5 文件、autostash、旧包未变。代码、文档提交与包来源分别记录；未推送、未合并，WS01–WS08 仍待隔离环境验收。

## 内核与 TUN 可靠性批次（2026-10-06）

- 用户已授权在完善范围和任务后开发与测试。本批从 `development@2b587a80ad187995194608ffcd0f9f8cfa6695cd` 开始，沿用唯一开发入口。方案与依赖见 `engineering/plans/kernel-tun-reliability-2026-10-06.md`，测试矩阵、覆盖率及真实环境缺口见 `engineering/testing/kernel-tun-reliability-2026-10-06.md`。
- 固定 Mihomo `v1.19.32`（`88dcbf7f1614a67c3b36b848ee3592dfa92ada36`），保留原栈默认值与 uTLS 覆盖。带校验的最小生命周期补丁通过独立生成源和 overlay 加载，不改模块缓存、不追随 Alpha。构建入口和 CI 已接入；新云端检查尚未触发，不以开工基线 CI 作为新代码证据。
- UI 区分意图、实际状态和操作，Windows 的开启以真实 listener 与接口状态为依据；修复 IPC 假成功、后台授权、旧响应、只读挂接及退出/重连/迁移竞态。Agent/Helper 使用实际停止确认和 Core 会话归属；旧组件不满足合同则拒绝自动交接。微信、礼品卡兑换、账号订阅、匿名套餐和价格均保留。
- Core 最终 46 项含子用例 PASS，Windows race PASS，四个桌面平台 Core 编译及 Android arm64 c-shared 编译通过；Flutter 最终 342、Agent 64、Helper 29 PASS，均 0 FAIL / 0 SKIP。独立审查的问题已在最终源码关闭；既有 analyzer/clippy/format 问题与覆盖缺口在报告单列。
- 四个本地提交依次为 `1f750b1`（Core/构建）、`8bbdfc7`（Agent/Helper）、`b3f83bb`（Flutter）、`f0b1b7e`（范围/测试文档）。新 Windows 普通免安装包从 `f0b1b7eba271b2402a9a82809bec0ea53d9a3e8e` 干净源码完成四组件重编，`dist/FreedomCloud-windows-amd64-preview-f0b1b7eba271.zip` 为 152,707,168 字节，SHA256 `b45cf6f4f7a6e72499baedbb7e23893c694b4d9441d5ed79e966b99bdb41defb`。独立核对 73 文件完整 ZIP/解压/交付 hash、组件来源、Helper/Core 绑定和补丁 manifest 通过；旧包保留。后续证据文档提交不改变包来源。
- 真实 Windows TUN/UAC/服务交接/路由/Antigravity 流量均 NOT RUN；等待获准的隔离 Windows 环境。开发工作站服务和网络未更改。当前仅准备普通预览，不声称正式发行、严格 WFP 或全部应用流量已验收。
- 开工与新源码两份增量 bundle 已离线恢复/fsck 验证，原始 5 个 coverage/测试文件 hash 一致，旧包 `863298c7e3f4` SHA256 保持 `cae86090054186ed680e3467025f857badfca1a9f9670cfd6de9c98c4a0cafbd`。新源码 bundle SHA256 为 `d6c11db51cf451307cfae06190dfcceea548aa9fc53b4ae9626c40b685ac2b1f`，私有构建日志与测试证据一起保留。本批未推送、未创建/合并 PR、未改主线或远端保护。
- 下一步按 `engineering/testing/kernel-tun-vm-acceptance-2026-10-06.md` 执行 W01–W20。获取隔离环境后补真实运行证据，另经授权推送开发分支运行云端 CI；通过后再准备单一晋级 PR。不能从本地构建成功推导自动合并或正式发布。

## 唯一开发入口（2026-10-06）

- 用户要求收敛为一个日常开发分支和受保护的 `main`。今后日常只在 `development` 开发，默认工作目录为 `E:\CodeWorkstation\FlClashX`；旧任务分支和工作树只保留追溯，不继续写入。详细流程、门禁、任务与回退见 `engineering/plans/single-development-2026-10-06.md`。
- 本地 `main`、`development` 已从各自祖先无 force 快进到自有主线 `4738293ea90ca9b90afcc201a5c9a09b729a86ad`，当前检出 `development`。本地 `main` 已由跟踪上游 `origin/main` 改为跟踪自有 `freedomcloud/main`；开发分支跟踪并推向 `freedomcloud/development`。
- 日常小提交正常推送开发分支；按验收批次创建一个 `development → main` PR。普通 merge 后同步 `main` 回开发分支，避免 squash/rebase 长期分支造成重复提交和冲突。主线合并和正式发布分别按当次授权执行。
- 迁移前新建私有全 refs bundle，并完成 verify、离线 mirror 恢复和 fsck；5 份原稿逐项复制/hash 一致，原来源分支和 stash 未改动。95,620 个忽略文件及 5 个未跟踪文件与目标的 798 个跟踪文件没有同名或父子路径覆盖；实际切换使用 `--no-overwrite-ignore`。此前大备份和全部旧工作树保留，异地副本仍另行安排。
- 云端保护于 2026-10-06 07:28 UTC 配置并回读确认：开发分支只移除接收提交前的必需 CI 状态，正常推送后仍运行 CI；主线新增必需 PR、0 个必需审批，保留原有三项 CI、严格更新、讨论解决、管理员适用和禁止强推删除。其余保护字段逐项比较不变，API 前后快照保存在私有恢复目录；后续开工仍需核实最新设置。
- 本次 CI 改动仅为 quality-gate 增加 `push main`，已有测试命令与固定工具版本不变。该修改进入 `main` 前，旧主线仍不监听 push main；进入后才会产生最终主线提交检查。开发分支推送不触发现有正式发行；macOS 预览仍可手动触发，不默认增加每次提交的全平台构建。
- 本轮不合并新的主线 PR、不创建标签、不发布版本、不运行本机代理程序；此前 Windows/macOS 运行验收边界保持原记录。推送后以开发 HEAD 对应的实际 Actions 结果及本次最终报告为准，不能沿用上一批次 CI 作为新提交通过证明。

## 本轮主线集成进展

用户已接受先研究方案、规划任务，再执行主线集成和 Windows 普通预览；异地备份单独安排。执行方案见 `engineering/plans/mainline-windows-preview-2026-10-05.md`。以下是 2026-10-05 的新结果，后文保留首次整理时的来源与验证记录。

| 工作单元 | 最终 PR head | 新组合验证 | 主线合并 |
| --- | --- | --- | --- |
| PR #56 购买中心/匿名套餐 | `eeaf6b0468177313bb98709eb421c01757a97fb5` | quality-gate `37298035201` 三项成功 | `1efc29fe4aaeb29d849a4cd7be4b0728f66ca528` |
| PR #57 受保护启动/安装预检 | `5b2d8a9e88414327174e8bf241c86da89cc338f8`，正常合入 #56 后重验 | quality-gate `37307123153` 三项成功 | `6b6d1532e55b5c0717986a588f25c4ec86d1d34f` |
| PR #55 macOS 开发包 | `0ce398967a0299a0b5bcb97ab8cbc5aed1727bf9`，正常合入 #56/#57 后重验 | quality-gate `37307467535`；完整 macOS 构建 `37307460810` 均成功 | `14571208a15c732b11522da6607212d559ee2695` |
| PR #58 购买焦点与操作进度 | `694cec8f2bfe2f614067b325fbb4542ac1582d53` | [quality-gate 37310446707](https://github.com/Hao-Monster/FreedomCloud/actions/runs/37310446707)：Flutter 290 PASS、Core Go、M3 package checks 成功 | `863298c7e3f44e821eb6df5dedeb97f95d31d987` |

前三项均以普通 merge commit 合并，没有改写历史或删除源分支。主线 `1457120` 已验证包含三个原始 PR head，其 tree `5407871e914f5f326ed1316208566b4c4c38b838` 与最后受检组合 `0ce3989` 完全一致。当前工作流不监听 push main，不能把合并前检查称为自动发生的主线检查。

随后 [PR #58](https://github.com/Hao-Monster/FreedomCloud/pull/58) 也以普通 merge commit 合并。Windows 预览的功能源码基线为 `863298c7e3f44e821eb6df5dedeb97f95d31d987`，tree `18d658d6f785518012f5bfa6cab437582531948e` 与最终受检 head `694cec8` 一致；后续仅记录交付证据的文档提交不改变该包的构建来源。

组合 macOS 产物经过本地 SHA256、ZIP CRC、host/provider/helper 标识和 arm64 二进制核对，PASS：55,252,135 字节，SHA256 `c4e9c5fa88af8f29b1b4dcf252982db7dc898a61bf93c63434e6fb78ff7433d0`，来源严格为 `0ce3989`。它仍为 UNSIGNED，签名、公证、激活和真实设备运行 NOT RUN。

集成前另做增量保全：169 个 refs、4 个关键 HEAD/tree、唯一 stash 在独立 bundle mirror 中恢复一致，5 份原始未跟踪文件逐项 hash 一致。新增 bundle SHA256 `e2709fe9ee3bb10068abc99d50b8a8aee010f3427b78c964fe705055cca6cce4`；原有大归档、旧工作树和原稿保留。私有证据留在仓库外，未上传账号、卡号、订阅内容或原始日志。

四项合并后再做增量保全：新 bundle 235,929,439 字节，SHA256 `b82cd392fc98f5e4399c9cd392aaab4d628489621d9d62797771027633fb95e4`；`git bundle verify`、离线 `clone --mirror` 和 `git fsck --full --strict` 均 exit 0，172/172 refs 完整恢复，7 个关键提交的 tree 一致。原 HEAD、5 份原稿、stash 和两份旧 bundle 的哈希不变。临时 `refs/codex/turn-diffs` 数量变化已逐对象核对，不是用户分支或源码丢失。此快照对应源码整合完成时刻，不包含随后构建缓存；异地副本按用户决定另行安排。

本轮 Windows 预览前已修复 QA001 登录焦点和 QA003 操作进度文案：生产购买正文隔离侧栏焦点遍历，查询/兑换分别显示本操作进度，保留全局互斥和原消费逻辑。真实宿主/manager 回归在修复前为 6 PASS/6 FAIL；扩充后的最终目标测试 15 PASS，购买模块 181 PASS，均 0 FAIL/SKIP。变更 Dart 文件 `analyze --fatal-infos` 与 format 检查通过；测试边界和后续运行结果分开记录，不能把组件测试当 Windows 实机验收。

匿名目录于 2026-10-05 12:37:51 UTC 实际执行一次无 Authorization/Cookie 的 GET，HTTP 200、TLS 校验通过；同一响应经生产解析器离线验证成功。返回 1 个套餐、200 GiB，`onetime` 整数金额 15000 按客户端规则显示为 150.00；接口没有币种字段，不推断币种。此证据不代表 Windows 新包页面已验收。

Helper 重连调查见 `engineering/testing/helper-reattach-investigation-2026-10-05.md`：已确定调用链与状态缺口，但历史唯一触发入口未证实，也没有以恢复布尔值绕过信任检查。完整 Helper 修复和严格模式仍需要隔离环境；本机 UI 验收与新 native 全栈运行分别记录。存在自动订阅更新时，单纯打开新 UI 仍可能触发配置应用和授权；不能从“先连接旧 Agent”推断后台绝对不变。

Windows 普通免安装包已从上述 `863298c7` 干净源码完成重编，交付 `dist/FreedomCloud-windows-amd64-preview-863298c7e3f4.zip`，139,359,772 字节，SHA256 `cae86090054186ed680e3467025f857badfca1a9f9670cfd6de9c98c4a0cafbd`。72 文件完整解压及交付副本逐文件校验通过；未运行该包，原生验收仍为 NOT RUN。环境适配、失败历史、实际命令结果和受控测试条件见 `engineering/testing/windows-preview-build-2026-10-05.md`。

## 基线与保全

- 自有远端为 `Hao-Monster/FreedomCloud`（通常是 `freedomcloud`）；上游为 `pluralplay/FlClashX`（通常是 `origin`）。首次保全时的自有主线为 `cc1d31bc8b24b0103bc78dea2453768cb0c5a339`；后续集成结果见本文开头。
- 2026-10-05 首次保全时，本地 `main` 跟踪上游，旧 `development` 也落后于自有主线；当时保持原状。2026-10-06 的无 force 快进与唯一开发入口见本文开头，旧提交仍在新基线的祖先历史中。
- 原购买来源分支 `codex/m3-7-helper-diagnostics` 的提交保留；远端 `codex/purchase-source-snapshot-20261005` 另存其源历史。2026-10-05 的集成在独立工作树进行，之后的日常开发遵循本文开头的唯一开发入口。
- 初始 40 个工作树、全部本地 refs、stash 及 detached HEAD 已归入私有离线 bundle 和逐工作树快照。未提交文件保存精确副本、SHA256 及暂存/未暂存二进制补丁；忽略文件另行保存，不能只依靠 Git bundle。
- 恢复演练：16 个实际有未提交内容的工作树从独立 bundle 恢复后，文件 hash、Git 状态及暂存内容一致；23 个干净工作树 HEAD 已验证；1 个初始化异常另行保全。初次审计与备份时刻的 dirty 数量因生成文件的换行规范化而不同，不混为同一快照。
- 忽略文件归档已完成：164,527 个文件、42,850,666,804 字节逐文件 SHA256 核验通过，0 错误，复制期间未发现源文件变化。Windows 长路径复制的首次失败已通过续传和重新核验解决。另复核了原快照的 137 个现有变更文件，原位置内容仍与整理前一致。
- `locked initializing` 工作树缺 index、仅有 `.git`，694 个缺失文件不视为有意删除。其 `9ca5644` HEAD 已从离线 bundle 在隔离目录成功检出 694 个跟踪文件，状态干净；原异常目录保持不动，未提交这些删除状态。
- 所有原工作树、旧预览包和唯一 autostash 仍保留。忽略文件的最终完整性、私有路径和恢复步骤以仓库外备份清单为准；不将原始日志、凭据或测试账户状态推到公开仓库。
- 私有快照当前只在本机，远端分支保存经审查的源码。它不是操作系统、证书库或异地灾备，不以“已备份”推导可以删除原稿。

## 来源与集成映射

| 工作单元 | 原始来源 | 整合提交或分支 | 远端追踪 |
| --- | --- | --- | --- |
| 原生礼品卡购买中心 | `43ed4e2` | `ac58869`，`codex/purchase-integration-20261005` | [PR #56](https://github.com/Hao-Monster/FreedomCloud/pull/56) |
| MSVC/Ninja 警告参数修复 | `622abe1`；便携包分支 `f8c2d6a` 为相同 patch-id | `c463c32`，只吸收一次 | PR #56 |
| 未登录套餐与价格展示 | `7d02a94` | `33a8de2` | PR #56 |
| 项目协作规则 | `04be72f` | `cafb7a7` | PR #56 |
| 非 macOS 旧工作树归属审计 | 逐文件与历史提交核查 | `e9057cc` | PR #56 |
| Windows 受保护 Agent 启动和严格模式测试初始化原稿 | `FlClashX-test-portable-20261002` 的 4 个未提交文件 | `eac3938` 运行时、`780b31c` 安装预检，分支 `codex/protected-launch-20261005` | [PR #57](https://github.com/Hao-Monster/FreedomCloud/pull/57) |
| macOS 构建与完整开发包 | PR #55 原 head `7cce2da` | `ddc6965` 正常合并主线，`82ac8a4` 修复 helper，`4de17bd` 修复测试路径别名，`62d53a7` 拆分嵌入文件引用以匹配当前配置 | [PR #55](https://github.com/Hao-Monster/FreedomCloud/pull/55) |

购买、Windows 启动/测试安装、macOS 打包分为独立 PR；首次整理时未合并，随后经用户接受执行方案后按本文开头的顺序集成。每次合并都检查最终 head 的 CI、冲突和剩余验收范围。禁止从旧预览工作树整文件覆盖当前主线。

## 旧稿归属结论

- 非 macOS 34 个不同文件与 2 份补丁草稿，均已吸收、被主线改进替代或属于无效草稿，未发现应重复移植的独有有效功能。逐项证据见 PR #56 的 `engineering/reconciliation-audit-2026-10-05.md`。
- macOS 5 个旧工作树共 50 个文件条目：35 个与主线一致，15 个属于格式或主线后续修正；无需用旧文件回灌。详见 PR #55 的 `engineering/macos-reconciliation-2026-10-05.md`。
- autostash 共 18 项：15 项已精确吸收，3 项由后续主线改进替代。保留 stash，不 pop/drop。
- 构建链 `47438c1`、连接性能 `b77972f`、诊断隐私 `2a50b01`/`63c0d57` 虽仍显示本地独有提交，`git cherry -v freedomcloud/main` 均为 `-`，等价补丁已在主线，不能当作四项遗漏再次合入。
- `m3-2-zip-v4` 的独有草稿在 ZIP entry 打开写入后设置时间戳，已在内存复现 IOException；主线在打开前设置正确。保留草稿备份，拒绝合入错误行为。
- 旧 UAC 提交 `f082792` 的等效防重复提示行为已被 `99df219`、`bbece1b`、`6eb440b` 吸收，不按提交 SHA 不同判断为遗漏。
- 主工作树原有覆盖率、原生 QA 报告和焦点探针保存在原目录及私有快照中；它们不是未经审查即可公开上传的生产代码。

## 实际验证与预览边界

| 工作单元 | 已有证据 | 未代表的能力 |
| --- | --- | --- |
| 购买集成 | 本地 Flutter 全量 261 PASS，0 FAIL/SKIP；目标 Dart analyze 无问题；3 个 M3 包工具/manifest/evidence 脚本 PASS；`e9057cc` 对应 [CI 37293130664](https://github.com/Hao-Monster/FreedomCloud/actions/runs/37293130664) 的 Flutter、Go、package 三项 PASS | 不代表已在最终集成 SHA 重新做本机完整业务验收、签名发行或后端部署 |
| Windows 受保护启动/测试安装 | 23 项 Dart 测试、68 项只读安装预检用例和 3 个既有包工具脚本 PASS；路径异常 mutation 按预期失败，恢复后回归 PASS；两项审查缺口均已关闭；`780b31c` 对应 [CI 37295298644](https://github.com/Hao-Monster/FreedomCloud/actions/runs/37295298644) 三项 PASS | 本机未运行安装器、修改服务、安装驱动或切换网络；需要隔离 VM 验收 |
| macOS 开发包 | 本地 19 项 helper/工程合同测试和两份上游 ZIP SHA256 核验 PASS；`62d53a7` 的 [质量门禁 37296920008](https://github.com/Hao-Monster/FreedomCloud/actions/runs/37296920008) 三项 PASS；[完整构建 37296914010](https://github.com/Hao-Monster/FreedomCloud/actions/runs/37296914010) 的 Xcode、归档及上传均 SUCCESS | 命令行覆盖曾未解决旧产品引用问题，已移除并保留失败记录；当前产物明确为 unsigned arm64 开发包，不等同于 Apple 签名、公证、激活或真实设备验收 |

本机 Flutter 3.47.4 / Dart 3.13.3；CI 使用仓库固定 Flutter 3.41.7。Windows 相关新 Dart 文件 analyze 无问题；包含既有 `service.dart` 时有 13 项原有提示（1 warning、12 info，exit 2），与独立检查的主线基线相同，没有以修改规则消除这些提示。安装器验证使用 PowerShell 7.6.5 和临时文件/签名替身，不能代替真实 Authenticode、服务或驱动验收。

2026-10-04 的原生测试结果对应原来源与当时包，不回写成当前集成分支的运行证明。本次没有消费新的礼品卡。

仍需单独追踪：此前原生测试发现的 Helper 修复/UAC 问题；Windows 严格模式 VM、真实流量及签名验收；macOS Apple 签名、公证、受管激活和设备流量。未签名 macOS 开发包只能如实标记 unsigned，不要求用户关闭系统安全。

## 后续开发顺序

1. 读取项目 `AGENTS.md`，核实 `development` 本地/远端进度、未提交内容及自有 `main`；在唯一开发分支继续任务，不为独立任务默认新建分支或工作树。
2. 一次推进一个可测试增量；小范围相关门禁通过即可提供标明来源和缺口的部分预览，不把全平台正式发布门禁强加给每次 UI 迭代。
3. 对需共享的代码及时形成可审查提交并经授权推送 `development`；CI 和预览达到批次验收标准后，再创建一个晋级 PR。更新本台账，记录源提交、实际检查、预览 hash 和未验收项。
4. 主线合并、正式发布和历史清理分别按授权执行。保全完成不是自动删除旧分支、工作树或 stash 的授权。

## 套餐卡片富文本增量（2026-10-11至2026-10-12）

- 用户要求先核实“后台写什么、客户端展示什么”，不足直接开发；本轮起点development@c2fe8c5，fetch自有远端后领先10/落后0。原稿与QA资料保留，未改分支、stash、旧工作树或已有预览包。
- 已确认70c4643包含主要套餐字段和完整Markdown卡片；当前公开套餐正文163字符、三段说明、无图片。此次只补链接内部样式、下划线行内/代码/转义语义、代码块影响列表缩进，以及受限HTTPS图片，不改API、模型、套餐字段、价格、兑换、账户或其他页面。
- 新图片组件保留代理路由与TLS验证，不携带账号凭据，不跟随重定向；单图下载4MiB、取得槽位后15秒、解码最长2048px、共享4路并发和16MP目标栅格预算。失败/不安全/不支持资源保留alt，任意HTML不执行；动画仅首帧。
- 先冻结C1-C8矩阵；4条富文本缺陷和2条图片资源缺陷均有真实Red→Green。最终目标58 PASS、全Flutter **591 PASS/0 FAIL/0 SKIP**（97.33秒），定向analyze无问题，Windows目标debug UI资源编译exit0；本次diff行290/293、分支104/111。四种真实组件截图已查看，仍是合成内容而非当前客户端实机。
- 源码、测试与本节随本次development本地提交保存；详细命令、覆盖率、边界和审查在`engineering/testing/plan-card-rich-content-2026-10-11.md`。未推送、未PR/合并、未打新可执行包、未部署，旧CI不冒充本提交结果。
- NOT RUN：完整客户端/真实图片/TLS设备与兑换、原生解码中故障注入、Core/Agent/Helper和各平台实机。没有启动候选应用、改代理/TUN或消费卡码；如需让运行中的客户端包含新展示，应另从精确提交构建预览并遵守启动环境授权。

# 仅兑换码购买页：测试任务与验收记录 v2

日期：2026-10-11（用例编制）/ 2026-10-25（执行完成）。替代余额结算 v1 矩阵；无新增支付、余额、报价或在线下单测试要求。

依据：[方案v2](../plans/purchase-redemption-2026-10-11.md)。

## 1. 场景验收结果（R01–R12）

| ID | 场景 | 必须验证的结果 | 状态 | 对应验证文件 |
| --- | --- | --- | --- | --- |
| R01 | 未登录浏览套餐，目录加载失败/重试 | 公开资料完整且不携带凭据；不影响登录/兑换状态；界面与新建配置标签不暴露 `Xboard` | PASS | `plan_catalog_api_test.dart`、`plan_catalog_host_test.dart`、`purchase_v2_ux_test.dart` |
| R02 | 没有码，查看套餐后获取兑换码 | 卡片“获取此套餐兑换码”拉起渠道抽屉、一键复制带套餐名咨询话术；两个微信复制与既有商店入口可用；不调用兑换或普通订单接口 | PASS | `plan_catalog_widgets_test.dart`、`purchase_v2_ux_test.dart` |
| R03 | 已有码，不先选套餐直接查码 | 桌面首屏右侧工作台直接可达（含6套餐目录不滚屏）；智能粘贴清洗兑换码；复用登录并只查码不消费 | PASS | `purchase_interaction_test.dart`、`purchase_v2_ux_test.dart` |
| R04 | 浏览A套餐后输入B套餐码 | 先打开A套餐购码抽屉再查B套餐码，确认区严格显示B套餐快照与变更对比，用户确认前 `redeem` 调用 `0` 次 | PASS | `purchase_v2_ux_test.dart` |
| R05 | 有效码确认、连续点击；编辑码/迟回预览 | 明确确认仅发一次兑换；编辑或清空码使旧预览立即失效，迟回响应不恢复旧确认 | PASS | `purchase_manager_test.dart`、`purchase_interaction_test.dart` |
| R06 | 无效/过期/已用/不适用码 | 清楚显示失败原因且确认按钮禁用；无余额或补差入口 | PASS | `purchase_widgets_test.dart`、`purchase_manager_test.dart` |
| R07 | type4新购、周期续费、按量续费、不同套餐/模式 | 展示服务端快照、`兑换前 → 兑换后` 额度/有效期对比及新开通/续费徽标，保留既有资格规则 | PASS | `xboard_api_test.dart`、`purchase_widgets_test.dart`、`purchase_v2_ux_test.dart` |
| R08 | 兑换成功，同步失败后重试 | 成功回执置顶保留并支持一键跳转配置页；同步失败仅重试订阅同步，不重复消费兑换码 | PASS | `purchase_manager_test.dart`、`purchase_widgets_test.dart`、`purchase_v2_ux_test.dart` |
| R09 | 兑换结果不明、重启、已用type4码恢复 | 原账号/原码锁定输入并通过历史与幂等契约恢复；不要求重新 `check` 成功 | PASS | `purchase_manager_test.dart`、`purchase_storage_test.dart`、`purchase_interaction_test.dart` |
| R10 | 会话过期、切号、安全存储失败 | 原账号待恢复记录隔离；安全存储失败不消费兑换码；凭据与完整码不写入普通日志 | PASS | `purchase_storage_test.dart`、`purchase_interaction_test.dart`、`purchase_profile_sync_test.dart` |
| R11 | 记录折叠/展开、分页、旧卡type1–3 | 兑换记录默认收起并展示总数角标，按需展开显示脱敏码与分页；保留 `type1–3` 真实奖励文案 | PASS | `purchase_widgets_test.dart`、`purchase_v2_ux_test.dart` |
| R12 | 浅/深色、窄窗、桌面、2x文字、键盘、各加载状态 | 桌面双栏消除单套餐半屏黑洞，窄窗提供“直达核销”锚点，`320x800 @ 2.0x` 无溢出；辅助图标按钮跳过 `Tab` 焦点陷阱 | PASS | `plan_catalog_details_test.dart`、`purchase_interaction_test.dart`、`purchase_v2_ux_test.dart` |

## 2. 工具链与执行记录

- 本机工具版本：`Flutter 3.47.4`（channel stable）/ `Dart 3.13.3`（Windows 10.0.26200）；注：`.github/workflows/quality-gate.yaml` 配置 `FLUTTER_VERSION: "3.41.7"`，已在本文与总台账披露差异。
- 基线源码：`development@591481f`。

1. **现有购买模块基线（D1 前置）**
   - 命令：`& E:\flutter\bin\flutter.bat test --no-pub test/purchase --reporter compact`
   - 结果：**PASS**（退出码 `0`，`296 PASS / 0 FAIL / 0 SKIP`）。
2. **新 UI/UE 目标用例有效 Red（D1）**
   - 命令：`& E:\flutter\bin\flutter.bat test --no-pub test/purchase/purchase_v2_ux_test.dart test/purchase/purchase_widgets_test.dart test/purchase/purchase_interaction_test.dart --reporter expanded`
   - 结果：**有效 Red**（退出码 `1`，`24 PASS / 10 FAIL`，捕获 `Xboard` 文案残留、6 套餐下 `purchase-check` 被挤至 `y=1441 > 900`、缺失卡片获码抽屉/默认折叠记录/窄窗直达锚点等预期失败）。
3. **购买模块全量回归与目标验收（D4）**
   - 命令：`& E:\flutter\bin\flutter.bat test --no-pub test/purchase --reporter expanded`
   - 结果：**PASS**（退出码 `0`，`302 PASS / 0 FAIL / 0 SKIP`）。
4. **静态检查（D5）**
   - 命令：`& E:\flutter\bin\dart.bat analyze lib/views/purchase lib/services/purchase_profile_sync.dart lib/l10n test/purchase`
   - 结果：**PASS**（退出码 `0`，`No issues found!` — `0 error / 0 warning / 0 info`）。
5. **全仓 Flutter 回归测试（D5）**
   - 命令：`& E:\flutter\bin\flutter.bat test --no-pub -j 4 --reporter compact`
   - 结果：**PASS**（退出码 `0`，`968 PASS / 0 FAIL / 0 SKIP`）。
6. **离线真实 Widget 合成数据渲染与视觉复核（D5）**
   - 命令：`& E:\flutter\bin\flutter.bat test --no-pub test/purchase/purchase_render_test.dart test/purchase/plan_catalog_render_test.dart --reporter expanded`
   - 产物路径：`build/purchase-preview/flagship-us-single.png`、`login.png`、`redemption-preview.png`、`success-sync-failed.png`、`narrow-login.png`、`narrow-preview.png`（及对应 `*-support.png`）与 `build/plan-card-rich-content-preview/catalog-light.png`、`catalog-dark.png`、`catalog-narrow.png`、`catalog-large-text.png`。
   - 视觉审查修正：首轮截图巡检发现混排中英文标签绑定 `JetBrainsMono` 时缺少中文字体回退链导致中文字符显示为 `.notdef` 方框，已在 `plan_catalog.dart` 与 `center.dart` 补齐 `_cjkMonoFallback` 回退链并二次生成 PNG 逐图人工核验通过。
7. **Code Review 七项问题（`CR-01`–`CR-07`）修复与回归验证**
   - 范围：针对 `development@cb68fb9` 独立审查识别的 7 项问题实施修复：
     - `CR-01`（P1）：新增块级结构感知摘要 `summarizePlanMarkdown`，跳过前导空行并保持 GFM 表格表头/分隔行/数据行、围栏代码块 ```` ``` ```` 及 `<u>...</u>` 完整闭合；
     - `CR-02`（P1）：新增 `extractRedemptionCodeFromClipboard`，剥离 URL 端口与时间戳冒号干扰，优先提取显式标签卡密，并移除 `substring(0, 32)` 与 `maxLength: 32` 静默截断，保留超长无效串交由本地 `gift_code_format` 拦截；
     - `CR-03`（P2）：抽离响应式 `_AcquirePlanSheet`，修正微信按钮文案为 `l.copy`（“复制”），使用弹窗内联反馈条替代被遮罩遮挡的底层 `SnackBar`，支持 `cardStoreUrl` 动态响应；
     - `CR-04`（P2）：新增 `resolvePlanRegionBadge`，按出现顺序渲染双国旗（如“日本/新加坡” → `🇯🇵 🇸🇬`）、全球/三国及以上渲染 `🌐`，剔除 `MY`/`IN` 等英文营销词误判；
     - `CR-05`（P2）：修复混合计费套餐目录筛选胶囊显隐、`ValueListenableBuilder` 实时联动纯空格清空按钮，以及 `logout` 失败时不提前清空输入与折叠历史；
     - `CR-06`（P3）：恢复窄窗 `purchase-jump-workbench` 与兑换码粘贴/清空按钮的键盘 `Tab` 可达性（仅保留密码显隐按钮跳过 `Tab`），并通过外层 `MergeSemantics` 注入手风琴 `button` + `expanded` 无障碍语义；
     - `CR-07`（P3）：统一执行 `dart format` 清零缩进偏差。
   - 前置 Red 验证：`test/purchase/purchase_v2_ux_test.dart` 新增 `CR-01`–`CR-06` 6 组回归用例，在旧实现上全部命中预期失败（`6 PASS / 6 FAIL`，退出码 `1`）。
   - 修复后验证：
     - `dart format --set-exit-if-changed`：**PASS**（0 差异）；
     - `dart analyze`：**PASS**（`No issues found!`）；
     - `flutter test --no-pub test/purchase`：**PASS**（`308 PASS / 0 FAIL`）；
     - 全仓 `flutter test --no-pub -j 4`：**PASS**（`974 PASS / 0 FAIL`）；
     - 离线 PNG 快照二次核验：`build/purchase-preview/login.png`、`redemption-preview.png`、`narrow-login.png` 已目视确认双国旗 `🇯🇵 🇸🇬` 顺序正确且去掉 `maxLength` 字符计数噪声。
8. **二轮深度 Code Review 六项问题（`CR2-01`–`CR2-06`）修复与回归验证**
   - 范围：针对 `development` 上购买改版及首轮修复范围（`cb68fb9..0631995`）开展高级工程二轮审查并完成修复：
     - `CR2-01`（P1）：加固 `extractRedemptionCodeFromClipboard`（剥离 ASCII URL、邮箱地址、`YYYY-MM-DD` 日期与时间戳，补齐英文标签前向词边界防 `status_code: 200` 误命中，支持反引号/方括号/引号包裹卡密，收紧无标签词边界防 `wxid_abc123456` 误提取）与 `PurchaseManager.setCode`（统一剥离空白与横线分隔符并转大写，消除键盘 `Ctrl+V` 粘贴带连字符卡密触发 `gift_code_format` 的割裂，同时保留非法符号与超长串交由本地校验拦截）；
     - `CR2-02`（P1）：新增 `_UpperCaseCodeFormatter` 与 `_updatingCodeFromInput` 输入重入守卫，修复桌面物理键盘在字符串中间键入小写字母时触发光标强制跳尾及打断中文/日文 IME 组合态（`composing`）的问题；
     - `CR2-03`（P2）：修正 `summarizePlanMarkdown` 开围栏识别遵循 CommonMark §4.5（反引号围栏 info string 不含反引号，防止行首行内代码 ```` ```VIP2026``` ```` 吞噬全文）、补齐 ATX 标题与分割线边界、`innerLines` 真实行数预算，并通过块内同构扫描 `_closeTruncatedUnderlines` 忽略转义与反引号代码跨度，消除 `` `<u>` `` 误补字面 `</u>`；
     - `CR2-04`（P2）：在 `resolvePlanRegionBadge` 补齐繁体 `'中國香港'`/`'中國澳門'`、英文命中掩码（防 `'North Korea'` 二次命中 `KR`）、剔除大写冲突词 `MO`/`CAN`/`ARE`，并区分显式全域覆盖词（`全球`/`多国`/`全节点`/`Worldwide` → `🌐`）与普通 `Global` 前缀（`'Global Pro · 日本/新加坡'` → `🇯🇵 🇸🇬`）；
     - `CR2-05`（P2）：登出、401 会话过期及组件切换 `manager` 时自动重置 `_obscurePassword = true` 并清空残留输入，同时抽离 `_receiptCard` 使 401 保全回执完整保留模板名称、奖励明细与订单号；
     - `CR2-06`（P3）：为 `catalogPane` 绑定 `_catalogAnchor = GlobalKey()` 保证跨 `860px` 单双栏断点缩放不丢失筛选与展开态，并在 `_AcquirePlanSheet` 补齐 `channelError` 降级提示与桌面显式关闭按钮 `purchase-acquire-close`。
   - 前置 Red 验证：`test/purchase/purchase_manager_test.dart` 与 `test/purchase/purchase_v2_ux_test.dart` 新增 7 组 `CR2-*` 回归用例，在旧实现上全部命中预期失败（`31 PASS / 7 FAIL`，退出码 `1`）。
   - 修复后验证：
     - `dart format --set-exit-if-changed`：**PASS**（0 差异）；
     - `dart analyze`：**PASS**（`No issues found!` — `0 error / 0 warning / 0 info`）；
     - `flutter test --no-pub test/purchase`：**PASS**（`315 PASS / 0 FAIL`）；
     - 全仓 `flutter test --no-pub -j 4`：**PASS**（`981 PASS / 0 FAIL`）；
     - 离线 PNG 快照复核：`build/purchase-preview/login.png`、`redemption-preview.png`、`success-sync-failed.png` 目视确认国旗徽章、双栏排版与抽离后的 `_receiptCard` 渲染无回退。

## 3. 未运行项与边界说明（NOT RUN）

- **真实 Windows 客户端窗口启动与交互**：**NOT RUN**（按 `AGENTS.md` 规定，完整启动候选客户端会自动触发代理/TUN 接管副作用，未经专门环境授权不在开发工作站直接运行候选二进制）。
- **Windows 系统凭据库（Credential Manager）实机集成**：**NOT RUN**（单测通过抽象/桩存储验证隔离与容错，未读写本机真实账户凭据）。
- **远端 GitHub Actions CI（`quality-gate`）**：**NOT RUN**（仅完成本地验证与本地提交，尚未推送远端）。
- **服务端线上真实发卡、兑换消费与订阅拉取**：**NOT RUN**（全程使用合成账号与合成兑换码，零真实库存消耗、零后端改动或部署）。

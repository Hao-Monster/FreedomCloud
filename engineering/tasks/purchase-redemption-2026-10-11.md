# 仅兑换码购买页：开发任务 v2

日期：2026-10-11（任务编制）/ 2026-10-25（实施与验证完成）。替代余额结算 v1 任务；不再要求后端购买接口、防重表、钱包或在线订单开发。

依据：[方案v2](../plans/purchase-redemption-2026-10-11.md)；验证：[测试任务](../testing/purchase-redemption-2026-10-11.md)。

| 顺序 | 开发任务 | 完成条件 | 状态 |
| --- | --- | --- | --- |
| D1 | 固定仅兑码验收用例，先运行现有购买模块基线，再写本次UI目标用例 | 测试不得要求钱包、报价、普通订单或选支付方式；有效Red单独记录 | DONE |
| D2 | 整理购买页布局：套餐介绍、常见视口可达的兑换入口、渠道、折叠记录 | 匿名目录完整；无需先选套餐；两个微信复制与既有购码入口保留；其他页面不改 | DONE |
| D3 | 复用现有查码/确认/结果组件，完善套餐及权益摘要、账号提示和文案 | 实际套餐取自码预览；确认才兑换；新购/续费/不适用如实显示；不展示收银台概念 | DONE |
| D4 | 回归成功、同步失败、超时恢复、切号与旧卡兼容；补视觉和键盘用例 | 原恢复/安全存储/同步逻辑不回退；只重试失败阶段，不新增消费 | DONE |
| D5 | 执行测试、静态检查、离线真实Widget渲染和独立复核，更新台账 | 准确报告PASS/FAIL/NOT RUN；产品实现验证后单独本地提交，不推送或部署 | DONE |

实际改动范围：

- 文案与多语言生成：`arb/intl_en.arb`、`arb/intl_zh_CN.arb`、`arb/intl_ja.arb`、`arb/intl_ru.arb` 及生成的 `lib/l10n/l10n.dart`、`lib/l10n/intl/messages_*.dart`（清理登录引导中的 `Xboard` 后台技术名词，补充步骤引导、分类筛选、购码咨询话术、密码显隐、窄窗直达核销等 19 个本地化键）。
- 托管订阅新配置默认名称：`lib/services/purchase_profile_sync.dart` 将新建托管配置默认标签由 `'Xboard · ${account.email}'` 调整为 `'FreedomCloud · ${account.email}'`（保留 `xboard-$ownership` 配置 ID、`xboardAccountMarker` 与 `xboardTlsMarker` 安全标记不变，不影响既有配置归属复用）。
- 购买页与套餐目录组件：`lib/views/purchase/plan_catalog.dart`（Material 3 卡片层级、国家国旗 `Twemoji` 徽标、单套餐通栏 / 多套餐响应式双列网格、`全部 / 周期订阅 / 按量流量包` 筛选胶囊、等宽数字+中文字体回退配额与价格磁贴、规格胶囊、长说明渐进折叠与卡片级 `获取此套餐兑换码` 动作）与 `lib/views/purchase/center.dart`（桌面 `>=860*textScale` 左橱窗 + 右核销工作台双栏并排布局、窄窗单列 + 一键直达核销锚点、独立 `FocusTraversalGroup` 与跳过 `Tab` 陷阱的辅助按钮、账户流量进度条、支票级 `兑换前 → 兑换后` 权益确认卡、置顶成功回执与一键查看节点、默认收起的兑换记录手风琴、以及不产生订单的购码渠道底部抽屉）。
- 测试与离线渲染证据：新增 `test/purchase/purchase_v2_ux_test.dart`，同步更新 `test/purchase/purchase_widgets_test.dart`、`test/purchase/purchase_interaction_test.dart`、`test/purchase/purchase_render_test.dart`、`test/purchase/plan_catalog_render_test.dart`。

未触碰 `Xboard-Go` 后端、未新增第三方依赖或改动 `pubspec.lock`、未修改客户端其他页面或导航结构、未重写 `PurchaseManager` / `XboardApi` / `SecurePurchaseStorage` 状态机。

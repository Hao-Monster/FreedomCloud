# 购买页公开套餐展示

## 范围与验收

2026-10-04 增量：在现有原生购买页上方增加套餐名称、流量和各销售周期价格；未登录、恢复会话和已登录时均展示。微信购买、两个微信复制按钮、礼品卡商店、登录、账户、兑换码查询/兑换、历史与订阅同步全部保留。套餐区仅展示，不创建订单或调用支付接口。

目录登录前后统一使用后台公开在售集合，不作为账号专属报价。加载、空列表和失败重试有独立状态；目录请求不占用兑换 busy，不访问安全存储，失败不注销账号、不清除兑换结果。

## 接口与价格

- 匿名 GET `/api/v1/guest/plans`，沿用现有 HTTPS 专用传输与禁止重定向策略，不传 Bearer、Cookie 或账号参数。
- 服务端控制可见、在售和剩余容量；客户端只展示 `can_purchase=true` 且有合法新购周期价格的套餐，保留服务端排序。
- `transfer_enable` 已为 GiB；`prices` 为整数分，展示时用整数除法及余数保留两位小数。0 是合法价格；null/缺失不是免费。
- 周期按月、季、半年、年、两年、三年、按流量排列。`reset_traffic` 为已有套餐的流量重置，不混入新购展示。仅有重置价格或没有价格的项目不展示。
- 负数、浮点/字符串价格、超出后端上限的金额、未知有价周期、重复套餐 ID 和格式异常响应明确报错，不伪装成空目录或免费价格。
- 公开接口不提供币种，公开配置亦无币种字段。本次不猜测货币符号；显示精确网站数字标价，提示联系现有微信确认币种和购买。没有为此增加后端部署依赖。
- 不渲染套餐 HTML 描述或加载其中的外部资源。

## 变更位置

- `lib/models/xboard.dart`：公开目录、套餐和价格模型。
- `lib/services/xboard_api.dart`：匿名目录请求及字段校验。
- `lib/manager/purchase_manager.dart`：独立的目录加载、去重和错误状态。
- `lib/views/purchase.dart`：真实页面初始化时并行启动目录和会话恢复。
- `lib/views/purchase/plan_catalog.dart`：响应式套餐卡片；`center.dart` 仅插入此区块。
- `arb/`、`lib/l10n/`：中、英、日、俄文案及生成文件。

## 测试矩阵

| 验收或风险 | 测试入口 |
|---|---|
| 匿名请求、同一客户端带授权请求后不泄露凭据、严格金额/周期/排序 | `test/purchase/plan_catalog_api_test.dart` |
| 登录前后、会话恢复故障、busy 隔离、并发去重、失败重试、dispose | `test/purchase/plan_catalog_manager_test.dart` |
| 原页面实际触发目录加载 | `test/purchase/plan_catalog_host_test.dart` |
| 未登录/已登录、全部周期和零价、微信复制及原兑换功能保留 | `test/purchase/plan_catalog_widgets_test.dart`、既有 `purchase_widgets_test.dart` |
| 320 宽、2 倍文字、长名称、两列/一列和错误/空/加载 | `test/purchase/plan_catalog_widgets_test.dart` |
| 真实 Flutter Widget Tree 中文渲染和滚动到微信区 | `test/purchase/purchase_render_test.dart` |

新增 UI 用例在 UI 尚未实现时实际失败 8 项，实现后通过。API/manager 测试首次运行时实现已到位，没有伪造 Red 阶段。真实匿名 API 使用新客户端解析器已成功读取公开套餐：200 GiB，按流量 15000 分；该读操作未登录、未兑换或修改服务端。

渲染图为合成数据，不是线上价格清单或原生打包端到端截图。旧测试报告中的焦点问题、同步状态文案及 Helper/Core 兼容性结论不因本次展示增量关闭。本次无需改动或部署 Xboard-Go。

## 本轮验证结果

环境：Windows x64，Flutter 3.47.4 / Dart 3.13.3。日期按用户时区 America/Los_Angeles 记为 2026-10-04。

| 实际命令 | 状态 / 退出码 | 结果 |
|---|---|---|
| `E:/flutter/bin/flutter.bat test --no-pub --reporter expanded` | PASS / 0 | 261 通过、0 失败、0 跳过；25.034 秒。含新增 API 21、manager 10、UI 9、真实宿主 2 项；既有 219 项均保留 |
| `E:/flutter/bin/dart.bat analyze lib/manager/purchase_manager.dart lib/models/xboard.dart lib/services/xboard_api.dart lib/views/purchase.dart lib/views/purchase/center.dart lib/views/purchase/plan_catalog.dart test/purchase` | PASS / 0 | 0 诊断；27.074 秒 |
| `E:/flutter/bin/dart.bat run build/plan-catalog-live-check.dart` | PASS / 0 | 生产 API 解析器匿名读取线上公开目录成功，返回 1 项、200 GiB、按流量 15000 分 |
| `git diff --check` | PASS / 0 | 没有空白错误；CRLF 转换提示不是错误 |
| `& ./build/plan-catalog-windows-build.ps1` | PASS / 0 | 最终 Windows Release UI 构建 59.773 秒；使用现有 MSVC/SDK 和 CMake/Ninja，输出至新的 plan-catalog bundle，旧 ZIP 保留 |
| 覆盖率重新计算 | NOT RUN | 本次没有重新计算行/分支覆盖率，未沿用旧 coverage 作为本轮结果 |
| 新包真实 Windows 进程启动及账号兑换 | NOT RUN | 本轮用真实 Widget Tree、真实宿主初始化和匿名线上接口分层验证；没有重启当前代理应用或再次消费测试卡 |

初次静态分析发现既有 manager 测试替身缺少新增 API 方法，以及价格校验中的两条 nullable cast 提示；已最小适配替身并改用局部变量类型收窄，原断言不变，重新分析通过。新增宿主测试早期的类型推断和文案匹配错误属于测试自身，修正后通过，不作为产品 Red 证据。

独立审查未发现本次新增的 Critical/High 问题，提出的真实宿主加载接线缺口已由两项集成用例补齐；没有把旧 QA 未验收项改为通过。最终构建及 ZIP 校验信息见包内 BUILD-INFO/SHA256SUMS 和本次交付说明。

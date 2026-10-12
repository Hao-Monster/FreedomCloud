# 购买页套餐展示补全

## 需求基线与范围

用户授权“先研究一个方案，然后进行开发”。采用标准对齐：仅补全购买页公开套餐展示，不改变套餐可见范围、购买/兑换/认证规则，不改其他页面，也不实施先前讨论的侧栏账户入口。

基线 `development@b565b33`；fetch 自有 freedomcloud 后落后0、领先8，无开放 development PR。最近远端CI成功对应旧 `6ce68d8`，不是本轮结果。保留现有coverage、QA草稿、stash、旧工作树、预览包；不推送、部署或启动候选客户端。

## 已核实的合同

- 本轮无认证 GET `https://fast.hjy.ca:8443/api/v1/guest/plans` 成功，公开产品已含 `content`、`tags`、`reset_traffic_method`、`capacity_remaining` 等。客户端当前解析丢弃这些字段。
- Xboard-Go本地 `2acd15f9` 的 `internal/store/plans.go`、用户 `PlanCatalogPage.tsx`、`SafeMarkdown.tsx` 和后台套餐表单交叉确认字段语义。本地源码不代表全部线上能力。
- 名称/流量/7种新购周期继续保持原合同；流量已经是GiB，金额是整数分，0为合法价格，null不是免费，不推断币种。
- 正文是服务端已经替换模板变量的Markdown。支持标题/列表/强调/删除线/表格及无属性u下划线，不执行任意HTML。按运营配置呈现，不自行增删服务承诺。
- 限速/设备字段显式null或0表示未限制；字段缺失显示未提供，不能伪造不限。重置方式null为跟随系统，0每月1日、1按到期日每月、2不重置、3每年1月1日、4按到期月日每年；未来未知枚举如实标为未知，不能映射成不重置。
- `capacity_remaining` 显式null为销售名额不限；非负整数是剩余销售名额，不是用户流量。缺失时不推断容量。
- `reset_traffic` 价格可以单列为流量重置标价，仅说明，不增加重置或支付动作，也不使仅含重置价格的套餐成为新购项。
- 继续请求匿名公开目录；定向用户/仅续费套餐、当前账户资格、后台计数、组ID及管理字段不在范围。匿名can_renew=false不展示成“不可续费”。

## 实现顺序

1. 在真实PurchaseView宿主测试中加入新字段响应，先证明正文/标签未展示的Red。
2. 补齐模型和严格类型解析，兼容可选字段缺失，保持公开请求与manager生命周期不变。
3. 仅更新套餐卡：标签、限额、重置、销售名额、全部标价和安全Markdown正文；保持卡片与购买中心原有位置和其他区块不变。
4. 新增兼容当前SDK的 `flutter_markdown_plus 1.0.12`，直接使用其markdown AST时声明 `markdown` 依赖。现有组件不足以安全完整呈现Markdown，采用成熟原生renderer而非WebView或自制通用HTML引擎。只增这些必要依赖及锁定的传递项，不升级无关依赖。正文图片只显示说明，不自动加载外部资源；链接仅显式点击有效HTTPS时经既有外跳入口打开，无凭据拼接。
5. 补测试、真实Widget树离线渲染截图、独立审查、全Flutter回归、定向analyze和本地提交。真实客户端/网络/兑换不运行。

## 可执行验收矩阵（执行前冻结）

| 编号 | 验收/风险 | 测试层级与位置 | 命令/预期 |
| --- | --- | --- | --- |
| C01 | 真实公开响应经API/manager/宿主展示正文和标签 | plan_catalog_host_test | flutter test；先因缺失内容失败，再通过；无Authorization和额外请求 |
| C02 | 新字段完整、缺失/null/非法类型、未知重置码 | plan_catalog_api_test | flutter test；保留原值/明确未知，异常不伪装成功 |
| C03 | 七种价格/0/最大整数/重置价格分离 | API及widget | 精确显示，旧过滤/顺序/币种不变 |
| C04 | 正文标题/强调/列表/表格/下划线及中文 | 新plan_catalog_details_test | 实际原生渲染文本和结构可见 |
| C05 | raw HTML/事件/危险链接/图片无副作用 | details安全用例、真实host网络替身 | 无脚本执行组件、无网络图片，危险链接不调用外跳 |
| C06 | 标签/限额/5重置规则/继承/销售名额 | API与details | 不把缺失等同不限，不把容量等同流量 |
| C07 | 窄窗320、2倍文字、多标签/长正文、多周期/主题 | details及离线render | 无Flutter overflow，文本与原入口可达 |
| C08 | 匿名独立加载、兑换busy/失败隔离、旧微信/购卡/登录/兑换 | 现有test/purchase全套 | 不改变既有行为 |
| C09 | en/zh_CN/ja/ru与其他页面不变 | 既有ARB生成、定向analyze、diff与独立审查 | 无硬编码新标签/无非购买页行为修改 |
| C10 | 整体回归 | flutter test --no-pub，定向覆盖率输出独立路径 | 记录PASS/FAIL/NOT RUN，保留原coverage |

执行使用 `E:\flutter\bin\flutter.bat` / `dart.bat`。本机Flutter3.47.4/Dart3.13.3，CI固定Flutter3.41.7；必须在报告保留版本差异。具体命令、计数和失败记录另存本轮结果文件，不能用计划代替通过证据。

## 回退与未授权事项

使用单个可追溯本地实现提交；需要回退时可对该提交新建revert，不覆盖用户配置或改写历史。不触碰后端/线上套餐，不进行真实兑换/购买，不运行会自动启用代理/TUN的完整客户端，不推送、建PR或发布。

## 执行完成

模型/解析/原生卡片/受限Markdown/4语言和测试已实现。最终购买模块268例、全Flutter563例通过，静态分析0问题，Windows目标UI资源编译通过；真实客户端未启动。Red→Green、独立审查修正、覆盖率、截图和NOT RUN见 `engineering/testing/plan-catalog-completeness-2026-10-10.md`。

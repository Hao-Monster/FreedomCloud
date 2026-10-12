# 购买页套餐展示补全验证记录

## 范围与证据边界

- 起点 `development@b565b33da5cf4d95baa9a2e752b5884f26fa57dd`。用户授权先研究后开发；只修改购买页公开套餐卡及必要模型、解析、本地化、依赖与测试。
- 原始方案和执行前矩阵：`engineering/plans/plan-catalog-completeness-2026-10-10.md`。
- 本轮匿名线上 GET 已确认公开套餐包含 content、tags、reset_traffic_method、capacity_remaining；没有访问管理写接口、修改线上配置、下单或兑换。
- 客户端继续使用匿名公开目录。网页登录后的定向/当前套餐续费集合不在本次范围；币种接口未提供，保留原币种确认说明，不沿用网页硬编码的货币符号。
- 其他页面、账号/订阅同步、兑换确认/历史/恢复、微信/购卡入口、代理/TUN与导航行为均未改变。`PurchaseCenter` 产品代码只增加正文外跳回调的一行传递。

## 实现与安全

- 模型和解析保留说明、标签、销售剩余名额、重置规则、重置标价。可选字段兼容旧接口；通过存在标记区分缺失与显式 null，未知数字重置码如实显示未知。
- 原七种新购价格顺序、整数金额、零价、无价过滤、reset-only 过滤及匿名请求边界保持。重置标价独立展示，不新增操作。
- 正文采用原生 Markdown：标题、段落、列表、强调、删除线、表格、无属性 u。其他 HTML 保持原文，不执行标签/脚本/属性。表格可横向滚动；列表缩进按实际字体和缩放测量，TextPainter 使用后释放。
- 图片在元素构建阶段转为“未加载外部图片 + alt”，不解析/获取图片地址，不加载网络、本地文件或 data 图片。链接只允许用户显式激活无 userInfo 的 HTTPS，沿用购买页外跳和失败提示；不附加账户凭据。
- 新增 `flutter_markdown_plus 1.0.12`、`markdown 7.3.1`。已检查两者 BSD-3-Clause 许可与 SDK 约束；锁文件只新增这两个纯 Dart/Flutter 包，没有升级原依赖或引入新的原生平台插件。
- 4个ARB文件既有键值逐项比对不变，仅新增本页文案；生成文件中的其他消息函数编号移动来自标准生成器，文案与行为未修改。

## Red → Green 与审查修正

1. 在真实 `PurchaseView` 的传输替身中先加入正文/标签：`flutter test --no-pub test/purchase/plan_catalog_host_test.dart --reporter expanded`，原实现 0 PASS / 2 FAIL / 0 SKIP、exit1、框架4秒。两例都因找不到 `Public catalog tag` 失败，不是编译失败。实现后同两例随目标和全模块回归通过。
2. 新Markdown详情/截图首轮 30 PASS / 1 FAIL：根级HTML文本被渲染器忽略。保留失败断言，补受限 block 包装后 31 PASS / 0 FAIL，不引入 HTML 解释器。
3. 独立审查发现 linked-image 标签为空、链接中 u/粗体原始标记泄漏；修正安全alt提取和行内AST，加入复合回归。
4. 独立审查建议缓存隔离与真正入口验证，已补同Document跨段落用例，以及 `PurchaseCenter` 外跳成功/失败两例。
5. 进一步2x有序列表文字盒断言实测 FAIL：Ahem字体下数值和句点跨两行。保留断言，改为实际字体测量后本模块268例PASS。此前中文真实字体截图只能证明该字体，不能替代此跨字体回归。
6. 50,000个未闭合u解析用例检查全部文本保留、耗时小于5秒、下一段合法u/strong不受缓存污染。这是受限解析回归，不是生产压力或响应延迟承诺。

## 验收矩阵

| ID | 层级与用例 | 结果 |
| --- | --- | --- |
| C01 | 真实PurchaseView/API/manager，缺失/损坏会话依然匿名展示正文和标签，无额外请求 | PASS |
| C02 | API新增字段类型、missing/null/0、错误与未知码、构造器兼容 | PASS |
| C03 | 七周期、整数极值、零价；重置标价分离且无按钮；reset-only仍过滤 | PASS |
| C04 | Markdown文字及实际TextSpan粗体/斜体/删除线/下划线，列表、表格、中文 | PASS |
| C05 | HTML文本、危险/相对URL、图片各类URI与malformed、HttpClient创建0次；显式点击/键盘/真实页面失败提示 | PASS |
| C06 | 标签顺序/重复/特殊字符；限额；5种重置/继承/未知；销售名额0/null/缺失 | PASS |
| C07 | 320px/2x长标签、20标签、无空格长串、完整价格、横向表格、底部可达；序号两个字符同一行 | PASS |
| C08 | 整个购买模块既有认证/微信复制/购卡/确认/不确定结果恢复/同步/历史测试 | PASS |
| C09 | en/zh_CN/ja/ru × 浅/深色，无key泄漏；ARB既有键值不变；定向静态检查 | PASS |
| C10 | 最终全Flutter回归与行/分支覆盖率 | PASS：563/0/0 |

## 执行记录

环境：Windows，Flutter **3.47.4**、Dart **3.13.3**；仓库CI固定Flutter **3.41.7**，本地结果不是CI结果。以下命令中的SDK使用 `E:\flutter\bin\flutter.bat` 和 `dart.bat`。时长为测试框架或明确测量的墙钟，未记录者不估算。

| 命令 | 状态/exit | 数量 PASS/FAIL/SKIP | 时间与说明 |
| --- | --- | --- | --- |
| `flutter pub get` | PASS/0 | 不适用 | 只新增2依赖 |
| `dart run intl_utils:generate` | PASS/0 | 不适用 | 正常生成4语言 |
| `flutter test --no-pub test/purchase/plan_catalog_api_test.dart test/purchase/plan_catalog_host_test.dart test/purchase/plan_catalog_widgets_test.dart --reporter expanded` | PASS/0 | 86/0/0 | 初轮，框架9秒 |
| `flutter test --no-pub test/purchase/plan_catalog_details_test.dart test/purchase/plan_catalog_render_test.dart --reporter expanded` | PASS/0 | 31/0/0 | HTML修正后，框架2秒 |
| `flutter test --no-pub test/purchase --reporter expanded` | PASS/0 | 268/0/0 | 补齐入口/缓存/字体回归后，框架23秒 |
| `dart analyze lib/models/xboard.dart lib/services/xboard_api.dart lib/views/purchase/plan_catalog.dart lib/views/purchase/plan_content.dart lib/views/purchase/center.dart test/purchase/plan_catalog_api_test.dart test/purchase/plan_catalog_host_test.dart test/purchase/plan_catalog_details_test.dart test/purchase/plan_catalog_widgets_test.dart test/purchase/plan_catalog_render_test.dart` | PASS/0 | 0 error/warning/info | 最终定向检查 |
| `flutter test --no-pub --branch-coverage --coverage-path build/plan-catalog-completeness-coverage/lcov.info --reporter expanded` | PASS/0 | 563/0/0 | 最终框架82秒、墙钟95.44秒；前轮561/0/0、墙钟102.07秒 |
| `flutter build bundle --no-pub --debug --target-platform windows-x64 --asset-dir build/plan-catalog-completeness-assets --depfile build/plan-catalog-completeness-assets.d` | PASS/0 | 不适用 | 最终重编墙钟23.92秒；仅编译UI资源，不是Windows安装包或真实运行 |
| `git diff --check` | PASS/0 | 不适用 | 仓库常规CRLF提示非内容错误 |

## 覆盖率与视觉证据

覆盖率独立输出到 `build/plan-catalog-completeness-coverage/lcov.info`，不覆盖原有 `coverage/`。按最终 `git diff --unified=0` 的新增行与LCOV记录求交集（新文件取全部行），本轮记录的可执行变更行 **161/162，99.38%**；记录的变更分支 **43/43，100%**。不是所有源码行、所有语义分支或全仓覆盖率。

| 产品文件 | 全文件LCOV行 | 全文件LCOV分支 | 本轮diff行 | 本轮diff分支 |
| --- | --- | --- | --- | --- |
| `lib/models/xboard.dart` | 25/25 | 16/16 | 0/0 | 0/0 |
| `lib/services/xboard_api.dart` | 302/309 | 96/106 | 18/18 | 5/5 |
| `lib/views/purchase/center.dart` | 361/397 | 76/107 | 1/1 | 0/0 |
| `lib/views/purchase/plan_catalog.dart` | 111/111 | 35/36 | 53/53 | 17/17 |
| `lib/views/purchase/plan_content.dart` | 89/90 | 21/21 | 89/90 | 21/21 |

模型新增const构造器/字段没有对应LCOV可执行行，存在性语义由API及widget行为用例覆盖。唯一未命中的新增行是 `plan_content.dart:146` 的默认父样式兜底，真实Markdown路径始终提供父样式；不得把100%记录分支误解为所有潜在路径都被执行。原账户/API文件的未改分支仍保留缺口。依赖库、系统外部浏览器、真实支付或原生网络不在本覆盖统计之内。

非作者独立审查已复核字段合同、Markdown资源边界、金额/匿名行为及后续修正，最后没有新增源码阻塞；所有提出的三个测试缺口已补，不存在已知本轮Critical/High问题。此结论不替代下面的真实运行NOT RUN项。

`test/purchase/plan_catalog_render_test.dart` 从真实Widget树、合成套餐、系统中文字体生成：

- `build/plan-catalog-completeness-preview/catalog-light.png`（1000×1300）
- `build/plan-catalog-completeness-preview/catalog-dark.png`（1000×1300）
- `build/plan-catalog-completeness-preview/catalog-narrow.png`（360×1200）
- `build/plan-catalog-completeness-preview/catalog-large-text.png`（320×2600、2x）

4张截图已实际查看。截图为离线组件渲染，不是候选客户端实机截图；使用示例套餐而非用户私有账户数据，不覆盖旧预览包。

## 未运行与交付边界

- NOT RUN：完整客户端启动、真实Windows窗口/外部浏览器、真实账号登录/兑换/支付、代理/TUN/驱动/后台服务、Android/iOS/macOS设备。未获相应环境授权；完整应用启动存在代理/TUN副作用。
- NOT RUN：CI、正式Windows打包/签名、远端推送/PR/合并/发布/部署。UI资源编译不是可分发程序，未修改线上任何配置。
- 回退：对本轮本地实现提交创建新revert即可；不涉及数据库、配置迁移或用户状态重置。保留旧包、未跟踪QA文档与coverage。

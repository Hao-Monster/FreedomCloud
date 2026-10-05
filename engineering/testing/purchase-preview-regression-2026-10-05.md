# P06 QA001 / QA003 修复与验证

日期：2026-10-05。工作树：purchase-preview-fixes-20261005；分支 codex/purchase-preview-fixes-20261005。基线 0ce398967a0299a0b5bcb97ab8cbc5aed1727bf9。此报告是本地源码与自动化证据，不代表 Windows 原生包验收或最终主线构建完成。

## 修改范围

- lib/views/purchase/center.dart：购买正文建立 FocusTraversalGroup，保持表单在真实侧栏旁的遍历顺序；查询与确认兑换按钮按对应操作显示进度。
- lib/manager/purchase_manager.dart：私有 check/redeem 操作标识在既有 _run 的进入/finally 中设置和清除；busy、canRedeem、存储、恢复和消费逻辑不变。
- test/purchase/purchase_interaction_test.dart：15 项正式回归，用生产 CommonScaffold、CommonNavigationBar 和真实 PurchaseManager，只在 API、存储、订阅同步边界使用合成替身。
- 三个既有 widget/render 替身仅补充 checkingCode、redeemingCode 接口；不替代新的真实 manager 用例。

## 测试矩阵

| 验收或风险 | 场景 | 最终结果 |
| --- | --- | --- |
| QA001 键盘遍历 | 916×1024 / 480×800，各含目录有/无；邮箱→密码、Shift+Tab 返回、密码→登录→注册→找回；继续可到微信及侧栏，无焦点陷阱 | 4 PASS |
| 登录提交与互斥 | 聚焦登录按钮按 Enter、挂起请求重复 Enter 不重复登录；密码提交先校验错误输入，再成功登录 | 2 PASS |
| 实际查询进度 | 请求挂起时显示 Checking、按钮/卡号禁用、重复请求被阻止；成功、失败、401 后状态复位 | 3 PASS |
| QA003 无关操作 | 同步、账户刷新、历史分页实际挂起时，查询/确认按钮保留正常文案，继续互斥，不产生查询或消费副作用 | 3 PASS |
| 兑换提交及后续同步 | 保存 pending 前显示 Redeeming；pending 写入后才消费；重复调用不重复消费；后续同步不假报查询 | 1 PASS |
| 独立审查补充 | pending 存储失败后正常确认文案和可用状态恢复，0 消费；清除故障后单次重试成功 | 1 PASS |
| 不确定结果恢复 | 通过历史恢复原收据，不假报新查询，不发起额外消费，最终恢复空闲 | 1 PASS |

## 命令与结果

环境：Windows，本机 Flutter 3.47.4 / Dart 3.13.3；CI 固定版本另由主代理核对。SDK 详情见 flutter-version.json。所有账号、卡号和 URI 均为合成测试数据，未向真实后端发送测试请求。

| 命令 | 结果 | exit | PASS / FAIL / SKIP | 时间 |
| --- | --- | --- | --- | --- |
| E:\flutter\bin\flutter.bat pub get --offline | PASS | 0 | 不适用 | 54.15s（含版本读取） |
| flutter test --no-pub --machine test/purchase/purchase_interaction_test.dart，正式 Red（interaction-red-2） | 预期 FAIL | 1 | 6 / 6 / 0 | 21.77s |
| 同一 12 项首次 Green（interaction-green-1） | PASS | 0 | 12 / 0 / 0 | 23.73s |
| 最终目标测试（interaction-reviewed-final） | PASS | 0 | 15 / 0 / 0 | 20.64s |
| flutter test --no-pub --machine --coverage --coverage-path=build/qa-preview/purchase-lcov-final.info test/purchase | PASS | 0 | 181 / 0 / 0 | 40.11s |
| dart analyze --fatal-infos，6 个变更 Dart 文件 | PASS，无诊断 | 0 | 不适用 | 33.92s |
| dart format --output=none --set-exit-if-changed，6 个变更 Dart 文件 | PASS，0 changed | 0 | 不适用 | 3.58s |
| git diff --check，任务文件 | PASS | 0 | 不适用 | 未单独计时 |

每条最终命令的完整参数、退出码和时长分别保存在 *-result.json；机器测试事件保存在对应 .jsonl。最终文件内容的 SHA256 在 p06-source-sha256.json。

Red 证据：正式 red-2 的 6 个失败分别是窄窗真实侧栏中的邮箱 Tab、同步/分页/兑换/恢复时查询文案、刷新时确认按钮文案。未通过修改断言迎合生产行为。首轮 red-1 另暴露了测试辅助 finder 选错文本子节点/不存在 key 的问题，已修正；不将该辅助错误当作产品缺陷证据。red-2 在生产修改之前完成。

静态检查首轮虽 exit 0，但发现新测试一条 prefer_final_locals info。已将该局部变量改为 final；最终启用 --fatal-infos 后为 No issues found。早期 14 项/180 项通过记录保留，最终计数以 15 项/181 项为准。

## 覆盖率与边界

- PurchaseManager：227 / 244 行，93.03%；diff 范围内可执行行 5 / 5 命中。
- PurchaseCenter：357 / 396 行，90.15%；diff 范围内可执行行 32 / 33 命中。未命中的新行号 141 是新增外层组件后缩进移动的既有“已退出登录但保留成功收据”分支，不是本次新增业务行为。
- 分支覆盖率：NOT COLLECTED，本次 Flutter --coverage 输出为行覆盖率，不将其表述为分支覆盖。
- 独立审查未发现 Critical/High/Medium，已落实其唯一 Low 测试建议。仍需最终 Windows 包的真实键盘、导航和当前后台不变验收；该部分 NOT RUN。
- 未运行安装器、驱动、服务修改、真实兑换或生产故障注入；未修改 API 协议或支付方式。
- pub get 仅产生 7 个生成文件的 EOL 状态漂移，主代理逐项核对 HEAD/index/规范化内容相同后刷新索引，未纳入提交内容。锁文件无改动。
- 提交、主线集成、CI 与 Windows 产物状态以 engineering/development-status.md 和对应构建证据为准。

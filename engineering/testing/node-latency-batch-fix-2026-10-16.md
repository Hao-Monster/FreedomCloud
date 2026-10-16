# 节点延迟漏测与所选配置入口修复（2026-10-16）

基线为 `development@e3ab52bd1afc46b009907f0ee7386fd228914d8e` 上已有 P1/全量延迟 WIP。用户反馈全量遗漏配置，以及选中配置后当前配置按钮无效。本轮不执行任何 Git 写操作，不启动候选，不操作代理、TUN、服务或用户配置。

## 诊断与根因

1. `nodeCatalogTesterProvider` 监听 `versionProvider` 并调用 `disposeScope()`；`GlobalState.startGroupsUpdateTask()` 每 60 秒触发普通代理组刷新，`AppController.updateGroups()` 每次成功都递增该版本。因此普通刷新也会取消正在准备或执行的批次。真实 provider 回归分别复现 `cancelled` / `uiInactive`，无需用户点击取消。
2. `_testCurrent()` 只读取活动代理组，忽略总览选中的 profileId；无活动组时还会禁用按钮。回归复现选中非活动配置没有进入其测试路径，以及窄屏按钮被错误禁用。
3. 用户当前旧预览窗口只读截图显示“已完成55、失败8、未测5、异常配置1；测速已中断”。既有日志采样两轮共消费2MiB，仍有 read_budget_reached 和历史轮转缺口，不能据此确认当次精确中断事件。静态路径、PID也不证明已加载组件版本。
4. 用户指定配置只读结构检查仅输出计数、协议类别和时间，不输出原文/节点/端点/凭据。三份有1/6/24个内联节点，均无协议预筛或重复身份阻断；另一份文件本身无内联或provider节点。历史容量143条，未达到5000上限。该私有诊断不进入包或源码快照。

## 最小修复范围

- `lib/providers/node_overview.dart`：去掉普通组刷新与测试取消的错误关联。保留活动配置、脚本和配置定义变化的失效规则；会话错误仍由共享协调器与Core传输返回。新增依赖注入入口仍默认返回既有单例协调器，不建立额外任务预算。
- `lib/views/proxies/overview/overview.dart`：选中特定配置时只测试该配置的全部节点，复用隔离全配置管线；无特定选择时保持原活动组及URL语义。所选配置不依赖活动组存在，不受搜索/只看可用筛选影响。
- `test/common/node_catalog_batch_lifecycle_test.dart`：真实provider、目录服务、协调器路由及历史存储组合，只在Core测量边界使用替身。16个合成配置/170节点，普通刷新发生在准备与执行阶段均须全部完成、逐配置历史计数一致、15个非空目录释放。活动配置/脚本变化仍中止的4项反例。
- `test/views/node_overview_test.dart`：新增宽屏与窄屏所选配置入口回归，原当前组URL语义回归保留。

Core/Agent/Helper、协议、依赖锁、网络配置及其他产品功能本轮未修改。原始WIP保留；本轮前59文件备份及hash清单在 `E:/Temp/fcx-latency-fix-20261016/before`。

## 测试矩阵与实际结果

| 验收点 | 用例 / 命令 | 结果 |
|---|---|---|
| 选中配置后按钮进入正确配置，窄屏无活动组仍可用 | `flutter test test/views/node_overview_test.dart` | 66 PASS，0 FAIL/SKIP，exit0 |
| 普通刷新不漏后续配置，170条历史全部写入 | `flutter test test/common/node_catalog_batch_lifecycle_test.dart` | 2正向+4失效反例 PASS，exit0 |
| 配置失败隔离、分块、存储、provider失效 | tester/all/catalog_delay/node_overview_providers 四套 | 53 PASS，0 FAIL/SKIP，exit0 |
| 全量回归 | `flutter test --reporter json` | 894 PASS，0 FAIL/SKIP，exit0；测试事件耗时69.606秒 |
| 静态分析 | `dart analyze --format machine` | 0 error、11既有warning、889info，exit2；未称零告警 |
| 差异空白检查 | `git diff --check` | exit0 |

工具：本机 Flutter 3.47.4 / Dart 3.13.3，与CI版本差异沿用已有披露；未升级依赖。
本轮未采集覆盖率；Go源码无本轮变化，未重复Go测试。先前Go120顶层/164含子测试通过只作为相同Go源码的历史证据。

Red→Green：页面2项修复前失败；刷新2项在生产取消监听仍存在时分别返回cancelled/uiInactive，删除错误监听后全部通过。回归测试最初两次运行因测试夹具编译/初始化缺失失败，修正夹具后才取得有效Red证据，未计为产品缺陷复现。

证据：`E:/Temp/fcx-latency-fix-20261016` 中 current-red.log、refresh-red-r3.log、ui-green.log、refresh-green.log、domain-regression.log、flutter-full.jsonl、analyze-full.log、test-summary.json。新测试代码复审未发现阻塞项；不以合成通过代替用户真实订阅/窗口验收。

## 预览与待验收

本文件在新包冻结前写入；具体新快照、包hash、构建及审计结果在交付证据和开发台账记录。仍为未提交WIP预览，保留旧完整包，Core/Agent/Helper/UI完整重编并核对绑定。真实新候选的跨60秒全量完成、所选配置按钮、实际延迟与代理/TUN兼容性均待用户测试。窗口隐藏、离开页面、手动取消等现有生命周期行为本轮保持原义；不从历史泛化提示推断用户进行了这些操作。

## 构建后交付补记

- 新完整目录：`E:/CodeWorkstation/FlClashX/dist/FreedomCloud-windows-amd64-latency-fix-wip-69d7ea5b117c`。
- ZIP：`E:/CodeWorkstation/FlClashX/dist/FreedomCloud-windows-amd64-latency-fix-wip-69d7ea5b117c.zip`，154,081,036 bytes。
- ZIP SHA256：`addf26b9e47e8374f3216fdfcbe2190c0d516e5f58a6dc6418ede39e64550501`。
- WIP快照：`69d7ea5b117c2d0334a8c1ac1d579bdf34a116008a757aa456c4d98d20d9ebd1`，1007个源码/文档文件；基线SHA只标识底座，不能代表该WIP产物。
- 可恢复源码：`E:/CodeWorkstation/FlClashX/dist/FreedomCloud-source-latency-fix-wip-69d7ea5b117c.zip`，SHA256 `7a35f977b2a8ce4a5b99ca946f4403d2a6333a353e46acef3e96b51215968c4c`；快照复制、ZIP恢复逐文件核验通过。
- 完整重编 exit0，569.096秒；独立静态审计8/8 PASS。解压目录与bundle逐文件校验一致，Helper/Core绑定及UI编译输入核验通过。
- 首轮静态审计7/8 PASS：交付目录尚缺源码伴随ZIP；复制既有冻结源码ZIP并校验SHA256后，第二轮8/8 PASS。首轮失败证据保留，没有放宽校验或修改产品产物。
- 既有VS发现config-only exit1按明确工具链配置继续，随后实际AOT/native构建通过；未跳过实际编译。构建步骤明细在证据目录。
- 证据目录：`E:/CodeWorkstation/FlClashX/dist/latency-fix-wip-69d7ea5b117c-evidence`。旧全量预览ZIP hash复核一致，完整目录保留。
- 用户验收：选中任一非活动配置后测试当前配置；全量测试保持总览页面打开并持续超过一个60秒刷新周期，确认末尾配置有结果；0节点配置仍为0；新包真实业务验收NOT RUN。

本段和开发台账在构建审计后更新，属于交付记录，不改变包内冻结源码。没有Git写操作，没有运行新候选，没有修改现役代理/TUN/服务/网卡/用户配置。

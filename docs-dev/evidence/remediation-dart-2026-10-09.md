# Dart 性能与资源修复方案及验证

日期：2026-10-09（Asia/Singapore）。基线：`development@a52907c`。

用户已授权逐项修复并统一打包。本子任务范围为 F06/F07/F08/F09/F10 UI 侧/F12，并协调 F01 配置协议与 F05 成功后提交状态；所有产品测试均使用隔离替身、合成输入或专有临时目录，不启动候选客户端，不改当前代理/TUN/服务。主代理统一审查、提交与打包。以下保留最初方案，后附实际实现、失败和执行证据。

## 方案与顺序

1. F06：请求使用局部 Completer，统一在成功/失败/超时/断连完成时清理 pending/default；移除无条件延迟清理 Timer，迟到和重复回复忽略。
2. F07：连接轮询保留当前代待刷意图，旧请求结束后给当前代补一次；保持单请求在途、旧结果丢弃、stop/dispose不复活。
3. F08：流量取样改为单个在途周期，使用当前运行意图和代数控制重启；执行器不改写他代Timer，Timer回调核对所属代，停止失效后续工作。
4. F09：统一窗口显示、最小化和生命周期；后台暂停连接列表取样、1秒运行时UI计时和Core UI事件。桌面托盘仍消费3秒流量与60秒分组刷新，故保留这两项及3秒TUN观察；Android后台同时停止其流量/分组循环。恢复及时刷新，不启动/停止代理。
5. F10：跨分组全局10 worker，按节点/URL去重，单批次busy防重复，取消/超时向Core发送request-id取消；过期结果不能覆盖当前状态，配置/会话/后台变化取消批次。Core实现由另一个代理提供；协议对齐后执行集成验证。
6. F12：日志按实际日期和大小滚动，每次新建都执行所有权限定的保留清理；保留当前文件与非本logger日志，异步清理失败如实限制影响。

## 测试矩阵

| 编号 | 用户契约/风险 | 层级与测试入口 | 主要场景 | 预期 |
|---|---|---|---|---|
| D06 | 完成RPC及时释放 | `test/clash/rpc_lifecycle_test.dart` | 60成功回复、2分钟timeout提前完成、同步回复/发送异常、类型错误、超时、迟返/重复、断连完成 | pending/default即时为0，无多余timer，返回约定正确 |
| D07 | 连接轮询可恢复且不并发 | `test/connection/connection_manager_test.dart` | 在途stop/start、多次启停、旧成功/失败、隐藏、手动刷新、dispose | 新代继续，旧数据不生效，峰值并发1 |
| D08 | 流量轮询停止不复活 | `test/common/update_tasks_test.dart` | 慢/快取样交错、连续start、stop/resume、异常、跨多个周期 | 峰值1，stop后不增长，恢复仍有效 |
| D09 | 可见性控制纯UI工作 | `test/common/ui_activity_test.dart` 及适用widget测试 | 当前连接页/其他页、最小化、隐藏、恢复、生命周期、重复事件 | 后台不拉snapshot，恢复补读；TUN/代理动作不被调用 |
| D10 | 测速任务和取消有界 | `test/common/delay_test_coordinator_test.dart` 及协议测试 | 大订阅、跨组重复、busy、取消、超时、旧回复、配置变化 | 最多10在途，任务去重，取消向Core传递，不更新过期结果 |
| D12 | 日志磁盘预算和所有权 | `test/common/file_logger_test.dart` | 同日多次滚动、跨日、非本logger文件、当前文件保护、失败重试 | 保留数量有界，日期正确，不删其他文件 |

尽可能先运行目标测试记录Red，再实施、重跑Green和相关既有测试。最终对修改Dart文件运行静态检查，并在主代理协调的独占Flutter测试窗口完成全量回归；不降低既有lint或跳过用例。新测试辅助类无法在缺失实现时编译的项目，明确记录未建立单独Red。

## 未运行边界

真实Windows窗口/TUN/代理连续性、长时heap/GC/CPU采样、真实网络批量测速、Android实际pause/resume以及Linux/macOS实机均由主代理安排后续验收；隔离验证不代表这些已通过。

## 执行记录

### 已实现行为

- F06：`safeFuture` 返回可等待的 `Future<T>`，完成后立即清理；移除无条件追加的延迟清理Timer。RPC调用持有局部Completer，先安装清理再发送；同步回包、同步/异步发送失败、超时、类型错误、迟到/重复回包、断连均释放pending/default。60个立即完成请求分别使用30秒及2分钟超时，完成即无pending/default和残留Timer。
- F07：连接轮询维持单个在途请求，跨代完成后消化当前代的刷新意图。stop、隐藏、dispose清理意图；旧成功和旧失败均不能写入新代。
- F08：流量任务使用运行意图、epoch和单个在途周期；多次start合并，stop失效后续任务，异常不杀死未来周期。
- F09：新增 `UiActivity`，区分桌面失焦、隐藏、最小化和Android生命周期。Core活跃更新串行合并，并在重连时重新声明；窗口恢复不会启动代理/TUN。桌面分组刷新直接调度，不再依赖隐藏窗口不保证执行的post-frame回调。
- F10：所有节点、分组、全部分组和托盘入口共享10 worker；按节点名/URL去重，等待队列只保存数据，最多10,000个目标，单请求5秒、整个批次30秒。每个任务携带session/batch/index生成的request-id；显式取消、超时、配置变更、后台边沿及会话退出撤销结果所有权并通知Core，活动spinner回到失败/取消结果。工具栏显示取消，重复发起受busy保护。传输取消本身最多等待1秒，Core也有自己的接收起算deadline；旧回复不能覆盖新批次。真实网络耗时、CPU和吞吐尚未测量。
- F12：日志按实际日期及UTF-8已接受字节轮转，每次创建新文件都预留数量和容量。默认每份10MiB、至多7份，总预算70MiB；历史超大自有日志也在预算内收敛。仅删除匹配本logger命名的文件，保留当前文件及外来日志。删除失败不继续创建文件，队列有界并退避；dispose等待writer并关闭sink。测试小阈值允许保存一整行，实际默认单条16Ki字符上限小于文件限额。

### F01/F05 协议与快照

- 普通增量更新不发送 `external-controller` / `controller-enabled`，防止默认9090覆盖profile端点；显式关闭发送false，显式打开传true及恢复的profile端点。TLS/Unix/Pipe-only profile显式打开不额外添加明文9090。
- 完整setup保留profile优先语义；重新加载profile仍按profile应用。没有新增产品三态开关。Go侧负责同一合同下全部controller listener的启停和secret保持。
- `getSetupParams` 只构造候选值；Core setup返回成功才提交 `lastRuntimeConfig` / profileId、外控端点/secret/UI目录以及有效网络值、分组元数据。失败与超时保持上一成功快照。
- 独立复核发现配置构造期间切换profile会混用身份与内容。现从控制器入口捕获Profile，并经network sync、`getSetupParams`、`patchRawConfig` 显式传递；所有关键await后核对当前profile和操作意图，再提交。配置A不会被配置B的内容替换却仍标为A。
- 独立复核发现Android恢复时的慢probe可在pause或手动stop后重写startTime并复活采样。现 `probeStartTime` 只读，恢复调用在提交前核对status/UI/probe三个epoch，并在后续异步图标更新后再次核对。

### 验收矩阵补充与结果

| 项目 | 可执行验证 | 结果 |
|---|---|---|
| D06 | RPC立即完成、长timeout、同步回包/异常、迟返/重复、断连和错误类型 | PASS；无残余pending/default/Timer |
| D07 | 真实ConnectionManager的stop/start、隐藏、旧成功/失败、dispose | PASS；单请求在途，新代继续 |
| D08 | 实际GlobalState任务循环的慢任务、重复start、任务异常、stop跳过后续任务 | PASS；停止不复活 |
| D09 | UiActivity与真实ConnectionManager连接、Core UI更新串行/重新声明 | PASS；保留桌面失焦采样，隐藏暂停连接列表 |
| D09恢复边界 | `test/clash/resume_state_test.dart`：pause、pause→resume、manual stop、正常恢复 | PASS；旧probe不写状态，正常恢复继续取样，无真实VPN操作 |
| D10 | 有界调度、去重、busy、批次/单请求deadline、取消、旧回复和真实工具栏按钮 | PASS；Dart协议与Core约定一致 |
| D12 | 同日/跨日轮转、外来文件、未flush字节、历史超大日志、确定性删除失败 | PASS；文件/字节/重试有界 |
| F01/F05 | `controller_config_protocol_test.dart`，普通更新/显式开关/特殊端点/成功失败投影 | PASS |
| F05快照 | `config_snapshot_test.dart`：构造前已切换及构造中切换 | PASS；真实配置变换函数使用捕获Profile，构造不提交runtime状态 |

### 命令与执行结果

环境为Windows本机、`E:\flutter\bin\flutter.bat` 3.47.4、Dart 3.13.3；单元/组件测试使用假时钟、合成RPC及专用临时目录。以下路径中的 `work/performance-audit/` 位于本聊天工作目录 `C:\Users\冯飏\Documents\Codex\2026-10-08\new-chat`，不在源码仓库内。

| 执行 | 结果、退出码 | 时间 | 证据 |
|---|---|---|---|
| 11个Dart目标/相关RPC与TUN测试文件 | PASS 52 / FAIL 0 / SKIP 0；exit 0 | 15.434秒 | `dart-remediation-targets.txt` |
| 第一轮 `flutter test --no-pub --reporter expanded` | PASS 448 / FAIL 0 / SKIP 0；exit 0 | 36.345秒 | `flutter-remediation-full.txt` |
| 日志预算与UI重连边界首轮 | PASS 10 / FAIL 1 / SKIP 0；exit 1 | 10.456秒 | `dart-remediation-boundaries.txt`；失败为测试自己的Windows读取句柄阻止轮转删除 |
| 上述边界修正fixture并增加删除失败合同测试 | PASS 12 / FAIL 0 / SKIP 0；exit 0 | 9.239秒 | `dart-remediation-boundaries-final.txt` |
| 第二轮全量 | PASS 451 / FAIL 0 / SKIP 0；exit 0 | 31.552秒 | `flutter-remediation-final.txt` |
| resume边界有效Red | PASS 1 / FAIL 3 / SKIP 0；exit 1 | 9.384秒 | `dart-resume-review-red-valid.txt`；三个迟返场景均错误提交startTime |
| 两项审查修复及相关启动/配置/可见性回归 | PASS 38 / FAIL 0 / SKIP 0；exit 0 | 9.296秒 | `dart-review-boundaries-green.txt` |
| 最终全量，采集行与分支coverage | PASS 457 / FAIL 0 / SKIP 0；exit 0 | 49.995秒 | `flutter-remediation-final-coverage.txt` |
| 全部owned Dart源文件及测试的 `dart analyze` | 0 error / 1 warning / 214 info；exit 2 | 15.625秒 | `dart-remediation-analyze-final.txt` |
| owned路径 `git diff --check` | PASS；exit 0 | 未单独计时 | 仅Git的LF/CRLF转换提示，无空白错误 |

最终全量命令（已确认本SDK支持两个coverage参数）：

```powershell
E:\flutter\bin\flutter.bat test --no-pub --coverage --branch-coverage --coverage-path='C:\Users\冯飏\Documents\Codex\2026-10-08\new-chat\work\performance-audit\remediation-final-lcov.info' --reporter expanded
```

38项审查边界Green命令：

```powershell
E:\flutter\bin\flutter.bat test --no-pub --reporter expanded test/clash/resume_state_test.dart test/clash/config_snapshot_test.dart test/clash/controller_config_protocol_test.dart test/common/ui_activity_test.dart test/clash/windows_startup_controller_test.dart
```

静态检查的唯一warning是未修改的 `lib/views/proxies/providers.dart:45`（`invalid_null_aware_operator`，该文件git diff为空）；info包含既有与新代码风格提示。没有禁用规则或把exit 2写成PASS。`delay_tests.dart` 的延迟访问闭包必须保留，直接tearoff会提前初始化真实ClashService，破坏初始化顺序和测试隔离。

### Red → Green 与失败分类

- F06先获得8个目标失败（exit 1，8.526秒），修复后与相关超时用例合计16通过。最早一次widget fixture误触平台初始化，已改用纯test+fake_async，该环境失败不算有效Red。
- F07/F08有效Red为8通过、5目标失败；修复后13通过。
- F12仅加入测试seam时，2通过、2目标失败：同日8份突破3份测试限额、跨日未创建正确日志；初步修复后4通过（8.513秒），后续总预算和失败合同包含在最终457中。
- F09/F10的新helper及F01/F05新参数合同没有可在缺失实现时独立编译的Dart基线Red；使用原审查复现、Core积压probe、协议测试、实际入口组件测试和完整回归作证，不伪造先失败记录。
- resume最早新增fixture未初始化AppState，4个失败中混有fixture错误（`dart-resume-review-red.txt`，29.829秒）；补齐隔离AppState后重跑，1通过、3个目标失败构成有效Red，再修复得Green。
- 日志同日测试曾在后台轮转时读取目录文件，自己的Windows句柄阻止删除。产品按预期退避；fixture改为等待writer完成才读取，并新增注入删除失败的独立测试。没有吞掉产品错误、删除断言或加重试使测试变绿。

### 覆盖率与独立审查

- 覆盖率保存到仓库外指定文件，原有 `coverage/` 未覆盖。LCOV大小403204字节，SHA256：`f50cb8e3be53659770d56dfb5c9ef549c31f9d4569ed9e8502586a132267042d`。
- 此次全部已加载package记录（包含generated及未涉及模块）行覆盖率为5767/27947，即20.64%；分支记录1637/9606，即17.04%。本SDK输出BRDA而未输出BRF/BRH，分支按BRDA计数。该口径不是本次改动行覆盖率；主报告另外根据diff计算变更覆盖。
- 尚未覆盖的重要现场路径：真实Android重连和生命周期、原生窗口隐藏与恢复、实际服务断连、真实网络队列取消、长时heap/GC/CPU和持续托盘使用。覆盖率不替代这些验收。
- 独立代理只读复核RPC、任务轮询、ConnectionManager、日志、测速、配置与可见性。发现的两个Medium交错点已修复并复核关闭；未发现新增High。独立复核未重复运行Flutter，由本执行者记录上述测试。
- 本子任务未执行Git提交、推送、打包、候选客户端启动或系统配置变更；最终Git与包验收由主代理统一负责。

# Windows Helper 与 UI 重连调查

日期：2026-10-05。源码基线：`0ce398967a0299a0b5bcb97ab8cbc5aed1727bf9`。下文源码位置均为此提交的仓库相对路径与行号。

本项只交付源码调查和后续验证任务，不修改授权、TUN、自动订阅更新或 Agent 协议。没有运行原生应用、服务命令、安装器、故障注入或真实业务测试。**历史 UAC 问题尚未关闭，不能将本次整合或购买 UI 修复表述为 Helper 已修复。**

## 1. 历史事实与证据边界

本机保全的历史资料为 `purchase-native-qa-2026-10-04.md`、`purchase-native-qa-2026-10-04-results.md` 和 `plan-catalog-native-qa-2026-10-04.md`。原始日志和账号状态留在私有测试资料中，本文件只记录脱敏结论。

| 事项 | 历史证据 | 不支持的结论 |
| --- | --- | --- |
| 礼品卡包 `622abe1` 重开 UI | 观察到 UAC，用户明确手动取消；日志有 Helper 修复超时与授权错误 | 没有证明修复成功，也没有完整新 Agent/Core/Helper 组合验收 |
| 目录包 `7d02a94` 重开 UI | 观察到 UAC；提示随后消失，但用户选择未知；日志中的修复命令引用该测试包 | 不能将消失解释为取消、允许或修复完成 |
| 服务与包内 Core | 两者哈希不同，旧 Helper 允许值与旧 Core 相符 | 这是不一致事实；缺少当时健康响应、调用入口和状态关联，不能据此指定唯一根因 |
| 后台状态 | 记录到原 Agent/Core/Helper 被复用，监听归属未变 | PID 和监听不证明 TUN、路由、配置及实际流量没有变化 |
| 安装修复日志 | 没有对应本轮成功修复的阶段记录 | `ShellExecuteW` 返回值大于 32 只代表启动请求成功，不证明服务操作完成 |

历史报告将问题记为 QA-002 / QA-CAT-01。当前源码调查不能补写当时未采集的运行证据。

### 历史包已经包含的修复

只读 `git merge-base --is-ancestor <commit> <source>` 核对确认：以下提交均已是 `622abe1`、`7d02a94` 和本次基线的祖先。

| 提交 | 行为范围 |
| --- | --- |
| `99df219`、`bbece1b`、`6eb440b` | 并发授权共享、单 UI 会话失败锁存、异常与清理 Future 处理 |
| `da8d4d1` | 正确分类 `ShellExecuteW` 返回值 |
| `905465f` | 服务并发启动返回 1056 时继续验证健康，不直接回退 UAC |
| `74633b0` | 服务生命周期幂等处理 |
| `7470391` | 记录 Helper 修复阶段结果 |

旧分支提交 `f082792` 的等效行为已经归入主线。提交 SHA 不同不等于功能遗漏；此次恢复历史源码不是上述问题的新修复。授权锁存只在一个 UI 进程会话内有效，不能保证下一进程的首次授权不发生。

## 2. 已确定的源码调用链

### UI 重连时的状态

1. `lib/state.dart:118` 的 `initApp` 在每个新 UI 进程构造 `AppState`；`lib/models/app.dart:35` 的 `realTunEnable` 默认是 `false`。
2. `lib/providers/app.dart:14` 从该内存状态构造 `realTunEnableProvider`。源码中没有在 Agent ready 事件后恢复此字段的路径。
3. `lib/controller.dart:1296` 的 `_initCore` 在 Core 已初始化且使用 Agent 时，仅刷新 groups、providers 和 UI cache，不重复 `applyProfile`；此分支也没有读取运行 TUN 状态。
4. `services/agent/src/runtime.rs:2049` 的 ready 消息包含 `proxyRunning` 和 `privilegedBackend`，没有 TUN 状态。两者都不能作为 TUN 已启用的替代证据。
5. `lib/controller.dart:1384` 的 `_initStatus` 采用 Agent 启停状态并调用 `updateStatus`；它不恢复 `realTunEnable`。`lib/providers/state.dart:121` 的 `updateParamsProvider` 不依赖运行计时，因此不能声称计时恢复本身触发配置更新。
6. `lib/controller.dart:1278` 的 `_handlePreference` 检查 SharedPreferences 是否初始化成功；正常时返回，异常时提示并退出。它不是正常启动中的 TUN 恢复入口。

因此，“已有 Agent 已 ready”与“新 UI 已掌握运行 TUN 状态”是两个不同条件。该状态缺口是源码事实；它在历史事件中是否参与触发仍需运行证据。

### 两条可达授权入口

| 入口 | 条件与路径 | 关键位置 |
| --- | --- | --- |
| 启动模式规范化 | 保存模式为 global，当前 profile 的 `flclashx-globalmode=false`；立即监听安排 `changeMode(rule)`，改变 updateParams 后进入配置更新 | `lib/manager/app_state_manager.dart:101` → `lib/controller.dart:1857` → `lib/manager/clash_manager.dart:50` → `lib/controller.dart:654` |
| 当前订阅启动更新 | `autoUpdateProfiles` 更新到期订阅，或延迟任务更新开启自动更新的当前订阅；成功更新当前 profile 后静默应用配置 | `lib/controller.dart:1367` → `lib/controller.dart:859` / `lib/controller.dart:880` → `lib/controller.dart:431` → `lib/controller.dart:479` → `lib/controller.dart:740` |

两条路径最终都可进入 `lib/controller.dart:669` 的 `_requestAdmin`。当所请求 TUN 为 true 而内存 `realTunEnable` 为 false 时，会进入授权路径。此时若 Helper 不健康，`system.authorizeCore` 可尝试启动现有服务或安装/修复。

上述链条在历史两个包中已经存在，但历史没有同时记录 `wasInitialized`、模式规范化条件、订阅更新分支、请求 TUN、内存 TUN 及授权入口。因此不能将任何一条写成“已证实的唯一历史根因”。另外，Core 未初始化、Agent 未 ready、后续用户更改也可能走不同路径，需区分。

### Helper 与 PR57 的边界

- `lib/common/windows.dart:201` 的健康判断要求服务存在、配置路径正确、SCM 为运行态及 Helper ping 校验通过。
- `lib/common/request.dart:186` 比较当前包 Core 实际文件的哈希与 Helper 响应；`services/helper/src/service/hub.rs:180`、`:466` 使用本 Helper 构建固定允许值。不得因为版本不一致而删除此信任检查。
- `lib/common/windows.dart:225` 的修复操作只有健康轮询通过才返回成功；启动进程成功不等于修复成功。
- PR57 的 `lib/clash/windows_agent_launch.dart:37` 在 Broker 存在时要求受保护 Agent/Core 与包内对应组件匹配，缺失或不匹配时拒绝启动。
- `lib/clash/service.dart:152` 优先连接已有 Agent；连接成功后不会进入新组件路径选择。因此 PR57 不能证明已解决旧后台重连的 Helper/UAC 问题。
- 授权失败后 `lib/controller.dart:718` 可把实际 TUN 值设为 false，并继续由调用方生成配置；这提示需核验后台副作用，不能据此反推历史已经改变了 TUN。

## 3. 新旧 Core 的运行配置契约

| 来源 | 返回含义 | 使用限制 |
| --- | --- | --- |
| 当前 `getConfig("fcx://runtime")` | `core/hub.go:979` 调用 `core/runtime_config.go:14`，由实际应用过的配置与 live General 合成；TUN 为 `isRunning && pendingTunEnable` | 可用于观察 Core 当前应用配置，不代表 Windows 设备或流量验收成功 |
| 当前普通 `getConfig(path)` | 读取并解析指定配置文件 | 文件内容不是运行状态 |
| 旧 `622abe1` / `7d02a94` 的 `getConfig` | 仅支持读取配置文件，没有 runtime 特殊分支 | 对旧后台必须处理 unsupported/error，不能把保存偏好当运行真值 |
| Agent ready / CoreState | Agent ready 有启停和特权后端信息；`CoreState` 是写入侧状态模型且没有 TUN | 不得据此推断 TUN=true；没有可替代 runtime 查询的现成 `getState` 读取接口 |

runtime 特殊分支来自 `6e22112`。Dart 底层 `clashCore.clashInterface.getConfig("fcx://runtime")` 可发送原路径；外层 `ClashCore.getConfig(id)`（`lib/clash/core.dart:318`）会先拼接 profile 文件路径，不能直接传该 URI。现有底层超时为两分钟，若将来用于启动观察，应另行评估合理的有界等待，不能让 UI 启动长时间阻塞。

读取结果应保留已知 true、已知 false、unknown 的区别；超时、不支持或字段非法均不能补成某个布尔值。完整返回可能含私密配置，后续只能解析必要布尔字段，不落盘或打印原始响应。

**单独把 `realTunEnable` 恢复为 true 不是完整修复。** 它会跳过 `_requestAdmin` 当前条件，不能用来把“旧后台已经运行”当作“新包已通过修改权限与组件信任检查”。只读重连和真实变更应分别定义行为，真实变更仍保留健康、哈希及授权要求。

## 4. 后续纯测试与诊断任务

以下均为计划，尚未实现或执行。先建立窄的系统效果边界替身，防止测试调用真实 `sc`、UAC、进程启动或网络配置；不能把手工复制生产判断的测试当作调用链回归。

| 编号 | 场景 | 需验证的合同 |
| --- | --- | --- |
| P07-T1 | ready Agent，只读重连，runtime 明确 TUN=true/false | 观察状态准确；不授权、不修服务、不因观察发送 setup/updateConfig |
| P07-T2 | 旧 Core 不支持 runtime、超时或字段错误 | 结果为 unknown；不从 privilege/proxyRunning/保存配置补值，不写 TUN=false |
| P07-T3 | 启动模式规范化 | 从真实 provider 变更捕获入口和变更字段，不误标为用户显式启用 TUN |
| P07-T4 | 启动订阅更新 | 捕获静默 apply/setup 的入口，与纯 attach 区分；自动应用的策略须先明确 |
| P07-T5 | 用户真实变更且 Helper 与新包不匹配 | 恢复观察状态后仍执行必要信任与授权检查 |
| P07-T6 | 拒绝授权、并发、显式重试 | 不伪成功；并发共享、失败锁存有效；不将未知后台状态默写为关闭 |

现有 `test/common/admin_authorization_test.dart`、`test/common/windows_runas_test.dart`、`test/common/windows_service_command_test.dart` 和 `test/clash/windows_agent_launch_test.dart` 覆盖各自单元边界，但不等于 controller 启动调用链或真实 SCM 验收。

最小后续诊断可记录：启动关联 ID、调用入口枚举、`usesAgent`、`wasInitialized`、ready/代次、请求 TUN、观察 TUN 与来源、发生改变的字段名、Helper 健康失败分类、授权结果及是否准备发送配置。禁止记录 token、完整配置、订阅地址、账号、卡号或原始 HTTP 响应。本轮没有添加这些运行日志。

若完整修复需要改变自动订阅应用行为、升级旧组件或扩展 Agent 协议，应另立范围和回归合同，不为本轮购买预览临时绕过信任检查。

## 5. 隔离环境任务与本轮边界

- 在可恢复 Windows VM 验证：完整匹配组件、无 Helper、停止/健康 Helper、路径错误、哈希不匹配、1056 并发、取消 UAC、旧 Agent/Core 不支持 runtime。分别记录包来源、系统前后状态、授权次数与真实网络行为。
- 独立验证关闭 UI 后 Agent/Core 与连接连续，再验证重连。不能用 PID/端口代替连接证据，也不能靠更改本机生产代理制造失败。
- X/Alt+F4 走 `handleBackOrExit`；`minimizeOnExit=true` 只隐藏 UI，进程与单实例锁仍在。`minimizeOnExit=false` 且使用 Agent 时才走保存、detach、退出 UI。非 Agent 情况会退到完整退出。见 `lib/controller.dart:1030`、`:1055`。
- 托盘“退出”调用 `handleExit`，会停后台；不用于保留后台的预览替换。调整关闭偏好前记录原值，不为解除开关锁定顺手修改提供商策略。

| 本项活动 | 状态 | 说明 |
| --- | --- | --- |
| 源码、历史报告与 Git 祖先关系核对 | 已完成只读调查 | 仅证明文中源码与历史记录，不是原生行为复测 |
| P07-T1 至 P07-T6 | NOT RUN | 仅提出合同；未新增或运行测试，未建立本轮 Red → Green |
| 原生 UI/真实 UAC/Helper 维修/服务启动停止 | NOT RUN | 本项明确禁止执行 |
| VM、驱动、TUN、真实流量、旧组件矩阵 | NOT RUN | 需要独立隔离环境及对应授权 |
| 业务兑换或生产接口测试 | NOT RUN | 不属于本项范围 |

购买 UI 的验收和本问题分别跟踪。即使购买焦点、进度文案、目录显示及新预览包通过，也不能关闭 Helper/UAC 或完整 Windows 组件验收缺口。

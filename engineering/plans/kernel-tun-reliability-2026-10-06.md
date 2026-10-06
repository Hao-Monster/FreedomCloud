# 内核升级与 Windows TUN 可靠性开发批次

状态：已获用户开发与测试授权，执行中；不是已验收发布。基线 `development@2b587a80ad187995194608ffcd0f9f8cfa6695cd`。2026-10-06 开工 fetch 后与远端 ahead/behind 为 0/0，无开放 PR；基线 quality-gate 37430048151 成功。仅本地开发、测试、提交与预览准备，不推送、合并、发布或操作工作站服务/路由。

## 需求基线与范围

目标：开关反映当前 Core 的 TUN 真实运行状态。用户意图、配置接受、网卡就绪及特定流量是否代理分别建模，不能用保存的 `enable=true`、Helper ping 或通用 `proxyRunning=true` 代替 TUN 成功。升级与修复分别验证，再验证同一源码产生的 UI / Agent / Core / Helper。

本批范围：

1. Mihomo 固定为稳定版 `v1.19.32`（上游提交 `88dcbf7f1614a67c3b36b848ee3592dfa92ada36`），锁定依赖。保留现有 uTLS 指纹覆盖并验证编译兼容，不追随浮动 Alpha，不更改默认 TUN 栈或用户配置。
2. 最小、可追溯的 Mihomo 生命周期补丁：在真实 listener 创建、关闭、失败、外部配置修改与 Cleanup 路径观测状态，受同一锁保护。补丁校验固定输入 hash，构建必须显式加载，禁止修改全局模块缓存。
3. Core 提供专用、无账号/订阅内容的 `getTunStatus`；返回进程实例、状态版本、实际 listener、设备/接口检查和受控错误码。Windows 开启成功至少要求 listener 有效且对应接口 up。接口查询失败是 unknown；状态 on 不承诺所有流量均被代理。
4. Agent 提供可验证的实例/代次与启动来源；Helper 存在不等于当前 Core 有权限。后端重启必须确认旧实例退出和新实例连接，禁止固定延时后接回旧进程并报告成功。包含 Helper 停止响应的必要修复：只有实际停止才确认成功，保留失败进程句柄供诊断/重试，启动替换受同一锁保护。新 Agent 的 start/stop 绑定公开的 Core 会话归属，Helper 重启丢失记录时不能以空记录确认旧进程退出。旧组件缺可靠合同则明确拒绝自动迁移；不涉及服务安装策略或孤儿进程强制回收。
5. Flutter 分离持久化意图、观测状态与正在进行的操作；配置失败、超时、旧 Core、断连及过期结果不显示成功。网络设置、快捷入口、托盘、热键及内部真实状态消费者保持一致。显式重试，不以反转已保存意图代替重试。
6. 只读恢复、后台配置刷新不触发 UAC；新授权由明确用户操作发起。保留冷启动意图，既有 Helper 可用时允许正常恢复，但仍必须观察实际结果。
7. 配置接受与 TUN 达成分层：监听失败可能发生在其他配置已应用之后，不能虚构原子回滚；Agent journal 保留明确接受的配置意图，不持久化“已经运行”的观测结论。IPC 失败不能默认返回空字符串成功。
8. 增补目标回归、失败/竞态/兼容测试、Windows 编译检查和可追溯构建；同批交付的底层组件不得混用旧包。

非目标：WFP 驱动/Broker 重写、安装测试签名、改动工作站防火墙/SCM/路由、Antigravity 专属规则、在线支付、购买流程改造、默认启用新协议或 mips 栈、正式签名发行。微信联系、兑换与历史、账号订阅、匿名套餐与价格全部保留。

## 状态与接口合同

`getTunStatus` schemaVersion=1，有限字段：`coreInstanceId`、`revision`、`observedAt`（UTC 毫秒）、`requestedEnabled`、`state`（off/starting/on/failed/unknown）、`listenerActive`、`device`、可选 `errorCode`、`privilege`（elevated/unprivileged/unknown）、`interfaceState`（up/down/missing/unknown/notApplicable）。具体最终序列化由实现及契约测试锁定。

用户意图不等于观测结果；operation 独立表示 enabling/disabling/idle。关闭失败仍可能处于运行态，必须保留实际结果和错误。请求编号、Core 实例/代次与 revision 防止旧响应覆盖新操作。断连立即使当前观测失效；有界轮询不允许永久绿色。旧组件不支持合同时显示未知/需要更新，不推断关闭。状态观察无配置写入、无授权和服务重启副作用。

配置接受不代表 listener 达成，也不代表路由/目标流量验收。`auto-route=false` 是合法配置，不能仅因没有全局路由认定创建失败。权限和接口探测失败必须保留未知语义。

Helper `/capabilities` 只公开协议能力和允许的 Core hash，保留原认证边界。应用要求 `stopAcknowledgesExit`、`ownedStop` 与同批组件匹配。新 Agent 在发送 start 前记下本实例和启动代次组成的 `ownerInstanceId`，不使用认证令牌作为归属标识；网络结果不确定时保留归属，不能退回无归属 stop。已确认退出的同一会话可以重复关闭；不匹配或 Helper 重启后未知归属必须拒绝确认。这是生命周期合同，不是新的身份认证机制。

独立审查增加的必要边界：退出/重启/清除先撤销正在等待的 TUN 意图并排空配置队列；后端迁移与后台重连共用协调器；连接既有 Agent 默认只读；取消授权不能通过偏好监听器延迟重新提交配置。它们属于原“失败与恢复不伪成功”的完整实现，不扩展购买或驱动范围。

## 任务、依赖与完成条件

| ID | 任务 | 依赖 | 完成证据 | 状态 |
|---|---|---|---|---|
| T0 | 基线、原稿保全、范围与合同 | 无 | refs/bundle/drafts、明确写入分工、本计划 | PASS；bundle 离线恢复/fsck，原稿 hash 一致 |
| T1 | 原缺陷与异常路径目标回归 | T0 | 修复前失败及原因，禁止伪造 Red | PASS；Dart 最初 Red 只有当时工具输出，报告披露原始日志缺口 |
| T2 | 固定内核依赖与可复现补丁入口 | T0 | go.sum/verify、补丁 hash、带/不带补丁门禁、桌面构建 | PASS；四平台 Core 与 Android 桥接编译通过 |
| T3 | Core 真实 TUN 状态与错误合同 | T1,T2 | 生命周期、并发、外部更新、Cleanup、权限/接口测试 | 自动化 PASS；实际网卡/权限场景 NOT RUN |
| T4 | Agent 实例、代次与后端交接 | T1 | Rust 协议/恢复/错误测试与 Windows 编译 | Agent 64 / Helper 29 PASS；静态检查基线问题见报告；真实服务 NOT RUN |
| T5 | 应用操作协调、观测、授权与 IPC 失败 | T3,T4 | 正常/失败/断线/重试/乱序/恢复回归 | 自动化 PASS；OS 入口端到端 NOT RUN |
| T6 | 全入口 UI 与真实状态消费者 | T5 | 组件测试、购买回归、非 Windows 兼容 | Flutter 342 PASS；原生窗口/托盘/热键 NOT RUN |
| T7 | 独立跨层审查与 CI 集成、源码检查点 | T2–T6 | 缺口修复、最终 diff、相关检查、分逻辑本地提交 | 独立审查无剩余已知 High；提交准备中；云端 CI NOT RUN |
| T8 | 同源码 Windows 完整构建与隔离验收 | T7 | 四组件来源/hash、包校验、VM 与真实流量证据分列 | 构建待执行；隔离 VM 信息未提供，运行验收 NOT RUN |
| T9 | 台账与交付收口 | T7,T8 | 源码提交映射、包来源、测试报告、限制和恢复步骤 | 执行中；不把预览交付等同于运行验收 |

写入边界：Core 代理 `core/**`；应用代理 `lib/**`、`test/**` 与 l10n 源资源；Agent 代理 `services/agent/**` 与必要的 `services/helper/**` 停止合同；主负责人仅构建/CI/工程文档与整合。Git 写入只由主负责人串行执行。不存在第二个开发分支。只读构建快照不作为新的开发入口。

## 验收与测试矩阵

| 验收标准/风险 | 区域 | 层级与场景 | 预期 |
|---|---|---|---|
| 无权限创建失败 | Core/Flutter | lifecycle fixture + controller test；VM 非管理员 | 真实失败/原因；无绿色伪成功，可明确重试 |
| Helper 可用、旧 Core 非特权 | Agent/服务连接 | 实例交接测试；VM 混版本 | 不把 ping 当 Core 权限；不接回旧实例冒充成功 |
| Helper 重启或旧会话归属丢失 | Agent/Helper | 归属不匹配、重复关闭、请求超时、真实 HTTP fixture | 不假确认旧 Core 退出，不停止其他会话，不盲目并行新启动 |
| 无权限/UAC 取消/Helper 启动失败 | 应用 | 协调器测试；VM 安全对话框由用户操作 | 保留失败与意图，后台不自动反复授权 |
| IPC 断开/发送失败/超时/格式错误 | IPC/应用 | 故障注入单元测试 | 非成功结果，观测 unknown，不能空字符串成功 |
| listener 失败、关闭失败 | Core | 注入 listener lifecycle | 最近实际状态准确，关闭失败不谎报 off |
| PATCH/Cleanup/重复切换 | Core/应用 | 并发、状态转换、乱序响应 | revision/实例隔离，无旧成功覆盖新请求 |
| 重新挂接/重启/过期 | Agent/应用 | 恢复、时钟与断连测试 | 重新读取，旧观测失效，不以持久化意图推断运行 |
| 退出/重启与授权、迁移同时发生 | 应用生命周期 | 真实生产协调器的可控 Future/队列回归 | 撤销旧意图，旧回调不重新开网卡；重启失败不留下静默不可用窗口 |
| 设备检查失败 | Core | 查询错误/缺失/关闭 fixture；VM | unknown 或明确失败，不伪成功 |
| 各入口一致 | UI/托盘/热键 | 组件/状态测试、隔离真实窗口 | 等待、失败、关闭、运行和重试语义一致 |
| 配置兼容 | Go/Dart | 现有配置/枚举解析、栈保持 | 不更换用户栈；可解释未知值，旧组件降级明确 |
| 购买入口保留 | Flutter | 现有购买/目录测试 | 匿名套餐、微信、兑换、账号订阅回归无丢失 |
| 升级依赖/补丁完整 | 构建/CI | 固定源 hash、mod verify、带 with_gvisor 编译 | 未加载或错误补丁不能构建；Core 与 Helper hash 一致 |
| 网卡与流量效果 | Windows | 隔离 VM，TCP/UDP/DNS/IPv4/IPv6及恢复 | 分别记录网卡、路由、流量；不以单一探针替代全部 |

实际命令、退出码、计数、时间、环境、覆盖率及 NOT RUN 原因写入本批测试报告。纯构建无测试计数。Linux CI 不替代 Windows 分支；源码通过不替代设备/业务验收。

## 风险与回退

升级涉及 sing-tun/gVisor/QUIC/TLS；依赖与自有状态修复分开核验，不从上游发布说明推断本机 IDE 流量已修好。保留现有 uTLS 指纹覆盖，单独验证新依赖兼容。未在本机改网络、停止服务、安装驱动或运行实际 TUN 故障注入。

代码回退使用后续 revert 提交，禁止 reset/强推。上一可用 `FreedomCloud-windows-amd64-preview-863298c7e3f4.zip` 保留；新预览用新文件名和组件清单。恢复到旧包必须成套恢复 UI/Agent/Core/Helper；由于涉及服务身份和授权，运行回退仅在批准的隔离环境执行。私有原稿和备份不纳入提交。

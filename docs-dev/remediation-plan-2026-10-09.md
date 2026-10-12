# 性能与资源缺陷修复实施计划

授权：2026-10-09，用户要求逐项研究方案、拆分任务并实施，全部修复后统一打包，由用户进行本机测试。基线 `development@a52907c2d4425f6c1679792f64a3129ae4c562d7`。不运行候选客户端、不改变当前代理/TUN/服务，不推送或发布。

## 执行与完成条件

1. 各项先记录方案与测试矩阵，再建立失败证据、实施、目标回归和独立复核。
2. 按互不重叠的源码区域并行研究/实施，同一文件单一负责人；主代理统一 Git 和文档状态。
3. F01–F17 均完成代码修复和适用自动化验证后，统一构建 Windows 普通免安装包，重新构建变更的组件，不复用旧插件/Core/Agent/Helper 冒充新实现。
4. 包包含来源、组件 hash、测试说明与回滚路径，保留旧包；用户本机验收与 Android/隔离 VM 验收单独保留，不把本地单元测试当成实机通过。

## 开发任务与验收映射

| 任务 | 修复方案 | 验证重点 | 负责人区域 |
|---|---|---|---|
| F01 | 统一构造完整 controller 配置，保留认证/TLS/CORS | setup/update/reload/关闭；匿名401、合法凭据成功、字段保留 | Core |
| F02 | ZIP路径/类型/数量/体积预检，受限解压，独立暂存后安装；下载取消/期限/单飞 | 越界/盘符/链接/重复项、虚假大小、超限/取消/失败、旧面板保留 | 主代理 |
| F03 | Core 与 Agent 分别建立有界可取消写出及超时；写出移出状态锁 | 慢消费者、控制停止、恢复/断连、响应不被静默丢弃 | Core + Services |
| F04 | 真实停止完成后报告服务停止；失败保留所有权与可重试状态 | stop错误/超时/成功，不提前假报Stopped | Services |
| F05 | 完整解析候选成功后才替换运行配置 | raw/semantic/JSON失败保留last-known-good | Core |
| F06 | 请求结束统一立即清除pending，取消清理Timer | 30秒/2分钟、成功/异常/超时/迟到回包 | Dart |
| F07 | 旧请求结束按最新generation补调度，丢弃过期结果 | 在途stop/start与可见性切换 | Dart |
| F08 | 流量轮询single-flight和epoch/Timer所有权 | stop/resume/旧请求晚回，不复活 | Dart |
| F09 | 统一有效UI消费者与窗口状态，后台按需要降频/暂停 | 最小化/隐藏/恢复、后台必要观察、手动停止 | Dart |
| F10 | UI有界worker、去重、取消；Core排队计入deadline | 排队超时、重复批次、配置切换、取消 | Dart + Core |
| F11 | 栈/RAII替代裸分配；枚举前置、错误传播与必要通知；严格UTF-8 | RAS/API各失败点、部分失败、UTF-8/无效输入 | 主代理 |
| F12 | 每次轮转强制数量上限，跨日切换，只清理自有命名日志 | 同日多档、跨日、活动文件和其他日志保留 | Dart |
| F13 | 认证前连接并发上限+deadline+取消回收 | 慢握手、配额耗尽、合法会话可恢复 | Services |
| F14 | stdout/stderr增量有界行读取并记录截断 | 无换行巨行、UTF-8边界、退出和下一行 | Services |
| F15 | retired generation引用计数，最后在途调用完成后释放JNI | drain超时、迟到完成、重复停止/UAF | Core |
| F16 | 移除全桌面菜单查找和Timer，关闭由native TrackPopupMenu管理；主题仅作用本应用 | 左键/右键/选中/取消/销毁、现有资源和回调回归 | 主代理 |
| F17/P02 | 同步取像素作用域结束即释放Win32，图像编码独立finally | 成功/null/异常释放一次、后续队列、原生持有范围 | 主代理 |

P01 为尚未确认的优化候选，保留 NORMAL/HIGH 对照测量，不能将未经测量的性能结论写成修复。V01–V05/H01/S01 中的真实窗口、长时运行、系统恢复、Android实机和驱动/服务故障验收在相应授权环境执行，本机测试由用户完成。

## 测试与交付记录

- 分模块方案、Red→Green、命令和缺口分别记录于 `evidence/remediation-core-2026-10-09.md`、`evidence/remediation-services-2026-10-09.md`、`evidence/remediation-dart-2026-10-09.md` 和 `evidence/remediation-native-ui-2026-10-09.md`。
- 集成后执行适用的 Flutter tests/analyze、Go overlay tests、Windows Agent/Helper tests、原生资源测试和打包工具检查，再记录统一结果。
- 原有 `coverage/` 和四项 QA 草稿保留；没有未经核实清理历史分支/worktree/stash。

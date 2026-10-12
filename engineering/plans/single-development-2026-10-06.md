# 唯一开发分支与受保护主线

日期：2026-10-06。适用于 `Hao-Monster/FreedomCloud` 的快速开发、快速迭代和部分功能预览阶段。

## 目标与边界

仅保留两条活跃长期分支：`development` 承载日常开发和预览，`main` 承载经授权验收的集成结果。历史分支、工作树、stash、构建包与原稿继续保全，不把“唯一开发入口”误写成“历史分支已删除”。不因本次迁移修改购买方式、后端、代理服务、驱动或发布版本。

迁移基线：`freedomcloud/main = 4738293ea90ca9b90afcc201a5c9a09b729a86ad`。原本地 `main = dc77f6f`、本地 `development = 80c1182`、远端 `development = d7f64f5` 都是该基线祖先，分别落后 346、85、68 个提交，能够直接快进，无需改写或复制功能代码。

## 日常规则

| 环节 | development | main |
| --- | --- | --- |
| 写入方式 | 单个负责人组织小提交，正常 push | 一个验收批次一个 PR |
| 校验时机 | 本地相关验证，push 后三项 CI | 合并前同三项必需 CI、严格更新、讨论解决 |
| 历史保护 | 禁止强推、删除，适用于管理员 | 同左，另强制 PR，当前必需审批人数 0 |
| 预览 | 明确 SHA、包 hash、已测范围与缺口 | 合并不等于正式发行或平台验收 |
| 并行协作 | 只读调查/审查可并行；写入明确文件所有权；Git mutation 串行 | 仅一条晋级通道 |
| 失败处理 | 先修复或新提交 revert；失败不得晋级 | 不绕过门禁、不自动合并 |

0 个必需审批适配当前维护方式，不代表免审查、免验收或自动合并。以后有真实独立维护者时再评估强制一人审批，不能用作者自己或形式化机器人审批制造安全感。

操作顺序：

1. 检查当前分支、未提交内容、stash 和远端，读取台账。仅以不覆盖原稿的方式同步 `freedomcloud/development`。
2. 在 `development` 完成一个最小可测试增量；明确文件归属，不让多个执行者同时提交、切分支或推送。
3. 运行相关验证后小提交，经该任务授权正常推送。等待该 HEAD 的 CI；失败及时修正，不把旧成功结果当新结果。
4. 从明确提交构建部分预览，保留上一可用包。尚未完成的高风险行为不得默认启用；若不能安全隔离，则完成它后再晋级，不把无关半成品混入验收批次。
5. 到一个可验收批次后，固定开发 head，停止无关写入，创建唯一 `development → main` PR。复核最终 head、真实测试、验收和合并授权。
6. 使用普通 merge commit。禁止 squash/rebase 这条长期开发分支；GitHub 官方也指出持续复用 squash 后的 head 分支会增加重复提交和冲突风险。
7. 合并后 fetch 自有远端，将 `main` 新的合并提交快进同步回 `development`，正常推送，待开发 CI 结束后开始下批次。若出现分叉，查明并发来源，禁止 reset/force。

同一时间只允许一个晋级 PR。批次以可验证范围为边界，不以堆积天数或大批文件数量为目标。紧急修复仍走 development 的小批次；特殊维护分支或隔离实验需先说明必要性并获授权。

## 迁移任务与验证

| ID | 任务及依赖 | 完成证据 |
| --- | --- | --- |
| BD-01 | 审计两远端、最新 SHA、占用、脏文件、云端保护、PR、工作流 | main/development 祖先与无占用确认；0 open PR；当前保护和触发器实际读取 |
| BD-02 | 保全 refs、配置、工作树、stash、根补丁、5 原稿；依赖 BD-01 | bundle verify、离线 mirror、fsck 成功，关键 refs 和原稿 hash 一致 |
| BD-03 | 无 force 原子快进本地 main/development 并安全切换；依赖 BD-02 | HEAD=4738293，main upstream=freedomcloud/main，5 原稿/stash/原来源不变 |
| BD-04 | 更新 AGENTS、台账、当前流程及 main push 检查；依赖 BD-03 | 文档独立审查；YAML 解析；测试 job、命令、版本未改变；diff check |
| BD-05 | 保存并更新云端保护；依赖 BD-04 方案明确 | main 只新增必需 PR；development 只移除预先通过 CI 的推送门禁；防强推/删除/管理员适用仍在 |
| BD-06 | 正常推送 development、核对最终 HEAD 与 CI；依赖 BD-05 | 实际远端 SHA 和该提交 Actions 终态；未合并 main、未发布 |
| BD-07 | 结束保全与交接；依赖 BD-06 | 新提交离线恢复、5 原稿和 stash 复核、云端保护回读、实际结果报告 |

表中“完成证据”是验收要求，不是未执行步骤的预填结果。精确命令、开始/结束状态、哈希和 API 读取保存在仓库外私有恢复目录 `FlClashX-Recovery/20261006-single-development`；最新执行结果以该记录及交接报告为准。历史原生 QA、账号或订阅相关文件不得因整理顺便提交到公开仓库。

提交本文前，BD-01 至 BD-05 已执行：无覆盖冲突、备份离线恢复、快进切换、文档独立复核、YAML 对比及云端保护回读均通过。07:28 UTC 的 API 回读确认 main 仅新增必需 PR，development 仅移除必需状态检查子设置，其余保护字段不变。首次 API 修改因 TLS 握手超时未确认结果，读取实际状态后经现有本机代理重试成功，全程保留 TLS 校验。BD-06/07 的最终提交、CI 和结束保全结果记录于本次交接报告与私有执行结果，不在尚未推送时预填成功。

现有质量检查保持 `Flutter tests`、`Core Go tests`、`M3 package integrity checks`，检查来源绑定 GitHub Actions app `15368`。development 的新提交必须先到达远端才能由 push 触发 CI，因此开发分支不要求提交在接收前已经具有远端成功状态；质量强制门禁设在 main。开发 CI 红灯仍必须处理，并阻止该批次验收。

本次只给质量工作流增加 `push main`，不改测试断言、不跳过 job、不降低版本或主线要求。首次包含此 workflow 的 main push 即可触发最终主线提交检查；迁移本身不合并 main，因此本轮不声称主线 push 已实测。Windows/macOS 自动预览流水线的扩展作为后续独立任务，当前 macOS 可手动运行已有打包流程。

## 保全、回退与限制

- 新快照补充之前的大归档；此次未重新复制全部忽略缓存，因为不会修改它们。切换前检查 95,620 个 ignored、5 个 untracked 与目标 798 个 tracked 的同名和文件/目录父子冲突为 0，并使用 `git switch --no-overwrite-ignore`。
- 原来源 `codex/m3-7-helper-diagnostics@a5a9873` 和 `stash@{0}@f580c63` 保留。其他旧工作树不切换、不 reset、不清理；当前工程目录从此只在 development 继续。
- 需要恢复旧工作入口时，先保存当前新增修改，再安全切换回原来源分支。已推送的错误改动用新 revert 提交修正，禁止强制后退共享 refs。
- 云端设置修改前保存完整 JSON。必要时核对是否已有后来修改，再恢复原保护设置；不能用陈旧快照覆盖其他人的治理调整。
- GitHub 默认分支保留 main，避免改变现有默认页面和手动工作流语义。设置/保护读取验证不等于已经演练所有恶意推送场景；不为验证而尝试强推或删除真实分支。
- 本机备份不是异地灾备；异地副本依用户既有决定单独安排。旧分支的物理清理也需要单独核验和授权，不在本轮删除。

参考：[GitHub 分支保护](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)、[长期分支的合并方式](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/about-pull-request-merges)。

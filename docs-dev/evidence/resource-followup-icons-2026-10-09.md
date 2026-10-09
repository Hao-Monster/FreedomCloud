# R2：Windows 进程图标有界队列验证

日期：2026-10-09。对应冻结方案 `docs-dev/resource-followup-plan-2026-10-09.md` 的 R2。开发起点 `development@13b0ea05dfca6840e402a1f29d543705e30382e4`。本记录只证明本轮源码和自动化测试，不证明现役程序已经替换或 Windows 长时资源测试通过。

## 实现与验收对应

| 合同/风险 | 实现和执行用例 | 结果 |
|---|---|---|
| 1 running + 64 waiting + 64 success cache | `ProcessIconQueue` 分离任务表和成功 LRU；130 个 key 验证 65 admitted / 65 retry later；150 次成功验证缓存上限与 LRU | PASS |
| 等价路径和同 key 多消费者 | 每个 widget 持有 lease；pending/inflight 独立去重；满队列仍允许加入同 key；等价 UNC 请求保留最初 native source | PASS |
| 无人消费的等待任务不得继续执行 | 最后一个 lease 释放即取消 queued；80 个真实 `ProcessIcon` 在首任务阻塞后全部卸载，仅首任务调用 loader | PASS，原行为 Red → Green |
| 运行中取消不提前释放执行槽 | 原 native/codec future 实际返回后才释放；新消费者可以重新加入仍在执行的同 key | PASS |
| 队满不永久留下 fallback | 队满不保存候补请求；仍 mounted widget 自持容量 listener，合并通知后重试；66 个图标不靠父级 rebuild 全部显示 | PASS |
| 错误不毒化队列或永久负缓存 | null、同步异常、异步异常；同 widget rebuild 不反复重试，重新进入后成功 | PASS |
| widget 过期结果和生命周期 | A → B 的晚 A 结果丢弃；disable/enable、unmount 释放 lease/listener；无 setState-after-dispose | PASS |
| KeepScope 页面仍 mounted 时离页 | `ConnectionsView` 独立 `ValueNotifier` 直接跟随 `_isCurrentPage && uiActivity`；scope 隐藏取消、恢复重新请求，不依赖 manager 发通知 | PASS（活动 scope 组件验证及调用点审查） |
| root overlay 与窗口活动 | 共享 `ProcessIcon` 同时监听 `uiActivity`；无 scope 的窗口隐藏/恢复，以及 scope+window 同时许可场景 | PASS |
| 卸载后活动 listener 释放 | page/window notifier 暴露监听状态；卸载后两者均无监听，再切换活动状态无新请求 | PASS |
| UNC 与当前盘根路径不能碰撞 | `\\server\share\APP.exe` 和 `\server\share\APP.exe` 各自调用 native loader、显示不同 ImageProvider；保留双前导 slash | PASS，独立审查补充的既有缺陷 Red → Green |
| PNG 编码成功/null/error 的资源释放 | 既有 `process_icon_test.dart` 的 3 项真实 `ui.Image` 测试保持通过 | PASS |

实现文件：

- `lib/common/process_icon_queue.dart`：专用有界队列、lease、成功 LRU、合并容量通知和 dispose。
- `lib/common/process_icon.dart`：可注入 Windows loader、规范化 key/原始 native source 分离，保留 Win32 和 Image/codec/descriptor/buffer 的资源 finally。
- `lib/common/process_icon_activity.dart`、`lib/views/connection/connections.dart`：连接页活动 scope；不修改全局导航生命周期。
- `lib/views/connection/item.dart`：Windows widget 持有请求生命周期；六类现有消费入口继续统一使用 `ProcessIcon`；Linux/Android 既有逻辑保留。
- `test/common/process_icon_queue_test.dart`、`test/common/process_icon_widget_test.dart`：8 项队列测试、11 项真实 widget 测试；加既有 3 项 PNG 测试共 22 项。

未新增依赖、Timer 轮询或全局溢出候补队列；没有清理用户配置、触碰现役程序或更改网络。

## 命令、环境与执行结果

环境：本机 Windows，Flutter 3.47.4 / Dart 3.13.3，`E:\flutter\bin`。所有 icon fixture 只在测试边界注入 loader，未调用实际 Win32 取图标 API；widget 本身使用生产 `ProcessIcon` 的 Windows 分支。队列采用受控 Future/fake async；PNG fixture 使用真实 Flutter image 编解码并释放。

原始日志保存在私有目录：`C:\Users\冯飏\Documents\Codex\2026-10-09\resource-followup-184840`。耗时为工具包装的实测 wall seconds。下列按名称筛选的卸载用例命令用于当前复现；其最早 Red 时测试文件只有该目标用例，未将新增 API 的编译失败作为 Red。当前源码为修复态，不能直接重复得到历史 Red。

```powershell
# 卸载目标用例：最早 Red 在行为不变的 loader 注入与旧 Future 链下执行
E:\flutter\bin\flutter.bat test --no-pub --reporter expanded test/common/process_icon_widget_test.dart --plain-name 'unmount cancels queued icons behind a blocked extraction'

# UNC 既有路径碰撞 Red：新增回归用例后、改规范化前执行
E:\flutter\bin\flutter.bat test --no-pub --reporter expanded test/common/process_icon_widget_test.dart --plain-name 'UNC and current-drive-rooted paths load different icons'

# 最终目标与相关回归
E:\flutter\bin\flutter.bat test --no-pub --reporter expanded test/common/process_icon_queue_test.dart test/common/process_icon_widget_test.dart test/common/process_icon_test.dart

# 定向静态检查
E:\flutter\bin\dart.bat analyze --format=machine lib/common/process_icon.dart lib/common/process_icon_queue.dart lib/common/process_icon_activity.dart lib/views/connection/item.dart lib/views/connection/connections.dart test/common/process_icon_queue_test.dart test/common/process_icon_widget_test.dart test/common/process_icon_test.dart

git diff --check -- lib/common/process_icon.dart lib/common/process_icon_queue.dart lib/common/process_icon_activity.dart lib/views/connection/item.dart lib/views/connection/connections.dart test/common/process_icon_queue_test.dart test/common/process_icon_widget_test.dart test/common/process_icon_test.dart
```

| 阶段/日志 | 状态 | exit | 通过/失败/跳过 | 秒 | 说明 |
|---|---|---:|---|---:|---|
| `r2-icon-queue-red.txt` | FAIL（预期 Red） | 1 | 0 / 1 / 0 | 15.413 | 全部卸载后期望仅 1 次 loader，实际 80 次；不是缺失 API 或编译失败 |
| `r2-icon-queue-green-first.txt` | FAIL | 1 | 11 / 1 load fail / 0 | 16.986 | 新 scope/item 缺少 foundation import，已修复；不算目标 Red |
| `r2-icon-queue-green-second.txt` | PASS | 0 | 21 / 0 / 0 | 14.891 | 初轮目标回归 |
| `r2-icon-queue-green.txt` | FAIL | 1 | 20 / 1 / 0 | 11.694 | 扩展活动恢复测试错误要求兄弟组件恢复请求顺序，见下文 |
| `r2-icon-queue-green-final.txt` | PASS | 0 | 21 / 0 / 0 | 10.271 | 保留核心状态断言后修正请求顺序预期 |
| `r2-icon-unc-red.txt` | FAIL（预期 Red） | 1 | 0 / 1 / 0 | 13.175 | UNC/rooted 期望两个 native 请求，实际只有 UNC 请求 |
| `r2-icon-unc-green.txt` | PASS | 0 | 22 / 0 / 0 | 9.795 | 包括两项目标 Red 的最终相关回归 |
| `r2-icon-unc-analyze.txt` | PASS，有 info | 0 | 0 error / 0 warning / 22 info | 15.957 | 未隐藏 info，详见原始日志 |
| `git diff --check` | PASS | 0 | 不适用 | 未独立计时 | 仅有仓库 CRLF 转换提示 |

静态检查的 22 个 info 包含既有 Linux async IO、win32 常量弃用和 item 风格提示，也包含新增队列/test 的 forEach、cascade、布尔参数风格提示；没有 error、warning 或新增未处理 Future lint。不为消除非阻塞风格提示进行无关代码修改。

`r2-icon-queue-green.txt` 的失败依据已调查：Flutter 的 InheritedNotifier 不承诺兄弟依赖组件按界面排列顺序重新请求。测试改为断言恢复段两个 key **各一次**、两个图标均显示，仍保留隐藏时不启动排队任务、已运行任务占槽、卸载后监听归零及切换活动后没有新请求的断言。它是测试预期错误，不标记 flaky，没有用重复重试掩盖失败。

UNC/rooted 碰撞由独立审查发现，并从原提交确认已经存在；本轮不是新引入该缺陷。先通过真实两个 widget 复现，再修复 key 规范化；等价 UNC 的共享和原 native source 保留用例继续通过。

## 审查、覆盖率与未运行项

- 已审查成功缓存与任务表分离、执行槽所有权、取消、容量 listener、generation/lease 晚结果保护、scope/window 生命周期、六类调用点、无关平台路径和 finally 保留。
- 独立审查发现的请求顺序测试合同与 UNC 碰撞已按上文处理。没有发现尚未解决的 Critical/High 源码问题；这不等于原生长时运行已经验收。
- R2 定向运行没有采集覆盖率；完整 Flutter、独立 LCOV 与统一构建由主负责人执行，结果应引用本轮总报告，不以此处目标通过代替。
- **NOT RUN**：真实 Windows 页面视觉/导航、真实 Win32 大量进程图标压力、长时 RSS/USER/GDI 曲线、Linux/Android 实机。没有启动候选客户端、连接 Agent UI 会话或修改现役代理/TUN/服务。
- **架构限制**：若同步 Win32 调用永不返回，本轮保持唯一执行槽而不能强杀该调用。后续任务不会并发扩大积压，但该调用仍可能阻塞 UI；进程隔离属于独立架构范围。
- 全局成功 LRU 上限约束缓存所有者；正在显示的 widget 和 Flutter 自身 ImageCache 仍按各自生命周期持有图像，不能将“64 个缓存项”误解为整个进程只允许 64 张可见图像。
- 未执行 Git 写操作、提交、推送或发布；最终集成由主负责人串行处理。

# 累计源码晋级与跨平台测试修正

日期：2026-10-12。本文为合并前证据快照；最终 head、合并提交、检查终态及分支同步结果见 [PR #60](https://github.com/Hao-Monster/FreedomCloud/pull/60) 的实际记录。本次只集成源码，不生成可执行客户端包、不启动客户端、不部署。

## 范围与审查

- 起点：自有主线 `4738293`、远端开发 `6ce68d8`、本地开发 `a97e42d`；本地分别领先主线31个、开发远端11个提交，没有分叉。累计范围含 Core/TUN、Windows 启动/Helper、托盘及资源生命周期、购买套餐卡片。
- `a92e3ec` 已选择性保存仅兑换码 v2 方案/任务/测试矩阵及 v1 作废标记，并正常推送；未提交 QA/probes、coverage、stash、旧工作树与旧包未清理或发布。
- 三个非作者只读审查覆盖购买/文档、桌面/原生插件、Core/Agent/Helper。未发现可确认的新增 High/Medium 产品代码问题；平台与系统验收缺口保留。审查不是重新执行测试。
- `a97e42d` 之后本次不修改产品代码；唯一测试修正为 `test/common/tray_refresh_test.dart` 的 Windows/Linux 合同。没有新增 skip、取消用例、忽略诊断或改变 CI 版本/保护。

## CI Red 与根因

`a92e3ec` 的 [push run 38218687923](https://github.com/Hao-Monster/FreedomCloud/actions/runs/38218687923) 和 [PR run 38218766828](https://github.com/Hao-Monster/FreedomCloud/actions/runs/38218766828) 都在 Linux Flutter 3.41.7 上复现相同失败：**588 PASS / 2 FAIL / 1 SKIP，测试 exit 1**。PR run 的 Core Go、Windows Core and service、M3 package integrity 三项已成功，不能用它们绕过 Flutter 失败。

1. 控制器测试在 `setContextMenu` 被阻塞时要求 `destroy` 已发生。Windows 先更新图标再设置菜单；Linux 则先设置菜单再更新图标。Linux 的正确输出此时为 `[setContextMenu]`，旧测试套用了 Windows 顺序。
2. 流量 tooltip 测试在所有宿主都要求 Windows `setToolTip`，但产品合同明确 Linux 不调用该方法。此时零 tray 调用是正确结果，不是产品回归。

修正使用真实 `dart:io.Platform`，不以 Flutter 的 UI 平台 override 冒充 Windows。保持等待菜单的断言，并精确核对阻塞阶段和完成阶段的完整调用序列；合并刷新最终 destroy 次数分别为 Windows1/Linux2；Windows tooltip 的唯一调用及流量文本断言全部保留，Linux 明确断言零调用。独立复核确认没有弱化 Windows 合同。

Linux 的1项 SKIP 来自原有 `windows_service_command_test.dart` 的 `requires cmd.exe` 限制；本次未新增或修改该 skip，Windows 完整测试实际覆盖它。

## 验证矩阵

| 验收或风险 | 可执行验证 | 结果与边界 |
| --- | --- | --- |
| 强制刷新透传、原生菜单完成前不可提前返回 | controller 阻塞/完成阶段精确调用序列 | Windows 目标通过；Linux 等最终 head CI |
| 重复刷新有界且保持最新状态 | coalesce 菜单数、状态、等待者和最终 destroy 次数 | Windows 目标通过；Linux 等最终 head CI |
| 流量刷新不能重建菜单或在不支持平台调用 tooltip | Windows 唯一 tooltip 及文本；Linux 零 tray 调用 | Windows 目标通过；Linux 等最终 head CI |
| 购买与其他 Dart 行为不回归 | 完整 `flutter test --no-pub --reporter expanded` | 本机完整回归执行结果见下表 |
| 不发布错误的余额方案 | 6份 v1/v2 文档的13个相对链接及作废标记 | PASS；v2整页布局仍未实施 |
| 不触发客户端包或改变系统 | workflow触发器检查、Git范围与候选启动检查 | 普通push/PR仅quality-gate；未打tag/手动触发构建/启动客户端 |

## 本次执行

本机 Windows amd64，Flutter 3.47.4 / Dart 3.13.3；与 CI 固定 Flutter 3.41.7 分开报告。SDK 命令位于 `E:/flutter/bin/`。

| 命令 | 状态 / exit | PASS / FAIL / SKIP | 时间 |
| --- | --- | --- | --- |
| `flutter test --no-pub test/common/tray_refresh_test.dart test/common/tray_plugin_menu_test.dart --reporter expanded` | PASS / 0 | 19 / 0 / 0 | runner约1秒，未单独测墙钟 |
| `flutter test --no-pub --reporter expanded` | PASS / 0 | 591 / 0 / 0 | 最终完整50.38秒；此前55.65秒及53.00秒两次完整回归也通过 |
| `dart analyze --fatal-infos test/common/tray_refresh_test.dart` | PASS / 0 | 0 error / warning / info | 最终输出No issues found；未单独计时 |
| `dart format --output=none --set-exit-if-changed test/common/tray_refresh_test.dart` | PASS / 0 | 1文件0改动 | 0.02秒 |
| 6份需求文档相对链接与空白检查 | PASS / 0 | 13链接有效 | 未单独计时 |
| 本次测试/文档 `git diff --check` 与新增报告/台账的3个本地链接 | PASS / 0 | 无测试计数 | 未单独计时 |

这次只改测试和文档，不重新计算产品覆盖率；购买富文本的实际行/分支覆盖率保留在[原报告](plan-card-rich-content-2026-10-11.md)，不是本轮新采集。

静态检查初次及中途曾因同文件原有 `cascade_invocations` info 返回exit1；最终将相邻调用与初始化改为等价cascade后严格检查通过，没有降低规则。最终完整591项是在这项样式修正之后重新运行的结果。

累计 `git diff --check 4738293...a92e3ec` 为 FAIL / 2：56处行尾空白仅在4份原样引入的 tray_manager Linux/macOS 缓存源码。已逐文件与本机 0.5.2 Pub cache hash 比较一致，未独立核验官方归档；遵循 `plugins/tray_manager/LOCAL-CHANGES.md` 的来源声明，不为了格式检查改写无关平台文件。本次测试/文档 diff 检查单独执行。

## 合并与未运行边界

必须等最终 PR head 的全部4项 quality-gate 成功，再普通 merge；保留两条长期分支，合并后将 main 的合并提交快进同步到 development。最终结果写入同一 PR，避免为记录自身合并SHA而再制造新的分支差异。

本轮 CI 不执行两个原生 UI 插件的 NativeCompile/Regression/Win32 测试；它们只有对应相同源码的历史本地证据。真实 Windows 窗口/UAC/SCM/TUN/路由、长时资源、真实账号/兑换/图片TLS、原生解码内部取消故障注入、macOS/Android设备均为 NOT RUN。测试工具编译不等同于生成可执行客户端发行包；本轮没有正式发行、部署、后台配置或消费操作。

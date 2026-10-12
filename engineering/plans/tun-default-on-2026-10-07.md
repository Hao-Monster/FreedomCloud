# Windows TUN 默认开启并尊重已保存偏好（2026-10-07）

状态：源码与自动化完成，本地提交 `b64e0d5`（分支 `feature/tun-default-on`，基线 `development@8089f66cdb0d93dd9d2591b6aaed2e0035a5f687`）。系统运行验收 NOT RUN。未推送、未建 PR。

## 用户决定

- A2：全新安装 TUN 默认开启；保存为关闭的选择不被覆盖。修订 `b2cccee` 中“不受保存的 TUN 关闭值阻断”的策略。
- B2：用户授权本任务在 `feature/tun-default-on` 上工作，作为单一开发分支规则的一次性例外。
- C1：仅构建与自动化验证；真实 UAC/网卡/路由/流量/退出清理等待隔离 VM。

## 行为

| 保存的 `tun.enable` | Windows 完整启动 |
|---|---|
| 无保存配置（全新安装） | 模型默认 `Tun.enable=true`（`clash_config.dart`，生成代码一致）→ 代理 + TUN 完整启动，按需一次授权 |
| `true` | 同上（`b2cccee` 原流程不变） |
| `false` | 只启动或接管代理（`startProxyWithoutTun`：`_initCore` → 已运行则只读接管，否则 `updateStatus(true)`），不请求权限、不改写偏好 |

- 启动失败（权限拒绝、配置/listener 失败等）：保存偏好保持 `true`，开关按实际观测显示关闭并给出原因；下次启动或点开关重试。不崩溃，代理及其他功能可用。
- 本会话手动关闭 TUN 写入 `false`，此后启动尊重该选择。
- 订阅只同步 `stack`，`state.dart` 以补丁值覆盖配置的 `tun.enable`；未发现订阅/覆写强制关闭 TUN 的路径。
- 老用户：配置 JSON 显式保存了 `enable`，升级后按原值执行。历史默认值为关闭且从未开启过的老用户仍保持关闭，需手动开启一次。
- 日志：`startup: saved TUN preference is on/off ...`、`startup: TUN observed=<state>[, failure=<code> ...]`、`startup: proxy start failed: ...`，经 `commonPrint` 写入文件日志与应用日志。

## 配置兼容性（只读核对，未改）

- `stack` 默认 `mixed`；桌面 `getRealTun` 强制 `auto-route=true`、清空 `route-address`；`dns-hijack` 默认 `any:53`；未设置 `strict-route`（Mihomo 默认 false）。
- Wintun：仓库源码无独立 `wintun.dll` 引用，依赖 Mihomo/sing-tun 内置实现；缺失场景未在本轮验证。
- 系统代理与 TUN 并存、分流模式与 DNS、退出后网卡/路由/系统代理清理：沿用既有实现，需 VM 验收。

## 自动化验证（本机 Flutter 3.47.4 stable，`E:\flutter\bin`）

| 命令 | 结果 |
|---|---|
| `flutter test test/clash/windows_startup_controller_test.dart` | 24 PASS / 0 FAIL |
| `flutter test`（全量） | 366 PASS / 0 FAIL |
| `flutter analyze` 三个改动文件 | exit 0；0 error / 0 warning；74 info 均不在改动行 |
| Go Core / Agent / Helper、`flutter build windows` | NOT RUN（本次未改 Go/原生代码，未产出新包） |

## 系统验收（全部 NOT RUN，需隔离 VM）

| ID | 场景 | 预期 |
|---|---|---|
| TD01 | 清空配置首次启动 | 开关为开；一次 UAC 后出现 FlClashX 网卡，流量可通 |
| TD02 | 保存 TUN=on 启动 | 同上；已运行匹配实例只接管 |
| TD03 | 保存 TUN=off 启动 | 仅代理运行；无 UAC；开关为关；偏好不变 |
| TD04 | 首启取消 UAC | 不崩溃；开关关并提示权限原因；代理等功能可用；点开关可重试 |
| TD05 | 退出应用 | 无残留网卡、路由、系统代理 |
| TD06 | 旧版本配置升级 | 保存值不被改写 |

## 回退

用后续 revert 提交回退 `b64e0d5`，不改写历史。

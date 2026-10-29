# Windows TUN 修复预览：构建与交付

日期：2026-10-14（America/Los_Angeles）。本轮按用户要求正常推送全部已提交开发成果、重建预览，由用户自行启动和测试；观察方不启动候选客户端、不切换代理/TUN、不安装服务。

## 来源与交付

- 源码：`development@fb6f5d43e204b1cc47278b8916ecae2ebc1dcccf`；tree `95cfbed5ea981018da8c65c11d26299ffcb7c6d1`。
- 从自有远端 `f08fedb` 起的 9 个提交已正常推送到 `Hao-Monster/FreedomCloud:development`，远端 SHA 回读一致。未更改 main、未创建 PR/tag/release。
- tracked/index 干净后通过 Git archive 构建；原 coverage、原生 QA/probes、stash、47 个历史工作树均保留，未将它们混入提交或包。
- [预览 ZIP](../../dist/FreedomCloud-windows-amd64-tunfix-fb6f5d43e204.zip)：**153,552,555 bytes**，73 文件。
- SHA256：`4c70e5cba8d9afb1b13de47fcf674232a82318c5070b88295040cd7096393055`；[校验文件](../../dist/FreedomCloud-windows-amd64-tunfix-fb6f5d43e204.zip.sha256)。
- 已准备并逐文件校验的解压目录：`dist/FreedomCloud-windows-amd64-tunfix-fb6f5d43e204`。旧 `resourcefix-485abf4d2e86` 与其他旧包保留。
- 本报告及台账属于打包后的文档提交，不改变包内固定源码 SHA。

## 构建环境、命令与证据

构建根：`E:\Temp\flclashx-tun-preview-20261014-fb6f5d4`。使用已审查的历史构建工具副本，仅修改工作/输出路径、tunfix 名称及本轮 README，没有放宽来源、绑定、防覆盖或产物校验。

```powershell
& 'E:\Temp\flclashx-tun-preview-tools-20261014-fb6f5d4\Build-Remediation.ps1' -ExpectedSha 'fb6f5d43e204b1cc47278b8916ecae2ebc1dcccf'
```

- 00:04:30–00:16:01，整体 exit 0。源码 archive SHA256：`c46c40b2f2836e40956d34feb337c1755a137386b7c9917a3a49644a569eff93`。
- Flutter 3.47.4 / Dart 3.13.3、Go 1.25.13、Rust 1.98.1、MSVC 14.44.35207、SDK 10.0.26100.0、经 manifest/hash 校验的 ATL 14.51.36237。
- 本机 Flutter/Go 与 CI 的 3.41.7/1.26.0 不同，未升级依赖或改锁文件。CI 对包对应源码另行通过。
- 普通 Windows Core 按现有 `setup.dart` 使用 `CGO_ENABLED=0`、`with_gvisor` 和固定 Mihomo v1.19.32 overlay。之前审查进程中的 CGO=1 编译失败不被标为修复；本次生产构建模式和目标测试不使用它，race 由 Linux CI 验证。
- Core、Agent、Helper、Dart AOT、runner 和原生插件均重新编译。Flutter engine、QuickJS、CRT 和 EnableLoopback 为核验来源的预置输入，不声称全部第三方二进制从源码重编。

| 阶段 | 结果 / exit | 秒 |
|---|---|---:|
| Git archive | PASS / 0 | 7.12 |
| offline pub get | PASS / 0 | 130.47 |
| Core + Agent + Helper | PASS / 0 | 237.76 |
| Flutter config-only | 已知 VS 发现失败 / 1 | 4.74 |
| CMake configure | PASS / 0 | 7.23 |
| Flutter AOT | PASS / 0 | 107.79 |
| Windows runner / 原生插件 | PASS / 0 | 60.41 |
| Bundle install | PASS / 0 | 1.72 |
| tray imports | PASS / 0 | 0.28 |
| 包元数据 / checksums / ZIP | PASS / 0 | 14.75 |
| ZIP roundtrip、交付目录逐文件核验 | PASS | 未单独计时 |
| 非构建作者独立产物审计 | PASS / 0，8/8组 | 6.71 |

config-only 唯一错误仍是 `Unable to find suitable Visual Studio toolchain`；随后用已核验的 CMake/Ninja/MSVC 完成真实编译，没有忽略其他构建失败。保留 strict-broker 依赖既有 dead-code 警告和 `/W3` 被 `/W4` 覆盖提示。

## 验证矩阵

对应源码的 [quality-gate 38525761829](https://github.com/Hao-Monster/FreedomCloud/actions/runs/38525761829) 四项全部成功。

| 风险 / 验收点 | 层级与实际命令 | 结果 |
|---|---|---|
| TUN 状态、生命周期及受影响 Dart 逻辑 | CI Linux `flutter test`，Flutter 3.41.7 | PASS：609 通过 / 0 失败 / 1 平台跳过 |
| 被跳过的 Windows 修复命令测试 | 本机 `flutter test --no-pub --reporter expanded test/common/windows_service_command_test.dart` | PASS / exit 0：11 通过 / 0 失败 / 0 跳过，测试体约 2 秒 |
| 包模式对应 Core 逻辑 | 本机 CGO=0，`go test -modfile=<review>/go.mod -overlay=<review>/mihomo-overlay.json -tags=with_gvisor -json ./...` | PASS / exit 0：91 测试（含子用例）/ 0 失败 / 0 跳过；core 3.652 秒、overlay 工具 0.392 秒 |
| Linux Core 普通/gVisor 与 listener/controller/URLTest race | CI `Core Go tests`，按 quality-gate 命令 | PASS |
| Windows Core / Agent / Helper 合同 | CI `Windows Core and service tests`，按 quality-gate 命令 | PASS；Agent 83 / Helper 48，均 0 失败 / 0 ignored |
| M3 清单与证据工具 | CI `M3 package integrity checks` | PASS；其中 strict test validation 68 场景，无安装/驱动/网络操作 |
| 精确源码、四组件绑定、包内容 | 独立 `audit_portable_artifact.py` | PASS / exit 0：8/8 组 |
| 本机真实启动、权限、开关及偏好恢复 | 用户启动新包后验收 | NOT RUN：交付时未启动候选程序 |
| 切网、休眠、慢关闭、网卡丢失、长时稳定性 | 用户普通使用 / 获授权隔离 VM | NOT RUN；不在工作站故障注入 |

CI 的唯一 skip 是 Windows-only `repair still copies binaries when its directories already exist`，原因为 Linux 缺少 cmd.exe；本机补跑已覆盖。该测试只操作临时文本“二进制”和专用不存在服务名，不操作现役 FlClashHelperService。

本轮没有产品修改，没有新建 Red 阶段；前序修复的 Red→Green 留在原记录。本轮未采集覆盖率，不能将 CI 或静态审计视为实机稳定性验收。

## 组件与产物审计

| 组件 | SHA256 |
|---|---|
| FlClashCore.exe | `0b3a4d3a0d082af6dd2f0c41e27819b6a9c6753ed41d273763ef4886a9605a81` |
| FlClashAgent.exe | `6e9e7f4999f2e3bb5aab1615cd167ebd89ee0fc5b4db1ba599f9abc90d621864` |
| FlClashHelperService.exe | `21a37bc6a901cc7a4cbaeb4fc4c06242c8e7617095fca10ada6679a9be8ab67d` |
| FlClashX.exe | `e865c56c2fd21e7ba25798b555a1263a26dd85cfbec6e5e0afb53a3c50edfec5` |
| data/app.so | `a2935238ba37417a060d2d27b70060d83bc889759fa5ade87ecf298c518a67ee` |
| CORE-PATCH.json | `103b5faa5b6a5854b8c01d1f5db9cc0a4fe602023e2c82a047531464290b2891` |

- 948 Git blobs 对应精确源码：892 处归档 CRLF 转换，7 个 registrant 仅行尾变化，0 语义变化。
- 73 ZIP/bundle 文件、72 内部校验、32 组件描述、14 插件 / 111 原生输入一致；交付目录再次核验一致。
- Helper 编译字节中完整新 Core hash 出现 1 次；实际 Flutter 配置 `APP_ENV=pre`、`APP_VERSION=tunfix-fb6f5d43e204`、`CORE_VERSION=v1.19.32`、`CORE_SHA256` 均匹配。
- 固定 overlay 的 10 模板 / 10 映射 / 1015 有效模块文件一致；没有改模块缓存或浮动更新 Mihomo。
- 29 个 PE 为 x64；唯一 x86 是来源一致的 EnableLoopback。未夹带 strict 驱动/Broker、用户配置、订阅、私密日志、凭据或账号数据库。
- 独立证据：`E:\Temp\flclashx-tun-audit-20261014-fb6f5d4\audit.json`；SHA256 `1762af45b390de542577063a87ebe19aa11fa79a2e2ec6a4da946050825a7b53`。

## 用户测试与只读观察

1. 保留完整旧包与配置备份；从托盘“退出”旧客户端，而不只是关闭窗口，再由用户启动新目录中的 `FlClashX.exe`。不要同时运行两份，不混用 Core/Helper/Agent/DLL。必要 UAC 由用户处理。
2. 保存 TUN 开启后完整启动，检查 UI、网卡与实际联网一致；手动关闭后等待至少 15 秒并隐藏/恢复窗口，确认没有自行重开或重复提权。
3. 再次开启，重复开关 3 次；另测保存关闭偏好后完整重启应只启代理、不启 TUN。记录异常提示与操作时间。
4. 正常使用 10–15 分钟，观察状态回跳、Core 重启和错误日志。切网/休眠等按用户测试安排；不要删除网卡、强杀 Core 或制造驱动/SCM 故障。
5. 回退时退出新包、启动保留的完整旧包；不删除用户数据。免安装包共享用户配置，必要的服务版本同步仍由应用/用户授权流程完成。

观察只读进程 PID/启动时间、可访问映像/AOT/hash、服务配置与已安装文件、网卡状态、UI/Agent/Helper 脱敏日志摘要。禁止连接 Agent IPC（可能挤掉 UI session），不启动/停止进程或服务，不改代理/TUN/路由/防火墙，不读取凭据。

交付前基线确认仍是 `resourcefix-485abf4d2e86`、FlClashX 网卡 Up；不是新包运行证据。受进程权限限制，Helper/Core 运行映像路径及 USER/GDI 可能不可读，必须记录 unavailable，不能靠磁盘文件 hash 假定运行进程已经升级。网卡 Up 也不等于流量已通过验证。日志时间需要区分 Helper Unix 毫秒 UTC 与 UI 无时区文本，滑动尾部关键词计数不等于新增错误或真实重启次数。

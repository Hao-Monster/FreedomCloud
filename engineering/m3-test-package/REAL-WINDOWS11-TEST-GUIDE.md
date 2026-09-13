# M3 Windows 11 真机/隔离机验收操作稿

这份文档只适用于已经通过受信任签名的 M3 qualification bundle。它不是
开发机上的代理测试说明，也不会把本地编译、测试证书或静态分析结果当成
严格代理已经可用。

## 0. 测试边界和前置条件

1. 优先使用可恢复快照的 Windows 11 x64 虚拟机。使用实体机时，必须是专用
   测试机，并在 preflight 命令中显式加入 `-AllowPhysicalTestHost`。不要在
   开发机上启用测试签名、安装驱动、创建 WFP 对象或改变默认路由。
2. 测试包必须同时包含以下文件：

   - `FlClashStrictCallout.sys`
   - `FlClashStrictBroker.exe`
   - `FlClashAgent.exe`
   - `FlClashCore.exe`
   - `strict-package-manifest.json`
   - `SHA256SUMS.txt`

   驱动、Broker、Agent 和 Core 必须显示受信任的 Authenticode 状态。测试证书
   或仅本地信任的证书不满足 M3 发布门禁。
3. 记录测试机的 Windows 版本/构建、Secure Boot、HVCI、CPU/内存、网卡和
   测试包版本。保留开始测试前的快照；失败时先停测并恢复快照，不要连续在
   未知状态上重装驱动。

## 1. 包完整性和 preflight

将 ZIP 解压到普通目录，例如 `D:\FlClashX-M3-<version>`，不要放在符号链接、
网络盘或会自动同步的目录。使用管理员 PowerShell 7（`pwsh`）执行：

```powershell
Set-Location 'D:\FlClashX-M3-<version>'
pwsh -NoProfile -File '.\engineering\m3-test-package\Invoke-M3VmPreflight.ps1' `
  -PackageDirectory (Get-Location).Path `
  -EvidenceDirectory 'D:\FlClashX-M3-evidence\preflight'
```

如果脚本与包一起交付在包根目录，则把脚本路径改为包内实际路径。实体专用
测试机才允许使用：

```powershell
pwsh -NoProfile -File '.\Invoke-M3VmPreflight.ps1' `
  -PackageDirectory (Get-Location).Path `
  -EvidenceDirectory 'D:\FlClashX-M3-evidence\preflight' `
  -AllowPhysicalTestHost
```

必须得到 `M3-PREFLIGHT.json`，其中每个包文件的 SHA-256 与
`SHA256SUMS.txt` 一致，四个可执行/驱动文件的签名状态均为 `Valid`，并且
`driverBuildId` 与 manifest、驱动和 Broker 的构建标识一致。任一项失败都标记
为 **FAIL**，不进入严格代理测试。

> Windows 11 自带的 Windows PowerShell 5.1 不应被当作脚本兼容性保证。当前
> 证据脚本使用较新的 `System.IO.Path` API；有 `pwsh` 时优先使用 PowerShell 7。
> 如果机器只有 5.1，不要修改脚本后继续测试，应保留 preflight 未运行证据并
> 手工执行下方日志收集或安装 PowerShell 7 到测试机。

## 2. 严格代理业务验收顺序

每个步骤记录本地时间、操作、目标进程和 UI/Agent/Broker 状态；只用测试域名、
测试节点和无凭据的配置。严格模式的状态只有在完整 capability proof 到齐后
才允许显示 `armed`。

1. **初始状态**：不选择严格应用，确认普通 Mihomo 域名/IP 规则可用；记录
   `FlClashX`、`FlClashAgent`、`FlClashCore`、`FlClashStrictBroker` 和服务
   状态。
2. **应用身份**：选择 Edge 和一个 Electron 应用，检查显示名称、图标、规范化
   路径及其实际联网的 helper/renderer 子进程。路径或签名身份不匹配时必须拒绝，
   不能靠目录通配符放行。
3. **forceProxy**：为 Edge 设置 `forceProxy` 和测试代理组，提交后确认状态为
   `armed`；访问测试站点并在连接页观察按进程聚合、速率和详情。若 Broker、Core、
   DNS、驱动或 UDP/QUIC 能力任一项没有证明，状态应为 `blocking`，选中应用的
   流量必须失败关闭，而不是直接连接。
4. **block**：把 Electron 应用改为 `block`，确认 TCP/UDP 请求失败；同时用未
   选择的应用验证原有域名/IP 规则未改变。
5. **TCP**：分别验证 IPv4、IPv6、短连接、长连接、并发连接和代理节点切换。
6. **UDP**：验证 connected `connect`/`send`、未连接 `sendto`、同一 socket 交替
   两个 IPv4/IPv6 目的地。任何一个路径没有完整证明时，必须保持 `blocking`；
   不能把“页面能打开”当作 UDP 严格能力通过。
7. **DNS/QUIC/HTTP3**：分别验证 DNS UDP、DNS TCP fallback、QUIC/HTTP3。未提供
   对应 capability 时，应记录为未支持/阻断，而不是推断成功。
8. **故障注入**：在 prepare、commit、active UDP、lease renewal 和 shutdown
   阶段分别停止或结束 Broker、Agent、Core。选中应用必须阻断；未选择应用仍遵循
   普通规则。重启后只能在重新认证、重新枚举过滤器和 capability proof 完整后
   从 `blocking` 回到 `armed`。
9. **系统事件**：执行睡眠/恢复、网卡切换、Core 重启、服务重启和用户界面关闭。
   界面关闭不能让严格策略失效；“停止代理”和“完全退出”必须有可区分结果。
10. **卸载/回滚**：禁用并卸载后，检查没有残留驱动、服务、WFP provider/sublayer、
    filter、路由、TUN、DNS 或 Broker 进程；恢复快照后重复检查服务和网络状态。

## 3. 性能和稳定性记录

使用固定的 1、128、512、1,024 条 active flows，分别执行小包、最大包、突发和
持续 TCP/UDP 负载。记录吞吐、丢包、CPU、p50/p95/p99 延迟、IOCTL 次数、进程
working set/private bytes、句柄、线程和驱动 nonpaged-pool。至少持续 30 分钟，
观察流量结束后的回收是否稳定；单次启动的空闲内存不能代替此项证据。

超出连接、关联、flow 或 in-flight injection 上限时，必须看到有界拒绝/阻断，
不能出现无界内存增长或物理网络 fallback。

## 4. 日志和证据收集

应用可能没有创建所有目录；以实际存在的文件为准，不要为了“补目录”而手工
写入日志。默认日志位置如下：

| 类别 | 默认位置 |
|---|---|
| Flutter/UI | `%APPDATA%\com.follow\clashx\logs` |
| UI 备用目录 | `%LOCALAPPDATA%\FlClashX\logs` |
| Agent/应用公共日志 | `%ProgramData%\FlClashX\logs` |
| Strict Broker | `%ProgramData%\FlClashX.StrictBroker\logs` |
| Helper 服务 | `%ProgramFiles%\FlClashX Service\logs` |
| SCM 事件 | Windows Event Viewer → Windows Logs → System → Service Control Manager |
| 驱动内核诊断 | DebugView/ETW capture；驱动不会自行写普通文本文件 |

允许收集的日志名包括 `FlClashX_YYYY-MM-DD*.log`、
`connections_diagnostic*.log`、`FlClashAgent*.log`、`FlClashHelperService*.log`
和 `FlClashStrictBroker*.log`。不要提交配置 YAML、订阅地址、token、认证头、
完整主机/IP 历史、用户名、进程命令行或数据包内容。

完成业务和性能步骤后，在证据目录执行（优先 PowerShell 7）：

```powershell
pwsh -NoProfile -File '.\Collect-M3VmEvidence.ps1' `
  -OutputDirectory 'D:\FlClashX-M3-evidence\run-<date>' `
  -DurationMinutes 30 `
  -SampleIntervalSeconds 5
```

如果收集脚本因 PowerShell 版本失败，不要删除或修改失败输出；把错误文本、
上述五个日志目录中允许的文件、服务状态和事件导出一并交付，标记为
`collector NOT RUN`。手工服务/进程信息可用：

```powershell
Get-Service FlClashStrictCallout,FlClashStrictBroker,FlClashHelperService -ErrorAction SilentlyContinue
Get-Process FlClashX,FlClashAgent,FlClashCore,FlClashStrictBroker,FlClashHelperService -ErrorAction SilentlyContinue |
  Select-Object Name,Id,WorkingSet64,PrivateMemorySize64,HandleCount,Threads
Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Service Control Manager'; StartTime=(Get-Date).AddHours(-2)} |
  Select-Object TimeCreated,Id,LevelDisplayName,Message
```

在恢复快照前，把 `M3-PREFLIGHT.json`、`log-inventory.json`、
`system-summary.json`、`process-samples.csv`、`service-control-events.txt`、
`driver-verifier.txt`、驱动 DebugView/ETW 文件以及测试结果表一起压缩。压缩前
逐个检查文件内容，确认没有敏感配置。使用证据目录内的 `SHA256SUMS.txt` 校验
传输完整性。

## 5. 判定规则

- **PASS**：包签名/哈希通过；严格策略真实生效；失败路径阻断；未选择应用和
  Zashboard/普通规则未回归；卸载无残留；性能和 30 分钟资源趋势满足项目门禁。
- **FAIL**：出现任意静默直连、未授权应用被捕获、状态虚报 `armed`、签名或构建
  标识不匹配、驱动/过滤器卸载不完整、崩溃/Verifier/bugcheck、无界内存增长。
- **NOT RUN**：缺少受信任签名、WDK/HLK 结果、真实驱动执行、QUIC/DNS 证据、
  PowerShell 7 收集环境或目标应用；不得用静态分析和模拟结果替代。

测试结束后请提供：测试包版本和 SHA-256、`M3-PREFLIGHT.json`、上述证据目录、
每个步骤的 PASS/FAIL/NOT RUN 表及失败发生前后的时间点。不要只提供截图。

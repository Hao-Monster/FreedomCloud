# R3 健康检查缓存修复与隔离验证

日期：2026-10-09（Asia/Singapore）。基线：`development@13b0ea0`。本报告对应本轮工作区 `core/hub.go` 及两个新增 forwarder 测试文件；不代表现役进程已更新。

## 实现与边界

- `healthCheckSweepMu` 串行快照、提交和发送；读取当前配置/provider 集合时使用 `runLock`，读取历史与发消息时不持 `runLock` 或 `healthCheckMu`。
- reset/stop 递增 generation 并清空缓存；提交在状态锁内核对 generation，丢弃已经失效的完整快照。stop 在没有定时 worker 时也释放状态。
- 每轮用当前非空历史构造结构化 `(proxyName, testURL)` → `(UnixNano, delay)` map，并整体替换缓存。删除节点/URL、同名节点替换成无历史对象时不保留旧项；新 map 使旧 bucket 分配也可回收，不设置任意 live-key 硬上限。
- 定时 worker 的前台采样和后台 Touch 都传入所属 run 的 stopCh；停止与 timer 同时 ready 时，关闭的旧 run 不再访问 provider。显式前台 flush/屏幕恢复 Touch 保留原入口和语义。
- 去重契约、0→-1、provider Touch 节奏、现有流事件有界队列保持不变。已提交/入队的事件不追溯取消；generation 保护尚未提交的快照和缓存，不增加消息协议。

锁顺序：sweep → run → state（捕获）；sweep → state（提交）；reset 只取 state；stop 可取 channel → state，但不取 sweep。无 native callback/IPC 跨 run/state 锁调用。

修改仅在 `core/hub.go`、`core/healthcheck_forwarder_test.go`、`core/healthcheck_forwarder_output_test.go`。没有修改 common.go、依赖版本、模块缓存、现役文件或网络配置。

## 测试矩阵

所有 fixture 使用内存 proxy/provider、受控 channel 或 `net.Pipe`/真实 `coreOutput` 内存队列。没有连接现役 Core/Agent，也没有创建代理 listener、TUN、SCM 或健康检查网络请求。

| ID | 用例/可观察结果 | 结果 |
|---|---|---|
| H01/H09 | `OutputDedupAndLatestSampleContract`：默认及 extra 最新样本、重复不发、时间/延迟变化、0→-1、reset 后重发 | PASS |
| H02/H03 | `CacheTracksLiveHistories`：A,B→B,C，增加/删除 URL、同名空历史替换、空目录；`OutputReturningNodePublishesSameSample`：相同历史重加入仍发出 | PASS |
| H04 | `CacheProviderUpdatesRemainBounded`：同一 provider 原地 2000 批×8节点×3历史，每批严格 24 项，最后 0 项，Touch 恰 2001 次 | PASS |
| H05 | `CacheLargeDirectoryIsNotTruncated`：9000→1→0；`OutputLargeDirectoryDoesNotRepeat`：9000 活节点第二轮零重复消息 | PASS |
| H06 | `CacheResetRejectsInflightSnapshot`：闸门控制旧读与新代 flush；`OutputResetDiscardsInflightSnapshot`：新代尚未提交前旧快照零消息、缓存仍空，随后新节点正常发出 | PASS |
| H07 | `OutputConcurrentFlushesEmitOnce`：64 并发 flush 只发一次；`CacheConcurrentResetsAndFlushes`：32×20 flush 与20次 reset，最后状态正确 | PASS；后者含 race |
| H08 | `CacheStopClearsWithoutWorker`、`CacheStopRejectsInflightSnapshot`、`StoppedRunDoesNotTouchOrRepopulate`：无 worker 停止清空、在途失效、已关闭 run 不采样/不 Touch | PASS |
| H10 | `OutputKeyPartsCannotCollide`：原字符串连接相同的两个结构化 node/URL 独立发出和去重 | PASS |
| H11 | `CacheNoConfigDoesNotTouchProvider`：无配置时不 Touch/不填充缓存；关闭 run 后显式 Touch 仍保留正常行为 | PASS |

测试名称均以前缀 `TestHealthCheck` 开头。新测试共15项，未加 skip/only，也未弱化原测试。

## 命令与执行结果

环境：Windows amd64，Go **1.25.13**；CI 配置为1.26.0，本机未更换工具链。普通/with_gvisor 使用 `CGO_ENABLED=0`；race 使用 `CGO_ENABLED=1`、`CC=C:\msys64\ucrt64\bin\gcc.exe`。所有 Go 命令从 `core` 目录执行。

证据目录：`C:\Users\冯飏\Documents\Codex\2026-10-09\resource-followup-184840`（下称 `$probe`）。时长使用 `go test -json` 的实际 package elapsed，不混同首次编译命令总耗时。

```powershell
go run ./tools/mihomo-overlay
$env:CGO_ENABLED='0'
go test '-modfile=.generated/go.mod' '-overlay=.generated/mihomo-overlay.json' -run '^TestHealthCheck' -count=1 -timeout=45s -json .
go test '-modfile=.generated/go.mod' '-overlay=.generated/mihomo-overlay.json' -count=1 -timeout=90s "-coverprofile=$probe\r3-core-final.cover" -json ./...
go test '-modfile=.generated/go.mod' '-overlay=.generated/mihomo-overlay.json' '-tags=with_gvisor' -count=1 -timeout=90s -json ./...
$env:CGO_ENABLED='1'
$env:CC='C:\msys64\ucrt64\bin\gcc.exe'
go test '-modfile=.generated/go.mod' '-overlay=.generated/mihomo-overlay.json' -race -run '^(TestHealthCheck|TestConfig|TestController)' -count=1 -timeout=90s -json .
go tool cover "-func=$probe\r3-core-final.cover"
$env:CGO_ENABLED='0'
go build '-modfile=.generated/go.mod' '-overlay=.generated/mihomo-overlay.json' '-tags=with_gvisor' -o "$probe\FlClashCore-r3-validation-WIP.exe" .
```

| 执行 | 状态/exit | PASS/FAIL/SKIP 测试数 | package时间 | 日志 |
|---|---|---|---|---|
| overlay 源 hash 校验及生成 | PASS / 0 | 非测试 | 未独立计时 | `r3-overlay.txt` |
| 旧实现目标 Red | 预期 FAIL / 1 | 3/8/0 | core 1.255s | `r3-red.jsonl` |
| 最终目标 Green | PASS / 0 | 15/0/0 | core 1.287s | `r3-green-final.jsonl` |
| 普通完整 Core + coverage | PASS / 0 | 90/0/0 | core 2.707s；tools 0.222s | `r3-core-full-final.jsonl` |
| with_gvisor 完整回归 | PASS / 0 | 90/0/0 | core 2.524s；tools 0.199s | `r3-gvisor-final.jsonl` |
| health/config/controller race | PASS / 0 | 22/0/0 | core 2.878s | `r3-race.jsonl` |
| 移除代际检查的临时 overlay mutation | 预期 FAIL / 1 | 0/1/0 | core 1.280s | `r3-generation-mutation.jsonl` |
| Windows amd64 with_gvisor 独立 Core 编译 | PASS / 0 | 非测试 | 未独立计时 | `r3-build.txt`、`r3-build-sha256.json` |
| `git diff --check -- core/hub.go` | PASS / 0 | 非测试 | 未独立计时 | 只有 Git LF/CRLF 提示，无 whitespace error |

`core/state` 没有测试，with_gvisor 的 package skip 不计为跳过用例。`!cgo` 输出测试不包含在 race 中，已由普通及 with_gvisor 完整套件执行；缓存/代际并发测试在 cgo race 中执行。

独立编译产物为工作区 WIP 验证文件，SHA256 `ad528cd05343eee59630c5cb1f74c1d4ab3375202fd77143d94f976ac95f50ac`；未启动、未与现役Helper混用、不是完整预览包。

## Red → Green 与断言强度

生产 hub.go 未修改时先执行11项可在旧入口运行的测试，8项按目标缺陷失败：节点更换后3项而非2项；provider第二批48项而非24项；9000缩1仍9000；reset旧代回填；stop无worker残留/在途回填；移除再加入被压制；字符串key碰撞丢消息。既有去重/消息契约、并发同样本去重、无配置行为3项通过。该 Red 不是缺函数或编译失败。

最终新用例还验证了关闭 run 的两条路径、大目录实际零重复输出及失效快照无旧消息。独立审查指出仅检查最终map可能被后来的正确新代覆盖，故补充了“新代尚未提交”的真实输出断言。

通过临时 overlay 仅将 generation 拒绝条件置为 false，该补充用例明确失败：`reset snapshot emitted stale delays ... Name:retired`。变异文件和 overlay 只存于 `$probe`，不改生产工作区或模块缓存；正常完整测试使用原固定 overlay。

实施中首次 Green 构建因移除字符串签名后遗留 `fmt` unused import 而失败，随后删除无用 import；失败记录为 `r3-initial-build-failure.jsonl`，不计为缺陷 Red。首次导出覆盖率函数表从仓库根目录误执行，报 `package core is not in std`；改从 core 目录执行成功。这两项均已修复，不是测试跳过或产品运行失败。

## 覆盖率、限制与待验收

- 标准 Go coverage 为 statement coverage：core package **42.9%**；包含 tools/state 的 profile 总计 **40.5%**。不将它写成行覆盖率或分支覆盖率；标准工具本轮未提供独立 line/branch 数字。
- 本次关键函数 `forwardHealthCheckDelaysForRun`、`collectLatestDelay`、`resetHealthCheckForwarderState`、`touchProvidersSafelyForRun` 为 **100% statements**；`stopHealthCheckForwarder` 为66.7%，未用真实 timer worker覆盖既有 channel非nil关闭分支。
- 后台定时循环真实时间调度、真实 provider下载/探测及跨配置端到端 IPC、Android设备、长时 RSS 资源曲线：**NOT RUN**。本轮通过直接生产入口和控制交错验证缓存/并发；不据此声称现役Windows或所有平台已经验收。
- 每轮缓存分配/时间复杂度为 O(本轮有历史的key及当前proxy数)。provider在本轮采样后更新时，旧项在下一轮有效 sweep 清理；不会修改原探测间隔。
- 不修改/重启现役程序、不改代理/TUN，不创建Git提交或推送。主负责人串行整合与提交。

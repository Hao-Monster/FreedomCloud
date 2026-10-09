# Core 资源与可靠性修复及验证证据

基线：`development@a52907c`。日期：2026-10-09（Asia/Singapore）。
范围：F01、F03 的 Go 侧、F05、F10 的 Go 侧、F15。Core 子代理负责 `core/**`，
其中 `retired_resource.go` 及其测试由主代理实现、Core 子代理接入 Android；
主代理负责统一台账、Git 与打包。保留原有未跟踪稿，不运行候选客户端、
真实代理、TUN、服务或生产配置。测试仅使用合成配置、内存连接和注入的应用边界。

## 实施任务

1. F01：统一完整 controller 配置构造，保留认证、TLS、CORS 及对应字段；关闭时
   不意外开启其他监听。检查固定 Mihomo 的异步重建 API，使用经校验的最小 overlay
   改进错误感知，避免无认证回退。测试覆盖实际重建调用边界和实际 HTTP handler。
2. F05：参数与完整候选解析成功前不修改全局配置、strict ingress、描述、测试 URL、
   健康检查状态。拒绝空/null/坏 JSON 与语义错误；成功后一次提交候选。只在成功应用
   后取消旧测速代；失败保留旧运行意图和元数据。测试注入 apply 边界，不创建真实监听。
3. F03：每个 Core 会话拥有有界输出、有限 write deadline 与明确关闭；业务锁内的
   stream 发送仅非阻塞入队。可靠响应发送失败终止会话，不伪装成功；关闭无需取得
   writer 锁。限制入口 action 并发，提供明确过载响应；net.Pipe 验证慢读及取消。
4. F10：创建 worker 前实施执行/排队预算，总 deadline 覆盖排队与测试；可选 request-id
   支持显式取消，同时保留旧请求兼容。配置、会话与 UI 生命周期取消旧任务，回调至多
   一次。与 Dart 子代理对齐取消协议与过载/取消反馈。
5. F15：用可测试的引用所有权组件管理 TUN handler 代际，在途调用持有租约；retire 后
   拒绝新调用，最后一次迟返触发一次 JNI 引用释放。保持停止等待有界，并暴露持续未归还
   代际计数。用纯 Go 合成回调测试，不声称 Android JNI 实机完成。

## 冻结测试矩阵

| 任务/风险 | 测试层级与场景 | 目标测试文件 | 预期 |
| --- | --- | --- | --- |
| F01 认证丢失 | 完整字段传递、setup/reload/update/关闭开启；真实 router 无/错/合法凭据 | `core/controller_config_test.go` 与 overlay route tests | 未授权401；合法成功；无字段丢失 |
| F01 重建失败 | 注入监听创建失败、保留/关闭边界、错误返回 | 同上 | 不返回假成功、不降级匿名 |
| F05 坏配置破坏旧状态 | 语法/语义/null/脚本产物坏规则；有效→失败→重试；无旧配置 | `core/config_transaction_test.go` | apply不调用且旧配置/元数据/意图不变 |
| F03 慢消费者 | net.Pipe不读、仅stream、可靠队列满、恢复读取、关闭、新会话 | `core/server_test.go` | 有限时间退出；可靠失败明确；goroutine收敛 |
| F03 入口洪峰 | 超并发、取消/关闭、输出失败 | 同上 | 执行与输出队列有界 |
| F10 排队超时 | 1000请求、槽满、总deadline、过载、取消/配置更换 | `core/delay_tasks_test.go` | 峰值有界；过期不执行；回调至多一次 |
| F15 JNI所有权 | 正常、迟返、永不归还、重复retire、快速多代、并发 | `core/retired_resource_test.go` | 不提前释放；迟返仅释放一次；停止有界 |

执行顺序：F01/F03/F05/F10 先新增保护性测试得到目标 Red，再实现并 Green；F15 的
旧 JNI 超时路径以代码证据确认，所有权组件新增后验证其迟后释放行为，未伪造旧组件 Red。
随后执行 Core 完整测试、with_gvisor、相关 race 与平台编译。固定依赖通过现有
生成器/overlay，禁止修改模块缓存。
真实监听/TLS socket、Android JNI/设备、TUN/路由及本机长时运行保留为 NOT RUN 或由主代理
在明确可恢复环境安排；不把纯逻辑测试等同于这些验收。

## 已实施

### F01：完整控制器配置与可感知重建

- `config_runtime.go` 统一传递 TCP/TLS/Unix/pipe 地址、routing mark、secret、TLS
  certificate/private key/client auth/ECH、DoH、debug、CORS 与 UIPath。固定 Mihomo
  `v1.19.32` 的 overlay 新增同步 `ReCreateServerChecked`，绑定失败返回错误；部分
  candidate 关闭后尝试恢复上一份完整配置，恢复失败也明确返回。
- 先验证 TLS，再替换监听。debug 路由同样受 secret 保护；Unix socket 权限为 0600，
  不删除占用路径的普通文件。TLS 保留上游 ALPN、GetCertificate、client auth 与 ECH
  配置。UIPath 在 router 创建时捕获，legacy setter 使用同一生命周期锁。
- 监听代际追踪已 accept 的连接；代际关闭同时终止已经 hijack 的 WebSocket。追踪层
  位于 TLS 包装内侧，保持 `*tls.Conn` 识别及 HTTP/2 行为。
- 与 Dart 协议已对齐：setup 使用完整 profile，不新增 `controller-enabled`；update
  中该字段为可选布尔值，省略保持当前开关，false 关闭全部有效监听但保留配置，true
  恢复完整配置。`external-controller` 仅更新地址，不隐式推断开关；TLS/pipe-only
  配置的 TCP 地址可为空。普通 Dart update 省略这两个字段。

### F03：Core IPC 有界输出和会话所有权

- 每连接独立 writer：256 帧、4 MiB 字节预算、单帧 1 MiB。stream 非阻塞入队，预留
  32 个响应槽；可靠响应入队上限 2 秒，写入 deadline 5 秒，失败关闭会话。
- close 直接关闭连接，不等待 writer 锁；admission gate 与 WaitGroup 保证关闭后
  sender、队列及字节计数收敛。入口限制 64 个普通 action，加 8 个取消/UI/停止控制槽。
- 异步响应绑定原会话，旧会话结果不能串入新连接；编码失败显式返回错误并归还 action
  槽或 JNI 回调。输入限制 1 MiB 并拒绝截断行。macOS 清理先 detach 再等业务锁。

### F05：候选配置验证与失败回滚

- 缺失/null/坏 JSON/尾随 JSON/语义错误直接返回；完整解析、strict 目标校验与控制器
  绑定成功之前不触碰配置应用边界。错误输入不再以默认配置覆盖有效配置。
- 元数据、描述、健康检查周期、测试 URL 和旧测速代取消，仅在成功提交后更新。
  删除额外 `go runtime.GC()`，避免与上游 ApplyConfig 的 GC 重复。
- post-apply strict 恢复失败时回滚旧配置与控制器。首次 setup 没有旧配置时，应用无
  监听/DNS/NTP/TUN 的 dormant 配置清理已应用的 candidate，关闭控制器并保持
  `currentConfig == nil`；该分支只用于失败后清理，不作为坏输入 fallback。
- 回滚时继续保持 stopped/Android 的 TUN 抑制。配置应用边界由测试注入，真实 OS
  监听与 TUN 回滚仍为 NOT RUN；上游 void ApplyConfig 内部失败不被包装为全局原子事务。

### F10：测速预算、取消与历史记录提交

- 创建 goroutine 前 admission：最多 150 个任务，50 个执行、100 个等待。1–60000 ms
  的总 deadline 覆盖排队、配置锁和 URLTest。配置锁支持 context 取消。
- request-id 支持 `cancelTestDelay`，Data 为 ID 字符串；过载、重复 ID、显式取消、
  deadline、配置换代、session close、UI inactive 均有明确 reason。重复 inactive
  不取消之后从隐藏托盘显式发起的测速。携带 ID 的任务只走关联响应，legacy 流消息保留。
- 上游 URLTest 默认会在 defer 写入共享 history/alive；新增经过固定 hash 校验的
  adapter overlay，对带 ID 的显式手工任务添加 history guard。取消/deadline 先到
  则不提交；提交先到则在 `delayTasksMu` 内写完 history/alive 并标记完成，之后的取消
  返回 false，完成结果不会再被后到的 deadline 改成取消。正常手工成功/失败仍保留
  history 与自动选组语义；自动 health check 和无 ID legacy 保持上游行为。

### F15：Android JNI 迟后释放

- callback 保持 immutable；atomic ready 控制新调用，context 取消 semaphore 排队，
  在途 JNI 持有独立 lease。retire 拒绝新 lease，最后一个迟返调用释放 callback 一次。
- close 保留 3 秒有界等待，超时记录 pending retired handlers；初始化失败统一 close
  与 retire，并清理 runTime。真正永不返回的 JNI 调用仍必须保留引用，不能安全强制 free。

## Red → Green

Red 使用固定 `-modfile=.generated/go.mod` 与
`-overlay=.generated/mihomo-overlay.json`；下表记录目标选择器和实际失败证据。
这些 Red 在旧实现/未启用目标补丁时运行，当前代码的 Green 命令见下一节。

| 任务 | Red 目标选择器 | 实际结果 | Green 对应证据 |
| --- | --- | --- | --- |
| F10 排队 | `-run '^TestDelayAdmission'` | FAIL；1000 请求保留 1000 goroutine，1 秒后 0/1000 完成；package 2.280s | 6 个 Core delay 测试通过，含实际 50 执行 + 100 排队取消及配置锁 deadline |
| F03 stream | `-run '^TestCoreStreamCannotWait'` | FAIL；net.Pipe 对端不读，1024 次发送在 100ms 内仍阻塞；package 1.416s | 8 个桌面 IPC 测试及 1 个独立 race 测试通过 |
| F05 配置 | `-run '^TestConfigInvalidCandidate'` | FAIL；坏配置触碰 6 个运行边界并覆盖旧 metadata；package 1.151s | 7 个配置事务测试通过，包含首次 post-apply 失败清理 |
| F01 控制器 | `-run '^TestControllerRuntime'` | FAIL；实际构造边界丢失认证/transport 字段；package 1.052s | 2 个 Core 边界测试、4 个真实 route lifecycle 测试通过 |
| F10 history | adapter 包 `-run '^TestFCXURLTest'` | 2 FAIL / 2 PASS；取消及 owner 拒绝仍污染 history；package 0.769s | 最终 5 个 adapter 测试通过，含迟返取消及 guard 覆盖完整提交 |
| F15 JNI | 不适用：旧代码没有独立 ownership helper | 旧 timeout 分支永久跳过释放的源码证据；未运行旧 JNI 实机 Red | 5 个 ownership 测试和 race 通过；Android 编译通过 |

## 最终执行记录

环境：Windows/amd64，Go `1.25.13`；项目 CI 固定 Go `1.26.0`。本次执行未替换本机
工具链，此差异在统一交付中保留。Mihomo 继续固定 `v1.19.32`，没有新增生产依赖。
生成器校验原文件 hash，再生成可审计 overlay/manifest；未改模块缓存。

工作目录：`E:\CodeWorkstation\FlClashX\core`。命令使用进程局部环境变量；测试只用
合成配置、注入 apply/listen 边界与 net.Pipe，没有启动真实客户端或 Core listener。
日志目录：`C:\Users\冯飏\Documents\Codex\2026-10-08\new-chat\work\core-audit-probe`。
以下 `$probe` 指该目录。

```powershell
go run ./tools/mihomo-overlay

$env:CGO_ENABLED='0'
go test '-modfile=.generated/go.mod' '-overlay=.generated/mihomo-overlay.json' -count=1 -timeout=90s "-coverprofile=$probe\remediation-core.cover" -json ./...
go test '-modfile=.generated/go.mod' '-overlay=.generated/mihomo-overlay.json' '-tags=with_gvisor' -count=1 -timeout=90s -json ./...

$env:CGO_ENABLED='1'
$env:CC='C:\msys64\ucrt64\bin\gcc.exe'
go test '-modfile=.generated/go.mod' '-overlay=.generated/mihomo-overlay.json' -race -run '^(TestConfig|TestController|TestDelay|TestRetired|TestFCXController|TestFCXTun|TestFCXURLTest)' -count=1 -timeout=90s -json . github.com/metacubex/mihomo/hub/route github.com/metacubex/mihomo/listener github.com/metacubex/mihomo/adapter
go test -race server_output.go server_output_race_test.go -count=1 -timeout=30s -v
go test retired_resource.go retired_resource_test.go -count=1 -timeout=30s -v
go test -race retired_resource.go retired_resource_test.go -count=1 -timeout=30s -v
```

| 执行 | 状态/退出码 | PASS / FAIL / SKIP（测试数） | 实际 package 时间 | 证据 |
| --- | --- | --- | --- | --- |
| overlay 生成 | PASS / 0 | 非测试 | 未单独采集 | 固定依赖及源 hash 校验成功 |
| 完整 Core + coverage | PASS / 0 | 75 / 0 / 0 | core 3.196s；tools 0.342s | `remediation-core.jsonl`、`remediation-core.cover` |
| with_gvisor 回归 | PASS / 0 | 75 / 0 / 0 | core 2.438s；tools 0.237s | `remediation-gvisor.jsonl` |
| Core + route/listener/adapter race | PASS / 0 | 38 / 0 / 0 | core 3.293s；route 1.658s；listener/adapter 各 1.442s | `remediation-race.jsonl` |
| 独立桌面 IPC race | PASS / 0 | 1 / 0 / 0 | 2.067s；用例 0.04s | 20 代 × 16 并发 sender/close，队列字节收敛 |
| ownership helper | PASS / 0 | 5 / 0 / 0 | 未保留独立 package 时间 | 迟返、多代、重复 retire、cleanup 完成顺序 |
| ownership helper race | PASS / 0 | 5 / 0 / 0 | 2.076s | 同上含 32 lease/8 retire × 100 代并发 |
| `git diff --check -- core` | PASS / 0 | 非测试 | 未单独采集 | 只有仓库 LF/CRLF 提示，无 whitespace 错误 |

`core/state` 没有测试文件，with_gvisor JSON 的 package skip 不计为跳过测试。
CGO race 构建不包含带 `!cgo` 的桌面 server，因此另外显式传入输出实现与独立 race 文件。
以上时间为 Go 输出的 package 时间，不将其宣称为完整构建墙钟时间。

### 覆盖率

- Core 包语句覆盖率 40.5%；overlay 工具包 25.5%；state 包 0.0%；合并 coverprofile
  的语句覆盖率 38.3%。Go 标准覆盖率不提供分支覆盖率，本次不声称已覆盖全部分支。
- F15 helper 全部函数 100%；history 提交 gate 与单任务取消 100%；测速入口 88.6%；
  IPC dispatch 94.7%，writeLoop 92.3%，readCoreLine 100%；setupConfig 76.2%，
  updateConfig 49.2%。真实 socket 启动、平台导出/JNI 路径未由这些数据覆盖。
- overlay 新增依赖文件的 coverage 采集尝试失败：Go 1.25 cover.exe 仍查找原路径
  `listener/tun_status_fcx.go`、`hub/route/controller_fcx.go`，忽略新增 overlay 文件。
  未通过改写生成源树或模块缓存绕过；这些依赖的正常测试及 race 已通过，依赖 coverage
  为 NOT AVAILABLE，不混入 Core 本体成功结果。

### 平台编译

Android 最终命令：

```powershell
$env:GOOS='android'
$env:GOARCH='arm64'
$env:CGO_ENABLED='1'
$env:CC='C:\Users\冯飏\AppData\Local\Android\Sdk\ndk\28.0.13004108\toolchains\llvm\prebuilt\windows-x86_64\bin\aarch64-linux-android21-clang.cmd'
go build '-modfile=.generated/go.mod' '-overlay=.generated/mihomo-overlay.json' '-tags=with_gvisor,cmfa' '-buildmode=c-shared' -o "$probe\libcore-remediation-android-arm64.so" .
```

PASS，退出码 0，最终产物 86,454,736 字节（14:28:29 +08:00）。此前一次漏 `cmfa`
标签的尝试因 `dns.UpdateSystemDNS` / `FlushCacheWithDefaultResolver` 未定义而失败；
按项目 setup.dart 的真实标签重跑成功。编译不等同于 Android JNI/设备验收。

Darwin 最终命令：

```powershell
$env:GOOS='darwin'
$env:GOARCH='arm64'
$env:CGO_ENABLED='0'
go build '-modfile=.generated/go.mod' '-overlay=.generated/mihomo-overlay.json' '-tags=with_gvisor' -o "$probe\core-remediation-darwin-arm64" .
```

PASS，退出码 0，最终产物 79,392,034 字节（14:28:32 +08:00）。两项交叉编译均未单独
采集完整墙钟时间、未运行产物。Windows Core 的正式 release 构建由主代理统一执行。

## 独立复核与剩余验收

- 只读独立复核确认 history guard 覆盖 alive 与两套 history 的整个提交，取消与提交
  在同一锁内决定先后；lookup 释放 runLock 后才调用 URLTest，guard 不产生反向锁链。
  派生 context 闭包只读取 Err，不递归 gate。该复核没有代替测试或声称额外运行测试。
- 主代理已复核 controller 升级连接关闭与 history gate，并增加 route/adapter 的 CI
  测试门禁。没有因本次局部验证声称完整仓库或 CI 已成功。
- NOT RUN：真实 controller TCP/TLS/Unix/pipe socket、TLS 握手/HTTP2 互操作、真实
  Windows/macOS TUN/路由和 strict rollback、Android JNI/设备、GUI 本机运行、长时间
  heap/goroutine/句柄稳定性。真实 route/WebSocket 逻辑仅通过注入 listener + net.Pipe
  验证；这些结果不等同于真实 OS 监听验收。
- JNI 永不归还时仍有未退休完成的资源；日志可观测，迟返会回收，无法安全强制释放。
- Core 子代理未提交、推送、打包或切换本机运行版本；主代理统一提交打包，用户验收本机。

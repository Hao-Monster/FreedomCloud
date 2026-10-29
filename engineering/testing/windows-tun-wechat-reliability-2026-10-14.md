# Windows TUN / 微信间歇断网：DoH 恢复修复验证

日期：2026-10-14。基线 `development@3c48432a77971a3e0c18a26ca1c55d1632df04e6`。需求与实现前矩阵见 [修复计划](../plans/windows-tun-wechat-reliability-2026-10-14.md)。本报告只证明所列代码与隔离测试，不是微信实机长期验收。

## 结论与范围

已修复两个独立重现的 Mihomo DoH 共享 client 恢复缺陷：调用者 deadline 到期不再触发共享连接重建；旧请求的迟到错误不再关闭或替换新代次。获取/重置缓存的锁内再次检查 context，避免排队期间过期后继续变更共享状态。真实传输超时、最多两次重试、QUIC 0-RTT token 更新、显式全局 `ResetConnection` 和 DNS ID 行为保留。

未改变 DNS/TLS 默认值、规则、节点、IPv6、TUN 栈、依赖版本或系统设置。上游固定 `v1.19.32` / commit `88dcbf7f1614a67c3b36b848ee3592dfa92ada36`；`dns/doh.go` 原始 SHA256 为 `1ba0170bed4aabf6b295471f9fddb03da20122d339526a97170dff537fbde57b`，修改前后模块缓存文件 hash 一致。生成器只替换三个方法，增加四模板；有效 overlay 为 12 映射、14 模板、1016 个有效模块文件。

现场证据支持“短暂双栈 DIRECT 拨号及 DNS 故障后恢复”，但尚不能将全部公网 IP 超时归因于这两个 DNS 缺陷。串行多 IP 首地址耗尽总 deadline 是另一个可重现韧性限制，缺少本次同族后备地址可达证据，不纳入本轮。没有凭网卡 Up、后续有流量或源码修复宣称微信业务恢复。

## Red → Green

原始无网络探针保存在 `E:\Temp\flclashx-wechat-dns-lifecycle-audit-20261014`。从 `core` 执行：

```powershell
$env:CGO_ENABLED='0'
go test '-modfile=.generated/go.mod' '-overlay=E:\Temp\flclashx-wechat-dns-lifecycle-audit-20261014\overlay.json' github.com/metacubex/mihomo/dns -run '^TestAuditDoH' -count=1 -timeout=30s -v
```

修复前 exit 1：3 PASS / 2 FAIL / 0 SKIP。失败均为 `closes=1, same_client=false`，分别证明到期请求误重置及旧错误销毁新 client；正常请求、主动 cancel、真实传输 timeout 对照通过。测试使用内存 transport，不发起 DNS 或实际 socket。

保留上述测试逐字不变，只将生产文件切换为修复 overlay，在新 `original-audit-on-fixed-overlay.json` 上执行相同选择器：exit 0，5 PASS / 0 FAIL / 0 SKIP，墙钟 7.702s。此为相同断言的 Green，不用编译失败冒充 Red。

## 执行环境与结果

- Windows amd64，Go 1.25.13；现有 CI 指定 Go 1.26.0，本轮未推送或触发 CI。
- 普通 Windows 生产构建同 `setup.dart` 使用 `CGO_ENABLED=0` 和 `with_gvisor`。
- Rust / Cargo 1.98.1。全部测试只操作隔离 fixture、临时文件、内存或自建 loopback 随机端口；没有连接现役 Agent IPC/Helper、启动产品、操作服务或修改网络。
- 下表区分顶层组与子例，不把父测试、子测试或重复轮次当成不同独立需求覆盖。

| 命令（`core` 工作目录，另有说明除外） | 结果 / exit | 通过 / 失败 / 跳过 | 墙钟 |
| --- | --- | --- | --- |
| `go test ./tools/mihomo-overlay -count=1 -json` | PASS / 0 | 6 组 + 6 子例 / 0 / 0 | 3.669s |
| `go run ./tools/mihomo-overlay` | PASS / 0 | 固定来源、14 模板及 manifest 生成 | 18.875s |
| `go test -modfile=.generated/go.mod -overlay=.generated/mihomo-overlay.json github.com/metacubex/mihomo/dns -run '^TestFCXDoH' -count=1 -timeout=30s -v` | PASS / 0 | 17 组 + 2 子例 / 0 / 0 | 包 5.807s |
| 上述 DNS 选择器，`-count=100 -shuffle=on -timeout=120s -json` | PASS / 0 | 1700 组 + 200 子例执行 / 0 / 0 | 9.444s |
| `go test -modfile=.generated/go.mod -overlay=.generated/mihomo-overlay.json ./... -count=1 -json` | PASS / 0 | 81 组 + 17 子例 / 0 / 0 | 36.301s |
| 上述 Core 命令增加 `-tags=with_gvisor` | PASS / 0 | 81 组 + 17 子例 / 0 / 0 | 30.192s |
| `go test -modfile=.generated/go.mod -overlay=.generated/mihomo-overlay.json -run '^TestFCX(Tun\|Controller\|URLTest)' github.com/metacubex/mihomo/listener github.com/metacubex/mihomo/hub/route github.com/metacubex/mihomo/adapter -count=1 -json` | PASS / 0 | 17 组 + 2 子例 / 0 / 0 | 14.056s |
| `go vet -modfile=.generated/go.mod -overlay=.generated/mihomo-overlay.json ./... github.com/metacubex/mihomo/dns` | PASS / 0 | 静态检查无诊断 | 39.771s |
| 仓库根：`cargo +1.98.1 test --locked --manifest-path services/agent/Cargo.toml` | PASS / 0 | 83 / 0 / 0 | 9.556s |
| 仓库根：`cargo +1.98.1 test --locked --features windows-service --manifest-path services/helper/Cargo.toml`，进程内 MSVC 环境 | PASS / 0 | 48 / 0 / 0 | 12.252s |
| `git diff --check` | PASS / 0 | 无 whitespace error | — |

主要原始记录：`E:\Temp\flclashx-tunwechat-validation-20261014-r1`，各命令日志与 `steps.jsonl` 保留。Agent/Helper 日志分别在 `E:\Temp\flclashx-tunwechat-services-20261014-agent-r1`、`...helper-r1`、`...helper-r2-msvc`。Rust 保留四项既有 strict-broker `dead_code` warning，未为通过测试修改源码/锁文件。

## 失败、环境限制与覆盖率

- Helper 首次构建 exit 101，13.072s，未进入测试：PATH 先命中 Cygwin 的 `link.exe`，报 `missing operand`。仅在重跑子进程将既有 MSVC/SDK 路径及 LIB/INCLUDE 置前，完整同套测试 48 项通过；主环境、系统/用户 PATH 未改。
- DNS `-race -count=20 -shuffle=on` 两次构建均 exit 1（14.512s / 7.185s），均未进入测试。显式 UCRT GCC 及仅调整子进程 PATH 仍不能链接；直接 `ld.exe --version` 返回 `-1073741515`（`0xC0000135`，依赖加载失败）。没有安装/修复工具或把此记为产品断言失败；race 动态验证 **NOT RUN**。已将 DNS 专项显式加入 Linux/race 和 Windows CI，不能拿旧 SHA 的 CI 代替新修复。
- 原 `-coverprofile` + overlay 尝试 exit 1（10.699s），编译器看到原始 `resetClient(ctx,error)` 签名，与补丁测试三参数调用不符。独立 `-x` 复核确认 Go 1.25 `cover.exe` 对原始 source-tree 文件插桩，而测试取自 overlay。普通测试/生产构建不使用该插桩路径。
- 隔离 effective-source 覆盖率测量 PASS：逐字复制并机械应用 overlay 后，1016 文件逐 hash 与 manifest 完全一致，聚合 hash 为 `8accf3ce58e1c9593541208294187e413a1fae34c04df0c681a65461be72bd94`。在独立 modfile 指向该副本、不带 overlay 的同一 DNS 测试中，17 组 + 2 子例通过，exit 0，墙钟 22.260s / 包 0.855s；测试前后源 manifest、overlay、12 产物、mod/sum 与副本 hash 未变。证据：`E:\Temp\fcx-doh-coverage-audit-20261014-211444-6dd2faf94b7e4a4cab9277a4061706a2`。
- 三个替换方法的**语句**覆盖：`ExchangeContext` 22/26（84.6%），`resetClient` 15/17（88.2%），`getClient` 14/15（93.3%），合计 51/58（87.9%）。全 DNS 包的定向测试语句覆盖为 12.6%，不代表完整 DNS 测试。Go 标准工具不提供分支覆盖，也不将语句覆盖称为行覆盖。
- 未覆盖路径：ExchangeContext 中 reset 返回错误，以及显式 reset 与重试交错令 client=nil 后的懒建/失败；resetClient 入口即取消、closeClient 返回错误的 warning；getClient 原有 30 秒锁等待超时。没有为了覆盖率添加生产测试钩子、真实联网或长时 sleep；这些缺口保留披露。
- Flutter 源码未改，整套 Flutter 单测本轮 NOT RUN；预览仍须完整编译 UI、runner 与插件，不能复用旧 Core/Helper 混包。Linux/macOS/Android 实机和 Windows 真实 TUN/SCM、切网/休眠、长时微信业务验收均 NOT RUN。

## 独立审查与变异验证

独立只读复核未发现本轮新增的高置信阻塞问题。已核对：上游 hash、三方法 receiver/集合检查、显式 reset 不变、补丁与有效文件 manifest 完整、Windows 与 Linux/race CI 包选择器、请求取消和代次所有权。

在新的私有目录中变异生产补丁副本，不改仓库、共享 `.generated` 或模块缓存：

| 试验 | exit / 结果 | 精确证据 |
| --- | --- | --- |
| 未变异三个目标用例 | 0 / 3 PASS | 迟到错误、并发 peer、等锁取消均通过 |
| 删除 client 身份 guard | 1 / 2 个预期 FAIL | `same=false`，旧 client 被再次关闭 `old_closes=2`，新代次被覆盖；此变异的 `new_closes=0`，不能误写新 transport 被关闭 |
| 删除 resetClient 锁内 context 检查 | 1 / 1 个预期 FAIL | 等锁取消后仍返回 `err=<nil>` 并重置共享 client |

证据与命令：`E:\Temp\fcx-doh-mutation-audit-b1699021b2444ca58ee15f23093b36d0`。未变异副本 hash 与有效 overlay 一致，变异产物不参与构建。

## 发布与验收边界

用户授权本地修复、提交与独立新预览；未授权本轮推送、PR、合并或发布。新包必须从修复后的干净 tracked 提交完整编译 Core/Agent/Helper/UI，Helper 和 UI 绑定同一新 Core hash，独立审计后再交付。构建期间不改该源码提交；打包后文档另提交。

用户验收至少覆盖此前故障出现的运行时长，记录新包路径/版本、开始/异常/恢复时间及微信消息、图片、文件功能；若用户自行切换 TUN，记录各操作时间与效果，不能将干预后的恢复计为此前连续观察通过。不采集联系人、聊天内容、账号、凭据或订阅。完成真实测试后，只能依据证据表述在所记录的时长与场景内是否复现，不保证所有间歇故障已消除。

构建后补记：源码已固定为 `4e4a146513c90e18090fe87a7f9eeada501e5a71` 并完整重编 Windows 预览，独立产物审计 8/8 PASS；同名解压目录已逐文件校验。组件 hash、构建失败/回退路径、工具版本差异及用户自行换包验收见[交付报告](windows-tun-wechat-preview-2026-10-14.md)。本补记是后续文档，不改变包内源码；本轮未推送或运行候选。

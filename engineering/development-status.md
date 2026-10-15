# 开发、集成与预览台账

更新日期：2026-10-15。当前阶段是快速开发、快速迭代和部分功能预览。本文记录来源与验收边界；每次继续开发仍需核实实际 Git/PR/CI 状态，不能把历史报告视为当前通过证明。

## 跨配置节点总览 P1 隔离测速与界面层级重构排期（2026-10-15）

- 用户明确反馈当前总览中存在严重的视觉与逻辑重复（左侧选配置后右侧依然存在折叠卡片，活动配置嵌套展示代理组卡片与当前视图重复），并要求落地非活动配置节点的后台测速（P1 隔离测速）。
- 方案已由技术负责人完成详细工程设计，详见 [P1 隔离测速与界面层级重构工程书](plans/cross-profile-node-overview-p1-and-ui-refactor-2026-10-15.md)。
- 关键重构点：
  1. 彻底废除手风琴折叠（移除 `_expanded` 状态与外层折叠卡片）：左侧栏专注作为配置筛选器（“全部配置”及各配置），右侧为平铺节点列表直出；“全部配置”时由轻量吸顶标题分段，选中单个配置时仅直出该配置节点。
  2. 活动配置叶子节点扁平化：移除代理组嵌套与 `ProxyCard`，统一渲染为扁平节点行，绑定实时延迟与色彩；节点选择逻辑严格留在“当前配置”视图。
  3. P1 隔离测速：Go Core 新增 `catalogPrepare`、`catalogTestDelay`、`catalogRelease`，利用独立出站适配器在后台测速，不切换配置、不影响 TUN、不打断现有连接；Dart 协调器扩展 `scope` 统一并发调度。
- 任务拆解与提示词已整理完备，已向开发人员（Dev）派发执行。技术负责人负责代码审查与门禁质量把关。

## 跨配置节点总览 P0 推送与 Windows 预览（2026-10-15）

- 用户新授权推送、打包，由用户在本机测试，观察方只读看日志。`2074cce → f6dff78c762654af1f77adfa46eed697a1492626` 共 5 提交已正常推送自有 `freedomcloud/development`，远端 SHA 回读一致；未晋级 main、未 PR/tag/release。下方“仅本地”是上一阶段历史状态。
- 固定源 [CI 38713589918](https://github.com/Hao-Monster/FreedomCloud/actions/runs/38713589918) 4/4 success：Flutter 731 PASS/1 既有 Linux cmd.exe skip，Core Linux 默认/with_gvisor/四组 race、Windows Core 专项、Agent83/Helper48、M3 四脚本均通过。本机此前732项无skip结果保持为修复阶段证据。
- 从干净 tracked Git archive 完整新编并交付 `dist/FreedomCloud-windows-amd64-nodeoverview-f6dff78c7626.zip` 及同名完整解压目录；153,831,212 bytes，SHA256 `30793c99108b69fdd040253d7ea1dea4dd4dc618d870aa584080d33f0b3ffc46`。构建 r1 exit0、约345.44s；73文件/72checksum，独立静态审计8/8 PASS，Helper实际绑定Core hash、UI编译输入一致。普通未签名预览，无strict驱动/Broker，旧DoH包及原始草稿保留。
- 本轮没有产品源码改动；交付文档单独提交，不改变固定包源码。完整命令、工具差异、已知VS发现exit1与后续实际编译、测试矩阵、组件hash及用户验收见 [节点总览预览交付](testing/windows-node-overview-preview-2026-10-15.md)。
- 只读观察工具私有目录 `E:\Temp\flclashx-nodeoverview-monitor-20261015-f6dff78c7626`，21项合成测试PASS；09:45:54Z从15个日志EOF建立新基线，0读取错误/缺口，现役UI/Agent仍是旧DoH包。已启用本对话每5分钟心跳，关注node.health原因、UI异常、组件生命周期和DNS失败，仅读增量并脱敏计数。候选启动和操作由用户执行；打包方未启动候选、未改代理/TUN/节点/服务/配置。真实Windows接管、UI/IPC、网络与长时验收仍待用户，不以静态包或无错误日志代替。

## 跨配置节点总览 P0 评审修复（2026-10-15，仅本地）

- 来源：用户对 `c8fa0a3` 的复评明确该版不能按 P0 验收。修复起点 `development@5a38b1a`，fetch 后领先自有远端 3、落后 0，无开放 PR；最新远端 CI 仍只对应 `2074cce`。本轮沿用本地实施/测试/提交授权，不推送、不运行候选、不操作现役代理/TUN。
- 四项修复：控制流取消不覆盖健康结果；单坏节点仅自身显示无法识别；可见折叠配置与宽侧栏自动构建摘要；接管通过已有只读 `fcx://runtime` 与文件的可识别节点集合核对，匹配后可记录显式测速。先前“需新增只读协议”的判断已纠正。原始 Future 与可撤销归属令牌防止配置切换/同 ID 更新及删除重建的迟返串写；缺失 Core 接口时读取不构造单例。
- 同轮调整：范围入口回到工具栏、色带沿用现有色阶、活动来源只取可信运行目录；活动时间使用实际组级 URL，不串用默认 URL 历史。后续批次刷新读取不再撤销前一批未完成的校验。缓存内部 schema 2 迁移只保留 v1 成功值，旧负值均变未测（旧版错误码存在歧义）；无法恢复此前已被覆盖的好值。Go Core、Agent、Helper、协议和锁文件未变。
- 源码/测试已本地提交 `2ecb4ece674dd9668ac6cdde355f8088cdcca4c3`（`fix(proxies): address node overview P0 review findings`）。最终目标 130 PASS、全 Flutter 732 PASS/0 FAIL/0 SKIP、UI 行为 26 + 合成宽窄渲染 2 PASS且看图、Windows debug UI 资源编译 PASS。七个手写模块行覆盖 897/960（93.44%）、分支 321/370（86.76%）；全仓 analyze 0 error、11 既有 warning、851 info，exit 1，无新增 error/warning。独立审查发现的相关问题均已补修并回归。完整矩阵、命令、Red→Green、覆盖率及失败记录见 [P0 评审修复记录](testing/node-overview-p0-review-2026-10-15.md)。下方首轮计数保持为历史证据，不代表复评通过。
- 交付边界：未推送、未 PR/合并、未部署、未生成或启动可执行候选；真实 Windows 接管/IPC/QuickJS、代理/TUN、性能与长时验收 NOT RUN。P1/P2 未实施，无请求归属广播及无法证明运行归属时不写新历史。原 coverage/QA/probes 5 文件 hash、stash、历史工作树保持原状。

## 跨配置节点总览 P0（2026-10-15，首轮历史记录，已被上方复评修复替代）

- 来源：[工程书](plans/cross-profile-node-overview-2026-10-15.md) 设计基线 `2074cce`，实际开工 `development@c7166fe`（仅增加工程书/台账，fetch 后领先自有远端 1、落后 0，无开放 PR）。用户明确授权从 P0 实施、测试和本地提交；不推送、不运行候选包、不影响现役代理/TUN。
- 源码与测试已本地提交 `c8fa0a3f55386778a4d1f17c7ce4845a03980449`（`feat(proxies): add cross-profile node overview P0`）。实现脱敏目录/稳定键、受限并发与 LRU、跨会话健康文件、按请求捕获归属、宽窄总览/搜索/排序/筛选/异常卡、活动 ProxyCard 复用和四语言文案。`FCX_NODE_OVERVIEW=false` 可关闭；当前配置仍默认，少于两个配置隐藏范围入口。Core/Agent/Helper 未改动。
- 验证：新增目标 64 PASS，全 Flutter 674 PASS/0 FAIL/0 SKIP；合成渲染 400×800、1200×900 两项 PASS 且看图；Windows debug UI 资源编译 PASS（非可执行预览包）。新增六个手写模块行覆盖率 726/787（92.25%）、分支 240/282（85.11%）。全仓 analyze 0 error、11 既有 warning，退出 1，未冒充全绿；最终独立复核未发现未解决 Critical/High。首次提前初始化回归和 coverage 内存崩溃均保留失败证据，前者已修复并重跑，后者以分离/降低并发采集成功。完整矩阵、命令、覆盖缺口见 [P0 测试记录](testing/node-overview-p0-2026-10-15.md)。本机 Flutter 3.47.4 / Dart 3.13.3，CI 仍声明 Flutter 3.41.7，未升级依赖。
- **验收限制**：FR-4 只记录可绑定到已应用快照的显式测速；接管已有 Core 且本会话未应用配置时缺少可信快照，保留实时值/旧历史，不新写历史；无归属自动广播同样不写。UI 有说明，未用 setup/重启补救。因此 P0 本地实现已交付，完整接管历史与真实运行验收尚未完成。非活动 provider 叶子属 P1；peers-only WireGuard 缺顶层 server/port 时目录明确解析失败。
- 交付状态：仅本地源码和本地文档提交；未推送、未 PR/合并、未生成可执行预览、未部署、未启动候选。真实窗口、性能、QuickJS/IPC 与现役代理/TUN 验收 NOT RUN。原 coverage/QA/probes 文件 hash、stash、历史工作树保持原状。后续先补可信只读运行身份契约或明确接管限制，再按授权构建预览和运行验收；P1/P2 未实施，P1 改 Core 时仍须整包重建、Helper/Core hash 绑定及 VM 证据。

## DoH 静默连接恢复回归修复（2026-10-14）

- 来源：两份独立审查对 `4e4a146` 的同一 P2——调用方 5s 截止（`DefaultDNSTimeout`）总先于 `http.Client.Timeout`（5s）到期，“调用方已过期即返回”跳过恢复，静默的 HTTP/2/HTTP/3 连接留在池中，后续查询继续复用并再次超时，只能等 H2 ping（约 30–45s）/QUIC idle 或切网 `ResetConnection`。两项发现为同一根因。
- 修复（本地提交 `4fdf293`，基于 `fa758a6`）：新增 `dns/doh_health_fcx.go` 按客户端代次统计应答。调用方截止且该代次在整个请求期间**没有任何应答**时，立即停止分发该代次（`doh.client=nil`，下一次查询懒建新连接），延迟 `fcxDoHRetireGrace`（默认 5s）再关闭，避免切断仍在途的并发请求。取消、旧代次、锁竞争（`TryLock`）一律不计；保留代次保护、显式重置不被撤销、0-RTT 与最多两次重试。健康判断用单调应答计数而非墙钟时间戳——首版时间戳在 Windows 粗粒度时钟下被真实 H2 探针抓到误判“期间有应答”。
- 新增日志 `[DNS][DoH] <host>`：重试（Debug）、旧代次失败忽略/重置跳过（Debug）、重建连接池及原因（Info）、静默连接退役（Warn，含时长/末次错误/累计次数）、延迟关闭结果（Debug/Warn）、建池失败（Warn）、截止但期间有应答而保留（Debug）。仅记录 host，错误文本中的 DoH 路径/查询串被替换，避免账号标识进日志。
- 验证：overlay 生成器 PASS；DoH 专项 24 组 + 2 子例 PASS，重复 10 轮 PASS（原“截止即保留 client”断言已按新语义改写）；审查者真实 TLS/HTTP/2 黑洞探针 **时间戳版 FAIL → 最终 PASS**（下一次查询新建 TCP、7ms 成功）；内存静默探针 PASS；dns 包 vet PASS；Core `-tags=with_gvisor ./...` PASS；`git diff --check` PASS。本机 Go 1.25.13（CI 1.26.0）。
- 2026-10-15 交付补记：源码 `335911106ea827ae9776789c8563d0409f227a4a`（含 `4fdf293` 修复及 `3359111` 文档）已在自有 `freedomcloud/development`，本轮 fetch/远端回读一致；[CI 38671805210](https://github.com/Hao-Monster/FreedomCloud/actions/runs/38671805210) 对应该 SHA，4/4 success。Linux DoH `-race` 实际 PASS（2.198s），Windows Core 专项 PASS，Agent 83/Helper 48 PASS；Flutter 609 PASS/1 SKIP（Linux 无 cmd.exe 的既有用例），M3 四脚本 PASS。本机 Windows race 仍因 UCRT 链接限制 NOT RUN，不能将其误写为 CI race 未运行。
- 同 SHA 完整新编 Core/Agent/Helper/UI 的普通未签名包：`dist/FreedomCloud-windows-amd64-dohfix-335911106ea8.zip`，153,567,226 bytes，SHA256 `20fb8fe5c6b61515a92c444360d11b8410e4435484da620b865399982c5e7199`；同名完整解压目录已逐项核对。构建 r2 exit 0，73 文件/72 checksum、独立静态审计 8/8 PASS，Helper 实际内嵌的新 Core hash 与 UI 编译输入一致；新增 `dns/doh_health_fcx.go` 在包内 manifest/唯一 overlay 映射/生成文件的专项核验 PASS。未覆盖旧产物，未混用旧 Core/Helper。
- r1 构建失败证据保留：`E:\Temp\flclashx-dohfix-preview-20261015-335911106ea8-r1` 的 AOT `zone.cc: 95: error: Out of memory`，snapshotter exit `-1073740791`。用户表示内存已改善后在全新 r2 重建；同源码/同脚本的 AOT 70.780s PASS、完整构建约 408.66s。便携 pwsh 7.6.7 的 ZIP digest 已核对官方 release；本地 Flutter 3.47.4/Go1.25.13 与 CI 3.41.7/1.26.0 的差异及已知 VS config-only exit 1 均保留披露。
- 详细组件 hash、15 步构建、独立审计、CI 证据、r1 失败、观察信号及换包/回退见[DoH 静默连接修复预览交付](testing/windows-dohfix-preview-2026-10-15.md)。交付文档单独本地提交，本任务未推送文档、未 PR/合并/发布/部署。真实微信长时、TUN/SCM/切网/休眠实机及候选运行仍 NOT RUN；未操作本机客户端、代理/TUN/服务、UAC，未启动或修改观察脚本。
- 已知取舍：空闲连接上单个慢查询（>5s 且无其他应答）会触发一次重连；上游完全不可达时每个超时查询各退役一个代次，Warn 日志随之增加（含累计计数便于识别）。

## 微信间歇断网调查与 DoH 恢复修复（2026-10-14）

- 用户确认微信长时运行后显示网络不可用、微信不重启而关闭 TUN 即恢复，授权定位、修复、回归及独立新预览。本轮从 `development@3c48432a77971a3e0c18a26ca1c55d1632df04e6` 继续，仅本地提交，未授权推送/PR/合并/发布；当前客户端、服务及网络保持不动，旧包/草稿/stash/历史工作树保留。
- 现场被动证据仍来自旧 `resourcefix-485abf4d2e86`，20:35–20:37 双栈公网 DIRECT 与 DoH 暂时性故障，之后同 PID 恢复部分新连接。用户微信业务是否恢复及关闭 TUN 精确时间未由自动化观察确认。不能把此缩减为“网卡 Up 即正常”，或认定今天旧候选已被实机测试。
- 固定 Mihomo v1.19.32 overlay 仅替换三个 DoH 方法：请求到期/取消不重置共享 client，迟到错误仅允许作用于原失败代次，锁等待后重新检查 context。保留有效 transport timeout、0-RTT、显式 ResetConnection 与最多两次重试。未改 DNS/TLS/分流默认值、TUN 栈或依赖版本。此修复消除已重现的 DNS 恢复放大器，尚不能独立解释全部公网 IP 超时。
- 原始同一 5 项内存探针 **2 FAIL/3 PASS → 5 PASS**；新增 17 组 + 2 子例随机重复 100 轮全部通过；Core 普通与 gVisor 各 81 组 + 17 子例、既有补丁专项 17 组 + 2 子例、vet、Agent83/Helper48 均通过。独立审查无本轮新增高置信阻塞，移除身份/锁内取消保护的隔离变异被测试检出。三方法语句覆盖 51/58（87.9%），无 Go 分支率。
- 环境限制：Helper 首次链接器路径误选，子进程使用既有 MSVC 后全套通过；Go1.25 coverage+overlay 编译限制由逐文件匹配 manifest 的隔离 effective-source 副本补测；Windows race 因现有 UCRT ld 依赖加载失败未执行。DNS Windows/Linux-race CI 命令已加入，但新提交尚未推送，不能借用旧 CI 结果。
- 源码已本地提交为 `4e4a146513c90e18090fe87a7f9eeada501e5a71`（`fix(core): isolate DoH recovery from expired and stale requests`），从该干净 tracked SHA 完整重编 Core/Agent/Helper/UI/原生插件。普通未签名包 `dist/FreedomCloud-windows-amd64-tunwechat-4e4a146513c9.zip` 为 153,556,800 bytes，SHA256 `db4a47bafceb0af6981c496e4d407e59ccadbdd5673af9416732dba3ef604a1f`；同名完整解压目录已校验，旧包未覆盖。
- 独立产物审计 8/8 PASS：73 文件/72 checksum、955 源 blob、32 组件、14 插件/111 输入；Helper 实际新 Core hash、UI 编译输入/AOT与包含 DoH 补丁的 14 模板/12 映射一致。Flutter config-only 的已知 VS 识别失败如实保留，后续完整 CMake/Ninja/AOT/Windows 编译通过；未运行候选。
- 详细范围/矩阵见 [计划](plans/windows-tun-wechat-reliability-2026-10-14.md)，命令、计数、失败记录、覆盖率及未验证项见 [回归报告](testing/windows-tun-wechat-reliability-2026-10-14.md)，产物来源/hash/构建与用户验收见 [新预览交付](testing/windows-tun-wechat-preview-2026-10-14.md)。交付文档另作本地提交，不改变包的 `4e4a146` 源码；本轮源码与交付文档均未推送。真实微信长时、TUN/SCM/切网/休眠验收仍 NOT RUN，须先确认实际运行组件匹配，不将静态文件 hash 当作运行验收。

## TUN 修复源码推送与 Windows 预览（2026-10-14）

- 用户授权正常推送全部开发代码并重打预览，由用户自行测试、观察方只读看日志/运行。`f08fedb → fb6f5d43e204b1cc47278b8916ecae2ebc1dcccf` 共 9 提交已推送自有 `freedomcloud/development`，远端 SHA 回读一致；未晋级 main、未建 PR/tag/release。原 coverage、QA/probes、stash、47 历史工作树及旧包保留未动。
- 精确源码 [CI 38525761829](https://github.com/Hao-Monster/FreedomCloud/actions/runs/38525761829) 四项全通过：Flutter 609 PASS/0 FAIL/1 Linux 平台 skip（Windows cmd.exe）；本机对应 11 项补跑全通过。Core 按预览 CGO=0/with_gvisor 全量 91 PASS，CI Linux/race 和 Windows Core/Agent 83/Helper 48 通过。未把此前 CGO=1 环境编译失败记为修复。
- 从干净 tracked HEAD 的 Git archive 完整重编 Core/Agent/Helper/UI/原生插件；普通未签名包 `dist/FreedomCloud-windows-amd64-tunfix-fb6f5d43e204.zip`，153,552,555 bytes，SHA256 `4c70e5cba8d9afb1b13de47fcf674232a82318c5070b88295040cd7096393055`。同名解压目录已准备并校验，旧包未覆盖。
- 独立产物审计 8/8 PASS：73 文件/72 校验、948 源 blob、14 插件/111 输入、Helper 实际新 Core hash、UI 编译定义及固定 overlay 一致；无用户配置/凭据/私密日志和 strict 驱动/Broker。构建工具适配与只读观察脚本另做审查。
- 详细矩阵、构建命令、组件 hash、工具版本漂移及用户验收见 [Windows TUN 预览报告](testing/windows-tun-preview-2026-10-14.md)。本条为打包后文档，不改变包对应的 `fb6f5d4` 源码。
- 交付时现役仍为旧 `resourcefix-485abf4d2e86`；候选未启动，未操作当前代理/TUN/服务。用户真实开关、权限、慢关闭、切网/休眠与长时稳定性仍 NOT RUN；观察不连接 Agent IPC，不将静态构建或网卡 Up 当作运行验收。

## TUN 启动与状态同步稳定性修复（2026-10-13，第一批）

- 来源：对 `resourcefix-485abf4d2e86` 现场“Core 已建卡、UI 报 statusUnavailable/TUN 未开启”及外部只读排查的复核。起点 `development@f08fedb`（与 `freedomcloud/development` 领先0/落后0）。原 coverage、QA 草稿、probes、stash、历史工作树均保留未动。
- Core overlay：`GetTunLifecycleStatus` 改为读取原子发布的快照，不再等待建卡持有的 `tunMux`；`ReCreateTun` 在建卡前发布 `starting`，结束和 `Cleanup` 时发布终态。新增 `TestFCXTunStatusReadableDuringSlowCreation`。Mihomo 固定版本/上游 hash 未变，仅补丁内容变化（manifest 中补丁 hash 会随之变化，Helper 绑定的 Core hash 需随新包重建）。
- Dart：① Agent 只在 Core 状态切换时推送 `proxyRunning`，现由 `ClashService` 在同一 Core 确认 start/stopListener 后同步缓存，TUN 重开不再误判为全量重载；② 启动最终验证对 null/unknown 做有界等待（默认 8 次×500ms），并接受观察器已采纳的新鲜读数，不再因并发轮询失效 epoch 而误报；③ 轮询之后读到同一 Core TUN 已开且运行投影缺失时补做一次 `reflectRunning`；④ `TunRuntimeController.requestFailure` 与观察失败分离，后台配置刷新的降级只看真实请求失败；⑤ `_setupClashConfigImpl` 只合并订阅同步字段，不再整份回写旧快照覆盖 TUN 开关。
- 验证：Core overlay `TestFCXTun*` PASS；Core `-tags=with_gvisor ./...` PASS（本机 Go 1.25.13，CI 为 1.26.0）。Flutter 3.47.4（与已提交 `pubspec.lock` 一致）全量 **599 PASS/0 FAIL**，锁文件未变化。另用 CI 声明的 3.41.7 跑过：TUN/Agent 相关 9 个文件 77 PASS/0 FAIL，全量 592 PASS/7 FAIL，7 项均为 `ink_sparkle.frag` 着色器资源版本不兼容（未修改模块），该 SDK 改写的 `pubspec.lock` 已还原。定向 analyze 无 error/warning。新增用例依赖新 API，未在修复前代码上执行 Red。
- NOT RUN：race 用例、ClashService 监听缓存的单元测试（需真实 Agent 连接）、真实 Windows 开关/切网/休眠恢复/长时运行、预览包构建、CI。未推送、未 PR、未打包、未改动本机代理/TUN/服务。
- 待处理（第二批）：网卡消失（interfaceMissing/listener 仍在）时用户无法直接重开且 `ReCreateTun` 同配置不重建；`closeFailed` 锁存无自动恢复；全量路径内 `checkAndUpdate` 联网拉订阅；订阅 `tun.stack` 覆盖导致重建网卡；网卡名精确匹配与 Up 判定在真机的可靠性。

## TUN 网卡消失与 closeFailed 恢复（2026-10-13，第二批）

- 起点：第一批本地提交 `f0aa190` 之上，同一 `development` 工作树。
- Core overlay：`ReCreateTun` 同配置快速路径增加 `fcxTunInterfaceUsable(device)`；Windows 上网卡缺失或非 Up 时关闭并重建，枚举失败或非 Windows 保持原行为。新增 `TestFCXTunIdenticalReloadRebuildsVanishedAdapter`。`tun_status.go` 网卡名改为大小写不敏感匹配（`matchTunInterface`，新增 `TestTunInterfaceMatchIsCaseInsensitive`）。补丁 hash 再次变化，Core 与 Helper 必须一同重建。
- Dart：① 用户显式开启时，已提权 Core 返回 unknown（如 interfaceMissing）也允许下发配置以触发重建；后台刷新仍不对 unknown 动作，未提权仍拒绝。② 启动/显式开启读到 `closeFailed` 时先在同一后端重启 Core（不提权、不重入 TUN 队列），再强制走全量配置与监听。③ 轮询发现同一 Core listener 仍在而网卡 `interfaceMissing` 且偏好开启、无请求失败、已提权时，自动走增量路径重建；不请求 UAC，失败记为请求失败并停止重试，每个 Core 实例最多 2 次，读到 on 后清零。`interfaceDown`（可能是用户禁用网卡）只在用户显式开启时修复，不后台自动修复。
- 复核后不改：`checkAndUpdate` 只在配置文件缺失时下载，而启动前已要求可读配置，原先“全量路径联网拉订阅”的判断夸大；订阅覆盖 `tun.stack` 属既有设计（`overrideNetworkSettings=false`），栈变化本就需要重建网卡。
- 验证：Core overlay `TestFCXTun*` PASS；Core `-tags=with_gvisor ./...` PASS（Go 1.25.13，CI 为 1.26.0）。Flutter 3.47.4 全量 **607 PASS/0 FAIL**（新增 8 项），`pubspec.lock` 未变化；定向 analyze 无 error/warning。新增 Dart 用例依赖新接口，未在修复前代码执行 Red。
- NOT RUN：真实 Windows 网卡删除/禁用、驱动重置、closeFailed 现场、切网/休眠/长时运行、race 用例、CI 3.41.7 复跑、预览包构建。未推送、未 PR、未打包、未改动本机代理/TUN/服务。

## TUN 交叉审查补修（2026-10-13，第二批之后）

- 来源：对 `f08fedb → 315274c` 的外部交叉审查，2 项 P2，均复核属实。
- P2-1 慢关闭期间仍报告旧 `on`：`closeTunListener` 已清除内部 listener 并进入可能阻塞的 `Close()`，但快照只在函数返回时发布。现于 `Close()` 前发布 `state=unknown / ListenerActive=false` 过渡快照并推进 revision，关闭结束后由调用方发布真实终态（off 或 closeFailed），不提前宣称关闭成功；`starting` 过渡同样改为独立 revision（`fcxPublishTunTransition`）。新增 `TestFCXTunStatusNotReadyDuringSlowClose`（Cleanup 与 ReCreateTun(disable) 两个子场景）。**Red**：用 HEAD 的 `close_tun.txt` 运行，两个子场景均返回旧 `on`，与审查一致；恢复修复后 Green。
- P2-2 `proxyRunning` 缓存被不含该字段的 Agent 事件清空：Agent `publish_strict_status` 与 `commandResult` 报文不带 `proxyRunning`，原解析为 null 后无条件覆盖。现 `AgentEvent.proxyRunningReported` 区分“未提供字段”和“显式 null”；`mergeAgentProxyRunning` 仅在同一 ready Core 上对缺字段事件保留缓存，显式 null 仍清空，换 Core 或非 ready 清空。回归测试使用 `runtime.rs` 实际报文形状。Agent 未改动。该 Dart 用例依赖新 API，未执行 Red。
- 验证：Core overlay `TestFCXTun*` 8 项 PASS；Core `-tags=with_gvisor ./...` PASS（Go 1.25.13）。Flutter 3.47.4 全量 **610 PASS/0 FAIL**，`pubspec.lock` 未变。审查方报告的主 Core `TestTun*` cgo 编译失败本机未复现（本机全量 Core 通过）。
- NOT RUN：真实 Windows 慢关闭/切网/休眠/长时运行、race、CI、预览包。未推送、未打包、未改动本机代理/TUN/服务。

## 开发分支累计源码晋级（2026-10-12，合并前快照）

- 用户明确授权本次正常推送 `development` 并通过 PR 合并 `main`，暂不生成可执行客户端包。只做源码集成和质量检查；不创建版本标签、不运行候选客户端、不修改当前代理/TUN/服务、不部署。
- 开工 fetch 后：本地 `development@a97e42d860b40e4918d9310328e4582ac445d2d8`，远端 `development@6ce68d86e855573c1d1e42cdaf4af3073b58005b`，自有 `main@4738293ea90ca9b90afcc201a5c9a09b729a86ad`；本地领先开发远端11个、领先主线31个提交，均无落后，无开放 PR。晋级范围包含此前 Core/TUN、Windows 启动、托盘及资源生命周期修复，不仅是本轮购买卡片。
- 将已经确认的仅兑换码 v2 方案/任务/测试矩阵与 v1 作废标记作为独立文档提交保存，避免主线继续把余额结算当作当前需求。套餐目录及富文本展示已实现；v2 四区域布局整理仍是未执行任务，不据此宣称完整新版购买页已交付。
- 最新本地产品验证对应 `a97e42d`：全 Flutter 591 PASS/0 FAIL/0 SKIP，购买目标58项通过，定向 analyze 无问题；详见[卡片富文本测试报告](testing/plan-card-rich-content-2026-10-11.md)。其他批次沿用各自历史证据，最终 head 的远端 CI 尚待本轮推送后核实。
- 已回读主线保护：必需 PR、三项指定 Actions 检查、严格更新、讨论解决、管理员适用，禁止强推/删除；本次另等待 Windows Core and service tests，采用普通 merge commit，再把主线合并提交快进同步回 `development`。不改保护设置。
- 已核对全部 workflow 触发器：普通 `development`/`main` push 与 PR 只触发 `quality-gate`；可执行包构建要求版本标签、独立旧预览分支或手动触发，本轮均不执行。M3 package integrity checks 只是现有工具/清单测试，不是客户端发行包。
- 原 coverage、原生 QA/probes、stash、旧工作树和已有预览包保持原位，不混入提交。系统/真实兑换/实机验收边界维持各报告的 NOT RUN；合并不代表打包、部署或正式发布。
- `a92e3ec` 已正常推送，单一晋级 [PR #60](https://github.com/Hao-Monster/FreedomCloud/pull/60) 已建立。三个独立只读审查覆盖累计产品范围；CI 在 Linux 复现两条托盘测试错误平台预期，Core/Windows service/M3 检查通过。仅修正测试的真实宿主调用顺序/tooltip断言，不改产品代码、不新增skip，最终head重新通过全部检查前不合并。
- 本轮具体 Red、Windows 回归、静态检查、历史空白诊断及 NOT RUN 边界见[源码晋级验证](testing/source-promotion-2026-10-12.md)。最终合并SHA、最终head CI和两分支同步结果以同一 PR 的实际记录为准；不为记录自身合并SHA再追加造成分叉的文档提交。

## 购买页重新设计：只用兑换码（2026-10-11）

- 用户明确排除钱包、余额支付、第三方支付、金额补差和余额结算：通过微信或其他渠道取得兑换码，再兑换套餐。2026-10-10的v1方案/开发任务/测试矩阵已标记作废；不再等待或申请其中的后端扩展。
- 当前development@c2fe8c5；fetch freedomcloud成功，本地领先10/落后0。无开放development PR；最新CI仍对应旧6ce68d8，不是本轮验证。原coverage、QA/probes、stash和旧工作树保持不动。
- 客户端及Xboard-Go本地07476e0只读核实：现有查码/兑换/历史和type4套餐购买码已能支持主链；套餐取自兑换码，浏览目录不创建订单。旧卡类型保留原规则，不改成余额支付。
- v2方案、5项开发任务、12组测试任务已整理到engineering/plans/purchase-redemption-2026-10-11.md、engineering/tasks/purchase-redemption-2026-10-11.md、engineering/testing/purchase-redemption-2026-10-11.md。
- 独立只读复核通过；文档git diff --check通过，6份新旧方案文档的13个相对链接有效，无行尾空白。文档修订保留在当前工作树，本轮重新设计未创建新提交。
- 本轮只重新设计和更新文档，尚未实现新版布局或执行功能测试；未改产品/后端代码，未真实兑换、修改模板、启动客户端、推送或部署。

## 历史：完整购买流程v1（2026-10-10，已由2026-10-11用户纠正作废）

- 用户要求先研究方案、拆开发任务，再开发和测试；仍保留仅购买页的范围限制。当前研究基线development@70c4643；Xboard-Go本地07476e0不等于线上部署版本。两次Git fetch因网络失败，另用GitHub API核实远端development为6ce68d8，本地领先9/落后0；无开放development PR，旧CI成功不是本轮验证。
- 源码与已打开网页只读核实：余额扣款基础存在，但普通用户接口缺购买上下文余额/币种组合与完整报价；创建订单会立即抵扣余额，且无请求幂等键。不能只串客户端接口就承诺可靠完整结算。当前后台可见模板未见余额型通用卡，本轮未新增/修改。
- 推荐仅改客户端购买页，并新增Xboard-Go必要购买上下文、无消费报价、原子余额型购买和精确恢复接口/防重记录；旧页面、旧兑换与订单合同保留。type4快照码和标准onetime订单权益规则不同，不能统一成相同叠加。
- 已编制方案、开发任务、30组测试矩阵：engineering/plans/purchase-checkout-2026-10-10.md、engineering/tasks/purchase-checkout-2026-10-10.md、engineering/testing/purchase-checkout-plan-2026-10-10.md。状态为等待用户确认后端范围和业务基线，产品实现未开始。
- 已完成后端合同与文档独立审查，补入报价时间派生字段、单报价执行绑定、不同请求争用有限资源，以及邀请奖励/佣金/折抵旧单共同回滚的验收条件；这是方案审查，不是新功能测试通过。
- 文档检查：git diff --check通过；3份新增文档的5个相对链接均有效，无行尾空白；修订后的独立文档复核通过。方案文档作为独立本地成果保存，产品开发任务仍等待G0确认。
- 本轮未运行新的购买功能测试，全部新用例NOT RUN；未真实下单/兑换、未启动完整客户端、未推送/部署。现有coverage/QA/probes/stash/工作树和后台未跟踪文档均保留。

## 购买页公开套餐展示补全（2026-10-10）

- 用户授权“先研究一个方案，然后进行开发”，仅补全购买页套餐信息。起点 `development@b565b33da5cf4d95baa9a2e752b5884f26fa57dd`；fetch自有远端后领先8、落后0，无开放development PR；最近CI成功对应旧 `6ce68d8`，不是本轮证据。原coverage、QA原稿、stash、历史工作树与旧包保留。
- 本轮匿名GET和Xboard-Go本地源码确认公开字段已存在，客户端原解析丢弃。现保留并呈现正文Markdown、标签、明确限额、流量重置规则、销售剩余名额和单列重置标价；不猜测币种，不改变匿名可见集合、七新购周期、价格精度或礼品卡兑换行为。账号左下角入口、其他页面、在线支付、后端、代理/TUN均未修改。
- 正文使用原生 `flutter_markdown_plus 1.0.12` / `markdown 7.3.1`（只新增两项依赖，BSD许可）；仅无属性u可扩展，其余HTML保持原文，图片以alt占位不加载外部资源；仅显式HTTPS链接经购买页原有外跳和失败提示。4语言既有ARB键值未变。
- 有效宿主Red 0/2→Green；审查期间修正HTML根文本丢失、linked-image alt、复合下划线、未闭合u扫描和多字体列表缩进，并补入口异常/段落隔离/实际文字盒断言。最终购买模块 **268 PASS/0 FAIL/0 SKIP**；全Flutter带行/分支coverage **563 PASS/0 FAIL/0 SKIP**，墙钟95.44秒；定向analyze无error/warning/info；Windows目标debug UI资源编译exit0（非可运行包）。
- 本轮LCOV记录的可执行diff行161/162（99.38%），分支43/43（100%）；默认父样式兜底未命中，新增const字段无LCOV可执行行记录。真实Widget树4张中文浅/深/窄窗/2x截图已查看，保存在 `build/plan-catalog-completeness-preview`，均为合成套餐，不是真实客户端运行。独立只读复核最后无新增阻塞。
- 方案与本轮详细证据：`engineering/plans/plan-catalog-completeness-2026-10-10.md`、`engineering/testing/plan-catalog-completeness-2026-10-10.md`。目标分支为development，源码和本节随同一可追溯本地提交保存；未推送、未PR/合并、未打新可执行包、未部署。
- NOT RUN：真实Windows窗口/外部浏览器、真实账户/兑换/支付、各平台设备、Core/Agent/Helper新验证、代理/TUN与系统服务、CI。下一步如需预览包，须从本轮精确提交单独构建并标明组件来源，完整启动/网络验收须另获环境授权。

## 运行诊断后续资源修复（2026-10-09）

- 用户授权先研究再修复，起点 `development@13b0ea05dfca6840e402a1f29d543705e30382e4`。方案先冻结到 `docs-dev/resource-followup-plan-2026-10-09.md`，再实施 R1 Helper日志所有权/输出收尾、R2 Windows图标有界队列/消费者释放、R3健康检查缓存清理/代际隔离。旧coverage、QA草稿、分支/工作树和预览包均保留。
- 三项均有有效Red→Green；交叉审查补充修复既有UNC/rooted图标key碰撞并加强失效快照消息与活动监听释放断言。汇总及三个模块证据见 `docs-dev/resource-followup-results-2026-10-09.md`。没有改变日志级别、进程优先级、Mihomo固定版本、购买或代理/TUN产品行为，没有新生产依赖。
- 最终完整Flutter 476 PASS/0 FAIL/0 SKIP；图标目标22项；Helper service48/default45项；Core普通90/with_gvisor90项、health/config/controller race22项、overlay合同race14项全部通过。Dart定向analyze 0error/0warning/22info，service clippy通过；额外default clippy保留未修改process_stop.rs:39的既有dead_code错误。
- 本轮Dart文本diff可执行行173/271（63.84%）、分支74/96（77.08%），含整页包装缩进；新队列与activity scope在LCOV中的行/分支100%。真实ConnectionsView整页/Win32平台入口未覆盖。Core package statement42.9%，Rust未采集coverage，范围和缺口已披露。
- 三模块非作者复核无剩余本轮源码阻塞。源码已保存为本地提交 `485abf4d2e8664b8e03fb17ed63add2a3b2359c8`（`fix: bound residual resource lifecycles`）；当前客户端/服务/网络保持不动，真实SCM/SYSTEM、窗口/导航、长时资源及其他平台验收NOT RUN。不推送、不合并、不发布。
- 从485abf4的精确Git archive完整重编Core/Agent/Helper/UI/原生插件，Windows构建exit0；新普通未签名包 `dist/FreedomCloud-windows-amd64-resourcefix-485abf4d2e86.zip`，152,994,092 bytes，SHA256 `050695fe6ad62e64f4efcb4985fd9c65f75cbf4b61b9276820087a66a1f318c5`。dist及聊天outputs副本/hash一致，旧包未覆盖；构建与交付见 `docs-dev/evidence/resource-followup-build-2026-10-09.md`。
- 独立产物审查8组PASS：73文件/72内部校验、931源blob、32组件、14插件/111输入、Helper/Core绑定、UI编译定义及1015有效overlay文件一致。唯一x86为既有EnableLoopback，其他29个PE为x64；运行NOT RUN和配置共享/启动副作用声明保留。交付文档单独本地提交，未运行候选版本，未把静态审查认定为长期无泄漏。

## 性能、资源与可靠性17项修复（2026-10-09）

- 用户授权在唯一 `development` 分支逐项修复、统一打包后自行本机测试。修复基线 `a52907c2d4425f6c1679792f64a3129ae4c562d7`；未推送/发布，未启动候选客户端或修改现役代理/TUN/SCM/驱动/Shell。原coverage/QA草稿及旧包保留。
- F01–F17源码与对应隔离回归完成，详见 `docs-dev/remediation-plan-2026-10-09.md`、`docs-dev/remediation-results-2026-10-09.md` 和四份模块evidence；TODO区分代码/自动化与平台验收。P02原生资源作用域已优化；P01优先级对照测量仍待办，没有修改HIGH_PRIORITY_CLASS。
- 最终Flutter带行/分支coverage全量457 PASS/0 FAIL/0 SKIP；Core75项、with_gvisor75项、目标race38项，Agent83项、Helper37项均PASS。proxy故障/UTF-8、tray原生8组/200次USER 1→1、包装工具与68项strict包装检查PASS；Android arm64 c-shared及Darwin arm64仅编译通过。
- 修改且有LCOV记录的Dart行覆盖535/706（75.78%）、分支182/291（62.54%），两个窗口/lifecycle manager未载入LCOV；Core语句40.5%。平台入口与真实系统验收缺口见汇总。Dart analyze保留1条未修改文件warning，Agent clippy保留2条既有诊断，未弱化规则。
- 独立复核发现的事务取消、WebSocket退休、首次配置失败清理、测速history、Android迟返、Profile快照、ZIP预检及组件来源问题已逐一处理。真实Windows/SCM/TUN/IDN/长时资源及Android设备验收仍NOT RUN，交由用户或隔离环境完成。
- 本地修复提交 `7d0a00777342ab4503e2ae20d4f4435742538d60`；从精确Git archive完整重编Core/Agent/Helper/UI/原生插件，Windows Release与73文件ZIP roundtrip PASS。普通未签名包 `dist/FreedomCloud-windows-amd64-resourcefix-7d0a00777342.zip`，152,946,986 bytes，SHA256 `f0aae7982964e9e29c22022b76fb8f8996f8d2507f0db77aaa2964bcc78fea40`。聊天outputs有同hash副本，旧包保留；构建及组件证据见 `docs-dev/evidence/remediation-build-2026-10-09.md`。候选客户端未启动。
- 最终独立产物审查PASS：ZIP/bundle73文件、72项内部校验、32项组件描述、14插件/111输入、Helper实际Core绑定、UI编译定义及CORE-PATCH一致；预置输入和普通未签名/运行NOT RUN声明准确，无夹带用户配置或凭据。EnableLoopback为既有x86工具，其余29个PE为x64。交付文档后续提交，不改变包对应的7d0a007源码。

## 外部程序员报告复核与 TODO 补充（2026-10-09）

- 按用户要求在 `development@3227a863f5bdbb4ca7dc1f8caa5b7708d1f104dc` 核验外部六项主张，详细结论见 `docs-dev/evidence/external-review-verification-2026-10-09.md`。产品源码与原审查基线相同，本次仍仅调查/文档，不实施修复。
- F11 补充 Unicode 排除域名错误编码；新增 F16 托盘菜单全桌面查找缺少所有权且主题监视启动过晚、F17 PNG 编码异常遗漏 ui.Image 显式释放。DC 跨异步持有确认但有 Win32 finally 与串行提取，作为 P02 优化候选；HIGH 优先级保留 P01，未采纳“已证明 P0/Explorer 崩溃根因”的推断。
- 对 F06 补充 2 分钟 timeout 请求的滞留；对 F09 补充后台 Timer 清单及边界：Core 只发送新增请求，组刷新依赖 post-frame，detach/会话退出已有 setUiActive(false)，不能把正常托盘状态观察全部停掉。
- Unicode C++ 隔离表达式 probe：4 项中 2 PASS / 2 目标 FAIL / 0 SKIP，exit 1；使用真实 Flutter EncodableValue 和严格 UTF-8 对照，未更改代理/注册表。菜单和图像失败路径为源码/契约确认，动态跨程序/PNG 故障验收未运行。原覆盖率/QA 草稿和历史报告保留；本轮无推送、发布或服务/系统设置变更。
- 文档完整性检查 PASS：17 项均为 OPEN、原 15 项保留，9 个辅助章节/8 个本地链接/27 个源码路径及 probe 附录一致性通过；历史快照和产品源码未改。独立只读复核无阻塞，`git diff --check` 通过。本轮交付仅四份文档，所有产品修复/性能与真实系统验收仍按 TODO 跟踪。

## 性能、资源生命周期与可靠性审查待办（2026-10-09）

- 用户要求将本轮发现完整登记到 `docs-dev`；清单见 `docs-dev/performance-resource-todo-2026-10-09.md`，原始报告快照见 `docs-dev/evidence/performance-resource-audit-2026-10-09.md`。源码基线为 `development@c5c5ae4400d225cf2abefccb92184d29c1b81bcd`，本次仅文档整理，未实施其中的产品修复。
- F01–F15 覆盖外控认证、ZIP 路径边界、IPC 阻塞、Helper 停止失败、无效配置覆盖运行态、RPC 滞留、两类轮询竞态、后台取样、测速排队、Windows 代理失败路径、日志滚动、认证前连接、日志读取及 Android JNI 回收。另列 P01 优先级测量、V01–V05 长期/系统验收，以及 H01 托盘历史修复与 S01 开始菜单恢复边界，均保留独立状态。
- 历史隔离验证：Flutter 0 PASS / 4 目标 FAIL / 0 SKIP，表示四项缺陷复现；Go 两个观察性测试各 1 PASS、一个纯解析探针 exit 0，证明所述机制，不表示产品已修。Green、完整回归、发布构建、覆盖率、长时 profile、原生故障注入和 Android 实机验收均未因此完成。
- 本轮不更改客户端/代理/TUN/服务/Windows Shell，原有 coverage/QA 草稿保留；没有推送或发布。后续按清单逐项补修复提交、目标/回归测试及平台验收证据，不把记录 TODO 视为修复完成。

## Windows 托盘菜单泄漏与任务栏异常（2026-10-08–09）

- 用户先要求只读系统日志/源码分析，再授权修复并打包。基线为唯一 `development@6ce68d86e855573c1d1e42cdaf4af3073b58005b`；开工 fetch 自有远端后无 ahead/behind、无开放 PR。保留旧预览与原 coverage/QA 草稿；本轮未授权推送、发布或当前工作站客户端/网络切换。
- 确认旧运行 UI 的 USER 对象达到 10000，系统 Win32k 桌面堆失败与 Explorer 连续退出。托盘插件 `RemoveMenu` 脱挂旧子树但未销毁，TUN 3 秒观察又无条件重建菜单；这是已确认的客户端资源缺陷，当前 Explorer 故障的完整退出/替换对照仍未执行。
- 修复使用仓库内 tray_manager：整树所有权/失败回滚/展示期间延迟替换、popup 选中 ID 与已显示菜单快照、shared lifetime 保护 owner 销毁、图标注册失败与恢复。主包仅显示状态变化触发刷新，更新等待真实完成并串行合并；保留 tooltip、force 图标重建和非 Windows legacy 回调。
- 最终全量 Flutter 388 PASS / 0 FAIL / 0 SKIP；主包修改可执行行 36/39，Native 8 组 PASS，真实 Win32 200 次多层替换及 owner dispose/reset USER 1 → 1，生产插件警告视为错误编译 PASS。定向 analyze 0 error/warning，85 个既有 info（原始 exit 1）；独立源码复审无剩余已知中/高风险。详见 `engineering/testing/tray-menu-resources-2026-10-08.md`。
- 从修复的精确本地提交归档准备新 Windows amd64 普通免安装包，完整重编 runner/全部插件/UI；未改 Core/Agent/Helper 逐 hash 复用 `b2cccee7303d` 来源并记录兼容证据，不复用旧托盘 DLL。实际构建提交、ZIP/hash 与核验结果在交付后追加；所有旧包保留。
- 真实应用、鼠标 popup、当前 Explorer 恢复、Shell 故障/恢复、长时 USER/GDI、TUN/UAC/服务/流量验收 NOT RUN。本轮未运行候选客户端，不把本地测试和构建声明为本机任务栏已恢复。尚未推送、未合并、未发布。
- 本地修复提交为 `71a07a9d7ad0502d4a3eef1527e499460542b026`，精确 Git archive 源构建完成 Windows runner/全部插件/UI 重编；新托盘 DLL SHA256 `39625c5e0630fd718bdfcafa4f7574bc3715835b4d9f9999fac16656c21db428`，包含 DestroyMenu，与旧 DLL 不同。Core/Agent/Helper byte-identical 复用来源和 Core define/Helper 内嵌绑定均核验。
- 新包 `FreedomCloud-windows-amd64-trayfix-71a07a9d7ad0.zip`，152,755,710 字节，SHA256 `11dc19f930ebbe90e266bdd3d39611e8cdb9bd8ecb7c4f32d3ac3f75e7a2302d`；73 文件完整 ZIP/解压/交付核验 PASS。构建准备/包装元数据错误已在包装工具修复，完整原生 build 成功后只在新目录副本重封装，原失败记录保留。交付在本次聊天 outputs，dist 同名副本不覆盖旧包；后续证据文档不改变该包源码来源。
- 独立只读产物审查 PASS：ZIP/bundle 全文件、31 项组件元数据、commit/tree、菜单释放导入、后端固定来源及 Helper/Core hash 绑定一致；清单无用户配置或凭据，普通未签名和实机 NOT RUN 边界准确，未发现打包阻塞问题。

## 非管理员启动 UAC 后仍无法开启 TUN（2026-10-07）

- 用户实测（预览包 `136546fd19c4`，非管理员启动）：自动开启失败；手动点 TUN 弹出 UAC 并同意，仍失败。应用日志：`windows runas ... resultCode:42`（提权进程已启动）后 `helper install/repair timed out`；`%ProgramData%\FlClashX\logs\helper-install.log` 自 2026-09-16 后无任何新记录，Helper 服务 PID 未变化 → 提权修复命令一条都未执行。
- 根因（已复现）：cmd 中 `if not exist X mkdir X & 其余…` 把整条 `&` 链都当作 IF 主体；日志目录（或服务目录）存在后，整段修复（停服务/复制/配置/启动）被静默跳过。用相同命令、临时路径和不存在的服务名非提权重放：目录不存在时正常执行，预先建好目录时不产生任何输出。
- 修复提交 `68716be`：两处 IF 加括号；停服务改为同步 `net stop`，再替换二进制；服务 SDDL 给 SY/BA 完整权限（旧值缺 DC/SD/WD/WO，09-16 日志中管理员 `sc config`/`sc sdset` 返回 5；IU 权限不变）；修复后健康等待从 4.5 s 增至 30 s。新增 Windows 用例真实执行该命令（假服务名、预建目录），对旧写法确认失败。
- 验证：专项 11 PASS；全量 Flutter 370 PASS / 0 FAIL；改动文件 analyze 0 error/warning（4 条既有 info）。真实 UAC → 服务修复 → TUN 开启 NOT RUN。已被旧 SDDL 锁定的现有服务：管理员仍无法 `sc config/sdset`（binPath 不变时不影响修复），需卸载重装或用 SYSTEM 修复，未处理。
- 用户授权后 `development` 推送 `af7ee28..5a41421`（正常快进，无强推）。GitHub Actions quality-gate run `37578112377`（head `5a41421`）全部 PASS：Core Go tests、Flutter tests、M3 package integrity checks、Windows Core and service tests。未建 PR，`main` 未变。
- 用户要求后产出新预览包 `dist/FreedomCloud-windows-amd64-preview-5a414210319a.zip`，59,112,074 字节，SHA256 `dba968033ef9b2469e6e82bc937e77eb1248ebf82730b9a3b935f51ed88a8a7a`，73 文件，ZIP 解压逐文件校验通过。构建方式为“仅 UI 重打包”：在 `5a41421` 干净 detached 快照用 `flutter assemble` 重编 `data/app.so`（SHA256 `3b8da58e45469653072ccce047df111670e8a7ec9c256ab05581c13c8c653c5a`）与 flutter_assets；Runner/插件/Core/Agent/Helper/运行库逐字节复用已校验的 `b2cccee7303d` 包（依据：`b2cccee..5a41421` 未改 windows/core/services/libclash/setup.dart/pubspec/assets/arb，复用前重验 hash；engine 文件一致）。旧包均保留未变。未在开发工作站启动；真实 UAC 提权修复服务及 TUN 开启等待隔离 VM 验收。构建脚本与日志保存在会话私有 scratch（`Build-UiRepackPreview.ps1`、`build-5a414210319a.log`）。

## Windows 缺陷修复批次（2026-10-07）

- 同一 `feature/tun-default-on` 分支，用户批准后修复 4 个确认问题，各自独立提交：`7b89ae2` 主窗口在运行时启动（UAC/后端交接）前显示；`b07e493` 自启动注册表写入 await 并记录失败；`cbcc5e0` HKCU Run 值给可执行路径加引号（已开启用户下次启动自动改写为带引号值，关闭时总是移除含旧值的条目）；`be46c97` 标题栏最大化图标跟随 Win+↑/贴靠。
- 疑似未改：安装后 `runascurrentuser` 提权启动、退出等待挂起的 UAC 队列、最大化尺寸被保存、`SetProcessDPIAware` 与清单重复/UI 高优先级。Go Core、Agent/Helper 本轮未审查。
- 三文件 analyze 0 error/warning（info 为既有或随代码移动）；真实窗口/注册表/UAC 行为 NOT RUN。未推送、未建 PR。
- 用户要求后，本地 `development` 从 `8089f66` 无冲突快进到 `136546fd19c404767ee3a1a140e807dbe311614f`（含 TUN 默认开启与本批修复），领先 `freedomcloud/development` 14 个提交；`feature/tun-default-on` 保留。未推送。
- 预览包 `dist/FreedomCloud-windows-amd64-preview-136546fd19c4.zip`，59,111,599 字节，SHA256 `b148337c83c4704250bbfa0273b976a6eec1115df7a04fd0739135a278656cf3`，73 文件，ZIP 解压逐文件校验通过。构建方式为“仅 UI 重打包”：在 `136546f` 干净 detached 快照用 `flutter assemble`（Flutter 3.47.4）重编 `data/app.so`（SHA256 `89b5506c528844ac7e5776d4bd692a1050df55dc89cc783f092e2d63df94e4a2`）与 flutter_assets；Runner/插件/Core/Agent/Helper/运行库逐字节复用已校验的 `b2cccee7303d` 包。依据：`b2cccee..136546f` 未改 windows/core/services/libclash/setup.dart/pubspec/assets/arb；复用前重验旧包 72 项 hash；assemble 生成的 flutter_windows.dll、icudtl.dat 与复用件一致；与旧包相比仅 app.so、NOTICES.Z 及 4 个元数据文件不同。ZIP 采用 Optimal 压缩，体积小于旧包不代表内容缺失。旧包 SHA256 `a04fa740…c6bb97b` 未变。未在工作站启动；TD01–TD06、B1/B3 系统验收 NOT RUN。构建脚本与日志保存在会话私有 scratch（`Build-UiRepackPreview.ps1`、`build-136546fd19c4.log`）。
- 用户授权后 `development` 正常推送 `2b587a8..9d6b406`（快进，无强推）。quality-gate run `37507619436`（head `9d6b406`）全部 PASS：Flutter tests、Core Go tests、Windows Core and service tests、M3 package integrity checks。未建 PR，`main` 未变；预览包仍为 `136546f` 源码（`136546f..9d6b406` 仅台账文档）。

## TUN 默认开启并尊重保存偏好（2026-10-07）

- 用户选择 A2/B2/C1：全新安装默认开启 TUN、保存的关闭不被覆盖；本任务在 `feature/tun-default-on`（自 `development@8089f66`）上进行，为用户授权的一次性分支例外；仅自动化验证。
- 源码提交 `b64e0d5`：保存 `tun.enable=false` 时 Windows 启动只启动/接管代理且不请求权限；`true`/无保存配置沿用 `b2cccee` 完整流程；启动结果与降级原因写日志。专项 24、全量 Flutter 366 PASS，0 FAIL；三文件 analyze 0 error/warning，info 不在改动行。
- 未改 Go/原生代码、未出新包；真实 UAC/网卡/流量/退出清理 TD01–TD06 NOT RUN。未推送、未建 PR。详见 `engineering/plans/tun-default-on-2026-10-07.md`。

## Windows 启动交互修正（2026-10-06）

- 用户明确要求完整启动软件即启动代理与虚拟网卡，替代上一批应用启动只读接管的产品策略。生产入口需完成一次完整流程，实际运行才显示开启；本会话手动关闭后，后台刷新、重连和恢复窗口不自动重开。`autoLaunch` 的 Windows 登录启动含义不变。
- 方案、任务与验收边界见 `engineering/plans/windows-startup-tun-2026-10-06.md`，本轮结果见 `engineering/testing/windows-startup-tun-2026-10-06.md`。旧 VM 清单 W01/W05 的启动预期仅适用于旧包；新候选按 WS01–WS08 及仍适用的原系统用例验收。
- 基线 `development@d2708be491c8002400a657b66bde93eda6a16ce3`，fetch 后领先远端 5 个本地提交、无落后、无开放 PR；最近 development CI 37430048151 对应旧基线 `2b587a8`，不是本轮通过证据。旧包 `f0b1b7eba271`、历史 worktree/stash 和 coverage/QA 原稿均保留。
- 本轮仅本地修复、测试、提交与独立新包；未授权远端推送、主线合并或部署。真实 Windows TUN/UAC/服务/网络验收仍等待获准隔离环境，不在开发工作站启动候选程序。
- 修复源码已本地提交为 `b2cccee7303d4d5e0f0a2d94d03fab367814bd6a`：Windows 一次完整启动、取消后明确重试、同步撤销旧开启意图、断线过期观测保护，以及 derived provider 延迟通知的配置去重。保留日志/代理组/provider 投影和旧购买功能。最终专项 27、全量 Flutter 365 PASS，均 0 FAIL/SKIP；定向分析 exit 0，0 error/warning，134 条 info 的源码对照和覆盖缺口详见报告。独立审查无剩余已知 Critical/High 代码问题；系统验收未完成。
- 新免安装包为 `dist/FreedomCloud-windows-amd64-preview-b2cccee7303d.zip`，152,707,659 字节，SHA256 `a04fa7408baa4a0fb8ce866ccc66189f06ca0b2594691b0828153cb38bd6c97b`。四组件从该干净源码重编、73 文件 ZIP/解压及交付副本 hash 检查通过；上一包未覆盖。构建仍使用已验证 CMake/Ninja 处理本机 VS 发现限制，阶段结果在本轮报告单列。
- 独立产物审查 PASS：四组件来源、Helper 实际内嵌 Core 绑定、全部 73 文件、清单覆盖、1,011 个有效模块文件及补丁输入均通过；未发现新的高风险产物问题。包未在工作站启动，不把包完整性或本地测试等同于 UAC/TUN/路由/Antigravity 实机验收。
- 新增源码 bundle 已 verify、独立 clone/检出精确 SHA、fsck 验证；SHA256 `0dfe6ac23aa4dd6a45c4a4788747f286d6736f854164d8d3ed0f750962af0fa0`。本轮原始 5 文件、autostash、旧包未变。代码、文档提交与包来源分别记录；未推送、未合并，WS01–WS08 仍待隔离环境验收。

## 内核与 TUN 可靠性批次（2026-10-06）

- 用户已授权在完善范围和任务后开发与测试。本批从 `development@2b587a80ad187995194608ffcd0f9f8cfa6695cd` 开始，沿用唯一开发入口。方案与依赖见 `engineering/plans/kernel-tun-reliability-2026-10-06.md`，测试矩阵、覆盖率及真实环境缺口见 `engineering/testing/kernel-tun-reliability-2026-10-06.md`。
- 固定 Mihomo `v1.19.32`（`88dcbf7f1614a67c3b36b848ee3592dfa92ada36`），保留原栈默认值与 uTLS 覆盖。带校验的最小生命周期补丁通过独立生成源和 overlay 加载，不改模块缓存、不追随 Alpha。构建入口和 CI 已接入；新云端检查尚未触发，不以开工基线 CI 作为新代码证据。
- UI 区分意图、实际状态和操作，Windows 的开启以真实 listener 与接口状态为依据；修复 IPC 假成功、后台授权、旧响应、只读挂接及退出/重连/迁移竞态。Agent/Helper 使用实际停止确认和 Core 会话归属；旧组件不满足合同则拒绝自动交接。微信、礼品卡兑换、账号订阅、匿名套餐和价格均保留。
- Core 最终 46 项含子用例 PASS，Windows race PASS，四个桌面平台 Core 编译及 Android arm64 c-shared 编译通过；Flutter 最终 342、Agent 64、Helper 29 PASS，均 0 FAIL / 0 SKIP。独立审查的问题已在最终源码关闭；既有 analyzer/clippy/format 问题与覆盖缺口在报告单列。
- 四个本地提交依次为 `1f750b1`（Core/构建）、`8bbdfc7`（Agent/Helper）、`b3f83bb`（Flutter）、`f0b1b7e`（范围/测试文档）。新 Windows 普通免安装包从 `f0b1b7eba271b2402a9a82809bec0ea53d9a3e8e` 干净源码完成四组件重编，`dist/FreedomCloud-windows-amd64-preview-f0b1b7eba271.zip` 为 152,707,168 字节，SHA256 `b45cf6f4f7a6e72499baedbb7e23893c694b4d9441d5ed79e966b99bdb41defb`。独立核对 73 文件完整 ZIP/解压/交付 hash、组件来源、Helper/Core 绑定和补丁 manifest 通过；旧包保留。后续证据文档提交不改变包来源。
- 真实 Windows TUN/UAC/服务交接/路由/Antigravity 流量均 NOT RUN；等待获准的隔离 Windows 环境。开发工作站服务和网络未更改。当前仅准备普通预览，不声称正式发行、严格 WFP 或全部应用流量已验收。
- 开工与新源码两份增量 bundle 已离线恢复/fsck 验证，原始 5 个 coverage/测试文件 hash 一致，旧包 `863298c7e3f4` SHA256 保持 `cae86090054186ed680e3467025f857badfca1a9f9670cfd6de9c98c4a0cafbd`。新源码 bundle SHA256 为 `d6c11db51cf451307cfae06190dfcceea548aa9fc53b4ae9626c40b685ac2b1f`，私有构建日志与测试证据一起保留。本批未推送、未创建/合并 PR、未改主线或远端保护。
- 下一步按 `engineering/testing/kernel-tun-vm-acceptance-2026-10-06.md` 执行 W01–W20。获取隔离环境后补真实运行证据，另经授权推送开发分支运行云端 CI；通过后再准备单一晋级 PR。不能从本地构建成功推导自动合并或正式发布。

## 唯一开发入口（2026-10-06）

- 用户要求收敛为一个日常开发分支和受保护的 `main`。今后日常只在 `development` 开发，默认工作目录为 `E:\CodeWorkstation\FlClashX`；旧任务分支和工作树只保留追溯，不继续写入。详细流程、门禁、任务与回退见 `engineering/plans/single-development-2026-10-06.md`。
- 本地 `main`、`development` 已从各自祖先无 force 快进到自有主线 `4738293ea90ca9b90afcc201a5c9a09b729a86ad`，当前检出 `development`。本地 `main` 已由跟踪上游 `origin/main` 改为跟踪自有 `freedomcloud/main`；开发分支跟踪并推向 `freedomcloud/development`。
- 日常小提交正常推送开发分支；按验收批次创建一个 `development → main` PR。普通 merge 后同步 `main` 回开发分支，避免 squash/rebase 长期分支造成重复提交和冲突。主线合并和正式发布分别按当次授权执行。
- 迁移前新建私有全 refs bundle，并完成 verify、离线 mirror 恢复和 fsck；5 份原稿逐项复制/hash 一致，原来源分支和 stash 未改动。95,620 个忽略文件及 5 个未跟踪文件与目标的 798 个跟踪文件没有同名或父子路径覆盖；实际切换使用 `--no-overwrite-ignore`。此前大备份和全部旧工作树保留，异地副本仍另行安排。
- 云端保护于 2026-10-06 07:28 UTC 配置并回读确认：开发分支只移除接收提交前的必需 CI 状态，正常推送后仍运行 CI；主线新增必需 PR、0 个必需审批，保留原有三项 CI、严格更新、讨论解决、管理员适用和禁止强推删除。其余保护字段逐项比较不变，API 前后快照保存在私有恢复目录；后续开工仍需核实最新设置。
- 本次 CI 改动仅为 quality-gate 增加 `push main`，已有测试命令与固定工具版本不变。该修改进入 `main` 前，旧主线仍不监听 push main；进入后才会产生最终主线提交检查。开发分支推送不触发现有正式发行；macOS 预览仍可手动触发，不默认增加每次提交的全平台构建。
- 本轮不合并新的主线 PR、不创建标签、不发布版本、不运行本机代理程序；此前 Windows/macOS 运行验收边界保持原记录。推送后以开发 HEAD 对应的实际 Actions 结果及本次最终报告为准，不能沿用上一批次 CI 作为新提交通过证明。

## 本轮主线集成进展

用户已接受先研究方案、规划任务，再执行主线集成和 Windows 普通预览；异地备份单独安排。执行方案见 `engineering/plans/mainline-windows-preview-2026-10-05.md`。以下是 2026-10-05 的新结果，后文保留首次整理时的来源与验证记录。

| 工作单元 | 最终 PR head | 新组合验证 | 主线合并 |
| --- | --- | --- | --- |
| PR #56 购买中心/匿名套餐 | `eeaf6b0468177313bb98709eb421c01757a97fb5` | quality-gate `37298035201` 三项成功 | `1efc29fe4aaeb29d849a4cd7be4b0728f66ca528` |
| PR #57 受保护启动/安装预检 | `5b2d8a9e88414327174e8bf241c86da89cc338f8`，正常合入 #56 后重验 | quality-gate `37307123153` 三项成功 | `6b6d1532e55b5c0717986a588f25c4ec86d1d34f` |
| PR #55 macOS 开发包 | `0ce398967a0299a0b5bcb97ab8cbc5aed1727bf9`，正常合入 #56/#57 后重验 | quality-gate `37307467535`；完整 macOS 构建 `37307460810` 均成功 | `14571208a15c732b11522da6607212d559ee2695` |
| PR #58 购买焦点与操作进度 | `694cec8f2bfe2f614067b325fbb4542ac1582d53` | [quality-gate 37310446707](https://github.com/Hao-Monster/FreedomCloud/actions/runs/37310446707)：Flutter 290 PASS、Core Go、M3 package checks 成功 | `863298c7e3f44e821eb6df5dedeb97f95d31d987` |

前三项均以普通 merge commit 合并，没有改写历史或删除源分支。主线 `1457120` 已验证包含三个原始 PR head，其 tree `5407871e914f5f326ed1316208566b4c4c38b838` 与最后受检组合 `0ce3989` 完全一致。当前工作流不监听 push main，不能把合并前检查称为自动发生的主线检查。

随后 [PR #58](https://github.com/Hao-Monster/FreedomCloud/pull/58) 也以普通 merge commit 合并。Windows 预览的功能源码基线为 `863298c7e3f44e821eb6df5dedeb97f95d31d987`，tree `18d658d6f785518012f5bfa6cab437582531948e` 与最终受检 head `694cec8` 一致；后续仅记录交付证据的文档提交不改变该包的构建来源。

组合 macOS 产物经过本地 SHA256、ZIP CRC、host/provider/helper 标识和 arm64 二进制核对，PASS：55,252,135 字节，SHA256 `c4e9c5fa88af8f29b1b4dcf252982db7dc898a61bf93c63434e6fb78ff7433d0`，来源严格为 `0ce3989`。它仍为 UNSIGNED，签名、公证、激活和真实设备运行 NOT RUN。

集成前另做增量保全：169 个 refs、4 个关键 HEAD/tree、唯一 stash 在独立 bundle mirror 中恢复一致，5 份原始未跟踪文件逐项 hash 一致。新增 bundle SHA256 `e2709fe9ee3bb10068abc99d50b8a8aee010f3427b78c964fe705055cca6cce4`；原有大归档、旧工作树和原稿保留。私有证据留在仓库外，未上传账号、卡号、订阅内容或原始日志。

四项合并后再做增量保全：新 bundle 235,929,439 字节，SHA256 `b82cd392fc98f5e4399c9cd392aaab4d628489621d9d62797771027633fb95e4`；`git bundle verify`、离线 `clone --mirror` 和 `git fsck --full --strict` 均 exit 0，172/172 refs 完整恢复，7 个关键提交的 tree 一致。原 HEAD、5 份原稿、stash 和两份旧 bundle 的哈希不变。临时 `refs/codex/turn-diffs` 数量变化已逐对象核对，不是用户分支或源码丢失。此快照对应源码整合完成时刻，不包含随后构建缓存；异地副本按用户决定另行安排。

本轮 Windows 预览前已修复 QA001 登录焦点和 QA003 操作进度文案：生产购买正文隔离侧栏焦点遍历，查询/兑换分别显示本操作进度，保留全局互斥和原消费逻辑。真实宿主/manager 回归在修复前为 6 PASS/6 FAIL；扩充后的最终目标测试 15 PASS，购买模块 181 PASS，均 0 FAIL/SKIP。变更 Dart 文件 `analyze --fatal-infos` 与 format 检查通过；测试边界和后续运行结果分开记录，不能把组件测试当 Windows 实机验收。

匿名目录于 2026-10-05 12:37:51 UTC 实际执行一次无 Authorization/Cookie 的 GET，HTTP 200、TLS 校验通过；同一响应经生产解析器离线验证成功。返回 1 个套餐、200 GiB，`onetime` 整数金额 15000 按客户端规则显示为 150.00；接口没有币种字段，不推断币种。此证据不代表 Windows 新包页面已验收。

Helper 重连调查见 `engineering/testing/helper-reattach-investigation-2026-10-05.md`：已确定调用链与状态缺口，但历史唯一触发入口未证实，也没有以恢复布尔值绕过信任检查。完整 Helper 修复和严格模式仍需要隔离环境；本机 UI 验收与新 native 全栈运行分别记录。存在自动订阅更新时，单纯打开新 UI 仍可能触发配置应用和授权；不能从“先连接旧 Agent”推断后台绝对不变。

Windows 普通免安装包已从上述 `863298c7` 干净源码完成重编，交付 `dist/FreedomCloud-windows-amd64-preview-863298c7e3f4.zip`，139,359,772 字节，SHA256 `cae86090054186ed680e3467025f857badfca1a9f9670cfd6de9c98c4a0cafbd`。72 文件完整解压及交付副本逐文件校验通过；未运行该包，原生验收仍为 NOT RUN。环境适配、失败历史、实际命令结果和受控测试条件见 `engineering/testing/windows-preview-build-2026-10-05.md`。

## 基线与保全

- 自有远端为 `Hao-Monster/FreedomCloud`（通常是 `freedomcloud`）；上游为 `pluralplay/FlClashX`（通常是 `origin`）。首次保全时的自有主线为 `cc1d31bc8b24b0103bc78dea2453768cb0c5a339`；后续集成结果见本文开头。
- 2026-10-05 首次保全时，本地 `main` 跟踪上游，旧 `development` 也落后于自有主线；当时保持原状。2026-10-06 的无 force 快进与唯一开发入口见本文开头，旧提交仍在新基线的祖先历史中。
- 原购买来源分支 `codex/m3-7-helper-diagnostics` 的提交保留；远端 `codex/purchase-source-snapshot-20261005` 另存其源历史。2026-10-05 的集成在独立工作树进行，之后的日常开发遵循本文开头的唯一开发入口。
- 初始 40 个工作树、全部本地 refs、stash 及 detached HEAD 已归入私有离线 bundle 和逐工作树快照。未提交文件保存精确副本、SHA256 及暂存/未暂存二进制补丁；忽略文件另行保存，不能只依靠 Git bundle。
- 恢复演练：16 个实际有未提交内容的工作树从独立 bundle 恢复后，文件 hash、Git 状态及暂存内容一致；23 个干净工作树 HEAD 已验证；1 个初始化异常另行保全。初次审计与备份时刻的 dirty 数量因生成文件的换行规范化而不同，不混为同一快照。
- 忽略文件归档已完成：164,527 个文件、42,850,666,804 字节逐文件 SHA256 核验通过，0 错误，复制期间未发现源文件变化。Windows 长路径复制的首次失败已通过续传和重新核验解决。另复核了原快照的 137 个现有变更文件，原位置内容仍与整理前一致。
- `locked initializing` 工作树缺 index、仅有 `.git`，694 个缺失文件不视为有意删除。其 `9ca5644` HEAD 已从离线 bundle 在隔离目录成功检出 694 个跟踪文件，状态干净；原异常目录保持不动，未提交这些删除状态。
- 所有原工作树、旧预览包和唯一 autostash 仍保留。忽略文件的最终完整性、私有路径和恢复步骤以仓库外备份清单为准；不将原始日志、凭据或测试账户状态推到公开仓库。
- 私有快照当前只在本机，远端分支保存经审查的源码。它不是操作系统、证书库或异地灾备，不以“已备份”推导可以删除原稿。

## 来源与集成映射

| 工作单元 | 原始来源 | 整合提交或分支 | 远端追踪 |
| --- | --- | --- | --- |
| 原生礼品卡购买中心 | `43ed4e2` | `ac58869`，`codex/purchase-integration-20261005` | [PR #56](https://github.com/Hao-Monster/FreedomCloud/pull/56) |
| MSVC/Ninja 警告参数修复 | `622abe1`；便携包分支 `f8c2d6a` 为相同 patch-id | `c463c32`，只吸收一次 | PR #56 |
| 未登录套餐与价格展示 | `7d02a94` | `33a8de2` | PR #56 |
| 项目协作规则 | `04be72f` | `cafb7a7` | PR #56 |
| 非 macOS 旧工作树归属审计 | 逐文件与历史提交核查 | `e9057cc` | PR #56 |
| Windows 受保护 Agent 启动和严格模式测试初始化原稿 | `FlClashX-test-portable-20261002` 的 4 个未提交文件 | `eac3938` 运行时、`780b31c` 安装预检，分支 `codex/protected-launch-20261005` | [PR #57](https://github.com/Hao-Monster/FreedomCloud/pull/57) |
| macOS 构建与完整开发包 | PR #55 原 head `7cce2da` | `ddc6965` 正常合并主线，`82ac8a4` 修复 helper，`4de17bd` 修复测试路径别名，`62d53a7` 拆分嵌入文件引用以匹配当前配置 | [PR #55](https://github.com/Hao-Monster/FreedomCloud/pull/55) |

购买、Windows 启动/测试安装、macOS 打包分为独立 PR；首次整理时未合并，随后经用户接受执行方案后按本文开头的顺序集成。每次合并都检查最终 head 的 CI、冲突和剩余验收范围。禁止从旧预览工作树整文件覆盖当前主线。

## 旧稿归属结论

- 非 macOS 34 个不同文件与 2 份补丁草稿，均已吸收、被主线改进替代或属于无效草稿，未发现应重复移植的独有有效功能。逐项证据见 PR #56 的 `engineering/reconciliation-audit-2026-10-05.md`。
- macOS 5 个旧工作树共 50 个文件条目：35 个与主线一致，15 个属于格式或主线后续修正；无需用旧文件回灌。详见 PR #55 的 `engineering/macos-reconciliation-2026-10-05.md`。
- autostash 共 18 项：15 项已精确吸收，3 项由后续主线改进替代。保留 stash，不 pop/drop。
- 构建链 `47438c1`、连接性能 `b77972f`、诊断隐私 `2a50b01`/`63c0d57` 虽仍显示本地独有提交，`git cherry -v freedomcloud/main` 均为 `-`，等价补丁已在主线，不能当作四项遗漏再次合入。
- `m3-2-zip-v4` 的独有草稿在 ZIP entry 打开写入后设置时间戳，已在内存复现 IOException；主线在打开前设置正确。保留草稿备份，拒绝合入错误行为。
- 旧 UAC 提交 `f082792` 的等效防重复提示行为已被 `99df219`、`bbece1b`、`6eb440b` 吸收，不按提交 SHA 不同判断为遗漏。
- 主工作树原有覆盖率、原生 QA 报告和焦点探针保存在原目录及私有快照中；它们不是未经审查即可公开上传的生产代码。

## 实际验证与预览边界

| 工作单元 | 已有证据 | 未代表的能力 |
| --- | --- | --- |
| 购买集成 | 本地 Flutter 全量 261 PASS，0 FAIL/SKIP；目标 Dart analyze 无问题；3 个 M3 包工具/manifest/evidence 脚本 PASS；`e9057cc` 对应 [CI 37293130664](https://github.com/Hao-Monster/FreedomCloud/actions/runs/37293130664) 的 Flutter、Go、package 三项 PASS | 不代表已在最终集成 SHA 重新做本机完整业务验收、签名发行或后端部署 |
| Windows 受保护启动/测试安装 | 23 项 Dart 测试、68 项只读安装预检用例和 3 个既有包工具脚本 PASS；路径异常 mutation 按预期失败，恢复后回归 PASS；两项审查缺口均已关闭；`780b31c` 对应 [CI 37295298644](https://github.com/Hao-Monster/FreedomCloud/actions/runs/37295298644) 三项 PASS | 本机未运行安装器、修改服务、安装驱动或切换网络；需要隔离 VM 验收 |
| macOS 开发包 | 本地 19 项 helper/工程合同测试和两份上游 ZIP SHA256 核验 PASS；`62d53a7` 的 [质量门禁 37296920008](https://github.com/Hao-Monster/FreedomCloud/actions/runs/37296920008) 三项 PASS；[完整构建 37296914010](https://github.com/Hao-Monster/FreedomCloud/actions/runs/37296914010) 的 Xcode、归档及上传均 SUCCESS | 命令行覆盖曾未解决旧产品引用问题，已移除并保留失败记录；当前产物明确为 unsigned arm64 开发包，不等同于 Apple 签名、公证、激活或真实设备验收 |

本机 Flutter 3.47.4 / Dart 3.13.3；CI 使用仓库固定 Flutter 3.41.7。Windows 相关新 Dart 文件 analyze 无问题；包含既有 `service.dart` 时有 13 项原有提示（1 warning、12 info，exit 2），与独立检查的主线基线相同，没有以修改规则消除这些提示。安装器验证使用 PowerShell 7.6.5 和临时文件/签名替身，不能代替真实 Authenticode、服务或驱动验收。

2026-10-04 的原生测试结果对应原来源与当时包，不回写成当前集成分支的运行证明。本次没有消费新的礼品卡。

仍需单独追踪：此前原生测试发现的 Helper 修复/UAC 问题；Windows 严格模式 VM、真实流量及签名验收；macOS Apple 签名、公证、受管激活和设备流量。未签名 macOS 开发包只能如实标记 unsigned，不要求用户关闭系统安全。

## 后续开发顺序

1. 读取项目 `AGENTS.md`，核实 `development` 本地/远端进度、未提交内容及自有 `main`；在唯一开发分支继续任务，不为独立任务默认新建分支或工作树。
2. 一次推进一个可测试增量；小范围相关门禁通过即可提供标明来源和缺口的部分预览，不把全平台正式发布门禁强加给每次 UI 迭代。
3. 对需共享的代码及时形成可审查提交并经授权推送 `development`；CI 和预览达到批次验收标准后，再创建一个晋级 PR。更新本台账，记录源提交、实际检查、预览 hash 和未验收项。
4. 主线合并、正式发布和历史清理分别按授权执行。保全完成不是自动删除旧分支、工作树或 stash 的授权。

## 套餐卡片富文本增量（2026-10-11至2026-10-12）

- 用户要求先核实“后台写什么、客户端展示什么”，不足直接开发；本轮起点development@c2fe8c5，fetch自有远端后领先10/落后0。原稿与QA资料保留，未改分支、stash、旧工作树或已有预览包。
- 已确认70c4643包含主要套餐字段和完整Markdown卡片；当前公开套餐正文163字符、三段说明、无图片。此次只补链接内部样式、下划线行内/代码/转义语义、代码块影响列表缩进，以及受限HTTPS图片，不改API、模型、套餐字段、价格、兑换、账户或其他页面。
- 新图片组件保留代理路由与TLS验证，不携带账号凭据，不跟随重定向；单图下载4MiB、取得槽位后15秒、解码最长2048px、共享4路并发和16MP目标栅格预算。失败/不安全/不支持资源保留alt，任意HTML不执行；动画仅首帧。
- 先冻结C1-C8矩阵；4条富文本缺陷和2条图片资源缺陷均有真实Red→Green。最终目标58 PASS、全Flutter **591 PASS/0 FAIL/0 SKIP**（97.33秒），定向analyze无问题，Windows目标debug UI资源编译exit0；本次diff行290/293、分支104/111。四种真实组件截图已查看，仍是合成内容而非当前客户端实机。
- 源码、测试与本节随本次development本地提交保存；详细命令、覆盖率、边界和审查在`engineering/testing/plan-card-rich-content-2026-10-11.md`。未推送、未PR/合并、未打新可执行包、未部署，旧CI不冒充本提交结果。
- NOT RUN：完整客户端/真实图片/TLS设备与兑换、原生解码中故障注入、Core/Agent/Helper和各平台实机。没有启动候选应用、改代理/TUN或消费卡码；如需让运行中的客户端包含新展示，应另从精确提交构建预览并遵守启动环境授权。

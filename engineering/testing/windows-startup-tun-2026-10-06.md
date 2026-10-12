# Windows 启动代理与 TUN 修复验证

状态：本地实现、自动化、独立代码审查与 Windows 预览构建完成；系统验收 NOT RUN。需求与任务见 `engineering/plans/windows-startup-tun-2026-10-06.md`。基线为 `d2708be491c8002400a657b66bde93eda6a16ce3`；历史 kernel-tun 报告仅证明其记录的来源。本次只改变 Flutter 启动编排和相应设置/测试，不重新归因前一批 Core/Rust 测试。

## 环境与证据

Windows 开发工作站；Flutter 3.47.4、Dart 3.13.3。CI 当前固定 Flutter 3.41.7，版本不同且本轮未触发云端 CI。受控测试替代平台 IPC、文件和权限等外部边界；未运行候选程序、未修改工作站代理/服务/路由。真实网卡、UAC、服务交接和流量仍为 NOT RUN。

私有日志与增量恢复证据位于 `C:\Users\冯飏\AppData\Local\FlClashX-Recovery\20261006-startup-tun-followup`，不将账号、完整配置或订阅写入仓库。现有 coverage/原生 QA 原稿保留，新增覆盖率单独输出。

## Red 与缺陷修复证据

- 启动入口 Red：先引入可测试的 `initializeRuntime()` 外部边界，保留原“只读观察”行为；测试期待 profile/authorize/backend/init/config/listener/reflect，实际只有 `observe`，1 FAIL，exit 1。它不是缺少方法导致的编译失败，也不是未经修改的完整 Application 运行。原始 `flutter-startup-red.log` 保留。
- 首次目标 Green 尝试仍失败：取消授权后真实 derived provider 的延迟通知发生在 busy 清除之后，多排了 1 次配置；断言要求 0。`flutter-startup-first-green-failure.log` 保留。生产监听器加入已消费意图序号，保留失败断言；普通模式变化仍可触发更新。
- 独立审查修复了组件 hash 检查期间断连后的旧 on 接管、实际 `updateStatus(false)` 未撤销启动意图，以及绕过旧初始化时漏掉的日志订阅/节点与 provider 投影。新关闭在排队前同步撤销旧意图；已提交后端交接只允许最低恢复，取消后不配置或启动 listener。

## 证据边界与审查

测试执行真实 `AppController.initializeRuntime()`、实际 TUN Switch 回调、实际 `updateStatus(false)` 与生产共用的 Riverpod 配置监听组件，替换文件/IPC/权限等外部效果。生产 `Application` post-frame → `AppController.init()` → `initializeRuntime()` 接线由独立源码审查确认；完整 `init()`/Application 接线尚无自动端到端证据。删除生产调用不能保证由当前 fixture 捕获，真实窗口仍待隔离验收。

本地 profile 预检只证明路径可读、UTF-8 有效且非空；YAML/脚本和最终配置语义由现有解析/Core 接受边界决定，拒绝不能显示成功。不要把预检称为完整配置验证。服务交接、日志订阅、系统状态栏等真实插件结果同样不由受控 effects 证明。

本轮未新增生产依赖，未变更 Core/Agent/Helper 源码与锁文件；四组件重编只用于来源一致的预览。无远端 CI、真实 Windows 系统验收或正式发布结果。之前 Core/Rust 检查仍属之前批次，不计作本次新执行。

源码检查点：`b2cccee7303d4d5e0f0a2d94d03fab367814bd6a`，提交 `fix(windows): start proxy and TUN on application launch`。全部变更源码在提交前与测试时记录的 SHA256 一致。增量 bundle 为 236,010,302 字节，SHA256 `0dfe6ac23aa4dd6a45c4a4788747f286d6736f854164d8d3ed0f750962af0fa0`；`git bundle verify`、独立 clone/精确 SHA 检出和 `git fsck --full --strict` 均 exit 0，构建输入干净。5 份原始未提交文件、既有 autostash 和旧包哈希复核保持。原始私有日志、包与忽略文件不由源码 bundle 包含，分别保留原位置；没有删除历史工作树或分支。

## 执行结果

命令在仓库根执行，Flutter/Dart 使用 `E:\flutter\bin`。覆盖率路径为上述私有目录中的 `startup-lcov.info`。计数为 PASS/FAIL/SKIP；单项与全套重叠，不相加。

| 命令 | 状态 | exit | 计数 | 耗时 |
|---|---|---|---|---|
| `flutter test --no-pub test/clash/windows_startup_controller_test.dart`（Red） | FAIL，目标缺陷 | 1 | 0/1/0 | runner 1 秒；未单独计完整命令耗时 |
| `flutter test --no-pub test/clash/windows_startup_controller_test.dart test/clash/tun_config_scheduling_test.dart` | PASS | 0 | 27/0/0 | 22.16 秒 |
| `flutter test --no-pub --coverage --branch-coverage --coverage-path=<私有目录>/startup-lcov.info` | PASS | 0 | 365/0/0 | 83.27 秒；runner 64 秒 |
| `dart analyze` 下列 10 个变更文件 | PASS，保留 info | 0 | 0 error / 0 warning / 134 info | 55.58 秒 |
| `git diff --check -- lib test arb` | PASS | 0 | 不适用 | 未单独计时 |
| 私有 `build-tools/Test-PreviewBuildTools.ps1` | PASS | 0 | 56/0/0 | 未单独计完整命令耗时 |

分析文件：`lib/controller.dart`、`lib/common/windows_tun_startup.dart`、`lib/common/windows_tun_prepare.dart`、`lib/common/tun_runtime.dart`、`lib/clash/service.dart`、`lib/manager/clash_config_update_listener.dart`、`lib/manager/clash_manager.dart`、`lib/views/application_setting.dart`、`lib/widgets/tun_status.dart`、`test/clash/windows_startup_controller_test.dart`。133 条 info 对应 HEAD 中未改源位置，1 条为既有 bool 回调类型的换行；这是逐行源码对照，不是重新运行 HEAD analyzer 的对照实验，不能声称全仓 lint 已清零。

全套最终 365 包含最后两个审查用例。此前 363 日志及覆盖率保留为 intermediate，最终覆盖率针对冻结源码重新生成。完整命令、起始时间、退出码、最终源码 hash 与覆盖率统计保存在 `verification.json`。中途补日志订阅时曾出现对 void 返回值使用 await 的编译错误，已移除 await 并由最终目标及全套重新验证；不将该编译错误计为 Red 行为证据。

## 自动化验收矩阵

| 标准 | 实现/测试位置 | 结果与证明范围 |
|---|---|---|
| S01 四种保存偏好仍启动一次 | controller 初始化、`windows_startup_controller_test.dart` | PASS；完整受控顺序与一次性 Future |
| S02 已运行匹配后台只接管 | startup 协调器及上述 fixture | PASS；无授权、配置或 listener 重启，允许无本地 profile |
| S03 缺配置、初始化/配置/listener/观测失败 | 本地文件预检及上述 fixture | PASS；错误明确，无下游假成功；真实 YAML/Core 语义仍待系统验证 |
| S04 取消授权后现有 Switch 重试 | 实际 controller + Switch + 共用配置监听器 | PASS；一次授权、明确重试完整启动、无延迟重复配置 |
| S05 旧组件与失配、断线旧状态 | 既有 `windows_tun_prepare_test.dart` + 新 startup fixture | PASS；复用原合同回归，新增组件检查期间断线不接管旧 on；真实身份/服务为 NOT RUN |
| S06 取消/停止/退出与异步阶段竞态 | profile/auth/init/config/listener 可控 Future、实际 `updateStatus(false)` | PASS；较新意图截断，已提交迁移只最低恢复 |
| S07 手动关闭后重复初始化、配置调度 | 上述 fixture + `tun_config_scheduling_test.dart` | PASS；不重启，混合 mode/TUN 与后续外部 TUN 变化不被误吞；真实 resume/reconnect NOT RUN |
| S08 非 Windows 和购买回归 | 保留非 Windows 分支、全套购买/配置测试、源码审查 | 自动化及源码审查 PASS；跨平台设备启动与 Windows 设置真实窗口 NOT RUN |

## 覆盖率与明确缺口

LCOV 为本次加载/插桩文件：行 4,679/27,380（17.09%），分支 1,254/9,364（13.39%）。不是全仓功能完成率。

| 文件/区域 | 行覆盖 | 分支覆盖 | 本次变更行 |
|---|---|---|---|
| `windows_tun_startup.dart` | 52/53，98.11% | 25/32，78.12% | 52/53 |
| `clash_config_update_listener.dart` | 17/17，100% | 6/6，100% | 17/17 |
| `tun_runtime.dart` | 108/115，93.91% | 49/58，84.48% | 5/5 |
| `windows_tun_prepare.dart` | 21/31，67.74% | 11/20，55% | 0/3 |
| `controller.dart` | 35/1,163，3.01% | 21/548，3.83% | 23/107 |
| `clash/service.dart` | 0/510 | 0/253 | 0/20 |

默认 Windows effects、真实 IPC、组件文件与进程交接、完整 `init`、系统状态栏和成功后日志/列表投影未由受控 fixture 执行。这些路径经过独立源码审查和随后编译，仍需要 WS 系统验收。设置页新增 Windows 条件及缺配置文案分支亦没有真实窗口证据。没有修改、降低或跳过既有测试/覆盖率门禁。独立审查未发现剩余已知 Critical/High 代码问题；上述运行证据缺口阻止将候选称为正式验收版本。

## 干净构建与交付

源码与四组件来源均为 `b2cccee7303d4d5e0f0a2d94d03fab367814bd6a`，独立 detached 构建快照不是第二开发分支。私有复现入口：`build-tools/Build-OrdinaryPreview.ps1 -Repo C:\Users\冯飏\.codex\builds\startup-tun-b2cccee7303d -ExpectedSha b2cccee7303d4d5e0f0a2d94d03fab367814bd6a -Output <私有目录>/windows-preview-b2cccee7303d-r1 -StandaloneClone`。实际环境：Flutter/Dart 如前；Go 1.25.13、Rust 1.98.1、MSVC 14.44.35207、Windows SDK 10.0.26100.0、CMake 3.31.6、Ninja 1.11.1。ATL 来源与所有运行库输入 hash 随私有 inventory/包内 COMPONENTS 记录。

| 构建步骤 | 状态 | exit | 耗时 |
|---|---|---|---|
| Flutter 依赖恢复 / Go module verify / driver analyze | PASS | 均 0 | 89.60 / 17.81 / 1.29 秒 |
| Core / Agent / Helper 从同 SHA 重编 | PASS | 均 0 | 71.68 / 75.26 / 128.51 秒 |
| Flutter config-only | FAIL，已知 VS 发现限制 | 1 | 6.62 秒 |
| 已验证 CMake 配置路径 | PASS | 0 | 7.11 秒 |
| Flutter assemble / Windows build | PASS | 均 0 | 156.10 / 70.29 秒 |
| bundle copy / package / ZIP roundtrip | PASS | 均 0 | 2.44 / 22.03 / 20.66 秒 |

共 18 阶段：17 个 exit 0，1 个明确记录的 VS 发现失败。脚本只接受预先限定的这类发现错误，随后 CMake/Ninja 的真实构建均通过；未注册/安装 Visual Studio 或修改全局环境。不能把 18 个阶段全称为 exit 0。构建不含测试计数，包验证计文件数。

交付：`dist/FreedomCloud-windows-amd64-preview-b2cccee7303d.zip`，152,707,659 字节，SHA256 `a04fa7408baa4a0fb8ce866ccc66189f06ca0b2594691b0828153cb38bd6c97b`。旁边保留 `.zip.sha256` 及同名解压目录；完整 73 文件 ZIP/解压校验通过，交付副本与原 bundle 逐文件 hash 一致。Core SHA256 `6caa426bb583547d9123bfe3f746893ffbff9719ecadf972aee93259d24add64`，Helper 绑定对应此 hash。Mihomo 仍为 v1.19.32 加原有生命周期补丁，不在本轮再次变更内核版本。

包内 `PREVIEW-README.txt` 明确启动会自动请求代理/TUN、可能需要 UAC；`BUILD-INFO.txt` 和 `COMPONENTS.json` 标注来源及普通未签名预览边界；不含严格 WFP 驱动。旧 `f0b1b7eba271` 包保持原 SHA256 `b45cf6f4f7a6e72499baedbb7e23893c694b4d9441d5ed79e966b99bdb41defb`。没有运行新 EXE、安装服务或改变当前工作站网络。后续证据文档提交不改变包的源提交。

独立产物审查 PASS：流式重算 ZIP 与原 bundle、验证解压及最终交付目录均为 73 文件、逐项同名同 hash；SHA256SUMS 精确覆盖其余 72 文件；Helper 二进制内嵌 Core hash 与清单/实物一致。复算 1,011 个有效模块文件、6 个补丁源、2 个上游输入、生成器及 go.mod 均一致，有效模块 hash 为 `c316c60c9b11cc8f494749c6907a51168dba9bacfc7e5ae9a685d7dd67d26cd5`。未发现新的高风险产物问题；此结论仍不是运行验收。

## 运行验收补充

以下项目均为 NOT RUN；原因是未提供获准的可恢复 Windows VM/专用测试机。这是具体系统层验收缺口，不能以 fixture 或构建替代。

| ID | 操作 | 预期与证据 |
|---|---|---|
| WS01 | 有有效配置，保存 autoRun=false/TUN=false，完整启动新进程 | 无需点击代理/TUN；按需一次 UAC 后真实网卡 up，代理监听运行，UI 与实际一致 |
| WS02 | 启动时取消 UAC，切页/轮询/恢复窗口，再点击现有重试 | 自动阶段不重复弹窗；明确重试完成全流程，无需先手动开代理 |
| WS03 | 已有同批后台代理/TUN 运行，再完整启动 UI | 同一实例、连接保持；不重复授权、重启或配置 |
| WS04 | 本会话手动关 TUN 或代理，再恢复窗口/重连 | 保持关闭；只有下次完整启动或明确开启才发新意图 |
| WS05 | 缺少配置、坏配置、旧 Agent/Helper、权限或接口失败 | 明确失败/未知；不显示成功，不停不明归属的后台 |
| WS06 | 等待授权/配置/迁移时取消、关闭或退出 | 迟到结果不重新开启，不出现并行 Core，状态如实显示 |
| WS07 | 检查 Windows 设置与购买页 | 无矛盾的应用内 autoRun 开关；登录启动设置独立；微信、兑换、账号订阅、匿名套餐均保留 |
| WS08 | 按原 W17/W18/W20 做网络矩阵、IDE 和回退 | 实际出站与规则符合预期；成套回退可用，不从网卡 up 推导所有流量成功 |

完整隔离前置条件继续遵循 `kernel-tun-vm-acceptance-2026-10-06.md`。先核对新包来源/hash，再执行本表及原清单中仍适用的项；旧包 W01/W05 的只读启动预期已被本需求替代。

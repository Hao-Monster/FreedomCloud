# Windows 全配置节点延迟预览：复审与交付（2026-10-15）

本轮未发现阻塞预览的新增缺陷；完整 Windows amd64 WIP 包构建、独立静态审计及解压校验均通过。没有修改产品代码，没有运行候选程序。真实业务验收由用户执行。

## 交付物

- 完整目录：`E:/CodeWorkstation/FlClashX/dist/FreedomCloud-windows-amd64-all-delay-wip-1509079d76b5`；入口为其中 `FlClashX.exe`。不要单独复制 EXE 或混用旧组件。
- ZIP：`E:/CodeWorkstation/FlClashX/dist/FreedomCloud-windows-amd64-all-delay-wip-1509079d76b5.zip`，154,097,799 bytes（146.96 MiB）。
- ZIP SHA256：`892e73f7948a775c11df548d5dfacda10081505b040d1f4804eee2dd28f554a8`。
- 可恢复源码：`dist/FreedomCloud-source-all-delay-wip-1509079d76b5.zip`，SHA256 `e21e81b49c3c626b906a558314f528d8effb77fb7c6cdfba7871d0aba5a48fd5`。
- 证据目录：`E:/CodeWorkstation/FlClashX/dist/all-delay-wip-evidence-1509079d76b5`，附源码清单、恢复校验、复审、测试摘要、构建、审计及解压报告。
- 前一个 P1 完整目录仍在 dist；旧 ZIP 保留于 `E:/Temp/fcx-p1-4c1df825-r2/FreedomCloud-windows-amd64-nodeoverview-p1-wip-4c1df825fcf3.zip`，已重新核对原 hash，保留不覆盖。原 dist 旧 ZIP 当前不存在；首次交付记录核验因此停止，随后定位并核验原 WorkRoot ZIP，未改动或重建旧包。

## 来源与复审结果

`development@e3ab52bd1afc46b009907f0ee7386fd228914d8e`，暂存区为空；59 个变更文件与两阶段验证清单对应，冻结 1004 个源码/文档文件。源码快照 ID：`1509079d76b5eb7887db1013a334aeadcc2ca6350a1605f502e4bf06b22fe914`。Git SHA 只表示基线，WIP 快照标识实际构建输入。

重点复查：全量入口不受展示筛选影响、当前入口独立、配置失败隔离、动态批次预算、取消与迟返回收、历史归属/覆盖/容量、provider 只读获取与纯解析动作、共享 IPC 大小上限和协议资源限制。未发现新增阻塞项。详见证据目录 `code-review.md`。

本轮重跑 Dart 目标 **105 PASS / 0 FAIL / 0 SKIP**（exit 0，22.936 秒）；Go Core 全套 **120 顶层 / 含子测试 164 PASS**，0 fail/skip（exit 0，21.752 秒）；`git diff --check` exit 0。

相同源码的上一轮完整证据经 hash 核对后沿用：Flutter **886 PASS**；Go default/gVisor 各120顶层、race38顶层；Dart analyze **0 error / 11既有warning / 886info，exit 2**，无新增 warning，不能称静态分析零告警。完整命令、覆盖率、Red→Green 与未运行项见 [实现报告](all-profile-node-latency-2026-10-15.md) 和证据目录。

## 构建与独立审计

- 完整构建 exit 0，用时 **598.417 秒**。Core、Agent、Helper、Dart AOT、runner 和仓库原生插件均从同一冻结快照重编；第三方插件从锁定依赖重编。
- 工具链：Flutter 3.47.4 / Dart 3.13.3，Go 1.25.13，Rust 1.98.1，CMake 3.31.6，Ninja 1.11.1，MSVC 14.44.35207 / SDK 10.0.26100.0 / ATL 14.51.36237。未升级依赖；Flutter/Rust 离线依赖构建。
- `flutter-config-only` exit 1 为已有的 VS 自动发现精确例外，随后指定 CMake/MSVC 的配置、实际 AOT 与 native 编译均通过。未绕过其他失败。
- 独立静态审计 **8/8 PASS**（9.053 秒），审计工具 guard 最终 **8/8 PASS**。适配仅涉及本次59文件精确清单及 README 同义披露文案；组件、路径、来源和绑定断言保留。
- ZIP、构建目录与交付解压目录 **74 文件一致，73 条 checksum**。Source ZIP 恢复后逐文件 hash 一致；构建期间源码语义变化为0，额外可编译源码为0。
- Helper 二进制内嵌实际新 Core hash；UI 编译参数与其一致，AOT 与构建输出一致。14 插件/111 原生输入文件、9 CRT、16补丁模板/15 overlay映射均核验。该静态证据不等于运行时组件身份确认。

| 组件 | 字节数 | SHA256 |
|---|---:|---|
| `FlClashCore.exe` | 60,786,176 | `38e54b70c4bdfbb323441746f297c1d69aea21aef65276a464a9182053096ba6` |
| `FlClashAgent.exe` | 1,026,048 | `644537f042bc349d4209e925f11fec472009ab9063a4956204d8ccf0d37d3a5d` |
| `FlClashHelperService.exe` | 1,031,680 | `0ab67f0c496971eddd332bfd27ede2f01288b0d4d04749c7d612e8fabbe4f547` |
| `FlClashX.exe` | 134,144 | `fd97caf36bbb81a1e857cdde4e10071b554744d907ed585ddff5afd333ec41f5` |
| `data/app.so` | 16,089,992 | `c1fadf325a17fd719cd3ba6b8b8c4b8941dc3bb0d4cc8b66be4509088afe5ec3` |

| 构建步骤 | 状态 / 退出码 | 秒 |
|---|---|---:|
| `source-archive` | PASS / 0 | 0.782 |
| `go-version` | PASS / 0 | 0.552 |
| `rust-version` | PASS / 0 | 1.094 |
| `cmake-version` | PASS / 0 | 0.979 |
| `ninja-version` | PASS / 0 | 0.331 |
| `flutter-version` | PASS / 0 | 2.513 |
| `flutter-pub-get` | PASS / 0 | 81.671 |
| `backend-build` | PASS / 0 | 268.259 |
| `flutter-config-only` | EXPECTED_VS_DISCOVERY_FAILURE / 1 | 2.962 |
| `cmake-configure` | PASS / 0 | 5.505 |
| `flutter-assemble` | PASS / 0 | 66.966 |
| `windows-build` | PASS / 0 | 62.633 |
| `bundle-copy` | PASS / 0 | 1.305 |
| `tray-imports` | PASS / 0 | 0.206 |
| `package` | PASS / 0 | 10.878 |

## 用户测试重点与边界

1. 保留完整旧包，按自己的测试安排启动新目录内的程序。免安装不等于配置隔离；完整启动会启动或接管代理，TUN 依已保存设置执行，权限提示由用户处理。
2. “测试当前配置”保持独立：检查点击后开始、大批次不在30秒被截断、进度按实际请求计数。
3. “测试全部节点延迟”：在设置搜索/选中配置/只看可用的情况下仍遍历全部配置；一份异常配置不阻断后续正常配置；只测延迟，不测带宽。
4. 验证 provider 缓存命中和缺失两类情况、进度与取消、旧延迟保留及下一次有效测量覆盖；独立测试不切换现役节点、不污染实时延迟。

已知边界：危险协议/传输、链式代理、严格模式、provider 特殊 override/全局 Age 密钥/具名下载代理缺缓存等仍明确未测。历史上限5000条/4MiB，满额保护旧数据并报告新增拒存。活动列表仍依运行时叶子，文件 provider 历史单独标识；节点投影丢失后需重新解析。不能把“遍历全部配置”理解为已经支持所有协议。

真实窗口、产品 IPC/QuickJS、真实订阅网络、现役接管/代理/TUN、长时稳定性均 **NOT RUN**。普通未签名预览没有 strict WFP 驱动/Broker。没有 Git 写操作、候选启动、UAC 或现役服务/网卡/配置操作；提交和推送仍由技术负责人管理。

本报告和台账更新发生在冻结源码构建、审计完成之后，仅属于交付文档，不改变包内的冻结源码；历史阶段“未打新包”的记录保留原义。

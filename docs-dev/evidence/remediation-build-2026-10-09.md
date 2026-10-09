# Windows 资源修复预览构建与交付证据

日期：2026-10-09（Asia/Singapore）。源码提交：`7d0a00777342ab4503e2ae20d4f4435742538d60`，分支`development`，提交说明`fix: address audited resource and lifecycle defects`。后续文档提交不改变包内源码来源。

## 产物

- 文件：`FreedomCloud-windows-amd64-resourcefix-7d0a00777342.zip`
- 大小：**152,946,986 bytes**，ZIP含73个文件。
- SHA256：`f0aae7982964e9e29c22022b76fb8f8996f8d2507f0db77aaa2964bcc78fea40`
- 主交付：`E:\CodeWorkstation\FlClashX\dist\FreedomCloud-windows-amd64-resourcefix-7d0a00777342.zip`
- 聊天副本：`C:\Users\冯飏\Documents\Codex\2026-10-08\new-chat\outputs\FreedomCloud-windows-amd64-resourcefix-7d0a00777342.zip`
- 两处均有同名`.zip.sha256`，复制使用拒绝覆盖模式，复制后重新计算SHA256一致；旧包保留。
- 类型：普通、未签名、Windows amd64免安装预览。不包含严格WFP驱动/Broker；没有宣称严格模式验收。

## 源码与构建输入

工作目录：聊天`work/remediation-build`，其中`source`由精确Git archive生成；`native-build`、`bundle`、`zip-roundtrip`均为本次新建的独立目录，没有借用旧包中的Core/Agent/Helper/插件。

| 输入 | 核对值 |
|---|---|
| Git commit | `7d0a00777342ab4503e2ae20d4f4435742538d60` |
| Git tree | `5beef766a13b6a23edd94f91ac10a729633c535f` |
| source archive SHA256 | `662cc8674b1762f3db75f3b44e9d3691559f5e4a3aaf4a8818155ed26ac1e34e` |
| source inventory SHA256 | `f4389fff56d1fffa9009e7aa413aa6a20b0e0aaf8cdc3bbe0ac597ff768ae3ba` |
| source文件数/解压bytes | 919 / 60,671,139 |

独立来源预检：Git tree、ZIP、inventory清单一致。当前Git换行设置使863个文本文件在归档中使用CRLF；归一CRLF后逐项核对Git blob SHA1，其余56项按原bytes核对。构建后912文件保持inventory bytes，7个生成registrant只允许行尾变化；未把源ZIP声称为逐字节等同Git blobs。7份构建工具hash已记录/核对。

应用Core/Agent/Helper/UI和仓库插件由该提交重新编译；14个Windows原生插件的依赖锁条目及Windows源码文件hash清单写入`COMPONENTS.json`。第三方插件从锁定Pub/git依赖重编，不伪称源码属于本仓库提交。Flutter engine、QuickJS bridge、MSVC CRT与EnableLoopback为单独核验的预置输入。

## 实际构建

命令（当时HEAD与修复提交一致、tracked tree干净）：

```powershell
& 'C:\Users\冯飏\Documents\Codex\2026-10-08\new-chat\work\remediation-build-tools\Build-Remediation.ps1' -ExpectedSha '7d0a00777342ab4503e2ae20d4f4435742538d60'
```

构建脚本拒绝已有工作目录、输出覆盖和来源变动。重跑必须核对实际HEAD及输入，并使用新的构建/输出路径，不能覆盖本次证据。

- 开始：2026-10-09 14:40:59 +08:00；完成：14:48:50；整体约7分51秒，最终exit0。
- Flutter3.47.4 / Dart3.13.3；Go1.25.13；Rust1.98.1；MSVC14.44.35207、SDK10.0.26100.0、经hash校验的ATL14.51.36237。
- Core使用项目正式`setup.dart` buildCore与固定Mihomo overlay；Helper在新Core hash计算之后编译；Agent亦完整重编。Rust使用locked/offline依赖。

| 步骤 | 状态 / exit | 秒 |
|---|---|---|
| source archive | PASS / 0 | 3.80 |
| Flutter offline pub get | PASS / 0 | 25.90 |
| Core + Agent + Helper release | PASS / 0 | 122.32 |
| Flutter config-only | 已识别环境失败 / 1 | 2.90 |
| CMake configure | PASS / 0 | 3.58 |
| Flutter release AOT | PASS / 0 | 59.62 |
| Windows runner / native plugins | PASS / 0 | 43.84 |
| Bundle install | PASS / 0 | 1.33 |
| tray DLL imports | PASS / 0 | 0.06 |
| 包元数据、checksums与ZIP | PASS / 0 | 9.75 |
| 73文件ZIP解压集合/长度/hash、输出复制 | PASS | 含在整体时间，未单独计时 |

Flutter config-only失败的唯一错误为无法发现Visual Studio工具链；工具仅允许这一已知情况继续。随后以已核验的本机MSVC/CMake/Ninja完成真实编译，不删除编译步骤或忽略未知错误。保留strict-broker依赖既有4项dead-code警告及MSVC `/W3`被`/W4`覆盖提示。

## 关键组件

| 组件 | bytes | SHA256 |
|---|---|---|
| FlClashCore.exe | 60,702,720 | `5d85a90aa0330205845c563c0c97ee50a7c38d439c9649c580f6190a2c66c568` |
| FlClashAgent.exe | 1,026,048 | `0bfcaf03bb5b54809113c8d49f710ea6d0d45832cf30318bc482800d4d65de80` |
| FlClashHelperService.exe | 1,022,976 | `c531f0f94435d5f0588ecb3fd44c26442d34bb891795074ec38781a9049d9b39` |
| FlClashX.exe | 134,144 | `b593f183dc55d21f70eb237d77feafaf561054271ee450a263853313aed47c6c` |
| data/app.so | 15,041,416 | `22d570605d699d0d285b90623d25be2669a0674bedac8cecee4f9e35c00c4bd1` |
| tray_manager_plugin.dll | 116,736 | `2e0aa31d61e16f4ac6d6ec39d223c10281878b880ddc299e8051faeaca856c64` |
| proxy_plugin.dll | 98,304 | `12b4abd7c86def98fc418d967a58707796be95f3d976e3ba53c60f3c7e5f0585` |

Core为`v1.19.32`固定源加审计overlay，`CORE-PATCH.json`随包保留。UI `CORE_SHA256` 与Helper编译绑定均使用上述新Core hash。新tray DLL导入`DestroyMenu`；完整PE架构、必要资产、输入变动、backend→bundle逐组件hash及ZIP roundtrip均已检查。

PE架构边界：29个应用/插件/运行库PE为x64；`EnableLoopback.exe`是仓库原有x86预置辅助工具，单独记录来源。不能把“Windows amd64包”写成包内所有PE均为x64。

完整机器记录：聊天`outputs/resourcefix-build-7d0a00777342.json`、`work/remediation-build/build-report.json`、`logs/steps.jsonl`及各step日志；包内`COMPONENTS.json`、`BUILD-INFO.txt`、`CORE-PATCH.json`、`SHA256SUMS.txt`与`PREVIEW-README.txt`。

## 独立最终产物审查

结果：**PASS，未发现阻塞交付的问题**。只读审查，未执行包内程序。

- ZIP与bundle的73/73文件路径、长度、SHA256全部一致；解压内容152,912,956 bytes，内部校验72项完整覆盖（排除校验文件自身），外部校验与build-report一致。没有重复/越界路径或bundle重解析点。
- Core/Agent/Helper与backend manifest和本次源快照输出一致；Agent/Helper与Cargo Release文件一致。runner及14个插件与本次native-build Release一致，AOT与本次Flutter输出一致。
- Helper二进制偏移771785找到唯一完整Core hash，并与`allowed_hash() -> env!("TOKEN")`实现核对。UI生成配置的DART_DEFINES解码后APP_VERSION/CORE_VERSION/CORE_SHA256一致；这是编译输入核验，未声称已从AOT读取运行值或运行UI验收。
- `CORE-PATCH.json`的generator/go.mod、10个补丁模板、4个上游源输入匹配；1009原始模块文件聚合为`adb2170dcce92d63d9da0102eb6669bf8b719c6d9ed33b985c3d0a3aa9c1dd7a`，1015有效模块文件聚合为`129ccaab30a64fb785e3ca5f5c626d3180fcfd172cfacf156e729b63f92e436c`。生成清单/backend复制件/包内清单一致，controller及history补丁实际应用；最终Core的Go build info为windows/amd64、with_gvisor及本次生成模块。
- 32个组件描述与实际文件匹配；14个插件的111个原生输入文件和锁条目匹配，3个仓库插件关联源码commit，11个第三方插件未误标。Flutter engine、QuickJS、9个CRT、EnableLoopback与实际预置输入逐bytes一致。
- tray DLL确实导入DestroyMenu/CreatePopupMenu而无RemoveMenu；四应用组件和tray/proxy均未签名，符合声明。没有strict驱动/Broker/manifest，也没有夹带用户配置、订阅、安全存储、数据库、密钥文件或运行日志。
- README的配置共享、启动副作用、未签名/普通预览及运行NOT RUN边界准确。静态产物完整性不扩大为Windows运行或长时资源验收。

## 平台边界与回退

运行验收为**NOT RUN**：未启动新客户端、未退出当前版本、未改代理/TUN/SCM/WFP/驱动/用户配置。普通启动可能按已保存设置启动/接管代理并触发TUN权限流程，由用户安排本机测试；免安装不代表用户配置隔离。

完整解压到新目录，不混用不同包的组件；保留完整旧包及配置备份。回退由用户退出新包后启动完整旧包，不删除用户数据。真实Windows/Android/系统级故障与长时指标按原TODO继续验收。本轮没有推送、PR、合并或发布。

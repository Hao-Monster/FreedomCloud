# Windows 普通免安装预览构建证据

日期：2026-10-05。功能源码：`863298c7e3f44e821eb6df5dedeb97f95d31d987`，tree `18d658d6f785518012f5bfa6cab437582531948e`。该源码与 PR #58 最终受检 head 的 tree 一致。此报告的后续纯文档提交不是本包的新构建来源。

## 交付物与范围

- ZIP：`dist/FreedomCloud-windows-amd64-preview-863298c7e3f4.zip`，139,359,772 字节。
- SHA256：`cae86090054186ed680e3467025f857badfca1a9f9670cfd6de9c98c4a0cafbd`。
- 同名目录为已解压便携文件；复制到交付目录后再次核验 ZIP 和全部 72 个文件的名称、长度、SHA256，与源 bundle 一致。
- UI、Core、Agent、Helper 均从同一准确源码重新编译。Core 内嵌 `vcs=git`、`vcs.revision=863298c7e3f44e821eb6df5dedeb97f95d31d987`、`vcs.modified=false`；Helper 编译绑定本次 Core SHA256。
- 普通、未签名的部分功能预览，未包含 strict driver、Broker 或 strict manifest。不是正式发布，不代表安装、严格模式或真实网络验收。
- 包内包含 `BUILD-INFO.txt`、`COMPONENTS.json`、`SHA256SUMS.txt` 和 `PREVIEW-README.txt`。实际步骤时间、输入来源和失败历史在私有构建证据中；BUILD-INFO 的时间按源码提交时间固定，不冒充实际编译时间。
- 二进制中的部分编译器/依赖源码路径包含构建用户目录，尚未进行对外分发的路径脱敏；不将此本机预览包称为已完成隐私清理的正式发布物。包文件清单没有用户配置、账户数据或凭据文件。

## 环境与执行结果

Windows x64；Flutter 3.47.4 / Dart 3.13.3、Go 1.25.13、Rust 1.98.1、MSVC 14.44.35207、SDK 10.0.26100.0、ATL 14.51.36237、CMake 3.31.6、Ninja 1.11.1。本机版本与 CI 固定的 Flutter 3.41.7 / Go 1.26.0 不同，不声称跨工具链字节级可重复。

私有驱动调用仓库 `setup.dart` 的 `Build.buildCore/buildAgent/buildHelper` 与公开打包 API；未复制旧程序充当新构建，未修改业务源码或 SDK。`<repo>`、`<output>`、`<driver>` 是每次创建的新源码副本和私有证据路径，不是可直接省略的参数。

| 步骤 / 命令 | 状态 | exit | 秒 |
|---|---|---:|---:|
| `flutter pub get --offline` | PASS | 0 | 65.56 |
| `go mod verify`（离线） | PASS | 0 | 5.83 |
| `dart analyze <driver>` | PASS | 0 | 1.09 |
| `Build.buildCore`；随后 `go version -m` 核对实际 VCS | PASS | 0 | 19.36 + 0.54 |
| `Build.buildAgent` | PASS | 0 | 89.03 |
| `Build.buildHelper`（绑定本次 Core） | PASS | 0 | 131.98 |
| `flutter build windows --config-only`（含已记录的准确 defines） | EXPECTED_VS_DISCOVERY_FAILURE | 1 | 5.61 |
| CMake / Ninja Multi-Config 配置 | PASS | 0 | 7.70 |
| `cmake --build <build> --config Release --target flutter_assemble` | PASS | 0 | 112.01 |
| `cmake --build <build> --config Release` | PASS | 0 | 58.05 |
| `cmake --install <build> --config Release`（使用已核验 cache 中的新 bundle prefix） | PASS | 0 | 1.78 |
| 公开打包 API | PASS | 0 | 16.93 |
| ZIP 完整解压、精确文件集/长度/SHA256 roundtrip | PASS，72 文件 | 0 | 20.19 |

Visual Studio 注册缺失为已核实环境问题；仅匹配唯一已知错误并核对新生成的配置、插件路径、编译参数和源码状态后，才使用已安装的 MSVC/CMake/Ninja 完成实际构建。该命令的 exit 1 没有改写成 PASS。安装输出目录在 CMake 配置时通过 `-DCMAKE_INSTALL_PREFIX=<new-bundle>` 固定，复制前再次核验 cache；没有向系统目录安装。Agent 的 strict-broker 库产生 4 条未使用代码警告，完整日志保留，没有压制警告或修改业务代码。

相关自动化验证：私有构建工具最终 56 PASS / 0 FAIL / 0 SKIP；购买目标 15 PASS、模块 181 PASS；最终功能 PR 的 CI Flutter 290 PASS，Core Go 与 M3 package checks 成功。具体购买测试命令、Red→Green 和覆盖率见 `purchase-preview-regression-2026-10-05.md`。构建步骤没有测试用例计数，不能与上述套件计数混加。

## 失败历史与纠正

1. Rustup 的 cargo/rustc 为官方符号链接，初始通用输入门禁拒绝。仅允许其精确解析到同目录普通 rustup.exe，并记录目标哈希；源码和输出路径的链接限制保持。
2. 生成文件原 Git mode 为 100755，初始工具误假设 100644。改为保持 HEAD 的合法 regular mode，要求 HEAD/index/规范化 blob 与原始字节全部一致；没有纳入语义变化。
3. Go 离线缓存缺包；官方 HTTPS 直连出现 IPv6 超时。仅下载子进程使用本机既有代理，保留 sumdb；补齐锁定依赖后在线/离线 verify 和 Cargo locked/offline 检查通过。锁文件不变。
4. managed worktree 的 `.git` 指针文件不被本机 Go 的 VCS 根检测识别。旧尝试虽完成三个原生组件，但按来源门禁停止。最终从已验证 bundle 创建独立 clone，避开 AppData 的 MSIX 路径映射，再完整重编，实际 VCS 检查通过。

每次失败输出、日志和旧可用包均保留，没有用失败目录覆盖后续结果。未安装工具、驱动或服务，未修改当前应用配置。

## 原生验收边界

本包真实启动、购买页面实机交互、新 Agent/Core/Helper 运行及 Helper/UAC 行为均为 **NOT RUN**。本机当前订阅自动更新与保存的 TUN 配置使新 UI 启动可能进入配置应用及授权路径，取消 UAC 也未证明不会改变后台状态。默认不改变当前代理的约束下，需要隔离环境或明确的受控测试安排后执行。

没有新增真实礼品卡消费，没有把历史用户手动兑换成功或旧包的测试结果记为本次验收。Helper 调查和后续合同见 `helper-reattach-investigation-2026-10-05.md`；其问题仍未关闭。

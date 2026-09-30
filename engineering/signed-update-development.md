# 签名完整应用更新：开发交付说明

状态：代码已接入关于页“检查更新”。未运行构建、测试、签名、安装器或真机验收；不能据此声明平台更新已验证。

## 支持的发行格式

- Windows `inno-exe`：完整 Inno 安装包，包含当前版本的签名回滚安装器。已安装 Helper/Broker/驱动服务时使用此格式。
- Windows `portable-zip`：无已安装特权服务的完整便携包，并排版本目录与显式回滚。存在服务时拒绝便携更新，避免 Helper 内置 Core 哈希失配。
- Linux `portable-zip`：完整应用、Core、Agent 和资源，按签名清单恢复文件权限；不支持以此覆盖发行版包管理器文件。
- macOS `macos-app-zip`：完整 `FlClashX.app`，同时验证 CMS 固定证书、固定 Developer ID Team、完整 codesign 和 Gatekeeper 接受状态。

不单独更新 Core。发布者必须先按实际构建链签署 Core，再生成依赖该 Core 哈希的 Helper/UI，随后生成不可变完整更新包。

## 编译参数和外部依赖

客户端编译时配置：

1. `FCX_RELEASE_MANIFEST_URL`：对应平台和架构的直接 HTTPS CMS 清单 URL。禁止重定向、明文 HTTP 和 URL 用户信息。
2. `FCX_RELEASE_CERT_SHA256`：CMS 发布证书 DER 的 SHA-256，64 位十六进制。Windows 安装器和应用必须使用同一证书；该证书同时需被目标 Windows 信任。
3. `FCX_MACOS_TEAM_ID`：macOS 10 字符 Apple Developer Team ID；Windows/Linux 不使用。

参数可通过 Flutter 的 `--dart-define=名称=值` 传入。项目 `setup.dart` 桌面构建入口也读取并校验上述同名环境变量，再传给 Flutter；因此使用 setup 构建时应设置这三个发行环境变量（第三个仅 macOS 使用）。缺失参数给出明确原因，不跳过签名校验。

Windows 使用系统 PowerShell/.NET CMS、Authenticode 和原生签名安装器。macOS/Linux 使用 PATH 中的 Python 3.9+ 和支持 `cms`、`x509` 的 OpenSSL；不内置密码算法，不自动提权安装解释器。macOS 还使用系统 `codesign`、`spctl` 和原生授权提示。解释器或 OpenSSL 缺失时会报告依赖错误。

## macOS 启动行为变化

**普通本地 macOS 开发构建不要求购买 Developer ID。** 原生 bootstrap 支持两个明确分离的路径：正式应用存在有效 Team 时，Core 必须通过同 Team 的签名要求；没有 Team 时，只接受应用和 Core 都通过 codesign 完整性验证且明确标记 `Signature=adhoc` 的本地开发构建。后者安装/变更 Core 前展示完整 SHA-256、说明不具备发布者信任，要求用户明确选择本地开发安装，再由管理员授权提示确认。不是无签名兜底；无效签名仍拒绝。已安装完全相同哈希且 root 所有/权限正确的 Core 不重复提权。

**正式在线更新仍必须满足固定 CMS 发布证书、Developer ID Team、codesign 与 Gatekeeper/公证要求**，不接受本地 ad-hoc 包充当可信更新。Apple Developer ID/公证与 Windows 自签名测试证书是不同前提。

特权 Core 从旧的用户可写 `~/Library/Application Support/com.follow.clash/cores/FlClashCore` 改到根用户所有的 `/Library/Application Support/FlClashX/Core/FlClashCore`。原生 bootstrap 按上述正式签名或明确授权的本地开发路径验证包与 Core，将 Core 复制到该目录的 root-owned 临时目录，核对 SHA-256 和 codesign 后设置 root:wheel/4755 并原子替换。判断升级/回滚使用内容哈希而非修改时间。

设置、订阅、配置、Agent token 和其他用户数据目录不迁移、不删除。旧用户目录的 Core 不被更新器自动删除。新 bundle 的 Core 已由 CMS 文件清单约束，bootstrap 再核对签名和复制后的哈希；拒绝路径链接和非 root 所有的特权目录。

## 发布工具

以下工具仅创建本地发行产物，不上传，不输出私钥：

- `tool/New-SignedPortableRelease.ps1`：Windows 完整便携目录 → ZIP、附带内容的 CMS `.p7m`。
- `tool/New-SignedInstallerRelease.ps1`：新旧完整 Inno 安装器及对应 UI 可执行文件 → `inno-exe` CMS 清单。
- `tool/new_signed_unix_release.py`：Linux 完整目录或已签名/公证的 `FlClashX.app` → ZIP 和 CMS。

Windows 工具从 CurrentUser/My 中按 `CertificateThumbprint` 使用本地证书。Unix 工具接受本地 `--certificate`、`--key` PEM 路径；可使用 `FCX_SIGNING_KEY_PASSWORD` 环境变量解锁加密私钥。不要将私钥、密码或这些本地文件提交到 Git。

Inno 工具的 `-UpdaterAwareInstallers` 是发布者对**两个**安装器协议的明确声明：新旧安装器都必须实现 `/FCXUPDATE`，不强杀应用、不删除用户数据。需要以更新后的模板重新封装历史版本回滚安装器，保持旧 UI 内容 SHA 对应实际运行版本。普通历史安装器不能仅标记后直接视作兼容。

清单 schema=1，包含版本、目标平台架构、发行格式、到期时间、完整产物大小/SHA-256。便携清单逐文件包含大小、哈希；Unix 额外包含类型、权限和受约束的相对链接。Inno 清单包含 `installerProtocol=fcx-update-v1`、新版本应用 SHA，以及精确匹配当前版本和应用 SHA 的 rollback 安装器描述。

## 切换、恢复与真实状态

- 下载限制清单 2 MiB、产物 2 GiB，连接和读取超时、总下载截止时间，ZIP 展开总量和单文件量受限。
- 应用内先完成新包和恢复材料校验，再调用现有 `handleExit()`。独立工作器等待退出，不强杀应用。
- 便携版本保存在应用支持目录 `signed-updates/versions`，使用原子 current/previous 指针。首次回滚基线是本机旧安装的完整哈希快照，不是给未签名历史文件补造远程签名。
- Windows 安装器只提权运行已验证、持有只读锁的 Inno 可执行文件。安装失败或安装后的应用 SHA 错误会尝试签名旧安装器重装。**这不是保证成功的数据库/MSI 原子事务**；恢复也可能失败，错误及安装包保留用于用户恢复。
- macOS/Linux 同样保留并排版本、原子指针与回滚入口；新进程在初始观察期退出时恢复旧指针并启动旧版。进程存活不等于业务验收通过。
- Windows 生成 `FreedomCloud Updated` 桌面快捷方式；Linux 生成同名应用菜单入口；macOS 在 `signed-updates` 目录生成 `FreedomCloud Updated.command`。旧安装快捷方式保留并仍指向旧目录。
- 状态记录位于 `signed-updates/last-result.json`，UI 会呈现失败。成功状态仅表示已启动/安装器完成，均标记等待用户验收。

历史版本目录及签名恢复材料不会自动删除。发布证书轮换、真实发行源、目标系统信任和实际平台验收均需对应发布环境提供，代码不会制造这些外部证据。

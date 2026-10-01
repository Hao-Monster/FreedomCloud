# macOS managed strict proxy 开发交付

本实现采用 macOS 11+ Network Extension **system extension** 和 managed per-app VPN。源代码与部署资料已接线；构建、签名、安装、MDM 下发、流量验证及验收均由使用者执行，本轮未运行。

## 生成部署 profile

先在目标 Mac 上使用应用的原生身份导出入口导出 JSON。导出过程必须通过 Security.framework 检查真实已安装应用及 provider 的代码签名；不要手工编造签名 identity。生成器只检查格式和字段关联，不会也不能在其他机器离线证明签名真实性。

JSON 格式为 `schemaVersion: 1`，以及 `provider` 对象和 `applications` 数组。每项必须含 `identifier`（实际 bundle ID）、`signingIdentifier`、`teamIdentifier`、`designatedRequirement`、`path`（规范绝对可执行文件路径）、`codeDirectoryHash`。provider 必须是本次部署的已签名 system extension。`applications` 限 128 项；provider 运行配置独立限制 256 个精确身份。辅助进程的身份需在应用策略中显式登记；profile 不凭通配符允许任何 helper。

使用 Python 3.9+；以下只是使用示例，本次未执行：

```sh
python3 tools/macos/New-ManagedStrictProfile.py \
  --host-bundle-id com.follow.clash \
  --provider-bundle-id com.follow.clash.StrictProxy \
  --team-id YOURTEAMID \
  --control-key-account '实际控制账户的UUID' \
  --identities '/安全目录/native-identities.json' \
  --output '/安全目录/freedomcloud-strict.mobileconfig'
```

`controlKeyAccount` 是应用提供的账户 UUID 标识，不是密钥；profile 的 VendorConfig 只包含此标识。控制密钥、SOCKS 凭据、证书私钥不进入 profile。生成器拒绝未知 JSON 字段和重复键、重复应用、非法 UUID、超过 2 MiB 的输入，以及覆盖已有文件。输出为**未签名** XML profile；生成器不安装、不注册 MDM、不上传、不执行签名，不读取 Keychain。

输出包含：

- `com.apple.vpn.managed.applayer`：`VPNType=VPN`、host `VPNSubType`、唯一 `VPNUUID`，`VPN.ProviderType=app-proxy`、provider bundle 和其原生 `ProviderDesignatedRequirement`；应用网络请求触发 On Demand。
- `com.apple.vpn.managed.appmapping`：每项包含实际 Identifier、SigningIdentifier、DesignatedRequirement、Path，并引用同一 VPNUUID。没有域名例外、直连兜底或全系统流量捕获。

每次生成分配新的 profile/payload/VPN UUID。部署更新时应由 MDM 管理员按既有安装记录执行替换，不叠加安装。Apple 的 appmapping payload 在 macOS 是单例；若设备已有其他 appmapping，需在 MDM 管理端审阅并合并映射，不能直接覆盖已有业务。

## 部署约束

- Apple TN3134 限制 app-proxy `.appex` 在 macOS 走 App Store；当前直发方式使用 `.systemextension`，由 Host 请求激活。普通 ad-hoc 或自签名不能赋予受限 Network Extension entitlement。
- Host/provider 使用同一 Team，分别提供具备 Network Extension 及共享 Keychain access-group 权限的 provisioning profiles：`FCX_HOST_PROVISIONING_PROFILE`、`FCX_STRICT_PROVISIONING_PROFILE`。Release bundle 为 `com.follow.clash.StrictProxy`，Debug 为 `com.follow.clash.debug.StrictProxy`。
- 在管理端按组织制度批准 system extension、部署 profile；账户标识须对应已经安全配置的控制材料。部署前确认 Core 的已认证入口和 provider 状态；导出文件包含应用路径等设备资料，应按内部部署资料保管。
- 未匹配本地策略的受管流量由 provider 拒绝。应用/helper 更新、路径变化、身份变化后，应重新导出并更新精确策略及 MDM 映射。Apple 默认 app mapping 也捕获匹配应用的 spawned helper 流量，这不等于 provider 自动信任该 helper。
- 尚未验证真实设备的授权、Keychain 跨上下文访问、MDM 映射、断线和 provider 重启阻断、IPv4/IPv6/TCP/UDP/DNS/QUIC、升级和移除恢复。不能把成功生成 XML 当成严格防泄漏已经验收。

## 对照的 Apple 官方定义

- [Network Extension deployment TN3134](https://developer.apple.com/documentation/technotes/tn3134-network-extension-provider-deployment)
- [VPN payload schema](https://github.com/apple/device-management/blob/release/mdm/profiles/com.apple.vpn.managed.yaml)
- [App-layer VPN payload schema](https://github.com/apple/device-management/blob/release/mdm/profiles/com.apple.vpn.managed.applayer.yaml)
- [App mapping payload schema](https://github.com/apple/device-management/blob/release/mdm/profiles/com.apple.vpn.managed.appmapping.yaml)

对照日期：2026-10-01。工具只序列化上述字段；不绕过操作系统签名或设备管理审批。

## 应用操作与恢复代码

连接设置中的 macOS 盾牌打开受管严格代理面板，可激活系统扩展、导出签名身份、
选择 MDM 配置、指定 DNS IP、下发当前 PROXY/BLOCK 策略、读取状态和停止转发。
同一 Core 只允许一个受管严格 profile，旧 profile 必须由管理端替换。

策略编辑会先要求 provider 保存空策略并关闭已有流，再写入普通应用规则。
空策略不会解除 MDM 捕获：所有已捕获应用保持阻断，直到用户重新应用完整策略。
“停止转发”也保存阻断状态，防止系统自动重连时恢复旧的转发意图。
无法连接 provider 时不会假装撤销成功，须先启动受管 provider。

Agent 使用原生 Keychain 保存成功的基础配置与严格入口恢复快照，按普通配置→
固定 TCP/UDP 入口的顺序恢复。Core 单独崩溃、Agent 重启及基础配置重载均走相同
严格凭据与端口约束；端口冲突、Keychain 锁定或配置拒绝返回失败，不能换到普通
代理或直连。无 Agent 的源码兼容启动路径不提供后台持久恢复保证。

TCP 使用按目标组认证的 SOCKS5；UDP 使用带 HMAC、generation、association 和
重放窗口的 FCXD。IPv4/IPv6 使用 v1，macOS 域名端点使用 v2；域名在认证后
传给 Core 的既有严格代理解析路径，不在扩展中调用系统解析器。系统 DNS 归属、
FakeIP 恢复、IPv6/QUIC、应用升级、系统睡眠与
崩溃场景均未执行验证，不能据源码存在宣称验收完成。

本轮没有执行测试、构建、lint、类型检查、生成器、签名、安装或部署。

## 登录后台 Agent

面板提供显式启用和移除登录后台 Agent 的按钮。注册前核对应用、Agent、固定
Core 的签名及 Team，Core 固定在 `/Library/Application Support/FlClashX/Core/FlClashCore`，
其目录链必须由 root 所有且不可被普通用户写入。登录项只属于当前用户，配置写入
其私有 LaunchAgents plist，命令参数不包含密钥。注册成功不代表 Agent 已健康运行。

已存在的 detached Agent 不会被强制终止；它可能持有 singleton lock，需通过应用
正常退出后让 launchd 接管。移除时仍核对组件和注册归属，组件缺失或签名失效时
返回错误并保留注册。登录项仅覆盖用户登录期间，不提供未登录阶段的 Core 服务。

FCXD v2 的域名最多 253 ASCII/IDNA 字节，UDP 数据最多 16 KiB；域名长度、标签、
地址类型及完整 HMAC 都经过处理后才交给 Core。Windows 保持 v1 协议。以上均为
源码交付，尚未执行编译、协议互通或故障恢复验证。

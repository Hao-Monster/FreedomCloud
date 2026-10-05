# 原生礼品卡中心

本次范围：把购买页接入 Xboard-Go，使用原生 Flutter 登录、礼品卡预览、确认兑换、历史和订阅同步。礼品卡是本阶段主要开通与续费方式，不创建普通支付订单、不接入在线收银台。注册和找回密码打开现有网站；微信联系入口保留，可读取后台配置的礼品卡商店链接。

## 接口和业务边界

- 默认 origin 为 `https://fast.hjy.ca:8443`，构建可用 `--dart-define=XBOARD_BASE_URL=https://example.com` 指定另一个 HTTPS origin。禁止路径、查询、内嵌凭据和 HTTP 降级。
- `/api/v1/passport/auth/login` 的 `auth_data` 用作 Bearer 凭据；相邻的 `token` 是订阅令牌，不能用于登录认证。
- 读取 `/api/v1/auth/session`、`/api/v1/subscription`、`/api/v1/user/purchase-channels`。本页用于普通用户账户，分销商身份会明确拒绝。
- 礼品卡调用 `/api/v1/user/gift-card/check`、`redeem`、`history`。Bearer 路径兼容 legacy envelope，不能假设与 cookie-session 返回结构相同。
- 支持现有 1–4 类礼品卡，type 4 购买兑换码为重点。权益、叠加、套餐兼容性、待支付订单限制、卡片过期、原子发放均沿用服务端判定。
- 盲盒查询返回的随机样本不当作承诺权益展示。余额卡到账不当作已开通套餐。合法空奖励显示“未增加额外权益”。
- 兑换前展示当前账户和真实权益变化，只有明确确认才调用兑换。输入变化使预览失效；不允许并发点击兑换。

## 不确定结果与恢复

兑换请求前，先将待确认卡号、类型、code ID、历史 usage ID 基线写入系统安全存储并读回验证。写入失败不会发起兑换。超时、连接中断、服务端异常或无法解析成功响应保留待确认状态，阻止再次输入其他卡号。

- type 4 的同账号、同卡号重复兑换由后端返回原始成功记录，恢复可安全调用 redeem，不能对已用卡重新 check 并据此判断原请求失败。
- 其他类型没有相同幂等保证。客户端只查询历史，以准确 code ID 和不在请求前基线中的 usage ID 对账，不会自动重放兑换，不会用掩码前缀猜测结果。
- 历史基线与恢复扫描最多 20 页；无法确认时保留待确认状态，交由人工核对。旧服务器缺少 code ID 时，普通卡仍能正常成功兑换，但超时结果无法自动准确对账。
- Xboard-Go 配套变更仅给 legacy 查询、兑换、历史响应追加 `code_id`，不变更礼品卡计算规则、数据库结构、支付能力或已有字段。要启用普通卡的自动历史核对，需要先发布该后端增量；本次未部署。
- 已确认兑换和订阅同步结果分开显示。下载失败只重试同步；会话过期清除登录凭据、提示重新登录，并保留本次已确认成功提示。待确认记录按 origin 与账号隔离，退出登录保留恢复记录。

## 本地订阅与安全

`PurchaseProfileSynchronizer` 用 origin + 账号 ID 的散列关联配置。令牌轮换仍复用同一配置；可接管完全相同 URL 且未归属其他账号的导入配置。保留用户名称、节点选择、覆盖规则、展开状态及其他账号配置。同步不自动切换当前配置；当前正在使用同一配置时遵循现有自动应用行为。

下载与磁盘保存分离，保存前核对配置来源和最新本地设置；用户在下载期间删除配置或更改来源会中止保存。配置仍经过现有 Clash 核心校验，保存配置失败明确报告同步失败。安全映射、配置文件和 SharedPreferences 不构成跨存储事务；没有宣称崩溃时具备全局原子性，失败后可重试同步，不重兑卡片。

账号凭据和待确认完整兑换码使用 `flutter_secure_storage`，不写普通 SharedPreferences 或诊断日志。历史再次掩码；密码只用于登录。配置订阅 URL 按现有客户端配置存储方式保存。

账号请求与托管订阅下载单独强制验证 TLS，保留已有代理/TUN 路由。托管订阅仅允许同源 HTTPS 重定向，最多五跳，不通过 `flclashx-newdomain` 转移凭据。代理日志只记录主机，下载异常不暴露 URL、令牌或响应配置。

新增安全存储依赖，保持现有 win32 主版本。Linux 构建安装 libsecret 开发包，Deb/RPM 声明运行依赖，AppImage 打包对应共享库；Linux 仍需要可用且已解锁的 Secret Service。macOS 使用本应用的 login Keychain，不要求跨应用共享钥匙串。

## 验证矩阵

| 验收或风险 | 验证位置 | 验证层级 |
|---|---|---|
| 登录、Bearer/订阅令牌区分、legacy envelope、异常响应 | `test/purchase/xboard_api_test.dart` | API 契约与真实 HttpClient 配置探针 |
| 明确确认、禁用/加载/错误/成功、盲盒和余额卡文案、中文窄屏 | `test/purchase/purchase_widgets_test.dart` | Flutter 组件与交互 |
| 重复提交、重启恢复、精确历史对账、401、成功后同步失败 | `test/purchase/purchase_manager_test.dart` | 状态与异步回归 |
| 持久化读回、账号及 origin 隔离、损坏记录拒绝 | `test/purchase/purchase_storage_test.dart` | 安全存储应用契约，底层测试替身 |
| 去重、令牌轮换、本地编辑保留、来源变更及删除 | `test/purchase/purchase_profile_sync_test.dart` | 配置同步边界 |
| 严格证书、代理保留、重定向限制、失败脱敏 | `test/purchase/secure_subscription_test.dart` | 下载传输契约 |
| 中文登录、权益预览、成功但同步失败、320px | `test/purchase/purchase_render_test.dart` | 真正 Flutter 离屏渲染，合成数据 |
| 四类卡 code ID 一致、掩码碰撞不混淆、认证及其他用户隔离 | Xboard-Go `internal/httpapi/gift_card_code_identity_test.go` | HTTP 入口和独立真实 SQLite |

渲染命令 `flutter test --no-pub test/purchase/purchase_render_test.dart` 将图片写入 `build/purchase-preview/`。可用 `PURCHASE_PREVIEW_FONT` 指定本机中文字体；不将操作系统字体提交到仓库。

## 本机验收边界

环境为 Windows，Flutter 3.47.4 / Dart 3.13.3；仓库 CI 使用 Flutter 3.41.7。针对性测试均已验证，完整回归、覆盖率和检查结果见下方执行记录。

`flutter build windows --debug --no-pub` 因本机没有 Visual Studio C++ 工具链而失败；`flutter doctor -v` 确認 Visual Studio 未安装。没有把离屏渲染当作 Windows 可执行文件验收。真实 Windows/Android/macOS/Linux 安全存储、安装包启动、代理环境端到端、真实账户登录、礼品卡消费和配置核心完整同步未运行；不得把契约测试作为这些平台验收的替代。

本次没有推送、创建 PR、部署、迁移、购买礼品卡或消费真实卡片。后续经授权发布顺序为后端 additive 接口，再客户端；使用测试账号及专用测试卡验证首次开通、同套餐续期/流量叠加、冲突拒绝、重启恢复、同步失败重试和账号切换。

## 执行记录（2026-10-04）

Flutter 命令使用 `E:\flutter\bin\flutter.bat`，Dart 使用 `E:\flutter\bin\dart.bat`。未降低或跳过现有测试。

| 实际命令 | 状态 / 退出码 | 结果与耗时 |
|---|---|---|
| `flutter test --no-pub --coverage --branch-coverage --reporter expanded` | PASS / 0 | 219 通过、0 失败、0 跳过；测试计时 55 秒，含已有回归与 124 项购买相关测试 |
| `dart analyze lib/manager/purchase_manager.dart lib/models/xboard.dart lib/services/purchase_storage.dart lib/services/purchase_profile_sync.dart lib/services/secure_subscription.dart lib/services/xboard_api.dart lib/views/purchase.dart lib/views/purchase/center.dart test/purchase` | PASS / 0 | No issues found；包含宿主、全部新增模块和测试 |
| 扩展上述 analyze 至 `lib/models/profile.dart lib/common/request.dart lib/common/http.dart setup.dart` | FAIL / 1 | 无 error；4 个 setup.dart 既有 warning，另有旧文件 lint info。独立分析 `git show HEAD:setup.dart` 的基线副本复现同样 4 个 warning，未为通过检查重构旧模块 |
| `git diff --check`（两仓库） | PASS / 0 | 无空白错误；Windows CRLF 转换提醒不是失败 |
| Xboard-Go `go test ./internal/httpapi -run '^TestGiftCard(BearerCodeIdentityAcrossCheckRedeemAndHistory\|CodeIdentityRequiresAuthentication)$' -count=1 -v` | PASS / 0 | 2 个顶层用例、4 个卡类型子用例；约 1.36 秒 |
| Xboard-Go `go test ./internal/httpapi ./internal/store -run 'Gift(Card\|Purchase)' -count=1 -json` | PASS / 0 | HTTP 10、store 46 个 pass 事件（含子用例），0 fail、0 skip；包耗时 2.42 / 4.75 秒；Go 1.26.8 Windows amd64 |
| Xboard-Go `go vet ./internal/httpapi` | PASS / 0 | 无诊断 |
| `flutter build windows --debug --no-pub` | FAIL / 1 | 缺少 Visual Studio C++ 工具链，约 7 秒即退出；没有生成本期可执行包 |
| 平台密钥库、原生安装包、真实账户兑换、完整核心导入 | NOT RUN | 工具链与真实业务验收边界；未消费真实卡片 |

针对性测试数量：API 31、manager 19、storage 16、profile sync 9、secure download 35、widgets 13、render 1。离屏渲染的四张图已人工检查，包含中文标签、明确的当前账户、兑换确认、失败状态和窄屏换行。日期包括年份，避免年度续期前后显示相同月日而产生歧义。

覆盖率来自本次 Dart VM LCOV。七个新增生产模块合计行覆盖 948/1036（91.5%）、分支 278/359（77.4%）；把改写的购买页宿主也计入，则为 949/1076（88.2%）、279/375（74.4%）。宿主仅 1/40 行被加载，真实 provider、核心校验、磁盘提交与平台存储没有被这些契约测试替代。覆盖率不是原生业务验收证明。已有 Profile、Request 和打包脚本的本次接入点还需要平台集成验证。

有效 RED → GREEN 证据：

- 后端追加字段前，四类卡的 code ID 一致性用例失败；追加字段后全部通过，认证测试保持通过。
- manager 回归先复现 native String 校验异常逃逸、同步 401 保留登录、成功后会话过期丢状态（16 pass / 3 fail），修复后 19/19。
- profile sync 先复现下载期间名称被覆盖（7 pass / 1 fail），合并最新本地设置并增加来源变更验证后 9/9。
- storage 先复现空/含换行 Bearer、非正数 code ID 被接受（14 pass / 2 fail），修复后 16/16。
- secure download 先复现非 HTTPS redirect 的 StateError；错误脱敏增强测试又复现 HTTP/网络/畸形 Location 泄露 URL（22 pass / 13 fail），修复后 35/35。

独立审查复核 TLS、日志、401、重放、账号隔离、并发配置编辑和打包依赖；没有发现遗留 Critical/High 实际缺陷。仍保留上述跨存储非原子性、平台运行和真实业务验收限制。

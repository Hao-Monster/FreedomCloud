# 完整购买流程测试方案与用例任务 v1

日期：2026-10-10。状态：执行前候选矩阵；等待需求基线确认后冻结并编写可执行用例。以下新用例全部NOT RUN，不是已通过报告。

适用方案：[完整购买流程v1](../plans/purchase-checkout-2026-10-10.md)。
本矩阵采用推荐的“新余额购买事务原子执行”预期，不把旧接口分段充值的预期混入。旧单独兑换仍按旧规则回归。

## 1. 环境与隔离

- FlClashX当前基线70c4643；Xboard-Go本地07476e0。测试时再固定最终源码SHA和dirty状态。
- 全部交易数据使用独立临时SQLite与QA-CHECKOUT-*合成用户、套餐和卡。禁止读写真实卡库存、账户余额、线上订单或共享数据库。
- 服务端测试通过真实HTTP handler与SQLite；跨语言链路仅启动测试handler，不启动生产调度、邮件、节点或通知进程。
- Dart真实Dio/manager连接隔离测试服务；如使用TLS，仅测试SecurityContext信任夹具证书，不放宽生产HTTPS或全部证书校验。
- 不启动完整客户端，以免自动启动代理/TUN；本轮可用真实Widget树离线渲染，真实窗口/平台密钥库仍单独验收。
- 凭据、完整卡码、订阅令牌不写测试快照/普通日志/报告；引用稳定合成身份，失败诊断也脱敏。

## 2. 验收矩阵

预计用例位置：

- API：test/purchase/checkout_api_test.dart。
- 状态机：test/purchase/checkout_manager_test.dart。
- 持久化：test/purchase/checkout_storage_test.dart。
- UI/宿主/渲染：test/purchase/checkout_widgets_test.dart、checkout_host_test.dart、checkout_render_test.dart。
- 后端：Xboard-Go/internal/httpapi/purchase_checkout_test.go、internal/store/purchase_checkout_test.go及迁移测试。

以上新文件名为任务位置建议，当前尚未创建。执行时可按现有结构调整文件名，但不能缩减核心断言。

| ID | Given / When / Then | 层级与关键断言 | 当前 |
| --- | --- | --- | --- |
| P01 | 未登录选套餐/周期→在购买页登录→选择保留，登录前无消费 | widget+host，匿名请求不带凭据，目录独立busy | NOT RUN |
| P02 | 有效纯余额码恰好补足→确认→一次订单完成并开通 | HTTP+真实SQLite+client，usage/order/权益事件唯一，买方/邀请人余额、奖励审计、佣金与折抵旧单状态正确 | NOT RUN |
| P03 | 已有余额足额/免费套餐→确认→无需强制输入卡 | 同上；零价仍有明确完成订单，不能仅看应付0判断成功 | NOT RUN |
| P04 | 余额加一张卡不足→提交→无消费拒绝并显示差额 | 钱包/卡次数/usage/orders/权益均不变；不默建欠款订单 | NOT RUN |
| P05 | 卡余额超出价格→确认→只支付实际金额，余款留账户 | 整数分、最大合法金额、零、舍入边界；明细与数据库一致 | NOT RUN |
| P06 | type1混合奖励/type2/type3→付款入口→不按现金核销 | 新交易0副作用；旧兑换入口原行为仍可用 | NOT RUN |
| P07 | type4匹配/不匹配套餐周期→确认→按原快照生效/无消耗拒绝 | 固定套餐码不转余额；0站内金额不显示免费；旧幂等保留 | NOT RUN |
| P08 | 编辑码/套餐/周期、A→B→A、迟回成功/失败→旧确认失效 | manager+widget，提交绑定不可变报价，旧响应不得解锁 | NOT RUN |
| P09 | 查卡/提交连点、多个设备同键重放；两账号不同键争用同一单次卡；同quote换键 | HTTP并发+独立Store/SQLite连接，同键仅一个结果，quote仅绑定一个执行身份；同卡至多一次消费，失败者无钱包/奖励/佣金/订单/权益/成功记录变化 | NOT RUN |
| P10 | 同账号同键不同参数→拒绝；其他账号复用键值→隔离 | owner绑定、输入指纹校验；不得返回别人的结果或金额，不得对另一账号扣款 | NOT RUN |
| P11 | handler已提交后丢弃成功响应→同键查询/重试→原结果 | 真正提交后断流，不以“没发请求直接抛超时”替代；重启后仍唯一；暂未查到结果不换键重试或宣布失败 | NOT RUN |
| P12 | 提交前/事务中/本地保存失败/进程退出→恢复 | 写后读失败0 mutation；事务失败全回滚；成功事实不因清pending失败丢失 | NOT RUN |
| P13 | 价格/折扣/折抵/权益规则/卡模板倍率/余额在报价后变化→拒绝重报 | 检查和写入同事务；仅动态到期秒值变化不误拒绝；时间折抵跨最小金额单位时须重报；不能事后取消冒充未扣 | NOT RUN |
| P14 | 有效期内无金额/业务变化推进1秒→可提交；到有效期边界/他人使用/篡改→无消费拒绝 | 不直接比较动态整快照；已成功请求在报价过期后仍能查询或重试返回同一结果 | NOT RUN |
| P15 | 卡过期/耗尽/禁用/模板限次/冷却/不适用账号→明确失败 | 保留原条件；限次1时同用户并发兑换同模板两张不同卡仅一次成功；同模板用过不能误作同卡成功 | NOT RUN |
| P16 | 不同请求竞争不足以完成两笔的余额/最后套餐名额；已有Pending/Processing订单 | 独立Store/SQLite连接并发；失败方无消费/权益/成功记录；不自动取消/支付别处订单，不依赖“最新同套餐”认领 | NOT RUN |
| P17 | 用户明确取消选定旧Pending订单→余额按旧规则返还 | 权限、重复取消、响应丢失、支付处理中拒绝；只操作选中tradeNo | NOT RUN |
| P18 | 普通onetime订单与type4按量码→分别验证 | 标准订单按既有规则替换额度/清已用；type4追加快照额度/保留已用 | NOT RUN |
| P19 | 新购/续费/换套餐/禁用换套餐/停售/容量/定向资格变化 | 权益before/after按服务端规则；失败不消费，不把目录标价当最终事实 | NOT RUN |
| P20 | 每个阶段401/退出/切号/不同origin→重新认证与隔离 | 已确认结果和账号级恢复留存；其他账号不见码、订单或错误详情 | NOT RUN |
| P21 | 损坏/旧版安全存储、写后读不符/删失败→关闭消费 | 旧gift pending兼容；不能把损坏记录当无交易；无秘密进入普通存储 | NOT RUN |
| P22 | 购买已完成、订阅刷新/下载/导入失败→仅重试同步 | 仍显示购买成功和订单号，0额外兑换/下单/扣款；不切换当前代理配置 | NOT RUN |
| P23 | 未登录/分销商/他人请求键或订单/凭据撤销→拒绝 | 真实普通Bearer+cookie/CSRF权限测试；钱包与权益全不变 | NOT RUN |
| P24 | API缺字段/null/非法金额/未知状态/3xx/429/5xx/畸形200 | 严格契约，未知不等于成功/免费；错误文本不泄露卡码/令牌 | NOT RUN |
| P25 | 报价和能力读取→确认为无副作用 | 不写订单/余额/卡次数，不占库存；能力缺失不伪造0余额或币种 | NOT RUN |
| P26 | 旧后端/旧客户端/旧礼品卡type1–4/旧网页订单 | 新端能力门控，旧路由兼容；无静默降级消费；公开目录依旧可看 | NOT RUN |
| P27 | SQLite审计/权益/防重写入失败；邀请奖励已写/折抵旧单已标记后注入失败 | 卡核销、买方/邀请人钱包、奖励审计、佣金、旧新订单、权益全部回滚；重试成功仅一份效果 | NOT RUN |
| P28 | 增量迁移/重启/版本回退/重复迁移 | 新表与唯一约束正确；交易证据不删除，旧接口可用，恢复键不丢 | NOT RUN |
| P29 | 浅深色、320/360/桌面、2x、键盘、加载/空/错/成功 | 真实widget树，无溢出、焦点可达、付款摘要与确认按钮清晰 | NOT RUN |
| P30 | 两个微信复制/购卡、旧兑换历史、账户同步、其他页回归 | 完整test/purchase和Flutter回归；非购买页diff审查 | NOT RUN |

P02/P09/P10/P11/P13/P16/P18/P23/P27/P28必须有真实SQLite/HTTP层证据，不能全部由FakeApi提供成功对象。P08/P12/P20/P21/P22必须断言副作用调用次数和持久化结果，不能只检查文案。

## 3. 测试任务与顺序

| 任务 | 内容 | 门禁 |
| --- | --- | --- |
| T01 | G0确认后冻结矩阵；写合同、权限和事务用例 | 不从实现反推预期；记录版本和必要Red |
| T02 | 执行后端目标测试，再做真实事务/并发/回滚/迁移 | 全部核心财务不变量得到证据 |
| T03 | 客户端API、存储、manager和宿主目标测试 | 各故障阶段独立验证；已提交而丢响应得到覆盖 |
| T04 | 跨语言真实Dio→隔离Go handler/SQLite端到端 | 固定合成fixture与信任边界，重启后核查金额/记录数量 |
| T05 | 本页视觉/响应式/键盘与既有购买回归 | 只离线渲染不能标真实Windows通过 |
| T06 | Flutter全回归、定向analyze、资源编译；Go vet及必要回归 | 命令、exit、计数、时长、SDK分别记录 |
| T07 | 非作者独立安全/测试审查、补测并重跑 | 所有验收映射到证据；无已知Critical/High |
| T08 | 最终diff、秘密检查、覆盖率、台账和未运行项 | 不用历史563项代替新流程验证 |

### 当前已有合同的可执行基线命令

运行目录分别为FlClashX和Xboard-Go。以下命令尚未执行，本轮仅核对了用例名称存在。

~~~powershell
& E:\flutter\bin\flutter.bat test --no-pub test/purchase --reporter expanded
& E:\flutter\bin\flutter.bat test --no-pub --branch-coverage --coverage-path build/checkout-coverage/lcov.info --reporter expanded
& E:\flutter\bin\dart.bat analyze lib/models/xboard.dart lib/services/xboard_api.dart lib/services/purchase_storage.dart lib/manager/purchase_manager.dart lib/views/purchase test/purchase
& E:\flutter\bin\flutter.bat build bundle --no-pub --debug --target-platform windows-x64 --asset-dir build/checkout-assets --depfile build/checkout-assets.d

go test ./internal/httpapi -run 'Test(OrderAPICompletesFreeOrderAndEnforcesOwnershipAndCSRF|GiftCardBearerCodeIdentityAcrossCheckRedeemAndHistory|GiftPurchaseAPIAdminToUserOrderLifecycle)$' -count=1
go test ./internal/store -run 'Test(CreateOrderUsesServerPriceBalanceAndDatabaseActiveOrderInvariant|ActiveOrderInvariantHoldsAcrossIndependentSQLiteConnections|CompleteFreeRenewalIsExactlyOnceAndAppliesPlanEntitlements|ProcessingOrderRecoveryAndResetPurchaseAreIdempotent|CreateOrderFailureRollsBackBalanceAndCouponConsumptionThenRetrySucceeds|GiftCardRedemptionAuditFailureRollsBackRewardsAndRetrySucceeds|CancelledPartiallyFundedUpgradeRestoresWalletWithoutConsumingSurplus)$' -count=1
go vet ./internal/httpapi ./internal/store
~~~

新用例文件和函数存在后，再填写准确目标命令，不能运行空匹配后宣布通过。执行前核实实际SDK；现有CI固定Flutter3.41.7，本机上一轮为3.47.4，不能混同。

当前覆盖边界：源码中的现代订单全生命周期用例采用Cookie+CSRF；礼品卡Bearer用例不等于新购买接口Bearer全链路。既有提交后丢响应E2E固定type4与网页Cookie，不能替代通用余额卡、普通订单和客户端新请求键恢复测试。上述判断来自只读审查，本轮未执行这些既有测试。

## 4. 报告要求

每项记录：需求/用例ID、最终源码、环境、命令、PASS/FAIL/NOT RUN、exit、通过/失败/跳过数量、时间、真实副作用断言和失败原因。覆盖率报告区分全文件、变更行/分支、未覆盖路径，不以单一百分比替代金额正确性。

必须保留Red→Green的真实失败原因、缺失工具/网络/设备、未运行项和已知风险。原生Windows窗口、系统密钥库、真实付费/兑码、CI和部署均需要独立证据与相应授权。

# 裸配置智能本地分流、跨配置全局覆写与规则热更新精准断流工程方案（2026-11-05）

## 1. 背景与根因

1. **裸配置无公网分流兜底**：当订阅服务端仅下发节点与单条兜底规则（如 `rules: [MATCH,PROXY]` 或 `rules: []`）时，现有 `GlobalState.patchRawConfig` 仅在桌面端且手动开启 `RouteMode.bypassPrivate`（默认关闭且桌面端 UI 隐藏该入口）时注入私有 CIDR 直连，不含任何国内域名/IP 分流，导致 `*.baidu.com`、`*.bdstatic.com` 等所有国内流量全部走代理。
2. **规则覆写强绑定单配置且缺少跨订阅目标策略组适配**：现有 `Profile.overrideData` 耦合在单个 `Profile` 实例内，切换配置即失效；若简单复制规则到全局，不同订阅的主代理组命名差异（如 `PROXY`、`Proxy`、`🚀 节点选择`）会导致 Mihomo `ParseRawConfig` 因找不到目标策略组而拒绝加载配置。
3. **两步保存交互陷阱与挂载守卫漏洞**：`OverrideProfileView` 新增规则仅更新内存草稿且默认 `enable == false`，漏开开关或漏点保存即不生效；`AppController.setupClashConfig` 受 `homeScaffoldKey.currentState?.mounted` 限制可能静默跳过重载。
4. **热更新不断开失效长连接池**：Go 内核 `setupConfig`（`executor.ApplyConfig`）不重评存量连接，Chrome HTTP/2 (`h2`) / QUIC 连接池持续多路复用旧 `PROXY` 隧道。

## 2. 架构设计

### 2.1 五层确定性规则编译器（`lib/common/rule_compiler.dart`）
按从具体到通用顺序合成最终 `rawConfig["rule"]`：
1. **Layer 1 — 按应用分流策略（`perAppPolicyStore`）**：`PROCESS-PATH,<exe>,<target>`。
2. **Layer 2 — 单配置专属覆写（`Profile.overrideData`）**：当前订阅显式例外（若为 `OverrideRuleType.override` 则替换 Layer 4 订阅原始规则）。
3. **Layer 3 — 全局规则覆写（`Config.globalOverrideData`）**：跨所有订阅持久生效，默认 `enable: true`；支持语义代理目标 `DEFAULT_PROXY` 及不存在显式组名向当前配置 `PrimaryProxyTarget` 的自动安全回退。
4. **Layer 4 — 订阅原始规则（`Profile` 原始 `rules`，剥离末尾 `MATCH`）**。
5. **Layer 5 — 智能本地分流兜底引擎（`LocalSplitMode`：`auto` 默认 / `always` / `off`）**：
   - **裸配置判定（`isBareRuleProfile`）**：无有效 `RULE-SET` 引用，且剔除 `MATCH`/`FINAL` 与纯私有/回环/链路本地规则后公网分流规则数为 `0`。
   - **本地分流规则包（`GeoSite.dat` + `geoip.metadb` 离线内存匹配，Fake-IP 零泄露顺序）**：
     1. 私有与保留网段 `DIRECT,no-resolve`（排除 `198.18.0.0/16` Fake-IP 段）；
     2. `GEOSITE,private,DIRECT`；
     3. `GEOSITE,cn,DIRECT`（0 ms 域名直连，覆盖 `baidu.com`、`bdstatic.com` 等）；
     4. `GEOSITE,geolocation-!cn,<PrimaryProxyTarget>`（前置拦截已知海外域名，杜绝 Fake-IP 模式下为评估 `GEOIP,CN` 向国内 DoH 泄露查询与抢答污染）；
     5. `GEOIP,CN,DIRECT`（长尾国内站点与纯 IP 直连）；
     - 若极端测试环境缺失 GeoData 文件，自动降级为私有网段 + 核心 `.cn` 域名后缀直连，保证 `ParseRawConfig` 永不报错。
6. **Terminal — 终端兜底规则**：保留原末尾 `MATCH,...`；若裸配置缺失 `MATCH`（如 `rules: []`），自动补齐 `MATCH,<PrimaryProxyTarget>`。

### 2.2 即时生效 UI 与响应式下发
- 顶层 `Config` 新增 `globalOverrideData`（默认 `OverrideData(enable: true)`），`NetworkProps` 新增 `localSplitMode`（默认 `LocalSplitMode.auto`）。
- 「配置」页顶部栏与「设置 -> 基本配置」新增 **全局规则覆写** 入口；桌面与移动端「设置 -> 基本配置 -> 网络」暴露 **本地分流兜底** 与 **路由模式**。
- 全局覆写与单配置覆写统一升级为**即时自动保存与防抖热下发**（新增规则时若覆写开关关闭则自动开启），通过 `ClashManager` 独立监听路由规则状态触发 `setupClashConfigDebounce()`（保留节点延迟缓存、日志与滚动位置）。

### 2.3 Go 内核亚毫秒级差异化断流（`core/rule_reconcile.go`）
- 在 `setupConfig`（存在上一代配置且运行态开启自动断连时）及 `updateConfig`（切换 `Mode` 时）完成新配置应用后，遍历 `statistic.DefaultManager` 活跃连接。
- 通过非阻塞 `C.RuleMatchHelper` 纯内存重算每条连接的顶层目标出口 `newTarget`：
  - 仅当 `newTarget != oldTarget`（或规则表变化且命中依赖真实 IP 解析但当前仅持 Fake-IP/空 IP 的规则）时调用 `c.Close()` 切断旧隧道；
  - 路由结果未改变的正常连接（如持续走 `PROXY` 的下载/SSH 会话）保持零中断。

## 3. TDD 验证矩阵
1. **Dart 规则编译器单测（`test/common/rule_compiler_test.dart`）**：裸配置识别、完整配置零侵入、五层优先级、`DEFAULT_PROXY` 与缺失策略组跨配置自适应映射、Fake-IP 段排除、缺失 GeoData 降级。
2. **Dart 配置兼容与响应式热重载单测（`test/models/global_override_config_test.dart`）**：旧版 `Config.compatibleFromJson` 默认迁移、`globalOverrideProvider` 与 `localSplitMode` 变更触发持久化及重配信号。
3. **Dart 全局与单配置覆写即时生效组件测试（`test/views/profiles/global_override_view_test.dart`）**：全局覆写添加语义代理/直连规则即时落盘、开关关闭态新增规则自动启用、单配置覆写即时生效无需二次点保存。
4. **Go 内核精准断流与并发安全单测（`core/rule_reconcile_test.go`）**：`MATCH,PROXY` 热更新注入国内直连规则后精准关闭 `miao.baidu.com` / `cloud.baidu.com` 旧 `PROXY` 连接，同时保留 `github.com` 正常 `PROXY` 连接不断流；`Mode` 切换收敛；`-race` 零竞态。

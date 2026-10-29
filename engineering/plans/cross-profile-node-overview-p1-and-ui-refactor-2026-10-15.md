# 跨配置节点总览 P1 隔离测速与界面层级重构工程书
(Cross-Profile Node Overview P1 & UI Refactor Specification)

| 项 | 内容 |
|---|---|
| 文档版本 | v2.0 / P1（2026-10-15） |
| 基线分支 | `development@f6dff78c762654af1f77adfa46eed697a1492626`（与 `freedomcloud/development` 0/0） |
| 状态 | 需求评审通过，已排期实施；待 Dev 执行、Tech Lead 审查与门禁验收 |
| 负责人（评审/Git 写操作） | 技术负责人（Tech Lead） |
| 实施者 | Dev（UI 重构、Dart 领域层、Go Core 接口与单测） |
| 核心目标 | ① 彻底消除 UI 重复与折叠逻辑（左侧选配置、右侧平铺直出，活动配置扁平化）<br>② 落地 P1 隔离测速（Go Core 适配器解析与 Dart 调度，不切配置、不断网测非活动节点） |
| 授权与安全边界 | 本地开发与单元测试；严禁在开发机直接执行候选包、严禁触碰现役代理/TUN/系统网络；所有 Git 写操作由负责人串行执行 |

---

## 1. 背景与核心问题诊断

### 1.1 现状与用户痛点
在首轮 P0 交付中，虽然实现了跨配置目录解析与脱敏健康历史记录，但用户在真实使用中提出了两大根本性设计问题：
1. **视觉与交互重复（UI 冗余）**：
   - 宽屏左侧栏已经提供了配置列表作为筛选器；但右侧内容区依然把每个配置包裹在一个巨大的可折叠卡片（Accordion Card）中，并在卡片头部再次展示完整的健康摘要与展开/折叠箭头。
   - 用户在左侧点击某个配置后，期望的是右侧直接查看该配置下的所有节点；但右侧仍然保留了折叠卡片外壳，操作链路存在多余的手风琴点击。
2. **活动配置与当前代理视图职责混淆**：
   - 在总览页中，活动配置之前嵌套展示了各代理组（Proxy Group）及内部的 `ProxyCard`（包含切换单选按钮、组测试 URL 等）。这不仅使得活动配置与非活动配置的视觉样式分裂，而且在“全部配置总览”中复制了“当前配置”界面的组管理职责。
   - 用户的核心心智是**横向比对所有配置的节点质量与延迟**，节点在代理组中的选择属于“当前配置”视图的独立职责。
3. **非活动节点无法实时测速（P0 遗留瓶颈）**：
   - 非活动配置在 P0 中仅能读取历史测速结果（或显示“未测”）。用户若想知道某个备用订阅当前是否畅通，仍然无法在总览页主动发起测速，必须冒着断连风险切换配置。

### 1.2 重构与演进决策
经技术评审确认，采纳以下推荐架构方案：
1. **彻底废除手风琴折叠（No Accordion / No Collapsible Cards）**：
   - 左侧栏作为纯粹的**配置筛选器（Filter Sidebar）**，首项为“全部配置”，后续为各配置项。
   - 右侧主区域为纯粹的**平铺节点列表（Flat Node List）**：
     - 当选中“全部配置”时：右侧直接展示所有配置的节点，配置间仅由轻量级的吸顶标题行（`_PinnedProfileHeader`，含配置名称及“活动”徽标）分隔，无卡片包裹、无折叠开关。
     - 当左侧选中某一特定配置时：右侧直接过滤展示该配置的全部节点，无冗余分节卡片，列表直出。
     - 窄屏/移动端：隐藏左侧栏，在顶部操作栏提供紧凑的配置筛选器（下拉/菜单），选择后同样直接平铺展示节点，彻底告别单栏折叠手风琴。
2. **活动配置节点彻底扁平化（Active Node Flattening）**：
   - 活动配置在总览中移除代理组嵌套与 `ProxyCard`，统一扁平化为叶子节点行（`_ActiveNodeRow`）。
   - 实时延迟直接绑定 `delayDataSourceProvider` / `getDelayProvider`，并显示实时测试时间与健康颜色；节点选择交互严格留在“当前配置”视图。
3. **全面实施 P1 隔离测速（P1 Isolated Delay Testing）**：
   - Go Core 新增 `catalogPrepare`、`catalogTestDelay`、`catalogRelease` 三大 action，利用独立的出站适配器在后台发起 HTTP 204 延迟测试。
   - 绝不调用 `setupConfig`、绝不更新系统代理/TUN、绝不断开现役连接；Dart 协调器统一调度，结果安全回写 `NodeHealthStore`。

---

## 2. 界面与交互重构详细设计

### 2.1 宽屏布局结构（宽屏模式，`width > maxLaptopWidth`）

```
+-----------------------------------+---------------------------------------------------------------+
| 工具栏: [当前配置/全部配置]           | 筛选器: [仅看可用]  排序: [默认/名称/延迟]   [测当前配置] [测全部] |
+-----------------------------------+---------------------------------------------------------------+
| 左侧筛选栏 (280px)                 | 右侧平铺节点列表 (CustomScrollView)                             |
|                                   |                                                               |
|  [全部配置] (All Profiles) <选中>  |  === [配置 A (活动)] ======================================== |
|                                   |  Node A-01  | Shadowsocks | 88 ms  | 实时在线 (绿色)          |
|  [配置 A (活动)]                   |  Node A-02  | Vless       | 120 ms | 实时在线 (绿色)          |
|   可用 12/15 · 95ms · 刚刚         |  Node A-03  | Trojan      | 超时   | 实时离线 (红色)          |
|                                   |                                                               |
|  [配置 B]                         |  === [配置 B] =============================================== |
|   可用 8/10 · 140ms · 5分钟前      |  Node B-01  | Hysteria2   | 110 ms | 5分钟前 (绿色)   [测速]  |
|                                   |  Node B-02  | Shadowsocks | 未测   | 点击测速 (灰色)   [测速]  |
|  [配置 C]                         |                                                               |
|   可用 0/20 · 异常 (解析失败)       |  === [配置 C] =============================================== |
|                                   |  (提示：该配置解析失败/文件缺失，提供管理入口)                   |
+-----------------------------------+---------------------------------------------------------------+
```

当用户在左侧点击 **[配置 B]** 时：
```
+-----------------------------------+---------------------------------------------------------------+
| 左侧筛选栏 (280px)                 | 右侧平铺节点列表 (仅显示配置 B)                                 |
|                                   |                                                               |
|  [全部配置]                       |  Node B-01  | Hysteria2   | 110 ms | 5分钟前 (绿色)   [测速]  |
|                                   |  Node B-02  | Shadowsocks | 未测   | 点击测速 (灰色)   [测速]  |
|  [配置 A (活动)]                   |  Node B-03  | Vless       | 180 ms | 10分钟前 (黄色)  [测速]  |
|                                   |                                                               |
|  [配置 B] <选中>                  |                                                               |
|   可用 8/10 · 140ms · 5分钟前      |                                                               |
+-----------------------------------+---------------------------------------------------------------+
```

### 2.2 窄屏/移动端布局结构（`width <= maxLaptopWidth`）
- 窄屏下隐藏左侧栏，顶部增加一个配置选择器（Dropdown 或 Filter Popup）：
  - 选项：`[全部配置]`、`配置 A (活动)`、`配置 B`、`配置 C`。
- 选定后，下方直接以 `CustomScrollView` 平铺渲染对应的节点列表。
- 选“全部配置”时由轻量吸顶标题分段；选具体配置时直接直出该配置节点。**彻底移除单栏折叠手风琴卡片**。

### 2.3 节点行（Node Row）视觉契约
- **活动配置节点行（`_ActiveNodeRow`）**：
  - 左侧：节点名称（突出文本）、协议类型标签（如 `SS`、`VLESS`）、来源标签（`内联` 或订阅源名称）。
  - 右侧：实时延迟（如 `88 ms`，使用 `utils.getDelayColor` 色阶），下方标注 `实时` 或组测试 URL 测试时间。
  - 点击行：无代理切换行为（提示用户如需切换节点请至“当前配置”页，或直接只读查看）。
- **非活动配置节点行（`_InactiveNodeRow`）**：
  - 左侧：节点名称、协议类型标签、来源标签。
  - 右侧：
    - 若正在测速：展示圆形小微进度圈（`SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))`）或“测速中...”。
    - 若有测试结果：展示延迟数字（如 `120 ms`）及历史时间标签（如 `5分钟前` / `可能过时`）。
    - 若未测：展示灰字 `未测`。
    - 最右侧：单节点独立测速图标按钮（`IconButton(icon: Icon(Icons.bolt), tooltip: '测试此节点')`），点击直接向 `DelayTestCoordinator` 派发该单节点测试。
- **坏节点/无法识别节点**：
  - 展示问号图标与提示文案 `无法识别的节点配置`，不展示测速按钮，不参与统计。

---

## 3. P1 隔离测速（Core & Dart）详细设计

### 3.1 核心原则与安全边界
1. **现役隔离（Zero Interference）**：
   - 隔离测速绝不走 `tunnel` 路由转发，不注册进当前系统的入站/出站规则，流量不计入现役连接统计。
   - 严禁调用 `setupConfig`、`applyProfile` 或更新系统代理/TUN 驱动。
2. **生命周期与资源上限（Bounded Resources）**：
   - Core 维护 `catalogMu`，**严禁持有 `runLock`**（防止与 `setupConfig` 互锁产生死锁）。
   - Core 最多并发保留 **3 个 Catalog** 缓存，超出按 LRU 淘汰；空闲 **10 分钟** 自动销毁释放出站适配器。
   - 单个 Catalog 节点总数上限为 **2000**，超出直接拒绝并返回 `tooManyNodes`。
3. **并发预算共享（Unified Budget）**：
   - 隔离测速与现役测速共用 Core 内现有的 150 个任务槽位（`delayTaskSlots`）与执行信号量（`testDelaySem`），防止并发突发压垮网络或触发安全软件告警。
4. **延迟污染阻断（No Broadcast）**：
   - `catalogTestDelay` **必填 `request-id`**，且内部执行完毕后**绝对禁止**向外广播 `DelayMessage`，防止用非活动节点名称污染前端 `delayDataSourceProvider`。

---

### 3.2 Go Core 层接口与实现规格

#### 3.2.1 常量与方法注册
- 在 `core/constant.go` 增加：
  ```go
  const (
      catalogPrepareMethod   Method = "catalogPrepare"
      catalogTestDelayMethod Method = "catalogTestDelay"
      catalogReleaseMethod   Method = "catalogRelease"
  )
  ```
- 在 `core/action.go` 的 `handleAction` 中分发到对应处理器：
  ```go
  case catalogPrepareMethod:
      paramsString, ok := action.Data.(string)
      if !ok {
          result.error("invalid data type")
          return
      }
      handleCatalogPrepare(paramsString, result)
      return
  case catalogTestDelayMethod:
      paramsString, ok := action.Data.(string)
      if !ok {
          result.error("invalid data type")
          return
      }
      handleCatalogTestDelay(paramsString, func(response string) {
          result.success(response)
      })
      return
  case catalogReleaseMethod:
      paramsString, ok := action.Data.(string)
      if !ok {
          result.error("invalid data type")
          return
      }
      handleCatalogRelease(paramsString, result)
      return
  ```

#### 3.2.2 `catalogPrepare` 实现 (`core/catalog.go`)
- **请求参数**：
  ```json
  {
    "catalog-id": "c-550e8400-e29b-41d4-a716-446655440000",
    "proxies": [
      { "name": "HK 01", "type": "ss", "server": "1.2.3.4", "port": 8388, "password": "...", "cipher": "..." }
    ],
    "providers": [
      { "name": "sub1", "path": "E:\\...\\profiles\\providers\\p1\\proxies\\md5hash" }
    ]
  }
  ```
- **核心逻辑**：
  1. 校验 `catalog-id` 是否符合正则 `^c-[A-Za-z0-9-]{8,64}$`，否则返回 `invalidParameters`。
  2. 严格模式防御：若 `activeStrictIngress != nil || macStrictIngressIntent != nil`，直接返回错误 `strictModeUnsupported`。
  3. 节点上限截断：统计内联节点数，若内联节点数 > 2000，返回 `tooManyNodes`。
  4. 解析内联节点：
     - 遍历 `proxies` 映射：
       - 若包含 `dialer-proxy` 字段：标记 `supported = false, reason = "chainUnsupported"`。
       - 若 `type` 属于 `wireguard` 或 `amneziawg` 等重型网络协议：标记 `supported = false, reason = "typeUnsupported"`。
       - 调用 `adapter.ParseProxy(mapping)` 构建 `constant.Proxy`。构建失败者标记 `supported = false, reason = "parseFailed"`（**严禁回传底层错误详情**，防止泄漏配置明文）。
       - 构建成功者标记 `supported = true`，加入该 catalog 的适配器数组 `proxies []constant.Proxy`。
  5. 订阅源（Provider）本地缓存处理：
     - 校验 `path`：必须通过 `constant.Path.IsSafePath(path)`，规范化后必须位于 `<HomeDir>/profiles/providers/` 且包含 `/proxies/`。不合法直接报错 `invalidParameters`。
     - 检查本地文件是否存在：若不存在，标记该 Provider 为 `notCached`；
     - **预研降级保护**：P1 阶段若解析本地 provider 缓存过于复杂或未导出 Mihomo 现成解析器，该 provider 节点返回 `providerPending` 或 `notSupportedInPreview`，**绝不调用网络下载**。
  6. 存储与 LRU 淘汰：
     - 使用独立锁 `catalogMu sync.RWMutex` 保护全局 `catalogs = map[string]*catalogEntry{}`。
     - 若 `len(catalogs) >= 3`，淘汰 `lastUsed` 最早且当前无活跃测速引用的 catalog；淘汰时对所有实现 `io.Closer` 的 Proxy 适配器调用 `Close()`。
     - 记录创建时间与 `lastUsed = time.Now()`。
- **响应格式**：
  ```json
  {
    "catalog-id": "c-...",
    "nodes": [
      {
        "index": 0,
        "name": "HK 01",
        "type": "ss",
        "server": "1.2.3.4",
        "port": 8388,
        "supported": true,
        "reason": ""
      }
    ],
    "providers": [
      { "name": "sub1", "status": "notCached", "count": 0 }
    ]
  }
  ```

#### 3.2.3 `catalogTestDelay` 实现 (`core/delay_tasks.go` 重构与扩展)
- **共享运行器重构**：
  将 `core/delay_tasks.go` 中的测速核心逻辑抽取为公共高阶函数：
  ```go
  func runDelayTask(
      params TestDelayParams,
      lookup func(ctx context.Context) (constant.Proxy, string),
      fn func(string),
      broadcast bool,
  )
  ```
  - **现役节点测速（`handleAsyncTestDelay`）**：
    - `lookup`：在 `runLock` 内调用 `lookupDelayProxy(params.ProxyName)`。
    - `broadcast`：`params.RequestID == ""`。
  - **目录隔离测速（`handleCatalogTestDelay`）**：
    - 参数解析：要求入参包含 `catalog-id`、`index`、`request-id`（**必填**）、`test-url`、`timeout`。
    - `lookup`：在 `catalogMu.RLock()` 下查找 `catalogs[catalogID]` 并按 `index` 提取适配器；如果 catalog 不存在返回 `(nil, "catalogNotFound")`；如果 index 越界返回 `(nil, "invalidParameters")`。查找成功增加活跃引用计数。
    - `broadcast = false`（**绝对不发送 `DelayMessage`**）。
    - 运行器统一接入 `delayTaskSlots`（上限 150）与 `testDelaySem`，超时受 `context.WithDeadline` 保护。

#### 3.2.4 `catalogRelease` 实现 (`core/catalog.go`)
- 根据传入的 `catalog-id` 查找并从 `catalogs` 映射中删除。
- 释放前关闭全部底层出站代理适配器连接。
- 幂等设计：若 catalog 不存在直接返回成功。
- 在 `handleShutdown` 及 `server.go` 的连接关闭清理路径中，自动遍历调用清空所有 catalog 资源。

---

### 3.3 Dart 领域层与桥接设计

#### 3.3.1 枚举与接口扩展
1. **`lib/enum/enum.dart`**：
   在 `ActionMethod` 中增加：
   ```dart
   enum ActionMethod {
     ...
     catalogPrepare,
     catalogTestDelay,
     catalogRelease,
   }
   ```
2. **`lib/clash/interface.dart` 与 `lib/clash/core.dart`**：
   - 增加底层调用：
     ```dart
     Future<String> catalogPrepare(String catalogId, List<Map<String, dynamic>> proxies, List<Map<String, dynamic>> providers);
     Future<DelayTestResult> catalogTestDelay(String catalogId, int index, String url, {required String requestId, Duration timeout});
     Future<bool> catalogRelease(String catalogId);
     ```

#### 3.3.2 协调器扩展 (`lib/common/delay_test_coordinator.dart`)
1. **`DelayTestTarget` 扩展字段**：
   ```dart
   class DelayTestTarget {
     const DelayTestTarget(this.name, this.url, {this.scope, this.nodeIndex});
     final String name;      // live: 节点名; catalog: identityKey
     final String url;
     final String? scope;    // null: 现役配置; 非空: catalogId
     final int? nodeIndex;   // catalog 节点下标
     (String, String, String) get key => (scope ?? '', name, url);
   }
   ```
2. **动态批次超时支持**：
   `Future<DelayBatchResult> run(Iterable<DelayTestTarget> targets, {Duration? batchTimeout})`
   - 对于目录大批量测速，调用方可根据 `targets.length` 动态计算批次超时时间，避免 30 秒默认超时提前中断。

#### 3.3.3 测速路由与结果落地 (`lib/common/delay_tests.dart`)
- 修改 `delayTests` 的 `test` 分发回调：
  ```dart
  test: (target, requestId, timeout) {
    if (target.scope != null && target.nodeIndex != null) {
      return clashCore.catalogTestDelay(
        target.scope!,
        target.nodeIndex!,
        target.url,
        requestId: requestId,
        timeout: timeout,
      );
    }
    return clashCore.getDelayResult(
      target.url,
      target.name,
      requestId: requestId,
      timeout: timeout,
    );
  },
  onStarted: (target) {
    if (target.scope != null) {
      // 隔离节点测试开始：标记待测状态，不影响现役 delayDataSource
      nodeHealthStore.markPending(target.scope!, target.name);
      return;
    }
    // 现有逻辑不变...
  },
  onResult: (target, result) {
    if (target.scope != null) {
      // 隔离节点测试结束：记录结果至 NodeHealthStore
      nodeHealthStore.putCatalogResult(target.scope!, target.name, result);
      return;
    }
    // 现有逻辑不变...
  },
  ```

---

## 4. UI 代码重构落地方案 (`lib/views/proxies/overview/overview.dart`)

### 4.1 状态与组件精简
1. **废弃无用状态**：
   - 彻底删除 `_expanded = <String>{}` 集合。
   - 彻底删除 `_toggle(id)` 方法。
   - 仅保留：
     - `String? _selectedProfile`（`null` 表示“全部配置”，非空表示当前选中的 profileId）。
     - `bool _availableOnly`（仅看可用）。
     - 排序方式（从 `proxiesStyleSettingProvider` 获取）。
     - `Timer? _clock`（驱动“X分钟前”时间刷新）。

### 4.2 左右布局逻辑与平铺渲染
1. **宽屏模式（`!mobile && constraints.maxWidth > maxLaptopWidth`）**：
   - **左侧**：`_SidebarProfileCard` 列表。
     - 第 0 项为 `ListTile(title: Text('全部配置'), selected: _selectedProfile == null, onTap: () => setState(() => _selectedProfile = null))`。
     - 第 1..N 项为各配置卡片。点击时设置 `_selectedProfile = profile.id`。
   - **右侧**：`CustomScrollView`。
     - 若 `_selectedProfile == null`（全部配置模式）：
       - 遍历所有 `profiles`。
       - 为每个 profile 渲染轻量吸顶标题 `_PinnedProfileHeader(profile: profile, active: profile.id == activeId)`。
       - 紧随其后渲染该 profile 的节点平铺列表 Sliver（若无节点则渲染空提示）。
     - 若 `_selectedProfile != null`（单配置筛选模式）：
       - 仅渲染选中的那个 profile 的平铺节点列表 Sliver，**无外层卡片包裹，无手风琴折叠**。
2. **窄屏模式（`mobile || constraints.maxWidth <= maxLaptopWidth`）**：
   - 工具栏/顶部筛选区增加 `DropdownButton<String?>` 或弹出菜单：
     - 包含 `[全部配置]` 及各个 profile 名称。
     - 切换后更新 `_selectedProfile`。
   - 下方直接平铺展示节点列表。

### 4.3 节点行扁平化重构
1. **活动配置节点（`_ActiveNodeRow`）**：
   - 废除原有的代理组标题与嵌套 `ProxyCard`。
   - 从 `currentGroupsStateProvider` 提取所有去重的叶子节点。
   - 渲染为整齐的扁平 ListTile/Card，右侧显示实时测速延迟与健康色彩。
2. **非活动配置节点（`_InactiveNodeRow`）**：
   - 从 `ProfileCatalog.nodes` 中渲染。
   - 右侧展示 `NodeHealthStore` 历史/实时测速数据。
   - 增加测速按钮与加载中状态，点击时调用 `NodeCatalogService.ensurePrepared` 获取 `catalogId` 后向 `delayTests.run` 派发测试。
3. **顶部工具栏新增测速动作**：
   - `[测速当前配置]`：复用原有活动配置批量测速。
   - `[测试可见节点]`：对当前视图内筛选出的非活动配置节点发起批量 P1 隔离测速。
   - 当 `delayTests.busy` 时，显示线性进度指示器与 `[取消]` 按钮。

---

## 5. 潜在风险与防范策略 (Risk Registry)

| 风险项 | 严重级别 | 潜在诱因 | 防范策略与代码防线 |
|---|---|---|---|
| **R-1: Core 死锁** | Critical | 在 `catalogPrepare` 或 `catalogTestDelay` 中错误持有了 `runLock`，与主线程 `setupConfig` 互锁 | `catalog.go` 严禁引入或引用 `runLock`；目录查找与适配器管理使用纯独立的 `catalogMu sync.RWMutex` |
| **R-2: 延迟数据污染** | High | 隔离测速完成后通过广播发送 `DelayMessage`，导致前端将非活动节点的延迟误赋给同名现役节点 | `runDelayTask` 中严格判断：目录测速场景下 `broadcast = false`，绝对不调用 `sendMessage` |
| **R-3: 内存与连接泄漏** | High | 用户频繁切换非活动配置，创建了大量出站适配器未被释放 | ① LRU 限制最多 3 个 catalog；② 10 分钟空闲 TTL 清理；③ 淘汰时对实现 `io.Closer` 的 Proxy 显式执行 `Close()`；④ 视图销毁时调用 `catalogRelease` |
| **R-4: 协调器状态冲突** | Medium | 用户在现役测速尚未结束时触发非活动节点测速 | 协调器保持单例互斥设计，忙碌时返回 `busy`，UI 层置灰测速按钮并给出明确提示，不并发双批次 |
| **R-5: 订阅源文件非法读取** | High | 传入恶意的相对路径或系统敏感路径尝试读取 | 强制路径前置校验：必须通过 `constant.Path.IsSafePath` 且前缀严格限定在 `<HomeDir>/profiles/providers/` 目录 |

---

## 6. 测试矩阵与验收门禁

### 6.1 单元测试（Go Core）
- 新增 `core/catalog_test.go`：
  - `TestCatalogPrepare_ValidInlineNodes`：验证标准 SS/Vless 节点解析成功，生成正确索引。
  - `TestCatalogPrepare_UnsupportedTypes`：验证 `wireguard` 返回 `typeUnsupported`，`dialer-proxy` 返回 `chainUnsupported`。
  - `TestCatalogPrepare_TooManyNodes`：验证 > 2000 节点直接拒绝并返回 `tooManyNodes`。
  - `TestCatalogPrepare_LRUAndRelease`：验证第 4 个 catalog 会淘汰最早的未锁定 catalog 并调用 Close。
  - `TestCatalogTestDelay_IsolatedExecution`：验证单节点测速返回正确延迟且不触发 `DelayMessage` 广播。

### 6.2 单元测试（Dart）
- 更新 `test/views/node_overview_test.dart` 与 `test/common/node_overview_providers_test.dart`：
  - 验证平铺渲染：在全部配置模式下，节点无需手风琴点击即可直接在列表中被检索到（`findsWidgets`）。
  - 验证左侧选择：点击左侧配置后，右侧仅渲染该配置节点，其他配置节点消失。
  - 验证活动节点：活动节点不再渲染 `ProxyCard`，渲染统一的扁平节点行并展示实时延迟。
  - 验证 P1 隔离测速路由：触发非活动节点测速时，正确路由至 `clashCore.catalogTestDelay`，结果正确写入 `nodeHealthStore`。

### 6.3 质量门禁与执行要求
- `go test -modfile=.generated/go.mod -overlay=.generated/mihomo-overlay.json ./core/...` 全绿。
- `flutter test test/views/node_overview_test.dart` 及全量测试通过。
- `dart analyze` 无新增 error 与 warning。
- 所有代码编写完成后，提交由 Tech Lead 进行独立 Code Review，并严格执行 Git 写操作。

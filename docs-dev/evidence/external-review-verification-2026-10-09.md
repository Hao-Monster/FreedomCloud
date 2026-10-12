# 外部程序员报告逐项核验

核验日期：2026-10-09（Asia/Singapore）。任务：核实用户提供的六项排查，把成立的问题追加或合并到 [性能、资源生命周期与可靠性 TODO](../performance-resource-todo-2026-10-09.md)。本轮交付是核验记录与待办，未实施产品修复。

## 1. 来源与基线

- 外部报告：`C:\Users\冯飏\.codex\attachments\65bc0539-0297-423b-903e-4596f05570a7\已粘贴的文本.txt`。
- 附件 SHA256：`DF8C9F99B99770CF350BB350A0A07DA2EEBD4BEC4F4D9F82C56FD9657B5B36DD`。
- 仓库：`E:\CodeWorkstation\FlClashX`，核验基线 `development@3227a863f5bdbb4ca7dc1f8caa5b7708d1f104dc`。本文源码位置均相对于仓库根目录；SDK 路径另行列明。
- 原审查基线：`c5c5ae4400d225cf2abefccb92184d29c1b81bcd`。`git diff --name-only c5c5ae4400d225cf2abefccb92184d29c1b81bcd..3227a863f5bdbb4ca7dc1f8caa5b7708d1f104dc` 仅有文档，产品源码相同。
- [原始审查报告快照](performance-resource-audit-2026-10-09.md) 保持不变。F01–F15 编号保留，同根因补证据，新缺陷顺延编号。
- 证据分别标明源码确认、隔离复现、只读进程观测和待测量。没有运行候选客户端、修改优先级、向其他应用菜单发送消息、切换代理/TUN 或操作服务。

## 2. 六项裁定与 TODO 对照

| 外部项 | 裁定 | 已确认范围与应收紧之处 | TODO |
|---|---|---|---|
| R01：HIGH 导致外壳饥饿，认定 P0/崩溃根因 | 设置事实成立；事故因果未证实 | 源码与进程快照均确认 High；缺少调度跟踪和对照，不能直接证明 Explorer/输入故障由它引起 | 保留 P01/P3 测量项，补证据边界 |
| R02：代理插件 RAS 失败泄漏、漏通知、Unicode 损坏 | 成立 | A/B 是既有错误路径；C 的 UTF-16 参数损坏已隔离复现；真实 WinINet 匹配未测 | F11-A/B 保留，追加 F11-C |
| R03：safeFuture 孤儿 Timer/Map 泄漏 | 多余定时器与延迟回收成立 | 默认约 30 秒，部分请求约 2 分钟；最终会清理，不能称永久泄漏 | 补充既有 F06 |
| R04：全桌面查找菜单，误操作其他应用 | 所有权缺陷成立 | 当前调用链会选择外部目标并尝试 WM_CLOSE/SetWindowTheme；实际效果受时序、权限与消息处理影响 | 新增 F16/P2，含监视启动时机子问题 |
| R05：桌面隐藏仍前台轮询，Core 永远 true 且全量发送 | 后台活跃控制缺口成立；两项绝对说法不成立 | 最小化/隐藏路径不完整；detach/会话退出会 false；Core 扫描后只发新增 ID；组刷新依赖 post-frame | 补充既有 F09 |
| R06：屏幕 DC 跨 await，是 GDI 上升直接来源 | 资源持有过久成立；持续泄漏及事故因果未证实 | Win32 finally 存在，当前单 UI isolate 串行提取；复制像素后可提前释放 | 新增 P02/P3 优化候选 |
| R06 核查中的额外发现 | PNG 编码异常遗漏显式释放成立 | `toByteData` 报错跳过 `ui.Image.dispose()`；尚未动态注入失败或测资源增长 | 新增 F17/P2 |

未采纳外部报告的 P0 事故归因，也未把全部问题统一称为内存泄漏。F11-C 是配置正确性问题；F06 是延迟保留；F16 是菜单所有权/生命周期缺陷；F17 是异常资源清理缺口；P01/P02 的性能收益需要测量。

## 3. R01：进程高优先级

### 已确认事实

- `windows/runner/main.cpp:16` 调用 `SetPriorityClass(GetCurrentProcess(), HIGH_PRIORITY_CLASS)`。
- `git log -p -S"HIGH_PRIORITY_CLASS" -- windows/runner/main.cpp` 将该设置追溯到 `bd6d0e152f77782fcf11ef9588e68a07e83bf3a1`。
- 本轮 Windows 只读快照：FlClashX PID 17076 为 High、BasePriority 13；可读 Explorer 实例为 Normal、BasePriority 8。
- 同次快照的 `dwm` PID 2196 为 BasePriority 13、80 个线程，`ctfmon` PID 9188 为 BasePriority 13、15 个线程。因此外部报告把 DWM/输入相关进程一概描述为 8–10 不准确。这里的线程数表示进程持有线程，不表示线程当时都在占用 CPU；进程 BasePriority 也不等于每条线程的瞬时动态优先级。

### 官方契约与证据限制

- [SetPriorityClass](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-setpriorityclass) 告诫谨慎使用 HIGH，CPU 密集的高优先级工作可能影响其他进程。
- [Scheduling Priorities](https://learn.microsoft.com/en-us/windows/win32/procthread/scheduling-priorities) 说明线程调度还取决于进程优先级类、线程相对/动态优先级和可运行状态。
- 上述文档不能支持“每次唤醒必然造成外壳故障”“GUI 一律禁止 HIGH”的绝对断言。外壳错误模块或相似症状也不能替代调度因果证据。

**决定**：补入 P01；记录固定负载下 NORMAL/HIGH 的 UI 帧耗时、桌面交互延迟、Core 吞吐、CPU 和工作集对照。ETW/调度跟踪与优先级切换测试均 NOT RUN，本轮未修改运行中进程。

## 4. R02：Windows 代理插件

### A/B：既有失败路径成立

`plugins/proxy/windows/proxy_plugin.cpp:34,46,50` 分配地址/选项数组，`81–84` 的 RAS 失败早退跳过 `91–96` 的释放与通知；stop 路径 `107,130–141` 有相同缺口。`InternetSetOption` 返回值未检查，`214–225` 的普通 StartProxy/StopProxy wrapper 仍返回成功。

这些问题已记录于 F11-A/B。确认的是“RAS 返回失败时这条路径泄漏并漏通知”，没有验证附件举例的 RAS 未启用、虚拟网卡异常等情况在本机必然产生该返回值，也没有据此归因旧的 USER 对象耗尽。PAC 分支已有错误传播，未来修复不得回退。

### C：Unicode 排除项参数损坏是新补充

真实输入路径：

1. `lib/views/config/network.dart:338–348` 保存排除列表。
2. `lib/widgets/input.dart:207–240,497–509,559–570` 检查非空/唯一，允许 Unicode，没有 IDN/Punycode 预转换。
3. `lib/providers/state.dart:156–175` → `lib/manager/proxy_manager.dart:37–43` → `plugins/proxy/lib/proxy_method_channel.dart:19–23` 原样传递列表。
4. Flutter `E:\flutter\packages\flutter\lib\src\services\message_codecs.dart:406–429` 将字符串编码为 UTF-8；C++ wrapper `windows/flutter/ephemeral/cpp_client_wrapper/standard_codec.cc:186–191` 将字节放进 `std::string`。
5. `plugins/proxy/windows/proxy_plugin.cpp:43` 直接以 `std::wstring(std::string.begin(), end())` 逐字节扩宽；`63–66` 交给 `INTERNET_PER_CONN_PROXY_BYPASS`。`windows/CMakeLists.txt:33` 开启 UNICODE。

同文件 `153–158` 的 SetPac 已使用 `MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, ...)`，可作为后续统一编码处理的已有模式。

### 隔离复现

环境：Windows，`g++.exe (Rev5, Built by MSYS2 project) 16.1.0`，真实 Flutter EncodableValue 头文件。探针复制上述单行转换表达式，用独立 UTF-16 期望值断言，并以严格 CP_UTF8 解码交叉核对。

本地探针目录：`C:\Users\冯飏\Documents\Codex\2026-10-08\new-chat\work\external-review-2026-10-09`。源文件 `proxy_unicode_probe.cpp`、程序 `proxy_unicode_probe.exe`、输出 `proxy_unicode_probe-output.txt`；为避免后续只剩私有路径，源码同时保存在本文附录。

```powershell
Set-Location -LiteralPath 'C:\Users\冯飏\Documents\Codex\2026-10-08\new-chat\work\external-review-2026-10-09'
& 'C:\msys64\ucrt64\bin\g++.exe' -std=c++17 -Wall -Wextra -static-libgcc -static-libstdc++ '-IE:\CodeWorkstation\FlClashX\windows\flutter\ephemeral\cpp_client_wrapper\include' '.\proxy_unicode_probe.cpp' -o '.\proxy_unicode_probe.exe'
& '.\proxy_unicode_probe.exe'
```

| 输入 | 结果 |
|---|---|
| `example.com` | PASS |
| `xn--fsqu00a.xn--0zwm56d` | PASS |
| `例子.测试` | FAIL：UTF-16 内容损坏 |
| `*.例子.测试` | FAIL：UTF-16 内容损坏 |

```text
unicode_idn current_utf16_equal=false
current_units= FFE4 FFBE FF8B FFE5 FFAD FF90 002E FFE6 FFB5 FF8B FFE8 FFAF FF95
expected_units= 4F8B 5B50 002E 6D4B 8BD5
RESULT checks=4 passed=2 failed=2 settings_mutated=false
```

编译 PASS，exit 0。执行 **2 PASS / 2 目标 FAIL / 0 SKIP，exit 1**，主代理复跑执行耗时 **166ms**，不含编译。exit 1 是缺陷复现，未产生修复后的 Green。

**边界**：没有调用 InternetSetOption、RAS、注册表或网络。这是原表达式的隔离复现，未通过完整插件 MethodChannel 执行，也未证明 Windows 最终 IDN 匹配或真实流量已错误代理。F11-C 的验收应分别覆盖编码保真与授权环境中的 WinINet 实际匹配；普通域名、Punycode、Unicode 通配符、`<local>`、非法编码和列表分隔语义都要保留。

## 5. R03：safeFuture 定时器与响应滞留

- `lib/common/future.dart:13–18` 无条件创建 `timeout + commonDuration` 的清理 Timer，成功完成不会取消。
- `lib/clash/interface.dart:105–145,148–190` 完成 Completer，但两个 map 要等 onLast 才移除。
- `lib/clash/interface.dart:237–270` 的 updateConfig/getConfig/setupConfig 使用 2 分钟 timeout；这解释了外部报告提到的更长保留窗口。
- 原审查真实类探针已有：60 次成功回复后 retainedCompleters=60、持有响应 6,000,170 字符；推进虚拟时间到 31 秒后清零。这里只引用原证据，本次未重复运行；字符数不能当作 heap 字节数。

**决定**：合并 F06，补自定义 2 分钟 timeout 的清理验收。最终会清理，不能写成永久孤儿或已实测长期无界增长。修复要在成功、错误、超时、断连等结束路径及时释放，并保持真正未完成请求的超时合同。

## 6. R04：菜单所有权与监视时机

### 当前生产入口仍然可达

- `lib/application.dart:88–98` 挂载 TrayManager。
- 原生 `plugins/tray_manager/windows/tray_manager_plugin.cpp:211–219` 的左键通知 → `plugins/tray_manager/lib/src/tray_manager.dart:68–73` → `lib/manager/tray_manager.dart:167–170` → `_closeWindowsPopupMenu`。
- 关闭函数 `lib/manager/tray_manager.dart:34–50` 以 `FindWindow('#32768', nullptr)` 查全桌面第一个匹配菜单，随后 PostMessage WM_CLOSE，没有 PID、线程或本次 popup 校验。
- 旧 HMENU 修复后的选择路径也可达：native `417–424` 以 `TPM_RETURNCMD | TPM_NONOTIFY` 返回选中 ID → Dart 插件 `270–275` 的 `_dispatchMenuClick` → `53–59` listener → 应用 `159–163` 再次关闭。TPM_NONOTIFY 没有绕过 Dart 回调。

### 主题监视也脱离自身 popup 生命周期

- 应用 `lib/manager/tray_manager.dart:152–156` 在 `await popUpContextMenu()` 返回后才启动监视；当前 native 此时已结束 TrackPopupMenu。
- `60–78` 每 100ms 全局查找，只有非零/可见性检查；`lib/common/windows.dart:134–155` 随后调用 SetWindowTheme，无归属校验。
- 若此时出现外部 Win32 菜单，可被选为操作目标；监视器也可能跟随外部菜单存在。

**决定**：新增 F16/P2，分别跟踪所有权与监视时机。优先让原生端按 popup owner/线程/展示生命周期管理；临时句柄校验至少包含 PID、线程、本次 popup 身份和有效性，PID 相同本身也不充分。覆盖左键、选中回调、右键展示、取消、错误和 dispose。

**边界**：源码证明错误目标可能被选中并尝试操作，实际关闭/主题效果取决于时序、UIPI 与接收方行为。不是所有 Chrome 等应用菜单都属于 #32768；正常外部点击本来也会关闭菜单，不能把“菜单消失”当作因果验证。本轮没有对真实外部窗口发消息或改主题，未证明它造成 Explorer 崩溃或 USER 长期增长。

## 7. R05：后台采样与 Core 活跃状态

成立的部分已属于 F09：`lib/manager/window_manager.dart:98` 的最小化仅暂停渲染，`lib/views/connection/connections.dart:135` 仍受当前页面与 window.visible 控制；`lib/common/window.dart:95` 的隐藏到托盘才修改 visible。`lib/manager/app_state_manager.dart:141–150` 中 setUiActive(false) 等暂停工作位于 Android 分支，桌面隐藏且 IPC 保持时缺少一致的活跃信号。

| 路径 | 当前事实 | 外部报告应收紧的说法 |
|---|---|---|
| `lib/controller.dart:56–65` | TUN 观察约每 3 秒 | 托盘/代理状态仍可能有必要的后台消费者 |
| `lib/state.dart:173–186` | 流量上一轮结束后再等 3 秒 | 不是无条件精确墙钟 3 秒并发触发 |
| `lib/controller.dart:335–340` | 运行时显示 Timer 为 1 秒 | 纳入是否仍有可见消费者的核对 |
| `lib/state.dart:214–221` | 60 秒 Timer 后等待 post-frame | 渲染暂停时不保证墙钟每 60 秒发组请求 |
| `core/hub.go:518–558` | 4 秒扫描活动连接，requestSeen 去重，仅发新增 ID | 不能写每轮全量 IPC 发送 |
| `lib/clash/service.dart:1009–1014`、`services/agent/src/runtime.rs:1368–1369` | detach/会话退出已有 setUiActive(false) | 不能写 uiActive 永远 true |

**决定**：补入 F09 的修复/验收清单，统一实际可见性、页面订阅、最小化与 Core 消费者状态。必要的后台代理/TUN/托盘更新保留；不一律停止所有 Timer。CPU、IPC 分配与耗电收益未做真实前后台对照，不填写优化百分比。

## 8. R06：图标 DC 持有与额外异常缺口

### P02：缩短原生资源持有范围

`lib/common/process_icon.dart:239` 获取 HDC，`240–251` 已读取并复制 BGRA 到 Dart 内存，原生资源仍保持到 `275/276` 两次 await 后的 `279–286` finally；外层 `203–207` 才销毁 HICON。复制像素后可提前释放这些资源。

但正常完成、同步异常、编码 Future 报错均会执行 Win32 finally；当前 `_extractQueue`（`170–182`）串行等待完整提取/编码，同一 UI isolate 同时至多一组正在提取的 Win32 图标资源。`13–33` 的图标缓存有 64 项上限，`lib/common/memory_policy.dart:3–4,14–16` 的 decoded image cache 有 256 项/32MiB 上限。缓存上限不等于提取排队上限，已淘汰任务是否继续做无用工作需单独测量。

已查阅官方 [GetDC](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getdc)、[ReleaseDC](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-releasedc) 与 [Common Display Device Contexts](https://learn.microsoft.com/en-us/windows/win32/gdi/common-display-device-contexts)：要求同一线程获取/释放、common DC 用后释放，并建议尽快释放。所查页面没有附件声称的“严禁跨消息循环”原文；await 也不能独立证明切换了 OS 线程，源码没有把该 HDC 交给其他 isolate/thread。

**决定**：新增 P02/P3，像素复制后结束原生提取作用域，测慢编码下的持有时长、USER/GDI 与队列积压。没有连续采样证实本段造成持续 GDI 泄漏或历史外壳事故。

### F17：PNG 编码失败遗漏 ui.Image.dispose

```dart
final image = await completer.future;                // process_icon.dart:275
final png = await image.toByteData(format: ui.ImageByteFormat.png); // 276
image.dispose();                                    // 277
```

[Image.toByteData](https://api.flutter.dev/flutter/dart-ui/Image/toByteData.html) 允许编码 Future 报错，[Image.dispose](https://api.flutter.dev/flutter/dart-ui/Image/dispose.html) 要求持有者不再使用图像时释放；同时核对本机 SDK `E:\flutter\bin\cache\pkg\sky_engine\lib\ui\painting.dart:2057–2065,2104–2112`。

若第 276 行报错，第 277 行不会执行。外层 finally 只清 Win32/FFI 资源，`_loadWindowsIcon` 的 `178–179` catch 降级 null 也不会补偿图像释放。

**决定**：新增 F17/P2，给已创建的 ui.Image 建立独立 try/finally，成功、null、抛错均释放恰好一次，失败后串行队列继续。确认的是遗漏显式释放、回收时机失控；未动态注入编码失败，也未测得永久无限泄漏。解码回调不返回仅列为待验证边界，不当成已复现死锁。

## 9. 验证矩阵与未运行项目

| 核验/命令 | 结果 | 证据强度与限制 |
|---|---|---|
| 附件 Get-FileHash、基线 git diff、相关源码/调用点读取 | PASS | 核对输入、版本与可达性；不等于运行中故障复现 |
| HIGH 历史 git log、Get-Process 只读采样 | PASS | 配置/快照事实；无调度因果结论 |
| 第 4 节 g++ 编译命令 | PASS，exit 0 | Windows g++ 16.1.0；完整编译耗时未单独记录 |
| 第 4 节 probe 执行命令 | FAIL，exit 1；2 PASS / 2 FAIL / 0 SKIP；166ms | 两项 Unicode 目标缺陷复现，未修复 |
| F11 RAS 失败/部分代理应用、WinINet IDN 实际匹配 | NOT RUN | 本轮不更改系统代理；留待获准隔离环境 |
| F16 own/foreign/stale/reused 菜单隔离交互与权限测试 | NOT RUN | 本轮仅核对源码调用链，未向外部窗口发送消息 |
| F17 PNG 编码失败注入、P02 缓慢编码/队列/长时资源压力 | NOT RUN | 源码与 API 契约确认，资源增长量未知 |
| P01 NORMAL/HIGH 对照、F09 前后台 CPU/耗电/IPC profile | NOT RUN | 未调整优先级或窗口运行状态；收益待测 |
| 修复后 Green、完整 Flutter/Go/Agent/Helper 回归、发布构建、覆盖率 | NOT RUN | 本轮仅核验/文档，未改产品实现；不冒用原审查或此前修复的测试成绩 |

提交前 PowerShell 文档检查 **PASS，exit 0**：F01–F17 各有一处总待办和详细章节且均为 OPEN，原 F01–F15 完整保留；P01/P02、V01–V05、H01/S01 共 9 个辅助章节保留；8 个本地链接与 27 个不同源码路径有效；附录与实际运行的 probe 源码一致；原快照及产品源码未变。`git diff --check` **PASS，exit 0**，仅提示已有的 LF/CRLF 工作树转换规则。

独立只读复核检查了原条目保留、六项映射、F16 的当前原生/Dart 调用链、F17/P02 的资源边界、附件 hash 与 probe 输出，无阻塞问题。将进程线程数量误读为线程正在运行的歧义已在 TODO 中消除；快照不能证明实时调度状态。

## 附录：Unicode 隔离探针源码

以下为本轮实际运行的 `proxy_unicode_probe.cpp`；仅复制问题表达式，不执行系统代理设置。预期在当前缺陷基线返回 exit 1。该探针不是完整插件端到端测试。

```cpp
#include <windows.h>

#include <flutter/encodable_value.h>

#include <iomanip>
#include <iostream>
#include <string>

// Isolated copy of the exact bypass-list expression at
// plugins/proxy/windows/proxy_plugin.cpp:43 (3227a86).
// No InternetSetOption, registry, RAS, network, or process operations.
std::wstring currentExpression(const flutter::EncodableValue& domain) {
  std::wstring wBypassList;
  wBypassList += std::wstring(std::get<std::string>(domain).begin(), std::get<std::string>(domain).end());
  return wBypassList;
}

std::wstring utf8Decode(const std::string& input) {
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
      input.data(), static_cast<int>(input.size()), nullptr, 0);
  if (length <= 0) throw std::runtime_error("UTF-8 decoding failed");
  std::wstring result(length, L'\0');
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
      input.data(), static_cast<int>(input.size()), result.data(), length) != length) {
    throw std::runtime_error("UTF-8 decoding failed");
  }
  return result;
}

void printUnits(const std::wstring& value) {
  for (const auto unit : value) {
    std::cout << " " << std::hex << std::uppercase << std::setfill('0')
              << std::setw(4) << static_cast<unsigned int>(unit);
  }
  std::cout << std::dec;
}

int main() {
  static_assert(sizeof(wchar_t) == 2, "This probe requires Windows UTF-16 wchar_t");
  struct Case {
    const char* name;
    std::string utf8;
    std::wstring expected;
  };
  const Case cases[] = {
      {"ascii", "example.com", L"example.com"},
      {"punycode", "xn--fsqu00a.xn--0zwm56d", L"xn--fsqu00a.xn--0zwm56d"},
      {"unicode_idn", "\xE4\xBE\x8B\xE5\xAD\x90.\xE6\xB5\x8B\xE8\xAF\x95", L"\u4F8B\u5B50.\u6D4B\u8BD5"},
      {"unicode_wildcard", "*.\xE4\xBE\x8B\xE5\xAD\x90.\xE6\xB5\x8B\xE8\xAF\x95", L"*.\u4F8B\u5B50.\u6D4B\u8BD5"},
  };
  int failed = 0;
  for (const auto& item : cases) {
    const flutter::EncodableValue domain(item.utf8);
    const auto actual = currentExpression(domain);
    const auto decoded = utf8Decode(item.utf8);
    if (decoded != item.expected) {
      std::cerr << "PROBE_SETUP_ERROR " << item.name << "\n";
      return 2;
    }
    const bool passed = actual == item.expected;
    std::cout << item.name << " current_utf16_equal=" << std::boolalpha << passed
              << " current_units=";
    printUnits(actual);
    std::cout << " expected_units=";
    printUnits(item.expected);
    std::cout << "\n";
    if (!passed) ++failed;
  }
  std::cout << "RESULT checks=4 passed=" << (4 - failed) << " failed=" << failed
            << " settings_mutated=false\n";
  return failed == 0 ? 0 : 1;
}
```

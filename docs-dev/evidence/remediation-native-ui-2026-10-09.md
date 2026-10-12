# F02/F11/F16/F17 与 P02 修复记录

基线：`development@a52907c`。仅代码/隔离测试，不运行候选客户端或操作系统代理/外部菜单。

## 方案与测试矩阵

| 项目 | 方案 | 回归场景/文件 | 命令 |
|---|---|---|---|
| F02 | 下载流32MiB上限、总期限60秒、最多4096项/单项16MiB/总128MiB；预检路径/重复/类型/ZIP头，再受限解压到唯一暂存目录，成功后rename，失败保留旧目录，同目标单飞 | `test/common/zashboard_test.dart`：真实ZIP正常/越界/链接/重复/损坏/超限/取消/并发/失败 | `flutter test --no-pub test/common/zashboard_test.dart` |
| F11 | 枚举RAS先于写入；wstring/栈数组/RAII持有，严格UTF-8；部分写入失败仍通知并返回首个错误 | `plugins/proxy/windows/tests/`：生产helper注入WinINet/RAS边界，不实际修改代理；UTF-8及所有失败分支 | 原生编译/独立测试脚本 |
| F16 | 删除全桌面查菜单与过期监视Timer；native popup自然关闭，保留应用范围深色主题初始化 | 现有tray plugin/menu lifetime回归；确认不存在FindWindow/外部HWND消息调用入口 | `flutter test --no-pub test/common/tray_plugin_menu_test.dart test/common/tray_refresh_test.dart` 与 native Run-Tests |
| F17/P02 | Win32同步复制像素后释放所有句柄，异步编码独立图像finally | `test/common/process_icon_test.dart`：真实ui.Image成功、null、抛错，dispose一次；原生提取只读资源采样 | `flutter test --no-pub test/common/process_icon_test.dart` |

不把移除危险菜单操作后的静态调用链检查冒充真实跨应用交互；动态故障/长时/用户本机验收保持独立。

## 执行结果

### F02：受限下载与安装

- 正式回归 `test/common/zashboard_test.dart` 21 项通过，覆盖合法嵌套目录/正反斜杠、八类危险路径、symlink、大小写冲突、缺 index、损坏包、四种预算、伪报解压量、Content-Length、旧目录保留、同目标单飞、取消/期限后重试、文件系统失败。
- 独立复核固定依赖 archive 4.0.7 后补充两道 parser 前门禁：拒绝 ZIP comment（防其末尾伪 EOCD 被解码器重新选择），验证 central/local 名称长度、唯一 local offset、signature、flags、压缩方式、内容范围及 data descriptor。相关恶意输入加入回归。ZIP64、多卷、加密和非 store/deflate 包明确拒绝。
- 外部取消以可解除订阅传递，finally 解除，避免长寿命 CancelToken 保留已完成下载的 token/requestOptions；暂存目录清理失败记录日志，不把 finally 异常变成未处理错误。
- 原始越界 Red 见历史审查 probe；本轮新增单飞初稿出现真实超时：`whenComplete` 的表达式返回了 map 中同一个 Future，形成自等待。改为无返回值清理后通过成功/并发/失败重试用例。初轮还暴露测试日志插件 fixture 缺失，已用独立临时日志目录修正；插件环境错误不计作产品 Red。

### F11：普通 Windows 代理

- `plugins/proxy/windows/tests/Run-Tests.ps1 -Mode Regression`：PASS，exit 0，1379ms。真实生产 helper 配合 WinINet/RAS API 替身，覆盖 ASCII/Punycode/Unicode/通配符/`<local>`、start/stop、2000 次 RAS 失败循环、启停共 8 个写入/通知失败点、非法 UTF-8/NUL/端口。设置调用次数与错误返回逐项断言，没有修改实际代理。
- `-Mode NativeCompile`：PASS，exit 0，1649ms；生产插件按 `/W4 /WX` 编译。
- UTF-8 → UTF-16 的修复前 2 PASS/2 目标 FAIL 隔离证据保留于外部审查记录。RAS 分支没有额外伪造 Red；其所有权缺口经源码确认，当前生产 helper 的故障回归覆盖释放后恢复和零写入约束。
- 当前合同保留 Unicode/ASCII/Punycode、通配符与 `<local>` 原意，拒绝非法编码和嵌入 NUL。实际 Windows IDN 匹配行为仍为 NOT RUN，不据字符串单测宣称系统匹配已验收。

### F16：托盘菜单

- 删除全桌面 `FindWindow('#32768')`、对外部菜单发消息以及 100ms 监视器。主题仅在本进程展示前配置；native `TrackPopupMenu` 负责选择/取消，foreground/WM_NULL 仅操作自己的 owner。
- 新 widget 用例验证并发右键只开一次、取消后可重新打开、dispose 无遗留回调。已有菜单快照、更新合并和回调用例保持通过。
- native `Run-Tests.ps1 -Mode Regression`：8 组 PASS，exit 0，1568ms；`-Mode NativeCompile`：PASS，1968ms；`-Mode Win32`：200 次真实菜单资源替换 PASS，USER 1→1，1320ms。未展示菜单或操作其他应用。
- 外部/陈旧 HWND 测试策略改为删除该类查找/操作入口，源码复核没有外部窗口操作路径；真实多程序菜单/不同权限交互留作用户或隔离 VM 验收。

### F17/P02：图像与原生资源

- 同步 Win32 阶段复制 BGRA 后即释放 HDC/HBITMAP/buffer/HICON；异步 Flutter 解码与 PNG 编码均有独立 finally，codec/descriptor/ImmutableBuffer 也显式 dispose。
- 解码改用可传播失败的 Future API，取代只有成功回调的等待；原串行提取和缓存上限保持。
- 真实 `ui.Image` 测试 Red 为 2 PASS/1 目标 FAIL（编码异常后 `debugDisposed=false`）；修复后成功/null/error 三项 PASS，后续编码正常。新解码路径也经过下述集成编译/测试。
- Win32 图标压力采样、延迟编码时的 GDI/USER 曲线、队列峰值、图标视觉回归 NOT RUN；不宣称性能百分比或旧任务栏故障因果。

### 统一目标验证

命令：`E:\flutter\bin\flutter.bat test --no-pub test/common/zashboard_test.dart test/common/process_icon_test.dart test/common/tray_refresh_test.dart test/common/tray_plugin_menu_test.dart --reporter expanded`。

结果：**43 PASS / 0 FAIL / 0 SKIP，exit 0**，测试执行段约 1 秒（加载/编译另计）。四文件分别为 21/3/9/10 项。最终 `dart analyze --format=machine` 检查本组 8 个修改文件：**exit 0，0 error、0 warning、29 info**；info 为 IO/风格提示。测试直接使用的 `fake_async` / `path_provider_platform_interface` 已明确声明为 dev_dependencies，锁文件仅把原有条目标为 direct dev，版本/hash 未变。分析输出保存在聊天 `work/performance-audit/native-ui-remediation-analyze-final.txt`；`git diff --check` PASS。

覆盖率：43项目标运行没有单独采集；最终457项全量另行收集 line/branch coverage，逐文件及改动范围见 `../remediation-results-2026-10-09.md`。没有运行候选客户端、真实 WinINet 修改、SCM、TUN、驱动或本机桌面交互验收。

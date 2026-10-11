# 套餐卡片富文本补全：测试矩阵与验收记录

日期：2026-10-11。范围：仅套餐卡片内容展示；不改后端、目录可见性、账户/兑换/支付或其他页面。起点development@c2fe8c5，保留现有v2方案草稿和QA文件。

本轮匿名GET已确认当前公开套餐1条、正文163字符，正文为Markdown且无图片；现有名称、正文、价格、限额、标签、重置和名额已实现。剩余差异是后台编辑器支持的图片仅显示占位，以及链接内部格式被压成纯文本。支持安全HTTPS图片是本次“后台内容完整展示”的增量，不支持任意HTML或脚本执行。

| ID | 验收/风险 | 验证位置与预期 | 执行前状态 |
| --- | --- | --- | --- |
| C1 | 当前公开模板结构与全部产品字段 | API/宿主/卡片测试，后台标题、条目、注意事项完整可见，卡片布局与匿名请求不变 | NOT RUN |
| C2 | 链接内粗体/斜体/删除线/下划线/代码 | details测试先Red，再验证实际TextSpan样式、原HTTPS点击与键盘，不压平或执行HTML | NOT RUN |
| C3 | 下划线仍是行内内容 | 字面#、组合装饰与嵌套链接保持原语义，不再次当成块级标题解析 | NOT RUN |
| C4 | 普通图片与链接图片 | 合成图片传输/解码成功后实际RawImage可见；保留alt与链接按钮；窄卡片不溢出 | NOT RUN |
| C5 | 图片安全/错误/资源限制 | 仅HTTPS无userinfo；无账号认证/cookie/referer；证书拒绝不放宽；重定向、超时、过大响应、非图像/损坏图像可读失败；释放连接/取消未完成请求；并发与累计解码像素有界 | NOT RUN |
| C6 | 不安全/无效图片及HTML | file/data/http/相对/畸形图片不发请求，仅保留说明；raw HTML不执行；旧危险链接保护保留 | NOT RUN |
| C7 | 长列表/表格/大字与主题 | 320/360px、2x、明暗、宽表/代码块、长编号用例；无未声明溢出，正文可达 | NOT RUN |
| C8 | 购买回归与静态/资源编译 | test/purchase、定向analyze、全Flutter相关回归和UI资源编译；真实客户端/线上兑换NOT RUN | NOT RUN |

使用现有Flutter3.47.4/Dart3.13.3（CI3.41.7），现有依赖不升级。测试使用合成内容，不下载线上图片、不消费真实兑换码，不启动完整应用或代理/TUN。图片自动请求不携带登录凭据，保留正常代理路由且独立强制TLS校验；外部链接仍需用户点击。

## 实施与证据（2026-10-11至2026-10-12）

### 核实结果与范围

- `70c4643` 已有套餐卡片、顾客可见字段、七种新购周期及单列重置标价，不重复改解析器或商业行为。
- 后端编辑器实际契约是Markdown/GFM和精确无属性`<u>`，不是任意HTML。公共正文没有摘要/截断；内部权限、分销、组ID等控制字段不等同于应给顾客显示的套餐说明。
- 本次仅修改`lib/views/purchase/plan_content.dart`和新增`plan_image.dart`，修复链接内样式、下划线行内语义、代码块干扰列表缩进，增加受限HTTPS栅格图片。既有包、其他页面、账户、兑换、微信联系和订阅同步未修改。
- 独立预审指出单图有上限但多图累计无界，因此在最终验证前补充共享加载并发和累计解码预算测试；没有引入缓存架构或新生产依赖。

### 已执行的基线与Red→Green

命令均使用`E:/flutter/bin/flutter.bat`和`--no-pub --reporter expanded`；环境Windows、Flutter3.47.4/Dart3.13.3。测试使用合成数据，未消费真实卡、下单、启动主应用或调用线上图片。

| 执行 | 状态 / exit | 数量 / 时间 | 证据 |
| --- | --- | --- | --- |
| 修改前5个plan_catalog API/widgets/details/host/manager测试文件 | PASS / 0 | 128通过、0失败、0跳过；runner约4秒 | 已有卡片与匿名目录基线 |
| details `--plain-name 'links preserve inline emphasis'` | FAIL / 1 | 0通过、1失败、0跳过 | 链接粗体TextSpan断言为false，文字被压平 |
| details `--plain-name 'underline contents stay inline'` | FAIL / 1 | 0通过、1失败、0跳过 | `# 字面标题`丢失，被二次当标题解析 |
| details `--plain-name 'code block numbers'` | FAIL / 1 | 0通过、1失败、0跳过 | 320px/2x下RenderFlex向右溢出87px |
| 修复后details | PASS / 0 | 35通过、0失败、0跳过；runner2秒 | 上述3条原失败用例全部转Green |
| 补充嵌套链接与raw HTML安全断言后details + render | PASS / 0 | 37通过、0失败、0跳过；runner2秒 | 36详情用例+1截图用例 |
| 图片并发保护Red（`--plain-name 'twenty stalled images'`） | FAIL / 1 | 0通过、1失败、0跳过 | 同时产生20个client，预期4个；非编译失败 |
| 图片累计预算Red（`--plain-name 'shared raster budget'`） | FAIL / 1 | 0通过、1失败、0跳过 | 实际5张2048平方图片，预期最多4张；非编译失败 |
| 图片完整套件`plan_image_test.dart` | PASS / 0 | 19通过、0失败、0跳过 | 普通/链接/混合/下划线/表格/列表共6张真实合成图均成功、恰好6请求、重建不重载；并发/预算Red转Green |
| `test/purchase`首轮完整回归 | PASS / 0 | 293通过、0失败、0跳过；墙钟33.49秒 | 包括原账号/兑换/同步/匿名目录；随后又修正下列正文边界 |
| 末次审查`--plain-name 'underline ignores closing tags'` | FAIL / 1 | 0通过、1失败、0跳过 | 下划线内代码包含`</u>`时被提前截断 |
| 最终details | PASS / 0 | 37通过、0失败、0跳过；runner3秒 | 改为单次索引合法结束标签，跳过代码/转义；原未闭合u性能断言保持通过 |

初次定向`dart analyze --fatal-infos`因新增测试中的`FontWeight.index`产生2条弃用info而exit1；已改为明确的`FontWeight.bold`断言，未降低测试预期。图片文件首次测试因新文件尚不存在而编译失败，只是测试先行骨架检查，不作为业务Red证据。

### 视觉检查

`test/purchase/plan_catalog_render_test.dart`离线渲染真实Widget树：浅色、深色、360px窄窗、320px/2x大字四种状态，输出在`build/plan-card-rich-content-preview/catalog-{light,dark,narrow,large-text}.png`。均已实际查看；没有溢出、正文尾段丢失或标记漏显。新增monospace测试字体加载仅修正截图环境的Ahem占位，不改变生产字体。

这些是合成套餐的组件截图，不是已安装客户端或完整Windows窗口验收。尚未打新可执行包。

### 图片能力及安全边界

- 使用独立HttpClient保留应用现有代理路由，覆盖宽松证书回调为拒绝；无Authorization/Cookie/Referer，不跟随重定向、不复用账号API客户端。
- 来源仅有效HTTPS栅格，单次下载4MiB，取得共享槽位后15秒超时；源最大边8192且总像素16MP，目标最大边2048。PNG/JPEG/WebP/GIF/BMP等由原生codec解码，动画仅显示首帧；SVG/HTML不执行，HTTP/file/data/相对地址不发请求。
- 同时最多4项工作；共享目标栅格预留/持有上限16MP（按RGBA约64MiB），包括解码前预留。不把此数当作进程RSS或原生codec临时分配上限。
- 源切换/卸载取消排队与正在请求的连接；成功后的预算归图像包装对象持有，失败/取消/迟到结果及销毁均释放。共享预算超限、加载失败和不支持资源保留本地化提示与alt，不显示URL或伪装加载成功。
- 原生解码内部执行中故障注入/取消尚未做平台级测试；槽位在真实工作退出后释放的路径经独立源码复核。安全传输测试使用HttpOverrides替身，不把它当作真实远端TLS/设备验收。

### 最终执行与验收结果

下表命令前缀使用`E:/flutter/bin/`下的相应SDK脚本。全部对应最终产品代码；首次全量589通过之后只补充了2条测试，没有再次改变生产代码。

| 命令 | 状态 / exit | 通过 / 失败 / 跳过 | 时间与说明 |
| --- | --- | --- | --- |
| `flutter test --no-pub test/purchase/plan_catalog_details_test.dart test/purchase/plan_image_test.dart --reporter expanded` | PASS / 0 | 58 / 0 / 0 | runner2秒；38详情+20图片，含连续u、硬换行、流中断 |
| `flutter test --no-pub --coverage --branch-coverage --coverage-path build/plan-card-rich-content-coverage/lcov.info --reporter expanded` | PASS / 0 | **591 / 0 / 0** | 最终墙钟97.33秒；此前同产品代码589项首轮100.20秒 |
| `dart analyze --fatal-infos lib/views/purchase test/purchase` | PASS / 0 | 无测试计数；0 error/warning/info | 最终补测后重新执行，无问题；未单独计时 |
| `dart format --output=none --set-exit-if-changed`加5个本次Dart文件 | PASS / 0 | 无测试计数 | 5文件0修改；新增末次测试另正常格式化 |
| `flutter build bundle --no-pub --debug --target-platform windows-x64 --asset-dir build/plan-card-rich-content-assets --depfile build/plan-card-rich-content-assets.d` | PASS / 0 | 无测试计数 | 墙钟24.81秒；kernel_blob.bin 89,641,248字节、AssetManifest.bin 2,021字节；只是UI资源编译，不是可执行包 |
| `git diff --check` | PASS / 0 | 无测试计数 | 未放宽lint或添加skip/ignore；既有LF/CRLF提示不影响检查 |

| 验收项 | 最终结果 | 证据范围 |
| --- | --- | --- |
| C1 完整字段/模板内容/匿名目录 | PASS | API/widgets/details/host/manager；当前线上模板只读核实，三段结构使用合成对应测试；无服务端管理字段扩展 |
| C2 链接内部样式/点击/键盘 | PASS | 实际TextSpan样式、HTTPS按钮、Tab/Enter、危险链接不可操作 |
| C3 下划线行内语义 | PASS | 字面标题符号、嵌套强调/链接、代码/转义结束标签、连续u/硬换行、不闭合长正文 |
| C4 图片渲染与卡片集成 | PASS | 合成图经实际Markdown/RawImage成功解码、alt语义、链接/列表/表格及320px/2x |
| C5 图片安全与资源 | PASS（本地边界） | 20项图片用例，含安全来源、证书回调/代理、大小/类型、超时/中断、4路并发、16MP预算、取消/归还 |
| C6 HTML/不安全来源 | PASS | raw HTML原样且0资源请求；不安全图片不创建client；未启用脚本或WebView |
| C7 布局/主题/大字 | PASS（组件） | 四张实际检查过的截图、窄列表/长编号/表格/完整末段用例；不是原生应用实机验收 |
| C8 回归/静态/编译 | PASS（本地） | 全Flutter591、analyze无问题、UI资源编译成功；CI与可执行包另行验证 |

### 覆盖率

读取最终LCOV，并以`git diff --unified=0`的新侧行号计算diff覆盖；新增`plan_image.dart`全文件纳入新增行。只计算LCOV实际记录的可执行行/分支，不把无执行记录的构造字段算作通过。

| 范围 | 行覆盖 | 分支覆盖 |
| --- | --- | --- |
| `plan_content.dart`整文件 | 145/147（98.64%） | 50/51（98.04%） |
| 新增`plan_image.dart` | 177/179（98.88%） | 65/71（91.55%） |
| 本次可执行diff合计 | **290/293（98.98%）** | **104/111（93.69%）** |

未覆盖的主要路径：默认父文字样式兜底；原生图像已成功生成的精细取消/迟到时间窗口。图像解码内部故障注入没有伪造为已测试，也未用跳过/削弱断言换取覆盖。

### 审查、Git与未运行项

- 两个独立只读审查确认接口/模型/价格/兑换/其他页面没有被改动；多图资源与富文本结束标签发现已用针对测试复现并修正。最终没有已知本次Critical/High阻塞。
- 仅把本次2个产品文件、3个测试文件、本报告和台账的新增段落保存为development本地提交；原先checkout/redemption方案草稿、coverage、QA/probes等保留，不混入本提交。恢复位置是本工作树和本地提交，未清理旧成果。
- **NOT RUN**：线上真实图片/TLS设备验收、真实账号/卡兑换、完整Windows客户端窗口与代理/TUN、原生解码故障注入、跨平台设备、Core/Agent/Helper新测试、当前提交CI；原因分别为使用合成隔离边界、本任务无真实消费/启动/发布授权及未改变相关组件。
- 未推送、未创建/合并PR、未打新可执行安装包、未部署。已安装客户端是否包含此前卡片提交不能从源码HEAD推断，本报告不声称当前运行客户端已经更新。
- 回退限本次两个展示文件及对应测试的可追溯提交；不涉及后端迁移或用户数据回滚。

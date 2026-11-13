// DO NOT EDIT. This is code generated via package:intl/generate_localized.dart
// This is a library that provides messages for a zh_CN locale. All the
// messages from the main program should be duplicated here with the same
// function name.

// Ignore issues from commonly used lints in this file.
// ignore_for_file:unnecessary_brace_in_string_interps, unnecessary_new
// ignore_for_file:prefer_single_quotes,comment_references, directives_ordering
// ignore_for_file:annotate_overrides,prefer_generic_function_type_aliases
// ignore_for_file:unused_import, file_names, avoid_escaping_inner_quotes
// ignore_for_file:unnecessary_string_interpolations, unnecessary_string_escapes

import 'package:intl/intl.dart';
import 'package:intl/message_lookup_by_library.dart';

final messages = new MessageLookup();

typedef String MessageIfAbsent(String messageStr, List<dynamic> args);

class MessageLookup extends MessageLookupByLibrary {
  String get localeName => 'zh_CN';

  static String m0(node) => "当前节点：${node}";

  static String m1(count) => "规则覆写 ${count}";

  static String m2(count) => "共 ${count} 个节点";

  static String m3(label) => "确定删除选中的${label}吗？";

  static String m4(label) => "确定删除当前${label}吗？";

  static String m5(label) => "${label}不能为空";

  static String m6(label) => "${label}当前已存在";

  static String m7(time, elapsed) => "上次检查 ${time} · 用时 ${elapsed}";

  static String m8(mb) => "IPC 正常 · ${mb} MB";

  static String m9(exitPart) => "已验证经过代理${exitPart}";

  static String m10(node) => "节点 ${node} 无法连通探测地址";

  static String m11(node) => "节点 ${node} 测速地址受限，但端到端实测已连通";

  static String m12(node) => "节点 ${node} 延迟偏慢";

  static String m13(count) => "已加载（${count} 个策略组）";

  static String m14(days) => "剩余 ${days} 天到期";

  static String m15(percent) => "流量已使用 ${percent}%";

  static String m16(flag) => " · 出口 ${flag}";

  static String m17(delay) => "当前为直连模式 · 本机外网 ${delay} ms";

  static String m18(node, delay, exitPart) =>
      "节点 ${node} · 出站 ${delay} ms${exitPart}";

  static String m19(available, tested, total) =>
      "节点：可用 ${available} / 已测 ${tested} / 共 ${total}";

  static String m20(count) => "共 ${count} 个配置";

  static String m21(text) => "公告：${text}";

  static String m22(profile, node, delay) =>
      "已自动连接最快节点：${profile} · ${node}（${delay} ms）";

  static String m23(profile, node, delay) =>
      "已开启智能选择节点：${profile}（当前最快：${node} · ${delay} ms）";

  static String m24(node) => "已自动选中 ${node}（当前节点测速均未连通，若无法上网请更新订阅或切换其他节点）";

  static String m25(node) => "已选中节点 ${node}，但该订阅已过期，请更换订阅或续费后点击更新订阅";

  static String m26(node) => "已选中节点 ${node}，但该订阅剩余流量已用尽，请续费或更换订阅";

  static String m27(hours) => "自动更新 ${hours}h";

  static String m28(minutes) => "自动更新 ${minutes}m";

  static String m29(count) => "失败 ${count}";

  static String m30(count) => "流畅 ${count}";

  static String m31(count) => "偏慢 ${count}";

  static String m32(count) => "未测 ${count}";

  static String m33(completed, failed, untested, profiles) =>
      "已完成 ${completed} · 失败 ${failed} · 未测 ${untested} · 异常配置 ${profiles}";

  static String m34(name) => "当前活动：${name}";

  static String m35(date) => "到期时间：${date}";

  static String m36(days) => "剩余 ${days} 天";

  static String m37(hours) => "剩余 ${hours} 小时";

  static String m38(count) => "${count} 个已过期";

  static String m39(count) => "${count} 个即将到期";

  static String m40(provider) => "配置文件 · ${provider}";

  static String m41(median) => "全局中位：${median}";

  static String m42(median, best) => "中位延迟：${median} · 最快 ${best}";

  static String m43(available, tested, total) =>
      "可用 ${available} / 已测 ${tested} / 总数 ${total}";

  static String m44(time) => "上次活动时测速：${time}";

  static String m45(time) => "同步时间：${time}";

  static String m46(time) => "最近测速：${time}";

  static String m47(profile, node) => "已锁定固定节点：${profile} · ${node}";

  static String m48(delay) => "中位延迟：${delay}";

  static String m49(count) => "另有 ${count} 类问题";

  static String m50(available, total) => "可用 ${available} / ${total}";

  static String m51(date) => "到期 ${date}";

  static String m52(count) => "共 ${count} 个";

  static String m53(completed, total) => "${completed} / ${total}";

  static String m54(provider) => "${provider}：激活后可见节点";

  static String m55(profile) => "代理已开启 · 智能选择：${profile}（自动优选中）";

  static String m56(profile, node) => "代理已开启 · 智能选择：${profile} · ${node}";

  static String m57(profile, node) => "代理已开启 · 正在使用 ${profile} · ${node}";

  static String m58(traffic) => "剩余流量：${traffic}";

  static String m59(profile, node) => "已切换至 ${profile} · ${node}";

  static String m60(profile) => "已开启智能选择节点：${profile}";

  static String m61(profile, node) => "已开启智能选择节点：${profile}（当前：${node}）";

  static String m62(used, total) => "已用 ${used} / 共 ${total}";

  static String m63(used) => "已用流量：${used}";

  static String m64(label) => "暂无${label}";

  static String m65(label) => "${label}必须为数字";

  static String m66(label) => "${label} 必须在 1024 到 49151 之间";

  static String m67(plan) => "已打开「${plan}」购卡页";

  static String m68(plan, quota, price) =>
      "您好，我想咨询购买【${plan} · ${quota} GiB（${price}）】兑换码。";

  static String m69(count) => "仅剩 ${count} 席";

  static String m70(code) => "未知规则（${code}）";

  static String m71(count) => "已选择 ${count} 项";

  static String m72(days) => "您的订阅将在${days}天后到期";

  static String m73(reason) => "虚拟网卡：${reason}";

  static String m74(label) => "${label}必须为URL";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
    "about": MessageLookupByLibrary.simpleMessage("关于"),
    "accessControl": MessageLookupByLibrary.simpleMessage("访问控制"),
    "accessControlAllowDesc": MessageLookupByLibrary.simpleMessage(
      "只允许选中应用进入VPN",
    ),
    "accessControlDesc": MessageLookupByLibrary.simpleMessage("配置应用访问代理"),
    "accessControlNotAllowDesc": MessageLookupByLibrary.simpleMessage(
      "选中应用将会被排除在VPN之外",
    ),
    "account": MessageLookupByLibrary.simpleMessage("账号"),
    "action": MessageLookupByLibrary.simpleMessage("操作"),
    "action_mode": MessageLookupByLibrary.simpleMessage("切换模式"),
    "action_proxy": MessageLookupByLibrary.simpleMessage("系统代理"),
    "action_start": MessageLookupByLibrary.simpleMessage("启动/停止"),
    "action_tun": MessageLookupByLibrary.simpleMessage("虚拟网卡"),
    "action_view": MessageLookupByLibrary.simpleMessage("显示/隐藏"),
    "add": MessageLookupByLibrary.simpleMessage("添加"),
    "addRule": MessageLookupByLibrary.simpleMessage("添加规则"),
    "addedOriginRules": MessageLookupByLibrary.simpleMessage("附加到原始规则"),
    "address": MessageLookupByLibrary.simpleMessage("地址"),
    "addressHelp": MessageLookupByLibrary.simpleMessage("WebDAV服务器地址"),
    "addressTip": MessageLookupByLibrary.simpleMessage("请输入有效的WebDAV地址"),
    "adminAutoLaunch": MessageLookupByLibrary.simpleMessage("管理员自启动"),
    "adminAutoLaunchDesc": MessageLookupByLibrary.simpleMessage("使用管理员模式开机自启动"),
    "ago": MessageLookupByLibrary.simpleMessage("前"),
    "agree": MessageLookupByLibrary.simpleMessage("同意"),
    "allApps": MessageLookupByLibrary.simpleMessage("所有应用"),
    "allowBypass": MessageLookupByLibrary.simpleMessage("允许应用绕过VPN"),
    "allowBypassDesc": MessageLookupByLibrary.simpleMessage("开启后部分应用可绕过VPN"),
    "allowLan": MessageLookupByLibrary.simpleMessage("局域网代理"),
    "allowLanDesc": MessageLookupByLibrary.simpleMessage("允许通过局域网访问代理"),
    "announcement": MessageLookupByLibrary.simpleMessage("公告"),
    "app": MessageLookupByLibrary.simpleMessage("应用"),
    "appAccessControl": MessageLookupByLibrary.simpleMessage("应用访问控制"),
    "appBrandName": MessageLookupByLibrary.simpleMessage("自由云"),
    "appBrandTagline": MessageLookupByLibrary.simpleMessage("旗舰级智能网络加速客户端"),
    "appDesc": MessageLookupByLibrary.simpleMessage("处理应用相关设置"),
    "application": MessageLookupByLibrary.simpleMessage("应用程序设置"),
    "applicationDesc": MessageLookupByLibrary.simpleMessage("标准应用程序设置"),
    "auto": MessageLookupByLibrary.simpleMessage("自动"),
    "autoCheckUpdate": MessageLookupByLibrary.simpleMessage("自动检查更新"),
    "autoCheckUpdateDesc": MessageLookupByLibrary.simpleMessage("应用启动时自动检查更新"),
    "autoCloseConnections": MessageLookupByLibrary.simpleMessage("自动关闭连接"),
    "autoCloseConnectionsDesc": MessageLookupByLibrary.simpleMessage(
      "切换节点后自动关闭连接",
    ),
    "autoLaunch": MessageLookupByLibrary.simpleMessage("自启动"),
    "autoLaunchDesc": MessageLookupByLibrary.simpleMessage("跟随系统自启动"),
    "autoRun": MessageLookupByLibrary.simpleMessage("自动运行"),
    "autoRunDesc": MessageLookupByLibrary.simpleMessage("应用打开时自动运行"),
    "autoSetSystemDns": MessageLookupByLibrary.simpleMessage("自动设置系统DNS"),
    "autoStart": MessageLookupByLibrary.simpleMessage("自启动"),
    "autoStartDesc": MessageLookupByLibrary.simpleMessage(
      "允许后台自启动，使 VPN 在重启和更新后仍能恢复（MIUI/EMUI 等）",
    ),
    "autoUpdate": MessageLookupByLibrary.simpleMessage("自动更新"),
    "autoUpdateInterval": MessageLookupByLibrary.simpleMessage("自动更新间隔（分钟）"),
    "backup": MessageLookupByLibrary.simpleMessage("备份"),
    "backupAndRecovery": MessageLookupByLibrary.simpleMessage("备份与恢复"),
    "backupAndRecoveryDesc": MessageLookupByLibrary.simpleMessage(
      "通过WebDAV或者文件同步数据",
    ),
    "backupSuccess": MessageLookupByLibrary.simpleMessage("备份成功"),
    "basicConfig": MessageLookupByLibrary.simpleMessage("基本配置"),
    "basicConfigDesc": MessageLookupByLibrary.simpleMessage("全局修改基本配置"),
    "batteryOptimization": MessageLookupByLibrary.simpleMessage("电池优化"),
    "batteryOptimizationDesc": MessageLookupByLibrary.simpleMessage(
      "将应用加入白名单，避免系统在后台杀死 VPN",
    ),
    "bind": MessageLookupByLibrary.simpleMessage("绑定"),
    "blacklistMode": MessageLookupByLibrary.simpleMessage("黑名单模式"),
    "brandDialogSubtitle": MessageLookupByLibrary.simpleMessage("品牌介绍与核心体验"),
    "brandPillarModesBody": MessageLookupByLibrary.simpleMessage(
      "「小白模式」清爽直观、系统级 TUN 与代理无缝协同；展开「大佬模式」即可掌控分流、连接与诊断细节。",
    ),
    "brandPillarModesTitle": MessageLookupByLibrary.simpleMessage(
      "双模驾驭 · 即开即连",
    ),
    "brandPillarServiceBody": MessageLookupByLibrary.simpleMessage(
      "订阅流量、剩余比例与到期状态清晰可查，支持礼品卡核验兑换、多配置同步与专属客服协助。",
    ),
    "brandPillarServiceTitle": MessageLookupByLibrary.simpleMessage(
      "透明权益 · 安心续享",
    ),
    "brandPillarSmartBody": MessageLookupByLibrary.simpleMessage(
      "并发健康测速与直观色阶呈现，支持一键连最快、地区筛选与固定节点自由切换。",
    ),
    "brandPillarSmartTitle": MessageLookupByLibrary.simpleMessage(
      "智能选点 · 毫秒级感知",
    ),
    "brandShowcaseBadge": MessageLookupByLibrary.simpleMessage(
      "FREEDOMNET · 官方旗舰客户端",
    ),
    "brandShowcaseHeroBody": MessageLookupByLibrary.simpleMessage(
      "自由云（FreedomNet）专注打造纯粹、稳定、低延迟的全球智能网络加速体验。无论跨境办公、AI 生产力协作还是高清流媒体娱乐，一键即达理想连接。",
    ),
    "brandShowcaseHeroTitle": MessageLookupByLibrary.simpleMessage(
      "连接无界 · 疾速随行",
    ),
    "bypassDomain": MessageLookupByLibrary.simpleMessage("排除域名"),
    "bypassDomainDesc": MessageLookupByLibrary.simpleMessage("仅在系统代理启用时生效"),
    "cacheCorrupt": MessageLookupByLibrary.simpleMessage("缓存已损坏，是否清空？"),
    "cancel": MessageLookupByLibrary.simpleMessage("取消"),
    "cancelFilterSystemApp": MessageLookupByLibrary.simpleMessage("取消过滤系统应用"),
    "cancelSelectAll": MessageLookupByLibrary.simpleMessage("取消全选"),
    "change": MessageLookupByLibrary.simpleMessage("切换"),
    "changeServer": MessageLookupByLibrary.simpleMessage("切换服务器"),
    "checkError": MessageLookupByLibrary.simpleMessage("检测失败"),
    "checkUpdate": MessageLookupByLibrary.simpleMessage("检查更新"),
    "checkUpdateError": MessageLookupByLibrary.simpleMessage("当前应用已经是最新版了"),
    "checking": MessageLookupByLibrary.simpleMessage("检测中..."),
    "clearData": MessageLookupByLibrary.simpleMessage("清除数据"),
    "clearDataTip": MessageLookupByLibrary.simpleMessage(
      "这将删除所有应用数据并重新启动应用程序。您确定吗？",
    ),
    "clipboardExport": MessageLookupByLibrary.simpleMessage("导出剪贴板"),
    "clipboardImport": MessageLookupByLibrary.simpleMessage("剪贴板导入"),
    "color": MessageLookupByLibrary.simpleMessage("颜色"),
    "colorSchemes": MessageLookupByLibrary.simpleMessage("配色方案"),
    "columns": MessageLookupByLibrary.simpleMessage("列数"),
    "compatible": MessageLookupByLibrary.simpleMessage("兼容模式"),
    "compatibleDesc": MessageLookupByLibrary.simpleMessage(
      "开启将失去部分应用能力，获得全量的Clash的支持",
    ),
    "confirm": MessageLookupByLibrary.simpleMessage("确定"),
    "connections": MessageLookupByLibrary.simpleMessage("连接"),
    "connectionsActive": MessageLookupByLibrary.simpleMessage("活动"),
    "connectionsAllProcesses": MessageLookupByLibrary.simpleMessage("全部进程"),
    "connectionsAscending": MessageLookupByLibrary.simpleMessage("升序"),
    "connectionsClassicMode": MessageLookupByLibrary.simpleMessage("经典"),
    "connectionsClearClosed": MessageLookupByLibrary.simpleMessage("清空已关闭"),
    "connectionsCloseFiltered": MessageLookupByLibrary.simpleMessage(
      "关闭筛选出的活动连接",
    ),
    "connectionsClosed": MessageLookupByLibrary.simpleMessage("已关闭"),
    "connectionsDesc": MessageLookupByLibrary.simpleMessage("查看当前连接数据"),
    "connectionsDescending": MessageLookupByLibrary.simpleMessage("降序"),
    "connectionsDestination": MessageLookupByLibrary.simpleMessage("目标"),
    "connectionsDestinationGeo": MessageLookupByLibrary.simpleMessage(
      "目标 GeoIP",
    ),
    "connectionsDetail": MessageLookupByLibrary.simpleMessage("连接详情"),
    "connectionsDnsMode": MessageLookupByLibrary.simpleMessage("DNS 模式"),
    "connectionsDownloadSpeed": MessageLookupByLibrary.simpleMessage("下载速率"),
    "connectionsEstablished": MessageLookupByLibrary.simpleMessage("建立时间"),
    "connectionsFilterHint": MessageLookupByLibrary.simpleMessage(
      "筛选进程、主机、IP、代理或规则",
    ),
    "connectionsHost": MessageLookupByLibrary.simpleMessage("主机"),
    "connectionsInbound": MessageLookupByLibrary.simpleMessage("入站"),
    "connectionsInboundName": MessageLookupByLibrary.simpleMessage("入站名称"),
    "connectionsInboundUser": MessageLookupByLibrary.simpleMessage("入站用户"),
    "connectionsListView": MessageLookupByLibrary.simpleMessage("列表视图"),
    "connectionsLog": MessageLookupByLibrary.simpleMessage("日志"),
    "connectionsMemory": MessageLookupByLibrary.simpleMessage("内存"),
    "connectionsOther": MessageLookupByLibrary.simpleMessage("其他"),
    "connectionsPause": MessageLookupByLibrary.simpleMessage("暂停更新"),
    "connectionsPaused": MessageLookupByLibrary.simpleMessage("连接列表已暂停更新"),
    "connectionsProcess": MessageLookupByLibrary.simpleMessage("进程"),
    "connectionsProcessMode": MessageLookupByLibrary.simpleMessage("按进程"),
    "connectionsProcessPath": MessageLookupByLibrary.simpleMessage("进程路径"),
    "connectionsProxyChain": MessageLookupByLibrary.simpleMessage("代理链"),
    "connectionsRefreshInterval": MessageLookupByLibrary.simpleMessage("刷新间隔"),
    "connectionsRefreshIntervalDesc": MessageLookupByLibrary.simpleMessage(
      "100–10000 毫秒；数值越低 CPU 占用越高",
    ),
    "connectionsRemoteDestination": MessageLookupByLibrary.simpleMessage(
      "远程目标",
    ),
    "connectionsRequestLog": MessageLookupByLibrary.simpleMessage("请求记录"),
    "connectionsResetColumns": MessageLookupByLibrary.simpleMessage("重置列"),
    "connectionsResume": MessageLookupByLibrary.simpleMessage("继续更新"),
    "connectionsRouting": MessageLookupByLibrary.simpleMessage("路由"),
    "connectionsRule": MessageLookupByLibrary.simpleMessage("规则"),
    "connectionsRulePayload": MessageLookupByLibrary.simpleMessage("规则内容"),
    "connectionsSettings": MessageLookupByLibrary.simpleMessage("连接设置"),
    "connectionsShowIcons": MessageLookupByLibrary.simpleMessage("显示应用图标"),
    "connectionsSniffHost": MessageLookupByLibrary.simpleMessage("嗅探主机"),
    "connectionsSource": MessageLookupByLibrary.simpleMessage("来源"),
    "connectionsSourceGeo": MessageLookupByLibrary.simpleMessage("来源 GeoIP"),
    "connectionsTableColumns": MessageLookupByLibrary.simpleMessage("表格列"),
    "connectionsTableView": MessageLookupByLibrary.simpleMessage("表格视图"),
    "connectionsTotalDownload": MessageLookupByLibrary.simpleMessage("累计下载"),
    "connectionsTotalUpload": MessageLookupByLibrary.simpleMessage("累计上传"),
    "connectionsTraffic": MessageLookupByLibrary.simpleMessage("流量"),
    "connectionsType": MessageLookupByLibrary.simpleMessage("类型"),
    "connectionsUid": MessageLookupByLibrary.simpleMessage("UID"),
    "connectionsUploadSpeed": MessageLookupByLibrary.simpleMessage("上传速率"),
    "connectionsUseApplicationName": MessageLookupByLibrary.simpleMessage(
      "优先显示应用名称",
    ),
    "connectivity": MessageLookupByLibrary.simpleMessage("连通性："),
    "contactMe": MessageLookupByLibrary.simpleMessage("联系我"),
    "content": MessageLookupByLibrary.simpleMessage("内容"),
    "contentScheme": MessageLookupByLibrary.simpleMessage("内容主题"),
    "copy": MessageLookupByLibrary.simpleMessage("复制"),
    "copyEnvVar": MessageLookupByLibrary.simpleMessage("复制环境变量"),
    "copyLink": MessageLookupByLibrary.simpleMessage("复制链接"),
    "copySuccess": MessageLookupByLibrary.simpleMessage("复制成功"),
    "core": MessageLookupByLibrary.simpleMessage("内核"),
    "coreInfo": MessageLookupByLibrary.simpleMessage("内核信息"),
    "country": MessageLookupByLibrary.simpleMessage("区域"),
    "crashTest": MessageLookupByLibrary.simpleMessage("崩溃测试"),
    "crashlytics": MessageLookupByLibrary.simpleMessage("崩溃报告"),
    "crashlyticsDesc": MessageLookupByLibrary.simpleMessage(
      "通过 Firebase Crashlytics 自动上传崩溃日志，不包含敏感信息",
    ),
    "create": MessageLookupByLibrary.simpleMessage("创建"),
    "cut": MessageLookupByLibrary.simpleMessage("剪切"),
    "dark": MessageLookupByLibrary.simpleMessage("深色"),
    "dashboard": MessageLookupByLibrary.simpleMessage("仪表盘"),
    "dashboardAnnouncementBadge": MessageLookupByLibrary.simpleMessage("公告"),
    "dashboardClickUpdateSubscription": MessageLookupByLibrary.simpleMessage(
      "点击更新订阅",
    ),
    "dashboardContactSupport": MessageLookupByLibrary.simpleMessage("联系支持"),
    "dashboardCurrentNodeLabel": m0,
    "dashboardHwidNotSupported": MessageLookupByLibrary.simpleMessage(
      "当前服务端未启用硬件标识 (HWID) 绑定",
    ),
    "dashboardNotSyncedYet": MessageLookupByLibrary.simpleMessage("同步时间：尚未同步"),
    "dashboardRuleOverrideCount": m1,
    "dashboardTotalNodesCount": m2,
    "days": MessageLookupByLibrary.simpleMessage("天"),
    "defaultNameserver": MessageLookupByLibrary.simpleMessage("默认域名服务器"),
    "defaultNameserverDesc": MessageLookupByLibrary.simpleMessage("用于解析DNS服务器"),
    "defaultProxyAutoTarget": MessageLookupByLibrary.simpleMessage(
      "默认代理 (自动适配各配置)",
    ),
    "defaultSort": MessageLookupByLibrary.simpleMessage("按默认排序"),
    "defaultText": MessageLookupByLibrary.simpleMessage("默认"),
    "delay": MessageLookupByLibrary.simpleMessage("延迟"),
    "delaySort": MessageLookupByLibrary.simpleMessage("按延迟排序"),
    "delete": MessageLookupByLibrary.simpleMessage("删除"),
    "deleteMultipTip": m3,
    "deleteTip": m4,
    "desc": MessageLookupByLibrary.simpleMessage(
      "基于ClashMeta的多平台代理客户端，简单易用，开源无广告。",
    ),
    "detectionTip": MessageLookupByLibrary.simpleMessage("依赖第三方api，仅供参考"),
    "determiningIp": MessageLookupByLibrary.simpleMessage("正在获取 IP..."),
    "developerMode": MessageLookupByLibrary.simpleMessage("开发者模式"),
    "developerModeEnableTip": MessageLookupByLibrary.simpleMessage("开发者模式已启用。"),
    "direct": MessageLookupByLibrary.simpleMessage("直连"),
    "disclaimer": MessageLookupByLibrary.simpleMessage("免责声明"),
    "disclaimerDesc": MessageLookupByLibrary.simpleMessage(
      "本软件仅供学习交流、科研等非商业性质的用途，严禁将本软件用于商业目的。如有任何商业行为，均与本软件无关。",
    ),
    "discoverNewVersion": MessageLookupByLibrary.simpleMessage("发现新版本"),
    "discovery": MessageLookupByLibrary.simpleMessage("发现新版本"),
    "dnsDesc": MessageLookupByLibrary.simpleMessage("更新DNS相关设置"),
    "dnsMode": MessageLookupByLibrary.simpleMessage("DNS模式"),
    "doYouWantToPass": MessageLookupByLibrary.simpleMessage("添加配置文件从"),
    "domain": MessageLookupByLibrary.simpleMessage("域名"),
    "download": MessageLookupByLibrary.simpleMessage("下载"),
    "downloadingZashboard": MessageLookupByLibrary.simpleMessage(
      "正在下载 Zashboard…",
    ),
    "edit": MessageLookupByLibrary.simpleMessage("编辑"),
    "emptyTip": m5,
    "en": MessageLookupByLibrary.simpleMessage("英语"),
    "enableGlobalOverride": MessageLookupByLibrary.simpleMessage("启用全局规则覆写"),
    "enableOverride": MessageLookupByLibrary.simpleMessage("启用覆写"),
    "entries": MessageLookupByLibrary.simpleMessage("个条目"),
    "exclude": MessageLookupByLibrary.simpleMessage("从最近任务中隐藏"),
    "excludeDesc": MessageLookupByLibrary.simpleMessage("应用在后台时,从最近任务中隐藏应用"),
    "existsTip": m6,
    "exit": MessageLookupByLibrary.simpleMessage("退出"),
    "expand": MessageLookupByLibrary.simpleMessage("标准"),
    "expertMode": MessageLookupByLibrary.simpleMessage("大佬模式"),
    "expirationTime": MessageLookupByLibrary.simpleMessage("到期时间"),
    "expiresOn": MessageLookupByLibrary.simpleMessage("到期于"),
    "exportFile": MessageLookupByLibrary.simpleMessage("导出文件"),
    "exportLogs": MessageLookupByLibrary.simpleMessage("导出日志"),
    "exportSuccess": MessageLookupByLibrary.simpleMessage("导出成功"),
    "expressiveScheme": MessageLookupByLibrary.simpleMessage("表现力"),
    "externalController": MessageLookupByLibrary.simpleMessage("外部控制器"),
    "externalControllerDesc": MessageLookupByLibrary.simpleMessage(
      "开启后将可以通过9090端口控制Clash内核",
    ),
    "externalLink": MessageLookupByLibrary.simpleMessage("外部链接"),
    "externalResources": MessageLookupByLibrary.simpleMessage("外部资源"),
    "fakeipFilter": MessageLookupByLibrary.simpleMessage("Fakeip过滤"),
    "fakeipRange": MessageLookupByLibrary.simpleMessage("Fakeip范围"),
    "fallback": MessageLookupByLibrary.simpleMessage("Fallback"),
    "fallbackDesc": MessageLookupByLibrary.simpleMessage("一般情况下使用境外DNS"),
    "fallbackFilter": MessageLookupByLibrary.simpleMessage("Fallback过滤"),
    "fidelityScheme": MessageLookupByLibrary.simpleMessage("高保真"),
    "file": MessageLookupByLibrary.simpleMessage("文件"),
    "fileDesc": MessageLookupByLibrary.simpleMessage("直接上传配置文件"),
    "fileIsUpdate": MessageLookupByLibrary.simpleMessage("文件有修改，是否保存修改"),
    "fileTooLarge": MessageLookupByLibrary.simpleMessage("文件过大"),
    "filterSystemApp": MessageLookupByLibrary.simpleMessage("过滤系统应用"),
    "findProcessMode": MessageLookupByLibrary.simpleMessage("查找进程"),
    "findProcessModeDesc": MessageLookupByLibrary.simpleMessage("开启后会有一定性能损耗"),
    "fontFamily": MessageLookupByLibrary.simpleMessage("字体"),
    "fourColumns": MessageLookupByLibrary.simpleMessage("四列"),
    "fruitSaladScheme": MessageLookupByLibrary.simpleMessage("果缤纷"),
    "general": MessageLookupByLibrary.simpleMessage("常规"),
    "generalDesc": MessageLookupByLibrary.simpleMessage("修改通用设置"),
    "geoData": MessageLookupByLibrary.simpleMessage("地理数据"),
    "geodataLoader": MessageLookupByLibrary.simpleMessage("Geo低内存模式"),
    "geodataLoaderDesc": MessageLookupByLibrary.simpleMessage("开启将使用Geo低内存加载器"),
    "geoipCode": MessageLookupByLibrary.simpleMessage("Geoip代码"),
    "getOriginRules": MessageLookupByLibrary.simpleMessage("获取原始规则"),
    "global": MessageLookupByLibrary.simpleMessage("全局"),
    "globalOverride": MessageLookupByLibrary.simpleMessage("全局规则覆写"),
    "globalOverrideDesc": MessageLookupByLibrary.simpleMessage(
      "跨订阅配置持久生效，切换或更新订阅无需重复编辑",
    ),
    "go": MessageLookupByLibrary.simpleMessage("前往"),
    "goDownload": MessageLookupByLibrary.simpleMessage("前往下载"),
    "goToPurchasePrompt": MessageLookupByLibrary.simpleMessage(
      "还没有订阅？去购买 / 兑换",
    ),
    "gratitude": MessageLookupByLibrary.simpleMessage("感激"),
    "hasCacheChange": MessageLookupByLibrary.simpleMessage("是否缓存修改"),
    "healthActionOpenDns": MessageLookupByLibrary.simpleMessage("打开 DNS 设置"),
    "healthActionOpenNetwork": MessageLookupByLibrary.simpleMessage("打开网络设置"),
    "healthActionOpenProfiles": MessageLookupByLibrary.simpleMessage("前往配置页"),
    "healthActionOpenProxies": MessageLookupByLibrary.simpleMessage("切换代理节点"),
    "healthActionOpenPurchase": MessageLookupByLibrary.simpleMessage("前往兑换续费"),
    "healthActionOpenTun": MessageLookupByLibrary.simpleMessage("打开 TUN 设置"),
    "healthActionReapplySystemProxy": MessageLookupByLibrary.simpleMessage(
      "一键恢复系统代理",
    ),
    "healthActionRestartCore": MessageLookupByLibrary.simpleMessage("重启核心"),
    "healthActionStartProxy": MessageLookupByLibrary.simpleMessage("启动代理"),
    "healthCheckCancel": MessageLookupByLibrary.simpleMessage("取消检查"),
    "healthCheckChecking": MessageLookupByLibrary.simpleMessage("正在检查…"),
    "healthCheckCopied": MessageLookupByLibrary.simpleMessage("诊断摘要已复制到剪贴板"),
    "healthCheckCopySummary": MessageLookupByLibrary.simpleMessage("复制摘要"),
    "healthCheckDiagnoseAction": MessageLookupByLibrary.simpleMessage("诊断"),
    "healthCheckExport": MessageLookupByLibrary.simpleMessage("导出脱敏报告"),
    "healthCheckExportDialogTitle": MessageLookupByLibrary.simpleMessage(
      "导出脱敏诊断报告",
    ),
    "healthCheckExportFailed": MessageLookupByLibrary.simpleMessage("诊断报告导出失败"),
    "healthCheckExportSuccess": MessageLookupByLibrary.simpleMessage(
      "脱敏诊断报告已导出",
    ),
    "healthCheckLastChecked": m7,
    "healthCheckPrivacyNote": MessageLookupByLibrary.simpleMessage(
      "导出文件仅含状态枚举与耗时，不含节点名、IP、订阅地址或日志。",
    ),
    "healthCheckRecheck": MessageLookupByLibrary.simpleMessage("重新检查"),
    "healthCheckSubtitle": MessageLookupByLibrary.simpleMessage(
      "检测配置、代理核心、流量接管与真实网络连通性",
    ),
    "healthCheckTitle": MessageLookupByLibrary.simpleMessage("健康检查"),
    "healthDetailCancelled": MessageLookupByLibrary.simpleMessage("已取消"),
    "healthDetailCoreDelayBusy": MessageLookupByLibrary.simpleMessage(
      "批量测速繁忙，请稍后重新检查",
    ),
    "healthDetailCoreFailed": MessageLookupByLibrary.simpleMessage(
      "无法读取核心状态或控制接口超时",
    ),
    "healthDetailCoreHealthy": m8,
    "healthDetailCoreSlow": MessageLookupByLibrary.simpleMessage(
      "核心响应偏慢（> 500 ms）",
    ),
    "healthDetailDirectFailed": MessageLookupByLibrary.simpleMessage(
      "本机直连探测失败，请检查网卡、路由器或防火墙",
    ),
    "healthDetailDirectMode": MessageLookupByLibrary.simpleMessage(
      "当前处于直连模式 (Direct)",
    ),
    "healthDetailDirectOk": MessageLookupByLibrary.simpleMessage("物理外网可达"),
    "healthDetailDirectSlow": MessageLookupByLibrary.simpleMessage(
      "本机直连外网延迟偏高",
    ),
    "healthDetailDnsFailed": MessageLookupByLibrary.simpleMessage("域名解析失败或超时"),
    "healthDetailDnsFakeIp": MessageLookupByLibrary.simpleMessage(
      "Core DNS 接管 (fake-ip)",
    ),
    "healthDetailDnsOk": MessageLookupByLibrary.simpleMessage("域名解析正常"),
    "healthDetailDnsPoisoned": MessageLookupByLibrary.simpleMessage(
      "解析返回黑洞/回环地址，疑似 DNS 污染",
    ),
    "healthDetailDnsStaleFakeIp": MessageLookupByLibrary.simpleMessage(
      "检测到残留 Fake-IP 缓存，可能导致直连断网",
    ),
    "healthDetailE2eBypassed": MessageLookupByLibrary.simpleMessage(
      "出口探测成功，但核心连接表中未见该请求",
    ),
    "healthDetailE2eDirectRule": MessageLookupByLibrary.simpleMessage(
      "已进入核心（探测域名命中直连规则）",
    ),
    "healthDetailE2eFailed": MessageLookupByLibrary.simpleMessage(
      "真实路径出口请求全部超时或失败",
    ),
    "healthDetailE2eVerified": m9,
    "healthDetailLocalProfile": MessageLookupByLibrary.simpleMessage(
      "本地配置（无远程套餐额度信息）",
    ),
    "healthDetailNoProfile": MessageLookupByLibrary.simpleMessage("尚未选择任何订阅配置"),
    "healthDetailOutboundDirectSelected": MessageLookupByLibrary.simpleMessage(
      "策略组当前选中的是 DIRECT，不会经过代理节点",
    ),
    "healthDetailOutboundFailed": m10,
    "healthDetailOutboundProbeFallbackOk": m11,
    "healthDetailOutboundRejectSelected": MessageLookupByLibrary.simpleMessage(
      "策略组当前选中的是 REJECT，连接被阻断",
    ),
    "healthDetailOutboundSlow": m12,
    "healthDetailProfileFileMissing": MessageLookupByLibrary.simpleMessage(
      "本地配置文件缺失或为空，请重新更新订阅",
    ),
    "healthDetailProxyRunning": MessageLookupByLibrary.simpleMessage("运行中"),
    "healthDetailProxyStopped": MessageLookupByLibrary.simpleMessage("未启动"),
    "healthDetailRuntimeMismatch": MessageLookupByLibrary.simpleMessage(
      "当前配置尚未应用到运行核心",
    ),
    "healthDetailRuntimeSynced": m13,
    "healthDetailSkipPrerequisite": MessageLookupByLibrary.simpleMessage(
      "因前置检查未通过而跳过",
    ),
    "healthDetailSkipProxyStopped": MessageLookupByLibrary.simpleMessage(
      "代理未启动，跳过此项",
    ),
    "healthDetailSubDeviceLimit": MessageLookupByLibrary.simpleMessage(
      "设备数量已达订阅上限",
    ),
    "healthDetailSubExhausted": MessageLookupByLibrary.simpleMessage("套餐流量已耗尽"),
    "healthDetailSubExpired": MessageLookupByLibrary.simpleMessage("订阅已到期"),
    "healthDetailSubExpiringSoon": m14,
    "healthDetailSubHealthy": MessageLookupByLibrary.simpleMessage("订阅有效"),
    "healthDetailSubHealthyEternal": MessageLookupByLibrary.simpleMessage(
      "长期有效 · 不限流量",
    ),
    "healthDetailSubNeverSynced": MessageLookupByLibrary.simpleMessage(
      "订阅尚未同步，建议先更新订阅",
    ),
    "healthDetailSubNoMeta": MessageLookupByLibrary.simpleMessage(
      "服务端未返回到期与流量信息",
    ),
    "healthDetailSubTrafficLow": m15,
    "healthDetailSysProxyDisabled": MessageLookupByLibrary.simpleMessage(
      "未开启（按设置跳过）",
    ),
    "healthDetailSysProxyDisabledExternally":
        MessageLookupByLibrary.simpleMessage("系统代理开关处于关闭状态"),
    "healthDetailSysProxyHijacked": MessageLookupByLibrary.simpleMessage(
      "系统代理已被其他软件关闭或改写",
    ),
    "healthDetailSysProxyInvalidPort": MessageLookupByLibrary.simpleMessage(
      "本地混合端口未启用 (mixed-port = 0)",
    ),
    "healthDetailSysProxyNotApplied": MessageLookupByLibrary.simpleMessage(
      "系统代理尚未写入本机设置",
    ),
    "healthDetailSysProxyReadFailed": MessageLookupByLibrary.simpleMessage(
      "无法读取系统代理设置",
    ),
    "healthDetailSysProxyUnexpectedPac": MessageLookupByLibrary.simpleMessage(
      "检测到残留 PAC 地址，可能抢占系统代理",
    ),
    "healthDetailSysProxyUnsupported": MessageLookupByLibrary.simpleMessage(
      "当前平台不适用注册表校验",
    ),
    "healthDetailTakeoverBoth": MessageLookupByLibrary.simpleMessage(
      "TUN 虚拟网卡 + 系统代理双接管",
    ),
    "healthDetailTakeoverNone": MessageLookupByLibrary.simpleMessage(
      "TUN 与系统代理均未生效，应用流量未受接管",
    ),
    "healthDetailTakeoverPartial": MessageLookupByLibrary.simpleMessage(
      "仅单一通道生效，另一已开启接管项异常",
    ),
    "healthDetailTakeoverSysProxy": MessageLookupByLibrary.simpleMessage(
      "系统代理接管",
    ),
    "healthDetailTakeoverTun": MessageLookupByLibrary.simpleMessage(
      "TUN 全局虚拟网卡接管",
    ),
    "healthDetailTunBypassedSystemProxyOk":
        MessageLookupByLibrary.simpleMessage("TUN 通道未接管流量，系统代理通道正常"),
    "healthDetailTunDisabled": MessageLookupByLibrary.simpleMessage(
      "未开启（按设置跳过）",
    ),
    "healthDetailTunReady": MessageLookupByLibrary.simpleMessage("虚拟网卡已就绪"),
    "healthDetailTunReadyElevated": MessageLookupByLibrary.simpleMessage(
      "已就绪 · 管理员权限",
    ),
    "healthExitCountryPart": m16,
    "healthItemCoreResponsive": MessageLookupByLibrary.simpleMessage("Core 响应"),
    "healthItemDirect": MessageLookupByLibrary.simpleMessage("本机直连外网"),
    "healthItemDns": MessageLookupByLibrary.simpleMessage("DNS 解析"),
    "healthItemEndToEnd": MessageLookupByLibrary.simpleMessage("端到端实测"),
    "healthItemOutbound": MessageLookupByLibrary.simpleMessage("当前节点出站"),
    "healthItemProfileSelected": MessageLookupByLibrary.simpleMessage("当前配置"),
    "healthItemProxyStarted": MessageLookupByLibrary.simpleMessage("代理开关状态"),
    "healthItemRuntimeConfig": MessageLookupByLibrary.simpleMessage("运行配置生效"),
    "healthItemSubscription": MessageLookupByLibrary.simpleMessage("订阅状态"),
    "healthItemSystemProxy": MessageLookupByLibrary.simpleMessage("系统代理"),
    "healthItemTrafficTakeover": MessageLookupByLibrary.simpleMessage("接管结论"),
    "healthItemTunTakeover": MessageLookupByLibrary.simpleMessage("TUN 虚拟网卡"),
    "healthLayerConfig": MessageLookupByLibrary.simpleMessage("配置与订阅"),
    "healthLayerCore": MessageLookupByLibrary.simpleMessage("代理核心"),
    "healthLayerNetwork": MessageLookupByLibrary.simpleMessage("网络链路"),
    "healthLayerTakeover": MessageLookupByLibrary.simpleMessage("流量接管"),
    "healthStatusFailed": MessageLookupByLibrary.simpleMessage("失败"),
    "healthStatusPassed": MessageLookupByLibrary.simpleMessage("通过"),
    "healthStatusRunning": MessageLookupByLibrary.simpleMessage("检查中"),
    "healthStatusSkipped": MessageLookupByLibrary.simpleMessage("跳过"),
    "healthStatusTimeout": MessageLookupByLibrary.simpleMessage("超时"),
    "healthStatusWarning": MessageLookupByLibrary.simpleMessage("警告"),
    "healthVerdictCancelledTitle": MessageLookupByLibrary.simpleMessage(
      "健康检查已取消",
    ),
    "healthVerdictCheckingTitle": MessageLookupByLibrary.simpleMessage(
      "正在逐层检测连接链路…",
    ),
    "healthVerdictCoreUnresponsive": MessageLookupByLibrary.simpleMessage(
      "代理核心无响应，控制通道异常",
    ),
    "healthVerdictDnsFailed": MessageLookupByLibrary.simpleMessage(
      "DNS 域名解析异常或遭到污染",
    ),
    "healthVerdictEndToEndFailed": MessageLookupByLibrary.simpleMessage(
      "端到端出口探测失败，请切换节点或检查规则",
    ),
    "healthVerdictHealthyDirectSubtitle": m17,
    "healthVerdictHealthySubtitle": m18,
    "healthVerdictHealthyTitle": MessageLookupByLibrary.simpleMessage("连接正常"),
    "healthVerdictLocalNetworkDown": MessageLookupByLibrary.simpleMessage(
      "本机物理网络不可用，与代理节点无关",
    ),
    "healthVerdictOutboundFailed": MessageLookupByLibrary.simpleMessage(
      "本机网络正常，但当前节点无法连通外网",
    ),
    "healthVerdictProfileMissing": MessageLookupByLibrary.simpleMessage(
      "未选择可用配置或本地配置文件缺失",
    ),
    "healthVerdictProxyNotStarted": MessageLookupByLibrary.simpleMessage(
      "代理尚未启动，应用流量当前直连",
    ),
    "healthVerdictSubscriptionExhausted": MessageLookupByLibrary.simpleMessage(
      "订阅流量已用尽，请续费或更换配置",
    ),
    "healthVerdictSubscriptionExpired": MessageLookupByLibrary.simpleMessage(
      "订阅已过期，节点将无法连接",
    ),
    "healthVerdictTakeoverFailed": MessageLookupByLibrary.simpleMessage(
      "应用流量未被接管，请开启 TUN 或修复系统代理",
    ),
    "healthVerdictTrafficBypassed": MessageLookupByLibrary.simpleMessage(
      "外网可达，但探测连接未经过代理核心（流量绕过）",
    ),
    "healthVerdictTunBypassedTitle": MessageLookupByLibrary.simpleMessage(
      "TUN 虚拟网卡未接管流量，当前仅系统代理可用",
    ),
    "healthVerdictWarningsTitle": MessageLookupByLibrary.simpleMessage(
      "连接可用，但存在需关注的告警项",
    ),
    "hostsDesc": MessageLookupByLibrary.simpleMessage("追加Hosts"),
    "hotkeyConflict": MessageLookupByLibrary.simpleMessage("快捷键冲突"),
    "hotkeyManagement": MessageLookupByLibrary.simpleMessage("快捷键管理"),
    "hotkeyManagementDesc": MessageLookupByLibrary.simpleMessage("使用键盘控制应用程序"),
    "hours": MessageLookupByLibrary.simpleMessage("小时"),
    "icon": MessageLookupByLibrary.simpleMessage("图片"),
    "iconConfiguration": MessageLookupByLibrary.simpleMessage("图片配置"),
    "iconStyle": MessageLookupByLibrary.simpleMessage("图标样式"),
    "import": MessageLookupByLibrary.simpleMessage("导入"),
    "importFile": MessageLookupByLibrary.simpleMessage("通过文件导入"),
    "importFromURL": MessageLookupByLibrary.simpleMessage("粘贴订阅链接，点击确定即可"),
    "importUrl": MessageLookupByLibrary.simpleMessage("通过URL导入"),
    "infiniteTime": MessageLookupByLibrary.simpleMessage("长期有效"),
    "init": MessageLookupByLibrary.simpleMessage("初始化"),
    "inputCorrectHotkey": MessageLookupByLibrary.simpleMessage("请输入正确的快捷键"),
    "intelligentSelected": MessageLookupByLibrary.simpleMessage("智能选择"),
    "internet": MessageLookupByLibrary.simpleMessage("互联网"),
    "interval": MessageLookupByLibrary.simpleMessage("间隔"),
    "intranetIP": MessageLookupByLibrary.simpleMessage("内网 IP"),
    "ipcidr": MessageLookupByLibrary.simpleMessage("IP/掩码"),
    "ipv6Desc": MessageLookupByLibrary.simpleMessage("开启后将可以接收IPv6流量"),
    "ipv6InboundDesc": MessageLookupByLibrary.simpleMessage("允许IPv6入站"),
    "ja": MessageLookupByLibrary.simpleMessage("日语"),
    "just": MessageLookupByLibrary.simpleMessage("刚刚"),
    "keepAliveIntervalDesc": MessageLookupByLibrary.simpleMessage("TCP保持活动间隔"),
    "key": MessageLookupByLibrary.simpleMessage("键"),
    "language": MessageLookupByLibrary.simpleMessage("语言"),
    "layout": MessageLookupByLibrary.simpleMessage("布局"),
    "light": MessageLookupByLibrary.simpleMessage("浅色"),
    "list": MessageLookupByLibrary.simpleMessage("列表"),
    "listen": MessageLookupByLibrary.simpleMessage("监听"),
    "local": MessageLookupByLibrary.simpleMessage("本地"),
    "localBackupDesc": MessageLookupByLibrary.simpleMessage("备份数据到本地"),
    "localRecoveryDesc": MessageLookupByLibrary.simpleMessage("通过文件恢复数据"),
    "localSplitMode": MessageLookupByLibrary.simpleMessage("国内与局域网智能分流"),
    "localSplitModeDesc": MessageLookupByLibrary.simpleMessage(
      "当订阅未下发分流规则（裸配置）时自动补充国内直连与局域网绕过",
    ),
    "localSplitMode_always": MessageLookupByLibrary.simpleMessage("始终补充国内直连"),
    "localSplitMode_auto": MessageLookupByLibrary.simpleMessage("智能识别裸配置 (自动)"),
    "localSplitMode_off": MessageLookupByLibrary.simpleMessage("关闭"),
    "locations": MessageLookupByLibrary.simpleMessage("节点"),
    "logLevel": MessageLookupByLibrary.simpleMessage("日志等级"),
    "logcat": MessageLookupByLibrary.simpleMessage("日志捕获"),
    "logcatDesc": MessageLookupByLibrary.simpleMessage("禁用将会隐藏日志入口"),
    "logs": MessageLookupByLibrary.simpleMessage("日志"),
    "logsDesc": MessageLookupByLibrary.simpleMessage("日志捕获记录"),
    "logsTest": MessageLookupByLibrary.simpleMessage("日志测试"),
    "loopback": MessageLookupByLibrary.simpleMessage("回环解锁工具"),
    "loopbackDesc": MessageLookupByLibrary.simpleMessage("用于UWP回环解锁"),
    "loose": MessageLookupByLibrary.simpleMessage("宽松"),
    "managedByProvider": MessageLookupByLibrary.simpleMessage("这些设置由您的提供商管理"),
    "managedByProviderNetwork": MessageLookupByLibrary.simpleMessage(
      "这些参数由您的提供商管理",
    ),
    "memoryInfo": MessageLookupByLibrary.simpleMessage("内存信息"),
    "messageTest": MessageLookupByLibrary.simpleMessage("消息测试"),
    "messageTestTip": MessageLookupByLibrary.simpleMessage("这是一条消息。"),
    "min": MessageLookupByLibrary.simpleMessage("最小"),
    "minimizeOnExit": MessageLookupByLibrary.simpleMessage("退出时最小化"),
    "minimizeOnExitDesc": MessageLookupByLibrary.simpleMessage("修改系统默认退出事件"),
    "minutes": MessageLookupByLibrary.simpleMessage("分钟"),
    "mixedPort": MessageLookupByLibrary.simpleMessage("混合端口"),
    "mode": MessageLookupByLibrary.simpleMessage("模式"),
    "monochromeScheme": MessageLookupByLibrary.simpleMessage("单色"),
    "months": MessageLookupByLibrary.simpleMessage("月"),
    "more": MessageLookupByLibrary.simpleMessage("更多"),
    "name": MessageLookupByLibrary.simpleMessage("名称"),
    "nameSort": MessageLookupByLibrary.simpleMessage("按名称排序"),
    "nameserver": MessageLookupByLibrary.simpleMessage("域名服务器"),
    "nameserverDesc": MessageLookupByLibrary.simpleMessage("用于解析域名"),
    "nameserverPolicy": MessageLookupByLibrary.simpleMessage("域名服务器策略"),
    "nameserverPolicyDesc": MessageLookupByLibrary.simpleMessage("指定对应域名服务器策略"),
    "network": MessageLookupByLibrary.simpleMessage("网络"),
    "networkDesc": MessageLookupByLibrary.simpleMessage("修改网络相关设置"),
    "networkDetection": MessageLookupByLibrary.simpleMessage("您的IP地址"),
    "networkSpeed": MessageLookupByLibrary.simpleMessage("网络速度"),
    "neutralScheme": MessageLookupByLibrary.simpleMessage("中性"),
    "noData": MessageLookupByLibrary.simpleMessage("暂无数据"),
    "noHotKey": MessageLookupByLibrary.simpleMessage("暂无快捷键"),
    "noIcon": MessageLookupByLibrary.simpleMessage("无图标"),
    "noInfo": MessageLookupByLibrary.simpleMessage("暂无信息"),
    "noMoreInfoDesc": MessageLookupByLibrary.simpleMessage("暂无更多信息"),
    "noNetwork": MessageLookupByLibrary.simpleMessage("无网络"),
    "noNetworkApp": MessageLookupByLibrary.simpleMessage("无网络应用"),
    "noProxy": MessageLookupByLibrary.simpleMessage("暂无代理"),
    "noProxyDesc": MessageLookupByLibrary.simpleMessage("请创建配置文件或者添加有效配置文件"),
    "noResolve": MessageLookupByLibrary.simpleMessage("不解析IP"),
    "nodeOverviewActive": MessageLookupByLibrary.simpleMessage("活动配置"),
    "nodeOverviewAddSubscription": MessageLookupByLibrary.simpleMessage("添加订阅"),
    "nodeOverviewAllHealthCounts": m19,
    "nodeOverviewAllProfiles": MessageLookupByLibrary.simpleMessage("全部配置"),
    "nodeOverviewAllProfilesCount": m20,
    "nodeOverviewAmbiguousNode": MessageLookupByLibrary.simpleMessage(
      "节点定义重复，无法确认归属",
    ),
    "nodeOverviewAnnouncement": m21,
    "nodeOverviewAutoConnectedBest": m22,
    "nodeOverviewAutoConnectedSmartBest": m23,
    "nodeOverviewAutoSelectedAllFailedWarning": m24,
    "nodeOverviewAutoSelectedExpiredWarning": m25,
    "nodeOverviewAutoSelectedTrafficExhaustedWarning": m26,
    "nodeOverviewAutoUpdateHours": m27,
    "nodeOverviewAutoUpdateMinutes": m28,
    "nodeOverviewAvailableFilterEmpty": MessageLookupByLibrary.simpleMessage(
      "当前没有测速可用的节点（可能尚未测速或节点全部超时）",
    ),
    "nodeOverviewAvailableOnly": MessageLookupByLibrary.simpleMessage("仅显示可用"),
    "nodeOverviewBandFailed": m29,
    "nodeOverviewBandFast": m30,
    "nodeOverviewBandSlow": m31,
    "nodeOverviewBandUntested": m32,
    "nodeOverviewBatchSummary": m33,
    "nodeOverviewChainUnsupported": MessageLookupByLibrary.simpleMessage(
      "代理链暂不支持隔离测速",
    ),
    "nodeOverviewCurrentActiveProfile": m34,
    "nodeOverviewCurrentProfile": MessageLookupByLibrary.simpleMessage("当前配置"),
    "nodeOverviewDeviceLimitReached": MessageLookupByLibrary.simpleMessage(
      "已达设备数量上限",
    ),
    "nodeOverviewEmptySubtitle": MessageLookupByLibrary.simpleMessage(
      "粘贴订阅链接并点击确定，软件将自动测速并连接最快节点",
    ),
    "nodeOverviewEmptyTitle": MessageLookupByLibrary.simpleMessage("还没有添加订阅配置"),
    "nodeOverviewExpireAt": m35,
    "nodeOverviewExpireDaysLeft": m36,
    "nodeOverviewExpireHoursLeft": m37,
    "nodeOverviewExpireSoon": MessageLookupByLibrary.simpleMessage("不足 1 小时"),
    "nodeOverviewExpired": MessageLookupByLibrary.simpleMessage("订阅已过期"),
    "nodeOverviewExpiredCountBadge": m38,
    "nodeOverviewExpiringSoonCountBadge": m39,
    "nodeOverviewFileMissing": MessageLookupByLibrary.simpleMessage("配置文件缺失"),
    "nodeOverviewFileSource": m40,
    "nodeOverviewGlobalMedian": m41,
    "nodeOverviewGlobalMedianAndBest": m42,
    "nodeOverviewHealthCapacityExceeded": MessageLookupByLibrary.simpleMessage(
      "历史容量已满，部分结果未保存",
    ),
    "nodeOverviewHealthCounts": m43,
    "nodeOverviewHealthStoreUnavailable": MessageLookupByLibrary.simpleMessage(
      "部分延迟测试结果未能保存",
    ),
    "nodeOverviewHistoryNotice": MessageLookupByLibrary.simpleMessage(
      "延迟结果保留至下次有效测试，测试时间见节点下方。",
    ),
    "nodeOverviewInUse": MessageLookupByLibrary.simpleMessage("使用中"),
    "nodeOverviewIndependentTest": MessageLookupByLibrary.simpleMessage(
      "独立延迟测试",
    ),
    "nodeOverviewLastActiveTest": m44,
    "nodeOverviewLastSync": m45,
    "nodeOverviewLastTest": m46,
    "nodeOverviewLive": MessageLookupByLibrary.simpleMessage("实时"),
    "nodeOverviewLocalProfile": MessageLookupByLibrary.simpleMessage("本地配置"),
    "nodeOverviewLockedManualNode": m47,
    "nodeOverviewManageProfiles": MessageLookupByLibrary.simpleMessage(
      "管理配置 / 更新订阅",
    ),
    "nodeOverviewManualSelectSubtitle": MessageLookupByLibrary.simpleMessage(
      "固定IP",
    ),
    "nodeOverviewManualSelectTitle": MessageLookupByLibrary.simpleMessage(
      "手动选择节点",
    ),
    "nodeOverviewManualUpdate": MessageLookupByLibrary.simpleMessage("手动更新"),
    "nodeOverviewMedian": m48,
    "nodeOverviewMoreIssues": m49,
    "nodeOverviewNeverExpires": MessageLookupByLibrary.simpleMessage(
      "到期时间：长期有效",
    ),
    "nodeOverviewNoActiveProfile": MessageLookupByLibrary.simpleMessage(
      "当前活动：未选择",
    ),
    "nodeOverviewNoNodes": MessageLookupByLibrary.simpleMessage("没有符合条件的节点"),
    "nodeOverviewNodeUnidentified": MessageLookupByLibrary.simpleMessage(
      "无法识别此节点",
    ),
    "nodeOverviewParseFailed": MessageLookupByLibrary.simpleMessage("配置解析失败"),
    "nodeOverviewPartialSummary": MessageLookupByLibrary.simpleMessage(
      "摘要仅统计已加载的节点",
    ),
    "nodeOverviewPickerAvailableNodes": m50,
    "nodeOverviewPickerExpireDate": m51,
    "nodeOverviewPickerPerpetual": MessageLookupByLibrary.simpleMessage("长期有效"),
    "nodeOverviewPreviewUnsupported": MessageLookupByLibrary.simpleMessage(
      "本预览暂不支持订阅源缓存节点",
    ),
    "nodeOverviewProfileCountBadge": m52,
    "nodeOverviewProgress": m53,
    "nodeOverviewProviderDownloadFailed": MessageLookupByLibrary.simpleMessage(
      "订阅源下载失败",
    ),
    "nodeOverviewProviderNotCached": MessageLookupByLibrary.simpleMessage(
      "订阅源本地缓存不可用",
    ),
    "nodeOverviewProviderOptionsUnsupported":
        MessageLookupByLibrary.simpleMessage("此类订阅源选项暂不支持"),
    "nodeOverviewProviderPending": m54,
    "nodeOverviewProviderTooLarge": MessageLookupByLibrary.simpleMessage(
      "订阅源超出大小或节点数量限制",
    ),
    "nodeOverviewProviderUnloaded": MessageLookupByLibrary.simpleMessage(
      "订阅源节点尚未加载；测试全部节点延迟时会读取，缺失缓存会获取。",
    ),
    "nodeOverviewProviderUnsafePath": MessageLookupByLibrary.simpleMessage(
      "订阅源文件不在授权目录内",
    ),
    "nodeOverviewProviderUnsafeUrl": MessageLookupByLibrary.simpleMessage(
      "订阅源地址不符合安全要求",
    ),
    "nodeOverviewProxyConnected": MessageLookupByLibrary.simpleMessage(
      "代理已开启 · 网络流量已接管",
    ),
    "nodeOverviewProxyConnectedSmart": m55,
    "nodeOverviewProxyConnectedSmartWithNode": m56,
    "nodeOverviewProxyConnectedWithNode": m57,
    "nodeOverviewProxyDisconnected": MessageLookupByLibrary.simpleMessage(
      "代理未开启 · 点击右侧按钮或任一节点「使用」即可上网",
    ),
    "nodeOverviewProxyStarting": MessageLookupByLibrary.simpleMessage(
      "正在开启代理…",
    ),
    "nodeOverviewProxyStopping": MessageLookupByLibrary.simpleMessage(
      "正在关闭代理…",
    ),
    "nodeOverviewQuickUse": MessageLookupByLibrary.simpleMessage("一键连最快"),
    "nodeOverviewRemainingTraffic": m58,
    "nodeOverviewRuntimeSource": MessageLookupByLibrary.simpleMessage("运行时节点"),
    "nodeOverviewSelectProfileTitle": MessageLookupByLibrary.simpleMessage(
      "切换配置",
    ),
    "nodeOverviewShowAllNodes": MessageLookupByLibrary.simpleMessage("显示全部节点"),
    "nodeOverviewSmartInUse": MessageLookupByLibrary.simpleMessage("智能使用中"),
    "nodeOverviewSmartSelectSubtitle": MessageLookupByLibrary.simpleMessage(
      "体验更好",
    ),
    "nodeOverviewSmartSelectTitle": MessageLookupByLibrary.simpleMessage(
      "智能选择节点",
    ),
    "nodeOverviewStale": MessageLookupByLibrary.simpleMessage("可能过时"),
    "nodeOverviewStatusExpired": MessageLookupByLibrary.simpleMessage("已过期"),
    "nodeOverviewStrictUnsupported": MessageLookupByLibrary.simpleMessage(
      "严格模式下不可使用隔离测速",
    ),
    "nodeOverviewSwitchedToNode": m59,
    "nodeOverviewSwitchedToSmart": m60,
    "nodeOverviewSwitchedToSmartWithNode": m61,
    "nodeOverviewTestAll": MessageLookupByLibrary.simpleMessage("测试全部节点延迟"),
    "nodeOverviewTestCurrent": MessageLookupByLibrary.simpleMessage("测试当前配置"),
    "nodeOverviewTestFailed": MessageLookupByLibrary.simpleMessage("测试失败"),
    "nodeOverviewTestInterrupted": MessageLookupByLibrary.simpleMessage(
      "测速已中断，已保留此前的测量结果",
    ),
    "nodeOverviewTestNode": MessageLookupByLibrary.simpleMessage("延迟测试"),
    "nodeOverviewTestTimedOut": MessageLookupByLibrary.simpleMessage(
      "测速或订阅源读取超时",
    ),
    "nodeOverviewTestUnavailable": MessageLookupByLibrary.simpleMessage(
      "未能启动测速，请检查后台组件版本后重试",
    ),
    "nodeOverviewTooManyNodes": MessageLookupByLibrary.simpleMessage(
      "节点过多，预览版暂不展示",
    ),
    "nodeOverviewTrafficUnlimited": MessageLookupByLibrary.simpleMessage(
      "流量：不限流量",
    ),
    "nodeOverviewTurnOffProxy": MessageLookupByLibrary.simpleMessage("关闭代理"),
    "nodeOverviewTurnOnProxy": MessageLookupByLibrary.simpleMessage("开启代理"),
    "nodeOverviewTypeUnsupported": MessageLookupByLibrary.simpleMessage(
      "此协议暂不支持隔离测速",
    ),
    "nodeOverviewUntested": MessageLookupByLibrary.simpleMessage("未测"),
    "nodeOverviewUpdateAllSubscriptions": MessageLookupByLibrary.simpleMessage(
      "全部更新",
    ),
    "nodeOverviewUpdateSubscription": MessageLookupByLibrary.simpleMessage(
      "更新订阅",
    ),
    "nodeOverviewUpdating": MessageLookupByLibrary.simpleMessage("正在更新订阅"),
    "nodeOverviewUpdatingShort": MessageLookupByLibrary.simpleMessage("更新中"),
    "nodeOverviewUseNode": MessageLookupByLibrary.simpleMessage("使用"),
    "nodeOverviewUsedOfTotalTraffic": m62,
    "nodeOverviewUsedTrafficOnly": m63,
    "none": MessageLookupByLibrary.simpleMessage("无"),
    "notSelectedTip": MessageLookupByLibrary.simpleMessage("当前代理组无法选中"),
    "noviceMode": MessageLookupByLibrary.simpleMessage("小白模式"),
    "nullProfileDesc": MessageLookupByLibrary.simpleMessage("没有配置文件,请先添加配置文件"),
    "nullScriptTip": MessageLookupByLibrary.simpleMessage("暂无脚本"),
    "nullTip": m64,
    "numberTip": m65,
    "oneColumn": MessageLookupByLibrary.simpleMessage("一列"),
    "oneline": MessageLookupByLibrary.simpleMessage("单行"),
    "onlyIcon": MessageLookupByLibrary.simpleMessage("仅图标"),
    "onlyOtherApps": MessageLookupByLibrary.simpleMessage("仅第三方应用"),
    "onlyStatisticsProxy": MessageLookupByLibrary.simpleMessage("仅统计代理"),
    "onlyStatisticsProxyDesc": MessageLookupByLibrary.simpleMessage(
      "开启后，将只统计代理流量",
    ),
    "openLogsFolder": MessageLookupByLibrary.simpleMessage("打开日志文件夹"),
    "openPanel": MessageLookupByLibrary.simpleMessage("打开面板"),
    "options": MessageLookupByLibrary.simpleMessage("选项"),
    "originalRepository": MessageLookupByLibrary.simpleMessage("原始存储库"),
    "other": MessageLookupByLibrary.simpleMessage("其他"),
    "otherContributors": MessageLookupByLibrary.simpleMessage("贡献者"),
    "outboundMode": MessageLookupByLibrary.simpleMessage("出站模式"),
    "override": MessageLookupByLibrary.simpleMessage("覆写"),
    "overrideAutoSavedHint": MessageLookupByLibrary.simpleMessage(
      "规则变更自动保存并即时热重载生效",
    ),
    "overrideDesc": MessageLookupByLibrary.simpleMessage("覆写代理相关配置"),
    "overrideDns": MessageLookupByLibrary.simpleMessage("覆写DNS"),
    "overrideDnsDesc": MessageLookupByLibrary.simpleMessage("开启后将覆盖配置中的DNS选项"),
    "overrideInvalidTip": MessageLookupByLibrary.simpleMessage("在脚本模式下不生效"),
    "overrideNetworkSettings": MessageLookupByLibrary.simpleMessage("覆盖网络设置"),
    "overrideNetworkSettingsDesc": MessageLookupByLibrary.simpleMessage(
      "忽略提供商配置中的网络设置",
    ),
    "overrideOriginRules": MessageLookupByLibrary.simpleMessage("覆盖原始规则"),
    "overrideProviderSettings": MessageLookupByLibrary.simpleMessage("覆盖"),
    "overrideProviderSettingsDesc": MessageLookupByLibrary.simpleMessage(
      "忽略提供商设置并手动管理",
    ),
    "palette": MessageLookupByLibrary.simpleMessage("调色板"),
    "password": MessageLookupByLibrary.simpleMessage("密码"),
    "paste": MessageLookupByLibrary.simpleMessage("粘贴"),
    "pasteFromClipboard": MessageLookupByLibrary.simpleMessage("粘贴"),
    "pleaseBindWebDAV": MessageLookupByLibrary.simpleMessage("请绑定WebDAV"),
    "pleaseEnterScriptName": MessageLookupByLibrary.simpleMessage("请输入脚本名称"),
    "pleaseInputAdminPassword": MessageLookupByLibrary.simpleMessage(
      "请输入管理员密码",
    ),
    "pleaseUploadFile": MessageLookupByLibrary.simpleMessage("请上传文件"),
    "pleaseUploadValidQrcode": MessageLookupByLibrary.simpleMessage(
      "请上传有效的二维码",
    ),
    "port": MessageLookupByLibrary.simpleMessage("端口"),
    "portConflictTip": MessageLookupByLibrary.simpleMessage("请输入不同的端口"),
    "portTip": m66,
    "preferH3Desc": MessageLookupByLibrary.simpleMessage("优先使用DOH的http/3"),
    "pressKeyboard": MessageLookupByLibrary.simpleMessage("请按下按键"),
    "preview": MessageLookupByLibrary.simpleMessage("预览"),
    "profile": MessageLookupByLibrary.simpleMessage("配置"),
    "profileAutoUpdateIntervalInvalidValidationDesc":
        MessageLookupByLibrary.simpleMessage("请输入有效间隔时间格式"),
    "profileAutoUpdateIntervalNullValidationDesc":
        MessageLookupByLibrary.simpleMessage("请输入自动更新间隔时间"),
    "profileHasUpdate": MessageLookupByLibrary.simpleMessage(
      "配置文件已经修改,是否关闭自动更新 ",
    ),
    "profileNameNullValidationDesc": MessageLookupByLibrary.simpleMessage(
      "请输入配置名称",
    ),
    "profileParseErrorDesc": MessageLookupByLibrary.simpleMessage("配置文件解析错误"),
    "profileUrlInvalidValidationDesc": MessageLookupByLibrary.simpleMessage(
      "请输入有效配置URL",
    ),
    "profileUrlNullValidationDesc": MessageLookupByLibrary.simpleMessage(
      "请输入配置URL",
    ),
    "profiles": MessageLookupByLibrary.simpleMessage("配置"),
    "profilesSort": MessageLookupByLibrary.simpleMessage("配置排序"),
    "project": MessageLookupByLibrary.simpleMessage("项目"),
    "providers": MessageLookupByLibrary.simpleMessage("提供者"),
    "proxies": MessageLookupByLibrary.simpleMessage("代理"),
    "proxiesSetting": MessageLookupByLibrary.simpleMessage("代理设置"),
    "proxyGroup": MessageLookupByLibrary.simpleMessage("代理组"),
    "proxyNameserver": MessageLookupByLibrary.simpleMessage("代理域名服务器"),
    "proxyNameserverDesc": MessageLookupByLibrary.simpleMessage("用于解析代理节点的域名"),
    "proxyPort": MessageLookupByLibrary.simpleMessage("代理端口"),
    "proxyPortDesc": MessageLookupByLibrary.simpleMessage("设置Clash监听端口"),
    "proxyProviders": MessageLookupByLibrary.simpleMessage("代理提供者"),
    "purchase": MessageLookupByLibrary.simpleMessage("购买"),
    "purchaseAccount": MessageLookupByLibrary.simpleMessage("账户与订阅"),
    "purchaseAcquirePlanCode": MessageLookupByLibrary.simpleMessage("获取此套餐兑换码"),
    "purchaseAcquireSheetSubtitle": MessageLookupByLibrary.simpleMessage(
      "通过下方自助商店或微信客服获取兑换码后，返回本页输入核销；客户端内不创建付款订单。",
    ),
    "purchaseAuthTabLogin": MessageLookupByLibrary.simpleMessage("登录账户"),
    "purchaseAuthTabRegister": MessageLookupByLibrary.simpleMessage("免费注册领 2G"),
    "purchaseAvailablePlans": MessageLookupByLibrary.simpleMessage("可购买套餐"),
    "purchaseBackupContactsLabel": MessageLookupByLibrary.simpleMessage(
      "备用人工协助（微信号）",
    ),
    "purchaseBalance": MessageLookupByLibrary.simpleMessage("账户余额"),
    "purchaseBalanceOnlyHint": MessageLookupByLibrary.simpleMessage(
      "余额到账不代表套餐已经开通。",
    ),
    "purchaseBenefitsAfter": MessageLookupByLibrary.simpleMessage(
      "实际权益将在兑换后显示。",
    ),
    "purchaseCardStore": MessageLookupByLibrary.simpleMessage("打开礼品卡商店"),
    "purchaseCenterDescription": MessageLookupByLibrary.simpleMessage(
      "使用礼品卡开通或续费服务，兑换后同步订阅。",
    ),
    "purchaseCenterTitle": MessageLookupByLibrary.simpleMessage("礼品卡兑换"),
    "purchaseChannelError": MessageLookupByLibrary.simpleMessage(
      "礼品卡商店信息加载失败，仍可通过下方微信联系客服。",
    ),
    "purchaseCheck": MessageLookupByLibrary.simpleMessage("查询权益"),
    "purchaseChecking": MessageLookupByLibrary.simpleMessage("正在查询…"),
    "purchaseClearCode": MessageLookupByLibrary.simpleMessage("清空兑换码"),
    "purchaseClipboardEmpty": MessageLookupByLibrary.simpleMessage(
      "剪贴板中未检测到可用的兑换码",
    ),
    "purchaseCode": MessageLookupByLibrary.simpleMessage("礼品卡兑换码"),
    "purchaseCodeFormatError": MessageLookupByLibrary.simpleMessage(
      "请输入由 8–32 位字母和数字组成的兑换码。",
    ),
    "purchaseConfirmRedeem": MessageLookupByLibrary.simpleMessage("确认兑换"),
    "purchaseContactDescription": MessageLookupByLibrary.simpleMessage(
      "暂不支持在线支付，请添加以下任一微信号联系购买或续费。",
    ),
    "purchaseCopyInquiry": MessageLookupByLibrary.simpleMessage("一键复制咨询口令"),
    "purchaseEmail": MessageLookupByLibrary.simpleMessage("邮箱地址"),
    "purchaseEmailDomainError": MessageLookupByLibrary.simpleMessage(
      "当前站点暂不支持该邮箱域名，请更换常用邮箱或前往网页注册。",
    ),
    "purchaseEmailExistsError": MessageLookupByLibrary.simpleMessage(
      "该邮箱已注册，请直接切换到「登录账户」。",
    ),
    "purchaseEmailRequired": MessageLookupByLibrary.simpleMessage(
      "请输入有效的邮箱地址。",
    ),
    "purchaseExpires": MessageLookupByLibrary.simpleMessage("到期时间"),
    "purchaseExpiryChange": MessageLookupByLibrary.simpleMessage(
      "有效期：兑换前 → 兑换后",
    ),
    "purchaseExtraDays": MessageLookupByLibrary.simpleMessage("延长有效期（天）"),
    "purchaseExtraDevices": MessageLookupByLibrary.simpleMessage("增加设备数量"),
    "purchaseFilterAll": MessageLookupByLibrary.simpleMessage("全部套餐"),
    "purchaseFilterOnetime": MessageLookupByLibrary.simpleMessage("按量流量包"),
    "purchaseFilterPeriod": MessageLookupByLibrary.simpleMessage("周期订阅"),
    "purchaseGenericError": MessageLookupByLibrary.simpleMessage("请求失败，请重试。"),
    "purchaseGetCard": MessageLookupByLibrary.simpleMessage("获取礼品卡"),
    "purchaseGetCardDescription": MessageLookupByLibrary.simpleMessage(
      "可通过自助发卡商店、在线客服或备用微信购买礼品卡与获取协助。",
    ),
    "purchaseGmailAliasError": MessageLookupByLibrary.simpleMessage(
      "当前站点不支持 Gmail 别名邮箱（含 + 号），请使用主邮箱地址。",
    ),
    "purchaseHandoffDescription": MessageLookupByLibrary.simpleMessage(
      "完成购卡并复制兑换码后，切回本窗口将自动识别并查验权益（不会自动核销）。",
    ),
    "purchaseHandoffPasteAction": MessageLookupByLibrary.simpleMessage("粘贴并查询"),
    "purchaseHandoffTitle": m67,
    "purchaseHeaderSyncedBadge": MessageLookupByLibrary.simpleMessage(
      "高速节点已就绪",
    ),
    "purchaseHeaderTrialBadge": MessageLookupByLibrary.simpleMessage(
      "新客注册立享 2 GiB 体验 · 流量包永不过期",
    ),
    "purchaseHidePassword": MessageLookupByLibrary.simpleMessage("隐藏密码"),
    "purchaseHistory": MessageLookupByLibrary.simpleMessage("兑换记录"),
    "purchaseHistoryEmpty": MessageLookupByLibrary.simpleMessage("暂无兑换记录。"),
    "purchaseHistoryPage": MessageLookupByLibrary.simpleMessage("页码"),
    "purchaseHistoryRetry": MessageLookupByLibrary.simpleMessage("重新加载记录"),
    "purchaseHistoryTotal": MessageLookupByLibrary.simpleMessage("总计"),
    "purchaseInquiryTemplate": m68,
    "purchaseJumpToWorkbench": MessageLookupByLibrary.simpleMessage(
      "已有兑换码？直达核销",
    ),
    "purchaseLoggingIn": MessageLookupByLibrary.simpleMessage("正在登录…"),
    "purchaseLogin": MessageLookupByLibrary.simpleMessage("登录"),
    "purchaseLoginDescription": MessageLookupByLibrary.simpleMessage(
      "登录账户后核销兑换码，套餐权益与高速节点将自动同步至本机。",
    ),
    "purchaseLoginTitle": MessageLookupByLibrary.simpleMessage("登录后兑换"),
    "purchaseLogout": MessageLookupByLibrary.simpleMessage("退出登录"),
    "purchaseLogoutRemoteError": MessageLookupByLibrary.simpleMessage(
      "已在此设备退出登录，但尚未确认服务器端注销结果。",
    ),
    "purchaseMysteryPreview": MessageLookupByLibrary.simpleMessage(
      "这是一张盲盒礼品卡，实际权益将在兑换成功后揭晓。",
    ),
    "purchaseNewActivationBadge": MessageLookupByLibrary.simpleMessage("新购开通"),
    "purchaseNextPage": MessageLookupByLibrary.simpleMessage("下一页"),
    "purchaseNoBenefits": MessageLookupByLibrary.simpleMessage("未增加额外权益。"),
    "purchaseNoExpiry": MessageLookupByLibrary.simpleMessage("不限时"),
    "purchaseNoPlan": MessageLookupByLibrary.simpleMessage("暂无可用套餐"),
    "purchaseNoPreviousExpiry": MessageLookupByLibrary.simpleMessage("未设置"),
    "purchaseNotEligible": MessageLookupByLibrary.simpleMessage(
      "当前账户暂时不能兑换此礼品卡。",
    ),
    "purchaseOnlineSupport": MessageLookupByLibrary.simpleMessage("在线客服"),
    "purchaseOpenLinkFailed": MessageLookupByLibrary.simpleMessage(
      "无法打开页面，请重试。",
    ),
    "purchaseOpenNodesAction": MessageLookupByLibrary.simpleMessage("查看配置与节点"),
    "purchaseOrderNumber": MessageLookupByLibrary.simpleMessage("兑换订单"),
    "purchasePassword": MessageLookupByLibrary.simpleMessage("密码"),
    "purchasePasswordMinLength": MessageLookupByLibrary.simpleMessage(
      "密码至少需要 8 位字符。",
    ),
    "purchasePasswordRequired": MessageLookupByLibrary.simpleMessage("请输入密码。"),
    "purchasePeriod": MessageLookupByLibrary.simpleMessage("购买周期"),
    "purchasePeriodHalfYearly": MessageLookupByLibrary.simpleMessage("半年付"),
    "purchasePeriodMonthly": MessageLookupByLibrary.simpleMessage("月付"),
    "purchasePeriodOnetime": MessageLookupByLibrary.simpleMessage("按流量"),
    "purchasePeriodQuarterly": MessageLookupByLibrary.simpleMessage("季付"),
    "purchasePeriodThreeYearly": MessageLookupByLibrary.simpleMessage("三年付"),
    "purchasePeriodTwoYearly": MessageLookupByLibrary.simpleMessage("两年付"),
    "purchasePeriodYearly": MessageLookupByLibrary.simpleMessage("年付"),
    "purchasePlan": MessageLookupByLibrary.simpleMessage("当前套餐"),
    "purchasePlanBuyNow": MessageLookupByLibrary.simpleMessage("去购买"),
    "purchasePlanCollapseDetails": MessageLookupByLibrary.simpleMessage(
      "收起套餐说明",
    ),
    "purchasePlanDetails": MessageLookupByLibrary.simpleMessage("套餐说明"),
    "purchasePlanDevices": MessageLookupByLibrary.simpleMessage("设备上限"),
    "purchasePlanExpandDetails": MessageLookupByLibrary.simpleMessage(
      "展开完整套餐说明",
    ),
    "purchasePlanFeaturedBadge": MessageLookupByLibrary.simpleMessage("热销档位"),
    "purchasePlanImageNotLoaded": MessageLookupByLibrary.simpleMessage(
      "未加载外部图片",
    ),
    "purchasePlanLowStock": m69,
    "purchasePlanNotProvided": MessageLookupByLibrary.simpleMessage("未提供"),
    "purchasePlanResetMonthStart": MessageLookupByLibrary.simpleMessage(
      "每月 1 日",
    ),
    "purchasePlanResetMonthlyExpiry": MessageLookupByLibrary.simpleMessage(
      "每月按到期日",
    ),
    "purchasePlanResetNever": MessageLookupByLibrary.simpleMessage("不自动重置"),
    "purchasePlanResetPrice": MessageLookupByLibrary.simpleMessage("流量重置标价"),
    "purchasePlanResetSystem": MessageLookupByLibrary.simpleMessage("跟随系统设置"),
    "purchasePlanResetUnknown": m70,
    "purchasePlanResetYearStart": MessageLookupByLibrary.simpleMessage(
      "每年 1 月 1 日",
    ),
    "purchasePlanResetYearlyExpiry": MessageLookupByLibrary.simpleMessage(
      "每年按到期月日",
    ),
    "purchasePlanSalesCapacity": MessageLookupByLibrary.simpleMessage("剩余销售名额"),
    "purchasePlanSoldOut": MessageLookupByLibrary.simpleMessage("已售罄"),
    "purchasePlanSpeed": MessageLookupByLibrary.simpleMessage("速率上限"),
    "purchasePlanTrafficReset": MessageLookupByLibrary.simpleMessage("流量重置"),
    "purchasePlanUnknown": MessageLookupByLibrary.simpleMessage("订阅套餐"),
    "purchasePlanUnlimited": MessageLookupByLibrary.simpleMessage("不限"),
    "purchasePlansDescription": MessageLookupByLibrary.simpleMessage(
      "价格按网站标价显示；点击「去购买」前往自助发卡商店购卡，复制兑换码后返回本页核销。",
    ),
    "purchasePlansEmpty": MessageLookupByLibrary.simpleMessage("暂无可购买的套餐。"),
    "purchasePlansError": MessageLookupByLibrary.simpleMessage("套餐加载失败，请重试。"),
    "purchasePlansErrorHint": MessageLookupByLibrary.simpleMessage(
      "右侧账号登录、免费注册与礼品卡核销不受影响，可直接继续操作。",
    ),
    "purchasePlansLoading": MessageLookupByLibrary.simpleMessage("正在加载套餐…"),
    "purchasePlansRetry": MessageLookupByLibrary.simpleMessage("重新加载套餐"),
    "purchasePreloginCodeHint": MessageLookupByLibrary.simpleMessage(
      "已买好卡密？可先粘贴于此，登录或注册后自动查验权益",
    ),
    "purchasePreview": MessageLookupByLibrary.simpleMessage("确认兑换权益"),
    "purchasePreviousPage": MessageLookupByLibrary.simpleMessage("上一页"),
    "purchaseProfiles": MessageLookupByLibrary.simpleMessage("管理配置"),
    "purchaseQuotaChange": MessageLookupByLibrary.simpleMessage(
      "总流量额度：兑换前 → 兑换后",
    ),
    "purchaseRecoverPassword": MessageLookupByLibrary.simpleMessage("前往网页找回密码"),
    "purchaseRecoverResult": MessageLookupByLibrary.simpleMessage("查询兑换结果"),
    "purchaseRedeemFor": MessageLookupByLibrary.simpleMessage("兑换至账户"),
    "purchaseRedeemTitle": MessageLookupByLibrary.simpleMessage("兑换礼品卡"),
    "purchaseRedeeming": MessageLookupByLibrary.simpleMessage("正在兑换…"),
    "purchaseRefresh": MessageLookupByLibrary.simpleMessage("刷新账户"),
    "purchaseRegister": MessageLookupByLibrary.simpleMessage("前往网页注册"),
    "purchaseRegisterSubmit": MessageLookupByLibrary.simpleMessage("免费注册并同步节点"),
    "purchaseRegisterTrialBanner": MessageLookupByLibrary.simpleMessage(
      "注册即赠 2 GiB 永久体验流量，自动导入高速节点并开启智能连接。",
    ),
    "purchaseRegisterWebRequiredError": MessageLookupByLibrary.simpleMessage(
      "当前站点启用了邮箱验证或人机校验，请点击下方「前往网页注册」完成注册。",
    ),
    "purchaseRegistering": MessageLookupByLibrary.simpleMessage("正在注册并开通…"),
    "purchaseRegistrationClosedError": MessageLookupByLibrary.simpleMessage(
      "当前站点暂未开放新用户注册。",
    ),
    "purchaseRemaining": MessageLookupByLibrary.simpleMessage("剩余流量"),
    "purchaseRenewalBadge": MessageLookupByLibrary.simpleMessage("续费叠加"),
    "purchaseResetTraffic": MessageLookupByLibrary.simpleMessage("重置已用流量"),
    "purchaseRestoring": MessageLookupByLibrary.simpleMessage("正在恢复账户…"),
    "purchaseShowPassword": MessageLookupByLibrary.simpleMessage("显示密码"),
    "purchaseStepBrowse": MessageLookupByLibrary.simpleMessage("① 选套餐或获取兑换码"),
    "purchaseStepRedeem": MessageLookupByLibrary.simpleMessage("② 登录并核验兑换码"),
    "purchaseStepSync": MessageLookupByLibrary.simpleMessage("③ 自动同步节点"),
    "purchaseStorageError": MessageLookupByLibrary.simpleMessage(
      "无法访问系统安全凭据存储，请检查后重试。",
    ),
    "purchaseSuccess": MessageLookupByLibrary.simpleMessage("礼品卡兑换成功"),
    "purchaseSuccessDescription": MessageLookupByLibrary.simpleMessage(
      "权益已发放至当前账户，订阅同步结果请单独确认。",
    ),
    "purchaseSync": MessageLookupByLibrary.simpleMessage("同步订阅"),
    "purchaseSyncError": MessageLookupByLibrary.simpleMessage(
      "订阅同步失败，可点击下方按钮重试。",
    ),
    "purchaseSyncFailed": MessageLookupByLibrary.simpleMessage(
      "兑换已成功，但订阅同步失败。请重试同步，无需再次兑换。",
    ),
    "purchaseSyncSucceeded": MessageLookupByLibrary.simpleMessage("订阅已同步成功。"),
    "purchaseSyncing": MessageLookupByLibrary.simpleMessage("正在同步订阅…"),
    "purchaseTitle": MessageLookupByLibrary.simpleMessage("购买与续费"),
    "purchaseTraffic": MessageLookupByLibrary.simpleMessage("流量额度"),
    "purchaseUnresolved": MessageLookupByLibrary.simpleMessage("兑换结果待确认"),
    "purchaseUnresolvedDescription": MessageLookupByLibrary.simpleMessage(
      "请求中断，暂时无法确认兑换结果。请先查询结果，再兑换其他礼品卡。",
    ),
    "purchaseUnsupportedAccount": MessageLookupByLibrary.simpleMessage(
      "请使用普通用户账户兑换礼品卡。",
    ),
    "purchaseUsed": MessageLookupByLibrary.simpleMessage("已用流量"),
    "purchaseUsedPreserved": MessageLookupByLibrary.simpleMessage("保留已用流量"),
    "purchaseValidityDays": MessageLookupByLibrary.simpleMessage("有效期（天）"),
    "pureBlackMode": MessageLookupByLibrary.simpleMessage("纯黑模式"),
    "qrcode": MessageLookupByLibrary.simpleMessage("二维码"),
    "qrcodeDesc": MessageLookupByLibrary.simpleMessage("扫描二维码获取配置文件"),
    "rainbowScheme": MessageLookupByLibrary.simpleMessage("彩虹"),
    "recovery": MessageLookupByLibrary.simpleMessage("恢复"),
    "recoveryAll": MessageLookupByLibrary.simpleMessage("恢复所有数据"),
    "recoveryProfiles": MessageLookupByLibrary.simpleMessage("仅恢复配置文件"),
    "recoveryStrategy": MessageLookupByLibrary.simpleMessage("恢复策略"),
    "recoveryStrategy_compatible": MessageLookupByLibrary.simpleMessage("兼容"),
    "recoveryStrategy_override": MessageLookupByLibrary.simpleMessage("覆盖"),
    "recoverySuccess": MessageLookupByLibrary.simpleMessage("恢复成功"),
    "redirPort": MessageLookupByLibrary.simpleMessage("Redir端口"),
    "redo": MessageLookupByLibrary.simpleMessage("重做"),
    "regExp": MessageLookupByLibrary.simpleMessage("正则"),
    "remote": MessageLookupByLibrary.simpleMessage("远程"),
    "remoteBackupDesc": MessageLookupByLibrary.simpleMessage("备份数据到WebDAV"),
    "remoteRecoveryDesc": MessageLookupByLibrary.simpleMessage("通过WebDAV恢复数据"),
    "remove": MessageLookupByLibrary.simpleMessage("移除"),
    "rename": MessageLookupByLibrary.simpleMessage("重命名"),
    "renew": MessageLookupByLibrary.simpleMessage("续订"),
    "requests": MessageLookupByLibrary.simpleMessage("请求"),
    "requestsDesc": MessageLookupByLibrary.simpleMessage("查看最近请求记录"),
    "reset": MessageLookupByLibrary.simpleMessage("重置"),
    "resetTip": MessageLookupByLibrary.simpleMessage("确定要重置吗?"),
    "resources": MessageLookupByLibrary.simpleMessage("资源"),
    "resourcesDesc": MessageLookupByLibrary.simpleMessage("外部资源相关信息"),
    "respectRules": MessageLookupByLibrary.simpleMessage("遵守规则"),
    "respectRulesDesc": MessageLookupByLibrary.simpleMessage(
      "DNS连接跟随rules,需配置proxy-server-nameserver",
    ),
    "restart": MessageLookupByLibrary.simpleMessage("重启"),
    "routeAddress": MessageLookupByLibrary.simpleMessage("路由地址"),
    "routeAddressDesc": MessageLookupByLibrary.simpleMessage("配置监听路由地址"),
    "routeMode": MessageLookupByLibrary.simpleMessage("路由模式"),
    "routeMode_bypassPrivate": MessageLookupByLibrary.simpleMessage("绕过私有路由地址"),
    "routeMode_config": MessageLookupByLibrary.simpleMessage("使用配置"),
    "ru": MessageLookupByLibrary.simpleMessage("俄语"),
    "rule": MessageLookupByLibrary.simpleMessage("按规则"),
    "ruleName": MessageLookupByLibrary.simpleMessage("规则名称"),
    "ruleProviders": MessageLookupByLibrary.simpleMessage("规则提供者"),
    "ruleTarget": MessageLookupByLibrary.simpleMessage("规则目标"),
    "running": MessageLookupByLibrary.simpleMessage("运行中"),
    "save": MessageLookupByLibrary.simpleMessage("保存"),
    "saveChanges": MessageLookupByLibrary.simpleMessage("是否保存更改？"),
    "saveTip": MessageLookupByLibrary.simpleMessage("确定要保存吗？"),
    "scan": MessageLookupByLibrary.simpleMessage("扫码"),
    "script": MessageLookupByLibrary.simpleMessage("脚本"),
    "search": MessageLookupByLibrary.simpleMessage("搜索"),
    "seconds": MessageLookupByLibrary.simpleMessage("秒"),
    "selectAll": MessageLookupByLibrary.simpleMessage("全选"),
    "selected": MessageLookupByLibrary.simpleMessage("已选择"),
    "selectedCountTitle": m71,
    "settings": MessageLookupByLibrary.simpleMessage("设置"),
    "show": MessageLookupByLibrary.simpleMessage("显示"),
    "shrink": MessageLookupByLibrary.simpleMessage("紧凑"),
    "silentLaunch": MessageLookupByLibrary.simpleMessage("静默启动"),
    "silentLaunchDesc": MessageLookupByLibrary.simpleMessage("后台启动"),
    "size": MessageLookupByLibrary.simpleMessage("尺寸"),
    "socksPort": MessageLookupByLibrary.simpleMessage("Socks端口"),
    "sort": MessageLookupByLibrary.simpleMessage("排序"),
    "source": MessageLookupByLibrary.simpleMessage("来源"),
    "sourceIp": MessageLookupByLibrary.simpleMessage("源IP"),
    "stackMode": MessageLookupByLibrary.simpleMessage("栈模式"),
    "standard": MessageLookupByLibrary.simpleMessage("标准"),
    "start": MessageLookupByLibrary.simpleMessage("启动"),
    "startVpn": MessageLookupByLibrary.simpleMessage("正在启动VPN..."),
    "status": MessageLookupByLibrary.simpleMessage("状态"),
    "statusDesc": MessageLookupByLibrary.simpleMessage("关闭后将使用系统DNS"),
    "stop": MessageLookupByLibrary.simpleMessage("暂停"),
    "stopVpn": MessageLookupByLibrary.simpleMessage("正在停止VPN..."),
    "stopped": MessageLookupByLibrary.simpleMessage("已停止"),
    "style": MessageLookupByLibrary.simpleMessage("风格"),
    "subRule": MessageLookupByLibrary.simpleMessage("子规则"),
    "submit": MessageLookupByLibrary.simpleMessage("提交"),
    "subscriptionClipboardEmptyError": MessageLookupByLibrary.simpleMessage(
      "剪贴板为空，请先复制订阅链接",
    ),
    "subscriptionEternal": MessageLookupByLibrary.simpleMessage("长期有效"),
    "subscriptionExpired": MessageLookupByLibrary.simpleMessage("您的订阅已过期"),
    "subscriptionExpiresInDays": m72,
    "subscriptionExpiresSoon": MessageLookupByLibrary.simpleMessage("订阅即将到期"),
    "subscriptionExpiresToday": MessageLookupByLibrary.simpleMessage(
      "您的订阅今天到期",
    ),
    "subscriptionImportAuthOrNotFoundError":
        MessageLookupByLibrary.simpleMessage("订阅链接无效或已失效，请确认复制完整或联系服务商"),
    "subscriptionImportGenericError": MessageLookupByLibrary.simpleMessage(
      "导入订阅失败，请检查订阅链接是否正确后重试",
    ),
    "subscriptionImportInvalidConfigError":
        MessageLookupByLibrary.simpleMessage(
          "该链接不是有效的订阅配置（可能误粘了网页地址），请复制正确的订阅链接",
        ),
    "subscriptionImportTimeoutError": MessageLookupByLibrary.simpleMessage(
      "拉取订阅超时或网络不通，请检查网络连接后重试",
    ),
    "subscriptionUrlEmptyError": MessageLookupByLibrary.simpleMessage(
      "请先粘贴订阅链接",
    ),
    "subscriptionUrlInvalidError": MessageLookupByLibrary.simpleMessage(
      "未识别到有效的 http(s):// 订阅链接，请检查复制内容",
    ),
    "support": MessageLookupByLibrary.simpleMessage("支持"),
    "sync": MessageLookupByLibrary.simpleMessage("同步"),
    "system": MessageLookupByLibrary.simpleMessage("系统"),
    "systemApp": MessageLookupByLibrary.simpleMessage("系统应用"),
    "systemFont": MessageLookupByLibrary.simpleMessage("系统字体"),
    "systemProxy": MessageLookupByLibrary.simpleMessage("系统代理"),
    "systemProxyDesc": MessageLookupByLibrary.simpleMessage("设置系统代理"),
    "tab": MessageLookupByLibrary.simpleMessage("标签页"),
    "tabAnimation": MessageLookupByLibrary.simpleMessage("选项卡动画"),
    "tabAnimationDesc": MessageLookupByLibrary.simpleMessage("仅在移动视图中有效"),
    "tcpConcurrent": MessageLookupByLibrary.simpleMessage("TCP并发"),
    "tcpConcurrentDesc": MessageLookupByLibrary.simpleMessage("开启后允许TCP并发"),
    "testUrl": MessageLookupByLibrary.simpleMessage("测速链接"),
    "textScale": MessageLookupByLibrary.simpleMessage("文本缩放"),
    "thanks": MessageLookupByLibrary.simpleMessage("感谢贡献"),
    "theme": MessageLookupByLibrary.simpleMessage("主题"),
    "themeColor": MessageLookupByLibrary.simpleMessage("主题色彩"),
    "themeDesc": MessageLookupByLibrary.simpleMessage("设置深色模式，调整色彩"),
    "themeMode": MessageLookupByLibrary.simpleMessage("主题模式"),
    "threeColumns": MessageLookupByLibrary.simpleMessage("三列"),
    "tight": MessageLookupByLibrary.simpleMessage("紧凑"),
    "time": MessageLookupByLibrary.simpleMessage("时间"),
    "tip": MessageLookupByLibrary.simpleMessage("提示"),
    "toggle": MessageLookupByLibrary.simpleMessage("切换"),
    "tonalSpotScheme": MessageLookupByLibrary.simpleMessage("调性点缀"),
    "tooFrequentOperation": MessageLookupByLibrary.simpleMessage("请等待15秒后再次刷新"),
    "tools": MessageLookupByLibrary.simpleMessage("设置"),
    "tproxyPort": MessageLookupByLibrary.simpleMessage("Tproxy端口"),
    "trafficUnlimited": MessageLookupByLibrary.simpleMessage("不限流量"),
    "trafficUsage": MessageLookupByLibrary.simpleMessage("流量统计"),
    "tributeDialogTitle": MessageLookupByLibrary.simpleMessage("开源致敬与特别鸣谢"),
    "tributeFlclashxBadge": MessageLookupByLibrary.simpleMessage(
      "OPEN-SOURCE HERITAGE",
    ),
    "tributeFlclashxBody": MessageLookupByLibrary.simpleMessage(
      "自由云（FreedomNet）郑重声明：本软件基于开源项目 FlClashX（pluralplay/FlClashX）构建，承袭 FlClash 与 Mihomo（Clash.Meta）内核生态。谨向 FlClashX 原作者及全体上游开源贡献者致以最崇高的敬意与诚挚感谢。",
    ),
    "tributeFlclashxTitle": MessageLookupByLibrary.simpleMessage(
      "郑重声明：本项目基于开源项目 FlClashX 构建",
    ),
    "tributeGeminiBadge": MessageLookupByLibrary.simpleMessage(
      "ENGINEERING & DESIGN SUPPORT",
    ),
    "tributeGeminiBody": MessageLookupByLibrary.simpleMessage(
      "郑重感谢 Gemini 4 为自由云（FreedomNet）的系统架构演进、商业级交互设计、代码工程重构与全链路自动化验证提供的核心技术支持。",
    ),
    "tributeGeminiTitle": MessageLookupByLibrary.simpleMessage(
      "特别鸣谢：Gemini 4 研发与设计支持",
    ),
    "tun": MessageLookupByLibrary.simpleMessage("虚拟网卡"),
    "tunDesc": MessageLookupByLibrary.simpleMessage("仅在管理员模式生效"),
    "tunDisableAction": MessageLookupByLibrary.simpleMessage("请求关闭"),
    "tunErrorAdapterCreate": MessageLookupByLibrary.simpleMessage(
      "Windows 未能添加虚拟网卡，请稍后重新开启重试",
    ),
    "tunErrorAuthorization": MessageLookupByLibrary.simpleMessage(
      "需要管理员授权，可重新开启重试",
    ),
    "tunErrorComponents": MessageLookupByLibrary.simpleMessage(
      "后台组件不匹配，可重新开启更新",
    ),
    "tunErrorConfiguration": MessageLookupByLibrary.simpleMessage("配置未成功应用"),
    "tunErrorLegacyAgent": MessageLookupByLibrary.simpleMessage(
      "请先退出旧版后台，再重新打开本版本",
    ),
    "tunErrorProfileRequired": MessageLookupByLibrary.simpleMessage(
      "请先选择可读取且非空的配置，再重试连接",
    ),
    "tunErrorStart": MessageLookupByLibrary.simpleMessage("网卡启动失败，可重新开启重试"),
    "tunErrorStop": MessageLookupByLibrary.simpleMessage("关闭失败，请核对当前运行状态"),
    "tunErrorUnavailable": MessageLookupByLibrary.simpleMessage(
      "无法确认状态，请检查后台版本",
    ),
    "tunStatusFailure": m73,
    "tunStatusOff": MessageLookupByLibrary.simpleMessage("未启动"),
    "tunStatusOn": MessageLookupByLibrary.simpleMessage("已启动"),
    "tunStatusStarting": MessageLookupByLibrary.simpleMessage("正在开启…"),
    "tunStatusStopping": MessageLookupByLibrary.simpleMessage("正在关闭…"),
    "tunStatusUnknown": MessageLookupByLibrary.simpleMessage("状态未知"),
    "tunStatusWaiting": MessageLookupByLibrary.simpleMessage("代理启动后启用"),
    "twoColumns": MessageLookupByLibrary.simpleMessage("两列"),
    "unableToUpdateCurrentProfileDesc": MessageLookupByLibrary.simpleMessage(
      "无法更新当前配置文件",
    ),
    "undo": MessageLookupByLibrary.simpleMessage("撤销"),
    "unifiedDelay": MessageLookupByLibrary.simpleMessage("统一延迟"),
    "unifiedDelayDesc": MessageLookupByLibrary.simpleMessage("去除握手等额外延迟"),
    "unknown": MessageLookupByLibrary.simpleMessage("未知"),
    "unnamed": MessageLookupByLibrary.simpleMessage("未命名"),
    "update": MessageLookupByLibrary.simpleMessage("更新"),
    "updateAllGeoData": MessageLookupByLibrary.simpleMessage("更新所有地理数据"),
    "upload": MessageLookupByLibrary.simpleMessage("上传"),
    "url": MessageLookupByLibrary.simpleMessage("URL"),
    "urlDesc": MessageLookupByLibrary.simpleMessage("通过URL获取配置文件"),
    "urlTip": m74,
    "useHosts": MessageLookupByLibrary.simpleMessage("使用Hosts"),
    "useSystemHosts": MessageLookupByLibrary.simpleMessage("使用系统Hosts"),
    "value": MessageLookupByLibrary.simpleMessage("值"),
    "vibrantScheme": MessageLookupByLibrary.simpleMessage("活力"),
    "view": MessageLookupByLibrary.simpleMessage("查看"),
    "vpnDesc": MessageLookupByLibrary.simpleMessage("修改VPN相关设置"),
    "vpnEnableDesc": MessageLookupByLibrary.simpleMessage(
      "通过VpnService自动路由系统所有流量",
    ),
    "vpnSystemProxyDesc": MessageLookupByLibrary.simpleMessage(
      "为VpnService附加HTTP代理",
    ),
    "vpnTip": MessageLookupByLibrary.simpleMessage("重启VPN后改变生效"),
    "webDAVConfiguration": MessageLookupByLibrary.simpleMessage("WebDAV配置"),
    "wechatId": MessageLookupByLibrary.simpleMessage("微信号"),
    "whitelistMode": MessageLookupByLibrary.simpleMessage("白名单模式"),
    "years": MessageLookupByLibrary.simpleMessage("年"),
    "zashboardInApp": MessageLookupByLibrary.simpleMessage("在应用内打开 zashboard"),
    "zashboardInAppDesc": MessageLookupByLibrary.simpleMessage(
      "使用内置浏览器显示控制面板，无需跳转到外部浏览器",
    ),
    "zh_CN": MessageLookupByLibrary.simpleMessage("中文简体"),
  };
}

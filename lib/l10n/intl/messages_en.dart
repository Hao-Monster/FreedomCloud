// DO NOT EDIT. This is code generated via package:intl/generate_localized.dart
// This is a library that provides messages for a en locale. All the
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
  String get localeName => 'en';

  static String m0(node) => "Current node: ${node}";

  static String m1(count) => "Overrides ${count}";

  static String m2(count) => "${count} nodes";

  static String m3(label) =>
      "Are you sure you want to delete the selected ${label}?";

  static String m4(label) =>
      "Are you sure you want to delete the current ${label}?";

  static String m5(label) => "${label} cannot be empty";

  static String m6(label) => "Current ${label} already exists";

  static String m7(time, elapsed) => "Last checked ${time} · ${elapsed}";

  static String m8(mb) => "IPC OK · ${mb} MB";

  static String m9(exitPart) => "Verified through proxy${exitPart}";

  static String m10(node) => "Node ${node} failed connectivity check";

  static String m11(node) =>
      "Node ${node} failed delay probe, but live E2E traffic succeeded";

  static String m12(node) => "Node ${node} latency is elevated";

  static String m13(count) => "Loaded (${count} groups)";

  static String m14(days) => "${days}d remaining";

  static String m15(percent) => "${percent}% quota used";

  static String m16(flag) => " · Exit ${flag}";

  static String m17(delay) => "Direct mode · Uplink ${delay} ms";

  static String m18(node, delay, exitPart) =>
      "Node ${node} · ${delay} ms${exitPart}";

  static String m19(available, tested, total) =>
      "Nodes: ${available} available / ${tested} tested / ${total} total";

  static String m20(count) => "${count} profiles";

  static String m21(text) => "Announcement: ${text}";

  static String m22(profile, node, delay) =>
      "Auto-connected to fastest node: ${profile} · ${node} (${delay} ms)";

  static String m23(profile, node, delay) =>
      "Smart Select active: ${profile} (fastest: ${node} · ${delay} ms)";

  static String m24(node) =>
      "Auto-selected ${node} (all nodes failed latency check; update subscription or try another node if offline)";

  static String m25(node) =>
      "Selected ${node}, but this subscription has expired. Renew or replace it";

  static String m26(node) =>
      "Selected ${node}, but subscription traffic is exhausted. Renew or replace it";

  static String m27(hours) => "Auto-update ${hours}h";

  static String m28(minutes) => "Auto-update ${minutes}m";

  static String m29(count) => "Failed ${count}";

  static String m30(count) => "Fast ${count}";

  static String m31(count) => "Slow ${count}";

  static String m32(count) => "Untested ${count}";

  static String m33(completed, failed, untested, profiles) =>
      "Completed ${completed} · Failed ${failed} · Untested ${untested} · Profiles with issues ${profiles}";

  static String m34(name) => "Active: ${name}";

  static String m35(date) => "Expires: ${date}";

  static String m36(days) => "${days}d left";

  static String m37(hours) => "${hours}h left";

  static String m38(count) => "${count} expired";

  static String m39(count) => "${count} expiring soon";

  static String m40(provider) => "Profile file · ${provider}";

  static String m41(median) => "Global median: ${median}";

  static String m42(median, best) => "Median: ${median} · Best: ${best}";

  static String m43(available, tested, total) =>
      "${available} available / ${tested} tested / ${total} total";

  static String m44(time) => "Last active test: ${time}";

  static String m45(time) => "Synced: ${time}";

  static String m46(time) => "Last test: ${time}";

  static String m47(profile, node) => "Locked fixed node: ${profile} · ${node}";

  static String m48(delay) => "Median: ${delay}";

  static String m49(count) => "Additional issue types: ${count}";

  static String m50(available, total) => "Available ${available} / ${total}";

  static String m51(date) => "Exp. ${date}";

  static String m52(count) => "${count} profiles";

  static String m53(completed, total) => "${completed} / ${total}";

  static String m54(provider) => "${provider}: nodes visible after activation";

  static String m55(profile) => "Proxy on · Smart: ${profile} (auto-selecting)";

  static String m56(profile, node) => "Proxy on · Smart: ${profile} · ${node}";

  static String m57(profile, node) => "Proxy on · Using ${profile} · ${node}";

  static String m58(traffic) => "Remaining: ${traffic}";

  static String m59(profile, node) => "Switched to ${profile} · ${node}";

  static String m60(profile) => "Enabled Smart Select: ${profile}";

  static String m61(profile, node) =>
      "Enabled Smart Select: ${profile} (current: ${node})";

  static String m62(used, total) => "Used ${used} / ${total}";

  static String m63(used) => "Used: ${used}";

  static String m64(label) => "No ${label} at the moment";

  static String m65(label) => "${label} must be a number";

  static String m66(label) => "${label} must be between 1024 and 49151";

  static String m67(seconds) =>
      "Too many requests. Please try again in ${seconds}s.";

  static String m68(plan) => "Opened store for ${plan}";

  static String m69(plan, quota, price) =>
      "Hello, I would like to get a redemption code for [${plan} · ${quota} GiB (${price})].";

  static String m70(count) => "${count} left";

  static String m71(code) => "Unknown rule (${code})";

  static String m72(price) => "~${price} / GB";

  static String m73(seconds) => "Resend in ${seconds}s";

  static String m74(periods) => "Billing cycle: ${periods}";

  static String m75(count) => "Device limit: ${count}";

  static String m76(speed) => "Speed limit: ${speed} Mbps";

  static String m77(count) => "${count} items have been selected";

  static String m78(days) => "Your subscription expires in ${days} day(s)";

  static String m79(name) => "${name} is typing...";

  static String m80(reason) => "TUN: ${reason}";

  static String m81(label) => "${label} must be a url";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
    "about": MessageLookupByLibrary.simpleMessage("About"),
    "accessControl": MessageLookupByLibrary.simpleMessage("AccessControl"),
    "accessControlAllowDesc": MessageLookupByLibrary.simpleMessage(
      "Only allow selected app to enter VPN",
    ),
    "accessControlDesc": MessageLookupByLibrary.simpleMessage(
      "Configure application access proxy",
    ),
    "accessControlNotAllowDesc": MessageLookupByLibrary.simpleMessage(
      "The selected application will be excluded from VPN",
    ),
    "account": MessageLookupByLibrary.simpleMessage("Account"),
    "action": MessageLookupByLibrary.simpleMessage("Action"),
    "action_mode": MessageLookupByLibrary.simpleMessage("Switch mode"),
    "action_proxy": MessageLookupByLibrary.simpleMessage("System proxy"),
    "action_start": MessageLookupByLibrary.simpleMessage("Start/Stop"),
    "action_tun": MessageLookupByLibrary.simpleMessage("TUN"),
    "action_view": MessageLookupByLibrary.simpleMessage("Show/Hide"),
    "add": MessageLookupByLibrary.simpleMessage("Add"),
    "addFromPhoneSubtitle": MessageLookupByLibrary.simpleMessage(
      "Scan QR code with phone",
    ),
    "addFromPhoneTitle": MessageLookupByLibrary.simpleMessage("Add from Phone"),
    "addProfile": MessageLookupByLibrary.simpleMessage("Add Profile"),
    "addRule": MessageLookupByLibrary.simpleMessage("Add rule"),
    "addedOriginRules": MessageLookupByLibrary.simpleMessage(
      "Attach on the original rules",
    ),
    "address": MessageLookupByLibrary.simpleMessage("Address"),
    "addressHelp": MessageLookupByLibrary.simpleMessage(
      "WebDAV server address",
    ),
    "addressTip": MessageLookupByLibrary.simpleMessage(
      "Please enter a valid WebDAV address",
    ),
    "adminAutoLaunch": MessageLookupByLibrary.simpleMessage(
      "Admin auto launch",
    ),
    "adminAutoLaunchDesc": MessageLookupByLibrary.simpleMessage(
      "Boot up by using admin mode",
    ),
    "ago": MessageLookupByLibrary.simpleMessage(" Ago"),
    "agree": MessageLookupByLibrary.simpleMessage("Agree"),
    "allApps": MessageLookupByLibrary.simpleMessage("All apps"),
    "allowBypass": MessageLookupByLibrary.simpleMessage(
      "Allow applications to bypass VPN",
    ),
    "allowBypassDesc": MessageLookupByLibrary.simpleMessage(
      "Some apps can bypass VPN when turned on",
    ),
    "allowLan": MessageLookupByLibrary.simpleMessage("AllowLan"),
    "allowLanDesc": MessageLookupByLibrary.simpleMessage(
      "Allow access proxy through the LAN",
    ),
    "announcement": MessageLookupByLibrary.simpleMessage("Announcement"),
    "app": MessageLookupByLibrary.simpleMessage("App"),
    "appAccessControl": MessageLookupByLibrary.simpleMessage(
      "App access control",
    ),
    "appBrandName": MessageLookupByLibrary.simpleMessage("FreedomNet"),
    "appBrandTagline": MessageLookupByLibrary.simpleMessage(
      "Next-Generation Intelligent Network Client",
    ),
    "appDesc": MessageLookupByLibrary.simpleMessage(
      "Processing app related settings",
    ),
    "application": MessageLookupByLibrary.simpleMessage("Application Settings"),
    "applicationDesc": MessageLookupByLibrary.simpleMessage(
      "Standard application settings",
    ),
    "auto": MessageLookupByLibrary.simpleMessage("Auto"),
    "autoCheckUpdate": MessageLookupByLibrary.simpleMessage(
      "Auto check updates",
    ),
    "autoCheckUpdateDesc": MessageLookupByLibrary.simpleMessage(
      "Auto check for updates when the app starts",
    ),
    "autoCloseConnections": MessageLookupByLibrary.simpleMessage(
      "Auto close connections",
    ),
    "autoCloseConnectionsDesc": MessageLookupByLibrary.simpleMessage(
      "Auto close connections after change node",
    ),
    "autoLaunch": MessageLookupByLibrary.simpleMessage("Auto launch"),
    "autoLaunchDesc": MessageLookupByLibrary.simpleMessage(
      "Follow the system self startup",
    ),
    "autoRun": MessageLookupByLibrary.simpleMessage("AutoRun"),
    "autoRunDesc": MessageLookupByLibrary.simpleMessage(
      "Auto run when the application is opened",
    ),
    "autoSetSystemDns": MessageLookupByLibrary.simpleMessage(
      "Auto set system DNS",
    ),
    "autoStart": MessageLookupByLibrary.simpleMessage("Autostart"),
    "autoStartDesc": MessageLookupByLibrary.simpleMessage(
      "Allow background autostart so the VPN survives reboots and updates (MIUI/EMUI etc.)",
    ),
    "autoUpdate": MessageLookupByLibrary.simpleMessage("Auto update"),
    "autoUpdateInterval": MessageLookupByLibrary.simpleMessage(
      "Auto update interval (minutes)",
    ),
    "backup": MessageLookupByLibrary.simpleMessage("Backup"),
    "backupAndRecovery": MessageLookupByLibrary.simpleMessage(
      "Backup and Recovery",
    ),
    "backupAndRecoveryDesc": MessageLookupByLibrary.simpleMessage(
      "Sync data via WebDAV or file",
    ),
    "backupSuccess": MessageLookupByLibrary.simpleMessage("Backup success"),
    "basicConfig": MessageLookupByLibrary.simpleMessage("Basic configuration"),
    "basicConfigDesc": MessageLookupByLibrary.simpleMessage(
      "Modify the basic configuration globally",
    ),
    "batteryOptimization": MessageLookupByLibrary.simpleMessage(
      "Battery optimization",
    ),
    "batteryOptimizationDesc": MessageLookupByLibrary.simpleMessage(
      "Exempt the app so the system doesn\'t kill the VPN in the background",
    ),
    "bind": MessageLookupByLibrary.simpleMessage("Bind"),
    "blacklistMode": MessageLookupByLibrary.simpleMessage("Blacklist mode"),
    "blacklistModeDesc": MessageLookupByLibrary.simpleMessage(
      "The selected apps connect directly; all others are routed through the VPN.",
    ),
    "brandDialogSubtitle": MessageLookupByLibrary.simpleMessage(
      "Brand Overview & Core Experience",
    ),
    "brandPillarModesBody": MessageLookupByLibrary.simpleMessage(
      "Novice Mode keeps everyday connection effortless with seamless TUN & system proxy, while Expert Mode unlocks full routing, connection, and diagnostic control.",
    ),
    "brandPillarModesTitle": MessageLookupByLibrary.simpleMessage(
      "Dual-Mode Cockpit · Zero Friction",
    ),
    "brandPillarServiceBody": MessageLookupByLibrary.simpleMessage(
      "Track data quota, remaining balance, and expiry at a glance, with instant gift-card verification, multi-profile sync, and dedicated support.",
    ),
    "brandPillarServiceTitle": MessageLookupByLibrary.simpleMessage(
      "Transparent Quota · Instant Activation",
    ),
    "brandPillarSmartBody": MessageLookupByLibrary.simpleMessage(
      "Concurrent latency health checks with clear visual tiers, one-click fastest connect, region filters, and pinned node control.",
    ),
    "brandPillarSmartTitle": MessageLookupByLibrary.simpleMessage(
      "Smart Routing · Millisecond Insight",
    ),
    "brandShowcaseBadge": MessageLookupByLibrary.simpleMessage(
      "FREEDOMNET · FLAGSHIP CLIENT",
    ),
    "brandShowcaseHeroBody": MessageLookupByLibrary.simpleMessage(
      "FreedomNet delivers a clean, reliable, low-latency global network acceleration experience—built for cross-border work, AI productivity, and high-definition streaming in one click.",
    ),
    "brandShowcaseHeroTitle": MessageLookupByLibrary.simpleMessage(
      "Borderless Access, Effortless Speed",
    ),
    "buyExtraTraffic": MessageLookupByLibrary.simpleMessage(
      "Buy extra traffic",
    ),
    "bypassDomain": MessageLookupByLibrary.simpleMessage("Bypass domain"),
    "bypassDomainDesc": MessageLookupByLibrary.simpleMessage(
      "Only takes effect when the system proxy is enabled",
    ),
    "cacheCorrupt": MessageLookupByLibrary.simpleMessage(
      "The cache is corrupt. Do you want to clear it?",
    ),
    "cancel": MessageLookupByLibrary.simpleMessage("Cancel"),
    "cancelFilterSystemApp": MessageLookupByLibrary.simpleMessage(
      "Cancel filter system app",
    ),
    "cancelSelectAll": MessageLookupByLibrary.simpleMessage(
      "Cancel select all",
    ),
    "change": MessageLookupByLibrary.simpleMessage("Change"),
    "changeServer": MessageLookupByLibrary.simpleMessage("Change Server"),
    "checkError": MessageLookupByLibrary.simpleMessage("Check error"),
    "checkUpdate": MessageLookupByLibrary.simpleMessage("Check for updates"),
    "checkUpdateError": MessageLookupByLibrary.simpleMessage(
      "The current application is already the latest version",
    ),
    "checking": MessageLookupByLibrary.simpleMessage("Checking..."),
    "clearData": MessageLookupByLibrary.simpleMessage("Clear Data"),
    "clearDataTip": MessageLookupByLibrary.simpleMessage(
      "This will delete all app data and restart the application. Are you sure?",
    ),
    "clipboardExport": MessageLookupByLibrary.simpleMessage("Export clipboard"),
    "clipboardImport": MessageLookupByLibrary.simpleMessage("Clipboard import"),
    "collapseAll": MessageLookupByLibrary.simpleMessage("Collapse all"),
    "color": MessageLookupByLibrary.simpleMessage("Color"),
    "colorSchemes": MessageLookupByLibrary.simpleMessage("Color schemes"),
    "columns": MessageLookupByLibrary.simpleMessage("Columns"),
    "compatible": MessageLookupByLibrary.simpleMessage("Compatibility mode"),
    "compatibleDesc": MessageLookupByLibrary.simpleMessage(
      "Opening it will lose part of its application ability and gain the support of full amount of Clash.",
    ),
    "confirm": MessageLookupByLibrary.simpleMessage("Confirm"),
    "connections": MessageLookupByLibrary.simpleMessage("Connections"),
    "connectionsActive": MessageLookupByLibrary.simpleMessage("Active"),
    "connectionsAllProcesses": MessageLookupByLibrary.simpleMessage(
      "All processes",
    ),
    "connectionsAscending": MessageLookupByLibrary.simpleMessage("Ascending"),
    "connectionsClassicMode": MessageLookupByLibrary.simpleMessage("Classic"),
    "connectionsClearClosed": MessageLookupByLibrary.simpleMessage(
      "Clear closed",
    ),
    "connectionsCloseFiltered": MessageLookupByLibrary.simpleMessage(
      "Close filtered active connections",
    ),
    "connectionsClosed": MessageLookupByLibrary.simpleMessage("Closed"),
    "connectionsDesc": MessageLookupByLibrary.simpleMessage(
      "View current connections data",
    ),
    "connectionsDescending": MessageLookupByLibrary.simpleMessage("Descending"),
    "connectionsDestination": MessageLookupByLibrary.simpleMessage(
      "Destination",
    ),
    "connectionsDestinationGeo": MessageLookupByLibrary.simpleMessage(
      "Destination GeoIP",
    ),
    "connectionsDetail": MessageLookupByLibrary.simpleMessage(
      "Connection details",
    ),
    "connectionsDnsMode": MessageLookupByLibrary.simpleMessage("DNS mode"),
    "connectionsDownloadSpeed": MessageLookupByLibrary.simpleMessage(
      "Download speed",
    ),
    "connectionsEstablished": MessageLookupByLibrary.simpleMessage(
      "Established",
    ),
    "connectionsFilterHint": MessageLookupByLibrary.simpleMessage(
      "Filter process, host, IP, proxy or rule",
    ),
    "connectionsHost": MessageLookupByLibrary.simpleMessage("Host"),
    "connectionsInbound": MessageLookupByLibrary.simpleMessage("Inbound"),
    "connectionsInboundName": MessageLookupByLibrary.simpleMessage(
      "Inbound name",
    ),
    "connectionsInboundUser": MessageLookupByLibrary.simpleMessage(
      "Inbound user",
    ),
    "connectionsListView": MessageLookupByLibrary.simpleMessage("List view"),
    "connectionsLog": MessageLookupByLibrary.simpleMessage("Log"),
    "connectionsMemory": MessageLookupByLibrary.simpleMessage("Memory"),
    "connectionsOther": MessageLookupByLibrary.simpleMessage("Other"),
    "connectionsPause": MessageLookupByLibrary.simpleMessage("Pause updates"),
    "connectionsPaused": MessageLookupByLibrary.simpleMessage(
      "Connection list updates are paused",
    ),
    "connectionsProcess": MessageLookupByLibrary.simpleMessage("Process"),
    "connectionsProcessMode": MessageLookupByLibrary.simpleMessage(
      "By process",
    ),
    "connectionsProcessPath": MessageLookupByLibrary.simpleMessage(
      "Process path",
    ),
    "connectionsProxyChain": MessageLookupByLibrary.simpleMessage(
      "Proxy chain",
    ),
    "connectionsRefreshInterval": MessageLookupByLibrary.simpleMessage(
      "Refresh interval",
    ),
    "connectionsRefreshIntervalDesc": MessageLookupByLibrary.simpleMessage(
      "100–10000 ms; lower values use more CPU",
    ),
    "connectionsRemoteDestination": MessageLookupByLibrary.simpleMessage(
      "Remote destination",
    ),
    "connectionsRequestLog": MessageLookupByLibrary.simpleMessage(
      "Request records",
    ),
    "connectionsResetColumns": MessageLookupByLibrary.simpleMessage(
      "Reset columns",
    ),
    "connectionsResume": MessageLookupByLibrary.simpleMessage("Resume updates"),
    "connectionsRouting": MessageLookupByLibrary.simpleMessage("Routing"),
    "connectionsRule": MessageLookupByLibrary.simpleMessage("Rule"),
    "connectionsRulePayload": MessageLookupByLibrary.simpleMessage(
      "Rule payload",
    ),
    "connectionsSettings": MessageLookupByLibrary.simpleMessage(
      "Connection settings",
    ),
    "connectionsShowIcons": MessageLookupByLibrary.simpleMessage(
      "Show application icons",
    ),
    "connectionsSniffHost": MessageLookupByLibrary.simpleMessage(
      "Sniffed host",
    ),
    "connectionsSource": MessageLookupByLibrary.simpleMessage("Source"),
    "connectionsSourceGeo": MessageLookupByLibrary.simpleMessage(
      "Source GeoIP",
    ),
    "connectionsTableColumns": MessageLookupByLibrary.simpleMessage(
      "Table columns",
    ),
    "connectionsTableView": MessageLookupByLibrary.simpleMessage("Table view"),
    "connectionsTotalDownload": MessageLookupByLibrary.simpleMessage(
      "Total download",
    ),
    "connectionsTotalUpload": MessageLookupByLibrary.simpleMessage(
      "Total upload",
    ),
    "connectionsTraffic": MessageLookupByLibrary.simpleMessage("Traffic"),
    "connectionsType": MessageLookupByLibrary.simpleMessage("Type"),
    "connectionsUid": MessageLookupByLibrary.simpleMessage("UID"),
    "connectionsUploadSpeed": MessageLookupByLibrary.simpleMessage(
      "Upload speed",
    ),
    "connectionsUseApplicationName": MessageLookupByLibrary.simpleMessage(
      "Prefer application name",
    ),
    "connectivity": MessageLookupByLibrary.simpleMessage("Connectivity："),
    "contactMe": MessageLookupByLibrary.simpleMessage("Contact me"),
    "content": MessageLookupByLibrary.simpleMessage("Content"),
    "contentScheme": MessageLookupByLibrary.simpleMessage("Content"),
    "copy": MessageLookupByLibrary.simpleMessage("Copy"),
    "copyEnvVar": MessageLookupByLibrary.simpleMessage(
      "Copying environment variables",
    ),
    "copyLink": MessageLookupByLibrary.simpleMessage("Copy link"),
    "copySuccess": MessageLookupByLibrary.simpleMessage("Copy success"),
    "core": MessageLookupByLibrary.simpleMessage("Core"),
    "coreInfo": MessageLookupByLibrary.simpleMessage("Core info"),
    "coreStatusRestarting": MessageLookupByLibrary.simpleMessage("Restarting"),
    "coreStatusRunning": MessageLookupByLibrary.simpleMessage("Running"),
    "coreStatusStopped": MessageLookupByLibrary.simpleMessage("Stopped"),
    "coreUpdate": MessageLookupByLibrary.simpleMessage("Core update"),
    "coreUpdateAvailable": MessageLookupByLibrary.simpleMessage(
      "Core update available",
    ),
    "coreUpdateChecking": MessageLookupByLibrary.simpleMessage(
      "Checking for updates...",
    ),
    "coreUpdateDownloading": MessageLookupByLibrary.simpleMessage(
      "Downloading...",
    ),
    "coreUpdateFailed": MessageLookupByLibrary.simpleMessage("Update failed"),
    "coreUpdateSuccess": MessageLookupByLibrary.simpleMessage(
      "Core updated successfully",
    ),
    "country": MessageLookupByLibrary.simpleMessage("Country"),
    "crashTest": MessageLookupByLibrary.simpleMessage("Crash test"),
    "crashlytics": MessageLookupByLibrary.simpleMessage("Crash reports"),
    "crashlyticsDesc": MessageLookupByLibrary.simpleMessage(
      "Automatically upload crash logs via Firebase Crashlytics; no sensitive data is included",
    ),
    "create": MessageLookupByLibrary.simpleMessage("Create"),
    "cut": MessageLookupByLibrary.simpleMessage("Cut"),
    "dark": MessageLookupByLibrary.simpleMessage("Dark"),
    "dashboard": MessageLookupByLibrary.simpleMessage("Dashboard"),
    "dashboardAnnouncementBadge": MessageLookupByLibrary.simpleMessage(
      "Notice",
    ),
    "dashboardClickUpdateSubscription": MessageLookupByLibrary.simpleMessage(
      "Click to update subscription",
    ),
    "dashboardContactSupport": MessageLookupByLibrary.simpleMessage("Support"),
    "dashboardCurrentNodeLabel": m0,
    "dashboardHwidNotSupported": MessageLookupByLibrary.simpleMessage(
      "HWID binding is not enabled on this server",
    ),
    "dashboardNotSyncedYet": MessageLookupByLibrary.simpleMessage(
      "Synced: Not yet",
    ),
    "dashboardRuleOverrideCount": m1,
    "dashboardTotalNodesCount": m2,
    "day": MessageLookupByLibrary.simpleMessage("day"),
    "days": MessageLookupByLibrary.simpleMessage("days"),
    "daysGenitive": MessageLookupByLibrary.simpleMessage("days"),
    "defaultNameserver": MessageLookupByLibrary.simpleMessage(
      "Default nameserver",
    ),
    "defaultNameserverDesc": MessageLookupByLibrary.simpleMessage(
      "For resolving DNS server",
    ),
    "defaultProxyAutoTarget": MessageLookupByLibrary.simpleMessage(
      "Default Proxy (Auto-adapt)",
    ),
    "defaultSort": MessageLookupByLibrary.simpleMessage("Sort by default"),
    "defaultText": MessageLookupByLibrary.simpleMessage("Default"),
    "delay": MessageLookupByLibrary.simpleMessage("Delay"),
    "delaySort": MessageLookupByLibrary.simpleMessage("Sort by delay"),
    "delete": MessageLookupByLibrary.simpleMessage("Delete"),
    "deleteMultipTip": m3,
    "deleteTip": m4,
    "desc": MessageLookupByLibrary.simpleMessage(
      "A multi-platform proxy client based on ClashMeta, simple and easy to use, open-source and ad-free.",
    ),
    "detectionTip": MessageLookupByLibrary.simpleMessage(
      "Relying on third-party api is for reference only",
    ),
    "determiningIp": MessageLookupByLibrary.simpleMessage("Determining IP..."),
    "developerMode": MessageLookupByLibrary.simpleMessage("Developer mode"),
    "developerModeEnableTip": MessageLookupByLibrary.simpleMessage(
      "Developer mode is enabled.",
    ),
    "direct": MessageLookupByLibrary.simpleMessage("Direct"),
    "disclaimer": MessageLookupByLibrary.simpleMessage("Disclaimer"),
    "disclaimerDesc": MessageLookupByLibrary.simpleMessage(
      "This software is only used for non-commercial purposes such as learning exchanges and scientific research. It is strictly prohibited to use this software for commercial purposes. Any commercial activity, if any, has nothing to do with this software.",
    ),
    "discoverNewVersion": MessageLookupByLibrary.simpleMessage(
      "Discover the new version",
    ),
    "discovery": MessageLookupByLibrary.simpleMessage(
      "Discovery a new version",
    ),
    "dnsDesc": MessageLookupByLibrary.simpleMessage(
      "Update DNS related settings",
    ),
    "dnsMode": MessageLookupByLibrary.simpleMessage("DNS mode"),
    "doYouWantToPass": MessageLookupByLibrary.simpleMessage(
      "Adding profile from",
    ),
    "domain": MessageLookupByLibrary.simpleMessage("Domain"),
    "download": MessageLookupByLibrary.simpleMessage("Download"),
    "downloadingZashboard": MessageLookupByLibrary.simpleMessage(
      "Downloading Zashboard…",
    ),
    "edit": MessageLookupByLibrary.simpleMessage("Edit"),
    "emptyTip": m5,
    "en": MessageLookupByLibrary.simpleMessage("English"),
    "enableGlobalOverride": MessageLookupByLibrary.simpleMessage(
      "Enable Global Override",
    ),
    "enableOverride": MessageLookupByLibrary.simpleMessage("Enable override"),
    "entries": MessageLookupByLibrary.simpleMessage(" entries"),
    "errorTitle": MessageLookupByLibrary.simpleMessage("Error"),
    "exclude": MessageLookupByLibrary.simpleMessage("Hidden from recent tasks"),
    "excludeDesc": MessageLookupByLibrary.simpleMessage(
      "When the app is in the background, the app is hidden from the recent task",
    ),
    "excludeFromVpn": MessageLookupByLibrary.simpleMessage("Exclude from VPN"),
    "existsTip": m6,
    "exit": MessageLookupByLibrary.simpleMessage("Exit"),
    "expand": MessageLookupByLibrary.simpleMessage("Standard"),
    "expandAll": MessageLookupByLibrary.simpleMessage("Expand all"),
    "expertMode": MessageLookupByLibrary.simpleMessage("Expert Mode"),
    "expirationTime": MessageLookupByLibrary.simpleMessage("Expiration time"),
    "expiresOn": MessageLookupByLibrary.simpleMessage("Expires on"),
    "exportFile": MessageLookupByLibrary.simpleMessage("Export file"),
    "exportLogs": MessageLookupByLibrary.simpleMessage("Export logs"),
    "exportSuccess": MessageLookupByLibrary.simpleMessage("Export Success"),
    "expressiveScheme": MessageLookupByLibrary.simpleMessage("Expressive"),
    "externalController": MessageLookupByLibrary.simpleMessage(
      "ExternalController",
    ),
    "externalControllerDesc": MessageLookupByLibrary.simpleMessage(
      "Once enabled, the Clash kernel can be controlled on port 9090",
    ),
    "externalLink": MessageLookupByLibrary.simpleMessage("External link"),
    "externalResources": MessageLookupByLibrary.simpleMessage(
      "External resources",
    ),
    "fakeipFilter": MessageLookupByLibrary.simpleMessage("Fakeip filter"),
    "fakeipRange": MessageLookupByLibrary.simpleMessage("Fakeip range"),
    "fallback": MessageLookupByLibrary.simpleMessage("Fallback"),
    "fallbackDesc": MessageLookupByLibrary.simpleMessage(
      "Generally use offshore DNS",
    ),
    "fallbackFilter": MessageLookupByLibrary.simpleMessage("Fallback filter"),
    "fidelityScheme": MessageLookupByLibrary.simpleMessage("Fidelity"),
    "file": MessageLookupByLibrary.simpleMessage("File"),
    "fileDesc": MessageLookupByLibrary.simpleMessage("Directly upload profile"),
    "fileIsUpdate": MessageLookupByLibrary.simpleMessage(
      "The file has been modified. Do you want to save the changes?",
    ),
    "fileTooLarge": MessageLookupByLibrary.simpleMessage("File is too large"),
    "filterSystemApp": MessageLookupByLibrary.simpleMessage(
      "Filter system app",
    ),
    "findProcessMode": MessageLookupByLibrary.simpleMessage("Find process"),
    "findProcessModeDesc": MessageLookupByLibrary.simpleMessage(
      "There is a certain performance loss after opening",
    ),
    "fontFamily": MessageLookupByLibrary.simpleMessage("FontFamily"),
    "fourColumns": MessageLookupByLibrary.simpleMessage("Four columns"),
    "fruitSaladScheme": MessageLookupByLibrary.simpleMessage("FruitSalad"),
    "general": MessageLookupByLibrary.simpleMessage("General"),
    "generalDesc": MessageLookupByLibrary.simpleMessage(
      "Modify general settings",
    ),
    "geoData": MessageLookupByLibrary.simpleMessage("GeoData"),
    "geodataLoader": MessageLookupByLibrary.simpleMessage(
      "Geo Low Memory Mode",
    ),
    "geodataLoaderDesc": MessageLookupByLibrary.simpleMessage(
      "Enabling will use the Geo low memory loader",
    ),
    "geoipCode": MessageLookupByLibrary.simpleMessage("Geoip code"),
    "getOriginRules": MessageLookupByLibrary.simpleMessage(
      "Get original rules",
    ),
    "global": MessageLookupByLibrary.simpleMessage("Global"),
    "globalOverride": MessageLookupByLibrary.simpleMessage(
      "Global Rule Override",
    ),
    "globalOverrideDesc": MessageLookupByLibrary.simpleMessage(
      "Persists across all profiles without re-editing on switch or update",
    ),
    "go": MessageLookupByLibrary.simpleMessage("Go"),
    "goDownload": MessageLookupByLibrary.simpleMessage("Go to download"),
    "goToPurchasePrompt": MessageLookupByLibrary.simpleMessage(
      "No subscription yet? Buy or Redeem",
    ),
    "goToSelected": MessageLookupByLibrary.simpleMessage("Go to selected"),
    "gratitude": MessageLookupByLibrary.simpleMessage("Gratitude"),
    "hasCacheChange": MessageLookupByLibrary.simpleMessage(
      "Do you want to cache the changes?",
    ),
    "healthActionOpenDns": MessageLookupByLibrary.simpleMessage("DNS Settings"),
    "healthActionOpenNetwork": MessageLookupByLibrary.simpleMessage(
      "Network Settings",
    ),
    "healthActionOpenProfiles": MessageLookupByLibrary.simpleMessage(
      "Open Profiles",
    ),
    "healthActionOpenProxies": MessageLookupByLibrary.simpleMessage(
      "Switch Node",
    ),
    "healthActionOpenPurchase": MessageLookupByLibrary.simpleMessage(
      "Renew / Redeem",
    ),
    "healthActionOpenTun": MessageLookupByLibrary.simpleMessage("TUN Settings"),
    "healthActionReapplySystemProxy": MessageLookupByLibrary.simpleMessage(
      "Restore System Proxy",
    ),
    "healthActionRestartCore": MessageLookupByLibrary.simpleMessage(
      "Restart Core",
    ),
    "healthActionStartProxy": MessageLookupByLibrary.simpleMessage(
      "Start Proxy",
    ),
    "healthCheckCancel": MessageLookupByLibrary.simpleMessage("Cancel"),
    "healthCheckChecking": MessageLookupByLibrary.simpleMessage("Checking…"),
    "healthCheckCopied": MessageLookupByLibrary.simpleMessage(
      "Diagnostic summary copied",
    ),
    "healthCheckCopySummary": MessageLookupByLibrary.simpleMessage(
      "Copy Summary",
    ),
    "healthCheckDiagnoseAction": MessageLookupByLibrary.simpleMessage(
      "Diagnose",
    ),
    "healthCheckExport": MessageLookupByLibrary.simpleMessage("Export Report"),
    "healthCheckExportDialogTitle": MessageLookupByLibrary.simpleMessage(
      "Export Redacted Health Report",
    ),
    "healthCheckExportFailed": MessageLookupByLibrary.simpleMessage(
      "Failed to export report",
    ),
    "healthCheckExportSuccess": MessageLookupByLibrary.simpleMessage(
      "Diagnostic report exported",
    ),
    "healthCheckLastChecked": m7,
    "healthCheckPrivacyNote": MessageLookupByLibrary.simpleMessage(
      "Exports contain only status codes and timings — never node names, IPs, URLs, or logs.",
    ),
    "healthCheckRecheck": MessageLookupByLibrary.simpleMessage("Re-check"),
    "healthCheckSubtitle": MessageLookupByLibrary.simpleMessage(
      "Inspect profile, core, traffic capture, and live connectivity",
    ),
    "healthCheckTitle": MessageLookupByLibrary.simpleMessage("Health Check"),
    "healthDetailCancelled": MessageLookupByLibrary.simpleMessage("Cancelled"),
    "healthDetailCoreDelayBusy": MessageLookupByLibrary.simpleMessage(
      "Delay test slots busy; retry shortly",
    ),
    "healthDetailCoreFailed": MessageLookupByLibrary.simpleMessage(
      "Core control interface failed or timed out",
    ),
    "healthDetailCoreHealthy": m8,
    "healthDetailCoreSlow": MessageLookupByLibrary.simpleMessage(
      "Core IPC response is slow (> 500 ms)",
    ),
    "healthDetailDirectFailed": MessageLookupByLibrary.simpleMessage(
      "Direct uplink failed; check Wi-Fi, router, or firewall",
    ),
    "healthDetailDirectMode": MessageLookupByLibrary.simpleMessage(
      "Direct mode is selected",
    ),
    "healthDetailDirectOk": MessageLookupByLibrary.simpleMessage(
      "Direct uplink reachable",
    ),
    "healthDetailDirectSlow": MessageLookupByLibrary.simpleMessage(
      "Direct uplink latency is high",
    ),
    "healthDetailDnsFailed": MessageLookupByLibrary.simpleMessage(
      "DNS lookup failed or timed out",
    ),
    "healthDetailDnsFakeIp": MessageLookupByLibrary.simpleMessage(
      "Core DNS (fake-ip)",
    ),
    "healthDetailDnsOk": MessageLookupByLibrary.simpleMessage("Resolved"),
    "healthDetailDnsPoisoned": MessageLookupByLibrary.simpleMessage(
      "DNS returned loopback/sinkhole IP",
    ),
    "healthDetailDnsStaleFakeIp": MessageLookupByLibrary.simpleMessage(
      "Stale Fake-IP cache detected while TUN is inactive",
    ),
    "healthDetailE2eBypassed": MessageLookupByLibrary.simpleMessage(
      "Reached internet, but connection bypassed Core",
    ),
    "healthDetailE2eDirectRule": MessageLookupByLibrary.simpleMessage(
      "Entered Core (matched DIRECT rule)",
    ),
    "healthDetailE2eFailed": MessageLookupByLibrary.simpleMessage(
      "All end-to-end exit probes failed",
    ),
    "healthDetailE2eVerified": m9,
    "healthDetailLocalProfile": MessageLookupByLibrary.simpleMessage(
      "Local file profile",
    ),
    "healthDetailNoProfile": MessageLookupByLibrary.simpleMessage(
      "No profile selected",
    ),
    "healthDetailOutboundDirectSelected": MessageLookupByLibrary.simpleMessage(
      "Selected target is DIRECT",
    ),
    "healthDetailOutboundFailed": m10,
    "healthDetailOutboundProbeFallbackOk": m11,
    "healthDetailOutboundRejectSelected": MessageLookupByLibrary.simpleMessage(
      "Selected target is REJECT",
    ),
    "healthDetailOutboundSlow": m12,
    "healthDetailProfileFileMissing": MessageLookupByLibrary.simpleMessage(
      "Profile YAML file is missing or empty",
    ),
    "healthDetailProxyRunning": MessageLookupByLibrary.simpleMessage("Running"),
    "healthDetailProxyStopped": MessageLookupByLibrary.simpleMessage("Stopped"),
    "healthDetailRuntimeMismatch": MessageLookupByLibrary.simpleMessage(
      "Current profile not yet applied to Core",
    ),
    "healthDetailRuntimeSynced": m13,
    "healthDetailSkipPrerequisite": MessageLookupByLibrary.simpleMessage(
      "Skipped due to earlier check",
    ),
    "healthDetailSkipProxyStopped": MessageLookupByLibrary.simpleMessage(
      "Skipped while proxy is stopped",
    ),
    "healthDetailSubDeviceLimit": MessageLookupByLibrary.simpleMessage(
      "Device limit reached",
    ),
    "healthDetailSubExhausted": MessageLookupByLibrary.simpleMessage(
      "Traffic quota exhausted",
    ),
    "healthDetailSubExpired": MessageLookupByLibrary.simpleMessage(
      "Subscription expired",
    ),
    "healthDetailSubExpiringSoon": m14,
    "healthDetailSubHealthy": MessageLookupByLibrary.simpleMessage(
      "Subscription active",
    ),
    "healthDetailSubHealthyEternal": MessageLookupByLibrary.simpleMessage(
      "Lifetime · Unlimited",
    ),
    "healthDetailSubNeverSynced": MessageLookupByLibrary.simpleMessage(
      "Not synced yet; update subscription first",
    ),
    "healthDetailSubNoMeta": MessageLookupByLibrary.simpleMessage(
      "No quota metadata from server",
    ),
    "healthDetailSubTrafficLow": m15,
    "healthDetailSysProxyDisabled": MessageLookupByLibrary.simpleMessage(
      "Disabled in settings",
    ),
    "healthDetailSysProxyDisabledExternally":
        MessageLookupByLibrary.simpleMessage(
          "System proxy switch is turned off in OS",
        ),
    "healthDetailSysProxyHijacked": MessageLookupByLibrary.simpleMessage(
      "System proxy disabled or overwritten externally",
    ),
    "healthDetailSysProxyInvalidPort": MessageLookupByLibrary.simpleMessage(
      "Local mixed-port is disabled (0)",
    ),
    "healthDetailSysProxyNotApplied": MessageLookupByLibrary.simpleMessage(
      "System proxy has not been applied to OS yet",
    ),
    "healthDetailSysProxyReadFailed": MessageLookupByLibrary.simpleMessage(
      "Could not read system proxy settings",
    ),
    "healthDetailSysProxyUnexpectedPac": MessageLookupByLibrary.simpleMessage(
      "Residual PAC URL detected in system settings",
    ),
    "healthDetailSysProxyUnsupported": MessageLookupByLibrary.simpleMessage(
      "Not applicable on this platform",
    ),
    "healthDetailTakeoverBoth": MessageLookupByLibrary.simpleMessage(
      "TUN + System Proxy active",
    ),
    "healthDetailTakeoverNone": MessageLookupByLibrary.simpleMessage(
      "Neither TUN nor System Proxy is active",
    ),
    "healthDetailTakeoverPartial": MessageLookupByLibrary.simpleMessage(
      "Only one enabled capture mode is active",
    ),
    "healthDetailTakeoverSysProxy": MessageLookupByLibrary.simpleMessage(
      "Captured via System Proxy",
    ),
    "healthDetailTakeoverTun": MessageLookupByLibrary.simpleMessage(
      "Captured via TUN adapter",
    ),
    "healthDetailTunBypassedSystemProxyOk":
        MessageLookupByLibrary.simpleMessage(
          "TUN path failed; verified via System Proxy",
        ),
    "healthDetailTunDisabled": MessageLookupByLibrary.simpleMessage(
      "Disabled in settings",
    ),
    "healthDetailTunReady": MessageLookupByLibrary.simpleMessage(
      "Virtual adapter active",
    ),
    "healthDetailTunReadyElevated": MessageLookupByLibrary.simpleMessage(
      "Active · Elevated",
    ),
    "healthExitCountryPart": m16,
    "healthItemCoreResponsive": MessageLookupByLibrary.simpleMessage(
      "Core Responsiveness",
    ),
    "healthItemDirect": MessageLookupByLibrary.simpleMessage(
      "Local Direct Uplink",
    ),
    "healthItemDns": MessageLookupByLibrary.simpleMessage("DNS Resolution"),
    "healthItemEndToEnd": MessageLookupByLibrary.simpleMessage(
      "End-to-End Verification",
    ),
    "healthItemOutbound": MessageLookupByLibrary.simpleMessage(
      "Active Outbound Node",
    ),
    "healthItemProfileSelected": MessageLookupByLibrary.simpleMessage(
      "Active Profile",
    ),
    "healthItemProxyStarted": MessageLookupByLibrary.simpleMessage(
      "Proxy State",
    ),
    "healthItemRuntimeConfig": MessageLookupByLibrary.simpleMessage(
      "Runtime Config",
    ),
    "healthItemSubscription": MessageLookupByLibrary.simpleMessage(
      "Subscription Status",
    ),
    "healthItemSystemProxy": MessageLookupByLibrary.simpleMessage(
      "System Proxy",
    ),
    "healthItemTrafficTakeover": MessageLookupByLibrary.simpleMessage(
      "Capture Summary",
    ),
    "healthItemTunTakeover": MessageLookupByLibrary.simpleMessage(
      "TUN Virtual Adapter",
    ),
    "healthLayerConfig": MessageLookupByLibrary.simpleMessage(
      "Profile & Subscription",
    ),
    "healthLayerCore": MessageLookupByLibrary.simpleMessage("Proxy Core"),
    "healthLayerNetwork": MessageLookupByLibrary.simpleMessage("Network Path"),
    "healthLayerTakeover": MessageLookupByLibrary.simpleMessage(
      "Traffic Capture",
    ),
    "healthStatusFailed": MessageLookupByLibrary.simpleMessage("Failed"),
    "healthStatusPassed": MessageLookupByLibrary.simpleMessage("Passed"),
    "healthStatusRunning": MessageLookupByLibrary.simpleMessage("Checking"),
    "healthStatusSkipped": MessageLookupByLibrary.simpleMessage("Skipped"),
    "healthStatusTimeout": MessageLookupByLibrary.simpleMessage("Timeout"),
    "healthStatusWarning": MessageLookupByLibrary.simpleMessage("Warning"),
    "healthVerdictCancelledTitle": MessageLookupByLibrary.simpleMessage(
      "Health check cancelled",
    ),
    "healthVerdictCheckingTitle": MessageLookupByLibrary.simpleMessage(
      "Checking connection layers…",
    ),
    "healthVerdictCoreUnresponsive": MessageLookupByLibrary.simpleMessage(
      "Proxy core is unresponsive",
    ),
    "healthVerdictDnsFailed": MessageLookupByLibrary.simpleMessage(
      "DNS resolution failed or returned sinkhole address",
    ),
    "healthVerdictEndToEndFailed": MessageLookupByLibrary.simpleMessage(
      "End-to-end exit check failed; try switching nodes",
    ),
    "healthVerdictHealthyDirectSubtitle": m17,
    "healthVerdictHealthySubtitle": m18,
    "healthVerdictHealthyTitle": MessageLookupByLibrary.simpleMessage(
      "Connection Healthy",
    ),
    "healthVerdictLocalNetworkDown": MessageLookupByLibrary.simpleMessage(
      "Local network is unreachable (unrelated to proxy node)",
    ),
    "healthVerdictOutboundFailed": MessageLookupByLibrary.simpleMessage(
      "Local network is OK, but active proxy node failed",
    ),
    "healthVerdictProfileMissing": MessageLookupByLibrary.simpleMessage(
      "No valid profile selected or file is missing",
    ),
    "healthVerdictProxyNotStarted": MessageLookupByLibrary.simpleMessage(
      "Proxy is stopped; traffic goes direct",
    ),
    "healthVerdictSubscriptionExhausted": MessageLookupByLibrary.simpleMessage(
      "Subscription traffic is exhausted",
    ),
    "healthVerdictSubscriptionExpired": MessageLookupByLibrary.simpleMessage(
      "Subscription has expired",
    ),
    "healthVerdictTakeoverFailed": MessageLookupByLibrary.simpleMessage(
      "Traffic capture inactive; check TUN or system proxy",
    ),
    "healthVerdictTrafficBypassed": MessageLookupByLibrary.simpleMessage(
      "Probe reached internet without traversing proxy core",
    ),
    "healthVerdictTunBypassedTitle": MessageLookupByLibrary.simpleMessage(
      "TUN capture failed; only System Proxy is working",
    ),
    "healthVerdictWarningsTitle": MessageLookupByLibrary.simpleMessage(
      "Connected with warnings",
    ),
    "hostsDesc": MessageLookupByLibrary.simpleMessage("Add Hosts"),
    "hotkeyConflict": MessageLookupByLibrary.simpleMessage("Hotkey conflict"),
    "hotkeyManagement": MessageLookupByLibrary.simpleMessage(
      "Hotkey Management",
    ),
    "hotkeyManagementDesc": MessageLookupByLibrary.simpleMessage(
      "Use keyboard to control applications",
    ),
    "hour": MessageLookupByLibrary.simpleMessage("hour"),
    "hours": MessageLookupByLibrary.simpleMessage("Hours"),
    "hoursGenitive": MessageLookupByLibrary.simpleMessage("hours"),
    "hoursPlural": MessageLookupByLibrary.simpleMessage("hours"),
    "hwidNotSupported": MessageLookupByLibrary.simpleMessage(
      "HWID binding is not supported on this platform.",
    ),
    "icon": MessageLookupByLibrary.simpleMessage("Icon"),
    "iconConfiguration": MessageLookupByLibrary.simpleMessage(
      "Icon configuration",
    ),
    "iconStyle": MessageLookupByLibrary.simpleMessage("Icon style"),
    "import": MessageLookupByLibrary.simpleMessage("Import"),
    "importFile": MessageLookupByLibrary.simpleMessage("Import from file"),
    "importFromURL": MessageLookupByLibrary.simpleMessage(
      "Paste subscription link and tap Confirm",
    ),
    "importUrl": MessageLookupByLibrary.simpleMessage("Import from URL"),
    "includeInVpn": MessageLookupByLibrary.simpleMessage("Include in VPN"),
    "infiniteTime": MessageLookupByLibrary.simpleMessage("Long term effective"),
    "init": MessageLookupByLibrary.simpleMessage("Init"),
    "inputCorrectHotkey": MessageLookupByLibrary.simpleMessage(
      "Please enter the correct hotkey",
    ),
    "intelligentSelected": MessageLookupByLibrary.simpleMessage(
      "Intelligent selection",
    ),
    "internet": MessageLookupByLibrary.simpleMessage("Internet"),
    "interval": MessageLookupByLibrary.simpleMessage("Interval"),
    "intranetIP": MessageLookupByLibrary.simpleMessage("Intranet IP"),
    "invalidQrMessage": MessageLookupByLibrary.simpleMessage("Invalid QR code"),
    "ipcidr": MessageLookupByLibrary.simpleMessage("Ipcidr"),
    "ipv6Desc": MessageLookupByLibrary.simpleMessage(
      "When turned on it will be able to receive IPv6 traffic",
    ),
    "ipv6InboundDesc": MessageLookupByLibrary.simpleMessage(
      "Allow IPv6 inbound",
    ),
    "ja": MessageLookupByLibrary.simpleMessage("Japanese"),
    "just": MessageLookupByLibrary.simpleMessage("Just"),
    "keepAliveIntervalDesc": MessageLookupByLibrary.simpleMessage(
      "Tcp keep alive interval",
    ),
    "key": MessageLookupByLibrary.simpleMessage("Key"),
    "language": MessageLookupByLibrary.simpleMessage("Language"),
    "layout": MessageLookupByLibrary.simpleMessage("Layout"),
    "light": MessageLookupByLibrary.simpleMessage("Light"),
    "list": MessageLookupByLibrary.simpleMessage("List"),
    "listen": MessageLookupByLibrary.simpleMessage("Listen"),
    "local": MessageLookupByLibrary.simpleMessage("Local"),
    "localBackupDesc": MessageLookupByLibrary.simpleMessage(
      "Backup local data to local",
    ),
    "localRecoveryDesc": MessageLookupByLibrary.simpleMessage(
      "Recovery data from file",
    ),
    "localSplitMode": MessageLookupByLibrary.simpleMessage(
      "Domestic & LAN Local Split",
    ),
    "localSplitModeDesc": MessageLookupByLibrary.simpleMessage(
      "Automatically bypass domestic & LAN traffic when subscription lacks routing rules",
    ),
    "localSplitMode_always": MessageLookupByLibrary.simpleMessage(
      "Always Add Domestic Direct",
    ),
    "localSplitMode_auto": MessageLookupByLibrary.simpleMessage(
      "Smart Bare-Profile Detection (Auto)",
    ),
    "localSplitMode_off": MessageLookupByLibrary.simpleMessage("Off"),
    "locations": MessageLookupByLibrary.simpleMessage("Locations"),
    "logLevel": MessageLookupByLibrary.simpleMessage("LogLevel"),
    "logcat": MessageLookupByLibrary.simpleMessage("Logcat"),
    "logcatDesc": MessageLookupByLibrary.simpleMessage(
      "Disabling will hide the log entry",
    ),
    "logs": MessageLookupByLibrary.simpleMessage("Logs"),
    "logsDesc": MessageLookupByLibrary.simpleMessage("Log capture records"),
    "logsTest": MessageLookupByLibrary.simpleMessage("Logs test"),
    "loopback": MessageLookupByLibrary.simpleMessage("Loopback unlock tool"),
    "loopbackDesc": MessageLookupByLibrary.simpleMessage(
      "Used for UWP loopback unlocking",
    ),
    "loose": MessageLookupByLibrary.simpleMessage("Loose"),
    "managedByProvider": MessageLookupByLibrary.simpleMessage(
      "These settings are managed by your provider",
    ),
    "managedByProviderNetwork": MessageLookupByLibrary.simpleMessage(
      "These parameters are managed by your provider",
    ),
    "memoryInfo": MessageLookupByLibrary.simpleMessage("Memory info"),
    "messageTest": MessageLookupByLibrary.simpleMessage("Message test"),
    "messageTestTip": MessageLookupByLibrary.simpleMessage(
      "This is a message.",
    ),
    "min": MessageLookupByLibrary.simpleMessage("Min"),
    "minimizeOnExit": MessageLookupByLibrary.simpleMessage("Minimize on exit"),
    "minimizeOnExitDesc": MessageLookupByLibrary.simpleMessage(
      "Modify the default system exit event",
    ),
    "minutes": MessageLookupByLibrary.simpleMessage("Minutes"),
    "mixedPort": MessageLookupByLibrary.simpleMessage("Mixed Port"),
    "mode": MessageLookupByLibrary.simpleMessage("Mode"),
    "monochromeScheme": MessageLookupByLibrary.simpleMessage("Monochrome"),
    "months": MessageLookupByLibrary.simpleMessage("Months"),
    "more": MessageLookupByLibrary.simpleMessage("More"),
    "name": MessageLookupByLibrary.simpleMessage("Name"),
    "nameSort": MessageLookupByLibrary.simpleMessage("Sort by name"),
    "nameserver": MessageLookupByLibrary.simpleMessage("Nameserver"),
    "nameserverDesc": MessageLookupByLibrary.simpleMessage(
      "For resolving domain",
    ),
    "nameserverPolicy": MessageLookupByLibrary.simpleMessage(
      "Nameserver policy",
    ),
    "nameserverPolicyDesc": MessageLookupByLibrary.simpleMessage(
      "Specify the corresponding nameserver policy",
    ),
    "network": MessageLookupByLibrary.simpleMessage("Network"),
    "networkDesc": MessageLookupByLibrary.simpleMessage(
      "Modify network-related settings",
    ),
    "networkDetection": MessageLookupByLibrary.simpleMessage("Your IP Address"),
    "networkSpeed": MessageLookupByLibrary.simpleMessage("Network speed"),
    "neutralScheme": MessageLookupByLibrary.simpleMessage("Neutral"),
    "newDashboard": MessageLookupByLibrary.simpleMessage("Concise mode"),
    "noData": MessageLookupByLibrary.simpleMessage("No data"),
    "noHotKey": MessageLookupByLibrary.simpleMessage("No HotKey"),
    "noIcon": MessageLookupByLibrary.simpleMessage("None"),
    "noInfo": MessageLookupByLibrary.simpleMessage("No info"),
    "noMoreInfoDesc": MessageLookupByLibrary.simpleMessage("No more info"),
    "noNetwork": MessageLookupByLibrary.simpleMessage("No network"),
    "noNetworkApp": MessageLookupByLibrary.simpleMessage("No network APP"),
    "noProxy": MessageLookupByLibrary.simpleMessage("No proxy"),
    "noProxyDesc": MessageLookupByLibrary.simpleMessage(
      "Please create a profile or add a valid profile",
    ),
    "noResolve": MessageLookupByLibrary.simpleMessage("No resolve IP"),
    "nodeOverviewActive": MessageLookupByLibrary.simpleMessage("Active"),
    "nodeOverviewAddSubscription": MessageLookupByLibrary.simpleMessage(
      "Add subscription",
    ),
    "nodeOverviewAllHealthCounts": m19,
    "nodeOverviewAllProfiles": MessageLookupByLibrary.simpleMessage(
      "All profiles",
    ),
    "nodeOverviewAllProfilesCount": m20,
    "nodeOverviewAmbiguousNode": MessageLookupByLibrary.simpleMessage(
      "Duplicate node definitions; identity could not be verified",
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
      "No tested available nodes right now (untested or all timed out)",
    ),
    "nodeOverviewAvailableOnly": MessageLookupByLibrary.simpleMessage(
      "Available only",
    ),
    "nodeOverviewBandFailed": m29,
    "nodeOverviewBandFast": m30,
    "nodeOverviewBandSlow": m31,
    "nodeOverviewBandUntested": m32,
    "nodeOverviewBatchSummary": m33,
    "nodeOverviewChainUnsupported": MessageLookupByLibrary.simpleMessage(
      "Proxy chains cannot be tested in isolation",
    ),
    "nodeOverviewCurrentActiveProfile": m34,
    "nodeOverviewCurrentProfile": MessageLookupByLibrary.simpleMessage(
      "Current profile",
    ),
    "nodeOverviewDeviceLimitReached": MessageLookupByLibrary.simpleMessage(
      "Device limit reached",
    ),
    "nodeOverviewEmptyStepsHint": MessageLookupByLibrary.simpleMessage(
      "① Add subscription  ·  ② Auto speedtest  ·  ③ Connect fastest",
    ),
    "nodeOverviewEmptySubtitle": MessageLookupByLibrary.simpleMessage(
      "Paste your subscription link and confirm to auto-test and connect to the fastest node",
    ),
    "nodeOverviewEmptyTitle": MessageLookupByLibrary.simpleMessage(
      "No subscription profile yet",
    ),
    "nodeOverviewExpireAt": m35,
    "nodeOverviewExpireDaysLeft": m36,
    "nodeOverviewExpireHoursLeft": m37,
    "nodeOverviewExpireSoon": MessageLookupByLibrary.simpleMessage("< 1h left"),
    "nodeOverviewExpired": MessageLookupByLibrary.simpleMessage(
      "Subscription expired",
    ),
    "nodeOverviewExpiredCountBadge": m38,
    "nodeOverviewExpiringSoonCountBadge": m39,
    "nodeOverviewFileMissing": MessageLookupByLibrary.simpleMessage(
      "Profile file is missing",
    ),
    "nodeOverviewFileSource": m40,
    "nodeOverviewGlobalMedian": m41,
    "nodeOverviewGlobalMedianAndBest": m42,
    "nodeOverviewHealthCapacityExceeded": MessageLookupByLibrary.simpleMessage(
      "History storage is full; some results were not saved",
    ),
    "nodeOverviewHealthCounts": m43,
    "nodeOverviewHealthStoreUnavailable": MessageLookupByLibrary.simpleMessage(
      "Some delay results could not be saved",
    ),
    "nodeOverviewHistoryNotice": MessageLookupByLibrary.simpleMessage(
      "Delay results are kept until the next completed test. Test times appear below each node.",
    ),
    "nodeOverviewInUse": MessageLookupByLibrary.simpleMessage("In use"),
    "nodeOverviewIndependentTest": MessageLookupByLibrary.simpleMessage(
      "Independent delay test",
    ),
    "nodeOverviewLastActiveTest": m44,
    "nodeOverviewLastSync": m45,
    "nodeOverviewLastTest": m46,
    "nodeOverviewLive": MessageLookupByLibrary.simpleMessage("Live"),
    "nodeOverviewLocalProfile": MessageLookupByLibrary.simpleMessage(
      "Local file",
    ),
    "nodeOverviewLockedManualNode": m47,
    "nodeOverviewManageProfiles": MessageLookupByLibrary.simpleMessage(
      "Manage profiles / update subscription",
    ),
    "nodeOverviewManualSelectCompact": MessageLookupByLibrary.simpleMessage(
      "Fixed IP",
    ),
    "nodeOverviewManualSelectSubtitle": MessageLookupByLibrary.simpleMessage(
      "Fixed IP",
    ),
    "nodeOverviewManualSelectTitle": MessageLookupByLibrary.simpleMessage(
      "Manual Select",
    ),
    "nodeOverviewManualUpdate": MessageLookupByLibrary.simpleMessage(
      "Manual update",
    ),
    "nodeOverviewMedian": m48,
    "nodeOverviewMoreIssues": m49,
    "nodeOverviewNeverExpires": MessageLookupByLibrary.simpleMessage(
      "Expires: Never",
    ),
    "nodeOverviewNoActiveProfile": MessageLookupByLibrary.simpleMessage(
      "Active: None",
    ),
    "nodeOverviewNoNodes": MessageLookupByLibrary.simpleMessage(
      "No matching nodes",
    ),
    "nodeOverviewNodeUnidentified": MessageLookupByLibrary.simpleMessage(
      "Node could not be identified",
    ),
    "nodeOverviewParseFailed": MessageLookupByLibrary.simpleMessage(
      "Profile could not be parsed",
    ),
    "nodeOverviewPartialSummary": MessageLookupByLibrary.simpleMessage(
      "Summary includes loaded nodes only",
    ),
    "nodeOverviewPickerAvailableNodes": m50,
    "nodeOverviewPickerExpireDate": m51,
    "nodeOverviewPickerPerpetual": MessageLookupByLibrary.simpleMessage(
      "Never expires",
    ),
    "nodeOverviewPreviewUnsupported": MessageLookupByLibrary.simpleMessage(
      "Local provider nodes are not supported in this preview",
    ),
    "nodeOverviewProfileCountBadge": m52,
    "nodeOverviewProgress": m53,
    "nodeOverviewProviderDownloadFailed": MessageLookupByLibrary.simpleMessage(
      "Provider download failed",
    ),
    "nodeOverviewProviderNotCached": MessageLookupByLibrary.simpleMessage(
      "Provider cache is unavailable",
    ),
    "nodeOverviewProviderOptionsUnsupported":
        MessageLookupByLibrary.simpleMessage(
          "These provider options are not supported",
        ),
    "nodeOverviewProviderPending": m54,
    "nodeOverviewProviderTooLarge": MessageLookupByLibrary.simpleMessage(
      "Provider exceeds the size or node limit",
    ),
    "nodeOverviewProviderUnloaded": MessageLookupByLibrary.simpleMessage(
      "Provider nodes are not loaded yet. Testing all node delays reads them and downloads missing caches.",
    ),
    "nodeOverviewProviderUnsafePath": MessageLookupByLibrary.simpleMessage(
      "Provider file is outside the allowed directory",
    ),
    "nodeOverviewProviderUnsafeUrl": MessageLookupByLibrary.simpleMessage(
      "Provider URL does not meet safety requirements",
    ),
    "nodeOverviewProxyConnected": MessageLookupByLibrary.simpleMessage(
      "Proxy on · Traffic connected",
    ),
    "nodeOverviewProxyConnectedSmart": m55,
    "nodeOverviewProxyConnectedSmartWithNode": m56,
    "nodeOverviewProxyConnectedWithNode": m57,
    "nodeOverviewProxyDisconnected": MessageLookupByLibrary.simpleMessage(
      "Proxy off · Tap Turn on or Use on any node to connect",
    ),
    "nodeOverviewProxyStarting": MessageLookupByLibrary.simpleMessage(
      "Starting proxy…",
    ),
    "nodeOverviewProxyStopping": MessageLookupByLibrary.simpleMessage(
      "Stopping proxy…",
    ),
    "nodeOverviewQuickUse": MessageLookupByLibrary.simpleMessage(
      "Connect fastest",
    ),
    "nodeOverviewRemainingTraffic": m58,
    "nodeOverviewRuntimeSource": MessageLookupByLibrary.simpleMessage(
      "Runtime node",
    ),
    "nodeOverviewSelectProfileTitle": MessageLookupByLibrary.simpleMessage(
      "Switch profile",
    ),
    "nodeOverviewShowAllNodes": MessageLookupByLibrary.simpleMessage(
      "Show all nodes",
    ),
    "nodeOverviewSmartInUse": MessageLookupByLibrary.simpleMessage(
      "Smart active",
    ),
    "nodeOverviewSmartSelectCompact": MessageLookupByLibrary.simpleMessage(
      "Smart",
    ),
    "nodeOverviewSmartSelectSubtitle": MessageLookupByLibrary.simpleMessage(
      "Better experience",
    ),
    "nodeOverviewSmartSelectTitle": MessageLookupByLibrary.simpleMessage(
      "Smart Select",
    ),
    "nodeOverviewStale": MessageLookupByLibrary.simpleMessage(
      "May be outdated",
    ),
    "nodeOverviewStatusExpired": MessageLookupByLibrary.simpleMessage(
      "Expired",
    ),
    "nodeOverviewStrictUnsupported": MessageLookupByLibrary.simpleMessage(
      "Isolated tests are unavailable in strict mode",
    ),
    "nodeOverviewSwitchedToNode": m59,
    "nodeOverviewSwitchedToSmart": m60,
    "nodeOverviewSwitchedToSmartWithNode": m61,
    "nodeOverviewTestAll": MessageLookupByLibrary.simpleMessage(
      "Test all node delays",
    ),
    "nodeOverviewTestCurrent": MessageLookupByLibrary.simpleMessage(
      "Test current profile",
    ),
    "nodeOverviewTestFailed": MessageLookupByLibrary.simpleMessage(
      "Test failed",
    ),
    "nodeOverviewTestInterrupted": MessageLookupByLibrary.simpleMessage(
      "Test interrupted; earlier measurements were preserved",
    ),
    "nodeOverviewTestNode": MessageLookupByLibrary.simpleMessage("Delay test"),
    "nodeOverviewTestTimedOut": MessageLookupByLibrary.simpleMessage(
      "Test or provider read timed out",
    ),
    "nodeOverviewTestUnavailable": MessageLookupByLibrary.simpleMessage(
      "Could not start this test. Check the background component version and retry.",
    ),
    "nodeOverviewTooManyNodes": MessageLookupByLibrary.simpleMessage(
      "Too many nodes to display in this preview",
    ),
    "nodeOverviewTrafficUnlimited": MessageLookupByLibrary.simpleMessage(
      "Traffic: Unlimited",
    ),
    "nodeOverviewTurnOffProxy": MessageLookupByLibrary.simpleMessage(
      "Turn off",
    ),
    "nodeOverviewTurnOnProxy": MessageLookupByLibrary.simpleMessage("Turn on"),
    "nodeOverviewTypeUnsupported": MessageLookupByLibrary.simpleMessage(
      "This protocol is not supported for isolated tests",
    ),
    "nodeOverviewUntested": MessageLookupByLibrary.simpleMessage("Untested"),
    "nodeOverviewUpdateAllSubscriptions": MessageLookupByLibrary.simpleMessage(
      "Update all",
    ),
    "nodeOverviewUpdateSubscription": MessageLookupByLibrary.simpleMessage(
      "Update",
    ),
    "nodeOverviewUpdating": MessageLookupByLibrary.simpleMessage(
      "Updating subscription",
    ),
    "nodeOverviewUpdatingShort": MessageLookupByLibrary.simpleMessage(
      "Updating",
    ),
    "nodeOverviewUseNode": MessageLookupByLibrary.simpleMessage("Use"),
    "nodeOverviewUsedOfTotalTraffic": m62,
    "nodeOverviewUsedTrafficOnly": m63,
    "none": MessageLookupByLibrary.simpleMessage("none"),
    "notSelectedTip": MessageLookupByLibrary.simpleMessage(
      "The current proxy group cannot be selected.",
    ),
    "noviceMode": MessageLookupByLibrary.simpleMessage("Simple Mode"),
    "nullProfileDesc": MessageLookupByLibrary.simpleMessage(
      "No profile, Please add a profile",
    ),
    "nullScriptTip": MessageLookupByLibrary.simpleMessage("No scripts"),
    "nullTip": m64,
    "numberTip": m65,
    "oneColumn": MessageLookupByLibrary.simpleMessage("One column"),
    "oneline": MessageLookupByLibrary.simpleMessage("Oneline"),
    "onlyIcon": MessageLookupByLibrary.simpleMessage("Icon"),
    "onlyOtherApps": MessageLookupByLibrary.simpleMessage(
      "Only third-party apps",
    ),
    "onlyStatisticsProxy": MessageLookupByLibrary.simpleMessage(
      "Count only proxy traffic",
    ),
    "onlyStatisticsProxyDesc": MessageLookupByLibrary.simpleMessage(
      "When turned on, only proxy traffic will be counted in statistics",
    ),
    "openLogsFolder": MessageLookupByLibrary.simpleMessage("Open logs folder"),
    "openPanel": MessageLookupByLibrary.simpleMessage("Open panel"),
    "options": MessageLookupByLibrary.simpleMessage("Options"),
    "originalRepository": MessageLookupByLibrary.simpleMessage(
      "Original Repository",
    ),
    "other": MessageLookupByLibrary.simpleMessage("Other"),
    "otherContributors": MessageLookupByLibrary.simpleMessage("Contributors"),
    "outboundMode": MessageLookupByLibrary.simpleMessage("Outbound mode"),
    "override": MessageLookupByLibrary.simpleMessage("Override"),
    "overrideAutoSavedHint": MessageLookupByLibrary.simpleMessage(
      "Rule changes auto-save and hot-reload immediately",
    ),
    "overrideDesc": MessageLookupByLibrary.simpleMessage(
      "Override Proxy related config",
    ),
    "overrideDns": MessageLookupByLibrary.simpleMessage("Override Dns"),
    "overrideDnsDesc": MessageLookupByLibrary.simpleMessage(
      "Turning it on will override the DNS options in the profile",
    ),
    "overrideInvalidTip": MessageLookupByLibrary.simpleMessage(
      "Does not take effect in script mode",
    ),
    "overrideNetworkSettings": MessageLookupByLibrary.simpleMessage(
      "Override network settings",
    ),
    "overrideNetworkSettingsDesc": MessageLookupByLibrary.simpleMessage(
      "Ignore network settings from provider config",
    ),
    "overrideOriginRules": MessageLookupByLibrary.simpleMessage(
      "Override the original rule",
    ),
    "overrideProviderSettings": MessageLookupByLibrary.simpleMessage(
      "Override",
    ),
    "overrideProviderSettingsDesc": MessageLookupByLibrary.simpleMessage(
      "Ignore provider settings and manage manually",
    ),
    "palette": MessageLookupByLibrary.simpleMessage("Palette"),
    "password": MessageLookupByLibrary.simpleMessage("Password"),
    "paste": MessageLookupByLibrary.simpleMessage("Paste"),
    "pasteFromClipboard": MessageLookupByLibrary.simpleMessage("Paste"),
    "pleaseBindWebDAV": MessageLookupByLibrary.simpleMessage(
      "Please bind WebDAV",
    ),
    "pleaseEnterScriptName": MessageLookupByLibrary.simpleMessage(
      "Please enter a script name",
    ),
    "pleaseInputAdminPassword": MessageLookupByLibrary.simpleMessage(
      "Please enter the admin password",
    ),
    "pleaseUploadFile": MessageLookupByLibrary.simpleMessage(
      "Please upload file",
    ),
    "pleaseUploadValidQrcode": MessageLookupByLibrary.simpleMessage(
      "Please upload a valid QR code",
    ),
    "port": MessageLookupByLibrary.simpleMessage("Port"),
    "portConflictTip": MessageLookupByLibrary.simpleMessage(
      "Please enter a different port",
    ),
    "portTip": m66,
    "preferH3Desc": MessageLookupByLibrary.simpleMessage(
      "Prioritize the use of DOH\'s http/3",
    ),
    "pressKeyboard": MessageLookupByLibrary.simpleMessage(
      "Please press the keyboard.",
    ),
    "preview": MessageLookupByLibrary.simpleMessage("Preview"),
    "profile": MessageLookupByLibrary.simpleMessage("Profile"),
    "profileAutoUpdateIntervalInvalidValidationDesc":
        MessageLookupByLibrary.simpleMessage(
          "Please input a valid interval time format",
        ),
    "profileAutoUpdateIntervalNullValidationDesc":
        MessageLookupByLibrary.simpleMessage(
          "Please enter the auto update interval time",
        ),
    "profileHasUpdate": MessageLookupByLibrary.simpleMessage(
      "The profile has been modified. Do you want to disable auto update?",
    ),
    "profileNameNullValidationDesc": MessageLookupByLibrary.simpleMessage(
      "Please input the profile name",
    ),
    "profileParseErrorDesc": MessageLookupByLibrary.simpleMessage(
      "profile parse error",
    ),
    "profileUrlInvalidValidationDesc": MessageLookupByLibrary.simpleMessage(
      "Please input a valid profile URL",
    ),
    "profileUrlNullValidationDesc": MessageLookupByLibrary.simpleMessage(
      "Please input the profile URL",
    ),
    "profiles": MessageLookupByLibrary.simpleMessage("Profiles"),
    "profilesSort": MessageLookupByLibrary.simpleMessage("Profiles sort"),
    "project": MessageLookupByLibrary.simpleMessage("Project"),
    "providers": MessageLookupByLibrary.simpleMessage("Providers"),
    "proxies": MessageLookupByLibrary.simpleMessage("Proxies"),
    "proxiesSetting": MessageLookupByLibrary.simpleMessage("Proxies setting"),
    "proxyGroup": MessageLookupByLibrary.simpleMessage("Proxy group"),
    "proxyNameserver": MessageLookupByLibrary.simpleMessage("Proxy nameserver"),
    "proxyNameserverDesc": MessageLookupByLibrary.simpleMessage(
      "Domain for resolving proxy nodes",
    ),
    "proxyPort": MessageLookupByLibrary.simpleMessage("ProxyPort"),
    "proxyPortDesc": MessageLookupByLibrary.simpleMessage(
      "Set the Clash listening port",
    ),
    "proxyProviders": MessageLookupByLibrary.simpleMessage("Proxy providers"),
    "purchase": MessageLookupByLibrary.simpleMessage("Purchase"),
    "purchaseAccount": MessageLookupByLibrary.simpleMessage(
      "Account and subscription",
    ),
    "purchaseAcquireOpenSupport": MessageLookupByLibrary.simpleMessage(
      "Chat with support",
    ),
    "purchaseAcquirePlanCode": MessageLookupByLibrary.simpleMessage("Get code"),
    "purchaseAcquireSheetSubtitle": MessageLookupByLibrary.simpleMessage(
      "Contact support or open the card store to get a code, then return here to redeem. No order is created in the app.",
    ),
    "purchaseAuthTabLogin": MessageLookupByLibrary.simpleMessage("Sign in"),
    "purchaseAuthTabRegister": MessageLookupByLibrary.simpleMessage(
      "Free 2G sign-up",
    ),
    "purchaseAvailablePlans": MessageLookupByLibrary.simpleMessage(
      "Available plans",
    ),
    "purchaseBackToLogin": MessageLookupByLibrary.simpleMessage(
      "Back to sign in",
    ),
    "purchaseBackupContactsLabel": MessageLookupByLibrary.simpleMessage(
      "Backup support (WeChat)",
    ),
    "purchaseBalance": MessageLookupByLibrary.simpleMessage("Account balance"),
    "purchaseBalanceOnlyHint": MessageLookupByLibrary.simpleMessage(
      "A balance credit does not activate a subscription.",
    ),
    "purchaseBenefitsAfter": MessageLookupByLibrary.simpleMessage(
      "Benefits will be shown after redemption.",
    ),
    "purchaseCaptchaRequiredNotice": MessageLookupByLibrary.simpleMessage(
      "This site requires CAPTCHA verification. Continue on the website.",
    ),
    "purchaseCardStore": MessageLookupByLibrary.simpleMessage(
      "Open gift card store",
    ),
    "purchaseCenterDescription": MessageLookupByLibrary.simpleMessage(
      "Redeem your card to activate or renew your service, then sync your subscription.",
    ),
    "purchaseCenterTitle": MessageLookupByLibrary.simpleMessage(
      "Gift card redemption",
    ),
    "purchaseChannelError": MessageLookupByLibrary.simpleMessage(
      "Gift card store information could not be loaded. You can still contact live support below.",
    ),
    "purchaseCheck": MessageLookupByLibrary.simpleMessage("Preview benefits"),
    "purchaseChecking": MessageLookupByLibrary.simpleMessage("Checking…"),
    "purchaseClearCode": MessageLookupByLibrary.simpleMessage("Clear code"),
    "purchaseClipboardEmpty": MessageLookupByLibrary.simpleMessage(
      "No valid gift card code found in clipboard.",
    ),
    "purchaseCode": MessageLookupByLibrary.simpleMessage("Gift card code"),
    "purchaseCodeFormatError": MessageLookupByLibrary.simpleMessage(
      "Enter an 8–32 character code using letters and numbers.",
    ),
    "purchaseCodeSentNotice": MessageLookupByLibrary.simpleMessage(
      "Verification code sent. Check your inbox and spam folder.",
    ),
    "purchaseConfirmRedeem": MessageLookupByLibrary.simpleMessage(
      "Confirm redemption",
    ),
    "purchaseContactDescription": MessageLookupByLibrary.simpleMessage(
      "Online payment is not available yet. Add either WeChat account below to purchase or renew your service.",
    ),
    "purchaseCooldownWithSecondsError": m67,
    "purchaseCopyInquiry": MessageLookupByLibrary.simpleMessage(
      "Copy plan inquiry",
    ),
    "purchaseEmail": MessageLookupByLibrary.simpleMessage("Email address"),
    "purchaseEmailCode": MessageLookupByLibrary.simpleMessage(
      "Email verification code",
    ),
    "purchaseEmailCodeInvalidError": MessageLookupByLibrary.simpleMessage(
      "Invalid or expired email verification code.",
    ),
    "purchaseEmailCodeLockedError": MessageLookupByLibrary.simpleMessage(
      "Too many verification attempts. Request a new code later.",
    ),
    "purchaseEmailCodeRequired": MessageLookupByLibrary.simpleMessage(
      "Enter the 6-digit verification code",
    ),
    "purchaseEmailCooldownError": MessageLookupByLibrary.simpleMessage(
      "Please wait before requesting another code.",
    ),
    "purchaseEmailDomainError": MessageLookupByLibrary.simpleMessage(
      "This email domain is not allowed. Try another email address or register on the website.",
    ),
    "purchaseEmailExistsError": MessageLookupByLibrary.simpleMessage(
      "This email is already registered. Switch to Sign in.",
    ),
    "purchaseEmailRateLimitedError": MessageLookupByLibrary.simpleMessage(
      "Too many verification emails requested. Try again later.",
    ),
    "purchaseEmailRequired": MessageLookupByLibrary.simpleMessage(
      "Enter a valid email address.",
    ),
    "purchaseEmailVerifyDisabledError": MessageLookupByLibrary.simpleMessage(
      "Email verification is currently disabled.",
    ),
    "purchaseExpires": MessageLookupByLibrary.simpleMessage("Expires"),
    "purchaseExpiryChange": MessageLookupByLibrary.simpleMessage(
      "Expiration before → after",
    ),
    "purchaseExtraDays": MessageLookupByLibrary.simpleMessage(
      "Extra validity (days)",
    ),
    "purchaseExtraDevices": MessageLookupByLibrary.simpleMessage(
      "Additional devices",
    ),
    "purchaseFilterAll": MessageLookupByLibrary.simpleMessage("All plans"),
    "purchaseFilterOnetime": MessageLookupByLibrary.simpleMessage(
      "Traffic pack",
    ),
    "purchaseFilterPeriod": MessageLookupByLibrary.simpleMessage("Recurring"),
    "purchaseForgotPassword": MessageLookupByLibrary.simpleMessage(
      "Forgot password?",
    ),
    "purchaseGenericError": MessageLookupByLibrary.simpleMessage(
      "The request failed. Please try again.",
    ),
    "purchaseGetCard": MessageLookupByLibrary.simpleMessage("Get a gift card"),
    "purchaseGetCardDescription": MessageLookupByLibrary.simpleMessage(
      "Buy a gift card or get assistance through the self-service store or 24/7 live support.",
    ),
    "purchaseGmailAliasError": MessageLookupByLibrary.simpleMessage(
      "Gmail alias addresses (with \'+\') are not allowed. Use your base Gmail address.",
    ),
    "purchaseHandoffDescription": MessageLookupByLibrary.simpleMessage(
      "Copy your code after purchase and return to this window to auto-preview benefits (never redeemed without confirmation).",
    ),
    "purchaseHandoffPasteAction": MessageLookupByLibrary.simpleMessage(
      "Paste & check",
    ),
    "purchaseHandoffTitle": m68,
    "purchaseHeaderSyncedBadge": MessageLookupByLibrary.simpleMessage(
      "High-speed nodes ready",
    ),
    "purchaseHeaderTrialBadge": MessageLookupByLibrary.simpleMessage(
      "Free 2 GiB trial on sign-up · Lifetime traffic packs",
    ),
    "purchaseHidePassword": MessageLookupByLibrary.simpleMessage(
      "Hide password",
    ),
    "purchaseHistory": MessageLookupByLibrary.simpleMessage(
      "Redemption history",
    ),
    "purchaseHistoryEmpty": MessageLookupByLibrary.simpleMessage(
      "No redemptions yet.",
    ),
    "purchaseHistoryPage": MessageLookupByLibrary.simpleMessage("Page"),
    "purchaseHistoryRetry": MessageLookupByLibrary.simpleMessage(
      "Reload history",
    ),
    "purchaseHistoryTotal": MessageLookupByLibrary.simpleMessage("Total"),
    "purchaseInquiryTemplate": m69,
    "purchaseInvitationUnavailableError": MessageLookupByLibrary.simpleMessage(
      "Invitations are currently unavailable.",
    ),
    "purchaseInviteCode": MessageLookupByLibrary.simpleMessage("Invite code"),
    "purchaseInviteCodeInvalidError": MessageLookupByLibrary.simpleMessage(
      "Invalid or expired invite code.",
    ),
    "purchaseInviteCodeOptionalToggle": MessageLookupByLibrary.simpleMessage(
      "Have an invite code? (Optional)",
    ),
    "purchaseInviteCodeRequired": MessageLookupByLibrary.simpleMessage(
      "Enter your invite code",
    ),
    "purchaseInviteCodeRequiredError": MessageLookupByLibrary.simpleMessage(
      "An invite code is required to register on this site.",
    ),
    "purchaseJumpToWorkbench": MessageLookupByLibrary.simpleMessage(
      "Have a code? Redeem now",
    ),
    "purchaseLoggingIn": MessageLookupByLibrary.simpleMessage("Signing in…"),
    "purchaseLogin": MessageLookupByLibrary.simpleMessage("Sign in"),
    "purchaseLoginDescription": MessageLookupByLibrary.simpleMessage(
      "Sign in to your account to redeem a code and sync high-speed nodes automatically.",
    ),
    "purchaseLoginTitle": MessageLookupByLibrary.simpleMessage(
      "Sign in to redeem",
    ),
    "purchaseLogout": MessageLookupByLibrary.simpleMessage("Sign out"),
    "purchaseLogoutRemoteError": MessageLookupByLibrary.simpleMessage(
      "Signed out on this device. Server sign-out could not be confirmed.",
    ),
    "purchaseMailUnavailableError": MessageLookupByLibrary.simpleMessage(
      "Email delivery is unavailable right now. Contact support or try again later.",
    ),
    "purchaseMysteryPreview": MessageLookupByLibrary.simpleMessage(
      "This is a mystery card. The actual benefits are revealed after redemption.",
    ),
    "purchaseNewActivationBadge": MessageLookupByLibrary.simpleMessage(
      "New activation",
    ),
    "purchaseNewPassword": MessageLookupByLibrary.simpleMessage("New password"),
    "purchaseNextPage": MessageLookupByLibrary.simpleMessage("Next page"),
    "purchaseNoBenefits": MessageLookupByLibrary.simpleMessage(
      "No additional benefits.",
    ),
    "purchaseNoExpiry": MessageLookupByLibrary.simpleMessage("No expiration"),
    "purchaseNoPlan": MessageLookupByLibrary.simpleMessage("No active plan"),
    "purchaseNoPreviousExpiry": MessageLookupByLibrary.simpleMessage("Not set"),
    "purchaseNotEligible": MessageLookupByLibrary.simpleMessage(
      "This card cannot be redeemed by this account.",
    ),
    "purchaseOnlineSupport": MessageLookupByLibrary.simpleMessage(
      "Live support",
    ),
    "purchaseOpenLinkFailed": MessageLookupByLibrary.simpleMessage(
      "Could not open the page. Please try again.",
    ),
    "purchaseOpenNodesAction": MessageLookupByLibrary.simpleMessage(
      "View profiles & nodes",
    ),
    "purchaseOpenWebAuth": MessageLookupByLibrary.simpleMessage(
      "Continue on website",
    ),
    "purchaseOrderNumber": MessageLookupByLibrary.simpleMessage(
      "Redemption order",
    ),
    "purchasePassword": MessageLookupByLibrary.simpleMessage("Password"),
    "purchasePasswordMinLength": MessageLookupByLibrary.simpleMessage(
      "Enter at least 8 characters.",
    ),
    "purchasePasswordRequired": MessageLookupByLibrary.simpleMessage(
      "Enter your password.",
    ),
    "purchasePeriod": MessageLookupByLibrary.simpleMessage("Period"),
    "purchasePeriodHalfYearly": MessageLookupByLibrary.simpleMessage(
      "Half-yearly",
    ),
    "purchasePeriodMonthly": MessageLookupByLibrary.simpleMessage("Monthly"),
    "purchasePeriodOnetime": MessageLookupByLibrary.simpleMessage(
      "Traffic based",
    ),
    "purchasePeriodQuarterly": MessageLookupByLibrary.simpleMessage(
      "Quarterly",
    ),
    "purchasePeriodThreeYearly": MessageLookupByLibrary.simpleMessage(
      "Three years",
    ),
    "purchasePeriodTwoYearly": MessageLookupByLibrary.simpleMessage(
      "Two years",
    ),
    "purchasePeriodYearly": MessageLookupByLibrary.simpleMessage("Yearly"),
    "purchasePlan": MessageLookupByLibrary.simpleMessage("Current plan"),
    "purchasePlanBuyNow": MessageLookupByLibrary.simpleMessage("Buy card"),
    "purchasePlanCollapseDetails": MessageLookupByLibrary.simpleMessage(
      "Hide plan details",
    ),
    "purchasePlanDetails": MessageLookupByLibrary.simpleMessage("Plan details"),
    "purchasePlanDevices": MessageLookupByLibrary.simpleMessage("Device limit"),
    "purchasePlanExpandDetails": MessageLookupByLibrary.simpleMessage(
      "Show full plan details",
    ),
    "purchasePlanFeaturedBadge": MessageLookupByLibrary.simpleMessage(
      "Popular tier",
    ),
    "purchasePlanFreeBadge": MessageLookupByLibrary.simpleMessage("Free trial"),
    "purchasePlanFreeHint": MessageLookupByLibrary.simpleMessage("Free"),
    "purchasePlanImageNotLoaded": MessageLookupByLibrary.simpleMessage(
      "External image not loaded",
    ),
    "purchasePlanLowStock": m70,
    "purchasePlanNotProvided": MessageLookupByLibrary.simpleMessage(
      "Not provided",
    ),
    "purchasePlanResetMonthStart": MessageLookupByLibrary.simpleMessage(
      "On the 1st of each month",
    ),
    "purchasePlanResetMonthlyExpiry": MessageLookupByLibrary.simpleMessage(
      "Monthly on the expiry day",
    ),
    "purchasePlanResetNever": MessageLookupByLibrary.simpleMessage(
      "Does not reset automatically",
    ),
    "purchasePlanResetPrice": MessageLookupByLibrary.simpleMessage(
      "Traffic reset · listed price",
    ),
    "purchasePlanResetSystem": MessageLookupByLibrary.simpleMessage(
      "Follows system settings",
    ),
    "purchasePlanResetUnknown": m71,
    "purchasePlanResetYearStart": MessageLookupByLibrary.simpleMessage(
      "On January 1 each year",
    ),
    "purchasePlanResetYearlyExpiry": MessageLookupByLibrary.simpleMessage(
      "Yearly on the expiry month and day",
    ),
    "purchasePlanSalesCapacity": MessageLookupByLibrary.simpleMessage(
      "Remaining sales slots",
    ),
    "purchasePlanSoldOut": MessageLookupByLibrary.simpleMessage("Sold out"),
    "purchasePlanSpeed": MessageLookupByLibrary.simpleMessage("Speed limit"),
    "purchasePlanTrafficReset": MessageLookupByLibrary.simpleMessage(
      "Traffic reset",
    ),
    "purchasePlanUnitPriceHint": m72,
    "purchasePlanUnknown": MessageLookupByLibrary.simpleMessage("Subscription"),
    "purchasePlanUnlimited": MessageLookupByLibrary.simpleMessage("Unlimited"),
    "purchasePlansDescription": MessageLookupByLibrary.simpleMessage(
      "Prices are shown as listed on the website. Confirm the currency on the store page when buying a gift card, then return here to redeem.",
    ),
    "purchasePlansEmpty": MessageLookupByLibrary.simpleMessage(
      "No plans are currently available.",
    ),
    "purchasePlansError": MessageLookupByLibrary.simpleMessage(
      "Plans could not be loaded. Please try again.",
    ),
    "purchasePlansErrorHint": MessageLookupByLibrary.simpleMessage(
      "Account sign-in, free sign-up, and gift card redemption on the right remain available.",
    ),
    "purchasePlansLoading": MessageLookupByLibrary.simpleMessage(
      "Loading plans…",
    ),
    "purchasePlansRetry": MessageLookupByLibrary.simpleMessage("Reload plans"),
    "purchasePreloginCodeHint": MessageLookupByLibrary.simpleMessage(
      "Already bought a code? Paste it here to auto-preview right after sign-in",
    ),
    "purchasePreview": MessageLookupByLibrary.simpleMessage(
      "Review before redeeming",
    ),
    "purchasePreviousPage": MessageLookupByLibrary.simpleMessage(
      "Previous page",
    ),
    "purchaseProfiles": MessageLookupByLibrary.simpleMessage("Manage profiles"),
    "purchaseQuotaChange": MessageLookupByLibrary.simpleMessage(
      "Total traffic before → after",
    ),
    "purchaseRecoverPassword": MessageLookupByLibrary.simpleMessage(
      "Reset password on website",
    ),
    "purchaseRecoverResult": MessageLookupByLibrary.simpleMessage(
      "Check redemption result",
    ),
    "purchaseRedeemFor": MessageLookupByLibrary.simpleMessage("Redeem for"),
    "purchaseRedeemTitle": MessageLookupByLibrary.simpleMessage(
      "Redeem a gift card",
    ),
    "purchaseRedeeming": MessageLookupByLibrary.simpleMessage("Redeeming…"),
    "purchaseRefresh": MessageLookupByLibrary.simpleMessage("Refresh account"),
    "purchaseRegister": MessageLookupByLibrary.simpleMessage(
      "Create account on website",
    ),
    "purchaseRegisterSubmit": MessageLookupByLibrary.simpleMessage(
      "Create account & sync nodes",
    ),
    "purchaseRegisterTrialBanner": MessageLookupByLibrary.simpleMessage(
      "Get 2 GiB of lifetime trial traffic instantly, with automatic node import and Smart Connect.",
    ),
    "purchaseRegisterWebRequiredError": MessageLookupByLibrary.simpleMessage(
      "Email verification or CAPTCHA is enabled. Use \'Create account on website\' below.",
    ),
    "purchaseRegistering": MessageLookupByLibrary.simpleMessage(
      "Creating account…",
    ),
    "purchaseRegistrationClosedError": MessageLookupByLibrary.simpleMessage(
      "New account registration is currently closed.",
    ),
    "purchaseRemaining": MessageLookupByLibrary.simpleMessage(
      "Remaining traffic",
    ),
    "purchaseRenewalBadge": MessageLookupByLibrary.simpleMessage("Renewal"),
    "purchaseResetPasswordDescription": MessageLookupByLibrary.simpleMessage(
      "Enter your registered email and a 6-digit verification code to set a new password.",
    ),
    "purchaseResetPasswordSubmit": MessageLookupByLibrary.simpleMessage(
      "Confirm password reset",
    ),
    "purchaseResetPasswordSuccess": MessageLookupByLibrary.simpleMessage(
      "Password reset. Sign in with your new password.",
    ),
    "purchaseResetPasswordTitle": MessageLookupByLibrary.simpleMessage(
      "Reset password",
    ),
    "purchaseResetTraffic": MessageLookupByLibrary.simpleMessage(
      "Reset used traffic",
    ),
    "purchaseResettingPassword": MessageLookupByLibrary.simpleMessage(
      "Resetting...",
    ),
    "purchaseRestoring": MessageLookupByLibrary.simpleMessage(
      "Restoring account…",
    ),
    "purchaseSafetyBody": MessageLookupByLibrary.simpleMessage(
      "For your network privacy and security, please contact live support directly to purchase.",
    ),
    "purchaseSafetyTag24h": MessageLookupByLibrary.simpleMessage(
      "24/7 Fast Reply",
    ),
    "purchaseSafetyTagFunds": MessageLookupByLibrary.simpleMessage(
      "Payment Safety",
    ),
    "purchaseSafetyTagOfficial": MessageLookupByLibrary.simpleMessage(
      "Official Direct",
    ),
    "purchaseSafetyTitle": MessageLookupByLibrary.simpleMessage(
      "Official Secure Purchase · 24/7 Live Support",
    ),
    "purchaseSendCode": MessageLookupByLibrary.simpleMessage("Send code"),
    "purchaseSendCodeCooldown": m73,
    "purchaseSendingCode": MessageLookupByLibrary.simpleMessage("Sending..."),
    "purchaseShowPassword": MessageLookupByLibrary.simpleMessage(
      "Show password",
    ),
    "purchaseSpecAllDevicesSupported": MessageLookupByLibrary.simpleMessage(
      "Supports all device types",
    ),
    "purchaseSpecBillingCycle": m74,
    "purchaseSpecDevicesCount": m75,
    "purchaseSpecDevicesUnlimited": MessageLookupByLibrary.simpleMessage(
      "Devices: Unlimited",
    ),
    "purchaseSpecDurationUnlimited": MessageLookupByLibrary.simpleMessage(
      "Validity: Never expires",
    ),
    "purchaseSpecSpeedLimit": m76,
    "purchaseSpecTrafficUntilUsed": MessageLookupByLibrary.simpleMessage(
      "Traffic valid until used up",
    ),
    "purchaseStepBrowse": MessageLookupByLibrary.simpleMessage(
      "1. Choose plan or get code",
    ),
    "purchaseStepRedeem": MessageLookupByLibrary.simpleMessage(
      "2. Sign in & verify code",
    ),
    "purchaseStepSync": MessageLookupByLibrary.simpleMessage(
      "3. Auto-sync nodes",
    ),
    "purchaseStorageError": MessageLookupByLibrary.simpleMessage(
      "Secure account storage is unavailable. Retry after checking your system credential storage.",
    ),
    "purchaseSuccess": MessageLookupByLibrary.simpleMessage(
      "Gift card redeemed",
    ),
    "purchaseSuccessDescription": MessageLookupByLibrary.simpleMessage(
      "Your account benefits have been updated. Subscription sync is a separate step.",
    ),
    "purchaseSync": MessageLookupByLibrary.simpleMessage("Sync subscription"),
    "purchaseSyncError": MessageLookupByLibrary.simpleMessage(
      "Subscription sync failed. You can retry below.",
    ),
    "purchaseSyncFailed": MessageLookupByLibrary.simpleMessage(
      "Redemption is complete. Subscription sync failed; retry sync below.",
    ),
    "purchaseSyncSucceeded": MessageLookupByLibrary.simpleMessage(
      "Subscription synced successfully.",
    ),
    "purchaseSyncing": MessageLookupByLibrary.simpleMessage(
      "Syncing subscription…",
    ),
    "purchaseTitle": MessageLookupByLibrary.simpleMessage(
      "Purchase and renewal",
    ),
    "purchaseTosAgreementPrefix": MessageLookupByLibrary.simpleMessage(
      "By registering, you agree to the",
    ),
    "purchaseTosLinkLabel": MessageLookupByLibrary.simpleMessage(
      "Terms of Service",
    ),
    "purchaseTraffic": MessageLookupByLibrary.simpleMessage("Traffic quota"),
    "purchaseUnresolved": MessageLookupByLibrary.simpleMessage(
      "Redemption result needs confirmation",
    ),
    "purchaseUnresolvedDescription": MessageLookupByLibrary.simpleMessage(
      "The request was interrupted. Check the result before redeeming another card.",
    ),
    "purchaseUnsupportedAccount": MessageLookupByLibrary.simpleMessage(
      "Use a regular user account to redeem gift cards.",
    ),
    "purchaseUsed": MessageLookupByLibrary.simpleMessage("Used traffic"),
    "purchaseUsedPreserved": MessageLookupByLibrary.simpleMessage(
      "Used traffic is preserved",
    ),
    "purchaseValidityDays": MessageLookupByLibrary.simpleMessage(
      "Validity (days)",
    ),
    "pureBlackMode": MessageLookupByLibrary.simpleMessage("Pure black mode"),
    "qrNotFound": MessageLookupByLibrary.simpleMessage("QR code not found"),
    "qrcode": MessageLookupByLibrary.simpleMessage("QR code"),
    "qrcodeDesc": MessageLookupByLibrary.simpleMessage(
      "Scan QR code to obtain profile",
    ),
    "rainbowScheme": MessageLookupByLibrary.simpleMessage("Rainbow"),
    "receiveSubscriptionTitle": MessageLookupByLibrary.simpleMessage(
      "Receive Subscription",
    ),
    "recovery": MessageLookupByLibrary.simpleMessage("Recovery"),
    "recoveryAll": MessageLookupByLibrary.simpleMessage("Recovery all data"),
    "recoveryProfiles": MessageLookupByLibrary.simpleMessage(
      "Only recovery profiles",
    ),
    "recoveryStrategy": MessageLookupByLibrary.simpleMessage(
      "Recovery strategy",
    ),
    "recoveryStrategy_compatible": MessageLookupByLibrary.simpleMessage(
      "Compatible",
    ),
    "recoveryStrategy_override": MessageLookupByLibrary.simpleMessage(
      "Override",
    ),
    "recoverySuccess": MessageLookupByLibrary.simpleMessage("Recovery success"),
    "redirPort": MessageLookupByLibrary.simpleMessage("Redir Port"),
    "redo": MessageLookupByLibrary.simpleMessage("redo"),
    "regExp": MessageLookupByLibrary.simpleMessage("RegExp"),
    "remaining": MessageLookupByLibrary.simpleMessage("Remaining"),
    "remainingPlural": MessageLookupByLibrary.simpleMessage("Remaining"),
    "remainingSingular": MessageLookupByLibrary.simpleMessage("Remaining"),
    "remote": MessageLookupByLibrary.simpleMessage("Remote"),
    "remoteBackupDesc": MessageLookupByLibrary.simpleMessage(
      "Backup local data to WebDAV",
    ),
    "remoteRecoveryDesc": MessageLookupByLibrary.simpleMessage(
      "Recovery data from WebDAV",
    ),
    "remove": MessageLookupByLibrary.simpleMessage("Remove"),
    "rename": MessageLookupByLibrary.simpleMessage("Rename"),
    "renew": MessageLookupByLibrary.simpleMessage("Renew"),
    "renewSubscription": MessageLookupByLibrary.simpleMessage(
      "Renew subscription",
    ),
    "requests": MessageLookupByLibrary.simpleMessage("Requests"),
    "requestsDesc": MessageLookupByLibrary.simpleMessage(
      "View recently request records",
    ),
    "reset": MessageLookupByLibrary.simpleMessage("Reset"),
    "resetTip": MessageLookupByLibrary.simpleMessage("Make sure to reset"),
    "resources": MessageLookupByLibrary.simpleMessage("Resources"),
    "resourcesDesc": MessageLookupByLibrary.simpleMessage(
      "External resource related info",
    ),
    "respectRules": MessageLookupByLibrary.simpleMessage("Respect rules"),
    "respectRulesDesc": MessageLookupByLibrary.simpleMessage(
      "DNS connection following rules, need to configure proxy-server-nameserver",
    ),
    "restart": MessageLookupByLibrary.simpleMessage("Restart"),
    "restartCore": MessageLookupByLibrary.simpleMessage("Restart core"),
    "routeAddress": MessageLookupByLibrary.simpleMessage("Route address"),
    "routeAddressDesc": MessageLookupByLibrary.simpleMessage(
      "Config listen route address",
    ),
    "routeMode": MessageLookupByLibrary.simpleMessage("Route mode"),
    "routeMode_bypassPrivate": MessageLookupByLibrary.simpleMessage(
      "Bypass private route address",
    ),
    "routeMode_config": MessageLookupByLibrary.simpleMessage("Use config"),
    "ru": MessageLookupByLibrary.simpleMessage("Russian"),
    "rule": MessageLookupByLibrary.simpleMessage("By rule"),
    "ruleName": MessageLookupByLibrary.simpleMessage("Rule name"),
    "ruleProviders": MessageLookupByLibrary.simpleMessage("Rule providers"),
    "ruleTarget": MessageLookupByLibrary.simpleMessage("Rule target"),
    "running": MessageLookupByLibrary.simpleMessage("Running"),
    "runtimeConfig": MessageLookupByLibrary.simpleMessage("Runtime config"),
    "runtimeConfigNotAvailable": MessageLookupByLibrary.simpleMessage(
      "Runtime config not available",
    ),
    "save": MessageLookupByLibrary.simpleMessage("Save"),
    "saveChanges": MessageLookupByLibrary.simpleMessage(
      "Do you want to save the changes?",
    ),
    "saveTip": MessageLookupByLibrary.simpleMessage(
      "Are you sure you want to save?",
    ),
    "scan": MessageLookupByLibrary.simpleMessage("Scan"),
    "script": MessageLookupByLibrary.simpleMessage("Script"),
    "search": MessageLookupByLibrary.simpleMessage("Search"),
    "seconds": MessageLookupByLibrary.simpleMessage("Seconds"),
    "selectAll": MessageLookupByLibrary.simpleMessage("Select all"),
    "selectProfile": MessageLookupByLibrary.simpleMessage("Select Profile"),
    "selected": MessageLookupByLibrary.simpleMessage("Selected"),
    "selectedCountTitle": m77,
    "sendToTv": MessageLookupByLibrary.simpleMessage("Send to TV"),
    "sendToTvTitle": MessageLookupByLibrary.simpleMessage("Send to TV"),
    "sentSuccessfullyMessage": MessageLookupByLibrary.simpleMessage(
      "Sent successfully",
    ),
    "settings": MessageLookupByLibrary.simpleMessage("Settings"),
    "settingsSendDeviceDataSubtitle": MessageLookupByLibrary.simpleMessage(
      "Send device identifier, app version and device name to proxy provider server",
    ),
    "settingsSendDeviceDataTitle": MessageLookupByLibrary.simpleMessage(
      "Send HWID",
    ),
    "show": MessageLookupByLibrary.simpleMessage("Show"),
    "shrink": MessageLookupByLibrary.simpleMessage("Shrink"),
    "silentLaunch": MessageLookupByLibrary.simpleMessage("SilentLaunch"),
    "silentLaunchDesc": MessageLookupByLibrary.simpleMessage(
      "Start in the background",
    ),
    "size": MessageLookupByLibrary.simpleMessage("Size"),
    "socksPort": MessageLookupByLibrary.simpleMessage("Socks Port"),
    "sort": MessageLookupByLibrary.simpleMessage("Sort"),
    "source": MessageLookupByLibrary.simpleMessage("Source"),
    "sourceIp": MessageLookupByLibrary.simpleMessage("Source IP"),
    "stackMode": MessageLookupByLibrary.simpleMessage("Stack mode"),
    "standard": MessageLookupByLibrary.simpleMessage("Standard"),
    "start": MessageLookupByLibrary.simpleMessage("Start"),
    "startVpn": MessageLookupByLibrary.simpleMessage("Starting VPN..."),
    "status": MessageLookupByLibrary.simpleMessage("Status"),
    "statusDesc": MessageLookupByLibrary.simpleMessage(
      "System DNS will be used when turned off",
    ),
    "stop": MessageLookupByLibrary.simpleMessage("Stop"),
    "stopVpn": MessageLookupByLibrary.simpleMessage("Stopping VPN..."),
    "stopped": MessageLookupByLibrary.simpleMessage("Stopped"),
    "style": MessageLookupByLibrary.simpleMessage("Style"),
    "subRule": MessageLookupByLibrary.simpleMessage("Sub rule"),
    "submit": MessageLookupByLibrary.simpleMessage("Submit"),
    "subscriptionClipboardEmptyError": MessageLookupByLibrary.simpleMessage(
      "Clipboard is empty. Copy a subscription link first",
    ),
    "subscriptionEternal": MessageLookupByLibrary.simpleMessage(
      "Lifetime Subscription",
    ),
    "subscriptionExpired": MessageLookupByLibrary.simpleMessage(
      "Your subscription has expired",
    ),
    "subscriptionExpiresInDays": m78,
    "subscriptionExpiresSoon": MessageLookupByLibrary.simpleMessage(
      "Subscription expires soon",
    ),
    "subscriptionExpiresToday": MessageLookupByLibrary.simpleMessage(
      "Your subscription expires today",
    ),
    "subscriptionImportAuthOrNotFoundError": MessageLookupByLibrary.simpleMessage(
      "Subscription link is invalid or expired. Verify the URL or contact support",
    ),
    "subscriptionImportGenericError": MessageLookupByLibrary.simpleMessage(
      "Failed to import subscription. Check the link and try again",
    ),
    "subscriptionImportInvalidConfigError": MessageLookupByLibrary.simpleMessage(
      "This URL did not return a valid subscription config (it may be a webpage)",
    ),
    "subscriptionImportTimeoutError": MessageLookupByLibrary.simpleMessage(
      "Timed out fetching subscription. Check your network and retry",
    ),
    "subscriptionUnlimited": MessageLookupByLibrary.simpleMessage(
      "Lifetime Subscription",
    ),
    "subscriptionUrlEmptyError": MessageLookupByLibrary.simpleMessage(
      "Please paste a subscription link first",
    ),
    "subscriptionUrlInvalidError": MessageLookupByLibrary.simpleMessage(
      "No valid http(s):// subscription link found",
    ),
    "successTitle": MessageLookupByLibrary.simpleMessage("Success"),
    "support": MessageLookupByLibrary.simpleMessage("Support"),
    "supportBackupWechatToggle": MessageLookupByLibrary.simpleMessage(
      "Backup WeChat",
    ),
    "supportComposerHint": MessageLookupByLibrary.simpleMessage(
      "Type a message, press Enter to send...",
    ),
    "supportConversationLockedNotice": MessageLookupByLibrary.simpleMessage(
      "This conversation is resolved. Start a new conversation to continue.",
    ),
    "supportMessageFailed": MessageLookupByLibrary.simpleMessage("Failed"),
    "supportMessageSending": MessageLookupByLibrary.simpleMessage("Sending"),
    "supportNewConversation": MessageLookupByLibrary.simpleMessage(
      "New conversation",
    ),
    "supportNotConfiguredNotice": MessageLookupByLibrary.simpleMessage(
      "Live chat is not configured yet. Use the backup WeChat contacts below.",
    ),
    "supportOpenExternalFallback": MessageLookupByLibrary.simpleMessage(
      "Open in browser",
    ),
    "supportRefreshTooltip": MessageLookupByLibrary.simpleMessage(
      "Refresh messages",
    ),
    "supportRetryAction": MessageLookupByLibrary.simpleMessage("Retry"),
    "supportSendTooltip": MessageLookupByLibrary.simpleMessage("Send"),
    "supportSheetTitle": MessageLookupByLibrary.simpleMessage("Live Support"),
    "supportStatusConnected": MessageLookupByLibrary.simpleMessage("Connected"),
    "supportStatusConnecting": MessageLookupByLibrary.simpleMessage(
      "Connecting",
    ),
    "supportStatusOffline": MessageLookupByLibrary.simpleMessage("Offline"),
    "supportTypingAnonymous": MessageLookupByLibrary.simpleMessage("Agent"),
    "supportTypingIndicator": m79,
    "supportWelcomeFallbackSubtitle": MessageLookupByLibrary.simpleMessage(
      "Ask us anything about plans, nodes, or gift card redemption.",
    ),
    "supportWelcomeFallbackTitle": MessageLookupByLibrary.simpleMessage(
      "Welcome to FreedomNet Support",
    ),
    "sync": MessageLookupByLibrary.simpleMessage("Sync"),
    "system": MessageLookupByLibrary.simpleMessage("System"),
    "systemApp": MessageLookupByLibrary.simpleMessage("System APP"),
    "systemFont": MessageLookupByLibrary.simpleMessage("System font"),
    "systemProxy": MessageLookupByLibrary.simpleMessage("System proxy"),
    "systemProxyDesc": MessageLookupByLibrary.simpleMessage(
      "Attach HTTP proxy to VpnService",
    ),
    "tab": MessageLookupByLibrary.simpleMessage("Tab"),
    "tabAnimation": MessageLookupByLibrary.simpleMessage("Tab animation"),
    "tabAnimationDesc": MessageLookupByLibrary.simpleMessage(
      "Effective only in mobile view",
    ),
    "tcpConcurrent": MessageLookupByLibrary.simpleMessage("TCP concurrent"),
    "tcpConcurrentDesc": MessageLookupByLibrary.simpleMessage(
      "Enabling it will allow TCP concurrency",
    ),
    "testAllDelay": MessageLookupByLibrary.simpleMessage("Test latency"),
    "testUrl": MessageLookupByLibrary.simpleMessage("Test url"),
    "textScale": MessageLookupByLibrary.simpleMessage("Text Scaling"),
    "thanks": MessageLookupByLibrary.simpleMessage("Thanks for contribution"),
    "theme": MessageLookupByLibrary.simpleMessage("Theme"),
    "themeAtmosphereCustomBgHint": MessageLookupByLibrary.simpleMessage(
      "Custom wallpaper is active. Enable \"Prefer Day/Night sky background\" above to tune sky glass and motion.",
    ),
    "themeAtmosphereSection": MessageLookupByLibrary.simpleMessage(
      "Atmosphere & Motion",
    ),
    "themeColor": MessageLookupByLibrary.simpleMessage("Theme color"),
    "themeCustomBgNotice": MessageLookupByLibrary.simpleMessage(
      "Subscription custom wallpaper detected",
    ),
    "themeDesc": MessageLookupByLibrary.simpleMessage(
      "Day/Night sky sync, glass translucency & accent color",
    ),
    "themeGlassPresetAiry": MessageLookupByLibrary.simpleMessage("Airy"),
    "themeGlassPresetBalanced": MessageLookupByLibrary.simpleMessage(
      "Balanced",
    ),
    "themeGlassPresetLabel": MessageLookupByLibrary.simpleMessage(
      "Card glass translucency",
    ),
    "themeGlassPresetSolid": MessageLookupByLibrary.simpleMessage("Solid"),
    "themeIgnoreCustomBgLabel": MessageLookupByLibrary.simpleMessage(
      "Prefer Day/Night sky background",
    ),
    "themeMode": MessageLookupByLibrary.simpleMessage("Theme mode"),
    "themeSkyAmbientAnimation": MessageLookupByLibrary.simpleMessage(
      "Drifting clouds & starlight",
    ),
    "themeSkyAmbientAnimationDesc": MessageLookupByLibrary.simpleMessage(
      "Pauses steady drift to save power while keeping sunrise/sunset transitions",
    ),
    "themeSkyConsoleSection": MessageLookupByLibrary.simpleMessage(
      "Day & Night Sky Sync",
    ),
    "themeSkyModeDay": MessageLookupByLibrary.simpleMessage("Always Sunny Day"),
    "themeSkyModeDayDesc": MessageLookupByLibrary.simpleMessage(
      "Keep the bright sunny sky even when disconnected",
    ),
    "themeSkyModeFollow": MessageLookupByLibrary.simpleMessage(
      "Follow connection",
    ),
    "themeSkyModeFollowDesc": MessageLookupByLibrary.simpleMessage(
      "Sunny sky when connected, starry night when off",
    ),
    "themeSkyModeNight": MessageLookupByLibrary.simpleMessage(
      "Always Starry Night",
    ),
    "themeSkyModeNightDesc": MessageLookupByLibrary.simpleMessage(
      "Keep the dark starry sky even while connected",
    ),
    "themeSkyStatusConnecting": MessageLookupByLibrary.simpleMessage(
      "Pre-dawn · Connecting",
    ),
    "themeSkyStatusCustomBgActive": MessageLookupByLibrary.simpleMessage(
      "Custom wallpaper active · Syncing UI brightness",
    ),
    "themeSkyStatusDayConnected": MessageLookupByLibrary.simpleMessage(
      "Sunny Day · Connected",
    ),
    "themeSkyStatusLockedDay": MessageLookupByLibrary.simpleMessage(
      "Sunny Day · Locked",
    ),
    "themeSkyStatusLockedNight": MessageLookupByLibrary.simpleMessage(
      "Starry Night · Locked",
    ),
    "themeSkyStatusNightDisconnected": MessageLookupByLibrary.simpleMessage(
      "Starry Night · Disconnected",
    ),
    "themeTextScaleDefaultDesc": MessageLookupByLibrary.simpleMessage(
      "Follow system default (100%)",
    ),
    "threeColumns": MessageLookupByLibrary.simpleMessage("Three columns"),
    "tight": MessageLookupByLibrary.simpleMessage("Tight"),
    "time": MessageLookupByLibrary.simpleMessage("Time"),
    "tip": MessageLookupByLibrary.simpleMessage("tip"),
    "toggle": MessageLookupByLibrary.simpleMessage("Toggle"),
    "tonalSpotScheme": MessageLookupByLibrary.simpleMessage("TonalSpot"),
    "tooFrequentOperation": MessageLookupByLibrary.simpleMessage(
      "Please wait 15 seconds before refreshing again",
    ),
    "tools": MessageLookupByLibrary.simpleMessage("Settings"),
    "tproxyPort": MessageLookupByLibrary.simpleMessage("Tproxy Port"),
    "traffic": MessageLookupByLibrary.simpleMessage("Traffic"),
    "trafficUnlimited": MessageLookupByLibrary.simpleMessage(
      "Unlimited Traffic",
    ),
    "trafficUsage": MessageLookupByLibrary.simpleMessage("Traffic usage"),
    "tributeDialogTitle": MessageLookupByLibrary.simpleMessage(
      "Open-Source Tribute & Special Credits",
    ),
    "tributeFlclashxBadge": MessageLookupByLibrary.simpleMessage(
      "OPEN-SOURCE HERITAGE",
    ),
    "tributeFlclashxBody": MessageLookupByLibrary.simpleMessage(
      "FreedomNet solemnly declares that this software is built upon the open-source project FlClashX (pluralplay/FlClashX), inheriting the FlClash and Mihomo (Clash.Meta) ecosystem. With our deepest respect and gratitude to the original authors and all upstream open-source contributors.",
    ),
    "tributeFlclashxTitle": MessageLookupByLibrary.simpleMessage(
      "Built Upon Open-Source Project FlClashX",
    ),
    "tributeGeminiBadge": MessageLookupByLibrary.simpleMessage(
      "ENGINEERING & DESIGN SUPPORT",
    ),
    "tributeGeminiBody": MessageLookupByLibrary.simpleMessage(
      "Special thanks to Gemini 4 for supporting FreedomNet\'s architecture evolution, commercial UI/UX design, engineering refactoring, and automated verification.",
    ),
    "tributeGeminiTitle": MessageLookupByLibrary.simpleMessage(
      "Special Thanks to Gemini 4",
    ),
    "tun": MessageLookupByLibrary.simpleMessage("TUN"),
    "tunDesc": MessageLookupByLibrary.simpleMessage(
      "only effective in administrator mode",
    ),
    "tunDisableAction": MessageLookupByLibrary.simpleMessage("Request stop"),
    "tunErrorAdapterCreate": MessageLookupByLibrary.simpleMessage(
      "Windows could not add the virtual adapter; try again later",
    ),
    "tunErrorAuthorization": MessageLookupByLibrary.simpleMessage(
      "Administrator authorization required; enable to retry",
    ),
    "tunErrorComponents": MessageLookupByLibrary.simpleMessage(
      "Background components differ; enable to update",
    ),
    "tunErrorConfiguration": MessageLookupByLibrary.simpleMessage(
      "Configuration was not applied",
    ),
    "tunErrorLegacyAgent": MessageLookupByLibrary.simpleMessage(
      "Exit the old background app, then reopen this version",
    ),
    "tunErrorProfileRequired": MessageLookupByLibrary.simpleMessage(
      "Select a readable, non-empty profile before connecting",
    ),
    "tunErrorStart": MessageLookupByLibrary.simpleMessage(
      "Interface could not start; enable to retry",
    ),
    "tunErrorStop": MessageLookupByLibrary.simpleMessage(
      "Could not stop; verify the current state",
    ),
    "tunErrorUnavailable": MessageLookupByLibrary.simpleMessage(
      "Cannot verify status; check the background version",
    ),
    "tunStatusFailure": m80,
    "tunStatusOff": MessageLookupByLibrary.simpleMessage("Not running"),
    "tunStatusOn": MessageLookupByLibrary.simpleMessage("Running"),
    "tunStatusStarting": MessageLookupByLibrary.simpleMessage("Starting…"),
    "tunStatusStopping": MessageLookupByLibrary.simpleMessage("Stopping…"),
    "tunStatusUnknown": MessageLookupByLibrary.simpleMessage("Status unknown"),
    "tunStatusWaiting": MessageLookupByLibrary.simpleMessage(
      "Enable when proxy starts",
    ),
    "tvSyncApplying": MessageLookupByLibrary.simpleMessage(
      "Receiving profile from phone…",
    ),
    "tvSyncCouldNotGetIp": MessageLookupByLibrary.simpleMessage(
      "Could not obtain LAN IP address",
    ),
    "tvSyncFailed": MessageLookupByLibrary.simpleMessage(
      "Failed to add profile",
    ),
    "tvSyncScanQrHint": MessageLookupByLibrary.simpleMessage(
      "Scan the QR code with your phone camera",
    ),
    "tvSyncSuccess": MessageLookupByLibrary.simpleMessage("Profile added"),
    "tvSyncWebApplying": MessageLookupByLibrary.simpleMessage(
      "Importing subscription on device…",
    ),
    "tvSyncWebConnectionLost": MessageLookupByLibrary.simpleMessage(
      "Connection to device lost",
    ),
    "tvSyncWebEmptyUrl": MessageLookupByLibrary.simpleMessage(
      "Please paste a subscription URL",
    ),
    "tvSyncWebErrorPrefix": MessageLookupByLibrary.simpleMessage("❌ Error: "),
    "tvSyncWebHeading": MessageLookupByLibrary.simpleMessage(
      "Import Subscription",
    ),
    "tvSyncWebPageTitle": MessageLookupByLibrary.simpleMessage(
      "FreedomNet — Import Subscription",
    ),
    "tvSyncWebPaste": MessageLookupByLibrary.simpleMessage("Paste"),
    "tvSyncWebReceived": MessageLookupByLibrary.simpleMessage(
      "Link received by device…",
    ),
    "tvSyncWebRejected": MessageLookupByLibrary.simpleMessage(
      "The device rejected the subscription URL",
    ),
    "tvSyncWebSend": MessageLookupByLibrary.simpleMessage("Send"),
    "tvSyncWebSending": MessageLookupByLibrary.simpleMessage("Sending…"),
    "tvSyncWebSubtitle": MessageLookupByLibrary.simpleMessage(
      "Paste your subscription link and tap \"Send\" — it will sync to this device automatically.",
    ),
    "tvSyncWebSuccess": MessageLookupByLibrary.simpleMessage(
      "✅ Done! Subscription added to device",
    ),
    "tvSyncWebUnreachable": MessageLookupByLibrary.simpleMessage(
      "Could not reach the receiving device",
    ),
    "twoColumns": MessageLookupByLibrary.simpleMessage("Two columns"),
    "unableToUpdateCurrentProfileDesc": MessageLookupByLibrary.simpleMessage(
      "unable to update current profile",
    ),
    "undo": MessageLookupByLibrary.simpleMessage("undo"),
    "unifiedDelay": MessageLookupByLibrary.simpleMessage("Unified delay"),
    "unifiedDelayDesc": MessageLookupByLibrary.simpleMessage(
      "Remove extra delays such as handshaking",
    ),
    "unknown": MessageLookupByLibrary.simpleMessage("Unknown"),
    "unnamed": MessageLookupByLibrary.simpleMessage("Unnamed"),
    "untilDate": MessageLookupByLibrary.simpleMessage("until"),
    "update": MessageLookupByLibrary.simpleMessage("Update"),
    "updateAllGeoData": MessageLookupByLibrary.simpleMessage(
      "Update All Geo Files",
    ),
    "updated": MessageLookupByLibrary.simpleMessage("Updated"),
    "upload": MessageLookupByLibrary.simpleMessage("Upload"),
    "url": MessageLookupByLibrary.simpleMessage("URL"),
    "urlDesc": MessageLookupByLibrary.simpleMessage(
      "Obtain profile through URL",
    ),
    "urlTip": m81,
    "useHosts": MessageLookupByLibrary.simpleMessage("Use hosts"),
    "useSystemHosts": MessageLookupByLibrary.simpleMessage("Use system hosts"),
    "value": MessageLookupByLibrary.simpleMessage("Value"),
    "vibrantScheme": MessageLookupByLibrary.simpleMessage("Vibrant"),
    "view": MessageLookupByLibrary.simpleMessage("View"),
    "vpnDesc": MessageLookupByLibrary.simpleMessage(
      "Modify VPN related settings",
    ),
    "vpnEnableDesc": MessageLookupByLibrary.simpleMessage(
      "Auto routes all system traffic through VpnService",
    ),
    "vpnSystemProxyDesc": MessageLookupByLibrary.simpleMessage(
      "Attach HTTP proxy to VpnService",
    ),
    "vpnTip": MessageLookupByLibrary.simpleMessage(
      "Changes take effect after restarting the VPN",
    ),
    "webDAVConfiguration": MessageLookupByLibrary.simpleMessage(
      "WebDAV configuration",
    ),
    "wechatId": MessageLookupByLibrary.simpleMessage("WeChat ID"),
    "whitelistMode": MessageLookupByLibrary.simpleMessage("Whitelist mode"),
    "whitelistModeDesc": MessageLookupByLibrary.simpleMessage(
      "Only the selected apps are routed through the VPN; all others connect directly.",
    ),
    "years": MessageLookupByLibrary.simpleMessage("Years"),
    "zashboardInApp": MessageLookupByLibrary.simpleMessage(
      "Open zashboard in the app",
    ),
    "zashboardInAppDesc": MessageLookupByLibrary.simpleMessage(
      "Show the control panel in the built-in browser instead of switching to an external one",
    ),
    "zh_CN": MessageLookupByLibrary.simpleMessage("Simplified Chinese"),
  };
}

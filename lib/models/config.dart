// ignore_for_file: invalid_annotation_target

import 'package:flclashx/common/common.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'models.dart';

part 'generated/config.freezed.dart';
part 'generated/config.g.dart';

const defaultBypassDomain = [
  "*zhihu.com",
  "*zhimg.com",
  "*jd.com",
  "100ime-iat-api.xfyun.cn",
  "*360buyimg.com",
  "localhost",
  "*.local",
  "127.*",
  "10.*",
  "172.16.*",
  "172.17.*",
  "172.18.*",
  "172.19.*",
  "172.2*",
  "172.30.*",
  "172.31.*",
  "192.168.*"
];

const defaultAppSettingProps = AppSettingProps();
const defaultVpnProps = VpnProps();
const defaultNetworkProps = NetworkProps();
const defaultGlobalOverrideData = OverrideData(enable: true);
const defaultProxiesStyle = ProxiesStyle();
const defaultWindowProps = WindowProps();
const defaultAccessControl = AccessControl();
const defaultThemeProps = ThemeProps(
  primaryColor: defaultPrimaryColor,
  themeMode: ThemeMode.dark,
);

const defaultConnectionTableColumns = [
  'status',
  'time',
  'type',
  'host',
  'process',
  'rule',
  'chains',
  'remoteDestination',
  'uploadSpeed',
  'downloadSpeed',
  'upload',
  'download',
];

const List<DashboardWidget> defaultDashboardWidgets = [
  DashboardWidget.metainfo,
  DashboardWidget.networkSpeed,
  DashboardWidget.outboundModeV2,
];

List<DashboardWidget> normalizeDashboardWidgets(
  Iterable<DashboardWidget> items, {
  bool dropRedundantAnnounce = false,
}) {
  final hasMetainfo = items.contains(DashboardWidget.metainfo);
  final normalized = <DashboardWidget>[];
  for (final raw in items) {
    if (dropRedundantAnnounce &&
        hasMetainfo &&
        raw == DashboardWidget.announce) {
      continue;
    }
    final resolved = raw == DashboardWidget.trafficUsage
        ? DashboardWidget.networkSpeed
        : raw;
    if (!normalized.contains(resolved)) {
      normalized.add(resolved);
    }
  }
  return normalized;
}

List<DashboardWidget> dashboardWidgetsSafeFormJson(
  List<dynamic>? dashboardWidgets,
) {
  if (dashboardWidgets == null) {
    return defaultDashboardWidgets;
  }
  try {
    final decoded = <DashboardWidget>[];
    for (final item in dashboardWidgets) {
      final parsed = $enumDecodeNullable(_$DashboardWidgetEnumMap, item);
      if (parsed != null) {
        decoded.add(parsed);
      }
    }
    return normalizeDashboardWidgets(decoded);
  } catch (_) {
    return defaultDashboardWidgets;
  }
}

@freezed
class AppSettingProps with _$AppSettingProps {
  const factory AppSettingProps({
    String? locale,
    @Default(defaultDashboardWidgets)
    @JsonKey(fromJson: dashboardWidgetsSafeFormJson)
    List<DashboardWidget> dashboardWidgets,
    @Default(true) bool dashboardDefaultV2Migrated,
    @Default(true) bool tunDesktopStackGvisorRestored,
    @Default(true) bool dnsRespectRulesDefaultMigrated,
    @Default(false) bool onlyStatisticsProxy,
    @Default(false) bool autoLaunch,
    @Default(false) bool silentLaunch,
    @Default(false) bool autoRun,
    @Default(false) bool openLogs,
    @Default(true) bool closeConnections,
    @Default(defaultTestUrl) String testUrl,
    @Default(true) bool isAnimateToPage,
    @Default(false) bool autoCheckUpdate,
    @Default(false) bool showLabel,
    @Default(false) bool disclaimerAccepted,
    @Default(false) bool minimizeOnExit,
    @Default(false) bool hidden,
    @Default(false) bool developerMode,
    @Default(true) bool crashlytics,
    @Default(true) bool zashboardInApp,
    @Default(false) bool overrideProviderSettings,
    @Default(false) bool overrideNetworkSettings,
    @Default(RecoveryStrategy.compatible) RecoveryStrategy recoveryStrategy,
    @JsonKey(unknownEnumValue: ConnectionListMode.process)
    @Default(ConnectionListMode.process)
    ConnectionListMode connectionListMode,
    @JsonKey(unknownEnumValue: ConnectionViewMode.list)
    @Default(ConnectionViewMode.list)
    ConnectionViewMode connectionViewMode,
    @JsonKey(unknownEnumValue: ConnectionSort.time)
    @Default(ConnectionSort.time)
    ConnectionSort connectionSort,
    @JsonKey(unknownEnumValue: ConnectionSortDirection.descending)
    @Default(ConnectionSortDirection.descending)
    ConnectionSortDirection connectionSortDirection,
    @Default(true) bool connectionShowIcon,
    @Default(true) bool connectionUseApplicationName,
    @Default(500) int connectionRefreshInterval,
    @Default(defaultConnectionTableColumns) List<String> connectionTableColumns,
    @Default({}) Map<String, double> connectionTableColumnWidths,
    bool? newDashboard,
  }) = _AppSettingProps;

  factory AppSettingProps.fromJson(Map<String, Object?> json) =>
      _$AppSettingPropsFromJson(json);

  factory AppSettingProps.safeFromJson(Map<String, Object?>? json) =>
      json == null ? defaultAppSettingProps : AppSettingProps.fromJson(json);
}

@freezed
class AccessControl with _$AccessControl {
  const factory AccessControl({
    @Default(false) bool enable,
    @Default(AccessControlMode.rejectSelected) AccessControlMode mode,
    @Default([]) List<String> acceptList,
    @Default([]) List<String> rejectList,
    @Default(AccessSortType.none) AccessSortType sort,
    @Default(true) bool isFilterSystemApp,
    @Default(true) bool isFilterNonInternetApp,
  }) = _AccessControl;

  factory AccessControl.fromJson(Map<String, Object?> json) =>
      _$AccessControlFromJson(json);
}

extension AccessControlExt on AccessControl {
  List<String> get currentList => switch (mode) {
        AccessControlMode.acceptSelected => acceptList,
        AccessControlMode.rejectSelected => rejectList,
      };
}

@freezed
class WindowProps with _$WindowProps {
  const factory WindowProps({
    @Default(450) double width,
    @Default(900) double height,
    double? top,
    double? left,
  }) = _WindowProps;

  factory WindowProps.fromJson(Map<String, Object?>? json) =>
      json == null ? const WindowProps() : _$WindowPropsFromJson(json);
}

@freezed
class VpnProps with _$VpnProps {
  const factory VpnProps({
    @Default(true) bool enable,
    @Default(false) bool systemProxy,
    @Default(true) bool ipv6,
    @Default(false) bool allowBypass,
    @Default(defaultAccessControl) AccessControl accessControl,
  }) = _VpnProps;

  factory VpnProps.fromJson(Map<String, Object?> json) =>
      _$VpnPropsFromJson(json);
}

@freezed
class NetworkProps with _$NetworkProps {
  const factory NetworkProps({
    @Default(false) bool systemProxy,
    @Default(defaultBypassDomain) List<String> bypassDomain,
    @Default(RouteMode.config) RouteMode routeMode,
    @JsonKey(unknownEnumValue: LocalSplitMode.auto)
    @Default(LocalSplitMode.auto)
    LocalSplitMode localSplitMode,
    @Default(true) bool autoSetSystemDns,
  }) = _NetworkProps;

  factory NetworkProps.fromJson(Map<String, Object?>? json) =>
      json == null ? const NetworkProps() : _$NetworkPropsFromJson(json);
}

@freezed
class ProxiesStyle with _$ProxiesStyle {
  const factory ProxiesStyle({
    @Default(ProxiesType.list) ProxiesType type,
    @Default(ProxiesSortType.delay) ProxiesSortType sortType,
    @Default(true) bool sortTypeDefaultDelayMigrated,
    @Default(ProxiesLayout.standard) ProxiesLayout layout,
    @JsonKey(unknownEnumValue: ProxiesIconStyle.icon)
    @Default(ProxiesIconStyle.icon)
    ProxiesIconStyle iconStyle,
    @Default(ProxyCardType.expand) ProxyCardType cardType,
    @Default({}) Map<String, String> iconMap,
  }) = _ProxiesStyle;

  factory ProxiesStyle.fromJson(Map<String, Object?>? json) =>
      json == null ? defaultProxiesStyle : _$ProxiesStyleFromJson(json);
}

@freezed
class TextScale with _$TextScale {
  const factory TextScale({
    @Default(false) enable,
    @Default(1.0) scale,
  }) = _TextScale;

  factory TextScale.fromJson(Map<String, Object?> json) =>
      _$TextScaleFromJson(json);
}

@freezed
class ThemeProps with _$ThemeProps {
  const factory ThemeProps({
    int? primaryColor,
    @Default(defaultPrimaryColors) List<int> primaryColors,
    @Default(ThemeMode.system) ThemeMode themeMode,
    @Default(DynamicSchemeVariant.content) DynamicSchemeVariant schemeVariant,
    @Default(false) bool pureBlack,
    @Default(TextScale()) TextScale textScale,
  }) = _ThemeProps;

  factory ThemeProps.fromJson(Map<String, Object?> json) =>
      _$ThemePropsFromJson(json);

  factory ThemeProps.safeFromJson(Map<String, Object?>? json) {
    if (json == null) {
      return defaultThemeProps;
    }
    try {
      return ThemeProps.fromJson(json);
    } catch (_) {
      return defaultThemeProps;
    }
  }
}

@freezed
class ScriptProps with _$ScriptProps {
  const factory ScriptProps({
    String? currentId,
    @Default([]) List<Script> scripts,
  }) = _ScriptProps;

  factory ScriptProps.fromJson(Map<String, Object?> json) =>
      _$ScriptPropsFromJson(json);
}

extension ScriptPropsExt on ScriptProps {
  String? get realId {
    final index = scripts.indexWhere((script) => script.id == currentId);
    if (index != -1) {
      return currentId;
    }
    return null;
  }

  Script? get currentScript {
    final index = scripts.indexWhere((script) => script.id == currentId);
    if (index != -1) {
      return scripts[index];
    }
    return null;
  }
}

@freezed
class Config with _$Config {
  const factory Config({
    @JsonKey(fromJson: AppSettingProps.safeFromJson)
    @Default(defaultAppSettingProps)
    AppSettingProps appSetting,
    @Default([]) List<Profile> profiles,
    @Default([]) List<HotKeyAction> hotKeyActions,
    String? currentProfileId,
    @Default(false) bool overrideDns,
    DAV? dav,
    @Default(defaultNetworkProps) NetworkProps networkProps,
    @Default(defaultVpnProps) VpnProps vpnProps,
    @JsonKey(fromJson: ThemeProps.safeFromJson) required ThemeProps themeProps,
    @Default(defaultProxiesStyle) ProxiesStyle proxiesStyle,
    @Default(defaultWindowProps) WindowProps windowProps,
    @Default(defaultClashConfig) ClashConfig patchClashConfig,
    @Default(ScriptProps()) ScriptProps scriptProps,
    @Default(defaultGlobalOverrideData) OverrideData globalOverrideData,
  }) = _Config;

  factory Config.fromJson(Map<String, Object?> json) => _$ConfigFromJson(json);

  factory Config.compatibleFromJson(
    Map<String, Object?> json, {
    bool? isDesktop,
  }) {
    final effectiveIsDesktop = isDesktop ?? system.isDesktop;
    final normalizedJson = Map<String, Object?>.from(json);
    try {
      final accessControlMap = normalizedJson["accessControl"];
      final isAccessControl = normalizedJson["isAccessControl"];
      if (accessControlMap is Map) {
        final nextAccessControl = Map<String, Object?>.from(accessControlMap);
        nextAccessControl["enable"] = isAccessControl;
        normalizedJson["accessControl"] = nextAccessControl;
        final vpnProps = normalizedJson["vpnProps"];
        if (vpnProps is Map) {
          final nextVpnProps = Map<String, Object?>.from(vpnProps);
          nextVpnProps["accessControl"] = nextAccessControl;
          normalizedJson["vpnProps"] = nextVpnProps;
        }
      }
    } catch (_) {}

    try {
      // Migration: Replace deprecated "standard" iconStyle with "icon" and
      // promote legacy unmigrated default sortType ("none") to "delay" once.
      final proxiesStyle = normalizedJson["proxiesStyle"];
      if (proxiesStyle is Map) {
        final nextProxiesStyle = Map<String, Object?>.from(proxiesStyle);
        if (nextProxiesStyle["iconStyle"] == "standard") {
          nextProxiesStyle["iconStyle"] = "icon";
        }
        final rawSort = nextProxiesStyle["sortType"];
        if (rawSort is! String ||
            !const {'none', 'delay', 'name'}.contains(rawSort)) {
          nextProxiesStyle.remove("sortType");
        }
        if (nextProxiesStyle["sortTypeDefaultDelayMigrated"] != true) {
          if (nextProxiesStyle["sortType"] == null ||
              nextProxiesStyle["sortType"] == "none") {
            nextProxiesStyle["sortType"] = "delay";
          }
          nextProxiesStyle["sortTypeDefaultDelayMigrated"] = true;
        }
        normalizedJson["proxiesStyle"] = nextProxiesStyle;
      } else if (proxiesStyle != null) {
        normalizedJson.remove("proxiesStyle");
      }
    } catch (_) {}

    try {
      // Migration: promote unified networkSpeed + trafficUsage card once for
      // legacy unmigrated configs, deduplicating legacy trafficUsage/announce
      // while preserving any subsequent user hide preference.
      final appSetting = normalizedJson["appSetting"];
      if (appSetting is Map) {
        final nextAppSetting = Map<String, Object?>.from(appSetting);
        if (nextAppSetting["dashboardDefaultV2Migrated"] != true) {
          final rawWidgets = nextAppSetting["dashboardWidgets"];
          if (rawWidgets is List) {
            final stringWidgets = <String>[];
            final hasMetainfo = rawWidgets.any((e) => e == "metainfo");
            for (final item in rawWidgets) {
              if (item is! String) continue;
              if (hasMetainfo && item == "announce") continue;
              final mapped =
                  item == "trafficUsage" ? "networkSpeed" : item;
              if (!stringWidgets.contains(mapped)) {
                stringWidgets.add(mapped);
              }
            }
            if (!stringWidgets.contains("networkSpeed")) {
              final metainfoIdx = stringWidgets.indexOf("metainfo");
              if (metainfoIdx >= 0) {
                stringWidgets.insert(metainfoIdx + 1, "networkSpeed");
              } else {
                stringWidgets.insert(0, "networkSpeed");
              }
            }
            nextAppSetting["dashboardWidgets"] = stringWidgets;
          }
          nextAppSetting["dashboardDefaultV2Migrated"] = true;
        }
        normalizedJson["appSetting"] = nextAppSetting;
      } else if (appSetting != null) {
        normalizedJson.remove("appSetting");
      }
    } catch (_) {}

    try {
      // Migration: strip removed fields from profiles
      final profiles = normalizedJson["profiles"];
      if (profiles is List) {
        normalizedJson["profiles"] = [
          for (final p in profiles)
            if (p is Map)
              (Map<String, Object?>.from(p)..remove("updateMethod"))
            else
              p,
        ];
      }
    } catch (_) {}

    try {
      // One-shot desktop recovery migration: both f329535-migrated configs and
      // legacy desktop installs created when `const Tun()` defaulted to `mixed`
      // are upgraded once to `gvisor` while preserving explicit `system`/`mips`
      // and any manual `mixed` choice saved after `tunDesktopStackGvisorRestored`.
      if (effectiveIsDesktop) {
        final rawAppSetting = normalizedJson["appSetting"];
        final alreadyRestored = rawAppSetting is Map &&
            rawAppSetting["tunDesktopStackGvisorRestored"] == true;
        if (!alreadyRestored) {
          final rawPatchClash = normalizedJson["patchClashConfig"];
          if (rawPatchClash is Map) {
            final rawTun = rawPatchClash["tun"];
            if (rawTun is Map) {
              final rawStack = rawTun["stack"];
              if (rawStack == null || rawStack == "mixed") {
                final nextTun = Map<String, Object?>.from(rawTun);
                nextTun["stack"] = "gvisor";
                final nextPatchClash = Map<String, Object?>.from(rawPatchClash);
                nextPatchClash["tun"] = nextTun;
                normalizedJson["patchClashConfig"] = nextPatchClash;
              }
            } else if (rawTun == null) {
              final nextPatchClash = Map<String, Object?>.from(rawPatchClash);
              nextPatchClash["tun"] = <String, Object?>{"stack": "gvisor"};
              normalizedJson["patchClashConfig"] = nextPatchClash;
            }
          } else if (rawPatchClash == null) {
            normalizedJson["patchClashConfig"] = <String, Object?>{
              "tun": <String, Object?>{"stack": "gvisor"},
            };
          }
          if (rawAppSetting is Map) {
            final nextAppSetting = Map<String, Object?>.from(rawAppSetting);
            nextAppSetting.remove("tunDesktopStackMixedMigrated");
            nextAppSetting["tunDesktopStackGvisorRestored"] = true;
            normalizedJson["appSetting"] = nextAppSetting;
          } else if (rawAppSetting == null) {
            normalizedJson["appSetting"] = <String, Object?>{
              "tunDesktopStackGvisorRestored": true,
            };
          }
        }
      }
    } catch (_) {}

    try {
      final rawAppSetting = normalizedJson["appSetting"];
      final alreadyMigratedDns = rawAppSetting is Map &&
          rawAppSetting["dnsRespectRulesDefaultMigrated"] == true;
      if (!alreadyMigratedDns) {
        final rawPatchClash = normalizedJson["patchClashConfig"];
        if (rawPatchClash is Map) {
          final rawDns = rawPatchClash["dns"];
          if (rawDns is Map) {
            final parsedDns = Dns.safeDnsFromJson(
              Map<String, Object?>.from(rawDns),
            );
            if (parsedDns == const Dns(respectRules: false)) {
              final nextDns = Map<String, Object?>.from(rawDns);
              nextDns["respect-rules"] = true;
              final nextPatchClash = Map<String, Object?>.from(rawPatchClash);
              nextPatchClash["dns"] = nextDns;
              normalizedJson["patchClashConfig"] = nextPatchClash;
            }
          }
        }
        final latestAppSetting = normalizedJson["appSetting"];
        if (latestAppSetting is Map) {
          final nextAppSetting = Map<String, Object?>.from(latestAppSetting);
          nextAppSetting["dnsRespectRulesDefaultMigrated"] = true;
          normalizedJson["appSetting"] = nextAppSetting;
        } else if (latestAppSetting == null) {
          normalizedJson["appSetting"] = <String, Object?>{
            "dnsRespectRulesDefaultMigrated": true,
          };
        }
      }
    } catch (_) {}

    try {
      final globalOverride = normalizedJson["globalOverrideData"];
      if (globalOverride != null && globalOverride is! Map) {
        normalizedJson.remove("globalOverrideData");
      }
    } catch (_) {}

    return Config.fromJson(normalizedJson);
  }
}

extension ConfigExt on Config {
  Profile? get currentProfile => profiles.getProfile(currentProfileId);
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flclashx/common/delay_test_coordinator.dart';
import 'package:flclashx/common/design_system.dart';
import 'package:flclashx/common/health/health_environment.dart';
import 'package:flclashx/common/health/health_models.dart';
import 'package:flclashx/common/health/health_verdict.dart';
import 'package:flclashx/common/tun_runtime.dart';
import 'package:flclashx/common/windows_system_proxy_probe.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class _HealthCancelledException implements Exception {
  const _HealthCancelledException();
}

class HealthRunner {
  HealthRunner(this.environment);

  static const List<String> directConnectivityProbeUrls = [
    'http://connectivitycheck.platform.hicloud.com/generate_204',
    'http://connect.rom.miui.com/generate_204',
    'http://www.msftconnecttest.com/connecttest.txt',
  ];

  static const List<String> outboundFallbackProbeUrls = [
    'https://cp.cloudflare.com/generate_204',
    'http://www.gstatic.com/generate_204',
    'https://www.google.com/generate_204',
    'http://cp.cloudflare.com/generate_204',
  ];

  static String _selectOutboundFallbackUrl(String primaryUrl) {
    final primaryHost = Uri.tryParse(primaryUrl)?.host.toLowerCase() ?? '';
    final primaryIsCloudflare = primaryHost.contains('cloudflare');
    final primaryIsGoogle =
        primaryHost.contains('gstatic') || primaryHost.contains('google');
    return outboundFallbackProbeUrls.firstWhere(
      (candidate) {
        if (candidate == primaryUrl) return false;
        final candidateHost =
            Uri.tryParse(candidate)?.host.toLowerCase() ?? '';
        if (primaryIsCloudflare) {
          return !candidateHost.contains('cloudflare');
        }
        if (primaryIsGoogle) {
          return !candidateHost.contains('gstatic') &&
              !candidateHost.contains('google');
        }
        return true;
      },
      orElse: () => outboundFallbackProbeUrls.firstWhere(
        (u) => u != primaryUrl,
        orElse: () => '',
      ),
    );
  }

  static const List<String> systemDnsProbeHosts = [
    'connectivitycheck.platform.hicloud.com',
    'www.msftconnecttest.com',
  ];

  final HealthProbeEnvironment environment;
  bool _running = false;
  int _sequence = 0;

  bool get isRunning => _running;

  static DateTime? _parseExpireUtc(int rawExpire) {
    if (rawExpire <= 0) return null;
    final ms = rawExpire >= 100000000000 ? rawExpire : rawExpire * 1000;
    if (ms <= 0 || ms > 253402300799000) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  static String? _decodeServerInfoHeader(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    var text = raw.trim();
    if (text.startsWith('base64:')) {
      text = text.substring(7).trim();
    }
    if (text.isEmpty) return null;
    try {
      final normalized = base64.normalize(text);
      final decoded = utf8.decode(base64.decode(normalized)).trim();
      return decoded.isEmpty ? null : decoded;
    } catch (_) {
      return raw.trim().isEmpty ? null : raw.trim();
    }
  }

  static Group? _selectActiveGroup(
    HealthConfigSnapshot cfg, {
    required bool preferRuntimeNow,
  }) {
    if (cfg.mode == Mode.global) {
      return cfg.allGroups.getGroup(GroupName.GLOBAL.name) ??
          (cfg.visibleGroups.isNotEmpty ? cfg.visibleGroups.first : null);
    }
    final serverInfoGroup = _decodeServerInfoHeader(
      cfg.currentProfile?.providerHeaders['flclashx-serverinfo'],
    );
    if (serverInfoGroup != null && serverInfoGroup.isNotEmpty) {
      final found = cfg.allGroups.getGroup(serverInfoGroup);
      if (found != null) return found;
    }

    final ruleTarget = cfg.primaryRuleTargetGroup?.trim();
    if (ruleTarget != null &&
        ruleTarget.isNotEmpty &&
        ruleTarget.toUpperCase() != GroupName.GLOBAL.name) {
      final found = cfg.allGroups.getGroup(ruleTarget);
      if (found != null) return found;
    }

    bool resolvesToRealProxy(Group group) {
      final res = _resolveSelectedLeaf(
        group,
        cfg.allGroups,
        cfg.selectedMap,
        preferRuntimeNow: preferRuntimeNow,
      );
      final leaf = res.leaf;
      return leaf != null &&
          leaf != 'DIRECT' &&
          leaf != 'REJECT' &&
          leaf != 'REJECT-DROP';
    }

    Group? preferredGroup;
    final preferred = cfg.currentProfile?.currentGroupName?.trim();
    if (preferred != null &&
        preferred.isNotEmpty &&
        preferred.toUpperCase() != GroupName.GLOBAL.name) {
      preferredGroup = cfg.visibleGroups.getGroup(preferred);
      if (preferredGroup == null) {
        final foundAll = cfg.allGroups.getGroup(preferred);
        if (foundAll != null && foundAll.hidden != true) {
          preferredGroup = foundAll;
        }
      }
      if (preferredGroup != null && resolvesToRealProxy(preferredGroup)) {
        return preferredGroup;
      }
    }

    for (final group in cfg.visibleGroups) {
      if (group.name != GroupName.GLOBAL.name && resolvesToRealProxy(group)) {
        return group;
      }
    }
    for (final group in cfg.allGroups) {
      if (group.name != GroupName.GLOBAL.name &&
          group.hidden != true &&
          resolvesToRealProxy(group)) {
        return group;
      }
    }

    if (preferredGroup != null) {
      return preferredGroup;
    }
    if (cfg.visibleGroups.isNotEmpty) {
      return cfg.visibleGroups.first;
    }
    for (final group in cfg.allGroups) {
      if (group.name != GroupName.GLOBAL.name && group.hidden != true) {
        return group;
      }
    }
    return cfg.allGroups.isNotEmpty ? cfg.allGroups.first : null;
  }

  static ({String? leaf, String? failureReason, Group? dynamicGroup})
      _resolveSelectedLeaf(
    Group entryGroup,
    List<Group> allGroups,
    Map<String, String> selectedMap, {
    required bool preferRuntimeNow,
  }) {
    final visited = <String>{};
    var current = entryGroup;
    Group? dynamicGroup;
    while (visited.add(current.name) && visited.length <= 32) {
      if (const {
        GroupType.URLTest,
        GroupType.Fallback,
        GroupType.LoadBalance,
      }.contains(current.type)) {
        dynamicGroup ??= current;
      }
      final picked = (preferRuntimeNow && current.realNow.isNotEmpty)
          ? current.realNow
          : current.getCurrentSelectedName(selectedMap[current.name] ?? '');
      if (picked == current.name) {
        return (
          leaf: null,
          failureReason: 'outboundGroupLoop',
          dynamicGroup: dynamicGroup,
        );
      }
      if (picked.isEmpty) {
        if (current.all.isEmpty) {
          return (
            leaf: null,
            failureReason: 'outboundGroupMissing',
            dynamicGroup: dynamicGroup,
          );
        }
        // LoadBalance, Relay, and unprobed lazy URLTest/Fallback groups
        // legitimately report an empty `now` in Mihomo; return the group name
        // so D3 delay-tests the group itself through Core.
        return (
          leaf: current.name,
          failureReason: null,
          dynamicGroup: dynamicGroup,
        );
      }
      if (picked == 'DIRECT' || picked == 'REJECT' || picked == 'REJECT-DROP') {
        return (
          leaf: picked,
          failureReason: null,
          dynamicGroup: dynamicGroup,
        );
      }
      final nextGroup = allGroups.getGroup(picked);
      if (nextGroup == null) {
        return (
          leaf: picked,
          failureReason: null,
          dynamicGroup: dynamicGroup,
        );
      }
      current = nextGroup;
    }
    return (
      leaf: null,
      failureReason: 'outboundGroupLoop',
      dynamicGroup: dynamicGroup,
    );
  }

  static Set<String> _collectReachableProxyLeaves(
    Group rootGroup,
    List<Group> allGroups,
  ) {
    final leaves = <String>{};
    final visitedGroups = <String>{};
    void visit(Group group) {
      if (!visitedGroups.add(group.name) || visitedGroups.length > 64) {
        return;
      }
      for (final proxy in group.all) {
        final name = proxy.name;
        if (name.isEmpty ||
            name == 'DIRECT' ||
            name == 'REJECT' ||
            name == 'REJECT-DROP') {
          continue;
        }
        final nested = allGroups.getGroup(name);
        if (nested != null) {
          visit(nested);
        } else {
          leaves.add(name);
        }
      }
    }

    visit(rootGroup);
    return leaves;
  }

  @visibleForTesting
  static String mapTunFailureReason(String? code) => switch (code) {
        'permissionDenied' ||
        'authorizationRequired' =>
          'tunAuthorizationRequired',
        'componentsMismatch' => 'tunComponentsMismatch',
        'legacyAgent' => 'tunLegacyAgent',
        'interfaceMissing' => 'tunInterfaceMissing',
        'interfaceDown' => 'tunInterfaceDown',
        'configurationFailed' => 'tunConfigurationFailed',
        'adapterCreateFailed' => 'tunAdapterCreateFailed',
        'statusUnavailable' || 'invalidStatus' => 'tunStatusUnavailable',
        _ => 'tunStartFailed',
      };

  static bool _isPoisonedAddress(InternetAddress address) {
    final raw = address.rawAddress;
    if (address.type == InternetAddressType.IPv4 && raw.length == 4) {
      if (raw[0] == 0 && raw[1] == 0 && raw[2] == 0 && raw[3] == 0) {
        return true;
      }
      if (raw[0] == 127) {
        return true;
      }
    } else if (address.type == InternetAddressType.IPv6 && raw.length == 16) {
      var allZero = true;
      var loopback = true;
      for (var i = 0; i < 16; i++) {
        if (raw[i] != 0) allZero = false;
        if (i < 15 && raw[i] != 0) loopback = false;
        if (i == 15 && raw[i] != 1) loopback = false;
      }
      if (allZero || loopback) return true;
    }
    return false;
  }

  static bool _isFakeIpAddress(InternetAddress address) {
    final raw = address.rawAddress;
    return address.type == InternetAddressType.IPv4 &&
        raw.length == 4 &&
        raw[0] == 198 &&
        (raw[1] == 18 || raw[1] == 19);
  }

  Future<HealthReport> run({
    HealthCancellationToken? cancelToken,
    void Function(Map<HealthCheckId, HealthCheckResult> snapshot)? onProgress,
  }) async {
    if (_running) {
      throw StateError('Health check already running');
    }
    _running = true;
    final token = cancelToken ?? HealthCancellationToken();
    final seq = ++_sequence;
    final startedAt = environment.now();
    final totalWatch = Stopwatch()..start();

    final state = <HealthCheckId, HealthCheckResult>{};

    void emitProgress() {
      if (token.isCancelled || onProgress == null) return;
      onProgress(Map<HealthCheckId, HealthCheckResult>.unmodifiable(state));
    }

    void markRunning(Iterable<HealthCheckId> ids) {
      for (final id in ids) {
        state[id] = HealthCheckResult(
          id: id,
          status: HealthStatus.running,
          elapsedMs: 0,
          reasonCode: 'running',
        );
      }
      emitProgress();
    }

    void record(HealthCheckResult result) {
      if (token.isCancelled) throw const _HealthCancelledException();
      state[result.id] = result;
      emitProgress();
    }

    Future<T> raceCancel<T>(Future<T> future) => Future.any<T>([
          future,
          token.onCancelled
              .then<T>((_) => throw const _HealthCancelledException()),
        ]);

    try {
      if (token.isCancelled) throw const _HealthCancelledException();

      markRunning(const [
        HealthCheckId.profileSelected,
        HealthCheckId.subscriptionHealth,
        HealthCheckId.runtimeConfigLoaded,
        HealthCheckId.coreResponsive,
        HealthCheckId.proxyStarted,
        HealthCheckId.tunTakeover,
        HealthCheckId.systemProxyTakeover,
        HealthCheckId.trafficTakeover,
      ]);

      final cfgWatch = Stopwatch()..start();
      final cfg = await raceCancel(environment.readConfigSnapshot());
      final cfgElapsed = cfgWatch.elapsedMilliseconds;

      // A1: Current Profile
      final HealthCheckResult a1;
      if (cfg.currentProfileId == null || cfg.currentProfileId!.isEmpty) {
        a1 = HealthCheckResult(
          id: HealthCheckId.profileSelected,
          status: HealthStatus.failed,
          elapsedMs: cfgElapsed,
          reasonCode: 'noProfileSelected',
          action: HealthAction.openProfiles,
        );
      } else if (cfg.currentProfile == null) {
        a1 = HealthCheckResult(
          id: HealthCheckId.profileSelected,
          status: HealthStatus.failed,
          elapsedMs: cfgElapsed,
          reasonCode: 'profileEntityMissing',
          action: HealthAction.openProfiles,
        );
      } else if (!cfg.profileFileExists || cfg.profileFileBytes <= 0) {
        a1 = HealthCheckResult(
          id: HealthCheckId.profileSelected,
          status: HealthStatus.failed,
          elapsedMs: cfgElapsed,
          reasonCode: 'profileFileMissing',
          localDetail: cfg.currentProfile!.label ?? cfg.currentProfile!.id,
          action: HealthAction.openProfiles,
        );
      } else {
        a1 = HealthCheckResult(
          id: HealthCheckId.profileSelected,
          status: HealthStatus.passed,
          elapsedMs: cfgElapsed,
          reasonCode: 'ok',
          localDetail: cfg.currentProfile!.label ?? cfg.currentProfile!.id,
        );
      }
      record(a1);

      // A2: Subscription Status
      final HealthCheckResult a2;
      if (a1.status.isFailure) {
        a2 = const HealthCheckResult(
          id: HealthCheckId.subscriptionHealth,
          status: HealthStatus.skipped,
          elapsedMs: 0,
          reasonCode: 'prerequisiteFailed',
        );
      } else {
        final profile = cfg.currentProfile!;
        if (profile.url.trim().isEmpty) {
          a2 = const HealthCheckResult(
            id: HealthCheckId.subscriptionHealth,
            status: HealthStatus.skipped,
            elapsedMs: 0,
            reasonCode: 'localProfile',
          );
        } else {
          final sub = profile.subscriptionInfo;
          if (sub == null) {
            a2 = profile.lastUpdateDate == null
                ? const HealthCheckResult(
                    id: HealthCheckId.subscriptionHealth,
                    status: HealthStatus.warning,
                    elapsedMs: 0,
                    reasonCode: 'subscriptionNeverSynced',
                    action: HealthAction.openProfiles,
                  )
                : const HealthCheckResult(
                    id: HealthCheckId.subscriptionHealth,
                    status: HealthStatus.skipped,
                    elapsedMs: 0,
                    reasonCode: 'subscriptionMetadataUnavailable',
                  );
          } else {
            final nowUtc = environment.now().toUtc();
            final expireUtc = _parseExpireUtc(sub.expire);
            final used = math.max(0, sub.upload) + math.max(0, sub.download);
            final hasQuota = sub.total > 0;
            final ratio = hasQuota ? used / sub.total : 0.0;
            final usedPct =
                hasQuota ? (ratio * 100).round().clamp(0, 100) : null;
            final remainingDuration = expireUtc?.difference(nowUtc);
            final daysLeft = remainingDuration != null
                ? math.max(0, (remainingDuration.inHours / 24).ceil())
                : null;
            final hwidMax = profile
                .providerHeaders['x-hwid-max-devices-reached']
                ?.trim()
                .toLowerCase();

            if (expireUtc != null && !expireUtc.isAfter(nowUtc)) {
              a2 = const HealthCheckResult(
                id: HealthCheckId.subscriptionHealth,
                status: HealthStatus.failed,
                elapsedMs: 0,
                reasonCode: 'subscriptionExpired',
                action: HealthAction.openPurchase,
              );
            } else if (hasQuota && used >= sub.total) {
              a2 = const HealthCheckResult(
                id: HealthCheckId.subscriptionHealth,
                status: HealthStatus.failed,
                elapsedMs: 0,
                reasonCode: 'subscriptionTrafficExhausted',
                quotaUsedPercent: 100,
                action: HealthAction.openPurchase,
              );
            } else if (remainingDuration != null &&
                remainingDuration <= const Duration(days: 3)) {
              a2 = HealthCheckResult(
                id: HealthCheckId.subscriptionHealth,
                status: HealthStatus.warning,
                elapsedMs: 0,
                reasonCode: 'subscriptionExpiringSoon',
                daysRemaining: daysLeft,
                quotaUsedPercent: usedPct,
                action: HealthAction.openPurchase,
              );
            } else if (hasQuota && ratio >= 0.90) {
              a2 = HealthCheckResult(
                id: HealthCheckId.subscriptionHealth,
                status: HealthStatus.warning,
                elapsedMs: 0,
                reasonCode: 'subscriptionTrafficLow',
                daysRemaining: daysLeft,
                quotaUsedPercent: usedPct,
                action: HealthAction.openPurchase,
              );
            } else if (hwidMax == '1' || hwidMax == 'true') {
              a2 = const HealthCheckResult(
                id: HealthCheckId.subscriptionHealth,
                status: HealthStatus.warning,
                elapsedMs: 0,
                reasonCode: 'subscriptionDeviceLimit',
                action: HealthAction.openPurchase,
              );
            } else if (!hasQuota && expireUtc == null) {
              a2 = const HealthCheckResult(
                id: HealthCheckId.subscriptionHealth,
                status: HealthStatus.passed,
                elapsedMs: 0,
                reasonCode: 'subscriptionEternalUnlimited',
              );
            } else {
              a2 = HealthCheckResult(
                id: HealthCheckId.subscriptionHealth,
                status: HealthStatus.passed,
                elapsedMs: 0,
                reasonCode: 'ok',
                daysRemaining: daysLeft,
                quotaUsedPercent: usedPct,
              );
            }
          }
        }
      }
      record(a2);

      // C1: Proxy Started
      final c1 = cfg.proxyStarted
          ? const HealthCheckResult(
              id: HealthCheckId.proxyStarted,
              status: HealthStatus.passed,
              elapsedMs: 0,
              reasonCode: 'ok',
            )
          : const HealthCheckResult(
              id: HealthCheckId.proxyStarted,
              status: HealthStatus.failed,
              elapsedMs: 0,
              reasonCode: 'proxyNotStarted',
              action: HealthAction.startProxy,
            );
      record(c1);

      // Run B1 (Core), C2 (TUN), and C3 (System Proxy) in parallel
      String? verifiedSysProxyDirective;
      var observedTunListenerActive = false;

      Future<HealthCheckResult> runB1() async {
        final watch = Stopwatch()..start();
        try {
          final obs = await raceCancel(
            environment.checkCoreLiveness().timeout(const Duration(seconds: 3)),
          );
          final ms = watch.elapsedMilliseconds;
          if (!obs.isInit) {
            return HealthCheckResult(
              id: HealthCheckId.coreResponsive,
              status: HealthStatus.failed,
              elapsedMs: ms,
              reasonCode: 'coreNotInitialized',
              action: HealthAction.restartCore,
            );
          }
          if (obs.memoryBytes == null || !obs.trafficValid) {
            return HealthCheckResult(
              id: HealthCheckId.coreResponsive,
              status: HealthStatus.failed,
              elapsedMs: ms,
              reasonCode: 'coreIpcInvalid',
              action: HealthAction.restartCore,
            );
          }
          final mb = obs.memoryBytes! / (1024 * 1024);
          if (ms > 500) {
            return HealthCheckResult(
              id: HealthCheckId.coreResponsive,
              status: HealthStatus.warning,
              elapsedMs: ms,
              reasonCode: 'coreSlowResponse',
              memoryMb: mb,
              action: HealthAction.restartCore,
            );
          }
          return HealthCheckResult(
            id: HealthCheckId.coreResponsive,
            status: HealthStatus.passed,
            elapsedMs: ms,
            reasonCode: 'ok',
            memoryMb: mb,
          );
        } on _HealthCancelledException {
          rethrow;
        } on TimeoutException {
          return HealthCheckResult(
            id: HealthCheckId.coreResponsive,
            status: HealthStatus.timeout,
            elapsedMs: watch.elapsedMilliseconds,
            reasonCode: 'coreIpcTimeout',
            action: HealthAction.restartCore,
          );
        } catch (_) {
          return HealthCheckResult(
            id: HealthCheckId.coreResponsive,
            status: HealthStatus.failed,
            elapsedMs: watch.elapsedMilliseconds,
            reasonCode: 'coreIpcFailed',
            action: HealthAction.restartCore,
          );
        }
      }

      Future<HealthCheckResult> runC2() async {
        if (c1.status.isFailure) {
          return const HealthCheckResult(
            id: HealthCheckId.tunTakeover,
            status: HealthStatus.skipped,
            elapsedMs: 0,
            reasonCode: 'proxyNotRunning',
          );
        }
        final watch = Stopwatch()..start();
        if (environment.platform == 'windows') {
          TunStatus? tun;
          String? probeError;
          try {
            tun = await raceCancel(
              environment.readTunStatus().timeout(const Duration(seconds: 3)),
            );
          } on _HealthCancelledException {
            rethrow;
          } on TunFailure catch (e) {
            probeError = e.code;
          } on TimeoutException {
            probeError = 'statusUnavailable';
          } catch (_) {
            probeError = 'statusUnavailable';
          }
          final ms = watch.elapsedMilliseconds;
          observedTunListenerActive =
              tun != null && tun.listenerActive && tun.interfaceState == 'up';
          if (!cfg.tunDesiredEnabled) {
            if (tun?.observed == TunObservedState.on ||
                tun?.errorCode == 'closeFailed') {
              return HealthCheckResult(
                id: HealthCheckId.tunTakeover,
                status: HealthStatus.warning,
                elapsedMs: ms,
                reasonCode: 'tunCloseFailed',
                action: HealthAction.openTunSettings,
              );
            }
            return HealthCheckResult(
              id: HealthCheckId.tunTakeover,
              status: HealthStatus.skipped,
              elapsedMs: ms,
              reasonCode: 'tunDisabledByPreference',
            );
          }
          if (tun != null &&
              tun.listenerActive &&
              tun.interfaceState == 'up' &&
              tun.state == 'on' &&
              tun.errorCode == null) {
            return HealthCheckResult(
              id: HealthCheckId.tunTakeover,
              status: HealthStatus.passed,
              elapsedMs: ms,
              reasonCode:
                  tun.privilege == 'elevated' ? 'tunReadyElevated' : 'ok',
            );
          }
          if (tun != null &&
              tun.observed == TunObservedState.on &&
              tun.errorCode == 'closeFailed') {
            return HealthCheckResult(
              id: HealthCheckId.tunTakeover,
              status: HealthStatus.warning,
              elapsedMs: ms,
              reasonCode: 'tunCloseFailed',
              action: HealthAction.openTunSettings,
            );
          }
          final reason = mapTunFailureReason(
            tun?.errorCode ?? cfg.tunFailureCode ?? probeError,
          );
          return HealthCheckResult(
            id: HealthCheckId.tunTakeover,
            status: HealthStatus.failed,
            elapsedMs: ms,
            reasonCode: reason,
            action: HealthAction.openTunSettings,
          );
        }

        if (!cfg.tunDesiredEnabled) {
          return const HealthCheckResult(
            id: HealthCheckId.tunTakeover,
            status: HealthStatus.skipped,
            elapsedMs: 0,
            reasonCode: 'tunDisabledByPreference',
          );
        }
        return cfg.realTunEnable
            ? HealthCheckResult(
                id: HealthCheckId.tunTakeover,
                status: HealthStatus.passed,
                elapsedMs: watch.elapsedMilliseconds,
                reasonCode: 'ok',
              )
            : HealthCheckResult(
                id: HealthCheckId.tunTakeover,
                status: HealthStatus.failed,
                elapsedMs: watch.elapsedMilliseconds,
                reasonCode: 'tunStartFailed',
                action: HealthAction.openTunSettings,
              );
      }

      Future<HealthCheckResult> runC3() async {
        if (c1.status.isFailure) {
          return const HealthCheckResult(
            id: HealthCheckId.systemProxyTakeover,
            status: HealthStatus.skipped,
            elapsedMs: 0,
            reasonCode: 'proxyNotRunning',
          );
        }
        if (environment.platform != 'windows') {
          return HealthCheckResult(
            id: HealthCheckId.systemProxyTakeover,
            status: HealthStatus.skipped,
            elapsedMs: 0,
            reasonCode: cfg.systemProxyEnabled
                ? 'platformUnsupported'
                : 'systemProxyDisabledByPreference',
          );
        }
        final watch = Stopwatch()..start();
        final snap = await raceCancel(environment.readWindowsSystemProxy());
        final eval = evaluateWindowsSystemProxy(
          expectedEnabled: cfg.systemProxyEnabled,
          expectedPort: cfg.mixedPort,
          expectedPacEnabled: cfg.pacEnabled,
          expectedPacUrl: cfg.pacUrl,
          snapshot: snap,
        );
        verifiedSysProxyDirective = eval.verifiedProxyDirective;
        final HealthAction? c3Action;
        if (eval.status == HealthStatus.passed ||
            eval.status == HealthStatus.skipped) {
          c3Action = null;
        } else if (eval.reasonCode == 'systemProxyInvalidPort' ||
            eval.reasonCode == 'systemProxyReadFailed') {
          c3Action = HealthAction.openNetworkSettings;
        } else {
          c3Action = HealthAction.reapplySystemProxy;
        }
        return HealthCheckResult(
          id: HealthCheckId.systemProxyTakeover,
          status: eval.status,
          elapsedMs: watch.elapsedMilliseconds,
          reasonCode: eval.reasonCode,
          localDetail: eval.localDetail,
          action: c3Action,
        );
      }

      final phase1Results = await Future.wait<HealthCheckResult>([
        runB1(),
        runC2(),
        runC3(),
      ]);
      final b1 = phase1Results[0];
      final c2 = phase1Results[1];
      final c3 = phase1Results[2];
      record(b1);
      record(c2);
      record(c3);

      // A3: Runtime Config Loaded
      final HealthCheckResult a3;
      if (a1.status.isFailure) {
        a3 = const HealthCheckResult(
          id: HealthCheckId.runtimeConfigLoaded,
          status: HealthStatus.skipped,
          elapsedMs: 0,
          reasonCode: 'prerequisiteFailed',
        );
      } else if (b1.status.isFailure) {
        a3 = const HealthCheckResult(
          id: HealthCheckId.runtimeConfigLoaded,
          status: HealthStatus.skipped,
          elapsedMs: 0,
          reasonCode: 'coreUnavailable',
        );
      } else if (!cfg.proxyStarted) {
        if (cfg.lastRuntimeProfileId == cfg.currentProfileId &&
            cfg.allGroups.isNotEmpty) {
          a3 = HealthCheckResult(
            id: HealthCheckId.runtimeConfigLoaded,
            status: HealthStatus.passed,
            elapsedMs: 0,
            reasonCode: 'ok',
            groupCount: cfg.allGroups.length,
          );
        } else {
          a3 = const HealthCheckResult(
            id: HealthCheckId.runtimeConfigLoaded,
            status: HealthStatus.skipped,
            elapsedMs: 0,
            reasonCode: 'proxyNotRunning',
          );
        }
      } else {
        final matchesExplicit =
            cfg.lastRuntimeProfileId == cfg.currentProfileId;
        final matchesTakeover = cfg.lastRuntimeProfileId == null &&
            (cfg.groupsSnapshotProfileId == null ||
                cfg.groupsSnapshotProfileId == cfg.currentProfileId);
        if ((matchesExplicit || matchesTakeover) && cfg.allGroups.isNotEmpty) {
          a3 = HealthCheckResult(
            id: HealthCheckId.runtimeConfigLoaded,
            status: HealthStatus.passed,
            elapsedMs: 0,
            reasonCode: 'ok',
            groupCount: cfg.allGroups.length,
          );
        } else {
          a3 = const HealthCheckResult(
            id: HealthCheckId.runtimeConfigLoaded,
            status: HealthStatus.warning,
            elapsedMs: 0,
            reasonCode: 'runtimeConfigMismatch',
            action: HealthAction.openProfiles,
          );
        }
      }
      record(a3);

      // C4: Traffic Takeover Summary
      final tunCapturingTraffic = environment.platform == 'windows'
          ? (c2.status == HealthStatus.passed ||
              (c2.status == HealthStatus.warning && observedTunListenerActive))
          : (c2.status == HealthStatus.passed ||
              c2.status == HealthStatus.warning);
      final HealthCheckResult c4;
      if (c1.status.isFailure) {
        c4 = const HealthCheckResult(
          id: HealthCheckId.trafficTakeover,
          status: HealthStatus.skipped,
          elapsedMs: 0,
          reasonCode: 'proxyNotRunning',
        );
      } else {
        final sysOk = c3.status == HealthStatus.passed ||
            c3.status == HealthStatus.warning;
        final tunAbnormal =
            c2.status.isFailure || c2.status == HealthStatus.warning;
        final sysFailed = c3.status.isFailure;
        final tunRepairAction = c2.action ?? HealthAction.openTunSettings;
        final sysRepairAction = c3.action ?? HealthAction.openNetworkSettings;

        if (tunCapturingTraffic && sysOk) {
          c4 = (c2.status == HealthStatus.warning ||
                  c3.status == HealthStatus.warning)
              ? HealthCheckResult(
                  id: HealthCheckId.trafficTakeover,
                  status: HealthStatus.warning,
                  elapsedMs: 0,
                  reasonCode: 'partialTakeover',
                  action: c2.status == HealthStatus.warning
                      ? tunRepairAction
                      : sysRepairAction,
                )
              : const HealthCheckResult(
                  id: HealthCheckId.trafficTakeover,
                  status: HealthStatus.passed,
                  elapsedMs: 0,
                  reasonCode: 'takeoverBoth',
                );
        } else if (tunCapturingTraffic) {
          c4 = (sysFailed || c2.status == HealthStatus.warning)
              ? HealthCheckResult(
                  id: HealthCheckId.trafficTakeover,
                  status: HealthStatus.warning,
                  elapsedMs: 0,
                  reasonCode: 'partialTakeover',
                  action: sysFailed ? sysRepairAction : tunRepairAction,
                )
              : const HealthCheckResult(
                  id: HealthCheckId.trafficTakeover,
                  status: HealthStatus.passed,
                  elapsedMs: 0,
                  reasonCode: 'takeoverTun',
                );
        } else if (sysOk) {
          c4 = (tunAbnormal || c3.status == HealthStatus.warning)
              ? HealthCheckResult(
                  id: HealthCheckId.trafficTakeover,
                  status: HealthStatus.warning,
                  elapsedMs: 0,
                  reasonCode: 'partialTakeover',
                  action: tunAbnormal ? tunRepairAction : sysRepairAction,
                )
              : const HealthCheckResult(
                  id: HealthCheckId.trafficTakeover,
                  status: HealthStatus.passed,
                  elapsedMs: 0,
                  reasonCode: 'takeoverSysProxy',
                );
        } else if (environment.platform != 'windows' &&
            !cfg.tunDesiredEnabled &&
            cfg.systemProxyEnabled) {
          c4 = const HealthCheckResult(
            id: HealthCheckId.trafficTakeover,
            status: HealthStatus.skipped,
            elapsedMs: 0,
            reasonCode: 'takeoverUnverifiedPlatform',
          );
        } else if (!cfg.tunDesiredEnabled &&
            !cfg.systemProxyEnabled &&
            !tunAbnormal) {
          c4 = const HealthCheckResult(
            id: HealthCheckId.trafficTakeover,
            status: HealthStatus.failed,
            elapsedMs: 0,
            reasonCode: 'noTakeoverConfigured',
            action: HealthAction.openTunSettings,
          );
        } else {
          c4 = HealthCheckResult(
            id: HealthCheckId.trafficTakeover,
            status: HealthStatus.failed,
            elapsedMs: 0,
            reasonCode: 'takeoverFailed',
            action: tunAbnormal ? tunRepairAction : sysRepairAction,
          );
        }
      }
      record(c4);

      // Phase 2: Network Layer (D1 Direct, D2 DNS, D3 Outbound Node in parallel)
      markRunning(const [
        HealthCheckId.directConnectivity,
        HealthCheckId.dnsResolution,
        HealthCheckId.outboundConnectivity,
      ]);

      Future<HealthCheckResult> runD1() async {
        if (b1.status.isFailure) {
          return const HealthCheckResult(
            id: HealthCheckId.directConnectivity,
            status: HealthStatus.skipped,
            elapsedMs: 0,
            reasonCode: 'coreUnavailable',
          );
        }
        final watch = Stopwatch()..start();
        var sawTimeout = false;
        for (var i = 0; i < directConnectivityProbeUrls.length; i++) {
          final reqId = 'hc-direct-$seq-$i';
          token.register(() => environment.cancelProxyDelay(reqId));
          final perAttemptTimeout = i == 0
              ? const Duration(milliseconds: 2200)
              : const Duration(milliseconds: 1800);
          try {
            final res = await raceCancel(
              environment
                  .testProxyDelay(
                    proxyName: 'DIRECT',
                    testUrl: directConnectivityProbeUrls[i],
                    requestId: reqId,
                    timeout: perAttemptTimeout,
                  )
                  .timeout(
                      perAttemptTimeout + const Duration(milliseconds: 600)),
            );
            final ms = watch.elapsedMilliseconds;
            if (res.value > 0) {
              return res.value >= 800
                  ? HealthCheckResult(
                      id: HealthCheckId.directConnectivity,
                      status: HealthStatus.warning,
                      elapsedMs: ms,
                      reasonCode: 'directSlow',
                      delayMs: res.value,
                      localDetail: '${res.value} ms',
                    )
                  : HealthCheckResult(
                      id: HealthCheckId.directConnectivity,
                      status: HealthStatus.passed,
                      elapsedMs: ms,
                      reasonCode: 'ok',
                      delayMs: res.value,
                      localDetail: '${res.value} ms',
                    );
            }
            if (res.reason == 'notFound') {
              return HealthCheckResult(
                id: HealthCheckId.directConnectivity,
                status: HealthStatus.skipped,
                elapsedMs: ms,
                reasonCode: 'runtimeNotLoaded',
              );
            }
            if (res.reason == 'overloaded') {
              return HealthCheckResult(
                id: HealthCheckId.directConnectivity,
                status: HealthStatus.warning,
                elapsedMs: ms,
                reasonCode: 'coreDelayBusy',
              );
            }
            if (res.reason == 'deadlineExceeded') {
              sawTimeout = true;
            }
          } on _HealthCancelledException {
            rethrow;
          } on TimeoutException {
            sawTimeout = true;
          } catch (_) {
            // Fall through to secondary captive-portal endpoint.
          }
        }
        final totalMs = watch.elapsedMilliseconds;
        return sawTimeout
            ? HealthCheckResult(
                id: HealthCheckId.directConnectivity,
                status: HealthStatus.timeout,
                elapsedMs: totalMs,
                reasonCode: 'directTimeout',
              )
            : HealthCheckResult(
                id: HealthCheckId.directConnectivity,
                status: HealthStatus.failed,
                elapsedMs: totalMs,
                reasonCode: 'directFailed',
              );
      }

      Future<HealthCheckResult> runD2() async {
        final tunCapturingDns =
            c1.status == HealthStatus.passed && tunCapturingTraffic;
        final List<String> candidateHosts;
        if (tunCapturingDns) {
          final parsedHost = Uri.tryParse(cfg.testUrl)?.host.trim() ?? '';
          final primary = (parsedHost.isEmpty ||
                  InternetAddress.tryParse(parsedHost) != null)
              ? 'www.gstatic.com'
              : parsedHost;
          candidateHosts = <String>[primary];
        } else {
          // Without TUN DNS interception, InternetAddress.lookup goes directly
          // to ISP/OS DNS; never query GFW-poisoned overseas hosts like gstatic.
          candidateHosts = systemDnsProbeHosts;
        }

        final watch = Stopwatch()..start();
        var sawTimeout = false;
        var addresses = const <InternetAddress>[];
        for (final probeHost in candidateHosts) {
          try {
            final resolved = await raceCancel(
              environment
                  .lookupHost(probeHost)
                  .timeout(const Duration(seconds: 3)),
            );
            if (resolved.isNotEmpty) {
              addresses = resolved;
              break;
            }
          } on _HealthCancelledException {
            rethrow;
          } on TimeoutException {
            sawTimeout = true;
          } catch (_) {
            // Try next system DNS host if any.
          }
        }
        final ms = watch.elapsedMilliseconds;
        if (addresses.isEmpty) {
          return sawTimeout
              ? HealthCheckResult(
                  id: HealthCheckId.dnsResolution,
                  status: HealthStatus.timeout,
                  elapsedMs: ms,
                  reasonCode: 'dnsTimeout',
                  action: HealthAction.openDnsSettings,
                )
              : HealthCheckResult(
                  id: HealthCheckId.dnsResolution,
                  status: HealthStatus.failed,
                  elapsedMs: ms,
                  reasonCode: 'dnsLookupFailed',
                  action: HealthAction.openDnsSettings,
                );
        }
        if (addresses.any(_isPoisonedAddress)) {
          return HealthCheckResult(
            id: HealthCheckId.dnsResolution,
            status: HealthStatus.failed,
            elapsedMs: ms,
            reasonCode: 'dnsPoisonedLoopback',
            action: HealthAction.openDnsSettings,
          );
        }
        final fakeIp = addresses.any(_isFakeIpAddress);
        if (fakeIp && !tunCapturingDns) {
          return HealthCheckResult(
            id: HealthCheckId.dnsResolution,
            status: HealthStatus.failed,
            elapsedMs: ms,
            reasonCode: 'dnsStaleFakeIp',
            action: HealthAction.openDnsSettings,
          );
        }
        return HealthCheckResult(
          id: HealthCheckId.dnsResolution,
          status: HealthStatus.passed,
          elapsedMs: ms,
          reasonCode: fakeIp ? 'dnsFakeIpActive' : 'ok',
        );
      }

      String? resolvedActiveLeaf;
      Group? activeDynamicGroup;
      int? resolvedOutboundDelay;

      Future<HealthCheckResult> runD3() async {
        if (c1.status.isFailure) {
          return const HealthCheckResult(
            id: HealthCheckId.outboundConnectivity,
            status: HealthStatus.skipped,
            elapsedMs: 0,
            reasonCode: 'proxyNotRunning',
          );
        }
        if (b1.status.isFailure) {
          return const HealthCheckResult(
            id: HealthCheckId.outboundConnectivity,
            status: HealthStatus.skipped,
            elapsedMs: 0,
            reasonCode: 'coreUnavailable',
          );
        }
        if (cfg.mode == Mode.direct) {
          return const HealthCheckResult(
            id: HealthCheckId.outboundConnectivity,
            status: HealthStatus.skipped,
            elapsedMs: 0,
            reasonCode: 'directModeActive',
          );
        }
        final preferRuntimeNow =
            cfg.proxyStarted && a3.status == HealthStatus.passed;
        final group = _selectActiveGroup(
          cfg,
          preferRuntimeNow: preferRuntimeNow,
        );
        if (group == null) {
          return const HealthCheckResult(
            id: HealthCheckId.outboundConnectivity,
            status: HealthStatus.failed,
            elapsedMs: 0,
            reasonCode: 'outboundGroupMissing',
            action: HealthAction.openProfiles,
          );
        }
        final leafResult = _resolveSelectedLeaf(
          group,
          cfg.allGroups,
          cfg.selectedMap,
          preferRuntimeNow: preferRuntimeNow,
        );
        final leaf = leafResult.leaf;
        if (leaf == null) {
          return HealthCheckResult(
            id: HealthCheckId.outboundConnectivity,
            status: HealthStatus.failed,
            elapsedMs: 0,
            reasonCode: leafResult.failureReason ?? 'outboundGroupLoop',
            action: HealthAction.openProfiles,
          );
        }
        resolvedActiveLeaf = leaf;
        activeDynamicGroup = leafResult.dynamicGroup;
        if (leaf == 'REJECT' || leaf == 'REJECT-DROP') {
          return HealthCheckResult(
            id: HealthCheckId.outboundConnectivity,
            status: HealthStatus.failed,
            elapsedMs: 0,
            reasonCode: 'outboundSelectedReject',
            nodeName: leaf,
            localDetail: leaf,
            action: HealthAction.openProxies,
          );
        }
        if (leaf == 'DIRECT') {
          return HealthCheckResult(
            id: HealthCheckId.outboundConnectivity,
            status: HealthStatus.warning,
            elapsedMs: 0,
            reasonCode: 'outboundSelectedDirect',
            nodeName: leaf,
            localDetail: leaf,
            action: HealthAction.openProxies,
          );
        }

        final watch = Stopwatch()..start();
        final primaryUrl = cfg.resolveGroupTestUrl(group.testUrl);

        Future<DelayTestResult> runOutboundAttempt(
          String targetUrl,
          String attemptReqId,
          Duration attemptTimeout,
        ) {
          if (token.isCancelled) {
            throw const _HealthCancelledException();
          }
          token.register(() => environment.cancelProxyDelay(attemptReqId));
          return raceCancel(
            environment
                .testProxyDelay(
                  proxyName: group.name,
                  testUrl: targetUrl,
                  requestId: attemptReqId,
                  timeout: attemptTimeout,
                )
                .timeout(attemptTimeout + const Duration(seconds: 1)),
          );
        }

        bool shouldRetryFastFailure(DelayTestResult r) =>
            r.value <= 0 &&
            r.reason != 'overloaded' &&
            r.reason != 'notFound' &&
            r.reason != 'deadlineExceeded';

        try {
          const totalBudgetMs = 6500;
          const minRetryBudgetMs = 1200;
          const maxRetryTimeoutMs = 3500;
          var res = await runOutboundAttempt(
            primaryUrl,
            'hc-outbound-$seq',
            const Duration(seconds: 5),
          );
          final remainingAfterPrimary =
              totalBudgetMs - watch.elapsedMilliseconds;
          if (shouldRetryFastFailure(res) &&
              remainingAfterPrimary >= minRetryBudgetMs) {
            final r1TimeoutMs = math.min(
              maxRetryTimeoutMs,
              remainingAfterPrimary,
            );
            res = await runOutboundAttempt(
              primaryUrl,
              'hc-outbound-$seq-r1',
              Duration(milliseconds: r1TimeoutMs),
            );
          }
          final remainingAfterRetry1 =
              totalBudgetMs - watch.elapsedMilliseconds;
          if (shouldRetryFastFailure(res) &&
              remainingAfterRetry1 >= minRetryBudgetMs) {
            final fallbackUrl = _selectOutboundFallbackUrl(primaryUrl);
            if (fallbackUrl.isNotEmpty) {
              final r2TimeoutMs = math.min(
                maxRetryTimeoutMs,
                remainingAfterRetry1,
              );
              res = await runOutboundAttempt(
                fallbackUrl,
                'hc-outbound-$seq-r2',
                Duration(milliseconds: r2TimeoutMs),
              );
            }
          }
          final ms = watch.elapsedMilliseconds;
          if (res.value > 0) {
            resolvedOutboundDelay = res.value;
            final detail = '$leaf · ${res.value} ms';
            if (res.value <= kLatencyFastMaxMs) {
              return HealthCheckResult(
                id: HealthCheckId.outboundConnectivity,
                status: HealthStatus.passed,
                elapsedMs: ms,
                reasonCode: 'ok',
                nodeName: leaf,
                delayMs: res.value,
                localDetail: detail,
              );
            }
            return HealthCheckResult(
              id: HealthCheckId.outboundConnectivity,
              status: HealthStatus.warning,
              elapsedMs: ms,
              reasonCode: 'outboundVerySlow',
              nodeName: leaf,
              delayMs: res.value,
              localDetail: detail,
              action: HealthAction.openProxies,
            );
          }
          return switch (res.reason) {
            'overloaded' => HealthCheckResult(
                id: HealthCheckId.outboundConnectivity,
                status: HealthStatus.warning,
                elapsedMs: ms,
                reasonCode: 'coreDelayBusy',
                nodeName: leaf,
                localDetail: leaf,
              ),
            'deadlineExceeded' => HealthCheckResult(
                id: HealthCheckId.outboundConnectivity,
                status: HealthStatus.timeout,
                elapsedMs: ms,
                reasonCode: 'outboundTimeout',
                nodeName: leaf,
                localDetail: leaf,
                action: HealthAction.openProxies,
              ),
            'notFound' => HealthCheckResult(
                id: HealthCheckId.outboundConnectivity,
                status: HealthStatus.failed,
                elapsedMs: ms,
                reasonCode: 'outboundNotFound',
                nodeName: leaf,
                localDetail: leaf,
                action: HealthAction.openProfiles,
              ),
            _ => HealthCheckResult(
                id: HealthCheckId.outboundConnectivity,
                status: HealthStatus.failed,
                elapsedMs: ms,
                reasonCode: 'outboundFailed',
                nodeName: leaf,
                localDetail: leaf,
                action: HealthAction.openProxies,
              ),
          };
        } on _HealthCancelledException {
          rethrow;
        } on TimeoutException {
          return HealthCheckResult(
            id: HealthCheckId.outboundConnectivity,
            status: HealthStatus.timeout,
            elapsedMs: watch.elapsedMilliseconds,
            reasonCode: 'outboundTimeout',
            nodeName: leaf,
            localDetail: leaf,
            action: HealthAction.openProxies,
          );
        } catch (_) {
          return HealthCheckResult(
            id: HealthCheckId.outboundConnectivity,
            status: HealthStatus.failed,
            elapsedMs: watch.elapsedMilliseconds,
            reasonCode: 'outboundFailed',
            nodeName: leaf,
            localDetail: leaf,
            action: HealthAction.openProxies,
          );
        }
      }

      final phase2Results = await Future.wait<HealthCheckResult>([
        runD1(),
        runD2(),
        runD3(),
      ]);
      final d1 = phase2Results[0];
      final d2 = phase2Results[1];
      final d3 = phase2Results[2];
      record(d1);
      record(d2);

      // Phase 3: End-to-End Verification (D4)
      const structuralD3Failures = {
        'outboundSelectedReject',
        'outboundGroupMissing',
        'outboundGroupLoop',
        'outboundNotFound',
      };
      final d4CanRunUnderGate = !c1.status.isFailure &&
          !b1.status.isFailure &&
          cfg.mode != Mode.direct &&
          !c4.status.isFailure &&
          (!d3.status.isFailure ||
              (!d1.status.isFailure &&
                  !structuralD3Failures.contains(d3.reasonCode)));
      final d4WillRunLiveProbe = d4CanRunUnderGate &&
          (tunCapturingTraffic || verifiedSysProxyDirective != null);
      if (!d3.status.isFailure || !d4WillRunLiveProbe) {
        record(d3);
      }
      markRunning(const [HealthCheckId.endToEndConnectivity]);
      String? exitCountryCode;
      HealthCheckResult d4;
      if (c1.status.isFailure) {
        d4 = const HealthCheckResult(
          id: HealthCheckId.endToEndConnectivity,
          status: HealthStatus.skipped,
          elapsedMs: 0,
          reasonCode: 'proxyNotRunning',
        );
      } else if (b1.status.isFailure) {
        d4 = const HealthCheckResult(
          id: HealthCheckId.endToEndConnectivity,
          status: HealthStatus.skipped,
          elapsedMs: 0,
          reasonCode: 'coreUnavailable',
        );
      } else if (cfg.mode == Mode.direct) {
        d4 = const HealthCheckResult(
          id: HealthCheckId.endToEndConnectivity,
          status: HealthStatus.skipped,
          elapsedMs: 0,
          reasonCode: 'directModeActive',
        );
      } else if (c4.status.isFailure) {
        d4 = const HealthCheckResult(
          id: HealthCheckId.endToEndConnectivity,
          status: HealthStatus.skipped,
          elapsedMs: 0,
          reasonCode: 'takeoverFailed',
        );
      } else if (d3.status.isFailure &&
          (d1.status.isFailure ||
              structuralD3Failures.contains(d3.reasonCode))) {
        d4 = const HealthCheckResult(
          id: HealthCheckId.endToEndConnectivity,
          status: HealthStatus.skipped,
          elapsedMs: 0,
          reasonCode: 'outboundFailed',
        );
      } else {
        final tunActive = tunCapturingTraffic;
        final systemProxyDirective = verifiedSysProxyDirective;

        HealthCheckResult classifyObservation(
          EndToEndProbeObservation obs,
          int elapsedMs, {
          bool acceptLoopbackProxy = false,
          bool tunBypassedSystemProxyFallback = false,
        }) {
          final normalizedCountry =
              obs.exitCountryCode.length == 2 ? obs.exitCountryCode : null;
          final observedInCore = obs.observedInCore || acceptLoopbackProxy;
          if (!observedInCore) {
            return HealthCheckResult(
              id: HealthCheckId.endToEndConnectivity,
              status: HealthStatus.warning,
              elapsedMs: elapsedMs,
              reasonCode: 'trafficBypassedCore',
              exitCountryCode: normalizedCountry,
              action: HealthAction.openTunSettings,
            );
          }
          if (obs.matchedLeafProxy == 'REJECT' ||
              obs.matchedLeafProxy == 'REJECT-DROP') {
            return HealthCheckResult(
              id: HealthCheckId.endToEndConnectivity,
              status: HealthStatus.failed,
              elapsedMs: elapsedMs,
              reasonCode: 'e2eRejectedByRule',
              action: HealthAction.openProxies,
            );
          }
          exitCountryCode = normalizedCountry;
          if (tunBypassedSystemProxyFallback) {
            return HealthCheckResult(
              id: HealthCheckId.endToEndConnectivity,
              status: HealthStatus.warning,
              elapsedMs: elapsedMs,
              reasonCode: 'tunBypassedSystemProxyOk',
              exitCountryCode: exitCountryCode,
              nodeName: obs.matchedLeafProxy,
              action: HealthAction.openTunSettings,
            );
          }
          if (obs.matchedLeafProxy == 'DIRECT') {
            return HealthCheckResult(
              id: HealthCheckId.endToEndConnectivity,
              status: HealthStatus.passed,
              elapsedMs: elapsedMs,
              reasonCode: 'routedDirectByRule',
              exitCountryCode: exitCountryCode,
            );
          }
          return HealthCheckResult(
            id: HealthCheckId.endToEndConnectivity,
            status: HealthStatus.passed,
            elapsedMs: elapsedMs,
            reasonCode: 'ok',
            exitCountryCode: exitCountryCode,
            nodeName: obs.matchedLeafProxy,
          );
        }

        HealthCheckResult failedProbeResult(
          String reasonCode,
          int elapsedMs,
        ) => HealthCheckResult(
            id: HealthCheckId.endToEndConnectivity,
            status: reasonCode == 'e2eTimeout'
                ? HealthStatus.timeout
                : HealthStatus.failed,
            elapsedMs: elapsedMs,
            reasonCode: reasonCode,
            action: HealthAction.openProxies,
          );

        if (!tunActive && systemProxyDirective == null) {
          if (environment.platform == 'windows' &&
              c3.status == HealthStatus.warning) {
            d4 = const HealthCheckResult(
              id: HealthCheckId.endToEndConnectivity,
              status: HealthStatus.warning,
              elapsedMs: 0,
              reasonCode: 'trafficBypassedCore',
              action: HealthAction.openNetworkSettings,
            );
          } else {
            d4 = HealthCheckResult(
              id: HealthCheckId.endToEndConnectivity,
              status: HealthStatus.skipped,
              elapsedMs: 0,
              reasonCode: cfg.pacEnabled
                  ? 'pacExternalUnverifiable'
                  : 'takeoverUnverifiedPlatform',
            );
          }
        } else {
          final primaryDirective = tunActive ? 'DIRECT' : systemProxyDirective!;
          final primaryWatch = Stopwatch()..start();
          EndToEndProbeObservation? primaryObservation;
          String? primaryFailureReason;
          try {
            primaryObservation = await raceCancel(
              environment
                  .probeEndToEnd(
                    cancelToken: token,
                    explicitProxyDirective: primaryDirective,
                  )
                  .timeout(const Duration(seconds: 10)),
            );
          } on _HealthCancelledException {
            rethrow;
          } on TimeoutException {
            primaryFailureReason = 'e2eTimeout';
          } catch (_) {
            primaryFailureReason = 'e2eAllSourcesFailed';
          }
          final primaryMs = primaryWatch.elapsedMilliseconds;
          final failedAttemptCapturedByCore = switch (environment) {
            CoreFailedProbeTelemetry(:final lastFailedProbeObservedInCore) =>
              lastFailedProbeObservedInCore,
            _ => false,
          };
          final primaryFailedOutsideCore =
              (primaryFailureReason != null || primaryObservation == null) &&
                  !failedAttemptCapturedByCore;
          final needsSystemProxyFallback = tunActive &&
              systemProxyDirective != null &&
              (primaryFailedOutsideCore ||
                  (primaryObservation != null &&
                      !primaryObservation.observedInCore));
          if (!needsSystemProxyFallback) {
            d4 = primaryObservation != null
                ? classifyObservation(
                    primaryObservation,
                    primaryMs,
                    acceptLoopbackProxy: !tunActive,
                  )
                : failedProbeResult(
                    primaryFailureReason ?? 'e2eAllSourcesFailed',
                    primaryMs,
                  );
          } else {
            final fallbackWatch = Stopwatch()..start();
            EndToEndProbeObservation? fallbackObservation;
            String? fallbackFailureReason;
            try {
              fallbackObservation = await raceCancel(
                environment
                    .probeEndToEnd(
                      cancelToken: token,
                      explicitProxyDirective: systemProxyDirective,
                    )
                    .timeout(const Duration(seconds: 10)),
              );
            } on _HealthCancelledException {
              rethrow;
            } on TimeoutException {
              fallbackFailureReason = 'e2eTimeout';
            } catch (_) {
              fallbackFailureReason = 'e2eAllSourcesFailed';
            }
            final fallbackMs = fallbackWatch.elapsedMilliseconds;
            if (fallbackObservation != null) {
              d4 = classifyObservation(
                fallbackObservation,
                primaryMs + fallbackMs,
                acceptLoopbackProxy: true,
                tunBypassedSystemProxyFallback: true,
              );
            } else if (primaryObservation != null) {
              d4 = classifyObservation(
                primaryObservation,
                primaryMs + fallbackMs,
              );
            } else {
              d4 = failedProbeResult(
                fallbackFailureReason ??
                    primaryFailureReason ??
                    'e2eAllSourcesFailed',
                primaryMs + fallbackMs,
              );
            }
          }
        }
      }
      final d4Leaf = d4.nodeName;
      final d4ProvesProxyStatus =
          (d4.status == HealthStatus.passed && d4.reasonCode == 'ok') ||
              (d4.status == HealthStatus.warning &&
                  d4.reasonCode == 'tunBypassedSystemProxyOk');
      final d4MatchesExpectedOutbound = isVerifiedProxyOutboundLeaf(d4Leaf) &&
          (d4Leaf == resolvedActiveLeaf ||
              (activeDynamicGroup != null &&
                  _collectReachableProxyLeaves(
                    activeDynamicGroup!,
                    cfg.allGroups,
                  ).contains(d4Leaf)));
      final e2eProvesProxyOutbound =
          d4ProvesProxyStatus && d4MatchesExpectedOutbound;
      if (d3.status.isFailure && e2eProvesProxyOutbound) {
        resolvedActiveLeaf = d4Leaf;
        record(
          HealthCheckResult(
            id: HealthCheckId.outboundConnectivity,
            status: HealthStatus.warning,
            elapsedMs: d3.elapsedMs,
            reasonCode: 'outboundProbeFallbackOk',
            nodeName: d4Leaf,
            localDetail: d3.localDetail,
          ),
        );
      } else if (d3.status.isFailure && d4WillRunLiveProbe) {
        record(d3);
      }
      record(d4);

      final orderedChecks = [
        for (final id in HealthCheckId.values) state[id]!,
      ];
      final verdict = computeHealthVerdict(
        orderedChecks,
        mode: cfg.mode,
        activeNodeName: resolvedActiveLeaf,
        outboundDelayMs: resolvedOutboundDelay,
        directDelayMs: d1.delayMs,
        exitCountryCode: exitCountryCode,
      );

      final completedAt = environment.now();
      return HealthReport(
        startedAt: startedAt,
        completedAt: completedAt,
        totalElapsedMs: totalWatch.elapsedMilliseconds,
        mode: cfg.mode,
        platform: environment.platform,
        appVersion: environment.appVersion,
        checks: List.unmodifiable(orderedChecks),
        verdict: verdict,
      );
    } on _HealthCancelledException {
      throw StateError('Health check cancelled');
    } finally {
      _running = false;
    }
  }
}

class HealthCheckController extends ChangeNotifier {
  HealthCheckController(this.runner);

  final HealthRunner runner;
  final Set<Object> _activeViewLeases = <Object>{};

  HealthReport? _lastReport;
  Map<HealthCheckId, HealthCheckResult> _liveSnapshot = const {};
  Map<HealthCheckId, HealthCheckResult> _previousById = const {};
  HealthCancellationToken? _activeToken;
  Future<HealthReport?>? _inFlightFuture;
  bool _running = false;
  bool _restarting = false;
  bool _wasCancelledWithoutReport = false;
  bool _disposed = false;

  HealthReport? get lastReport => _lastReport;
  Map<HealthCheckId, HealthCheckResult> get liveSnapshot => _liveSnapshot;
  Map<HealthCheckId, HealthCheckResult> get previousById => _previousById;
  bool get isRunning => _running;
  bool get wasCancelledWithoutReport =>
      _wasCancelledWithoutReport && _lastReport == null && !_running;

  Object attachView() {
    final lease = Object();
    _activeViewLeases.add(lease);
    return lease;
  }

  Future<void> detachView(Object lease) async {
    if (!_activeViewLeases.remove(lease)) return;
    if (_activeViewLeases.isEmpty) {
      await cancelActive();
    }
  }

  Future<HealthReport?> startOrAttach() async {
    if (_disposed) return _lastReport;
    if (_running) {
      final currentToken = _activeToken;
      if (currentToken != null && !currentToken.isCancelled) {
        return _inFlightFuture ?? _lastReport;
      }
      final dyingFuture = _inFlightFuture;
      if (dyingFuture != null) {
        try {
          await dyingFuture;
        } catch (_) {}
      }
      if (_disposed) return _lastReport;
      if (_running && _activeToken != null && !_activeToken!.isCancelled) {
        return _inFlightFuture ?? _lastReport;
      }
    }
    final future = _executeRun();
    _inFlightFuture = future;
    return future;
  }

  Future<HealthReport?> restart() async {
    if (_disposed) return _lastReport;
    _restarting = true;
    try {
      await cancelActive();
      final dyingFuture = _inFlightFuture;
      if (dyingFuture != null) {
        try {
          await dyingFuture;
        } catch (_) {}
      }
    } finally {
      _restarting = false;
    }
    return startOrAttach();
  }

  Future<HealthReport?> _executeRun() async {
    if (_lastReport != null) {
      _previousById = {
        for (final item in _lastReport!.checks) item.id: item,
      };
    }
    final token = HealthCancellationToken();
    _activeToken = token;
    _running = true;
    _wasCancelledWithoutReport = false;
    _liveSnapshot = {
      for (final id in HealthCheckId.values)
        id: HealthCheckResult(
          id: id,
          status: HealthStatus.running,
          elapsedMs: 0,
          reasonCode: 'running',
        ),
    };
    notifyListeners();

    try {
      final report = await runner.run(
        cancelToken: token,
        onProgress: (snapshot) {
          if (_disposed || !identical(_activeToken, token)) return;
          _liveSnapshot = snapshot;
          notifyListeners();
        },
      );
      if (!_disposed && identical(_activeToken, token)) {
        _lastReport = report;
        _previousById = {
          for (final item in report.checks) item.id: item,
        };
        _liveSnapshot = _previousById;
      }
      return report;
    } catch (_) {
      // Cancelled or interrupted: restore previous completed snapshot if any,
      // or settle remaining running items to skipped/cancelled so UI never
      // spins indefinitely when the first-ever check is cancelled.
      if (!_disposed && identical(_activeToken, token) && !_restarting) {
        if (_previousById.isNotEmpty) {
          _liveSnapshot = _previousById;
        } else {
          _wasCancelledWithoutReport = true;
          _liveSnapshot = {
            for (final id in HealthCheckId.values)
              id: (_liveSnapshot[id] != null &&
                      _liveSnapshot[id]!.status != HealthStatus.running)
                  ? _liveSnapshot[id]!
                  : HealthCheckResult(
                      id: id,
                      status: HealthStatus.skipped,
                      elapsedMs: 0,
                      reasonCode: 'cancelled',
                    ),
          };
        }
      }
      return null;
    } finally {
      if (identical(_activeToken, token)) {
        _activeToken = null;
        _inFlightFuture = null;
        _running = false;
        if (!_disposed && !_restarting) notifyListeners();
      }
    }
  }

  Future<void> cancelActive() async {
    final token = _activeToken;
    if (token == null) return;
    await token.cancel();
  }

  @override
  void dispose() {
    _disposed = true;
    _activeViewLeases.clear();
    final token = _activeToken;
    _activeToken = null;
    if (token != null) {
      unawaited(token.cancel());
    }
    super.dispose();
  }
}

final healthCheckControllerProvider =
    ChangeNotifierProvider<HealthCheckController>((ref) {
  final env = ref.watch(healthProbeEnvironmentProvider);
  return HealthCheckController(HealthRunner(env));
});

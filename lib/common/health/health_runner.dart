import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

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

  static Group? _selectActiveGroup(HealthConfigSnapshot cfg) {
    if (cfg.mode == Mode.global) {
      return cfg.allGroups.getGroup(GroupName.GLOBAL.name) ??
          (cfg.visibleGroups.isNotEmpty ? cfg.visibleGroups.first : null);
    }
    final preferred = cfg.currentProfile?.currentGroupName;
    if (preferred != null && preferred.isNotEmpty) {
      final foundVisible = cfg.visibleGroups.getGroup(preferred);
      if (foundVisible != null) return foundVisible;
      final foundAll = cfg.allGroups.getGroup(preferred);
      if (foundAll != null && foundAll.hidden != true) return foundAll;
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

  static String _resolveSelectedLeaf(
    Group entryGroup,
    List<Group> allGroups,
    Map<String, String> selectedMap, [
    int depth = 0,
  ]) {
    if (depth > 16) return entryGroup.name;
    final picked =
        entryGroup.getCurrentSelectedName(selectedMap[entryGroup.name] ?? '');
    if (picked.isEmpty || picked == entryGroup.name) {
      return entryGroup.name;
    }
    if (picked == 'DIRECT' ||
        picked == 'REJECT' ||
        picked == 'REJECT-DROP') {
      return picked;
    }
    final nextGroup = allGroups.getGroup(picked);
    if (nextGroup == null) {
      return picked;
    }
    return _resolveSelectedLeaf(nextGroup, allGroups, selectedMap, depth + 1);
  }

  static String _mapTunFailureReason(String? code) => switch (code) {
        'permissionDenied' || 'authorizationRequired' => 'tunAuthorizationRequired',
        'componentsMismatch' => 'tunComponentsMismatch',
        'legacyAgent' => 'tunLegacyAgent',
        'interfaceMissing' => 'tunInterfaceMissing',
        'interfaceDown' => 'tunInterfaceDown',
        'configurationFailed' => 'tunConfigurationFailed',
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
          token.onCancelled.then<T>((_) => throw const _HealthCancelledException()),
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
            final hwidMax =
                profile.providerHeaders['x-hwid-max-devices-reached']
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

      Future<HealthCheckResult> runB1() async {
        final watch = Stopwatch()..start();
        try {
          final obs = await raceCancel(
            environment
                .checkCoreLiveness()
                .timeout(const Duration(seconds: 3)),
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
          if (!cfg.tunDesiredEnabled && tun?.observed != TunObservedState.on) {
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
          final reason = _mapTunFailureReason(
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
        return HealthCheckResult(
          id: HealthCheckId.systemProxyTakeover,
          status: eval.status,
          elapsedMs: watch.elapsedMilliseconds,
          reasonCode: eval.reasonCode,
          localDetail: eval.localDetail,
          action: (eval.status == HealthStatus.passed ||
                  eval.status == HealthStatus.skipped)
              ? null
              : HealthAction.openNetworkSettings,
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
        final matchesExplicit = cfg.lastRuntimeProfileId == cfg.currentProfileId;
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
      final HealthCheckResult c4;
      if (c1.status.isFailure) {
        c4 = const HealthCheckResult(
          id: HealthCheckId.trafficTakeover,
          status: HealthStatus.skipped,
          elapsedMs: 0,
          reasonCode: 'proxyNotRunning',
        );
      } else {
        final tunOk =
            c2.status == HealthStatus.passed || c2.status == HealthStatus.warning;
        final sysOk =
            c3.status == HealthStatus.passed || c3.status == HealthStatus.warning;
        final tunFailed = c2.status.isFailure;
        final sysFailed = c3.status.isFailure;

        if (tunOk && sysOk) {
          c4 = (c2.status == HealthStatus.warning ||
                  c3.status == HealthStatus.warning)
              ? HealthCheckResult(
                  id: HealthCheckId.trafficTakeover,
                  status: HealthStatus.warning,
                  elapsedMs: 0,
                  reasonCode: 'partialTakeover',
                  action: c2.status == HealthStatus.warning
                      ? HealthAction.openTunSettings
                      : HealthAction.openNetworkSettings,
                )
              : const HealthCheckResult(
                  id: HealthCheckId.trafficTakeover,
                  status: HealthStatus.passed,
                  elapsedMs: 0,
                  reasonCode: 'takeoverBoth',
                );
        } else if (tunOk) {
          c4 = sysFailed
              ? const HealthCheckResult(
                  id: HealthCheckId.trafficTakeover,
                  status: HealthStatus.warning,
                  elapsedMs: 0,
                  reasonCode: 'partialTakeover',
                  action: HealthAction.openNetworkSettings,
                )
              : const HealthCheckResult(
                  id: HealthCheckId.trafficTakeover,
                  status: HealthStatus.passed,
                  elapsedMs: 0,
                  reasonCode: 'takeoverTun',
                );
        } else if (sysOk) {
          c4 = tunFailed
              ? const HealthCheckResult(
                  id: HealthCheckId.trafficTakeover,
                  status: HealthStatus.warning,
                  elapsedMs: 0,
                  reasonCode: 'partialTakeover',
                  action: HealthAction.openTunSettings,
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
        } else if (!cfg.tunDesiredEnabled && !cfg.systemProxyEnabled) {
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
            action: tunFailed
                ? HealthAction.openTunSettings
                : HealthAction.openNetworkSettings,
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
        final reqId = 'hc-direct-$seq';
        token.register(() => environment.cancelProxyDelay(reqId));
        final watch = Stopwatch()..start();
        try {
          final res = await raceCancel(
            environment
                .testProxyDelay(
                  proxyName: 'DIRECT',
                  testUrl: cfg.testUrl,
                  requestId: reqId,
                  timeout: const Duration(seconds: 5),
                )
                .timeout(const Duration(seconds: 6)),
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
          return switch (res.reason) {
            'notFound' => HealthCheckResult(
                id: HealthCheckId.directConnectivity,
                status: HealthStatus.skipped,
                elapsedMs: ms,
                reasonCode: 'runtimeNotLoaded',
              ),
            'overloaded' => HealthCheckResult(
                id: HealthCheckId.directConnectivity,
                status: HealthStatus.warning,
                elapsedMs: ms,
                reasonCode: 'coreDelayBusy',
              ),
            'deadlineExceeded' => HealthCheckResult(
                id: HealthCheckId.directConnectivity,
                status: HealthStatus.timeout,
                elapsedMs: ms,
                reasonCode: 'directTimeout',
              ),
            _ => HealthCheckResult(
                id: HealthCheckId.directConnectivity,
                status: HealthStatus.failed,
                elapsedMs: ms,
                reasonCode: 'directFailed',
              ),
          };
        } on _HealthCancelledException {
          rethrow;
        } on TimeoutException {
          return HealthCheckResult(
            id: HealthCheckId.directConnectivity,
            status: HealthStatus.timeout,
            elapsedMs: watch.elapsedMilliseconds,
            reasonCode: 'directTimeout',
          );
        } catch (_) {
          return HealthCheckResult(
            id: HealthCheckId.directConnectivity,
            status: HealthStatus.failed,
            elapsedMs: watch.elapsedMilliseconds,
            reasonCode: 'directFailed',
          );
        }
      }

      Future<HealthCheckResult> runD2() async {
        final parsedHost = Uri.tryParse(cfg.testUrl)?.host.trim() ?? '';
        final probeHost = (parsedHost.isEmpty ||
                InternetAddress.tryParse(parsedHost) != null)
            ? 'www.gstatic.com'
            : parsedHost;
        final watch = Stopwatch()..start();
        try {
          final addresses = await raceCancel(
            environment
                .lookupHost(probeHost)
                .timeout(const Duration(seconds: 3)),
          );
          final ms = watch.elapsedMilliseconds;
          if (addresses.isEmpty) {
            return HealthCheckResult(
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
          return HealthCheckResult(
            id: HealthCheckId.dnsResolution,
            status: HealthStatus.passed,
            elapsedMs: ms,
            reasonCode: fakeIp ? 'dnsFakeIpActive' : 'ok',
          );
        } on _HealthCancelledException {
          rethrow;
        } on TimeoutException {
          return HealthCheckResult(
            id: HealthCheckId.dnsResolution,
            status: HealthStatus.timeout,
            elapsedMs: watch.elapsedMilliseconds,
            reasonCode: 'dnsTimeout',
            action: HealthAction.openDnsSettings,
          );
        } catch (_) {
          return HealthCheckResult(
            id: HealthCheckId.dnsResolution,
            status: HealthStatus.failed,
            elapsedMs: watch.elapsedMilliseconds,
            reasonCode: 'dnsLookupFailed',
            action: HealthAction.openDnsSettings,
          );
        }
      }

      String? resolvedActiveLeaf;
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
        final group = _selectActiveGroup(cfg);
        if (group == null) {
          return const HealthCheckResult(
            id: HealthCheckId.outboundConnectivity,
            status: HealthStatus.failed,
            elapsedMs: 0,
            reasonCode: 'outboundGroupMissing',
            action: HealthAction.openProfiles,
          );
        }
        final leaf =
            _resolveSelectedLeaf(group, cfg.allGroups, cfg.selectedMap);
        resolvedActiveLeaf = leaf;
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

        final reqId = 'hc-outbound-$seq';
        token.register(() => environment.cancelProxyDelay(reqId));
        final watch = Stopwatch()..start();
        final url = cfg.resolveGroupTestUrl(group.testUrl);
        try {
          final res = await raceCancel(
            environment
                .testProxyDelay(
                  proxyName: group.name,
                  testUrl: url,
                  requestId: reqId,
                  timeout: const Duration(seconds: 5),
                )
                .timeout(const Duration(seconds: 6)),
          );
          final ms = watch.elapsedMilliseconds;
          if (res.value > 0) {
            resolvedOutboundDelay = res.value;
            final detail = '$leaf · ${res.value} ms';
            if (res.value <= 300) {
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
              reasonCode: res.value <= 800 ? 'outboundSlow' : 'outboundVerySlow',
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
      record(d3);

      // Phase 3: End-to-End Verification (D4)
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
      } else if (d3.status.isFailure) {
        d4 = const HealthCheckResult(
          id: HealthCheckId.endToEndConnectivity,
          status: HealthStatus.skipped,
          elapsedMs: 0,
          reasonCode: 'outboundFailed',
        );
      } else {
        final tunActive =
            c2.status == HealthStatus.passed || c2.status == HealthStatus.warning;
        final directive = tunActive ? 'DIRECT' : verifiedSysProxyDirective;
        final watch = Stopwatch()..start();
        try {
          final obs = await raceCancel(
            environment
                .probeEndToEnd(
                  cancelToken: token,
                  explicitProxyDirective: directive,
                )
                .timeout(const Duration(seconds: 8)),
          );
          final ms = watch.elapsedMilliseconds;
          if (obs == null) {
            d4 = HealthCheckResult(
              id: HealthCheckId.endToEndConnectivity,
              status: HealthStatus.failed,
              elapsedMs: ms,
              reasonCode: 'e2eAllSourcesFailed',
              action: HealthAction.openProxies,
            );
          } else {
            exitCountryCode =
                obs.exitCountryCode.length == 2 ? obs.exitCountryCode : null;
            if (!obs.observedInCore) {
              d4 = HealthCheckResult(
                id: HealthCheckId.endToEndConnectivity,
                status: HealthStatus.warning,
                elapsedMs: ms,
                reasonCode: 'trafficBypassedCore',
                exitCountryCode: exitCountryCode,
                action: HealthAction.openTunSettings,
              );
            } else if (obs.matchedLeafProxy == 'REJECT' ||
                obs.matchedLeafProxy == 'REJECT-DROP') {
              d4 = HealthCheckResult(
                id: HealthCheckId.endToEndConnectivity,
                status: HealthStatus.failed,
                elapsedMs: ms,
                reasonCode: 'e2eRejectedByRule',
                action: HealthAction.openProxies,
              );
            } else if (obs.matchedLeafProxy == 'DIRECT') {
              d4 = HealthCheckResult(
                id: HealthCheckId.endToEndConnectivity,
                status: HealthStatus.passed,
                elapsedMs: ms,
                reasonCode: 'routedDirectByRule',
                exitCountryCode: exitCountryCode,
              );
            } else {
              d4 = HealthCheckResult(
                id: HealthCheckId.endToEndConnectivity,
                status: HealthStatus.passed,
                elapsedMs: ms,
                reasonCode: 'ok',
                exitCountryCode: exitCountryCode,
                nodeName: obs.matchedLeafProxy,
              );
            }
          }
        } on _HealthCancelledException {
          rethrow;
        } on TimeoutException {
          d4 = HealthCheckResult(
            id: HealthCheckId.endToEndConnectivity,
            status: HealthStatus.timeout,
            elapsedMs: watch.elapsedMilliseconds,
            reasonCode: 'e2eTimeout',
            action: HealthAction.openProxies,
          );
        } catch (_) {
          d4 = HealthCheckResult(
            id: HealthCheckId.endToEndConnectivity,
            status: HealthStatus.failed,
            elapsedMs: watch.elapsedMilliseconds,
            reasonCode: 'e2eAllSourcesFailed',
            action: HealthAction.openProxies,
          );
        }
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

  HealthReport? _lastReport;
  Map<HealthCheckId, HealthCheckResult> _liveSnapshot = const {};
  Map<HealthCheckId, HealthCheckResult> _previousById = const {};
  HealthCancellationToken? _activeToken;
  bool _running = false;
  bool _disposed = false;

  HealthReport? get lastReport => _lastReport;
  Map<HealthCheckId, HealthCheckResult> get liveSnapshot => _liveSnapshot;
  Map<HealthCheckId, HealthCheckResult> get previousById => _previousById;
  bool get isRunning => _running;

  Future<HealthReport?> startOrAttach() async {
    if (_disposed || _running) return _lastReport;
    if (_lastReport != null) {
      _previousById = {
        for (final item in _lastReport!.checks) item.id: item,
      };
    }
    final token = HealthCancellationToken();
    _activeToken = token;
    _running = true;
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
      // Cancelled or interrupted: restore previous completed snapshot if any.
      if (!_disposed && _previousById.isNotEmpty) {
        _liveSnapshot = _previousById;
      }
      return null;
    } finally {
      if (identical(_activeToken, token)) {
        _activeToken = null;
        _running = false;
        if (!_disposed) notifyListeners();
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

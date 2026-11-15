import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flclashx/clash/clash.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/delay_test_coordinator.dart';
import 'package:flclashx/common/health/health_models.dart';
import 'package:flclashx/common/tun_runtime.dart';
import 'package:flclashx/common/windows_system_proxy_probe.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/pac.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class HealthConfigSnapshot {
  const HealthConfigSnapshot({
    required this.currentProfileId,
    required this.currentProfile,
    required this.profileFileExists,
    required this.profileFileBytes,
    required this.mode,
    required this.mixedPort,
    required this.testUrl,
    required this.resolveGroupTestUrl,
    required this.systemProxyEnabled,
    required this.pacEnabled,
    required this.pacUrl,
    required this.tunDesiredEnabled,
    required this.tunFailureCode,
    required this.realTunEnable,
    required this.proxyStarted,
    required this.lastRuntimeProfileId,
    required this.groupsSnapshotProfileId,
    required this.allGroups,
    required this.visibleGroups,
    required this.selectedMap,
    this.primaryRuleTargetGroup,
  });

  final String? currentProfileId;
  final Profile? currentProfile;
  final bool profileFileExists;
  final int profileFileBytes;
  final Mode mode;
  final int mixedPort;
  final String testUrl;
  final String Function(String? groupTestUrl) resolveGroupTestUrl;
  final bool systemProxyEnabled;
  final bool pacEnabled;
  final String? pacUrl;
  final bool tunDesiredEnabled;
  final String? tunFailureCode;
  final bool realTunEnable;
  final bool proxyStarted;
  final String? lastRuntimeProfileId;
  final String? groupsSnapshotProfileId;
  final List<Group> allGroups;
  final List<Group> visibleGroups;
  final Map<String, String> selectedMap;
  final String? primaryRuleTargetGroup;
}

int resolveEffectiveMixedPort({
  required int configuredMixedPort,
  required Map<String, dynamic>? lastRuntimeConfig,
  required String? lastRuntimeProfileId,
  required String? currentProfileId,
}) {
  final profileMatches = lastRuntimeProfileId == null ||
      (currentProfileId != null && lastRuntimeProfileId == currentProfileId);
  if (profileMatches &&
      lastRuntimeConfig != null &&
      lastRuntimeConfig.containsKey('mixed-port')) {
    final raw = lastRuntimeConfig['mixed-port'];
    if (raw is int && raw >= 0 && raw <= 65535) {
      return raw;
    }
    if (raw is num) {
      final asInt = raw.toInt();
      if (asInt >= 0 && asInt <= 65535) {
        return asInt;
      }
    }
    if (raw is String) {
      final parsed = int.tryParse(raw.trim());
      if (parsed != null && parsed >= 0 && parsed <= 65535) {
        return parsed;
      }
    }
  }
  return configuredMixedPort;
}

class CoreLivenessObservation {
  const CoreLivenessObservation({
    required this.isInit,
    required this.memoryBytes,
    required this.trafficValid,
  });

  final bool isInit;
  final int? memoryBytes;
  final bool trafficValid;
}

class EndToEndProbeObservation {
  const EndToEndProbeObservation({
    required this.exitCountryCode,
    required this.observedInCore,
    this.matchedLeafProxy,
  });

  final String exitCountryCode;
  final bool observedInCore;
  final String? matchedLeafProxy;
}

abstract class HealthProbeEnvironment {
  DateTime now();
  String get platform;
  String get appVersion;

  Future<HealthConfigSnapshot> readConfigSnapshot();
  Future<CoreLivenessObservation> checkCoreLiveness();
  Future<TunStatus?> readTunStatus();
  Future<WindowsSystemProxySnapshot?> readWindowsSystemProxy();
  Future<DelayTestResult> testProxyDelay({
    required String proxyName,
    required String testUrl,
    required String requestId,
    required Duration timeout,
  });
  Future<void> cancelProxyDelay(String requestId);
  Future<List<InternetAddress>> lookupHost(String host);
  Future<EndToEndProbeObservation?> probeEndToEnd({
    required HealthCancellationToken cancelToken,
    required String? explicitProxyDirective,
  });
}

/// Optional telemetry capability allowing `HealthRunner` to distinguish
/// "socket never entered Core (TUN bypass/blackhole)" from "socket entered
/// Core via TUN and failed upstream on the selected proxy node".
abstract interface class CoreFailedProbeTelemetry {
  bool get lastFailedProbeObservedInCore;
}

/// Optional capability allowing `HealthRunner` to pass an adaptive timeout
/// budget to end-to-end exit-IP probes without altering the legacy signature.
abstract interface class AdaptiveEndToEndProbeEnvironment {
  Future<EndToEndProbeObservation?> probeEndToEndWithBudget({
    required HealthCancellationToken cancelToken,
    required String? explicitProxyDirective,
    required Duration connectTimeout,
    required Duration attemptTimeout,
  });
}

bool isVerifiedLoopbackProxyDirective(String? directive) {
  if (directive == null) return false;
  final trimmed = directive.trim();
  if (!trimmed.toUpperCase().startsWith('PROXY ')) return false;
  final lower = trimmed.substring(6).trim().toLowerCase();
  return lower.startsWith('127.0.0.1:') ||
      lower.startsWith('localhost:') ||
      lower.startsWith('[::1]:');
}

({bool observedInCore, String? matchedLeafProxy})
    resolveEndToEndCoreObservation({
  required String? explicitProxyDirective,
  required Set<String> sourcePorts,
  required String probeHost,
  required DateTime minStart,
  required DateTime maxStart,
  required List<Connection> connections,
  required Set<String> groupNames,
}) {
  final normalizedHost = probeHost.trim().toLowerCase();
  for (var i = connections.length - 1; i >= 0; i--) {
    final conn = connections[i];
    if (conn.start.isBefore(minStart) || conn.start.isAfter(maxStart)) {
      continue;
    }
    final srcPort = conn.metadata.sourcePort.trim();
    final portMatched = srcPort.isNotEmpty && sourcePorts.contains(srcPort);
    if (!portMatched) continue;

    final metaHost = conn.metadata.host.trim().toLowerCase();
    final sniffHost = conn.metadata.sniffHost.trim().toLowerCase();
    final hostConsistent = normalizedHost.isEmpty ||
        (metaHost.isEmpty && sniffHost.isEmpty) ||
        metaHost == normalizedHost ||
        sniffHost == normalizedHost;
    if (!hostConsistent) continue;

    String? matchedLeaf;
    if (conn.chains.isNotEmpty) {
      matchedLeaf = conn.chains.firstWhere(
        (hop) => hop.isNotEmpty && !groupNames.contains(hop),
        orElse: () => conn.chains.first,
      );
    }
    return (observedInCore: true, matchedLeafProxy: matchedLeaf);
  }
  if (isVerifiedLoopbackProxyDirective(explicitProxyDirective)) {
    return (observedInCore: true, matchedLeafProxy: null);
  }
  return (observedInCore: false, matchedLeafProxy: null);
}

class DefaultHealthProbeEnvironment
    implements
        HealthProbeEnvironment,
        CoreFailedProbeTelemetry,
        AdaptiveEndToEndProbeEnvironment {
  DefaultHealthProbeEnvironment(this._ref, {Request? probeRequest})
      : _probeRequest = probeRequest;
  final Ref _ref;
  final Request? _probeRequest;
  bool _lastFailedProbeObservedInCore = false;

  @override
  bool get lastFailedProbeObservedInCore => _lastFailedProbeObservedInCore;

  @override
  DateTime now() => DateTime.now();

  @override
  String get platform => Platform.operatingSystem;

  @override
  String get appVersion {
    try {
      return globalState.packageInfo.version;
    } catch (_) {
      return 'unknown';
    }
  }

  @override
  Future<HealthConfigSnapshot> readConfigSnapshot() async {
    final currentProfileId = _ref.read(currentProfileIdProvider);
    final profiles = _ref.read(profilesProvider);
    final currentProfile = profiles.getProfile(currentProfileId);
    var fileExists = false;
    var fileBytes = 0;
    if (currentProfileId != null && currentProfileId.isNotEmpty) {
      try {
        final profilePath = await appPath.getProfilePath(currentProfileId);
        // Never use Isolate.run here: Dart closures in the same lexical scope
        // share a single Context that captures `_ref` (ProviderContainer /
        // ReceivePort / Timer), throwing ArgumentError on Isolate message send.
        final stat = File(profilePath).statSync();
        fileExists = stat.type != FileSystemEntityType.notFound;
        fileBytes = fileExists ? stat.size : 0;
      } on FileSystemException {
        fileExists = false;
        fileBytes = 0;
      } catch (_) {
        fileExists = false;
        fileBytes = 0;
      }
    }

    final patchClash = _ref.read(patchClashConfigProvider);
    final networkProps = _ref.read(networkSettingProvider);
    var pac = _ref.read(pacSettingsProvider).valueOrNull;
    if (pac == null) {
      try {
        pac = await _ref
            .read(pacSettingsProvider.future)
            .timeout(const Duration(seconds: 1));
      } catch (_) {
        pac = _ref.read(pacSettingsProvider).valueOrNull;
      }
    }
    final tunRuntimeCtrl = _ref.read(tunRuntimeProvider);

    final bool tunDesired;
    if (Platform.isWindows) {
      final hasRuntimeIntent =
          tunRuntimeCtrl.status != null || tunRuntimeCtrl.intentRevision > 0;
      tunDesired =
          hasRuntimeIntent ? tunRuntimeCtrl.desiredEnabled : patchClash.tun.enable;
    } else if (Platform.isAndroid) {
      tunDesired = _ref.read(vpnSettingProvider).enable;
    } else {
      tunDesired = patchClash.tun.enable;
    }

    var allGroups = _ref.read(groupsProvider);
    var visibleGroups = _ref.read(currentGroupsStateProvider).value;
    try {
      final activeCore = ClashCore.existingCore;
      if (activeCore != null) {
        final liveGroups = await (() async {
          if (!await Future.value(activeCore.isInit)) {
            return const <Group>[];
          }
          return activeCore.getProxiesGroups();
        })().timeout(const Duration(milliseconds: 1200));
        if (liveGroups.isNotEmpty) {
          allGroups = liveGroups;
          visibleGroups = switch (patchClash.mode) {
            Mode.direct => const <Group>[],
            Mode.global => liveGroups
                .where((g) => g.name == GroupName.GLOBAL.name)
                .toList(),
            Mode.rule => liveGroups
                .where(
                  (g) => g.hidden != true && g.name != GroupName.GLOBAL.name,
                )
                .toList(),
          };
        }
      }
    } catch (_) {
      // Retain Riverpod snapshot if live IPC group fetch times out.
    }

    final lastRuntimeProfileId = globalState.lastRuntimeProfileId;
    final runtimeProfileMatches = lastRuntimeProfileId == null ||
        (currentProfileId != null && lastRuntimeProfileId == currentProfileId);
    final effectiveMixedPort = resolveEffectiveMixedPort(
      configuredMixedPort: patchClash.mixedPort,
      lastRuntimeConfig: globalState.lastRuntimeConfig,
      lastRuntimeProfileId: lastRuntimeProfileId,
      currentProfileId: currentProfileId,
    );

    String? primaryRuleTargetGroup;
    if (runtimeProfileMatches && allGroups.isNotEmpty) {
      final compiledTarget =
          globalState.lastCompiledRuleResult?.primaryProxyTarget.trim();
      if (compiledTarget != null &&
          compiledTarget.isNotEmpty &&
          allGroups.any((g) => g.name == compiledTarget)) {
        primaryRuleTargetGroup = compiledTarget;
      } else if (globalState.lastRuntimeConfig case final runtimeCfg?) {
        final rawRules = runtimeCfg['rules'];
        final rawProxyGroups = runtimeCfg['proxy-groups'];
        final rawProxies = runtimeCfg['proxies'];
        if (rawRules is Iterable) {
          final synthesizedGroups = rawProxyGroups is Iterable
              ? rawProxyGroups
              : <Map<String, Object?>>[
                  for (final g in allGroups)
                    <String, Object?>{'name': g.name, 'hidden': g.hidden},
                ];
          final candidate = resolvePrimaryProxyTarget(
            rawRules: rawRules,
            proxyGroups: synthesizedGroups,
            proxies: rawProxies is Iterable ? rawProxies : const [],
          );
          if (candidate.isNotEmpty &&
              allGroups.any((g) => g.name == candidate)) {
            primaryRuleTargetGroup = candidate;
          }
        }
      }
    }

    final selectedMap = _ref.read(selectedMapProvider);
    final testUrl = _ref.read(appSettingProvider).testUrl;

    return HealthConfigSnapshot(
      currentProfileId: currentProfileId,
      currentProfile: currentProfile,
      profileFileExists: fileExists,
      profileFileBytes: fileBytes,
      mode: patchClash.mode,
      mixedPort: effectiveMixedPort,
      testUrl: testUrl,
      resolveGroupTestUrl: (groupUrl) => _ref.read(getRealTestUrlProvider(groupUrl)),
      systemProxyEnabled: networkProps.systemProxy,
      pacEnabled: pac?.enabled ?? false,
      pacUrl: pac?.url,
      tunDesiredEnabled: tunDesired,
      tunFailureCode: Platform.isWindows ? tunRuntimeCtrl.failure : null,
      realTunEnable: globalState.isAppStateInitialized
          ? globalState.appState.realTunEnable
          : false,
      proxyStarted: _ref.read(runTimeProvider) != null,
      lastRuntimeProfileId: lastRuntimeProfileId,
      groupsSnapshotProfileId: globalState.groupsSnapshotProfileId,
      allGroups: allGroups,
      visibleGroups: visibleGroups,
      selectedMap: selectedMap,
      primaryRuleTargetGroup: primaryRuleTargetGroup,
    );
  }

  @override
  Future<CoreLivenessObservation> checkCoreLiveness() async {
    final activeCore = ClashCore.existingCore;
    if (activeCore == null) {
      return const CoreLivenessObservation(
        isInit: false,
        memoryBytes: null,
        trafficValid: false,
      );
    }
    final init = await activeCore.isInit;
    if (!init) {
      return const CoreLivenessObservation(
        isInit: false,
        memoryBytes: null,
        trafficValid: false,
      );
    }
    final memRaw = await activeCore.clashInterface.getMemory();
    final memBytes = int.tryParse(memRaw);
    final trafficRaw = await activeCore.clashInterface.getTraffic();
    var trafficOk = false;
    if (trafficRaw is Map) {
      trafficOk = trafficRaw['up'] is num && trafficRaw['down'] is num;
    } else if (trafficRaw is String && trafficRaw.isNotEmpty) {
      final decoded = jsonDecode(trafficRaw);
      trafficOk =
          decoded is Map && decoded['up'] is num && decoded['down'] is num;
    }
    return CoreLivenessObservation(
      isInit: true,
      memoryBytes: (memBytes != null && memBytes >= 0) ? memBytes : null,
      trafficValid: trafficOk,
    );
  }

  @override
  Future<TunStatus?> readTunStatus() async {
    final activeCore = ClashCore.existingCore;
    if (!Platform.isWindows || activeCore == null) return null;
    return activeCore.getTunStatus();
  }

  @override
  Future<WindowsSystemProxySnapshot?> readWindowsSystemProxy() async {
    if (!Platform.isWindows) return null;
    return readWindowsSystemProxyRegistry();
  }

  @override
  Future<DelayTestResult> testProxyDelay({
    required String proxyName,
    required String testUrl,
    required String requestId,
    required Duration timeout,
  }) =>
      clashCore.getDelayResult(
        testUrl,
        proxyName,
        requestId: requestId,
        timeout: timeout,
      );

  @override
  Future<void> cancelProxyDelay(String requestId) =>
      clashCore.cancelDelayTest(requestId);

  @override
  Future<List<InternetAddress>> lookupHost(String host) =>
      InternetAddress.lookup(host);

  static const Duration _defaultEndToEndConnectTimeout =
      Duration(milliseconds: 2800);
  static const Duration _defaultEndToEndAttemptTimeout =
      Duration(milliseconds: 3200);

  @override
  Future<EndToEndProbeObservation?> probeEndToEnd({
    required HealthCancellationToken cancelToken,
    required String? explicitProxyDirective,
  }) =>
      _probeEndToEndInternal(
        cancelToken: cancelToken,
        explicitProxyDirective: explicitProxyDirective,
        connectTimeout: _defaultEndToEndConnectTimeout,
        attemptTimeout: _defaultEndToEndAttemptTimeout,
      );

  @override
  Future<EndToEndProbeObservation?> probeEndToEndWithBudget({
    required HealthCancellationToken cancelToken,
    required String? explicitProxyDirective,
    required Duration connectTimeout,
    required Duration attemptTimeout,
  }) =>
      _probeEndToEndInternal(
        cancelToken: cancelToken,
        explicitProxyDirective: explicitProxyDirective,
        connectTimeout: connectTimeout,
        attemptTimeout: attemptTimeout,
      );

  Future<EndToEndProbeObservation?> _probeEndToEndInternal({
    required HealthCancellationToken cancelToken,
    required String? explicitProxyDirective,
    required Duration connectTimeout,
    required Duration attemptTimeout,
  }) async {
    final dioCancel = CancelToken();
    cancelToken.register(() {
      if (!dioCancel.isCancelled) {
        dioCancel.cancel('healthCheckCancelled');
      }
    });

    Future<List<Connection>> snapshotCoreConnections() {
      final activeCore = ClashCore.existingCore;
      if (activeCore == null) {
        return Future.value(const <Connection>[]);
      }
      return activeCore
          .getConnections()
          .timeout(const Duration(milliseconds: 1500))
          .catchError((Object _) => const <Connection>[]);
    }

    List<Connection> readRecentRecordedConnections() {
      final results = <Connection>[];
      try {
        results.addAll(_ref.read(requestsProvider).list);
      } catch (_) {}
      if (globalState.isAppStateInitialized) {
        results.addAll(globalState.appState.requests.list);
      }
      return results;
    }

    _lastFailedProbeObservedInCore = false;
    final startedAt = DateTime.now();
    final inFlightFutures = <Future<List<Connection>>>[];
    final observedAttemptPorts = <String>{};

    bool anyAttemptObservedInCore(Iterable<Connection> connections) {
      if (observedAttemptPorts.isEmpty) return false;
      return resolveEndToEndCoreObservation(
        explicitProxyDirective: 'DIRECT',
        sourcePorts: observedAttemptPorts,
        probeHost: '',
        minStart: startedAt.subtract(const Duration(seconds: 2)),
        maxStart: DateTime.now().add(const Duration(seconds: 2)),
        connections: connections.toList(growable: false),
        groupNames: const <String>{},
      ).observedInCore;
    }

    try {
      final activeRequest = _probeRequest ?? request;
      final res = await activeRequest.checkIpWithHost(
        cancelToken: dioCancel,
        keepAliveHold: const Duration(milliseconds: 1800),
        connectTimeout: connectTimeout,
        attemptTimeout: attemptTimeout,
        forceHoldSocket: true,
        proxyResolver: explicitProxyDirective != null
            ? (_) => explicitProxyDirective
            : null,
        onSocketConnected: (activePorts) {
          if (cancelToken.isCancelled) return;
          observedAttemptPorts.addAll(activePorts);
          if (!_lastFailedProbeObservedInCore &&
              anyAttemptObservedInCore(readRecentRecordedConnections())) {
            _lastFailedProbeObservedInCore = true;
          }
          final snapFuture = snapshotCoreConnections();
          inFlightFutures.add(snapFuture);
          unawaited(
            snapFuture.then((conns) {
              if (!_lastFailedProbeObservedInCore &&
                  anyAttemptObservedInCore([
                    ...conns,
                    ...readRecentRecordedConnections(),
                  ])) {
                _lastFailedProbeObservedInCore = true;
              }
            }),
          );
        },
      );
      if (cancelToken.isCancelled) {
        _lastFailedProbeObservedInCore = false;
        return null;
      }
      if (res.isError || res.data == null) {
        if (!_lastFailedProbeObservedInCore &&
            observedAttemptPorts.isNotEmpty) {
          final mergedOnFailure = <Connection>[
            ...readRecentRecordedConnections(),
          ];
          for (final f in inFlightFutures) {
            if (cancelToken.isCancelled) break;
            mergedOnFailure.addAll(await f);
          }
          if (!_lastFailedProbeObservedInCore &&
              !cancelToken.isCancelled &&
              !anyAttemptObservedInCore(mergedOnFailure)) {
            final activeCore = ClashCore.existingCore;
            if (activeCore != null) {
              mergedOnFailure.addAll(
                await activeCore
                    .getConnections()
                    .timeout(const Duration(milliseconds: 300))
                    .catchError((Object _) => const <Connection>[]),
              );
            }
          }
          if (anyAttemptObservedInCore(mergedOnFailure)) {
            _lastFailedProbeObservedInCore = true;
          }
        }
        return null;
      }
      _lastFailedProbeObservedInCore = false;
      final probe = res.data!;

      final allGroups = _ref.read(groupsProvider);
      final groupNames = <String>{
        for (final g in allGroups) g.name,
        GroupName.GLOBAL.name,
      };

      final mergedConnections = <Connection>[];
      for (final f in inFlightFutures) {
        if (cancelToken.isCancelled) return null;
        mergedConnections.addAll(await f);
      }
      if (!cancelToken.isCancelled) {
        mergedConnections
          ..addAll(await snapshotCoreConnections())
          ..addAll(readRecentRecordedConnections());
      }

      var resolved = resolveEndToEndCoreObservation(
        explicitProxyDirective: explicitProxyDirective,
        sourcePorts: probe.sourcePorts,
        probeHost: probe.host,
        minStart: startedAt.subtract(const Duration(seconds: 2)),
        maxStart: DateTime.now().add(const Duration(seconds: 2)),
        connections: mergedConnections,
        groupNames: groupNames,
      );

      if ((!resolved.observedInCore || resolved.matchedLeafProxy == null) &&
          !cancelToken.isCancelled) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        if (!cancelToken.isCancelled) {
          mergedConnections
            ..addAll(await snapshotCoreConnections())
            ..addAll(readRecentRecordedConnections());
          resolved = resolveEndToEndCoreObservation(
            explicitProxyDirective: explicitProxyDirective,
            sourcePorts: probe.sourcePorts,
            probeHost: probe.host,
            minStart: startedAt.subtract(const Duration(seconds: 2)),
            maxStart: DateTime.now().add(const Duration(seconds: 2)),
            connections: mergedConnections,
            groupNames: groupNames,
          );
        }
      }

      return EndToEndProbeObservation(
        exitCountryCode: probe.ipInfo.countryCode.trim().toUpperCase(),
        observedInCore: resolved.observedInCore,
        matchedLeafProxy: resolved.matchedLeafProxy,
      );
    } finally {
      if (!dioCancel.isCancelled) {
        dioCancel.cancel('probeComplete');
      }
    }
  }
}

final healthProbeEnvironmentProvider = Provider<HealthProbeEnvironment>(
  DefaultHealthProbeEnvironment.new,
);

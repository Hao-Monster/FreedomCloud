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
import 'package:flclashx/providers/tun.dart';
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

class DefaultHealthProbeEnvironment implements HealthProbeEnvironment {
  DefaultHealthProbeEnvironment(this._ref);
  final Ref _ref;

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
        final stat = File(profilePath).statSync();
        fileExists = stat.type != FileSystemEntityType.notFound;
        fileBytes = fileExists ? stat.size : 0;
      } catch (_) {
        fileExists = false;
        fileBytes = 0;
      }
    }

    final patchClash = _ref.read(patchClashConfigProvider);
    final networkProps = _ref.read(networkSettingProvider);
    final pac = _ref.read(pacSettingsProvider).valueOrNull;
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

    final allGroups = _ref.read(groupsProvider);
    final visibleGroups = _ref.read(currentGroupsStateProvider).value;
    final selectedMap = _ref.read(selectedMapProvider);
    final testUrl = _ref.read(appSettingProvider).testUrl;

    return HealthConfigSnapshot(
      currentProfileId: currentProfileId,
      currentProfile: currentProfile,
      profileFileExists: fileExists,
      profileFileBytes: fileBytes,
      mode: patchClash.mode,
      mixedPort: patchClash.mixedPort,
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
      lastRuntimeProfileId: globalState.lastRuntimeProfileId,
      groupsSnapshotProfileId: globalState.groupsSnapshotProfileId,
      allGroups: allGroups,
      visibleGroups: visibleGroups,
      selectedMap: selectedMap,
    );
  }

  @override
  Future<CoreLivenessObservation> checkCoreLiveness() async {
    final init = await clashCore.isInit;
    if (!init) {
      return const CoreLivenessObservation(
        isInit: false,
        memoryBytes: null,
        trafficValid: false,
      );
    }
    final memRaw = await clashCore.clashInterface.getMemory();
    final memBytes = int.tryParse(memRaw);
    final trafficRaw = await clashCore.clashInterface.getTraffic();
    var trafficOk = false;
    if (trafficRaw.isNotEmpty) {
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
    if (!Platform.isWindows) return null;
    return clashCore.getTunStatus();
  }

  @override
  Future<WindowsSystemProxySnapshot?> readWindowsSystemProxy() async =>
      readWindowsSystemProxyRegistry();

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

  @override
  Future<EndToEndProbeObservation?> probeEndToEnd({
    required HealthCancellationToken cancelToken,
    required String? explicitProxyDirective,
  }) async {
    final dioCancel = CancelToken();
    cancelToken.register(() {
      if (!dioCancel.isCancelled) {
        dioCancel.cancel('healthCheckCancelled');
      }
    });

    final startedAt = DateTime.now();
    try {
      final res = await request.checkIpWithHost(
        cancelToken: dioCancel,
        keepAliveHold: const Duration(milliseconds: 1800),
        connectTimeout: const Duration(seconds: 4),
        proxyResolver: explicitProxyDirective != null
            ? (_) => explicitProxyDirective
            : null,
      );
      if (cancelToken.isCancelled || res.isError) return null;
      final probe = res.data;
      if (probe == null) return null;

      final allGroups = _ref.read(groupsProvider);
      final groupNames = <String>{
        for (final g in allGroups) g.name,
        GroupName.GLOBAL.name,
      };

      var observedInCore = false;
      String? matchedLeaf;
      try {
        final connections = await clashCore.getConnections();
        final minStart = startedAt.subtract(const Duration(seconds: 2));
        final maxStart = DateTime.now().add(const Duration(seconds: 2));
        final probeHost = probe.host.trim().toLowerCase();

        for (var i = connections.length - 1; i >= 0; i--) {
          final conn = connections[i];
          if (conn.start.isBefore(minStart) || conn.start.isAfter(maxStart)) {
            continue;
          }
          final srcPort = conn.metadata.sourcePort.trim();
          final portMatched =
              srcPort.isNotEmpty && probe.sourcePorts.contains(srcPort);
          if (!portMatched) continue;

          final metaHost = conn.metadata.host.trim().toLowerCase();
          final sniffHost = conn.metadata.sniffHost.trim().toLowerCase();
          final hostConsistent = probeHost.isEmpty ||
              (metaHost.isEmpty && sniffHost.isEmpty) ||
              metaHost == probeHost ||
              sniffHost == probeHost;
          if (!hostConsistent) continue;

          observedInCore = true;
          if (conn.chains.isNotEmpty) {
            matchedLeaf = conn.chains.firstWhere(
              (hop) => hop.isNotEmpty && !groupNames.contains(hop),
              orElse: () => conn.chains.first,
            );
          }
          break;
        }
      } catch (_) {
        observedInCore = false;
      }

      return EndToEndProbeObservation(
        exitCountryCode: probe.ipInfo.countryCode.trim().toUpperCase(),
        observedInCore: observedInCore,
        matchedLeafProxy: matchedLeaf,
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

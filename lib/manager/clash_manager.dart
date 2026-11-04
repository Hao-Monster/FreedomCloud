import 'dart:async';

import 'package:flclashx/clash/clash.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/tun_runtime.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/app.dart';
import 'package:flclashx/providers/config.dart';
import 'package:flclashx/providers/state.dart';
import 'package:flclashx/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'clash_config_update_listener.dart';
import 'connection_manager.dart';

class ClashManager extends ConsumerStatefulWidget {
  const ClashManager({
    super.key,
    required this.child,
  });
  final Widget child;

  @override
  ConsumerState<ClashManager> createState() => _ClashContainerState();
}

class _ClashContainerState extends ConsumerState<ClashManager>
    with AppMessageListener {
  static const int _telemetryBatchFlushLimit = 128;
  static const Duration _telemetryBatchWindow = Duration(milliseconds: 64);
  final List<Log> _pendingLogs = [];
  final List<Connection> _pendingRequests = [];
  Timer? _telemetryFlushTimer;

  void _scheduleTelemetryFlush() {
    _telemetryFlushTimer ??= Timer(_telemetryBatchWindow, _flushPendingTelemetry);
  }

  void _flushPendingTelemetry() {
    _telemetryFlushTimer?.cancel();
    _telemetryFlushTimer = null;
    if (!mounted) {
      _pendingLogs.clear();
      _pendingRequests.clear();
      return;
    }
    if (_pendingLogs.isNotEmpty) {
      final batch = List<Log>.of(_pendingLogs, growable: false);
      _pendingLogs.clear();
      ref.read(logsProvider.notifier).addLogs(batch);
    }
    if (_pendingRequests.isNotEmpty) {
      final batch = List<Connection>.of(_pendingRequests, growable: false);
      _pendingRequests.clear();
      ref.read(requestsProvider.notifier).addRequests(batch);
    }
  }

  @override
  Widget build(BuildContext context) => ClashConfigUpdateListener(
    runtime: tunRuntime,
    onConfigChanged: () => globalState.appController.updateClashConfigDebounce(),
    child: widget.child,
  );

  @override
  void initState() {
    super.initState();
    clashMessage.addListener(this);
    connectionDiagnostics.log(
      '[ConnectionsDiag] clashManager.init '
      'build=${ConnectionDiagnostics.buildId} '
      'runtime=${ref.read(runTimeProvider) != null} '
      'intervalMs=${ref.read(appSettingProvider).connectionRefreshInterval}',
    );
    ref.listenManual(needSetupProvider, (prev, next) {
      if (prev != next) {
        globalState.appController.handleChangeProfile();
      }
    });
    ref.listenManual(coreStateProvider, (prev, next) async {
      if (prev != next) {
        await clashCore.setState(next);
      }
    });

    ref.listenManual(
      appSettingProvider.select((state) => state.openLogs),
      (prev, next) {
        if (next) {
          clashCore.startLog();
        } else {
          clashCore.stopLog();
        }
      },
    );
    ref.listenManual(
      runTimeProvider.select((state) => state != null),
      (previous, running) {
        connectionDiagnostics.log(
          '[ConnectionsDiag] runtime.changed '
          'previous=$previous running=$running',
        );
        connectionManager.configure(
          running: running,
          refreshIntervalMs:
              ref.read(appSettingProvider).connectionRefreshInterval,
        );
      },
      fireImmediately: true,
    );
    ref.listenManual(
      appSettingProvider.select((state) => state.connectionRefreshInterval),
      (previous, refreshIntervalMs) {
        connectionDiagnostics.log(
          '[ConnectionsDiag] interval.changed '
          'previous=$previous intervalMs=$refreshIntervalMs '
          'runtime=${ref.read(runTimeProvider) != null}',
        );
        connectionManager.configure(
          running: ref.read(runTimeProvider) != null,
          refreshIntervalMs: refreshIntervalMs,
        );
      },
      fireImmediately: true,
    );
  }

  @override
  Future<void> dispose() async {
    _telemetryFlushTimer?.cancel();
    _telemetryFlushTimer = null;
    _pendingLogs.clear();
    _pendingRequests.clear();
    connectionDiagnostics.log(
      '[ConnectionsDiag] clashManager.dispose '
      'managerRunning=${connectionManager.running}',
    );
    clashMessage.removeListener(this);
    super.dispose();
  }

  @override
  Future<void> onDelay(Delay delay) async {
    super.onDelay(delay);
    final appController = globalState.appController;
    appController.setDelay(delay);
    debouncer.call(
      FunctionTag.updateDelay,
      () async {
        appController.updateGroupsDebounce();
      },
      duration: const Duration(milliseconds: 5000),
    );
  }

  @override
  void onLog(Log log) {
    _pendingLogs.add(log);
    if (_pendingLogs.length >= _telemetryBatchFlushLimit) {
      _flushPendingTelemetry();
    } else {
      _scheduleTelemetryFlush();
    }

    // Write core logs to file
    fileLogger.log("[${log.logLevel.name.toUpperCase()}] ${log.payload}");

    if (log.logLevel == LogLevel.error) {
      globalState.showNotifier(log.payload);
    }
    super.onLog(log);
  }

  @override
  void onRequest(Connection connection) {
    _pendingRequests.add(connection);
    if (_pendingRequests.length >= _telemetryBatchFlushLimit) {
      _flushPendingTelemetry();
    } else {
      _scheduleTelemetryFlush();
    }
    super.onRequest(connection);
  }

  @override
  Future<void> onLoaded(String providerName) async {
    final configEpoch = globalState.runtimeConfigEpoch;
    final profileId = ref.read(currentProfileIdProvider);
    final provider = await clashCore.getExternalProvider(
      providerName,
    );
    if (!mounted ||
        configEpoch != globalState.runtimeConfigEpoch ||
        profileId != ref.read(currentProfileIdProvider)) {
      return;
    }
    ref.read(providersProvider.notifier).setProvider(provider);
    globalState.appController.updateGroupsDebounce();
    super.onLoaded(providerName);
  }
}

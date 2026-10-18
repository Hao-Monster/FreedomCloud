import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:flclashx/clash/clash.dart';
import 'package:flclashx/common/archive.dart';
import 'package:flclashx/services/subscription_notification_service.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/plugins/app.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/widgets/dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:path/path.dart' hide windows;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'common/common.dart';
import 'common/admin_authorization.dart';
import 'common/delay_tests.dart';
import 'common/node_health_recorder.dart';
import 'common/node_health_store.dart';
import 'common/tun_runtime.dart';
import 'common/ui_activity.dart';
import 'common/windows_tun_prepare.dart';
import 'common/windows_tun_startup.dart';
import 'models/models.dart';
import 'plugins/vpn.dart';
import 'providers/node_overview.dart';
import 'views/profiles/override_profile.dart';

class AppController {
  AppController(this.context, WidgetRef ref, {
    WindowsTunStartupEffects? windowsStartupEffects,
    TunRuntimeController? tunRuntimeController,
    Future<DateTime?> Function()? nativeRunTimeProbe,
    Duration tunSettleDelay = const Duration(milliseconds: 500),
  }) : _ref = ref,
       _windowsStartupEffects = windowsStartupEffects,
       _nativeRunTimeProbe = nativeRunTimeProbe,
       _tunSettleDelay = tunSettleDelay,
       _tunRuntime = tunRuntimeController ?? tunRuntime;
  final WindowsTunStartupEffects? _windowsStartupEffects;
  final Future<DateTime?> Function()? _nativeRunTimeProbe;
  final Duration _tunSettleDelay;
  final TunRuntimeController _tunRuntime;
  Future<void>? _runtimeInitialization;
  bool _runtimeInitialized = false;
  bool _recoveringRunningProjection = false;
  bool _pendingWindowsProxyStop = false;
  int _applyingWindowsConfigDepth = 0;
  Future<bool>? _activeTunRepair;
  Future<bool>? _lastTriggeredTunRepair;
  bool _hasAppliedWindowsProfile = false;
  bool _needsWindowsCoreRestore = false;
  bool _windowsCoreRestoreNeedsListener = false;
  String? _lastAppliedWindowsProfileId;
  UpdateParams? _syncingProfileUpdateParams;
  static const _maxTunRepairAttempts = 2;
  final Map<String, int> _tunRepairAttempts = {};
  int? lastProfileModified;
  final BuildContext context;
  final WidgetRef _ref;
  final _nodeHealthWrites = <Future<void>>{};
  NodeHealthStore? get catalogHealthStore =>
      _ref.read(nodeOverviewEnabledProvider)
          ? _ref.read(nodeHealthRecorderProvider).store
          : null;
  // A configuration update can race with profile recovery or another UI
  // setting.  Keep one privileged operation in flight and latch a failed
  // attempt so an unavailable/denied service cannot trigger UAC repeatedly.
  final AdminAuthorizationGate _adminAuthorization =
      AdminAuthorizationGate();
  Timer? _tunObservationTimer;
  late final TunStatusObserver _tunObserver = TunStatusObserver(
    runtime: _tunRuntime,
    read: () => clashCore.getTunStatus(),
  );

  WindowsTunStartupEffects _startupEffects({bool syncProviderSettings = true}) {
    final injected = _windowsStartupEffects;
    if (injected != null) {
      return _TrackedWindowsTunStartupEffects(this, injected);
    }
    return _ControllerWindowsTunStartupEffects(
      this,
      syncProviderSettings: syncProviderSettings,
    );
  }

  void startTunObservation() {
    if (!Platform.isWindows || _tunObservationTimer != null) return;
    _tunRuntime.desiredEnabled = _ref.read(patchClashConfigProvider).tun.enable;
    clashService?.onTunTransportChanged = () {
      _tunRuntime.invalidate('statusUnavailable');
      _ref.invalidate(nodeRuntimeReadProvider);
      unawaited(updateTray());
    };
    _tunObservationTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(refreshWindowsTunStatus());
    });
    unawaited(refreshWindowsTunStatus());
  }

  Future<TunStatus?> refreshWindowsTunStatus({bool fresh = false}) async {
    final TunStatus? status;
    if (_windowsStartupEffects != null) {
      final epoch = _tunRuntime.observationEpoch;
      final observed = await _windowsStartupEffects.observe();
      status = observed == null || !_tunRuntime.accept(observed, epoch)
          ? null
          : observed;
    } else {
      if (!Platform.isWindows) return null;
      status = await _tunObserver.refresh(fresh: fresh);
    }
    if (status != null) {
      if (status.observed == TunObservedState.on && status.errorCode == null) {
        _tunRepairAttempts.remove(status.instanceId);
      }
      if (_applyingWindowsConfigDepth == 0 && !_pendingWindowsProxyStop) {
        _recoverRunningProjection(status);
        unawaited(_repairVanishedAdapter(status));
      }
    }
    return status;
  }

  bool _isRepairableTunFailure(
      TunStatus status, WindowsTunStartupEffects effects) {
    if (status.privilege != 'elevated') return false;
    if (status.listenerActive) {
      return status.errorCode == 'interfaceMissing' ||
          status.errorCode == 'interfaceDown';
    }
    if (!effects.proxyRunning && !globalState.isStart) return false;
    if (status.state != 'failed') return false;
    return (status.requestedEnabled && status.errorCode == 'startFailed') ||
        status.errorCode == 'closeFailed';
  }

  bool _canRepairVanishedAdapter(TunStatus status) {
    if (status.observed == TunObservedState.on) return false;
    final effects = _startupEffects();
    if (!_runtimeInitialized ||
        _pendingWindowsProxyStop ||
        _tunRuntime.busy ||
        _tunRuntime.closing ||
        !_tunRuntime.desiredEnabled ||
        _tunRuntime.requestFailure != null ||
        !_isRepairableTunFailure(status, effects)) {
      return false;
    }
    return (_tunRepairAttempts[status.instanceId] ?? 0) < _maxTunRepairAttempts;
  }

  /// The Core still holds an enabled listener whose adapter is missing or down,
  /// or a configuration reload failed while tearing down / recreating the TUN
  /// listener (`startFailed` / `closeFailed`). Rebuild incrementally first and
  /// escalate to a Core restart via the Helper if needed. Never requests
  /// authorization; bounded per Core instance and reset by a healthy
  /// observation. A failure is recorded as a request failure, which also stops
  /// background re-enables until the user retries.
  Future<bool> _repairVanishedAdapter(
    TunStatus status, {
    bool fullConfiguration = false,
    bool applyPendingConfig = false,
  }) {
    if (status.observed == TunObservedState.on && status.errorCode == null) {
      _tunRepairAttempts.remove(status.instanceId);
      return Future.value(false);
    }
    if (!_canRepairVanishedAdapter(status)) {
      return Future.value(false);
    }
    final effects = _startupEffects(syncProviderSettings: fullConfiguration);
    final attempts = _tunRepairAttempts[status.instanceId] ?? 0;
    _tunRepairAttempts[status.instanceId] = attempts + 1;
    effects.log(
        'TUN adapter ${status.errorCode ?? 'missing'}; rebuilding (attempt ${attempts + 1})');
    var repairedAndApplied = false;
    var terminalOutcome = false;
    var finished = false;
    String? escalatedInstanceId;
    int? previousEscalatedAttempts;
    void rollbackAttemptsIfCancelled() {
      if (terminalOutcome) return;
      final currentCount = _tunRepairAttempts[status.instanceId] ?? 0;
      if (currentCount > attempts) {
        if (attempts == 0) {
          _tunRepairAttempts.remove(status.instanceId);
        } else {
          _tunRepairAttempts[status.instanceId] = attempts;
        }
      }
      final extraId = escalatedInstanceId;
      if (extraId != null && extraId != status.instanceId) {
        final baseline = previousEscalatedAttempts ?? 0;
        final currentExtraCount = _tunRepairAttempts[extraId] ?? 0;
        if (currentExtraCount > baseline) {
          if (baseline == 0) {
            _tunRepairAttempts.remove(extraId);
          } else {
            _tunRepairAttempts[extraId] = baseline;
          }
        }
      }
    }

    bool isPendingConfigSatisfied(
      String? appliedProfileId,
      UpdateParams? appliedUpdateParams,
    ) {
      if (!applyPendingConfig) return true;
      if (fullConfiguration) {
        return _windowsStartupEffects != null
            ? _ref.read(currentProfileIdProvider) == appliedProfileId
            : (_hasAppliedWindowsProfile &&
                _lastAppliedWindowsProfileId ==
                    _ref.read(currentProfileIdProvider));
      }
      return _ref.read(updateParamsProvider) == appliedUpdateParams;
    }

    late final Future<bool> repairFuture;
    void finishRepair() {
      if (finished) return;
      finished = true;
      if (identical(_activeTunRepair, repairFuture)) {
        _activeTunRepair = null;
      }
      rollbackAttemptsIfCancelled();
    }

    repairFuture = _tunRuntime.request(true, (intent) async {
      try {
        bool current() => _tunRuntime.isCurrentIntent(intent);
        Future<TunStatus?> observeSettled() async {
          TunStatus? latest;
          final maxReads = _tunSettleDelay > Duration.zero ? 8 : 1;
          for (var read = 0; read < maxReads; read++) {
            latest = await refreshWindowsTunStatus(fresh: true);
            if (!current()) return null;
            if (latest != null && latest.observed != TunObservedState.unknown) {
              break;
            }
            if (read + 1 >= maxReads) break;
            await Future.delayed(_tunSettleDelay);
            if (!current()) return null;
          }
          return latest;
        }

        final currentStatus = _tunRuntime.status;
        if (currentStatus != null) {
          if (currentStatus.observed == TunObservedState.on &&
              currentStatus.errorCode == null) {
            _tunRepairAttempts
              ..remove(currentStatus.instanceId)
              ..remove(status.instanceId);
            repairedAndApplied = !applyPendingConfig;
            return;
          }
          if (!_isRepairableTunFailure(currentStatus, effects)) {
            if (_pendingWindowsProxyStop ||
                (!effects.proxyRunning && !globalState.isStart) ||
                (currentStatus.observed == TunObservedState.off &&
                    currentStatus.errorCode == null)) {
              return;
            }
            rollbackAttemptsIfCancelled();
            terminalOutcome = true;
            throw TunFailure(
              currentStatus.errorCode ??
                  (currentStatus.privilege != 'elevated'
                      ? 'permissionDenied'
                      : null) ??
                  status.errorCode ??
                  'statusUnavailable',
            );
          }
        }
        final activeStatus = currentStatus ?? status;
        final activeAttempts = activeStatus.instanceId == status.instanceId
            ? attempts
            : (_tunRepairAttempts[activeStatus.instanceId] ?? 0);
        if (activeStatus.instanceId != status.instanceId &&
            activeAttempts >= _maxTunRepairAttempts) {
          rollbackAttemptsIfCancelled();
          terminalOutcome = true;
          throw TunFailure(
            activeStatus.errorCode ?? status.errorCode ?? 'startFailed',
          );
        }
        if (activeStatus.instanceId != status.instanceId) {
          escalatedInstanceId = activeStatus.instanceId;
          previousEscalatedAttempts =
              _tunRepairAttempts[activeStatus.instanceId];
          _tunRepairAttempts[activeStatus.instanceId] = activeAttempts + 1;
        }
        final activeErrorCode =
            activeStatus.observed == TunObservedState.on &&
                    activeStatus.errorCode == null
                ? null
                : (activeStatus.errorCode ?? status.errorCode);
        TunStatus? observed;
        TunFailure? stageOneFailure;
        if (activeErrorCode != 'closeFailed') {
          if (_tunSettleDelay > Duration.zero &&
              activeErrorCode != null &&
              activeErrorCode != 'interfaceMissing') {
            await Future.delayed(_tunSettleDelay);
            if (!current()) return;
            if (!applyPendingConfig &&
                activeStatus.listenerActive &&
                activeErrorCode == 'interfaceDown') {
              observed = await refreshWindowsTunStatus(fresh: true);
              if (!current()) return;
              if (observed?.observed == TunObservedState.on) {
                _tunRepairAttempts
                  ..remove(status.instanceId)
                  ..remove(activeStatus.instanceId);
                repairedAndApplied = true;
                terminalOutcome = true;
                return;
              }
            }
          }
          try {
            final appliedProfileId = _ref.read(currentProfileIdProvider);
            final appliedUpdateParams = _ref.read(updateParamsProvider);
            if (fullConfiguration) {
              _hasAppliedWindowsProfile = false;
            }
            await effects.applyConfiguration(
                full: fullConfiguration, isCurrent: current);
            if (!current()) return;
            observed = await observeSettled();
            if (!current()) return;
            if (observed?.observed == TunObservedState.on) {
              _tunRepairAttempts
                ..remove(status.instanceId)
                ..remove(activeStatus.instanceId);
              repairedAndApplied = isPendingConfigSatisfied(
                appliedProfileId,
                appliedUpdateParams,
              );
              terminalOutcome = true;
              return;
            }
          } on TunFailure catch (error) {
            if (error.code == 'componentsMismatch' ||
                error.code == 'permissionDenied' ||
                error.code == 'authorizationRequired') {
              terminalOutcome = true;
              rethrow;
            }
            stageOneFailure = error;
          } catch (_) {
            terminalOutcome = true;
            rethrow;
          }
        }
        final canEscalate = activeErrorCode == 'closeFailed' ||
            ((activeErrorCode != 'interfaceMissing' ||
                    observed?.errorCode != 'interfaceMissing') &&
                activeAttempts + 1 < _maxTunRepairAttempts);
        if (canEscalate) {
          if (activeErrorCode != 'closeFailed') {
            _tunRepairAttempts[status.instanceId] = attempts + 2;
            _tunRepairAttempts[activeStatus.instanceId] = activeAttempts + 2;
          }
          final stageOneReason = stageOneFailure?.code == 'statusUnavailable'
              ? (activeErrorCode ?? stageOneFailure?.code)
              : (stageOneFailure?.code ?? activeErrorCode);
          effects.log(
              'TUN adapter ${observed?.errorCode ?? stageOneReason}; restarting Core');
          stageOneFailure = null;
          try {
            await effects.restartCore();
            // Once the Core process has been replaced, restore its initialization
            // before yielding the queue, even if this repair intent was superseded.
            await effects.initialize(() => true);
            if (!current()) return;
            final appliedProfileId = _ref.read(currentProfileIdProvider);
            final appliedUpdateParams = _ref.read(updateParamsProvider);
            _hasAppliedWindowsProfile = false;
            await effects.applyConfiguration(full: true, isCurrent: current);
            if (!current()) return;
            final started = await effects.startListener();
            if (!current()) return;
            if (!started) throw const TunFailure('startFailed');
            observed = await observeSettled();
            if (!current()) return;
            if (observed?.observed == TunObservedState.on) {
              _tunRepairAttempts
                ..remove(status.instanceId)
                ..remove(activeStatus.instanceId);
              repairedAndApplied = isPendingConfigSatisfied(
                appliedProfileId,
                appliedUpdateParams,
              );
              terminalOutcome = true;
              final instanceId = observed!.instanceId;
              final epoch = _tunRuntime.observationEpoch;
              await effects.reflectRunning(() =>
                  current() &&
                  epoch == _tunRuntime.observationEpoch &&
                  _tunRuntime.isEnabled &&
                  _tunRuntime.status?.instanceId == instanceId);
              return;
            }
            if (_windowsStartupEffects == null) {
              await clashCore.setUiActive(uiActivity.value);
              if (_ref.read(appSettingProvider).openLogs) {
                clashCore.startLog();
              } else {
                clashCore.stopLog();
              }
              await updateGroups();
              await updateProviders();
              initForegroundCache();
            }
          } catch (_) {
            terminalOutcome = true;
            _tunRepairAttempts[status.instanceId] = _maxTunRepairAttempts;
            _tunRepairAttempts[activeStatus.instanceId] = _maxTunRepairAttempts;
            final failedInstanceId =
                observed?.instanceId ?? _tunRuntime.status?.instanceId;
            if (failedInstanceId != null) {
              _tunRepairAttempts[failedInstanceId] = _maxTunRepairAttempts;
            }
            rethrow;
          }
        }
        terminalOutcome = true;
        _tunRepairAttempts[status.instanceId] = _maxTunRepairAttempts;
        _tunRepairAttempts[activeStatus.instanceId] = _maxTunRepairAttempts;
        final failedInstanceId =
            observed?.instanceId ?? _tunRuntime.status?.instanceId;
        if (failedInstanceId != null) {
          _tunRepairAttempts[failedInstanceId] = _maxTunRepairAttempts;
        }
        final fallbackFailure = stageOneFailure?.code == 'statusUnavailable'
            ? (activeErrorCode ?? stageOneFailure?.code)
            : (stageOneFailure?.code ?? activeErrorCode);
        throw TunFailure(
            observed?.errorCode ?? fallbackFailure ?? 'statusUnavailable');
      } finally {
        finishRepair();
      }
    }).whenComplete(() {
      finishRepair();
      if (_windowsStartupEffects == null) unawaited(updateTray());
    }).then((_) => repairedAndApplied);
    _activeTunRepair = repairFuture;
    return repairFuture;
  }

  /// A startup whose final status read failed skips the running projection
  /// (uptime, traffic tasks, tray icon). When a later poll proves the same
  /// Core has TUN on, complete that projection once instead of leaving a
  /// working tunnel displayed as stopped.
  void _recoverRunningProjection(TunStatus status) {
    if (!_runtimeInitialized ||
        _recoveringRunningProjection ||
        _pendingWindowsProxyStop ||
        _tunRuntime.busy ||
        _tunRuntime.closing ||
        status.observed != TunObservedState.on ||
        globalState.startTime != null) {
      return;
    }
    _recoveringRunningProjection = true;
    final effects = _startupEffects();
    effects.log('TUN observed on after startup; restoring running state');
    unawaited(effects
        .reflectRunning(() =>
            !_pendingWindowsProxyStop &&
            !_tunRuntime.busy &&
            !_tunRuntime.closing &&
            _tunRuntime.isEnabled &&
            _tunRuntime.status?.instanceId == status.instanceId)
        .catchError((Object error) {
      effects.log('TUN running-state recovery failed: $error');
    }).whenComplete(() => _recoveringRunningProjection = false));
  }

  void _handlePostConfigTunStatus(TunStatus? status) {
    if (_applyingWindowsConfigDepth != 0 ||
        _pendingWindowsProxyStop ||
        status == null) {
      return;
    }
    _recoverRunningProjection(status);
    if (_canRepairVanishedAdapter(status)) {
      _lastTriggeredTunRepair = _repairVanishedAdapter(status);
    }
  }

  Future<void> _applyWindowsConfig(Future<String> Function(bool enable) apply,
      {bool Function()? isCurrent, bool explicitTunOperation = false}) async {
    _applyingWindowsConfigDepth++;
    try {
      await applyWindowsTunConfiguration(
        componentsMatch: () async =>
            await clashService?.windowsComponentsMatch() ?? false,
        observe: () => refreshWindowsTunStatus(fresh: true),
        desiredEnabled: () => _ref.read(patchClashConfigProvider).tun.enable,
        explicitStop: () =>
            explicitTunOperation &&
            _tunRuntime.operation == TunOperation.disabling,
        explicitOperation: () => explicitTunOperation && _tunRuntime.busy,
        failedRequest: () => _tunRuntime.requestFailure != null,
        reportFailure: _tunRuntime.fail,
        invalidate: _tunRuntime.invalidate,
        apply: apply,
        isCurrent: isCurrent,
      );
    } finally {
      _applyingWindowsConfigDepth--;
    }
    _handlePostConfigTunStatus(_tunRuntime.status);
  }

  Future<void> _updateWindowsConfig({bool Function()? isCurrent,
      String? controllerAddress, bool? controllerEnabled}) async {
    if (_windowsStartupEffects != null) {
      await _startupEffects().applyConfiguration(
        full: false,
        isCurrent: isCurrent ?? () => true,
      );
      return;
    }
    await _applyWindowsConfig(
      (enabled) => clashCore.updateConfig(
        _ref.read(updateParamsProvider).copyWith.tun(enable: enabled),
        controllerAddress: controllerAddress,
        controllerEnabled: controllerEnabled,
      ),
      isCurrent: isCurrent,
      explicitTunOperation: isCurrent != null,
    );
  }

  Future<void> _restoreReplacedWindowsCoreIfNeeded({
    bool Function()? isCurrent,
    bool syncProviderSettings = false,
    bool applyProfileIfMissing = true,
  }) async {
    if (!_needsWindowsCoreRestore || _pendingWindowsProxyStop) return;
    bool current() => isCurrent == null || isCurrent();
    TunFailure? pendingTunFailure;
    if (applyProfileIfMissing && !_hasAppliedWindowsProfile) {
      try {
        if (_windowsStartupEffects != null) {
          await _startupEffects(
            syncProviderSettings: syncProviderSettings,
          ).applyConfiguration(full: true, isCurrent: current);
        } else {
          await _setupClashConfigImpl(
            isCurrent: isCurrent,
            syncProviderSettings: syncProviderSettings,
          );
        }
      } on TunFailure catch (error) {
        pendingTunFailure = error;
      }
    }
    if (!current() || _pendingWindowsProxyStop || !_hasAppliedWindowsProfile) {
      if (pendingTunFailure != null) throw pendingTunFailure;
      return;
    }
    if (globalState.isStart || _windowsCoreRestoreNeedsListener) {
      if (_windowsStartupEffects != null) {
        final started = await _startupEffects(
          syncProviderSettings: syncProviderSettings,
        ).startListener();
        if (!current()) return;
        if (!started) {
          throw pendingTunFailure ?? const TunFailure('startFailed');
        }
      } else {
        final started = await clashCore.startListener();
        if (!current()) return;
        if (!started) {
          throw pendingTunFailure ?? const TunFailure('startFailed');
        }
        _needsWindowsCoreRestore = false;
        _windowsCoreRestoreNeedsListener = false;
        await clashCore.setUiActive(uiActivity.value);
        if (!current()) return;
        if (_ref.read(appSettingProvider).openLogs) {
          clashCore.startLog();
        } else {
          clashCore.stopLog();
        }
        await updateGroups();
        if (!current()) return;
        await updateProviders();
        if (!current()) return;
        initForegroundCache();
      }
    } else {
      _needsWindowsCoreRestore = false;
      _windowsCoreRestoreNeedsListener = false;
    }
    if (pendingTunFailure != null) {
      throw pendingTunFailure;
    }
  }

  Future<void> setTunEnabled(bool enabled) async {
    if (!Platform.isWindows && _windowsStartupEffects == null) {
      _ref.read(patchClashConfigProvider.notifier).updateState(
        (state) => state.copyWith.tun(enable: enabled));
      return;
    }
    _adminAuthorization.clearFailure();
    _tunRepairAttempts.clear();
    if (enabled) {
      await _startWindowsTun();
      if (_windowsStartupEffects == null) await updateTray();
      return;
    }
    final operation = _tunRuntime.request(enabled, (intent) async {
      if (!_tunRuntime.isCurrentIntent(intent)) return;
      if (_needsWindowsCoreRestore && !_pendingWindowsProxyStop) {
        if (_hasAppliedWindowsProfile) {
          try {
            await _updateWindowsConfig(
              isCurrent: () => _tunRuntime.isCurrentIntent(intent),
            );
          } finally {
            if (_needsWindowsCoreRestore &&
                !_pendingWindowsProxyStop &&
                _hasAppliedWindowsProfile &&
                _tunRuntime.isCurrentIntent(intent)) {
              await _restoreReplacedWindowsCoreIfNeeded(
                isCurrent: () => _tunRuntime.isCurrentIntent(intent),
                applyProfileIfMissing: false,
              );
            }
          }
        } else {
          await _restoreReplacedWindowsCoreIfNeeded(
            isCurrent: () => _tunRuntime.isCurrentIntent(intent),
          );
        }
      } else {
        await _updateWindowsConfig(
          isCurrent: () => _tunRuntime.isCurrentIntent(intent),
        );
      }
      final status = await refreshWindowsTunStatus(fresh: true);
      if (!_tunRuntime.isCurrentIntent(intent)) return;
      if (status == null) throw const TunFailure('statusUnavailable');
      if (status.observed != TunObservedState.off) {
        throw const TunFailure('closeFailed');
      }
    }, writeIntent: (value) {
      _ref.read(patchClashConfigProvider.notifier).updateState(
        (state) => state.copyWith.tun(enable: value));
    });
    await operation;
    if (_windowsStartupEffects == null) await updateTray();
  }

  void setupClashConfigDebounce() {
    debouncer.call(FunctionTag.setupClashConfig, () async {
      await setupClashConfig();
    });
  }

  void updateClashConfigDebounce() {
    final synced = _syncingProfileUpdateParams;
    if (synced != null) {
      _syncingProfileUpdateParams = null;
      if (_ref.read(updateParamsProvider) == synced) return;
    }
    debouncer.call(FunctionTag.updateClashConfig, () async {
      await updateClashConfig();
    });
  }

  void updateGroupsDebounce() {
    debouncer.call(FunctionTag.updateGroups, updateGroups);
  }

  void addCheckIpNumDebounce() {
    debouncer.call(FunctionTag.addCheckIpNum, () {
      _ref.read(checkIpNumProvider.notifier).add();
    });
  }

  void applyProfileDebounce({
    bool silence = false,
  }) {
    debouncer.call(FunctionTag.applyProfile, (silence) {
      applyProfile(silence: silence);
    }, args: [silence]);
  }

  void savePreferencesDebounce() {
    debouncer.call(FunctionTag.savePreferences, savePreferences);
  }

  void changeProxyDebounce(String groupName, String proxyName) {
    final targetProfileId = _ref.read(currentProfileIdProvider);
    debouncer.call(FunctionTag.changeProxy, (
      String groupName,
      String proxyName,
      String? expectedProfileId,
    ) async {
      if (_ref.read(currentProfileIdProvider) != expectedProfileId) {
        return;
      }
      final currentSelected =
          _ref.read(currentProfileProvider)?.selectedMap[groupName];
      if (currentSelected != null && currentSelected != proxyName) {
        return;
      }
      final configEpochBeforeChange = globalState.runtimeConfigEpoch;
      await changeProxy(
        groupName: groupName,
        proxyName: proxyName,
      );
      if (_ref.read(currentProfileIdProvider) != expectedProfileId ||
          globalState.runtimeConfigEpoch != configEpochBeforeChange) {
        return;
      }
      await updateGroups();
    }, args: [groupName, proxyName, targetProfileId]);
  }

  /// Initialize foreground notification cache with current profile
  void initForegroundCache() {
    final profile = globalState.config.currentProfile;
    if (profile == null) return;

    final profileName = profile.label ?? profile.id;

    // Decode service name from header
    String serviceName = "";
    final svc = profile.providerHeaders['flclashx-servicename'];
    if (svc != null && svc.isNotEmpty) {
      try {
        final normalized = base64.normalize(svc);
        serviceName = utf8.decode(base64.decode(normalized)).trim();
      } catch (_) {
        serviceName = svc.trim();
      }
    }

    commonPrint.log('[initForegroundCache] profileName="$profileName" serviceName="$serviceName"');
    vpn?.updateProfileInfo(
      profileName: profileName,
      serviceName: serviceName,
    );
  }

  Future<void> restartCore() async {
    if (Platform.isWindows) {
      await _tunRuntime.serialize(() async {
        _tunRuntime.invalidate();
        _tunRuntime.clearCoreRuntimeFailure();
        _tunRepairAttempts.clear();
        globalState.clearRuntimeSetup();
        _windowsCoreRestoreNeedsListener = _windowsCoreRestoreNeedsListener ||
            globalState.isStart ||
            (clashService?.agentProxyRunning ?? false);
        _hasAppliedWindowsProfile = false;
        _needsWindowsCoreRestore = true;
        _applyingWindowsConfigDepth++;
        try {
          await clashService?.reStart();
          await _initCore(ownsWindowsConfig: true);
          if (_ref.read(runTimeProvider.notifier).isStart) await globalState.handleStart();
          _needsWindowsCoreRestore = false;
          _windowsCoreRestoreNeedsListener = false;
        } finally {
          _applyingWindowsConfigDepth--;
          await refreshWindowsTunStatus(fresh: true);
        }
      });
      return;
    }
    commonPrint.log("restart core");
    globalState.clearRuntimeSetup();
    await clashService?.reStart();
    await _initCore();
    if (_ref.read(runTimeProvider.notifier).isStart) {
      await globalState.handleStart();
    }
  }

  // Serializes VPN toggles. A stop issued while a (possibly ~70s) start is in
  // flight must queue behind it, never interleave — otherwise native start/stop
  // ordering is nondeterministic and the tunnel can survive a "disconnected" UI.
  Future<void> _statusOp = Future.value();
  int _statusEpoch = 0;
  // True only while a start/stop op is actually executing _updateStatus (e.g. a
  // ~70s startVpn awaiting VPN consent). A resume-triggered resync must skip
  // while this is set: the tunnel isn't up yet so getRunTime returns null and
  // would clobber the optimistic startTime, tearing down a live tunnel's UI.
  bool _statusOpInFlight = false;

  Future<void> updateStatus(bool isStart) {
    final windowsTun = Platform.isWindows || _windowsStartupEffects != null;
    if (windowsTun) {
      _pendingWindowsProxyStop = !isStart;
      if (!isStart) {
        _tunRuntime.cancelPendingIntent();
      }
    }
    final epoch = ++_statusEpoch;
    final op = _statusOp.then((_) async {
      try {
        // Superseded by a newer toggle (rapid double-tap, start-then-stop): make
        // it a no-op instead of driving a full redundant bring-up/tear-down.
        if (epoch != _statusEpoch) return;
        _statusOpInFlight = true;
        try {
          if (windowsTun) {
            await _tunRuntime.serialize(() async {
              if (epoch != _statusEpoch) return;
              _tunRuntime.invalidate();
              if (isStart) _applyingWindowsConfigDepth++;
              try {
                if (!isStart) {
                  await _startupEffects().stopProxy();
                } else {
                  await _updateStatus(true);
                }
              } finally {
                if (isStart) _applyingWindowsConfigDepth--;
                await refreshWindowsTunStatus(fresh: true);
              }
            });
          } else {
            await _updateStatus(isStart);
          }
        } finally {
          _statusOpInFlight = false;
        }
      } finally {
        if (windowsTun && !isStart && epoch == _statusEpoch) {
          _pendingWindowsProxyStop = false;
        }
      }
    });
    // Keep the chain alive if one toggle throws, but still surface the error to
    // this caller.
    _statusOp = op.catchError((_) {});
    return op;
  }

  Future<void> _updateStatus(bool isStart) async {
    await StatusBarManager.updateIcon(isConnected: isStart);

    if (isStart) {
      if (Platform.isWindows && clashService?.usesAgent == true &&
          clashService?.agentCoreReady != true) {
        await clashService!.recoverCoreForUser();
        _tunRuntime.clearCoreRuntimeFailure();
        _tunRepairAttempts.clear();
        globalState.clearRuntimeSetup();
        _hasAppliedWindowsProfile = false;
        _needsWindowsCoreRestore = true;
        _windowsCoreRestoreNeedsListener = true;
        await _initCore(ownsWindowsConfig: true);
      } else if (Platform.isWindows &&
          _needsWindowsCoreRestore &&
          !_hasAppliedWindowsProfile) {
        await _initCore(ownsWindowsConfig: true);
      }
      // Drop the previous exit-IP immediately so the panel shows "determining" right
      // away instead of flashing the old IP until the debounced check runs.
      detectionState.markChecking();
      // Initialize foreground notification cache before starting
      initForegroundCache();
      final started = await globalState.handleStart([
        updateTraffic,
      ]);
      if (!started) {
        // Bring-up failed (VPN consent denied / establish failed): undo the
        // optimistic "connected" UI instead of leaving a ticking-but-dead state
        // that never self-heals.
        await StatusBarManager.updateIcon(isConnected: false);
        stopRunTimeTimer();
        _ref.read(runTimeProvider.notifier).value = null;
        addCheckIpNumDebounce();
        return;
      }
      _needsWindowsCoreRestore = false;
      _windowsCoreRestoreNeedsListener = false;
      startRunTimeTimer();
      // Android: the long-lived mihomo executor (DNS resolver, fake-ip pool,
      // providers) survives a plain stop→start — only setupConfig/ApplyConfig
      // rebuilds it. After a long session that state degrades, so a toggle
      // reconnects onto a broken executor (tunnel "dies" after hours; off→on then
      // drops instantly). Force a full re-setup on every start so a reconnect
      // rebuilds the executor — the same thing the manual profile-switch workaround
      // does. Desktop keeps the fast path (re-apply only when the profile changed).
      if (Platform.isAndroid) {
        // Direct silent re-setup, NOT applyProfileDebounce(): the debounced path
        // runs applyProfile(silence:false), which skips entirely when the home
        // scaffold isn't mounted (early/headless start) — exactly when recovery
        // is needed, so the reconnect would land on the degraded executor.
        // silence:true bypasses the scaffold gate and the 600ms debounce window.
        unawaited(applyProfile(silence: true));
        return;
      }
      final currentLastModified =
          await _ref.read(currentProfileProvider)?.profileLastModified;
      if (currentLastModified == null || lastProfileModified == null) {
        addCheckIpNumDebounce();
        return;
      }
      if (currentLastModified <= (lastProfileModified ?? 0)) {
        addCheckIpNumDebounce();
        return;
      }
      applyProfileDebounce();
    } else {
      stopRunTimeTimer();
      await globalState.handleStop();
      _windowsCoreRestoreNeedsListener = false;
      if (_hasAppliedWindowsProfile) {
        _needsWindowsCoreRestore = false;
      }
      clashCore.resetTraffic();
      _ref.read(trafficsProvider.notifier).clear();
      _ref.read(totalTrafficProvider.notifier).value = Traffic();
      _ref.read(runTimeProvider.notifier).value = null;
      addCheckIpNumDebounce();
    }
  }

  Timer? _runTimeTimer;

  void startRunTimeTimer() {
    stopRunTimeTimer();
    updateRunTime();
    if (!uiActivity.value) return;
    _runTimeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      updateRunTime();
    });
  }

  void stopRunTimeTimer() {
    _runTimeTimer?.cancel();
    _runTimeTimer = null;
  }

  void updateRunTime() {
    final startTime = globalState.startTime;
    if (startTime != null) {
      final startTimeStamp = startTime.millisecondsSinceEpoch;
      final nowTimeStamp = DateTime.now().millisecondsSinceEpoch;
      _ref.read(runTimeProvider.notifier).value = nowTimeStamp - startTimeStamp;
    } else {
      _ref.read(runTimeProvider.notifier).value = null;
    }
  }

  Future<void> updateTraffic() async {
    final traffic = await clashCore.getTraffic();
    _ref.read(trafficsProvider.notifier).addTraffic(traffic);
    _ref.read(totalTrafficProvider.notifier).value =
        await clashCore.getTotalTraffic();
  }

  Future<void> addProfile(Profile profile) async {
    _ref.read(profilesProvider.notifier).setProfile(profile);
    if (_ref.read(currentProfileIdProvider) != null) return;
    // Setting currentProfileId drives needSetupProvider → clash_manager →
    // handleChangeProfile() → applyProfile(), so an explicit apply here would
    // run setupConfig twice on the first add.
    _ref.read(currentProfileIdProvider.notifier).value = profile.id;
  }

  Future<void> deleteProfile(String id) async {
    _ref.read(profilesProvider.notifier).deleteProfileById(id);
    clearEffect(id);
    if (globalState.config.currentProfileId == id) {
      final profiles = globalState.config.profiles;
      final currentProfileId = _ref.read(currentProfileIdProvider.notifier);
      if (profiles.isNotEmpty) {
        final updateId = profiles.first.id;
        currentProfileId.value = updateId;
      } else {
        currentProfileId.value = null;
        updateStatus(false);
      }
    }
  }

  Future<void> updateProviders() async {
    final configEpoch = globalState.runtimeConfigEpoch;
    final profileId = _ref.read(currentProfileIdProvider);
    final providers = await clashCore.getExternalProviders();
    if (configEpoch != globalState.runtimeConfigEpoch ||
        profileId != _ref.read(currentProfileIdProvider)) {
      return;
    }
    _ref.read(providersProvider.notifier).value = providers;
  }

  Future<void> updateLocalIp() async {
    _ref.read(localIpProvider.notifier).value = null;
    await Future.delayed(commonDuration);
    _ref.read(localIpProvider.notifier).value = await utils.getLocalIpAddress();
  }

  void applySubscriptionSettings(Set<String>? settings) {
    try {
      final currentSettings = _ref.read(appSettingProvider);
      if (currentSettings.overrideProviderSettings) {
        commonPrint.log(
            "Override provider settings enabled - ignoring subscription settings");
        return;
      }

      // If settings is null (header removed), reset to defaults (false)
      final effectiveSettings = settings ?? {};

      _ref
          .read(appSettingProvider.notifier)
          .updateState((state) => state.copyWith(
                minimizeOnExit: effectiveSettings.contains('minimize'),
                autoLaunch: effectiveSettings.contains('autorun'),
                silentLaunch: effectiveSettings.contains('shadowstart'),
                autoRun: effectiveSettings.contains('autostart'),
                autoCheckUpdate: effectiveSettings.contains('autoupdate'),
                openLogs: effectiveSettings.contains('openlogs'),
                closeConnections: effectiveSettings.contains('closeconnections'),
              ));
    } catch (e) {
      // Silently ignore subscription settings errors
    }
  }

  void _applyAllHeaderSettings(Profile profile, {required bool isNewProfile}) {
    final headers = profile.providerHeaders;
    if (headers.isEmpty) return;

    final customBehavior = headers['flclashx-custom'];

    final shouldApply = switch (customBehavior) {
      'add' => isNewProfile,
      'update' => true,
      _ => false,
    };

    if (!shouldApply) return;

    _applyProviderSettings(headers);
    _applyThemeColor(headers);
    _applyCustomViewSettings(profile);
  }

  void _applyProviderSettings(Map<String, String> headers) {
    try {
      final currentSettings = _ref.read(appSettingProvider);
      if (currentSettings.overrideProviderSettings) {
        commonPrint.log(
            "Override provider settings enabled - ignoring provider settings");
        return;
      }

      final settingsHeader = headers['flclashx-settings'];
      if (settingsHeader != null) {
        final settings = settingsHeader
            .split(',')
            .map((s) => s.trim().toLowerCase())
            .where((s) => s.isNotEmpty)
            .toSet();
        applySubscriptionSettings(settings);
      }
    } catch (e) {
      commonPrint.log("Failed to apply provider settings: $e");
    }
  }

  void _applyThemeColor(Map<String, String> headers) {
    try {
      final hexHeader = headers['flclashx-hex'];
      if (hexHeader != null && hexHeader.isNotEmpty) {
        _applyThemeColorFromHex(hexHeader);
      }
    } catch (e) {
      commonPrint.log("Failed to apply theme color: $e");
    }
  }

  void _applyThemeColorFromHex(String hexHeader) {
    try {
      final parts = hexHeader.split(':');
      final hexString = parts[0].trim().replaceAll('#', '');
      final variantName = parts.length > 1 ? parts[1].trim() : null;

      // Check for pureblack flag in any position after color
      bool enablePureBlack = false;
      for (int i = 1; i < parts.length; i++) {
        final part = parts[i].trim().toLowerCase();
        if (part == 'pureblack') {
          enablePureBlack = true;
          break;
        }
      }

      if (hexString.length != 6 && hexString.length != 8) {
        commonPrint.log('Invalid hex color length: $hexString');
        return;
      }

      final colorValue = int.parse(
        hexString.length == 6 ? 'FF$hexString' : hexString,
        radix: 16,
      );

      commonPrint
          .log('Applying theme from flclashx-hex: #${hexString.toUpperCase()}'
              '${variantName != null ? ', variant=$variantName' : ''}'
              '${enablePureBlack ? ', pureBlack=true' : ''}');

      _ref.read(themeSettingProvider.notifier).updateState((state) {
        final updatedColors = [...state.primaryColors];
        if (!updatedColors.contains(colorValue)) {
          updatedColors.add(colorValue);
        }

        DynamicSchemeVariant? newVariant;
        if (variantName != null && variantName.toLowerCase() != 'pureblack') {
          try {
            newVariant = DynamicSchemeVariant.values.firstWhere(
              (v) => v.name.toLowerCase() == variantName.toLowerCase(),
            );
            commonPrint.log('Using scheme variant: ${newVariant.name}');
          } catch (e) {
            commonPrint.log(
                'Unknown variant: $variantName, using current: ${state.schemeVariant.name}');
          }
        }

        commonPrint.log(
            'Theme updated: primaryColor=#${colorValue.toRadixString(16).toUpperCase()}'
            '${enablePureBlack ? ', pureBlack=true' : ''}');

        return state.copyWith(
          primaryColor: colorValue,
          primaryColors: updatedColors,
          schemeVariant: newVariant ?? state.schemeVariant,
          pureBlack: enablePureBlack,
        );
      });

      savePreferencesDebounce();

      commonPrint.log('Theme applied successfully');
    } catch (e) {
      commonPrint.log('Failed to parse hex color from header: $hexHeader - $e');
    }
  }

  Future<void> updateProfile(Profile profile) async {
    _ref.read(profilesProvider.notifier).setProfile(
      profile.copyWith(isUpdating: true),
    );
    try {
    final prefs = await SharedPreferences.getInstance();
    final shouldSend = prefs.getBool('sendDeviceHeaders') ?? true;
    final newProfile = await profile.update(
      shouldSendHeaders: shouldSend,
    );

    final mergedHeaders = Map<String, String>.from(profile.providerHeaders)
      ..addAll(newProfile.providerHeaders);
    for (final key in ['announce', 'support-url']) {
      if (!newProfile.providerHeaders.containsKey(key)) {
        mergedHeaders.remove(key);
      }
    }
    final mergedProfile = newProfile.copyWith(
      providerHeaders: mergedHeaders,
      isUpdating: false,
    );

    // Apply the header-driven app settings (theme/flclashx-hex, flclashx-settings,
    // flclashx-custom view/widgets, etc.) ONLY when the updated profile is the ACTIVE
    // one. Otherwise auto-updating a background profile would push its headers into the
    // global settings and clobber the active profile's ("last updated wins"). Mirrors
    // the active-profile gate on applyProfileDebounce below; the reactive header
    // providers (background / global-mode / server-info) already read the active profile.
    if (mergedHeaders.isNotEmpty &&
        profile.id == _ref.read(currentProfileIdProvider)) {
      _applyAllHeaderSettings(mergedProfile, isNewProfile: false);
    }

    final showHwidLimit = mergedHeaders['x-hwid-max-devices-reached']?.toLowerCase() == 'true';
    final announceText = mergedHeaders['announce'];
    if (showHwidLimit && announceText != null && announceText.isNotEmpty) {
      _showHwidLimitNotice(announceText, mergedHeaders['support-url']);
    }

    if (mergedHeaders['x-hwid-not-supported']?.toLowerCase() == 'true') {
      _showHwidNotSupportedNotice();
    }

    _ref
        .read(profilesProvider.notifier)
        .setProfile(mergedProfile);

    if (profile.id == _ref.read(currentProfileIdProvider)) {
      applyProfileDebounce(silence: true);
    }

    // Check subscription expiration and show notification if needed
    unawaited(SubscriptionNotificationService.checkAndNotify(newProfile)
        .catchError((e) {
      commonPrint.log("Error checking subscription: $e");
    }));
    } catch (e) {
      _ref.read(profilesProvider.notifier).setProfile(
        profile.copyWith(isUpdating: false),
      );
      rethrow;
    }
  }

  void _showHwidNotSupportedNotice() {
    globalState.showMessage(
      title: 'HWID',
      message: TextSpan(text: appLocalizations.hwidNotSupported),
      cancelable: false,
    );
  }

  void _showHwidLimitNotice(String encodedText, String? supportUrl) {
    String? announceText;
    var textToDecode = encodedText;

    if (encodedText.startsWith('base64:')) {
      textToDecode = encodedText.substring(7);
    }

    try {
      final normalized = base64.normalize(textToDecode);
      announceText = utf8.decode(base64.decode(normalized));
    } catch (e) {
      announceText = encodedText;
    }

    if (announceText.isNotEmpty) {
      final actions = <Widget>[];

      if (supportUrl != null && supportUrl.isNotEmpty) {
        actions.add(
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              globalState.openUrl(supportUrl);
            },
            child: Text(appLocalizations.support),
          ),
        );
      }

      actions.add(
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text(appLocalizations.confirm),
        ),
      );

      globalState.showCommonDialog(
        child: CommonDialog(
          title: appLocalizations.tip,
          actions: actions,
          child: Container(
            width: 300,
            constraints: const BoxConstraints(maxHeight: 200),
            child: SingleChildScrollView(
              child: SelectableText(
                announceText,
                style: const TextStyle(
                  overflow: TextOverflow.visible,
                ),
              ),
            ),
          ),
        ),
      );
    }
  }

  void setProfile(Profile profile) {
    _ref.read(profilesProvider.notifier).setProfile(profile);
  }

  void setProfileAndAutoApply(Profile profile) {
    _ref.read(profilesProvider.notifier).setProfile(profile);
    if (profile.id == _ref.read(currentProfileIdProvider)) {
      applyProfileDebounce(silence: true);
    }
  }

  void setProfiles(List<Profile> profiles) {
    _ref.read(profilesProvider.notifier).value = profiles;
  }

  void addLog(Log log) {
    _ref.read(logsProvider).add(log);
  }

  void updateOrAddHotKeyAction(HotKeyAction hotKeyAction) {
    final hotKeyActions = _ref.read(hotKeyActionsProvider);
    final index =
        hotKeyActions.indexWhere((item) => item.action == hotKeyAction.action);
    if (index == -1) {
      _ref.read(hotKeyActionsProvider.notifier).value = List.from(hotKeyActions)
        ..add(hotKeyAction);
    } else {
      _ref.read(hotKeyActionsProvider.notifier).value = List.from(hotKeyActions)
        ..[index] = hotKeyAction;
    }
  }

  List<Group> getCurrentGroups() =>
      _ref.read(currentGroupsStateProvider.select((state) => state.value));

  String getRealTestUrl(String? url) => _ref.read(getRealTestUrlProvider(url));

  int getProxiesColumns() => _ref.read(getProxiesColumnsProvider);

  dynamic addSortNum() => _ref.read(sortNumProvider.notifier).add();

  String? getCurrentGroupName() {
    final currentGroupName = _ref.read(currentProfileProvider.select(
      (state) => state?.currentGroupName,
    ));
    return currentGroupName;
  }

  ProxyCardState getProxyCardState(proxyName) =>
      _ref.read(getProxyCardStateProvider(proxyName));

  String? getSelectedProxyName(groupName) =>
      _ref.read(getSelectedProxyNameProvider(groupName));

  void updateCurrentGroupName(String groupName) {
    final profile = _ref.read(currentProfileProvider);
    if (profile == null || profile.currentGroupName == groupName) {
      return;
    }
    setProfile(
      profile.copyWith(currentGroupName: groupName),
    );
  }

  Future<void> updateClashConfig() async {
    final commonScaffoldState = globalState.homeScaffoldKey.currentState;
    if (commonScaffoldState?.mounted != true) return;
    await commonScaffoldState?.loadingRun(() async {
      await _updateClashConfig();
    });
  }

  /// Explicit toggles share the normal configuration serialization. Commit the
  /// visible state only after Core acknowledges the listener change.
  Future<void> setExternalControllerEnabled(bool enable) async {
    String? address;
    if (enable) {
      var runtimeConfig = globalState.lastRuntimeConfig;
      // Attaching to an existing Agent/Core does not re-apply the profile.
      // Resolve its endpoint without silently replacing it with port 9090.
      final profileId = _ref.read(currentProfileProvider)?.id;
      if (runtimeConfig == null && profileId != null) {
        runtimeConfig = await globalState.handleEvaluate(
          await globalState.getProfileConfig(profileId));
      }
      address = globalState.controllerAddressForEnable(runtimeConfig);
    }
    await _updateClashConfig(controllerAddress: address, controllerEnabled: enable);
    _ref.read(patchClashConfigProvider.notifier).updateState(
          (state) => state.copyWith(
            externalController: enable
                ? ExternalControllerStatus.open
                : ExternalControllerStatus.close,
          ),
        );
    globalState.effectiveExternalController.value =
        enable ? address! : "";
  }

  Future<void> _updateClashConfig({String? controllerAddress, bool? controllerEnabled}) async {
    if (Platform.isWindows) {
      final hasControllerOverride =
          controllerAddress != null || controllerEnabled != null;
      TunStatus? preApplyRepairStatus;
      var repairFailedOrCancelled = false;
      for (var pass = 0; pass < 3; pass++) {
        Future<bool>? preApplyRepair;
        Future<bool>? pendingRepair;
        Future<bool>? postApplyRepair;
        await _tunRuntime.serialize(() async {
          _lastTriggeredTunRepair = null;
          if (repairFailedOrCancelled &&
              _tunRuntime.observed == TunObservedState.on &&
              _tunRuntime.requestFailure == null) {
            repairFailedOrCancelled = false;
          }
          if (!repairFailedOrCancelled &&
              pass < 2 &&
              _activeTunRepair != null) {
            pendingRepair = _activeTunRepair;
            return;
          }
          if (repairFailedOrCancelled &&
              !_pendingWindowsProxyStop &&
              _tunRuntime.desiredEnabled &&
              _tunRuntime.observed != TunObservedState.on &&
              _tunRuntime.requestFailure == null) {
            _tunRuntime.fail(
              _tunRuntime.status?.errorCode ??
                  preApplyRepairStatus?.errorCode ??
                  'startFailed',
            );
          }
          try {
            if (_needsWindowsCoreRestore && !_pendingWindowsProxyStop) {
              if (_hasAppliedWindowsProfile) {
                try {
                  await _updateWindowsConfig(
                    controllerAddress: controllerAddress,
                    controllerEnabled: controllerEnabled,
                  );
                } finally {
                  if (_needsWindowsCoreRestore &&
                      !_pendingWindowsProxyStop &&
                      _hasAppliedWindowsProfile) {
                    await _restoreReplacedWindowsCoreIfNeeded(
                      applyProfileIfMissing: false,
                    );
                  }
                }
              } else {
                await _restoreReplacedWindowsCoreIfNeeded();
                if (hasControllerOverride) {
                  await _updateWindowsConfig(
                    controllerAddress: controllerAddress,
                    controllerEnabled: controllerEnabled,
                  );
                }
              }
            } else {
              await _updateWindowsConfig(
                controllerAddress: controllerAddress,
                controllerEnabled: controllerEnabled,
              );
            }
            postApplyRepair = _lastTriggeredTunRepair ?? _activeTunRepair;
          } on TunFailure catch (error) {
            final status = _tunRuntime.status;
            if (!repairFailedOrCancelled &&
                pass < 2 &&
                error.code == 'statusUnavailable') {
              if (status != null && _canRepairVanishedAdapter(status)) {
                preApplyRepairStatus = status;
                preApplyRepair = _repairVanishedAdapter(
                  status,
                  fullConfiguration: false,
                  applyPendingConfig: true,
                );
                return;
              }
              if (_activeTunRepair != null) {
                pendingRepair = _activeTunRepair;
                return;
              }
            }
            _tunRuntime.fail(error.code);
            if (error.code == 'statusUnavailable' && status != null) {
              unawaited(_repairVanishedAdapter(status));
            }
            rethrow;
          } finally {
            _lastTriggeredTunRepair = null;
          }
        });
        var needsFollowUpApply = false;
        if (preApplyRepair != null) {
          final applied = await preApplyRepair!;
          needsFollowUpApply =
              !_pendingWindowsProxyStop && (!applied || hasControllerOverride);
          repairFailedOrCancelled = !applied &&
              !_pendingWindowsProxyStop &&
              _tunRuntime.observed != TunObservedState.on;
        } else if (pendingRepair != null) {
          final repaired = await pendingRepair!;
          needsFollowUpApply = !_pendingWindowsProxyStop;
          repairFailedOrCancelled = !repaired &&
              !_pendingWindowsProxyStop &&
              _tunRuntime.observed != TunObservedState.on;
        } else if (postApplyRepair != null) {
          final applied = await postApplyRepair!;
          final failedPostRepair = !applied &&
              !_pendingWindowsProxyStop &&
              _tunRuntime.desiredEnabled &&
              (_tunRuntime.requestFailure != null ||
                  _tunRuntime.observed != TunObservedState.on);
          needsFollowUpApply = !_pendingWindowsProxyStop &&
              (hasControllerOverride || failedPostRepair);
          repairFailedOrCancelled = failedPostRepair;
        }
        if (!needsFollowUpApply) break;
      }
      return;
    }
    final updateParams = _ref.read(updateParamsProvider);
    final res = await _requestAdmin(updateParams.tun.enable);
    if (res.isError) {
      if (controllerEnabled != null) throw res.message;
      return;
    }
    final realTunEnable = _ref.read(realTunEnableProvider);
    final message = await clashCore.updateConfig(
      updateParams.copyWith.tun(
        enable: realTunEnable,
      ),
      controllerAddress: controllerAddress, controllerEnabled: controllerEnabled,
    );
    if (message.isNotEmpty) throw message;
  }

  Future<Result<bool>> _requestAdmin(bool enableTun) async {
    final realTunEnable = _ref.read(realTunEnableProvider);
    // Disabling TUN is an explicit user retry boundary.  It also makes a
    // failed enable -> disable -> enable sequence predictable without adding
    // another button or changing Zashboard's config/update path.
    if (!enableTun) {
      _adminAuthorization.clearFailure();
    }
    if (enableTun != realTunEnable && realTunEnable == false) {
      if (_adminAuthorization.isFailureLatched) {
        // Service state can change outside this process (for example, an
        // administrator starts it from Services).  This check is read-only
        // and never invokes UAC; if it is healthy, allow the normal path to
        // observe AuthorizeCode.none and continue.
        try {
          if (await system.checkIsAdmin()) {
            _adminAuthorization.clearFailure();
          } else {
            commonPrint.log(
              '[admin] authorization failure latched; skipping repeated UAC',
            );
            _ref.read(realTunEnableProvider.notifier).value = false;
            return Result.success(false);
          }
        } catch (error) {
          commonPrint.log('[admin] service state check failed: $error');
          _ref.read(realTunEnableProvider.notifier).value = false;
          return Result.success(false);
        }
      }

      late final AuthorizeCode code;
      try {
        code = await _adminAuthorization.request(() async {
          final authorization = await system.authorizeCore();
          if (authorization == AuthorizeCode.success) {
            // Restart is part of the shared operation.  Otherwise concurrent
            // callers would each restart the core after sharing one UAC prompt.
            await restartCore();
          }
          return authorization;
        });
      } catch (error, stackTrace) {
        commonPrint.log('[admin] authorization operation failed: $error');
        commonPrint.log('[admin] authorization stack: $stackTrace');
        _ref.read(realTunEnableProvider.notifier).value = false;
        return Result.success(false);
      }
      commonPrint.log('[admin] authorization result=${code.name}');
      switch (code) {
        case AuthorizeCode.success:
          return Result.error("");
        case AuthorizeCode.none:
          break;
        case AuthorizeCode.error:
          enableTun = false;
          break;
      }
    }
    _ref.read(realTunEnableProvider.notifier).value = enableTun;
    return Result.success(enableTun);
  }

  Future<void> setupClashConfig() async {
    final commonScaffoldState = globalState.homeScaffoldKey.currentState;
    if (commonScaffoldState?.mounted != true) return;
    await commonScaffoldState?.loadingRun(() async {
      await _setupClashConfig();
    });
  }

  Future<void> _setupClashConfig() async {
    if (Platform.isWindows) {
      TunStatus? preApplyRepairStatus;
      var repairFailedOrCancelled = false;
      for (var pass = 0; pass < 3; pass++) {
        Future<bool>? preApplyRepair;
        Future<bool>? pendingRepair;
        Future<bool>? postApplyRepair;
        await _tunRuntime.serialize(() async {
          _lastTriggeredTunRepair = null;
          if (repairFailedOrCancelled &&
              _tunRuntime.observed == TunObservedState.on &&
              _tunRuntime.requestFailure == null) {
            repairFailedOrCancelled = false;
          }
          if (!repairFailedOrCancelled &&
              pass < 2 &&
              _activeTunRepair != null) {
            pendingRepair = _activeTunRepair;
            return;
          }
          if (repairFailedOrCancelled &&
              !_pendingWindowsProxyStop &&
              _tunRuntime.desiredEnabled &&
              _tunRuntime.observed != TunObservedState.on &&
              _tunRuntime.requestFailure == null) {
            _tunRuntime.fail(
              _tunRuntime.status?.errorCode ??
                  preApplyRepairStatus?.errorCode ??
                  'startFailed',
            );
          }
          try {
            try {
              await _setupClashConfigImpl();
            } finally {
              if (_needsWindowsCoreRestore &&
                  !_pendingWindowsProxyStop &&
                  _hasAppliedWindowsProfile) {
                await _restoreReplacedWindowsCoreIfNeeded(
                  applyProfileIfMissing: false,
                );
              }
            }
            postApplyRepair = _lastTriggeredTunRepair ?? _activeTunRepair;
          } on TunFailure catch (error) {
            final status = _tunRuntime.status;
            if (!repairFailedOrCancelled &&
                pass < 2 &&
                error.code == 'statusUnavailable') {
              if (status != null && _canRepairVanishedAdapter(status)) {
                preApplyRepairStatus = status;
                preApplyRepair = _repairVanishedAdapter(
                  status,
                  fullConfiguration: true,
                  applyPendingConfig: true,
                );
                return;
              }
              if (_activeTunRepair != null) {
                pendingRepair = _activeTunRepair;
                return;
              }
            }
            _tunRuntime.fail(error.code);
            if (error.code == 'statusUnavailable' && status != null) {
              unawaited(_repairVanishedAdapter(status));
            }
            rethrow;
          } finally {
            _lastTriggeredTunRepair = null;
          }
        });
        var needsFollowUpApply = false;
        if (preApplyRepair != null) {
          final applied = await preApplyRepair!;
          needsFollowUpApply = !_pendingWindowsProxyStop && !applied;
          repairFailedOrCancelled = !applied &&
              !_pendingWindowsProxyStop &&
              _tunRuntime.observed != TunObservedState.on;
        } else if (pendingRepair != null) {
          final repaired = await pendingRepair!;
          needsFollowUpApply = !_pendingWindowsProxyStop;
          repairFailedOrCancelled = !repaired &&
              !_pendingWindowsProxyStop &&
              _tunRuntime.observed != TunObservedState.on;
        } else if (postApplyRepair != null) {
          final applied = await postApplyRepair!;
          final failedPostRepair = !applied &&
              !_pendingWindowsProxyStop &&
              _tunRuntime.desiredEnabled &&
              (_tunRuntime.requestFailure != null ||
                  _tunRuntime.observed != TunObservedState.on);
          needsFollowUpApply = failedPostRepair;
          repairFailedOrCancelled = failedPostRepair;
        }
        if (!needsFollowUpApply) break;
      }
      return;
    }
    return _setupClashConfigImpl();
  }

  Future<void> _setupClashConfigImpl({
    bool Function()? isCurrent,
    bool syncProviderSettings = true,
  }) async {
    final isWindows = Platform.isWindows;
    var configApplied = false;
    if (isWindows) _applyingWindowsConfigDepth++;
    try {
      for (var profileAttempt = 0; profileAttempt < 4; profileAttempt++) {
        final applyingProfile = _ref.read(currentProfileProvider);
        final applyingProfileId = applyingProfile?.id;
        bool intentIsCurrent() => isCurrent == null || isCurrent();
        bool configurationIsCurrent() =>
            intentIsCurrent() &&
            _ref.read(currentProfileProvider)?.id == applyingProfileId;
        if (!intentIsCurrent()) return;
        await applyingProfile?.checkAndUpdate();
        if (!intentIsCurrent()) return;
        if (!configurationIsCurrent()) {
          if (isCurrent != null) continue;
          return;
        }
        var patchConfig = _ref.read(patchClashConfigProvider);

        // Sync network settings from provider config if not overriding
        final appSetting = _ref.read(appSettingProvider);
        ClashConfig? syncedConfig;
        if (syncProviderSettings && !appSetting.overrideNetworkSettings) {
          syncedConfig =
              await globalState.syncNetworkSettingsFromProvider(patchConfig,
                  profile: applyingProfile);
          if (!intentIsCurrent()) return;
          if (!configurationIsCurrent()) {
            if (isCurrent != null) continue;
            return;
          }
        }

        final beforeProfileSync = _ref.read(updateParamsProvider);
        if (syncedConfig != null) {
          final resolvedSyncedConfig = syncedConfig;
          // Always update provider when using provider settings to ensure UI reflects config.
          // Merge only the synced fields: the snapshot was read before several
          // awaits, and writing it back whole could revert a concurrent TUN
          // switch or other preference change.
          _ref.read(patchClashConfigProvider.notifier).updateState((state) => state
              .copyWith(
                ipv6: resolvedSyncedConfig.ipv6,
                allowLan: resolvedSyncedConfig.allowLan,
                mixedPort: resolvedSyncedConfig.mixedPort,
                findProcessMode: resolvedSyncedConfig.findProcessMode,
              )
              .copyWith
              .tun(stack: resolvedSyncedConfig.tun.stack));
          patchConfig = _ref.read(patchClashConfigProvider);
        }

        final disableGlobalMode =
            applyingProfile?.providerHeaders['flclashx-globalmode']
                    ?.trim()
                    .toLowerCase() ==
                'false';
        if (disableGlobalMode && patchConfig.mode == Mode.global) {
          patchConfig = patchConfig.copyWith(mode: Mode.rule);
          _ref
              .read(patchClashConfigProvider.notifier)
              .updateState((state) => state.copyWith(mode: Mode.rule));
        }

        // flclashx-androidsecure header: on Android, when the current profile
        // declares "androidsecure: true", force mixedPort=0 on the Dart-side
        // ClashConfig so that all downstream providers (coreStateProvider,
        // proxyStateProvider, http.handleFindProxy) observe the disabled inbound
        // and behave consistently with patchRawConfig's forced override. Applied
        // after syncFromProvider so it overrides both user and provider values.
        if (Platform.isAndroid) {
          final secure =
              applyingProfile?.providerHeaders['flclashx-androidsecure']
                      ?.trim()
                      .toLowerCase() ==
                  'true';
          if (secure && patchConfig.mixedPort != 0) {
            patchConfig = patchConfig.copyWith(mixedPort: 0);
            _ref
                .read(patchClashConfigProvider.notifier)
                .updateState((state) => state.copyWith(mixedPort: 0));
          }
        }
        final afterProfileSync = _ref.read(updateParamsProvider);
        if (afterProfileSync != beforeProfileSync) {
          _syncingProfileUpdateParams = afterProfileSync;
        }

        try {
          final applyingModified = await applyingProfile?.profileLastModified;
          if (!intentIsCurrent()) return;
          if (!configurationIsCurrent()) {
            if (isCurrent != null) continue;
            return;
          }

          if (isWindows) {
            var applyEntered = false;
            var setupExecuted = false;
            await _applyWindowsConfig(
              (enabled) async {
                applyEntered = true;
                final currentPatchConfig = _ref.read(patchClashConfigProvider);
                final params = await globalState.getSetupParams(
                  pathConfig: currentPatchConfig.copyWith.tun(enable: enabled),
                  profile: applyingProfile,
                );
                if (!configurationIsCurrent()) return '';
                if (isCurrent != null && params.config.isEmpty) {
                  throw const TunFailure('profileRequired');
                }
                if (_ref.read(patchClashConfigProvider) == currentPatchConfig) {
                  debouncer.cancel(FunctionTag.updateClashConfig);
                }
                setupExecuted = true;
                final message = await clashCore.setupConfig(
                  params,
                  profileId: applyingProfileId,
                );
                if (message.isEmpty) {
                  _hasAppliedWindowsProfile = true;
                  _lastAppliedWindowsProfileId = applyingProfileId;
                }
                return message;
              },
              isCurrent: () => applyEntered
                  ? intentIsCurrent()
                  : configurationIsCurrent(),
              explicitTunOperation: isCurrent != null,
            );
            if (!setupExecuted) {
              if (isCurrent != null && intentIsCurrent()) continue;
              return;
            }
            configApplied = true;
          } else {
            final res = await _requestAdmin(patchConfig.tun.enable);
            if (res.isError || !configurationIsCurrent()) return;
            final currentPatchConfig = _ref.read(patchClashConfigProvider);
            final realTunEnable = _ref.read(realTunEnableProvider);
            final realPatchConfig =
                currentPatchConfig.copyWith.tun(enable: realTunEnable);
            final params = await globalState.getSetupParams(
                pathConfig: realPatchConfig, profile: applyingProfile);
            if (!configurationIsCurrent()) return;
            if (_ref.read(patchClashConfigProvider) == currentPatchConfig) {
              debouncer.cancel(FunctionTag.updateClashConfig);
            }
            final message = await clashCore.setupConfig(params,
                profileId: applyingProfileId);
            if (message.isNotEmpty) {
              // Don't advance lastProfileModified on a failed/timed-out setup: doing so
              // would make the next start's recovery re-apply think the profile is
              // already applied and skip it, leaving a degraded executor in place.
              throw message;
            }
          }
          if (configurationIsCurrent()) lastProfileModified = applyingModified;
          break;
        } finally {
          if (afterProfileSync != beforeProfileSync) {
            unawaited(
              Future(() {
                if (_syncingProfileUpdateParams == afterProfileSync) {
                  _syncingProfileUpdateParams = null;
                }
              }),
            );
          }
        }
      }
    } finally {
      if (isWindows) _applyingWindowsConfigDepth--;
    }
    if (isWindows && configApplied) {
      _handlePostConfigTunStatus(_tunRuntime.status);
    }
  }

  Future _applyProfile({bool silence = false}) async {
    clashCore.requestGc();
    if (silence) {
      // Silent/headless/early-start recovery: bypass the PUBLIC setupClashConfig()
      // scaffold gate + loadingRun (which no-ops when the home scaffold isn't
      // mounted — exactly when recovery is needed — and shows a loading overlay
      // when it is) by re-applying through the private path directly.
      await _setupClashConfig();
    } else {
      await setupClashConfig();
    }
    await updateGroups();
    await updateProviders();
    initForegroundCache();
  }

  Future applyProfile({bool silence = false}) async {
    if (silence) {
      await _applyProfile(silence: true);
    } else {
      final commonScaffoldState = globalState.homeScaffoldKey.currentState;
      if (commonScaffoldState?.mounted != true) return;
      await commonScaffoldState?.loadingRun(() async {
        await _applyProfile();
      });
    }
    addCheckIpNumDebounce();
    // Re-persist cold-start params so tile/widget/Always-on headless restarts reflect
    // the currently active profile, not a stale one from app init.
    unawaited(_persistColdStartParams());
  }

  void handleChangeProfile() {
    debouncer.cancel(FunctionTag.changeProxy);
    debouncer.cancel(FunctionTag.updateGroups);
    _ref.read(delayDataSourceProvider.notifier).value = {};

    final currentProfileId = _ref.read(currentProfileIdProvider);
    if (currentProfileId != null) {
      final profiles = _ref.read(profilesProvider);
      var currentProfile = profiles.firstWhere(
        (p) => p.id == currentProfileId,
        orElse: () => profiles.first,
      );

      if (currentProfile.providerHeaders.isNotEmpty) {
        _applyAllHeaderSettings(currentProfile, isNewProfile: false);
      }
    }

    applyProfile();
    _ref.read(logsProvider.notifier).value = FixedList(maxLength);
    _ref.read(requestsProvider.notifier).value = FixedList(maxLength);
    globalState.cacheHeightMap = {};
    globalState.cacheScrollPosition = {};

  }

  void updateBrightness(Brightness brightness) {
    _ref.read(appBrightnessProvider.notifier).value = brightness;
  }

  Future<void> autoUpdateProfiles() async {
    for (final profile in _ref.read(profilesProvider)) {
      if (!profile.autoUpdate) continue;
      final isNotNeedUpdate = profile.lastUpdateDate
          ?.add(
            profile.autoUpdateDuration,
          )
          .isBeforeNow;
      if (isNotNeedUpdate == false || profile.type == ProfileType.file) {
        continue;
      }
      try {
        await updateProfile(profile);
      } catch (e) {
        commonPrint.log(e.toString());
      }
    }
  }

  /// Updates subscription info for the current profile on app startup.
  /// This ensures the subscription info is always up-to-date when the app launches.
  Future<void> _updateCurrentProfileSubscription() async {
    try {
      final currentProfileId = _ref.read(currentProfileIdProvider);
      commonPrint.log(
          "_updateCurrentProfileSubscription: currentProfileId = $currentProfileId");
      if (currentProfileId == null) {
        commonPrint.log(
            "_updateCurrentProfileSubscription: No current profile selected, skipping");
        return;
      }

      final profiles = _ref.read(profilesProvider);
      commonPrint.log(
          "_updateCurrentProfileSubscription: profiles count = ${profiles.length}");

      final currentProfile =
          profiles.where((p) => p.id == currentProfileId).firstOrNull;
      if (currentProfile == null) {
        commonPrint.log(
            "_updateCurrentProfileSubscription: Profile not found in list, skipping");
        return;
      }

      if (currentProfile.type == ProfileType.file) {
        commonPrint.log(
            "_updateCurrentProfileSubscription: Profile is file type, skipping");
        return;
      }

      commonPrint.log(
          "Updating subscription info for current profile '${currentProfile.label}' on startup...");
      if (currentProfile.autoUpdate) {
        // autoUpdateProfiles() (fired immediately on startup) already refreshes
        // any auto-update profile whose update window has elapsed (or that never
        // updated). Skip those here so we don't fetch+apply the same current
        // profile a second time 1s later; only handle the not-yet-due case it
        // leaves untouched.
        final isDue = currentProfile.lastUpdateDate
                ?.add(currentProfile.autoUpdateDuration)
                .isBeforeNow ??
            true;
        if (isDue) {
          commonPrint.log(
              "_updateCurrentProfileSubscription: already covered by autoUpdateProfiles, skipping");
          return;
        }
        await updateProfile(currentProfile);
        commonPrint.log("Subscription info updated successfully");
      } else {
        commonPrint.log(
            "Auto-update disabled for current profile, skipping startup update");
      }
    } catch (e, stackTrace) {
      commonPrint.log("Failed to update subscription info on startup: $e");
      commonPrint.log("Stack trace: $stackTrace");
    }
  }

  /// When the profile declares an explicit GLOBAL proxy-group, restrict the
  /// core's auto-generated GLOBAL group to exactly those members, in the
  /// declared order. Names not present in the core's GLOBAL are skipped; an
  /// empty/absent override (or one that matches nothing) leaves groups as-is.
  List<Group> _applyGlobalGroupOverride(List<Group> groups) {
    final order = globalState.globalGroupOrder.value;
    if (order.isEmpty) return groups;
    final index = groups.indexWhere((g) => g.name == GroupName.GLOBAL.name);
    if (index == -1) return groups;
    final global = groups[index];
    final byName = {for (final p in global.all) p.name: p};
    final groupByName = {for (final g in groups) g.name: g};
    final curated = <Proxy>[];
    for (final name in order) {
      final existing = byName[name];
      if (existing != null) {
        curated.add(existing);
        continue;
      }
      // Name declared in GLOBAL but missing from the core's GLOBAL.all (e.g. a
      // referenced group). Synthesize it from the full group list so the
      // curated list stays complete; selection/now resolves through groups.
      final group = groupByName[name];
      if (group != null) {
        curated.add(Proxy(name: group.name, type: group.type.value));
      }
    }
    if (curated.isEmpty) return groups;
    final result = List<Group>.from(groups);
    result[index] = global.copyWith(all: curated);
    return result;
  }

  Future<void> updateGroups() async {
    final configEpoch = globalState.runtimeConfigEpoch;
    final profileId = _ref.read(currentProfileIdProvider);
    try {
      final newGroups = await retry(
        task: () async => clashCore.getProxiesGroups(),
        retryIf: (res) =>
            res.isEmpty &&
            configEpoch == globalState.runtimeConfigEpoch &&
            profileId == _ref.read(currentProfileIdProvider),
      );
      if (configEpoch != globalState.runtimeConfigEpoch ||
          profileId != _ref.read(currentProfileIdProvider)) {
        return;
      }

      if (newGroups.isNotEmpty) {
        _ref.read(groupsProvider.notifier).value =
            _applyGlobalGroupOverride(newGroups);
        _ref.read(versionProvider.notifier).value =
            _ref.read(versionProvider) + 1;
      } else {
        commonPrint
            .log("updateGroups: received empty groups, keeping old state");
      }
    } catch (e) {
      commonPrint.log("updateGroups error: $e, keeping old groups");
    }
  }

  Future<void> updateProfiles() async {
    for (final profile in _ref.read(profilesProvider)) {
      if (profile.type == ProfileType.file) {
        continue;
      }
      await updateProfile(profile);
    }
  }

  Future<void> savePreferences() async {
    commonPrint.log("save preferences");
    await preferences.saveConfig(globalState.config);
    await flushNodeHealth();
  }

  Future<void> flushNodeHealth() async {
    while (_nodeHealthWrites.isNotEmpty) {
      await Future.wait(_nodeHealthWrites.toList());
    }
    if (_ref.read(nodeOverviewEnabledProvider) &&
        _ref.exists(nodeHealthRecorderProvider)) {
      try {
        await _ref.read(nodeHealthRecorderProvider).flush();
      } catch (_) {
        commonPrint.log('node.health reason=flushFailed');
      }
    }
  }

  Future<void> changeProxy({
    required String groupName,
    required String proxyName,
  }) async {
    await clashCore.changeProxy(
      ChangeProxyParams(
        groupName: groupName,
        proxyName: proxyName,
      ),
    );
    if (_ref.read(appSettingProvider).closeConnections) {
      clashCore.closeConnections();
    }
    addCheckIpNumDebounce();
    // Android: re-persist cold-start params so a later headless restart (tile/
    // Always-on/sticky) brings the tunnel up with the NEWLY selected node, not
    // the one captured at app init. Without this, "picked a server, phone sat
    // idle, VPN auto-reconnected to the old one". changeProxy is debounced, so
    // this runs at most once per debounce window.
    if (Platform.isAndroid && globalState.isStart) {
      unawaited(_persistColdStartParams());
    }
  }

  Future<void> handleBackOrExit() async {
    if (_ref.read(backBlockProvider)) {
      return;
    }
    // Android: the back gesture must never shut the core down while the tunnel
    // is up — the FGS + TUN are designed to outlive the UI, and handleExit()
    // would kill the executor under a live VPN icon (blackholed traffic).
    // Background the activity instead, regardless of minimizeOnExit.
    if (Platform.isAndroid && globalState.isStart) {
      await system.back();
      return;
    }
    if (_ref.read(appSettingProvider).minimizeOnExit) {
      if (system.isDesktop) {
        savePreferencesDebounce();
      }
      await system.back();
    } else {
      await handleCloseUi();
    }
  }

  /// Closes only the desktop UI. The per-user Agent remains the Core owner, so
  /// the virtual network card, system proxy and application policies continue
  /// without retaining a Flutter engine in memory.
  Future<void> handleCloseUi() async {
    if (!system.isDesktop || clashService?.usesAgent != true) {
      await handleExit();
      return;
    }
    await _quiesceWindows(() async {
      try {
        await savePreferences();
        await clashService?.detach();
      } finally {
        system.exit();
      }
    });
  }

  void backBlock() {
    _ref.read(backBlockProvider.notifier).value = true;
  }

  void unBackBlock() {
    _ref.read(backBlockProvider.notifier).value = false;
  }

  Future<void> _quiesceWindows(Future<void> Function() action) async {
    if (!Platform.isWindows) { await action(); return; }
    _tunObservationTimer?.cancel();
    ++_statusEpoch;
    await _tunRuntime.quiesce(action);
  }

  Future<void> handleExit() => _quiesceWindows(_handleExit);

  Future<void> _handleExit() async {
    _tunObservationTimer?.cancel();
    // Bound the cleanup instead of pre-arming a 300ms hard-exit timer. On macOS the
    // DNS/proxy teardown is several slow networksetup/route subprocesses that easily
    // overrun 300ms, so the old timer fired mid-cleanup and exit(0) skipped the DNS
    // restore / proxy stop / core shutdown — leaking 1.1.1.1, leaving a dead system
    // proxy, and orphaning the root core. Mirror handleRestart: run cleanup under a
    // generous deadline, each step isolated, then always exit.
    try {
      await Future.any([
        Future(() async {
          try {
            await savePreferences();
          } catch (_) {}
          try {
            await system.setMacOSDns(true);
          } catch (_) {}
          try {
            await proxy?.stopProxy();
          } catch (_) {}
          try {
            await clashCore.shutdown();
          } catch (_) {}
          try {
            await clashService?.destroy();
          } catch (_) {}
        }),
        Future.delayed(const Duration(seconds: 8)),
      ]);
    } finally {
      system.exit();
    }
  }

  Future<void> handleRestart() => _quiesceWindows(_handleRestart);

  Future<void> _handleRestart() async {
    await cancelDelayTests(reason: 'sessionClosed');
    commonPrint.log("Starting application restart...");

    if (clashService?.usesAgent == true) {
      // A UI restart is an Agent detach/reattach, not a proxy restart. This is
      // the same path used by reopening after Close UI and does not interrupt
      // existing connections.
      try {
        await savePreferences();
        await clashService?.detach();
      } catch (_) {}
    } else {
      // Compatibility path for source/debug bundles without FlClashAgent.
      await Future.any([
        Future(() async {
          try {
            await proxy?.stopProxy();
          } catch (_) {}
          try {
            await clashCore.shutdown();
          } catch (_) {}
          try {
            await clashService?.destroy();
          } catch (_) {}
        }),
        Future.delayed(const Duration(seconds: 3)),
      ]);
    }

    if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
      final executablePath = Platform.resolvedExecutable;
      commonPrint.log("Launching new process: $executablePath");

      try {
        await Process.start(
          executablePath,
          [],
          mode: ProcessStartMode.detached,
        );
        commonPrint.log("New process started, exiting old process...");
      } catch (e) {
        commonPrint.log("Failed to start new process: $e");
        // The Windows UI has already detached and revoked pending operations.
        // End this instance; reusing it would silently ignore future requests.
        if (Platform.isWindows) system.exit();
        return;
      }
    }

    system.exit();
  }

  Future<void> handleClear() => _quiesceWindows(_handleClear);

  Future<void> _handleClear() async {
    try {
      // Stop proxy/VPN first
      await globalState.handleStop();
      commonPrint.log("stopped proxy/VPN");

      // Stop core
      await clashCore.shutdown();
      commonPrint.log("shutdown core");

      // Wait a bit for all file handles to close
      await Future.delayed(const Duration(milliseconds: 500));

      // Clear preferences
      await preferences.clearPreferences();
      commonPrint.log("cleared preferences");

      // Get paths
      final homePath = await appPath.homeDirPath;
      final profilesPath = await appPath.profilesPath;

      // Delete profiles directory
      final profilesDir = Directory(profilesPath);
      if (await profilesDir.exists()) {
        try {
          await profilesDir.delete(recursive: true);
          commonPrint.log("deleted profiles directory");
        } catch (e) {
          commonPrint.log("failed to delete profiles directory: $e");
        }
      }

      // Delete cache and temporary files
      final filesToDelete = [
        'cache.db',
        'libCachedImageData.json',
        'FlClashX.lock',
      ];

      for (final fileName in filesToDelete) {
        final file = File(join(homePath, fileName));
        if (await file.exists()) {
          try {
            await file.delete();
            commonPrint.log("deleted $fileName");
          } catch (e) {
            commonPrint.log("failed to delete $fileName: $e");
          }
        }
      }

      // Reset config
      globalState.config = const Config(
        themeProps: defaultThemeProps,
      );

      commonPrint.log("handleClear completed");

      // Close file logger to release file handles (MUST be last step)
      await fileLogger.dispose();
      if (Platform.isWindows) system.exit();
    } catch (e) {
      commonPrint.log("handleClear error: $e");
      await fileLogger.dispose();
      rethrow;
    }
  }

  Future<void> autoCheckUpdate() async {
    if (!_ref.read(appSettingProvider).autoCheckUpdate) return;
    final res = await request.checkForUpdate();
    checkUpdateResultHandle(data: res);
  }

  Future<void> checkUpdateResultHandle({
    Map<String, dynamic>? data,
    bool handleError = false,
  }) async {
    if (globalState.isPre) {
      return;
    }
    if (data != null) {
      final tagName = data['tag_name'];
      final body = data['body'];
      final submits = utils.parseReleaseBody(body);
      final textTheme = context.textTheme;
      final res = await globalState.showMessage(
        title: appLocalizations.discoverNewVersion,
        message: TextSpan(
          text: "$tagName \n",
          style: textTheme.headlineSmall,
          children: [
            TextSpan(
              text: "\n",
              style: textTheme.bodyMedium,
            ),
            for (final submit in submits)
              TextSpan(
                text: "- $submit \n",
                style: textTheme.bodyMedium,
              ),
          ],
        ),
        confirmText: appLocalizations.goDownload,
      );
      if (res != true) {
        return;
      }
      unawaited(launchUrl(
        Uri.parse("https://github.com/$repository/releases/latest"),
      ));
    } else if (handleError) {
      globalState.showMessage(
        title: appLocalizations.checkUpdate,
        message: TextSpan(
          text: appLocalizations.checkUpdateError,
        ),
      );
    }
  }

  Future<void> _handlePreference() async {
    if (await preferences.isInit) {
      return;
    }
    final res = await globalState.showMessage(
      title: appLocalizations.tip,
      message: TextSpan(text: appLocalizations.cacheCorrupt),
    );
    if (res == true) {
      final file = File(await appPath.sharedPreferencesPath);
      final isExists = await file.exists();
      if (isExists) {
        await file.delete();
      }
    }
    await handleExit();
  }

  Future<void> _initCore({bool ownsWindowsConfig = false}) async {
    _ref.invalidate(nodeRuntimeReadProvider);
    if (Platform.isWindows && clashService?.usesAgent == true &&
        clashService?.agentCoreReady != true) return;
    final wasInitialized = await clashCore.isInit;
    if (!wasInitialized) {
      await clashCore.init();
      await clashCore.setState(
        globalState.getCoreState(),
      );
    }
    await clashCore.setUiActive(uiActivity.value);
    // Re-assert the log subscription on every attach. startLog() lives inside
    // clashCore.init(), which is skipped above when the core is already
    // initialised — e.g. after a headless tile/always-on cold-start the core is
    // isInit==true with no log subscriber, so Logs would stay empty until a full
    // process kill. startLog/stopLog are idempotent (resubscribe), so re-issuing
    // on every launch/attach is safe and fixes empty Logs without re-init.
    if (globalState.config.appSetting.openLogs) {
      clashCore.startLog();
    } else {
      clashCore.stopLog();
    }
    if (wasInitialized && clashService?.usesAgent == true) {
      // Reopening the UI attaches to the already-configured Core. Re-running
      // setupConfig here rebuilds listeners/providers and can interrupt live
      // flows, defeating R-121. Refresh only the UI projections; configuration
      // remains owned by the Agent/Core journal until the user changes it.
      await updateGroups();
      await updateProviders();
      initForegroundCache();
    } else if (Platform.isWindows && ownsWindowsConfig) {
      // Restart already owns the Windows configuration queue. Re-entering
      // applyProfile would wait on ourselves and deadlock recovery.
      await _setupClashConfigImpl();
      await updateGroups();
      await updateProviders();
      initForegroundCache();
    } else {
      await applyProfile();
    }
  }

  Future<void> _persistColdStartParams() async {
    if (clashLib == null) return;
    try {
      final clashConfig = globalState.config.patchClashConfig.copyWith.tun(
        enable: false,
      );
      final setupParams = await globalState.getSetupParams(
        pathConfig: clashConfig,
        profile: globalState.config.currentProfile,
      );
      unawaited(clashLib?.saveParamsForColdStart(
        initParams: InitParams(
          homeDir: await appPath.homeDirPath,
          version: await system.version,
        ),
        setupParams: setupParams,
        state: globalState.getCoreState(),
      ));
    } catch (e) {
      commonPrint.log("persistColdStartParams: $e");
    }
  }

  Future<void> initializeRuntime() =>
      _runtimeInitialization ??= _initializeRuntime()
          .whenComplete(() => _runtimeInitialized = true);

  Future<void> _startWindowsTun() => startWindowsTunOnLaunch(
    runtime: _tunRuntime,
    effects: _startupEffects(),
    writeIntent: (value) => _ref.read(patchClashConfigProvider.notifier)
      .updateState((state) => state.copyWith.tun(enable: value)),
    settleDelay: _tunSettleDelay,
  );

  Future<void> _initializeRuntime() async {
    if (Platform.isWindows || _windowsStartupEffects != null) {
      final effects = _startupEffects();
      // Fresh installs default to tun.enable=true. A saved preference (including
      // an existing user's explicit off) is respected rather than overridden.
      if (!_ref.read(patchClashConfigProvider).tun.enable) {
        effects.log('startup: saved TUN preference is off; starting proxy without TUN');
        try {
          await effects.startProxyWithoutTun();
        } catch (e) {
          effects.log('startup: proxy start failed: $e');
        }
        return;
      }
      effects.log('startup: saved TUN preference is on; starting proxy and TUN');
      await _startWindowsTun();
      final failure = _tunRuntime.failure;
      effects.log('startup: TUN observed=${_tunRuntime.observed.name}'
          '${failure == null ? '' : ', failure=$failure (TUN not enabled; retry from the TUN switch)'}');
      return;
    }
    try {
      await _initCore();
    } catch (e) {
      commonPrint.log('initCore failed (will retry on profile change): $e');
    }
    await _initStatus();
  }

  Future<void> init() async {
    startTunObservation();
    FlutterError.onError = (details) {
      commonPrint.log(details.stack.toString());
    };
    updateTray(true);
    // Desktop only (clashService is null on Android): on an unexpected core-process
    // death, respawn it AND re-init/re-apply (and re-start the tunnel if it was up).
    clashService?.onCoreCrash = (_) => restartCore();
    // Show (or hide) the window before runtime startup. On Windows startup may
    // wait for a UAC reply or a backend handover; the native window is created
    // hidden, so awaiting first left the user with no app window meanwhile.
    if (!Platform.isMacOS) {
      if (!_ref.read(appSettingProvider).silentLaunch) {
        window?.show();
      } else {
        window?.hide();
      }
    }
    await initializeRuntime();
    autoLaunch?.updateStatus(
      _ref.read(appSettingProvider).autoLaunch,
    );
    // Delay subscription update to ensure network is ready after app initialization
    Future.delayed(
        const Duration(seconds: 1), _updateCurrentProfileSubscription);
    autoUpdateProfiles();
    autoCheckUpdate();
    await _handlePreference();
    await _handlerDisclaimer();
    _ref.read(initProvider.notifier).value = true;
  }

  Future<void> _initStatus() async {
    if (Platform.isAndroid) {
      final known = await globalState.updateStartTime();
      if (!known) {
        // Probe failed → tunnel state unknown. Don't drive updateStatus(false):
        // it sends a stop intent that kills a possibly-live VPN service (the
        // classic "opened the app and VPN dropped" on slow-binding OEMs).
        // Leave native state untouched; the resumed-resync picks up the truth.
        addCheckIpNumDebounce();
        return;
      }
    }
    final agentStatus = clashService?.usesAgent == true
        ? clashService?.agentProxyRunning
        : null;
    if (Platform.isWindows && clashService?.usesAgent == true) {
      if (agentStatus == null) {
        _tunRuntime.invalidate('statusUnavailable');
        return;
      }
      // Opening a UI attaches to the Agent-owned runtime. Restore local
      // projections without sending start/stop and disturbing its listeners.
      await StatusBarManager.updateIcon(isConnected: agentStatus);
      if (agentStatus) {
        globalState.startTime ??= DateTime.now();
        globalState.startUpdateTasks();
        startRunTimeTimer();
      } else {
        globalState.startTime = null;
        globalState.stopUpdateTasks();
        stopRunTimeTimer();
        _ref.read(runTimeProvider.notifier).value = null;
      }
      await refreshWindowsTunStatus(fresh: true);
      return;
    }
    final status = agentStatus ??
        (globalState.isStart == true
            ? true
            : _ref.read(appSettingProvider).autoRun);

    await updateStatus(status);
    if (!status) {
      addCheckIpNumDebounce();
    }
  }

  /// Aligns UI run-state with the native truth after a resume. STOP/START can
  /// be missed while the process is frozen or killed (fire-and-forget tile
  /// channel, lost broadcasts), leaving a ticking "connected" UI over a dead
  /// tunnel — or a "disconnected" UI over a live one. Never sends start/stop
  /// IPC; only local state is touched.
  int _resumeProbeEpoch = 0;

  Future<void> syncVpnStateOnResume() async {
    // A start/stop toggle is mid-flight (e.g. a ~70s startVpn still awaiting VPN
    // consent): its optimistic startTime isn't reflected by getRunTime yet, so
    // re-probing now would null it and tear down a live tunnel's UI. The
    // in-flight op sets the correct run-state on completion, so just skip.
    if (_statusOpInFlight || !uiActivity.value) return;
    final statusEpoch = _statusEpoch;
    final activityEpoch = uiActivity.epoch;
    final probeEpoch = ++_resumeProbeEpoch;
    bool isCurrent() => !_statusOpInFlight &&
        statusEpoch == _statusEpoch &&
        activityEpoch == uiActivity.epoch &&
        probeEpoch == _resumeProbeEpoch &&
        uiActivity.value;
    final result = await globalState.probeStartTime(readRunTime: _nativeRunTimeProbe);
    if (!result.known || !isCurrent()) return;
    globalState.startTime = result.startTime;
    final running = globalState.isStart;
    await StatusBarManager.updateIcon(isConnected: running);
    if (!isCurrent()) return;
    if (running) {
      globalState.startUpdateTasks();
      startRunTimeTimer();
    } else {
      stopRunTimeTimer();
      globalState.stopUpdateTasks();
      _ref.read(runTimeProvider.notifier).value = null;
      _ref.read(trafficsProvider.notifier).clear();
      _ref.read(totalTrafficProvider.notifier).value = Traffic();
      addCheckIpNumDebounce();
    }
  }

  Future<NodeHealthTarget?> captureNodeHealthTarget(Delay delay,
      {bool refreshRuntime = false}) async {
    if (!_ref.read(nodeOverviewEnabledProvider)) return null;
    final profileId = _ref.read(currentProfileIdProvider);
    if (profileId == null) return null;
    final profile = _ref.read(profilesProvider).getProfile(profileId);
    if (profile == null || profile.isUpdating) return null;
    try {
      // One fresh, shared read per explicit batch. This does not wait before
      // starting the measurement and never applies configuration to gain trust.
      final read = _ref.read(nodeRuntimeReadProvider);
      if (refreshRuntime) {
        read.refresh();
        _ref.invalidate(verifiedNodeRuntimeProvider);
      }
      final catalog = await read.result;
      if (!read.isCurrent || catalog == null || catalog.profileId != profileId ||
          _ref.read(currentProfileIdProvider) != profileId) return null;
      return _ref.read(nodeHealthRecorderProvider).captureCatalog(
          catalog: catalog, name: delay.name, url: delay.url);
    } catch (_) {
      commonPrint.log('node.health reason=runtimeUnavailable');
      return null;
    }
  }

  void setDelay(Delay delay, {
    String? reason,
    FutureOr<NodeHealthTarget?>? healthTarget,
    bool capturedHealthTarget = false,
  }) {
    _ref.read(delayDataSourceProvider.notifier).setDelay(delay);
    if (!_ref.read(nodeOverviewEnabledProvider) ||
        delay.value == null || delay.value == 0) return;
    if (delay.value! < 0 && reason != 'testFailed' &&
        reason != 'deadlineExceeded') return;
    // Broadcast DelayMessage has no configuration generation. A late message
    // after setup cannot safely become cross-profile history; only explicit
    // requests carry the snapshot captured when they started.
    if (capturedHealthTarget && healthTarget != null) {
      final arrivedAt = DateTime.now();
      final write = () async {
        final target = await healthTarget;
        if (target != null) {
          await _ref.read(nodeHealthRecorderProvider)
              .record(target, delay.value!, reason: reason, testedAt: arrivedAt);
        }
      }().catchError((Object _) => commonPrint.log('node.health reason=recordFailed'));
      _nodeHealthWrites.add(write);
      unawaited(write.whenComplete(() => _nodeHealthWrites.remove(write)));
    }
  }

  void toPage(PageLabel pageLabel) {
    _ref.read(currentPageLabelProvider.notifier).value = pageLabel;
  }

  void toProfiles() {
    toPage(PageLabel.profiles);
  }

  void initLink() {
    linkManager.initAppLinksListen(
      (url) async {
        final res = await globalState.showMessage(
          title: "${appLocalizations.add} ${appLocalizations.profile}",
          message: TextSpan(
            children: [
              TextSpan(text: appLocalizations.doYouWantToPass),
              TextSpan(
                text: " $url",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  decoration: TextDecoration.underline,
                  decorationColor: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        );

        if (res != true) {
          return;
        }
        addProfileFormURL(url);
      },
    );
  }

  Future<bool> showDisclaimer() async =>
      await globalState.showCommonDialog<bool>(
        dismissible: false,
        child: CommonDialog(
          title: appLocalizations.disclaimer,
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop<bool>(false);
              },
              child: Text(appLocalizations.exit),
            ),
            TextButton(
              onPressed: () {
                _ref.read(appSettingProvider.notifier).updateState(
                      (state) => state.copyWith(disclaimerAccepted: true),
                    );
                Navigator.of(context).pop<bool>(true);
              },
              child: Text(appLocalizations.agree),
            )
          ],
          child: SelectableText(
            appLocalizations.disclaimerDesc,
          ),
        ),
      ) ??
      false;

  Future<void> _handlerDisclaimer() async {
    if (_ref.read(appSettingProvider).disclaimerAccepted) {
      return;
    }
    final isDisclaimerAccepted = await showDisclaimer();
    if (!isDisclaimerAccepted) {
      await handleExit();
    }
    return;
  }

  Future<void> addProfileFormURL(String url) async {
    if (globalState.navigatorKey.currentState?.canPop() ?? false) {
      globalState.navigatorKey.currentState?.popUntil((route) => route.isFirst);
    }
    final commonScaffoldState = globalState.homeScaffoldKey.currentState;
    if (commonScaffoldState?.mounted != true) return;

    try {
      final profile = await commonScaffoldState?.loadingRun<Profile>(
        () async {
          final prefs = await SharedPreferences.getInstance();
          final shouldSend = prefs.getBool('sendDeviceHeaders') ?? true;
          return Profile.normal(url: url).update(shouldSendHeaders: shouldSend);
        },
        title: "${appLocalizations.add}${appLocalizations.profile}",
      );

      if (profile != null) {
        _applyAllHeaderSettings(profile, isNewProfile: true);

        final headers = profile.providerHeaders;
        final showHwidLimit = headers['x-hwid-max-devices-reached']?.toLowerCase() == 'true';
        final announceText = headers['announce'];
        if (showHwidLimit && announceText != null && announceText.isNotEmpty) {
          _showHwidLimitNotice(announceText, headers['support-url']);
        }
        if (headers['x-hwid-not-supported']?.toLowerCase() == 'true') {
          _showHwidNotSupportedNotice();
        }

        await addProfile(profile);
      }
    } catch (err) {
      commonPrint.log('Add Profile Failed: $err');
      unawaited(
          globalState.showMessage(message: TextSpan(text: err.toString())));
    }
  }

  /// Download, validate and add a profile from [url] WITHOUT any navigation or
  /// global loading overlay. Used by the TV phone-sync receive dialog so it can
  /// keep its own UI alive and report the real apply result back to the phone.
  /// Throws on failure (network / invalid config) so the caller can surface it.
  Future<void> addProfileFromUrlForSync(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final shouldSend = prefs.getBool('sendDeviceHeaders') ?? true;
    final profile =
        await Profile.normal(url: url).update(shouldSendHeaders: shouldSend);
    _applyAllHeaderSettings(profile, isNewProfile: true);
    final headers = profile.providerHeaders;
    final showHwidLimit =
        headers['x-hwid-max-devices-reached']?.toLowerCase() == 'true';
    final announceText = headers['announce'];
    if (showHwidLimit && announceText != null && announceText.isNotEmpty) {
      _showHwidLimitNotice(announceText, headers['support-url']);
    }
    if (headers['x-hwid-not-supported']?.toLowerCase() == 'true') {
      _showHwidNotSupportedNotice();
    }
    await addProfile(profile);
  }

  Future<Null> addProfileFormFile() async {
    final platformFile = await globalState.safeRun(picker.pickerFile);
    final bytes = platformFile?.bytes;
    if (bytes == null) {
      return null;
    }
    if (!context.mounted) return;
    globalState.navigatorKey.currentState?.popUntil((route) => route.isFirst);
    toPage(PageLabel.dashboard);
    final commonScaffoldState = globalState.homeScaffoldKey.currentState;
    if (commonScaffoldState?.mounted != true) return;
    final profile = await commonScaffoldState?.loadingRun<Profile?>(
      () async {
        await Future.delayed(const Duration(milliseconds: 300));
        return Profile.normal(label: platformFile?.name).saveFile(bytes);
      },
      title: "${appLocalizations.add}${appLocalizations.profile}",
    );
    if (profile != null) {
      await addProfile(profile);
    }
  }

  Future<void> addProfileFormQrCode() async {
    final url = await globalState.safeRun(picker.pickerConfigQRCode);
    if (url == null) return;
    addProfileFormURL(url);
  }

  void updateViewSize(Size size) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ref.read(viewSizeProvider.notifier).value = size;
    });
  }

  void setProvider(ExternalProvider? provider) {
    _ref.read(providersProvider.notifier).setProvider(provider);
  }

  List<Proxy> _sortOfName(List<Proxy> proxies) => List.of(proxies)
    ..sort(
      (a, b) => utils.sortByChar(
        utils.getPinyin(a.name),
        utils.getPinyin(b.name),
      ),
    );

  List<Proxy> _sortOfDelay({
    required List<Proxy> proxies,
    String? testUrl,
  }) =>
      List.of(proxies)
        ..sort(
          (a, b) {
            final aDelay = _ref.read(getDelayProvider(
              proxyName: a.name,
              testUrl: testUrl,
            ));
            final bDelay = _ref.read(
              getDelayProvider(
                proxyName: b.name,
                testUrl: testUrl,
              ),
            );
            // null (untested) and -1 (failed) are equivalent "no delay"
            // sentinels: map both to the same rank so the comparator stays
            // antisymmetric (compare(a,b) == -compare(b,a)) and they sort to
            // the end together.
            if (aDelay == null || aDelay == -1) {
              return (bDelay == null || bDelay == -1) ? 0 : 1;
            }
            if (bDelay == null || bDelay == -1) {
              return -1;
            }
            return aDelay.compareTo(bDelay);
          },
        );

  List<Proxy> getSortProxies(List<Proxy> proxies, [String? url]) =>
      switch (_ref.read(proxiesStyleSettingProvider).sortType) {
        ProxiesSortType.none => proxies,
        ProxiesSortType.delay => _sortOfDelay(
            proxies: proxies,
            testUrl: url,
          ),
        ProxiesSortType.name => _sortOfName(proxies),
      };

  Future<Null> clearEffect(String profileId) async {
    if (_ref.read(nodeOverviewEnabledProvider)) {
      if (_ref.exists(nodeCatalogServiceProvider)) {
        _ref.read(nodeCatalogServiceProvider).invalidate(profileId);
      }
      // Explicit deletion also cleans history before the overview is opened.
      try {
        await _ref.read(nodeHealthRecorderProvider).removeProfile(profileId);
      } catch (_) {
        commonPrint.log('node.health reason=removeFailed');
      }
    }
    final profilePath = await appPath.getProfilePath(profileId);
    final providersDirPath = await appPath.getProvidersDirPath(profileId);
    return Isolate.run(() async {
      final profileFile = File(profilePath);
      final isExists = await profileFile.exists();
      if (isExists) {
        unawaited(profileFile.delete(recursive: true));
      }
      final providersFileDir = File(providersDirPath);
      final providersFileIsExists = await providersFileDir.exists();
      if (providersFileIsExists) {
        unawaited(providersFileDir.delete(recursive: true));
      }
    });
  }

  void updateTun() {
    unawaited(setTunEnabled(Platform.isWindows
      ? !_tunRuntime.isEnabled && !_tunRuntime.desiredEnabled
      : !_ref.read(patchClashConfigProvider).tun.enable));
  }

  void updateSystemProxy() {
    _ref.read(networkSettingProvider.notifier).updateState(
          (state) => state.copyWith(
            systemProxy: !state.systemProxy,
          ),
        );
  }

  void _applyCustomViewSettings(Profile profile) {
    final headers = profile.providerHeaders;

    // New-look dashboard: writes the user-facing `newDashboard` setting. Gated by
    // the caller's flclashx-custom policy (update => every apply, add => only on
    // first add), and the settings toggle stays user-controllable afterwards.
    final newboard = headers['flclashx-newboard'];
    if (newboard == 'true' || newboard == 'false') {
      _ref.read(appSettingProvider.notifier).updateState(
            (state) => state.copyWith(newDashboard: newboard == 'true'),
          );
    }

    final dashboardLayout = headers['flclashx-widgets'];
    if (dashboardLayout != null && dashboardLayout.isNotEmpty) {
      final newLayout = DashboardWidgetParser.parseLayout(dashboardLayout);
      if (newLayout.isNotEmpty) {
        _ref.read(appSettingProvider.notifier).updateState(
              (state) => state.copyWith(dashboardWidgets: newLayout),
            );
      }
    }

    final proxiesView = headers['flclashx-view'];
    if (proxiesView != null && proxiesView.isNotEmpty) {
      final proxiesStyleNotifier =
          _ref.read(proxiesStyleSettingProvider.notifier);
      proxiesStyleNotifier.updateState((currentState) {
        var newState = currentState;
        final settings = proxiesView.split(';');
        for (final setting in settings) {
          final parts = setting.split(':');
          if (parts.length == 2) {
            final key = parts[0].trim().toLowerCase();
            final value = parts[1].trim().toLowerCase();
            switch (key) {
              case 'type':
                switch (value) {
                  case 'list':
                    newState = newState.copyWith(type: ProxiesType.list);
                    break;
                  case 'tab':
                    newState = newState.copyWith(type: ProxiesType.tab);
                    break;
                }
                break;
              case 'sort':
                switch (value) {
                  case 'none':
                    newState =
                        newState.copyWith(sortType: ProxiesSortType.none);
                    break;
                  case 'delay':
                    newState =
                        newState.copyWith(sortType: ProxiesSortType.delay);
                    break;
                  case 'name':
                    newState =
                        newState.copyWith(sortType: ProxiesSortType.name);
                    break;
                }
                break;
              case 'layout':
                switch (value) {
                  case 'loose':
                    newState = newState.copyWith(layout: ProxiesLayout.loose);
                    break;
                  case 'standard':
                    newState =
                        newState.copyWith(layout: ProxiesLayout.standard);
                    break;
                  case 'tight':
                    newState = newState.copyWith(layout: ProxiesLayout.tight);
                    break;
                }
                break;
              case 'icon':
                switch (value) {
                  case 'standard':
                  case 'icon':
                    newState =
                        newState.copyWith(iconStyle: ProxiesIconStyle.icon);
                    break;
                  case 'none':
                    newState =
                        newState.copyWith(iconStyle: ProxiesIconStyle.none);
                    break;
                }
                break;
              case 'card':
                switch (value) {
                  case 'expand':
                    newState =
                        newState.copyWith(cardType: ProxyCardType.expand);
                    break;
                  case 'shrink':
                    newState =
                        newState.copyWith(cardType: ProxyCardType.shrink);
                    break;
                  case 'min':
                    newState = newState.copyWith(cardType: ProxyCardType.min);
                    break;
                  case 'oneline':
                    newState =
                        newState.copyWith(cardType: ProxyCardType.oneline);
                    break;
                }
                break;
            }
          }
        }
        return newState;
      });
    }
  }

  Future<List<Package>> getPackages() async {
    if (_ref.read(isMobileViewProvider)) {
      await Future.delayed(commonDuration);
    }
    if (_ref.read(packagesProvider).isEmpty) {
      _ref.read(packagesProvider.notifier).value =
          await app?.getPackages() ?? [];
    }
    return _ref.read(packagesProvider);
  }

  void updateStart() {
    updateStatus(!_ref.read(runTimeProvider.notifier).isStart);
  }

  void updateCurrentSelectedMap(String groupName, String proxyName) {
    final currentProfile = _ref.read(currentProfileProvider);
    if (currentProfile != null &&
        currentProfile.selectedMap[groupName] != proxyName) {
      final selectedMap = Map<String, String>.from(
        currentProfile.selectedMap,
      )..[groupName] = proxyName;
      _ref.read(profilesProvider.notifier).setProfile(
            currentProfile.copyWith(
              selectedMap: selectedMap,
            ),
          );
    }
  }

  void updateCurrentUnfoldSet(Set<String> value) {
    final currentProfile = _ref.read(currentProfileProvider);
    if (currentProfile == null) {
      return;
    }
    _ref.read(profilesProvider.notifier).setProfile(
          currentProfile.copyWith(
            unfoldSet: value,
          ),
        );
  }

  void changeMode(Mode mode) {
    _ref.read(patchClashConfigProvider.notifier).updateState(
          (state) => state.copyWith(mode: mode),
        );
    if (mode == Mode.global) {
      updateCurrentGroupName(GroupName.GLOBAL.name);
    }
    addCheckIpNumDebounce();
  }

  void updateAutoLaunch() {
    _ref.read(appSettingProvider.notifier).updateState(
          (state) => state.copyWith(
            autoLaunch: !state.autoLaunch,
          ),
        );
  }

  void updateTheme(ThemeProps themeProps) {
    _ref.read(themeSettingProvider.notifier).updateState((_) => themeProps);
  }

  Future<void> updateVisible() async {
    if (Platform.isMacOS) return;

    final visible = await window?.isVisible;
    if (visible != null && !visible) {
      window?.show();
    } else {
      window?.hide();
    }
  }

  void updateMode() {
    _ref.read(patchClashConfigProvider.notifier).updateState(
      (state) {
        final index = Mode.values.indexWhere((item) => item == state.mode);
        if (index == -1) {
          return null;
        }
        final nextIndex = index + 1 > Mode.values.length - 1 ? 0 : index + 1;
        return state.copyWith(
          mode: Mode.values[nextIndex],
        );
      },
    );
  }

  Future<void> handleAddOrUpdate(WidgetRef ref, [Rule? rule]) async {
    final res = await globalState.showCommonDialog<Rule>(
      child: AddRuleDialog(
        rule: rule,
        snippet: ref.read(
          profileOverrideStateProvider.select(
            (state) => state.snippet!,
          ),
        ),
      ),
    );
    if (res == null) {
      return;
    }
    ref.read(profileOverrideStateProvider.notifier).updateState(
      (state) {
        final model = state.copyWith.overrideData!(
          rule: state.overrideData!.rule.updateRules(
            (rules) {
              final index = rules.indexWhere((item) => item.id == res.id);
              if (index == -1) {
                return List.from([res, ...rules]);
              }
              return List.from(rules)..[index] = res;
            },
          ),
        );
        return model;
      },
    );
  }

  Future<bool> exportLogs() async {
    final logsRaw = _ref.read(logsProvider).list.map(
          (item) => item.toString(),
        );
    final data = await Isolate.run<List<int>>(() async {
      final logsRawString = logsRaw.join("\n");
      return utf8.encode(logsRawString);
    });
    return await picker.saveFile(
          utils.logFile,
          Uint8List.fromList(data),
        ) !=
        null;
  }

  Future<List<int>> backupData() async {
    final homeDirPath = await appPath.homeDirPath;
    final profilesPath = await appPath.profilesPath;
    final configJson = globalState.config.toJson();
    return Isolate.run<List<int>>(() async {
      final archive = Archive();
      archive.addJson("config.json", configJson);
      archive.addDirectoryToArchive(profilesPath, homeDirPath);
      final zipEncoder = ZipEncoder();
      return zipEncoder.encode(archive);
    });
  }

  Future<void> updateTray([bool focus = false]) async {
    await tray.update(
      trayState: _ref.read(trayStateProvider),
      focus: focus,
    );
  }

  Future<void> recoveryData(
    List<int> data,
    RecoveryOption recoveryOption,
  ) async {
    final archive = await Isolate.run<Archive>(() {
      final zipDecoder = ZipDecoder();
      return zipDecoder.decodeBytes(data);
    });
    final homeDirPath = await appPath.homeDirPath;
    final configs =
        archive.files.where((item) => item.name.endsWith(".json")).toList();
    final profiles =
        archive.files.where((item) => !item.name.endsWith(".json"));
    final configIndex =
        configs.indexWhere((config) => config.name == "config.json");
    if (configIndex == -1) throw "invalid backup file";
    final configFile = configs[configIndex];
    var tempConfig = Config.compatibleFromJson(
      json.decode(
        utf8.decode(configFile.content),
      ),
    );
    for (final profile in profiles) {
      if (!profile.isFile) continue;
      final filePath = join(homeDirPath, profile.name);
      final file = File(filePath);
      await file.create(recursive: true);
      await file.writeAsBytes(profile.content);
    }
    final clashConfigIndex =
        configs.indexWhere((config) => config.name == "clashConfig.json");
    if (clashConfigIndex != -1) {
      final clashConfigFile = configs[clashConfigIndex];
      tempConfig = tempConfig.copyWith(
        patchClashConfig: ClashConfig.fromJson(
          json.decode(
            utf8.decode(
              clashConfigFile.content,
            ),
          ),
        ),
      );
    }
    _recovery(
      tempConfig,
      recoveryOption,
    );
  }

  void _recovery(Config config, RecoveryOption recoveryOption) {
    final recoveryStrategy = _ref.read(appSettingProvider.select(
      (state) => state.recoveryStrategy,
    ));
    final profiles = config.profiles;
    if (recoveryStrategy == RecoveryStrategy.override) {
      _ref.read(profilesProvider.notifier).value = profiles;
    } else {
      for (final profile in profiles) {
        _ref.read(profilesProvider.notifier).setProfile(
              profile,
            );
      }
    }
    final onlyProfiles = recoveryOption == RecoveryOption.onlyProfiles;
    if (!onlyProfiles) {
      _ref.read(patchClashConfigProvider.notifier).value =
          config.patchClashConfig;
      _ref.read(appSettingProvider.notifier).value = config.appSetting;
      _ref.read(currentProfileIdProvider.notifier).value =
          config.currentProfileId;
      _ref.read(appDAVSettingProvider.notifier).value = config.dav;
      _ref.read(themeSettingProvider.notifier).value = config.themeProps;
      _ref.read(windowSettingProvider.notifier).value = config.windowProps;
      _ref.read(vpnSettingProvider.notifier).value = config.vpnProps;
      _ref.read(proxiesStyleSettingProvider.notifier).value =
          config.proxiesStyle;
      _ref.read(overrideDnsProvider.notifier).value = config.overrideDns;
      _ref.read(networkSettingProvider.notifier).value = config.networkProps;
      _ref.read(hotKeyActionsProvider.notifier).value = config.hotKeyActions;
      _ref.read(scriptStateProvider.notifier).value = config.scriptProps;
    }
    final currentProfile = _ref.read(currentProfileProvider);
    if (currentProfile == null) {
      _ref.read(currentProfileIdProvider.notifier).value = profiles.first.id;
    }
    savePreferencesDebounce();
  }
}

class _ControllerWindowsTunStartupEffects implements WindowsTunStartupEffects {
  _ControllerWindowsTunStartupEffects(
    this.controller, {
    this.syncProviderSettings = true,
  });
  final AppController controller;
  final bool syncProviderSettings;
  @override
  bool get proxyRunning => clashService?.agentProxyRunning ?? false;
  @override
  Future<bool> hasProfile() async {
    final profile = controller._ref.read(currentProfileProvider);
    if (profile == null) return false;
    final path = await appPath.getProfilePath(profile.id);
    return isReadableWindowsStartupProfile(path);
  }
  @override
  Future<TunStatus?> observe() => controller.refreshWindowsTunStatus(fresh: true);
  @override
  Future<bool> componentsMatch() async => await clashService?.windowsComponentsMatch() ?? false;
  @override
  bool canMigrate() => clashService?.windowsAgentSupportsMigration ?? false;
  @override
  Future<bool> authorize() async => await controller._adminAuthorization.request(system.authorizeCore) != AuthorizeCode.error;
  @override
  Future<bool> ensureBackend(bool Function() isCurrent) async {
    final wasRunning = globalState.isStart || proxyRunning;
    final replaced =
        await clashService?.ensureWindowsTunBackend(isCurrent: isCurrent) ??
            false;
    if (replaced) {
      controller._tunRuntime.clearCoreRuntimeFailure();
      globalState.clearRuntimeSetup();
      controller._hasAppliedWindowsProfile = false;
      controller._needsWindowsCoreRestore = true;
      controller._windowsCoreRestoreNeedsListener =
          controller._windowsCoreRestoreNeedsListener || wasRunning;
      controller._ref.invalidate(nodeRuntimeReadProvider);
    }
    return replaced;
  }
  @override
  Future<void> initialize(bool Function() isCurrent) async {
    final initialized = await clashCore.isInit;
    if (!isCurrent()) return;
    if (!initialized) {
      final accepted = await clashCore.init();
      if (!isCurrent()) return;
      if (!accepted) throw const TunFailure('configurationFailed');
    }
    final accepted = await clashCore.setState(globalState.getCoreState());
    if (!isCurrent()) return;
    if (!accepted) throw const TunFailure('configurationFailed');
  }
  @override
  Future<void> applyConfiguration({required bool full, required bool Function() isCurrent}) async {
    try {
      if (full) {
        await controller._setupClashConfigImpl(
          isCurrent: isCurrent,
          syncProviderSettings: syncProviderSettings,
        );
      } else {
        await controller._updateWindowsConfig(isCurrent: isCurrent);
      }
    } on TunFailure {
      if (full &&
          controller._needsWindowsCoreRestore &&
          !controller._pendingWindowsProxyStop &&
          controller._hasAppliedWindowsProfile &&
          isCurrent()) {
        await controller._restoreReplacedWindowsCoreIfNeeded(
          isCurrent: isCurrent,
          applyProfileIfMissing: false,
        );
      }
      rethrow;
    } catch (_) { throw const TunFailure('configurationFailed'); }
  }
  @override
  Future<bool> startListener() async {
    final started = await clashCore.startListener();
    if (started) {
      controller._needsWindowsCoreRestore = false;
      controller._windowsCoreRestoreNeedsListener = false;
    }
    return started;
  }
  @override
  Future<void> stopProxy() => controller._updateStatus(false);
  @override
  Future<void> startProxyWithoutTun() async {
    try {
      await controller._initCore();
    } catch (e) {
      commonPrint.log('initCore failed (will retry on profile change): $e');
    }
    if (proxyRunning) {
      // Adopt an Agent-owned running proxy read-only; do not restart listeners.
      await controller._initStatus();
      return;
    }
    await controller.updateStatus(true);
  }
  @override
  Future<void> restartCore() async {
    // Runs inside the TUN request queue; AppController.restartCore would
    // re-enter the same queue and deadlock. Drop observations of the old Core
    // so its latched closeFailed cannot be accepted after the replacement.
    final service = clashService;
    if (service == null) throw const TunFailure('startFailed');
    final wasRunning = globalState.isStart || proxyRunning;
    controller._tunRuntime.invalidate();
    controller._tunRuntime.clearCoreRuntimeFailure();
    globalState.clearRuntimeSetup();
    controller._hasAppliedWindowsProfile = false;
    controller._needsWindowsCoreRestore = true;
    controller._windowsCoreRestoreNeedsListener =
        controller._windowsCoreRestoreNeedsListener || wasRunning;
    controller._ref.invalidate(nodeRuntimeReadProvider);
    await service.reStart();
  }
  @override
  void log(String message) => commonPrint.log(message);
  @override
  Future<void> reflectRunning(bool Function() isCurrent) async {
    if (!isCurrent()) return;
    await clashCore.setUiActive(uiActivity.value);
    if (!isCurrent()) return;
    if (controller._ref.read(appSettingProvider).openLogs) {
      clashCore.startLog();
    } else {
      clashCore.stopLog();
    }
    if (!isCurrent()) return;
    await controller.updateGroups();
    if (!isCurrent()) return;
    await controller.updateProviders();
    if (!isCurrent()) return;
    controller.initForegroundCache();
    await StatusBarManager.updateIcon(isConnected: true);
    if (!isCurrent()) return;
    globalState.startTime ??= DateTime.now();
    unawaited(globalState.startUpdateTasks([controller.updateTraffic]));
    controller.startRunTimeTimer();
  }
}

class _TrackedWindowsTunStartupEffects implements WindowsTunStartupEffects {
  _TrackedWindowsTunStartupEffects(this.controller, this.delegate);
  final AppController controller;
  final WindowsTunStartupEffects delegate;

  @override
  bool get proxyRunning => delegate.proxyRunning;
  @override
  Future<bool> hasProfile() => delegate.hasProfile();
  @override
  Future<TunStatus?> observe() => delegate.observe();
  @override
  Future<bool> componentsMatch() => delegate.componentsMatch();
  @override
  bool canMigrate() => delegate.canMigrate();
  @override
  Future<bool> authorize() => delegate.authorize();
  @override
  Future<bool> ensureBackend(bool Function() isCurrent) async {
    final wasRunning = globalState.isStart || delegate.proxyRunning;
    final replaced = await delegate.ensureBackend(isCurrent);
    if (replaced) {
      controller._tunRuntime.clearCoreRuntimeFailure();
      globalState.clearRuntimeSetup();
      controller._hasAppliedWindowsProfile = false;
      controller._needsWindowsCoreRestore = true;
      controller._windowsCoreRestoreNeedsListener =
          controller._windowsCoreRestoreNeedsListener || wasRunning;
      controller._ref.invalidate(nodeRuntimeReadProvider);
    }
    return replaced;
  }
  @override
  Future<void> initialize(bool Function() isCurrent) =>
      delegate.initialize(isCurrent);
  @override
  Future<void> applyConfiguration({
    required bool full,
    required bool Function() isCurrent,
  }) async {
    var checkedCurrentBeforeDispatch = false;
    var wasCurrentAtDispatch = false;
    try {
      await delegate.applyConfiguration(
        full: full,
        isCurrent: () {
          final current = isCurrent();
          if (!checkedCurrentBeforeDispatch) {
            checkedCurrentBeforeDispatch = true;
            wasCurrentAtDispatch = current;
          }
          return current;
        },
      );
      if (full && (wasCurrentAtDispatch || isCurrent())) {
        controller._hasAppliedWindowsProfile = true;
        controller._lastAppliedWindowsProfileId =
            controller._ref.read(currentProfileIdProvider);
      }
    } on TunFailure {
      if (full &&
          controller._needsWindowsCoreRestore &&
          !controller._pendingWindowsProxyStop &&
          controller._hasAppliedWindowsProfile &&
          isCurrent()) {
        await controller._restoreReplacedWindowsCoreIfNeeded(
          isCurrent: isCurrent,
          applyProfileIfMissing: false,
        );
      }
      rethrow;
    }
  }
  @override
  Future<bool> startListener() async {
    final started = await delegate.startListener();
    if (started) {
      controller._needsWindowsCoreRestore = false;
      controller._windowsCoreRestoreNeedsListener = false;
    }
    return started;
  }
  @override
  Future<void> stopProxy() async {
    controller._windowsCoreRestoreNeedsListener = false;
    if (controller._hasAppliedWindowsProfile) {
      controller._needsWindowsCoreRestore = false;
    }
    await delegate.stopProxy();
  }
  @override
  Future<void> startProxyWithoutTun() => delegate.startProxyWithoutTun();
  @override
  Future<void> restartCore() async {
    final wasRunning = globalState.isStart || delegate.proxyRunning;
    controller._tunRuntime.invalidate();
    controller._tunRuntime.clearCoreRuntimeFailure();
    globalState.clearRuntimeSetup();
    controller._hasAppliedWindowsProfile = false;
    controller._needsWindowsCoreRestore = true;
    controller._windowsCoreRestoreNeedsListener =
        controller._windowsCoreRestoreNeedsListener || wasRunning;
    controller._ref.invalidate(nodeRuntimeReadProvider);
    await delegate.restartCore();
  }
  @override
  void log(String message) => delegate.log(message);
  @override
  Future<void> reflectRunning(bool Function() isCurrent) =>
      delegate.reflectRunning(isCurrent);
}

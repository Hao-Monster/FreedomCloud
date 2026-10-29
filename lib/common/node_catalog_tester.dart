import 'dart:async';

import 'package:flclashx/models/node_catalog.dart';
import 'package:flclashx/models/profile.dart';
import 'package:flutter/foundation.dart';

import 'delay_test_coordinator.dart';
import 'node_catalog_service.dart';
import 'node_health_store.dart';

typedef CatalogTestSelection = ({Profile profile, List<CatalogNode> nodes});

/// View-owned orchestration; the coordinator remains the single live/catalog
/// request budget. Preparing one profile at a time prevents LRU eviction of a
/// later profile's adapters before its queued requests can use them.
class NodeCatalogTester extends ChangeNotifier {
  NodeCatalogTester({
    required this.service,
    required this.store,
    required this.coordinator,
    required this.isCurrentProfile,
    required this.activeProfileId,
    this.activity,
  }) {
    coordinator.addListener(_progress);
    activity?.addListener(_activityChanged);
  }

  final NodeCatalogService service;
  final NodeHealthStore store;
  final DelayTestCoordinator coordinator;
  final bool Function(Profile profile) isCurrentProfile;
  final String? Function() activeProfileId;
  final ValueListenable<bool>? activity;
  bool _running = false;
  bool _collecting = false;
  bool _disposed = false;
  int _epoch = 0;
  int? _ownedBatch;
  int _total = 0;
  int _completed = 0;
  ({String profileId, Future<ProfileCatalog> future})? _preparation;
  final _catalogs = <String, String>{};
  final _profileIds = <String>{};
  bool _testingAll = false;
  String? _testingProfile;
  CatalogTestPlan? _activePlan;

  bool get busy => _collecting || _running || coordinator.busy;
  int get total => _collecting
      ? 0
      : _running
          ? _total
          : coordinator.total;
  int get completed => _collecting
      ? 0
      : _running
          ? _completed +
              (_ownedBatch != null && _ownedBatch == coordinator.activeBatchId
                  ? coordinator.completed
                  : 0)
          : coordinator.completed;

  bool pending(String profileId, String identityKey) =>
      coordinator.activeTargets.any((target) =>
          target.scope != null &&
          _catalogs[target.scope] == profileId &&
          target.name == identityKey);

  void _progress() {
    if (!_disposed) notifyListeners();
  }

  void _activityChanged() {
    // A hidden window must also revoke work not yet admitted to the shared
    // coordinator; cancelling its currently empty batch cannot do that.
    if (activity?.value == false) disposeScope();
  }

  Future<DelayBatchResult> collectAndTest(
      Future<List<CatalogTestSelection>> Function(bool Function() isCurrent)
          collect,
      String url) async {
    if (activity?.value == false) {
      return const DelayBatchResult(
          completed: 0, failed: 0, reason: 'uiInactive');
    }
    if (busy || _disposed) {
      return const DelayBatchResult(completed: 0, failed: 0, reason: 'busy');
    }
    _collecting = true;
    _total = _completed = 0;
    final epoch = ++_epoch;
    _progress();
    try {
      final selections = await collect(() => !_disposed && epoch == _epoch);
      if (_disposed || epoch != _epoch) return _result('cancelled');
      _collecting = false;
      return await testVisible(selections, url);
    } on CatalogBuildException catch (error) {
      return _result(error.reason);
    } catch (_) {
      return _result('prepareFailed');
    } finally {
      _collecting = false;
      _progress();
    }
  }

  Future<DelayBatchResult> testCurrent(
      Iterable<DelayTestTarget> targets) async {
    if (activity?.value == false) {
      return const DelayBatchResult(
          completed: 0, failed: 0, reason: 'uiInactive');
    }
    if (busy || _disposed) {
      return const DelayBatchResult(completed: 0, failed: 0, reason: 'busy');
    }
    _running = true;
    _profileIds.addAll([if (activeProfileId() case final String id) id]);
    final unique = <(String, String, String), DelayTestTarget>{};
    for (final target in targets) {
      if (target.name.isNotEmpty) unique.putIfAbsent(target.key, () => target);
    }
    final selected = unique.values.toList(growable: false);
    _total = selected.length;
    _completed = 0;
    _progress();
    try {
      final result = coordinator.run(selected,
          batchTimeout: _batchTimeout(selected.length));
      _ownedBatch = coordinator.activeBatchId;
      return await result;
    } finally {
      _ownedBatch = null;
      _running = false;
      _profileIds.clear();
      _progress();
    }
  }

  Duration _batchTimeout(int count) => Duration(
      milliseconds:
          ((count + coordinator.concurrency - 1) ~/ coordinator.concurrency +
                      1) *
                  coordinator.requestTimeout.inMilliseconds +
              5000);

  /// Explicit all-profile action. Resolve, prepare and release one profile at
  /// a time; a bad subscription must never prevent another from being tested.
  /// Display filters are deliberately not inputs to this operation.
  Future<DelayBatchResult> testAll(List<Profile> profiles, String url) async {
    if (activity?.value == false) {
      return const DelayBatchResult(
          completed: 0, failed: 0, reason: 'uiInactive');
    }
    if (busy || _disposed) {
      return const DelayBatchResult(completed: 0, failed: 0, reason: 'busy');
    }
    final epoch = ++_epoch;
    final selected = {for (final profile in profiles) profile.id: profile};
    _profileIds.addAll(selected.keys);
    _testingAll = _running = true;
    _total = _completed = 0;
    var failed = 0;
    var untested = 0;
    final issues = <DelayBatchIssue>[];
    bool current() => !_disposed && epoch == _epoch;
    DelayBatchResult result([String? reason]) => DelayBatchResult(
        completed: _completed,
        failed: failed,
        untested: untested +
            (reason == null
                ? 0
                : (_total - _completed - untested).clamp(0, _total)),
        issues: List.unmodifiable(issues),
        reason: reason);
    void issue(String profileId, String reason, [int count = 0]) {
      untested += count;
      issues.add(
          DelayBatchIssue(profileId: profileId, reason: reason, count: count));
    }

    _progress();
    try {
      for (final profile in selected.values) {
        if (!current()) return result('cancelled');
        _testingProfile = profile.id;
        CatalogTestPlan? plan;
        var accounted = 0;
        try {
          if (!isCurrentProfile(profile) || profile.isUpdating) {
            issue(
                profile.id, profile.isUpdating ? 'updating' : 'configChanged');
            continue;
          }
          plan = await service.resolveForTestAll(profile,
              isCurrent: () => current() && isCurrentProfile(profile));
          _activePlan = plan;
          if (!current()) return result('cancelled');
          _total += plan.nodes.length;
          for (final provider in plan.providerIssues) {
            _total += provider.count;
            issue(profile.id, provider.reason, provider.count);
          }
          // An ambiguous identity cannot be bound to persistent history. Do
          // not let one such row turn into a capability error for the batch.
          final identities = <String, int>{};
          for (final node in plan.nodes) {
            identities.update(node.identityKey, (count) => count + 1,
                ifAbsent: () => 1);
          }
          for (var chunk = 0; chunk < plan.chunkCount; chunk++) {
            if (!current()) return result('cancelled');
            ProfileCatalog? prepared;
            try {
              prepared = await plan.prepareChunk(chunk);
              if (!current()) return result('cancelled');
              if (!isCurrentProfile(profile)) {
                throw const CatalogBuildException('configChanged');
              }
              final id = prepared.coreCatalogId;
              if (id == null) {
                throw const CatalogBuildException('invalidResponse');
              }
              final targets = <DelayTestTarget>[];
              for (final node in prepared.nodes) {
                if (node.unsupported != CatalogUnsupportedReason.none ||
                    node.coreIndex == null ||
                    identities[node.identityKey] != 1) {
                  issue(
                      profile.id,
                      identities[node.identityKey] != 1
                          ? 'ambiguousNode'
                          : node.unsupported == CatalogUnsupportedReason.none
                              ? 'invalidResponse'
                              : node.unsupported.name,
                      1);
                  accounted++;
                } else {
                  targets.add(DelayTestTarget(node.identityKey, url,
                      scope: id, nodeIndex: node.coreIndex));
                }
              }
              if (coordinator.busy) return result('busy');
              store.bindCatalog(prepared);
              _catalogs[id] = profile.id;
              final rejectedBefore = store.catalogCapacityRejectedWrites(id);
              final run = coordinator.run(targets,
                  batchTimeout: _batchTimeout(targets.length));
              _ownedBatch = coordinator.activeBatchId;
              final measured = await run;
              _ownedBatch = null;
              await store.awaitCatalogWrites();
              final rejectedWrites =
                  store.catalogCapacityRejectedWrites(id) - rejectedBefore;
              try {
                await store.flush();
              } catch (_) {
                issues.add(DelayBatchIssue(
                    profileId: profile.id, reason: 'healthStoreUnavailable'));
              }
              final measurements = measured.completed - measured.untested;
              _completed += measurements;
              failed += measured.failed - measured.untested;
              accounted += targets.length;
              if (rejectedWrites > 0) {
                issues.add(DelayBatchIssue(
                    profileId: profile.id,
                    reason: 'healthCapacityExceeded',
                    count: rejectedWrites));
              }
              if (measured.reason != null) {
                issue(profile.id, measured.reason!,
                    targets.length - measurements);
                if (!current() || _stopsAllProfiles(measured.reason!)) {
                  return result(measured.reason);
                }
              } else if (measured.untested > 0) {
                issue(profile.id, 'invalidResponse', measured.untested);
              }
              if (!isCurrentProfile(profile)) {
                issue(
                    profile.id, 'configChanged', plan.nodes.length - accounted);
                break;
              }
              _progress();
            } finally {
              final id = prepared?.coreCatalogId;
              if (id != null) {
                store.unbindCatalog(id);
                _catalogs.remove(id);
                await service.releasePrepared(id);
              }
            }
          }
        } on CatalogBuildException catch (error) {
          if (!current()) return result('cancelled');
          final reason =
              !isCurrentProfile(profile) ? 'configChanged' : error.reason;
          issue(profile.id, reason, (plan?.nodes.length ?? 0) - accounted);
          if (_stopsAllProfiles(reason)) return result(reason);
        } catch (_) {
          if (!current()) return result('cancelled');
          issue(profile.id, 'prepareFailed',
              (plan?.nodes.length ?? 0) - accounted);
        } finally {
          plan?.dispose();
          _activePlan = null;
          _testingProfile = null;
          _progress();
        }
      }
      return result();
    } finally {
      _ownedBatch = null;
      _testingAll = _running = false;
      _profileIds.clear();
      _progress();
    }
  }

  static bool _stopsAllProfiles(String reason) => const {
        'cancelled',
        'uiInactive',
        'sessionClosed',
        'coreRestarted',
        'transportFailure',
        'coreUnavailable',
        'runtimeUnavailable',
        'strictModeUnsupported',
        'busy',
      }.contains(reason);

  /// A changed profile revokes only its own work during an all-profile run.
  /// Window/session changes still use disposeScope to stop the entire action.
  void profileChanged(String profileId) {
    if (!_profileIds.contains(profileId)) return;
    if (!_testingAll) {
      disposeScope();
    } else if (_testingProfile == profileId) {
      for (final entry in _catalogs.entries
          .where((entry) => entry.value == profileId)
          .toList()) {
        store.unbindCatalog(entry.key);
        _catalogs.remove(entry.key);
      }
      _activePlan?.dispose();
      if (_ownedBatch != null && _ownedBatch == coordinator.activeBatchId) {
        unawaited(coordinator.cancel(reason: 'configChanged'));
      }
    }
  }

  Future<DelayBatchResult> testVisible(
      List<CatalogTestSelection> selections, String url) async {
    if (activity?.value == false) {
      return const DelayBatchResult(
          completed: 0, failed: 0, reason: 'uiInactive');
    }
    if (busy || _disposed) {
      return const DelayBatchResult(completed: 0, failed: 0, reason: 'busy');
    }
    final epoch = ++_epoch;
    final selected = [
      for (final selection in selections)
        if (selection.profile.id != activeProfileId())
          (
            profile: selection.profile,
            nodes: [
              for (final node in selection.nodes)
                if (node.unsupported == CatalogUnsupportedReason.none) node,
            ]
          ),
    ];
    _total = selected.fold(0, (sum, item) => sum + item.nodes.length);
    _profileIds.addAll(selected.map((item) => item.profile.id));
    _completed = 0;
    var failed = 0;
    _running = true;
    _progress();
    try {
      for (final selection in selected) {
        if (epoch != _epoch || _disposed) return _result('cancelled', failed);
        if (selection.nodes.isEmpty) continue;
        if (!isCurrentProfile(selection.profile) ||
            selection.profile.id == activeProfileId()) {
          return _result('configChanged', failed);
        }
        ProfileCatalog? prepared;
        try {
          final preparing = service.ensurePrepared(selection.profile);
          _preparation = (profileId: selection.profile.id, future: preparing);
          prepared = await preparing;
          _preparation = null;
          if (epoch != _epoch || _disposed) return _result('cancelled', failed);
          if (!isCurrentProfile(selection.profile) ||
              selection.profile.id == activeProfileId()) {
            return _result('configChanged', failed);
          }
          final id = prepared.coreCatalogId!;
          final wanted =
              selection.nodes.map((node) => node.identityKey).toSet();
          if (!prepared.nodes
              .map((node) => node.identityKey)
              .toSet()
              .containsAll(wanted)) {
            return _result('configChanged', failed);
          }
          final targets = [
            for (final node in prepared.nodes)
              if (node.coreIndex != null &&
                  node.unsupported == CatalogUnsupportedReason.none &&
                  wanted.contains(node.identityKey))
                DelayTestTarget(node.identityKey, url,
                    scope: id, nodeIndex: node.coreIndex),
          ];
          _total -= selection.nodes.length - targets.length;
          if (coordinator.busy) return _result('busy', failed);
          store.bindCatalog(prepared);
          _catalogs[id] = selection.profile.id;
          final timeout = Duration(
              milliseconds: ((targets.length + coordinator.concurrency - 1) ~/
                              coordinator.concurrency +
                          1) *
                      coordinator.requestTimeout.inMilliseconds +
                  5000);
          final future = coordinator.run(targets, batchTimeout: timeout);
          _ownedBatch = coordinator.activeBatchId;
          final result = await future;
          _ownedBatch = null;
          await store.awaitCatalogWrites();
          _completed += result.completed;
          failed += result.failed;
          _progress();
          if (result.reason != null) return _result(result.reason, failed);
        } on CatalogBuildException catch (error) {
          return _result(epoch != _epoch ? 'cancelled' : error.reason, failed);
        } finally {
          _preparation = null;
          final id = prepared?.coreCatalogId;
          if (id != null) {
            store.unbindCatalog(id);
            _catalogs.remove(id);
            await service.releasePrepared(id);
          }
        }
      }
      return _result(null, failed);
    } finally {
      _ownedBatch = null;
      _running = false;
      _profileIds.clear();
      _progress();
    }
  }

  DelayBatchResult _result(String? reason, [int failed = 0]) =>
      DelayBatchResult(completed: _completed, failed: failed, reason: reason);

  Future<void> cancel({String reason = 'cancelled'}) async {
    _epoch++;
    _activePlan?.dispose();
    _cancelPreparation();
    // The general Cancel action also controls a live test started elsewhere.
    await coordinator.cancel(reason: reason);
  }

  /// Disposing a view is not permission to cancel another entry point's test.
  void disposeScope() {
    _epoch++;
    _activePlan?.dispose();
    _cancelPreparation();
    if (_ownedBatch != null && _ownedBatch == coordinator.activeBatchId) {
      unawaited(coordinator.cancel(reason: 'uiInactive'));
    }
    for (final id in _catalogs.keys.toList()) {
      store.unbindCatalog(id);
      unawaited(service.releasePrepared(id));
    }
    _catalogs.clear();
  }

  void _cancelPreparation() {
    final pending = _preparation;
    if (pending != null) {
      service.cancelPreparation(pending.profileId, pending.future);
      _preparation = null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    activity?.removeListener(_activityChanged);
    disposeScope();
    coordinator.removeListener(_progress);
    super.dispose();
  }
}

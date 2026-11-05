import 'package:flclashx/common/proxy.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/pac.dart';
import 'package:flclashx/providers/state.dart';
import 'package:flclashx/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef _AppliedProxySignature = (
  bool active,
  bool pacEnabled,
  String pacUrl,
  int port,
  String bypassJoined,
);

const _AppliedProxySignature _disarmedProxySignature = (false, false, '', 0, '');

/// Coordinates synchronous pre-stop System Proxy disarm with [ProxyManager] so
/// Windows WinInet clears `127.0.0.1:<mixedPort>` while the Core listener is
/// still alive, eliminating the `ERR_PROXY_CONNECTION_FAILED` blackhole window
/// and avoiding duplicate WinInet broadcasts when `runTimeProvider` clears.
class SystemProxyCoordinator {
  _ProxyManagerState? _attached;
  int _disarmDepth = 0;

  bool get isAttached => _attached?.mounted ?? false;

  bool get isDisarmingForStop => _disarmDepth > 0;

  void _attach(_ProxyManagerState state) {
    _attached = state;
    _disarmDepth = 0;
  }

  void _detach(_ProxyManagerState state) {
    if (identical(_attached, state)) {
      _attached = null;
      _disarmDepth = 0;
    }
  }

  /// Acquires an idempotent pre-stop disarm lease through the same serialized
  /// queue as [ProxyManager] before Core listeners close. Releasing the outermost
  /// lease with `reconcile: true` automatically re-arms or retries cleanup if
  /// `stopProxy()` failed while the proxy remained active.
  Future<void Function({bool reconcile})> acquireStopDisarm() async {
    final manager = _attached;
    if (manager == null || !manager.mounted) {
      return ({reconcile = true}) {};
    }
    _disarmDepth++;
    try {
      await manager._disarmNow();
    } catch (_) {
      if (_disarmDepth > 0) {
        _disarmDepth--;
      }
      rethrow;
    }
    var released = false;
    return ({reconcile = true}) {
      if (released) return;
      released = true;
      if (_disarmDepth > 0) {
        _disarmDepth--;
      }
      if (_disarmDepth == 0 && reconcile) {
        final currentManager = _attached;
        if (currentManager != null && currentManager.mounted) {
          currentManager._reconcileAfterStopDisarm();
        }
      }
    };
  }
}

final systemProxyCoordinator = SystemProxyCoordinator();

class ProxyManager extends ConsumerStatefulWidget {
  const ProxyManager({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState createState() => _ProxyManagerState();
}

class _ProxyManagerState extends ConsumerState<ProxyManager> {
  Future<void> _pending = Future.value();
  _AppliedProxySignature? _lastApplied;

  Future<void> _disarmNow() {
    final op = _pending.then((_) async {
      if (!mounted) return;
      if (_lastApplied == _disarmedProxySignature) return;
      try {
        if ((await proxy?.stopProxy()) ?? false) {
          _lastApplied = _disarmedProxySignature;
        } else {
          _lastApplied = null;
        }
      } catch (_) {
        _lastApplied = null;
      }
    });
    _pending = op.catchError((Object _) {});
    return op;
  }

  void _reconcileAfterStopDisarm() {
    if (!mounted) return;
    final state = ref.read(proxyStateProvider);
    if (state.isStart || _lastApplied != _disarmedProxySignature) {
      _scheduleUpdate();
    }
  }

  void _scheduleUpdate() {
    // Serialize OS mutations and read latest state after earlier work completes.
    _pending = _pending.then((_) async {
      if (!mounted) return;
      try {
        await _updateProxy(ref.read(proxyStateProvider));
      } catch (_) {
        _lastApplied = null;
        globalState.showNotifier('系统代理设置失败，请检查网络设置后重试');
      }
    });
  }

  Future<void> _updateProxy(ProxyState proxyState) async {
    final isStart =
        proxyState.isStart && !systemProxyCoordinator.isDisarmingForStop;
    final systemProxy = proxyState.systemProxy;
    final port = proxyState.port;
    if (isStart && systemProxy) {
      final pac = ref.read(pacSettingsProvider).valueOrNull;
      if (pac == null) return;
      final signature = (
        true,
        pac.enabled,
        pac.enabled ? pac.url : '',
        pac.enabled ? 0 : port,
        pac.enabled ? '' : proxyState.bassDomain.join('\u0000'),
      );
      if (_lastApplied == signature) return;
      final success = pac.enabled
          ? await proxy?.startPac(pac.url)
          : await proxy?.startProxy(port, proxyState.bassDomain);
      if (success != true) {
        _lastApplied = null;
        throw StateError('System proxy operation failed');
      }
      _lastApplied = signature;
    } else {
      if (_lastApplied == _disarmedProxySignature) return;
      if (await proxy?.stopProxy() != true) {
        _lastApplied = null;
        throw StateError('System proxy cleanup failed');
      }
      _lastApplied = _disarmedProxySignature;
    }
  }

  @override
  void initState() {
    super.initState();
    systemProxyCoordinator._attach(this);
    ref.listenManual(
      proxyStateProvider,
      (prev, next) {
        if (prev != next) {
          _scheduleUpdate();
        }
      },
      fireImmediately: true,
    );
    ref.listenManual(pacSettingsProvider, (_, next) {
      if (next.hasValue) _scheduleUpdate();
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    systemProxyCoordinator._detach(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

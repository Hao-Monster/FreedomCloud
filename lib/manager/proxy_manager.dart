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

class ProxyManager extends ConsumerStatefulWidget {
  const ProxyManager({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState createState() => _ProxyManagerState();
}

class _ProxyManagerState extends ConsumerState<ProxyManager> {
  Future<void> _pending = Future.value();
  _AppliedProxySignature? _lastApplied;

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
    final isStart = proxyState.isStart;
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
      const signature = (false, false, '', 0, '');
      if (_lastApplied == signature) return;
      if (await proxy?.stopProxy() != true) {
        _lastApplied = null;
        throw StateError('System proxy cleanup failed');
      }
      _lastApplied = signature;
    }
  }

  @override
  void initState() {
    super.initState();
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
  Widget build(BuildContext context) => widget.child;
}

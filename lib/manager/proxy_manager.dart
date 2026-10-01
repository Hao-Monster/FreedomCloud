import 'package:flclashx/common/proxy.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/state.dart';
import 'package:flclashx/providers/pac.dart';
import 'package:flclashx/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ProxyManager extends ConsumerStatefulWidget {

  const ProxyManager({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState createState() => _ProxyManagerState();
}

class _ProxyManagerState extends ConsumerState<ProxyManager> {
  Future<void> _pending = Future.value();

  void _scheduleUpdate() {
    // Serialize OS mutations and read latest state after earlier work completes.
    _pending = _pending.then((_) async {
      if (!mounted) return;
      try {
        await _updateProxy(ref.read(proxyStateProvider));
      } catch (_) {
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
      final success = pac.enabled
          ? await proxy?.startPac(pac.url)
          : await proxy?.startProxy(port, proxyState.bassDomain);
      if (success != true) throw StateError('System proxy operation failed');
    } else {
      if (await proxy?.stopProxy() != true) throw StateError('System proxy cleanup failed');
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

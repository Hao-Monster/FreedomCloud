import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flclashx/providers/network_automation.dart';
import 'package:flclashx/providers/config.dart';
import 'package:flclashx/state.dart';

class ConnectivityManager extends ConsumerStatefulWidget {

  const ConnectivityManager({
    super.key,
    this.onConnectivityChanged,
    required this.child,
  });
  final Function(List<ConnectivityResult> results)? onConnectivityChanged;
  final Widget child;

  @override
  ConsumerState<ConnectivityManager> createState() => _ConnectivityManagerState();
}

class _ConnectivityManagerState extends ConsumerState<ConnectivityManager> {
  late StreamSubscription subscription;
  Timer? _automationTimer;
  List<ConnectivityResult> _latest = const [];
  int _networkRevision = 0;

  void _scheduleAutomation() {
    _automationTimer?.cancel();
    _automationTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      final settings = ref.read(networkAutomationProvider).valueOrNull;
      if (settings == null || !settings.enabled) return;
      final available = _latest.map((result) => result.name).toSet();
      for (final type in NetworkAutomationSettings.priority) {
        if (!available.contains(type)) continue;
        final id = settings.profiles[type];
        if (id == null) continue;
        if (!ref.read(profilesProvider).any((profile) => profile.id == id)) {
          globalState.showNotifier('网络自动切换的目标配置已删除，请更新规则');
          return;
        }
        if (ref.read(currentProfileIdProvider) != id) {
          ref.read(currentProfileIdProvider.notifier).value = id;
        }
        return;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    subscription = Connectivity().onConnectivityChanged.listen((results) async {
      _networkRevision++;
      _latest = List.of(results);
      _scheduleAutomation();
      if (widget.onConnectivityChanged != null) {
        widget.onConnectivityChanged!(results);
      }
    });
    ref.listenManual(networkAutomationProvider, (_, next) {
      if (next.hasValue) _scheduleAutomation();
    }, fireImmediately: true);
    final revision = _networkRevision;
    Connectivity().checkConnectivity().then((results) {
      if (!mounted || revision != _networkRevision) return;
      _latest = List.of(results);
      _scheduleAutomation();
    }).catchError((Object _) {
      if (mounted) globalState.showNotifier('无法读取网络环境，自动切换等待下一次网络变化');
    });
  }

  @override
  void dispose() {
    subscription.cancel();
    _automationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

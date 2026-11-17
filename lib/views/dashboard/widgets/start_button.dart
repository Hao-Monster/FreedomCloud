import 'dart:async';
import 'dart:io';

import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/widgets/tactile_proxy_switch.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class StartButton extends ConsumerStatefulWidget {
  const StartButton({
    super.key,
    this.floating = false,
  });

  final bool floating;

  @override
  ConsumerState<StartButton> createState() => _StartButtonState();
}

class _StartButtonState extends ConsumerState<StartButton> {
  bool _localPending = false;
  bool? _localTargetStart;

  Future<void> handleSwitchStart() async {
    final providerPending = ref.read(statusSwitchPendingProvider);
    final startCancelable = ref.read(statusStartCancelableProvider);
    if (providerPending != null) {
      if (providerPending && startCancelable) {
        if (Platform.isAndroid) {
          unawaited(HapticFeedback.mediumImpact());
        }
        if (globalState.isAppControllerReady) {
          await globalState.appController.updateStatus(false);
        }
      }
      return;
    }
    if (_localPending || !globalState.isAppControllerReady) {
      return;
    }
    if (Platform.isAndroid) {
      unawaited(HapticFeedback.mediumImpact());
    }
    final isRunning = ref.read(runTimeProvider) != null;
    final targetStart = !isRunning;
    setState(() {
      _localPending = true;
      _localTargetStart = targetStart;
    });
    try {
      await globalState.appController.updateStatus(targetStart);
    } finally {
      if (mounted) {
        setState(() {
          _localPending = false;
          _localTargetStart = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(startButtonSelectorStateProvider);
    if (!state.isInit || !state.hasProfile) {
      return const SizedBox.shrink();
    }
    final providerPending = ref.watch(statusSwitchPendingProvider);
    final startCancelable = ref.watch(statusStartCancelableProvider);
    final effectiveStart = ref.watch(
      runTimeProvider.select((value) => value != null),
    );
    final pendingTarget =
        providerPending ?? (_localPending ? _localTargetStart : null);

    final dock = FloatingProxyDock(
      key: const ValueKey('dashboard-floating-proxy-dock'),
      surfaceKey: const ValueKey('dashboard-floating-proxy-dock-surface'),
      switchKey: const ValueKey('dashboard-proxy-toggle'),
      railKey: const ValueKey('dashboard-proxy-toggle-rail'),
      thumbKey: const ValueKey('dashboard-proxy-toggle-thumb'),
      isRunning: effectiveStart,
      pendingTarget: pendingTarget,
      startCancelable: startCancelable,
      onToggle: () => unawaited(handleSwitchStart()),
    );

    if (widget.floating) {
      return dock;
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        widthFactor: 1.0,
        heightFactor: 1.0,
        child: dock,
      ),
    );
  }
}

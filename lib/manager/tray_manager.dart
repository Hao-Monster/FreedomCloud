import 'dart:async';
import 'dart:io';

import 'package:flclashx/common/common.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/providers/tun.dart';
import 'package:flclashx/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';

final _tunTrayStateProvider = Provider(
  (ref) => ref.watch(tunRuntimeProvider).displayState,
);

class TrayManager extends ConsumerStatefulWidget {
  const TrayManager({
    super.key,
    required this.child,
  });
  final Widget child;

  @override
  ConsumerState<TrayManager> createState() => _TrayContainerState();
}

class _TrayContainerState extends ConsumerState<TrayManager>
    with TrayListener, WidgetsBindingObserver {
  bool _openingMenu = false;
  DateTime? _lastRateUpdate;

  @override
  void initState() {
    super.initState();
    tray.selectProfile = (id) {
      ref.read(currentProfileIdProvider.notifier).value = id;
    };
    StatusBarManager.setMenuRefresh(() async {
      await tray.update(trayState: ref.read(trayStateProvider));
    });
    trayManager.addListener(this);
    WidgetsBinding.instance.addObserver(this);
    ref.listenManual(trafficsProvider, (_, next) {
      final now = DateTime.now();
      if (_lastRateUpdate != null &&
          now.difference(_lastRateUpdate!) < const Duration(seconds: 2)) return;
      _lastRateUpdate = now;
      unawaited(tray.updateTrayTitle(next.list.lastOrNull));
    });
    ref.listenManual(
      trayStateProvider,
      (prev, next) {
        if (prev != next) {
          unawaited(globalState.appController.updateTray());
        }
      },
    );
    ref.listenManual(_tunTrayStateProvider, (prev, next) {
      if (prev != next) {
        unawaited(globalState.appController.updateTray());
      }
    });
  }

  @override
  void didChangePlatformBrightness() {
    unawaited(globalState.appController.updateTray());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(globalState.appController.updateTray());
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void onTrayIconRightMouseDown() {
    unawaited(_openContextMenu());
  }

  Future<void> _openContextMenu() async {
    if (_openingMenu) return;
    _openingMenu = true;
    try {
      await tray.update(trayState: ref.read(trayStateProvider));
      if (!mounted) return;
      // Theme configuration is process-scoped. Native TrackPopupMenu owns the
      // popup lifetime and closes it on selection/cancel/outside click.
      windows?.enableDarkModeForApp();
      await trayManager.popUpContextMenu();
    } catch (error) {
      commonPrint.log('Tray popup failed: $error');
    } finally {
      _openingMenu = false;
    }
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    render?.active();
    super.onTrayMenuItemClick(menuItem);
  }

  @override
  void onTrayIconMouseDown() {
    if (!Platform.isLinux) {
      unawaited(window?.show());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    StatusBarManager.setMenuRefresh(null);
    tray.selectProfile = null;
    trayManager.removeListener(this);
    super.dispose();
  }
}

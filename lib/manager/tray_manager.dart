import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:win32/win32.dart';

class TrayManager extends ConsumerStatefulWidget {
  const TrayManager({
    super.key,
    required this.child,
  });
  final Widget child;

  @override
  ConsumerState<TrayManager> createState() => _TrayContainerState();
}

class _TrayContainerState extends ConsumerState<TrayManager> with TrayListener, WidgetsBindingObserver {
  Timer? _menuMonitor;
  DateTime? _lastRateUpdate;

  void _closeWindowsPopupMenu() {
    if (!Platform.isWindows) return;

    try {
      final className = '#32768'.toNativeUtf16();
      final hwnd = FindWindow(className, nullptr);

      if (hwnd != 0) {
        PostMessage(hwnd, WM_CLOSE, 0, 0);
      }

      calloc.free(className);
    } catch (_) {
      // FFI menu detection may fail
    }

    _stopMenuMonitor();
  }

  void _startMenuMonitor() {
    if (!Platform.isWindows) return;

    _menuMonitor?.cancel();
    var themeApplied = false;
    var waitCycles = 0;

    _menuMonitor = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      try {
        final className = '#32768'.toNativeUtf16();
        final hwnd = FindWindow(className, nullptr);
        calloc.free(className);

        if (hwnd == 0) {
          _stopMenuMonitor();
          return;
        }

        if (IsWindowVisible(hwnd) == 0) {
          _stopMenuMonitor();
          return;
        }

        if (!themeApplied) {
          windows?.applyDarkModeToMenu(hwnd);
          themeApplied = true;
        }

        if (waitCycles < 3) {
          waitCycles++;
          return;
        }

        // Native menus dismiss on outside clicks. A submenu can lie outside
        // the parent rectangle, so manually closing here breaks node selection.
      } catch (e) {
        _stopMenuMonitor();
      }
    });
  }

  void _stopMenuMonitor() {
    _menuMonitor?.cancel();
    _menuMonitor = null;
  }

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
          globalState.appController.updateTray();
        }
      },
    );
  }

  @override
  void didChangePlatformBrightness() {
    globalState.appController.updateTray();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      globalState.appController.updateTray();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void onTrayIconRightMouseDown() {
    unawaited(_openContextMenu());
  }

  Future<void> _openContextMenu() async {
    await tray.update(trayState: ref.read(trayStateProvider));
    if (!mounted) return;
    await trayManager.popUpContextMenu();
    _startMenuMonitor();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    render?.active();
    _closeWindowsPopupMenu();
    super.onTrayMenuItemClick(menuItem);
  }

  @override
  void onTrayIconMouseDown() {
    _closeWindowsPopupMenu();
    if (!Platform.isLinux) {
      window?.show();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopMenuMonitor();
    StatusBarManager.setMenuRefresh(null);
    tray.selectProfile = null;
    trayManager.removeListener(this);
    super.dispose();
  }
}

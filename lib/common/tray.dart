import 'dart:async';
import 'dart:io';

import 'package:flclashx/common/system.dart';
import 'package:flclashx/views/proxies/common.dart';
import 'package:flclashx/common/utils.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:tray_manager/tray_manager.dart';

import 'app_localizations.dart';
import 'constant.dart';
import 'window.dart';
import 'statusbar.dart';

class Tray {
  void Function(String)? selectProfile;

  Future<void> _selectProxy(Group group, String name) async {
    try {
      final controller = globalState.appController;
      await controller.changeProxy(groupName: group.name, proxyName: name);
      controller.updateCurrentSelectedMap(group.name, name);
      await controller.updateGroups();
    } catch (error) {
      globalState.showNotifier(error.toString());
    }
  }

  String _nodeLabel(Group group, Proxy proxy) {
    final controller = globalState.appController;
    final state = controller.getProxyCardState(proxy.name);
    final url = state.testUrl == null || state.testUrl!.isEmpty
        ? controller.getRealTestUrl(group.testUrl)
        : state.testUrl!;
    final delay = globalState.appState.delayMap[url]?[state.proxyName];
    final value = delay == null ? '—' : delay == 0 ? '…' : delay < 0 ? 'Timeout' : '$delay ms';
    return '${proxy.name} · $value';
  }

  Future _updateSystemTray({
    required Brightness? brightness,
    required bool isRunning,
    bool force = false,
  }) async {
    if (Platform.isAndroid || Platform.isMacOS) {
      // Skip tray on Android and macOS (macOS uses native status bar)
      return;
    }
    if (Platform.isLinux || force) {
      await trayManager.destroy();
    }
    await trayManager.setIcon(
      utils.getTrayIconPath(
        brightness: brightness ??
            WidgetsBinding.instance.platformDispatcher.platformBrightness,
        isRunning: isRunning,
        isSystemDark: Platform.isWindows ? system.isWindowsSystemDark : null,
      ),
      isTemplate: true,
    );
    if (!Platform.isLinux) {
      await trayManager.setToolTip(
        appName,
      );
    }
  }

  Future<void> update({
    required TrayState trayState,
    bool focus = false,
  }) async {
    if (Platform.isAndroid) {
      // Android has no desktop tray.
      return;
    }
    if (!Platform.isLinux) {
      await _updateSystemTray(
        brightness: trayState.brightness,
        isRunning: trayState.isStart,
        force: focus,
      );
    }
    final menuItems = <MenuItem>[];
    final showMenuItem = MenuItem(
      key: 'show',
      label: appLocalizations.show,
      onClick: (_) {
        window?.show();
      },
    );
    menuItems.add(showMenuItem);
    final profiles = globalState.config.profiles;
    if (profiles.isNotEmpty && selectProfile != null) {
      menuItems.add(MenuItem.submenu(
        label: appLocalizations.profiles,
        submenu: Menu(items: [
          for (final profile in profiles)
            MenuItem.checkbox(
              label: profile.label == null || profile.label!.isEmpty ? profile.id : profile.label!,
              checked: profile.id == globalState.config.currentProfileId,
              onClick: (_) => selectProfile?.call(profile.id),
            ),
        ]),
      ));
    }
    if (trayState.isStart) {
      final traffic = globalState.appState.traffics.list.lastOrNull;
      if (traffic != null) {
        menuItems.add(MenuItem(
          label: '↑ ${traffic.up.show}/s  ↓ ${traffic.down.show}/s',
          disabled: true,
        ));
      }
      for (final group in trayState.groups.where((group) => group.hidden != true)) {
        final selected = group.getCurrentSelectedName(trayState.selectedMap[group.name] ?? '');
        final selectable = group.type == GroupType.Selector || group.type.isComputedSelected;
        menuItems.add(MenuItem.submenu(
          label: '${group.name} → $selected',
          submenu: Menu(items: [
            MenuItem(
              label: appLocalizations.delay,
              onClick: (_) async {
                await delayTest(group.all, group.testUrl);
                await globalState.appController.updateTray();
              },
            ),
            MenuItem.separator(),
            for (final proxy in group.all)
              MenuItem.checkbox(
                label: _nodeLabel(group, proxy),
                checked: selected == proxy.name,
                disabled: !selectable,
                onClick: (_) => unawaited(_selectProxy(group, proxy.name)),
              ),
          ]),
        ));
      }
    }
    final startMenuItem = MenuItem.checkbox(
      label: trayState.isStart ? appLocalizations.stop : appLocalizations.start,
      onClick: (_) async {
        globalState.appController.updateStart();
      },
      checked: false,
    );
    menuItems.add(startMenuItem);
    if (trayState.globalModeEnabled) {
      menuItems.add(MenuItem.separator());
      for (final mode in Mode.values) {
        menuItems.add(
          MenuItem.checkbox(
            label: Intl.message(mode.name),
            onClick: (_) {
              globalState.appController.changeMode(mode);
            },
            checked: mode == trayState.mode,
          ),
        );
      }
    }
    menuItems.add(MenuItem.separator());
    if (trayState.isStart) {
      menuItems.add(
        MenuItem.checkbox(
          label: appLocalizations.tun,
          onClick: (_) {
            globalState.appController.updateTun();
          },
          checked: trayState.tunEnable,
        ),
      );
      menuItems.add(
        MenuItem.checkbox(
          label: appLocalizations.systemProxy,
          onClick: (_) {
            globalState.appController.updateSystemProxy();
          },
          checked: trayState.systemProxy,
        ),
      );
      menuItems.add(MenuItem.separator());
    }
    final autoStartMenuItem = MenuItem.checkbox(
      label: appLocalizations.autoLaunch,
      onClick: (_) async {
        globalState.appController.updateAutoLaunch();
      },
      checked: trayState.autoLaunch,
    );
    final copyEnvVarMenuItem = MenuItem(
      label: appLocalizations.copyEnvVar,
      onClick: (_) async {
        await _copyEnv(trayState.port);
      },
    );
    menuItems.add(autoStartMenuItem);
    menuItems.add(copyEnvVarMenuItem);
    menuItems.add(MenuItem.separator());
    final restartMenuItem = MenuItem(
      label: appLocalizations.restart,
      onClick: (_) async {
        await globalState.appController.handleRestart();
      },
    );
    menuItems.add(restartMenuItem);
    final exitMenuItem = MenuItem(
      label: appLocalizations.exit,
      onClick: (_) async {
        await globalState.appController.handleExit();
      },
    );
    menuItems.add(exitMenuItem);
    final menu = Menu(items: menuItems);
    if (Platform.isMacOS) {
      await StatusBarManager.updateMenu(menu);
    } else {
      await trayManager.setContextMenu(menu);
    }
    if (Platform.isLinux) {
      await _updateSystemTray(
        brightness: trayState.brightness,
        isRunning: trayState.isStart,
        force: focus,
      );
    }
  }

  Future<void> updateTrayTitle([Traffic? traffic]) async {
    if (traffic == null) return;
    if (Platform.isMacOS) {
      await StatusBarManager.updateRates('↑ ${traffic.up.show}/s ↓ ${traffic.down.show}/s');
      return;
    }
    if (!Platform.isWindows) return;
    await trayManager.setToolTip(
      '$appName · ↑ ${traffic.up.show}/s ↓ ${traffic.down.show}/s',
    );
  }


  Future<void> _copyEnv(int port) async {
    final url = "http://127.0.0.1:$port";

    final cmdline = Platform.isWindows
        ? "set \$env:all_proxy=$url"
        : "export all_proxy=$url";

    await Clipboard.setData(
      ClipboardData(
        text: cmdline,
      ),
    );
  }
}

final tray = Tray();

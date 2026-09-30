import 'dart:io';
import 'package:flutter/services.dart';
import 'package:tray_manager/tray_manager.dart';

class StatusBarManager {
  static const MethodChannel _channel = MethodChannel('status_bar_icon');
  static final List<Menu> _menus = [];

  static void setMenuRefresh(Future<void> Function()? refresh) {
    if (!Platform.isMacOS) return;
    _channel.setMethodCallHandler(refresh == null ? null : (call) async {
      if (call.method == 'refreshMenu') {
        await refresh();
      } else if (call.method == 'menuAction' && call.arguments is int) {
        for (final menu in _menus.reversed) {
          final item = menu.getMenuItemById(call.arguments as int);
          if (item == null) continue;
          if (!item.disabled) item.onClick?.call(item);
          break;
        }
      }
    });
    if (refresh == null) _menus.clear();
  }

  static Future<void> updateMenu(Menu menu) async {
    if (!Platform.isMacOS) return;
    _menus.add(menu);
    if (_menus.length > 2) _menus.removeAt(0);
    await _channel.invokeMethod('updateMenu', menu.toJson());
  }

  static Future<void> updateRates(String text) async {
    if (!Platform.isMacOS) return;
    await _channel.invokeMethod('updateRates', text);
  }


  static Future<void> updateIcon({required bool isConnected}) async {
    if (!Platform.isMacOS) return;

    try {
      await _channel.invokeMethod('updateIcon', {
        'isConnected': isConnected,
      });
    } catch (e) {
      // silent
    }
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:menu_base/menu_base.dart';
import 'package:path/path.dart' as path;
import 'package:shortid/shortid.dart';
import 'package:tray_manager/src/helpers/sandbox.dart';
import 'package:tray_manager/src/tray_listener.dart';

const kEventOnTrayIconMouseDown = 'onTrayIconMouseDown';
const kEventOnTrayIconMouseUp = 'onTrayIconMouseUp';
const kEventOnTrayIconRightMouseDown = 'onTrayIconRightMouseDown';
const kEventOnTrayIconRightMouseUp = 'onTrayIconRightMouseUp';
const kEventOnTrayMenuItemClick = 'onTrayMenuItemClick';

enum TrayIconPosition { left, right }

class TrayManager {
  TrayManager._() {
    _channel.setMethodCallHandler(_methodCallHandler);
  }

  /// The shared instance of [TrayManager].
  static final TrayManager instance = TrayManager._();

  final MethodChannel _channel = const MethodChannel('tray_manager');

  final ObserverList<TrayListener> _listeners = ObserverList<TrayListener>();

  double get _devicePixelRatio {
    final flutterView = WidgetsBinding.instance.platformDispatcher.views.single;
    return MediaQueryData.fromView(flutterView).devicePixelRatio;
  }

  Menu? _menu;
  Future<void> _windowsMenuQueue = Future<void>.value();
  int _windowsSettersPending = 0;
  bool _windowsPopupInProgress = false;

  Future<T> _enqueueWindowsMenuOperation<T>(Future<T> Function() operation) {
    final result = _windowsMenuQueue.then((_) => operation());
    // Keep later operations runnable while returning the real error to this
    // operation's caller.
    _windowsMenuQueue =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> _dispatchMenuClick(int id, Menu? menu) async {
    final menuItem = menu?.getMenuItemById(id);
    if (menuItem == null) return;
    for (final listener in _listeners) {
      final oldChecked = menuItem.checked;
      menuItem.onClick?.call(menuItem);
      listener.onTrayMenuItemClick(menuItem);
      if (oldChecked != menuItem.checked &&
          identical(_menu, menu) &&
          _windowsSettersPending == 0) {
        await setContextMenu(menu!);
      }
    }
  }

  Future<void> _methodCallHandler(MethodCall call) async {
    for (final TrayListener listener in _listeners) {
      switch (call.method) {
        case kEventOnTrayIconMouseDown:
          listener.onTrayIconMouseDown();
          break;
        case kEventOnTrayIconMouseUp:
          listener.onTrayIconMouseUp();
          break;
        case kEventOnTrayIconRightMouseDown:
          listener.onTrayIconRightMouseDown();
          break;
        case kEventOnTrayIconRightMouseUp:
          listener.onTrayIconRightMouseUp();
          break;
        case kEventOnTrayMenuItemClick:
          final id = call.arguments['id'] as int;
          final menuItem = _menu?.getMenuItemById(id);
          if (menuItem != null) {
            final oldChecked = menuItem.checked;
            menuItem.onClick?.call(menuItem);
            listener.onTrayMenuItemClick(menuItem);
            if (oldChecked != menuItem.checked) {
              await setContextMenu(_menu!);
            }
          }
          break;
      }
    }
  }

  /// Whether any listeners are currently registered.
  bool get hasListeners {
    return _listeners.isNotEmpty;
  }

  /// Register a closure to be called when the tray events.
  void addListener(TrayListener listener) {
    _listeners.add(listener);
  }

  /// Remove a previously registered closure from the list of closures that are
  /// notified when the tray events.
  void removeListener(TrayListener listener) {
    _listeners.remove(listener);
  }

  // Destroys the tray icon immediately.
  Future<void> destroy() async {
    await _channel.invokeMethod('destroy');
  }

  /// Sets the image associated with this tray icon.
  ///
  /// [iconPath] is the path to the image file.
  ///
  /// However, if the app is running in a sandbox like Flatpak or Snap,
  /// [iconPath] should be the name of the icon as specified in the app's
  /// manifest file, without the path or file extension. For example, if the
  /// icon is specified as `org.example.app` in the Flatpak manifest file, then
  /// the icon should be passed as `org.example.app`.
  Future<void> setIcon(
    String iconPath, {
    bool isTemplate = false, // macOS only
    TrayIconPosition iconPosition = TrayIconPosition.left, // macOS only
    int iconSize = 18, // macOS only
  }) async {
    final Map<String, dynamic> arguments = {
      'id': shortid.generate(),
      'iconPath': path.joinAll([
        path.dirname(Platform.resolvedExecutable),
        'data/flutter_assets',
        iconPath,
      ]),
      'isTemplate': isTemplate,
      'iconPosition': iconPosition.name,
      'iconSize': iconSize,
    };

    switch (defaultTargetPlatform) {
      case TargetPlatform.linux:
        if (runningInSandbox()) {
          // Pass the icon name as specified if running in a sandbox.
          //
          // This is required because when running in a sandbox, paths are not
          // the same as seen by the app and the host system.
          arguments['iconPath'] = iconPath;
        }
        break;
      case TargetPlatform.macOS:
        // Add the icon as base64 string
        ByteData imageData = await rootBundle.load(iconPath);
        String base64Icon = base64Encode(imageData.buffer.asUint8List());
        arguments['base64Icon'] = base64Icon;
        break;
      default:
        break;
    }

    await _channel.invokeMethod('setIcon', arguments);
  }

  /// Sets the icon position of the tray icon.
  ///
  /// @platforms macos
  Future<void> setIconPosition(TrayIconPosition trayIconPosition) async {
    final arguments = <String, dynamic>{
      'iconPosition': trayIconPosition.name,
    };
    await _channel.invokeMethod('setIconPosition', arguments);
  }

  /// Sets the hover text for this tray icon.
  ///
  /// Must be called after the icon is set.
  /// ```dart
  /// await trayManager.setIcon(...);
  /// await trayManager.setToolTip(...);
  /// ```
  Future<void> setToolTip(String toolTip) async {
    final Map<String, dynamic> arguments = {
      'toolTip': toolTip,
    };
    await _channel.invokeMethod('setToolTip', arguments);
  }

  /// Sets the title for this tray icon.
  Future<void> setTitle(String title) async {
    final Map<String, dynamic> arguments = {
      'title': title,
    };
    await _channel.invokeMethod('setTitle', arguments);
  }

  /// Sets the context menu for this icon.
  Future<void> setContextMenu(Menu menu) async {
    final Map<String, dynamic> arguments = {
      'menu': menu.toJson(),
    };
    if (defaultTargetPlatform != TargetPlatform.windows) {
      _menu = menu;
      await _channel.invokeMethod('setContextMenu', arguments);
      return;
    }
    _windowsSettersPending++;
    await _enqueueWindowsMenuOperation<void>(() async {
      try {
        await _channel.invokeMethod('setContextMenu', arguments);
        _menu = menu;
      } finally {
        _windowsSettersPending--;
      }
    });
  }

  /// Pops up the context menu of the tray icon.
  ///
  /// [bringAppToFront] If true, the app will be brought to the front when the
  /// context menu is shown. Only works on Windows.
  Future<void> popUpContextMenu({
    @Deprecated(
      'This parameter is only supported on Windows and will be removed in the future.',
    )
    bool bringAppToFront = false,
  }) async {
    final Map<String, dynamic> arguments = {
      'bringAppToFront': bringAppToFront,
    };
    if (defaultTargetPlatform != TargetPlatform.windows) {
      await _channel.invokeMethod('popUpContextMenu', arguments);
      return;
    }
    if (_windowsPopupInProgress) {
      throw PlatformException(
        code: 'menu_unavailable',
        message: 'A menu is already being displayed.',
      );
    }
    _windowsPopupInProgress = true;
    try {
      Menu? displayedMenu;
      int? selectedId;
      Object? popupError;
      StackTrace? popupStack;
      late Future<void> popupCompletion;
      // Capture the installed menu and send the popup in the same FIFO slot.
      // Release that slot after dispatch so background setters can still run
      // while the native popup is tracking its immutable displayed tree.
      await _enqueueWindowsMenuOperation<void>(() async {
        displayedMenu = _menu;
        popupCompletion = _channel
            .invokeMethod<int>(
          'popUpContextMenu',
          arguments,
        )
            .then<void>((id) {
          selectedId = id;
        }, onError: (Object error, StackTrace stackTrace) {
          popupError = error;
          popupStack = stackTrace;
        });
      });
      await popupCompletion;
      if (popupError != null) {
        Error.throwWithStackTrace(popupError!, popupStack!);
      }
      if (selectedId != null && selectedId != 0) {
        await _dispatchMenuClick(selectedId!, displayedMenu);
      }
    } finally {
      _windowsPopupInProgress = false;
    }
  }

  /// The bounds of this tray icon.
  Future<Rect?> getBounds() async {
    final Map<String, dynamic> arguments = {
      'devicePixelRatio': _devicePixelRatio,
    };
    final Map<dynamic, dynamic>? resultData = await _channel.invokeMethod(
      'getBounds',
      arguments,
    );
    if (resultData == null) {
      return null;
    }
    return Rect.fromLTWH(
      resultData['x'],
      resultData['y'],
      resultData['width'],
      resultData['height'],
    );
  }
}

final trayManager = TrayManager.instance;

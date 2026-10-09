import 'dart:io';

import 'package:flutter/widgets.dart';

/// Losing desktop keyboard focus alone is not backgrounding: a tray popup can
/// temporarily take focus while visible consumers still need live samples.
class UiActivity extends ValueNotifier<bool> {
  UiActivity({this.inactiveIsHidden = false}) : super(true);

  final bool inactiveIsHidden;
  bool _visible = true;
  bool _minimized = false;
  AppLifecycleState? _lifecycle;
  int _epoch = 0;
  int get epoch => _epoch;

  void setVisible(bool visible) {
    _visible = visible;
    _update();
  }

  void setMinimized(bool minimized) {
    _minimized = minimized;
    _update();
  }

  void setLifecycle(AppLifecycleState state) {
    _lifecycle = state;
    _update();
  }

  void _update() {
    final lifecycleVisible = switch (_lifecycle) {
      AppLifecycleState.hidden ||
      AppLifecycleState.paused ||
      AppLifecycleState.detached =>
        false,
      AppLifecycleState.inactive => !inactiveIsHidden,
      _ => true,
    };
    final active = _visible && !_minimized && lifecycleVisible;
    if (active == value) return;
    _epoch++;
    value = active;
  }
}

final uiActivity = UiActivity(inactiveIsHidden: Platform.isAndroid);

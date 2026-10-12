import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Kept-alive pages explicitly release icon consumers when they leave view.
/// Root overlays have no page scope and use the shared window activity instead.
class ProcessIconActivityScope
    extends InheritedNotifier<ValueListenable<bool>> {
  const ProcessIconActivityScope({
    super.key,
    required ValueListenable<bool> activity,
    required super.child,
  }) : super(notifier: activity);

  static bool isActive(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ProcessIconActivityScope>()
          ?.notifier
          ?.value ??
      true;
}

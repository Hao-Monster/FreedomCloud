import 'dart:io';

import 'package:flclashx/common/tun_config_update.dart';
import 'package:flclashx/common/tun_runtime.dart';
import 'package:flclashx/providers/state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shared by ClashManager and its controlled controller integration fixture.
/// Keeping the subscription here tests the actual synchronous provider boundary.
class ClashConfigUpdateListener extends ConsumerStatefulWidget {
  const ClashConfigUpdateListener(
      {super.key,
      required this.child,
      required this.runtime,
      required this.onConfigChanged,
      this.isWindows});
  final Widget child;
  final TunRuntimeController runtime;
  final VoidCallback onConfigChanged;
  final bool? isWindows;
  @override
  ConsumerState<ClashConfigUpdateListener> createState() =>
      _ClashConfigUpdateListenerState();
}

class _ClashConfigUpdateListenerState
    extends ConsumerState<ClashConfigUpdateListener> {
  late int _observedIntent;
  @override
  void initState() {
    super.initState();
    _observedIntent = widget.runtime.intentRevision;
    ref.listenManual(updateParamsProvider, (previous, next) {
      final intent = widget.runtime.intentRevision;
      // A derived Riverpod provider can deliver its notification after the
      // operation finished. Keep ownership until that intent is observed;
      // a busy flag alone would re-apply after cancelled authorization.
      final ownsTunChange = widget.runtime.busy ||
          (_observedIntent != intent &&
              next.tun.enable == widget.runtime.desiredEnabled);
      _observedIntent = intent;
      if (shouldScheduleClashConfigUpdate(previous, next,
          explicitWindowsTunOperation:
              (widget.isWindows ?? Platform.isWindows) && ownsTunChange)) {
        widget.onConfigChanged();
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

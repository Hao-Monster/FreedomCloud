import 'package:flclashx/common/app_localizations.dart';
import 'package:flclashx/common/tun_runtime.dart';
import 'package:flutter/material.dart';

String tunStatusLabel(TunRuntimeController runtime, {bool waiting = false}) {
  if (runtime.operation == TunOperation.enabling)
    return appLocalizations.tunStatusStarting;
  if (runtime.operation == TunOperation.disabling)
    return appLocalizations.tunStatusStopping;
  if (runtime.failure != null) {
    final reason = switch (runtime.failure) {
      'permissionDenied' ||
      'authorizationRequired' =>
        appLocalizations.tunErrorAuthorization,
      'componentsMismatch' => appLocalizations.tunErrorComponents,
      'legacyAgent' => appLocalizations.tunErrorLegacyAgent,
      'backendStopFailed' || 'closeFailed' => appLocalizations.tunErrorStop,
      'statusUnavailable' ||
      'invalidStatus' =>
        appLocalizations.tunErrorUnavailable,
      'configurationFailed' => appLocalizations.tunErrorConfiguration,
      _ => appLocalizations.tunErrorStart,
    };
    return appLocalizations.tunStatusFailure(reason);
  }
  if (waiting && runtime.observed == TunObservedState.off)
    return appLocalizations.tunStatusWaiting;
  return switch (runtime.observed) {
    TunObservedState.on => appLocalizations.tunStatusOn,
    TunObservedState.off => appLocalizations.tunStatusOff,
    TunObservedState.unknown => appLocalizations.tunStatusUnknown,
  };
}

/// A shared presentation for settings and the dashboard. The checked state is
/// exclusively observed; unknown remains explicitly labelled and can be stopped.
class TunStatusSwitch extends StatelessWidget {
  const TunStatusSwitch(
      {super.key, required this.runtime, required this.onChanged});
  final TunRuntimeController runtime;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        if (!runtime.busy &&
            (runtime.observed == TunObservedState.unknown ||
                (runtime.desiredEnabled && !runtime.isEnabled)))
          IconButton(
              tooltip: appLocalizations.tunDisableAction,
              onPressed: () => onChanged(false),
              icon: const Icon(Icons.close)),
        Semantics(
            label: tunStatusLabel(runtime),
            child: Switch(
              value: runtime.isEnabled,
              onChanged: runtime.busy ? null : onChanged,
            )),
      ]);
}

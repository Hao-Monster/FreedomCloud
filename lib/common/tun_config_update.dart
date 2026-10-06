import 'package:flclashx/models/core.dart';

/// The explicit TUN transaction owns this change. Scheduling a second generic
/// update would apply configuration even after its authorization was cancelled.
bool shouldScheduleClashConfigUpdate(UpdateParams? previous, UpdateParams next,
    {required bool explicitWindowsTunOperation}) {
  if (previous == next) return false;
  if (explicitWindowsTunOperation &&
      previous != null &&
      previous.copyWith.tun(enable: next.tun.enable) == next) return false;
  return true;
}

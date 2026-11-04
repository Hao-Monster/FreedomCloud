import 'package:flclashx/common/tun_runtime.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final tunRuntimeProvider = ChangeNotifierProvider<TunRuntimeController>(
  (ref) => tunRuntime,
);

/// `null` when idle, `true` while starting proxy, `false` while stopping proxy.
final statusSwitchPendingProvider = StateProvider<bool?>((ref) => null);

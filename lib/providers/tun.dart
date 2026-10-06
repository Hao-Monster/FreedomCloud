import 'package:flclashx/common/tun_runtime.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final tunRuntimeProvider = ChangeNotifierProvider<TunRuntimeController>(
  (ref) => tunRuntime,
);

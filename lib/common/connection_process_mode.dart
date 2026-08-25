import 'dart:io';

import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/connection_tracker.dart';

bool get platformSupportsProcessLookup =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// Process cards require metadata for every connection. Mihomo's `strict`
/// mode resolves a process only when a PROCESS rule asks for it, so profiles
/// that set `strict` or `off` otherwise produce empty process cards.
FindProcessMode effectiveConnectionFindProcessMode({
  required FindProcessMode configured,
  required ConnectionListMode listMode,
  required bool supportsProcessLookup,
}) {
  if (supportsProcessLookup && listMode == ConnectionListMode.process) {
    return FindProcessMode.always;
  }
  return configured;
}

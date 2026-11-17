import 'dart:io';

import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/file_digest.dart';

class CoreUpdater {
  factory CoreUpdater() {
    _instance ??= CoreUpdater._internal();
    return _instance!;
  }

  CoreUpdater._internal();

  static CoreUpdater? _instance;

  /// SHA-256 of the core binary currently on disk. Shared with component
  /// preflight checks via [fileSha256] so repeated helper/agent checks neither
  /// rehash the binary nor block the UI isolate.
  Future<String?> calcCoreSha256() async {
    try {
      return await fileSha256(appPath.corePath);
    } catch (e) {
      commonPrint.log("calcCoreSha256 failed: $e");
      return null;
    }
  }

  /// Swap the core for a downloaded `.pending` binary. Must run before any core
  /// process is spawned: a running exe can't be deleted on Windows, and on
  /// macOS/Linux a swap after spawn leaves the whole session on the old core.
  Future<void> applyPending() async {
    final pending = File(appPath.corePendingPath);
    if (!await pending.exists()) {
      return;
    }
    // Standalone core downloads are not signed yet. Executing them as SYSTEM
    // (Windows helper) or setuid-root (macOS) turns a release-channel compromise
    // into local privilege escalation. R-206 restores this only with a signed,
    // rollback-capable update chain.
    commonPrint.log("Discarding unsigned standalone core update");
    try {
      await pending.delete();
    } catch (e) {
      commonPrint.log("Failed to discard unsigned core update: $e");
    }
  }
}

final coreUpdater = CoreUpdater();

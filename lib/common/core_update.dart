import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flclashx/common/common.dart';

class CoreUpdater {
  factory CoreUpdater() {
    _instance ??= CoreUpdater._internal();
    return _instance!;
  }

  CoreUpdater._internal();

  static CoreUpdater? _instance;

  String? _cachedHash;
  DateTime? _cachedMtime;
  int? _cachedSize;

  /// SHA-256 of the core binary currently on disk. Cached by mtime+size so
  /// repeated helper pings don't rehash the file.
  Future<String?> calcCoreSha256() async {
    try {
      final file = File(appPath.corePath);
      final stat = await file.stat();
      if (_cachedHash != null &&
          stat.modified == _cachedMtime &&
          stat.size == _cachedSize) {
        return _cachedHash;
      }
      final digest = await sha256.bind(file.openRead()).first;
      _cachedMtime = stat.modified;
      _cachedSize = stat.size;
      _cachedHash = digest.toString();
      return _cachedHash;
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

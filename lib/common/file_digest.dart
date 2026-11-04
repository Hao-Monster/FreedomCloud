// ignore_for_file: avoid_slow_async_io

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flclashx/common/bounded_cache.dart';
import 'package:path/path.dart' as p;

typedef _FileDigestKey = (String normalizedPath, int size, int modifiedMicros);

Future<String> _streamSha256Hex(String filePath) async {
  final digest = await sha256.bind(File(filePath).openRead()).first;
  return digest.toString();
}

/// Computes the SHA-256 hex digest of [filePath] on a background worker isolate.
Future<String> fileSha256InBackground(String filePath) =>
    Isolate.run(() => _streamSha256Hex(filePath));

/// Bounded, stat-keyed SHA-256 file digest cache that keeps large binary
/// hashing (`FlClashCore.exe`, `FlClashAgent.exe`, `FlClashHelperService.exe`)
/// off the Flutter UI isolate and avoids rehashing unchanged binaries on every
/// Helper/Agent preflight or poll.
class FileSha256Cache {
  FileSha256Cache({
    int maxEntries = 64,
    this.isolateThresholdBytes = 64 * 1024,
    Future<String> Function(String filePath)? computeDigest,
  })  : _cache = BoundedCache<_FileDigestKey, String>(maxEntries: maxEntries),
        _computeDigest = computeDigest ?? fileSha256InBackground;

  final int isolateThresholdBytes;
  final BoundedCache<_FileDigestKey, String> _cache;
  final Future<String> Function(String filePath) _computeDigest;
  final Map<_FileDigestKey, Future<({String digest, bool consistent})>> _inFlight = {};

  Future<String> hashFile(String filePath) async {
    final file = File(filePath);
    for (var attempt = 0; attempt < 2; attempt++) {
      final statBefore = await file.stat();
      if (statBefore.type != FileSystemEntityType.file ||
          statBefore.size < isolateThresholdBytes) {
        final bytes = await file.readAsBytes();
        return sha256.convert(bytes).toString();
      }

      final normalizedPath = Platform.isWindows
          ? p.normalize(file.absolute.path).toLowerCase()
          : p.normalize(file.absolute.path);
      final key = (
        normalizedPath,
        statBefore.size,
        statBefore.modified.microsecondsSinceEpoch,
      );

      if (_cache.containsKey(key)) {
        return _cache.putIfAbsent(key, () => '');
      }

      var future = _inFlight[key];
      if (future == null) {
        future = () async {
          final digest = await _computeDigest(file.path);
          final statAfter = await file.stat();
          final consistent = statAfter.type == FileSystemEntityType.file &&
              statAfter.size == statBefore.size &&
              statAfter.modified.microsecondsSinceEpoch ==
                  statBefore.modified.microsecondsSinceEpoch;
          if (consistent) {
            _cache.putIfAbsent(key, () => digest);
          }
          return (digest: digest, consistent: consistent);
        }();
        _inFlight[key] = future;
      }

      try {
        final outcome = await future;
        if (outcome.consistent) {
          return outcome.digest;
        }
      } finally {
        if (identical(_inFlight[key], future)) {
          final _ = _inFlight.remove(key);
        }
      }
    }

    // If the file is still actively changing after a bounded retry, return a
    // fresh digest without inserting a potentially torn entry into `_cache`.
    return _computeDigest(file.path);
  }

  void clear() {
    _cache.clear();
  }
}

final FileSha256Cache _defaultFileSha256Cache = FileSha256Cache();

/// Keep hashing Core, Agent, and Helper binaries off the Flutter UI isolate
/// while sharing a stat-keyed cache across repeated compatibility checks.
Future<String> fileSha256(String path) =>
    _defaultFileSha256Cache.hashFile(path);

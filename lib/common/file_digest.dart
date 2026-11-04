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
  final Map<_FileDigestKey, Future<String>> _inFlight = {};

  Future<String> hashFile(String filePath) async {
    final file = File(filePath);
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file ||
        stat.size < isolateThresholdBytes) {
      final bytes = await file.readAsBytes();
      return sha256.convert(bytes).toString();
    }

    final normalizedPath = Platform.isWindows
        ? p.normalize(file.absolute.path).toLowerCase()
        : p.normalize(file.absolute.path);
    final key = (
      normalizedPath,
      stat.size,
      stat.modified.microsecondsSinceEpoch,
    );

    if (_cache.containsKey(key)) {
      return _cache.putIfAbsent(key, () => '');
    }

    final existing = _inFlight[key];
    if (existing != null) {
      return existing;
    }

    final future = _computeDigest(file.path).then((digest) {
      _cache.putIfAbsent(key, () => digest);
      return digest;
    });
    _inFlight[key] = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlight[key], future)) {
        final _ = _inFlight.remove(key);
      }
    }
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

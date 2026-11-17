// ignore_for_file: avoid_slow_async_io

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flclashx/common/bounded_cache.dart';
import 'package:path/path.dart' as p;

typedef _FileDigestKey = (String normalizedPath, int size, int modifiedMicros);

final RegExp _windowsVerbatimUncPrefix =
    RegExp(r'^(?:\\\\\?\\|//\?/)unc[\\/]', caseSensitive: false);
final RegExp _windowsVerbatimDrivePrefix = RegExp(r'^(?:\\\\\?\\|//\?/)');

/// Strips Windows extended-length verbatim prefixes (`\\?\` and `\\?\UNC\`) so
/// paths reported by Win32 / Rust `std::fs::canonicalize` match standard Dart
/// application paths.
String stripWindowsVerbatimPrefix(String filePath) {
  final uncMatch = _windowsVerbatimUncPrefix.firstMatch(filePath);
  if (uncMatch != null) {
    return r'\\' + filePath.substring(uncMatch.end);
  }
  final driveMatch = _windowsVerbatimDrivePrefix.firstMatch(filePath);
  if (driveMatch != null) {
    return filePath.substring(driveMatch.end);
  }
  return filePath;
}

/// Canonicalizes [filePath] for digest cache and identity comparison without
/// touching the filesystem.
String normalizeDigestFilePath(String filePath, {bool? isWindows}) {
  final win = isWindows ?? Platform.isWindows;
  if (win) {
    final stripped = stripWindowsVerbatimPrefix(filePath).replaceAll('/', r'\');
    final resolved = p.windows.isAbsolute(stripped)
        ? stripped
        : p.windows.join(Directory.current.path, stripped);
    return p.windows.normalize(resolved).toLowerCase();
  }
  return p.posix.normalize(File(filePath).absolute.path);
}

/// Compares two binary paths for byte-identical content.
///
/// When [expectedPath] and [actualPath] canonicalize to the exact same existing
/// regular file (for example `E:\...\FlClashCore.exe` and Rust's verbatim
/// `\\?\E:\...\FlClashCore.exe`), skips reading and hashing the file against
/// itself. Symlinks/reparse points and distinct paths still verify SHA-256.
Future<bool> binaryFilesMatch(
  String expectedPath,
  String actualPath, {
  Future<String> Function(String path)? digestOf,
  bool? isWindows,
}) async {
  final win = isWindows ?? Platform.isWindows;
  final hash = digestOf ?? fileSha256;
  if (normalizeDigestFilePath(expectedPath, isWindows: win) ==
      normalizeDigestFilePath(actualPath, isWindows: win)) {
    final checkPath = win ? stripWindowsVerbatimPrefix(expectedPath) : expectedPath;
    final entityType = await FileSystemEntity.type(checkPath, followLinks: false);
    if (entityType == FileSystemEntityType.notFound) {
      throw PathNotFoundException(
        checkPath,
        const OSError('No such file or directory', 2),
      );
    }
    if (entityType == FileSystemEntityType.file) {
      return true;
    }
  }
  final (expectedDigest, actualDigest) =
      await (hash(expectedPath), hash(actualPath)).wait;
  return expectedDigest == actualDigest;
}

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
    final effectivePath =
        Platform.isWindows ? stripWindowsVerbatimPrefix(filePath) : filePath;
    final file = File(effectivePath);
    for (var attempt = 0; attempt < 2; attempt++) {
      final statBefore = await file.stat();
      if (statBefore.type != FileSystemEntityType.file ||
          statBefore.size < isolateThresholdBytes) {
        final bytes = await file.readAsBytes();
        return sha256.convert(bytes).toString();
      }

      final normalizedPath = normalizeDigestFilePath(effectivePath);
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

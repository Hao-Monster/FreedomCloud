import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

class NodeHealthRecord {
  const NodeHealthRecord({
    required this.delayMs,
    required this.testedAt,
    required this.testUrlHash,
    this.reason,
  });

  final int delayMs;
  final DateTime testedAt;
  final String testUrlHash;
  final String? reason;

  bool isStale(DateTime now) =>
      now.difference(testedAt) > const Duration(minutes: 10);

  Map<String, Object?> toJson() => {
        'd': delayMs,
        't': testedAt.millisecondsSinceEpoch,
        'r': reason,
        'u': testUrlHash,
      };
}

/// A disposable history cache. It never retains node names, endpoints, URLs or
/// raw errors. Runtime ownership must be established by the result producer
/// before calling [record]; this store cannot infer it from a node name.
class NodeHealthStore extends ChangeNotifier {
  NodeHealthStore({
    required this.fileProvider,
    DateTime Function()? now,
    this.debounce = const Duration(seconds: 2),
    this.maxEntries = 5000,
    this.retention = const Duration(days: 7),
    this.onError,
  })  : assert(maxEntries > 0, 'Cache capacity must be positive'),
        assert(debounce >= Duration.zero, 'Debounce cannot be negative'),
        assert(retention > Duration.zero, 'Retention must be positive'),
        _now = now ?? DateTime.now;

  final Future<File> Function() fileProvider;
  final DateTime Function() _now;
  final Duration debounce;
  final int maxEntries;
  final Duration retention;
  final void Function(String code)? onError;
  final _entries = <String, Map<String, NodeHealthRecord>>{};
  static final _identityPattern = RegExp(r'^[a-f0-9]{32}$');
  static final _urlHashPattern = RegExp(r'^[a-f0-9]{16}$');
  static const _schemaVersion = 2;
  static const _measurementFailureReasons = {
    'testFailed',
    'deadlineExceeded',
  };

  Future<void>? _loading;
  Future<void> _writeTail = Future.value();
  Timer? _timer;
  File? _file;
  int _revision = 0;
  int _persistedRevision = 0;
  bool _writable = true;
  bool _loaded = false;
  bool _disposed = false;
  String? _lastErrorCode;

  String? get lastErrorCode => _lastErrorCode;

  static String hashTestUrl(String url) =>
      sha256.convert(utf8.encode(url)).toString().substring(0, 16);

  Future<void> load() => _loading ??= _load();

  NodeHealthRecord? read(String profileId, String identityKey,
      {required String testUrl}) {
    final record = _entries[profileId]?[identityKey];
    return record?.testUrlHash == hashTestUrl(testUrl) ? record : null;
  }

  Map<String, NodeHealthRecord> readProfile(String profileId,
      {required String testUrl}) {
    final hash = hashTestUrl(testUrl);
    return Map.unmodifiable({
      for (final entry in (_entries[profileId] ?? {}).entries)
        if (entry.value.testUrlHash == hash) entry.key: entry.value,
    });
  }

  Future<void> record({
    required String profileId,
    required String identityKey,
    required int delayMs,
    required String testUrl,
    String? reason,
    DateTime? testedAt,
  }) async {
    _ensureActive();
    if (!_identityPattern.hasMatch(identityKey)) {
      throw ArgumentError('Health cache requires a hashed node identity');
    }
    // Zero means in progress. Cancellation, admission and transport failures
    // say nothing about the node, so preserve its last actual measurement.
    if (delayMs == 0 ||
        (delayMs < 0 && !_measurementFailureReasons.contains(reason))) {
      return;
    }
    final timestamp = testedAt ?? _now();
    if (!_loaded) await load();
    _ensureActive();
    final previous = _entries[profileId]?[identityKey];
    if (previous != null && timestamp.isBefore(previous.testedAt)) return;
    final records = _entries.putIfAbsent(profileId, () => {});
    records[identityKey] = NodeHealthRecord(
      delayMs: delayMs < 0 ? -1 : delayMs,
      testedAt: timestamp,
      testUrlHash: hashTestUrl(testUrl),
      reason: delayMs < 0 ? reason : null,
    );
    _trim();
    _changed();
  }

  Future<void> removeProfile(String profileId) async {
    _ensureActive();
    if (!_loaded) await load();
    _ensureActive();
    if (_entries.remove(profileId) != null) _changed();
  }

  /// Explicit flush reports failures to its caller. Timer-triggered writes
  /// report only a fixed diagnostic code through [onError].
  Future<void> flush() async {
    await load();
    _timer?.cancel();
    _timer = null;
    // Serialize filesystem writes. A prior failure must not prevent a later
    // explicit retry, and each queued operation snapshots the latest revision.
    final recoveredTail = _writeTail.then<void>((_) {}, onError: (Object _) {});
    final operation = recoveredTail.then((_) => _persist());
    _writeTail = operation;
    await operation;
  }

  Future<void> _load() async {
    try {
      final file = await fileProvider();
      _file = file;
      final stat = await file.stat();
      if (stat.type == FileSystemEntityType.notFound) return;
      if (stat.type != FileSystemEntityType.file) {
        throw const FileSystemException('Health cache is not a file');
      }
      // This is comfortably above 5000 records while bounding malformed input.
      if (stat.size > 4 * 1024 * 1024) {
        throw const FormatException('Health cache exceeds its limit');
      }
      final raw = jsonDecode(await file.readAsString());
      if (_decode(raw)) _revision++;
      _trim();
      if (_entries.isNotEmpty && !_disposed) notifyListeners();
    } on FormatException {
      _entries.clear();
      await _quarantine();
    } on FileSystemException {
      _writable = false;
      _report('readFailed');
    } finally {
      _loaded = true;
    }
  }

  bool _decode(Object? raw) {
    if (raw is! Map ||
        (raw['version'] != 1 && raw['version'] != _schemaVersion) ||
        raw['entries'] is! Map) {
      throw const FormatException('Unknown health cache schema');
    }
    final legacy = raw['version'] == 1;
    var needsRewrite = legacy;
    final entries = raw['entries'] as Map;
    for (final profile in entries.entries) {
      if (profile.key is! String || profile.value is! Map) {
        throw const FormatException('Invalid health profile');
      }
      final records = <String, NodeHealthRecord>{};
      for (final node in (profile.value as Map).entries) {
        final value = node.value;
        if (node.key is! String ||
            !_identityPattern.hasMatch(node.key as String) ||
            value is! Map ||
            value['d'] is! int ||
            (value['d'] as int) == 0 ||
            (value['d'] as int) < -1 ||
            value['t'] is! int ||
            (value['t'] as int) < 0 ||
            (value['t'] as int) > 8640000000000000 ||
            value['u'] is! String ||
            !_urlHashPattern.hasMatch(value['u'] as String) ||
            (value['r'] != null && value['r'] is! String)) {
          throw const FormatException('Invalid health record');
        }
        final delay = value['d'] as int;
        final reason = value['r'] as String?;
        // V1 conflated batch/request deadlines and mapped unknown errors to
        // testFailed. No negative V1 value proves node failure, and no older
        // good value survives in this cache. Migrate those as unmeasured.
        if (delay < 0 &&
            (legacy || !_measurementFailureReasons.contains(reason))) {
          needsRewrite = true;
          continue;
        }
        if (delay > 0 && reason != null) needsRewrite = true;
        records[node.key as String] = NodeHealthRecord(
          delayMs: delay,
          testedAt: DateTime.fromMillisecondsSinceEpoch(value['t'] as int,
              isUtc: true),
          testUrlHash: value['u'] as String,
          reason: delay < 0 ? reason : null,
        );
      }
      _entries[profile.key as String] = records;
    }
    return needsRewrite;
  }

  void _trim() {
    final cutoff = _now().subtract(retention);
    for (final records in _entries.values) {
      records.removeWhere((_, record) => record.testedAt.isBefore(cutoff));
    }
    final all = [
      for (final profile in _entries.entries)
        for (final node in profile.value.entries)
          (profile.key, node.key, node.value.testedAt),
    ];
    if (all.length > maxEntries) {
      all.sort((a, b) => a.$3.compareTo(b.$3));
      for (final oldest in all.take(all.length - maxEntries)) {
        _entries[oldest.$1]?.remove(oldest.$2);
      }
    }
    _entries.removeWhere((_, entries) => entries.isEmpty);
  }

  void _changed() {
    _revision++;
    _timer?.cancel();
    _timer = Timer(debounce, () {
      _timer = null;
      unawaited(flush().then<void>((_) {}, onError: (Object _) {
        // _persist reports a fixed reason code; raw filesystem errors can
        // contain private paths and must not be logged here.
      }));
    });
    notifyListeners();
  }

  Future<void> _persist() async {
    if (_revision == _persistedRevision) return;
    if (!_writable || _file == null) {
      _report('writeFailed');
      throw StateError('Health cache is not writable');
    }
    final file = _file!;
    final pending = File('${file.path}.pending');
    final revision = _revision;
    final encoded = jsonEncode({
      'version': _schemaVersion,
      'entries': {
        for (final profile in _entries.entries)
          profile.key: {
            for (final node in profile.value.entries)
              node.key: node.value.toJson(),
          },
      },
    });
    try {
      await file.parent.create(recursive: true);
      await pending.writeAsString(encoded, flush: true);
      // File.rename replaces a destination file. Do not delete the old cache
      // before this operation: a failed write must preserve its last snapshot.
      await pending.rename(file.path);
      _persistedRevision = revision;
      _lastErrorCode = null;
    } on FileSystemException {
      _report('writeFailed');
      rethrow;
    }
  }

  Future<void> _quarantine() async {
    final file = _file;
    if (file == null) return;
    try {
      final target = '${file.path}.corrupt-${_now().millisecondsSinceEpoch}';
      await file.rename(target);
      final ownBackup = RegExp(
          '^${RegExp.escape(path.basename(file.path))}\\.corrupt-[0-9]+\$');
      await for (final entity in file.parent.list(followLinks: false)) {
        if (entity is File &&
            !path.equals(entity.path, target) &&
            ownBackup.hasMatch(path.basename(entity.path))) {
          await entity.delete();
        }
      }
      _report('corruptRecovered');
    } on FileSystemException {
      _writable = false;
      _report('corruptBackupFailed');
    }
  }

  void _report(String code) {
    _lastErrorCode = code;
    onError?.call(code);
  }

  void _ensureActive() {
    if (_disposed) throw StateError('Health cache has been disposed');
  }

  /// Cancels delayed writes. Owners should await [flush] at their asynchronous
  /// shutdown boundary; calling it after dispose is also allowed.
  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flclashx/models/node_catalog.dart';
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

class _CatalogHealthBinding {
  _CatalogHealthBinding(this.catalogId, this.profileId, this.identities);
  final String catalogId;
  final String profileId;
  final Map<int, String> identities;
  final pending = <(String, String), NodeCatalogHealthTarget>{};
  int capacityRejectedWrites = 0;
}

/// A capability for one request. Releasing/rebinding its catalog revokes it.
/// Only identity and URL hashes are retained alongside the profile ownership.
class NodeCatalogHealthTarget {
  NodeCatalogHealthTarget._(this._binding, this._identity, this._urlHash);
  final _CatalogHealthBinding _binding;
  final String _identity;
  final String _urlHash;
  (String, String) get _key => (_identity, _urlHash);
}

/// A measurement history store. It never retains node names, endpoints, URLs or
/// raw errors. Runtime ownership must be established by the result producer
/// before calling [record]; this store cannot infer it from a node name.
class NodeHealthStore extends ChangeNotifier {
  NodeHealthStore({
    required this.fileProvider,
    DateTime Function()? now,
    this.debounce = const Duration(seconds: 2),
    this.maxEntries = 5000,
    this.retention,
    this.onError,
  })  : assert(maxEntries > 0, 'Cache capacity must be positive'),
        assert(debounce >= Duration.zero, 'Debounce cannot be negative'),
        assert(retention == null || retention > Duration.zero,
            'Retention must be positive'),
        _now = now ?? DateTime.now;

  final Future<File> Function() fileProvider;
  final DateTime Function() _now;
  final Duration debounce;
  final int maxEntries;

  /// Null retains each measurement until replaced or its profile is removed.
  final Duration? retention;
  final void Function(String code)? onError;
  final _entries = <String, Map<String, NodeHealthRecord>>{};
  final _catalogBindings = <String, _CatalogHealthBinding>{};
  final _catalogWrites = <Future<void>>{};
  static final _identityPattern = RegExp(r'^[a-f0-9]{32}$');
  static final _urlHashPattern = RegExp(r'^[a-f0-9]{16}$');
  static const _schemaVersion = 2;
  static const _maxFileBytes = 4 * 1024 * 1024;
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
  bool _capacityReadOnly = false;
  bool _loaded = false;
  bool _disposed = false;
  String? _lastErrorCode;
  int _capacityRejectedWrites = 0;

  String? get lastErrorCode => _lastErrorCode;

  /// Counts rejected measurements, not repeated diagnostics or flush attempts.
  int get capacityRejectedWrites => _capacityRejectedWrites;

  /// Catalog-owned counts prevent another entry point's concurrent writes from
  /// being attributed to this batch. Releasing the binding releases its count.
  int catalogCapacityRejectedWrites(String catalogId) =>
      _catalogBindings[catalogId]?.capacityRejectedWrites ?? 0;

  int get _entryCount =>
      _entries.values.fold(0, (count, records) => count + records.length);

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

  void bindCatalog(ProfileCatalog catalog) {
    _ensureActive();
    final id = catalog.coreCatalogId;
    if (id == null ||
        id.isEmpty ||
        catalog.status != ProfileCatalogStatus.ready) {
      throw ArgumentError('A prepared catalog is required');
    }
    final indices = <int, String>{};
    final seenIndices = <int>{};
    final seenIdentities = <String>{};
    final badIndices = <int>{};
    final badIdentities = <String>{};
    for (final node in catalog.nodes) {
      final index = node.coreIndex;
      if (index == null || index < 0) continue;
      if (!seenIndices.add(index)) badIndices.add(index);
      if (!seenIdentities.add(node.identityKey)) {
        badIdentities.add(node.identityKey);
      }
      if (node.unsupported != CatalogUnsupportedReason.none ||
          !_identityPattern.hasMatch(node.identityKey)) {
        continue;
      }
      indices[index] = node.identityKey;
    }
    indices.removeWhere((index, identity) =>
        badIndices.contains(index) || badIdentities.contains(identity));
    // Rebinding the same ID must never grant a previous request new ownership.
    _catalogBindings[id] =
        _CatalogHealthBinding(id, catalog.profileId, indices);
    notifyListeners();
  }

  void unbindCatalog(String catalogId) {
    if (_catalogBindings.remove(catalogId) != null && !_disposed) {
      notifyListeners();
    }
  }

  void clearCatalogBindings() {
    if (_catalogBindings.isEmpty) return;
    _catalogBindings.clear();
    if (!_disposed) notifyListeners();
  }

  NodeCatalogHealthTarget? beginCatalogTest({
    required String catalogId,
    required int nodeIndex,
    required String identityKey,
    required String testUrl,
  }) {
    if (_disposed) return null;
    final binding = _catalogBindings[catalogId];
    if (binding == null || binding.identities[nodeIndex] != identityKey) {
      return null;
    }
    final target =
        NodeCatalogHealthTarget._(binding, identityKey, hashTestUrl(testUrl));
    binding.pending[target._key] = target;
    notifyListeners();
    return target;
  }

  bool isCatalogPending(String catalogId, String identityKey,
          {required String testUrl}) =>
      _catalogBindings[catalogId]
          ?.pending
          .containsKey((identityKey, hashTestUrl(testUrl))) ??
      false;

  Future<void> finishCatalogTest(NodeCatalogHealthTarget target, int value,
      {String? reason, DateTime? testedAt}) {
    final binding = target._binding;
    if (!_isBound(binding) ||
        !identical(binding.pending[target._key], target)) {
      return Future.value();
    }
    binding.pending.remove(target._key);
    if (!_disposed) notifyListeners();
    if (!_isMeasurement(value, reason)) return Future.value();
    final timestamp = testedAt ?? _now();
    final operation = _recordCatalog(target, value, reason, timestamp);
    _catalogWrites.add(operation);
    unawaited(operation.then<void>((_) => _catalogWrites.remove(operation),
        onError: (Object _, StackTrace __) {
      _catalogWrites.remove(operation);
      _report('recordFailed');
    }));
    return operation;
  }

  bool _isBound(_CatalogHealthBinding binding) =>
      !_disposed && identical(_catalogBindings[binding.catalogId], binding);

  Future<void> _recordCatalog(NodeCatalogHealthTarget target, int value,
      String? reason, DateTime timestamp) async {
    if (!_loaded) await load();
    // Loading crosses an async boundary: deletion/release may have happened.
    if (!_isBound(target._binding)) return;
    final rejectedBefore = _capacityRejectedWrites;
    _record(target._binding.profileId, target._identity, value, target._urlHash,
        reason, timestamp);
    target._binding.capacityRejectedWrites +=
        _capacityRejectedWrites - rejectedBefore;
  }

  Future<void> awaitCatalogWrites() async {
    while (_catalogWrites.isNotEmpty) {
      await Future.wait(_catalogWrites.toList());
    }
  }

  static bool _isMeasurement(int value, String? reason) =>
      value > 0 || (value < 0 && _measurementFailureReasons.contains(reason));

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
    if (!_isMeasurement(delayMs, reason)) {
      return;
    }
    final timestamp = testedAt ?? _now();
    if (!_loaded) await load();
    _ensureActive();
    _record(profileId, identityKey, delayMs, hashTestUrl(testUrl), reason,
        timestamp);
  }

  void _record(String profileId, String identityKey, int delayMs,
      String urlHash, String? reason, DateTime timestamp) {
    // A larger snapshot may contain records outside the in-memory view. Never
    // replace that file with a partial view, even when updating a known key.
    if (_capacityReadOnly) {
      _capacityRejectedWrites++;
      _report('capacityExceeded');
      return;
    }
    final previous = _entries[profileId]?[identityKey];
    if (previous != null && timestamp.isBefore(previous.testedAt)) return;
    if (previous == null && _entryCount >= maxEntries) {
      _capacityRejectedWrites++;
      _report('capacityExceeded');
      return;
    }
    final records = _entries.putIfAbsent(profileId, () => {});
    records[identityKey] = NodeHealthRecord(
      delayMs: delayMs < 0 ? -1 : delayMs,
      testedAt: timestamp,
      testUrlHash: urlHash,
      reason: delayMs < 0 ? reason : null,
    );
    _trim();
    _changed();
  }

  Future<void> removeProfile(String profileId) async {
    _ensureActive();
    final removed = _catalogBindings.values
        .where((binding) => binding.profileId == profileId)
        .map((binding) => binding.catalogId)
        .toList();
    removed.forEach(_catalogBindings.remove);
    if (removed.isNotEmpty) notifyListeners();
    if (!_loaded) await load();
    _ensureActive();
    if (_entries.remove(profileId) != null) {
      if (!_capacityReadOnly && _lastErrorCode == 'capacityExceeded') {
        _lastErrorCode = null;
      }
      _changed();
    }
  }

  /// Explicit flush reports failures to its caller. Timer-triggered writes
  /// report only a fixed diagnostic code through [onError].
  Future<void> flush() async {
    await awaitCatalogWrites();
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
      if (stat.size > _maxFileBytes) {
        throw const FileSystemException('Health cache exceeds its read limit');
      }
      // Bound the actual read as well: the file can grow after stat(). A size
      // limit is not proof of corruption, so preserve oversized files intact.
      final bytes = await file
          .openRead(0, _maxFileBytes + 1)
          .fold<BytesBuilder>(
              BytesBuilder(copy: false), (buffer, chunk) => buffer..add(chunk));
      if (bytes.length > _maxFileBytes) {
        throw const FileSystemException('Health cache exceeds its read limit');
      }
      final raw = jsonDecode(utf8.decode(bytes.takeBytes()));
      if (_decode(raw)) _revision++;
      _trim();
      if (_entries.isNotEmpty && !_disposed) notifyListeners();
    } on FormatException {
      _entries.clear();
      _capacityReadOnly = false;
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
    var count = 0;
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
        if (count >= maxEntries) {
          _capacityReadOnly = true;
          continue;
        }
        count++;
        records[node.key as String] = NodeHealthRecord(
          delayMs: delay,
          testedAt: DateTime.fromMillisecondsSinceEpoch(value['t'] as int,
              isUtc: true),
          testUrlHash: value['u'] as String,
          reason: delay < 0 ? reason : null,
        );
      }
      if (records.isNotEmpty) _entries[profile.key as String] = records;
    }
    if (_capacityReadOnly) _report('capacityExceeded');
    return needsRewrite;
  }

  void _trim() {
    final retention = this.retention;
    if (retention != null) {
      final cutoff = _now().subtract(retention);
      for (final records in _entries.values) {
        records.removeWhere((_, record) => record.testedAt.isBefore(cutoff));
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
    if (_capacityReadOnly) {
      _report('capacityExceeded');
      throw StateError('Health cache exceeds its capacity');
    }
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
      // A successful update to an existing record does not resolve rejected
      // new records. Keep the capacity diagnostic until space is released.
      if (_lastErrorCode != 'capacityExceeded') _lastErrorCode = null;
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
    _catalogBindings.clear();
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}

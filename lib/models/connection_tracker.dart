import 'package:flclashx/models/common.dart';

enum ConnectionListMode { process, classic }

enum ConnectionViewMode { list, table }

enum ConnectionSort {
  time,
  upload,
  download,
  uploadSpeed,
  downloadSpeed,
  process,
}

enum ConnectionSortDirection { ascending, descending }

class ConnectionSnapshot {
  const ConnectionSnapshot({
    required this.downloadTotal,
    required this.uploadTotal,
    required this.memory,
    required this.connections,
  });

  factory ConnectionSnapshot.fromJson(Map<String, dynamic> json) {
    final rawConnections = json['connections'];
    return ConnectionSnapshot(
      downloadTotal: (json['downloadTotal'] as num?) ?? 0,
      uploadTotal: (json['uploadTotal'] as num?) ?? 0,
      memory: (json['memory'] as num?) ?? 0,
      connections: rawConnections is List
          ? rawConnections
              .whereType<Map>()
              .map(
                (item) => Connection.fromJson(
                  Map<String, Object?>.from(item),
                ),
              )
              .toList(growable: false)
          : const [],
    );
  }

  final num downloadTotal;
  final num uploadTotal;
  final num memory;
  final List<Connection> connections;
}

class TrackedConnection {
  const TrackedConnection({
    required this.connection,
    required this.isActive,
    required this.uploadSpeed,
    required this.downloadSpeed,
    this.closedAt,
  });

  final Connection connection;
  final bool isActive;
  final double uploadSpeed;
  final double downloadSpeed;
  final DateTime? closedAt;

  TrackedConnection copyWith({
    Connection? connection,
    bool? isActive,
    double? uploadSpeed,
    double? downloadSpeed,
    DateTime? closedAt,
  }) =>
      TrackedConnection(
        connection: connection ?? this.connection,
        isActive: isActive ?? this.isActive,
        uploadSpeed: uploadSpeed ?? this.uploadSpeed,
        downloadSpeed: downloadSpeed ?? this.downloadSpeed,
        closedAt: closedAt ?? this.closedAt,
      );
}

class ProcessConnectionGroup {
  const ProcessConnectionGroup({
    required this.key,
    required this.name,
    required this.processPath,
    required this.activeConnections,
    required this.closedConnections,
    required this.upload,
    required this.download,
    required this.uploadSpeed,
    required this.downloadSpeed,
  });

  final String key;
  final String name;
  final String processPath;
  final List<TrackedConnection> activeConnections;
  final List<TrackedConnection> closedConnections;
  final num upload;
  final num download;
  final double uploadSpeed;
  final double downloadSpeed;

  int get activeCount => activeConnections.length;
  int get closedCount => closedConnections.length;
  int get totalCount => activeCount + closedCount;
}

class ConnectionTracker {
  ConnectionTracker({this.maxClosed = 300})
      : assert(maxClosed >= 0, 'maxClosed must not be negative');

  final int maxClosed;
  final Map<String, TrackedConnection> _activeById = {};
  final Map<String, TrackedConnection> _closedById = {};

  DateTime? _lastSampleAt;
  num _downloadTotal = 0;
  num _uploadTotal = 0;
  num _memory = 0;
  List<TrackedConnection> _activeConnections = const [];
  List<TrackedConnection> _closedConnections = const [];
  List<ProcessConnectionGroup> _processGroups = const [];

  num get downloadTotal => _downloadTotal;
  num get uploadTotal => _uploadTotal;
  num get memory => _memory;
  List<TrackedConnection> get activeConnections => _activeConnections;
  List<TrackedConnection> get closedConnections => _closedConnections;
  List<ProcessConnectionGroup> get processGroups => _processGroups;

  void ingest(
    ConnectionSnapshot snapshot, {
    required DateTime sampledAt,
    bool calculateSpeed = true,
  }) {
    final previousSampleAt = _lastSampleAt;
    final elapsedSeconds = previousSampleAt == null
        ? 0.0
        : sampledAt.difference(previousSampleAt).inMicroseconds /
            Duration.microsecondsPerSecond;
    final canCalculateSpeed = calculateSpeed && elapsedSeconds > 0;
    final nextActive = <String, TrackedConnection>{};

    for (final connection in snapshot.connections) {
      final previous = _activeById[connection.id];
      final uploadSpeed = canCalculateSpeed && previous != null
          ? _rate(
              current: connection.upload,
              previous: previous.connection.upload,
              elapsedSeconds: elapsedSeconds,
            )
          : 0.0;
      final downloadSpeed = canCalculateSpeed && previous != null
          ? _rate(
              current: connection.download,
              previous: previous.connection.download,
              elapsedSeconds: elapsedSeconds,
            )
          : 0.0;
      nextActive[connection.id] = TrackedConnection(
        connection: connection,
        isActive: true,
        uploadSpeed: uploadSpeed,
        downloadSpeed: downloadSpeed,
      );
      _closedById.remove(connection.id);
    }

    for (final entry in _activeById.entries) {
      if (nextActive.containsKey(entry.key)) continue;
      _closedById[entry.key] = entry.value.copyWith(
        isActive: false,
        uploadSpeed: 0,
        downloadSpeed: 0,
        closedAt: sampledAt,
      );
    }

    _activeById
      ..clear()
      ..addAll(nextActive);
    _trimClosedConnections();
    _downloadTotal = snapshot.downloadTotal;
    _uploadTotal = snapshot.uploadTotal;
    _memory = snapshot.memory;
    _lastSampleAt = sampledAt;
    _rebuildViews();
  }

  void markAllClosed({required DateTime closedAt}) {
    for (final entry in _activeById.entries) {
      _closedById[entry.key] = entry.value.copyWith(
        isActive: false,
        uploadSpeed: 0,
        downloadSpeed: 0,
        closedAt: closedAt,
      );
    }
    _activeById.clear();
    _lastSampleAt = null;
    _trimClosedConnections();
    _rebuildViews();
  }

  void clearClosed() {
    if (_closedById.isEmpty) return;
    _closedById.clear();
    _rebuildViews();
  }

  void removeClosed(String id) {
    if (_closedById.remove(id) == null) return;
    _rebuildViews();
  }

  void reset() {
    _activeById.clear();
    _closedById.clear();
    _lastSampleAt = null;
    _downloadTotal = 0;
    _uploadTotal = 0;
    _memory = 0;
    _rebuildViews();
  }

  static double _rate({
    required num? current,
    required num? previous,
    required double elapsedSeconds,
  }) {
    final delta = (current ?? 0) - (previous ?? 0);
    if (delta <= 0 || elapsedSeconds <= 0) return 0;
    return delta / elapsedSeconds;
  }

  void _trimClosedConnections() {
    while (_closedById.length > maxClosed) {
      _closedById.remove(_closedById.keys.first);
    }
  }

  void _rebuildViews() {
    _activeConnections = List.unmodifiable(_activeById.values);
    _closedConnections = List.unmodifiable(_closedById.values);
    _processGroups = _buildProcessGroups(
      _activeConnections,
      _closedConnections,
    );
  }
}

class _MutableProcessGroup {
  _MutableProcessGroup({
    required this.key,
    required this.name,
    required this.processPath,
  });

  final String key;
  final String name;
  final String processPath;
  final List<TrackedConnection> activeConnections = [];
  final List<TrackedConnection> closedConnections = [];
  num upload = 0;
  num download = 0;
  double uploadSpeed = 0;
  double downloadSpeed = 0;

  void add(TrackedConnection item) {
    if (item.isActive) {
      activeConnections.add(item);
    } else {
      closedConnections.add(item);
    }
    upload += item.connection.upload ?? 0;
    download += item.connection.download ?? 0;
    uploadSpeed += item.uploadSpeed;
    downloadSpeed += item.downloadSpeed;
  }

  ProcessConnectionGroup freeze() => ProcessConnectionGroup(
        key: key,
        name: name,
        processPath: processPath,
        activeConnections: List.unmodifiable(activeConnections),
        closedConnections: List.unmodifiable(closedConnections),
        upload: upload,
        download: download,
        uploadSpeed: uploadSpeed,
        downloadSpeed: downloadSpeed,
      );
}

List<ProcessConnectionGroup> _buildProcessGroups(
  List<TrackedConnection> active,
  List<TrackedConnection> closed,
) {
  final groups = <String, _MutableProcessGroup>{};

  void add(TrackedConnection item) {
    final metadata = item.connection.metadata;
    final isInner = metadata.type.toLowerCase() == 'inner';
    final key = isInner
        ? 'mihomo'
        : _firstNotEmpty([
            metadata.processPath,
            metadata.process,
            metadata.sourceIP,
            'unknown',
          ]);
    final name = isInner
        ? 'mihomo'
        : _firstNotEmpty([metadata.process, metadata.sourceIP, 'unknown']);
    groups
        .putIfAbsent(
          key,
          () => _MutableProcessGroup(
            key: key,
            name: name,
            processPath: metadata.processPath,
          ),
        )
        .add(item);
  }

  active.forEach(add);
  closed.forEach(add);

  final result = groups.values.map((group) => group.freeze()).toList()
    ..sort((left, right) {
      final activeComparison = right.activeCount.compareTo(left.activeCount);
      if (activeComparison != 0) return activeComparison;
      final trafficComparison = (right.upload + right.download)
          .compareTo(left.upload + left.download);
      if (trafficComparison != 0) return trafficComparison;
      return left.name.toLowerCase().compareTo(right.name.toLowerCase());
    });
  return List.unmodifiable(result);
}

List<TrackedConnection> filterTrackedConnections(
  Iterable<TrackedConnection> connections,
  String query, {
  String Function(String path)? applicationNameForPath,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) return List.of(connections, growable: false);

  return connections.where((item) {
    final connection = item.connection;
    final metadata = connection.metadata;
    final applicationName =
        metadata.processPath.isEmpty || applicationNameForPath == null
            ? ''
            : applicationNameForPath(metadata.processPath);
    final values = [
      metadata.process,
      metadata.processPath,
      applicationName,
      metadata.host,
      metadata.sniffHost,
      metadata.destinationIP,
      metadata.remoteDestination,
      metadata.sourceIP,
      connection.chains.join(' '),
      connection.rule,
      connection.rulePayload,
      metadata.network,
      metadata.type,
    ];
    return values.any((value) => value.toLowerCase().contains(normalizedQuery));
  }).toList(growable: false);
}

List<TrackedConnection> sortTrackedConnections(
  Iterable<TrackedConnection> connections,
  ConnectionSort sort, {
  ConnectionSortDirection? direction,
}) {
  final resolvedDirection = direction ??
      (sort == ConnectionSort.process
          ? ConnectionSortDirection.ascending
          : ConnectionSortDirection.descending);
  final result = List<TrackedConnection>.of(connections)
    ..sort((left, right) {
      final comparison = switch (sort) {
        ConnectionSort.time =>
          left.connection.start.compareTo(right.connection.start),
        ConnectionSort.upload =>
          (left.connection.upload ?? 0).compareTo(right.connection.upload ?? 0),
        ConnectionSort.download => (left.connection.download ?? 0)
            .compareTo(right.connection.download ?? 0),
        ConnectionSort.uploadSpeed =>
          left.uploadSpeed.compareTo(right.uploadSpeed),
        ConnectionSort.downloadSpeed =>
          left.downloadSpeed.compareTo(right.downloadSpeed),
        ConnectionSort.process =>
          _processName(left).compareTo(_processName(right)),
      };
      final directed = resolvedDirection == ConnectionSortDirection.ascending
          ? comparison
          : -comparison;
      if (directed != 0) return directed;
      return left.connection.id.compareTo(right.connection.id);
    });
  return result;
}

String _processName(TrackedConnection item) => _firstNotEmpty([
      item.connection.metadata.process,
      item.connection.metadata.processPath,
      item.connection.metadata.sourceIP,
      'unknown',
    ]).toLowerCase();

String _firstNotEmpty(Iterable<String> values) =>
    values.firstWhere((value) => value.trim().isNotEmpty).trim();

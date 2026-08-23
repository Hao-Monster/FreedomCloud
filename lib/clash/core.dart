import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flclashx/clash/clash.dart';
import 'package:flclashx/clash/interface.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/state.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';

class ClashCore {
  factory ClashCore() {
    _instance ??= ClashCore._internal();
    return _instance!;
  }

  ClashCore._internal() {
    if (Platform.isAndroid) {
      clashInterface = clashLib!;
    } else {
      clashInterface = clashService!;
    }
  }
  static ClashCore? _instance;
  late ClashHandlerInterface clashInterface;
  final _connectionSnapshotDecoder = ConnectionSnapshotDecoder();
  int _connectionSnapshotRequestCount = 0;
  bool? _lastConnectionSnapshotWasEmpty;
  DateTime? _lastConnectionSnapshotDiagnosticAt;
  String? _lastConnectionSnapshotErrorType;

  Future<bool> preload() => clashInterface.preload();

  static Future<void> initGeo() async {
    final homePath = await appPath.homeDirPath;
    final homeDir = Directory(homePath);
    final isExists = await homeDir.exists();
    if (!isExists) {
      await homeDir.create(recursive: true);
    }
    const geoFileNameList = [
      mmdbFileName,
      geoIpFileName,
      geoSiteFileName,
      asnFileName,
    ];
    try {
      for (final geoFileName in geoFileNameList) {
        final geoFile = File(
          join(homePath, geoFileName),
        );
        final isExists = await geoFile.exists();
        if (isExists) {
          continue;
        }
        final data = await rootBundle.load('assets/data/$geoFileName');
        final List<int> bytes = data.buffer.asUint8List();
        await geoFile.writeAsBytes(bytes, flush: true);
      }
    } catch (e) {
      exit(0);
    }
  }

  Future<bool> init() async {
    await initGeo();
    if (globalState.config.appSetting.openLogs) {
      clashCore.startLog();
    } else {
      clashCore.stopLog();
    }
    final homeDirPath = await appPath.homeDirPath;
    return clashInterface.init(
      InitParams(
        homeDir: homeDirPath,
        version: globalState.appState.version,
      ),
    );
  }

  Future<bool> setState(CoreState state) => clashInterface.setState(state);

  Future<bool> setUiActive(bool active) => clashInterface.setUiActive(active);

  Future<void> shutdown() async {
    await clashInterface.shutdown();
  }

  FutureOr<bool> get isInit => clashInterface.isInit;

  FutureOr<String> validateConfig(String data) =>
      clashInterface.validateConfig(data);

  Future<String> updateConfig(UpdateParams updateParams) =>
      clashInterface.updateConfig(updateParams);

  Future<String> setupConfig(SetupParams setupParams) =>
      clashInterface.setupConfig(setupParams);

  Future<List<Group>> getProxiesGroups() async {
    final proxies = await clashInterface.getProxies();
    if (proxies.isEmpty) return [];
    bool isGroup(dynamic name) =>
        GroupTypeExtension.valueList.contains((proxies[name] ?? {})['type']);
    // Groups reachable through GLOBAL.all, keeping GLOBAL's own ordering.
    final fromGlobal =
        (((proxies[UsedProxy.GLOBAL.name] ?? {})["all"] ?? []) as List)
            .where(isGroup)
            .toList();
    final groupNames = [UsedProxy.GLOBAL.name, ...fromGlobal];
    // Only when GLOBAL opts in via `flclashx-override`: a curated GLOBAL lists
    // just a subset, so the service groups used by rules (YouTube, Telegram, …)
    // wouldn't otherwise surface. Enumerate them from the full proxy map so
    // every defined group is available (the hidden flag still controls display).
    if (globalState.globalOverrideEnabled.value) {
      final seen = {UsedProxy.GLOBAL.name, ...fromGlobal};
      // proxies.keys arrive alphabetically (Go's json.Marshal sorts map keys),
      // so enumerate in profile-declaration order first, then append any leftover
      // groups not named in proxy-groups (still alphabetical, but a rare tail).
      final declared = globalState.proxyGroupOrder.value;
      final extra = declared
          .where((name) => !seen.contains(name) && isGroup(name))
          .toList();
      groupNames.addAll(extra);
      seen.addAll(extra);
      groupNames.addAll(
        proxies.keys.where((name) => !seen.contains(name) && isGroup(name)),
      );
    }
    final groupsRaw = groupNames.map((groupName) {
      final group = Map<String, dynamic>.from(proxies[groupName] as Map);
      group["all"] = ((group["all"] ?? []) as List)
          .map(
            (name) => proxies[name] != null
                ? Map<String, dynamic>.from(proxies[name] as Map)
                : null,
          )
          .where((proxy) => proxy != null)
          .toList();
      return group;
    }).toList();
    return groupsRaw
        .map(
          (e) => Group.fromJson(Map<String, dynamic>.from(e)),
        )
        .toList();
  }

  FutureOr<String> changeProxy(ChangeProxyParams changeProxyParams) async =>
      await clashInterface.changeProxy(changeProxyParams);

  Future<ConnectionSnapshot> getConnectionsSnapshot() async {
    final requestNumber = ++_connectionSnapshotRequestCount;
    final stopwatch = Stopwatch()..start();
    try {
      final res = await clashInterface.getConnections();
      if (res.isEmpty) {
        _logConnectionSnapshotResult(
          requestNumber: requestNumber,
          responseLength: 0,
          connectionCount: 0,
          elapsedMilliseconds: stopwatch.elapsedMilliseconds,
        );
        return const ConnectionSnapshot(
          downloadTotal: 0,
          uploadTotal: 0,
          memory: 0,
          connections: [],
        );
      }
      final snapshot = await _connectionSnapshotDecoder.decode(res);
      _lastConnectionSnapshotErrorType = null;
      _logConnectionSnapshotResult(
        requestNumber: requestNumber,
        responseLength: res.length,
        connectionCount: snapshot.connections.length,
        elapsedMilliseconds: stopwatch.elapsedMilliseconds,
      );
      return snapshot;
    } catch (error) {
      _logConnectionSnapshotError(
        requestNumber: requestNumber,
        errorType: error.runtimeType.toString(),
        elapsedMilliseconds: stopwatch.elapsedMilliseconds,
      );
      rethrow;
    }
  }

  void _logConnectionSnapshotResult({
    required int requestNumber,
    required int responseLength,
    required int connectionCount,
    required int elapsedMilliseconds,
  }) {
    final now = DateTime.now();
    final isEmpty = connectionCount == 0;
    final shouldLog = requestNumber <= 3 ||
        _lastConnectionSnapshotWasEmpty != isEmpty ||
        _lastConnectionSnapshotDiagnosticAt == null ||
        now.difference(_lastConnectionSnapshotDiagnosticAt!) >=
            const Duration(seconds: 30);
    _lastConnectionSnapshotWasEmpty = isEmpty;
    if (!shouldLog) return;
    _lastConnectionSnapshotDiagnosticAt = now;
    connectionDiagnostics.log(
      '[ConnectionsDiag] core.snapshot status=ok request=$requestNumber '
      'durationMs=$elapsedMilliseconds responseLength=$responseLength '
      'connections=$connectionCount',
    );
  }

  void _logConnectionSnapshotError({
    required int requestNumber,
    required String errorType,
    required int elapsedMilliseconds,
  }) {
    final now = DateTime.now();
    final shouldLog = requestNumber <= 3 ||
        _lastConnectionSnapshotErrorType != errorType ||
        _lastConnectionSnapshotDiagnosticAt == null ||
        now.difference(_lastConnectionSnapshotDiagnosticAt!) >=
            const Duration(seconds: 30);
    _lastConnectionSnapshotErrorType = errorType;
    if (!shouldLog) return;
    _lastConnectionSnapshotDiagnosticAt = now;
    connectionDiagnostics.log(
      '[ConnectionsDiag] core.snapshot status=error request=$requestNumber '
      'durationMs=$elapsedMilliseconds errorType=$errorType',
    );
  }

  Future<bool> closeConnectionAndWait(String id) =>
      Future.value(clashInterface.closeConnection(id));

  Future<bool> closeConnectionsAndWait() =>
      Future.value(clashInterface.closeConnections());

  void closeConnection(String id) {
    unawaited(closeConnectionAndWait(id));
  }

  void closeConnections() {
    unawaited(closeConnectionsAndWait());
  }

  Future<List<Connection>> getConnections() async =>
      (await getConnectionsSnapshot()).connections;

  void resetConnections() {
    clashInterface.resetConnections();
  }

  Future<List<ExternalProvider>> getExternalProviders() async {
    final externalProvidersRawString =
        await clashInterface.getExternalProviders();
    if (externalProvidersRawString.isEmpty) {
      return [];
    }
    return Isolate.run<List<ExternalProvider>>(
      () {
        final externalProviders =
            (json.decode(externalProvidersRawString) as List<dynamic>)
                .map(
                  (item) => ExternalProvider.fromJson(item),
                )
                .toList();
        return externalProviders;
      },
    );
  }

  Future<ExternalProvider?> getExternalProvider(
      String externalProviderName) async {
    final externalProvidersRawString =
        await clashInterface.getExternalProvider(externalProviderName);
    if (externalProvidersRawString.isEmpty) {
      return null;
    }
    return ExternalProvider.fromJson(json.decode(externalProvidersRawString));
  }

  Future<String> updateGeoData(UpdateGeoDataParams params) =>
      clashInterface.updateGeoData(params);

  Future<String> sideLoadExternalProvider({
    required String providerName,
    required String data,
  }) =>
      clashInterface.sideLoadExternalProvider(
          providerName: providerName, data: data);

  Future<String> updateExternalProvider({
    required String providerName,
  }) async =>
      clashInterface.updateExternalProvider(providerName);

  Future<void> startListener() async {
    await clashInterface.startListener();
  }

  Future<void> stopListener() async {
    await clashInterface.stopListener();
  }

  Future<void> healthCheck([String groupName = '']) =>
      clashInterface.healthCheck(groupName);

  Future<Delay> getDelay(String url, String proxyName) async {
    final data = await clashInterface.asyncTestDelay(url, proxyName);
    return Delay.fromJson(json.decode(data));
  }

  Future<Map<String, dynamic>> getConfig(String id) async {
    final profilePath = await appPath.getProfilePath(id);
    final res = await clashInterface.getConfig(profilePath);
    if (res.isSuccess) {
      return Map<String, dynamic>.from(res.data as Map);
    } else {
      throw res.message;
    }
  }

  Future<Traffic> getTraffic() async {
    final trafficString = await clashInterface.getTraffic();
    if (trafficString.isEmpty) {
      return Traffic();
    }
    return Traffic.fromMap(json.decode(trafficString));
  }

  Future<IpInfo?> getCountryCode(String ip) async {
    final countryCode = await clashInterface.getCountryCode(ip);
    if (countryCode.isEmpty) {
      return null;
    }
    return IpInfo(
      ip: ip,
      countryCode: countryCode,
    );
  }

  Future<Traffic> getTotalTraffic() async {
    final totalTrafficString = await clashInterface.getTotalTraffic();
    if (totalTrafficString.isEmpty) {
      return Traffic();
    }
    return Traffic.fromMap(json.decode(totalTrafficString));
  }

  Future<int> getMemory() async {
    final value = await clashInterface.getMemory();
    if (value.isEmpty) {
      return 0;
    }
    return int.tryParse(value) ?? 0;
  }

  Future<String> getCoreVersion() async {
    try {
      return await clashInterface.getCoreVersion();
    } catch (_) {
      return '';
    }
  }

  void resetTraffic() {
    clashInterface.resetTraffic();
  }

  void startLog() {
    clashInterface.startLog();
  }

  void stopLog() {
    clashInterface.stopLog();
  }

  void requestGc() {
    clashInterface.forceGc();
  }

  Future<void> destroy() async {
    _connectionSnapshotDecoder.dispose();
    await clashInterface.destroy();
  }
}

final clashCore = ClashCore();

/// A persistent worker isolate avoids doing JSON decoding and hundreds of
/// generated model allocations on Flutter's UI isolate every refresh tick.
class ConnectionSnapshotDecoder {
  final ReceivePort _receivePort = ReceivePort();
  final Map<int, Completer<ConnectionSnapshot>> _pending = {};
  Future<SendPort>? _sendPortFuture;
  StreamSubscription<dynamic>? _subscription;
  Isolate? _isolate;
  var _requestId = 0;
  var _disposed = false;

  Future<ConnectionSnapshot> decode(String source) async {
    if (_disposed) throw StateError('Connection snapshot decoder is disposed');
    final sendPort = await (_sendPortFuture ??= _start());
    final id = _requestId++;
    final completer = Completer<ConnectionSnapshot>();
    _pending[id] = completer;
    sendPort.send((id, source));
    return completer.future;
  }

  Future<SendPort> _start() async {
    final ready = Completer<SendPort>();
    _subscription = _receivePort.listen((message) {
      if (message is SendPort) {
        if (!ready.isCompleted) ready.complete(message);
        return;
      }
      if (message is! (int, bool, Object)) return;
      final (id, success, payload) = message;
      final completer = _pending.remove(id);
      if (completer == null) return;
      if (success && payload is ConnectionSnapshot) {
        completer.complete(payload);
      } else {
        completer.completeError(FormatException('$payload'));
      }
    });
    _isolate = await Isolate.spawn(_decodeLoop, _receivePort.sendPort);
    return ready.future;
  }

  @pragma('vm:entry-point')
  static void _decodeLoop(SendPort mainPort) {
    final commands = ReceivePort();
    mainPort.send(commands.sendPort);
    commands.listen((message) {
      if (message is! (int, String)) return;
      final (id, source) = message;
      try {
        final decoded = json.decode(source);
        if (decoded is! Map) {
          throw const FormatException('Invalid connections snapshot');
        }
        final snapshot = ConnectionSnapshot.fromJson(
          Map<String, dynamic>.from(decoded),
        );
        mainPort.send((id, true, snapshot));
      } catch (error) {
        mainPort.send((id, false, error.toString()));
      }
    });
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    final subscription = _subscription;
    if (subscription != null) unawaited(subscription.cancel());
    _subscription = null;
    _receivePort.close();
    for (final completer in _pending.values) {
      completer
          .completeError(StateError('Connection snapshot decoder stopped'));
    }
    _pending.clear();
  }
}

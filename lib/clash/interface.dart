import 'dart:async';
import 'dart:convert';
import 'package:flclashx/common/node_catalog_codec.dart';
import 'dart:isolate';

import 'package:flclashx/clash/message.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/delay_test_coordinator.dart';
import 'package:flclashx/common/tun_runtime.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';

/// Protocol failures carry only fixed categories, never remote/parser text.
class CatalogCoreException implements Exception {
  factory CatalogCoreException(Object? reason) =>
      CatalogCoreException._(safeReason(reason));
  const CatalogCoreException._(this.reason);
  final String reason;

  static String safeReason(Object? reason) => reason is String &&
          const {
            'invalidParameters',
            'invalidResponse',
            'tooManyNodes',
            'strictModeUnsupported',
            'catalogNotFound',
            'overloaded',
            'duplicateRequest',
            'parseFailed',
            'chainUnsupported',
            'typeUnsupported',
            'testFailed',
            'deadlineExceeded',
            'cancelled',
            'uiInactive',
            'sessionClosed',
            'configChanged',
            'transportFailure',
            'coreUnavailable',
            'clientFailure',
            'batchDeadlineExceeded',
            'unknown',
            'providerTooLarge',
            'providerOptionsUnsupported',
          }.contains(reason)
      ? reason
      : 'unknown';

  @override
  String toString() => 'CatalogCoreException($reason)';
}

bool _isCatalogMethod(ActionMethod method) => const {
      ActionMethod.catalogPrepare,
      ActionMethod.catalogParseProvider,
      ActionMethod.catalogTestDelay,
      ActionMethod.catalogRelease,
    }.contains(method);

mixin ClashInterface {
  Future<bool> init(InitParams params);

  Future<bool> preload();

  Future<bool> shutdown();

  Future<bool> get isInit;

  Future<bool> forceGc();

  FutureOr<String> validateConfig(String data);

  FutureOr<Result> getConfig(String path);

  Future<String> asyncTestDelay(
    String url,
    String proxyName, {
    String? requestId,
    Duration timeout = const Duration(seconds: 5),
  });

  Future<bool> cancelTestDelay(String requestId);

  Future<String> catalogPrepare(String catalogId,
      List<Map<String, dynamic>> proxies, List<Map<String, dynamic>> providers);

  Future<String> catalogParseProvider(
      String contentBase64, Map<String, dynamic> definition);

  Future<DelayTestResult> catalogTestDelay(
      String catalogId, int index, String url,
      {required String requestId,
      Duration timeout = const Duration(seconds: 5)});

  Future<bool> catalogRelease(String catalogId);

  Future<void> healthCheck([String groupName = '']);

  FutureOr<String> updateConfig(
    UpdateParams updateParams, {
    String? controllerAddress,
    bool? controllerEnabled,
  });

  FutureOr<String> setupConfig(SetupParams setupParams);

  FutureOr<Map> getProxies();

  FutureOr<String> changeProxy(ChangeProxyParams changeProxyParams);

  Future<bool> startListener();

  Future<bool> stopListener();

  FutureOr<String> getExternalProviders();

  FutureOr<String>? getExternalProvider(String externalProviderName);

  Future<String> updateGeoData(UpdateGeoDataParams params);

  Future<String> sideLoadExternalProvider({
    required String providerName,
    required String data,
  });

  Future<String> updateExternalProvider(String providerName);

  FutureOr<String> getTraffic();

  FutureOr<String> getTotalTraffic();

  FutureOr<String> getCountryCode(String ip);

  FutureOr<String> getMemory();

  FutureOr<String> getCoreVersion();

  resetTraffic();

  startLog();

  stopLog();

  Future<bool> crash();

  FutureOr<String> getConnections();

  FutureOr<bool> closeConnection(String id);

  FutureOr<bool> closeConnections();

  FutureOr<bool> resetConnections();

  Future<bool> setState(CoreState state);

  Future<bool> setUiActive(bool active);
}

mixin AndroidClashInterface {
  Future<bool> updateDns(String value);

  Future<String> getAndroidVpnOptions();

  Future<String> getCurrentProfileName();

  Future<DateTime?> getRunTime();
}

abstract class ClashHandlerInterface with ClashInterface {
  Map<String, Completer> callbackCompleterMap = {};

  /// Per-call type-appropriate default value, so a failed call can complete the
  /// typed completer with the right default instead of `null` (which throws a
  /// TypeError on a non-nullable type and strands the caller until timeout).
  Map<String, dynamic> callbackDefaultMap = {};

  Future<void> handleResult(ActionResult result) async {
    final completer = callbackCompleterMap.remove(result.id);
    final defaultValue = callbackDefaultMap.remove(result.id);
    if (completer?.isCompleted == true) return;
    if (_isCatalogMethod(result.method)) {
      // Do not send catalog failures through the legacy dynamic completion/log
      // path: a mismatched type can include the remote value in its exception.
      if (result.code != ResultType.success) {
        completer?.completeError(CatalogCoreException(result.data));
      } else if (result.method == ActionMethod.catalogRelease
          ? result.data is bool
          : result.data is String) {
        completer?.complete(result.data);
      } else {
        completer?.completeError(CatalogCoreException('invalidResponse'));
      }
      return;
    }
    try {
      switch (result.method) {
        case ActionMethod.getTunStatus:
          completer?.complete(result.toResult);
          return;
        case ActionMethod.updateConfig:
        case ActionMethod.setupConfig:
          if (result.code != ResultType.success) {
            completer?.complete('Core rejected configuration');
          } else {
            completer?.complete(result.data);
          }
          return;
        case ActionMethod.message:
          clashMessage.controller.add(result.data);
          completer?.complete(true);
          return;
        case ActionMethod.getConfig:
          completer?.complete(result.toResult);
          return;
        default:
          completer?.complete(result.data);
          return;
      }
    } catch (e) {
      commonPrint.log("${result.id} error $e");
      // Type mismatch (e.g. the remote sent a bool for a Completer<String>):
      // completing with the wrong type threw above and left the completer
      // pending until the 30s safeFuture timeout — a "random" 30s freeze of
      // whatever call this was. Complete with the typed default now.
      if (completer != null && !completer.isCompleted) {
        completer.complete(defaultValue);
      }
    }
  }

  sendMessage(String message);

  reStart();

  FutureOr<bool> destroy();

  Future<T> invoke<T>({
    required ActionMethod method,
    dynamic data,
    Duration? timeout,
    FutureOr<T> Function()? onTimeout,
    T? defaultValue,
  }) async {
    final id = "${method.name}#${utils.id}";

    final completer = Completer<T>();
    callbackCompleterMap[id] = completer;

    dynamic mDefaultValue = defaultValue;
    if (mDefaultValue == null) {
      if (T == String) {
        mDefaultValue = "";
      } else if (T == bool) {
        mDefaultValue = false;
      } else if (T == Map) {
        mDefaultValue = {};
      }
    }
    callbackDefaultMap[id] = mDefaultValue;

    final result = completer.safeFuture(
      timeout: timeout,
      onLast: () {
        callbackCompleterMap.remove(id);
        callbackDefaultMap.remove(id);
      },
      onTimeout: onTimeout ?? () => mDefaultValue as T,
      functionName: id,
    );
    // Register completion/cleanup before sending: transports may reply or fail
    // synchronously, and an async send failure must not become a zone error.
    void failSend(Object _) {
      if (!completer.isCompleted) {
        if (_isCatalogMethod(method)) {
          completer.completeError(CatalogCoreException('transportFailure'));
        } else {
          completer.complete(mDefaultValue as T);
        }
      }
    }

    try {
      final sent = sendMessage(json.encode(Action(
        id: id,
        method: method,
        data: data,
      )));
      if (sent is Future) {
        unawaited(sent.then<void>((_) {}, onError: failSend));
      }
    } catch (error) {
      failSend(error);
    }
    return result;
  }

  @override
  Future<bool> init(InitParams params) => invoke<bool>(
        method: ActionMethod.initClash,
        data: json.encode(params),
      );

  @override
  Future<bool> setState(CoreState state) => invoke<bool>(
        method: ActionMethod.setState,
        data: json.encode(state),
      );

  @override
  Future<bool> setUiActive(bool active) => invoke<bool>(
        method: ActionMethod.setUiActive,
        data: active,
        // Short timeout so an older core without this handler degrades silently
        // instead of leaving a pending completer.
        timeout: const Duration(seconds: 2),
      );

  @override
  Future<bool> shutdown() => invoke<bool>(
        method: ActionMethod.shutdown,
        timeout: const Duration(seconds: 1),
      );

  @override
  Future<bool> get isInit => invoke<bool>(
        method: ActionMethod.getIsInit,
      );

  @override
  Future<bool> forceGc() => invoke<bool>(
        method: ActionMethod.forceGc,
      );

  @override
  FutureOr<String> validateConfig(String data) => invoke<String>(
        method: ActionMethod.validateConfig,
        data: data,
      );

  @override
  Future<String> updateConfig(
    UpdateParams updateParams, {
    String? controllerAddress,
    bool? controllerEnabled,
  }) =>
      invoke<String>(
        method: ActionMethod.updateConfig,
        // A general update has no authority to replace a profile's controller
        // endpoint with the UI enum's default, or re-enable a closed listener.
        data: json.encode({
          ...(updateParams.toJson()..remove('external-controller')),
          if (controllerAddress != null)
            'external-controller': controllerAddress,
          if (controllerEnabled != null)
            'controller-enabled': controllerEnabled,
        }),
        defaultValue: 'updateConfig transport unavailable',
        timeout: const Duration(minutes: 2),
        // Empty string means success to callers; the default-on-timeout is "",
        // which would mask a 2-minute hang as a successful apply. Return a
        // non-empty error string so the caller actually treats it as failed.
        onTimeout: () => 'updateConfig timed out',
      );

  @override
  Future<Result> getConfig(String path) => invoke<Result>(
        method: ActionMethod.getConfig,
        data: path,
        timeout: const Duration(minutes: 2),
        // A timed-out/failed read used to default to Result.success({}), making
        // the caller treat an empty config as a successful load. Yield an error
        // Result so getConfig()'s error path fires instead.
        defaultValue: Result.error('getConfig timed out'),
      );

  @override
  Future<String> setupConfig(SetupParams setupParams) async {
    final data = await Isolate.run(() => json.encode(setupParams));
    return invoke<String>(
      method: ActionMethod.setupConfig,
      data: data,
      defaultValue: 'setupConfig transport unavailable',
      timeout: const Duration(minutes: 2),
      // Non-empty = error to callers; the default "" would mask a 2-minute hang
      // as a successful setup (and falsely advance lastProfileModified), so the
      // recovery re-apply would silently no-op against a still-broken executor.
      onTimeout: () => 'setupConfig timed out',
    );
  }

  Future<TunStatus> getTunStatus() async {
    final result = await invoke<Result>(
      method: ActionMethod.getTunStatus,
      timeout: const Duration(seconds: 3),
      defaultValue: Result.error('statusUnavailable'),
    );
    if (result.isError) throw const TunFailure('statusUnavailable');
    return TunStatus.fromJson(result.data);
  }

  @override
  Future<bool> crash() => invoke<bool>(
        method: ActionMethod.crash,
      );

  @override
  Future<Map> getProxies() => invoke<Map>(
        method: ActionMethod.getProxies,
        timeout: const Duration(seconds: 5),
      );

  @override
  FutureOr<String> changeProxy(ChangeProxyParams changeProxyParams) =>
      invoke<String>(
        method: ActionMethod.changeProxy,
        data: json.encode(changeProxyParams),
      );

  @override
  FutureOr<String> getExternalProviders() => invoke<String>(
        method: ActionMethod.getExternalProviders,
      );

  @override
  FutureOr<String> getExternalProvider(String externalProviderName) =>
      invoke<String>(
        method: ActionMethod.getExternalProvider,
        data: externalProviderName,
      );

  @override
  Future<String> updateGeoData(UpdateGeoDataParams params) => invoke<String>(
      method: ActionMethod.updateGeoData,
      data: json.encode(params),
      timeout: const Duration(seconds: 100));

  @override
  Future<String> sideLoadExternalProvider({
    required String providerName,
    required String data,
  }) =>
      invoke<String>(
        method: ActionMethod.sideLoadExternalProvider,
        data: json.encode({
          "providerName": providerName,
          "data": data,
        }),
      );

  @override
  Future<String> updateExternalProvider(String providerName) => invoke<String>(
        method: ActionMethod.updateExternalProvider,
        data: providerName,
        timeout: const Duration(minutes: 1),
      );

  @override
  FutureOr<String> getConnections() => invoke<String>(
        method: ActionMethod.getConnections,
      );

  @override
  Future<bool> closeConnections() => invoke<bool>(
        method: ActionMethod.closeConnections,
      );

  @override
  Future<bool> resetConnections() => invoke<bool>(
        method: ActionMethod.resetConnections,
      );

  @override
  Future<bool> closeConnection(String id) => invoke<bool>(
        method: ActionMethod.closeConnection,
        data: id,
      );

  @override
  FutureOr<String> getTotalTraffic() => invoke<String>(
        method: ActionMethod.getTotalTraffic,
      );

  @override
  FutureOr<String> getTraffic() => invoke<String>(
        method: ActionMethod.getTraffic,
      );

  @override
  void resetTraffic() {
    invoke(method: ActionMethod.resetTraffic);
  }

  @override
  void startLog() {
    invoke(method: ActionMethod.startLog);
  }

  @override
  void stopLog() {
    invoke<bool>(
      method: ActionMethod.stopLog,
    );
  }

  @override
  Future<bool> startListener() => invoke<bool>(
        method: ActionMethod.startListener,
      );

  @override
  Future<bool> stopListener() => invoke<bool>(
        method: ActionMethod.stopListener,
      );

  @override
  Future<String> asyncTestDelay(
    String url,
    String proxyName, {
    String? requestId,
    Duration timeout = const Duration(seconds: 5),
  }) {
    final id = requestId ?? 'delay-${utils.id}';
    final delayParams = {
      "proxy-name": proxyName,
      "request-id": id,
      "timeout": timeout.inMilliseconds,
      "test-url": url,
    };
    return invoke<String>(
      method: ActionMethod.asyncTestDelay,
      data: json.encode(delayParams),
      timeout: timeout,
      onTimeout: () {
        unawaited(cancelTestDelay(id));
        return json.encode({
          'name': proxyName,
          'value': -1,
          'url': url,
          'reason': 'deadlineExceeded'
        });
      },
    );
  }

  @override
  Future<bool> cancelTestDelay(String requestId) => invoke<bool>(
        method: ActionMethod.cancelTestDelay,
        data: requestId,
        timeout: const Duration(seconds: 1),
      );

  @override
  Future<String> catalogPrepare(
      String catalogId,
      List<Map<String, dynamic>> proxies,
      List<Map<String, dynamic>> providers) async {
    final String data;
    try {
      data = jsonEncode({
        'catalog-id': catalogId,
        'proxies': proxies,
        'providers': providers
      });
      // The encoder uses Error for unsupported data and includes its value.
      // Sanitize this boundary instead of allowing raw configuration to escape.
      // ignore: avoid_catching_errors
    } on JsonUnsupportedObjectError {
      throw CatalogCoreException('invalidParameters');
    }
    if (utf8.encode(jsonEncode(data)).length > catalogPayloadFrameBytes) {
      throw CatalogCoreException('providerTooLarge');
    }
    return invoke<String>(
      method: ActionMethod.catalogPrepare,
      data: data,
      onTimeout: () => throw CatalogCoreException('deadlineExceeded'),
    );
  }

  @override
  Future<String> catalogParseProvider(
      String contentBase64, Map<String, dynamic> definition) async {
    final String data;
    // As with preparation, serialization failures must not expose raw inputs.
    // ignore: avoid_catching_errors
    try {
      data = jsonEncode(
          {'content-base64': contentBase64, 'definition': definition});
    } catch (_) {
      throw CatalogCoreException('invalidParameters');
    }
    try {
      final encoded = await encodeCatalogPayload(data);
      final response = await invoke<String>(
          method: ActionMethod.catalogParseProvider,
          data: encoded,
          timeout: const Duration(seconds: 10),
          onTimeout: () => throw CatalogCoreException('deadlineExceeded'));
      return await decodeCatalogPayload(response);
    } on CatalogPayloadException catch (error) {
      throw CatalogCoreException(error.reason);
    }
  }

  @override
  Future<DelayTestResult> catalogTestDelay(
      String catalogId, int index, String url,
      {required String requestId,
      Duration timeout = const Duration(seconds: 5)}) async {
    if (catalogId.isEmpty ||
        index < 0 ||
        requestId.isEmpty ||
        timeout <= Duration.zero) {
      return const DelayTestResult(-1, reason: 'invalidParameters');
    }
    try {
      final data = await invoke<String>(
        method: ActionMethod.catalogTestDelay,
        data: jsonEncode({
          'catalog-id': catalogId,
          'index': index,
          'request-id': requestId,
          'timeout': timeout.inMilliseconds,
          'test-url': url
        }),
        timeout: timeout,
        onTimeout: () {
          // Cancellation is best effort; Core still owns an independent
          // request deadline when the cancellation transport is unavailable.
          unawaited(Future<bool>.sync(() => cancelTestDelay(requestId))
              .then<void>((_) {}, onError: (Object _, StackTrace __) {}));
          return '{"value":-1,"reason":"deadlineExceeded"}';
        },
      );
      final decoded = jsonDecode(data);
      if (decoded is! Map ||
          decoded['value'] is! int ||
          decoded['value'] == 0 ||
          (decoded['value'] as int) < -1) {
        return const DelayTestResult(-1, reason: 'invalidResponse');
      }
      final value = decoded['value'] as int;
      return DelayTestResult(value,
          reason: value < 0
              ? CatalogCoreException.safeReason(decoded['reason'])
              : null);
    } on CatalogCoreException catch (error) {
      return DelayTestResult(-1, reason: error.reason);
    } on FormatException {
      return const DelayTestResult(-1, reason: 'invalidResponse');
    }
  }

  @override
  Future<bool> catalogRelease(String catalogId) => invoke<bool>(
        method: ActionMethod.catalogRelease,
        data: jsonEncode({'catalog-id': catalogId}),
        timeout: const Duration(seconds: 2),
        onTimeout: () => throw CatalogCoreException('deadlineExceeded'),
      );

  @override
  Future<void> healthCheck([String groupName = '']) => invoke<String>(
        method: ActionMethod.healthCheck,
        data: groupName,
        timeout: const Duration(seconds: 30),
      );

  @override
  FutureOr<String> getCountryCode(String ip) => invoke<String>(
        method: ActionMethod.getCountryCode,
        data: ip,
      );

  @override
  FutureOr<String> getMemory() => invoke<String>(
        method: ActionMethod.getMemory,
      );

  @override
  FutureOr<String> getCoreVersion() => invoke<String>(
        method: ActionMethod.getCoreVersion,
      );
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/tun_runtime.dart';
import 'package:flclashx/common/windows_helper_compatibility.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/services/secure_subscription.dart';
import 'package:flclashx/state.dart';
import 'package:flutter/cupertino.dart';

typedef IpCheckProbeResult = ({
  IpInfo ipInfo,
  String host,
  Set<String> sourcePorts,
  bool routedViaClash,
});

class Request {
  Request({
    Map<String, IpInfo Function(Map<String, dynamic>)>? ipInfoSources,
  }) : _ipInfoSources = ipInfoSources ?? _defaultIpInfoSources {
    _dio = Dio(
      BaseOptions(
        headers: {
          "User-Agent": browserUa,
        },
        // Without these a profile/subscription fetch over a half-dead uplink
        // (mobile network, doze-restricted background) hangs forever: the card
        // spins indefinitely and the auto-update chain stalls until app restart.
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
    _clashDio = Dio(
      BaseOptions(
        // Only cap connection setup globally so a dead/blackholed exit node fails
        // fast instead of hanging the IP check. Receive time is left unbounded
        // here (large proxied downloads use this same client) and capped
        // per-request in checkIp instead.
        connectTimeout: const Duration(seconds: 5),
      ),
    );
    _clashDio.httpClientAdapter = IOHttpClientAdapter(createHttpClient: () {
      final client = HttpClient();
      client.findProxy = (uri) {
        client.userAgent = globalState.ua;
        return FlClashHttpOverrides.handleFindProxy(uri);
      };
      return client;
    });
  }
  late final Dio _dio;
  late final Dio _clashDio;
  final _secureSubscription = SecureSubscriptionDownloader();
  String? userAgent;

  Future<Response<Uint8List>> getFileResponseForUrl(
    String rawUrl, {
    Map<String, dynamic>? headers,
    bool requireValidTls = false,
  }) async {
    final url = rawUrl.normalizeUrlCredentials;
    final requestHeaders = headers ?? {};
    requestHeaders['User-Agent'] = globalState.ua;

    if (requireValidTls) {
      return _secureSubscription.download(Uri.parse(url), requestHeaders);
    }

    final dio = _dio;

    final firstResponse = await dio.get<Uint8List>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        headers: requestHeaders,
        followRedirects: false,
        validateStatus: (status) => status != null && status < 400,
      ),
    );

    if (firstResponse.isRedirect == true) {
      final newUrl = firstResponse.headers.value('location');
      if (newUrl == null) {
        throw Exception('Redirect detected, but no location header was found.');
      }

      commonPrint.log('↪️ Redirecting to: $newUrl');
      final finalResponse = await dio.get<Uint8List>(
        newUrl,
        options: Options(
          responseType: ResponseType.bytes,
          headers: requestHeaders,
          followRedirects: true,
          maxRedirects: 5,
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      return finalResponse;
    }
    return firstResponse;
  }

  Future<Response> getTextResponseForUrl(String url) async {
    final response = await _clashDio.get(
      url,
      options: Options(
        responseType: ResponseType.plain,
      ),
    );
    return response;
  }

  Future<MemoryImage?> getImage(String url) async {
    if (url.isEmpty) return null;
    final response = await _dio.get<Uint8List>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
      ),
    );
    final data = response.data;
    if (data == null) return null;
    return MemoryImage(data);
  }

  Future<Map<String, dynamic>?> checkForUpdate() async {
    final response = await _dio.get(
      "https://api.github.com/repos/$repository/releases/latest",
      options: Options(
        responseType: ResponseType.json,
      ),
    );
    if (response.statusCode != 200) return null;
    final data = response.data as Map<String, dynamic>;
    final remoteVersion = data['tag_name'];
    final version = globalState.packageInfo.version;
    final hasUpdate =
        utils.compareVersions(remoteVersion.replaceAll('v', ''), version) > 0;
    if (!hasUpdate) return null;
    return data;
  }

  // Tried in order, first success wins. All return a dead-simple JSON with an
  // IPv4 exit IP + country code:
  //   ip.sb     — `api-ipv4` host is A-only, so the exit is forced over IPv4
  //   ip-api.com — IPv4-only on the free tier
  //   ipinfo.io — plain {ip, country}, used as a last-resort fallback
  static final Map<String, IpInfo Function(Map<String, dynamic>)>
      _defaultIpInfoSources = {
    "https://api-ipv4.ip.sb/geoip": IpInfo.fromIpSbJson,
    "http://ip-api.com/json/?fields=status,countryCode,query":
        IpInfo.fromIpApiComJson,
    "https://ipinfo.io/json": IpInfo.fromIpInfoIoJson,
  };
  final Map<String, IpInfo Function(Map<String, dynamic>)> _ipInfoSources;

  /// Resolve the exit IP by trying each source **sequentially**, stopping at the
  /// first success. A healthy primary therefore means exactly one request — not
  /// a parallel race that fires every source through the tunnel at once. Each
  /// source is bounded by a short receive timeout (plus the client-wide connect
  /// timeout) so a slow/dead node falls through to the next instead of hanging.
  Future<Result<IpInfo?>> checkIp({CancelToken? cancelToken}) async {
    final res = await checkIpWithHost(cancelToken: cancelToken);
    if (res.isError) {
      return Result.error(res.message);
    }
    return Result.success(res.data?.ipInfo);
  }

  Future<Result<IpCheckProbeResult?>> checkIpWithHost({
    CancelToken? cancelToken,
    Duration keepAliveHold = const Duration(milliseconds: 4500),
    Duration connectTimeout = const Duration(seconds: 5),
  }) async {
    for (final source in _ipInfoSources.entries) {
      if (cancelToken?.isCancelled ?? false) {
        return Result.error("cancelled");
      }
      final attemptPorts = <String>{};
      final clientAbortCallbacks = <void Function()>[];
      var attemptRoutedViaClash = false;
      var holdForTelemetry = false;

      void abortAllAttemptSockets() {
        for (final callback in clientAbortCallbacks.reversed) {
          try {
            callback();
          } catch (_) {}
        }
        clientAbortCallbacks.clear();
      }

      final attemptDio = Dio(
        BaseOptions(
          connectTimeout: connectTimeout,
        ),
      )..httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient()
            ..connectionTimeout = connectTimeout
            ..idleTimeout = keepAliveHold > Duration.zero
                ? keepAliveHold
                : const Duration(seconds: 1);
          client.findProxy = (uri) {
            if (!globalState.isAppStateInitialized) {
              attemptRoutedViaClash = false;
              return 'DIRECT';
            }
            client.userAgent = globalState.ua;
            final directive = FlClashHttpOverrides.handleFindProxy(uri);
            final isStart = globalState.appState.runTime != null;
            final tunHandlesTraffic = isStart &&
                (Platform.isAndroid ||
                    (Platform.isWindows
                        ? tunRuntime.isEnabled
                        : globalState.appState.realTunEnable));
            attemptRoutedViaClash =
                directive.startsWith('PROXY ') || tunHandlesTraffic;
            return directive;
          };
          client.connectionFactory = (uri, proxyHost, proxyPort) =>
              _openCancellableProbeConnection(
                uri: uri,
                proxyHost: proxyHost,
                proxyPort: proxyPort,
                attemptPorts: attemptPorts,
                clientAbortCallbacks: clientAbortCallbacks,
              );
          return client;
        },
      );
      try {
        final res = await attemptDio.get<Map<String, dynamic>>(
          source.key,
          cancelToken: cancelToken,
          options: Options(
            responseType: ResponseType.json,
            receiveTimeout: const Duration(seconds: 3),
          ),
        );
        if (res.statusCode == HttpStatus.ok && res.data != null) {
          final ipInfo = source.value(res.data!);
          final host = Uri.tryParse(source.key)?.host.toLowerCase() ?? '';
          holdForTelemetry =
              attemptRoutedViaClash && keepAliveHold > Duration.zero;
          if (holdForTelemetry) {
            final holdTimer = Timer(keepAliveHold, () {
              abortAllAttemptSockets();
              attemptDio.close(force: true);
            });
            if (cancelToken != null) {
              unawaited(
                cancelToken.whenCancel.then((_) {
                  holdTimer.cancel();
                  abortAllAttemptSockets();
                  attemptDio.close(force: true);
                }),
              );
            }
          }
          return Result.success((
            ipInfo: ipInfo,
            host: host,
            sourcePorts: Set<String>.unmodifiable(attemptPorts),
            routedViaClash: attemptRoutedViaClash,
          ));
        }
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) {
          return Result.error("cancelled");
        }
        // connect/receive timeout or bad status — fall through to the next source
      } catch (_) {
        // unexpected shape / parse failure — try the next source
      } finally {
        if (!holdForTelemetry) {
          abortAllAttemptSockets();
          attemptDio.close(force: true);
        }
      }
    }
    // Every source failed (offline, all timed out, or unparseable).
    return Result.success(null);
  }

  static Future<ConnectionTask<Socket>> _openCancellableProbeConnection({
    required Uri uri,
    required String? proxyHost,
    required int? proxyPort,
    required Set<String> attemptPorts,
    required List<void Function()> clientAbortCallbacks,
  }) {
    final isProxied = proxyHost != null && proxyPort != null;
    final isHttps = uri.isScheme('https');
    final targetHost = isProxied ? proxyHost : uri.host;
    final targetPort = isProxied
        ? proxyPort
        : (uri.hasPort ? uri.port : (isHttps ? 443 : 80));

    var aborted = false;
    final connectionAbortCallbacks = <void Function()>[];

    void abortConnection() {
      if (aborted) return;
      aborted = true;
      for (final callback in connectionAbortCallbacks.reversed) {
        try {
          callback();
        } catch (_) {}
      }
      connectionAbortCallbacks.clear();
    }

    clientAbortCallbacks.add(abortConnection);

    Future<Socket> openSocket() async {
      final outboundTask = await Socket.startConnect(targetHost, targetPort);
      connectionAbortCallbacks.add(outboundTask.cancel);
      if (aborted) {
        outboundTask.cancel();
        throw const SocketException('Probe connection cancelled');
      }

      final outboundSocket = await outboundTask.socket;
      unawaited(outboundSocket.done.then((_) {}, onError: (_) {}));
      connectionAbortCallbacks.add(outboundSocket.destroy);
      if (aborted) {
        outboundSocket.destroy();
        throw const SocketException('Probe connection cancelled');
      }
      attemptPorts.add(outboundSocket.port.toString());

      if (!isHttps) {
        return outboundSocket;
      }

      // `SecureSocket.secure` (used both here for direct HTTPS and inside
      // `HttpClient.createProxyTunnel` after HTTP CONNECT) detaches the raw
      // socket handle from its input `Socket`, which leaves upstream
      // `SecureSocket.startConnect` / `ConnectionTask.cancel()` unable to close
      // the underlying TCP connection once the TCP handshake has completed and
      // the peer stalls during TLS negotiation. Bridging TLS over a one-shot
      // loopback pair keeps `outboundSocket` directly destroyable on timeout or
      // cancellation while preserving full system CA and hostname/SAN validation.
      final localClient = await _bridgeSocketForTls(
        outboundSocket: outboundSocket,
        abortCallbacks: connectionAbortCallbacks,
        isAborted: () => aborted,
      );

      if (isProxied) {
        return localClient;
      }

      try {
        final tlsSocket = await SecureSocket.secure(
          localClient,
          host: uri.host,
        );
        unawaited(tlsSocket.done.then((_) {}, onError: (_) {}));
        connectionAbortCallbacks.add(tlsSocket.destroy);
        if (aborted) {
          tlsSocket.destroy();
          outboundSocket.destroy();
          throw const SocketException('Probe connection cancelled');
        }
        return tlsSocket;
      } catch (_) {
        abortConnection();
        rethrow;
      }
    }

    final socketFuture = openSocket();
    unawaited(socketFuture.then((_) {}, onError: (_) {}));
    return Future.value(ConnectionTask.fromSocket(socketFuture, abortConnection));
  }

  static Future<Socket> _bridgeSocketForTls({
    required Socket outboundSocket,
    required List<void Function()> abortCallbacks,
    required bool Function() isAborted,
  }) async {
    final bridgeServer = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    abortCallbacks.add(() {
      unawaited(bridgeServer.close());
    });
    if (isAborted()) {
      await bridgeServer.close();
      outboundSocket.destroy();
      throw const SocketException('Probe connection cancelled');
    }

    final peerCompleter = Completer<Socket>();
    late final StreamSubscription<Socket> acceptSubscription;
    acceptSubscription = bridgeServer.listen(
      (peer) {
        if (!peerCompleter.isCompleted) {
          peerCompleter.complete(peer);
        } else {
          peer.destroy();
        }
        unawaited(acceptSubscription.cancel());
        unawaited(bridgeServer.close());
      },
      onError: (error, stackTrace) {
        if (!peerCompleter.isCompleted) {
          peerCompleter.completeError(error, stackTrace);
        }
      },
    );

    final Socket localClient;
    try {
      localClient = await Socket.connect(
        InternetAddress.loopbackIPv4,
        bridgeServer.port,
      );
    } catch (_) {
      unawaited(acceptSubscription.cancel());
      unawaited(bridgeServer.close());
      outboundSocket.destroy();
      rethrow;
    }
    abortCallbacks.add(localClient.destroy);

    final bridgePeer = await peerCompleter.future;
    unawaited(bridgePeer.done.then((_) {}, onError: (_) {}));
    abortCallbacks.add(bridgePeer.destroy);

    if (isAborted()) {
      bridgePeer.destroy();
      localClient.destroy();
      outboundSocket.destroy();
      throw const SocketException('Probe connection cancelled');
    }

    outboundSocket.listen(
      (data) {
        try {
          bridgePeer.add(data);
        } catch (_) {
          outboundSocket.destroy();
          bridgePeer.destroy();
        }
      },
      onError: (_) {
        bridgePeer.destroy();
      },
      onDone: () {
        unawaited(
          bridgePeer.flush().then(
            (_) => bridgePeer.close(),
            onError: (_) {
              bridgePeer.destroy();
            },
          ),
        );
      },
    );

    bridgePeer.listen(
      (data) {
        try {
          outboundSocket.add(data);
        } catch (_) {
          bridgePeer.destroy();
          outboundSocket.destroy();
        }
      },
      onError: (_) {
        outboundSocket.destroy();
      },
      onDone: () {
        unawaited(
          outboundSocket.flush().then(
            (_) => outboundSocket.close(),
            onError: (_) {
              outboundSocket.destroy();
            },
          ),
        );
      },
    );

    return localClient;
  }

  Future<bool> pingHelper() async {
    if (Platform.isWindows) {
      return windowsHelperIsCompatible(
        readCapabilities: () async {
          final response = await _dio.get<Object?>(
            'http://$localhost:$helperPort/capabilities',
            options: Options(responseType: ResponseType.json),
          ).timeout(const Duration(seconds: 2));
          return response.statusCode == HttpStatus.ok ? response.data : null;
        },
        bundledCoreSha256: coreUpdater.calcCoreSha256,
        bundledHelper: appPath.helperPath,
        installedHelper: appPath.windowsServiceHelperPath,
        installedCore: appPath.windowsServiceCorePath,
      );
    }
    try {
      final response = await _dio
          .get(
            "http://$localhost:$helperPort/ping",
            options: Options(
              responseType: ResponseType.plain,
            ),
          )
          .timeout(
            const Duration(
              milliseconds: 2000,
            ),
          );
      if (response.statusCode != HttpStatus.ok) {
        return false;
      }
      // Compare against the binary actually on disk, not the build-time
      // constant — a separately updated core is otherwise reported as a
      // helper mismatch forever.
      final diskHash = await coreUpdater.calcCoreSha256();
      return diskHash != null && (response.data as String) == diskHash;
    } catch (_) {
      return false;
    }
  }

  Future<bool> startCoreByHelper(String arg) async {
    try {
      final homeDirPath = await appPath.homeDirPath;
      final helperToken = await _loadOrCreateHelperToken();
      if (helperToken == null) return false;
      final response = await _dio
          .post(
            "http://$localhost:$helperPort/start",
            data: json.encode({
              "path": appPath.windowsServiceCorePath,
              "arg": arg,
              "home_dir": homeDirPath,
              "helper_token": helperToken,
            }),
            options: Options(
              responseType: ResponseType.plain,
            ),
          )
          .timeout(
            const Duration(
              milliseconds: 2000,
            ),
          );
      if (response.statusCode != HttpStatus.ok) {
        commonPrint.log(formatHelperFailure(
          operation: 'start',
          statusCode: response.statusCode,
          responseBody: response.data?.toString(),
        ));
        return false;
      }
      final data = response.data as String;
      if (data.isNotEmpty) {
        commonPrint.log(formatHelperFailure(
          operation: 'start',
          statusCode: response.statusCode,
          responseBody: data,
        ));
      }
      return data.isEmpty;
    } on DioException catch (error) {
      commonPrint.log(formatHelperFailure(
        operation: 'start',
        statusCode: error.response?.statusCode,
        responseBody: error.response?.data?.toString(),
        error: error,
      ));
      return false;
    } catch (error) {
      commonPrint.log(formatHelperFailure(operation: 'start', error: error));
      return false;
    }
  }

  Future<bool> stopCoreByHelper() async {
    try {
      final helperToken = await _loadOrCreateHelperToken();
      if (helperToken == null) return false;
      final response = await _dio
          .post(
            "http://$localhost:$helperPort/stop",
            data: json.encode({
              "home_dir": await appPath.homeDirPath,
              "helper_token": helperToken,
            }),
            options: Options(responseType: ResponseType.plain),
          )
          .timeout(const Duration(milliseconds: 2000));

      if (response.statusCode != HttpStatus.ok) {
        commonPrint.log(formatHelperFailure(
          operation: 'stop',
          statusCode: response.statusCode,
          responseBody: response.data?.toString(),
        ));
        return false;
      }
      final data = response.data as String;
      if (data.isNotEmpty) {
        commonPrint.log(formatHelperFailure(
          operation: 'stop',
          statusCode: response.statusCode,
          responseBody: data,
        ));
      }
      return data.isEmpty;
    } on DioException catch (error) {
      commonPrint.log(formatHelperFailure(
        operation: 'stop',
        statusCode: error.response?.statusCode,
        responseBody: error.response?.data?.toString(),
        error: error,
      ));
      return false;
    } catch (error) {
      commonPrint.log(formatHelperFailure(operation: 'stop', error: error));
      return false;
    }
  }

  Future<String?> _loadOrCreateHelperToken() async {
    final file = File(await appPath.helperTokenPath);
    if (await file.exists()) {
      final token = await file.readAsString();
      return RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(token)
          ? token.toLowerCase()
          : null;
    }
    final random = Random.secure();
    final token = List<int>.generate(32, (_) => random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    try {
      await file.writeAsString(token, flush: true);
      return token;
    } on FileSystemException {
      // Another process may have won the create race. Accept only a complete,
      // well-formed credential and never repair an untrusted partial file.
      if (!await file.exists()) return null;
      final existing = await file.readAsString();
      return RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(existing)
          ? existing.toLowerCase()
          : null;
    }
  }

  Future<Map<String, dynamic>?> getCoreVersion() async {
    try {
      final addr = globalState.effectiveExternalController.value;
      if (addr.isEmpty) return null;
      final response = await _dio
          .get<Map<String, dynamic>>(
            "http://$addr/version",
            options: Options(
              responseType: ResponseType.json,
            ),
          )
          .timeout(const Duration(seconds: 2));

      if (response.statusCode != HttpStatus.ok) return null;
      return response.data;
    } catch (_) {
      return null;
    }
  }
}

final request = Request();

import 'dart:io';

import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/tun_runtime.dart';
import 'package:flclashx/state.dart';

class FlClashHttpOverrides extends HttpOverrides {
  static int _effectiveMixedPort() {
    final runtimeProfileId = globalState.lastRuntimeProfileId;
    final currentProfileId = globalState.config.currentProfileId;
    final profileMatches = runtimeProfileId == null ||
        (currentProfileId != null && runtimeProfileId == currentProfileId);
    final rawConfig = globalState.lastRuntimeConfig;
    if (profileMatches && rawConfig != null) {
      final rawPort = rawConfig['mixed-port'];
      final port = rawPort is num
          ? rawPort.toInt()
          : int.tryParse(rawPort?.toString().trim() ?? '');
      if (port != null && port >= 0 && port <= 65535) return port;
    }
    return globalState.config.patchClashConfig.mixedPort;
  }

  static bool _runtimeMixedPortRequiresAuthentication() {
    final authentication = globalState.lastRuntimeConfig?['authentication'];
    if (authentication is! Iterable) return false;
    return authentication.any(
      (entry) => entry?.toString().trim().isNotEmpty ?? false,
    );
  }

  static String handleFindProxy(Uri url) {
    if ([localhost].contains(url.host)) {
      return "DIRECT";
    }
    final isStart = globalState.appState.runTime != null;
    // Subscription credentials may live in either the path or query string.
    commonPrint.log("find ${url.host} proxy:$isStart");
    if (!isStart) return "DIRECT";
    // Loop prevention: clash-core outbound sockets are protected/bound outside
    // TUN (on Android via TunInterface.protect, on desktop via binding the
    // physical interface).
    //
    // On Android the service is always a VpnService (TUN), so when it's
    // running the traffic is already captured. Windows uses observed listener
    // and interface readiness. Other platforms retain their existing contract.
    final tunHandlesTraffic = Platform.isAndroid ||
        (Platform.isWindows
            ? tunRuntime.isEnabled
            : globalState.appState.realTunEnable);
    if (tunHandlesTraffic) {
      return "DIRECT";
    }
    final port = _effectiveMixedPort();
    if (port == 0 || _runtimeMixedPortRequiresAuthentication()) {
      // Mixed-port is disabled or requires credentials that Dart's bare
      // `PROXY host:port` directive cannot supply without 407 loops, and TUN
      // isn't handling traffic. Go DIRECT rather than hanging on port 0/407.
      return "DIRECT";
    }
    return "PROXY localhost:$port";
  }

  /// Bounded fallback proxy directive for Dashboard self-probes on Windows
  /// ONLY after a primary `DIRECT` pass over observed-active TUN has failed.
  static String? windowsTunLoopbackFallbackProxy(Uri url) {
    if ([localhost].contains(url.host)) {
      return null;
    }
    if (!Platform.isWindows || !globalState.isAppStateInitialized) {
      return null;
    }
    final isStart = globalState.appState.runTime != null;
    if (!isStart || !tunRuntime.isEnabled) {
      return null;
    }
    final port = _effectiveMixedPort();
    if (!globalState.config.networkProps.systemProxy ||
        port <= 0 ||
        _runtimeMixedPortRequiresAuthentication()) {
      return null;
    }
    return "PROXY 127.0.0.1:$port";
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..badCertificateCallback = ((_, __, ___) => true)
        ..findProxy = handleFindProxy;
}

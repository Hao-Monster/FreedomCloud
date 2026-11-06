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
    final port = _effectiveMixedPort();
    final canUseWindowsSystemProxy = Platform.isWindows &&
        globalState.config.networkProps.systemProxy &&
        port > 0 &&
        !_runtimeMixedPortRequiresAuthentication();

    // A TUN listener being up is not proof that this process's direct socket
    // will be captured. When Windows System Proxy is enabled, use the verified
    // local mixed port for app-owned requests so IP checks and subscription
    // requests do not silently bypass the working Core path.
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
    if (tunHandlesTraffic && !canUseWindowsSystemProxy) {
      return "DIRECT";
    }
    if (port == 0) {
      // Mixed-port is disabled and TUN isn't handling traffic — we have no
      // inbound to route through. Go DIRECT; at worst the request leaks, but
      // that's strictly better than trying PROXY localhost:0 which hangs.
      return "DIRECT";
    }
    return "PROXY 127.0.0.1:$port";
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..badCertificateCallback = ((_, __, ___) => true)
        ..findProxy = handleFindProxy;
}

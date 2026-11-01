import 'dart:io';

import 'package:flclashx/common/health/health_models.dart';
import 'package:win32_registry/win32_registry.dart';

class WindowsSystemProxySnapshot {
  const WindowsSystemProxySnapshot({
    required this.proxyEnabled,
    this.proxyServer,
    this.autoConfigUrl,
  });

  final bool proxyEnabled;
  final String? proxyServer;
  final String? autoConfigUrl;
}

class ParsedProxyEndpoint {
  const ParsedProxyEndpoint(this.host, this.port);
  final String host;
  final int port;
}

ParsedProxyEndpoint? _parseHostPort(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return null;
  final schemeSep = text.indexOf('://');
  if (schemeSep != -1) {
    text = text.substring(schemeSep + 3);
  }
  final slashIndex = text.indexOf('/');
  if (slashIndex != -1) {
    text = text.substring(0, slashIndex);
  }
  if (text.startsWith('[')) {
    final closeBracket = text.indexOf(']');
    if (closeBracket <= 1 || closeBracket + 2 > text.length) return null;
    if (text[closeBracket + 1] != ':') return null;
    final host = text.substring(1, closeBracket).trim();
    final port = int.tryParse(text.substring(closeBracket + 2).trim());
    if (host.isEmpty || port == null || port <= 0 || port > 65535) return null;
    return ParsedProxyEndpoint(host, port);
  }
  final colonIndex = text.lastIndexOf(':');
  if (colonIndex <= 0 || colonIndex + 1 >= text.length) return null;
  final host = text.substring(0, colonIndex).trim();
  final port = int.tryParse(text.substring(colonIndex + 1).trim());
  if (host.isEmpty || port == null || port <= 0 || port > 65535) return null;
  return ParsedProxyEndpoint(host, port);
}

bool _isLoopbackHost(String host) {
  final normalized = host.trim().toLowerCase();
  return normalized == '127.0.0.1' ||
      normalized == 'localhost' ||
      normalized == '::1';
}

bool _pacUrlsMatch(String? expectedRaw, String? actualRaw) {
  final expected = expectedRaw?.trim() ?? '';
  final actual = actualRaw?.trim() ?? '';
  if (expected.isEmpty || actual.isEmpty) return false;
  if (expected == actual) return true;
  final expectedUri = Uri.tryParse(expected);
  final actualUri = Uri.tryParse(actual);
  if (expectedUri == null || actualUri == null) return false;
  final sameScheme = expectedUri.scheme.toLowerCase() == actualUri.scheme.toLowerCase();
  final sameHost = (_isLoopbackHost(expectedUri.host) && _isLoopbackHost(actualUri.host)) ||
      expectedUri.host.toLowerCase() == actualUri.host.toLowerCase();
  final expectedPort = expectedUri.hasPort
      ? expectedUri.port
      : (expectedUri.scheme == 'https' ? 443 : 80);
  final actualPort = actualUri.hasPort
      ? actualUri.port
      : (actualUri.scheme == 'https' ? 443 : 80);
  return sameScheme &&
      sameHost &&
      expectedPort == actualPort &&
      expectedUri.path == actualUri.path &&
      expectedUri.query == actualUri.query;
}

Map<String, ParsedProxyEndpoint> parseWindowsProxyServer(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const {};
  final result = <String, ParsedProxyEndpoint>{};
  final segments = raw.split(';');
  for (final segment in segments) {
    final trimmed = segment.trim();
    if (trimmed.isEmpty) continue;
    final eqIndex = trimmed.indexOf('=');
    if (eqIndex > 0) {
      final scheme = trimmed.substring(0, eqIndex).trim().toLowerCase();
      final endpoint = _parseHostPort(trimmed.substring(eqIndex + 1));
      if (scheme.isNotEmpty && endpoint != null) {
        result[scheme] = endpoint;
      }
    } else {
      final endpoint = _parseHostPort(trimmed);
      if (endpoint != null) {
        result['*'] = endpoint;
      }
    }
  }
  return result;
}

({
  HealthStatus status,
  String reasonCode,
  String? localDetail,
  String? verifiedProxyDirective,
}) evaluateWindowsSystemProxy({
  required bool expectedEnabled,
  required int expectedPort,
  required bool expectedPacEnabled,
  required String? expectedPacUrl,
  required WindowsSystemProxySnapshot? snapshot,
}) {
  if (!expectedEnabled) {
    return (
      status: HealthStatus.skipped,
      reasonCode: 'systemProxyDisabledByPreference',
      localDetail: null,
      verifiedProxyDirective: null,
    );
  }
  if (snapshot == null) {
    return (
      status: HealthStatus.failed,
      reasonCode: 'systemProxyReadFailed',
      localDetail: null,
      verifiedProxyDirective: null,
    );
  }

  bool matchesExpected(ParsedProxyEndpoint? ep) =>
      ep != null && _isLoopbackHost(ep.host) && ep.port == expectedPort;

  bool manualSnapshotMatchesExpected() {
    if (expectedPort <= 0 || expectedPort > 65535) return false;
    final parsed = parseWindowsProxyServer(snapshot.proxyServer);
    if (parsed.isEmpty) return false;
    if (parsed.containsKey('*')) {
      return matchesExpected(parsed['*']);
    }
    final httpEp = parsed['http'];
    final httpsEp = parsed['https'];
    return httpEp != null &&
        httpsEp != null &&
        matchesExpected(httpEp) &&
        matchesExpected(httpsEp);
  }

  if (expectedPacEnabled) {
    if (_pacUrlsMatch(expectedPacUrl, snapshot.autoConfigUrl)) {
      if (snapshot.proxyEnabled && !manualSnapshotMatchesExpected()) {
        return (
          status: HealthStatus.warning,
          reasonCode: 'systemProxyHijacked',
          localDetail: snapshot.proxyServer,
          verifiedProxyDirective: null,
        );
      }
      final pacUri = Uri.tryParse(expectedPacUrl?.trim() ?? '');
      final isLoopbackPac = pacUri != null && _isLoopbackHost(pacUri.host);
      final pacDetail = isLoopbackPac
          ? 'PAC 127.0.0.1'
          : 'PAC (${(pacUri != null && pacUri.host.isNotEmpty) ? pacUri.host : 'auto'})';
      return (
        status: HealthStatus.passed,
        reasonCode: 'ok',
        localDetail: pacDetail,
        verifiedProxyDirective: (isLoopbackPac && expectedPort > 0)
            ? 'PROXY 127.0.0.1:$expectedPort'
            : null,
      );
    }
    final hasOtherPac = (snapshot.autoConfigUrl?.trim().isNotEmpty ?? false);
    return (
      status: HealthStatus.failed,
      reasonCode: hasOtherPac ? 'systemProxyHijacked' : 'systemProxyNotApplied',
      localDetail: null,
      verifiedProxyDirective: null,
    );
  }

  if (!snapshot.proxyEnabled) {
    return (
      status: HealthStatus.failed,
      reasonCode: 'systemProxyDisabledExternally',
      localDetail: null,
      verifiedProxyDirective: null,
    );
  }

  if (expectedPort <= 0 || expectedPort > 65535) {
    return (
      status: HealthStatus.failed,
      reasonCode: 'systemProxyInvalidPort',
      localDetail: null,
      verifiedProxyDirective: null,
    );
  }

  final parsed = parseWindowsProxyServer(snapshot.proxyServer);
  if (parsed.isEmpty) {
    return (
      status: HealthStatus.failed,
      reasonCode: 'systemProxyNotApplied',
      localDetail: null,
      verifiedProxyDirective: null,
    );
  }

  if (parsed.containsKey('*')) {
    if (!matchesExpected(parsed['*'])) {
      return (
        status: HealthStatus.failed,
        reasonCode: 'systemProxyHijacked',
        localDetail: null,
        verifiedProxyDirective: null,
      );
    }
  } else {
    final httpEp = parsed['http'];
    final httpsEp = parsed['https'];
    if (httpEp == null && httpsEp == null) {
      return (
        status: HealthStatus.failed,
        reasonCode: 'systemProxyHijacked',
        localDetail: null,
        verifiedProxyDirective: null,
      );
    }
    final httpInvalid = httpEp != null && !matchesExpected(httpEp);
    final httpsInvalid = httpsEp != null && !matchesExpected(httpsEp);
    if (httpInvalid || httpsInvalid) {
      return (
        status: HealthStatus.failed,
        reasonCode: 'systemProxyHijacked',
        localDetail: null,
        verifiedProxyDirective: null,
      );
    }
    if (httpEp == null || httpsEp == null) {
      return (
        status: HealthStatus.warning,
        reasonCode: 'systemProxyPartialScheme',
        localDetail: '127.0.0.1:$expectedPort',
        verifiedProxyDirective:
            httpsEp != null ? 'PROXY 127.0.0.1:$expectedPort' : null,
      );
    }
  }

  if (snapshot.autoConfigUrl?.trim().isNotEmpty ?? false) {
    return (
      status: HealthStatus.warning,
      reasonCode: 'systemProxyUnexpectedPac',
      localDetail: '127.0.0.1:$expectedPort',
      verifiedProxyDirective: 'PROXY 127.0.0.1:$expectedPort',
    );
  }

  return (
    status: HealthStatus.passed,
    reasonCode: 'ok',
    localDetail: '127.0.0.1:$expectedPort',
    verifiedProxyDirective: 'PROXY 127.0.0.1:$expectedPort',
  );
}

WindowsSystemProxySnapshot? readWindowsSystemProxyRegistry() {
  if (!Platform.isWindows) return null;
  const internetSettingsPath =
      r'Software\Microsoft\Windows\CurrentVersion\Internet Settings';
  RegistryKey? key;
  try {
    key = Registry.openPath(
      RegistryHive.currentUser,
      path: internetSettingsPath,
    );
    final proxyEnable = key.getIntValue('ProxyEnable') ?? 0;
    final proxyServer = key.getStringValue('ProxyServer');
    final autoConfigUrl = key.getStringValue('AutoConfigURL');
    return WindowsSystemProxySnapshot(
      proxyEnabled: proxyEnable != 0,
      proxyServer: proxyServer,
      autoConfigUrl: autoConfigUrl,
    );
  } catch (_) {
    return null;
  } finally {
    key?.close();
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AiEndpointId {
  gemini,
  claude,
  openai,
}

enum AiEndpointStatus {
  idle,
  running,
  reachable,
  regionBlocked,
  tlsOrTimeoutError,
  skipped,
}

class AiEndpointSpec {
  const AiEndpointSpec({
    required this.id,
    required this.displayName,
    required this.host,
    required this.probeUri,
  });

  final AiEndpointId id;
  final String displayName;
  final String host;
  final Uri probeUri;

  static final List<AiEndpointSpec> defaults = List<AiEndpointSpec>.unmodifiable([
    AiEndpointSpec(
      id: AiEndpointId.gemini,
      displayName: 'Gemini',
      host: 'generativelanguage.googleapis.com',
      probeUri:
          Uri.parse('https://generativelanguage.googleapis.com/v1beta/models'),
    ),
    AiEndpointSpec(
      id: AiEndpointId.claude,
      displayName: 'Claude',
      host: 'api.anthropic.com',
      probeUri: Uri.parse('https://api.anthropic.com/v1/models'),
    ),
    AiEndpointSpec(
      id: AiEndpointId.openai,
      displayName: 'OpenAI',
      host: 'api.openai.com',
      probeUri: Uri.parse('https://api.openai.com/v1/models'),
    ),
  ]);
}

class AiHttpProbeOutcome {
  const AiHttpProbeOutcome({
    this.statusCode,
    this.errorCode,
    this.detail,
  });

  final int? statusCode;
  final String? errorCode;
  final String? detail;
}

class AiEndpointProbeResult {
  const AiEndpointProbeResult({
    required this.id,
    required this.displayName,
    required this.host,
    required this.status,
    this.httpStatus,
    this.elapsedMs = 0,
    this.errorCode,
    this.detail,
  });

  final AiEndpointId id;
  final String displayName;
  final String host;
  final AiEndpointStatus status;
  final int? httpStatus;
  final int elapsedMs;
  final String? errorCode;
  final String? detail;
}

typedef AiHttpProber = Future<AiHttpProbeOutcome> Function(
  Uri uri, {
  required String explicitProxyDirective,
  required Duration timeout,
});

AiEndpointStatus classifyAiHttpOutcome(AiHttpProbeOutcome outcome) {
  final code = outcome.statusCode;
  if (code == 200 || code == 401 || code == 404) {
    return AiEndpointStatus.reachable;
  }
  if (code == 403 || code == 451) {
    return AiEndpointStatus.regionBlocked;
  }
  return AiEndpointStatus.tlsOrTimeoutError;
}

Future<AiHttpProbeOutcome> defaultAiHttpProber(
  Uri uri, {
  required String explicitProxyDirective,
  required Duration timeout,
}) async {
  final client = HttpClient()
    ..connectionTimeout = timeout
    ..badCertificateCallback = ((_, __, ___) => false)
    ..findProxy = (_) => explicitProxyDirective;
  try {
    final req = await client.getUrl(uri).timeout(timeout);
    req.followRedirects = false;
    req.headers.set(HttpHeaders.userAgentHeader, 'FreedomNet-Probe/1.0');
    final resp = await req.close().timeout(timeout);
    await resp.drain<void>().timeout(const Duration(seconds: 2)).catchError(
      (_) {},
    );
    return AiHttpProbeOutcome(statusCode: resp.statusCode);
  } on TimeoutException {
    return const AiHttpProbeOutcome(
      errorCode: 'timeout',
      detail: '连接超时',
    );
  } on HandshakeException catch (e) {
    return AiHttpProbeOutcome(
      errorCode: 'tlsHandshakeFailed',
      detail: e.message,
    );
  } on TlsException catch (e) {
    return AiHttpProbeOutcome(
      errorCode: 'tlsError',
      detail: e.message,
    );
  } on SocketException catch (e) {
    return AiHttpProbeOutcome(
      errorCode: 'socketError',
      detail: e.message,
    );
  } catch (e) {
    return AiHttpProbeOutcome(
      errorCode: 'probeFailed',
      detail: e.toString(),
    );
  } finally {
    client.close(force: true);
  }
}

class AiEndpointReachabilityRunner {
  AiEndpointReachabilityRunner({
    AiHttpProber? prober,
    List<AiEndpointSpec>? specs,
  })  : _prober = prober ?? defaultAiHttpProber,
        _specs = specs ?? AiEndpointSpec.defaults;

  final AiHttpProber _prober;
  final List<AiEndpointSpec> _specs;

  Future<List<AiEndpointProbeResult>> probeAll({
    required bool proxyStarted,
    required bool tunActive,
    required int mixedPort,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (!proxyStarted) {
      return [
        for (final spec in _specs)
          AiEndpointProbeResult(
            id: spec.id,
            displayName: spec.displayName,
            host: spec.host,
            status: AiEndpointStatus.skipped,
            errorCode: 'proxyNotRunning',
            detail: '代理未启动',
          ),
      ];
    }

    final proxyDirective = (!tunActive && mixedPort > 0)
        ? 'PROXY 127.0.0.1:$mixedPort'
        : 'DIRECT';

    return Future.wait([
      for (final spec in _specs) _probeOne(spec, proxyDirective, timeout),
    ]);
  }

  Future<AiEndpointProbeResult> _probeOne(
    AiEndpointSpec spec,
    String proxyDirective,
    Duration timeout,
  ) async {
    final watch = Stopwatch()..start();
    final outcome = await _prober(
      spec.probeUri,
      explicitProxyDirective: proxyDirective,
      timeout: timeout,
    );
    final elapsed = watch.elapsedMilliseconds;
    final status = classifyAiHttpOutcome(outcome);
    return AiEndpointProbeResult(
      id: spec.id,
      displayName: spec.displayName,
      host: spec.host,
      status: status,
      httpStatus: outcome.statusCode,
      elapsedMs: elapsed,
      errorCode: outcome.errorCode ??
          (outcome.statusCode != null ? 'http_${outcome.statusCode}' : null),
      detail: outcome.detail,
    );
  }
}

enum CliProxyCheckSeverity {
  ok,
  warning,
  info,
}

class CliProxyDiagnosticItem {
  const CliProxyDiagnosticItem({
    required this.id,
    required this.title,
    required this.summary,
    required this.severity,
    this.observedValue,
  });

  final String id;
  final String title;
  final String summary;
  final CliProxyCheckSeverity severity;
  final String? observedValue;
}

class CliProxyDiagnosticReport {
  const CliProxyDiagnosticReport({
    required this.effectivePort,
    required this.proxyStarted,
    required this.tunEnabled,
    required this.allowLan,
    required this.items,
    required this.powershellSnippet,
    required this.bashSnippet,
    required this.wslSnippet,
    required this.gitSnippet,
    this.wslGatewayIp,
  });

  final int effectivePort;
  final bool proxyStarted;
  final bool tunEnabled;
  final bool allowLan;
  final String? wslGatewayIp;
  final List<CliProxyDiagnosticItem> items;
  final String powershellSnippet;
  final String bashSnippet;
  final String wslSnippet;
  final String gitSnippet;

  String get combinedCopyText {
    final buf = StringBuffer()
      ..writeln('# FreedomNet CLI / Git / WSL2 代理环境配置 (端口 $effectivePort)')
      ..writeln()
      ..writeln('## PowerShell:')
      ..writeln(powershellSnippet)
      ..writeln()
      ..writeln('## Bash / Zsh:')
      ..writeln(bashSnippet);
    if (wslGatewayIp != null && wslGatewayIp!.isNotEmpty) {
      buf
        ..writeln()
        ..writeln('## WSL2 NAT (宿主机网关 $wslGatewayIp):')
        ..writeln(wslSnippet);
    }
    buf
      ..writeln()
      ..writeln('## Git 全局代理:')
      ..writeln(gitSnippet);
    return buf.toString().trimRight();
  }
}

class CliProxyDiagnosticsRunner {
  CliProxyDiagnosticsRunner({
    Map<String, String> Function()? envReader,
    Future<String?> Function(String key)? gitConfigReader,
    Future<String?> Function()? wslGatewayReader,
  })  : _envReader = envReader ?? (() => Platform.environment),
        _gitConfigReader = gitConfigReader ?? _defaultReadGitConfig,
        _wslGatewayReader = wslGatewayReader ?? _defaultDetectWslGateway;

  final Map<String, String> Function() _envReader;
  final Future<String?> Function(String key) _gitConfigReader;
  final Future<String?> Function() _wslGatewayReader;

  static Future<String?> _defaultReadGitConfig(String key) async {
    try {
      final result = await Process.run(
        'git',
        ['config', '--global', '--get', key],
        runInShell: false,
      ).timeout(const Duration(seconds: 2));
      if (result.exitCode != 0) return null;
      final value = result.stdout.toString().trim();
      return value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _defaultDetectWslGateway() async {
    if (!Platform.isWindows) return null;
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      ).timeout(const Duration(seconds: 2));
      for (final iface in interfaces) {
        final lower = iface.name.toLowerCase();
        if (lower.contains('wsl') && iface.addresses.isNotEmpty) {
          return iface.addresses.first.address;
        }
      }
    } catch (_) {
      // Ignore interface enumeration failures cleanly.
    }
    return null;
  }

  static String? _readEnvCaseInsensitive(
    Map<String, String> env,
    String upper,
    String lower,
  ) {
    final a = env[upper]?.trim();
    if (a != null && a.isNotEmpty) return a;
    final b = env[lower]?.trim();
    if (b != null && b.isNotEmpty) return b;
    return null;
  }

  static bool _matchesExpectedLocalPort(String? value, int port) {
    if (value == null || value.isEmpty) return false;
    final uri = Uri.tryParse(value.contains('://') ? value : 'http://$value');
    if (uri == null || uri.port != port) return false;
    final host = uri.host.toLowerCase();
    return host == '127.0.0.1' || host == 'localhost' || host == '::1';
  }

  Future<CliProxyDiagnosticReport> diagnose({
    required int mixedPort,
    required bool proxyStarted,
    required bool tunEnabled,
    required bool allowLan,
  }) async {
    final effectivePort = mixedPort > 0 ? mixedPort : 7890;
    final env = _envReader();
    final httpProxy = _readEnvCaseInsensitive(env, 'HTTP_PROXY', 'http_proxy');
    final httpsProxy =
        _readEnvCaseInsensitive(env, 'HTTPS_PROXY', 'https_proxy');
    final allProxy = _readEnvCaseInsensitive(env, 'ALL_PROXY', 'all_proxy');

    final gitResults = await Future.wait([
      _gitConfigReader('http.proxy'),
      _gitConfigReader('https.proxy'),
      _wslGatewayReader(),
    ]);
    final gitHttp = gitResults[0]?.trim();
    final gitHttps = gitResults[1]?.trim();
    final wslIp = gitResults[2]?.trim();

    final items = <CliProxyDiagnosticItem>[];

    // 1. CLI Environment Variables
    final hasAnyEnv =
        httpProxy != null || httpsProxy != null || allProxy != null;
    final envMatches = (httpProxy == null ||
            _matchesExpectedLocalPort(httpProxy, effectivePort)) &&
        (httpsProxy == null ||
            _matchesExpectedLocalPort(httpsProxy, effectivePort)) &&
        (allProxy == null ||
            _matchesExpectedLocalPort(allProxy, effectivePort));
    final observedEnvDesc = [
      if (httpProxy != null) 'HTTP_PROXY=$httpProxy',
      if (httpsProxy != null) 'HTTPS_PROXY=$httpsProxy',
      if (allProxy != null) 'ALL_PROXY=$allProxy',
    ].join('; ');

    if (!hasAnyEnv) {
      items.add(
        CliProxyDiagnosticItem(
          id: 'cliEnv',
          title: '终端环境变量 (HTTP_PROXY / HTTPS_PROXY / ALL_PROXY)',
          summary: tunEnabled
              ? '未设置代理环境变量（当前已启用 TUN 接管，大多数 CLI 可直接走 TUN；若仍直连可复制下方命令）。'
              : '未设置代理环境变量，且未启用 TUN 时终端工具（Codex/Claude/curl）可能无法走代理。',
          severity: tunEnabled
              ? CliProxyCheckSeverity.info
              : CliProxyCheckSeverity.warning,
        ),
      );
    } else if (!envMatches) {
      items.add(
        CliProxyDiagnosticItem(
          id: 'cliEnv',
          title: '终端环境变量 (HTTP_PROXY / HTTPS_PROXY / ALL_PROXY)',
          summary: '检测到代理环境变量与当前混合端口 $effectivePort 不一致，可能导致终端断网。',
          severity: CliProxyCheckSeverity.warning,
          observedValue: observedEnvDesc,
        ),
      );
    } else {
      items.add(
        CliProxyDiagnosticItem(
          id: 'cliEnv',
          title: '终端环境变量 (HTTP_PROXY / HTTPS_PROXY / ALL_PROXY)',
          summary: '已正确指向本地代理端口 $effectivePort。',
          severity: CliProxyCheckSeverity.ok,
          observedValue: observedEnvDesc,
        ),
      );
    }

    // 2. Git global proxy
    final hasGit = (gitHttp != null && gitHttp.isNotEmpty) ||
        (gitHttps != null && gitHttps.isNotEmpty);
    final gitMatches = (gitHttp == null ||
            gitHttp.isEmpty ||
            _matchesExpectedLocalPort(gitHttp, effectivePort)) &&
        (gitHttps == null ||
            gitHttps.isEmpty ||
            _matchesExpectedLocalPort(gitHttps, effectivePort));
    final observedGit = [
      if (gitHttp != null && gitHttp.isNotEmpty) 'http.proxy=$gitHttp',
      if (gitHttps != null && gitHttps.isNotEmpty) 'https.proxy=$gitHttps',
    ].join('; ');

    if (!hasGit) {
      items.add(
        CliProxyDiagnosticItem(
          id: 'gitProxy',
          title: 'Git 全局代理 (git config --global http.proxy)',
          summary: tunEnabled
              ? '未单独配置 Git 全局代理（TUN 开启时通常直接生效，如需显式配置可一键复制）。'
              : '未配置 Git 全局代理；关闭 TUN 时建议配置 http.proxy/https.proxy 指向 127.0.0.1:$effectivePort。',
          severity: tunEnabled
              ? CliProxyCheckSeverity.info
              : CliProxyCheckSeverity.warning,
        ),
      );
    } else if (!gitMatches) {
      items.add(
        CliProxyDiagnosticItem(
          id: 'gitProxy',
          title: 'Git 全局代理 (git config --global http.proxy)',
          summary: 'Git 全局代理端口与当前端口 $effectivePort 不匹配（可能是旧端口残留）。',
          severity: CliProxyCheckSeverity.warning,
          observedValue: observedGit,
        ),
      );
    } else {
      items.add(
        CliProxyDiagnosticItem(
          id: 'gitProxy',
          title: 'Git 全局代理 (git config --global http.proxy)',
          summary: 'Git 全局代理已指向 127.0.0.1:$effectivePort。',
          severity: CliProxyCheckSeverity.ok,
          observedValue: observedGit,
        ),
      );
    }

    // 3. WSL2 gateway host check
    if (wslIp != null && wslIp.isNotEmpty) {
      items.add(
        CliProxyDiagnosticItem(
          id: 'wsl2Gateway',
          title: 'WSL2 宿主机网关检测',
          summary: allowLan
              ? '检测到 WSL2 虚拟网卡网关 $wslIp，且已开启允许局域网连接 (allow-lan)，WSL2 可直接连接 http://$wslIp:$effectivePort。'
              : '检测到 WSL2 虚拟网卡网关 $wslIp，但尚未开启“允许局域网连接”，WSL2 NAT 模式将无法访问宿主机代理端口。',
          severity: allowLan
              ? CliProxyCheckSeverity.ok
              : CliProxyCheckSeverity.warning,
          observedValue: 'WSL2 宿主机网关: $wslIp (allow-lan=$allowLan)',
        ),
      );
    } else {
      items.add(
        CliProxyDiagnosticItem(
          id: 'wsl2Gateway',
          title: 'WSL2 宿主机网关检测',
          summary: '未检测到独立 WSL2 NAT 虚拟网卡（若使用 WSL2 Mirrored 模式可直接用 127.0.0.1:$effectivePort）。',
          severity: CliProxyCheckSeverity.info,
        ),
      );
    }

    final powershellSnippet =
        '\$env:HTTP_PROXY="http://127.0.0.1:$effectivePort"\n'
        '\$env:HTTPS_PROXY="http://127.0.0.1:$effectivePort"\n'
        '\$env:ALL_PROXY="socks5://127.0.0.1:$effectivePort"';
    final bashSnippet =
        'export HTTP_PROXY="http://127.0.0.1:$effectivePort"\n'
        'export HTTPS_PROXY="http://127.0.0.1:$effectivePort"\n'
        'export ALL_PROXY="socks5://127.0.0.1:$effectivePort"';
    final wslHost = (wslIp != null && wslIp.isNotEmpty) ? wslIp : '127.0.0.1';
    final wslSnippet =
        'export HTTP_PROXY="http://$wslHost:$effectivePort"\n'
        'export HTTPS_PROXY="http://$wslHost:$effectivePort"\n'
        'export ALL_PROXY="socks5://$wslHost:$effectivePort"';
    final gitSnippet =
        'git config --global http.proxy http://127.0.0.1:$effectivePort\n'
        'git config --global https.proxy http://127.0.0.1:$effectivePort';

    return CliProxyDiagnosticReport(
      effectivePort: effectivePort,
      proxyStarted: proxyStarted,
      tunEnabled: tunEnabled,
      allowLan: allowLan,
      wslGatewayIp: (wslIp != null && wslIp.isNotEmpty) ? wslIp : null,
      items: List<CliProxyDiagnosticItem>.unmodifiable(items),
      powershellSnippet: powershellSnippet,
      bashSnippet: bashSnippet,
      wslSnippet: wslSnippet,
      gitSnippet: gitSnippet,
    );
  }
}

final aiEndpointRunnerProvider = Provider<AiEndpointReachabilityRunner>(
  (ref) => AiEndpointReachabilityRunner(),
);

final cliProxyDiagnosticsRunnerProvider = Provider<CliProxyDiagnosticsRunner>(
  (ref) => CliProxyDiagnosticsRunner(),
);

final aiAutoProbeOnOpenProvider = Provider<bool>(
  (ref) => !Platform.environment.containsKey('FLUTTER_TEST'),
);

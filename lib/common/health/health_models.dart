import 'dart:async';

import 'package:flclashx/enum/enum.dart';

enum HealthLayer {
  configAndSubscription,
  coreEngine,
  trafficTakeover,
  networkLink,
}

enum HealthCheckId {
  profileSelected(HealthLayer.configAndSubscription),
  subscriptionHealth(HealthLayer.configAndSubscription),
  runtimeConfigLoaded(HealthLayer.configAndSubscription),
  coreResponsive(HealthLayer.coreEngine),
  proxyStarted(HealthLayer.trafficTakeover),
  tunTakeover(HealthLayer.trafficTakeover),
  systemProxyTakeover(HealthLayer.trafficTakeover),
  trafficTakeover(HealthLayer.trafficTakeover),
  directConnectivity(HealthLayer.networkLink),
  dnsResolution(HealthLayer.networkLink),
  outboundConnectivity(HealthLayer.networkLink),
  endToEndConnectivity(HealthLayer.networkLink);

  const HealthCheckId(this.layer);
  final HealthLayer layer;
}

enum HealthStatus {
  running,
  passed,
  warning,
  failed,
  timeout,
  skipped;

  bool get isFailure => this == HealthStatus.failed || this == HealthStatus.timeout;
  bool get isTerminal => this != HealthStatus.running;
}

enum HealthAction {
  openProfiles,
  openPurchase,
  openProxies,
  openTunSettings,
  openNetworkSettings,
  openDnsSettings,
  startProxy,
  restartCore,
}

class HealthCheckResult {
  const HealthCheckResult({
    required this.id,
    required this.status,
    required this.elapsedMs,
    required this.reasonCode,
    this.localDetail,
    this.action,
    this.daysRemaining,
    this.quotaUsedPercent,
    this.groupCount,
    this.memoryMb,
    this.nodeName,
    this.delayMs,
    this.exitCountryCode,
  });

  final HealthCheckId id;
  final HealthStatus status;
  final int elapsedMs;

  /// Closed ASCII identifier safe for redacted export.
  final String reasonCode;

  /// Local UI-only evidence summary (e.g. profile label, port). Never exported.
  final String? localDetail;

  final HealthAction? action;

  /// Optional structured parameters for localized UI rendering. Never exported.
  final int? daysRemaining;
  final int? quotaUsedPercent;
  final int? groupCount;
  final double? memoryMb;
  final String? nodeName;
  final int? delayMs;
  final String? exitCountryCode;
}

enum HealthVerdictSeverity {
  healthy,
  warning,
  failed,
}

class HealthVerdict {
  const HealthVerdict({
    required this.code,
    required this.severity,
    this.primaryCheckId,
    this.primaryAction,
    this.activeNodeName,
    this.outboundDelayMs,
    this.directDelayMs,
    this.exitCountryCode,
    this.mode = Mode.rule,
  });

  final String code;
  final HealthVerdictSeverity severity;
  final HealthCheckId? primaryCheckId;
  final HealthAction? primaryAction;
  final String? activeNodeName;
  final int? outboundDelayMs;
  final int? directDelayMs;
  final String? exitCountryCode;
  final Mode mode;
}

class HealthReport {
  const HealthReport({
    required this.startedAt,
    required this.completedAt,
    required this.totalElapsedMs,
    required this.mode,
    required this.platform,
    required this.appVersion,
    required this.checks,
    required this.verdict,
  });

  final DateTime startedAt;
  final DateTime completedAt;
  final int totalElapsedMs;
  final Mode mode;
  final String platform;
  final String appVersion;
  final List<HealthCheckResult> checks;
  final HealthVerdict verdict;

  HealthCheckResult? checkById(HealthCheckId id) {
    for (final item in checks) {
      if (item.id == id) return item;
    }
    return null;
  }
}

class HealthCancellationToken {
  bool _cancelled = false;
  final Completer<void> _completer = Completer<void>();
  final List<FutureOr<void> Function()> _callbacks = [];

  bool get isCancelled => _cancelled;
  Future<void> get onCancelled => _completer.future;

  void register(FutureOr<void> Function() callback) {
    if (_cancelled) {
      unawaited(Future<void>.sync(callback).catchError((Object _) {}));
      return;
    }
    _callbacks.add(callback);
  }

  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    if (!_completer.isCompleted) {
      _completer.complete();
    }
    final pending = List<FutureOr<void> Function()>.from(_callbacks.reversed);
    _callbacks.clear();
    for (final callback in pending) {
      try {
        await callback();
      } catch (_) {}
    }
  }
}

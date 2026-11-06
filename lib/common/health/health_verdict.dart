import 'package:flclashx/common/health/health_models.dart';
import 'package:flclashx/enum/enum.dart';

HealthVerdict computeHealthVerdict(
  List<HealthCheckResult> checks, {
  Mode mode = Mode.rule,
  String? activeNodeName,
  int? outboundDelayMs,
  int? directDelayMs,
  String? exitCountryCode,
}) {
  final byId = <HealthCheckId, HealthCheckResult>{
    for (final item in checks) item.id: item,
  };

  HealthCheckResult? get(HealthCheckId id) => byId[id];
  bool failed(HealthCheckId id) => get(id)?.status.isFailure ?? false;

  // Priority 1: Core unresponsive
  if (failed(HealthCheckId.coreResponsive)) {
    return HealthVerdict(
      code: 'coreUnresponsive',
      severity: HealthVerdictSeverity.failed,
      primaryCheckId: HealthCheckId.coreResponsive,
      primaryAction: get(HealthCheckId.coreResponsive)?.action ?? HealthAction.restartCore,
      mode: mode,
    );
  }

  // Priority 2: No valid profile or profile file missing
  if (failed(HealthCheckId.profileSelected)) {
    return HealthVerdict(
      code: 'profileMissing',
      severity: HealthVerdictSeverity.failed,
      primaryCheckId: HealthCheckId.profileSelected,
      primaryAction: get(HealthCheckId.profileSelected)?.action ?? HealthAction.openProfiles,
      mode: mode,
    );
  }

  // Priority 3: Subscription expired or quota exhausted
  if (failed(HealthCheckId.subscriptionHealth)) {
    final sub = get(HealthCheckId.subscriptionHealth)!;
    final code = sub.reasonCode == 'subscriptionTrafficExhausted'
        ? 'subscriptionExhausted'
        : 'subscriptionExpired';
    return HealthVerdict(
      code: code,
      severity: HealthVerdictSeverity.failed,
      primaryCheckId: HealthCheckId.subscriptionHealth,
      primaryAction: sub.action ?? HealthAction.openPurchase,
      mode: mode,
    );
  }

  // Priority 4: Proxy not started
  if (failed(HealthCheckId.proxyStarted)) {
    return HealthVerdict(
      code: 'proxyNotStarted',
      severity: HealthVerdictSeverity.failed,
      primaryCheckId: HealthCheckId.proxyStarted,
      primaryAction: get(HealthCheckId.proxyStarted)?.action ?? HealthAction.startProxy,
      mode: mode,
    );
  }

  // Priority 5: Traffic capture failed
  if (failed(HealthCheckId.trafficTakeover)) {
    final takeover = get(HealthCheckId.trafficTakeover)!;
    final tunFailed = failed(HealthCheckId.tunTakeover);
    return HealthVerdict(
      code: 'takeoverFailed',
      severity: HealthVerdictSeverity.failed,
      primaryCheckId: tunFailed
          ? HealthCheckId.tunTakeover
          : (failed(HealthCheckId.systemProxyTakeover)
              ? HealthCheckId.systemProxyTakeover
              : HealthCheckId.trafficTakeover),
      primaryAction: takeover.action ??
          (tunFailed ? HealthAction.openTunSettings : HealthAction.openNetworkSettings),
      mode: mode,
    );
  }

  // Priority 6: Local physical network down (only when proxy outbound / E2E has
  // not already proven that physical uplink reaches remote servers).
  final outboundStatus = get(HealthCheckId.outboundConnectivity)?.status;
  final e2eStatus = get(HealthCheckId.endToEndConnectivity)?.status;
  final uplinkProvenByProxy = outboundStatus == HealthStatus.passed ||
      outboundStatus == HealthStatus.warning ||
      e2eStatus == HealthStatus.passed;
  if (failed(HealthCheckId.directConnectivity) && !uplinkProvenByProxy) {
    return HealthVerdict(
      code: 'localNetworkDown',
      severity: HealthVerdictSeverity.failed,
      primaryCheckId: HealthCheckId.directConnectivity,
      primaryAction: null,
      mode: mode,
    );
  }

  // Priority 7: Direct network OK/skipped, active outbound node failed
  if (failed(HealthCheckId.outboundConnectivity)) {
    final outbound = get(HealthCheckId.outboundConnectivity)!;
    return HealthVerdict(
      code: 'outboundNodeFailed',
      severity: HealthVerdictSeverity.failed,
      primaryCheckId: HealthCheckId.outboundConnectivity,
      primaryAction: outbound.action ?? HealthAction.openProxies,
      activeNodeName: activeNodeName ?? outbound.nodeName,
      mode: mode,
    );
  }

  // Priority 8: End-to-end check failed or bypassed Core
  final e2e = get(HealthCheckId.endToEndConnectivity);
  if (e2e != null) {
    if (e2e.status.isFailure) {
      return HealthVerdict(
        code: 'endToEndFailed',
        severity: HealthVerdictSeverity.failed,
        primaryCheckId: HealthCheckId.endToEndConnectivity,
        primaryAction: e2e.action ?? HealthAction.openProxies,
        activeNodeName: activeNodeName,
        outboundDelayMs: outboundDelayMs,
        mode: mode,
      );
    }
    if (e2e.status == HealthStatus.warning &&
        e2e.reasonCode == 'trafficBypassedCore') {
      return HealthVerdict(
        code: 'trafficBypassed',
        severity: HealthVerdictSeverity.warning,
        primaryCheckId: HealthCheckId.endToEndConnectivity,
        primaryAction: e2e.action ?? HealthAction.openTunSettings,
        activeNodeName: activeNodeName,
        outboundDelayMs: outboundDelayMs,
        mode: mode,
      );
    }
  }

  // Priority 9: DNS lookup failed or poisoned
  if (failed(HealthCheckId.dnsResolution)) {
    return HealthVerdict(
      code: 'dnsFailed',
      severity: HealthVerdictSeverity.failed,
      primaryCheckId: HealthCheckId.dnsResolution,
      primaryAction: get(HealthCheckId.dnsResolution)?.action ?? HealthAction.openDnsSettings,
      mode: mode,
    );
  }

  // Priority 10: Any warning present (or direct probe failed/timed out while
  // physical uplink is already proven healthy by proxy outbound / E2E).
  for (final item in checks) {
    if (item.status == HealthStatus.warning) {
      return HealthVerdict(
        code: 'healthyWithWarnings',
        severity: HealthVerdictSeverity.warning,
        primaryCheckId: item.id,
        primaryAction: item.action,
        activeNodeName: activeNodeName,
        outboundDelayMs: outboundDelayMs,
        directDelayMs: directDelayMs,
        exitCountryCode: exitCountryCode,
        mode: mode,
      );
    }
  }
  if (failed(HealthCheckId.directConnectivity) && uplinkProvenByProxy) {
    return HealthVerdict(
      code: 'healthyWithWarnings',
      severity: HealthVerdictSeverity.warning,
      primaryCheckId: HealthCheckId.directConnectivity,
      primaryAction: get(HealthCheckId.directConnectivity)?.action,
      activeNodeName: activeNodeName,
      outboundDelayMs: outboundDelayMs,
      directDelayMs: directDelayMs,
      exitCountryCode: exitCountryCode,
      mode: mode,
    );
  }

  // Priority 11: All applicable checks passed
  return HealthVerdict(
    code: 'healthy',
    severity: HealthVerdictSeverity.healthy,
    activeNodeName: activeNodeName,
    outboundDelayMs: outboundDelayMs,
    directDelayMs: directDelayMs,
    exitCountryCode: exitCountryCode,
    mode: mode,
  );
}

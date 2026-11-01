import 'dart:convert';
import 'dart:typed_data';

import 'package:flclashx/common/health/health_models.dart';
import 'package:flclashx/l10n/l10n.dart';

/// Exports ONLY a closed, credential-free, address-free schema (v2).
/// Never append `localDetail`, node names, profile names, IP addresses,
/// domain names, subscription URLs, or exception strings.
Uint8List exportHealthReport(HealthReport report) {
  final payload = <String, Object>{
    'schema': 2,
    'createdAt': report.completedAt.toUtc().toIso8601String(),
    'appVersion': report.appVersion,
    'platform': report.platform,
    'mode': report.mode.name,
    'totalElapsedMs': report.totalElapsedMs,
    'verdict': <String, Object>{
      'code': report.verdict.code,
      'severity': report.verdict.severity.name,
    },
    'checks': [
      for (final check in report.checks)
        <String, Object>{
          'id': check.id.name,
          'status': check.status.name,
          'reasonCode': check.reasonCode,
          'elapsedMs': check.elapsedMs,
        },
    ],
  };
  return Uint8List.fromList(
    utf8.encode(const JsonEncoder.withIndent('  ').convert(payload)),
  );
}

String healthCheckItemTitle(HealthCheckId id, AppLocalizations l10n) =>
    switch (id) {
      HealthCheckId.profileSelected => l10n.healthItemProfileSelected,
      HealthCheckId.subscriptionHealth => l10n.healthItemSubscription,
      HealthCheckId.runtimeConfigLoaded => l10n.healthItemRuntimeConfig,
      HealthCheckId.coreResponsive => l10n.healthItemCoreResponsive,
      HealthCheckId.proxyStarted => l10n.healthItemProxyStarted,
      HealthCheckId.tunTakeover => l10n.healthItemTunTakeover,
      HealthCheckId.systemProxyTakeover => l10n.healthItemSystemProxy,
      HealthCheckId.trafficTakeover => l10n.healthItemTrafficTakeover,
      HealthCheckId.directConnectivity => l10n.healthItemDirect,
      HealthCheckId.dnsResolution => l10n.healthItemDns,
      HealthCheckId.outboundConnectivity => l10n.healthItemOutbound,
      HealthCheckId.endToEndConnectivity => l10n.healthItemEndToEnd,
    };

String healthStatusLabel(HealthStatus status, AppLocalizations l10n) =>
    switch (status) {
      HealthStatus.running => l10n.healthStatusRunning,
      HealthStatus.passed => l10n.healthStatusPassed,
      HealthStatus.warning => l10n.healthStatusWarning,
      HealthStatus.failed => l10n.healthStatusFailed,
      HealthStatus.timeout => l10n.healthStatusTimeout,
      HealthStatus.skipped => l10n.healthStatusSkipped,
    };

String healthVerdictHeadline(HealthVerdict verdict, AppLocalizations l10n) =>
    switch (verdict.code) {
      'healthy' => l10n.healthVerdictHealthyTitle,
      'coreUnresponsive' => l10n.healthVerdictCoreUnresponsive,
      'profileMissing' => l10n.healthVerdictProfileMissing,
      'subscriptionExpired' => l10n.healthVerdictSubscriptionExpired,
      'subscriptionExhausted' => l10n.healthVerdictSubscriptionExhausted,
      'proxyNotStarted' => l10n.healthVerdictProxyNotStarted,
      'takeoverFailed' => l10n.healthVerdictTakeoverFailed,
      'localNetworkDown' => l10n.healthVerdictLocalNetworkDown,
      'outboundNodeFailed' => l10n.healthVerdictOutboundFailed,
      'trafficBypassed' => l10n.healthVerdictTrafficBypassed,
      'endToEndFailed' => l10n.healthVerdictEndToEndFailed,
      'dnsFailed' => l10n.healthVerdictDnsFailed,
      'healthyWithWarnings' => l10n.healthVerdictWarningsTitle,
      _ => l10n.healthVerdictWarningsTitle,
    };

String formatHealthSummaryText(HealthReport report, AppLocalizations l10n) {
  final buffer = StringBuffer()
    ..writeln(
      '${l10n.healthCheckTitle}: ${healthVerdictHeadline(report.verdict, l10n)} (${report.totalElapsedMs} ms)',
    );
  for (final check in report.checks) {
    buffer.writeln(
      '- ${healthCheckItemTitle(check.id, l10n)}: '
      '${healthStatusLabel(check.status, l10n)} '
      '[${check.reasonCode}] (${check.elapsedMs} ms)',
    );
  }
  return buffer.toString().trimRight();
}

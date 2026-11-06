import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/health/health_export.dart';
import 'package:flclashx/common/health/health_models.dart';
import 'package:flclashx/common/health/health_runner.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/manager/proxy_manager.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/views/config/dns.dart';
import 'package:flclashx/views/config/network.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> openHealthCheck(
  BuildContext context, {
  void Function(HealthAction action)? onAction,
}) =>
    showExtend<void>(
      context,
      props: const ExtendProps(maxWidth: 460),
      builder: (_, type) => HealthCheckView(
        type: type,
        onAction: onAction,
      ),
    );

String _countryCodeToFlag(String code) {
  final upper = code.trim().toUpperCase();
  if (upper.length != 2) return upper;
  final c0 = upper.codeUnitAt(0);
  final c1 = upper.codeUnitAt(1);
  if (c0 < 0x41 || c0 > 0x5A || c1 < 0x41 || c1 > 0x5A) return upper;
  return String.fromCharCode(c0 - 0x41 + 0x1F1E6) +
      String.fromCharCode(c1 - 0x41 + 0x1F1E6);
}

String healthActionLabel(HealthAction action, AppLocalizations l10n) =>
    switch (action) {
      HealthAction.openProfiles => l10n.healthActionOpenProfiles,
      HealthAction.openPurchase => l10n.healthActionOpenPurchase,
      HealthAction.openProxies => l10n.healthActionOpenProxies,
      HealthAction.openTunSettings => l10n.healthActionOpenTun,
      HealthAction.openNetworkSettings => l10n.healthActionOpenNetwork,
      HealthAction.openDnsSettings => l10n.healthActionOpenDns,
      HealthAction.reapplySystemProxy => l10n.healthActionReapplySystemProxy,
      HealthAction.startProxy => l10n.healthActionStartProxy,
      HealthAction.restartCore => l10n.healthActionRestartCore,
    };

String healthLayerTitle(HealthLayer layer, AppLocalizations l10n) =>
    switch (layer) {
      HealthLayer.configAndSubscription => l10n.healthLayerConfig,
      HealthLayer.coreEngine => l10n.healthLayerCore,
      HealthLayer.trafficTakeover => l10n.healthLayerTakeover,
      HealthLayer.networkLink => l10n.healthLayerNetwork,
    };

String _withOptionalDetail(String base, String? detail) {
  final trimmed = detail?.trim();
  if (trimmed == null || trimmed.isEmpty) return base;
  return '$base ($trimmed)';
}

String healthCheckItemDetail(HealthCheckResult result, AppLocalizations l10n) {
  if (result.status == HealthStatus.running) {
    return l10n.healthStatusRunning;
  }
  switch (result.reasonCode) {
    case 'cancelled':
      return l10n.healthDetailCancelled;
    case 'prerequisiteFailed':
    case 'coreUnavailable':
    case 'runtimeNotLoaded':
      return l10n.healthDetailSkipPrerequisite;
    case 'proxyNotRunning':
      return l10n.healthDetailSkipProxyStopped;
    case 'directModeActive':
      return l10n.healthDetailDirectMode;
  }

  return switch (result.id) {
    HealthCheckId.profileSelected => switch (result.reasonCode) {
        'ok' => result.localDetail ?? l10n.healthStatusPassed,
        'profileFileMissing' => l10n.healthDetailProfileFileMissing,
        _ => l10n.healthDetailNoProfile,
      },
    HealthCheckId.subscriptionHealth => switch (result.reasonCode) {
        'localProfile' => l10n.healthDetailLocalProfile,
        'subscriptionNeverSynced' => l10n.healthDetailSubNeverSynced,
        'subscriptionMetadataUnavailable' => l10n.healthDetailSubNoMeta,
        'subscriptionEternalUnlimited' => l10n.healthDetailSubHealthyEternal,
        'subscriptionExpired' => l10n.healthDetailSubExpired,
        'subscriptionTrafficExhausted' => l10n.healthDetailSubExhausted,
        'subscriptionExpiringSoon' =>
          l10n.healthDetailSubExpiringSoon(result.daysRemaining ?? 0),
        'subscriptionTrafficLow' =>
          l10n.healthDetailSubTrafficLow(result.quotaUsedPercent ?? 90),
        'subscriptionDeviceLimit' => l10n.healthDetailSubDeviceLimit,
        _ => _formatHealthySubscription(result, l10n),
      },
    HealthCheckId.runtimeConfigLoaded => switch (result.reasonCode) {
        'ok' => l10n.healthDetailRuntimeSynced(result.groupCount ?? 0),
        _ => l10n.healthDetailRuntimeMismatch,
      },
    HealthCheckId.coreResponsive => switch (result.reasonCode) {
        'ok' =>
          l10n.healthDetailCoreHealthy((result.memoryMb ?? 0).toStringAsFixed(1)),
        'coreSlowResponse' => l10n.healthDetailCoreSlow,
        _ => l10n.healthDetailCoreFailed,
      },
    HealthCheckId.proxyStarted => result.reasonCode == 'ok'
        ? l10n.healthDetailProxyRunning
        : l10n.healthDetailProxyStopped,
    HealthCheckId.tunTakeover => switch (result.reasonCode) {
        'tunReadyElevated' => l10n.healthDetailTunReadyElevated,
        'ok' => l10n.healthDetailTunReady,
        'tunDisabledByPreference' => l10n.healthDetailTunDisabled,
        'tunAuthorizationRequired' => l10n.tunErrorAuthorization,
        'tunComponentsMismatch' => l10n.tunErrorComponents,
        'tunLegacyAgent' => l10n.tunErrorLegacyAgent,
        'tunConfigurationFailed' => l10n.tunErrorConfiguration,
        'tunStatusUnavailable' => l10n.tunErrorUnavailable,
        'tunCloseFailed' => l10n.tunErrorStop,
        _ => l10n.tunErrorStart,
      },
    HealthCheckId.systemProxyTakeover => switch (result.reasonCode) {
        'systemProxyDisabledByPreference' => l10n.healthDetailSysProxyDisabled,
        'platformUnsupported' => l10n.healthDetailSysProxyUnsupported,
        'ok' || 'pacMatched' => (result.localDetail?.trim().isNotEmpty ?? false)
            ? result.localDetail!.trim()
            : l10n.healthStatusPassed,
        'systemProxyReadFailed' => l10n.healthDetailSysProxyReadFailed,
        'systemProxyInvalidPort' => l10n.healthDetailSysProxyInvalidPort,
        'systemProxyNotApplied' => l10n.healthDetailSysProxyNotApplied,
        'systemProxyDisabledExternally' =>
          l10n.healthDetailSysProxyDisabledExternally,
        'systemProxyUnexpectedPac' || 'unexpectedPacUrl' => _withOptionalDetail(
            l10n.healthDetailSysProxyUnexpectedPac,
            result.localDetail,
          ),
        'systemProxyPartialScheme' => _withOptionalDetail(
            l10n.healthDetailTakeoverPartial,
            result.localDetail,
          ),
        _ => _withOptionalDetail(
            l10n.healthDetailSysProxyHijacked,
            result.localDetail,
          ),
      },
    HealthCheckId.trafficTakeover => switch (result.reasonCode) {
        'takeoverBoth' => l10n.healthDetailTakeoverBoth,
        'takeoverTun' => l10n.healthDetailTakeoverTun,
        'takeoverSysProxy' => l10n.healthDetailTakeoverSysProxy,
        'partialTakeover' => l10n.healthDetailTakeoverPartial,
        'takeoverUnverifiedPlatform' => l10n.healthDetailSysProxyUnsupported,
        _ => l10n.healthDetailTakeoverNone,
      },
    HealthCheckId.directConnectivity => switch (result.reasonCode) {
        'ok' => result.delayMs != null
            ? '${l10n.healthDetailDirectOk} · ${result.delayMs} ms'
            : l10n.healthDetailDirectOk,
        'directSlow' => result.delayMs != null
            ? '${l10n.healthDetailDirectSlow} · ${result.delayMs} ms'
            : l10n.healthDetailDirectSlow,
        'coreDelayBusy' => l10n.healthDetailCoreDelayBusy,
        _ => l10n.healthDetailDirectFailed,
      },
    HealthCheckId.dnsResolution => switch (result.reasonCode) {
        'ok' => l10n.healthDetailDnsOk,
        'dnsFakeIpActive' => l10n.healthDetailDnsFakeIp,
        'dnsPoisonedLoopback' => l10n.healthDetailDnsPoisoned,
        'dnsStaleFakeIp' => l10n.healthDetailDnsStaleFakeIp,
        _ => l10n.healthDetailDnsFailed,
      },
    HealthCheckId.outboundConnectivity => switch (result.reasonCode) {
        'ok' => result.localDetail ?? l10n.healthStatusPassed,
        'outboundSlow' || 'outboundVerySlow' => result.delayMs != null
            ? '${l10n.healthDetailOutboundSlow(result.nodeName ?? '-')} (${result.delayMs} ms)'
            : l10n.healthDetailOutboundSlow(result.nodeName ?? '-'),
        'outboundSelectedDirect' => l10n.healthDetailOutboundDirectSelected,
        'outboundSelectedReject' => l10n.healthDetailOutboundRejectSelected,
        'coreDelayBusy' => l10n.healthDetailCoreDelayBusy,
        'outboundGroupMissing' ||
        'outboundGroupLoop' ||
        'outboundNotFound' =>
          l10n.healthDetailRuntimeMismatch,
        _ => l10n.healthDetailOutboundFailed(result.nodeName ?? '-'),
      },
    HealthCheckId.endToEndConnectivity => switch (result.reasonCode) {
        'ok' => () {
            final cc = result.exitCountryCode;
            final exitPart = (cc != null && cc.length == 2)
                ? l10n.healthExitCountryPart('${_countryCodeToFlag(cc)} $cc')
                : '';
            return l10n.healthDetailE2eVerified(exitPart);
          }(),
        'routedDirectByRule' => l10n.healthDetailE2eDirectRule,
        'tunBypassedSystemProxyOk' => () {
            final cc = result.exitCountryCode;
            final exitPart = (cc != null && cc.length == 2)
                ? l10n.healthExitCountryPart('${_countryCodeToFlag(cc)} $cc')
                : '';
            return '${l10n.healthDetailTunBypassedSystemProxyOk}$exitPart';
          }(),
        'trafficBypassedCore' => _withOptionalDetail(
            l10n.healthDetailE2eBypassed,
            result.localDetail,
          ),
        'e2eRejectedByRule' => l10n.healthDetailOutboundRejectSelected,
        'takeoverFailed' ||
        'outboundFailed' ||
        'pacExternalUnverifiable' ||
        'takeoverUnverifiedPlatform' =>
          l10n.healthDetailSkipPrerequisite,
        _ => l10n.healthDetailE2eFailed,
      },
  };
}

String _formatHealthySubscription(
  HealthCheckResult result,
  AppLocalizations l10n,
) {
  final parts = <String>[];
  if (result.daysRemaining != null) {
    parts.add(l10n.nodeOverviewExpireDaysLeft(result.daysRemaining!));
  }
  if (result.quotaUsedPercent != null) {
    parts.add('${result.quotaUsedPercent}%');
  }
  return parts.isEmpty ? l10n.healthDetailSubHealthy : parts.join(' · ');
}

class HealthCheckView extends ConsumerStatefulWidget {
  const HealthCheckView({
    super.key,
    this.type = SheetType.sideSheet,
    this.onAction,
  });

  final SheetType type;
  final void Function(HealthAction action)? onAction;

  @override
  ConsumerState<HealthCheckView> createState() => _HealthCheckViewState();
}

class _HealthCheckViewState extends ConsumerState<HealthCheckView> {
  late final HealthCheckController _controller;
  Object? _viewLease;
  Animation<double>? _routeAnimation;
  bool _actionInFlight = false;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(healthCheckControllerProvider);
    _viewLease = _controller.attachView();
    unawaited(
      Future.microtask(() {
        if (mounted && _viewLease != null) {
          unawaited(_controller.startOrAttach());
        }
      }),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextAnimation = ModalRoute.of(context)?.animation;
    if (!identical(_routeAnimation, nextAnimation)) {
      _routeAnimation?.removeStatusListener(_onRouteAnimationStatus);
      _routeAnimation = nextAnimation;
      _routeAnimation?.addStatusListener(_onRouteAnimationStatus);
    }
  }

  void _onRouteAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.reverse ||
        status == AnimationStatus.dismissed) {
      _releaseViewLease();
    }
  }

  void _releaseViewLease() {
    final lease = _viewLease;
    if (lease == null) return;
    _viewLease = null;
    unawaited(_controller.detachView(lease));
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_onRouteAnimationStatus);
    _routeAnimation = null;
    _releaseViewLease();
    super.dispose();
  }

  String _formatClockTime(DateTime dt) {
    final local = dt.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final ss = local.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  Future<void> _handleAction(BuildContext context, HealthAction action) async {
    if (_actionInFlight) return;
    _actionInFlight = true;
    try {
      if (widget.onAction != null) {
        widget.onAction!(action);
        return;
      }
      final navigator = Navigator.maybeOf(context);
      final hostContext = navigator?.context ?? context;

      void popOverlaysToRoot() {
        if (navigator != null && navigator.canPop()) {
          navigator.popUntil((route) => route.isFirst);
        }
      }

      switch (action) {
        case HealthAction.openProfiles:
          popOverlaysToRoot();
          globalState.appController.toPage(PageLabel.profiles);
        case HealthAction.openPurchase:
          popOverlaysToRoot();
          globalState.appController.toPage(PageLabel.purchase);
        case HealthAction.openProxies:
          popOverlaysToRoot();
          globalState.appController.toPage(PageLabel.proxies);
        case HealthAction.openTunSettings:
          popOverlaysToRoot();
          await showSheet<void>(
            context: hostContext,
            builder: (_, type) => AdaptiveSheetScaffold(
              type: type,
              title: appLocalizations.tun,
              body: generateListView(
                generateSection(
                  items: [
                    if (system.isDesktop) const TUNItem(),
                    if (Platform.isMacOS) const AutoSetSystemDnsItem(),
                    const TunStackItem(),
                  ],
                ),
              ),
            ),
          );
        case HealthAction.openNetworkSettings:
          popOverlaysToRoot();
          await showExtend<void>(
            hostContext,
            builder: (_, type) => AdaptiveSheetScaffold(
              type: type,
              title: appLocalizations.network,
              body: const NetworkListView(),
            ),
          );
        case HealthAction.openDnsSettings:
          popOverlaysToRoot();
          await showExtend<void>(
            hostContext,
            builder: (_, type) => AdaptiveSheetScaffold(
              type: type,
              title: 'DNS',
              body: const DnsListView(),
            ),
          );
        case HealthAction.reapplySystemProxy:
          final restored = await systemProxyCoordinator.forceReapply();
          if (!restored) {
            if (hostContext.mounted) {
              popOverlaysToRoot();
              await showExtend<void>(
                hostContext,
                builder: (_, type) => AdaptiveSheetScaffold(
                  type: type,
                  title: appLocalizations.network,
                  body: const NetworkListView(),
                ),
              );
            }
            return;
          }
          if (mounted) {
            unawaited(_controller.restart());
          }
        case HealthAction.startProxy:
          await globalState.appController.updateStatus(true);
          if (mounted) {
            unawaited(_controller.restart());
          }
        case HealthAction.restartCore:
          await globalState.appController.restartCore();
          if (mounted) {
            unawaited(_controller.restart());
          }
      }
    } finally {
      _actionInFlight = false;
    }
  }

  Future<void> _copySummary(HealthReport report, AppLocalizations l10n) async {
    await Clipboard.setData(
      ClipboardData(text: formatHealthSummaryText(report, l10n)),
    );
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(l10n.healthCheckCopied)),
    );
  }

  Future<void> _exportReport(HealthReport report, AppLocalizations l10n) async {
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: l10n.healthCheckExportDialogTitle,
        fileName: 'freedomcloud-health.json',
        bytes: exportHealthReport(report),
      );
      if (!mounted || path == null) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(l10n.healthCheckExportSuccess)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(l10n.healthCheckExportFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.watch(healthCheckControllerProvider);
    final report = controller.lastReport;
    final isRunning = controller.isRunning;

    return AdaptiveSheetScaffold(
      type: widget.type,
      title: l10n.healthCheckTitle,
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                _VerdictBanner(
                  report: report,
                  isRunning: isRunning,
                  wasCancelled: controller.wasCancelledWithoutReport,
                  l10n: l10n,
                  formatTime: _formatClockTime,
                  onAction: (action) => unawaited(_handleAction(context, action)),
                ),
                const SizedBox(height: 14),
                for (final layer in HealthLayer.values) ...[
                  _LayerSection(
                    layer: layer,
                    controller: controller,
                    l10n: l10n,
                    onAction: (action) =>
                        unawaited(_handleAction(context, action)),
                  ),
                  const SizedBox(height: 12),
                ],
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    l10n.healthCheckPrivacyNote,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _BottomActionBar(
            isRunning: isRunning,
            report: report,
            l10n: l10n,
            onRecheckOrCancel: () {
              if (isRunning) {
                unawaited(controller.cancelActive());
              } else {
                unawaited(controller.startOrAttach());
              }
            },
            onCopy: report == null
                ? null
                : () => unawaited(_copySummary(report, l10n)),
            onExport: report == null
                ? null
                : () => unawaited(_exportReport(report, l10n)),
          ),
        ],
      ),
    );
  }
}

Color _healthyForeground(Brightness brightness) =>
    brightness == Brightness.dark
        ? Colors.green.shade300
        : Colors.green.shade900;

Color _warningForeground(Brightness brightness) =>
    brightness == Brightness.dark
        ? Colors.amber.shade300
        : const Color(0xFF7A4F00);

class _VerdictBanner extends StatelessWidget {
  const _VerdictBanner({
    required this.report,
    required this.isRunning,
    required this.wasCancelled,
    required this.l10n,
    required this.formatTime,
    required this.onAction,
  });

  final HealthReport? report;
  final bool isRunning;
  final bool wasCancelled;
  final AppLocalizations l10n;
  final String Function(DateTime) formatTime;
  final void Function(HealthAction) onAction;

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    final brightness = Theme.of(context).brightness;
    final verdict = report?.verdict;

    final Color bgColor;
    final Color borderColor;
    final Color accentColor;
    final IconData iconData;

    if (verdict == null) {
      bgColor = cs.surfaceContainerHighest.withValues(alpha: 0.55);
      borderColor = cs.outlineVariant.withValues(alpha: 0.5);
      accentColor = (!isRunning && wasCancelled) ? cs.outline : cs.primary;
      iconData = (!isRunning && wasCancelled)
          ? Icons.cancel_outlined
          : Icons.sync_rounded;
    } else {
      switch (verdict.severity) {
        case HealthVerdictSeverity.healthy:
          bgColor = Colors.green.withValues(alpha: 0.12);
          borderColor = Colors.green.withValues(alpha: 0.35);
          accentColor = _healthyForeground(brightness);
          iconData = Icons.check_circle_rounded;
        case HealthVerdictSeverity.warning:
          bgColor = Colors.amber.withValues(alpha: 0.14);
          borderColor = Colors.amber.withValues(alpha: 0.42);
          accentColor = _warningForeground(brightness);
          iconData = Icons.warning_amber_rounded;
        case HealthVerdictSeverity.failed:
          bgColor = cs.errorContainer.withValues(alpha: 0.45);
          borderColor = cs.error.withValues(alpha: 0.45);
          accentColor = cs.error;
          iconData = Icons.error_rounded;
      }
    }

    final headline = verdict == null
        ? (isRunning
            ? l10n.healthVerdictCheckingTitle
            : (wasCancelled
                ? l10n.healthVerdictCancelledTitle
                : l10n.healthCheckTitle))
        : healthVerdictHeadline(verdict, l10n);

    String? subtitle;
    if (verdict != null &&
        (verdict.code == 'healthy' ||
            verdict.code == 'healthyWithWarnings' ||
            verdict.code == 'tunBypassedSystemProxyOk')) {
      if (report?.mode == Mode.direct && verdict.directDelayMs != null) {
        subtitle = l10n.healthVerdictHealthyDirectSubtitle(
          verdict.directDelayMs!,
        );
      } else if (verdict.activeNodeName != null &&
          verdict.outboundDelayMs != null) {
        final cc = verdict.exitCountryCode;
        final exitPart = (cc != null && cc.length == 2)
            ? l10n.healthExitCountryPart('${_countryCodeToFlag(cc)} $cc')
            : '';
        subtitle = l10n.healthVerdictHealthySubtitle(
          verdict.activeNodeName!,
          verdict.outboundDelayMs!,
          exitPart,
        );
      }
    }

    return Container(
      key: const ValueKey('health-verdict-card'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: isRunning
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: accentColor,
                        ),
                      )
                    : Icon(iconData, color: accentColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      style: context.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: context.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontFamilyFallback: [FontFamily.twEmoji.value],
                        ),
                      ),
                    ],
                    if (report != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        l10n.healthCheckLastChecked(
                          formatTime(report!.completedAt),
                          '${(report!.totalElapsedMs / 1000).toStringAsFixed(1)}s',
                        ),
                        key: const ValueKey('health-timestamp-text'),
                        style: context.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontFamily: FontFamily.jetBrainsMono.value,
                        ),
                      ),
                    ] else if (isRunning) ...[
                      const SizedBox(height: 4),
                      Text(
                        l10n.healthCheckChecking,
                        style: context.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (verdict?.primaryAction case final primaryAction?) ...[
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              key: const ValueKey('health-verdict-action-button'),
              onPressed: () => onAction(primaryAction),
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: Text(
                healthActionLabel(primaryAction, l10n),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LayerSection extends StatelessWidget {
  const _LayerSection({
    required this.layer,
    required this.controller,
    required this.l10n,
    required this.onAction,
  });

  final HealthLayer layer;
  final HealthCheckController controller;
  final AppLocalizations l10n;
  final void Function(HealthAction) onAction;

  @override
  Widget build(BuildContext context) {
    final ids = HealthCheckId.values.where((id) => id.layer == layer).toList();
    final cs = context.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            healthLayerTitle(layer, l10n),
            style: context.textTheme.labelLarge?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          child: Column(
            children: [
              for (var i = 0; i < ids.length; i++) ...[
                _HealthCheckRow(
                  id: ids[i],
                  live: controller.liveSnapshot[ids[i]],
                  previous: controller.previousById[ids[i]],
                  isControllerRunning: controller.isRunning,
                  l10n: l10n,
                  onAction: onAction,
                ),
                if (i < ids.length - 1)
                  Divider(
                    height: 1,
                    indent: 42,
                    endIndent: 12,
                    color: cs.outlineVariant.withValues(alpha: 0.35),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _HealthCheckRow extends StatelessWidget {
  const _HealthCheckRow({
    required this.id,
    required this.live,
    required this.previous,
    required this.isControllerRunning,
    required this.l10n,
    required this.onAction,
  });

  final HealthCheckId id;
  final HealthCheckResult? live;
  final HealthCheckResult? previous;
  final bool isControllerRunning;
  final AppLocalizations l10n;
  final void Function(HealthAction) onAction;

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    final brightness = Theme.of(context).brightness;
    final isItemRunning = isControllerRunning &&
        (live == null || live!.status == HealthStatus.running);
    final effective = (isItemRunning && previous != null)
        ? previous!
        : (live?.status == HealthStatus.running && !isControllerRunning
            ? HealthCheckResult(
                id: id,
                status: HealthStatus.skipped,
                elapsedMs: 0,
                reasonCode: 'cancelled',
              )
            : live);
    final status = effective?.status ??
        (isControllerRunning ? HealthStatus.running : HealthStatus.skipped);
    final detailText = effective != null
        ? healthCheckItemDetail(effective, l10n)
        : (isControllerRunning
            ? l10n.healthStatusRunning
            : l10n.healthDetailCancelled);

    final (IconData icon, Color iconColor) = switch (status) {
      HealthStatus.passed => (
          Icons.check_circle_outline_rounded,
          _healthyForeground(brightness),
        ),
      HealthStatus.warning => (
          Icons.warning_amber_rounded,
          _warningForeground(brightness),
        ),
      HealthStatus.failed => (
          Icons.highlight_off_rounded,
          cs.error,
        ),
      HealthStatus.timeout => (
          Icons.timer_off_outlined,
          cs.error,
        ),
      HealthStatus.skipped => (
          Icons.remove_circle_outline_rounded,
          cs.outline,
        ),
      HealthStatus.running => (
          Icons.sync_rounded,
          cs.primary,
        ),
    };

    final rowAction = effective?.action;
    final showAction = !isItemRunning &&
        rowAction != null &&
        (status.isFailure || status == HealthStatus.warning);

    return Padding(
      key: ValueKey('health-row-${id.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (isItemRunning)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.primary,
                    ),
                  )
                else
                  Icon(icon, size: 19, color: iconColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    healthCheckItemTitle(id, l10n),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth * 0.42,
                  ),
                  child: _StatusPill(
                    status: isItemRunning ? HealthStatus.running : status,
                    label: healthStatusLabel(
                      isItemRunning ? HealthStatus.running : status,
                      l10n,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 28),
              child: Opacity(
                opacity: (isItemRunning && previous != null) ? 0.55 : 1.0,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      detailText,
                      style: context.textTheme.bodySmall?.copyWith(
                        color: status.isFailure
                            ? cs.error
                            : cs.onSurfaceVariant,
                        fontFamilyFallback: [FontFamily.twEmoji.value],
                      ),
                    ),
                    if (effective != null && effective.elapsedMs > 0)
                      Text(
                        '${effective.elapsedMs} ms',
                        style: context.textTheme.labelSmall?.copyWith(
                          color: cs.outline,
                          fontFamily: FontFamily.jetBrainsMono.value,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (showAction) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: OutlinedButton.icon(
                  key: ValueKey('health-row-action-${id.name}'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                  ),
                  onPressed: () => onAction(rowAction),
                  icon: const Icon(Icons.build_circle_outlined, size: 15),
                  label: Text(
                    healthActionLabel(rowAction, l10n),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.status,
    required this.label,
  });

  final HealthStatus status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    final brightness = Theme.of(context).brightness;
    final (Color bg, Color fg) = switch (status) {
      HealthStatus.passed => (
          Colors.green.withValues(alpha: brightness == Brightness.dark ? 0.18 : 0.14),
          _healthyForeground(brightness),
        ),
      HealthStatus.warning => (
          Colors.amber.withValues(alpha: brightness == Brightness.dark ? 0.18 : 0.16),
          _warningForeground(brightness),
        ),
      HealthStatus.failed || HealthStatus.timeout => (
          cs.errorContainer.withValues(alpha: 0.7),
          cs.onErrorContainer,
        ),
      HealthStatus.skipped => (
          cs.surfaceContainerHighest,
          cs.onSurfaceVariant,
        ),
      HealthStatus.running => (
          cs.primaryContainer.withValues(alpha: 0.55),
          cs.onPrimaryContainer,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({
    required this.isRunning,
    required this.report,
    required this.l10n,
    required this.onRecheckOrCancel,
    required this.onCopy,
    required this.onExport,
  });

  final bool isRunning;
  final HealthReport? report;
  final AppLocalizations l10n;
  final VoidCallback onRecheckOrCancel;
  final VoidCallback? onCopy;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.45)),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 380 || scale > 1.25;
          final secondaryStyle = OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          );
          final recheckBtn = FilledButton.icon(
            key: const ValueKey('health-recheck-button'),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onPressed: onRecheckOrCancel,
            icon: Icon(
              isRunning ? Icons.stop_circle_outlined : Icons.refresh_rounded,
              size: 17,
            ),
            label: Text(
              isRunning ? l10n.healthCheckCancel : l10n.healthCheckRecheck,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
          final copyBtn = OutlinedButton.icon(
            key: const ValueKey('health-copy-button'),
            style: secondaryStyle,
            onPressed: onCopy,
            icon: const Icon(Icons.copy_rounded, size: 15),
            label: Text(
              l10n.healthCheckCopySummary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
          final exportBtn = OutlinedButton.icon(
            key: const ValueKey('health-export-button'),
            style: secondaryStyle,
            onPressed: onExport,
            icon: const Icon(Icons.download_outlined, size: 15),
            label: Text(
              l10n.healthCheckExport,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );

          if (compact) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                recheckBtn,
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    copyBtn,
                    exportBtn,
                  ],
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    copyBtn,
                    exportBtn,
                  ],
                ),
              ),
              const SizedBox(width: 8),
              recheckBtn,
            ],
          );
        },
      ),
    );
  }
}

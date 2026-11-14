import 'dart:math' as math;

import 'package:flclashx/common/common.dart';
import 'package:flclashx/widgets/earth_proxy_switch.dart';
import 'package:flutter/material.dart';

export 'package:flclashx/widgets/earth_proxy_switch.dart'
    show computeFloatingEarthDiameter, EarthProxySwitch, EarthProxySwitchDebugSnapshot;

/// Computes the adaptive bottom margin between a floating proxy dock and the
/// bottom edge of its host viewport.
double computeFloatingProxyDockBottomMargin(double viewportHeight) =>
    math.min(16.0, math.max(6.0, viewportHeight * 0.03));

/// Computes the extra bottom scroll padding required so the last scrollable
/// item clears the floating Earth dock completely when scrolled to the end.
double computeFloatingProxyDockScrollClearance({
  required double textScale,
  required double bottomMargin,
  double? viewportWidth,
  double? viewportHeight,
}) {
  final diameter = (viewportWidth != null && viewportHeight != null)
      ? computeFloatingEarthDiameter(
          viewportWidth: viewportWidth,
          viewportHeight: viewportHeight,
        )
      : 152.0;
  final textReserve =
      textScale > 1.0 ? 8.0 * (textScale.clamp(1.0, 1.5) - 1.0) : 0.0;
  return diameter + bottomMargin + 20.0 + textReserve;
}

/// Persistent frameless floating Earth proxy master switch dock anchored at
/// the bottom-center of a host pane.
class FloatingProxyDock extends StatelessWidget {
  const FloatingProxyDock({
    super.key,
    required this.isRunning,
    required this.pendingTarget,
    required this.startCancelable,
    required this.onToggle,
    this.surfaceKey,
    this.switchKey = const ValueKey('overview-proxy-toggle'),
    this.railKey = const ValueKey('overview-proxy-toggle-rail'),
    this.thumbKey = const ValueKey('overview-proxy-toggle-thumb'),
    this.fallbackCountryCode,
    this.continuousAnimationInTests = false,
  });

  final bool isRunning;
  final bool? pendingTarget;
  final bool startCancelable;
  final VoidCallback? onToggle;
  final Key? surfaceKey;
  final Key switchKey;
  final Key railKey;
  final Key thumbKey;
  final String? fallbackCountryCode;
  final bool continuousAnimationInTests;

  @override
  Widget build(BuildContext context) {
    final isBusy = pendingTarget != null;
    final isPendingStart = pendingTarget ?? false;
    final isStartCancelablePending = isPendingStart && startCancelable;
    final canPress =
        onToggle != null && (!isBusy || isStartCancelablePending);
    final buttonLabel = isBusy
        ? (isStartCancelablePending
            ? appLocalizations.nodeOverviewTurnOffProxy
            : (isPendingStart
                ? appLocalizations.tunStatusStarting
                : appLocalizations.tunStatusStopping))
        : (isRunning
            ? appLocalizations.nodeOverviewTurnOffProxy
            : appLocalizations.nodeOverviewTurnOnProxy);

    final mediaSize = MediaQuery.sizeOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        var diameter = computeFloatingEarthDiameter(
          viewportWidth: mediaSize.width,
          viewportHeight: mediaSize.height,
        );
        if (constraints.maxWidth.isFinite && constraints.maxWidth > 0) {
          diameter = math.min(diameter, constraints.maxWidth);
        }
        if (constraints.maxHeight.isFinite && constraints.maxHeight > 0) {
          diameter = math.min(diameter, constraints.maxHeight);
        }
        return EarthProxySwitch(
          key: switchKey,
          surfaceKey: surfaceKey,
          railKey: railKey,
          thumbKey: thumbKey,
          diameter: diameter,
          isRunning: isRunning,
          pendingTarget: pendingTarget,
          startCancelable: startCancelable,
          canPress: canPress,
          semanticsLabel: buttonLabel,
          fallbackCountryCode: fallbackCountryCode,
          continuousAnimationInTests: continuousAnimationInTests,
          onToggle: onToggle,
        );
      },
    );
  }
}

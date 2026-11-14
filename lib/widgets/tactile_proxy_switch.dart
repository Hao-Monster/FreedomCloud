import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flclashx/common/common.dart';
import 'package:flclashx/widgets/earth_proxy_switch.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

export 'package:flclashx/widgets/earth_proxy_switch.dart'
    show
        computeFloatingEarthDiameter,
        EarthProxySwitch,
        EarthProxySwitchDebugSnapshot,
        FloatingProxyDockDragScope;

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

/// Normalized (`[0.0, 1.0]`) screen position of a user-dragged floating Earth
/// switch relative to the host viewport's safe travel range.
@immutable
class EarthDockPosition {
  EarthDockPosition({
    required double fracX,
    required double fracY,
  })  : fracX = fracX.isFinite ? fracX.clamp(0.0, 1.0) : 0.5,
        fracY = fracY.isFinite ? fracY.clamp(0.0, 1.0) : 1.0;

  final double fracX;
  final double fracY;

  String toJson() => jsonEncode(<String, double>{
        'fracX': fracX,
        'fracY': fracY,
      });

  static EarthDockPosition? tryParseJson(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final fx = decoded['fracX'];
      final fy = decoded['fracY'];
      if (fx is! num || fy is! num || !fx.isFinite || !fy.isFinite) {
        return null;
      }
      return EarthDockPosition(
        fracX: fx.toDouble(),
        fracY: fy.toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EarthDockPosition &&
          other.fracX == fracX &&
          other.fracY == fracY);

  @override
  int get hashCode => Object.hash(fracX, fracY);
}

/// Persistent store for the floating Earth switch position backed by
/// [SharedPreferences] and synchronized in-memory across pages.
class EarthDockPositionStore {
  EarthDockPositionStore._();

  static const String prefsKey = 'earthProxyDockPositionV1';

  static final EarthDockPositionStore instance = EarthDockPositionStore._();

  final ValueNotifier<EarthDockPosition?> _notifier =
      ValueNotifier<EarthDockPosition?>(null);
  int _epoch = 0;

  ValueListenable<EarthDockPosition?> get listenable => _notifier;

  EarthDockPosition? get current => _notifier.value;

  /// Preloads any previously saved position before the first UI frame renders.
  Future<void> ensureLoaded() async {
    final loadEpoch = _epoch;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_epoch != loadEpoch) return;
      _notifier.value = EarthDockPosition.tryParseJson(
        prefs.getString(prefsKey),
      );
    } catch (_) {}
  }

  void updateLive(EarthDockPosition position) {
    _epoch++;
    _notifier.value = position;
  }

  Future<void> save(EarthDockPosition position) async {
    final saveEpoch = ++_epoch;
    _notifier.value = position;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_epoch != saveEpoch) return;
      await prefs.setString(prefsKey, position.toJson());
    } catch (_) {}
  }

  Future<void> clear() async {
    final clearEpoch = ++_epoch;
    _notifier.value = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_epoch != clearEpoch) return;
      await prefs.remove(prefsKey);
    } catch (_) {}
  }

  @visibleForTesting
  void resetForTest([EarthDockPosition? initial]) {
    _epoch++;
    _notifier.value = initial;
  }
}

({
  double minLeft,
  double maxLeft,
  double minTop,
  double maxTop,
  double safeWidth,
  double safeHeight,
  double effectiveDiameter,
}) _computeDockBounds({
  required double viewportWidth,
  required double viewportHeight,
  required double diameter,
  double edgeMargin = 8.0,
}) {
  final safeWidth =
      viewportWidth.isFinite && viewportWidth > 0 ? viewportWidth : diameter;
  final safeHeight =
      viewportHeight.isFinite && viewportHeight > 0 ? viewportHeight : diameter;
  final effectiveDiameter = math.min(
    diameter,
    math.max(0.0, math.min(safeWidth, safeHeight)),
  );
  final minLeft = math.min(
    edgeMargin,
    math.max(0.0, (safeWidth - effectiveDiameter) * 0.5),
  );
  final maxLeft = math.max(minLeft, safeWidth - edgeMargin - effectiveDiameter);
  final minTop = math.min(
    edgeMargin,
    math.max(0.0, (safeHeight - effectiveDiameter) * 0.5),
  );
  final maxTop = math.max(minTop, safeHeight - edgeMargin - effectiveDiameter);
  return (
    minLeft: minLeft,
    maxLeft: maxLeft,
    minTop: minTop,
    maxTop: maxTop,
    safeWidth: safeWidth,
    safeHeight: safeHeight,
    effectiveDiameter: effectiveDiameter,
  );
}

/// Resolves the floating dock's pixel rect inside a host viewport.
/// When [savedPosition] is null, places the dock bottom-center across the full
/// viewport width; otherwise restores and clamps the saved normalized position.
Rect computeFloatingProxyDockRect({
  required double viewportWidth,
  required double viewportHeight,
  required double diameter,
  EarthDockPosition? savedPosition,
  double edgeMargin = 8.0,
}) {
  final bounds = _computeDockBounds(
    viewportWidth: viewportWidth,
    viewportHeight: viewportHeight,
    diameter: diameter,
    edgeMargin: edgeMargin,
  );
  final d = bounds.effectiveDiameter;
  if (savedPosition == null) {
    final left =
        ((bounds.safeWidth - d) * 0.5).clamp(bounds.minLeft, bounds.maxLeft);
    final bottomMargin = computeFloatingProxyDockBottomMargin(bounds.safeHeight);
    final top = (bounds.safeHeight - bottomMargin - d)
        .clamp(bounds.minTop, bounds.maxTop);
    return Rect.fromLTWH(left, top, d, d);
  }
  final spanX = bounds.maxLeft - bounds.minLeft;
  final spanY = bounds.maxTop - bounds.minTop;
  final left = spanX <= 0.001
      ? ((bounds.safeWidth - d) * 0.5).clamp(bounds.minLeft, bounds.maxLeft)
      : bounds.minLeft + savedPosition.fracX.clamp(0.0, 1.0) * spanX;
  final top = spanY <= 0.001
      ? ((bounds.safeHeight - d) * 0.5).clamp(bounds.minTop, bounds.maxTop)
      : bounds.minTop + savedPosition.fracY.clamp(0.0, 1.0) * spanY;
  return Rect.fromLTWH(left, top, d, d);
}

/// Converts a top-left dock offset within a host viewport into normalized
/// [EarthDockPosition] coordinates clamped to `[0.0, 1.0]`.
EarthDockPosition computeEarthDockPositionFromOffset({
  required Offset topLeft,
  required double viewportWidth,
  required double viewportHeight,
  required double diameter,
  double edgeMargin = 8.0,
}) {
  final bounds = _computeDockBounds(
    viewportWidth: viewportWidth,
    viewportHeight: viewportHeight,
    diameter: diameter,
    edgeMargin: edgeMargin,
  );
  final spanX = bounds.maxLeft - bounds.minLeft;
  final spanY = bounds.maxTop - bounds.minTop;
  final fracX =
      spanX <= 0.001 ? 0.5 : ((topLeft.dx - bounds.minLeft) / spanX).clamp(0.0, 1.0);
  final fracY =
      spanY <= 0.001 ? 1.0 : ((topLeft.dy - bounds.minTop) / spanY).clamp(0.0, 1.0);
  return EarthDockPosition(fracX: fracX, fracY: fracY);
}

/// Hosts [child] inside a full-viewport [Stack] and positions an optional
/// draggable floating Earth [dock], defaulting to bottom-center when undragged.
class FloatingProxyDockOverlay extends StatefulWidget {
  const FloatingProxyDockOverlay({
    super.key,
    required this.viewportWidth,
    required this.viewportHeight,
    required this.child,
    required this.dock,
    this.edgeMargin = 8.0,
    this.store,
  });

  final double viewportWidth;
  final double viewportHeight;
  final Widget child;
  final Widget? dock;
  final double edgeMargin;
  final EarthDockPositionStore? store;

  @override
  State<FloatingProxyDockOverlay> createState() =>
      _FloatingProxyDockOverlayState();
}

class _FloatingProxyDockOverlayState extends State<FloatingProxyDockOverlay> {
  Offset? _activeDragTopLeft;
  EarthDockPosition? _pendingSavePosition;
  double _latestDiameter = 152.0;

  EarthDockPositionStore get _store =>
      widget.store ?? EarthDockPositionStore.instance;

  void _handleDragStart() {
    final currentRect = computeFloatingProxyDockRect(
      viewportWidth: widget.viewportWidth,
      viewportHeight: widget.viewportHeight,
      diameter: _latestDiameter,
      savedPosition: _store.current,
      edgeMargin: widget.edgeMargin,
    );
    _activeDragTopLeft = currentRect.topLeft;
    _pendingSavePosition = null;
  }

  void _handleDragUpdate(Offset delta) {
    final bounds = _computeDockBounds(
      viewportWidth: widget.viewportWidth,
      viewportHeight: widget.viewportHeight,
      diameter: _latestDiameter,
      edgeMargin: widget.edgeMargin,
    );
    final base = _activeDragTopLeft ??
        computeFloatingProxyDockRect(
          viewportWidth: widget.viewportWidth,
          viewportHeight: widget.viewportHeight,
          diameter: _latestDiameter,
          savedPosition: _store.current,
          edgeMargin: widget.edgeMargin,
        ).topLeft;
    final clamped = Offset(
      (base.dx + delta.dx).clamp(bounds.minLeft, bounds.maxLeft),
      (base.dy + delta.dy).clamp(bounds.minTop, bounds.maxTop),
    );
    _activeDragTopLeft = clamped;
    final nextPos = computeEarthDockPositionFromOffset(
      topLeft: clamped,
      viewportWidth: widget.viewportWidth,
      viewportHeight: widget.viewportHeight,
      diameter: _latestDiameter,
      edgeMargin: widget.edgeMargin,
    );
    _pendingSavePosition = nextPos;
    _store.updateLive(nextPos);
  }

  void _handleDragEnd() {
    final topLeft = _activeDragTopLeft;
    _activeDragTopLeft = null;
    final toSave = _pendingSavePosition ??
        (topLeft != null
            ? computeEarthDockPositionFromOffset(
                topLeft: topLeft,
                viewportWidth: widget.viewportWidth,
                viewportHeight: widget.viewportHeight,
                diameter: _latestDiameter,
                edgeMargin: widget.edgeMargin,
              )
            : _store.current);
    _pendingSavePosition = null;
    if (toSave != null) {
      unawaited(_store.save(toSave));
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaSize = MediaQuery.sizeOf(context);
    final baseDiameter = computeFloatingEarthDiameter(
      viewportWidth: mediaSize.width,
      viewportHeight: mediaSize.height,
    );
    final safeW = widget.viewportWidth.isFinite && widget.viewportWidth > 0
        ? widget.viewportWidth
        : baseDiameter;
    final safeH = widget.viewportHeight.isFinite && widget.viewportHeight > 0
        ? widget.viewportHeight
        : baseDiameter;
    _latestDiameter = math.min(baseDiameter, math.min(safeW, safeH));

    final dock = widget.dock;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (dock != null)
          ValueListenableBuilder<EarthDockPosition?>(
            valueListenable: _store.listenable,
            child: FloatingProxyDockDragScope(
              onDragStart: _handleDragStart,
              onDragUpdate: _handleDragUpdate,
              onDragEnd: _handleDragEnd,
              child: dock,
            ),
            builder: (context, savedPos, dockChild) {
              final rect = computeFloatingProxyDockRect(
                viewportWidth: widget.viewportWidth,
                viewportHeight: widget.viewportHeight,
                diameter: _latestDiameter,
                savedPosition: savedPos,
                edgeMargin: widget.edgeMargin,
              );
              return Positioned(
                left: rect.left,
                top: rect.top,
                width: rect.width,
                height: rect.height,
                child: dockChild!,
              );
            },
          ),
      ],
    );
  }
}

/// Persistent frameless floating Earth proxy master switch dock anchored by its
/// host [FloatingProxyDockOverlay] (defaulting to bottom-center when undragged).
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

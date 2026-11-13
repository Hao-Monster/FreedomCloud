import 'dart:async';
import 'dart:math' as math;

import 'package:flclashx/common/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Computes the adaptive bottom margin between a floating proxy dock and the
/// bottom edge of its host viewport.
double computeFloatingProxyDockBottomMargin(double viewportHeight) =>
    math.min(16.0, math.max(6.0, viewportHeight * 0.03));

/// Computes the extra bottom scroll padding required so the last scrollable
/// item clears the floating dock completely when scrolled to the end.
double computeFloatingProxyDockScrollClearance({
  required double textScale,
  required double bottomMargin,
}) =>
    (40.0 * textScale.clamp(1.0, 1.40)).roundToDouble() +
    12.0 +
    bottomMargin +
    24.0;

/// Persistent floating stadium capsule housing the unique proxy master switch
/// anchored at the bottom-center of a host pane.
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
  });

  final bool isRunning;
  final bool? pendingTarget;
  final bool startCancelable;
  final VoidCallback? onToggle;
  final Key? surfaceKey;
  final Key switchKey;
  final Key railKey;
  final Key thumbKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isBusy = pendingTarget != null;
    final isPendingStart = pendingTarget ?? false;
    final isStartCancelablePending = isPendingStart && startCancelable;
    final showActiveDockPalette = isRunning || isBusy;
    final green = isDark ? kLatencyFastColor : const Color(0xFF059669);
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

    final dockBgColor = showActiveDockPalette
        ? Color.alphaBlend(
            green.withValues(alpha: isDark ? 0.14 : 0.08),
            (isDark ? const Color(0xFF111826) : Colors.white)
                .withValues(alpha: isDark ? 0.96 : 0.97),
          )
        : (isDark
            ? const Color(0xFF121927).withValues(alpha: 0.96)
            : Colors.white.withValues(alpha: 0.97));
    final dockBorderColor = showActiveDockPalette
        ? green.withValues(alpha: isDark ? 0.48 : 0.38)
        : (isDark
            ? Colors.white.withValues(alpha: 0.12)
            : const Color(0xFFCBD5E1).withValues(alpha: 0.95));

    return RepaintBoundary(
      child: Listener(
        behavior: HitTestBehavior.opaque,
        child: DecoratedBox(
          key: surfaceKey,
          decoration: BoxDecoration(
            color: dockBgColor,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: dockBorderColor, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.46 : 0.12),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: showActiveDockPalette
                    ? green.withValues(alpha: isDark ? 0.24 : 0.16)
                    : Colors.black.withValues(alpha: isDark ? 0.22 : 0.05),
                blurRadius: showActiveDockPalette ? 24 : 6,
                spreadRadius: showActiveDockPalette ? 1 : 0,
                offset: Offset(0, showActiveDockPalette ? 4 : 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: TactileProxySwitch(
              key: switchKey,
              railKey: railKey,
              thumbKey: thumbKey,
              isRunning: isRunning,
              pendingTarget: pendingTarget,
              startCancelable: startCancelable,
              canPress: canPress,
              semanticsLabel: buttonLabel,
              onToggle: onToggle,
            ),
          ),
        ),
      ),
    );
  }
}

/// Scheme B tactile cyber-switch track for the proxy master switch.
///
/// Triggered strictly by click/tap or keyboard activation (`Enter`/`Space`),
/// automatically sliding the thumb horizontally across a laser-illuminated rail
/// without requiring manual drag gestures.
class TactileProxySwitch extends StatefulWidget {
  const TactileProxySwitch({
    super.key,
    required this.isRunning,
    required this.pendingTarget,
    required this.startCancelable,
    required this.canPress,
    required this.semanticsLabel,
    required this.onToggle,
    this.railKey = const ValueKey('overview-proxy-toggle-rail'),
    this.thumbKey = const ValueKey('overview-proxy-toggle-thumb'),
  });

  final bool isRunning;
  final bool? pendingTarget;
  final bool startCancelable;
  final bool canPress;
  final String semanticsLabel;
  final VoidCallback? onToggle;
  final Key railKey;
  final Key thumbKey;

  @override
  State<TactileProxySwitch> createState() => _TactileProxySwitchState();
}

class _TactileProxySwitchState extends State<TactileProxySwitch>
    with TickerProviderStateMixin {
  static const Duration _slideDuration = Duration(milliseconds: 360);
  static const Duration _hoverDuration = Duration(milliseconds: 180);

  late final AnimationController _slideController;
  late final AnimationController _hoverController;
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  bool get _effectiveConnected => widget.pendingTarget ?? widget.isRunning;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: _slideDuration,
      value: _effectiveConnected ? 1.0 : 0.0,
    );
    _hoverController = AnimationController(
      vsync: this,
      duration: _hoverDuration,
      value: 0.0,
    );
  }

  @override
  void didUpdateWidget(covariant TactileProxySwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldConnected = oldWidget.pendingTarget ?? oldWidget.isRunning;
    final nextConnected = _effectiveConnected;
    if (oldConnected != nextConnected) {
      final target = nextConnected ? 1.0 : 0.0;
      final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (reduceMotion) {
        _slideController.value = target;
      } else {
        unawaited(
          _slideController.animateTo(
            target,
            duration: _slideDuration,
            curve: Curves.easeOutCubic,
          ),
        );
      }
    }
    if (!widget.canPress && _pressed) {
      _pressed = false;
    }
  }

  @override
  void dispose() {
    _slideController.dispose();
    _hoverController.dispose();
    super.dispose();
  }

  void _setHovered({required bool value}) {
    if (_hovered == value) return;
    _hovered = value;
    final target = value ? 1.0 : 0.0;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      _hoverController.value = target;
    } else {
      unawaited(
        _hoverController.animateTo(
          target,
          duration: _hoverDuration,
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  void _setPressed({required bool value}) {
    if (_pressed == value) return;
    setState(() {
      _pressed = value;
    });
  }

  void _setFocused({required bool value}) {
    if (_focused == value) return;
    setState(() {
      _focused = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final heightScale = textScale.clamp(1.0, 1.40);
    final widthScale = textScale.clamp(1.0, 1.48);
    final trackHeight = (40.0 * heightScale).roundToDouble();
    final desiredWidth = (142.0 * widthScale).roundToDouble();
    final isBusy = widget.pendingTarget != null;
    final isPendingStart = widget.pendingTarget ?? false;
    final isPendingStop = isBusy && !isPendingStart;

    return Semantics(
      container: true,
      button: true,
      enabled: widget.canPress,
      toggled: widget.isRunning,
      label: widget.semanticsLabel,
      child: FocusableActionDetector(
        enabled: widget.canPress,
        onShowFocusHighlight: (value) => _setFocused(value: value),
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              if (widget.canPress) {
                widget.onToggle?.call();
              }
              return null;
            },
          ),
        },
        child: MouseRegion(
          cursor: widget.canPress
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onEnter: (_) => _setHovered(value: true),
          onExit: (_) => _setHovered(value: false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.canPress ? widget.onToggle : null,
            onTapDown:
                widget.canPress ? (_) => _setPressed(value: true) : null,
            onTapUp:
                widget.canPress ? (_) => _setPressed(value: false) : null,
            onTapCancel: () => _setPressed(value: false),
            child: ExcludeSemantics(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final trackWidth = constraints.maxWidth.isFinite
                      ? math.min(constraints.maxWidth, desiredWidth)
                      : desiredWidth;
                  const inset = 4.0;
                  final thumbSize = math.max(24.0, trackHeight - inset * 2);
                  final travel =
                      math.max(0.0, trackWidth - thumbSize - inset * 2);

                  return SizedBox(
                    width: trackWidth,
                    height: trackHeight,
                    child: AnimatedBuilder(
                      animation: Listenable.merge([
                        _slideController,
                        _hoverController,
                      ]),
                      builder: (context, _) {
                        final p = _slideController.value.clamp(0.0, 1.0);
                        final hoverProgress =
                            _hoverController.value.clamp(0.0, 1.0);
                        final disconnectHover =
                            (p * (isPendingStop ? 1.0 : hoverProgress))
                                .clamp(0.0, 1.0);
                        final slideEnergy = math.sin(p * math.pi);
                        final thumbLeft = inset + travel * p;
                        final showDisconnectText =
                            disconnectHover >= 0.45 || isPendingStop;

                        final offLabelColor = isDark
                            ? const Color(0xFFCBD5E1)
                            : const Color(0xFF334155);
                        final onLabelColor = Color.lerp(
                          const Color(0xFFECFDF5),
                          const Color(0xFFFFE4E6),
                          disconnectHover,
                        )!;

                        final knobTopColor = Color.lerp(
                          Color.lerp(
                            isDark ? const Color(0xFF3B4963) : Colors.white,
                            const Color(0xFFA7F3D0),
                            p,
                          ),
                          const Color(0xFFFCA5A5),
                          disconnectHover,
                        )!;
                        final knobBottomColor = Color.lerp(
                          Color.lerp(
                            isDark
                                ? const Color(0xFF1E293B)
                                : const Color(0xFFE2E8F0),
                            kPortalBrandMarkBg,
                            p,
                          ),
                          const Color(0xFFEF4444),
                          disconnectHover,
                        )!;
                        final knobBorderColor = Color.lerp(
                          Color.lerp(
                            isDark
                                ? const Color(0xFF64748B)
                                : const Color(0xFFCBD5E1),
                            const Color(0xFFECFDF5),
                            p,
                          ),
                          const Color(0xFFFEE2E2),
                          disconnectHover,
                        )!;
                        final knobGlowColor = Color.lerp(
                          Color.lerp(
                            Colors.black.withValues(
                              alpha: isDark ? 0.36 : 0.14,
                            ),
                            const Color(0xFF10B981).withValues(
                              alpha: 0.48 + slideEnergy * 0.20,
                            ),
                            p,
                          ),
                          const Color(0xFFEF4444).withValues(alpha: 0.56),
                          disconnectHover,
                        )!;
                        final iconColor = Color.lerp(
                          Color.lerp(
                            isDark
                                ? const Color(0xFFE2E8F0)
                                : const Color(0xFF1E293B),
                            kPortalBrandMarkFg,
                            p,
                          ),
                          Colors.white,
                          disconnectHover,
                        )!;

                        final busyText = isPendingStart
                            ? appLocalizations.tunStatusStarting
                            : appLocalizations.tunStatusStopping;

                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned.fill(
                              child: RepaintBoundary(
                                child: CustomPaint(
                                  key: widget.railKey,
                                  painter: _TactileCyberSwitchRailPainter(
                                    progress: p,
                                    hoverProgress: hoverProgress,
                                    disconnectHover: disconnectHover,
                                    slideEnergy: slideEnergy,
                                    thumbCenterX: thumbLeft + thumbSize * 0.5,
                                    thumbRadius: thumbSize * 0.5,
                                    inset: inset,
                                    isDark: isDark,
                                    isFocused: _focused,
                                    focusColor: colors.primary,
                                  ),
                                ),
                              ),
                            ),
                            if (p < 0.5)
                              Positioned(
                                left: inset + thumbSize + 4,
                                right: 8,
                                top: 0,
                                bottom: 0,
                                child: Opacity(
                                  opacity:
                                      ((0.5 - p) / 0.5).clamp(0.0, 1.0),
                                  child: Center(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: isBusy
                                          ? Text(
                                              busyText,
                                              maxLines: 1,
                                              style: TextStyle(
                                                fontSize: 12.0,
                                                fontWeight: FontWeight.w600,
                                                color: offLabelColor,
                                                height: 1.1,
                                              ),
                                            )
                                          : Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  appLocalizations
                                                      .nodeOverviewTurnOnProxy,
                                                  maxLines: 1,
                                                  style: TextStyle(
                                                    fontSize: 12.5,
                                                    fontWeight: FontWeight.w600,
                                                    color: offLabelColor,
                                                    height: 1.1,
                                                  ),
                                                ),
                                                const SizedBox(width: 1),
                                                Icon(
                                                  Icons.chevron_right_rounded,
                                                  size: 15,
                                                  color:
                                                      offLabelColor.withValues(
                                                    alpha: 0.72,
                                                  ),
                                                ),
                                              ],
                                            ),
                                    ),
                                  ),
                                ),
                              )
                            else
                              Positioned(
                                left: 10,
                                right: inset + thumbSize + 4,
                                top: 0,
                                bottom: 0,
                                child: Opacity(
                                  opacity:
                                      ((p - 0.5) / 0.5).clamp(0.0, 1.0),
                                  child: Center(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        isBusy
                                            ? busyText
                                            : (showDisconnectText
                                                ? appLocalizations
                                                    .nodeOverviewTurnOffProxy
                                                : appLocalizations.running),
                                        maxLines: 1,
                                        style: TextStyle(
                                          fontSize: isBusy ? 12.0 : 12.5,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.2,
                                          color: onLabelColor,
                                          height: 1.1,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            Positioned(
                              left: thumbLeft,
                              top: inset,
                              width: thumbSize,
                              height: thumbSize,
                              child: AnimatedScale(
                                scale: (_pressed && widget.canPress) ? 0.93 : 1.0,
                                duration: const Duration(milliseconds: 90),
                                child: DecoratedBox(
                                  key: widget.thumbKey,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [knobTopColor, knobBottomColor],
                                    ),
                                    border: Border.all(
                                      color: knobBorderColor,
                                      width: 1.4,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: knobGlowColor,
                                        blurRadius: 6 +
                                            p * 6 +
                                            slideEnergy * 4 +
                                            disconnectHover * 3,
                                        spreadRadius: disconnectHover * 0.8,
                                        offset: Offset(0, p > 0.5 ? 1 : 2),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: isBusy
                                        ? SizedBox(
                                            width: thumbSize * 0.50,
                                            height: thumbSize * 0.50,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.0,
                                              color: iconColor,
                                            ),
                                          )
                                        : Icon(
                                            Icons.power_settings_new_rounded,
                                            size: (thumbSize * 0.54)
                                                .clamp(15.0, 22.0),
                                            color: iconColor,
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TactileCyberSwitchRailPainter extends CustomPainter {
  const _TactileCyberSwitchRailPainter({
    required this.progress,
    required this.hoverProgress,
    required this.disconnectHover,
    required this.slideEnergy,
    required this.thumbCenterX,
    required this.thumbRadius,
    required this.inset,
    required this.isDark,
    required this.isFocused,
    required this.focusColor,
  });

  final double progress;
  final double hoverProgress;
  final double disconnectHover;
  final double slideEnergy;
  final double thumbCenterX;
  final double thumbRadius;
  final double inset;
  final bool isDark;
  final bool isFocused;
  final Color focusColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = Radius.circular(size.height * 0.5);
    final stadium = RRect.fromRectAndRadius(rect, radius);

    // 1. Recessed metallic/slate stadium groove.
    final baseColors = isDark
        ? const [Color(0xFF0B111E), Color(0xFF162033)]
        : const [Color(0xFFDCE4EE), Color(0xFFEDF2F7)];
    final basePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: baseColors,
      ).createShader(rect);
    canvas.drawRRect(stadium, basePaint);

    // Subtle hover highlight when disconnected.
    if (hoverProgress > 0.01 && disconnectHover < 0.5) {
      final offHoverAlpha = hoverProgress * (1.0 - progress) * 0.14;
      if (offHoverAlpha > 0.005) {
        canvas.drawRRect(
          stadium,
          Paint()
            ..color = const Color(0xFF10B981).withValues(alpha: offHoverAlpha),
        );
      }
    }

    canvas
      ..save()
      ..clipRRect(stadium);

    // 2. Progressive cyber emerald rail fill + disconnect crimson hover blend.
    if (progress > 0.005) {
      final trailEndX = (thumbCenterX +
              thumbRadius * 0.65 +
              (size.width - (thumbCenterX + thumbRadius * 0.65)) * progress)
          .clamp(0.0, size.width);
      final fillRect = Rect.fromLTWH(0, 0, trailEndX, size.height);
      final fillStart = Color.lerp(
        const Color(0xFF064E3B),
        const Color(0xFF7F1D1D),
        disconnectHover * 0.65,
      )!;
      final fillMid = Color.lerp(
        const Color(0xFF047857),
        const Color(0xFF991B1B),
        disconnectHover * 0.55,
      )!;
      final fillEnd = Color.lerp(
        const Color(0xFF10B981),
        const Color(0xFFDC2626),
        disconnectHover * 0.65,
      )!;
      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [fillStart, fillMid, fillEnd],
        ).createShader(fillRect);
      canvas.drawRect(fillRect, fillPaint);

      // Subtle upper specular highlight inside active groove.
      final sheenRect = Rect.fromLTWH(0, 0, trailEndX, size.height * 0.45);
      canvas.drawRect(
        sheenRect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: 0.16),
              Colors.white.withValues(alpha: 0.0),
            ],
          ).createShader(sheenRect),
      );
    }

    // 3. Transient laser light-beam trailing the sliding thumb.
    if (slideEnergy > 0.01 && thumbCenterX > inset + thumbRadius * 0.5) {
      final centerY = size.height * 0.5;
      final beamStart = inset + thumbRadius * 0.35;
      final beamEnd = thumbCenterX;
      if (beamEnd > beamStart) {
        final glowPaint = Paint()
          ..strokeWidth = 6.0
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFF34D399)
              .withValues(alpha: (slideEnergy * 0.65).clamp(0.0, 1.0))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
        canvas.drawLine(
          Offset(beamStart, centerY),
          Offset(beamEnd, centerY),
          glowPaint,
        );

        final corePaint = Paint()
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFFA7F3D0)
              .withValues(alpha: (slideEnergy * 0.92).clamp(0.0, 1.0));
        canvas.drawLine(
          Offset(beamStart, centerY),
          Offset(beamEnd, centerY),
          corePaint,
        );
      }
    }

    canvas.restore();

    // 4. Outer stadium rim border + keyboard focus indicator.
    final offRim = isDark ? const Color(0xFF28354B) : const Color(0xFFC5D0DF);
    final onRim = Color.lerp(
      const Color(0xFF34D399),
      const Color(0xFFF87171),
      disconnectHover,
    )!;
    final rimColor = Color.lerp(offRim, onRim, progress)!;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(0.6), radius),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = rimColor,
    );

    if (isFocused) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(1.5), radius),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..color = focusColor.withValues(alpha: 0.78),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TactileCyberSwitchRailPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.hoverProgress != hoverProgress ||
      oldDelegate.disconnectHover != disconnectHover ||
      oldDelegate.slideEnergy != slideEnergy ||
      oldDelegate.thumbCenterX != thumbCenterX ||
      oldDelegate.thumbRadius != thumbRadius ||
      oldDelegate.inset != inset ||
      oldDelegate.isDark != isDark ||
      oldDelegate.isFocused != isFocused ||
      oldDelegate.focusColor != focusColor;
}

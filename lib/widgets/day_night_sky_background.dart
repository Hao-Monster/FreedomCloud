import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flclashx/common/ui_activity.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Atmospheric phase for the FreedomCloud dynamic Day/Night sky background.
enum DayNightSkyPhase {
  /// Disconnected or stopping: deep cosmic starry night (`0.0`).
  night,

  /// Master switch turned ON while proxy bring-up / handshake is in flight:
  /// subtle pre-dawn horizon glimmer (`0.16`) without entering daytime.
  connecting,

  /// Master switch ON and connection established: crisp clear sunny day (`1.0`).
  day,
}

/// Target sky progress (`0..1`) reached while proxy bring-up is still pending.
const double kDayNightConnectingProgress = 0.16;

/// Sky progress threshold (`0..1`) at which foreground surfaces cross from
/// nocturnal dark glass to sunlit porcelain glass.
const double kDayNightSurfaceThreshold = 0.52;

/// Resolves the canonical [DayNightSkyPhase] from proxy runtime & pending state.
///
/// Daytime is entered **only** when [isRunning] is `true` and [pendingTarget]
/// is `null`. Turning the switch OFF (`pendingTarget == false`) immediately
/// targets [DayNightSkyPhase.night]; turning it ON (`pendingTarget == true`)
/// holds at [DayNightSkyPhase.connecting] until bring-up succeeds or rolls back.
DayNightSkyPhase resolveDayNightSkyPhase({
  required bool isRunning,
  required bool? pendingTarget,
}) {
  if (pendingTarget == false) {
    return DayNightSkyPhase.night;
  }
  if (pendingTarget ?? false) {
    return DayNightSkyPhase.connecting;
  }
  return isRunning ? DayNightSkyPhase.day : DayNightSkyPhase.night;
}

/// Maps [phase] to its normalized sky progress scalar in `[0.0, 1.0]`.
double resolveDayNightTargetProgress(DayNightSkyPhase phase) => switch (phase) {
      DayNightSkyPhase.night => 0.0,
      DayNightSkyPhase.connecting => kDayNightConnectingProgress,
      DayNightSkyPhase.day => 1.0,
    };

/// Resolves the top-level [ThemeMode] synchronized with the sky state machine.
ThemeMode resolveDayNightThemeMode({
  required bool isRunning,
  required bool? pendingTarget,
}) =>
    resolveDayNightSkyPhase(
              isRunning: isRunning,
              pendingTarget: pendingTarget,
            ) ==
            DayNightSkyPhase.day
        ? ThemeMode.light
        : ThemeMode.dark;

/// Inherited scope advertising whether an ancestor `CommonScaffold` is actively
/// rendering [DayNightSkyBackground] behind its content.
class DayNightSkyScope extends InheritedWidget {
  const DayNightSkyScope({
    super.key,
    required this.isActive,
    required this.isDaySurface,
    required super.child,
  });

  final bool isActive;
  final bool isDaySurface;

  static bool isActiveOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<DayNightSkyScope>()
          ?.isActive ??
      false;

  static bool isDaySurfaceOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<DayNightSkyScope>()
          ?.isDaySurface ??
      false;

  @override
  bool updateShouldNotify(DayNightSkyScope oldWidget) =>
      isActive != oldWidget.isActive || isDaySurface != oldWidget.isDaySurface;
}

/// Immutable diagnostic snapshot exposed for deterministic widget testing.
@immutable
class DayNightSkyDebugSnapshot {
  const DayNightSkyDebugSnapshot({
    required this.phase,
    required this.dayProgress,
    required this.targetProgress,
    required this.isDaySurface,
    required this.isTickerActive,
  });

  final DayNightSkyPhase phase;
  final double dayProgress;
  final double targetProgress;
  final bool isDaySurface;
  final bool isTickerActive;
}

/// Full-bleed atmospheric sky canvas transitioning seamlessly between
/// Deep Cosmic Starry Night (disconnected), Pre-Dawn Horizon Glimmer
/// (connecting), and Crisp Clear Bright Sunny Day (connected).
class DayNightSkyBackground extends StatelessWidget {
  const DayNightSkyBackground({
    super.key,
    this.phase,
    this.onDaySurfaceChanged,
    this.continuousAnimationInTests = false,
  });

  /// Optional explicit phase override (primarily for isolated visual tests).
  /// When `null`, watches `runTimeProvider` and `statusSwitchPendingProvider`.
  final DayNightSkyPhase? phase;

  /// Notifies an enclosing `CommonScaffold` when the sky crosses
  /// [kDayNightSurfaceThreshold] so foreground glass surfaces flip contrast
  /// without per-frame widget tree rebuilds.
  final ValueChanged<bool>? onDaySurfaceChanged;

  /// Keeps ambient cloud drift / star twinkle running under `FLUTTER_TEST`.
  final bool continuousAnimationInTests;

  @visibleForTesting
  static DayNightSkyDebugSnapshot? debugSnapshotOf([Object? _]) =>
      _DayNightSkyCanvasState._latestSnapshot();

  @override
  Widget build(BuildContext context) {
    final explicitPhase = phase;
    if (explicitPhase != null) {
      return _DayNightSkyCanvas(
        phase: explicitPhase,
        onDaySurfaceChanged: onDaySurfaceChanged,
        continuousAnimationInTests: continuousAnimationInTests,
      );
    }
    return Consumer(
      builder: (_, ref, __) {
        final isRunning =
            ref.watch(runTimeProvider.select((state) => state != null));
        final pendingTarget = ref.watch(statusSwitchPendingProvider);
        return _DayNightSkyCanvas(
          phase: resolveDayNightSkyPhase(
            isRunning: isRunning,
            pendingTarget: pendingTarget,
          ),
          onDaySurfaceChanged: onDaySurfaceChanged,
          continuousAnimationInTests: continuousAnimationInTests,
        );
      },
    );
  }
}

class _DayNightSkyCanvas extends StatefulWidget {
  const _DayNightSkyCanvas({
    required this.phase,
    this.onDaySurfaceChanged,
    this.continuousAnimationInTests = false,
  });

  final DayNightSkyPhase phase;
  final ValueChanged<bool>? onDaySurfaceChanged;
  final bool continuousAnimationInTests;

  @override
  State<_DayNightSkyCanvas> createState() => _DayNightSkyCanvasState();
}

class _DayNightSkyCanvasState extends State<_DayNightSkyCanvas>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const double _steadyFrameStepSec = 0.033; // ~30 fps ambient budget
  static const double _convergenceEps = 0.0006;
  static final bool _runningInFlutterTest =
      Platform.environment.containsKey('FLUTTER_TEST');
  static final List<_DayNightSkyCanvasState> _mountedStates =
      <_DayNightSkyCanvasState>[];

  static DayNightSkyDebugSnapshot? _latestSnapshot() =>
      _mountedStates.isEmpty ? null : _mountedStates.last._buildSnapshot();

  late final _SkySharedGpuAssets _gpuAssets;
  late final _SkyPaintScratch _scratch;
  late final ValueNotifier<int> _repaintTick;
  late final Ticker _ticker;

  DayNightSkyPhase _phase = DayNightSkyPhase.night;
  double _dayProgress = 0.0;
  double _targetProgress = 0.0;
  double _elapsedSec = 0.0;
  double _steadyAccumulatorSec = 0.0;
  Duration? _lastTickElapsed;
  Duration? _tickerStartFrameTimestamp;

  bool _tickerModeEnabled = true;
  bool _reduceMotion = false;
  bool _appHiddenOrPaused = false;
  bool _uiActive = true;
  bool _lastReportedDaySurface = false;

  bool get _allowAmbientLoop =>
      !_runningInFlutterTest || widget.continuousAnimationInTests;

  bool get _canAnimateVisibly =>
      !_reduceMotion &&
      _tickerModeEnabled &&
      !_appHiddenOrPaused &&
      _uiActive;

  bool get _hasPendingTransition =>
      !_reduceMotion && (_dayProgress - _targetProgress).abs() > _convergenceEps;

  bool get _shouldTickerRun {
    if (!mounted || !_canAnimateVisibly) {
      return false;
    }
    if (_hasPendingTransition) return true;
    return _allowAmbientLoop;
  }

  DayNightSkyDebugSnapshot _buildSnapshot() => DayNightSkyDebugSnapshot(
        phase: _phase,
        dayProgress: _dayProgress,
        targetProgress: _targetProgress,
        isDaySurface: _dayProgress >= kDayNightSurfaceThreshold,
        isTickerActive: _ticker.isActive,
      );

  @override
  void initState() {
    super.initState();
    _mountedStates.add(this);
    WidgetsBinding.instance.addObserver(this);
    uiActivity.addListener(_handleUiActivityChanged);
    _uiActive = uiActivity.value;

    _gpuAssets = _SkySharedGpuAssets.instance;
    _scratch = _SkyPaintScratch();
    _repaintTick = ValueNotifier<int>(0);
    _ticker = createTicker(_onTick);

    _phase = widget.phase;
    _targetProgress = resolveDayNightTargetProgress(widget.phase);
    _dayProgress = _targetProgress;
    _lastReportedDaySurface = _dayProgress >= kDayNightSurfaceThreshold;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextTickerEnabled = TickerMode.valuesOf(context).enabled;
    final nextReduceMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final changed = nextTickerEnabled != _tickerModeEnabled ||
        nextReduceMotion != _reduceMotion;
    _tickerModeEnabled = nextTickerEnabled;
    _reduceMotion = nextReduceMotion;
    if (!_canAnimateVisibly && (_dayProgress - _targetProgress).abs() > 0.0) {
      _snapToTargetImmediately(
        notifySurface: true,
        deferCallback: true,
      );
    }
    if (changed || !_ticker.isActive) {
      _syncTickerState();
    }
  }

  @override
  void didUpdateWidget(covariant _DayNightSkyCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.phase != oldWidget.phase) {
      _applyTargetPhase(widget.phase);
    } else if (oldWidget.continuousAnimationInTests !=
        widget.continuousAnimationInTests) {
      _syncTickerState();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final hidden = switch (state) {
      AppLifecycleState.hidden ||
      AppLifecycleState.paused ||
      AppLifecycleState.detached =>
        true,
      AppLifecycleState.resumed || AppLifecycleState.inactive => false,
    };
    if (hidden != _appHiddenOrPaused) {
      _appHiddenOrPaused = hidden;
      if (hidden && (_dayProgress - _targetProgress).abs() > _convergenceEps) {
        _snapToTargetImmediately(notifySurface: true);
      } else {
        _syncTickerState();
      }
    }
  }

  void _handleUiActivityChanged() {
    final active = uiActivity.value;
    if (active != _uiActive) {
      _uiActive = active;
      if (!active && (_dayProgress - _targetProgress).abs() > _convergenceEps) {
        _snapToTargetImmediately(notifySurface: true);
      } else {
        _syncTickerState();
      }
    }
  }

  void _applyTargetPhase(DayNightSkyPhase nextPhase) {
    final nextTarget = resolveDayNightTargetProgress(nextPhase);
    if (_phase == nextPhase && (_targetProgress - nextTarget).abs() < 1e-6) {
      return;
    }
    _phase = nextPhase;
    _targetProgress = nextTarget;
    if (!_canAnimateVisibly) {
      _snapToTargetImmediately(
        notifySurface: true,
        deferCallback: true,
      );
    } else {
      _repaintTick.value++;
      _syncTickerState();
    }
  }

  void _snapToTargetImmediately({
    required bool notifySurface,
    bool deferCallback = false,
  }) {
    _dayProgress = _targetProgress;
    _repaintTick.value++;
    _maybeNotifyDaySurface(
      allowSchedule: notifySurface,
      deferCallback: deferCallback,
    );
    _syncTickerState();
  }

  void _maybeNotifyDaySurface({
    required bool allowSchedule,
    bool deferCallback = false,
  }) {
    final nextDaySurface = _dayProgress >= kDayNightSurfaceThreshold;
    if (nextDaySurface == _lastReportedDaySurface) {
      return;
    }
    _lastReportedDaySurface = nextDaySurface;
    final callback = widget.onDaySurfaceChanged;
    if (!allowSchedule || callback == null || !mounted) {
      return;
    }
    final schedulerPhase = SchedulerBinding.instance.schedulerPhase;
    if (deferCallback || schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onDaySurfaceChanged?.call(_lastReportedDaySurface);
        }
      });
    } else {
      callback(nextDaySurface);
    }
  }

  void _syncTickerState() {
    final want = _shouldTickerRun;
    if (want && !_ticker.isActive) {
      _lastTickElapsed = null;
      _steadyAccumulatorSec = 0.0;
      _tickerStartFrameTimestamp =
          SchedulerBinding.instance.currentSystemFrameTimeStamp;
      _ticker.start();
    } else if (!want && _ticker.isActive) {
      _ticker.stop();
      _lastTickElapsed = null;
      _tickerStartFrameTimestamp = null;
    }
  }

  void _onTick(Duration elapsed) {
    final prev = _lastTickElapsed;
    _lastTickElapsed = elapsed;
    if (prev == null) {
      final startedAt = _tickerStartFrameTimestamp;
      final nowFrame = SchedulerBinding.instance.currentSystemFrameTimeStamp;
      final sinceStartSec = startedAt != null
          ? (nowFrame - startedAt).inMicroseconds / 1e6
          : 0.016;
      final firstDt =
          sinceStartSec > 0.001 ? sinceStartSec.clamp(0.001, 2.5) : 0.016;
      _stepSimulation(firstDt);
      return;
    }
    final rawDt = (elapsed - prev).inMicroseconds / 1e6;
    if (rawDt <= 0.0) {
      return;
    }
    final dt = rawDt.clamp(0.0005, 2.5);
    if (_hasPendingTransition) {
      _steadyAccumulatorSec = 0.0;
      _stepSimulation(dt);
      return;
    }
    _steadyAccumulatorSec += dt;
    if (_steadyAccumulatorSec < _steadyFrameStepSec) {
      return;
    }
    final stepDt = _steadyAccumulatorSec;
    _steadyAccumulatorSec = 0.0;
    _stepSimulation(stepDt);
  }

  void _stepSimulation(double dt) {
    _elapsedSec += dt;

    final diff = _targetProgress - _dayProgress;
    if (diff.abs() > _convergenceEps) {
      final rate = switch (_phase) {
        DayNightSkyPhase.connecting => 2.25,
        DayNightSkyPhase.day => 2.45,
        DayNightSkyPhase.night => 2.75,
      };
      final expPull = diff * (1.0 - math.exp(-rate * dt));
      final linearTail = diff.sign * math.min(diff.abs(), 0.045 * dt);
      final delta = expPull.abs() >= linearTail.abs() ? expPull : linearTail;
      _dayProgress = (_dayProgress + delta).clamp(0.0, 1.0);
      if ((_targetProgress - _dayProgress).abs() <= _convergenceEps) {
        _dayProgress = _targetProgress;
      }
      _maybeNotifyDaySurface(allowSchedule: true);
    } else if (_dayProgress != _targetProgress) {
      _dayProgress = _targetProgress;
      _maybeNotifyDaySurface(allowSchedule: true);
    }

    _repaintTick.value++;
    if (!_shouldTickerRun && _ticker.isActive) {
      _ticker.stop();
      _lastTickElapsed = null;
    }
  }

  @override
  void dispose() {
    _mountedStates.remove(this);
    WidgetsBinding.instance.removeObserver(this);
    uiActivity.removeListener(_handleUiActivityChanged);
    _ticker.dispose();
    _repaintTick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: IgnorePointer(
          child: CustomPaint(
            painter: _DayNightSkyPainter(
              state: this,
              assets: _gpuAssets,
              scratch: _scratch,
              repaint: _repaintTick,
            ),
            size: Size.infinite,
          ),
        ),
      );
}

/// Immutable star descriptor generated deterministically at startup.
class _SkyStarSpec {
  const _SkyStarSpec({
    required this.nx,
    required this.ny,
    required this.radius,
    required this.baseAlpha,
    required this.twinkleSpeed,
    required this.twinklePhase,
    required this.color,
    required this.isHero,
  });

  final double nx;
  final double ny;
  final double radius;
  final double baseAlpha;
  final double twinkleSpeed;
  final double twinklePhase;
  final Color color;
  final bool isHero;
}

/// Immutable cloud descriptor for multi-depth parallax cumulus & cirrus drift.
class _SkyCloudSpec {
  const _SkyCloudSpec({
    required this.variantIndex,
    required this.baseNx,
    required this.ny,
    required this.widthFactor,
    required this.aspectRatio,
    required this.speedNxPerSec,
    required this.bobPhase,
    required this.opacity,
    required this.depthLayer,
  });

  final int variantIndex;
  final double baseNx;
  final double ny;
  final double widthFactor;
  final double aspectRatio;
  final double speedNxPerSec;
  final double bobPhase;
  final double opacity;
  final int depthLayer;
}

/// Pre-baked GPU textures & deterministic celestial catalogs shared across all
/// [DayNightSkyBackground] instances in the process.
class _SkySharedGpuAssets {
  _SkySharedGpuAssets._create()
      : cloudVariants = <ui.Image>[
          _bakeCumulusSprite(seed: 101, width: 256, height: 128),
          _bakeCumulusSprite(seed: 211, width: 256, height: 128),
          _bakeCumulusSprite(seed: 307, width: 256, height: 128),
          _bakeCumulusSprite(seed: 419, width: 256, height: 128),
        ],
        cirrusRibbon = _bakeCirrusSprite(width: 256, height: 80),
        milkyWayBand = _bakeMilkyWaySprite(width: 320, height: 160),
        moonSprite = _bakeMoonSprite(size: 96),
        stars = _generateStarCatalog(),
        clouds = _generateCloudCatalog();

  static _SkySharedGpuAssets? _instance;

  static _SkySharedGpuAssets get instance =>
      _instance ??= _SkySharedGpuAssets._create();

  final List<ui.Image> cloudVariants;
  final ui.Image cirrusRibbon;
  final ui.Image milkyWayBand;
  final ui.Image moonSprite;
  final List<_SkyStarSpec> stars;
  final List<_SkyCloudSpec> clouds;

  static ui.Image _bakeCumulusSprite({
    required int seed,
    required int width,
    required int height,
  }) {
    final rng = math.Random(seed);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );
    final w = width.toDouble();
    final h = height.toDouble();

    // Base soft ambient-occlusion underside shadow lobe
    final underShadowPaint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(w * 0.50, h * 0.68),
        w * 0.40,
        const <Color>[
          Color(0x52B9DCFF),
          Color(0x24CBE6FF),
          Color(0x00DCEFFF),
        ],
        const <double>[0.0, 0.58, 1.0],
      );
    canvas
      ..save()
      ..translate(w * 0.50, h * 0.68)
      ..scale(1.0, 0.36)
      ..translate(-w * 0.50, -h * 0.68)
      ..drawCircle(Offset(w * 0.50, h * 0.68), w * 0.40, underShadowPaint)
      ..restore();

    // Procedural billowy cumulus puffs (back-to-front sunlit lobes)
    const puffCenters = <({double x, double y, double r})>[
      (x: 0.24, y: 0.60, r: 0.19),
      (x: 0.76, y: 0.61, r: 0.18),
      (x: 0.36, y: 0.48, r: 0.23),
      (x: 0.63, y: 0.47, r: 0.22),
      (x: 0.50, y: 0.39, r: 0.26),
      (x: 0.44, y: 0.57, r: 0.21),
      (x: 0.58, y: 0.58, r: 0.20),
    ];

    for (final puff in puffCenters) {
      final jitterX = (rng.nextDouble() - 0.5) * 0.045;
      final jitterY = (rng.nextDouble() - 0.5) * 0.040;
      final jitterR = 0.90 + rng.nextDouble() * 0.22;
      final cx = (puff.x + jitterX) * w;
      final cy = (puff.y + jitterY) * h;
      final radius = puff.r * jitterR * w;
      final highlightCenter = Offset(cx + radius * 0.14, cy - radius * 0.18);

      final puffPaint = Paint()
        ..shader = ui.Gradient.radial(
          highlightCenter,
          radius,
          const <Color>[
            Color(0xF8FFFFFF),
            Color(0xDBFCFEFF),
            Color(0x8AF0F8FF),
            Color(0x00E6F4FF),
          ],
          const <double>[0.0, 0.42, 0.74, 1.0],
        );
      canvas.drawCircle(Offset(cx, cy), radius, puffPaint);
    }

    // Crisp silver-lined top rim highlight catching the upper-right Sun
    final rimPaint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(w * 0.54, h * 0.34),
        w * 0.26,
        const <Color>[
          Color(0xB8FFFFFF),
          Color(0x48FFFFFF),
          Color(0x00FFFFFF),
        ],
        const <double>[0.0, 0.55, 1.0],
      );
    canvas.drawCircle(Offset(w * 0.54, h * 0.34), w * 0.26, rimPaint);

    final picture = recorder.endRecording();
    final image = picture.toImageSync(width, height);
    picture.dispose();
    return image;
  }

  static ui.Image _bakeCirrusSprite({
    required int width,
    required int height,
  }) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );
    final w = width.toDouble();
    final h = height.toDouble();

    for (var i = 0; i < 5; i++) {
      final y = h * (0.28 + i * 0.11);
      final path = Path()
        ..moveTo(w * 0.05, y + 4)
        ..cubicTo(
          w * 0.32,
          y - 10 + i * 2.0,
          w * 0.66,
          y + 8 - i * 1.5,
          w * 0.95,
          y - 3,
        );
      final strokePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7.0 - i * 0.9
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.5)
        ..shader = ui.Gradient.linear(
          Offset(w * 0.05, y),
          Offset(w * 0.95, y),
          const <Color>[
            Color(0x00FFFFFF),
            Color(0x52FFFFFF),
            Color(0x66F5FBFF),
            Color(0x00FFFFFF),
          ],
          const <double>[0.0, 0.32, 0.68, 1.0],
        );
      canvas.drawPath(path, strokePaint);
    }

    final picture = recorder.endRecording();
    final image = picture.toImageSync(width, height);
    picture.dispose();
    return image;
  }

  static ui.Image _bakeMilkyWaySprite({
    required int width,
    required int height,
  }) {
    final rng = math.Random(7331);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );
    final w = width.toDouble();
    final h = height.toDouble();

    // Soft cosmic indigo-cyan nebula core along horizontal axis (rotated when drawn)
    for (var i = 0; i < 16; i++) {
      final t = i / 15.0;
      final cx = w * (0.12 + 0.76 * t) + (rng.nextDouble() - 0.5) * 18.0;
      final cy = h * 0.50 + math.sin(t * math.pi * 2.0) * 10.0;
      final r = 26.0 + rng.nextDouble() * 28.0;
      final color = i.isEven
          ? const Color(0x283B6FD4)
          : const Color(0x226348B5);
      final lobePaint = Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx, cy),
          r,
          <Color>[color, const Color(0x00091534)],
        );
      canvas.drawCircle(Offset(cx, cy), r, lobePaint);
    }

    // Fine unresolved galactic star dust
    final dustPaint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < 140; i++) {
      final x = w * (0.08 + rng.nextDouble() * 0.84);
      final spread = (rng.nextDouble() + rng.nextDouble() - 1.0) * h * 0.30;
      final y = h * 0.50 + spread;
      final alpha = (0.08 + rng.nextDouble() * 0.22).clamp(0.0, 1.0);
      dustPaint.color = const Color(0xFFDCEBFF).withValues(alpha: alpha);
      canvas.drawCircle(Offset(x, y), 0.55 + rng.nextDouble() * 0.65, dustPaint);
    }

    final picture = recorder.endRecording();
    final image = picture.toImageSync(width, height);
    picture.dispose();
    return image;
  }

  static ui.Image _bakeMoonSprite({required int size}) {
    final recorder = ui.PictureRecorder();
    final s = size.toDouble();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, s, s));
    final center = Offset(s * 0.5, s * 0.5);
    final discR = s * 0.24;

    // Soft outer silver-blue lunar atmospheric halo
    final haloPaint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        s * 0.49,
        const <Color>[
          Color(0x52D8EAFF),
          Color(0x228FB9F5),
          Color(0x004B79C4),
        ],
        const <double>[0.32, 0.64, 1.0],
      );
    canvas.drawCircle(center, s * 0.49, haloPaint);

    // Textured silver-ivory lunar disc
    final discPaint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(center.dx - discR * 0.26, center.dy - discR * 0.26),
        discR * 1.38,
        const <Color>[
          Color(0xFFFFFDF7),
          Color(0xFFEAF2FF),
          Color(0xFFC4D5EC),
        ],
        const <double>[0.0, 0.64, 1.0],
      );
    canvas
      ..save()
      ..clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: discR)))
      ..drawCircle(center, discR, discPaint);

    // Subtle Mare Tranquillitatis / Serenitatis lunar maria shading
    final mariaPaint = Paint()
      ..color = const Color(0x368AA2C2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2);
    canvas
      ..drawCircle(
        Offset(center.dx - discR * 0.22, center.dy - discR * 0.14),
        discR * 0.28,
        mariaPaint,
      )
      ..drawCircle(
        Offset(center.dx + discR * 0.18, center.dy + discR * 0.08),
        discR * 0.24,
        mariaPaint,
      )
      ..drawCircle(
        Offset(center.dx - discR * 0.05, center.dy + discR * 0.30),
        discR * 0.18,
        mariaPaint,
      )
      ..restore();

    final picture = recorder.endRecording();
    final image = picture.toImageSync(size, size);
    picture.dispose();
    return image;
  }

  static List<_SkyStarSpec> _generateStarCatalog() {
    final rng = math.Random(20261115);
    const palette = <Color>[
      Color(0xFFEFF5FF), // A-type crisp white-blue
      Color(0xFFCADBFF), // B-type sapphire white
      Color(0xFFFFF8EB), // F-type warm ivory
      Color(0xFFFFE4BE), // K-type amber starlight
      Color(0xFFA8CCFF), // O-type deep ice-blue
    ];
    final list = <_SkyStarSpec>[];
    for (var i = 0; i < 320; i++) {
      final isHero = i < 18;
      final nyRaw = rng.nextDouble();
      // Concentrate stars slightly higher toward the cosmic zenith
      final ny = math.pow(nyRaw, 1.28).toDouble() * 0.90;
      list.add(
        _SkyStarSpec(
          nx: rng.nextDouble(),
          ny: ny,
          radius: isHero
              ? 1.35 + rng.nextDouble() * 0.85
              : 0.55 + rng.nextDouble() * 0.78,
          baseAlpha: isHero
              ? 0.78 + rng.nextDouble() * 0.22
              : 0.26 + rng.nextDouble() * 0.56,
          twinkleSpeed: 1.1 + rng.nextDouble() * 2.8,
          twinklePhase: rng.nextDouble() * math.pi * 2.0,
          color: palette[i % palette.length],
          isHero: isHero,
        ),
      );
    }
    return List<_SkyStarSpec>.unmodifiable(list);
  }

  static List<_SkyCloudSpec> _generateCloudCatalog() {
    const specs = <_SkyCloudSpec>[
      // Far horizon soft mist clouds (depthLayer 0)
      _SkyCloudSpec(
        variantIndex: 0,
        baseNx: 0.12,
        ny: 0.74,
        widthFactor: 0.34,
        aspectRatio: 0.46,
        speedNxPerSec: 0.0042,
        bobPhase: 0.4,
        opacity: 0.62,
        depthLayer: 0,
      ),
      _SkyCloudSpec(
        variantIndex: 2,
        baseNx: 0.52,
        ny: 0.78,
        widthFactor: 0.38,
        aspectRatio: 0.44,
        speedNxPerSec: 0.0038,
        bobPhase: 1.9,
        opacity: 0.58,
        depthLayer: 0,
      ),
      _SkyCloudSpec(
        variantIndex: 1,
        baseNx: 0.88,
        ny: 0.72,
        widthFactor: 0.32,
        aspectRatio: 0.46,
        speedNxPerSec: 0.0045,
        bobPhase: 3.1,
        opacity: 0.60,
        depthLayer: 0,
      ),
      // Mid-altitude fair-weather cumulus (depthLayer 1)
      _SkyCloudSpec(
        variantIndex: 1,
        baseNx: 0.18,
        ny: 0.46,
        widthFactor: 0.30,
        aspectRatio: 0.50,
        speedNxPerSec: 0.0072,
        bobPhase: 0.8,
        opacity: 0.82,
        depthLayer: 1,
      ),
      _SkyCloudSpec(
        variantIndex: 3,
        baseNx: 0.64,
        ny: 0.52,
        widthFactor: 0.33,
        aspectRatio: 0.48,
        speedNxPerSec: 0.0068,
        bobPhase: 2.4,
        opacity: 0.80,
        depthLayer: 1,
      ),
      _SkyCloudSpec(
        variantIndex: 0,
        baseNx: 0.96,
        ny: 0.42,
        widthFactor: 0.28,
        aspectRatio: 0.50,
        speedNxPerSec: 0.0076,
        bobPhase: 4.2,
        opacity: 0.76,
        depthLayer: 1,
      ),
      // Near hero sunlit cumulus puffs (depthLayer 2)
      _SkyCloudSpec(
        variantIndex: 2,
        baseNx: 0.34,
        ny: 0.26,
        widthFactor: 0.34,
        aspectRatio: 0.50,
        speedNxPerSec: 0.0108,
        bobPhase: 1.3,
        opacity: 0.90,
        depthLayer: 2,
      ),
      _SkyCloudSpec(
        variantIndex: 3,
        baseNx: 0.80,
        ny: 0.31,
        widthFactor: 0.31,
        aspectRatio: 0.50,
        speedNxPerSec: 0.0102,
        bobPhase: 3.7,
        opacity: 0.86,
        depthLayer: 2,
      ),
    ];
    return specs;
  }
}

/// Reusable mutable [Paint] instances so [_DayNightSkyPainter.paint] performs
/// zero heap allocations for Paint wrappers on the 30–60 fps render path.
class _SkyPaintScratch {
  final Paint domePaint = Paint();
  final Paint horizonGlowPaint = Paint();
  final Paint spritePaint = Paint()..filterQuality = FilterQuality.medium;
  final Paint starPaint = Paint()..style = PaintingStyle.fill;
  final Paint spikePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.85
    ..strokeCap = StrokeCap.round;
  final Paint sunGlowPaint = Paint();
  final Paint rayPaint = Paint()..style = PaintingStyle.fill;
  final Paint meteorPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.4
    ..strokeCap = StrokeCap.round;
}

class _DayNightSkyPainter extends CustomPainter {
  const _DayNightSkyPainter({
    required this.state,
    required this.assets,
    required this.scratch,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final _DayNightSkyCanvasState state;
  final _SkySharedGpuAssets assets;
  final _SkyPaintScratch scratch;

  static const List<double> _domeStops = <double>[0.0, 0.30, 0.62, 0.86, 1.0];

  static const List<Color> _nightStops = <Color>[
    Color(0xFF020512),
    Color(0xFF040B1F),
    Color(0xFF071531),
    Color(0xFF0C2046),
    Color(0xFF112B59),
  ];

  static const List<Color> _dayStops = <Color>[
    Color(0xFF4CA4FA),
    Color(0xFF74BFFF),
    Color(0xFFA6DBFF),
    Color(0xFFD6EEFF),
    Color(0xFFF0FAFF),
  ];

  static double _smoothstep(double edge0, double edge1, double x) {
    final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width;
    final h = size.height;
    final p = state._dayProgress.clamp(0.0, 1.0);
    final t = state._elapsedSec;

    // 1. Atmospheric Sky Dome Gradient (Deep Cosmic Night <-> Crisp Clear Sunny Day)
    final skyCurve = _smoothstep(0.06, 0.96, p);
    final colors = <Color>[
      for (var i = 0; i < _domeStops.length; i++)
        Color.lerp(_nightStops[i], _dayStops[i], skyCurve)!,
    ];
    scratch.domePaint.shader = ui.Gradient.linear(
      Offset.zero,
      Offset(0, h),
      colors,
      _domeStops,
    );
    canvas.drawRect(Offset.zero & size, scratch.domePaint);

    // 2. Pre-Dawn / Dusk Horizon Twilight Bloom (peaks during Connecting ~0.16..0.48)
    final twilightWeight = math.sin(p * math.pi);
    if (twilightWeight > 0.015) {
      final glowCenter = Offset(w * 0.72, h * 0.98);
      final glowRadius = math.max(w, h) * 0.82;
      final amberAlpha = (0.34 * twilightWeight).clamp(0.0, 1.0);
      final cyanAlpha = (0.22 * twilightWeight).clamp(0.0, 1.0);
      scratch.horizonGlowPaint.shader = ui.Gradient.radial(
        glowCenter,
        glowRadius,
        <Color>[
          const Color(0xFFFFB26B).withValues(alpha: amberAlpha),
          const Color(0xFF38BDF8).withValues(alpha: cyanAlpha),
          Colors.transparent,
        ],
        const <double>[0.0, 0.46, 1.0],
      );
      canvas.drawRect(Offset.zero & size, scratch.horizonGlowPaint);
    }

    // 3. Nocturnal Celestial Layer: Milky Way + Twinkling Stars + Moon + Shooting Star
    final nightVisibility = (1.0 - _smoothstep(0.05, 0.56, p)).clamp(0.0, 1.0);
    if (nightVisibility > 0.008) {
      _paintNightCelestials(
        canvas: canvas,
        w: w,
        h: h,
        visibility: nightVisibility,
        dayProgress: p,
        elapsed: t,
      );
    }

    // 4. Sunny Day Celestial Layer: Upper-Right Sun, Corona, Tyndall Rays & Volumetric Clouds
    final dayVisibility = _smoothstep(0.14, 0.88, p);
    if (dayVisibility > 0.008) {
      _paintSunnyDayAtmosphere(
        canvas: canvas,
        w: w,
        h: h,
        visibility: dayVisibility,
        dayProgress: p,
        elapsed: t,
      );
    }
  }

  void _paintNightCelestials({
    required Canvas canvas,
    required double w,
    required double h,
    required double visibility,
    required double dayProgress,
    required double elapsed,
  }) {
    // 3a. Diagonal Milky Way Nebula Band
    final milkySrc = Rect.fromLTWH(
      0,
      0,
      assets.milkyWayBand.width.toDouble(),
      assets.milkyWayBand.height.toDouble(),
    );
    final bandWidth = math.max(w, h) * 1.28;
    final bandHeight = math.max(w, h) * 0.42;
    scratch.spritePaint.color =
        Colors.white.withValues(alpha: (0.72 * visibility).clamp(0.0, 1.0));
    canvas
      ..save()
      ..translate(w * 0.48, h * 0.36)
      ..rotate(-0.42)
      ..drawImageRect(
        assets.milkyWayBand,
        milkySrc,
        Rect.fromCenter(
          center: Offset.zero,
          width: bandWidth,
          height: bandHeight,
        ),
        scratch.spritePaint,
      )
      ..restore();

    // 3b. Multi-temperature Blackbody Starfield + 4-Ray Hero Star Glints
    for (final star in assets.stars) {
      final twinkle = 0.76 +
          0.24 * math.sin(elapsed * star.twinkleSpeed + star.twinklePhase);
      final horizonFade = (1.0 - _smoothstep(0.70, 0.94, star.ny));
      final alpha =
          (star.baseAlpha * twinkle * horizonFade * visibility).clamp(0.0, 1.0);
      if (alpha <= 0.015) continue;

      final sx = star.nx * w;
      final sy = star.ny * h;
      final center = Offset(sx, sy);
      scratch.starPaint.color = star.color.withValues(alpha: alpha);
      canvas.drawCircle(center, star.radius, scratch.starPaint);

      if (star.isHero && alpha > 0.35) {
        final arm = star.radius * (3.1 + 0.8 * twinkle);
        scratch.spikePaint.color =
            star.color.withValues(alpha: (alpha * 0.42).clamp(0.0, 1.0));
        canvas
          ..drawLine(Offset(sx - arm, sy), Offset(sx + arm, sy), scratch.spikePaint)
          ..drawLine(Offset(sx, sy - arm), Offset(sx, sy + arm), scratch.spikePaint);
      }
    }

    // 3c. Textured Silver Moon (gently sets slightly as dawn approaches)
    final moonSize = (math.min(w, h) * 0.16).clamp(44.0, 88.0);
    final moonCenter = Offset(
      w * 0.80,
      h * (0.19 + 0.14 * dayProgress),
    );
    final moonSrc = Rect.fromLTWH(
      0,
      0,
      assets.moonSprite.width.toDouble(),
      assets.moonSprite.height.toDouble(),
    );
    scratch.spritePaint.color =
        Colors.white.withValues(alpha: (0.95 * visibility).clamp(0.0, 1.0));
    canvas.drawImageRect(
      assets.moonSprite,
      moonSrc,
      Rect.fromCenter(center: moonCenter, width: moonSize, height: moonSize),
      scratch.spritePaint,
    );

    // 3d. Occasional Subtle Shooting Star (only in ambient animated mode)
    if (elapsed > 0.5 && visibility > 0.65) {
      const cycleSec = 9.5;
      final cyclePos = elapsed % cycleSec;
      if (cyclePos < 0.85) {
        final u = cyclePos / 0.85;
        final cycleIndex = (elapsed ~/ cycleSec);
        final startX = w * (0.26 + ((cycleIndex * 37) % 48) / 100.0);
        final startY = h * (0.10 + ((cycleIndex * 19) % 24) / 100.0);
        final head = Offset(startX + u * w * 0.22, startY + u * h * 0.14);
        final tail = Offset(head.dx - w * 0.075, head.dy - h * 0.048);
        final meteorAlpha = math.sin(u * math.pi) * 0.78 * visibility;
        scratch.meteorPaint.shader = ui.Gradient.linear(
          tail,
          head,
          <Color>[
            Colors.transparent,
            const Color(0xFFE0F2FE).withValues(alpha: meteorAlpha),
          ],
        );
        canvas.drawLine(tail, head, scratch.meteorPaint);
      }
    }
  }

  void _paintSunnyDayAtmosphere({
    required Canvas canvas,
    required double w,
    required double h,
    required double visibility,
    required double dayProgress,
    required double elapsed,
  }) {
    final sunLift = _smoothstep(0.18, 1.0, dayProgress);
    final sunCenter = Offset(
      w * 0.83,
      h * (0.48 - 0.32 * sunLift),
    );
    final shortest = math.min(w, h);

    // 4a. Subtle Diagonal Tyndall Crepuscular Light Shafts
    if (visibility > 0.25) {
      final rayAlpha = (0.10 * visibility).clamp(0.0, 1.0);
      const rayAngles = <double>[2.08, 2.28, 2.50, 2.72];
      final rayLength = math.max(w, h) * 0.92;
      for (var i = 0; i < rayAngles.length; i++) {
        final baseAngle = rayAngles[i] + math.sin(elapsed * 0.22 + i) * 0.018;
        const spread = 0.045;
        final p1 = Offset(
          sunCenter.dx + math.cos(baseAngle - spread) * rayLength,
          sunCenter.dy + math.sin(baseAngle - spread) * rayLength,
        );
        final p2 = Offset(
          sunCenter.dx + math.cos(baseAngle + spread) * rayLength,
          sunCenter.dy + math.sin(baseAngle + spread) * rayLength,
        );
        final path = Path()
          ..moveTo(sunCenter.dx, sunCenter.dy)
          ..lineTo(p1.dx, p1.dy)
          ..lineTo(p2.dx, p2.dy)
          ..close();
        scratch.rayPaint.shader = ui.Gradient.linear(
          sunCenter,
          Offset((p1.dx + p2.dx) * 0.5, (p1.dy + p2.dy) * 0.5),
          <Color>[
            const Color(0xFFFFFBEB).withValues(alpha: rayAlpha),
            Colors.transparent,
          ],
        );
        canvas.drawPath(path, scratch.rayPaint);
      }
    }

    // 4b. Mie Scattering Solar Corona & Crisp Radiant Sun Core
    final outerHaloR = (shortest * 0.42).clamp(96.0, 280.0);
    scratch.sunGlowPaint.shader = ui.Gradient.radial(
      sunCenter,
      outerHaloR,
      <Color>[
        Colors.white.withValues(alpha: (0.94 * visibility).clamp(0.0, 1.0)),
        const Color(0xFFFFF7D6)
            .withValues(alpha: (0.52 * visibility).clamp(0.0, 1.0)),
        const Color(0xFFE0F4FF)
            .withValues(alpha: (0.18 * visibility).clamp(0.0, 1.0)),
        Colors.transparent,
      ],
      const <double>[0.0, 0.16, 0.46, 1.0],
    );
    canvas.drawCircle(sunCenter, outerHaloR, scratch.sunGlowPaint);

    // 4c. High-Altitude Wispy Cirrus Ribbons
    final cirrusSrc = Rect.fromLTWH(
      0,
      0,
      assets.cirrusRibbon.width.toDouble(),
      assets.cirrusRibbon.height.toDouble(),
    );
    final cirrusDrift = (elapsed * 0.0032) % 1.0;
    scratch.spritePaint.color =
        Colors.white.withValues(alpha: (0.52 * visibility).clamp(0.0, 1.0));
    for (var i = 0; i < 2; i++) {
      final nx = ((0.28 + i * 0.52 - cirrusDrift) % 1.36) - 0.18;
      final cw = w * 0.46;
      final ch = cw * 0.24;
      canvas.drawImageRect(
        assets.cirrusRibbon,
        cirrusSrc,
        Rect.fromCenter(
          center: Offset(nx * w, h * (0.14 + i * 0.07)),
          width: cw,
          height: ch,
        ),
        scratch.spritePaint,
      );
    }

    // 4d. Multi-Depth Parallax Volumetric White Cumulus Clouds
    for (final cloud in assets.clouds) {
      final sprite = assets.cloudVariants[cloud.variantIndex];
      final src = Rect.fromLTWH(
        0,
        0,
        sprite.width.toDouble(),
        sprite.height.toDouble(),
      );
      final span = 1.0 + cloud.widthFactor * 1.35;
      final rawNx =
          (cloud.baseNx - elapsed * cloud.speedNxPerSec) % span;
      final wrappedNx =
          (rawNx < 0 ? rawNx + span : rawNx) - cloud.widthFactor * 0.675;
      final bobY = math.sin(elapsed * 0.35 + cloud.bobPhase) * 3.0;
      final cw = math.max(110.0, w * cloud.widthFactor);
      final ch = cw * cloud.aspectRatio;
      final cloudAlpha = (cloud.opacity * visibility).clamp(0.0, 1.0);

      scratch.spritePaint.color = Colors.white.withValues(alpha: cloudAlpha);
      canvas.drawImageRect(
        sprite,
        src,
        Rect.fromCenter(
          center: Offset(wrappedNx * w, cloud.ny * h + bobY),
          width: cw,
          height: ch,
        ),
        scratch.spritePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DayNightSkyPainter oldDelegate) =>
      oldDelegate.state != state;
}

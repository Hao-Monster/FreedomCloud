import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/ui_activity.dart';
import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestRunTime extends RunTime {
  _TestRunTime();

  @override
  int? build() => globalState.appState.runTime;
}

final _testCustomBackgroundUrlProvider = StateProvider<String?>((ref) => null);

Widget _buildSkyScaffoldHost({
  required ProviderContainer container,
  required Widget body,
  Widget? sideNavigationBar,
  bool disableBackground = false,
  bool disableAnimations = false,
  bool tickerEnabled = true,
  Brightness ambientBrightness = Brightness.dark,
  bool syncAppThemeMode = false,
}) {
  final darkScheme = calibrateFreedomNetColorScheme(
    ColorScheme.fromSeed(
      seedColor: const Color(defaultPrimaryColor),
      brightness: Brightness.dark,
    ),
    seedColor: const Color(defaultPrimaryColor),
  );
  final lightScheme = calibrateFreedomNetColorScheme(
    ColorScheme.fromSeed(
      seedColor: const Color(defaultPrimaryColor),
      brightness: Brightness.light,
    ),
    seedColor: const Color(defaultPrimaryColor),
  );
  final fallbackScheme =
      ambientBrightness == Brightness.dark ? darkScheme : lightScheme;
  return UncontrolledProviderScope(
    container: container,
    child: Consumer(
      builder: (_, ref, __) {
        final ThemeMode resolvedMode;
        if (syncAppThemeMode) {
          final backgroundUrl = ref.watch(backgroundUrlProvider);
          final hasCustom = backgroundUrl != null && backgroundUrl.isNotEmpty;
          final isRunning =
              ref.watch(runTimeProvider.select((state) => state != null));
          final pendingTarget = ref.watch(statusSwitchPendingProvider);
          resolvedMode = hasCustom
              ? ThemeMode.dark
              : resolveDayNightThemeMode(
                  isRunning: isRunning,
                  pendingTarget: pendingTarget,
                );
        } else {
          resolvedMode = ThemeMode.light;
        }
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.delegate.supportedLocales,
          themeMode: resolvedMode,
          theme: buildFreedomNetThemeData(
            colorScheme: syncAppThemeMode ? lightScheme : fallbackScheme,
          ),
          darkTheme: buildFreedomNetThemeData(colorScheme: darkScheme),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: disableAnimations,
            ),
            child: TickerMode(
              enabled: tickerEnabled,
              child: child!,
            ),
          ),
          home: CommonScaffold(
            title: '代理',
            disableBackground: disableBackground,
            sideNavigationBar: sideNavigationBar,
            body: body,
          ),
        );
      },
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await AppLocalizations.load(const Locale('zh', 'CN'));
  });

  setUp(() {
    globalState.config = const Config(themeProps: defaultThemeProps);
    globalState.appState = AppState(
      viewSize: const Size(1200, 820),
      version: 1,
      requests: FixedList(1),
      logs: FixedList(1),
      traffics: FixedList(1),
      totalTraffic: Traffic(),
      isInit: true,
    );
  });

  test(
    'DNS-01: resolveDayNightSkyPhase, target progress, and ThemeMode strictly honor connected-only daytime rule',
    () {
      // 1. Proxy OFF -> Deep Night (0.0)
      expect(
        resolveDayNightSkyPhase(isRunning: false, pendingTarget: null),
        equals(DayNightSkyPhase.night),
      );
      expect(
        resolveDayNightTargetProgress(DayNightSkyPhase.night),
        equals(0.0),
      );
      expect(
        resolveDayNightThemeMode(isRunning: false, pendingTarget: null),
        equals(ThemeMode.dark),
      );

      // 2. Proxy switch turned ON, bring-up / handshake in flight -> Pre-Dawn (0.16), NOT daytime
      expect(
        resolveDayNightSkyPhase(isRunning: false, pendingTarget: true),
        equals(DayNightSkyPhase.connecting),
      );
      expect(
        resolveDayNightSkyPhase(isRunning: true, pendingTarget: true),
        equals(DayNightSkyPhase.connecting),
      );
      expect(
        resolveDayNightTargetProgress(DayNightSkyPhase.connecting),
        closeTo(0.16, 1e-6),
      );
      expect(
        resolveDayNightThemeMode(isRunning: false, pendingTarget: true),
        equals(ThemeMode.dark),
      );

      // 3. Proxy switch ON AND connected -> Clear Bright Sunny Day (1.0)
      expect(
        resolveDayNightSkyPhase(isRunning: true, pendingTarget: null),
        equals(DayNightSkyPhase.day),
      );
      expect(
        resolveDayNightTargetProgress(DayNightSkyPhase.day),
        equals(1.0),
      );
      expect(
        resolveDayNightThemeMode(isRunning: true, pendingTarget: null),
        equals(ThemeMode.light),
      );

      // 4. Proxy switch pressed OFF while running -> immediately returns to Night (0.0)
      expect(
        resolveDayNightSkyPhase(isRunning: true, pendingTarget: false),
        equals(DayNightSkyPhase.night),
      );
      expect(
        resolveDayNightThemeMode(isRunning: true, pendingTarget: false),
        equals(ThemeMode.dark),
      );
    },
  );

  testWidgets(
    'DNS-02: Failed proxy handshake warms only to pre-dawn (~0.16) and rolls back to Deep Night without ever entering Daytime',
    (tester) async {
      final previousConfig = globalState.config;
      final previousAppState = globalState.appState;
      addTearDown(() {
        globalState.config = previousConfig;
        globalState.appState = previousAppState;
      });
      globalState.config = const Config(themeProps: defaultThemeProps);

      final container = ProviderContainer(
        overrides: [
          runTimeProvider.overrideWith(_TestRunTime.new),
        ],
      );
      addTearDown(container.dispose);

      BuildContext? capturedBodyContext;
      await tester.pumpWidget(
        _buildSkyScaffoldHost(
          container: container,
          body: Builder(
            builder: (ctx) {
              capturedBodyContext = ctx;
              return const SizedBox.expand();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      DayNightSkyDebugSnapshot snap() =>
          DayNightSkyBackground.debugSnapshotOf(tester)!;

      expect(snap().phase, equals(DayNightSkyPhase.night));
      expect(snap().dayProgress, equals(0.0));
      expect(snap().isDaySurface, isFalse);
      expect(DayNightSkyScope.isActiveOf(capturedBodyContext!), isTrue);

      // Turn switch ON -> enters connecting handshake
      container.read(statusSwitchPendingProvider.notifier).state = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final midHandshake = snap();
      expect(midHandshake.phase, equals(DayNightSkyPhase.connecting));
      expect(midHandshake.dayProgress, greaterThan(0.04));
      expect(midHandshake.dayProgress, lessThanOrEqualTo(0.18));
      expect(midHandshake.isDaySurface, isFalse);
      expect(
        Theme.of(capturedBodyContext!).brightness,
        equals(Brightness.dark),
      );

      // Simulate connection bring-up failure: pending clears while runTime remains null
      container.read(statusSwitchPendingProvider.notifier).state = null;
      await tester.pumpAndSettle();

      final afterFailure = snap();
      expect(afterFailure.phase, equals(DayNightSkyPhase.night));
      expect(afterFailure.dayProgress, equals(0.0));
      expect(afterFailure.isDaySurface, isFalse);
      expect(
        Theme.of(capturedBodyContext!).brightness,
        equals(Brightness.dark),
      );
    },
  );

  testWidgets(
    'DNS-03: Full Night -> Connecting -> Connected Sunny Day -> Night lifecycle settles cleanly and adapts translucent card surfaces',
    (tester) async {
      final previousConfig = globalState.config;
      final previousAppState = globalState.appState;
      addTearDown(() {
        globalState.config = previousConfig;
        globalState.appState = previousAppState;
      });
      globalState.config = const Config(themeProps: defaultThemeProps);

      final container = ProviderContainer(
        overrides: [
          runTimeProvider.overrideWith(_TestRunTime.new),
        ],
      );
      addTearDown(container.dispose);

      BuildContext? bodyCtx;
      await tester.pumpWidget(
        _buildSkyScaffoldHost(
          container: container,
          body: Builder(
            builder: (ctx) {
              bodyCtx = ctx;
              return const Card(
                key: ValueKey('probe-card'),
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('节点卡片'),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Night state: dark translucent card over starry night
      expect(Theme.of(bodyCtx!).brightness, equals(Brightness.dark));
      final nightCardColor = Theme.of(bodyCtx!).cardTheme.color!;
      expect(nightCardColor.a, lessThan(0.90));

      // Step 1: Switch ON (connecting)
      container.read(statusSwitchPendingProvider.notifier).state = true;
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        DayNightSkyBackground.debugSnapshotOf(tester)!.phase,
        equals(DayNightSkyPhase.connecting),
      );

      // Step 2: Connection established (runTime non-null, pending cleared)
      container.read(runTimeProvider.notifier).value = 1200;
      container.read(statusSwitchPendingProvider.notifier).state = null;
      await tester.pumpAndSettle();

      final daySnap = DayNightSkyBackground.debugSnapshotOf(tester)!;
      expect(daySnap.phase, equals(DayNightSkyPhase.day));
      expect(daySnap.dayProgress, equals(1.0));
      expect(daySnap.isDaySurface, isTrue);
      expect(Theme.of(bodyCtx!).brightness, equals(Brightness.light));
      final dayCardColor = Theme.of(bodyCtx!).cardTheme.color!;
      expect(dayCardColor.a, lessThan(0.90));

      // Step 3: User turns switch OFF -> immediate dusk transition back to Night
      container.read(statusSwitchPendingProvider.notifier).state = false;
      await tester.pump(const Duration(milliseconds: 120));
      expect(
        DayNightSkyBackground.debugSnapshotOf(tester)!.phase,
        equals(DayNightSkyPhase.night),
      );

      container.read(runTimeProvider.notifier).value = null;
      container.read(statusSwitchPendingProvider.notifier).state = null;
      await tester.pumpAndSettle();

      final finalSnap = DayNightSkyBackground.debugSnapshotOf(tester)!;
      expect(finalSnap.phase, equals(DayNightSkyPhase.night));
      expect(finalSnap.dayProgress, equals(0.0));
      expect(finalSnap.isDaySurface, isFalse);
      expect(Theme.of(bodyCtx!).brightness, equals(Brightness.dark));
    },
  );

  testWidgets(
    'DNS-04: Pixel raster verification distinguishes Deep Cosmic Starry Night from Clear Azure Sunny Day',
    (tester) async {
      Future<Uint8List> captureSkyBytes(DayNightSkyPhase phase) async {
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 240),
                disableAnimations: true,
              ),
              child: Center(
                child: RepaintBoundary(
                  key: boundaryKey,
                  child: SizedBox(
                    width: 360,
                    height: 240,
                    child: DayNightSkyBackground(
                      phase: phase,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final boundary = boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final rawBytes = await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1.0);
          try {
            final byteData =
                await image.toByteData(format: ui.ImageByteFormat.rawRgba);
            return byteData!.buffer.asUint8List();
          } finally {
            image.dispose();
          }
        });
        return rawBytes!;
      }

      ({double meanLum, double avgR, double avgG, double avgB, double maxLum})
          analyze(Uint8List rgba) {
        var sumR = 0.0;
        var sumG = 0.0;
        var sumB = 0.0;
        var sumLum = 0.0;
        var maxLum = 0.0;
        final pixelCount = rgba.length ~/ 4;
        for (var i = 0; i < rgba.length; i += 4) {
          final r = rgba[i] / 255.0;
          final g = rgba[i + 1] / 255.0;
          final b = rgba[i + 2] / 255.0;
          final lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
          sumR += r;
          sumG += g;
          sumB += b;
          sumLum += lum;
          if (lum > maxLum) maxLum = lum;
        }
        return (
          meanLum: sumLum / pixelCount,
          avgR: sumR / pixelCount,
          avgG: sumG / pixelCount,
          avgB: sumB / pixelCount,
          maxLum: maxLum,
        );
      }

      final nightRgba = await captureSkyBytes(DayNightSkyPhase.night);
      final dayRgba = await captureSkyBytes(DayNightSkyPhase.day);

      final nightStats = analyze(nightRgba);
      final dayStats = analyze(dayRgba);

      // Night: deep dark cosmos (< 0.10 mean luminance), nocturnal blue > red, bright pinpoint stars/moon present
      expect(nightStats.meanLum, lessThan(0.10));
      expect(nightStats.avgB, greaterThan(nightStats.avgR));
      expect(nightStats.maxLum, greaterThan(0.45));

      // Sunny Day: bright luminous azure sky & white clouds, clear blue dominance, > 5x brighter than Night
      expect(dayStats.meanLum, greaterThan(0.42));
      expect(dayStats.avgB, greaterThan(dayStats.avgR));
      expect(dayStats.meanLum, greaterThan(nightStats.meanLum * 5.0));
    },
  );

  testWidgets(
    'DNS-05: disableBackground, reduce-motion instant snap, and TickerMode(false) 0-fps gate work cleanly',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          runTimeProvider.overrideWith(_TestRunTime.new),
        ],
      );
      addTearDown(container.dispose);

      // 1. disableBackground: true omits DayNightSkyBackground
      BuildContext? disabledCtx;
      await tester.pumpWidget(
        _buildSkyScaffoldHost(
          container: container,
          disableBackground: true,
          body: Builder(
            builder: (ctx) {
              disabledCtx = ctx;
              return const SizedBox.expand();
            },
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(DayNightSkyBackground), findsNothing);
      expect(DayNightSkyScope.isActiveOf(disabledCtx!), isFalse);

      // 2. Reduce-motion snaps progress on first pump without intermediate frames
      container.read(runTimeProvider.notifier).value = 500;
      await tester.pumpWidget(
        _buildSkyScaffoldHost(
          container: container,
          disableAnimations: true,
          body: const SizedBox.expand(),
        ),
      );
      await tester.pump();
      expect(
        DayNightSkyBackground.debugSnapshotOf(tester)!.dayProgress,
        equals(1.0),
      );

      // 3. Continuous mode respects TickerMode(false) -> stops ticker at 0 fps
      final tickerEnabled = ValueNotifier<bool>(true);
      addTearDown(tickerEnabled.dispose);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(size: Size(400, 300)),
            child: ValueListenableBuilder<bool>(
              valueListenable: tickerEnabled,
              builder: (_, enabled, __) => TickerMode(
                enabled: enabled,
                child: const DayNightSkyBackground(
                  phase: DayNightSkyPhase.day,
                  continuousAnimationInTests: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        DayNightSkyBackground.debugSnapshotOf(tester)!.isTickerActive,
        isTrue,
      );

      tickerEnabled.value = false;
      await tester.pump();
      expect(
        DayNightSkyBackground.debugSnapshotOf(tester)!.isTickerActive,
        isFalse,
      );
    },
  );

  testWidgets(
    'DNS-06: Existing FloatingProxyDock / EarthProxySwitch UI coexists untouched above CommonScaffold DayNightSkyBackground',
    (tester) async {
      final previousConfig = globalState.config;
      final previousAppState = globalState.appState;
      addTearDown(() {
        globalState.config = previousConfig;
        globalState.appState = previousAppState;
      });
      globalState.config = const Config(themeProps: defaultThemeProps);

      final container = ProviderContainer(
        overrides: [
          runTimeProvider.overrideWith(_TestRunTime.new),
        ],
      );
      addTearDown(container.dispose);

      var toggled = 0;
      await tester.pumpWidget(
        _buildSkyScaffoldHost(
          container: container,
          body: Consumer(
            builder: (_, ref, __) {
              final isRunning =
                  ref.watch(runTimeProvider.select((s) => s != null));
              final pendingTarget = ref.watch(statusSwitchPendingProvider);
              return Center(
                child: FloatingProxyDock(
                  key: const ValueKey('dns06-dock'),
                  switchKey: const ValueKey('dns06-earth-switch'),
                  isRunning: isRunning,
                  pendingTarget: pendingTarget,
                  startCancelable: false,
                  onToggle: () => toggled++,
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DayNightSkyBackground), findsOneWidget);
      expect(find.byType(EarthProxySwitch), findsOneWidget);
      expect(
        DayNightSkyBackground.debugSnapshotOf(tester)!.phase,
        equals(DayNightSkyPhase.night),
      );

      // Tapping the untouched EarthProxySwitch center still dispatches onToggle cleanly.
      await tester.tap(find.byKey(const ValueKey('dns06-earth-switch')));
      await tester.pump();
      expect(toggled, equals(1));

      // Transitioning providers to connected updates sky to Sunny Day while EarthProxySwitch remains mounted intact.
      container.read(runTimeProvider.notifier).value = 900;
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      final connectedSnap = DayNightSkyBackground.debugSnapshotOf(tester)!;
      expect(connectedSnap.phase, equals(DayNightSkyPhase.day));
      expect(connectedSnap.dayProgress, closeTo(1.0, 0.02));
      expect(find.byType(EarthProxySwitch), findsOneWidget);
    },
  );

  testWidgets(
    'DNS-07: Desktop sideNavigationBar and main body stay brightness-synchronized across the 0.52 sky surface threshold',
    (tester) async {
      final previousConfig = globalState.config;
      final previousAppState = globalState.appState;
      addTearDown(() {
        globalState.config = previousConfig;
        globalState.appState = previousAppState;
      });
      globalState.config = const Config(themeProps: defaultThemeProps);

      final container = ProviderContainer(
        overrides: [
          runTimeProvider.overrideWith(_TestRunTime.new),
        ],
      );
      addTearDown(container.dispose);

      BuildContext? railCtx;
      BuildContext? bodyCtx;
      await tester.pumpWidget(
        _buildSkyScaffoldHost(
          container: container,
          syncAppThemeMode: true,
          sideNavigationBar: SizedBox(
            width: 104,
            child: Builder(
              builder: (ctx) {
                railCtx = ctx;
                return const SizedBox.expand();
              },
            ),
          ),
          body: Builder(
            builder: (ctx) {
              bodyCtx = ctx;
              return const SizedBox.expand();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(Theme.of(railCtx!).brightness, equals(Brightness.dark));
      expect(Theme.of(bodyCtx!).brightness, equals(Brightness.dark));
      expect(DayNightSkyScope.isDaySurfaceOf(railCtx!), isFalse);

      // MaterialApp switches ThemeMode.light immediately when connected, while
      // sky progresses gradually; rail and body must both wait until dayProgress >= 0.52.
      container.read(runTimeProvider.notifier).value = 1200;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final midSnap = DayNightSkyBackground.debugSnapshotOf(tester)!;
      expect(midSnap.dayProgress, lessThan(kDayNightSurfaceThreshold));
      expect(Theme.of(railCtx!).brightness, equals(Brightness.dark));
      expect(Theme.of(bodyCtx!).brightness, equals(Brightness.dark));
      expect(DayNightSkyScope.isDaySurfaceOf(railCtx!), isFalse);

      await tester.pumpAndSettle();
      final endSnap = DayNightSkyBackground.debugSnapshotOf(tester)!;
      expect(endSnap.dayProgress, equals(1.0));
      expect(Theme.of(railCtx!).brightness, equals(Brightness.light));
      expect(Theme.of(bodyCtx!).brightness, equals(Brightness.light));
      expect(DayNightSkyScope.isDaySurfaceOf(railCtx!), isTrue);
    },
  );

  testWidgets(
    'DNS-08: Minimized uiActivity and TickerMode(false) routes snap sky phase cleanly without replaying stale transitions',
    (tester) async {
      final previousConfig = globalState.config;
      final previousAppState = globalState.appState;
      addTearDown(() {
        uiActivity
          ..setVisible(true)
          ..setMinimized(false)
          ..setLifecycle(AppLifecycleState.resumed);
        globalState.config = previousConfig;
        globalState.appState = previousAppState;
      });
      globalState.config = const Config(themeProps: defaultThemeProps);

      final container = ProviderContainer(
        overrides: [
          runTimeProvider.overrideWith(_TestRunTime.new),
        ],
      );
      addTearDown(container.dispose);

      // Part A: uiActivity minimized (tray) -> phase change completes immediately
      BuildContext? bodyCtx;
      await tester.pumpWidget(
        _buildSkyScaffoldHost(
          container: container,
          body: Builder(
            builder: (ctx) {
              bodyCtx = ctx;
              return const SizedBox.expand();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(DayNightSkyBackground.debugSnapshotOf(tester)!.dayProgress, 0.0);

      uiActivity.setMinimized(true);
      await tester.pump();
      expect(uiActivity.value, isFalse);

      container.read(runTimeProvider.notifier).value = 900;
      await tester.pump();
      await tester.pump();

      final snappedHidden = DayNightSkyBackground.debugSnapshotOf(tester)!;
      expect(snappedHidden.phase, equals(DayNightSkyPhase.day));
      expect(snappedHidden.dayProgress, equals(1.0));
      expect(snappedHidden.isDaySurface, isTrue);
      expect(Theme.of(bodyCtx!).brightness, equals(Brightness.light));

      // Restoring visibility must remain at 1.0 (zero stale night->day replay).
      uiActivity.setMinimized(false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        DayNightSkyBackground.debugSnapshotOf(tester)!.dayProgress,
        equals(1.0),
      );

      // Part B: Route pushed over CommonScaffold mid-transition (TickerMode false)
      final tickerNotifier = ValueNotifier<bool>(true);
      addTearDown(tickerNotifier.dispose);
      container.read(runTimeProvider.notifier).value = null;
      await tester.pumpWidget(
        ValueListenableBuilder<bool>(
          valueListenable: tickerNotifier,
          builder: (_, enabled, __) => _buildSkyScaffoldHost(
            container: container,
            tickerEnabled: enabled,
            body: Builder(
              builder: (ctx) {
                bodyCtx = ctx;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(DayNightSkyBackground.debugSnapshotOf(tester)!.dayProgress, 0.0);

      container.read(runTimeProvider.notifier).value = 1500;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(
        DayNightSkyBackground.debugSnapshotOf(tester)!.dayProgress,
        lessThan(kDayNightSurfaceThreshold),
      );

      tickerNotifier.value = false;
      await tester.pump();
      await tester.pump();

      final coveredSnap = DayNightSkyBackground.debugSnapshotOf(tester)!;
      expect(coveredSnap.dayProgress, equals(1.0));
      expect(coveredSnap.isDaySurface, isTrue);
      expect(coveredSnap.isTickerActive, isFalse);
      expect(Theme.of(bodyCtx!).brightness, equals(Brightness.light));
    },
  );

  testWidgets(
    'DNS-09: Toggling back from custom background / disabled background resyncs DayNightSkyScope cleanly',
    (tester) async {
      final previousConfig = globalState.config;
      final previousAppState = globalState.appState;
      addTearDown(() {
        globalState.config = previousConfig;
        globalState.appState = previousAppState;
      });
      globalState.config = const Config(themeProps: defaultThemeProps);

      final container = ProviderContainer(
        overrides: [
          runTimeProvider.overrideWith(_TestRunTime.new),
          backgroundUrlProvider.overrideWith(
            (ref) => ref.watch(_testCustomBackgroundUrlProvider),
          ),
        ],
      );
      addTearDown(container.dispose);

      BuildContext? bodyCtx;
      await tester.pumpWidget(
        _buildSkyScaffoldHost(
          container: container,
          syncAppThemeMode: true,
          body: Builder(
            builder: (ctx) {
              bodyCtx = ctx;
              return const Card(
                child: Text('背景切换测试卡片'),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(DayNightSkyScope.isActiveOf(bodyCtx!), isTrue);
      expect(DayNightSkyScope.isDaySurfaceOf(bodyCtx!), isFalse);
      expect(Theme.of(bodyCtx!).brightness, equals(Brightness.dark));

      // Enable custom background while disconnected
      container.read(_testCustomBackgroundUrlProvider.notifier).state =
          'https://127.0.0.1:1/custom-bg.png';
      await tester.pump();
      expect(DayNightSkyScope.isActiveOf(bodyCtx!), isFalse);

      // Connect while custom background is active
      container.read(runTimeProvider.notifier).value = 1800;
      await tester.pump();
      expect(Theme.of(bodyCtx!).brightness, equals(Brightness.dark));

      // Clear custom background -> default sky returns and resyncs immediately to Day
      container.read(_testCustomBackgroundUrlProvider.notifier).state = null;
      await tester.pump();
      expect(DayNightSkyScope.isActiveOf(bodyCtx!), isTrue);
      expect(DayNightSkyScope.isDaySurfaceOf(bodyCtx!), isTrue);
      expect(Theme.of(bodyCtx!).brightness, equals(Brightness.light));
    },
  );
}

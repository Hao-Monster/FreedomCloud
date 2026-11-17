import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/theme.dart';
import 'package:flclashx/common/tun_runtime.dart';
import 'package:flclashx/controller.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/views/dashboard/dashboard.dart';
import 'package:flclashx/views/dashboard/widgets/hero_connect.dart';
import 'package:flclashx/views/dashboard/widgets/start_button.dart';
import 'package:flclashx/views/profiles/receive_profile_dialog.dart';
import 'package:flclashx/views/theme.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.root);
  final String root;

  @override
  Future<String> getApplicationSupportPath() async => root;

  @override
  Future<String> getTemporaryPath() async => root;

  @override
  Future<String> getDownloadsPath() async => root;
}

class _TestRunTime extends RunTime {
  @override
  int? build() => globalState.appState.runTime;
}

class _TestAppController implements AppController {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _AddSyncTestController extends _TestAppController {
  String? syncedUrl;

  @override
  Future<void> addProfileFromUrlForSync(String url) async {
    syncedUrl = url;
  }
}

class _DirectHttpOverrides extends HttpOverrides {}

void _resetGlobalTestState({
  ThemeProps themeProps = defaultThemeProps,
  AppSettingProps appSetting = const AppSettingProps(),
  int? runTime,
  List<Profile> profiles = const [],
  String? currentProfileId,
  PageLabel pageLabel = PageLabel.proxies,
}) {
  globalState.accentColor = const Color(defaultPrimaryColor);
  globalState.config = Config(
    themeProps: themeProps,
    appSetting: appSetting,
    profiles: profiles,
    currentProfileId: currentProfileId,
  );
  globalState.appState = AppState(
    viewSize: const Size(1040, 820),
    version: 1,
    requests: FixedList(1),
    logs: FixedList(1),
    traffics: FixedList(1),
    totalTraffic: Traffic(),
    isInit: true,
    runTime: runTime,
    pageLabel: pageLabel,
  );
}

Widget _buildLocalizedApp({
  required ProviderContainer container,
  required Widget home,
  bool disableAnimations = false,
  bool attachGlobalNavigatorKey = false,
  Size viewSize = const Size(960, 800),
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

  return UncontrolledProviderScope(
    container: container,
    child: Consumer(
      builder: (_, ref, __) {
        final themeProps = ref.watch(themeSettingProvider);
        final isRunning =
            ref.watch(runTimeProvider.select((state) => state != null));
        final pendingTarget = ref.watch(statusSwitchPendingProvider);
        final effectiveMode = resolveDayNightThemeMode(
          isRunning: isRunning,
          pendingTarget: pendingTarget,
          mode: themeProps.skyMode,
        );
        return MaterialApp(
          navigatorKey:
              attachGlobalNavigatorKey ? globalState.navigatorKey : null,
          debugShowCheckedModeBanner: false,
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.delegate.supportedLocales,
          themeMode: effectiveMode,
          theme: buildFreedomNetThemeData(colorScheme: lightScheme),
          darkTheme: buildFreedomNetThemeData(colorScheme: darkScheme),
          builder: (context, child) {
            globalState.measure = Measure.of(context, 1.0);
            globalState.theme = CommonTheme.of(context, 1.0);
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                size: viewSize,
                disableAnimations: disableAnimations,
              ),
              child: child!,
            );
          },
          home: home,
        );
      },
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('flclashx_thm_tdd_');
    PathProviderPlatform.instance = _TestPaths(tempDir.path);
    await AppLocalizations.load(const Locale('zh', 'CN'));
  });

  tearDownAll(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() {
    _resetGlobalTestState();
    globalState.appController = _TestAppController();
  });

  group('THM-01: Day/Night sky modes, glass presets, and ThemeProps persistence',
      () {
    test(
        'resolveDayNightSkyPhase & resolveDayNightThemeMode honor followConnection, alwaysNight, and alwaysDay',
        () {
      // followConnection (default)
      expect(
        resolveDayNightSkyPhase(
          isRunning: false,
          pendingTarget: null,
          mode: DayNightSkyMode.followConnection,
        ),
        equals(DayNightSkyPhase.night),
      );
      expect(
        resolveDayNightSkyPhase(
          isRunning: false,
          pendingTarget: true,
          mode: DayNightSkyMode.followConnection,
        ),
        equals(DayNightSkyPhase.connecting),
      );
      expect(
        resolveDayNightSkyPhase(
          isRunning: true,
          pendingTarget: null,
          mode: DayNightSkyMode.followConnection,
        ),
        equals(DayNightSkyPhase.day),
      );

      // alwaysNight overrides running state
      expect(
        resolveDayNightSkyPhase(
          isRunning: true,
          pendingTarget: null,
          mode: DayNightSkyMode.alwaysNight,
        ),
        equals(DayNightSkyPhase.night),
      );
      expect(
        resolveDayNightSkyPhase(
          isRunning: false,
          pendingTarget: true,
          mode: DayNightSkyMode.alwaysNight,
        ),
        equals(DayNightSkyPhase.night),
      );
      expect(
        resolveDayNightThemeMode(
          isRunning: true,
          pendingTarget: null,
          mode: DayNightSkyMode.alwaysNight,
        ),
        equals(ThemeMode.dark),
      );

      // alwaysDay overrides disconnected / stopping state
      expect(
        resolveDayNightSkyPhase(
          isRunning: false,
          pendingTarget: null,
          mode: DayNightSkyMode.alwaysDay,
        ),
        equals(DayNightSkyPhase.day),
      );
      expect(
        resolveDayNightSkyPhase(
          isRunning: true,
          pendingTarget: false,
          mode: DayNightSkyMode.alwaysDay,
        ),
        equals(DayNightSkyPhase.day),
      );
      expect(
        resolveDayNightThemeMode(
          isRunning: false,
          pendingTarget: null,
          mode: DayNightSkyMode.alwaysDay,
        ),
        equals(ThemeMode.light),
      );
    });

    test(
        'resolveDayNightGlassAlphas yields monotonic calibrated alphas across airy, balanced, and solid presets',
        () {
      for (final isDay in [true, false]) {
        final airy = resolveDayNightGlassAlphas(
          preset: DayNightGlassPreset.airy,
          isDaySurface: isDay,
        );
        final balanced = resolveDayNightGlassAlphas(
          preset: DayNightGlassPreset.balanced,
          isDaySurface: isDay,
        );
        final solid = resolveDayNightGlassAlphas(
          preset: DayNightGlassPreset.solid,
          isDaySurface: isDay,
        );

        expect(airy.scaffoldCard, lessThan(balanced.scaffoldCard));
        expect(balanced.scaffoldCard, lessThan(solid.scaffoldCard));
        expect(airy.cardResting, lessThan(balanced.cardResting));
        expect(balanced.cardResting, lessThan(solid.cardResting));
        expect(airy.cardHover, greaterThan(airy.cardResting));
        expect(balanced.stickyHeader, lessThan(solid.stickyHeader));
        expect(airy.scaffoldCard, greaterThan(0.35));
        expect(solid.cardHover, lessThan(0.98));
      }

      // Preserve balanced baseline alphas
      final balancedDay = resolveDayNightGlassAlphas(
        preset: DayNightGlassPreset.balanced,
        isDaySurface: true,
      );
      final balancedNight = resolveDayNightGlassAlphas(
        preset: DayNightGlassPreset.balanced,
        isDaySurface: false,
      );
      expect(balancedDay.scaffoldCard, closeTo(0.66, 1e-6));
      expect(balancedDay.cardResting, closeTo(0.68, 1e-6));
      expect(balancedNight.scaffoldCard, closeTo(0.62, 1e-6));
      expect(balancedNight.cardResting, closeTo(0.64, 1e-6));
    });

    test(
        'ThemeProps JSON serialization is backward-compatible with legacy configs and round-trips new fields',
        () {
      final legacy = ThemeProps.fromJson(const {
        'themeMode': 'light',
        'pureBlack': true,
      });
      expect(legacy.themeMode, equals(ThemeMode.light));
      expect(legacy.pureBlack, isTrue);
      expect(legacy.skyMode, equals(DayNightSkyMode.followConnection));
      expect(legacy.glassPreset, equals(DayNightGlassPreset.balanced));
      expect(legacy.skyAmbientAnimation, isTrue);
      expect(legacy.ignoreCustomBackground, isFalse);

      final custom = legacy.copyWith(
        skyMode: DayNightSkyMode.alwaysNight,
        glassPreset: DayNightGlassPreset.airy,
        skyAmbientAnimation: false,
        ignoreCustomBackground: true,
      );
      final encodedJson =
          jsonDecode(jsonEncode(custom.toJson())) as Map<String, dynamic>;
      final decoded = ThemeProps.fromJson(encodedJson);
      expect(decoded.skyMode, equals(DayNightSkyMode.alwaysNight));
      expect(decoded.glassPreset, equals(DayNightGlassPreset.airy));
      expect(decoded.skyAmbientAnimation, isFalse);
      expect(decoded.ignoreCustomBackground, isTrue);
    });
  });

  group('THM-02: ThemeView Day/Night Sky Console UI and interactions', () {
    testWidgets(
        'renders live 84px sky preview, 3-mode selector, glass preset, ambient animation toggle, collapsible text scale, and removes legacy zombie controls without overflow',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = ProviderContainer(
        overrides: [
          runTimeProvider.overrideWith(_TestRunTime.new),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildLocalizedApp(
          container: container,
          viewSize: const Size(360, 820),
          home: const CommonScaffold(
            title: '主题',
            disableBackground: true,
            body: ThemeView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Obsolete controls removed from ThemeView
      expect(find.text('自动'), findsNothing);
      expect(find.text('浅色'), findsNothing);
      expect(find.text('深色'), findsNothing);
      expect(find.text('纯黑模式'), findsNothing);
      expect(find.text('New look'), findsNothing);
      expect(find.text('简洁模式'), findsNothing);

      // Module 1: 84px live mini preview + status pill + 3 modes
      final previewFinder =
          find.byKey(const ValueKey('theme-sky-live-preview-card'));
      expect(previewFinder, findsOneWidget);
      expect(tester.getSize(previewFinder).height, closeTo(84.0, 1.5));
      expect(find.text('深邃黑夜 · 代理未连接'), findsOneWidget);

      expect(
        find.byKey(const ValueKey('theme-sky-mode-followConnection')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('theme-sky-mode-alwaysNight')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('theme-sky-mode-alwaysDay')),
        findsOneWidget,
      );
      expect(find.text('随连接切换'), findsOneWidget);
      expect(find.text('常驻星夜'), findsOneWidget);
      expect(find.text('常驻晴空'), findsOneWidget);

      // Connect proxy -> preview status flips to Connected Sunny Day
      container.read(runTimeProvider.notifier).value = 3000;
      await tester.pumpAndSettle();
      expect(find.text('晴朗白天 · 代理已连接'), findsOneWidget);

      // Switch sky mode -> alwaysNight
      await tester.tap(
        find.byKey(const ValueKey('theme-sky-mode-alwaysNight')),
      );
      await tester.pumpAndSettle();
      expect(
        container.read(themeSettingProvider).skyMode,
        equals(DayNightSkyMode.alwaysNight),
      );
      expect(find.text('常驻星夜 · 已锁定暗夜天象'), findsOneWidget);

      // Switch sky mode -> alwaysDay
      await tester.tap(
        find.byKey(const ValueKey('theme-sky-mode-alwaysDay')),
      );
      await tester.pumpAndSettle();
      expect(
        container.read(themeSettingProvider).skyMode,
        equals(DayNightSkyMode.alwaysDay),
      );
      expect(find.text('常驻晴空 · 已锁定晴朗天象'), findsOneWidget);

      // Switch back to followConnection
      await tester.tap(
        find.byKey(const ValueKey('theme-sky-mode-followConnection')),
      );
      await tester.pumpAndSettle();
      expect(
        container.read(themeSettingProvider).skyMode,
        equals(DayNightSkyMode.followConnection),
      );

      // Module 2: Glass preset & Ambient animation switch
      final airyFinder = find.byKey(const ValueKey('theme-glass-preset-airy'));
      await tester.ensureVisible(airyFinder);
      await tester.pumpAndSettle();
      expect(find.text('通透'), findsOneWidget);
      expect(find.text('均衡'), findsOneWidget);
      expect(find.text('沉稳'), findsOneWidget);

      await tester.tap(airyFinder);
      await tester.pumpAndSettle();
      expect(
        container.read(themeSettingProvider).glassPreset,
        equals(DayNightGlassPreset.airy),
      );

      await tester.tap(find.byKey(const ValueKey('theme-glass-preset-solid')));
      await tester.pumpAndSettle();
      expect(
        container.read(themeSettingProvider).glassPreset,
        equals(DayNightGlassPreset.solid),
      );

      final ambientSwitch =
          find.byKey(const ValueKey('theme-sky-ambient-animation-switch'));
      await tester.ensureVisible(ambientSwitch);
      await tester.pumpAndSettle();
      expect(find.text('流云与星芒动态'), findsOneWidget);
      await tester.tap(ambientSwitch);
      await tester.pumpAndSettle();
      expect(
        container.read(themeSettingProvider).skyAmbientAnimation,
        isFalse,
      );

      // Module 3: Compact scheme button & collapsible text scale
      expect(
        find.byKey(const ValueKey('theme-scheme-variant-button')),
        findsOneWidget,
      );

      final textScaleTitle = find.text('文本缩放');
      await tester.ensureVisible(textScaleTitle);
      await tester.pumpAndSettle();
      expect(find.text('跟随系统默认 (100%)'), findsOneWidget);
      expect(find.byType(Slider), findsNothing);

      final textScaleSwitch =
          find.byKey(const ValueKey('theme-text-scale-switch'));
      await tester.tap(textScaleSwitch);
      await tester.pumpAndSettle();
      expect(
        container.read(themeSettingProvider).textScale.enable,
        isTrue,
      );
      expect(find.byType(Slider), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'displays subscription custom wallpaper banner and override switch when backgroundUrlProvider is active',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          runTimeProvider.overrideWith(_TestRunTime.new),
          backgroundUrlProvider
              .overrideWith((_) => 'https://example.com/custom-wall.jpg'),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildLocalizedApp(
          container: container,
          home: const CommonScaffold(
            title: '主题',
            disableBackground: true,
            body: ThemeView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('当前订阅附带自定义壁纸'), findsOneWidget);
      final overrideSwitch =
          find.byKey(const ValueKey('theme-ignore-custom-bg-switch'));
      expect(overrideSwitch, findsOneWidget);

      await tester.tap(overrideSwitch);
      await tester.pumpAndSettle();
      expect(
        container.read(themeSettingProvider).ignoreCustomBackground,
        isTrue,
      );
    });
  });

  group(
      'THM-03: End-to-end CommonScaffold, DayNightSkyBackground, CommonCard, and 0-fps ambient halt',
      () {
    testWidgets(
        'skyMode locks surface brightness and glassPreset drives translucent card & CommonCard alpha values',
        (tester) async {
      _resetGlobalTestState(runTime: 12000);
      final container = ProviderContainer(
        overrides: [
          runTimeProvider.overrideWith(_TestRunTime.new),
        ],
      );
      addTearDown(container.dispose);

      BuildContext? bodyCtx;
      await tester.pumpWidget(
        _buildLocalizedApp(
          container: container,
          disableAnimations: true,
          home: CommonScaffold(
            title: '天象联调',
            body: Builder(
              builder: (ctx) {
                bodyCtx = ctx;
                return Center(
                  child: CommonCard(
                    onPressed: () {},
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('通透卡片'),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // Connected default (followConnection) -> sunny day & balanced preset
      expect(
        DayNightSkyBackground.debugSnapshotOf(tester)!.phase,
        equals(DayNightSkyPhase.day),
      );
      expect(Theme.of(bodyCtx!).brightness, equals(Brightness.light));
      expect(
        DayNightSkyScope.glassPresetOf(bodyCtx!),
        equals(DayNightGlassPreset.balanced),
      );
      expect(Theme.of(bodyCtx!).cardTheme.color!.a, closeTo(0.66, 0.01));

      // Lock to alwaysNight while still connected -> Dark Night sky + dark foreground
      container.read(themeSettingProvider.notifier).updateState(
            (s) => s.copyWith(skyMode: DayNightSkyMode.alwaysNight),
          );
      await tester.pump();
      expect(
        DayNightSkyBackground.debugSnapshotOf(tester)!.phase,
        equals(DayNightSkyPhase.night),
      );
      expect(
        DayNightSkyBackground.debugSnapshotOf(tester)!.dayProgress,
        equals(0.0),
      );
      expect(Theme.of(bodyCtx!).brightness, equals(Brightness.dark));
      expect(Theme.of(bodyCtx!).cardTheme.color!.a, closeTo(0.62, 0.01));

      // Disconnect proxy, then lock to alwaysDay -> Light Sunny Day sky
      container.read(runTimeProvider.notifier).value = null;
      container.read(themeSettingProvider.notifier).updateState(
            (s) => s.copyWith(skyMode: DayNightSkyMode.alwaysDay),
          );
      await tester.pump();
      expect(
        DayNightSkyBackground.debugSnapshotOf(tester)!.phase,
        equals(DayNightSkyPhase.day),
      );
      expect(Theme.of(bodyCtx!).brightness, equals(Brightness.light));

      // Change glassPreset -> airy then solid
      container.read(themeSettingProvider.notifier).updateState(
            (s) => s.copyWith(glassPreset: DayNightGlassPreset.airy),
          );
      await tester.pump();
      expect(Theme.of(bodyCtx!).cardTheme.color!.a, closeTo(0.48, 0.01));

      container.read(themeSettingProvider.notifier).updateState(
            (s) => s.copyWith(glassPreset: DayNightGlassPreset.solid),
          );
      await tester.pump();
      expect(Theme.of(bodyCtx!).cardTheme.color!.a, closeTo(0.86, 0.01));
    });

    testWidgets(
        'skyAmbientAnimation=false animates sunrise transition smoothly then halts ticker at 0 fps once settled',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          runTimeProvider.overrideWith(_TestRunTime.new),
        ],
      );
      addTearDown(container.dispose);

      container.read(themeSettingProvider.notifier).updateState(
            (s) => s.copyWith(skyAmbientAnimation: false),
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery(
              data: MediaQueryData(size: Size(420, 300)),
              child: DayNightSkyBackground(
                continuousAnimationInTests: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 32));

      // Settled at Night with ambient=false -> ticker halted at 0 fps
      expect(
        DayNightSkyBackground.debugSnapshotOf(tester)!.isTickerActive,
        isFalse,
      );

      // Connect proxy -> transition MUST animate even with ambient=false
      container.read(runTimeProvider.notifier).value = 5000;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final mid = DayNightSkyBackground.debugSnapshotOf(tester)!;
      expect(mid.isTickerActive, isTrue);
      expect(mid.dayProgress, greaterThan(0.05));
      expect(mid.dayProgress, lessThan(1.0));

      // Finish transition -> ticker automatically stops again
      await tester.pumpAndSettle();
      final settled = DayNightSkyBackground.debugSnapshotOf(tester)!;
      expect(settled.dayProgress, equals(1.0));
      expect(settled.isTickerActive, isFalse);

      // Re-enable ambient animation -> ticker starts steady loop
      container.read(themeSettingProvider.notifier).updateState(
            (s) => s.copyWith(skyAmbientAnimation: true),
          );
      await tester.pump();
      expect(
        DayNightSkyBackground.debugSnapshotOf(tester)!.isTickerActive,
        isTrue,
      );
    });
  });

  group('THM-04: DashboardView concise mode highlighted toggle capsule', () {
    testWidgets(
        'shows unhighlighted 简洁模式 button in classic grid, highlights when toggled to HeroConnect, and hides during grid edit mode',
        (tester) async {
      final semanticsHandle = tester.ensureSemantics();
      try {
        await tester.binding.setSurfaceSize(const Size(1040, 820));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final profile = Profile(
          id: 'p1',
          label: 'Test',
          url: 'https://example.com/sub',
          autoUpdateDuration: const Duration(days: 1),
          lastUpdateDate: DateTime(2026, 11, 1),
        );
        _resetGlobalTestState(
          profiles: [profile],
          currentProfileId: 'p1',
          appSetting: const AppSettingProps(newDashboard: false),
          pageLabel: PageLabel.dashboard,
        );

        final container = ProviderContainer(
          overrides: [
            runTimeProvider.overrideWith(_TestRunTime.new),
            tunRuntimeProvider.overrideWith((_) => TunRuntimeController()),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          _buildLocalizedApp(
            container: container,
            viewSize: const Size(1040, 820),
            home: const CommonScaffold(
              title: '仪表盘',
              body: DashboardView(),
            ),
          ),
        );
        await tester.pump();
        await tester.pumpAndSettle();

        final toggleFinder =
            find.byKey(const ValueKey('dashboard-concise-mode-toggle'));
        expect(toggleFinder, findsOneWidget);
        expect(find.text('简洁模式'), findsOneWidget);

        // Initial state: newDashboard == false -> unhighlighted + classic StartButton
        expect(find.byType(StartButton), findsOneWidget);
        expect(find.byType(HeroConnect), findsNothing);
        final initialPill =
            tester.widget<ConciseDashboardModePill>(
                find.byType(ConciseDashboardModePill));
        expect(initialPill.isHighlighted, isFalse);
        final initialSem = tester.getSemantics(toggleFinder);
        expect(initialSem.flagsCollection.isToggled, equals(ui.Tristate.isFalse));

        // Tap 简洁模式 -> highlighted + HeroConnect shown
        await tester.tap(toggleFinder);
        await tester.pump();
        await tester.pumpAndSettle();

        expect(
          container.read(appSettingProvider).newDashboard,
          isTrue,
        );
        expect(find.byType(HeroConnect), findsOneWidget);
        final activePill =
            tester.widget<ConciseDashboardModePill>(
                find.byType(ConciseDashboardModePill));
        expect(activePill.isHighlighted, isTrue);
        final activeSem = tester.getSemantics(toggleFinder);
        expect(activeSem.flagsCollection.isToggled, equals(ui.Tristate.isTrue));

        // Tap again -> returns to classic grid & unhighlighted
        await tester.tap(toggleFinder);
        await tester.pump();
        await tester.pumpAndSettle();
        expect(
          container.read(appSettingProvider).newDashboard,
          isFalse,
        );
        expect(find.byType(HeroConnect), findsNothing);
        expect(find.byType(StartButton), findsOneWidget);
        expect(
          tester
              .widget<ConciseDashboardModePill>(
                  find.byType(ConciseDashboardModePill))
              .isHighlighted,
          isFalse,
        );

        // Enter classic grid edit mode -> hides 简洁模式 button, save restores it
        await tester.tap(find.byIcon(Icons.edit));
        await tester.pump();
        expect(toggleFinder, findsNothing);

        await tester.tap(find.byIcon(Icons.save));
        await tester.pump();
        await tester.pumpAndSettle();
        expect(toggleFinder, findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        semanticsHandle.dispose();
      }
    });
  });

  group('THM-05: Mainland China localization & HeroConnect Russian removal',
      () {
    test('zh_CN AppLocalizations translates all previously missing UI keys',
        () async {
      final zh = await AppLocalizations.load(const Locale('zh', 'CN'));
      expect(zh.newDashboard, equals('简洁模式'));
      expect(zh.themeDesc, equals('昼夜天象联动、玻璃通透度与点缀色'));
      expect(zh.runtimeConfig, equals('运行配置'));
      expect(zh.runtimeConfigNotAvailable, equals('暂无运行配置'));
      expect(zh.restartCore, equals('重启核心'));
      expect(zh.coreStatusRunning, equals('运行中'));
      expect(zh.coreStatusRestarting, equals('正在重启'));
      expect(zh.coreStatusStopped, equals('已停止'));
      expect(zh.coreUpdate, equals('内核更新'));
      expect(zh.goToSelected, equals('定位到已选'));
      expect(zh.testAllDelay, equals('一键测速'));
      expect(zh.collapseAll, equals('全部收起'));
      expect(zh.expandAll, equals('全部展开'));
      expect(zh.addProfile, equals('添加配置'));
      expect(zh.selectProfile, equals('选择配置'));
      expect(zh.subscriptionUnlimited, equals('永久有效'));
      expect(zh.remaining, equals('剩余'));
      expect(zh.renewSubscription, equals('续费订阅'));
      expect(zh.buyExtraTraffic, equals('增购流量'));
    });

    testWidgets(
        'HeroConnect buy/renew buttons render Chinese labels instead of hardcoded Russian',
        (tester) async {
      final expiringSoonSec = DateTime.now()
              .add(const Duration(days: 1))
              .millisecondsSinceEpoch ~/
          1000;
      final profile = Profile(
        id: 'p_buy',
        label: '自由云节点',
        url: 'https://example.com/sub',
        autoUpdateDuration: const Duration(days: 1),
        lastUpdateDate: DateTime(2026, 11, 1),
        subscriptionInfo: SubscriptionInfo(
          upload: 950 * 1024 * 1024,
          download: 0,
          total: 1000 * 1024 * 1024,
          expire: expiringSoonSec,
        ),
        providerHeaders: const {
          'flclashx-buyplan': 'https://example.com/buy-plan',
          'flclashx-buytraffic': 'https://example.com/buy-traffic',
        },
      );
      _resetGlobalTestState(
        profiles: [profile],
        currentProfileId: 'p_buy',
        appSetting: const AppSettingProps(newDashboard: true),
      );

      final container = ProviderContainer(
        overrides: [
          runTimeProvider.overrideWith(_TestRunTime.new),
          tunRuntimeProvider.overrideWith((_) => TunRuntimeController()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildLocalizedApp(
          container: container,
          home: const CommonScaffold(
            title: '仪表盘',
            body: DashboardView(),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('续费订阅'), findsOneWidget);
      expect(find.text('增购流量'), findsOneWidget);
      expect(find.text('Продлить подписку'), findsNothing);
      expect(find.text('Докупить трафик'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('CR-THM: Code review remediations (P2-1..P2-3 & P3-1)', () {
    testWidgets(
        'CR-THM-01 (P2-1): ConciseDashboardModeButton exposes semantic tap action and toggles via semantics',
        (tester) async {
      final semanticsHandle = tester.ensureSemantics();
      try {
        await tester.binding.setSurfaceSize(const Size(1040, 820));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final profile = Profile(
          id: 'p_sem',
          label: 'Test',
          url: 'https://example.com/sub',
          autoUpdateDuration: const Duration(days: 1),
          lastUpdateDate: DateTime(2026, 11, 1),
        );
        _resetGlobalTestState(
          profiles: [profile],
          currentProfileId: 'p_sem',
          appSetting: const AppSettingProps(newDashboard: false),
          pageLabel: PageLabel.dashboard,
        );

        final container = ProviderContainer(
          overrides: [
            runTimeProvider.overrideWith(_TestRunTime.new),
            tunRuntimeProvider.overrideWith((_) => TunRuntimeController()),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          _buildLocalizedApp(
            container: container,
            viewSize: const Size(1040, 820),
            home: const CommonScaffold(
              title: '仪表盘',
              body: DashboardView(),
            ),
          ),
        );
        await tester.pump();
        await tester.pumpAndSettle();

        final toggleFinder =
            find.byKey(const ValueKey('dashboard-concise-mode-toggle'));
        expect(toggleFinder, findsOneWidget);

        final initialNode = tester.getSemantics(toggleFinder);
        expect(
          initialNode.getSemanticsData().hasAction(ui.SemanticsAction.tap),
          isTrue,
        );
        expect(
          initialNode.flagsCollection.isToggled,
          equals(ui.Tristate.isFalse),
        );

        initialNode.owner!.performAction(
          initialNode.id,
          ui.SemanticsAction.tap,
        );
        await tester.pumpAndSettle();

        expect(container.read(appSettingProvider).newDashboard, isTrue);
        expect(
          tester.getSemantics(toggleFinder).flagsCollection.isToggled,
          equals(ui.Tristate.isTrue),
        );
        expect(find.byType(HeroConnect), findsOneWidget);
      } finally {
        semanticsHandle.dispose();
      }
    });

    testWidgets(
        'CR-THM-02 (P2-2): custom wallpaper follows skyMode brightness cleanly and disables sky glass/ambient controls until overridden',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      _resetGlobalTestState(
        runTime: null,
        themeProps: defaultThemeProps.copyWith(
          themeMode: ThemeMode.light,
          skyMode: DayNightSkyMode.followConnection,
          ignoreCustomBackground: false,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          runTimeProvider.overrideWith(_TestRunTime.new),
          backgroundUrlProvider
              .overrideWith((_) => 'https://example.com/custom-wall.jpg'),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildLocalizedApp(
          container: container,
          viewSize: const Size(400, 900),
          home: const CommonScaffold(
            title: '主题',
            disableBackground: true,
            body: ThemeView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Legacy themeMode=light must NOT freeze brightness under skyMode=followConnection
      final themeViewCtx = tester.element(find.byType(ThemeView));
      expect(Theme.of(themeViewCtx).brightness, equals(Brightness.dark));
      expect(find.text('订阅壁纸生效中 · 同步界面明暗'), findsOneWidget);

      final hintFinder =
          find.byKey(const ValueKey('theme-atmosphere-custom-bg-hint'));
      expect(hintFinder, findsOneWidget);

      // While custom wallpaper is active, skyMode still drives MaterialApp brightness
      await tester.tap(find.byKey(const ValueKey('theme-sky-mode-alwaysDay')));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(ThemeView))).brightness,
        equals(Brightness.light),
      );

      // Atmosphere preset taps are ignored while custom wallpaper covers sky canvas
      final airyFinder = find.byKey(const ValueKey('theme-glass-preset-airy'));
      await tester.ensureVisible(airyFinder);
      await tester.pumpAndSettle();
      await tester.tap(airyFinder, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(
        container.read(themeSettingProvider).glassPreset,
        equals(DayNightGlassPreset.balanced),
      );

      // Enable override -> custom bg hint disappears and glass preset becomes interactive
      final overrideSwitch =
          find.byKey(const ValueKey('theme-ignore-custom-bg-switch'));
      await tester.ensureVisible(overrideSwitch);
      await tester.pumpAndSettle();
      await tester.tap(overrideSwitch);
      await tester.pumpAndSettle();

      expect(container.read(themeSettingProvider).ignoreCustomBackground, isTrue);
      expect(hintFinder, findsNothing);
      expect(find.text('常驻晴空 · 已锁定晴朗天象'), findsOneWidget);

      await tester.ensureVisible(airyFinder);
      await tester.pumpAndSettle();
      await tester.tap(airyFinder);
      await tester.pumpAndSettle();
      expect(
        container.read(themeSettingProvider).glassPreset,
        equals(DayNightGlassPreset.airy),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'CR-THM-03 (P2-3): ReceiveProfileDialog and embedded portal HTML localize cleanly and lib/ has zero hardcoded Cyrillic literals',
        (tester) async {
      final syncController = _AddSyncTestController();
      globalState.appController = syncController;

      final zh = await AppLocalizations.load(const Locale('zh', 'CN'));
      final zhHtml =
          ReceiveProfileDialog.buildReceiveProfilePortalHtml(zh, htmlLang: 'zh-CN');
      expect(zhHtml, contains('导入订阅配置'));
      expect(zhHtml, contains('粘贴'));
      expect(zhHtml, contains('发送'));
      expect(RegExp(r'[\u0400-\u04FF]').hasMatch(zhHtml), isFalse);

      // Verify no hardcoded Cyrillic UI strings remain anywhere under lib/
      final cyrillicRe = RegExp(r'[\u0400-\u04FF]');
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final normalized = entity.path.replaceAll(r'\', '/');
        if (normalized.endsWith('/messages_ru.dart')) continue;
        final nonCommentLines = entity
            .readAsLinesSync()
            .where((line) => !line.trimLeft().startsWith('//'));
        for (final line in nonCommentLines) {
          expect(
            cyrillicRe.hasMatch(line),
            isFalse,
            reason: 'Unexpected Cyrillic literal in $normalized: $line',
          );
        }
      }

      final container = ProviderContainer();
      addTearDown(container.dispose);

      Uri? listeningUri;
      await tester.pumpWidget(
        _buildLocalizedApp(
          container: container,
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    unawaited(
                      showDialog<void>(
                        context: ctx,
                        builder: (_) => ReceiveProfileDialog(
                          resolveWifiIp: () async => '127.0.0.1',
                          syncPort: 0,
                          onServerReady: (uri) => listeningUri = uri,
                        ),
                      ),
                    );
                  },
                  child: const Text('open-sync'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open-sync'));
      await tester.pump();

      for (var i = 0; i < 200 && listeningUri == null; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 15)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(listeningUri, isNotNull);
      expect(find.text('请使用手机相机扫描二维码'), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      final baseUri = listeningUri!;
      expect(baseUri.host, equals('127.0.0.1'));
      expect(baseUri.port, greaterThan(0));

      Future<T> pumpRealIo<T>(Future<T> Function() action) async {
        T? result;
        Object? caughtError;
        StackTrace? caughtStack;
        var done = false;
        Zone.root.run(() {
          unawaited(
            HttpOverrides.runWithHttpOverrides(action, _DirectHttpOverrides())
                .then(
              (value) {
                result = value;
                done = true;
              },
              onError: (Object error, StackTrace stack) {
                caughtError = error;
                caughtStack = stack;
                done = true;
              },
            ),
          );
        });
        for (var i = 0; i < 300 && !done; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 15)),
          );
          await tester.pump();
        }
        if (!done) {
          throw TimeoutException(
            'Loopback HTTP I/O did not finish within 4.5s',
          );
        }
        if (caughtError != null) {
          Error.throwWithStackTrace(caughtError!, caughtStack!);
        }
        return result as T;
      }

      final ioResult = await pumpRealIo(() async {
        final client = HttpClient();
        try {
          final getReq = await client.getUrl(baseUri);
          final getResp = await getReq.close();
          final htmlBody = await utf8.decodeStream(getResp);

          final postReq = await client.postUrl(baseUri.resolve('/add-profile'));
          postReq.headers.contentType = ContentType.json;
          postReq.write(jsonEncode({'url': 'https://example.com/sub.yaml'}));
          final postResp = await postReq.close();
          await utf8.decodeStream(postResp);
          return (
            getStatusCode: getResp.statusCode,
            htmlBody: htmlBody,
            postStatusCode: postResp.statusCode,
          );
        } finally {
          client.close(force: true);
        }
      });

      expect(ioResult.getStatusCode, equals(HttpStatus.ok));
      expect(ioResult.htmlBody, contains('导入订阅配置'));
      expect(cyrillicRe.hasMatch(ioResult.htmlBody), isFalse);
      expect(ioResult.postStatusCode, equals(HttpStatus.ok));

      await tester.pump();
      expect(syncController.syncedUrl, equals('https://example.com/sub.yaml'));
      expect(find.text('配置添加成功'), findsOneWidget);

      // Flush the 1600ms auto-close timer cleanly and confirm dialog closes
      await tester.pump(const Duration(milliseconds: 1700));
      await tester.pumpAndSettle();
      expect(find.byType(ReceiveProfileDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'CR-THM-04 (P3-1): sky/glass controls expose selected semantics and accent reset restores defaultThemeProps.schemeVariant',
        (tester) async {
      final semanticsHandle = tester.ensureSemantics();
      try {
        await tester.binding.setSurfaceSize(const Size(400, 920));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final container = ProviderContainer(
          overrides: [
            runTimeProvider.overrideWith(_TestRunTime.new),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          _buildLocalizedApp(
            container: container,
            attachGlobalNavigatorKey: true,
            viewSize: const Size(400, 920),
            home: const CommonScaffold(
              title: '主题',
              disableBackground: true,
              body: ThemeView(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final followNode = tester.getSemantics(
          find.byKey(const ValueKey('theme-sky-mode-followConnection')),
        );
        final nightNode = tester.getSemantics(
          find.byKey(const ValueKey('theme-sky-mode-alwaysNight')),
        );
        final balancedGlassNode = tester.getSemantics(
          find.byKey(const ValueKey('theme-glass-preset-balanced')),
        );
        expect(followNode.flagsCollection.isSelected, equals(ui.Tristate.isTrue));
        expect(
          followNode.getSemanticsData().hasAction(ui.SemanticsAction.tap),
          isTrue,
        );
        expect(nightNode.flagsCollection.isSelected, equals(ui.Tristate.isFalse));
        expect(
          balancedGlassNode.flagsCollection.isSelected,
          equals(ui.Tristate.isTrue),
        );

        final resetFinder =
            find.byKey(const ValueKey('theme-accent-reset-button'));
        expect(resetFinder, findsNothing);

        // Changing only schemeVariant should reveal the reset button
        container.read(themeSettingProvider.notifier).updateState(
              (s) => s.copyWith(schemeVariant: DynamicSchemeVariant.tonalSpot),
            );
        await tester.pumpAndSettle();
        await tester.ensureVisible(resetFinder);
        await tester.pumpAndSettle();
        expect(resetFinder, findsOneWidget);

        await tester.tap(resetFinder);
        await tester.pumpAndSettle();
        await tester.tap(find.text('确定'));
        await tester.pumpAndSettle();

        expect(
          container.read(themeSettingProvider).schemeVariant,
          equals(defaultThemeProps.schemeVariant),
        );
        expect(resetFinder, findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        semanticsHandle.dispose();
      }
    });
  });
}

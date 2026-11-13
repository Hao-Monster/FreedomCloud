import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flclashx/clash/clash.dart';
import 'package:flclashx/clash/interface.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/delay_test_coordinator.dart';
import 'package:flclashx/common/node_catalog_tester.dart';
import 'package:flclashx/common/theme.dart';
import 'package:flclashx/controller.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/pages/home.dart';
import 'package:flclashx/plugins/vpn.dart';
import 'package:flclashx/providers/node_overview.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/views/about.dart';
import 'package:flclashx/views/dashboard/widgets/hero_connect.dart';
import 'package:flclashx/views/dashboard/widgets/hero_nav_bar.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _NoopClashHandler extends Fake implements ClashHandlerInterface {
  @override
  FutureOr<String> getCoreVersion() => 'v1.19.32';
}

class _NoopCatalogTester extends ChangeNotifier implements NodeCatalogTester {
  @override
  bool busy = false;
  @override
  int total = 0;
  @override
  int completed = 0;

  @override
  bool pending(String profileId, String identityKey) => false;

  @override
  Set<String> pendingIdentitySnapshot(String profileId) => const <String>{};

  @override
  Future<DelayBatchResult> testAll(List<Profile> profiles, String url) async =>
      const DelayBatchResult(completed: 1, failed: 0);

  @override
  void disposeScope() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAppController extends Fake implements AppController {
  _FakeAppController(this.ref);

  final WidgetRef ref;

  @override
  void toPage(PageLabel pageLabel) {
    ref.read(currentPageLabelProvider.notifier).value = pageLabel;
  }

  @override
  void updateCurrentSelectedMap(String groupName, String proxyName) {}

  @override
  void changeProxyDebounce(String groupName, String proxyName) {}

  @override
  void updateCurrentGroupName(String groupName) {}

  @override
  void backBlock() {}

  @override
  void unBackBlock() {}

  @override
  Future<void> updateStatus(bool isStart) async {}
}

class _ControllerHost extends ConsumerStatefulWidget {
  const _ControllerHost({required this.child});

  final Widget child;

  @override
  ConsumerState<_ControllerHost> createState() => _ControllerHostState();
}

class _ControllerHostState extends ConsumerState<_ControllerHost> {
  @override
  void initState() {
    super.initState();
    globalState.appController = _FakeAppController(ref);
  }

  @override
  Widget build(BuildContext context) {
    globalState.measure = Measure.of(context, 1.0);
    globalState.theme = CommonTheme.of(context, 1.0);
    return widget.child;
  }
}

Widget _buildTestApp({
  Key? key,
  required Widget home,
  Locale locale = const Locale('zh', 'CN'),
  Brightness brightness = Brightness.dark,
  List<Override> overrides = const [],
}) =>
    ProviderScope(
      key: key ?? ValueKey('${locale.toLanguageTag()}-$brightness'),
      overrides: overrides,
      child: Consumer(
        builder: (context, ref, _) {
          final scheme = ref.watch(genColorSchemeProvider(brightness));
          return MaterialApp(
            locale: locale,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.delegate.supportedLocales,
            theme: buildFreedomNetThemeData(colorScheme: scheme),
            home: _ControllerHost(child: home),
          );
        },
      ),
    );

AppState _makeAppState({
  Size viewSize = const Size(1200, 820),
}) =>
    AppState(
      pageLabel: PageLabel.proxies,
      viewSize: viewSize,
      version: 1,
      requests: FixedList(maxLength),
      logs: FixedList(maxLength),
      traffics: FixedList(30),
      totalTraffic: Traffic(),
      isInit: true,
    );

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const trayChannel = MethodChannel('tray_manager');

  setUp(() async {
    await AppLocalizations.load(const Locale('zh', 'CN'));
    ClashCore.instanceForTesting = ClashCore.forTesting(_NoopClashHandler());
    globalState.packageInfo = PackageInfo(
      appName: 'FlClashX',
      packageName: 'com.follow.clashx',
      version: '1.0.0',
      buildNumber: '1',
    );
    globalState.coreVersion = 'v1.19.32';
    globalState.config = const Config(themeProps: defaultThemeProps);
    globalState.appState = _makeAppState();
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(trayChannel, null);
    ClashCore.instanceForTesting = null;
  });

  testWidgets(
      'CR-01: CommonScaffold preserves FreedomNet AppBarTheme (elevation 0, scrolledUnderElevation 0, w700 title) and uses Obsidian Slate tokens in search mode',
      (tester) async {
    final scaffoldKey = GlobalKey<CommonScaffoldState>();
    await tester.pumpWidget(
      _buildTestApp(
        home: CommonScaffold(
          key: scaffoldKey,
          title: '代理',
          body: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final appBarContext = tester.element(find.byType(AppBar));
    final appBarTheme = Theme.of(appBarContext).appBarTheme;
    expect(appBarTheme.elevation, equals(0));
    expect(appBarTheme.scrolledUnderElevation, equals(0));
    expect(appBarTheme.surfaceTintColor, equals(Colors.transparent));
    expect(appBarTheme.titleTextStyle?.fontWeight, equals(FontWeight.w700));

    scaffoldKey.currentState!.updateSearchState(
      (_) => AppBarSearchState(
        onSearch: (_) {},
        isSearch: true,
      ),
    );
    await tester.pumpAndSettle();

    final searchAppBarContext = tester.element(find.byType(AppBar));
    final searchAppBarTheme = Theme.of(searchAppBarContext).appBarTheme;
    expect(searchAppBarTheme.backgroundColor, equals(kFreedomNetDarkCard));
    expect(
      searchAppBarTheme.iconTheme?.color,
      equals(const Color(0xFF94A3B8)),
    );
  });

  test(
      'CR-02: Config.compatibleFromJson migrates uncustomized legacy themeProps once to Flagship Obsidian Slate while preserving explicit user customizations',
      () {
    expect(const ThemeProps().themeMode, equals(ThemeMode.dark));

    // 1. Legacy upgrade config with persisted old defaults (0xFF03A9F4 + system)
    final legacyDefaultJson = <String, Object?>{
      'themeProps': <String, Object?>{
        'primaryColor': 0xFF03A9F4,
        'primaryColors': <int>[
          0xFF795548,
          0xFF03A9F4,
          0xFFFFFF00,
          0xFFBBC9CC,
          0xFFABD397,
        ],
        'themeMode': 'system',
      },
    };
    final migratedDefault = Config.compatibleFromJson(
      legacyDefaultJson,
      isDesktop: true,
    );
    expect(migratedDefault.themeProps.primaryColor, equals(defaultPrimaryColor));
    expect(migratedDefault.themeProps.themeMode, equals(ThemeMode.dark));
    expect(
      migratedDefault.themeProps.primaryColors,
      contains(defaultPrimaryColor),
    );
    expect(migratedDefault.themeProps.freedomNetThemeV1Migrated, isTrue);
    expect(
      migratedDefault.themeProps.toJson()['freedomNetThemeV1Migrated'],
      isTrue,
    );

    // 1b. Legacy upgrade config with null primaryColor + system mode
    final legacyNullColorJson = <String, Object?>{
      'themeProps': <String, Object?>{
        'primaryColor': null,
        'themeMode': 'system',
      },
    };
    final migratedNullColor = Config.compatibleFromJson(
      legacyNullColorJson,
      isDesktop: true,
    );
    expect(
      migratedNullColor.themeProps.primaryColor,
      equals(defaultPrimaryColor),
    );
    expect(migratedNullColor.themeProps.themeMode, equals(ThemeMode.dark));
    expect(migratedNullColor.themeProps.freedomNetThemeV1Migrated, isTrue);

    // 2. Legacy upgrade config where user previously had green swatch + pureBlack + tonalSpot
    // (even if freedomNetThemeV1Migrated was already true): V2 one-shot migration resets once
    // to Flagship Plan A (Obsidian Slate + Electric Cyan + dark + pureBlack:false + content).
    final legacyCustomizedJson = <String, Object?>{
      'themeProps': <String, Object?>{
        'primaryColor': 0xFFC9E7CA,
        'primaryColors': <int>[0xFFC9E7CA, 0xFF03A9F4],
        'themeMode': 'dark',
        'freedomNetThemeV1Migrated': true,
        'schemeVariant': 'tonalSpot',
        'pureBlack': true,
      },
    };
    final migratedCustom = Config.compatibleFromJson(
      legacyCustomizedJson,
      isDesktop: true,
    );
    expect(migratedCustom.themeProps.primaryColor, equals(defaultPrimaryColor));
    expect(migratedCustom.themeProps.themeMode, equals(ThemeMode.dark));
    expect(migratedCustom.themeProps.pureBlack, isFalse);
    expect(
      migratedCustom.themeProps.schemeVariant,
      equals(DynamicSchemeVariant.content),
    );
    expect(
      migratedCustom.themeProps.primaryColors.first,
      equals(defaultPrimaryColor),
    );
    expect(
      migratedCustom.themeProps.toJson()['freedomNetThemeV2Migrated'],
      isTrue,
    );

    // 3. Post-V2 migration idempotency: if user later customizes light/system + pureBlack + color,
    // compatibleFromJson must NOT overwrite their choice again.
    final userReverted = migratedCustom.copyWith(
      themeProps: migratedCustom.themeProps.copyWith(
        primaryColor: 0xFF795548,
        themeMode: ThemeMode.light,
        pureBlack: true,
        schemeVariant: DynamicSchemeVariant.tonalSpot,
      ),
    );
    final reloaded = Config.compatibleFromJson(
      jsonDecode(jsonEncode(userReverted)) as Map<String, Object?>,
      isDesktop: true,
    );
    expect(reloaded.themeProps.primaryColor, equals(0xFF795548));
    expect(reloaded.themeProps.themeMode, equals(ThemeMode.light));
    expect(reloaded.themeProps.pureBlack, isTrue);
    expect(
      reloaded.themeProps.schemeVariant,
      equals(DynamicSchemeVariant.tonalSpot),
    );
  });

  testWidgets(
      'CR-03: Residual FlClashX brand leaks eliminated across Windows traffic tray tooltip, EmptyHero, VPN fallback, TV QR landing HTML, and Win32 window title',
      (tester) async {
    // 1. Dynamic Windows tray traffic tooltip must use appBrandName
    final calls = <MethodCall>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      trayChannel,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    await tester.runAsync(
      () => Tray().updateTrayTitle(Traffic(up: 2048, down: 4096)),
    );
    if (Platform.isWindows) {
      expect(calls, hasLength(1));
      final toolTip = (calls.single.arguments as Map)['toolTip'] as String;
      expect(toolTip, startsWith('${appLocalizations.appBrandName} · '));
      expect(toolTip, isNot(contains('FlClashX')));
    }

    // 2. Dashboard EmptyHero (0 profiles) must render localized FreedomNet brand
    await tester.pumpWidget(
      _buildTestApp(
        locale: const Locale('zh', 'CN'),
        home: const Scaffold(body: Center(child: HeroConnect())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FreedomNetBrandMark), findsOneWidget);
    expect(find.text('自由云'), findsOneWidget);
    expect(find.text('FlClashX'), findsNothing);

    // 3. VPN notification fallback & static HTML/C++ brand titles
    expect(Vpn().cachedProfileName, equals(brandNameEn));

    final mainDart = File('lib/main.dart').readAsStringSync();
    expect(
      mainDart,
      isNot(contains("if (profile == null) return 'FlClashX';")),
    );

    final receiveDialogDart =
        File('lib/views/profiles/receive_profile_dialog.dart')
            .readAsStringSync();
    expect(
      receiveDialogDart,
      isNot(contains('<title>FlClashX')),
    );
    expect(receiveDialogDart, contains('<title>FreedomNet'));

    final winMainCpp = File('windows/runner/main.cpp').readAsStringSync();
    expect(winMainCpp, isNot(contains('window.Create(L"FlClashX"')));
  });

  testWidgets(
      'CR-04: Narrow/mobile viewport (<=600px) in Novice Mode exposes brand-tribute-trigger without duplicating keys on desktop',
      (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    globalState.appState = _makeAppState(viewSize: const Size(390, 800));

    await tester.pumpWidget(
      _buildTestApp(
        overrides: [
          coldStartZeroProfilePromptedProvider.overrideWith((_) => true),
          nodeCatalogTesterProvider.overrideWith((_) => _NoopCatalogTester()),
        ],
        home: const HomePage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsNothing);
    final mobileTrigger = find.byKey(const ValueKey('brand-tribute-trigger'));
    expect(mobileTrigger, findsOneWidget);

    await tester.tap(mobileTrigger);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('freedomnet-tribute-dialog')),
      findsOneWidget,
    );
    expect(find.textContaining('FlClashX'), findsWidgets);
    expect(find.textContaining('Gemini 4'), findsWidgets);

    await tester.tap(
      find.byKey(const ValueKey('freedomnet-tribute-dialog-close')),
    );
    await tester.pumpAndSettle();

    // Verify desktop layout still renders exactly ONE brand-tribute-trigger
    tester.view.physicalSize = const Size(1200, 820);
    globalState.appState = _makeAppState(viewSize: const Size(1200, 820));
    await tester.pumpWidget(
      _buildTestApp(
        key: const ValueKey('desktop-recheck'),
        overrides: [
          coldStartZeroProfilePromptedProvider.overrideWith((_) => true),
          nodeCatalogTesterProvider.overrideWith((_) => _NoopCatalogTester()),
        ],
        home: const HomePage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(
      find.byKey(const ValueKey('brand-tribute-trigger')),
      findsOneWidget,
    );
  });

  testWidgets(
      'CR-05: toPureBlack(true) preserves non-inverted optical depth and mobile bottom bars align with FreedomNet recessed/hairline styling',
      (tester) async {
    final baseDark = calibrateFreedomNetColorScheme(
      ColorScheme.fromSeed(
        seedColor: const Color(defaultPrimaryColor),
        brightness: Brightness.dark,
      ),
      seedColor: const Color(defaultPrimaryColor),
    );
    final pure = baseDark.toPureBlack(true);
    expect(pure.surface, equals(Colors.black));
    expect(pure.surfaceDim, equals(Colors.black));
    expect(
      pure.surfaceDim.computeLuminance() <= pure.surface.computeLuminance(),
      isTrue,
      reason: 'Recessed surfaceDim must never be brighter than pureBlack canvas',
    );
    expect(
      pure.surface.computeLuminance() < pure.surfaceContainer.computeLuminance(),
      isTrue,
    );
    expect(
      pure.surfaceContainer.computeLuminance() <
          pure.surfaceContainerHigh.computeLuminance(),
      isTrue,
    );
    expect(pure.surfaceContainer.b >= pure.surfaceContainer.g, isTrue);

    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    globalState.config = const Config(
      themeProps: defaultThemeProps,
      profiles: [
        Profile(
          id: 'p1',
          label: '自由云订阅',
          url: 'https://example.invalid/sub',
          autoUpdateDuration: defaultUpdateDuration,
        ),
      ],
    );
    globalState.appState = _makeAppState(viewSize: const Size(390, 800));

    await tester.pumpWidget(
      _buildTestApp(
        home: Consumer(
          builder: (context, ref, _) {
            final items = ref.watch(currentNavigationsStateProvider).value;
            return Scaffold(
              body: const HeroNavBar(),
              bottomNavigationBar: CommonNavigationBar(
                viewMode: ViewMode.mobile,
                navigationItems: items,
                currentIndex: 0,
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final navBarContext = tester.element(find.byType(NavigationBar));
    final navBarTheme = NavigationBarTheme.of(navBarContext);
    expect(navBarTheme.elevation, equals(0));
    expect(navBarTheme.backgroundColor, equals(kFreedomNetDarkRecessed));

    final heroBarContainers = tester.widgetList<Container>(
      find.descendant(
        of: find.byType(HeroNavBar),
        matching: find.byType(Container),
      ),
    );
    final outerPill = heroBarContainers.firstWhere(
      (c) =>
          c.decoration is BoxDecoration &&
          (c.decoration! as BoxDecoration).borderRadius ==
              BorderRadius.circular(29),
    );
    expect((outerPill.decoration! as BoxDecoration).border, isNotNull);
  });

  testWidgets(
      'CR-06: Accessibility semantics & contrast — brand-tribute-trigger announces button semantics and AboutView Avatar supports keyboard InkWell focus + high-contrast initials',
      (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    try {
      tester.view.physicalSize = const Size(1200, 820);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          locale: const Locale('zh', 'CN'),
          home: Consumer(
            builder: (context, ref, _) {
              final items = ref.watch(currentNavigationsStateProvider).value;
              return CommonScaffold(
                title: '代理',
                sideNavigationBar: CommonNavigationBar(
                  viewMode: ViewMode.desktop,
                  navigationItems: items,
                  currentIndex: 0,
                ),
                body: const SizedBox.expand(),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final triggerFinder = find.byKey(const ValueKey('brand-tribute-trigger'));
      expect(
        tester.getSemantics(triggerFinder),
        matchesSemantics(
          isButton: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
          label: '自由云 · 开源致敬与特别鸣谢',
        ),
      );

      await tester.pumpWidget(
        _buildTestApp(
          brightness: Brightness.light,
          home: const Scaffold(
            body: Center(
              child: Avatar(
                contributor: Contributor(
                  name: 'alice',
                  link: 'https://github.com/alice',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(Avatar),
          matching: find.byType(InkWell),
        ),
        findsOneWidget,
      );
      final initialText = tester.widget<Text>(find.text('A'));
      expect(initialText.style?.color, equals(const Color(0xFF075985)));
    } finally {
      semanticsHandle.dispose();
    }
  });
}

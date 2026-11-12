import 'dart:async';

import 'package:flclashx/clash/clash.dart';
import 'package:flclashx/clash/interface.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/delay_test_coordinator.dart';
import 'package:flclashx/common/node_catalog_tester.dart';
import 'package:flclashx/common/node_health_store.dart';
import 'package:flclashx/common/theme.dart';
import 'package:flclashx/controller.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/models/node_catalog.dart';
import 'package:flclashx/pages/home.dart';
import 'package:flclashx/providers/node_overview.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/views/about.dart';
import 'package:flclashx/views/proxies/proxies.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/material.dart';
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

Widget _buildNavigationBarShell({Widget body = const SizedBox()}) => Consumer(
      builder: (context, ref, _) {
        final navItems = ref.watch(currentNavigationsStateProvider).value;
        return CommonScaffold(
          title: '代理',
          sideNavigationBar: CommonNavigationBar(
            viewMode: ViewMode.desktop,
            navigationItems: navItems,
            currentIndex: 0,
          ),
          body: body,
        );
      },
    );

Widget _buildTestApp({
  required Widget home,
  Locale locale = const Locale('zh', 'CN'),
  Brightness brightness = Brightness.dark,
  double textScale = 1.0,
  List<Override> overrides = const [],
}) =>
    ProviderScope(
      key: ValueKey('${locale.toLanguageTag()}-$brightness-$textScale'),
      overrides: overrides,
      child: Consumer(
        builder: (context, ref, _) {
          final scheme = ref.watch(genColorSchemeProvider(brightness));
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: MaterialApp(
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
            ),
          );
        },
      ),
    );

AppState _makeAppState({
  Size viewSize = const Size(1200, 820),
  int? runTime,
  List<Group> groups = const [],
}) =>
    AppState(
      pageLabel: PageLabel.proxies,
      viewSize: viewSize,
      version: 1,
      runTime: runTime,
      groups: groups,
      requests: FixedList(maxLength),
      logs: FixedList(maxLength),
      traffics: FixedList(30),
      totalTraffic: Traffic(),
      isInit: true,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    ClashCore.instanceForTesting = null;
  });

  test(
      'T1: Plan A color & theme system — Obsidian Slate dark, Porcelain Cloud light, Electric Cyan brand accent, and semantic latency colors',
      () {
    expect(defaultPrimaryColor, equals(0xFF0EA5E9));
    expect(defaultThemeProps.themeMode, equals(ThemeMode.dark));

    final container = ProviderContainer();
    addTearDown(container.dispose);

    final dark = container.read(genColorSchemeProvider(Brightness.dark));
    expect(dark.surface, equals(const Color(0xFF0B0E14)));
    expect(dark.surfaceDim, equals(const Color(0xFF07090E)));
    expect(dark.surfaceContainer, equals(const Color(0xFF121722)));
    expect(dark.primary, equals(const Color(0xFF38BDF8)));
    // Neutral surfaces must be cool slate (blue >= green), never swamp olive green.
    expect(
      dark.surfaceContainer.b >= dark.surfaceContainer.g,
      isTrue,
      reason: 'Dark card surface must not be tinted muddy green',
    );
    expect(
      dark.surfaceDim.computeLuminance() < dark.surface.computeLuminance(),
      isTrue,
    );
    expect(
      dark.surface.computeLuminance() <
          dark.surfaceContainer.computeLuminance(),
      isTrue,
    );

    final light = container.read(genColorSchemeProvider(Brightness.light));
    expect(light.surface, equals(const Color(0xFFF4F6FA)));
    expect(light.surfaceContainer, equals(const Color(0xFFFFFFFF)));
    expect(light.primary, equals(const Color(0xFF0284C7)));

    expect(utils.getDelayColor(120), equals(const Color(0xFF10B981)));
    expect(utils.getDelayColor(650), equals(const Color(0xFFF59E0B)));
    expect(utils.getDelayColor(-1), equals(const Color(0xFFEF4444)));
  });

  testWidgets(
      'T2: Brand rebrand ("自由云" / "FreedomNet") displays localized commercial brand while preserving internal system contracts',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Low-level system/Wintun/log contracts MUST remain intact.
    expect(appName, equals('FlClashX'));
    expect(const Tun().device, equals('FlClashX'));

    await tester.pumpWidget(
      _buildTestApp(
        locale: const Locale('zh', 'CN'),
        home: _buildNavigationBarShell(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('自由云'), findsOneWidget);
    expect(find.text('FreedomNet'), findsOneWidget);
    expect(find.text('FlClashX'), findsNothing);

    await tester.pumpWidget(
      _buildTestApp(
        locale: const Locale('en'),
        home: _buildNavigationBarShell(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('FreedomNet'), findsOneWidget);
    expect(find.text('FlClashX'), findsNothing);
  });

  testWidgets(
      'T3: Solemn Open-Source Tribute & Credits — AboutView monument and Novice Mode one-tap brand dialog honor FlClashX and Gemini 4',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // 1. AboutView monument renders brand + FlClashX tribute + Gemini 4 thanks + upstream contributors.
    await tester.pumpWidget(
      _buildTestApp(
        locale: const Locale('zh', 'CN'),
        home: const Scaffold(body: AboutView()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('about-brand-monument')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('about-tribute-flclashx')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('about-tribute-gemini4')),
      findsOneWidget,
    );
    expect(
      find.textContaining('FlClashX', findRichText: true),
      findsWidgets,
    );
    expect(
      find.textContaining('Gemini 4', findRichText: true),
      findsWidgets,
    );
    expect(find.text('pluralplay'), findsOneWidget);
    expect(find.text('kastov'), findsOneWidget);

    // 2. In Novice Mode (设置 collapsed), tapping top-left brand emblem opens tribute dialog.
    await tester.pumpWidget(
      _buildTestApp(
        locale: const Locale('zh', 'CN'),
        home: _buildNavigationBarShell(),
      ),
    );
    await tester.pumpAndSettle();

    final brandTrigger = find.byKey(const ValueKey('brand-tribute-trigger'));
    expect(brandTrigger, findsOneWidget);
    await tester.tap(brandTrigger);
    await tester.pumpAndSettle();

    final dialogFinder =
        find.byKey(const ValueKey('freedomnet-tribute-dialog'));
    expect(dialogFinder, findsOneWidget);
    expect(
      find.descendant(
        of: dialogFinder,
        matching: find.textContaining('FlClashX', findRichText: true),
      ),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: dialogFinder,
        matching: find.textContaining('Gemini 4', findRichText: true),
      ),
      findsWidgets,
    );

    await tester.tap(
      find.byKey(const ValueKey('freedomnet-tribute-dialog-close')),
    );
    await tester.pumpAndSettle();
    expect(dialogFinder, findsNothing);
  });

  testWidgets(
      'T4: Proxy cockpit novice decluttering hides geeky protocol strings & stale notices in 小白模式 and reveals them in 大佬模式',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const profile = Profile(
      id: 'p1',
      label: '自由云全球旗舰',
      url: 'https://example.com/sub',
      autoUpdateDuration: defaultUpdateDuration,
    );
    final testedAt = DateTime.now().subtract(const Duration(hours: 30));
    const catalog = ProfileCatalog(
      profileId: 'p1',
      fingerprint: 'fp-p1',
      status: ProfileCatalogStatus.ready,
      nodes: [
        CatalogNode(
          identityKey: 'n1',
          endpointKey: 'us.example.com:443',
          name: '美国洛城-AI高速',
          type: 'vless',
          source: CatalogNodeSource.inline,
          protocolSummary:
              'VLESS · TCP · REALITY · xtls-rprx-vision · uTLS:chrome · XUDP · UDP',
          selectGroups: ['Proxy'],
        ),
      ],
    );

    globalState.config = const Config(
      themeProps: defaultThemeProps,
      profiles: [profile],
    );
    globalState.appState = _makeAppState(
      viewSize: const Size(1280, 860),
      runTime: 1000,
      groups: const [
        Group(
          name: 'Proxy',
          type: GroupType.Selector,
          now: '美国洛城-AI高速',
          all: [
            Proxy(name: '美国洛城-AI高速', type: 'VLESS'),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      _buildTestApp(
        locale: const Locale('zh', 'CN'),
        overrides: [
          nodeOverviewEnabledProvider.overrideWithValue(true),
          activeNodeCatalogProvider.overrideWithValue(null),
          coldStartZeroProfilePromptedProvider.overrideWith((ref) => true),
          nodeCatalogTesterProvider.overrideWith((ref) => _NoopCatalogTester()),
          profileCatalogProvider.overrideWith((ref, id) async => catalog),
          nodeHealthEntriesProvider.overrideWith(
            (ref, id) => {
              'n1': NodeHealthRecord(
                delayMs: 138,
                testedAt: testedAt,
                testUrlHash: '0123456789abcdef',
              ),
            },
          ),
        ],
        home: _buildNavigationBarShell(body: const ProxiesView()),
      ),
    );
    await tester.pumpAndSettle();

    // Novice mode: node card & semantic latency pill are crisp; geeky telemetry is hidden.
    expect(find.text('美国洛城-AI高速'), findsWidgets);
    expect(find.text('138 ms'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('overview-mode-segmented-track')),
      findsOneWidget,
    );
    expect(
      find.textContaining('xtls-rprx-vision'),
      findsNothing,
    );
    expect(
      find.text(appLocalizations.nodeOverviewHistoryNotice),
      findsNothing,
    );

    // Switch to 大佬模式 -> geeky protocol telemetry & history notice immediately appear.
    await tester.tap(
      find.byKey(const ValueKey('navigation-expert-mode-toggle')),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('xtls-rprx-vision'),
      findsOneWidget,
    );
    expect(
      find.text(appLocalizations.nodeOverviewHistoryNotice),
      findsOneWidget,
    );
  });

  testWidgets(
      'T5: Brand monument & navigation rail render overflow-free at 2.0x text scale across zh_CN, en, ja, ru',
      (tester) async {
    for (final width in const [360.0, 1200.0]) {
      for (final locale in const [
        Locale('zh', 'CN'),
        Locale('en'),
        Locale('ja'),
        Locale('ru'),
      ]) {
        await AppLocalizations.load(locale);
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          _buildTestApp(
            locale: locale,
            textScale: 2.0,
            home: width <= 600
                ? const Scaffold(body: AboutView())
                : _buildNavigationBarShell(body: const AboutView()),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'Overflow at width=$width locale=${locale.toLanguageTag()}',
        );
        expect(
          find.byKey(const ValueKey('about-brand-monument')),
          findsOneWidget,
        );
      }
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

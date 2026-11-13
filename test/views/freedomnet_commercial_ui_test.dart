import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

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

    expect(utils.getDelayColor(null), isNull);
    expect(utils.getDelayColor(0), isNull);
    expect(utils.getDelayColor(1), equals(const Color(0xFF10B981)));
    expect(utils.getDelayColor(120), equals(const Color(0xFF10B981)));
    expect(utils.getDelayColor(650), equals(const Color(0xFF10B981)));
    expect(utils.getDelayColor(2000), equals(const Color(0xFF10B981)));
    expect(utils.getDelayColor(2001), equals(const Color(0xFFF59E0B)));
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
      'T3: Brand Showcase vs Solemn Credits — AboutView preserves FlClashX & Gemini 4 tributes while top-left brand dialog showcases FreedomNet brand only',
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
      find.textContaining('郑重声明', findRichText: true),
      findsWidgets,
    );
    expect(
      find.textContaining('FlClashX', findRichText: true),
      findsWidgets,
    );
    expect(
      find.textContaining('特别鸣谢', findRichText: true),
      findsWidgets,
    );
    expect(
      find.textContaining('Gemini 4', findRichText: true),
      findsWidgets,
    );
    expect(find.text('pluralplay'), findsOneWidget);
    expect(find.text('kastov'), findsOneWidget);

    // 2. Tapping top-left brand emblem opens FreedomNet brand showcase dialog without open-source tributes.
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
        matching: find.byKey(const ValueKey('freedomnet-brand-showcase')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialogFinder,
        matching: find.text('品牌介绍与核心体验'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialogFinder,
        matching: find.text('连接无界 · 疾速随行'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialogFinder,
        matching: find.text('智能选点 · 毫秒级感知'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialogFinder,
        matching: find.text('双模驾驭 · 即开即连'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialogFinder,
        matching: find.text('透明权益 · 安心续享'),
      ),
      findsOneWidget,
    );
    for (final forbidden in const [
      '开源致敬与特别鸣谢',
      '郑重声明',
      '特别鸣谢',
      'OPEN-SOURCE HERITAGE',
      'ENGINEERING & DESIGN SUPPORT',
      'FlClashX',
      'FlClash',
      'Mihomo',
      'Gemini 4',
    ]) {
      expect(
        find.descendant(
          of: dialogFinder,
          matching: find.textContaining(forbidden, findRichText: true),
        ),
        findsNothing,
        reason: 'Brand showcase dialog must not contain "$forbidden"',
      );
    }

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
        if (width == 360.0) {
          unawaited(
            showFreedomNetTributeDialog(
              tester.element(find.byType(AboutView)),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason:
                'Brand dialog overflow at width=$width locale=${locale.toLanguageTag()}',
          );
          expect(
            find.byKey(const ValueKey('freedomnet-brand-showcase')),
            findsOneWidget,
          );
          await tester.tap(
            find.byKey(const ValueKey('freedomnet-tribute-dialog-close')),
          );
          await tester.pumpAndSettle();
        }
      }
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets(
      'T6: Portal F brand mark (<span class="portal-brand-mark">F</span>) unifies FreedomNetBrandMark, taskbar app_icon.ico, and running/stopped tray icons',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _buildTestApp(
        locale: const Locale('zh', 'CN'),
        home: _buildNavigationBarShell(),
      ),
    );
    await tester.pumpAndSettle();

    final markFinder = find.byType(FreedomNetBrandMark);
    expect(markFinder, findsOneWidget);

    final container = tester.widget<Container>(
      find
          .descendant(
            of: markFinder,
            matching: find.byType(Container),
          )
          .first,
    );
    final box = container.decoration as BoxDecoration?;
    expect(box, isNotNull);
    expect(box!.color, equals(const Color(0xFF71D7A7)));
    expect(box.gradient, isNull);
    expect(box.borderRadius, equals(BorderRadius.circular(36 * (10.0 / 34.0))));

    final customPaint = tester.widget<CustomPaint>(
      find.descendant(
        of: markFinder,
        matching: find.byType(CustomPaint),
      ),
    );
    expect(customPaint.painter, isNotNull);

    final rgba = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      customPaint.painter!.paint(canvas, const Size(68, 68));
      final picture = recorder.endRecording();
      final rendered = await picture.toImage(68, 68);
      try {
        final raw = await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
        return raw?.buffer.asUint8List();
      } finally {
        rendered.dispose();
        picture.dispose();
      }
    });
    expect(rgba, isNotNull);
    int idx(int x, int y) => (y * 68 + x) * 4;

    // Pixel (29, 34) sits squarely on the bold dark-emerald F stem.
    final stemOffset = idx(29, 34);
    expect(rgba![stemOffset], equals(0x10));
    expect(rgba[stemOffset + 1], equals(0x20));
    expect(rgba[stemOffset + 2], equals(0x18));
    expect(rgba[stemOffset + 3], equals(0xFF));

    // Pixel (42, 44) in the bottom-right negative space must stay transparent.
    final blankOffset = idx(42, 44);
    expect(rgba[blankOffset + 3], equals(0));

    // Tray routing contract.
    expect(
      utils.getTrayIconPath(
        brightness: Brightness.dark,
        isRunning: true,
        isSystemDark: true,
      ),
      equals('assets/images/icon.ico'),
    );
    expect(
      utils.getTrayIconPath(
        brightness: Brightness.dark,
        isRunning: false,
        isSystemDark: true,
      ),
      equals('assets/images/icon_stop_white.ico'),
    );
    expect(
      utils.getTrayIconPath(
        brightness: Brightness.light,
        isRunning: false,
        isSystemDark: false,
      ),
      equals('assets/images/icon_stop_black.ico'),
    );

    Map<int, ({int offset, int size, int bpp})> parseIcoEntries(String path) {
      final bytes = File(path).readAsBytesSync();
      final data = ByteData.sublistView(bytes);
      expect(data.getUint16(0, Endian.little), equals(0), reason: path);
      expect(data.getUint16(2, Endian.little), equals(1), reason: path);
      final count = data.getUint16(4, Endian.little);
      final map = <int, ({int offset, int size, int bpp})>{};
      for (var i = 0; i < count; i++) {
        final base = 6 + i * 16;
        final w = bytes[base] == 0 ? 256 : bytes[base];
        final h = bytes[base + 1] == 0 ? 256 : bytes[base + 1];
        expect(w, equals(h), reason: '$path frame $i should be square');
        map[w] = (
          offset: data.getUint32(base + 12, Endian.little),
          size: data.getUint32(base + 8, Endian.little),
          bpp: data.getUint16(base + 6, Endian.little),
        );
      }
      return map;
    }

    Uint8List read32x32BgraPixels(String path) {
      final bytes = File(path).readAsBytesSync();
      final entries = parseIcoEntries(path);
      expect(
        entries.keys.toSet(),
        containsAll(const [16, 20, 24, 28, 32, 40, 48, 64, 256]),
        reason: '$path must contain full Windows DPI ladder + 256px frame',
      );
      final frame = entries[32]!;
      expect(frame.bpp, equals(32));
      // Skip 40-byte BITMAPINFOHEADER; XOR pixel rows are stored bottom-up.
      final xorStart = frame.offset + 40;
      return Uint8List.sublistView(bytes, xorStart, xorStart + 32 * 32 * 4);
    }

    (int r, int g, int b, int a) bgraPixel(Uint8List px, int x, int y) {
      final dibRow = 31 - y;
      final o = (dibRow * 32 + x) * 4;
      return (px[o + 2], px[o + 1], px[o], px[o + 3]);
    }

    // Taskbar app_icon.ico and running tray icon.ico use filled #71D7A7 + #102018 F.
    for (final filledPath in const [
      'windows/runner/resources/app_icon.ico',
      'assets/images/icon.ico',
    ]) {
      final px = read32x32BgraPixels(filledPath);
      expect(bgraPixel(px, 0, 0).$4, equals(0), reason: '$filledPath corner');
      final bg = bgraPixel(px, 7, 16);
      expect(bg, equals((0x71, 0xD7, 0xA7, 0xFF)), reason: '$filledPath bg');
      final hasDarkStem = [
        for (var x = 10; x <= 15; x++) bgraPixel(px, x, 16),
      ].any((p) => p.$4 > 200 && p.$1 < 0x30 && p.$2 < 0x40 && p.$3 < 0x30);
      expect(hasDarkStem, isTrue, reason: '$filledPath dark F stem');
    }

    // Stopped tray icons use transparent interior + crisp monochrome rounded outline + F.
    for (final stopSpec in const [
      (path: 'assets/images/icon_stop_white.ico', isWhite: true),
      (path: 'assets/images/icon_stop_black.ico', isWhite: false),
    ]) {
      final px = read32x32BgraPixels(stopSpec.path);
      expect(bgraPixel(px, 7, 16).$4, equals(0),
          reason: '${stopSpec.path} interior must stay transparent');
      final hasOutline = [
        for (var x = 1; x <= 4; x++) bgraPixel(px, x, 16),
      ].any((p) => p.$4 > 200 && (stopSpec.isWhite ? p.$1 > 220 : p.$1 < 50));
      expect(hasOutline, isTrue, reason: '${stopSpec.path} rounded outline');
      final hasStem = [
        for (var x = 10; x <= 15; x++) bgraPixel(px, x, 16),
      ].any((p) => p.$4 > 200 && (stopSpec.isWhite ? p.$1 > 220 : p.$1 < 50));
      expect(hasStem, isTrue, reason: '${stopSpec.path} monochrome F stem');
    }
  });
}

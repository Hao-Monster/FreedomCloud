import 'dart:io';
import 'dart:ui' as ui;

import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/node_catalog_tester.dart';
import 'package:flclashx/common/node_health_store.dart';
import 'package:flclashx/controller.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/models/node_catalog.dart';
import 'package:flclashx/providers/node_overview.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/views/proxies/proxies.dart';
import 'package:flclashx/widgets/scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _RenderCatalogTester extends ChangeNotifier implements NodeCatalogTester {
  @override
  bool get busy => false;
  @override
  int get total => 0;
  @override
  int get completed => 0;
  @override
  bool pending(String profileId, String identityKey) => false;
  @override
  void disposeScope() {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Rendering must not invoke ${invocation.memberName}');
}

class _RenderController implements AppController {
  @override
  List<Proxy> getSortProxies(List<Proxy> proxies, [String? url]) => proxies;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Rendering must not invoke ${invocation.memberName}');
}

/// Optional synthetic render evidence. Set NODE_OVERVIEW_RENDER_DIR to a private
/// output directory and run this file. No product process or real profile is used.
void main() {
  final output = Platform.environment['NODE_OVERVIEW_RENDER_DIR'];
  if (output == null || output.isEmpty) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fontPath = Platform.environment['NODE_OVERVIEW_RENDER_FONT'];
    final font = FontLoader('OverviewRender')
      ..addFont(fontPath == null
          ? rootBundle.load('assets/fonts/Unbounded-Regular.ttf')
          : File(fontPath).readAsBytes().then(ByteData.sublistView));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  CatalogNode node(String key, String name) => CatalogNode(
      identityKey: key,
      endpointKey: key,
      name: name,
      type: 'ss',
      source: CatalogNodeSource.inline);

  for (final size in [const Size(400, 920), const Size(1200, 900)]) {
    testWidgets('render overview ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
      await AppLocalizations.load(const Locale('en'));
      globalState.appController = _RenderController();
      const profiles = [
        Profile(
            id: 'a', label: 'Alpha profile', autoUpdateDuration: Duration.zero),
        Profile(
            id: 'b', label: 'Beta profile', autoUpdateDuration: Duration.zero),
      ];
      globalState.config = const Config(
          themeProps: defaultThemeProps,
          profiles: profiles,
          currentProfileId: 'a');
      globalState.appState = AppState(
          pageLabel: PageLabel.proxies,
          viewSize: size,
          version: 1,
          requests: FixedList(1),
          logs: FixedList(1),
          traffics: FixedList(1),
          totalTraffic: Traffic(),
          groups: const [
            Group(
                name: 'Runtime fixture',
                type: GroupType.Selector,
                hidden: false,
                all: [
                  Proxy(name: 'Singapore · Fast', type: 'Shadowsocks'),
                  Proxy(name: 'Tokyo · Unavailable', type: 'Shadowsocks'),
                  Proxy(name: 'London · Not tested', type: 'Shadowsocks'),
                ])
          ],
          delayMap: {
            defaultTestUrl: {
              'Singapore · Fast': 72,
              'Tokyo · Unavailable': -1,
            }
          });
      final now = DateTime.now();
      final catalogs = {
        'a': ProfileCatalog(
            profileId: 'a',
            fingerprint: 'synthetic',
            status: ProfileCatalogStatus.ready,
            nodes: [
              node('fast', 'Singapore · Fast'),
              node('failed', 'Tokyo · Unavailable'),
              node('untested', 'London · Not tested'),
            ]),
        'b': ProfileCatalog(
            profileId: 'b',
            fingerprint: 'synthetic',
            status: ProfileCatalogStatus.ready,
            nodes: [node('old', 'Frankfurt · Last session')],
            providerNodeCounts: const {'Cached subscription': -1}),
      };
      final health = {
        'a': {
          'fast': NodeHealthRecord(
              delayMs: 72, testedAt: now, testUrlHash: 'fixture'),
          'failed': NodeHealthRecord(
              delayMs: -1,
              testedAt: now,
              testUrlHash: 'fixture',
              reason: 'testFailed'),
        },
        'b': {
          'old': NodeHealthRecord(
              delayMs: 248,
              testedAt: now.subtract(const Duration(minutes: 20)),
              testUrlHash: 'fixture')
        },
      };
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      await tester.pumpWidget(ProviderScope(
          overrides: [
            nodeOverviewEnabledProvider.overrideWithValue(true),
            nodeCatalogTesterProvider
                .overrideWith((ref) => _RenderCatalogTester()),
            activeNodeCatalogProvider.overrideWithValue(catalogs['a']),
            cachedProfileCatalogsProvider.overrideWith((ref) => catalogs),
            profileCatalogProvider
                .overrideWith((ref, id) async => catalogs[id]!),
            nodeHealthEntriesProvider
                .overrideWith((ref, id) => health[id] ?? {}),
          ],
          child: RepaintBoundary(
            key: const ValueKey('overview-render'),
            child: MaterialApp(
              theme: ThemeData(fontFamily: 'OverviewRender'),
              locale: const Locale('en'),
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate
              ],
              supportedLocales: AppLocalizations.delegate.supportedLocales,
              home: CommonScaffold(
                  title: 'Proxies',
                  body: Builder(builder: (context) {
                    globalState.measure = Measure.of(context, 1);
                    return const ProxiesView();
                  })),
            ),
          )));
      await tester.pumpAndSettle();
      final scopeMenu = find.byKey(const ValueKey('overview-scope-menu'));
      if (scopeMenu.evaluate().isNotEmpty) {
        await tester.tap(scopeMenu);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(
            CheckedPopupMenuItem<ProxiesScope>, 'All profiles'));
      } else {
        await tester.tap(find.text('All profiles'));
      }
      await tester.pumpAndSettle();
      expect(find.text('Test current profile'), findsOneWidget);
      expect(find.text('Test all node delays'), findsOneWidget);
      expect(find.text('72 ms'), findsOneWidget);
      expect(find.text('Test failed'), findsOneWidget);
      expect(find.text('Untested'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('overview-render')));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final directory = await Directory(output).create(recursive: true);
          await File(
                  '${directory.path}/overview-${size.width.toInt()}x${size.height.toInt()}.png')
              .writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
        } finally {
          image.dispose();
        }
      });
    });
  }

  testWidgets('render narrow profile selector popup 440x820 dark zh_CN',
      (tester) async {
    const size = Size(440, 820);
    await AppLocalizations.load(const Locale('zh', 'CN'));
    globalState.appController = _RenderController();
    final now = DateTime.now();
    final profiles = [
      const Profile(
        id: 'admin',
        label: 'admin',
        url: 'https://example.com/admin',
        autoUpdateDuration: Duration(hours: 2400),
        subscriptionInfo: SubscriptionInfo(
          upload: 0,
          download: 585920000000,
          total: 0,
          expire: 0,
        ),
      ),
      Profile(
        id: 'vip',
        label: '测试-261026-GHDXXK',
        url: 'https://example.com/vip',
        autoUpdateDuration: const Duration(hours: 24),
        subscriptionInfo: SubscriptionInfo(
          upload: 0,
          download: 0,
          total: 536870912000,
          expire: now.add(const Duration(days: 27, hours: 6)).millisecondsSinceEpoch ~/ 1000,
        ),
      ),
      Profile(
        id: 'soon',
        label: '香港高速旗舰专线-临期',
        url: 'https://example.com/soon',
        autoUpdateDuration: const Duration(hours: 12),
        subscriptionInfo: SubscriptionInfo(
          upload: 1024,
          download: 2048,
          total: 107374182400,
          expire: now.add(const Duration(days: 4, hours: 6)).millisecondsSinceEpoch ~/ 1000,
        ),
      ),
      Profile(
        id: 'expired',
        label: '旧备用节点池',
        url: 'https://example.com/expired',
        autoUpdateDuration: const Duration(hours: 24),
        subscriptionInfo: SubscriptionInfo(
          upload: 1024,
          download: 2048,
          total: 10737418240,
          expire: now.subtract(const Duration(days: 5)).millisecondsSinceEpoch ~/ 1000,
        ),
      ),
      const Profile(
        id: 'local',
        label: '本地应急配置',
        url: '',
        autoUpdateDuration: Duration.zero,
      ),
    ];

    globalState.config = Config(
      themeProps: defaultThemeProps,
      profiles: profiles,
      currentProfileId: 'admin',
    );
    globalState.appState = AppState(
      pageLabel: PageLabel.proxies,
      viewSize: size,
      version: 1,
      requests: FixedList(1),
      logs: FixedList(1),
      traffics: FixedList(1),
      totalTraffic: Traffic(),
      groups: const [
        Group(
          name: 'Proxy',
          type: GroupType.Selector,
          now: '美国AGK-Reality-Vision',
          hidden: false,
          all: [
            Proxy(name: '美国AGK-Reality-Vision', type: 'VLESS'),
            Proxy(name: '香港IEPL-专线-01', type: 'VLESS'),
            Proxy(name: '日本东京-BGP-02', type: 'VLESS'),
          ],
        ),
      ],
      delayMap: {
        defaultTestUrl: {
          '美国AGK-Reality-Vision': 178,
          '香港IEPL-专线-01': 46,
          '日本东京-BGP-02': -1,
        },
      },
    );

    final catalogs = {
      'admin': ProfileCatalog(
        profileId: 'admin',
        fingerprint: 'f-admin',
        status: ProfileCatalogStatus.ready,
        nodes: [
          node('a1', '美国AGK-Reality-Vision'),
          node('a2', '香港IEPL-专线-01'),
          node('a3', '日本东京-BGP-02'),
        ],
      ),
      'vip': ProfileCatalog(
        profileId: 'vip',
        fingerprint: 'f-vip',
        status: ProfileCatalogStatus.ready,
        nodes: [
          node('v1', '新加坡-SG-01'),
          node('v2', '新加坡-SG-02'),
          node('v3', '美国西雅图-03'),
        ],
      ),
      'soon': ProfileCatalog(
        profileId: 'soon',
        fingerprint: 'f-soon',
        status: ProfileCatalogStatus.ready,
        nodes: [
          node('s1', '香港旗舰-01'),
          node('s2', '香港旗舰-02'),
        ],
      ),
      'expired': ProfileCatalog(
        profileId: 'expired',
        fingerprint: 'f-exp',
        status: ProfileCatalogStatus.ready,
        nodes: [node('e1', '旧节点-01')],
      ),
      'local': ProfileCatalog(
        profileId: 'local',
        fingerprint: 'f-loc',
        status: ProfileCatalogStatus.ready,
        nodes: [node('l1', '本地直连节点')],
      ),
    };
    final health = {
      'vip': {
        'v1': NodeHealthRecord(delayMs: 62, testedAt: now, testUrlHash: 'h'),
        'v2': NodeHealthRecord(delayMs: 85, testedAt: now, testUrlHash: 'h'),
        'v3': NodeHealthRecord(delayMs: -1, testedAt: now, testUrlHash: 'h'),
      },
      'soon': {
        's1': NodeHealthRecord(delayMs: 39, testedAt: now, testUrlHash: 'h'),
        's2': NodeHealthRecord(delayMs: -1, testedAt: now, testUrlHash: 'h'),
      },
      'expired': {
        'e1': NodeHealthRecord(delayMs: -1, testedAt: now, testUrlHash: 'h'),
      },
    };

    tester.view.physicalSize = const Size(880, 1640);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));

    final darkScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF60A5FA),
      brightness: Brightness.dark,
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        nodeOverviewEnabledProvider.overrideWithValue(true),
        nodeCatalogTesterProvider
            .overrideWith((ref) => _RenderCatalogTester()),
        activeNodeCatalogProvider.overrideWithValue(catalogs['admin']),
        cachedProfileCatalogsProvider.overrideWith((ref) => catalogs),
        profileCatalogProvider.overrideWith((ref, id) async => catalogs[id]!),
        nodeHealthEntriesProvider.overrideWith((ref, id) => health[id] ?? {}),
      ],
      child: RepaintBoundary(
        key: const ValueKey('overview-render-dark'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: darkScheme,
            fontFamily: 'OverviewRender',
          ),
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.delegate.supportedLocales,
          home: CommonScaffold(
            title: '代理',
            body: Builder(builder: (context) {
              globalState.measure = Measure.of(context, 1);
              return const ProxiesView();
            }),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final scopeMenu = find.byKey(const ValueKey('overview-scope-menu'));
    if (scopeMenu.evaluate().isNotEmpty) {
      await tester.tap(scopeMenu);
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<ProxiesScope>, '全部配置'),
      );
    } else {
      await tester.tap(find.text('全部配置'));
    }
    await tester.pumpAndSettle();

    // Open the narrow profile selector popup
    await tester.tap(find.byKey(const ValueKey('overview-profile-filter')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('overview-profile-menu')), findsOneWidget);
    expect(tester.takeException(), isNull);

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('overview-render-dark')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2.0);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final directory = await Directory(output).create(recursive: true);
        await File('${directory.path}/overview-narrow-picker-440x820.png')
            .writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
      } finally {
        image.dispose();
      }
    });
  });
}

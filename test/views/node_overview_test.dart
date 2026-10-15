import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/node_health_store.dart';
import 'package:flclashx/controller.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/models/node_catalog.dart';
import 'package:flclashx/providers/node_overview.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/views/proxies/card.dart';
import 'package:flclashx/views/proxies/overview/overview.dart';
import 'package:flclashx/views/proxies/proxies.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _a =
    Profile(id: 'a', label: 'Alpha profile', autoUpdateDuration: Duration.zero);
const _b =
    Profile(id: 'b', label: 'Beta profile', autoUpdateDuration: Duration.zero);

CatalogNode _node(String key, String name) => CatalogNode(
      identityKey: key,
      endpointKey: key,
      name: name,
      type: 'ss',
      source: CatalogNodeSource.inline,
    );

class _ProxyController implements AppController {
  final selections = <(String, String)>[];
  final changes = <(String, String)>[];

  @override
  void updateCurrentSelectedMap(String groupName, String proxyName) =>
      selections.add((groupName, proxyName));

  @override
  void changeProxyDebounce(String groupName, String proxyName) =>
      changes.add((groupName, proxyName));

  @override
  List<Proxy> getSortProxies(List<Proxy> proxies, [String? url]) => proxies;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
      'Unexpected controller effect: ${invocation.memberName}');
}

void main() {
  setUp(() async {
    await AppLocalizations.load(const Locale('en'));
    globalState.config =
        const Config(themeProps: defaultThemeProps, profiles: [_a, _b]);
    globalState.appState = AppState(
      viewSize: const Size(400, 900),
      version: 1,
      requests: FixedList(1),
      logs: FixedList(1),
      traffics: FixedList(1),
      totalTraffic: Traffic(),
    );
  });

  Future<ProviderContainer> mount(
    WidgetTester tester, {
    Widget child = const NodeOverviewView(),
    List<Profile> profiles = const [_a, _b],
    Map<String, ProfileCatalog> catalogs = const {},
    Map<String, ProfileCatalog> cached = const {},
    Map<String, Map<String, NodeHealthRecord>> health = const {},
    void Function(String)? onLoad,
    bool enabled = true,
    double width = 400,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    globalState.config = globalState.config.copyWith(profiles: profiles);
    globalState.appState =
        globalState.appState.copyWith(viewSize: Size(width, 1000));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        nodeOverviewEnabledProvider.overrideWithValue(enabled),
        cachedProfileCatalogsProvider.overrideWith((ref) => cached),
        profileCatalogProvider.overrideWith((ref, id) async {
          onLoad?.call(id);
          return catalogs[id] ??
              ProfileCatalog(
                  profileId: id,
                  fingerprint: '',
                  status: ProfileCatalogStatus.ready);
        }),
        nodeHealthEntriesProvider.overrideWith((ref, id) => health[id] ?? {}),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate
        ],
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        home: Scaffold(body: Builder(builder: (context) {
          globalState.measure = Measure.of(context, 1);
          return child;
        })),
      ),
    ));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(Scaffold)));
  }

  testWidgets('scope is hidden for one profile and when disabled',
      (tester) async {
    const scope =
        NodeOverviewScopeView(currentView: Text('Existing proxy view'));
    await mount(tester, child: scope, profiles: [_a]);
    expect(find.text('All profiles'), findsNothing);
    expect(find.text('Existing proxy view'), findsOneWidget);
    await mount(tester, child: scope, enabled: false);
    expect(find.text('All profiles'), findsNothing);
    expect(find.text('Existing proxy view'), findsOneWidget);
  });

  testWidgets(
      'defaults to existing view; opening overview loads no collapsed profiles',
      (tester) async {
    final loaded = <String>[];
    final container = await mount(tester,
        child: const NodeOverviewScopeView(
            currentView: Text('Existing proxy view')),
        onLoad: loaded.add);
    expect(find.text('Existing proxy view'), findsOneWidget);
    await tester.tap(find.text('All profiles'));
    await tester.pumpAndSettle();
    expect(find.text('Alpha profile'), findsOneWidget);
    expect(loaded, isEmpty);
    expect(container.read(currentProfileIdProvider), isNull);
    await tester.tap(find.byKey(const ValueKey('overview-header-b')));
    await tester.pumpAndSettle();
    expect(loaded, ['b']);
    expect(container.read(currentProfileIdProvider), isNull);
  });

  testWidgets(
      'same node names retain separate historical results; rows are read only',
      (tester) async {
    final now = DateTime.now();
    final container = await mount(tester, catalogs: {
      'a': ProfileCatalog(
          profileId: 'a',
          fingerprint: '',
          status: ProfileCatalogStatus.ready,
          nodes: [_node('a-node', 'Same node')]),
      'b': ProfileCatalog(
          profileId: 'b',
          fingerprint: '',
          status: ProfileCatalogStatus.ready,
          nodes: [_node('b-node', 'Same node')]),
    }, health: {
      'a': {
        'a-node':
            NodeHealthRecord(delayMs: 123, testedAt: now, testUrlHash: 'hash')
      },
      'b': {
        'b-node': NodeHealthRecord(
            delayMs: 456,
            testedAt: now.subtract(const Duration(minutes: 11)),
            testUrlHash: 'hash')
      },
    });
    for (final id in ['a', 'b']) {
      await tester.tap(find.byKey(ValueKey('overview-header-$id')));
      await tester.pumpAndSettle();
    }
    expect(find.text('Same node'), findsNWidgets(2));
    expect(find.text('123 ms'), findsOneWidget);
    expect(find.text('456 ms'), findsOneWidget);
    expect(find.textContaining('May be outdated'), findsWidgets);
    for (final id in ['a', 'b']) {
      expect(
          find.descendant(
              of: find.byKey(ValueKey('overview-node-$id-$id-node')),
              matching: find.textContaining('Last active test')),
          findsOneWidget);
    }
    await tester.tap(find.text('Same node').last);
    await tester.pump();
    expect(container.read(currentProfileIdProvider), isNull);
    expect(container.read(delayDataSourceProvider), isEmpty);
    expect(find.byType(ProxyCard), findsNothing);
  });

  testWidgets(
      'search, delay and name ordering, and available filter use each profile history',
      (tester) async {
    final now = DateTime.now();
    final container = await mount(tester, catalogs: {
      'a': ProfileCatalog(
          profileId: 'a',
          fingerprint: '',
          status: ProfileCatalogStatus.ready,
          nodes: [
            _node('z', 'Zulu'),
            _node('a', 'Alpha'),
            _node('f', 'Failed'),
            _node('u', 'Untested')
          ]),
    }, health: {
      'a': {
        'z': NodeHealthRecord(delayMs: 20, testedAt: now, testUrlHash: 'hash'),
        'a': NodeHealthRecord(delayMs: 100, testedAt: now, testUrlHash: 'hash'),
        'f': NodeHealthRecord(
            delayMs: -1,
            testedAt: now,
            testUrlHash: 'hash',
            reason: 'testFailed'),
      },
    });
    await tester.tap(find.byKey(const ValueKey('overview-header-a')));
    await tester.pumpAndSettle();
    container
        .read(proxiesStyleSettingProvider.notifier)
        .updateState((state) => state.copyWith(sortType: ProxiesSortType.name));
    await tester.pump();
    expect(tester.getTopLeft(find.text('Alpha')).dy,
        lessThan(tester.getTopLeft(find.text('Zulu')).dy));
    container.read(proxiesStyleSettingProvider.notifier).updateState(
        (state) => state.copyWith(sortType: ProxiesSortType.delay));
    await tester.pump();
    expect(tester.getTopLeft(find.text('Zulu')).dy,
        lessThan(tester.getTopLeft(find.text('Alpha')).dy));
    await tester.tap(find.text('Available only'));
    await tester.pump();
    expect(find.text('Failed'), findsNothing);
    expect(find.text('Untested'), findsNothing);
    container.read(proxiesQueryProvider.notifier).value = 'zUl';
    await tester.pump();
    expect(find.text('Zulu'), findsOneWidget);
    expect(find.text('Alpha'), findsNothing);
  });

  testWidgets(
      'wide sidebar is read only and selection lazily opens that profile',
      (tester) async {
    final loaded = <String>[];
    await mount(tester, width: 1200, onLoad: loaded.add);
    expect(find.byKey(const ValueKey('overview-sidebar')), findsOneWidget);
    expect(loaded, isEmpty);
    await tester.tap(find.byKey(const ValueKey('overview-select-b')));
    await tester.pumpAndSettle();
    expect(loaded, ['b']);
    expect(find.byKey(const ValueKey('overview-header-a')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'exception cards localize missing, parse, expiry, updating and provider placeholders',
      (tester) async {
    final profiles = [
      _a.copyWith(subscriptionInfo: const SubscriptionInfo(expire: 1)),
      _b.copyWith(isUpdating: true),
    ];
    await mount(tester, profiles: profiles, catalogs: {
      'a': const ProfileCatalog(
          profileId: 'a',
          fingerprint: '',
          status: ProfileCatalogStatus.fileMissing),
      'b': const ProfileCatalog(
          profileId: 'b',
          fingerprint: '',
          status: ProfileCatalogStatus.parseFailed),
    });
    for (final id in ['a', 'b']) {
      await tester.tap(find.byKey(ValueKey('overview-header-$id')));
      await tester.pumpAndSettle();
    }
    expect(find.text('Profile file is missing'), findsOneWidget);
    expect(find.text('Profile could not be parsed'), findsOneWidget);
    expect(find.text('Subscription expired'), findsWidgets);
    expect(find.text('Updating subscription'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'active nodes reuse live group cards and keep each selection target',
      (tester) async {
    globalState.config = globalState.config.copyWith(currentProfileId: 'a');
    const leaf = Proxy(name: 'Live leaf', type: 'Shadowsocks');
    const groupProxy = Proxy(name: 'Nested', type: 'Selector');
    globalState.appState = globalState.appState.copyWith(groups: [
      const Group(
          name: 'One',
          type: GroupType.Selector,
          hidden: false,
          testUrl: 'https://one.invalid',
          all: [leaf, groupProxy]),
      const Group(
          name: 'Two',
          type: GroupType.URLTest,
          hidden: false,
          testUrl: 'https://two.invalid',
          all: [leaf]),
      const Group(name: 'Nested', type: GroupType.Selector, hidden: true),
    ]);
    final container = await mount(tester);
    final cards = tester.widgetList<ProxyCard>(find.byType(ProxyCard)).toList();
    expect(cards, hasLength(2));
    expect(cards.map((card) => card.groupName), ['One', 'Two']);
    expect(cards.map((card) => card.groupType),
        [GroupType.Selector, GroupType.URLTest]);
    expect(cards.map((card) => card.testUrl),
        ['https://one.invalid', 'https://two.invalid']);
    expect(cards.map((card) => card.proxy.name), everyElement('Live leaf'));
    expect(container.read(currentProfileIdProvider), 'a');
    expect(container.read(delayDataSourceProvider), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'real proxies page round trip preserves original active node selection',
      (tester) async {
    final controller = _ProxyController();
    globalState.appController = controller;
    globalState.config = globalState.config.copyWith(currentProfileId: 'a');
    globalState.appState = globalState.appState.copyWith(
      pageLabel: PageLabel.proxies,
      groups: const [
        Group(
            name: 'Select',
            type: GroupType.Selector,
            hidden: false,
            all: [Proxy(name: 'Selectable leaf', type: 'Shadowsocks')])
      ],
    );
    final container =
        await mount(tester, child: const ProxiesView(), profiles: [
      _a.copyWith(unfoldSet: {'Select'}),
      _b
    ]);
    expect(find.byType(NodeOverviewView), findsNothing);
    await tester.tap(find.text('All profiles'));
    await tester.pumpAndSettle();
    expect(container.read(currentProfileIdProvider), 'a');
    expect(container.read(currentGroupsStateProvider).value, isNotEmpty);
    expect(find.byType(NodeOverviewView), findsOneWidget);
    await tester.tap(find.text('Selectable leaf', findRichText: true));
    await tester.pump();
    expect(controller.changes, [('Select', 'Selectable leaf')]);
    expect(controller.selections, [('Select', 'Selectable leaf')]);
    await tester.tap(find.text('Current profile'));
    await tester.pumpAndSettle();
    expect(find.byType(NodeOverviewView), findsNothing);
    await tester.tap(find.text('Selectable leaf', findRichText: true));
    await tester.pump();
    expect(controller.changes,
        [('Select', 'Selectable leaf'), ('Select', 'Selectable leaf')]);
    expect(container.read(currentProfileIdProvider), 'a');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'cold search loads collapsed profiles and clearing restores expansion',
      (tester) async {
    final loaded = <String>[];
    final container = await mount(tester, onLoad: loaded.add, catalogs: {
      'a': ProfileCatalog(
          profileId: 'a',
          fingerprint: '',
          status: ProfileCatalogStatus.ready,
          nodes: [_node('a-needle', 'Needle Alpha')]),
      'b': ProfileCatalog(
          profileId: 'b',
          fingerprint: '',
          status: ProfileCatalogStatus.ready,
          nodes: [_node('b-needle', 'Needle Beta')]),
    });
    expect(loaded, isEmpty);
    container.read(proxiesQueryProvider.notifier).value = 'needle';
    await tester.pumpAndSettle();
    expect(loaded, containsAll(['a', 'b']));
    expect(find.text('Needle Alpha'), findsOneWidget);
    expect(find.text('Needle Beta'), findsOneWidget);
    container.read(proxiesQueryProvider.notifier).value = '';
    await tester.pumpAndSettle();
    expect(find.text('Needle Alpha'), findsNothing);
    expect(find.text('Needle Beta'), findsNothing);
  });

  testWidgets(
      'wide search spans profiles even after selecting one in the sidebar',
      (tester) async {
    final container = await mount(tester, width: 1200, catalogs: {
      'a': ProfileCatalog(
          profileId: 'a',
          fingerprint: '',
          status: ProfileCatalogStatus.ready,
          nodes: [_node('a-needle', 'Needle Alpha')]),
      'b': ProfileCatalog(
          profileId: 'b',
          fingerprint: '',
          status: ProfileCatalogStatus.ready,
          nodes: [_node('b-needle', 'Needle Beta')]),
    });
    await tester.tap(find.byKey(const ValueKey('overview-select-b')));
    await tester.pumpAndSettle();
    expect(find.text('Needle Alpha'), findsNothing);
    container.read(proxiesQueryProvider.notifier).value = 'needle';
    await tester.pumpAndSettle();
    expect(find.text('Needle Alpha'), findsOneWidget);
    expect(find.text('Needle Beta'), findsOneWidget);
    container.read(proxiesQueryProvider.notifier).value = '';
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('overview-header-a')), findsNothing);
    expect(find.text('Needle Beta'), findsOneWidget);
  });

  testWidgets(
      'active health uses the first visible group test URL and deduplicates leaves',
      (tester) async {
    globalState.config = globalState.config.copyWith(currentProfileId: 'a');
    const leaf = Proxy(name: 'Live leaf', type: 'Shadowsocks');
    globalState.appState = globalState.appState.copyWith(
      groups: const [
        Group(
            name: 'First',
            type: GroupType.Selector,
            hidden: false,
            testUrl: 'https://custom.invalid',
            all: [leaf]),
        Group(
            name: 'Second',
            type: GroupType.Selector,
            hidden: false,
            all: [leaf]),
      ],
      delayMap: {
        'https://custom.invalid': {'Live leaf': 321},
        defaultTestUrl: {'Live leaf': -1}
      },
    );
    await mount(tester);
    expect(find.text('1 available / 1 tested / 1 total'), findsOneWidget);
    expect(find.text('Median: 321 ms'), findsOneWidget);
    expect(find.text('321 ms'), findsOneWidget);
    expect(find.text('Timeout'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [400.0, 1200.0]) {
    testWidgets(
        'cached errors and expiry remain visible while collapsed at width $width',
        (tester) async {
      final loaded = <String>[];
      await mount(tester, width: width, onLoad: loaded.add, profiles: [
        _a.copyWith(subscriptionInfo: const SubscriptionInfo(expire: 1)),
        _b.copyWith(isUpdating: true)
      ], cached: {
        'a': const ProfileCatalog(
            profileId: 'a',
            fingerprint: '',
            status: ProfileCatalogStatus.fileMissing),
        'b': const ProfileCatalog(
            profileId: 'b',
            fingerprint: '',
            status: ProfileCatalogStatus.parseFailed),
      });
      final scope = width > 840
          ? find.byKey(const ValueKey('overview-sidebar'))
          : find.byKey(const ValueKey('overview-nodes'));
      for (final message in [
        'Profile file is missing',
        'Profile could not be parsed',
        'Subscription expired',
        'Updating subscription'
      ]) {
        expect(find.descendant(of: scope, matching: find.text(message)),
            findsOneWidget);
      }
      expect(find.text('0 available / 0 tested / 0 total'), findsNothing);
      expect(loaded, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'large expanded catalogs only build viewport rows and show provider limitation',
      (tester) async {
    await mount(tester, catalogs: {
      'a': ProfileCatalog(
          profileId: 'a',
          fingerprint: '',
          status: ProfileCatalogStatus.ready,
          nodes: List.generate(2000, (i) => _node('key-$i', 'Node $i')),
          providerNodeCounts: const {'Provider QA': -1}),
    });
    await tester.tap(find.byKey(const ValueKey('overview-header-a')));
    await tester.pumpAndSettle();
    expect(find.text('Node 0'), findsOneWidget);
    expect(find.text('Node 1999'), findsNothing);
    expect(find.text('Summary includes loaded nodes only'), findsOneWidget);
    expect(
        find.textContaining('Node ').evaluate().length, lessThanOrEqualTo(20));
    expect(tester.takeException(), isNull);
  });

}

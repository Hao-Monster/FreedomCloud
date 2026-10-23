import 'dart:io';

import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/delay_test_coordinator.dart';
import 'package:flclashx/common/node_catalog_service.dart';
import 'package:flclashx/common/node_catalog_tester.dart';
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
import 'package:flclashx/views/proxies/list.dart';
import 'package:flclashx/views/proxies/overview/overview.dart';
import 'package:flclashx/views/proxies/proxies.dart';
import 'package:flclashx/widgets/scaffold.dart';
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
  final applyDebounces = <bool>[];

  @override
  void updateCurrentSelectedMap(String groupName, String proxyName) =>
      selections.add((groupName, proxyName));

  @override
  void changeProxyDebounce(String groupName, String proxyName) =>
      changes.add((groupName, proxyName));

  @override
  void applyProfileDebounce({bool silence = false}) =>
      applyDebounces.add(silence);

  @override
  List<Proxy> getSortProxies(List<Proxy> proxies, [String? url]) => proxies;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
      'Unexpected controller effect: ${invocation.memberName}');
}

class _CatalogTester extends ChangeNotifier implements NodeCatalogTester {
  final batches = <List<CatalogTestSelection>>[];
  final urls = <String>[];
  final current = <List<DelayTestTarget>>[];
  final all = <List<Profile>>[];
  final pendingKeys = <(String, String)>{};
  String? reason;
  DelayBatchResult? allResult;
  int cancellations = 0;
  int scopeDisposals = 0;
  @override
  bool busy = false;
  @override
  int total = 0;
  @override
  int completed = 0;
  @override
  bool pending(String profileId, String identityKey) =>
      pendingKeys.contains((profileId, identityKey));
  void progress({required int done, required int count}) {
    busy = true;
    completed = done;
    total = count;
    notifyListeners();
  }

  @override
  Future<DelayBatchResult> testCurrent(
      Iterable<DelayTestTarget> targets) async {
    current.add(targets.toList());
    return DelayBatchResult(completed: 0, failed: 0, reason: reason);
  }

  @override
  Future<DelayBatchResult> testAll(List<Profile> profiles, String url) async {
    all.add(profiles);
    urls.add(url);
    return allResult ??
        DelayBatchResult(completed: 0, failed: 0, reason: reason);
  }

  @override
  Future<DelayBatchResult> collectAndTest(
          Future<List<CatalogTestSelection>> Function(bool Function() isCurrent)
              collect,
          String url) async =>
      testVisible(await collect(() => true), url);

  @override
  Future<DelayBatchResult> testVisible(
      List<CatalogTestSelection> selections, String url) async {
    batches.add(selections);
    urls.add(url);
    return DelayBatchResult(completed: 0, failed: 0, reason: reason);
  }

  @override
  Future<void> cancel({String reason = 'cancelled'}) async {
    cancellations++;
    busy = false;
    pendingKeys.clear();
    notifyListeners();
  }

  @override
  void disposeScope() => scopeDisposals++;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected catalog effect: ${invocation.memberName}');
}

void main() {
  setUp(() async {
    await AppLocalizations.load(const Locale('en'));
    globalState.config =
        const Config(themeProps: defaultThemeProps, profiles: [_a, _b]);
    globalState.lastRuntimeConfig = null;
    globalState.lastRuntimeProfileId = null;
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
    bool appBarScaffold = false,
    bool scopeToolbar = false,
    ProfileCatalog? activeCatalog,
    NodeHealthStore? healthStore,
    _CatalogTester? catalogTester,
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
        nodeCatalogTesterProvider
            .overrideWith((ref) => catalogTester ?? _CatalogTester()),
        activeNodeCatalogProvider.overrideWithValue(activeCatalog),
        cachedProfileCatalogsProvider.overrideWith((ref) => cached),
        profileCatalogProvider.overrideWith((ref, id) async {
          onLoad?.call(id);
          return catalogs[id] ??
              cached[id] ??
              ProfileCatalog(
                  profileId: id,
                  fingerprint: '',
                  status: ProfileCatalogStatus.ready);
        }),
        if (healthStore != null)
          nodeHealthStoreProvider.overrideWith((ref) => healthStore),
        nodeHealthEntriesProvider.overrideWith((ref, id) => healthStore == null
            ? health[id] ?? {}
            : ref.watch(nodeHealthStoreProvider).readProfile(id,
                testUrl: ref.watch(nodeOverviewTestUrlProvider))),
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
        home: Builder(builder: (context) {
          final body = Builder(builder: (context) {
            globalState.measure = Measure.of(context, 1);
            return child;
          });
          return appBarScaffold || scopeToolbar
              ? CommonScaffold(
                  title: 'Proxies',
                  body: body,
                  actions:
                      scopeToolbar ? const [NodeOverviewScopeAction()] : null)
              : Scaffold(body: body);
        }),
      ),
    ));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(Scaffold)));
  }

  Future<void> selectScope(WidgetTester tester, String label) async {
    final menu = find.byKey(const ValueKey('overview-scope-menu'));
    if (menu.evaluate().isNotEmpty) {
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester
          .tap(find.widgetWithText(CheckedPopupMenuItem<ProxiesScope>, label));
    } else {
      await tester.tap(find.text(label));
    }
    await tester.pumpAndSettle();
  }

  Map<String, ProfileCatalog> flatCatalogs() => {
        'a': ProfileCatalog(
            profileId: 'a',
            fingerprint: 'fixture',
            status: ProfileCatalogStatus.ready,
            nodes: [_node('a-node', 'Alpha node')]),
        'b': ProfileCatalog(
            profileId: 'b',
            fingerprint: 'fixture',
            status: ProfileCatalogStatus.ready,
            nodes: [_node('b-node', 'Beta node')]),
      };

  testWidgets(
      'all-node test ignores selection and search and includes the active profile',
      (tester) async {
    final backend = _CatalogTester();
    globalState.config = globalState.config.copyWith(currentProfileId: 'a');
    final nodes = List.generate(50, (i) => _node('b-$i', 'Match $i'));
    final container =
        await mount(tester, width: 1200, catalogTester: backend, catalogs: {
      ...flatCatalogs(),
      'b': ProfileCatalog(
          profileId: 'b',
          fingerprint: 'fixture',
          status: ProfileCatalogStatus.ready,
          nodes: [...nodes, _node('other', 'Other')]),
    });
    await tester.tap(find.byKey(const ValueKey('overview-select-b')));
    container.read(proxiesQueryProvider.notifier).value = 'match';
    await tester.pumpAndSettle();
    expect(find.text('Match 49'), findsNothing);
    await tester.tap(find.text('Test all node delays'));
    await tester.pumpAndSettle();
    expect(backend.all.single.map((profile) => profile.id), ['a', 'b']);
    expect(backend.batches, isEmpty);
    expect(backend.urls, [defaultTestUrl]);
    expect(container.read(currentProfileIdProvider), 'a');
  });

  testWidgets('all-node test ignores the available-only filter',
      (tester) async {
    final backend = _CatalogTester();
    final now = DateTime.now();
    await mount(tester, width: 1200, catalogTester: backend, catalogs: {
      'a': ProfileCatalog(
          profileId: 'a',
          fingerprint: 'fixture',
          status: ProfileCatalogStatus.ready,
          nodes: [
            _node('fast', 'Fast'),
            _node('failed', 'Failed'),
            _node('new', 'New')
          ]),
    }, health: {
      'a': {
        'fast': NodeHealthRecord(
            delayMs: 50, testedAt: now, testUrlHash: 'fixture'),
        'failed': NodeHealthRecord(
            delayMs: -1, testedAt: now, testUrlHash: 'fixture'),
      }
    });
    await tester.tap(find.text('Available only'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test all node delays'));
    await tester.pumpAndSettle();
    expect(backend.all.single.map((profile) => profile.id), ['a', 'b']);
    expect(backend.batches, isEmpty);
  });

  testWidgets(
      'all-node test remains enabled when only the active profile is selected',
      (tester) async {
    final backend = _CatalogTester();
    globalState.config = globalState.config.copyWith(currentProfileId: 'a');
    await mount(tester,
        width: 1200, catalogTester: backend, catalogs: flatCatalogs());
    await tester.tap(find.byKey(const ValueKey('overview-select-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test all node delays'));
    await tester.pumpAndSettle();
    expect(backend.all.single.map((profile) => profile.id), ['a', 'b']);
    expect(backend.batches, isEmpty);
    expect(backend.current, isEmpty);
  });

  testWidgets(
      'all-node summary reports completed failed untested and affected profiles safely',
      (tester) async {
    final backend = _CatalogTester()
      ..allResult =
          const DelayBatchResult(completed: 3, failed: 1, untested: 4, issues: [
        DelayBatchIssue(
            profileId: 'private-profile-a',
            reason: 'typeUnsupported',
            count: 2),
        DelayBatchIssue(
            profileId: 'private-profile-a',
            reason: 'chainUnsupported',
            count: 1),
        DelayBatchIssue(
            profileId: 'private-profile-b',
            reason: 'https://private.invalid/token',
            count: 1),
      ]);
    await mount(tester, catalogTester: backend);
    await tester.tap(find.byKey(const ValueKey('overview-test-all')));
    await tester.pumpAndSettle();
    expect(
        find.textContaining(
            'Completed 3 · Failed 1 · Untested 4 · Profiles with issues 2'),
        findsOneWidget);
    expect(
        find.textContaining(
            'This protocol is not supported for isolated tests'),
        findsOneWidget);
    expect(find.textContaining('https://private.invalid'), findsNothing);
    expect(find.textContaining('private-profile'), findsNothing);
    expect(find.textContaining('typeUnsupported'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'all-node many issue types retain totals with bounded explanations',
      (tester) async {
    final backend = _CatalogTester()
      ..allResult =
          const DelayBatchResult(completed: 0, failed: 0, untested: 3, issues: [
        DelayBatchIssue(profileId: 'a', reason: 'ambiguousNode', count: 1),
        DelayBatchIssue(profileId: 'a', reason: 'healthCapacityExceeded'),
        DelayBatchIssue(profileId: 'a', reason: 'healthStoreUnavailable'),
        DelayBatchIssue(profileId: 'b', reason: 'providerNotCached', count: 2),
      ]);
    await mount(tester, catalogTester: backend);
    await tester.tap(find.byKey(const ValueKey('overview-test-all')));
    await tester.pumpAndSettle();
    expect(
        find.textContaining(
            'Completed 0 · Failed 0 · Untested 3 · Profiles with issues 2'),
        findsOneWidget);
    expect(
        find.textContaining(
            'Duplicate node definitions; identity could not be verified'),
        findsOneWidget);
    expect(
        find.textContaining(
            'History storage is full; some results were not saved'),
        findsOneWidget);
    expect(find.textContaining('Some delay results could not be saved'),
        findsOneWidget);
    expect(find.textContaining('Additional issue types: 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all-node interruption retains its partial summary',
      (tester) async {
    final backend = _CatalogTester()
      ..allResult = const DelayBatchResult(
          completed: 2, failed: 0, untested: 5, reason: 'cancelled');
    await mount(tester, catalogTester: backend);
    await tester.tap(find.byKey(const ValueKey('overview-test-all')));
    await tester.pumpAndSettle();
    expect(
        find.textContaining(
            'Completed 2 · Failed 0 · Untested 5 · Profiles with issues 0'),
        findsOneWidget);
    expect(
        find.textContaining(
            'Test interrupted; earlier measurements were preserved'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'loaded provider counts do not show unsupported or partial notices',
      (tester) async {
    await mount(tester, width: 1200, catalogs: {
      'a': ProfileCatalog(
          profileId: 'a',
          fingerprint: '',
          status: ProfileCatalogStatus.ready,
          nodes: [_node('provider-node', 'Cached provider node')],
          providerNodeCounts: const {'Loaded provider': 1}),
    });
    expect(find.text('Cached provider node'), findsOneWidget);
    expect(find.textContaining('Local provider nodes are not supported'),
        findsNothing);
    expect(find.text('Summary includes loaded nodes only'), findsNothing);
  });

  testWidgets(
      'unloaded provider notice explains all-node reads without changing filters',
      (tester) async {
    await mount(tester, catalogs: {
      'a': const ProfileCatalog(
          profileId: 'a',
          fingerprint: '',
          status: ProfileCatalogStatus.ready,
          providerNodeCounts: {'Pending provider': -1}),
    });
    expect(
        find.text(
            'Pending provider: Provider nodes are not loaded yet. Testing all node delays reads them and downloads missing caches.'),
        findsOneWidget);
    expect(
        find.text(
            'Delay results are kept until the next completed test. Test times appear below each node.'),
        findsOneWidget);
    expect(find.text('Available only'), findsOneWidget);
    expect(find.text('Test current profile'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final customHistory in [false, true]) {
    testWidgets(
        'active source: trusted history identifies its test URL: $customHistory',
        (tester) async {
      const key = '0123456789abcdef0123456789abcdef';
      const customUrl = 'https://custom.invalid/probe';
      final directory =
          Directory.systemTemp.createTempSync('node-overview-fallback-');
      final store = NodeHealthStore(
          fileProvider: () async => File('${directory.path}/health.json'),
          debounce: const Duration(hours: 1));
      addTearDown(() {
        expect(
            directory.parent.absolute.path, Directory.systemTemp.absolute.path);
        directory.deleteSync(recursive: true);
      });
      await tester.runAsync(() => store.record(
          profileId: 'a',
          identityKey: key,
          delayMs: 321,
          testUrl: customHistory ? customUrl : defaultTestUrl,
          testedAt: DateTime(2026, 10, 15, 10, 11)));
      globalState.config = globalState.config.copyWith(currentProfileId: 'a');
      globalState.appState = globalState.appState.copyWith(groups: const [
        Group(
            name: 'Custom',
            type: GroupType.Selector,
            hidden: false,
            testUrl: customUrl,
            all: [Proxy(name: 'Live leaf', type: 'Shadowsocks')]),
      ]);
      final container = await mount(tester,
          width: 1200,
          healthStore: store,
          activeCatalog: ProfileCatalog(
              profileId: 'a',
              fingerprint: 'verified-runtime',
              status: ProfileCatalogStatus.ready,
              nodes: [_node(key, 'Live leaf')]));
      final row = find.byKey(const ValueKey('overview-active-Live leaf'));
      expect(find.descendant(of: row, matching: find.text('321 ms')),
          findsOneWidget);
      expect(find.text('1 available / 1 tested / 1 total'), findsOneWidget);
      expect(
          find.descendant(
              of: row, matching: find.textContaining('Independent delay test')),
          customHistory ? findsNothing : findsOneWidget);
      if (customHistory) {
        await tester.tap(find.text('Available only'));
        await tester.pumpAndSettle();
        expect(row, findsOneWidget);
        await tester.tap(find.text('Available only'));
        await tester.pumpAndSettle();
        container
            .read(delayDataSourceProvider.notifier)
            .setDelay(const Delay(name: 'Live leaf', url: customUrl, value: 0));
        await tester.pump();
        expect(
            find.descendant(
                of: row, matching: find.byType(CircularProgressIndicator)),
            findsOneWidget);
        expect(find.descendant(of: row, matching: find.text('321 ms')),
            findsNothing);
        container.read(delayDataSourceProvider.notifier).setDelay(
            const Delay(name: 'Live leaf', url: customUrl, value: 77));
        await tester.pumpAndSettle();
        expect(find.descendant(of: row, matching: find.text('321 ms')),
            findsOneWidget);
        expect(find.text('Median: 321 ms'), findsOneWidget);
      }
    });
  }

  testWidgets('active source: provider history is explicitly a file result',
      (tester) async {
    globalState.config = globalState.config.copyWith(currentProfileId: 'a');
    globalState.appState = globalState.appState.copyWith(groups: const [
      Group(
          name: 'Live',
          type: GroupType.Selector,
          hidden: false,
          testUrl: 'https://group.invalid/probe',
          all: [
            Proxy(name: 'Shared', type: 'Shadowsocks'),
          ]),
    ], delayMap: {
      'https://group.invalid/probe': {'Shared': 42},
    });
    final node = _node('file-provider', 'Shared').copyWith(
        type: 'trojan',
        source: CatalogNodeSource.provider,
        providerName: 'Feed');
    final container = await mount(tester, width: 1200, catalogs: {
      'a': ProfileCatalog(
          profileId: 'a',
          fingerprint: 'file',
          status: ProfileCatalogStatus.ready,
          nodes: [
            node,
            node.copyWith(identityKey: 'not-running', name: 'Not running'),
          ]),
    }, health: {
      'a': {
        'file-provider': NodeHealthRecord(
            delayMs: 80,
            testedAt: DateTime(2026, 10, 15, 10, 11),
            testUrlHash: 'fixture'),
      },
    });
    final row = find.byKey(const ValueKey('overview-active-Shared'));
    expect(
        find.descendant(of: row, matching: find.text('80 ms')), findsOneWidget);
    expect(
        find.descendant(
            of: row,
            matching: find
                .text('trojan · Profile file · Feed · Independent delay test')),
        findsOneWidget);
    expect(find.descendant(of: row, matching: find.textContaining('10:11')),
        findsOneWidget);
    expect(find.text('Median: 80 ms'), findsOneWidget);
    expect(find.text('Not running'), findsNothing);
    expect(container.read(activeNodeCatalogProvider), isNull);
    expect(
        container.read(delayDataSourceProvider)['https://group.invalid/probe']
            ?['Shared'],
        42);
    expect(tester.takeException(), isNull);
  });

  for (final hasRuntimeHistory in [false, true]) {
    testWidgets(
        'active source: verified identity wins over file provider: '
        '$hasRuntimeHistory', (tester) async {
      globalState.config = globalState.config.copyWith(currentProfileId: 'a');
      globalState.appState = globalState.appState.copyWith(groups: const [
        Group(
            name: 'Live',
            type: GroupType.Selector,
            hidden: false,
            all: [Proxy(name: 'Shared', type: 'Shadowsocks')]),
      ], delayMap: {
        defaultTestUrl: {'Shared': 42}
      });
      await mount(tester,
          activeCatalog: ProfileCatalog(
              profileId: 'a',
              fingerprint: 'runtime',
              status: ProfileCatalogStatus.ready,
              nodes: [_node('runtime', 'Shared')]),
          catalogs: {
            'a': ProfileCatalog(
                profileId: 'a',
                fingerprint: 'file',
                status: ProfileCatalogStatus.ready,
                nodes: [
                  _node('file', 'Shared').copyWith(
                      source: CatalogNodeSource.provider, providerName: 'Feed'),
                ]),
          },
          health: {
            'a': {
              'file': NodeHealthRecord(
                  delayMs: 80,
                  testedAt: DateTime(2026, 10, 15, 10, 11),
                  testUrlHash: 'fixture'),
              if (hasRuntimeHistory)
                'runtime': NodeHealthRecord(
                    delayMs: 64,
                    testedAt: DateTime(2026, 10, 15, 9, 10),
                    testUrlHash: 'fixture'),
            },
          });
      final row = find.byKey(const ValueKey('overview-active-Shared'));
      expect(
          find.descendant(
              of: row,
              matching: find.text(hasRuntimeHistory ? '64 ms' : '42 ms')),
          findsOneWidget);
      expect(find.textContaining('Profile file'), findsNothing);
      expect(find.text('80 ms'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final invalid in [
    'inline duplicate',
    'provider duplicate',
    'no history',
    'unparseable',
    'file error',
    'updating'
  ]) {
    testWidgets(
        'active source: rejects ambiguous or unavailable file result: '
        '$invalid', (tester) async {
      globalState.config = globalState.config.copyWith(currentProfileId: 'a');
      globalState.appState = globalState.appState.copyWith(groups: const [
        Group(
            name: 'Live',
            type: GroupType.Selector,
            hidden: false,
            all: [Proxy(name: 'Shared', type: 'Shadowsocks')]),
      ], delayMap: {
        defaultTestUrl: {'Shared': 42}
      });
      final node = _node('file', 'Shared').copyWith(
          source: CatalogNodeSource.provider,
          providerName: 'Feed',
          unsupported: invalid == 'unparseable'
              ? CatalogUnsupportedReason.parseFailed
              : CatalogUnsupportedReason.none);
      await mount(tester, catalogs: {
        'a': ProfileCatalog(
            profileId: 'a',
            fingerprint: 'file',
            status: invalid == 'file error'
                ? ProfileCatalogStatus.fileMissing
                : invalid == 'updating'
                    ? ProfileCatalogStatus.updating
                    : ProfileCatalogStatus.ready,
            nodes: [
              node,
              if (invalid == 'inline duplicate') _node('inline', 'Shared'),
              if (invalid == 'provider duplicate')
                node.copyWith(identityKey: 'other', providerName: 'Other feed'),
            ]),
      }, health: {
        'a': {
          if (invalid != 'no history')
            'file': NodeHealthRecord(
                delayMs: 80,
                testedAt: DateTime(2026, 10, 15, 10, 11),
                testUrlHash: 'fixture'),
        },
      });
      final row = find.byKey(const ValueKey('overview-active-Shared'));
      expect(find.descendant(of: row, matching: find.text('42 ms')),
          findsOneWidget);
      expect(
          find.descendant(
              of: row, matching: find.text('Shadowsocks · Runtime node')),
          findsOneWidget);
      expect(
          find.descendant(of: row, matching: find.textContaining('Last test:')),
          findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('active source: file result drives filtering sorting and summary',
      (tester) async {
    globalState.config = globalState.config.copyWith(currentProfileId: 'a');
    globalState.appState = globalState.appState.copyWith(groups: const [
      Group(name: 'Live', type: GroupType.Selector, hidden: false, all: [
        Proxy(name: 'Failed', type: 'Shadowsocks'),
        Proxy(name: 'Good', type: 'Shadowsocks'),
      ]),
    ], delayMap: {
      defaultTestUrl: {'Failed': 20, 'Good': -1}
    });
    final container = await mount(tester, width: 1200, catalogs: {
      'a': ProfileCatalog(
          profileId: 'a',
          fingerprint: 'file',
          status: ProfileCatalogStatus.ready,
          nodes: [
            for (final name in ['Failed', 'Good'])
              _node(name, name).copyWith(
                  source: CatalogNodeSource.provider, providerName: 'Feed'),
          ]),
    }, health: {
      'a': {
        for (final name in ['Failed', 'Good'])
          name: NodeHealthRecord(
              delayMs: name == 'Good' ? 80 : -1,
              testedAt: DateTime(2026, 10, 15, 10, 11),
              testUrlHash: 'fixture'),
      },
    });
    expect(find.text('1 available / 2 tested / 2 total'), findsOneWidget);
    expect(find.text('Median: 80 ms'), findsOneWidget);
    container.read(proxiesStyleSettingProvider.notifier).updateState(
        (state) => state.copyWith(sortType: ProxiesSortType.delay));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Good')).dy,
        lessThan(tester.getTopLeft(find.text('Failed')).dy));
    await tester.tap(find.text('Available only'));
    await tester.pumpAndSettle();
    expect(find.text('Good'), findsOneWidget);
    expect(find.text('Failed'), findsNothing);
    container.read(proxiesQueryProvider.notifier).value = 'Feed';
    await tester.pumpAndSettle();
    expect(find.text('Good'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final sample in [
    (label: 'new history overrides older live value', live: 42, saved: 80),
    (
      label: 'cancellation does not replace successful history',
      live: -1,
      saved: 42
    ),
    (
      label: 'new failed measurement replaces successful live value',
      live: 42,
      saved: -1
    ),
  ]) {
    testWidgets('active explicit result: ${sample.label}', (tester) async {
      globalState.config = globalState.config.copyWith(currentProfileId: 'a');
      globalState.appState = globalState.appState.copyWith(groups: const [
        Group(
            name: 'Runtime',
            type: GroupType.Selector,
            hidden: false,
            all: [Proxy(name: 'Saved leaf', type: 'Shadowsocks')])
      ], delayMap: {
        defaultTestUrl: {'Saved leaf': sample.live}
      });
      final catalog = ProfileCatalog(
          profileId: 'a',
          fingerprint: 'runtime',
          status: ProfileCatalogStatus.ready,
          nodes: [_node('saved', 'Saved leaf')]);
      final container =
          await mount(tester, width: 1200, activeCatalog: catalog, health: {
        'a': {
          'saved': NodeHealthRecord(
              delayMs: sample.saved,
              testedAt: DateTime(2026, 10, 15, 10, 11),
              testUrlHash: 'fixture')
        }
      });
      final row = find.byKey(const ValueKey('overview-active-Saved leaf'));
      expect(
          find.descendant(
              of: row,
              matching: find.text(
                  sample.saved > 0 ? '${sample.saved} ms' : 'Test failed')),
          findsOneWidget);
      expect(find.descendant(of: row, matching: find.textContaining('10:11')),
          findsOneWidget);
      expect(
          find.text(
              '${sample.saved > 0 ? 1 : 0} available / 1 tested / 1 total'),
          findsOneWidget);
      expect(
          container.read(delayDataSourceProvider)[defaultTestUrl]
              ?['Saved leaf'],
          sample.live);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('P1 test: a single node uses its own profile identity',
      (tester) async {
    final backend = _CatalogTester();
    await mount(tester, catalogTester: backend, catalogs: {
      for (final id in ['a', 'b'])
        id: ProfileCatalog(
            profileId: id,
            fingerprint: 'fixture',
            status: ProfileCatalogStatus.ready,
            nodes: [_node('$id-key', 'Shared name')])
    });
    await tester.tap(find.byKey(const ValueKey('overview-test-b-b-key')));
    await tester.pumpAndSettle();
    expect(backend.batches.single.single.profile.id, 'b');
    expect(backend.batches.single.single.nodes.single.identityKey, 'b-key');
  });

  testWidgets(
      'P1 test: unsupported nodes explain why no test button is available',
      (tester) async {
    await mount(tester, catalogs: {
      'a': ProfileCatalog(
          profileId: 'a',
          fingerprint: 'fixture',
          status: ProfileCatalogStatus.ready,
          nodes: [
            _node('invalid', 'Invalid')
                .copyWith(unsupported: CatalogUnsupportedReason.parseFailed),
            _node('chain', 'Chain').copyWith(
                unsupported: CatalogUnsupportedReason.chainUnsupported),
            _node('type', 'Heavy').copyWith(
                unsupported: CatalogUnsupportedReason.typeUnsupported),
          ])
    });
    expect(find.byTooltip('Test this node'), findsNothing);
    expect(find.text('Proxy chains cannot be tested in isolation'),
        findsOneWidget);
    expect(find.text('This protocol is not supported for isolated tests'),
        findsOneWidget);
    expect(find.text('Node could not be identified'), findsOneWidget);
  });

  testWidgets('raw isolated protocol exclusions are visible before any test',
      (tester) async {
    final catalog = buildProfileCatalog(
      profileId: 'a',
      fingerprint: '',
      isolatedTest: true,
      raw: {
        'proxies': [
          {
            'name': 'Supported',
            'type': 'vless',
            'server': 'fixture.invalid',
            'port': 443
          },
          {
            'name': 'Heavy',
            'type': 'tuic',
            'server': 'fixture.invalid',
            'port': 443
          },
          {
            'name': 'Mux',
            'type': 'ss',
            'server': 'fixture.invalid',
            'port': 443,
            'SMUX': {'enabled': false}
          },
          {
            'name': 'Chain',
            'type': 'ss',
            'server': 'fixture.invalid',
            'port': 443,
            'dialer_proxy': 'upstream'
          },
        ]
      },
    );
    final backend = _CatalogTester();
    await mount(tester,
        width: 1200, catalogs: {'a': catalog}, catalogTester: backend);
    expect(find.byTooltip('Test this node'), findsOneWidget);
    expect(find.text('This protocol is not supported for isolated tests'),
        findsNWidgets(2));
    expect(find.text('Proxy chains cannot be tested in isolation'),
        findsOneWidget);
    for (final name in ['Supported', 'Heavy', 'Mux', 'Chain']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(backend.batches, isEmpty);
  });

  testWidgets('P1 test: current profile batch keeps all group URL semantics',
      (tester) async {
    final backend = _CatalogTester();
    globalState.config = globalState.config.copyWith(currentProfileId: 'a');
    globalState.appState = globalState.appState.copyWith(groups: const [
      Group(
          name: 'First',
          type: GroupType.Selector,
          hidden: false,
          testUrl: 'https://first.invalid',
          all: [Proxy(name: 'Live', type: 'Shadowsocks')]),
      Group(
          name: 'Second',
          type: GroupType.Selector,
          hidden: false,
          all: [Proxy(name: 'Live', type: 'Shadowsocks')]),
    ]);
    await mount(tester, catalogTester: backend);
    await tester.tap(find.text('Test current profile'));
    await tester.pumpAndSettle();
    expect(backend.current.single.map((t) => (t.name, t.url, t.scope)), [
      ('Live', 'https://first.invalid', null),
      ('Live', defaultTestUrl, null),
    ]);
    expect(backend.batches, isEmpty);
    expect(find.textContaining('Profiles with issues'), findsNothing);
  });

  testWidgets(
      'current profile tests the sidebar selection instead of the active profile',
      (tester) async {
    final backend = _CatalogTester();
    globalState.config = globalState.config.copyWith(currentProfileId: 'a');
    globalState.appState = globalState.appState.copyWith(groups: const [
      Group(
          name: 'Live group',
          type: GroupType.Selector,
          hidden: false,
          all: [Proxy(name: 'Live', type: 'Shadowsocks')]),
    ]);
    final container = await mount(tester,
        width: 1200, catalogs: flatCatalogs(), catalogTester: backend);
    await tester.tap(find.byKey(const ValueKey('overview-select-b')));
    await tester.pumpAndSettle();
    container.read(proxiesQueryProvider.notifier).state = 'no matching rows';
    await tester.tap(find.text('Available only'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('overview-test-current')));
    await tester.pumpAndSettle();
    expect(backend.all.single.map((profile) => profile.id), ['b']);
    expect(backend.current, isEmpty);
    expect(backend.batches, isEmpty);
  });

  testWidgets(
      'current profile tests the dropdown selection without live groups',
      (tester) async {
    final backend = _CatalogTester();
    await mount(tester, catalogs: flatCatalogs(), catalogTester: backend);
    await tester.tap(find.byKey(const ValueKey('overview-profile-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beta profile').last);
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('overview-test-current'));
    expect(tester.widget<TextButton>(button).onPressed, isNotNull);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(backend.all.single.map((profile) => profile.id), ['b']);
    expect(backend.current, isEmpty);
  });

  testWidgets(
      'P1 test: shared progress disables start controls and cancel remains usable',
      (tester) async {
    final backend = _CatalogTester();
    await mount(tester, catalogTester: backend, catalogs: flatCatalogs());
    backend.pendingKeys.add(('b', 'b-node'));
    backend.progress(done: 3, count: 8);
    await tester.pump();
    expect(find.text('3 / 8'), findsOneWidget);
    expect(
        tester
            .widget<TextButton>(
                find.widgetWithText(TextButton, 'Test all node delays'))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<IconButton>(
                find.byKey(const ValueKey('overview-test-a-a-node')))
            .onPressed,
        isNull);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('overview-node-b-b-node')),
            matching: find.byType(CircularProgressIndicator)),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('overview-cancel')));
    await tester.pumpAndSettle();
    expect(backend.cancellations, 1);
    expect(backend.batches, isEmpty);
    expect(find.text('3 / 8'), findsNothing);
  });

  testWidgets('P1 test: leaving overview disposes only its owned scope',
      (tester) async {
    final backend = _CatalogTester();
    await mount(tester, catalogTester: backend);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(backend.scopeDisposals, 1);
    expect(backend.cancellations, 0);
  });

  testWidgets('P1 test: rejected isolated test shows a localized reason',
      (tester) async {
    final backend = _CatalogTester()..reason = 'strictModeUnsupported';
    await mount(tester, catalogTester: backend, catalogs: flatCatalogs());
    await tester.tap(find.byKey(const ValueKey('overview-test-b-b-node')));
    await tester.pumpAndSettle();
    expect(find.text('Isolated tests are unavailable in strict mode'),
        findsOneWidget);
    expect(find.text('strictModeUnsupported'), findsNothing);
  });

  testWidgets('P1 flat: all profiles show nodes without accordion interactions',
      (tester) async {
    await mount(tester, width: 1200, catalogs: flatCatalogs());
    expect(find.text('Alpha node'), findsOneWidget);
    expect(find.text('Beta node'), findsOneWidget);
    final body = find.byKey(const ValueKey('overview-nodes'));
    expect(find.descendant(of: body, matching: find.byIcon(Icons.expand_more)),
        findsNothing);
    expect(find.descendant(of: body, matching: find.byIcon(Icons.expand_less)),
        findsNothing);
    expect(find.byType(SliverPersistentHeader), findsNWidgets(2));
    expect(
        tester
            .widgetList<SliverPersistentHeader>(
                find.byType(SliverPersistentHeader))
            .every((header) => header.pinned),
        isTrue);
  });

  testWidgets('P1 flat: sidebar selection shows only one plain node list',
      (tester) async {
    await mount(tester, width: 1200, catalogs: flatCatalogs());
    await tester.tap(find.byKey(const ValueKey('overview-select-b')));
    await tester.pumpAndSettle();
    expect(find.text('Beta node'), findsOneWidget);
    expect(find.text('Alpha node'), findsNothing);
    final body = find.byKey(const ValueKey('overview-nodes'));
    expect(find.descendant(of: body, matching: find.text('Beta profile')),
        findsNothing);
    expect(find.byType(SliverPersistentHeader), findsNothing);
  });

  testWidgets('P1 flat: profile heading stays pinned while its rows scroll',
      (tester) async {
    await mount(tester, width: 1200, catalogs: {
      'a': ProfileCatalog(
          profileId: 'a',
          fingerprint: 'fixture',
          status: ProfileCatalogStatus.ready,
          nodes: List.generate(30, (i) => _node('a-$i', 'Alpha $i'))),
    });
    final header = find.byKey(const ValueKey('overview-header-a'));
    final top = tester.getTopLeft(header).dy;
    await tester.drag(
        find.byKey(const ValueKey('overview-nodes')), const Offset(0, -450));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(header).dy, top);
    expect(find.text('Alpha 0'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('P1 flat: narrow profile selector filters without folding',
      (tester) async {
    await mount(tester, width: 400, catalogs: flatCatalogs());
    final selector = find.byKey(const ValueKey('overview-profile-filter'));
    expect(selector, findsOneWidget);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beta profile').last);
    await tester.pumpAndSettle();
    expect(find.text('Beta node'), findsOneWidget);
    expect(find.text('Alpha node'), findsNothing);
    expect(find.byType(SliverPersistentHeader), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('P1 flat: narrow parent constraints override wide app width',
      (tester) async {
    final container = await mount(tester,
        width: 1200,
        catalogs: flatCatalogs(),
        child: const Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 400, child: NodeOverviewView())));
    expect(container.read(viewWidthProvider), 1200);
    expect(find.byKey(const ValueKey('overview-sidebar')), findsNothing);
    final selector = find.byKey(const ValueKey('overview-profile-filter'));
    expect(selector, findsOneWidget);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beta profile').last);
    await tester.pumpAndSettle();
    expect(find.text('Beta node'), findsOneWidget);
    expect(find.text('Alpha node'), findsNothing);
    expect(find.byType(SliverPersistentHeader), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'P1 flat: active leaves are unique read-only rows using first URL',
      (tester) async {
    final controller = _ProxyController();
    globalState.appController = controller;
    globalState.config = globalState.config.copyWith(currentProfileId: 'a');
    const leaf = Proxy(name: 'Unique leaf', type: 'Shadowsocks');
    globalState.appState = globalState.appState.copyWith(
      groups: const [
        Group(
            name: 'First group',
            type: GroupType.Selector,
            hidden: false,
            testUrl: 'https://first.invalid',
            all: [
              leaf,
              Proxy(name: 'DIRECT', type: 'Direct'),
              Proxy(name: 'Other group', type: 'Selector')
            ]),
        Group(
            name: 'Other group',
            type: GroupType.URLTest,
            hidden: false,
            testUrl: 'https://second.invalid',
            all: [leaf]),
      ],
      delayMap: {
        'https://first.invalid': {'Unique leaf': 123},
        'https://second.invalid': {'Unique leaf': 999},
      },
    );
    await mount(tester);
    expect(find.byType(ProxyCard), findsNothing);
    expect(find.text('Unique leaf'), findsOneWidget);
    expect(find.text('123 ms'), findsOneWidget);
    expect(find.text('999 ms'), findsNothing);
    expect(find.text('First group'), findsNothing);
    expect(find.text('Other group'), findsNothing);
    await tester.tap(find.text('Unique leaf'));
    expect(controller.changes, isEmpty);
    expect(controller.selections, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final width in [400.0, 1200.0]) {
    testWidgets('visible profiles load lazily at width $width', (tester) async {
      final loaded = <String>[];
      final profiles =
          List.generate(40, (i) => _a.copyWith(id: 'p$i', label: 'Profile $i'));
      final catalogs = {
        for (final profile in profiles)
          profile.id: ProfileCatalog(
              profileId: profile.id,
              fingerprint: 'fixture',
              status: ProfileCatalogStatus.ready,
              nodes: [_node('${profile.id}-node', 'Node ${profile.id}')]),
      };
      await mount(tester,
          width: width,
          profiles: profiles,
          catalogs: catalogs,
          onLoad: loaded.add,
          health: {
            'p0': {
              'p0-node': NodeHealthRecord(
                  delayMs: 88, testedAt: DateTime.now(), testUrlHash: 'fixture')
            },
          });
      expect(loaded, contains('p0'));
      expect(loaded.length, lessThan(profiles.length));
      if (width > 840) {
        expect(find.text('1 available / 1 tested / 1 total'), findsOneWidget);
      }
      expect(find.text('Node p0'), findsOneWidget);
      final scroller = find
          .byKey(ValueKey(width > 840 ? 'overview-sidebar' : 'overview-nodes'));
      final firstCount = loaded.length;
      await tester.drag(scroller, const Offset(0, -1500));
      await tester.pumpAndSettle();
      expect(loaded.length, greaterThan(firstCount));
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [320.0, 1200.0]) {
    testWidgets(
        'review: scope selector belongs to the existing app bar at width $width',
        (tester) async {
      globalState.appState =
          globalState.appState.copyWith(pageLabel: PageLabel.proxies);
      await mount(tester,
          width: width, child: const ProxiesView(), appBarScaffold: true);
      final inBar = find.descendant(
          of: find.byType(AppBar),
          matching: width > 840
              ? find.text('Current profile')
              : find.byTooltip('Current profile'));
      expect(inBar, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'review: invalid node remains visible without usable historical health',
      (tester) async {
    final invalid = _node('invalid-node', 'Invalid node')
        .copyWith(unsupported: CatalogUnsupportedReason.parseFailed);
    await mount(tester, width: 1200, catalogs: {
      'a': ProfileCatalog(
          profileId: 'a',
          fingerprint: '',
          status: ProfileCatalogStatus.ready,
          nodes: [invalid, _node('good', 'Good node')]),
    }, health: {
      'a': {
        'invalid-node': NodeHealthRecord(
            delayMs: 123, testedAt: DateTime.now(), testUrlHash: 'fixture')
      }
    });
    expect(find.text('Node could not be identified'), findsOneWidget);
    expect(find.text('123 ms'), findsNothing);
    expect(find.text('0 available / 0 tested / 1 total'), findsOneWidget);
    await tester.tap(find.text('Available only'));
    await tester.pumpAndSettle();
    expect(find.text('Invalid node'), findsNothing);
  });

  testWidgets(
      'review: active source does not infer inline ownership from a disk catalog',
      (tester) async {
    globalState.config = globalState.config.copyWith(currentProfileId: 'a');
    globalState.lastRuntimeConfig = null;
    globalState.lastRuntimeProfileId = null;
    globalState.appState = globalState.appState.copyWith(groups: const [
      Group(
          name: 'Live',
          type: GroupType.Selector,
          hidden: false,
          all: [Proxy(name: 'Shared name', type: 'Shadowsocks')]),
    ]);
    await mount(tester, catalogs: {
      'a': ProfileCatalog(
          profileId: 'a',
          fingerprint: 'new-disk',
          status: ProfileCatalogStatus.ready,
          nodes: [_node('new', 'Shared name')]),
    });
    expect(find.textContaining('Runtime node'), findsOneWidget);
    expect(find.textContaining('Inline'), findsNothing);
  });

  testWidgets('scope is hidden for one profile and when disabled',
      (tester) async {
    const scope =
        NodeOverviewScopeView(currentView: Text('Existing proxy view'));
    await mount(tester, child: scope, profiles: [_a], scopeToolbar: true);
    expect(find.text('All profiles'), findsNothing);
    expect(find.text('Existing proxy view'), findsOneWidget);
    await mount(tester, child: scope, enabled: false, scopeToolbar: true);
    expect(find.text('All profiles'), findsNothing);
    expect(find.text('Existing proxy view'), findsOneWidget);
  });

  testWidgets('trusted runtime catalog supplies active node source and time',
      (tester) async {
    globalState.config = globalState.config.copyWith(currentProfileId: 'a');
    globalState.appState = globalState.appState.copyWith(groups: const [
      Group(
          name: 'Live',
          type: GroupType.Selector,
          hidden: false,
          all: [Proxy(name: 'Shared name', type: 'Shadowsocks')]),
    ]);
    await mount(tester,
        activeCatalog: ProfileCatalog(
            profileId: 'a',
            fingerprint: 'verified-runtime',
            status: ProfileCatalogStatus.ready,
            nodes: [
              _node('runtime-key', 'Shared name').copyWith(
                  source: CatalogNodeSource.provider,
                  providerName: 'Verified provider')
            ]),
        catalogs: {
          'a': ProfileCatalog(
              profileId: 'a',
              fingerprint: 'different-disk',
              status: ProfileCatalogStatus.ready,
              nodes: [_node('new-key', 'Shared name')]),
        },
        health: {
          'a': {
            'runtime-key': NodeHealthRecord(
                delayMs: 88, testedAt: DateTime.now(), testUrlHash: 'fixture')
          }
        });
    expect(find.textContaining('Verified provider'), findsOneWidget);
    expect(find.textContaining('Inline'), findsNothing);
    expect(find.textContaining('Runtime node'), findsNothing);
    expect(find.textContaining('Last test:'), findsWidgets);
  });

  testWidgets('explicit search loads profiles outside both viewports',
      (tester) async {
    final loaded = <String>[];
    final profiles =
        List.generate(40, (i) => _a.copyWith(id: 'p$i', label: 'Profile $i'));
    final container = await mount(tester,
        width: 1200,
        profiles: profiles,
        onLoad: loaded.add,
        catalogs: {
          for (final profile in profiles)
            profile.id: ProfileCatalog(
                profileId: profile.id,
                fingerprint: 'fixture',
                status: ProfileCatalogStatus.ready,
                nodes: [_node('${profile.id}-node', 'Needle ${profile.id}')]),
        });
    expect(loaded, isNot(contains('p39')));
    container.read(proxiesQueryProvider.notifier).value = 'needle';
    await tester.pumpAndSettle();
    expect(loaded.toSet(), profiles.map((p) => p.id).toSet());
    container.read(proxiesQueryProvider.notifier).value = '';
    await tester.pumpAndSettle();
    expect(find.text('Needle p0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('health band uses node color scale at the 600 ms boundary',
      (tester) async {
    final now = DateTime.now();
    await mount(tester, width: 1200, catalogs: {
      'a': ProfileCatalog(
          profileId: 'a',
          fingerprint: 'fixture',
          status: ProfileCatalogStatus.ready,
          nodes: [
            _node('fast', 'Fast'),
            _node('slow', 'Slow'),
            _node('failed', 'Failed'),
            _node('untested', 'Untested')
          ]),
    }, health: {
      'a': {
        for (final entry in {'fast': 599, 'slow': 600, 'failed': -1}.entries)
          entry.key: NodeHealthRecord(
              delayMs: entry.value, testedAt: now, testUrlHash: 'fixture')
      },
    });
    final bands = tester
        .widgetList<Container>(find.descendant(
            of: find.byKey(const ValueKey('overview-select-a')),
            matching: find.byType(Container)))
        .where((container) => container.constraints?.maxHeight == 5)
        .toList();
    expect(bands, hasLength(4));
    expect(bands.take(3).map((band) => band.color), [
      utils.getDelayColor(599),
      utils.getDelayColor(600),
      utils.getDelayColor(-1),
    ]);
    expect(find.text('2 available / 3 tested / 4 total'), findsOneWidget);
  });

  testWidgets(
      'defaults to existing view; opening overview loads visible profiles',
      (tester) async {
    final loaded = <String>[];
    final container = await mount(tester,
        child: const NodeOverviewScopeView(
            currentView: Text('Existing proxy view')),
        scopeToolbar: true,
        onLoad: loaded.add);
    expect(find.text('Existing proxy view'), findsOneWidget);
    await selectScope(tester, 'All profiles');
    expect(find.text('Alpha profile'), findsOneWidget);
    expect(loaded, containsAll(['a', 'b']));
    expect(container.read(currentProfileIdProvider), isNull);
    expect(loaded, ['a', 'b']);
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
    expect(find.text('Same node'), findsNWidgets(2));
    expect(find.text('123 ms'), findsOneWidget);
    expect(find.text('456 ms'), findsOneWidget);
    expect(find.textContaining('May be outdated'), findsWidgets);
    for (final id in ['a', 'b']) {
      expect(
          find.descendant(
              of: find.byKey(ValueKey('overview-node-$id-$id-node')),
              matching: find.textContaining('Last test:')),
          findsOneWidget);
    }
    expect(find.textContaining('Last active test'), findsNothing);
    await tester.tap(find.text('Same node').last);
    await tester.pump();
    expect(container.read(currentProfileIdProvider), isNull);
    expect(container.read(delayDataSourceProvider), isEmpty);
    expect(find.byType(ProxyCard), findsNothing);
  });

  testWidgets('inactive isolated result uses neutral last-test time',
      (tester) async {
    final directory =
        Directory.systemTemp.createTempSync('node-overview-isolated-time-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final store = NodeHealthStore(
        fileProvider: () async => File('${directory.path}/health.json'),
        debounce: const Duration(hours: 1));
    final node = catalogNodeFromMap(profileId: 'b', proxy: {
      'name': 'Isolated result',
      'type': 'ss',
      'server': 'fixture.invalid',
      'port': 443,
    }).copyWith(coreIndex: 0);
    final catalog = ProfileCatalog(
        profileId: 'b',
        fingerprint: '',
        status: ProfileCatalogStatus.ready,
        coreCatalogId: 'c-time-fixture',
        nodes: [node]);
    store.bindCatalog(catalog);
    final target = store.beginCatalogTest(
        catalogId: catalog.coreCatalogId!,
        nodeIndex: 0,
        identityKey: node.identityKey,
        testUrl: defaultTestUrl)!;
    await tester.runAsync(() => store.finishCatalogTest(target, 42));
    store.unbindCatalog(catalog.coreCatalogId!);
    final container =
        await mount(tester, catalogs: {'b': catalog}, healthStore: store);
    final row = find.byKey(ValueKey('overview-node-b-${node.identityKey}'));
    expect(
        find.descendant(of: row, matching: find.text('42 ms')), findsOneWidget);
    expect(
        find.descendant(of: row, matching: find.textContaining('Last test:')),
        findsOneWidget);
    expect(find.textContaining('Last active test'), findsNothing);
    expect(container.read(currentProfileIdProvider), isNull);
    expect(container.read(delayDataSourceProvider), isEmpty);
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
      'wide sidebar loads visible summaries and selection remains read only',
      (tester) async {
    final loaded = <String>[];
    await mount(tester, width: 1200, onLoad: loaded.add);
    expect(find.byKey(const ValueKey('overview-sidebar')), findsOneWidget);
    expect(loaded, containsAll(['a', 'b']));
    await tester.tap(find.byKey(const ValueKey('overview-select-b')));
    await tester.pumpAndSettle();
    expect(loaded, ['a', 'b']);
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
    expect(find.text('Profile file is missing'), findsOneWidget);
    expect(find.text('Profile could not be parsed'), findsOneWidget);
    expect(find.text('Subscription expired'), findsWidgets);
    expect(find.text('Updating subscription'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('active flat list omits nested groups and repeats no leaf',
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
    expect(find.byType(ProxyCard), findsNothing);
    expect(find.text('Live leaf'), findsOneWidget);
    expect(find.text('Nested'), findsNothing);
    expect(find.text('One'), findsNothing);
    expect(find.text('Two'), findsNothing);
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
    final container = await mount(tester,
        child: const ProxiesView(),
        appBarScaffold: true,
        profiles: [
          _a.copyWith(unfoldSet: {'Select'}),
          _b
        ]);
    expect(find.byType(NodeOverviewView), findsNothing);
    await selectScope(tester, 'All profiles');
    expect(container.read(currentProfileIdProvider), 'a');
    expect(container.read(currentGroupsStateProvider).value, isNotEmpty);
    expect(find.byType(NodeOverviewView), findsOneWidget);
    await tester.tap(find.text('Selectable leaf', findRichText: true));
    await tester.pump();
    expect(controller.changes, isEmpty);
    expect(controller.selections, isEmpty);
    await selectScope(tester, 'Current profile');
    expect(find.byType(NodeOverviewView), findsNothing);
    await tester.tap(find.text('Selectable leaf', findRichText: true));
    await tester.pump();
    expect(controller.changes, [('Select', 'Selectable leaf')]);
    expect(controller.selections, [('Select', 'Selectable leaf')]);
    expect(container.read(currentProfileIdProvider), 'a');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'search and clearing keep matching nodes visible without expansion',
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
    expect(loaded, containsAll(['a', 'b']));
    container.read(proxiesQueryProvider.notifier).value = 'needle';
    await tester.pumpAndSettle();
    expect(loaded, containsAll(['a', 'b']));
    expect(find.text('Needle Alpha'), findsOneWidget);
    expect(find.text('Needle Beta'), findsOneWidget);
    container.read(proxiesQueryProvider.notifier).value = '';
    await tester.pumpAndSettle();
    expect(find.text('Needle Alpha'), findsOneWidget);
    expect(find.text('Needle Beta'), findsOneWidget);
  });

  testWidgets(
      'wide search respects selected profile and All restores cross-profile search',
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
    expect(find.text('Needle Alpha'), findsNothing);
    expect(find.text('Needle Beta'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('overview-select-all')));
    await tester.pumpAndSettle();
    expect(find.text('Needle Alpha'), findsOneWidget);
    expect(find.text('Needle Beta'), findsOneWidget);
    container.read(proxiesQueryProvider.notifier).value = '';
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('overview-header-a')), findsOneWidget);
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
    await mount(tester, width: 1200);
    expect(find.text('1 available / 1 tested / 1 total'), findsOneWidget);
    expect(find.text('Median: 321 ms'), findsOneWidget);
    expect(find.text('321 ms'), findsOneWidget);
    expect(find.text('Test failed'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('active live summary remains visible alongside disk errors',
      (tester) async {
    globalState.config = globalState.config.copyWith(currentProfileId: 'a');
    globalState.appState = globalState.appState.copyWith(
      groups: const [
        Group(
            name: 'Live',
            type: GroupType.Selector,
            hidden: false,
            all: [Proxy(name: 'Live leaf', type: 'Shadowsocks')])
      ],
      delayMap: {
        defaultTestUrl: {'Live leaf': 88}
      },
    );
    for (final entry in {
      ProfileCatalogStatus.fileMissing: 'Profile file is missing',
      ProfileCatalogStatus.parseFailed: 'Profile could not be parsed',
    }.entries) {
      await mount(tester, width: 1200, catalogs: {
        'a': ProfileCatalog(profileId: 'a', fingerprint: '', status: entry.key),
      });
      expect(find.text(entry.value), findsNWidgets(2));
      expect(find.text('1 available / 1 tested / 1 total'), findsOneWidget);
      expect(find.text('Median: 88 ms'), findsOneWidget);
      expect(find.text('88 ms'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  for (final customHistory in [false, true]) {
    testWidgets(
        'active source: newest URL history and first-group summary: '
        '${customHistory ? 'custom' : 'default'} history', (tester) async {
      const key = '0123456789abcdef0123456789abcdef';
      const customUrl = 'https://custom.invalid/probe';
      final oldTime = DateTime(2026, 10, 15, 8, 9);
      final customTime = DateTime(2026, 10, 15, 10, 11);
      final directory =
          Directory.systemTemp.createTempSync('node-overview-url-');
      final store = NodeHealthStore(
          fileProvider: () async => File('${directory.path}/health.json'),
          now: () => customTime,
          debounce: const Duration(hours: 1));
      addTearDown(() {
        expect(
            directory.parent.absolute.path, Directory.systemTemp.absolute.path);
        directory.deleteSync(recursive: true);
      });
      await tester.runAsync(() => store.record(
          profileId: 'a',
          identityKey: key,
          delayMs: customHistory ? 88 : 321,
          testUrl: customHistory ? defaultTestUrl : customUrl,
          testedAt: oldTime));
      await tester.runAsync(() => store.record(
          profileId: 'a',
          identityKey: key,
          delayMs: customHistory ? 321 : 88,
          testUrl: customHistory ? customUrl : defaultTestUrl,
          testedAt: customTime));
      globalState.config = globalState.config.copyWith(currentProfileId: 'a');
      globalState.appState = globalState.appState.copyWith(groups: const [
        Group(
            name: 'Custom',
            type: GroupType.Selector,
            hidden: false,
            testUrl: customUrl,
            all: [Proxy(name: 'Live leaf', type: 'Shadowsocks')]),
        Group(
            name: 'Default',
            type: GroupType.Selector,
            hidden: false,
            all: [Proxy(name: 'Live leaf', type: 'Shadowsocks')]),
      ], delayMap: {
        customUrl: {'Live leaf': 321},
        defaultTestUrl: {'Live leaf': 88},
      });
      await mount(tester,
          width: 1200,
          healthStore: store,
          activeCatalog: ProfileCatalog(
              profileId: 'a',
              fingerprint: 'verified-runtime',
              status: ProfileCatalogStatus.ready,
              nodes: [_node(key, 'Live leaf')]));
      final row = find.byKey(const ValueKey('overview-active-Live leaf'));
      final summary = find.byKey(const ValueKey('overview-select-a'));
      final customTimes = find.textContaining('10:11');
      final defaultTimes = find.textContaining('8:09');
      expect(find.descendant(of: row, matching: defaultTimes), findsNothing);
      expect(
          find.descendant(of: summary, matching: defaultTimes), findsNothing);
      expect(find.descendant(of: row, matching: customTimes), findsOneWidget);
      expect(
          find.descendant(of: summary, matching: customTimes), findsOneWidget);
      expect(defaultTimes, findsNothing);
      expect(
          find.descendant(
              of: row, matching: find.textContaining('Independent delay test')),
          customHistory ? findsNothing : findsOneWidget);
      expect(find.text('1 available / 1 tested / 1 total'), findsOneWidget);
      expect(find.text(customHistory ? 'Median: 321 ms' : 'Median: 88 ms'),
          findsOneWidget);
      expect(find.text(customHistory ? '321 ms' : '88 ms'), findsOneWidget);
      expect(find.text(customHistory ? '88 ms' : '321 ms'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [400.0, 1200.0]) {
    testWidgets('cached errors and expiry remain visible at width $width',
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
      expect(loaded, containsAll(['a', 'b']));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      '2001-node real projections retain the last active node history in search',
      (tester) async {
    final raw = <String, dynamic>{
      'proxies': List.generate(
          2001,
          (i) => {
                'name': 'Node $i',
                'type': 'ss',
                'server': 'node-$i.invalid',
                'port': 443,
                'cipher': 'aes-128-gcm',
                'password': 'synthetic-fixture',
              }),
    };
    final fileCatalog = buildProfileCatalog(
        profileId: 'a', fingerprint: 'file', raw: raw, isolatedTest: true);
    final runtimeCatalog = buildProfileCatalog(
        profileId: 'a', fingerprint: 'verified-runtime', raw: raw);
    expect(fileCatalog.nodes, hasLength(2001));
    expect(runtimeCatalog.nodes, hasLength(2001));
    expect(fileCatalog.nodes.last.identityKey,
        runtimeCatalog.nodes.last.identityKey);
    final directory =
        Directory.systemTemp.createTempSync('node-overview-large-history-');
    final store = NodeHealthStore(
        fileProvider: () async => File('${directory.path}/health.json'),
        debounce: const Duration(hours: 1));
    addTearDown(() {
      expect(
          directory.parent.absolute.path, Directory.systemTemp.absolute.path);
      directory.deleteSync(recursive: true);
    });
    await tester.runAsync(() => store.record(
        profileId: 'a',
        identityKey: runtimeCatalog.nodes.last.identityKey,
        delayMs: 246,
        testUrl: defaultTestUrl,
        testedAt: DateTime(2026, 10, 15, 10, 11)));
    globalState.config = globalState.config.copyWith(currentProfileId: 'a');
    globalState.appState = globalState.appState.copyWith(groups: [
      Group(
          name: 'Live',
          type: GroupType.Selector,
          hidden: false,
          all: List.generate(
              2001, (i) => Proxy(name: 'Node $i', type: 'Shadowsocks'))),
    ]);
    final container = await mount(tester,
        width: 1200,
        catalogs: {'a': fileCatalog},
        activeCatalog: runtimeCatalog,
        healthStore: store);
    expect(find.text('Node 2000'), findsNothing);
    container.read(proxiesQueryProvider.notifier).value = 'Node 2000';
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('overview-active-Node 2000'));
    expect(row, findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('246 ms')),
        findsOneWidget);
    expect(find.descendant(of: row, matching: find.textContaining('10:11')),
        findsOneWidget);
    expect(find.text('1 available / 1 tested / 2001 total'), findsOneWidget);
    expect(find.text('Profile could not be parsed'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'large flat catalogs only build viewport rows and show provider limitation',
      (tester) async {
    await mount(tester, width: 1200, catalogs: {
      'a': ProfileCatalog(
          profileId: 'a',
          fingerprint: '',
          status: ProfileCatalogStatus.ready,
          nodes: List.generate(2000, (i) => _node('key-$i', 'Node $i')),
          providerNodeCounts: const {'Provider QA': -1}),
    });
    expect(find.text('Node 0'), findsOneWidget);
    expect(find.text('Node 1999'), findsNothing);
    expect(find.text('Summary includes loaded nodes only'), findsOneWidget);
    expect(
        find.textContaining('Node ').evaluate().length, lessThanOrEqualTo(20));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'one-click use: active profile switches proxy in first Selector group without profile reload and updates In use state',
      (tester) async {
    final controller = _ProxyController();
    globalState.appController = controller;
    globalState.config = globalState.config.copyWith(
      currentProfileId: 'a',
      profiles: [
        _a.copyWith(selectedMap: const {'Primary Select': 'Leaf 1'}),
        _b,
      ],
    );
    const leaf1 = Proxy(name: 'Leaf 1', type: 'Shadowsocks');
    const leaf2 = Proxy(name: 'Leaf 2', type: 'Shadowsocks');
    globalState.appState = globalState.appState.copyWith(
      groups: const [
        Group(
            name: 'Auto First',
            type: GroupType.URLTest,
            hidden: false,
            testUrl: 'https://auto.invalid',
            all: [leaf1, leaf2]),
        Group(
            name: 'Primary Select',
            type: GroupType.Selector,
            hidden: false,
            testUrl: 'https://select.invalid',
            now: 'Leaf 1',
            all: [leaf1, leaf2]),
        Group(
            name: 'Secondary Select',
            type: GroupType.Selector,
            hidden: false,
            all: [leaf1, leaf2]),
      ],
    );
    final container = await mount(
      tester,
      width: 1200,
      profiles: [
        _a.copyWith(selectedMap: const {'Primary Select': 'Leaf 1'}),
        _b,
      ],
    );

    final useLeaf1 = find.byKey(const ValueKey('overview-use-a-Leaf 1'));
    final useLeaf2 = find.byKey(const ValueKey('overview-use-a-Leaf 2'));
    expect(useLeaf1, findsOneWidget);
    expect(useLeaf2, findsOneWidget);
    expect(tester.widget<TextButton>(useLeaf1).onPressed, isNull);
    expect(
      find.descendant(of: useLeaf1, matching: find.text('In use')),
      findsOneWidget,
    );
    expect(tester.widget<TextButton>(useLeaf2).onPressed, isNotNull);
    expect(
      find.descendant(of: useLeaf2, matching: find.text('Use')),
      findsOneWidget,
    );

    await tester.tap(useLeaf2);
    await tester.pumpAndSettle();

    expect(container.read(currentProfileIdProvider), 'a');
    expect(controller.selections, [('Primary Select', 'Leaf 2')]);
    expect(controller.changes, [('Primary Select', 'Leaf 2')]);
    expect(
      container.read(profilesProvider).getProfile('a')?.selectedMap,
      {'Primary Select': 'Leaf 2'},
    );
    expect(
      container.read(profilesProvider).getProfile('a')?.currentGroupName,
      'Primary Select',
    );
    expect(tester.widget<TextButton>(useLeaf2).onPressed, isNull);
    expect(
      find.descendant(of: useLeaf2, matching: find.text('In use')),
      findsOneWidget,
    );
    expect(tester.widget<TextButton>(useLeaf1).onPressed, isNotNull);
    expect(
      find.descendant(of: useLeaf1, matching: find.text('Use')),
      findsOneWidget,
    );
    expect(find.text('Switched to Alpha profile · Leaf 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'one-click use: inactive profile cancels running test, writes first select group, and switches currentProfileId immediately',
      (tester) async {
    final backend = _CatalogTester();
    globalState.lastRuntimeProfileId = 'a';
    globalState.config = globalState.config.copyWith(currentProfileId: 'a');
    globalState.appState = globalState.appState.copyWith(
      groups: const [
        Group(
            name: 'Alpha Select',
            type: GroupType.Selector,
            hidden: false,
            now: 'Alpha live',
            all: [Proxy(name: 'Alpha live', type: 'Shadowsocks')]),
      ],
    );
    final container = await mount(
      tester,
      width: 1200,
      catalogTester: backend,
      catalogs: {
        'a': ProfileCatalog(
            profileId: 'a',
            fingerprint: 'fa',
            status: ProfileCatalogStatus.ready,
            nodes: [
              _node('a-1', 'Alpha live')
                  .copyWith(selectGroups: const ['Alpha Select']),
            ]),
        'b': ProfileCatalog(
            profileId: 'b',
            fingerprint: 'fb',
            status: ProfileCatalogStatus.ready,
            nodes: [
              _node('b-1', 'Beta fast').copyWith(
                  selectGroups: const ['GLOBAL', 'Beta Primary', 'Beta Backup']),
              _node('b-2', 'Beta other')
                  .copyWith(selectGroups: const ['Beta Primary']),
            ]),
      },
    );

    backend.progress(done: 1, count: 4);
    await tester.pump();
    expect(backend.busy, isTrue);

    final useBeta1 = find.byKey(const ValueKey('overview-use-b-b-1'));
    final useBeta2 = find.byKey(const ValueKey('overview-use-b-b-2'));
    expect(tester.widget<TextButton>(useBeta1).onPressed, isNotNull);
    await tester.tap(useBeta1);
    await tester.pumpAndSettle();

    expect(backend.cancellations, 1);
    expect(container.read(currentProfileIdProvider), 'b');
    final updatedBeta = container.read(profilesProvider).getProfile('b')!;
    expect(updatedBeta.selectedMap['Beta Primary'], 'Beta fast');
    expect(updatedBeta.currentGroupName, 'Beta Primary');
    expect(find.text('Switched to Beta profile · Beta fast'), findsNothing);
    expect(tester.widget<TextButton>(useBeta1).onPressed, isNotNull);
    expect(
      find.descendant(of: useBeta1, matching: find.text('Use')),
      findsOneWidget,
    );
    expect(tester.widget<TextButton>(useBeta2).onPressed, isNotNull);

    // A background 60s refresh before Core finishes setupConfig('b') must not
    // clear the pending switch and flash Alpha's old runtime groups under Beta.
    container.read(groupsProvider.notifier).value = const [
      Group(
          name: 'Alpha Select',
          type: GroupType.Selector,
          hidden: false,
          now: 'Alpha live',
          all: [Proxy(name: 'Alpha live', type: 'Shadowsocks')]),
    ];
    container.read(versionProvider.notifier).value = 2;
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('overview-use-b-b-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('overview-use-b-Alpha live')), findsNothing);

    // Simulate Core completing setupConfig('b') and publishing Beta's runtime groups.
    globalState.lastRuntimeProfileId = 'b';
    container.read(groupsProvider.notifier).value = const [
      Group(
          name: 'Beta Primary',
          type: GroupType.Selector,
          hidden: false,
          now: 'Beta fast',
          all: [
            Proxy(name: 'Beta fast', type: 'Shadowsocks'),
            Proxy(name: 'Beta other', type: 'Shadowsocks'),
          ]),
    ];
    container.read(versionProvider.notifier).value = 3;
    await tester.pumpAndSettle();

    final liveUseBeta1 = find.byKey(const ValueKey('overview-use-b-Beta fast'));
    expect(liveUseBeta1, findsOneWidget);
    expect(tester.widget<TextButton>(liveUseBeta1).onPressed, isNull);
    expect(
      find.descendant(of: liveUseBeta1, matching: find.text('In use')),
      findsOneWidget,
    );
    expect(find.text('Switched to Beta profile · Beta fast'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'one-click use: Global mode targets GLOBAL, Direct/unselectable disables Use, and parseFailed hides Use',
      (tester) async {
    const c = Profile(
      id: 'c',
      label: 'Gamma profile',
      autoUpdateDuration: Duration.zero,
      providerHeaders: {'flclashx-globalmode': 'false'},
    );
    globalState.config = globalState.config.copyWith(
      currentProfileId: 'a',
      profiles: [_a, _b, c],
      patchClashConfig: defaultClashConfig.copyWith(mode: Mode.global),
    );
    final container = await mount(
      tester,
      width: 1200,
      profiles: [_a, _b, c],
      catalogs: {
        'b': ProfileCatalog(
            profileId: 'b',
            fingerprint: 'fb',
            status: ProfileCatalogStatus.ready,
            nodes: [
              _node('b-global', 'Global node'),
              _node('b-chain', 'Chain node').copyWith(
                  selectGroups: const ['Proxy'],
                  unsupported: CatalogUnsupportedReason.chainUnsupported),
              _node('b-invalid', 'Invalid node').copyWith(
                  unsupported: CatalogUnsupportedReason.parseFailed),
            ]),
        'c': ProfileCatalog(
            profileId: 'c',
            fingerprint: 'fc',
            status: ProfileCatalogStatus.ready,
            nodes: [
              _node('c-rule', 'Rule-only node')
                  .copyWith(selectGroups: const ['Gamma Select']),
            ]),
      },
    );

    // parseFailed nodes never show a Use button.
    expect(
      find.byKey(const ValueKey('overview-use-b-b-invalid')),
      findsNothing,
    );

    // In Global mode, even a node with empty selectGroups targets GLOBAL.
    final useGlobal = find.byKey(const ValueKey('overview-use-b-b-global'));
    expect(tester.widget<TextButton>(useGlobal).onPressed, isNotNull);
    await tester.tap(useGlobal);
    await tester.pumpAndSettle();
    expect(container.read(currentProfileIdProvider), 'b');
    expect(
      container.read(profilesProvider).getProfile('b')?.selectedMap['GLOBAL'],
      'Global node',
    );

    // Profile C disables global mode via flclashx-globalmode: false, so Use
    // writes its first Rule-mode select group even while currently in Global mode.
    final useGamma = find.byKey(const ValueKey('overview-use-c-c-rule'));
    expect(tester.widget<TextButton>(useGamma).onPressed, isNotNull);
    await tester.tap(useGamma);
    await tester.pumpAndSettle();
    expect(container.read(currentProfileIdProvider), 'c');
    expect(
      container
          .read(profilesProvider)
          .getProfile('c')
          ?.selectedMap['Gamma Select'],
      'Rule-only node',
    );

    // In Direct mode, Use buttons are disabled.
    container.read(patchClashConfigProvider.notifier).updateState(
          (state) => state.copyWith(mode: Mode.direct),
        );
    await tester.pumpAndSettle();
    final useChain = find.byKey(const ValueKey('overview-use-b-b-chain'));
    expect(tester.widget<TextButton>(useChain).onPressed, isNull);

    // In Rule mode, a node without selectGroups is disabled, while a chain node with selectGroups is enabled.
    container.read(patchClashConfigProvider.notifier).updateState(
          (state) => state.copyWith(mode: Mode.rule),
        );
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(useGlobal).onPressed, isNull);
    expect(tester.widget<TextButton>(useChain).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'one-click use: unknown runtime identity does not clear pending switch on stale refresh',
      (tester) async {
    globalState.appController = _ProxyController();
    globalState.lastRuntimeProfileId = null;
    globalState.config = globalState.config.copyWith(currentProfileId: 'a');
    const staleGroups = [
      Group(
          name: 'Alpha Select',
          type: GroupType.Selector,
          hidden: false,
          now: 'Alpha live',
          all: [Proxy(name: 'Alpha live', type: 'Shadowsocks')]),
    ];
    globalState.appState = globalState.appState.copyWith(groups: staleGroups);
    final container = await mount(
      tester,
      width: 1200,
      catalogs: {
        'b': ProfileCatalog(
            profileId: 'b',
            fingerprint: 'fb',
            status: ProfileCatalogStatus.ready,
            nodes: [
              _node('b-1', 'Beta fast')
                  .copyWith(selectGroups: const ['Beta Select']),
            ]),
      },
    );

    await tester.tap(find.byKey(const ValueKey('overview-use-b-b-1')));
    await tester.pumpAndSettle();
    expect(container.read(currentProfileIdProvider), 'b');
    expect(find.byKey(const ValueKey('overview-use-b-b-1')), findsOneWidget);

    // A periodic refresh arrives while runtime identity is still unknown (null).
    container.read(groupsProvider.notifier).value = List<Group>.of(staleGroups);
    container.read(versionProvider.notifier).value = 2;
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('overview-use-b-Alpha live')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('overview-use-b-b-1')), findsOneWidget);

    // Even if lastRuntimeProfileId commits before updateGroups() publishes B's
    // groups, the absorbed stale groups must not prematurely clear pending switch.
    globalState.lastRuntimeProfileId = 'b';
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('overview-use-b-Alpha live')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('overview-use-b-b-1')), findsOneWidget);

    // Once B's runtime groups are published, the pending switch clears cleanly.
    container.read(groupsProvider.notifier).value = const [
      Group(
          name: 'Beta Select',
          type: GroupType.Selector,
          hidden: false,
          now: 'Beta fast',
          all: [Proxy(name: 'Beta fast', type: 'Shadowsocks')]),
    ];
    container.read(versionProvider.notifier).value = 3;
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('overview-use-b-Beta fast')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'one-click use: failed cross-profile switch keeps target node retryable and does not mark it In use while runtime stays on previous profile',
      (tester) async {
    final controller = _ProxyController();
    globalState.appController = controller;
    globalState.lastRuntimeProfileId = 'a';
    globalState.config = globalState.config.copyWith(currentProfileId: 'a');
    const aGroups = [
      Group(
          name: 'Alpha Select',
          type: GroupType.Selector,
          hidden: false,
          now: 'Alpha live',
          all: [Proxy(name: 'Alpha live', type: 'Shadowsocks')]),
    ];
    globalState.appState = globalState.appState.copyWith(groups: aGroups);
    final container = await mount(
      tester,
      width: 1200,
      catalogs: {
        'b': ProfileCatalog(
            profileId: 'b',
            fingerprint: 'fb',
            status: ProfileCatalogStatus.ready,
            nodes: [
              _node('b-1', 'Beta fast')
                  .copyWith(selectGroups: const ['Beta Select']),
            ]),
      },
    );

    final button = find.byKey(const ValueKey('overview-use-b-b-1'));
    await tester.tap(button);
    await tester.pumpAndSettle();

    // Model failed setup outcome: runtime stays A, and periodic group refresh
    // publishes the still-running A generation again.
    container.read(groupsProvider.notifier).value = List<Group>.of(aGroups);
    container.read(versionProvider.notifier).value =
        container.read(versionProvider) + 1;
    await tester.pumpAndSettle();

    expect(globalState.lastRuntimeProfileId, 'a');
    expect(container.read(currentProfileIdProvider), 'b');
    expect(container.read(groupsProvider).single.now, 'Alpha live');
    expect(find.text('Switched to Beta profile · Beta fast'), findsNothing);
    expect(
      find.descendant(of: button, matching: find.text('In use')),
      findsNothing,
    );
    expect(
      find.descendant(of: button, matching: find.text('Use')),
      findsOneWidget,
    );
    expect(
      tester.widget<TextButton>(button).onPressed,
      isNotNull,
      reason: 'Runtime is still A; B must not be disabled as successfully in use',
    );

    // Tapping Use again retries applying profile B and selecting the node.
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(controller.applyDebounces, [true]);
    expect(controller.changes, [('Beta Select', 'Beta fast')]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'one-click use: remounting overview via ProxiesScope during pending or failed switch never renders previous profile live nodes under target profile',
      (tester) async {
    globalState.lastRuntimeProfileId = 'a';
    globalState.config = globalState.config.copyWith(currentProfileId: 'a');
    globalState.appState = globalState.appState.copyWith(groups: const [
      Group(
          name: 'Alpha Select',
          type: GroupType.Selector,
          hidden: false,
          now: 'Alpha live',
          all: [Proxy(name: 'Alpha live', type: 'Shadowsocks')]),
    ]);
    final container = await mount(
      tester,
      width: 1200,
      child: const NodeOverviewScopeView(currentView: SizedBox.shrink()),
      catalogs: {
        'b': ProfileCatalog(
            profileId: 'b',
            fingerprint: 'fb',
            status: ProfileCatalogStatus.ready,
            nodes: [
              _node('b-1', 'Beta fast')
                  .copyWith(selectGroups: const ['Beta Select']),
            ]),
      },
    );

    container.read(proxiesScopeProvider.notifier).state = ProxiesScope.all;
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('overview-use-b-b-1')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('overview-use-b-Alpha live')),
      findsNothing,
    );

    // Toggle Current -> All to unmount and remount NodeOverviewView while runtime is still A.
    container.read(proxiesScopeProvider.notifier).state = ProxiesScope.current;
    await tester.pumpAndSettle();
    expect(find.byType(NodeOverviewView), findsNothing);

    // While overview is unmounted, a refresh completes for the still-running A
    // generation, and then setupConfig commits B before B's updateGroups returns.
    const aGroups = [
      Group(
          name: 'Alpha Select',
          type: GroupType.Selector,
          hidden: false,
          now: 'Alpha live',
          all: [Proxy(name: 'Alpha live', type: 'Shadowsocks')]),
    ];
    container.read(groupsProvider.notifier).value = List<Group>.of(aGroups);
    container.read(versionProvider.notifier).value =
        container.read(versionProvider) + 1;
    await tester.pumpAndSettle();
    globalState.lastRuntimeProfileId = 'b';
    container.read(proxiesScopeProvider.notifier).state = ProxiesScope.all;
    await tester.pumpAndSettle();

    expect(container.read(groupsProvider).single.name, 'Alpha Select');
    expect(container.read(currentProfileIdProvider), 'b');
    expect(globalState.lastRuntimeProfileId, 'b');
    expect(
      find.byKey(const ValueKey('overview-use-b-Alpha live')),
      findsNothing,
      reason:
          'Changing runtime identity does not attest the cached A group snapshot',
    );
    expect(find.text('Switched to Beta profile · Beta fast'), findsNothing);
    expect(find.byKey(const ValueKey('overview-use-b-b-1')), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('overview-use-b-b-1')))
          .onPressed,
      isNotNull,
    );

    // Once B's runtime groups are actually published, overview switches to B's live rows.
    container.read(groupsProvider.notifier).value = const [
      Group(
          name: 'Beta Select',
          type: GroupType.Selector,
          hidden: false,
          now: 'Beta fast',
          all: [Proxy(name: 'Beta fast', type: 'Shadowsocks')]),
    ];
    container.read(versionProvider.notifier).value =
        container.read(versionProvider) + 1;
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('overview-use-b-Beta fast')),
      findsOneWidget,
    );
    expect(find.text('Switched to Beta profile · Beta fast'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'one-click use: unrelated AppState updates and cold overview mount preserve preexisting group snapshot ownership',
      (tester) async {
    const oldGroups = [
      Group(
          name: 'Alpha Select',
          type: GroupType.Selector,
          hidden: false,
          now: 'Alpha live',
          all: [Proxy(name: 'Alpha live', type: 'Shadowsocks')]),
    ];
    const bSetup = SetupParams(
      config: {'proxy-groups': []},
      selectedMap: {},
      testUrl: 'https://example.invalid/204',
    );

    globalState.lastRuntimeProfileId = 'a';
    globalState.appState = globalState.appState.copyWith(
      viewSize: const Size(1200, 1000),
      groups: List<Group>.of(oldGroups),
    );
    expect(globalState.groupsSnapshotProfileId, 'a');

    globalState.config = globalState.config.copyWith(currentProfileId: 'b');
    globalState.commitRuntimeSetup(bSetup, 'b');
    expect(globalState.groupsSnapshotProfileId, 'a');

    final container = await mount(
      tester,
      width: 1200,
      child: const NodeOverviewScopeView(currentView: SizedBox.shrink()),
      catalogs: {
        'b': ProfileCatalog(
            profileId: 'b',
            fingerprint: 'fb',
            status: ProfileCatalogStatus.ready,
            nodes: [
              _node('b-1', 'Beta fast')
                  .copyWith(selectGroups: const ['Beta Select']),
            ]),
      },
    );
    container.read(runTimeProvider.notifier).value = 123;
    expect(globalState.appState.runTime, 123);
    expect(globalState.groupsSnapshotProfileId, 'a');

    container.read(proxiesScopeProvider.notifier).state = ProxiesScope.all;
    await tester.pumpAndSettle();

    expect(globalState.groupsSnapshotProfileId, 'a');
    expect(globalState.lastRuntimeProfileId, 'b');
    expect(container.read(currentProfileIdProvider), 'b');
    expect(container.read(groupsProvider).single.name, 'Alpha Select');
    expect(
      find.byKey(const ValueKey('overview-use-b-Alpha live')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('overview-use-b-b-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'one-click use: adding second profile after normal groups plus version publication preserves live In use rows',
      (tester) async {
    final controller = _ProxyController();
    globalState.appController = controller;
    globalState.lastRuntimeProfileId = 'a';
    final activeProfile = _a.copyWith(
      selectedMap: const {'Alpha Select': 'Alpha live'},
    );
    globalState.config = globalState.config.copyWith(
      currentProfileId: 'a',
      profiles: [activeProfile],
    );
    final container = await mount(
      tester,
      width: 1200,
      profiles: [activeProfile],
      child: const NodeOverviewScopeView(currentView: ProxiesListView()),
      catalogs: {
        'a': ProfileCatalog(
          profileId: 'a',
          fingerprint: 'fa',
          status: ProfileCatalogStatus.ready,
          nodes: [
            _node('a-1', 'Alpha live')
                .copyWith(selectGroups: const ['Alpha Select']),
          ],
        ),
      },
    );
    expect(find.byType(ProxiesListView), findsOneWidget);
    expect(find.byType(NodeOverviewView), findsNothing);

    final publishedGroups = <Group>[
      const Group(
        name: 'Alpha Select',
        type: GroupType.Selector,
        hidden: false,
        now: 'Alpha live',
        all: [Proxy(name: 'Alpha live', type: 'Shadowsocks')],
      ),
    ];
    container.read(groupsProvider.notifier).value = publishedGroups;
    container.read(versionProvider.notifier).value =
        container.read(versionProvider) + 1;
    await tester.pumpAndSettle();
    expect(identical(container.read(groupsProvider), publishedGroups), isTrue);
    expect(globalState.groupsSnapshotProfileId, 'a');

    container.read(profilesProvider.notifier).setProfile(_b);
    await tester.pumpAndSettle();
    container.read(proxiesScopeProvider.notifier).state = ProxiesScope.all;
    await tester.pumpAndSettle();

    final liveButton = find.byKey(const ValueKey('overview-use-a-Alpha live'));
    expect(liveButton, findsOneWidget);
    expect(tester.widget<TextButton>(liveButton).onPressed, isNull);
    expect(
      find.descendant(of: liveButton, matching: find.text('In use')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'country filter chips aggregate across all profiles, auto-hide empty profile sections, and toggle off on second tap',
      (tester) async {
    const pIkuuu = Profile(
      id: 'ikuuu',
      label: 'ikuuu',
      autoUpdateDuration: Duration.zero,
    );
    const pLondon = Profile(
      id: 'london',
      label: '伦敦',
      autoUpdateDuration: Duration.zero,
    );
    const pUs = Profile(
      id: 'us',
      label: '美国',
      autoUpdateDuration: Duration.zero,
    );
    await mount(
      tester,
      width: 1200,
      profiles: const [pIkuuu, pLondon, pUs],
      catalogs: {
        'ikuuu': ProfileCatalog(
          profileId: 'ikuuu',
          fingerprint: 'f1',
          status: ProfileCatalogStatus.ready,
          nodes: [
            _node('ik-us', '🇺🇸 US Node 1'),
            _node('ik-jp', '🇯🇵 Tokyo Node 1'),
          ],
        ),
        'london': ProfileCatalog(
          profileId: 'london',
          fingerprint: 'f2',
          status: ProfileCatalogStatus.ready,
          nodes: [
            _node('lon-1', 'VIP Line 1'),
            _node('lon-2', 'VIP Line 2'),
          ],
        ),
        'us': ProfileCatalog(
          profileId: 'us',
          fingerprint: 'f3',
          status: ProfileCatalogStatus.ready,
          nodes: [
            _node('us-2', 'Los Angeles 02'),
          ],
        ),
      },
    );

    final usChip = find.byKey(const ValueKey('overview-country-US'));
    final gbChip = find.byKey(const ValueKey('overview-country-GB'));
    final jpChip = find.byKey(const ValueKey('overview-country-JP'));
    expect(usChip, findsOneWidget);
    expect(gbChip, findsOneWidget);
    expect(jpChip, findsOneWidget);
    expect(find.text('🇺🇸 United States (2)'), findsOneWidget);
    expect(find.text('🇬🇧 United Kingdom (2)'), findsOneWidget);
    expect(find.text('🇯🇵 Japan (1)'), findsOneWidget);

    // Node card country badges are rendered
    expect(find.text('🇺🇸 United States'), findsNWidgets(2));
    expect(find.text('🇬🇧 United Kingdom'), findsNWidgets(2));
    expect(find.text('🇯🇵 Japan'), findsOneWidget);

    // Tap GB chip -> only London profile section and its 2 nodes are shown;
    // ikuuu and us profile sections are automatically hidden.
    await tester.tap(gbChip);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('overview-header-london')), findsOneWidget);
    expect(find.byKey(const ValueKey('overview-header-ikuuu')), findsNothing);
    expect(find.byKey(const ValueKey('overview-header-us')), findsNothing);
    expect(find.text('VIP Line 1'), findsOneWidget);
    expect(find.text('VIP Line 2'), findsOneWidget);
    expect(find.text('🇺🇸 US Node 1'), findsNothing);
    expect(find.text('🇯🇵 Tokyo Node 1'), findsNothing);

    // Tap GB chip a second time -> clears country filter and restores all sections
    await tester.tap(gbChip);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('overview-header-ikuuu')), findsOneWidget);
    expect(find.byKey(const ValueKey('overview-header-london')), findsOneWidget);
    expect(find.byKey(const ValueKey('overview-header-us')), findsOneWidget);
    expect(find.text('🇺🇸 US Node 1'), findsOneWidget);
    expect(find.text('🇯🇵 Tokyo Node 1'), findsOneWidget);
    expect(find.text('VIP Line 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'country filter chips scope to selected single profile on sidebar selection',
      (tester) async {
    const pIkuuu = Profile(
      id: 'ikuuu',
      label: 'ikuuu',
      autoUpdateDuration: Duration.zero,
    );
    const pLondon = Profile(
      id: 'london',
      label: '伦敦',
      autoUpdateDuration: Duration.zero,
    );
    await mount(
      tester,
      width: 1200,
      profiles: const [pIkuuu, pLondon],
      catalogs: {
        'ikuuu': ProfileCatalog(
          profileId: 'ikuuu',
          fingerprint: 'f1',
          status: ProfileCatalogStatus.ready,
          nodes: [
            _node('ik-us', '🇺🇸 US Node 1'),
            _node('ik-jp', '🇯🇵 Tokyo Node 1'),
          ],
        ),
        'london': ProfileCatalog(
          profileId: 'london',
          fingerprint: 'f2',
          status: ProfileCatalogStatus.ready,
          nodes: [
            _node('lon-1', 'VIP Line 1'),
          ],
        ),
      },
    );

    // Select ikuuu in sidebar
    await tester.tap(find.byKey(const ValueKey('overview-select-ikuuu')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('overview-country-US')), findsOneWidget);
    expect(find.byKey(const ValueKey('overview-country-JP')), findsOneWidget);
    expect(find.byKey(const ValueKey('overview-country-GB')), findsNothing);
    expect(find.text('🇺🇸 United States (1)'), findsOneWidget);
    expect(find.text('🇯🇵 Japan (1)'), findsOneWidget);

    // Filter by JP within ikuuu
    await tester.tap(find.byKey(const ValueKey('overview-country-JP')));
    await tester.pumpAndSettle();

    expect(find.text('🇯🇵 Tokyo Node 1'), findsOneWidget);
    expect(find.text('🇺🇸 US Node 1'), findsNothing);

    // Flag emojis in chips use Twemoji font family so Windows renders color flags
    final jpChipText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('overview-country-JP')),
        matching: find.byType(Text),
      ),
    );
    final rootSpan = jpChipText.textSpan! as TextSpan;
    final emojiSpan = rootSpan.children!.first as TextSpan;
    expect(emojiSpan.style?.fontFamily, FontFamily.twEmoji.value);

    // Switch sidebar to London (which has only GB, no JP):
    // JP filter clears cleanly without leaving a ghost filter when returning to All profiles.
    await tester.tap(find.byKey(const ValueKey('overview-select-london')));
    await tester.pumpAndSettle();

    expect(find.text('VIP Line 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('overview-country-GB')), findsOneWidget);
    expect(find.byKey(const ValueKey('overview-country-JP')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('overview-select-all')));
    await tester.pumpAndSettle();

    expect(find.text('🇺🇸 US Node 1'), findsOneWidget);
    expect(find.text('🇯🇵 Tokyo Node 1'), findsOneWidget);
    expect(find.text('VIP Line 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

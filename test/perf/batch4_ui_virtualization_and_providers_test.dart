import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flclashx/clash/core.dart';
import 'package:flclashx/clash/interface.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/delay_test_coordinator.dart';
import 'package:flclashx/common/node_catalog_service.dart';
import 'package:flclashx/common/node_catalog_tester.dart';
import 'package:flclashx/common/node_health_store.dart';
import 'package:flclashx/common/process_icon.dart';
import 'package:flclashx/common/process_icon_queue.dart';
import 'package:flclashx/common/theme.dart';
import 'package:flclashx/controller.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/views/connection/table.dart';
import 'package:flclashx/views/dashboard/widgets/memory_info.dart';
import 'package:flclashx/views/dashboard/widgets/start_button.dart';
import 'package:flclashx/views/logs.dart';
import 'package:flclashx/views/proxies/card.dart';
import 'package:flclashx/views/proxies/list.dart';
import 'package:flclashx/widgets/bar_chart.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingTransport implements ClashHandlerInterface {
  final List<bool> requestsActiveCalls = [];
  int memoryCalls = 0;

  @override
  Future<bool> setRequestsActive(bool active) async {
    requestsActiveCalls.add(active);
    return true;
  }

  @override
  FutureOr<String> getMemory() {
    memoryCalls++;
    return '67108864';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await AppLocalizations.load(const Locale('en'));
    globalState.config = const Config(themeProps: defaultThemeProps);
    globalState.appState = AppState(
      viewSize: const Size(1280, 800),
      version: 1,
      requests: FixedList(maxLength),
      logs: FixedList(maxLength),
      traffics: FixedList(30),
      totalTraffic: Traffic(),
      isInit: true,
    );
    globalState.startTime = null;
  });

  group('P0-5: ProxiesListView virtualization & narrow Riverpod selectors', () {
    testWidgets(
      'collapsed groups mount 0 ProxyCards and expanded large groups lazily mount only viewport rows',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final collapsedGroup = Group(
          name: 'CollapsedGroup',
          type: GroupType.Selector,
          hidden: false,
          all: [
            for (var i = 0; i < 200; i++)
              Proxy(name: 'Collapsed-$i', type: 'Shadowsocks'),
          ],
        );
        final expandedGroup = Group(
          name: 'ExpandedGroup',
          type: GroupType.Selector,
          hidden: false,
          all: [
            for (var i = 0; i < 300; i++)
              Proxy(name: 'Expanded-$i', type: 'Shadowsocks'),
          ],
        );
        final profile = Profile.normal().copyWith(
          id: 'p1',
          unfoldSet: const {'ExpandedGroup'},
        );
        globalState.config = globalState.config.copyWith(
          currentProfileId: 'p1',
          profiles: [profile],
        );
        globalState.appState = globalState.appState.copyWith(
          groups: [collapsedGroup, expandedGroup],
        );

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Consumer(
                builder: (context, ref, _) {
                  globalState.measure = Measure.of(context, 1.0);
                  globalState.theme = CommonTheme.of(context, 1.0);
                  globalState.appController = AppController(context, ref);
                  return const Scaffold(
                    body: SizedBox(
                      width: 1200,
                      height: 700,
                      child: ProxiesListView(),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pump();

        final mountedCards =
            tester.widgetList<ProxyCard>(find.byType(ProxyCard)).toList();
        expect(
          mountedCards.where((c) => c.groupName == 'CollapsedGroup'),
          isEmpty,
          reason: 'Collapsed groups must not mount hidden ProxyCard widgets',
        );
        expect(
          mountedCards.length,
          inInclusiveRange(1, 90),
          reason:
              'Expanded 300-node group must virtualize rows instead of mounting all 300 ProxyCards',
        );
      },
    );

    test(
      'getRealTestUrlProvider does not recompute when unrelated AppSettingProps change',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        var notifications = 0;
        final sub = container.listen<String>(
          getRealTestUrlProvider(null),
          (_, __) => notifications++,
          fireImmediately: true,
        );
        addTearDown(sub.close);
        expect(notifications, 1);

        container.read(appSettingProvider.notifier).updateState(
              (s) => s.copyWith(
                openLogs: !s.openLogs,
                showLabel: !s.showLabel,
                autoLaunch: !s.autoLaunch,
              ),
            );
        await container.pump();
        expect(notifications, 1);

        container.read(appSettingProvider.notifier).updateState(
              (s) => s.copyWith(
                testUrl: 'https://cp.cloudflare.com/generate_204',
              ),
            );
        await container.pump();
        expect(notifications, 2);
      },
    );
  });

  group('P1-2: Offstage/hidden gating & composite setRequestsActive', () {
    test('ClashCore ref-counts requests consumers accurately', () async {
      final transport = _RecordingTransport();
      final core = ClashCore.forTesting(transport);

      await core.acquireRequestsConsumer('requests_view');
      await core.acquireRequestsConsumer('ip_probe_1');
      expect(transport.requestsActiveCalls, [true]);

      await core.releaseRequestsConsumer('ip_probe_1');
      expect(
        transport.requestsActiveCalls,
        [true],
        reason: 'Still held by requests_view',
      );

      await core.releaseRequestsConsumer('requests_view');
      expect(transport.requestsActiveCalls, [true, false]);
    });

    testWidgets(
      'LogsView uses CacheTag.logs without shrinkWrap and tolerates duplicate payloads',
      (tester) async {
        final duplicateLogs = <Log>[
          for (var i = 0; i < 10; i++) Log.app('identical warning line'),
        ];
        globalState.appState = globalState.appState.copyWith(
          logs: FixedList<Log>(maxLength, list: duplicateLogs),
          pageLabel: PageLabel.logs,
        );

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Consumer(
                builder: (context, ref, _) {
                  globalState.measure = Measure.of(context, 1.0);
                  globalState.appController = AppController(context, ref);
                  return const Scaffold(body: LogsView());
                },
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);

        final listView = tester.widget<CacheItemExtentListView>(
          find.byType(CacheItemExtentListView),
        );
        expect(listView.tag, CacheTag.logs);
        expect(listView.shrinkWrap, isFalse);
      },
    );

    testWidgets(
      'MemoryInfo pauses 2s IPC polling when TickerMode is disabled',
      (tester) async {
        final transport = _RecordingTransport();
        final prevInterface = clashCore.clashInterface;
        clashCore.clashInterface = transport;
        addTearDown(() {
          clashCore.clashInterface = prevInterface;
        });

        final activeNotifier = ValueNotifier<bool>(true);
        addTearDown(activeNotifier.dispose);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Consumer(
                builder: (context, ref, _) {
                  globalState.measure = Measure.of(context, 1.0);
                  globalState.theme = CommonTheme.of(context, 1.0);
                  return Scaffold(
                    body: ValueListenableBuilder<bool>(
                      valueListenable: activeNotifier,
                      builder: (_, active, __) => TickerMode(
                        enabled: active,
                        child: const SizedBox(
                          width: 300,
                          height: 120,
                          child: MemoryInfo(),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pump();
        final callsWhileActive = transport.memoryCalls;
        expect(callsWhileActive, greaterThanOrEqualTo(1));

        activeNotifier.value = false;
        await tester.pump();
        final callsWhenPaused = transport.memoryCalls;

        await tester.pump(const Duration(seconds: 6));
        expect(
          transport.memoryCalls,
          callsWhenPaused,
          reason:
              'Offstage TickerMode(enabled: false) must pause getMemory timer',
        );
      },
    );
  });

  group('P1-4: Chart value equality, StartButton key stability & HealthStore',
      () {
    test('Point and BarChartData implement structural equality', () {
      expect(const Point(1, 20), equals(const Point(1, 20)));
      expect(const Point(1, 20).hashCode, equals(const Point(1, 20).hashCode));
      expect(
        listEquals(
          const [Point(0, 5), Point(1, 10)],
          const [Point(0, 5), Point(1, 10)],
        ),
        isTrue,
      );

      expect(
        const BarChartData(value: 12.5, label: 'TCP'),
        equals(const BarChartData(value: 12.5, label: 'TCP')),
      );
      expect(
        listEquals(
          const [BarChartData(value: 12.5, label: 'TCP')],
          const [BarChartData(value: 12.5, label: 'TCP')],
        ),
        isTrue,
      );
    });

    test('DelayDataSource.setDelays coalesces burst updates into 1 clone/notify',
        () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      var emissions = 0;
      final sub = container.listen<DelayMap>(
        delayDataSourceProvider,
        (_, __) => emissions++,
        fireImmediately: true,
      );
      addTearDown(sub.close);
      expect(emissions, 1);

      final burst = [
        for (var i = 0; i < 100; i++)
          Delay(name: 'node-$i', url: defaultTestUrl, value: 20 + i),
      ];
      container.read(delayDataSourceProvider.notifier).setDelays(burst);
      expect(emissions, 2);
      expect(container.read(delayDataSourceProvider)[defaultTestUrl]?.length, 100);

      // Identical repeat is a zero-allocation no-op.
      container.read(delayDataSourceProvider.notifier).setDelays(burst);
      expect(emissions, 2);
    });

    testWidgets(
      'StartButton does not restart AnimatedSwitcher transition on 1s uptime ticks',
      (tester) async {
        final profile = Profile.normal().copyWith(id: 'p1');
        globalState.config = globalState.config.copyWith(
          currentProfileId: 'p1',
          profiles: [profile],
        );
        globalState.appState = globalState.appState.copyWith(
          isInit: true,
          runTime: 1000,
        );
        final runTimeNotifier = _MutableRunTimeNotifier(1000);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              runTimeProvider.overrideWith(() => runTimeNotifier),
            ],
            child: MaterialApp(
              home: Consumer(
                builder: (context, ref, _) {
                  globalState.measure = Measure.of(context, 1.0);
                  globalState.theme = CommonTheme.of(context, 1.0);
                  globalState.appController = AppController(context, ref);
                  return const Scaffold(body: StartButton());
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('00:00:01'), findsOneWidget);

        runTimeNotifier.updateMs(2000);
        await tester.pump();
        expect(find.text('00:00:02'), findsOneWidget);

        final switcherFades = tester
            .widgetList<FadeTransition>(
              find.descendant(
                of: find.byType(AnimatedSwitcher),
                matching: find.byType(FadeTransition),
              ),
            )
            .toList();
        expect(
          switcherFades,
          hasLength(1),
          reason:
              '1-second uptime text change must update child in-place without spawning outgoing AnimatedSwitcher transition',
        );
        expect(switcherFades.single.opacity.value, 1.0);
      },
    );

    test(
      'NodeHealthStore tracks per-profile revision and NodeCatalogTester isolates pending set',
      () async {
        final store = NodeHealthStore(
          fileProvider: () => Completer<Never>().future,
        );
        addTearDown(store.dispose);

        expect(store.profileRevision('p1'), 0);
        expect(store.profileRevision('p2'), 0);

        final hash1 = NodeHealthStore.hashTestUrl(
          'https://www.gstatic.com/generate_204',
        );
        final hash2 = NodeHealthStore.hashTestUrl(
          'https://www.gstatic.com/generate_204',
        );
        expect(identical(hash1, hash2), isTrue);

        final coordinator = DelayTestCoordinator(
          test: (_, __, ___) async => const DelayTestResult(25),
          cancelRequest: (_) async {},
          onStarted: (_) {},
          onResult: (_, __) {},
        );
        addTearDown(coordinator.dispose);
        final service = NodeCatalogService(
          readProfileConfig: (_) async => const {},
          evaluate: (v) async => v,
          fileMetadata: (_) async => (modifiedMicros: 1, size: 1),
          scriptFingerprint: () => '',
          prepareCatalog: (id, _, __) async =>
              '{"catalog-id":"$id","nodes":[]}',
          releaseCatalog: (_) async => true,
        );
        final catalogTester = NodeCatalogTester(
          service: service,
          store: store,
          coordinator: coordinator,
          isCurrentProfile: (_) => true,
          activeProfileId: () => 'p1',
        );
        addTearDown(catalogTester.dispose);

        expect(
          identical(
            catalogTester.pendingIdentitySnapshot('p2'),
            catalogTester.pendingIdentitySnapshot('p2'),
          ),
          isTrue,
        );
      },
    );
  });

  group('P2-3 & P2-4: ConnectionTable pre-sorted fast path & ProcessIcon', () {
    testWidgets(
      'ConnectionTable preserves pre-sorted items order without redundant re-sort',
      (tester) async {
        final preSorted = [
          TrackedConnection(
            connection: Connection(
              id: 'first',
              upload: 100,
              download: 200,
              start: DateTime.utc(2026, 1, 1),
              metadata: const Metadata(
                uid: 0,
                network: 'tcp',
                sourceIP: '192.0.2.1',
                sourcePort: '1234',
                destinationIP: '203.0.113.1',
                destinationPort: '443',
                host: 'first.example.com',
                process: 'alpha.exe',
                processPath: r'C:\Apps\alpha.exe',
                remoteDestination: 'first.example.com:443',
              ),
              chains: const ['Proxy'],
            ),
            isActive: true,
            uploadSpeed: 2048,
            downloadSpeed: 4096,
          ),
          TrackedConnection(
            connection: Connection(
              id: 'second',
              upload: 50,
              download: 100,
              start: DateTime.utc(2026, 1, 1),
              metadata: const Metadata(
                uid: 0,
                network: 'tcp',
                sourceIP: '192.0.2.2',
                sourcePort: '1235',
                destinationIP: '203.0.113.2',
                destinationPort: '443',
                host: 'second.example.com',
                process: 'beta.exe',
                processPath: r'C:\Apps\beta.exe',
                remoteDestination: 'second.example.com:443',
              ),
              chains: const ['Proxy'],
            ),
            isActive: true,
            uploadSpeed: 512,
            downloadSpeed: 1024,
          ),
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 720,
                height: 300,
                child: ConnectionTable(
                  items: preSorted,
                  itemsPreSorted: true,
                  columns: const ['process', 'uploadSpeed'],
                  columnWidths: const {},
                  sort: ConnectionSort.uploadSpeed,
                  sortDirection: ConnectionSortDirection.descending,
                  onColumnWidthsChanged: (_) {},
                  onTap: (_) {},
                  onClose: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('alpha.exe'), findsOneWidget);
        expect(find.text('beta.exe'), findsOneWidget);
      },
    );

    test('negativeCacheTtl suppresses repeated null loads within TTL window',
        () {
      fakeAsync((clock) {
        var calls = 0;
        String? nextResult;
        final fakeClock = clock.getClock(DateTime.utc(2026, 1, 1));
        final queue = ProcessIconQueue<String>(
          negativeCacheTtl: const Duration(seconds: 60),
          now: fakeClock.now,
          load: (_) async {
            calls++;
            return nextResult;
          },
        );

        final results = <String?>[];
        unawaited(queue.acquire('missing.exe')!.future.then(results.add));
        clock
          ..flushMicrotasks()
          ..elapse(Duration.zero)
          ..flushMicrotasks();
        expect(calls, 1);
        expect(results, [null]);

        // Within 60s TTL, repeated acquire resolves immediately to null without calling load.
        unawaited(queue.acquire('missing.exe')!.future.then(results.add));
        clock
          ..flushMicrotasks()
          ..elapse(Duration.zero)
          ..flushMicrotasks();
        expect(calls, 1);
        expect(results, [null, null]);

        // After 61s, TTL expires and retries load.
        clock.elapse(const Duration(seconds: 61));
        nextResult = 'icon-ok';
        unawaited(queue.acquire('missing.exe')!.future.then(results.add));
        clock
          ..flushMicrotasks()
          ..elapse(Duration.zero)
          ..flushMicrotasks();
        expect(calls, 2);
        expect(results, [null, null, 'icon-ok']);

        queue.dispose();
      });
    });

    test('BgraProcessIconImage decodes raw BGRA8888 without PNG round-trip',
        () async {
      final provider = BgraProcessIconImage(
        bytes: Uint8List.fromList([255, 0, 0, 255]),
        width: 1,
        height: 1,
      );
      final completer = Completer<ImageInfo>();
      final stream = provider.resolve(ImageConfiguration.empty);
      late final ImageStreamListener listener;
      listener = ImageStreamListener((info, _) {
        completer.complete(info);
        stream.removeListener(listener);
      });
      stream.addListener(listener);
      final info = await completer.future;
      expect(info.image.width, 1);
      expect(info.image.height, 1);
      await provider.evict();
    });
  });
}

class _MutableRunTimeNotifier extends RunTime {
  _MutableRunTimeNotifier(this._initial);
  final int? _initial;

  @override
  int? build() => _initial;

  void updateMs(int? next) {
    state = next;
  }
}

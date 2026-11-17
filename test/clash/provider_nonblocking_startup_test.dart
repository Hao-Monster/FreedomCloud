import 'dart:async';

import 'package:flclashx/common/windows_tun_startup.dart';
import 'package:flclashx/manager/clash_manager.dart';
import 'package:flclashx/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

ExternalProvider _sampleProvider(String name, {int count = 3}) =>
    ExternalProvider(
      name: name,
      type: 'Proxy',
      vehicleType: 'HTTP',
      count: count,
      updateAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );

void main() {
  group('Issue 2: non-blocking provider LoadedMessage synchronization', () {
    test(
      'LoadedMessage("all") refreshes full provider list without querying single "all" provider',
      () async {
        final singleQueries = <String>[];
        var fullHydrations = 0;
        var groupsDebounced = 0;

        await dispatchLoadedProviderEvent(
          providerName: 'all',
          isCurrent: () => true,
          getExternalProvider: (name) async {
            singleQueries.add(name);
            return null;
          },
          hasExistingProvider: (_) => false,
          setProvider: (_) => fail('setProvider should not run for "all"'),
          updateProviders: () async {
            fullHydrations++;
          },
          updateGroupsDebounce: () {
            groupsDebounced++;
          },
        );

        expect(singleQueries, isEmpty);
        expect(fullHydrations, 1);
        expect(groupsDebounced, 1);
      },
    );

    test(
      'background provider completion updates slot in-place when provider list is already hydrated',
      () async {
        final updated = <ExternalProvider>[];
        var fullHydrations = 0;
        var groupsDebounced = 0;

        await dispatchLoadedProviderEvent(
          providerName: 'remote-proxies',
          isCurrent: () => true,
          getExternalProvider: (name) async => _sampleProvider(name, count: 12),
          hasExistingProvider: (name) => name == 'remote-proxies',
          setProvider: updated.add,
          updateProviders: () async {
            fullHydrations++;
          },
          updateGroupsDebounce: () {
            groupsDebounced++;
          },
        );

        expect(fullHydrations, 0);
        expect(updated, hasLength(1));
        expect(updated.single.name, 'remote-proxies');
        expect(updated.single.count, 12);
        expect(groupsDebounced, 1);
      },
    );

    test(
      'background provider completion before initial list hydration triggers full updateProviders instead of dropping entry',
      () async {
        final updated = <ExternalProvider>[];
        var fullHydrations = 0;
        var groupsDebounced = 0;

        await dispatchLoadedProviderEvent(
          providerName: 'remote-proxies',
          isCurrent: () => true,
          getExternalProvider: (name) async => _sampleProvider(name, count: 8),
          hasExistingProvider: (_) => false,
          setProvider: updated.add,
          updateProviders: () async {
            fullHydrations++;
          },
          updateGroupsDebounce: () {
            groupsDebounced++;
          },
        );

        expect(updated, isEmpty);
        expect(fullHydrations, 1);
        expect(groupsDebounced, 1);
      },
    );

    test(
      'stale config epoch and transient IPC errors are ignored without throwing unhandled exceptions',
      () async {
        var isCurrent = false;
        var groupsDebounced = 0;

        await dispatchLoadedProviderEvent(
          providerName: 'remote-proxies',
          isCurrent: () => isCurrent,
          getExternalProvider: (name) async => _sampleProvider(name),
          hasExistingProvider: (_) => true,
          setProvider: (_) => fail('stale epoch must not mutate state'),
          updateProviders: () async => fail('stale epoch must not hydrate'),
          updateGroupsDebounce: () {
            groupsDebounced++;
          },
        );
        expect(groupsDebounced, 0);

        isCurrent = true;
        await expectLater(
          dispatchLoadedProviderEvent(
            providerName: 'remote-proxies',
            isCurrent: () => isCurrent,
            getExternalProvider: (_) async =>
                throw StateError('IPC disconnected mid-query'),
            hasExistingProvider: (_) => true,
            setProvider: (_) => fail('error path must not mutate state'),
            updateProviders: () async {},
            updateGroupsDebounce: () {
              groupsDebounced++;
            },
          ),
          completes,
        );
        expect(groupsDebounced, 0);
      },
    );

    test(
      'reflectWindowsTunRunning marks proxy/TUN running immediately without waiting on stalled updateProviders',
      () async {
        final stalledProviders = Completer<void>();
        var markedRunning = false;
        var iconConnected = false;

        final watch = Stopwatch()..start();
        await reflectWindowsTunRunning(
          isCurrent: () => true,
          syncUiActive: () async {},
          syncLogStream: () {},
          initForegroundCache: () {},
          showConnectedIcon: () async {
            iconConnected = true;
          },
          markRunningNow: () {
            markedRunning = true;
          },
          updateGroups: () async {},
          updateProviders: () => stalledProviders.future,
        );
        watch.stop();

        expect(markedRunning, isTrue);
        expect(iconConnected, isTrue);
        expect(watch.elapsedMilliseconds, lessThan(100));

        stalledProviders.complete();
        await Future<void>.delayed(Duration.zero);
      },
    );
  });
}

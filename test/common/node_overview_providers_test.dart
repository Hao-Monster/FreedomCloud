import 'dart:async';

import 'package:flclashx/common/node_catalog_service.dart';
import 'package:flclashx/common/node_health_store.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/models/node_catalog.dart';
import 'package:flclashx/providers/node_overview.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const a = Profile(id: 'a', autoUpdateDuration: Duration.zero);
  Map<String, dynamic> raw(String name) => {
        'proxies': [
          {
            'name': name,
            'type': 'ss',
            'server': 'fixture.invalid',
            'port': 443
          },
        ]
      };
  late ProviderContainer container;
  var reads = 0;
  var built = 0;
  Future<Map<String, dynamic>> Function(String)? reader;

  setUp(() {
    reads = built = 0;
    reader = null;
    globalState.config =
        const Config(themeProps: defaultThemeProps, profiles: [a]);
    container = ProviderContainer(overrides: [
      nodeOverviewEnabledProvider.overrideWithValue(true),
      nodeCatalogServiceFactoryProvider.overrideWithValue(() {
        built++;
        return NodeCatalogService(
          fileMetadata: (_) async => (modifiedMicros: 1, size: 20),
          scriptFingerprint: () => 'fixed-for-test',
          readProfileConfig: (id) {
            reads++;
            return reader?.call(id) ?? Future.value(raw('node-$reads'));
          },
          evaluate: (value) async => value,
        );
      }),
    ]);
  });
  tearDown(() => container.dispose());

  test('tester profile guard ignores display metadata but revokes definitions',
      () async {
    final isolated = ProviderContainer(overrides: [
      nodeHealthStoreProvider.overrideWith((ref) => NodeHealthStore(
          fileProvider: () => throw StateError('No storage read expected'))),
      nodeCatalogServiceFactoryProvider.overrideWithValue(() =>
          NodeCatalogService(
              readProfileConfig: (_) async => raw('fixture'),
              evaluate: (r) async => r,
              fileMetadata: (_) async => (modifiedMicros: 1, size: 2),
              scriptFingerprint: () => '')),
    ]);
    addTearDown(isolated.dispose);
    final subscription = isolated.listen(nodeCatalogTesterProvider, (_, __) {});
    addTearDown(subscription.close);
    final tester = isolated.read(nodeCatalogTesterProvider);
    expect(tester.isCurrentProfile(a), isTrue);
    isolated.read(profilesProvider.notifier).setProfile(a.copyWith(
        label: 'Renamed',
        selectedMap: {'group': 'node'},
        unfoldSet: {'group'}));
    expect(tester.isCurrentProfile(a), isTrue);
    for (final changed in [
      a.copyWith(url: 'https://fixture.invalid/new'),
      a.copyWith(lastUpdateDate: DateTime.utc(2026)),
      a.copyWith(isUpdating: true)
    ]) {
      isolated.read(profilesProvider.notifier).setProfile(changed);
      expect(tester.isCurrentProfile(a), isFalse);
    }
    isolated.read(profilesProvider.notifier).value = [];
    expect(tester.isCurrentProfile(a), isFalse);
  });

  test(
      'real provider invalidates URL/date/update/script changes and preserves updating snapshot',
      () async {
    final subscription =
        container.listen(profileCatalogProvider('a'), (_, __) {});
    addTearDown(subscription.close);
    await container.read(profileCatalogProvider('a').future);
    expect(reads, 1);
    container
        .read(profilesProvider.notifier)
        .setProfile(a.copyWith(url: 'https://fixture.invalid/sub'));
    await container.read(profileCatalogProvider('a').future);
    expect(reads, 2);
    final changed = a.copyWith(lastUpdateDate: DateTime.utc(2026, 10, 15));
    container.read(profilesProvider.notifier).setProfile(changed);
    await container.read(profileCatalogProvider('a').future);
    expect(reads, 3);
    container
        .read(profilesProvider.notifier)
        .setProfile(changed.copyWith(isUpdating: true));
    final updating = await container.read(profileCatalogProvider('a').future);
    expect(updating.status, ProfileCatalogStatus.updating);
    expect(updating.nodes.single.name, 'node-3');
    expect(reads, 3);
    container.read(profilesProvider.notifier).setProfile(changed);
    await container.read(profileCatalogProvider('a').future);
    expect(reads, 4);
    container.read(scriptStateProvider.notifier).value =
        const ScriptProps(currentId: 's', scripts: [
      Script(id: 's', label: 'test', content: 'function main(c) { return c; }')
    ]);
    await container.read(profileCatalogProvider('a').future);
    expect(reads, 5,
        reason: 'real wiring must invalidate even with equal file metadata');
    expect(built, 1);
  });

  test('UI directory cache retains only eight complete catalogs', () async {
    container.read(profilesProvider.notifier).value = [
      for (var i = 0; i < 12; i++) a.copyWith(id: '$i'),
    ];
    for (var i = 0; i < 12; i++) {
      await container.read(profileCatalogProvider('$i').future);
    }
    expect(container.read(cachedProfileCatalogsProvider).keys,
        ['4', '5', '6', '7', '8', '9', '10', '11']);
    expect(container.read(nodeCatalogServiceProvider).peek('0'), isNull);
  });

  test('disposed pending catalog cannot repopulate UI cache', () async {
    final reply = Completer<Map<String, dynamic>>();
    reader = (_) => reply.future;
    final subscription =
        container.listen(profileCatalogProvider('a'), (_, __) {});
    final pending = container.read(profileCatalogProvider('a').future);
    await Future<void>.delayed(Duration.zero);
    subscription.close();
    await container.pump();
    reply.complete(raw('old'));
    await pending;
    expect(container.read(cachedProfileCatalogsProvider), isEmpty);
  });
}

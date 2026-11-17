import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flclashx/clash/core.dart';
import 'package:flclashx/clash/interface.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/controller.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

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

class _ProvidersTransport extends ClashHandlerInterface {
  Future<String> Function()? onGetExternalProviders;

  @override
  FutureOr<String> getExternalProviders() {
    final handler = onGetExternalProviders;
    if (handler != null) {
      return handler();
    }
    return '';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'AppController.updateProviders catches IPC exceptions and preserves prior providers state',
    (tester) async {
      final tempDir = await tester.runAsync(
        () => Directory.systemTemp.createTemp('fcx_providers_test_'),
      );
      final originalPaths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _TestPaths(tempDir!.path);

      globalState.appState = AppState(
        version: 0,
        viewSize: Size.zero,
        requests: FixedList(10),
        logs: FixedList(10),
        traffics: FixedList(10),
        totalTraffic: Traffic(),
      );

      final previousCore = ClashCore.existingCore;
      final transport = _ProvidersTransport();
      ClashCore.instanceForTesting = ClashCore.forTesting(transport);
      addTearDown(() async {
        ClashCore.instanceForTesting = previousCore;
        PathProviderPlatform.instance = originalPaths;
        await tester.runAsync(() => tempDir.delete(recursive: true));
      });

      const profile = Profile(
        id: 'p-providers',
        label: 'Providers Profile',
        url: 'https://sub.example.com/providers',
        autoUpdateDuration: Duration(hours: 24),
      );
      globalState.config = Config(
        themeProps: defaultThemeProps,
        profiles: [profile],
        currentProfileId: profile.id,
      );

      AppController? controller;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                controller ??= AppController(context, ref);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SizedBox)),
      );
      final seededProvider = ExternalProvider(
        name: 'seeded-rules',
        type: 'Rule',
        vehicleType: 'HTTP',
        count: 42,
        updateAt: DateTime.utc(2026, 11, 7, 8, 0, 0),
      );
      container.read(providersProvider.notifier).value = [seededProvider];

      // 1. Transient IPC failure during Core restart/shutdown must NOT throw and must preserve seeded state.
      transport.onGetExternalProviders = () async {
        throw const SocketException('IPC pipe closed during Core restart');
      };
      await expectLater(controller!.updateProviders(), completes);
      expect(
        container.read(providersProvider).map((p) => p.name).toList(),
        equals(['seeded-rules']),
      );

      // 2. Stale response arriving after runtimeConfigEpoch advances must be ignored.
      await tester.runAsync(() async {
        final gate = Completer<String>();
        transport.onGetExternalProviders = () => gate.future;
        final inFlight = controller!.updateProviders();
        globalState.runtimeConfigEpoch++;
        gate.complete(
          jsonEncode([
            <String, Object?>{
              'name': 'stale-provider',
              'type': 'Proxy',
              'vehicle-type': 'HTTP',
              'count': 5,
              'update-at': '2026-11-07T08:05:00Z',
            },
          ]),
        );
        await inFlight;
      });
      expect(
        container.read(providersProvider).map((p) => p.name).toList(),
        equals(['seeded-rules']),
      );

      // 3. Normal response updates providersProvider cleanly.
      await tester.runAsync(() async {
        transport.onGetExternalProviders = () async => jsonEncode([
              <String, Object?>{
                'name': 'fresh-provider',
                'type': 'Proxy',
                'vehicle-type': 'HTTP',
                'count': 12,
                'update-at': '2026-11-07T08:10:00Z',
              },
            ]);
        await controller!.updateProviders();
      });
      expect(
        container.read(providersProvider).map((p) => p.name).toList(),
        equals(['fresh-provider']),
      );

      await tester.pump(const Duration(seconds: 2));
    },
  );
}

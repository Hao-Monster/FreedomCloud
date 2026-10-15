import 'dart:io';
import 'dart:ui' as ui;

import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/node_health_store.dart';
import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/models/node_catalog.dart';
import 'package:flclashx/providers/node_overview.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/views/proxies/overview/overview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

  for (final size in [const Size(400, 800), const Size(1200, 900)]) {
    testWidgets('render overview ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
      await AppLocalizations.load(const Locale('en'));
      const profiles = [
        Profile(
            id: 'a', label: 'Alpha profile', autoUpdateDuration: Duration.zero),
        Profile(
            id: 'b', label: 'Beta profile', autoUpdateDuration: Duration.zero),
      ];
      globalState.config =
          const Config(themeProps: defaultThemeProps, profiles: profiles);
      globalState.appState = AppState(
          viewSize: size,
          version: 1,
          requests: FixedList(1),
          logs: FixedList(1),
          traffics: FixedList(1),
          totalTraffic: Traffic());
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
            cachedProfileCatalogsProvider.overrideWith((ref) => catalogs),
            profileCatalogProvider
                .overrideWith((ref, id) async => catalogs[id]!),
            nodeHealthEntriesProvider
                .overrideWith((ref, id) => health[id] ?? {}),
          ],
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
            home: const Scaffold(
                body: RepaintBoundary(
                    key: ValueKey('overview-render'),
                    child: Material(
                        child: NodeOverviewScopeView(
                            currentView: Text('Existing proxy view'))))),
          )));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All profiles'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('overview-header-a')));
      await tester.pumpAndSettle();
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
}

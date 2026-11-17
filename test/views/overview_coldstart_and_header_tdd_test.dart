import 'dart:async';
import 'dart:io';

import 'package:flclashx/clash/clash.dart';
import 'package:flclashx/clash/interface.dart';
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
import 'package:flclashx/views/proxies/overview/overview.dart';
import 'package:flclashx/widgets/keep_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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

class _ColdStartFakeClashHandler extends ClashHandlerInterface {
  _ColdStartFakeClashHandler({
    this.notReadyReason,
    this.failSendOnGetConfig = false,
    required this.configsByPathFragment,
  });

  String? notReadyReason;
  bool failSendOnGetConfig;
  final Map<String, Object> configsByPathFragment;
  int getConfigCalls = 0;

  @override
  String? get tunTransportNotReadyReason => notReadyReason;

  @override
  FutureOr<void> sendMessage(String message) {
    if (failSendOnGetConfig) {
      throw StateError('Simulated IPC socket closed');
    }
  }

  @override
  FutureOr<bool> reStart() => true;

  @override
  FutureOr<bool> destroy() => true;

  @override
  Future<Result> getConfig(String path) async {
    getConfigCalls++;
    if (failSendOnGetConfig) {
      return super.getConfig(path);
    }
    final preflight = tunTransportNotReadyReason;
    if (preflight != null) {
      return Result.error('not_ready:$preflight');
    }
    for (final entry in configsByPathFragment.entries) {
      if (path.contains(entry.key)) {
        final value = entry.value;
        if (value is Result) return value;
        if (value is Map<String, dynamic>) return Result.success(value);
      }
    }
    return Result.error('yaml: unmarshal errors: invalid config for $path');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _NoopCatalogTester extends ChangeNotifier implements NodeCatalogTester {
  @override
  bool busy = false;

  @override
  int completed = 0;

  @override
  int total = 0;

  @override
  bool Function(Profile profile) get isCurrentProfile => (_) => true;

  @override
  Set<String> pendingIdentitySnapshot(String profileId) => const <String>{};

  @override
  bool pending(String profileId, String identityKey) => false;

  @override
  Future<DelayBatchResult> testCurrent(Iterable<DelayTestTarget> targets) async =>
      const DelayBatchResult(completed: 0, failed: 0);

  @override
  Future<DelayBatchResult> testAll(List<Profile> profiles, String url) async =>
      const DelayBatchResult(completed: 0, failed: 0);

  @override
  Future<DelayBatchResult> collectAndTest(
    Future<List<CatalogTestSelection>> Function(bool Function() isCurrent) collect,
    String url,
  ) async =>
      testVisible(await collect(() => true), url);

  @override
  Future<DelayBatchResult> testVisible(
    List<CatalogTestSelection> selections,
    String url,
  ) async =>
      const DelayBatchResult(completed: 0, failed: 0);

  @override
  Future<void> cancel({String reason = 'cancelled'}) async {}

  @override
  void profileChanged(String id) {}

  @override
  void disposeScope() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeOverviewAppController implements AppController {
  @override
  void toPage(PageLabel pageLabel) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = _TestPaths(Directory.systemTemp.path);

  const profileActive = Profile(
    id: 'junxiong',
    label: '俊雄',
    url: 'https://fixture.invalid/junxiong',
    autoUpdateDuration: Duration.zero,
  );
  const profileLondon = Profile(
    id: 'london',
    label: '伦敦',
    url: 'https://fixture.invalid/london',
    autoUpdateDuration: Duration.zero,
  );
  const profileYidian = Profile(
    id: 'yidian',
    label: 'Yidian-Cloud',
    url: 'https://fixture.invalid/yidian',
    autoUpdateDuration: Duration.zero,
  );
  const profileFreedom = Profile(
    id: 'freedom',
    label: 'FreedomCloud',
    autoUpdateDuration: Duration.zero,
  );
  const profileBroken = Profile(
    id: 'broken',
    label: '损坏订阅',
    url: 'https://fixture.invalid/broken',
    autoUpdateDuration: Duration.zero,
  );

  File dummyHealthFile() =>
      File('${Directory.systemTemp.path}/fcx-tdd-noop-health.json');

  setUp(() async {
    await AppLocalizations.load(const Locale('zh', 'CN'));
    globalState.appController = _FakeOverviewAppController();
    globalState.lastRuntimeConfig = null;
    globalState.lastRuntimeProfileId = null;
    globalState.config = const Config(
      themeProps: defaultThemeProps,
      profiles: [profileActive, profileLondon],
      currentProfileId: 'junxiong',
    );
    globalState.appState = AppState(
      pageLabel: PageLabel.proxies,
      viewSize: const Size(1280, 900),
      version: 1,
      isInit: false,
      requests: FixedList(1),
      logs: FixedList(1),
      traffics: FixedList(1),
      totalTraffic: Traffic(),
    );
  });

  tearDown(() async {
    ClashCore.instanceForTesting = null;
    await AppLocalizations.load(const Locale('en'));
  });

  test('TDD-1: ActionResultExt.toResult safely coerces non-String error payload and ClashHandlerInterface.getConfig reports not_ready on transport drop', () async {
    final nonStringError = const ActionResult(
      id: 'getConfig#1',
      method: ActionMethod.getConfig,
      code: ResultType.error,
      data: <String, dynamic>{},
    ).toResult;
    expect(nonStringError.isError, isTrue);
    expect(nonStringError.message, isA<String>());

    final handler = _ColdStartFakeClashHandler(
      failSendOnGetConfig: true,
      configsByPathFragment: const {},
    );
    final res = await handler.getConfig('C:/profiles/london.yaml');
    expect(res.isError, isTrue);
    expect(
      res.message,
      startsWith('not_ready:'),
      reason: 'Disconnected/deferred cold-start IPC must report not_ready:* instead of getConfig timed out',
    );
  });

  testWidgets('TDD-2: Cold-start unready Core never flashes or caches 配置解析失败, recovers automatically when Core initializes, and still flags real YAML errors', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));

    final handler = _ColdStartFakeClashHandler(
      notReadyReason: 'deferred_cold_start',
      configsByPathFragment: <String, Object>{
        'junxiong': <String, dynamic>{
          'proxies': [
            {
              'name': '443-俊雄搬瓦工2',
              'type': 'ss',
              'server': 'us.fixture.invalid',
              'port': 443,
            },
          ],
        },
        'london': <String, dynamic>{
          'proxies': [
            {
              'name': '英国-London-IEPL-01',
              'type': 'ss',
              'server': 'uk.fixture.invalid',
              'port': 443,
            },
          ],
        },
        'broken': Result.error('yaml: line 2: mapping values are not allowed in this context'),
      },
    );
    ClashCore.instanceForTesting = ClashCore.forTesting(handler);

    globalState.config = globalState.config.copyWith(
      profiles: const [profileActive, profileLondon, profileBroken],
      currentProfileId: 'junxiong',
    );

    final container = ProviderContainer(
      overrides: [
        nodeOverviewEnabledProvider.overrideWithValue(true),
        activeNodeCatalogProvider.overrideWithValue(null),
        nodeCatalogTesterProvider.overrideWith((ref) => _NoopCatalogTester()),
        nodeHealthStoreProvider.overrideWith(
          (ref) => NodeHealthStore(fileProvider: () async => dummyHealthFile()),
        ),
        nodeHealthEntriesProvider.overrideWith((ref, id) => const {}),
        nodeCatalogServiceFactoryProvider.overrideWith(
          (ref) => () => NodeCatalogService(
                readProfileConfig: (id) async {
                  if (ClashCore.existingInterface == null) {
                    throw const CatalogBuildException('runtimeUnavailable');
                  }
                  try {
                    return await globalState.getProfileConfig(id);
                  } catch (error) {
                    if (error is String && error.startsWith('not_ready:')) {
                      throw const CatalogBuildException('runtimeUnavailable');
                    }
                    rethrow;
                  }
                },
                evaluate: (raw) async => raw,
                fileMetadata: (_) async => (modifiedMicros: 100, size: 64),
                scriptFingerprint: () => 'test-fp',
                onProxiesEvaluated: (profileId, proxies) => ref
                    .read(nodeCountryResolverProvider)
                    .registerProxyMaps(profileId, proxies),
              ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.delegate.supportedLocales,
          theme: buildFreedomNetThemeData(
            colorScheme: container.read(genColorSchemeProvider(Brightness.light)),
          ),
          home: const Scaffold(body: NodeOverviewView()),
        ),
      ),
    );

    // Pump initial layout + country index scan while Core is still deferred_cold_start.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.text(appLocalizations.nodeOverviewParseFailed),
      findsNothing,
      reason: 'Cold-start Core unavailability must never show false 配置解析失败 on any profile',
    );
    expect(
      container.read(cachedProfileCatalogsProvider).values.where(
            (c) => c.status == ProfileCatalogStatus.parseFailed,
          ),
      isEmpty,
      reason: 'cachedProfileCatalogsProvider must not be poisoned during cold-start',
    );

    // Now simulate Core initialization finishing (`notReadyReason = null` + `initProvider = true`).
    handler.notReadyReason = null;
    container.read(initProvider.notifier).value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    // Healthy inactive profile `伦敦` must now render its node automatically without manual refresh.
    expect(find.text('英国-London-IEPL-01'), findsOneWidget);
    // Country filter bar must also have indexed `英国` automatically on recovery.
    expect(find.textContaining('英国'), findsWidgets);
    // Genuine YAML error on `损坏订阅` must still display `配置解析失败`.
    expect(find.text(appLocalizations.nodeOverviewParseFailed), findsWidgets);
  });

  testWidgets('TDD-3: Switching from Dark + PureBlack (#000000) to Light (#F4F6FA) across PageView KeepScope & off-viewport SliverMainAxisGroup headers leaves zero #000000 black header blocks', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));

    const profileAdmin = Profile(
      id: 'admin',
      label: 'admin',
      url: 'https://fixture.invalid/admin',
      autoUpdateDuration: Duration.zero,
    );
    final profiles = [
      profileAdmin,
      profileActive,
      profileLondon,
      profileYidian,
      profileFreedom,
    ];
    globalState.config = globalState.config.copyWith(
      profiles: profiles,
      currentProfileId: 'junxiong',
      themeProps: defaultThemeProps.copyWith(
        themeMode: ThemeMode.dark,
        pureBlack: true,
      ),
    );
    globalState.appState = globalState.appState.copyWith(isInit: true);

    final pageController = PageController(initialPage: 0);
    addTearDown(pageController.dispose);
    final activePage = ValueNotifier<int>(0);
    addTearDown(activePage.dispose);

    final adminNodes = <CatalogNode>[
      for (var i = 0; i < 38; i++)
        CatalogNode(
          identityKey: 'admin-$i',
          endpointKey: 'de-$i.fixture.invalid:443',
          name: '德国SuperLine-$i',
          type: 'hysteria2',
          source: CatalogNodeSource.inline,
        ),
    ];

    final container = ProviderContainer(
      overrides: [
        nodeOverviewEnabledProvider.overrideWithValue(true),
        activeNodeCatalogProvider.overrideWithValue(null),
        nodeCatalogTesterProvider.overrideWith((ref) => _NoopCatalogTester()),
        nodeHealthStoreProvider.overrideWith(
          (ref) => NodeHealthStore(fileProvider: () async => dummyHealthFile()),
        ),
        nodeHealthEntriesProvider.overrideWith((ref, id) => const {}),
        profileCatalogProvider.overrideWith(
          (ref, id) async => ProfileCatalog(
            profileId: id,
            fingerprint: 'fp-$id',
            status: ProfileCatalogStatus.ready,
            nodes: id == 'admin' ? adminNodes : const <CatalogNode>[],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) {
            final themeProps = ref.watch(themeSettingProvider);
            return MaterialApp(
              locale: const Locale('zh', 'CN'),
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.delegate.supportedLocales,
              themeMode: themeProps.themeMode,
              theme: buildFreedomNetThemeData(
                colorScheme: ref.watch(genColorSchemeProvider(Brightness.light)),
              ),
              darkTheme: buildFreedomNetThemeData(
                colorScheme: ref
                    .watch(genColorSchemeProvider(Brightness.dark))
                    .toPureBlack(themeProps.pureBlack),
              ),
              home: Scaffold(
                body: ValueListenableBuilder<int>(
                  valueListenable: activePage,
                  builder: (context, currentIndex, _) => PageView.builder(
                    controller: pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 8,
                    itemBuilder: (_, index) {
                      final isActive = index == currentIndex;
                      return ExcludeFocus(
                        excluding: !isActive,
                        child: TickerMode(
                          enabled: isActive,
                          child: KeepScope(
                            key: ValueKey('tab-$index'),
                            keep: index == 0,
                            child: index == 0
                                ? const NodeOverviewView()
                                : Center(child: Text('Tab $index')),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    // Scroll down in Dark + PureBlack (#000000) so `伦敦`, `Yidian-Cloud`, `FreedomCloud`
    // build their SliverPersistentHeader children in PureBlack (#000000), then scroll back to top.
    final customScrollFinder = find.descendant(
      of: find.byType(NodeOverviewView),
      matching: find.byType(CustomScrollView),
    );
    final scrollableState = tester.state<ScrollableState>(
      find.descendant(
        of: customScrollFinder,
        matching: find.byType(Scrollable),
      ),
    );
    scrollableState.position.jumpTo(scrollableState.position.maxScrollExtent);
    await tester.pump();
    scrollableState.position.jumpTo(0);
    await tester.pump();

    // 1. User navigates to Settings tab (page 7, >1 viewport away so page 0 enters KeepAlive bucket + TickerMode(enabled: false)).
    activePage.value = 7;
    pageController.jumpToPage(7);
    await tester.pump();

    // 2. User switches from Dark + PureBlack (#000000) to Light Mode (#F4F6FA) in Settings -> Theme.
    container.read(themeSettingProvider.notifier).updateState(
          (state) => state.copyWith(
            themeMode: ThemeMode.light,
            pureBlack: false,
          ),
        );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 3. User clicks back to Proxies tab (page 0) and scrolls down to `伦敦`, `Yidian-Cloud`, `FreedomCloud`.
    activePage.value = 0;
    pageController.jumpToPage(0);
    await tester.pump();
    scrollableState.position.jumpTo(scrollableState.position.maxScrollExtent);
    await tester.pump();

    for (final profile in [profileLondon, profileYidian, profileFreedom]) {
      final headerFinder = find.byKey(ValueKey('overview-header-${profile.id}'));
      expect(headerFinder, findsOneWidget);

      final headerMaterialFinder = find
          .ancestor(
            of: headerFinder,
            matching: find.byType(Material),
          )
          .first;
      final renderPhysical = tester.renderObject<RenderPhysicalModel>(
        headerMaterialFinder,
      );
      expect(
        renderPhysical.color,
        equals(kFreedomNetLightCanvas),
        reason: 'Rendered header surface for ${profile.label} must be Light canvas #F4F6FA, never #000000 black!',
      );
    }
  });
}

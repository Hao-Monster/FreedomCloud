import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/delay_test_coordinator.dart';
import 'package:flclashx/common/node_catalog_tester.dart';
import 'package:flclashx/common/smart_node_selection.dart';
import 'package:flclashx/common/theme.dart';
import 'package:flclashx/controller.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/models/node_catalog.dart';
import 'package:flclashx/models/xboard.dart';
import 'package:flclashx/pages/home.dart';
import 'package:flclashx/providers/node_overview.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/services/purchase_profile_sync.dart';
import 'package:flclashx/services/purchase_storage.dart';
import 'package:flclashx/services/xboard_api.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/views/dashboard/widgets/hero_nav_bar.dart';
import 'package:flclashx/views/profiles/add_profile.dart';
import 'package:flclashx/views/proxies/overview/overview.dart';
import 'package:flclashx/views/proxies/proxies.dart';
import 'package:flclashx/views/purchase.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestAppController extends Fake implements AppController {
  _TestAppController(this.ref, {this.onUpdateStatus});

  final WidgetRef ref;
  final Future<void> Function(bool isStart)? onUpdateStatus;
  final List<PageLabel> navigatedPages = <PageLabel>[];
  final List<bool> updateStatusCalls = <bool>[];
  final List<Profile> addedProfiles = <Profile>[];
  final List<String> eventLog = <String>[];

  @override
  void toPage(PageLabel pageLabel) {
    navigatedPages.add(pageLabel);
    if (!noviceVisiblePageLabels.contains(pageLabel)) {
      ref.read(expertNavigationExpandedProvider.notifier).state = true;
    }
    ref.read(currentPageLabelProvider.notifier).value = pageLabel;
  }

  @override
  Future<void> updateStatus(bool isStart) async {
    eventLog.add('updateStatus:$isStart');
    updateStatusCalls.add(isStart);
    if (onUpdateStatus != null) {
      await onUpdateStatus!(isStart);
    }
    globalState.startTime = isStart ? DateTime.now() : null;
    ref.read(runTimeProvider.notifier).value = isStart ? 1000 : null;
  }

  @override
  Future<void> addProfile(Profile profile) async {
    final effectiveProfile =
        !profile.providerHeaders.containsKey(smartSelectionModeMarker) &&
                profile.selectedMap.isEmpty
            ? markProfileSelectionMode(profile, NodeSelectionMode.smart)
            : profile;
    addedProfiles.add(effectiveProfile);
    ref.read(profilesProvider.notifier).setProfile(effectiveProfile);
    if (ref.read(currentProfileIdProvider) == null) {
      ref.read(currentProfileIdProvider.notifier).value = effectiveProfile.id;
    }
  }

  @override
  void setProfileAndAutoApply(Profile profile) {
    ref.read(profilesProvider.notifier).setProfile(profile);
  }

  @override
  void updateCurrentSelectedMap(String groupName, String proxyName) {}

  @override
  void changeProxyDebounce(String groupName, String proxyName) {}

  @override
  void updateCurrentGroupName(String groupName) {}

  @override
  Future<Profile> registerImportedProfileForNovice(
    Profile profile, {
    bool isNewProfile = false,
    bool switchToProxiesPage = false,
  }) async {
    final hadZeroProfiles = ref.read(profilesProvider).isEmpty;
    final effectiveProfile =
        !profile.providerHeaders.containsKey(smartSelectionModeMarker) &&
                profile.selectedMap.isEmpty
            ? markProfileSelectionMode(profile, NodeSelectionMode.smart)
            : profile;
    final hadNoActiveProfile = ref.read(currentProfileIdProvider) == null;
    if (isNewProfile || hadNoActiveProfile) {
      await addProfile(effectiveProfile);
    } else {
      setProfileAndAutoApply(effectiveProfile);
    }
    if (hadZeroProfiles) {
      ref.read(pendingNoviceFirstProfileAutoTestProvider.notifier).state =
          effectiveProfile.id;
    }
    if (switchToProxiesPage) {
      ref.read(proxiesScopeProvider.notifier).state = ProxiesScope.all;
      toPage(PageLabel.proxies);
    }
    return effectiveProfile;
  }

  @override
  Future<void> tryStartProxyForActiveNoviceProfile(String profileId) async {
    final isActive = ref.read(currentProfileIdProvider) == profileId;
    if (!isActive || ref.read(runTimeProvider.notifier).isStart) {
      return;
    }
    try {
      await updateStatus(true);
    } catch (_) {}
  }

  @override
  Future<void> activateImportedProfileForNovice(
    Profile profile, {
    bool isNewProfile = false,
    bool switchToProxiesPage = false,
  }) async {
    final effectiveProfile = await registerImportedProfileForNovice(
      profile,
      isNewProfile: isNewProfile,
      switchToProxiesPage: switchToProxiesPage,
    );
    await tryStartProxyForActiveNoviceProfile(effectiveProfile.id);
  }
}

class _MemPurchaseStorage implements PurchaseStorage {
  PurchaseSession? session;
  final Map<int, PendingGiftRedemption> pending = <int, PendingGiftRedemption>{};
  final Map<int, String> profileIds = <int, String>{};

  @override
  Future<PurchaseSession?> readSession() async => session;

  @override
  Future<void> saveSession(PurchaseSession value) async {
    session = value;
  }

  @override
  Future<void> clearSession() async {
    session = null;
  }

  @override
  Future<PendingGiftRedemption?> readPending(int accountId) async =>
      pending[accountId];

  @override
  Future<void> savePending(int accountId, PendingGiftRedemption value) async {
    pending[accountId] = value;
  }

  @override
  Future<void> clearPending(int accountId) async {
    pending.remove(accountId);
  }

  @override
  Future<String?> readProfileId(int accountId) async => profileIds[accountId];

  @override
  Future<void> saveProfileId(int accountId, String profileId) async {
    profileIds[accountId] = profileId;
  }
}

class _FakeXboardApi implements XboardApi {
  _FakeXboardApi({required this.subscription});

  final XboardSubscription subscription;
  int loginCalls = 0;

  @override
  Uri get baseUri => Uri.parse('https://panel.example.test');

  @override
  Future<XboardPlanCatalog> getPlanCatalog() async =>
      const XboardPlanCatalog(plans: []);

  @override
  Future<String> login(String email, String password) async {
    loginCalls++;
    return 'Bearer token-42';
  }

  @override
  Future<XboardAccount> getAccount(String authorization) async =>
      const XboardAccount(id: 42, email: 'novice@example.test');

  @override
  Future<XboardSubscription> getSubscription(String authorization) async =>
      subscription;

  @override
  Future<GiftHistoryPage> getGiftHistory(String authorization,
          {int page = 1}) async =>
      GiftHistoryPage(entries: const [], page: page, lastPage: 1, total: 0);

  @override
  Future<Uri?> getCardStore(String authorization) async => null;

  @override
  Future<GiftPreview> checkGift(String authorization, String code) =>
      throw UnimplementedError();

  @override
  Future<GiftReceipt> redeemGift(String authorization, String code) =>
      throw UnimplementedError();

  @override
  Future<void> logout(String authorization) async {}

  @override
  void close() {}
}

class _SpyCatalogTester extends ChangeNotifier implements NodeCatalogTester {
  final List<List<Profile>> testedBatches = <List<Profile>>[];

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
  Future<DelayBatchResult> testAll(List<Profile> profiles, String url) async {
    testedBatches.add(List<Profile>.from(profiles));
    return const DelayBatchResult(completed: 1, failed: 0);
  }

  @override
  void disposeScope() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await AppLocalizations.load(const Locale('zh', 'CN'));
    globalState.config = const Config(themeProps: defaultThemeProps);
    globalState.appState = AppState(
      viewSize: const Size(1280, 900),
      pageLabel: PageLabel.proxies,
      version: 1,
      requests: FixedList(maxLength),
      logs: FixedList(maxLength),
      traffics: FixedList(30),
      totalTraffic: Traffic(),
      isInit: true,
    );
    globalState.startTime = null;
  });

  tearDown(() async {
    await AppLocalizations.load(const Locale('en'));
  });

  test(
      'Navigation order places proxies 1st, purchase 2nd, dashboard 3rd, and currentNavigationsState defaults to novice collapsed mode',
      () {
    final items = navigation.getItems(openLogs: true, hasProxies: true);
    final desktopLabels = items
        .where((item) => item.modes.contains(NavigationItemMode.desktop))
        .map((item) => item.label)
        .toList();

    expect(
      desktopLabels.take(3).toList(),
      equals([PageLabel.proxies, PageLabel.purchase, PageLabel.dashboard]),
    );
    expect(
      desktopLabels,
      equals([
        PageLabel.proxies,
        PageLabel.purchase,
        PageLabel.dashboard,
        PageLabel.profiles,
        PageLabel.connections,
        PageLabel.logs,
        PageLabel.tools,
      ]),
    );

    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Cold-start default is novice collapsed mode: only proxies and purchase.
    expect(container.read(expertNavigationExpandedProvider), isFalse);
    expect(
      container
          .read(currentNavigationsStateProvider)
          .value
          .map((e) => e.label)
          .toList(),
      equals([PageLabel.proxies, PageLabel.purchase]),
    );

    // Expanding expert mode exposes all desktop navigation items in order.
    container.read(expertNavigationExpandedProvider.notifier).state = true;
    expect(
      container
          .read(currentNavigationsStateProvider)
          .value
          .map((e) => e.label)
          .toList(),
      equals([
        PageLabel.proxies,
        PageLabel.purchase,
        PageLabel.dashboard,
        PageLabel.profiles,
        PageLabel.connections,
        PageLabel.tools,
      ]),
    );
  });

  testWidgets(
      'CommonNavigationBar removes nameless hamburger icon, toggles 大佬模式 <-> 小白模式, and returns from advanced pages to 代理 when collapsing',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    late _TestAppController controller;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.delegate.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) {
              globalState.measure = Measure.of(context, 1.0);
              globalState.theme = CommonTheme.of(context, 1.0);
              controller = _TestAppController(ref);
              globalState.appController = controller;
              final navItems = ref.watch(currentNavigationsStateProvider).value;
              final pageLabel = ref.watch(currentPageLabelProvider);
              final idx = navItems.indexWhere((e) => e.label == pageLabel);
              return Scaffold(
                body: Row(
                  children: [
                    CommonNavigationBar(
                      viewMode: ViewMode.desktop,
                      navigationItems: navItems,
                      currentIndex: idx < 0 ? 0 : idx,
                    ),
                    Expanded(child: Text('Current: ${pageLabel.name}')),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Nameless hamburger icon (Icons.menu) is removed.
    expect(find.byIcon(Icons.menu), findsNothing);

    // 2. Default collapsed state: only 代理 and 购买 are in NavigationRail, plus 大佬模式 toggle.
    final railCollapsed =
        tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(railCollapsed.destinations.length, 2);
    expect(find.text('代理'), findsOneWidget);
    expect(find.text('购买'), findsOneWidget);
    expect(find.text('仪表盘'), findsNothing);
    expect(find.text('设置'), findsNothing);

    final toggleFinder =
        find.byKey(const ValueKey('navigation-expert-mode-toggle'));
    expect(toggleFinder, findsOneWidget);
    expect(find.text('大佬模式'), findsOneWidget);
    expect(find.text('小白模式'), findsNothing);
    expect(find.byIcon(Icons.expand_more_rounded), findsOneWidget);

    // 3. Click 大佬模式 -> expands all items (代理, 购买, 仪表盘, 配置, 连接, 设置) & changes button to 小白模式.
    await tester.tap(toggleFinder);
    await tester.pumpAndSettle();

    final railExpanded =
        tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(railExpanded.destinations.length, 6);
    expect(find.text('仪表盘'), findsOneWidget);
    expect(find.text('配置'), findsOneWidget);
    expect(find.text('连接'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('小白模式'), findsOneWidget);
    expect(find.text('大佬模式'), findsNothing);
    expect(find.byIcon(Icons.expand_less_rounded), findsOneWidget);

    // 4. Navigate to 仪表盘 (3rd item) and set proxiesScope to current, then click 小白模式 ->
    // collapses rail AND automatically returns to 代理 (PageLabel.proxies) + ProxiesScope.all.
    final container =
        ProviderScope.containerOf(tester.element(find.byType(Scaffold)));
    container.read(currentPageLabelProvider.notifier).value =
        PageLabel.dashboard;
    container.read(proxiesScopeProvider.notifier).state = ProxiesScope.current;
    await tester.pumpAndSettle();
    expect(find.text('Current: dashboard'), findsOneWidget);

    await tester.tap(toggleFinder);
    await tester.pumpAndSettle();

    expect(container.read(expertNavigationExpandedProvider), isFalse);
    expect(container.read(currentPageLabelProvider), PageLabel.proxies);
    expect(container.read(proxiesScopeProvider), ProxiesScope.all);
    expect(find.text('Current: proxies'), findsOneWidget);
    expect(find.text('大佬模式'), findsOneWidget);
    expect(find.text('仪表盘'), findsNothing);

    // 5. If on 购买 (PageLabel.purchase) when collapsing from 大佬模式 -> stays on 购买!
    await tester.tap(toggleFinder); // expand
    await tester.pumpAndSettle();
    container.read(currentPageLabelProvider.notifier).value =
        PageLabel.purchase;
    await tester.pumpAndSettle();
    expect(find.text('Current: purchase'), findsOneWidget);

    await tester.tap(toggleFinder); // collapse while on purchase
    await tester.pumpAndSettle();
    expect(container.read(currentPageLabelProvider), PageLabel.purchase);
    expect(find.text('Current: purchase'), findsOneWidget);
  });

  testWidgets(
      'ProxiesView hides advanced top bar buttons in 小白模式 and reveals them in 大佬模式, and 0-profile URLFormDialog / empty card offer 去购买/兑换 shortcut',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final profileA = Profile.normal(
      label: 'Alpha',
      url: 'https://example.com/sub.yaml',
    ).copyWith(id: 'alpha');
    globalState.config = globalState.config.copyWith(
      profiles: [profileA],
      currentProfileId: 'alpha',
    );

    late _TestAppController controller;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nodeOverviewEnabledProvider.overrideWithValue(true),
          activeNodeCatalogProvider.overrideWithValue(null),
          cachedProfileCatalogsProvider.overrideWith(
            (ref) => {
              'alpha': const ProfileCatalog(
                profileId: 'alpha',
                fingerprint: 'fp',
                status: ProfileCatalogStatus.ready,
                nodes: [
                  CatalogNode(
                    identityKey: 'alpha::n1',
                    endpointKey: 'ep-n1',
                    name: '香港 01',
                    type: 'vless',
                    source: CatalogNodeSource.inline,
                    selectGroups: ['Proxy'],
                  ),
                ],
              ),
            },
          ),
          profileCatalogProvider.overrideWith(
            (ref, id) async =>
                ref.read(cachedProfileCatalogsProvider)[id] ??
                ProfileCatalog(
                  profileId: id,
                  fingerprint: '',
                  status: ProfileCatalogStatus.ready,
                ),
          ),
          nodeHealthEntriesProvider.overrideWith((ref, id) => const {}),
        ],
        child: MaterialApp(
          navigatorKey: globalState.navigatorKey,
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.delegate.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) {
              globalState.measure = Measure.of(context, 1.0);
              globalState.theme = CommonTheme.of(context, 1.0);
              controller = _TestAppController(ref);
              globalState.appController = controller;
              final navItems = ref.watch(currentNavigationsStateProvider).value;
              return CommonScaffold(
                key: globalState.homeScaffoldKey,
                title: '代理',
                sideNavigationBar: CommonNavigationBar(
                  viewMode: ViewMode.desktop,
                  navigationItems: navItems,
                  currentIndex: 0,
                ),
                body: const ProxiesView(),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // In default 小白模式, advanced AppBar controls are hidden.
    expect(find.byKey(const ValueKey('overview-scope-segments')), findsNothing);
    expect(find.byIcon(Icons.more_vert), findsNothing);

    // Click 大佬模式 -> advanced AppBar controls appear.
    await tester
        .tap(find.byKey(const ValueKey('navigation-expert-mode-toggle')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('overview-scope-segments')), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);

    // Open URLFormDialog via Step 1 添加订阅 -> has url-dialog-go-purchase button -> tapping navigates to 购买.
    await tester.tap(find.byKey(const ValueKey('overview-add-subscription')));
    await tester.pumpAndSettle();
    expect(find.byType(URLFormDialog), findsOneWidget);
    final goPurchaseInDialog =
        find.byKey(const ValueKey('url-dialog-go-purchase'));
    expect(goPurchaseInDialog, findsOneWidget);

    await tester.tap(goPurchaseInDialog);
    await tester.pumpAndSettle();
    expect(find.byType(URLFormDialog), findsNothing);
    expect(controller.navigatedPages.last, PageLabel.purchase);
  });

  testWidgets(
      '0-profile empty card offers 去购买/兑换 button, and purchase sync / deep-link import auto-activates Smart mode and starts proxy',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    globalState.config = globalState.config.copyWith(
      profiles: const [],
      currentProfileId: null,
    );

    late _TestAppController controller;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nodeOverviewEnabledProvider.overrideWithValue(true),
          activeNodeCatalogProvider.overrideWithValue(null),
          coldStartZeroProfilePromptedProvider.overrideWith((ref) => true),
          nodeCatalogTesterProvider.overrideWith((ref) => _SpyCatalogTester()),
          profileCatalogProvider.overrideWith(
            (ref, id) async => ProfileCatalog(
              profileId: id,
              fingerprint: 'fp',
              status: ProfileCatalogStatus.ready,
            ),
          ),
          nodeHealthEntriesProvider.overrideWith((ref, id) => const {}),
        ],
        child: MaterialApp(
          navigatorKey: globalState.navigatorKey,
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.delegate.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) {
              globalState.measure = Measure.of(context, 1.0);
              globalState.theme = CommonTheme.of(context, 1.0);
              controller = _TestAppController(ref);
              globalState.appController = controller;
              return const Scaffold(
                body: NodeOverviewView(),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Empty card has overview-empty-go-purchase shortcut.
    final emptyGoPurchase =
        find.byKey(const ValueKey('overview-empty-go-purchase'));
    expect(emptyGoPurchase, findsOneWidget);
    await tester.tap(emptyGoPurchase);
    await tester.pumpAndSettle();
    expect(controller.navigatedPages.last, PageLabel.purchase);

    // Simulate PurchaseProfileSynchronizer syncing a new subscription for a 0-profile novice user.
    final container =
        ProviderScope.containerOf(tester.element(find.byType(Scaffold)));
    final storage = _MemPurchaseStorage();
    final synchronizer = PurchaseProfileSynchronizer(
      origin: Uri.parse('https://panel.example.test'),
      storage: storage,
      readProfiles: () => container.read(profilesProvider),
      download: (target) async => target.copyWith(
        lastUpdateDate: DateTime.utc(2026, 11, 12),
      ),
      save: (updated) async {
        final beforeSave =
            container.read(profilesProvider).getProfile(updated.id);
        await controller.activateImportedProfileForNovice(
          updated,
          isNewProfile: beforeSave == null,
          switchToProxiesPage: true,
        );
      },
    );

    await synchronizer.synchronize(
      const XboardAccount(id: 42, email: 'novice@example.test'),
      XboardSubscription(
        valid: true,
        planId: 1,
        planName: 'Starter',
        url: Uri.parse('https://panel.example.test/api/v1/client/subscribe?token=t1'),
      ),
    );
    await tester.pumpAndSettle();

    final synced = container.read(profilesProvider).single;
    expect(resolveProfileSelectionMode(synced), NodeSelectionMode.smart);
    expect(container.read(currentProfileIdProvider), synced.id);
    expect(controller.updateStatusCalls, contains(true));
    expect(container.read(currentPageLabelProvider), PageLabel.proxies);

    // Subsequent sync preserves explicit manual mode marker on the profile.
    final manualProfile = markProfileSelectionMode(
      synced,
      NodeSelectionMode.manual,
      targetGroup: 'Proxy',
      manualNodeName: 'HK 01',
    );
    container.read(profilesProvider.notifier).setProfile(manualProfile);
    await synchronizer.synchronize(
      const XboardAccount(id: 42, email: 'novice@example.test'),
      XboardSubscription(
        valid: true,
        planId: 1,
        planName: 'Starter',
        url: Uri.parse('https://panel.example.test/api/v1/client/subscribe?token=t1'),
      ),
    );
    final resynced = container.read(profilesProvider).single;
    expect(resolveProfileSelectionMode(resynced), NodeSelectionMode.manual);
  });

  testWidgets(
      'CR-01: ViewMode.mobile (narrow <= 600px) exposes 大佬模式 <-> 小白模式 toggle in both classic NavigationBar and HeroNavBar without dead-ending',
      (tester) async {
    tester.view.physicalSize = const Size(430, 860);
    tester.view.devicePixelRatio = 1.0;
    globalState.appState = globalState.appState.copyWith(
      viewSize: const Size(430, 860),
    );
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // 1. Classic mobile NavigationBar (CommonNavigationBar with ViewMode.mobile).
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.delegate.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) {
              globalState.measure = Measure.of(context, 1.0);
              globalState.theme = CommonTheme.of(context, 1.0);
              globalState.appController = _TestAppController(ref);
              final navItems = ref.watch(currentNavigationsStateProvider).value;
              final pageLabel = ref.watch(currentPageLabelProvider);
              final idx = navItems.indexWhere((e) => e.label == pageLabel);
              return Scaffold(
                body: Center(child: Text('MobilePage:${pageLabel.name}')),
                bottomNavigationBar: CommonNavigationBar(
                  viewMode: ViewMode.mobile,
                  navigationItems: navItems,
                  currentIndex: idx < 0 ? 0 : idx,
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final toggleFinder =
        find.byKey(const ValueKey('navigation-expert-mode-toggle'));
    expect(toggleFinder, findsOneWidget);
    expect(find.text('大佬模式'), findsOneWidget);
    expect(find.text('设置'), findsNothing);

    await tester.tap(toggleFinder);
    await tester.pumpAndSettle();
    expect(find.text('小白模式'), findsOneWidget);
    expect(find.text('仪表盘'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Navigate to 设置 in mobile mode, then tap 小白模式 -> collapses and returns to 代理.
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('MobilePage:tools'), findsOneWidget);

    await tester.tap(toggleFinder);
    await tester.pumpAndSettle();
    expect(find.text('MobilePage:proxies'), findsOneWidget);
    expect(find.text('大佬模式'), findsOneWidget);

    // 2. HeroNavBar (newDashboard mobile bottom bar) also exposes the toggle.
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.delegate.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) {
              globalState.measure = Measure.of(context, 1.0);
              globalState.theme = CommonTheme.of(context, 1.0);
              globalState.appController = _TestAppController(ref);
              final pageLabel = ref.watch(currentPageLabelProvider);
              return Scaffold(
                body: Center(child: Text('HeroPage:${pageLabel.name}')),
                bottomNavigationBar: const HeroNavBar(),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(toggleFinder, findsOneWidget);
    await tester.tap(toggleFinder);
    await tester.pumpAndSettle();
    final heroContainer =
        ProviderScope.containerOf(tester.element(find.byType(HeroNavBar)));
    expect(heroContainer.read(expertNavigationExpandedProvider), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'CR-02: collapsing 小白模式 switches currentPageLabelProvider to proxies BEFORE shrinking currentNavigationsState, and HomePage handles initially collapsed advanced pageLabel safely',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // Start with appState.pageLabel = connections while expertNavigationExpanded is false:
    // HomePage must NOT crash with PageController(initialPage: -1).
    globalState.appState = globalState.appState.copyWith(
      pageLabel: PageLabel.connections,
    );

    final emissions = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nodeOverviewEnabledProvider.overrideWithValue(true),
          activeNodeCatalogProvider.overrideWithValue(null),
          coldStartZeroProfilePromptedProvider.overrideWith((ref) => true),
          nodeCatalogTesterProvider.overrideWith((ref) => _SpyCatalogTester()),
        ],
        child: MaterialApp(
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.delegate.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) {
              globalState.measure = Measure.of(context, 1.0);
              globalState.theme = CommonTheme.of(context, 1.0);
              globalState.appController = _TestAppController(ref);
              return const HomePage();
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final container =
        ProviderScope.containerOf(tester.element(find.byType(HomePage)));
    // Expand expert mode and navigate to connections (index 4).
    await tester
        .tap(find.byKey(const ValueKey('navigation-expert-mode-toggle')));
    await tester.pumpAndSettle();
    container.read(currentPageLabelProvider.notifier).value =
        PageLabel.connections;
    await tester.pumpAndSettle();

    final subPage = container.listen<PageLabel>(
      currentPageLabelProvider,
      (prev, next) => emissions.add('page:${next.name}'),
    );
    final subNav = container.listen<NavigationItemsState>(
      currentNavigationsStateProvider,
      (prev, next) => emissions.add('navLen:${next.value.length}'),
    );
    addTearDown(() {
      subPage.close();
      subNav.close();
    });

    // Collapse back to 小白模式 while on tools.
    await tester
        .tap(find.byKey(const ValueKey('navigation-expert-mode-toggle')));
    await tester.pumpAndSettle();

    expect(
      emissions,
      equals(['page:proxies', 'navLen:2']),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'CR-03: PurchaseView auto-syncs valid subscription on 0-profile login AND isolates proxy start errors from saveConfig & subscriptionSynced',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    globalState.config = globalState.config.copyWith(
      profiles: const [],
      currentProfileId: null,
    );

    final api = _FakeXboardApi(
      subscription: XboardSubscription(
        valid: true,
        planId: 7,
        planName: 'Pro Annual',
        url: Uri.parse(
            'https://panel.example.test/api/v1/client/subscribe?token=abc'),
      ),
    );
    final storage = _MemPurchaseStorage();
    final callOrder = <String>[];
    late _TestAppController controller;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.delegate.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) {
              globalState.measure = Measure.of(context, 1.0);
              globalState.theme = CommonTheme.of(context, 1.0);
              controller = _TestAppController(
                ref,
                onUpdateStatus: (isStart) async {
                  callOrder.add('updateStatus:$isStart');
                  throw StateError('Simulated UAC rejection');
                },
              );
              globalState.appController = controller;
              return Scaffold(
                body: PurchaseView(
                  apiOverride: api,
                  storageOverride: storage,
                  downloadOverride: (target) async => target.copyWith(
                    lastUpdateDate: DateTime.utc(2026, 11, 12),
                  ),
                  saveConfigOverride: (config) async {
                    callOrder.add('saveConfig:${config.profiles.length}');
                    return true;
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Enter credentials and log in on 0-profile install.
    await tester.enterText(
      find.byKey(const Key('purchase-email')),
      'novice@example.test',
    );
    await tester.enterText(
      find.byKey(const Key('purchase-password')),
      'secret123',
    );
    await tester.tap(find.byKey(const Key('purchase-login')));
    await tester.pumpAndSettle();

    final container =
        ProviderScope.containerOf(tester.element(find.byType(PurchaseView)));
    // 1. 0-profile login automatically synced the valid subscription without manual click!
    expect(container.read(profilesProvider), hasLength(1));
    final synced = container.read(profilesProvider).single;
    expect(resolveProfileSelectionMode(synced), NodeSelectionMode.smart);
    expect(container.read(currentProfileIdProvider), synced.id);

    // 2. saveConfig ran BEFORE updateStatus(true), and updateStatus throwing did NOT fail sync!
    expect(callOrder, equals(['saveConfig:1', 'updateStatus:true']));
    expect(find.textContaining('同步失败'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'CR-04 & CR-05: 小白模式 forces NodeOverviewView even if proxiesScopeProvider is current, and returning to 代理 after 0-profile PurchaseView sync auto-tests nodes',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final spyTester = _SpyCatalogTester();
    final api = _FakeXboardApi(
      subscription: XboardSubscription(
        valid: true,
        planId: 9,
        planName: 'Starter',
        url: Uri.parse(
            'https://panel.example.test/api/v1/client/subscribe?token=xyz'),
      ),
    );
    final storage = _MemPurchaseStorage();

    var showPurchase = true;
    late StateSetter setHostState;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nodeOverviewEnabledProvider.overrideWithValue(true),
          activeNodeCatalogProvider.overrideWithValue(null),
          coldStartZeroProfilePromptedProvider.overrideWith((ref) => true),
          nodeCatalogTesterProvider.overrideWith((ref) => spyTester),
          profileCatalogProvider.overrideWith(
            (ref, id) async => ProfileCatalog(
              profileId: id,
              fingerprint: 'fp',
              status: ProfileCatalogStatus.ready,
              nodes: [
                CatalogNode(
                  identityKey: '$id::hk1',
                  endpointKey: 'ep-hk1',
                  name: '香港 IPLC 01',
                  type: 'vless',
                  source: CatalogNodeSource.inline,
                  selectGroups: const ['Proxy'],
                ),
              ],
            ),
          ),
          nodeHealthEntriesProvider.overrideWith((ref, id) => const {}),
        ],
        child: MaterialApp(
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.delegate.supportedLocales,
          home: StatefulBuilder(
            builder: (context, setState) {
              setHostState = setState;
              return Consumer(
                builder: (context, ref, _) {
                  globalState.measure = Measure.of(context, 1.0);
                  globalState.theme = CommonTheme.of(context, 1.0);
                  globalState.appController = _TestAppController(ref);
                  final navItems =
                      ref.watch(currentNavigationsStateProvider).value;
                  return CommonScaffold(
                    title: showPurchase ? '购买' : '代理',
                    sideNavigationBar: CommonNavigationBar(
                      viewMode: ViewMode.desktop,
                      navigationItems: navItems,
                      currentIndex: showPurchase ? 1 : 0,
                    ),
                    body: Stack(
                      children: [
                        TickerMode(
                          enabled: !showPurchase,
                          child: const ProxiesView(),
                        ),
                        if (showPurchase)
                          PurchaseView(
                            apiOverride: api,
                            storageOverride: storage,
                            downloadOverride: (target) async => target.copyWith(
                              lastUpdateDate: DateTime.utc(2026, 11, 12),
                            ),
                            saveConfigOverride: (_) async => true,
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Log in on PurchaseView while 0 profiles exist -> auto-syncs first profile while ProxiesView is inactive.
    await tester.enterText(
      find.byKey(const Key('purchase-email')),
      'novice@example.test',
    );
    await tester.enterText(
      find.byKey(const Key('purchase-password')),
      'secret123',
    );
    await tester.tap(find.byKey(const Key('purchase-login')));
    await tester.pumpAndSettle();

    final container =
        ProviderScope.containerOf(tester.element(find.byType(ProxiesView)));
    expect(container.read(profilesProvider), hasLength(1));

    // Force proxiesScopeProvider to current while still in 小白模式 (CR-04).
    container.read(proxiesScopeProvider.notifier).state = ProxiesScope.current;

    // Switch back to 代理 page -> CR-04 keeps NodeOverviewView visible AND CR-05 runs auto-test!
    setHostState(() {
      showPurchase = false;
    });
    await tester.pumpAndSettle();

    expect(find.byType(NodeOverviewView), findsOneWidget);
    expect(spyTester.testedBatches, isNotEmpty);
  });

  testWidgets(
      'CR-06: _NavigationModeToggleButton exposes clean toggled button semantics without Tooltip duplicate readout and renders overflow-free at 2.0x across zh_CN/en/ja/ru',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final semanticsHandle = tester.ensureSemantics();
    try {
      for (final locale in const [
        Locale('zh', 'CN'),
        Locale('en'),
        Locale('ja'),
        Locale('ru'),
      ]) {
        await AppLocalizations.load(locale);
        await tester.pumpWidget(
          ProviderScope(
            key: ValueKey(locale.toLanguageTag()),
            child: MediaQuery(
              data: const MediaQueryData(
                size: Size(1280, 900),
                textScaler: TextScaler.linear(2.0),
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
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: const TextScaler.linear(2.0),
                  ),
                  child: child!,
                ),
                home: Consumer(
                  builder: (context, ref, _) {
                    globalState.measure = Measure.of(context, 2.0);
                    globalState.theme = CommonTheme.of(context, 2.0);
                    globalState.appController = _TestAppController(ref);
                    final navItems =
                        ref.watch(currentNavigationsStateProvider).value;
                    return Scaffold(
                      body: Row(
                        children: [
                          CommonNavigationBar(
                            viewMode: ViewMode.desktop,
                            navigationItems: navItems,
                            currentIndex: 0,
                          ),
                          const Expanded(child: SizedBox()),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final toggleFinder =
            find.byKey(const ValueKey('navigation-expert-mode-toggle'));
        expect(
          tester.getSemantics(toggleFinder),
          matchesSemantics(
            isButton: true,
            isFocusable: true,
            hasToggledState: true,
            isToggled: false,
            hasTapAction: true,
            hasFocusAction: true,
            label: appLocalizations.expertMode,
          ),
        );

        await tester.tap(toggleFinder);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        expect(
          tester.getSemantics(toggleFinder),
          matchesSemantics(
            isButton: true,
            isFocusable: true,
            hasToggledState: true,
            isToggled: true,
            hasTapAction: true,
            hasFocusAction: true,
            label: appLocalizations.noviceMode,
          ),
        );
      }
    } finally {
      semanticsHandle.dispose();
    }
  });
}

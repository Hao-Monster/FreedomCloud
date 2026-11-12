import 'package:flclashx/common/common.dart';
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
import 'package:flclashx/state.dart';
import 'package:flclashx/views/profiles/add_profile.dart';
import 'package:flclashx/views/proxies/overview/overview.dart';
import 'package:flclashx/views/proxies/proxies.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestAppController extends Fake implements AppController {
  _TestAppController(this.ref);

  final WidgetRef ref;
  final List<PageLabel> navigatedPages = <PageLabel>[];
  final List<bool> updateStatusCalls = <bool>[];
  final List<Profile> addedProfiles = <Profile>[];

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
    updateStatusCalls.add(isStart);
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
  Future<void> activateImportedProfileForNovice(
    Profile profile, {
    bool isNewProfile = false,
    bool switchToProxiesPage = false,
  }) async {
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
    if (switchToProxiesPage) {
      ref.read(proxiesScopeProvider.notifier).state = ProxiesScope.all;
      toPage(PageLabel.proxies);
    }
    final isActive =
        ref.read(currentProfileIdProvider) == effectiveProfile.id;
    if (isActive && !ref.read(runTimeProvider.notifier).isStart) {
      await updateStatus(true);
    }
  }
}

class _MemPurchaseStorage implements PurchaseStorage {
  final Map<int, String> profileIds = <int, String>{};

  @override
  Future<String?> readProfileId(int accountId) async => profileIds[accountId];

  @override
  Future<void> saveProfileId(int accountId, String profileId) async {
    profileIds[accountId] = profileId;
  }

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
}

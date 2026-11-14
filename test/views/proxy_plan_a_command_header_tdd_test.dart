import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/delay_test_coordinator.dart';
import 'package:flclashx/common/node_catalog_tester.dart';
import 'package:flclashx/common/node_health_store.dart';
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
import 'package:flclashx/services/purchase_storage.dart';
import 'package:flclashx/services/xboard_api.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/views/profiles/add_profile.dart';
import 'package:flclashx/views/proxies/overview/overview.dart';
import 'package:flclashx/views/proxies/proxies.dart';
import 'package:flclashx/views/purchase.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

class _TestAppController extends Fake implements AppController {
  _TestAppController(this.ref, {this.onAddProfileFormURL});

  final WidgetRef ref;
  final Future<void> Function(String url, WidgetRef ref)? onAddProfileFormURL;
  final List<PageLabel> navigatedPages = <PageLabel>[];
  final List<bool> updateStatusCalls = <bool>[];
  final List<(String, String)> selections = <(String, String)>[];
  final List<(String, String)> changes = <(String, String)>[];
  final List<String> addedUrls = <String>[];

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
  void setProfile(Profile profile) {
    ref.read(profilesProvider.notifier).setProfile(profile);
  }

  @override
  Future<void> addProfileFormURL(String url) async {
    addedUrls.add(url);
    if (onAddProfileFormURL != null) {
      await onAddProfileFormURL!(url, ref);
    }
  }

  @override
  void updateCurrentSelectedMap(String groupName, String proxyName) {
    selections.add((groupName, proxyName));
    final activeId = ref.read(currentProfileIdProvider);
    if (activeId == null) return;
    final profile = ref.read(profilesProvider).getProfile(activeId);
    if (profile == null) return;
    ref.read(profilesProvider.notifier).setProfile(
          profile.copyWith(
            selectedMap: {
              ...profile.selectedMap,
              groupName: proxyName,
            },
          ),
        );
  }

  @override
  void changeProxyDebounce(String groupName, String proxyName) {
    changes.add((groupName, proxyName));
  }

  @override
  void applyProfileDebounce({
    bool silence = false,
    bool skipIfUnchanged = false,
  }) {}

  @override
  void updateCurrentGroupName(String groupName) {}

  @override
  List<Group> getCurrentGroups() =>
      ref.read(currentGroupsStateProvider.select((state) => state.value));

  @override
  String getRealTestUrl(String? url) => ref.read(getRealTestUrlProvider(url));

  @override
  ProxyCardState getProxyCardState(dynamic proxyName) =>
      ref.read(getProxyCardStateProvider('$proxyName'));

  @override
  List<Proxy> getSortProxies(List<Proxy> proxies, [String? url]) => proxies;

  @override
  void updateCurrentUnfoldSet(Set<String> value) {
    final currentProfile = ref.read(currentProfileProvider);
    if (currentProfile == null) return;
    ref.read(profilesProvider.notifier).setProfile(
          currentProfile.copyWith(unfoldSet: value),
        );
  }

  @override
  void changeMode(Mode mode) {
    ref
        .read(patchClashConfigProvider.notifier)
        .updateState((state) => state.copyWith(mode: mode));
  }

  @override
  void backBlock() {}

  @override
  void unBackBlock() {}
}

class _SpyCatalogTester extends ChangeNotifier implements NodeCatalogTester {
  final List<List<DelayTestTarget>> current = <List<DelayTestTarget>>[];
  final List<List<Profile>> all = <List<Profile>>[];
  String? reason;
  DelayBatchResult? allResult;

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
  Future<DelayBatchResult> testCurrent(
    Iterable<DelayTestTarget> targets,
  ) async {
    final list = targets.toList();
    current.add(list);
    return DelayBatchResult(
      completed: reason == null ? list.length : 0,
      failed: 0,
      reason: reason,
    );
  }

  @override
  Future<DelayBatchResult> testAll(List<Profile> profiles, String url) async {
    all.add(List<Profile>.from(profiles));
    return allResult ??
        DelayBatchResult(
          completed: reason == null ? 1 : 0,
          failed: 0,
          reason: reason,
        );
  }

  @override
  Future<DelayBatchResult> collectAndTest(
    Future<List<CatalogTestSelection>> Function(bool Function() isCurrent)
        collect,
    String url,
  ) async =>
      testVisible(await collect(() => true), url);

  @override
  Future<DelayBatchResult> testVisible(
    List<CatalogTestSelection> selections,
    String url,
  ) async =>
      DelayBatchResult(completed: 0, failed: 0, reason: reason);

  @override
  Future<void> cancel({String reason = 'cancelled'}) async {}

  @override
  void disposeScope() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemPurchaseStorage implements PurchaseStorage {
  PurchaseSession? session;

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
  Future<PendingGiftRedemption?> readPending(int accountId) async => null;

  @override
  Future<void> savePending(int accountId, PendingGiftRedemption value) async {}

  @override
  Future<void> clearPending(int accountId) async {}

  @override
  Future<String?> readProfileId(int accountId) async => null;

  @override
  Future<void> saveProfileId(int accountId, String profileId) async {}
}

class _FakeXboardApi implements XboardApi {
  @override
  Uri get baseUri => Uri.parse('https://panel.example.test');

  @override
  Future<XboardPlanCatalog> getPlanCatalog() async =>
      const XboardPlanCatalog(plans: []);

  @override
  Future<String> login(String email, String password) async =>
      'Bearer token-test';

  @override
  Future<XboardAccount> getAccount(String authorization) async =>
      const XboardAccount(id: 1, email: 'test@example.test');

  @override
  Future<XboardSubscription> getSubscription(String authorization) async =>
      XboardSubscription(
        valid: false,
        url: Uri.parse('https://panel.example.test/sub?token=none'),
      );

  @override
  Future<GiftHistoryPage> getGiftHistory(
    String authorization, {
    int page = 1,
  }) async =>
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

class _StubNonProxyPage extends ConsumerStatefulWidget {
  const _StubNonProxyPage({required this.label});

  final String label;

  @override
  ConsumerState<_StubNonProxyPage> createState() => _StubNonProxyPageState();
}

class _StubNonProxyPageState extends ConsumerState<_StubNonProxyPage>
    with PageMixin {
  @override
  Widget build(BuildContext context) => Center(child: Text(widget.label));
}

class _DesktopPageViewShell extends ConsumerWidget {
  const _DesktopPageViewShell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Localizations.localeOf(context);
    AppLocalizations.of(context);
    ref.watch(appSettingProvider.select((state) => state.locale));
    final navItems = ref.watch(currentNavigationsStateProvider).value;
    final pageLabel = ref.watch(currentPageLabelProvider);
    final idx = navItems.indexWhere((e) => e.label == pageLabel);
    final currentIndex = idx < 0 ? 0 : idx;
    return CommonScaffold(
      key: globalState.homeScaffoldKey,
      title: Intl.message(pageLabel.name),
      sideNavigationBar: CommonNavigationBar(
        viewMode: ViewMode.desktop,
        navigationItems: navItems,
        currentIndex: currentIndex,
      ),
      body: const _DesktopKeepScopePages(),
    );
  }
}

class _DesktopKeepScopePages extends ConsumerStatefulWidget {
  const _DesktopKeepScopePages();

  @override
  ConsumerState<_DesktopKeepScopePages> createState() =>
      _DesktopKeepScopePagesState();
}

class _DesktopKeepScopePagesState extends ConsumerState<_DesktopKeepScopePages> {
  late final PageController _pageController;
  final XboardApi _fakeApi = _FakeXboardApi();
  final PurchaseStorage _memStorage = _MemPurchaseStorage();

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _resolvePageIndex());
    ref.listenManual(currentPageLabelProvider, (prev, next) {
      if (prev != next) {
        final target = _resolvePageIndex();
        if (_pageController.hasClients) {
          _pageController.jumpToPage(target);
        }
      }
    });
    ref.listenManual(currentNavigationsStateProvider, (prev, next) {
      if (prev?.value.length != next.value.length &&
          _pageController.hasClients) {
        _pageController.jumpToPage(_resolvePageIndex());
      }
    });
  }

  int _resolvePageIndex() {
    final navItems = ref.read(currentNavigationsStateProvider).value;
    final currentLabel = ref.read(currentPageLabelProvider);
    final idx = navItems.indexWhere((e) => e.label == currentLabel);
    return idx < 0 ? 0 : idx;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final navItems = ref.watch(currentNavigationsStateProvider).value;
    final pageLabel = ref.watch(currentPageLabelProvider);
    return PageView.builder(
      controller: _pageController,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: navItems.length,
      itemBuilder: (_, index) {
        final item = navItems[index];
        final isActive = item.label == pageLabel;
        final child = switch (item.label) {
          PageLabel.proxies => const ProxiesView(),
          PageLabel.purchase => PurchaseView(
              apiOverride: _fakeApi,
              storageOverride: _memStorage,
              saveConfigOverride: (_) async => true,
            ),
          _ => _StubNonProxyPage(label: 'Stub ${item.label.name}'),
        };
        return ExcludeFocus(
          excluding: !isActive,
          child: TickerMode(
            enabled: isActive,
            child: KeepScope(
              keep: true,
              key: Key(item.label.name),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

CatalogNode _node(String key, String name) => CatalogNode(
      identityKey: key,
      endpointKey: key,
      name: name,
      type: 'vless',
      source: CatalogNodeSource.inline,
      selectGroups: const ['Proxy'],
    );

String? _tooltipMessageFor(
  WidgetTester tester,
  Finder target, {
  Finder? scope,
}) {
  final widget = tester.widget<Widget>(target);
  if (widget is Tooltip) return widget.message;
  final descendant = find.descendant(of: target, matching: find.byType(Tooltip));
  if (descendant.evaluate().isNotEmpty) {
    return tester.widget<Tooltip>(descendant.first).message;
  }
  final ancestor = find.ancestor(of: target, matching: find.byType(Tooltip));
  if (ancestor.evaluate().isNotEmpty) {
    final closest = ancestor.first;
    if (scope == null ||
        find.descendant(of: scope, matching: closest).evaluate().isNotEmpty) {
      return tester.widget<Tooltip>(closest).message;
    }
  }
  return null;
}

Future<ProviderContainer> _mountDesktopShell(
  WidgetTester tester, {
  Size size = const Size(1280, 900),
  Locale locale = const Locale('zh', 'CN'),
  double textScale = 1.0,
  bool useSideRail = true,
  List<Profile> profiles = const [],
  String? currentProfileId,
  int? runTime,
  List<Group> groups = const [],
  Map<String, ProfileCatalog> catalogs = const {},
  Map<String, Map<String, NodeHealthRecord>> health = const {},
  _SpyCatalogTester? catalogTester,
  Future<void> Function(String url, WidgetRef ref)? onAddProfileFormURL,
  Widget? customHome,
}) async {
  await AppLocalizations.load(locale);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));

  final localeTag = (locale.countryCode?.isNotEmpty ?? false)
      ? '${locale.languageCode}_${locale.countryCode}'
      : locale.languageCode;
  globalState.config = Config(
    themeProps: defaultThemeProps.copyWith(
      textScale: TextScale(enable: true, scale: textScale),
    ),
    appSetting: AppSettingProps(locale: localeTag),
    profiles: profiles,
    currentProfileId: currentProfileId,
  );
  globalState.startTime = runTime != null ? DateTime.now() : null;
  globalState.appState = AppState(
    viewSize: size,
    pageLabel: PageLabel.proxies,
    version: 1,
    runTime: runTime,
    groups: groups,
    requests: FixedList(maxLength),
    logs: FixedList(maxLength),
    traffics: FixedList(30),
    totalTraffic: Traffic(),
    isInit: true,
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        nodeOverviewEnabledProvider.overrideWithValue(true),
        activeNodeCatalogProvider.overrideWithValue(null),
        coldStartZeroProfilePromptedProvider.overrideWith((ref) => true),
        nodeCatalogTesterProvider
            .overrideWith((ref) => catalogTester ?? _SpyCatalogTester()),
        cachedProfileCatalogsProvider.overrideWith((ref) => catalogs),
        profileCatalogProvider.overrideWith(
          (ref, id) async =>
              ref.read(cachedProfileCatalogsProvider)[id] ??
              catalogs[id] ??
              ProfileCatalog(
                profileId: id,
                fingerprint: '',
                status: ProfileCatalogStatus.ready,
              ),
        ),
        nodeHealthEntriesProvider.overrideWith((ref, id) => health[id] ?? const {}),
      ],
      child: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Consumer(
          builder: (context, ref, _) {
            final appLocaleStr = ref.watch(
              appSettingProvider.select((state) => state.locale),
            );
            final effectiveLocale =
                utils.getLocaleForString(appLocaleStr) ?? locale;
            return MaterialApp(
              navigatorKey: globalState.navigatorKey,
              locale: effectiveLocale,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.delegate.supportedLocales,
              builder: (context, child) => Consumer(
                builder: (context, ref, wrappedChild) {
                  final ts = ref.watch(
                    themeSettingProvider.select((state) => state.textScale),
                  );
                  final effectiveScale = ts.enable == true
                      ? (ts.scale as num).toDouble()
                      : textScale;
                  globalState.measure = Measure.of(context, effectiveScale);
                  globalState.theme = CommonTheme.of(context, effectiveScale);
                  return MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      size: size,
                      textScaler: TextScaler.linear(effectiveScale),
                    ),
                    child: wrappedChild!,
                  );
                },
                child: child,
              ),
              home: Consumer(
                builder: (context, ref, _) {
                  globalState.appController = _TestAppController(
                    ref,
                    onAddProfileFormURL: onAddProfileFormURL,
                  );
                  if (customHome != null) {
                    return customHome;
                  }
                  final navItems =
                      ref.watch(currentNavigationsStateProvider).value;
                  final pageLabel = ref.watch(currentPageLabelProvider);
                  final idx = navItems.indexWhere((e) => e.label == pageLabel);
                  return CommonScaffold(
                    key: globalState.homeScaffoldKey,
                    title: Intl.message(pageLabel.name),
                    sideNavigationBar: useSideRail
                        ? CommonNavigationBar(
                            viewMode: ViewMode.desktop,
                            navigationItems: navItems,
                            currentIndex: idx < 0 ? 0 : idx,
                          )
                        : null,
                    body: const ProxiesView(),
                  );
                },
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(CommonScaffold)));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await AppLocalizations.load(const Locale('zh', 'CN'));
    globalState.lastRuntimeConfig = null;
    globalState.lastRuntimeProfileId = null;
    globalState.lastSubscriptionImportError = null;
    globalState.suppressNextSubscriptionImportErrorDialog = false;
  });

  tearDown(() async {
    await AppLocalizations.load(const Locale('en'));
  });

  testWidgets(
      'PA-01: 1280x900 desktop CommonScaffold + ProxiesView renders unique inline overview-top-command-bar inside AppBar aligned with title without occluding rail or actions in 小白模式 and 大佬模式',
      (tester) async {
    const profileA = Profile(
      id: 'p1',
      label: '主力订阅',
      url: 'https://sub.example.com/p1',
      autoUpdateDuration: defaultUpdateDuration,
      currentGroupName: 'Proxy',
      selectedMap: {'Proxy': '香港 01'},
    );
    await _mountDesktopShell(
      tester,
      size: const Size(1280, 900),
      profiles: const [profileA],
      currentProfileId: 'p1',
      runTime: 1000,
      groups: const [
        Group(
          name: 'Proxy',
          type: GroupType.Selector,
          hidden: false,
          now: '香港 01',
          all: [Proxy(name: '香港 01', type: 'VLESS')],
        ),
      ],
      catalogs: {
        'p1': ProfileCatalog(
          profileId: 'p1',
          fingerprint: 'fp1',
          status: ProfileCatalogStatus.ready,
          nodes: [_node('hk-1', '香港 01')],
        ),
      },
    );

    final commandBar = find.byKey(const ValueKey('overview-top-command-bar'));
    final appBar = find.byType(AppBar);
    final navBar = find.byType(CommonNavigationBar);

    void verifyInlineHeader({required bool expertMode}) {
      expect(commandBar, findsOneWidget);
      expect(find.descendant(of: appBar, matching: commandBar), findsOneWidget);

      final appBarTitle = find.descendant(of: appBar, matching: find.text('代理'));
      expect(appBarTitle, findsOneWidget);

      final commandBarRect = tester.getRect(commandBar);
      final titleRect = tester.getRect(appBarTitle);
      final railRect = tester.getRect(navBar);
      expect(commandBarRect.center.dy, closeTo(titleRect.center.dy, 6.0));
      expect(commandBarRect.left, greaterThanOrEqualTo(railRect.right));
      expect(commandBarRect.left, greaterThanOrEqualTo(titleRect.right));

      final searchIcon =
          find.descendant(of: appBar, matching: find.byIcon(Icons.search));
      expect(searchIcon, findsOneWidget);
      final searchRect = tester.getRect(searchIcon);
      expect(commandBarRect.overlaps(searchRect), isFalse);
      expect(commandBarRect.right, lessThanOrEqualTo(searchRect.left));

      if (expertMode) {
        final scopeSegments = find.descendant(
          of: appBar,
          matching: find.byKey(const ValueKey('overview-scope-segments')),
        );
        final moreIcon = find.descendant(
          of: appBar,
          matching: find.byIcon(Icons.more_vert),
        );
        expect(scopeSegments, findsOneWidget);
        expect(moreIcon, findsOneWidget);
        expect(commandBarRect.overlaps(tester.getRect(scopeSegments)), isFalse);
        expect(
          commandBarRect.right,
          lessThanOrEqualTo(tester.getRect(scopeSegments).left),
        );
        expect(commandBarRect.overlaps(tester.getRect(moreIcon)), isFalse);
      }

      // Strict left-to-right order inside overview-top-command-bar:
      // 1) add-subscription (TextButton, no '1' badge)
      // 2) connection-bar (status capsule, no switch, tooltip has full status)
      // 3) mode-segmented-track ([智能选路, 固定IP] with full tooltips)
      // 4) quick-use (TextButton, '一键连最快')
      final addBtn = find.byKey(const ValueKey('overview-add-subscription'));
      final connBar = find.byKey(const ValueKey('overview-connection-bar'));
      final track =
          find.byKey(const ValueKey('overview-mode-segmented-track'));
      final smartBtn = find.byKey(const ValueKey('overview-mode-smart'));
      final manualBtn = find.byKey(const ValueKey('overview-mode-manual'));
      final quickUseBtn = find.byKey(const ValueKey('overview-quick-use'));

      expect(find.descendant(of: commandBar, matching: addBtn), findsOneWidget);
      expect(
          find.descendant(of: commandBar, matching: connBar), findsOneWidget);
      expect(find.descendant(of: commandBar, matching: track), findsOneWidget);
      expect(find.descendant(of: track, matching: smartBtn), findsOneWidget);
      expect(find.descendant(of: track, matching: manualBtn), findsOneWidget);
      expect(find.descendant(of: commandBar, matching: quickUseBtn),
          findsOneWidget);

      expect(tester.widget<Widget>(addBtn), isA<TextButton>());
      expect(find.descendant(of: addBtn, matching: find.text('1')),
          findsNothing);
      expect(tester.widget<Widget>(quickUseBtn), isA<TextButton>());
      expect(find.descendant(of: quickUseBtn, matching: find.text('一键连最快')),
          findsOneWidget);
      expect(find.descendant(of: quickUseBtn, matching: find.text('3')),
          findsNothing);

      expect(
        find.descendant(
          of: connBar,
          matching: find.byKey(const ValueKey('overview-proxy-toggle')),
        ),
        findsNothing,
      );
      final connTooltip =
          _tooltipMessageFor(tester, connBar, scope: commandBar);
      expect(connTooltip, isNotNull);
      expect(connTooltip, contains('代理已开启'));
      expect(connTooltip, contains('主力订阅'));

      expect(
        find.descendant(of: smartBtn, matching: find.text('智能选路')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: manualBtn, matching: find.text('固定IP')),
        findsOneWidget,
      );
      final smartTooltip =
          _tooltipMessageFor(tester, smartBtn, scope: commandBar);
      final manualTooltip =
          _tooltipMessageFor(tester, manualBtn, scope: commandBar);
      expect(smartTooltip, contains('智能选择节点'));
      expect(smartTooltip, contains('体验更好'));
      expect(manualTooltip, contains('手动选择节点'));
      expect(manualTooltip, contains('固定IP'));

      final addRect = tester.getRect(addBtn);
      final connRect = tester.getRect(connBar);
      final trackRect = tester.getRect(track);
      final smartRect = tester.getRect(smartBtn);
      final manualRect = tester.getRect(manualBtn);
      final useRect = tester.getRect(quickUseBtn);

      expect(addRect.right, lessThanOrEqualTo(connRect.left));
      expect(connRect.right, lessThanOrEqualTo(trackRect.left));
      expect(smartRect.right, lessThanOrEqualTo(manualRect.left));
      expect(trackRect.right, lessThanOrEqualTo(useRect.left));
      expect(addRect.center.dy, closeTo(commandBarRect.center.dy, 4.0));
      expect(connRect.center.dy, closeTo(commandBarRect.center.dy, 4.0));
      expect(trackRect.center.dy, closeTo(commandBarRect.center.dy, 4.0));
      expect(useRect.center.dy, closeTo(commandBarRect.center.dy, 4.0));
    }

    verifyInlineHeader(expertMode: false);

    // Toggle 大佬模式 and re-verify AppBar non-occlusion with scope segments & overflow menu.
    await tester
        .tap(find.byKey(const ValueKey('navigation-expert-mode-toggle')));
    await tester.pumpAndSettle();
    verifyInlineHeader(expertMode: true);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'PA-02: 1280x900 removes legacy workflow bar/arrows & permanent history notice, aligns sidebar and node list tops, and preserves overview-test-current in layer-2',
      (tester) async {
    final spyTester = _SpyCatalogTester();
    const profileA = Profile(
      id: 'p1',
      label: '主力订阅',
      url: 'https://sub.example.com/p1',
      autoUpdateDuration: defaultUpdateDuration,
      currentGroupName: 'Proxy',
      selectedMap: {'Proxy': '香港 01'},
    );
    const profileB = Profile(
      id: 'p2',
      label: '备用订阅',
      url: 'https://sub.example.com/p2',
      autoUpdateDuration: defaultUpdateDuration,
    );
    await _mountDesktopShell(
      tester,
      size: const Size(1280, 900),
      profiles: const [profileA, profileB],
      currentProfileId: 'p1',
      runTime: 1000,
      catalogTester: spyTester,
      groups: const [
        Group(
          name: 'Proxy',
          type: GroupType.Selector,
          hidden: false,
          now: '香港 01',
          all: [Proxy(name: '香港 01', type: 'VLESS')],
        ),
      ],
      catalogs: {
        'p1': ProfileCatalog(
          profileId: 'p1',
          fingerprint: 'fp1',
          status: ProfileCatalogStatus.ready,
          nodes: [_node('hk-1', '香港 01')],
        ),
        'p2': ProfileCatalog(
          profileId: 'p2',
          fingerprint: 'fp2',
          status: ProfileCatalogStatus.ready,
          nodes: [_node('jp-1', '日本 01')],
        ),
      },
    );

    expect(find.byKey(const ValueKey('overview-workflow-bar')), findsNothing);
    expect(
        find.byKey(const ValueKey('overview-workflow-arrow-1')), findsNothing);
    expect(
        find.byKey(const ValueKey('overview-workflow-arrow-2')), findsNothing);
    expect(find.text(appLocalizations.nodeOverviewHistoryNotice), findsNothing);
    expect(
      find.byKey(const ValueKey('overview-history-notice-tooltip')),
      findsNothing,
    );

    final commandBar = find.byKey(const ValueKey('overview-top-command-bar'));
    final sidebar = find.byKey(const ValueKey('overview-sidebar'));
    final nodes = find.byKey(const ValueKey('overview-nodes'));
    final testCurrentBtn = find.byKey(const ValueKey('overview-test-current'));
    final sortBtn = find.byKey(const ValueKey('overview-sort-button'));

    expect(commandBar, findsOneWidget);
    expect(sidebar, findsOneWidget);
    expect(nodes, findsOneWidget);
    expect(testCurrentBtn, findsOneWidget);

    final commandBarRect = tester.getRect(commandBar);
    final sidebarRect = tester.getRect(sidebar);
    final nodesRect = tester.getRect(nodes);
    final testCurrentRect = tester.getRect(testCurrentBtn);
    final sortRect = tester.getRect(sortBtn);

    expect(nodesRect.top, closeTo(sidebarRect.top, 2.0));
    expect(testCurrentRect.top, greaterThanOrEqualTo(commandBarRect.bottom));
    expect(testCurrentRect.bottom, lessThanOrEqualTo(nodesRect.top));
    expect(testCurrentRect.center.dy, closeTo(sortRect.center.dy, 2.0));

    await tester.tap(testCurrentBtn);
    await tester.pumpAndSettle();
    expect(spyTester.current, hasLength(1));

    // Switch to 大佬模式: permanent full-row notice remains gone, tooltip icon appears.
    await tester
        .tap(find.byKey(const ValueKey('navigation-expert-mode-toggle')));
    await tester.pumpAndSettle();
    expect(find.text(appLocalizations.nodeOverviewHistoryNotice), findsNothing);
    final noticeTooltip =
        find.byKey(const ValueKey('overview-history-notice-tooltip'));
    expect(noticeTooltip, findsOneWidget);
    expect(
      _tooltipMessageFor(tester, noticeTooltip),
      appLocalizations.nodeOverviewHistoryNotice,
    );
    expect(
      tester.getRect(nodes).top,
      closeTo(tester.getRect(sidebar).top, 2.0),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'PA-03a: search mode, 900px narrow width, and 2.0x textScale seamlessly fall back overview-top-command-bar to body row 1 and return to AppBar cleanly',
      (tester) async {
    const profileA = Profile(
      id: 'p1',
      label: '主力订阅',
      url: 'https://sub.example.com/p1',
      autoUpdateDuration: defaultUpdateDuration,
      currentGroupName: 'Proxy',
      selectedMap: {'Proxy': '香港 01'},
    );
    final catalogs = {
      'p1': ProfileCatalog(
        profileId: 'p1',
        fingerprint: 'fp1',
        status: ProfileCatalogStatus.ready,
        nodes: [_node('hk-1', '香港 01'), _node('sg-1', '新加坡 01')],
      ),
    };
    const groups = [
      Group(
        name: 'Proxy',
        type: GroupType.Selector,
        hidden: false,
        now: '香港 01',
        all: [
          Proxy(name: '香港 01', type: 'VLESS'),
          Proxy(name: '新加坡 01', type: 'VLESS'),
        ],
      ),
    ];

    await _mountDesktopShell(
      tester,
      size: const Size(1280, 900),
      profiles: const [profileA],
      currentProfileId: 'p1',
      runTime: 1000,
      groups: groups,
      catalogs: catalogs,
    );

    final commandBar = find.byKey(const ValueKey('overview-top-command-bar'));
    final appBar = find.byType(AppBar);
    final overview = find.byType(NodeOverviewView);

    expect(commandBar, findsOneWidget);
    expect(find.descendant(of: appBar, matching: commandBar), findsOneWidget);
    expect(find.descendant(of: overview, matching: commandBar), findsNothing);

    // Enter search mode -> command bar moves out of AppBar to body row 1 (unique instance).
    await tester
        .tap(find.descendant(of: appBar, matching: find.byIcon(Icons.search)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(commandBar, findsOneWidget);
    expect(find.descendant(of: appBar, matching: commandBar), findsNothing);
    expect(find.descendant(of: overview, matching: commandBar), findsOneWidget);
    final bodyCommandRect = tester.getRect(commandBar);
    final overviewRect = tester.getRect(overview);
    expect(
      bodyCommandRect.bottom,
      lessThanOrEqualTo(
        tester.getRect(find.byKey(const ValueKey('overview-sort-button'))).top,
      ),
    );
    expect(bodyCommandRect.width, greaterThanOrEqualTo(overviewRect.width - 48));

    // Exit search mode -> command bar seamlessly returns into AppBar.
    await tester.tap(
      find.descendant(of: appBar, matching: find.byIcon(Icons.arrow_back)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(commandBar, findsOneWidget);
    expect(find.descendant(of: appBar, matching: commandBar), findsOneWidget);
    expect(find.descendant(of: overview, matching: commandBar), findsNothing);

    // Narrow 900px width -> falls back to body row 1 without overflow.
    await tester.pumpWidget(const SizedBox.shrink());
    await _mountDesktopShell(
      tester,
      size: const Size(900, 900),
      profiles: const [profileA],
      currentProfileId: 'p1',
      runTime: 1000,
      groups: groups,
      catalogs: catalogs,
    );
    expect(commandBar, findsOneWidget);
    expect(find.descendant(of: appBar, matching: commandBar), findsNothing);
    expect(find.descendant(of: overview, matching: commandBar), findsOneWidget);
    expect(
      tester.getRect(commandBar).bottom,
      lessThanOrEqualTo(
        tester.getRect(find.byKey(const ValueKey('overview-sort-button'))).top,
      ),
    );
    expect(tester.takeException(), isNull);

    // 2.0x textScale at 1280x900 -> falls back to body row 1 without overflow.
    await tester.pumpWidget(const SizedBox.shrink());
    await _mountDesktopShell(
      tester,
      size: const Size(1280, 900),
      textScale: 2.0,
      profiles: const [profileA],
      currentProfileId: 'p1',
      runTime: 1000,
      groups: groups,
      catalogs: catalogs,
    );
    expect(commandBar, findsOneWidget);
    expect(find.descendant(of: appBar, matching: commandBar), findsNothing);
    expect(find.descendant(of: overview, matching: commandBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'PA-03b: 320px/380px/1200px @ 2.0x textScale across zh_CN/en/ja/ru render overflow-free with localized compact mode labels and tooltips',
      (tester) async {
    const profileA = Profile(
      id: 'p1',
      label: 'Primary',
      url: 'https://sub.example.com/p1',
      autoUpdateDuration: defaultUpdateDuration,
      currentGroupName: 'Proxy',
      selectedMap: {'Proxy': 'HK 01'},
    );
    final catalogs = {
      'p1': ProfileCatalog(
        profileId: 'p1',
        fingerprint: 'fp1',
        status: ProfileCatalogStatus.ready,
        nodes: [_node('hk-1', 'HK 01')],
      ),
    };
    const groups = [
      Group(
        name: 'Proxy',
        type: GroupType.Selector,
        hidden: false,
        now: 'HK 01',
        all: [Proxy(name: 'HK 01', type: 'VLESS')],
      ),
    ];

    const expectations = <String, ({
      String smartCompact,
      String manualCompact,
      String smartTitle,
      String smartSubtitle,
      String manualTitle,
      String manualSubtitle,
    })>{
      'zh': (
        smartCompact: '智能选路',
        manualCompact: '固定IP',
        smartTitle: '智能选择节点',
        smartSubtitle: '体验更好',
        manualTitle: '手动选择节点',
        manualSubtitle: '固定IP',
      ),
      'en': (
        smartCompact: 'Smart',
        manualCompact: 'Fixed IP',
        smartTitle: 'Smart Select',
        smartSubtitle: 'Better experience',
        manualTitle: 'Manual Select',
        manualSubtitle: 'Fixed IP',
      ),
      'ja': (
        smartCompact: 'スマート',
        manualCompact: '固定IP',
        smartTitle: 'スマート選択',
        smartSubtitle: 'より快適',
        manualTitle: '手動選択',
        manualSubtitle: '固定IP',
      ),
      'ru': (
        smartCompact: 'Умный',
        manualCompact: 'Фикс. IP',
        smartTitle: 'Умный выбор',
        smartSubtitle: 'Лучший опыт',
        manualTitle: 'Ручной выбор',
        manualSubtitle: 'Фикс. IP',
      ),
    };

    for (final width in const [320.0, 380.0, 1200.0]) {
      for (final locale in const [
        Locale('zh', 'CN'),
        Locale('en'),
        Locale('ja'),
        Locale('ru'),
      ]) {
        await tester.pumpWidget(const SizedBox.shrink());
        await _mountDesktopShell(
          tester,
          size: Size(width, 900),
          locale: locale,
          textScale: 2.0,
          useSideRail: width > maxMobileWidth,
          profiles: const [profileA],
          currentProfileId: 'p1',
          runTime: 1000,
          groups: groups,
          catalogs: catalogs,
        );

        final expected = expectations[locale.languageCode]!;
        final commandBar =
            find.byKey(const ValueKey('overview-top-command-bar'));
        final smartBtn = find.byKey(const ValueKey('overview-mode-smart'));
        final manualBtn = find.byKey(const ValueKey('overview-mode-manual'));

        expect(commandBar, findsOneWidget);
        expect(
          find.byKey(const ValueKey('overview-add-subscription')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('overview-connection-bar')),
          findsOneWidget,
        );
        expect(smartBtn, findsOneWidget);
        expect(manualBtn, findsOneWidget);
        expect(
          find.byKey(const ValueKey('overview-quick-use')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: smartBtn,
            matching: find.text(expected.smartCompact),
          ),
          findsOneWidget,
          reason: 'smart label mismatch at $width $locale',
        );
        expect(
          find.descendant(
            of: manualBtn,
            matching: find.text(expected.manualCompact),
          ),
          findsOneWidget,
          reason: 'manual label mismatch at $width $locale',
        );

        final smartTip = _tooltipMessageFor(tester, smartBtn, scope: commandBar);
        final manualTip =
            _tooltipMessageFor(tester, manualBtn, scope: commandBar);
        expect(smartTip, contains(expected.smartTitle));
        expect(smartTip, contains(expected.smartSubtitle));
        expect(manualTip, contains(expected.manualTitle));
        expect(manualTip, contains(expected.manualSubtitle));

        expect(
          tester.takeException(),
          isNull,
          reason: 'overflow at $width $locale @ 2.0x',
        );
      }
    }
  });

  testWidgets(
      'PA-04: switching ProxiesScope.current hides command bar from AppBar and restoring ProxiesScope.all brings it back; switching to purchase/tools never leaks command bar',
      (tester) async {
    const profileA = Profile(
      id: 'p1',
      label: '主力订阅',
      url: 'https://sub.example.com/p1',
      autoUpdateDuration: defaultUpdateDuration,
      currentGroupName: 'Proxy',
      selectedMap: {'Proxy': '香港 01'},
    );
    final container = await _mountDesktopShell(
      tester,
      size: const Size(1280, 900),
      profiles: const [profileA],
      currentProfileId: 'p1',
      runTime: 1000,
      groups: const [
        Group(
          name: 'Proxy',
          type: GroupType.Selector,
          hidden: false,
          now: '香港 01',
          all: [Proxy(name: '香港 01', type: 'VLESS')],
        ),
      ],
      catalogs: {
        'p1': ProfileCatalog(
          profileId: 'p1',
          fingerprint: 'fp1',
          status: ProfileCatalogStatus.ready,
          nodes: [_node('hk-1', '香港 01')],
        ),
      },
      customHome: const _DesktopPageViewShell(),
    );

    final appBar = find.byType(AppBar);
    final commandBar = find.byKey(const ValueKey('overview-top-command-bar'));
    final rail = find.byType(CommonNavigationBar);

    expect(find.descendant(of: appBar, matching: commandBar), findsOneWidget);

    // 1. Expand expert mode -> switch ProxiesScope to current -> command bar leaves AppBar.
    await tester
        .tap(find.byKey(const ValueKey('navigation-expert-mode-toggle')));
    await tester.pumpAndSettle();

    final scopeSegments = find.byKey(const ValueKey('overview-scope-segments'));
    expect(scopeSegments, findsOneWidget);
    await tester.tap(
      find.descendant(of: scopeSegments, matching: find.text('当前配置')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NodeOverviewView), findsNothing);
    expect(commandBar, findsNothing);
    expect(find.descendant(of: appBar, matching: commandBar), findsNothing);
    expect(tester.takeException(), isNull);

    // Switch back to ProxiesScope.all -> command bar returns inside AppBar.
    await tester.tap(
      find.descendant(of: scopeSegments, matching: find.text('全部配置')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NodeOverviewView), findsOneWidget);
    expect(find.descendant(of: appBar, matching: commandBar), findsOneWidget);

    // 2. Navigate to Purchase tab -> AppBar shows 购买 and zero proxy command bar even on provider update.
    await tester.tap(find.descendant(of: rail, matching: find.text('购买')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: appBar, matching: find.text('购买')),
      findsOneWidget,
    );
    expect(find.descendant(of: appBar, matching: commandBar), findsNothing);
    expect(commandBar, findsNothing);

    container.read(runTimeProvider.notifier).value = 2000;
    await tester.pumpAndSettle();
    expect(find.descendant(of: appBar, matching: commandBar), findsNothing);
    expect(commandBar, findsNothing);

    // 3. Navigate to Tools (设置) tab -> AppBar shows 设置 and zero proxy command bar.
    await tester.tap(find.byKey(const ValueKey('navigation-item-tools')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: appBar, matching: find.text('设置')),
      findsOneWidget,
    );
    expect(find.descendant(of: appBar, matching: commandBar), findsNothing);
    expect(commandBar, findsNothing);

    // 4. Return to Proxies tab -> command bar cleanly restored in AppBar.
    await tester.tap(find.descendant(of: rail, matching: find.text('代理')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: appBar, matching: find.text('代理')),
      findsOneWidget,
    );
    expect(find.descendant(of: appBar, matching: commandBar), findsOneWidget);
    expect(commandBar, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'PA-05a: 0-profile empty card shows 3-step guide while top add-subscription imports subscription end-to-end and enables mode + quick use',
      (tester) async {
    final spyTester = _SpyCatalogTester();
    const importedProfile = Profile(
      id: 'sub-1',
      label: '新手专线',
      url: 'https://sub.example.com/api/v1/client/subscribe?token=pa05',
      autoUpdateDuration: defaultUpdateDuration,
    );
    final importedCatalog = ProfileCatalog(
      profileId: 'sub-1',
      fingerprint: 'fp-sub-1',
      status: ProfileCatalogStatus.ready,
      nodes: [
        _node('hk-fast', 'HK Fast'),
        _node('us-slow', 'US Slow'),
      ],
    );
    final now = DateTime(2026, 11, 14, 12, 0);

    final container = await _mountDesktopShell(
      tester,
      size: const Size(1280, 900),
      profiles: const [],
      catalogTester: spyTester,
      catalogs: {'sub-1': importedCatalog},
      health: {
        'sub-1': {
          'hk-fast': NodeHealthRecord(
            delayMs: 45,
            testedAt: now,
            testUrlHash: 'h',
          ),
          'us-slow': NodeHealthRecord(
            delayMs: 180,
            testedAt: now,
            testUrlHash: 'h',
          ),
        },
      },
      onAddProfileFormURL: (url, ref) async {
        ref.read(profilesProvider.notifier).setProfile(importedProfile);
        ref.read(currentProfileIdProvider.notifier).value = importedProfile.id;
        ref.read(groupsProvider.notifier).value = const [
          Group(
            name: 'Proxy',
            type: GroupType.Selector,
            hidden: false,
            now: 'US Slow',
            all: [
              Proxy(name: 'HK Fast', type: 'VLESS'),
              Proxy(name: 'US Slow', type: 'VLESS'),
            ],
          ),
        ];
        ref.read(delayDataSourceProvider.notifier).value = {
          defaultTestUrl: const {
            'HK Fast': 45,
            'US Slow': 180,
          },
        };
      },
    );

    final emptyCard = find.byKey(const ValueKey('overview-empty-profiles'));
    expect(emptyCard, findsOneWidget);
    expect(
      find.descendant(
        of: emptyCard,
        matching: find.textContaining('① 添加订阅'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: emptyCard,
        matching: find.textContaining('② 自动测速'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: emptyCard,
        matching: find.textContaining('③ 一键连最快'),
      ),
      findsOneWidget,
    );

    final commandBar = find.byKey(const ValueKey('overview-top-command-bar'));
    final addBtn = find.byKey(const ValueKey('overview-add-subscription'));
    final quickUseBtn = find.byKey(const ValueKey('overview-quick-use'));
    expect(find.descendant(of: find.byType(AppBar), matching: commandBar),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('overview-connection-bar')), findsNothing);
    expect(tester.widget<TextButton>(addBtn).onPressed, isNotNull);
    expect(tester.widget<TextButton>(quickUseBtn).onPressed, isNull);

    // Import via top bar "添加订阅".
    await tester.tap(addBtn);
    await tester.pumpAndSettle();
    expect(find.byType(URLFormDialog), findsOneWidget);
    await tester.enterText(
      find.byType(TextField),
      'https://sub.example.com/api/v1/client/subscribe?token=pa05',
    );
    await tester.tap(find.byKey(const ValueKey('url-dialog-confirm')));
    await tester.pumpAndSettle();

    expect(find.byType(URLFormDialog), findsNothing);
    expect(emptyCard, findsNothing);
    expect(find.byKey(const ValueKey('overview-connection-bar')),
        findsOneWidget);
    expect(tester.widget<TextButton>(quickUseBtn).onPressed, isNotNull);

    // Switch to manual mode, stop proxy, then trigger quick use end-to-end.
    await tester.tap(find.byKey(const ValueKey('overview-mode-manual')));
    await tester.pumpAndSettle();
    expect(
      resolveProfileSelectionMode(
        container.read(profilesProvider).getProfile('sub-1'),
      ),
      NodeSelectionMode.manual,
    );
    expect(
      container.read(profilesProvider).getProfile('sub-1')?.selectedMap['Proxy'],
      'HK Fast',
    );

    container.read(runTimeProvider.notifier).value = null;
    await tester.pumpAndSettle();
    await tester.tap(quickUseBtn);
    await tester.pumpAndSettle();
    expect(container.read(runTimeProvider), isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'PA-05b: tester feedback surfaces overview-feedback with overview-feedback-dismiss that persistently clears and hides the banner',
      (tester) async {
    final spyTester = _SpyCatalogTester()..reason = 'timeout';
    const profileA = Profile(
      id: 'p1',
      label: '主力订阅',
      url: 'https://sub.example.com/p1',
      autoUpdateDuration: defaultUpdateDuration,
      currentGroupName: 'Proxy',
      selectedMap: {'Proxy': '香港 01'},
    );
    await _mountDesktopShell(
      tester,
      size: const Size(1280, 900),
      profiles: const [profileA],
      currentProfileId: 'p1',
      catalogTester: spyTester,
      groups: const [
        Group(
          name: 'Proxy',
          type: GroupType.Selector,
          hidden: false,
          now: '香港 01',
          all: [Proxy(name: '香港 01', type: 'VLESS')],
        ),
      ],
      catalogs: {
        'p1': ProfileCatalog(
          profileId: 'p1',
          fingerprint: 'fp1',
          status: ProfileCatalogStatus.ready,
          nodes: [_node('hk-1', '香港 01')],
        ),
      },
    );

    expect(find.byKey(const ValueKey('overview-feedback')), findsNothing);
    expect(
        find.byKey(const ValueKey('overview-feedback-dismiss')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('overview-test-current')));
    await tester.pumpAndSettle();

    final feedbackFinder = find.byKey(const ValueKey('overview-feedback'));
    final dismissFinder =
        find.byKey(const ValueKey('overview-feedback-dismiss'));
    expect(feedbackFinder, findsOneWidget);
    expect(dismissFinder, findsOneWidget);

    final feedbackRect = tester.getRect(feedbackFinder);
    final dismissRect = tester.getRect(dismissFinder);
    expect(feedbackRect.overlaps(dismissRect), isFalse);
    expect(dismissRect.center.dy, closeTo(feedbackRect.center.dy, 12.0));

    await tester.tap(dismissFinder);
    await tester.pumpAndSettle();

    expect(feedbackFinder, findsNothing);
    expect(dismissFinder, findsNothing);

    // Ensure dismissed feedback does not resurrect after UI rebuild (tracker cleared too).
    await tester
        .tap(find.byKey(const ValueKey('navigation-expert-mode-toggle')));
    await tester.pumpAndSettle();
    expect(feedbackFinder, findsNothing);
    expect(dismissFinder, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'PA-06: 1040px and 1160px @ 1.20x textScale with expertExpanded=true and globalModeEnabled=true across zh_CN/en/ja/ru render unique inline command bar with readable connection bar and zero overflow or occlusion',
      (tester) async {
    const profileA = Profile(
      id: 'p1',
      label: '超长旗舰线路配置名称-LongProfile',
      url: 'https://sub.example.com/p1',
      autoUpdateDuration: defaultUpdateDuration,
      currentGroupName: 'Proxy',
      selectedMap: {'Proxy': '香港 IPLC 超高速专线节点-01'},
    );
    const groups = [
      Group(
        name: 'Proxy',
        type: GroupType.Selector,
        hidden: false,
        now: '香港 IPLC 超高速专线节点-01',
        all: [
          Proxy(name: '香港 IPLC 超高速专线节点-01', type: 'VLESS'),
          Proxy(name: '日本 01', type: 'VLESS'),
        ],
      ),
    ];
    final catalogs = {
      'p1': ProfileCatalog(
        profileId: 'p1',
        fingerprint: 'fp1',
        status: ProfileCatalogStatus.ready,
        nodes: [
          _node('hk-1', '香港 IPLC 超高速专线节点-01'),
          _node('jp-1', '日本 01'),
        ],
      ),
    };
    const cases = <(double, Locale, String)>[
      (1040, Locale('zh', 'CN'), '代理'),
      (1040, Locale('en'), 'Proxies'),
      (1040, Locale('ja'), 'プロキシ'),
      (1040, Locale('ru'), 'Прокси'),
      (1160, Locale('zh', 'CN'), '代理'),
      (1160, Locale('en'), 'Proxies'),
      (1160, Locale('ja'), 'プロキシ'),
      (1160, Locale('ru'), 'Прокси'),
    ];

    for (final (width, locale, expectedTitle) in cases) {
      await _mountDesktopShell(
        tester,
        size: Size(width, 900),
        locale: locale,
        textScale: 1.20,
        profiles: const [profileA],
        currentProfileId: 'p1',
        runTime: 1000,
        groups: groups,
        catalogs: catalogs,
      );

      // Enable expert mode so scope menu, mode selector, search, and menu all share the AppBar.
      await tester
          .tap(find.byKey(const ValueKey('navigation-expert-mode-toggle')));
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: 'Unexpected exception/overflow at $width @ 1.20x ($locale)',
      );

      final appBar = find.byType(AppBar);
      final overview = find.byType(NodeOverviewView);
      final commandBar = find.byKey(const ValueKey('overview-top-command-bar'));
      final connBar = find.byKey(const ValueKey('overview-connection-bar'));
      final scopeMenu = find.byKey(const ValueKey('overview-scope-menu'));
      final modeAction = find.descendant(
        of: appBar,
        matching: find.byIcon(Icons.rule),
      );
      final searchAction = find.descendant(
        of: appBar,
        matching: find.byIcon(Icons.search),
      );
      final moreAction = find.descendant(
        of: appBar,
        matching: find.byIcon(Icons.more_vert),
      );

      // Confirm expertExpanded=true and globalModeEnabled=true actions are all active in AppBar
      // (<1200px uses compact overview-scope-menu so inline command bar preserves comfortable room).
      expect(scopeMenu, findsOneWidget);
      expect(modeAction, findsOneWidget);
      expect(searchAction, findsOneWidget);
      expect(moreAction, findsOneWidget);

      // Command bar must be unique, inline in AppBar, with readable non-zero connection bar.
      expect(commandBar, findsOneWidget);
      expect(find.descendant(of: appBar, matching: commandBar), findsOneWidget);
      expect(
        find.descendant(of: overview, matching: commandBar),
        findsNothing,
      );

      final commandBarRect = tester.getRect(commandBar);
      final connBarRect = tester.getRect(connBar);
      final addBtnRect = tester.getRect(
        find.byKey(const ValueKey('overview-add-subscription')),
      );
      final modeTrackRect = tester.getRect(
        find.byKey(const ValueKey('overview-mode-segmented-track')),
      );
      final quickUseRect = tester.getRect(
        find.byKey(const ValueKey('overview-quick-use')),
      );
      final railRect = tester.getRect(find.byType(CommonNavigationBar));
      final titleRect = tester.getRect(
        find.descendant(of: appBar, matching: find.text(expectedTitle)),
      );
      final scopeRect = tester.getRect(scopeMenu);

      expect(
        connBarRect.width,
        greaterThanOrEqualTo(64.0),
        reason:
            'Connection bar compressed too narrow (${connBarRect.width}) at $width @ 1.20x ($locale)',
      );
      expect(addBtnRect.width, greaterThanOrEqualTo(24.0));
      expect(modeTrackRect.width, greaterThanOrEqualTo(48.0));
      expect(quickUseRect.width, greaterThanOrEqualTo(24.0));

      // Non-overlapping horizontal order inside command bar.
      expect(addBtnRect.right, lessThanOrEqualTo(connBarRect.left + 1.0));
      expect(connBarRect.right, lessThanOrEqualTo(modeTrackRect.left + 1.0));
      expect(modeTrackRect.right, lessThanOrEqualTo(quickUseRect.left + 1.0));

      // Non-overlapping with rail, AppBar title, and expert/global AppBar actions.
      expect(commandBarRect.overlaps(railRect), isFalse);
      expect(commandBarRect.left, greaterThanOrEqualTo(titleRect.right - 1.0));
      expect(commandBarRect.right, lessThanOrEqualTo(scopeRect.left + 1.0));
      expect(commandBarRect.overlaps(tester.getRect(modeAction)), isFalse);
      expect(commandBarRect.overlaps(tester.getRect(searchAction)), isFalse);
      expect(commandBarRect.overlaps(tester.getRect(moreAction)), isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
      'PA-07: KeepScope + const subtree dynamically toggling runtime textScale 1.0x -> 1.4x -> 1.0x at 1280x900 keeps exactly 1 command bar and toggles inline <-> body cleanly',
      (tester) async {
    const profileA = Profile(
      id: 'p1',
      label: '主力订阅',
      url: 'https://sub.example.com/p1',
      autoUpdateDuration: defaultUpdateDuration,
      currentGroupName: 'Proxy',
      selectedMap: {'Proxy': '香港 01'},
    );
    final container = await _mountDesktopShell(
      tester,
      size: const Size(1280, 900),
      textScale: 1.0,
      profiles: const [profileA],
      currentProfileId: 'p1',
      runTime: 1000,
      groups: const [
        Group(
          name: 'Proxy',
          type: GroupType.Selector,
          hidden: false,
          now: '香港 01',
          all: [Proxy(name: '香港 01', type: 'VLESS')],
        ),
      ],
      catalogs: {
        'p1': ProfileCatalog(
          profileId: 'p1',
          fingerprint: 'fp1',
          status: ProfileCatalogStatus.ready,
          nodes: [_node('hk-1', '香港 01')],
        ),
      },
      customHome: const _DesktopPageViewShell(),
    );

    final appBar = find.byType(AppBar);
    final overview = find.byType(NodeOverviewView);
    final commandBar = find.byKey(const ValueKey('overview-top-command-bar'));

    // 1.0x initial: inline in AppBar, absent from body.
    expect(commandBar, findsOneWidget);
    expect(find.descendant(of: appBar, matching: commandBar), findsOneWidget);
    expect(find.descendant(of: overview, matching: commandBar), findsNothing);
    expect(tester.takeException(), isNull);

    // Runtime toggle 1.0x -> 1.4x: inline turns off, body fallback appears (still strictly 1).
    container.read(themeSettingProvider.notifier).updateState(
          (state) => state.copyWith(
            textScale: const TextScale(enable: true, scale: 1.4),
          ),
        );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(commandBar, findsOneWidget);
    expect(find.descendant(of: appBar, matching: commandBar), findsNothing);
    expect(find.descendant(of: overview, matching: commandBar), findsOneWidget);

    // Runtime toggle 1.4x -> 1.0x: body fallback removes, AppBar inline resumes (still strictly 1).
    container.read(themeSettingProvider.notifier).updateState(
          (state) => state.copyWith(
            textScale: const TextScale(enable: true, scale: 1.0),
          ),
        );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(commandBar, findsOneWidget);
    expect(find.descendant(of: appBar, matching: commandBar), findsOneWidget);
    expect(find.descendant(of: overview, matching: commandBar), findsNothing);
  });

  testWidgets(
      'PA-08: staying on Proxies under KeepScope while switching locale zh_CN -> en -> zh_CN restores AppBar titleAccessory, actions, and searchState without loss',
      (tester) async {
    const profileA = Profile(
      id: 'p1',
      label: '主力订阅',
      url: 'https://sub.example.com/p1',
      autoUpdateDuration: defaultUpdateDuration,
      currentGroupName: 'Proxy',
      selectedMap: {'Proxy': '香港 01'},
    );
    final container = await _mountDesktopShell(
      tester,
      size: const Size(1280, 900),
      locale: const Locale('zh', 'CN'),
      profiles: const [profileA],
      currentProfileId: 'p1',
      runTime: 1000,
      groups: const [
        Group(
          name: 'Proxy',
          type: GroupType.Selector,
          hidden: false,
          now: '香港 01',
          all: [Proxy(name: '香港 01', type: 'VLESS')],
        ),
      ],
      catalogs: {
        'p1': ProfileCatalog(
          profileId: 'p1',
          fingerprint: 'fp1',
          status: ProfileCatalogStatus.ready,
          nodes: [_node('hk-1', '香港 01')],
        ),
      },
      customHome: const _DesktopPageViewShell(),
    );

    final appBar = find.byType(AppBar);
    final overview = find.byType(NodeOverviewView);
    final commandBar = find.byKey(const ValueKey('overview-top-command-bar'));

    // Enable expert mode so scope segments, mode selector, search, and more_vert are all in AppBar.
    await tester
        .tap(find.byKey(const ValueKey('navigation-expert-mode-toggle')));
    await tester.pumpAndSettle();

    expect(find.descendant(of: appBar, matching: find.text('代理')), findsOneWidget);
    expect(commandBar, findsOneWidget);
    expect(find.descendant(of: appBar, matching: commandBar), findsOneWidget);
    expect(
      find.descendant(
        of: appBar,
        matching: find.byKey(const ValueKey('overview-scope-segments')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: appBar, matching: find.byIcon(Icons.rule)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: appBar, matching: find.byIcon(Icons.search)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: appBar, matching: find.byIcon(Icons.more_vert)),
      findsOneWidget,
    );

    // Switch locale zh_CN -> en while staying on Proxies inside KeepScope.
    container.read(appSettingProvider.notifier).updateState(
          (state) => state.copyWith(locale: 'en'),
        );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.descendant(of: appBar, matching: find.text('Proxies')),
      findsOneWidget,
    );
    expect(commandBar, findsOneWidget);
    expect(find.descendant(of: appBar, matching: commandBar), findsOneWidget);
    expect(find.descendant(of: overview, matching: commandBar), findsNothing);
    expect(
      find.descendant(
        of: appBar,
        matching: find.byKey(const ValueKey('overview-scope-segments')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: appBar, matching: find.byIcon(Icons.rule)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: appBar, matching: find.byIcon(Icons.search)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: appBar, matching: find.byIcon(Icons.more_vert)),
      findsOneWidget,
    );

    // Switch locale back en -> zh_CN while staying on Proxies.
    container.read(appSettingProvider.notifier).updateState(
          (state) => state.copyWith(locale: 'zh_CN'),
        );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.descendant(of: appBar, matching: find.text('代理')), findsOneWidget);
    expect(commandBar, findsOneWidget);
    expect(find.descendant(of: appBar, matching: commandBar), findsOneWidget);
    expect(find.descendant(of: overview, matching: commandBar), findsNothing);
    expect(
      find.descendant(
        of: appBar,
        matching: find.byKey(const ValueKey('overview-scope-segments')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: appBar, matching: find.byIcon(Icons.rule)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: appBar, matching: find.byIcon(Icons.search)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: appBar, matching: find.byIcon(Icons.more_vert)),
      findsOneWidget,
    );

    // Verify search state was restored after locale changes: search opens and exits cleanly.
    await tester
        .tap(find.descendant(of: appBar, matching: find.byIcon(Icons.search)));
    await tester.pumpAndSettle();
    expect(commandBar, findsOneWidget);
    expect(find.descendant(of: overview, matching: commandBar), findsOneWidget);
    expect(find.descendant(of: appBar, matching: commandBar), findsNothing);

    await tester.tap(
      find.descendant(of: appBar, matching: find.byIcon(Icons.arrow_back)),
    );
    await tester.pumpAndSettle();
    expect(commandBar, findsOneWidget);
    expect(find.descendant(of: appBar, matching: commandBar), findsOneWidget);
    expect(find.descendant(of: overview, matching: commandBar), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

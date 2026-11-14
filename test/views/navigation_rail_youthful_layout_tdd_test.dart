import 'dart:async';

import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/theme.dart';
import 'package:flclashx/controller.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/manager/support_manager.dart';
import 'package:flclashx/models/chatwoot.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/models/xboard.dart';
import 'package:flclashx/pages/home.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/providers/purchase_support_provider.dart';
import 'package:flclashx/services/chatwoot_service.dart';
import 'package:flclashx/services/chatwoot_storage.dart';
import 'package:flclashx/services/purchase_storage.dart';
import 'package:flclashx/services/xboard_api.dart';
import 'package:flclashx/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestAppController extends Fake implements AppController {
  _TestAppController(this.ref);

  final WidgetRef ref;

  @override
  void toPage(PageLabel pageLabel) {
    if (!noviceVisiblePageLabels.contains(pageLabel)) {
      ref.read(expertNavigationExpandedProvider.notifier).state = true;
    }
    ref.read(currentPageLabelProvider.notifier).value = pageLabel;
  }

  @override
  void updateCurrentSelectedMap(String groupName, String proxyName) {}

  @override
  void changeProxyDebounce(String groupName, String proxyName) {}

  @override
  void updateCurrentGroupName(String groupName) {}
}

class _MemPurchaseStorage implements PurchaseStorage {
  PurchaseSession? session;
  final Map<int, PendingGiftRedemption> pending = {};
  final Map<int, String> profileIds = {};

  @override
  Future<PurchaseSession?> readSession() async => session;

  @override
  Future<void> saveSession(PurchaseSession value) async => session = value;

  @override
  Future<void> clearSession() async => session = null;

  @override
  Future<PendingGiftRedemption?> readPending(int accountId) async =>
      pending[accountId];

  @override
  Future<void> savePending(int accountId, PendingGiftRedemption value) async =>
      pending[accountId] = value;

  @override
  Future<void> clearPending(int accountId) async => pending.remove(accountId);

  @override
  Future<String?> readProfileId(int accountId) async => profileIds[accountId];

  @override
  Future<void> saveProfileId(int accountId, String profileId) async =>
      profileIds[accountId] = profileId;
}

class _MemChatwootStorage implements ChatwootSessionStorage {
  final Map<String, ChatwootSession> _store = {};

  @override
  Future<void> clearSession({
    required Uri baseUrl,
    required String websiteToken,
    required String scopeKey,
  }) async {
    _store.remove('${baseUrl.origin}|$websiteToken|$scopeKey');
  }

  @override
  Future<ChatwootSession?> readSession({
    required Uri baseUrl,
    required String websiteToken,
    required String scopeKey,
  }) async =>
      _store['${baseUrl.origin}|$websiteToken|$scopeKey'];

  @override
  Future<void> saveSession({
    required Uri baseUrl,
    required String websiteToken,
    required ChatwootSession session,
  }) async {
    _store['${baseUrl.origin}|$websiteToken|${session.scopeKey}'] = session;
  }
}

class _FakeRealtime implements ChatwootRealtimeConnection {
  final StreamController<ChatwootRealtimeEvent> _controller =
      StreamController<ChatwootRealtimeEvent>.broadcast();
  bool _closed = false;

  @override
  Stream<ChatwootRealtimeEvent> get events => _controller.stream;

  @override
  Future<void> get done => _controller.done;

  @override
  bool get isClosed => _closed;

  @override
  Future<void> sendPresence() async {}

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _controller.close();
  }
}

class _FakeChatwootService extends Fake implements ChatwootService {
  @override
  Future<
      ({
        ChatwootChannelConfig config,
        String authToken,
        ChatwootContact contact,
      })> initializeSession({
    required Uri baseUrl,
    required String websiteToken,
    String? authToken,
  }) async =>
      (
        config: ChatwootChannelConfig(
          baseUrl: baseUrl,
          websiteToken: websiteToken,
          websiteName: 'FreedomNet 客服',
          welcomeTitle: '欢迎光临',
          welcomeTagline: '通常 5 分钟内回复',
          replyTime: '通常几分钟内回复',
          allowMessagesAfterResolved: false,
        ),
        authToken: authToken ?? 'cw-auth-1',
        contact: const ChatwootContact(
          id: 9001,
          name: 'Visitor',
          pubsubToken: 'pubsub-1',
        ),
      );

  @override
  Future<ChatwootContact?> updateContact({
    required Uri baseUrl,
    required String websiteToken,
    required String authToken,
    String? email,
    String? name,
    Map<String, Object?>? customAttributes,
  }) async =>
      null;

  @override
  Future<ChatwootConversation?> fetchConversation({
    required Uri baseUrl,
    required String websiteToken,
    required String authToken,
  }) async =>
      const ChatwootConversation(id: 501, status: 'open');

  @override
  Future<List<ChatwootMessage>> fetchMessages({
    required Uri baseUrl,
    required String websiteToken,
    required String authToken,
    int? before,
    int? after,
  }) async =>
      const [];
}

class _FakeSupportPassportApi extends Fake
    implements XboardApi, XboardPassportApi {
  @override
  final Uri baseUri = Uri.parse('https://fast.hjy.ca:8443');

  @override
  Future<XboardGuestAuthConfig> getGuestAuthConfig() async =>
      const XboardGuestAuthConfig();

  @override
  Future<XboardPurchaseChannels> getGuestPurchaseChannels() async =>
      XboardPurchaseChannels(
        cardStoreUrl: Uri.parse('https://shop.example.test/all'),
        chatwootBaseUrl: Uri.parse('https://chat.example.test'),
        chatwootWebsiteToken: 'cw-token-test',
      );

  @override
  Future<XboardPurchaseChannels> getUserPurchaseChannels(
    String authorization,
  ) =>
      getGuestPurchaseChannels();

  @override
  Future<XboardPlanCatalog> getPlanCatalog() async =>
      const XboardPlanCatalog(plans: []);

  @override
  void close() {}
}

ThemeData _buildTheme({
  required Brightness brightness,
  bool pureBlack = false,
}) {
  final scheme = calibrateFreedomNetColorScheme(
    ColorScheme.fromSeed(
      seedColor: const Color(defaultPrimaryColor),
      brightness: brightness,
    ),
    seedColor: const Color(defaultPrimaryColor),
  ).toPureBlack(pureBlack);
  return buildFreedomNetThemeData(colorScheme: scheme);
}

Widget _buildDesktopRailHost({
  Key? scopeKey,
  required Locale locale,
  required Brightness brightness,
  bool pureBlack = false,
  double textScale = 1.0,
  List<Override> overrides = const [],
}) =>
    ProviderScope(
      key: scopeKey,
      overrides: overrides,
      child: MediaQuery(
        data: MediaQueryData(
          size: const Size(1280, 900),
          textScaler: TextScaler.linear(textScale),
        ),
        child: MaterialApp(
          locale: locale,
          theme: _buildTheme(brightness: brightness, pureBlack: pureBlack),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.delegate.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
          home: Consumer(
            builder: (context, ref, _) {
              globalState.measure = Measure.of(context, textScale);
              globalState.theme = CommonTheme.of(context, textScale);
              globalState.appController = _TestAppController(ref);
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
                    Expanded(
                      child: Center(
                        child: Text('Page:${pageLabel.name}'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );

BoxDecoration _readBadgeDecoration(WidgetTester tester, String badgeId) {
  final finder = find.byKey(ValueKey('nav-badge-$badgeId'));
  expect(finder, findsOneWidget);
  final widget = tester.widget<Widget>(finder);
  if (widget is AnimatedContainer) {
    return widget.decoration! as BoxDecoration;
  }
  if (widget is Container) {
    return widget.decoration! as BoxDecoration;
  }
  if (widget is DecoratedBox) {
    return widget.decoration as BoxDecoration;
  }
  final decorated = tester.widget<DecoratedBox>(
    find.descendant(of: finder, matching: find.byType(DecoratedBox)).first,
  );
  return decorated.decoration as BoxDecoration;
}

BoxDecoration _readToggleDecoration(WidgetTester tester) {
  final toggleFinder = find.byKey(const ValueKey('navigation-expert-mode-toggle'));
  expect(toggleFinder, findsOneWidget);
  final boxes = tester.widgetList<DecoratedBox>(
    find.descendant(of: toggleFinder, matching: find.byType(DecoratedBox)),
  );
  for (final box in boxes) {
    final dec = box.decoration;
    if (dec is BoxDecoration && dec.gradient is LinearGradient) {
      return dec;
    }
  }
  fail('Expected navigation-expert-mode-toggle to paint a LinearGradient capsule');
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

  testWidgets(
      'Desktop rail places 在线客服 directly below 购买 and pins 大佬模式/小白模式 to bottom-left corner without shifting on toggle',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final previousConfig = globalState.config;
    addTearDown(() {
      globalState.config = previousConfig;
    });
    globalState.config = previousConfig.copyWith(
      appSetting: previousConfig.appSetting.copyWith(openLogs: true),
    );

    final supportManager = SupportManager(
      service: _FakeChatwootService(),
      storage: _MemChatwootStorage(),
      realtimeConnector: (_, __) async => _FakeRealtime(),
    );
    addTearDown(supportManager.dispose);

    await tester.pumpWidget(
      _buildDesktopRailHost(
        locale: const Locale('zh', 'CN'),
        brightness: Brightness.light,
        overrides: [
          purchaseSupportCoordinatorProvider.overrideWith((ref) {
            final coordinator = PurchaseSupportCoordinator.test(
              ref,
              api: _FakeSupportPassportApi(),
              storage: _MemPurchaseStorage(),
              supportManager: supportManager,
            );
            ref.onDispose(coordinator.dispose);
            return coordinator;
          }),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final panelFinder = find.byKey(const ValueKey('desktop-navigation-rail-panel'));
    final brandFinder = find.byKey(const ValueKey('brand-tribute-trigger'));
    final supportFinder = find.byKey(const ValueKey('navigation-support-trigger'));
    final toggleFinder = find.byKey(const ValueKey('navigation-expert-mode-toggle'));

    expect(panelFinder, findsOneWidget);
    expect(brandFinder, findsOneWidget);
    expect(supportFinder, findsOneWidget);
    expect(toggleFinder, findsOneWidget);

    // Toggle button must remain icon-free on desktop.
    expect(
      find.descendant(of: toggleFinder, matching: find.byType(Icon)),
      findsNothing,
    );

    // 1. Collapsed (小白模式): brand -> 代理 -> 购买 -> 在线客服 -> bottom-left 大佬模式.
    final collapsedOrder = <Finder>[
      brandFinder,
      find.text('代理'),
      find.text('购买'),
      supportFinder,
      toggleFinder,
    ];
    for (var i = 0; i < collapsedOrder.length - 1; i++) {
      expect(
        tester.getBottomLeft(collapsedOrder[i]).dy,
        lessThan(tester.getTopLeft(collapsedOrder[i + 1]).dy),
        reason: 'Collapsed item $i should be strictly above item ${i + 1}',
      );
    }

    final panelRect = tester.getRect(panelFinder);
    final collapsedToggleRect = tester.getRect(toggleFinder);
    expect(collapsedToggleRect.left, lessThan(120.0));
    expect(collapsedToggleRect.bottom, greaterThan(830.0));
    expect(panelRect.bottom - collapsedToggleRect.bottom, lessThanOrEqualTo(48.0));

    // Gap between 购买 and 在线客服 is compact (directly below), whereas gap before
    // bottom-left toggle is large whitespace/footer separation.
    final gapPurchaseToSupport =
        tester.getTopLeft(supportFinder).dy - tester.getBottomLeft(find.text('购买')).dy;
    final gapSupportToBottomToggle =
        collapsedToggleRect.top - tester.getBottomLeft(supportFinder).dy;
    expect(gapPurchaseToSupport, lessThan(40.0));
    expect(gapSupportToBottomToggle, greaterThan(300.0));

    // 2. Expand 大佬模式 -> toggle stays pinned at bottom-left, advanced items appear below 在线客服.
    await tester.tap(toggleFinder);
    await tester.pumpAndSettle();

    expect(find.text('小白模式'), findsOneWidget);
    expect(find.text('大佬模式'), findsNothing);
    expect(
      find.descendant(of: toggleFinder, matching: find.byType(Icon)),
      findsNothing,
    );

    final expandedToggleRect = tester.getRect(toggleFinder);
    expect(expandedToggleRect.top, closeTo(collapsedToggleRect.top, 0.01));
    expect(expandedToggleRect.bottom, closeTo(collapsedToggleRect.bottom, 0.01));

    final expandedOrder = <Finder>[
      brandFinder,
      find.text('代理'),
      find.text('购买'),
      supportFinder,
      find.text('仪表盘'),
      find.text('配置'),
      find.text('连接'),
      find.text('日志'),
      find.text('设置'),
      toggleFinder,
    ];
    for (var i = 0; i < expandedOrder.length - 1; i++) {
      expect(
        tester.getBottomLeft(expandedOrder[i]).dy,
        lessThan(tester.getTopLeft(expandedOrder[i + 1]).dy),
        reason: 'Expanded item $i should be strictly above item ${i + 1}',
      );
    }

    // 3. Tapping 在线客服 right below 购买 opens support-chat-sheet cleanly.
    await tester.tap(supportFinder);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('support-chat-sheet')), findsOneWidget);
    await tester.tap(find.byKey(const Key('support-close')));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(find.byKey(const Key('support-chat-sheet')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Rail panel and every button expose distinct vibrant youthful gradients in Light, Dark, and PureBlack modes',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final previousConfig = globalState.config;
    addTearDown(() {
      globalState.config = previousConfig;
    });
    globalState.config = previousConfig.copyWith(
      appSetting: previousConfig.appSetting.copyWith(openLogs: true),
    );

    for (final mode in const [
      (brightness: Brightness.light, pureBlack: false, name: 'light'),
      (brightness: Brightness.dark, pureBlack: false, name: 'dark'),
      (brightness: Brightness.dark, pureBlack: true, name: 'pureBlack'),
    ]) {
      globalState.appState = globalState.appState.copyWith(
        pageLabel: PageLabel.proxies,
      );
      await tester.pumpWidget(
        _buildDesktopRailHost(
          scopeKey: ValueKey(mode.name),
          locale: const Locale('zh', 'CN'),
          brightness: mode.brightness,
          pureBlack: mode.pureBlack,
        ),
      );
      await tester.pumpAndSettle();

      // Expand 大佬模式 so all 8 badges are mounted.
      final toggleFinder =
          find.byKey(const ValueKey('navigation-expert-mode-toggle'));
      final collapsedCapsuleGradient =
          _readToggleDecoration(tester).gradient! as LinearGradient;
      expect(collapsedCapsuleGradient.colors.length, greaterThanOrEqualTo(2));

      await tester.tap(toggleFinder);
      await tester.pumpAndSettle();

      final expandedCapsuleGradient =
          _readToggleDecoration(tester).gradient! as LinearGradient;
      expect(
        expandedCapsuleGradient.colors,
        isNot(equals(collapsedCapsuleGradient.colors)),
        reason: 'Expanded vs collapsed mode toggle should switch youthful gradients (${mode.name})',
      );

      // Rail panel must use multi-stop LinearGradient rather than monochrome grey.
      final panelBox = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('desktop-navigation-rail-panel')),
      );
      final panelDec = panelBox.decoration as BoxDecoration;
      expect(panelDec.gradient, isA<LinearGradient>());
      final panelGradient = panelDec.gradient! as LinearGradient;
      expect(panelGradient.colors.length, greaterThanOrEqualTo(3));
      expect(
        panelGradient.colors.first.toARGB32(),
        isNot(equals(panelGradient.colors.last.toARGB32())),
      );

      // All 8 badges must have LinearGradient decorations with distinct hues.
      const badgeIds = [
        'proxies',
        'purchase',
        'support',
        'dashboard',
        'profiles',
        'connections',
        'logs',
        'tools',
      ];
      final gradientSignatures = <String>{};
      for (final id in badgeIds) {
        final dec = _readBadgeDecoration(tester, id);
        expect(dec.gradient, isA<LinearGradient>(), reason: 'badge $id (${mode.name})');
        final grad = dec.gradient! as LinearGradient;
        expect(grad.colors.length, greaterThanOrEqualTo(2));
        final sig = grad.colors.map((c) => c.toARGB32().toRadixString(16)).join('-');
        gradientSignatures.add(sig);
      }
      expect(
        gradientSignatures.length,
        equals(badgeIds.length),
        reason: 'Each navigation button must have a unique vibrant palette (${mode.name})',
      );

      // Selected proxies badge has crisp white icon inside full-saturation gradient & glow.
      final proxiesDec = _readBadgeDecoration(tester, 'proxies');
      expect(proxiesDec.boxShadow, isNotEmpty);
      final proxiesIconTheme = tester.widget<IconTheme>(
        find
            .descendant(
              of: find.byKey(const ValueKey('nav-badge-proxies')),
              matching: find.byType(IconTheme),
            )
            .first,
      );
      expect(proxiesIconTheme.data.color, equals(Colors.white));

      // Selecting dashboard shifts white icon + glow to dashboard badge.
      await tester.tap(find.text('仪表盘'));
      await tester.pumpAndSettle();

      final dashboardIconTheme = tester.widget<IconTheme>(
        find
            .descendant(
              of: find.byKey(const ValueKey('nav-badge-dashboard')),
              matching: find.byType(IconTheme),
            )
            .first,
      );
      expect(dashboardIconTheme.data.color, equals(Colors.white));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets(
      'Short desktop height (1280x440) and 2.0x text scaling across zh_CN/en/ja/ru render overflow-free',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 440);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final previousConfig = globalState.config;
    addTearDown(() {
      globalState.config = previousConfig;
    });
    globalState.config = previousConfig.copyWith(
      appSetting: previousConfig.appSetting.copyWith(openLogs: true),
    );

    // 1. Short window 1280x440: expand all items, verify support directly below purchase, scroll to 设置, collapse back.
    await tester.pumpWidget(
      _buildDesktopRailHost(
        locale: const Locale('zh', 'CN'),
        brightness: Brightness.light,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final toggleFinder = find.byKey(const ValueKey('navigation-expert-mode-toggle'));
    await tester.tap(toggleFinder);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final supportFinder = find.byKey(const ValueKey('navigation-support-trigger'));
    expect(
      tester.getTopLeft(supportFinder).dy,
      greaterThan(tester.getBottomLeft(find.text('购买')).dy),
    );

    await tester.ensureVisible(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('Page:tools'), findsOneWidget);

    await tester.tap(toggleFinder);
    await tester.pumpAndSettle();
    expect(find.text('Page:proxies'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 2. Multi-locale 2.0x textScale check at 1280x900 across zh_CN, en, ja, ru.
    tester.view.physicalSize = const Size(1280, 900);
    for (final locale in const [
      Locale('zh', 'CN'),
      Locale('en'),
      Locale('ja'),
      Locale('ru'),
    ]) {
      await AppLocalizations.load(locale);
      await tester.pumpWidget(
        _buildDesktopRailHost(
          scopeKey: ValueKey('locale-${locale.toLanguageTag()}'),
          locale: locale,
          brightness: locale.languageCode == 'en'
              ? Brightness.dark
              : Brightness.light,
          textScale: 2.0,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'collapsed-$locale');

      await tester.tap(find.byKey(const ValueKey('navigation-expert-mode-toggle')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'expanded-$locale');
    }
  });
}

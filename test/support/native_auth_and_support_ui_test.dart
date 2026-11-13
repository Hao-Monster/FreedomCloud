import 'dart:async';

import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/theme.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/manager/purchase_manager.dart';
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
import 'package:flclashx/views/purchase/center.dart';
import 'package:flclashx/views/support/support_chat_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

class _FakePassportApi implements XboardApi, XboardPassportApi {
  _FakePassportApi({required this.authConfig});

  XboardGuestAuthConfig authConfig;
  int sendRegCodeCalls = 0;
  int sendResetCodeCalls = 0;
  int registerCalls = 0;
  int resetConfirmCalls = 0;
  String? lastRegisteredEmail;
  String? lastRegisteredEmailCode;
  String? lastRegisteredInviteCode;
  String? lastResetEmail;
  String? lastResetCode;
  String? lastResetPassword;
  XboardException? nextSendCodeError;
  bool loggedInUser = false;

  @override
  final Uri baseUri = Uri.parse('https://fast.hjy.ca:8443');

  @override
  Future<XboardGuestAuthConfig> getGuestAuthConfig() async => authConfig;

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
  Future<void> sendRegistrationEmailCode(String email) async {
    sendRegCodeCalls++;
    if (nextSendCodeError != null) throw nextSendCodeError!;
  }

  @override
  Future<void> sendPasswordResetEmailCode(String email) async {
    sendResetCodeCalls++;
    if (nextSendCodeError != null) throw nextSendCodeError!;
  }

  @override
  Future<String> registerAccount({
    required String email,
    required String password,
    String? emailCode,
    String? inviteCode,
  }) async {
    registerCalls++;
    lastRegisteredEmail = email;
    lastRegisteredEmailCode = emailCode;
    lastRegisteredInviteCode = inviteCode;
    loggedInUser = true;
    return 'Bearer reg-token';
  }

  @override
  Future<String> register(String email, String password) =>
      registerAccount(email: email, password: password);

  @override
  Future<void> confirmPasswordReset({
    required String email,
    required String emailCode,
    required String password,
  }) async {
    resetConfirmCalls++;
    lastResetEmail = email;
    lastResetCode = emailCode;
    lastResetPassword = password;
  }

  @override
  Future<XboardPlanCatalog> getPlanCatalog() async =>
      const XboardPlanCatalog(plans: [
        XboardPlanOffer(
          id: 1,
          name: '100G 流量包',
          transferGiB: 100,
          prices: [XboardPlanPrice(period: 'onetime', amount: 8800)],
        ),
      ]);

  @override
  Future<String> login(String email, String password) async =>
      'Bearer login-token';

  @override
  Future<XboardAccount> getAccount(String authorization) async =>
      XboardAccount(id: 77, email: lastRegisteredEmail ?? 'user@gmail.com');

  @override
  Future<XboardSubscription> getSubscription(String authorization) async =>
      XboardSubscription(
        valid: true,
        planId: 1,
        planName: '2G 体验',
        total: 2 * 1073741824,
        url: Uri.parse('https://fast.hjy.ca:8443/sub?t=1'),
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
  final StreamController<ChatwootRealtimeEvent> controller =
      StreamController<ChatwootRealtimeEvent>.broadcast();
  bool closed = false;

  @override
  Stream<ChatwootRealtimeEvent> get events => controller.stream;

  @override
  Future<void> get done => controller.done;

  @override
  bool get isClosed => closed;

  @override
  Future<void> sendPresence() async {}

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await controller.close();
  }
}

class _FakeChatwootService implements ChatwootService {
  List<ChatwootMessage> initialMessages = [];
  ChatwootConversation conversation = const ChatwootConversation(
    id: 501,
    status: 'open',
  );
  bool failNextSend = false;
  bool failFetch = false;
  final List<String> sentContents = [];
  int nextMsgId = 100;

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
      conversation;

  @override
  Future<List<ChatwootMessage>> fetchMessages({
    required Uri baseUrl,
    required String websiteToken,
    required String authToken,
    int? before,
    int? after,
  }) async {
    if (failFetch) {
      throw const ChatwootException(
        code: 'network_error',
        message: '连接客服失败',
      );
    }
    return List<ChatwootMessage>.from(initialMessages);
  }

  @override
  Future<ChatwootMessage> sendMessage({
    required Uri baseUrl,
    required String websiteToken,
    required String authToken,
    required String content,
    required String echoId,
  }) async {
    if (failNextSend) {
      failNextSend = false;
      throw const ChatwootException(
        code: 'send_failed',
        message: '网络波动，请重试',
      );
    }
    sentContents.add(content);
    final msg = ChatwootMessage(
      id: nextMsgId++,
      echoId: echoId,
      content: content,
      type: ChatwootMessageType.visitor,
      createdAt: DateTime.now().toUtc(),
    );
    initialMessages.add(msg);
    return msg;
  }

  @override
  Future<void> updateLastSeen({
    required Uri baseUrl,
    required String websiteToken,
    required String authToken,
  }) async {}

  @override
  void close() {}
}

Widget _wrapTestApp({
  required Widget child,
  Locale locale = const Locale('zh', 'CN'),
  double textScale = 1.0,
}) =>
    MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.delegate.supportedLocales,
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      builder: (context, inner) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: inner!,
      ),
      home: Scaffold(body: child),
    );

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
  });

  tearDown(() async {
    await AppLocalizations.load(const Locale('en'));
  });

  testWidgets(
      'Native register flow: email whitelist chips, local validation, email verify + 60s O(1) cooldown, forced invite, ToS link, and CAPTCHA fallback',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _FakePassportApi(
      authConfig: XboardGuestAuthConfig(
        isEmailVerify: true,
        isInviteForce: true,
        emailWhitelistSuffix: const ['gmail.com', 'qq.com'],
        isCaptcha: true,
        tosUrl: Uri.parse('https://fast.hjy.ca:8443/tos'),
      ),
    );
    final manager = PurchaseManager(
      api: api,
      storage: _MemPurchaseStorage(),
      synchronize: (_, __) async {},
    );
    addTearDown(manager.dispose);

    await manager.initialize();
    await manager.loadPlans();
    await manager.ensurePurchaseChannels();

    final openedLinks = <Uri>[];
    await tester.pumpWidget(
      _wrapTestApp(
        child: PurchaseCenter(
          manager: manager,
          openLink: (uri) async => openedLinks.add(uri),
          openProfiles: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Switch to Register tab.
    await tester.tap(find.byKey(const Key('purchase-auth-tab-register')));
    await tester.pumpAndSettle();

    // Whitelist suffix strip + ToS + CAPTCHA fallback + forced invite + email code visible.
    expect(find.byKey(const Key('purchase-email-suffix-strip')), findsOneWidget);
    expect(find.byKey(const Key('purchase-register-email-code')), findsOneWidget);
    expect(find.byKey(const Key('purchase-register-send-code')), findsOneWidget);
    expect(find.byKey(const Key('purchase-register-invite-code')), findsOneWidget);
    expect(find.byKey(const Key('purchase-register-tos-link')), findsOneWidget);
    expect(find.byKey(const Key('purchase-auth-web-fallback')), findsOneWidget);

    // Tapping ToS link and CAPTCHA web fallback triggers openLink.
    await tester.ensureVisible(find.byKey(const Key('purchase-register-tos-link')));
    await tester.tap(find.byKey(const Key('purchase-register-tos-link')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('purchase-auth-web-fallback')));
    await tester.tap(find.byKey(const Key('purchase-auth-web-fallback')));
    await tester.pumpAndSettle();
    expect(
      openedLinks,
      [
        Uri.parse('https://fast.hjy.ca:8443/tos'),
        Uri.parse('https://fast.hjy.ca:8443').replace(fragment: '/register'),
      ],
    );

    // Gmail + alias and non-whitelisted domain are rejected locally before network calls.
    await tester.enterText(
      find.byKey(const Key('purchase-email')),
      'alice+test@gmail.com',
    );
    await tester.ensureVisible(
      find.byKey(const Key('purchase-register-send-code')),
    );
    await tester.tap(find.byKey(const Key('purchase-register-send-code')));
    await tester.pumpAndSettle();
    expect(api.sendRegCodeCalls, 0);

    await tester.enterText(
      find.byKey(const Key('purchase-email')),
      'alice@blocked.org',
    );
    await tester.tap(find.byKey(const Key('purchase-register-send-code')));
    await tester.pumpAndSettle();
    expect(api.sendRegCodeCalls, 0);

    // Tapping @gmail.com chip fixes domain cleanly.
    await tester.tap(find.text('@gmail.com'));
    await tester.pumpAndSettle();
    final emailField = tester.widget<TextFormField>(
      find.byKey(const Key('purchase-email')),
    );
    expect(emailField.controller!.text, 'alice@gmail.com');

    // Sending verification code calls API and starts 60s countdown.
    await tester.tap(find.byKey(const Key('purchase-register-send-code')));
    await tester.pumpAndSettle();
    expect(api.sendRegCodeCalls, 1);
    expect(find.text('60s 后重发'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('58s 后重发'), findsOneWidget);

    // Complete registration with 6-digit code + invite code + password.
    await tester.enterText(
      find.byKey(const Key('purchase-register-email-code')),
      '123456',
    );
    await tester.enterText(
      find.byKey(const Key('purchase-password')),
      'strongPass123',
    );
    await tester.enterText(
      find.byKey(const Key('purchase-register-invite-code')),
      'INVITE88',
    );
    await tester.ensureVisible(find.byKey(const Key('purchase-register-submit')));
    await tester.tap(find.byKey(const Key('purchase-register-submit')));
    await tester.pumpAndSettle();

    expect(api.registerCalls, 1);
    expect(api.lastRegisteredEmail, 'alice@gmail.com');
    expect(api.lastRegisteredEmailCode, '123456');
    expect(api.lastRegisteredInviteCode, 'INVITE88');
    expect(manager.loggedIn, isTrue);
  });

  testWidgets(
      'Native forgot password flow: send reset code, confirm new password, and return to login with email preserved & success notice',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _FakePassportApi(
      authConfig: const XboardGuestAuthConfig(),
    );
    final manager = PurchaseManager(
      api: api,
      storage: _MemPurchaseStorage(),
      synchronize: (_, __) async {},
    );
    addTearDown(manager.dispose);

    await manager.initialize();
    await manager.loadPlans();
    await manager.ensurePurchaseChannels();

    await tester.pumpWidget(
      _wrapTestApp(
        child: PurchaseCenter(
          manager: manager,
          openLink: (_) async {},
          openProfiles: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('purchase-email')),
      'member@gmail.com',
    );
    await tester.tap(find.byKey(const Key('purchase-auth-forgot-trigger')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('purchase-reset-email-code')), findsOneWidget);
    expect(find.byKey(const Key('purchase-reset-send-code')), findsOneWidget);
    expect(find.byKey(const Key('purchase-reset-new-password')), findsOneWidget);

    await tester.tap(find.byKey(const Key('purchase-reset-send-code')));
    await tester.pumpAndSettle();
    expect(api.sendResetCodeCalls, 1);

    await tester.enterText(
      find.byKey(const Key('purchase-reset-email-code')),
      '654321',
    );
    await tester.enterText(
      find.byKey(const Key('purchase-reset-new-password')),
      'newSecret999',
    );
    await tester.tap(find.byKey(const Key('purchase-reset-submit')));
    await tester.pumpAndSettle();

    expect(api.resetConfirmCalls, 1);
    expect(api.lastResetEmail, 'member@gmail.com');
    expect(api.lastResetCode, '654321');
    expect(api.lastResetPassword, 'newSecret999');

    // Switched cleanly back to Login mode with email kept & success notice shown.
    expect(find.byKey(const Key('purchase-login')), findsOneWidget);
    expect(find.byKey(const Key('purchase-reset-success-notice')), findsOneWidget);
    final loginEmailField = tester.widget<TextFormField>(
      find.byKey(const Key('purchase-email')),
    );
    expect(loginEmailField.controller!.text, 'member@gmail.com');
  });

  testWidgets(
      'SupportChatSheet: desktop side sheet without BackdropFilter, O(1) composer keystrokes, Enter sends vs Shift+Enter newline, failed retry, error backup WeChat, and zero active resources on close',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _FakeChatwootService();
    _FakeRealtime? activeRealtime;
    final supportManager = SupportManager(
      service: service,
      storage: _MemChatwootStorage(),
      realtimeConnector: (_, __) async {
        activeRealtime = _FakeRealtime();
        return activeRealtime!;
      },
      echoIdGenerator: () => 'echo-1',
    )..configureChannel(
        baseUrl: Uri.parse('https://chat.example.test'),
        websiteToken: 'cw-token-test',
      );
    addTearDown(supportManager.dispose);

    await tester.pumpWidget(
      _wrapTestApp(
        child: Builder(
          builder: (context) => Center(
            child: FilledButton(
              key: const Key('open-support-test'),
              onPressed: () => openSupportChatSheet(
                context,
                supportManager: supportManager,
                initialDraft: '咨询 200G 套餐',
                externalWidgetUri: Uri.parse(
                  'https://chat.example.test/widget?website_token=cw-token-test',
                ),
                openLink: (_) async {},
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-support-test')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('support-chat-sheet')), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(supportManager.hasActiveRealtimeResources, isTrue);

    // Pre-filled initialDraft is in composer.
    final composerField = tester.widget<TextField>(
      find.byKey(const Key('support-composer')),
    );
    expect(composerField.controller!.text, '咨询 200G 套餐');

    // Shift+Enter inserts newline without sending.
    await tester.tap(find.byKey(const Key('support-composer')));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(service.sentContents, isEmpty);

    // Bare Enter sends message; test failed -> retry flow too.
    service.failNextSend = true;
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('support-error-banner')), findsOneWidget);
    expect(find.byKey(const Key('support-backup-wechat-strip')), findsOneWidget);
    expect(find.text('微信号: ChasingDream_2021'), findsOneWidget);
    expect(find.text('微信号: dxm_qa'), findsOneWidget);

    // Tap per-message retry button -> succeeds cleanly.
    await tester.tap(find.byKey(const Key('support-retry-echo-1')));
    await tester.pumpAndSettle();
    expect(service.sentContents, ['咨询 200G 套餐']);
    expect(find.byKey(const Key('support-error-banner')), findsNothing);

    // Incoming agent typing event renders typing banner.
    activeRealtime!.controller.add(
      const ChatwootTypingEvent(isTyping: true, senderName: '小云'),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('support-typing-banner')), findsOneWidget);
    expect(find.text('小云 正在输入...'), findsOneWidget);

    // Closing sheet destroys WebSocket & all timers immediately.
    await tester.tap(find.byKey(const Key('support-close')));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(find.byKey(const Key('support-chat-sheet')), findsNothing);
    expect(supportManager.hasActiveRealtimeResources, isFalse);
    expect(activeRealtime!.closed, isTrue);
  });

  testWidgets(
      'Navigation rail support trigger opens SupportChatSheet and 4-locale 2.0x textScale on 320x800 has zero overflows',
      (tester) async {
    final service = _FakeChatwootService();
    final supportManager = SupportManager(
      service: service,
      storage: _MemChatwootStorage(),
      realtimeConnector: (_, __) async => _FakeRealtime(),
    )..configureChannel(
        baseUrl: Uri.parse('https://chat.example.test'),
        websiteToken: 'cw-token-test',
      );
    addTearDown(supportManager.dispose);

    // 4-locale 2.0x textScale stress test at 320x800 for SupportChatSheet & PurchaseCenter register/reset.
    final passportApi = _FakePassportApi(
      authConfig: const XboardGuestAuthConfig(
        isEmailVerify: true,
        isInviteForce: true,
        emailWhitelistSuffix: ['gmail.com', 'qq.com'],
      ),
    );
    final purchaseManager = PurchaseManager(
      api: passportApi,
      storage: _MemPurchaseStorage(),
      synchronize: (_, __) async {},
    );
    addTearDown(purchaseManager.dispose);
    await purchaseManager.initialize();
    await purchaseManager.loadPlans();
    await purchaseManager.ensurePurchaseChannels();

    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final locale in const [
      Locale('zh', 'CN'),
      Locale('en'),
      Locale('ja'),
      Locale('ru'),
    ]) {
      await AppLocalizations.load(locale);
      await tester.pumpWidget(
        _wrapTestApp(
          locale: locale,
          textScale: 2.0,
          child: PurchaseCenter(
            manager: purchaseManager,
            supportManager: supportManager,
            openLink: (_) async {},
            openProfiles: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'center-login-$locale');

      await tester.ensureVisible(
        find.byKey(const Key('purchase-auth-tab-register')),
      );
      await tester.tap(find.byKey(const Key('purchase-auth-tab-register')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'center-register-$locale');

      await tester.ensureVisible(
        find.byKey(const Key('purchase-auth-tab-login')),
      );
      await tester.tap(find.byKey(const Key('purchase-auth-tab-login')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('purchase-auth-forgot-trigger')),
      );
      await tester.tap(find.byKey(const Key('purchase-auth-forgot-trigger')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'center-forgot-$locale');

      // Mobile SupportChatSheet at 320x800 2.0x textScale.
      await tester.pumpWidget(
        _wrapTestApp(
          locale: locale,
          textScale: 2.0,
          child: SupportChatSheet(
            supportManager: supportManager,
            externalWidgetUri: Uri.parse(
              'https://chat.example.test/widget?website_token=cw-token-test',
            ),
            openLink: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'support-sheet-$locale');
      unawaited(supportManager.closePanel());
      await tester.pump();
    }

    // Desktop CommonNavigationBar includes navigation-support-trigger at bottom of trailing.
    await AppLocalizations.load(const Locale('zh', 'CN'));
    tester.view.physicalSize = const Size(1280, 900);
    final navFakeApi = _FakePassportApi(
      authConfig: const XboardGuestAuthConfig(),
    );
    final navSupportService = _FakeChatwootService();
    final navSupportManager = SupportManager(
      service: navSupportService,
      storage: _MemChatwootStorage(),
      realtimeConnector: (_, __) async => _FakeRealtime(),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          purchaseSupportCoordinatorProvider.overrideWith((ref) {
            final coordinator = PurchaseSupportCoordinator.test(
              ref,
              api: navFakeApi,
              storage: _MemPurchaseStorage(),
              supportManager: navSupportManager,
            );
            ref.onDispose(coordinator.dispose);
            return coordinator;
          }),
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
              final navItems = ref.watch(currentNavigationsStateProvider).value;
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
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('navigation-support-trigger')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('navigation-support-trigger')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('support-chat-sheet')), findsOneWidget);
    await tester.tap(find.byKey(const Key('support-close')));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(find.byKey(const Key('support-chat-sheet')), findsNothing);
    expect(navSupportManager.hasActiveRealtimeResources, isFalse);
    expect(tester.takeException(), isNull);
  });

  test('purchaseSupportCoordinatorProvider shares one instance across reads', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final first = container.read(purchaseSupportCoordinatorProvider);
    final second = container.read(purchaseSupportCoordinatorProvider);
    expect(identical(first, second), isTrue);
    expect(identical(first.purchaseManager, second.purchaseManager), isTrue);
    expect(identical(first.supportManager, second.supportManager), isTrue);
  });
}

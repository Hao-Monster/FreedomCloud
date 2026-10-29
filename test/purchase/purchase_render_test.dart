// Generates review artifacts from the real widget tree using synthetic data.
// Run with: flutter test --no-pub test/purchase/purchase_render_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/manager/purchase_manager.dart';
import 'package:flclashx/models/xboard.dart';
import 'package:flclashx/services/xboard_api.dart';
import 'package:flclashx/views/purchase/center.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _gift = GiftReward(
  purchaseSnapshot: GiftPurchaseSnapshot(
    planId: 3,
    planName: '标准套餐 · 200 GiB',
    period: 'monthly',
    transferEnable: 214748364800,
  ),
);

const _singleUsCatalog = XboardPlanCatalog(plans: [
  XboardPlanOffer(
    id: 10,
    name: 'ultra线路-美国',
    transferGiB: 200,
    speedLimit: 0,
    deviceLimit: 0,
    resetTrafficMethod: 2,
    capacityRemaining: null,
    hasSpeedLimit: true,
    hasDeviceLimit: true,
    hasResetTrafficMethod: true,
    hasCapacityRemaining: true,
    tags: ['IEPL专线', '流媒体解锁'],
    prices: [XboardPlanPrice(period: 'onetime', amount: 15000)],
    content: '''
## 套餐特点
- 美国原生高速专线，晚高峰低延迟稳定连接
- 一次性流量包，无到期时间限制
- 支持 Windows、macOS、iOS、Android 全平台

## 使用说明
1. 点击获取兑换码联系微信客服或打开自助商店
2. 右侧登录账户后粘贴兑换码查询权益
3. 核对权益无误后点击确认兑换并同步订阅
''',
  ),
]);

void main() {
  String? previewFont;
  setUpAll(() async {
    // Keep optional artifact generation portable. Windows review uses an actual
    // installed Chinese font instead of the widget-test Ahem placeholder font.
    final fontPath = Platform.environment['PURCHASE_PREVIEW_FONT'] ??
        'C:/Windows/Fonts/msyh.ttc';
    final file = File(fontPath);
    if (file.existsSync()) {
      final bytes = await file.readAsBytes();
      final loader = FontLoader('PurchasePreviewChinese')
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
      previewFont = 'PurchasePreviewChinese';
    }
    await (FontLoader('JetBrainsMono')
          ..addFont(rootBundle.load('assets/fonts/JetBrainsMono-Regular.ttf')))
        .load();
    await (FontLoader('Twemoji')
          ..addFont(rootBundle.load('assets/fonts/Twemoji.Mozilla.ttf')))
        .load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  testWidgets('render Chinese purchase states using synthetic accounts',
      (tester) async {
    final output = Directory('build/purchase-preview');
    await tester.runAsync(() => output.create(recursive: true));
    final flagshipGuest = _PreviewManager()
      ..account = null
      ..planCatalog = _singleUsCatalog;
    final preview = _PreviewManager()
      ..code = 'DEMO2026MONTH'
      ..preview = GiftPreview(
        codeId: 101,
        type: 4,
        name: '标准套餐月付兑换码',
        canRedeem: true,
        rewards: _gift,
        purchasePreview: GiftPurchasePreview(
          transferBefore: 214748364800,
          transferAfter: 214748364800,
          usedTraffic: 37580963840,
          expiresBefore: DateTime.utc(2026, 11, 4),
          expiresAfter: DateTime.utc(2026, 12, 4),
          renewal: true,
        ),
      );
    final success = _PreviewManager()
      ..receipt = const GiftReceipt(
        templateName: '标准套餐月付兑换码',
        rewards: _gift,
        orderTradeNo: 'DEMO-ORDER-20261004',
      )
      ..syncError = const XboardException(
        code: 'download_timeout',
        message: '订阅下载超时，请检查网络后重试同步。',
      )
      ..history = GiftHistoryPage(
        entries: [
          GiftHistoryEntry(
            id: 1,
            codeId: 101,
            maskedCode: 'DEMO2026****',
            templateName: '标准套餐月付兑换码',
            rewards: _gift,
            usedAt: DateTime.utc(2026, 10, 4, 12),
            orderTradeNo: 'DEMO-ORDER-20261004',
          ),
        ],
        page: 1,
        lastPage: 1,
        total: 1,
      );
    final scenarios = [
      ('flagship-us-single', const Size(1280, 920), flagshipGuest),
      ('login', const Size(1180, 960), _PreviewManager()..account = null),
      ('narrow-login', const Size(360, 960), _PreviewManager()..account = null),
      ('redemption-preview', const Size(1240, 1180), preview),
      ('success-sync-failed', const Size(1240, 1280), success),
      ('narrow-preview', const Size(360, 1500), preview),
    ];
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    for (final (name, size, manager) in scenarios) {
      final boundaryKey = GlobalKey();
      tester.view.physicalSize = size;
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        theme: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          fontFamily: previewFont,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF03A9F4),
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: const Color(0xFF0E1519),
        ),
        home: RepaintBoundary(
          key: boundaryKey,
          child: Scaffold(
            appBar: AppBar(title: const Text('合成数据 · UI 预览')),
            body: PurchaseCenter(
              key: ValueKey(name),
              manager: manager,
              openLink: (_) async {},
              openProfiles: () {},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: name);
      if (name == 'success-sync-failed') {
        await tester.ensureVisible(find.byKey(const Key('purchase-history-toggle')));
        await tester.tap(find.byKey(const Key('purchase-history-toggle')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$name-history');
      }
      for (final phase in ['', '-support']) {
        if (phase.isNotEmpty) {
          await tester.ensureVisible(find.text('微信号: dxm_qa'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$name$phase');
        }
        final boundary = boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          try {
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            expect(data, isNotNull);
            await File('${output.path}/$name$phase.png')
                .writeAsBytes(data!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }
    }
  });
}

class _PreviewAPI implements XboardApi {
  @override
  final Uri baseUri = Uri.parse('https://panel.example.test');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PreviewManager extends ChangeNotifier implements PurchaseManager {
  @override
  XboardPlanCatalog? planCatalog = const XboardPlanCatalog(plans: [
    XboardPlanOffer(
      id: 1,
      name: '标准套餐 · 日本/新加坡',
      transferGiB: 200,
      speedLimit: 300,
      deviceLimit: 5,
      capacityRemaining: 8,
      tags: ['BGP高速', '晚高峰稳定'],
      prices: [
        XboardPlanPrice(period: 'monthly', amount: 1500),
        XboardPlanPrice(period: 'yearly', amount: 15000),
      ],
    ),
    XboardPlanOffer(
      id: 2,
      name: '轻量流量包 · 美国',
      transferGiB: 50,
      tags: ['按量不限时'],
      prices: [XboardPlanPrice(period: 'onetime', amount: 3000)],
    ),
  ]);
  @override
  bool plansLoading = false;
  @override
  XboardException? plansError;
  @override
  Future<void> loadPlans() async {}

  @override
  final XboardApi api = _PreviewAPI();
  @override
  XboardAccount? account = const XboardAccount(
    id: 1,
    email: 'demo@example.test',
  );
  @override
  XboardSubscription? subscription = XboardSubscription(
    valid: true,
    url: Uri.parse('https://panel.example.test/subscribe?token=SYNTHETIC'),
    planId: 3,
    planName: '标准套餐 · 200 GiB',
    upload: 5368709120,
    download: 32212254720,
    total: 214748364800,
    expiresAt: DateTime.utc(2026, 11, 4),
  );
  @override
  GiftPreview? preview;
  @override
  GiftReceipt? receipt;
  @override
  GiftHistoryPage? history;
  @override
  XboardException? error;
  @override
  XboardException? historyError;
  @override
  XboardException? syncError;
  @override
  XboardException? channelError;
  @override
  Uri? cardStoreUrl = Uri.parse('https://shop.example.test/cards');
  @override
  bool restoring = false;
  @override
  bool busy = false;
  @override
  bool get checkingCode => false;
  @override
  bool get redeemingCode => false;
  @override
  bool syncing = false;
  @override
  bool subscriptionSynced = false;
  @override
  bool unresolvedRedemption = false;
  @override
  String code = '';

  @override
  bool get loggedIn => account != null;
  @override
  bool get canRedeem => preview?.canRedeem ?? false;
  @override
  bool get canSync => loggedIn;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

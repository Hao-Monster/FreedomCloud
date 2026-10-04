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
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  testWidgets('render Chinese purchase states using synthetic accounts',
      (tester) async {
    final output = Directory('build/purchase-preview');
    await tester.runAsync(() => output.create(recursive: true));
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
      ('login', const Size(1000, 960), _PreviewManager()..account = null),
      ('redemption-preview', const Size(1100, 1440), preview),
      ('success-sync-failed', const Size(1100, 1500), success),
      ('narrow-preview', const Size(320, 1800), preview),
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
      final boundary = boundaryKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          expect(data, isNotNull);
          await File('${output.path}/$name.png')
              .writeAsBytes(data!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
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

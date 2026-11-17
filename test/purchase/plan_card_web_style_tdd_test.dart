import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/models/xboard.dart';
import 'package:flclashx/views/purchase/plan_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _boilerplateContent = '''
## 核心权益
- 设备数量：无限
- 使用时间：无限
- 流量用完为止
- 支持所有类型设备（iOS / Android / Windows / macOS / Linux）
''';

const _fourTierCatalog = XboardPlanCatalog(
  plans: [
    XboardPlanOffer(
      id: 101,
      name: '50G 永久流量包',
      transferGiB: 50,
      speedLimit: 0,
      deviceLimit: 0,
      resetTrafficMethod: 2,
      tags: ['轻量入门', '永久流量包'],
      prices: [XboardPlanPrice(period: 'onetime', amount: 3800)],
      content: _boilerplateContent,
    ),
    XboardPlanOffer(
      id: 102,
      name: '100G 永久流量包',
      transferGiB: 100,
      speedLimit: 0,
      deviceLimit: 0,
      resetTrafficMethod: 2,
      tags: ['日常常备', '永久流量包'],
      prices: [XboardPlanPrice(period: 'onetime', amount: 7500)],
      content: _boilerplateContent,
    ),
    XboardPlanOffer(
      id: 103,
      name: '200G 永久流量包',
      transferGiB: 200,
      speedLimit: 0,
      deviceLimit: 0,
      resetTrafficMethod: 2,
      tags: ['主力推荐', '永久流量包'],
      prices: [XboardPlanPrice(period: 'onetime', amount: 15000)],
      content: _boilerplateContent,
    ),
    XboardPlanOffer(
      id: 104,
      name: '500G 永久流量包',
      transferGiB: 500,
      speedLimit: 0,
      deviceLimit: 0,
      resetTrafficMethod: 2,
      tags: ['超值囤货', '永久流量包'],
      prices: [XboardPlanPrice(period: 'onetime', amount: 27000)],
      content: _boilerplateContent,
    ),
  ],
);

Future<void> _pumpCatalog(
  WidgetTester tester, {
  required XboardPlanCatalog catalog,
  Size size = const Size(1280, 900),
  Brightness brightness = Brightness.dark,
  Locale locale = const Locale('zh', 'CN'),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.delegate.supportedLocales,
      theme: ThemeData(
        useMaterial3: true,
        brightness: brightness,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF66BB6A),
          brightness: brightness,
        ),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: PurchasePlanCatalog(
            key: ValueKey('$brightness-$size-$locale-$textScale'),
            catalog: catalog,
            loading: false,
            failed: false,
            retry: () {},
            openLink: (_) async {},
            onBuyPlan: (_) {},
            onAcquirePlan: (_) {},
            collapsibleDetails: true,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'W01: standard storefront tiers render sleek web-style cards without redundant title, boilerplate markdown, or noisy spec pills',
      (tester) async {
    await _pumpCatalog(
      tester,
      catalog: _fourTierCatalog,
      size: const Size(1280, 900),
      brightness: Brightness.dark,
    );

    // Redundant titles, generic second tag pills, old _SpecPill labels, and boilerplate Markdown are omitted.
    expect(find.text('50G 永久流量包'), findsNothing);
    expect(find.text('100G 永久流量包'), findsNothing);
    expect(find.text('200G 永久流量包'), findsNothing);
    expect(find.text('500G 永久流量包'), findsNothing);
    expect(find.text('永久流量包'), findsNothing);
    expect(find.text('速率上限: 不限'), findsNothing);
    expect(find.text('剩余销售名额: 不限'), findsNothing);
    expect(find.text('套餐说明'), findsNothing);
    expect(find.text('核心权益', findRichText: true), findsNothing);

    // Single primary tier badges (including featured 200G badge key) & unit-price hints.
    expect(find.text('轻量入门'), findsOneWidget);
    expect(find.text('日常常备'), findsOneWidget);
    expect(find.byKey(const Key('purchase-plan-featured-103')), findsOneWidget);
    expect(find.text('主力推荐'), findsOneWidget);
    expect(find.text('超值囤货'), findsOneWidget);
    expect(find.text('约 0.76 / G'), findsOneWidget);
    expect(find.text('约 0.75 / G'), findsNWidgets(2)); // 7500/100 and 15000/200
    expect(find.text('约 0.54 / G'), findsOneWidget);

    // Hero quota & listed price.
    for (final quota in ['50G', '100G', '200G', '500G']) {
      expect(find.text(quota), findsOneWidget);
    }
    for (final price in ['38.00', '75.00', '150.00', '270.00']) {
      expect(find.text(price), findsOneWidget);
    }

    // Concise 4-item emerald checkmark benefit list on all 4 cards.
    expect(find.text('设备数量：无限'), findsNWidgets(4));
    expect(find.text('使用时间：无限'), findsNWidgets(4));
    expect(find.text('流量用完为止'), findsNWidgets(4));
    expect(find.text('支持所有类型设备'), findsNWidgets(4));

    // Full-width vertically stacked CTAs even on desktop width.
    final buyRect = tester.getRect(find.byKey(const Key('purchase-plan-buy-101')));
    final acquireRect =
        tester.getRect(find.byKey(const Key('purchase-plan-acquire-101')));
    expect(find.text('去购买'), findsNWidgets(4));
    expect(find.text('获取兑换码'), findsNWidgets(4));
    expect(buyRect.bottom, lessThan(acquireRect.top));
    expect((buyRect.width - acquireRect.width).abs(), lessThan(1.0));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'W02: side-by-side cards in a row share equal height and aligned bottom CTAs even when one has custom markdown',
      (tester) async {
    const asymmetricCatalog = XboardPlanCatalog(
      plans: [
        XboardPlanOffer(
          id: 201,
          name: '50G 永久流量包',
          transferGiB: 50,
          hasDeviceLimit: true,
          deviceLimit: 0,
          resetTrafficMethod: 2,
          tags: ['轻量入门'],
          prices: [XboardPlanPrice(period: 'onetime', amount: 3800)],
          content: _boilerplateContent,
        ),
        XboardPlanOffer(
          id: 202,
          name: '200G 旗舰专线',
          transferGiB: 200,
          hasDeviceLimit: true,
          deviceLimit: 0,
          resetTrafficMethod: 2,
          tags: ['主力推荐'],
          prices: [XboardPlanPrice(period: 'onetime', amount: 15000)],
          content: '## 补充说明\n- 解锁流媒体与 AI 工具\n- 附带专属售后支持',
        ),
      ],
    );

    await _pumpCatalog(
      tester,
      catalog: asymmetricCatalog,
      size: const Size(1280, 900),
      brightness: Brightness.dark,
    );

    final firstCard = tester.getRect(find.byKey(const Key('purchase-plan-201')));
    final secondCard = tester.getRect(find.byKey(const Key('purchase-plan-202')));
    expect(firstCard.top, secondCard.top);
    expect((firstCard.bottom - secondCard.bottom).abs(), lessThan(0.5));
    expect((firstCard.height - secondCard.height).abs(), lessThan(0.5));

    final firstAcquire =
        tester.getRect(find.byKey(const Key('purchase-plan-acquire-201')));
    final secondAcquire =
        tester.getRect(find.byKey(const Key('purchase-plan-acquire-202')));
    expect((firstAcquire.bottom - secondAcquire.bottom).abs(), lessThan(0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'W03: custom plan names, region flags, progressive Markdown details, light/dark themes, and 320px 2x text render without overflow',
      (tester) async {
    const richCatalog = XboardPlanCatalog(
      plans: [
        XboardPlanOffer(
          id: 301,
          name: 'ultra线路-美国',
          transferGiB: 200,
          hasDeviceLimit: true,
          deviceLimit: 0,
          resetTrafficMethod: 2,
          tags: ['主力推荐'],
          prices: [XboardPlanPrice(period: 'onetime', amount: 15000)],
          content: '## 线路说明\n'
              '- 第一条自定义说明\n'
              '- 第二条自定义说明\n'
              '- 第三条自定义说明\n'
              '- 第四条自定义说明\n'
              '- 第五条自定义说明\n'
              '- 第六条隐藏说明\n'
              '- 第七条隐藏说明\n',
        ),
        XboardPlanOffer(
          id: 302,
          name: 'Free Starter',
          transferGiB: 2,
          hasDeviceLimit: true,
          deviceLimit: 0,
          resetTrafficMethod: 2,
          prices: [XboardPlanPrice(period: 'onetime', amount: 0)],
        ),
      ],
    );

    for (final (brightness, size, scale) in [
      (Brightness.light, const Size(1280, 900), 1.0),
      (Brightness.dark, const Size(320, 800), 2.0),
    ]) {
      await _pumpCatalog(
        tester,
        catalog: richCatalog,
        brightness: brightness,
        size: size,
        textScale: scale,
      );
      expect(find.text('ultra线路-美国'), findsOneWidget);
      expect(find.byKey(const Key('purchase-plan-flag-301')), findsOneWidget);
      expect(find.byKey(const Key('purchase-plan-details-toggle-301')),
          findsOneWidget);
      expect(find.text('第六条隐藏说明', findRichText: true), findsNothing);
      await tester
          .ensureVisible(find.byKey(const Key('purchase-plan-details-toggle-301')));
      await tester.tap(find.byKey(const Key('purchase-plan-details-toggle-301')));
      await tester.pumpAndSettle();
      expect(find.text('第六条隐藏说明', findRichText: true), findsOneWidget);
      expect(find.text('Free Starter'), findsOneWidget);
      expect(find.text('免费体验'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}

// Offline screenshots of the actual catalogue widget, using synthetic plans.
// No application startup, account access, proxy service, or remote API calls.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/models/xboard.dart';
import 'package:flclashx/views/purchase/plan_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _plans = [
  XboardPlanOffer(
    id: 1,
    name: '示例流量包',
    transferGiB: 200,
    hasSpeedLimit: true,
    hasDeviceLimit: true,
    hasCapacityRemaining: true,
    resetTrafficMethod: 2,
    tags: ['按流量计费', '多设备支持'],
    prices: [XboardPlanPrice(period: 'onetime', amount: 15000)],
    content: '''
## 套餐特点
- 一次性流量包，无时间限制
- 支持 iOS、Android、Windows、macOS
- 已使用流量不会自动重置

## 使用说明
1. 通过下方微信确认币种并获取礼品卡。
2. 在客户端兑换，随后同步订阅。

**请保管好兑换码**，<u>勿向他人泄露</u>。

## 注意事项
- 遵守当地法律法规
- 套餐权益以实际配置为准
''',
  ),
  XboardPlanOffer(
    id: 2,
    name: '示例周期套餐',
    transferGiB: 500,
    speedLimit: 300,
    deviceLimit: 5,
    capacityRemaining: 12,
    resetTrafficMethod: 0,
    resetTrafficPrice: 1200,
    tags: ['周期套餐', '这是一个用于检查换行的较长套餐标签'],
    prices: [
      XboardPlanPrice(period: 'monthly', amount: 3000),
      XboardPlanPrice(period: 'quarterly', amount: 8500),
      XboardPlanPrice(period: 'half_yearly', amount: 16000),
      XboardPlanPrice(period: 'yearly', amount: 30000),
      XboardPlanPrice(period: 'two_yearly', amount: 56000),
      XboardPlanPrice(period: 'three_yearly', amount: 80000),
      XboardPlanPrice(period: 'onetime', amount: 32000),
    ],
    content: '''
## 套餐说明
价格周期和流量重置规则分别列出，**不互相推断**。

| 项目 | 说明 |
| --- | --- |
| 销售名额 | 指套餐剩余销售数量 |
| 流量重置标价 | 仅展示，不在此执行重置 |

[查看 **使用说明** 与 *设备支持*](https://example.test/help)

<u># 此处是字面说明，不是标题</u>

[~~旧版说明~~ 与 `client.yaml`](https://example.test/config)
''',
  ),
];

void main() {
  String? fontFamily;
  setUpAll(() async {
    final font = File(Platform.environment['PURCHASE_PREVIEW_FONT'] ??
        'C:/Windows/Fonts/msyh.ttc');
    if (font.existsSync()) {
      final loader = FontLoader('CatalogPreviewChinese')
        ..addFont(Future.value(ByteData.sublistView(await font.readAsBytes())));
      await loader.load();
      fontFamily = 'CatalogPreviewChinese';
    }
    // Widget tests otherwise render an unregistered monospace face with Ahem.
    final mono = File('C:/Windows/Fonts/consola.ttf');
    if (mono.existsSync()) {
      await (FontLoader('monospace')
            ..addFont(
                Future.value(ByteData.sublistView(await mono.readAsBytes()))))
          .load();
    }
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });

  testWidgets('render catalogue completeness without starting the application',
      (tester) async {
    final output = Directory('build/plan-card-rich-content-preview');
    await tester.runAsync(() => output.create(recursive: true));
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    for (final (name, size, brightness, scale, plans) in [
      ('light', const Size(1000, 1300), Brightness.light, 1.0, _plans),
      ('dark', const Size(1000, 1300), Brightness.dark, 1.0, _plans),
      ('narrow', const Size(360, 1200), Brightness.light, 1.0, [_plans.first]),
      (
        'large-text',
        const Size(320, 2600),
        Brightness.dark,
        2.0,
        [_plans.first]
      ),
    ]) {
      tester.view.physicalSize = size;
      final boundaryKey = GlobalKey();
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
          useMaterial3: true,
          fontFamily: fontFamily,
          colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF03A9F4), brightness: brightness),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: RepaintBoundary(
          key: boundaryKey,
          child: Scaffold(
            appBar: AppBar(title: const Text('套餐展示 · 合成数据预览')),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: PurchasePlanCatalog(
                key: ValueKey(name),
                catalog: XboardPlanCatalog(plans: plans),
                loading: false,
                failed: false,
                retry: () {},
                openLink: (_) async {},
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: name);
      expect(find.text('示例流量包'), findsOneWidget);
      expect(find.text('流量重置: 不自动重置'), findsOneWidget);
      expect(find.text('套餐权益以实际配置为准', findRichText: true), findsOneWidget);
      final boundary = boundaryKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          expect(data, isNotNull);
          await File('${output.path}/catalog-$name.png')
              .writeAsBytes(data!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    }
  });
}

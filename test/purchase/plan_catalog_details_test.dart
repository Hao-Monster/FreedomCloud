import 'dart:io';

import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/models/xboard.dart';
import 'package:flclashx/views/purchase/plan_catalog.dart';
import 'package:flclashx/views/purchase/plan_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

Future<void> _pump(WidgetTester tester, Widget child,
    {Locale locale = const Locale('en'),
    Brightness brightness = Brightness.light,
    double width = 800,
    double scale = 1}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1000);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.delegate.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: ThemeData(brightness: brightness, useMaterial3: true),
    builder: (context, child) => MediaQuery(
      data:
          MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: child,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Widget _catalog(XboardPlanOffer plan) => PurchasePlanCatalog(
      catalog: XboardPlanCatalog(plans: [plan]),
      loading: false,
      failed: false,
      retry: () {},
    );

XboardPlanOffer _plan({
  int? speed,
  int? devices,
  int? reset,
  int? slots,
  bool? hasSpeed,
  bool? hasDevices,
  bool? hasReset,
  bool? hasSlots,
  int? resetPrice,
  String content = '',
  List<String> tags = const [],
}) =>
    XboardPlanOffer(
      id: 1,
      name: 'Public plan',
      transferGiB: 200,
      prices: const [XboardPlanPrice(period: 'onetime', amount: 15000)],
      content: content,
      tags: tags,
      speedLimit: speed,
      deviceLimit: devices,
      resetTrafficMethod: reset,
      capacityRemaining: slots,
      hasSpeedLimit: hasSpeed,
      hasDeviceLimit: hasDevices,
      hasResetTrafficMethod: hasReset,
      hasCapacityRemaining: hasSlots,
      resetTrafficPrice: resetPrice,
    );

Iterable<TextSpan> _spans(InlineSpan span) sync* {
  if (span is TextSpan) {
    yield span;
    for (final child in span.children ?? <InlineSpan>[]) {
      yield* _spans(child);
    }
  }
}

Iterable<TextSpan> _textSpans(WidgetTester tester, String text) => tester
    .widgetList<RichText>(find.byType(RichText))
    .expand((widget) => _spans(widget.text))
    .where((span) => span.text?.contains(text) ?? false);

class _NoResourceRequests extends HttpOverrides {
  int requests = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    requests++;
    throw StateError('Plan descriptions must not load remote resources');
  }
}

void main() {
  testWidgets('missing metadata stays unknown rather than unlimited',
      (tester) async {
    await _pump(tester, _catalog(_plan()));
    for (final label in [
      'Speed limit',
      'Device limit',
      'Traffic reset',
      'Remaining sales slots',
    ]) {
      expect(find.text('$label: Not provided'), findsOneWidget);
    }
    expect(find.textContaining('Unlimited'), findsNothing);
    expect(find.text('Plan details'), findsNothing);
    expect(find.text('Traffic reset · listed price'), findsNothing);
  });

  testWidgets(
      'explicit null limits and capacity are unlimited, reset inherited',
      (tester) async {
    await _pump(
        tester,
        _catalog(_plan(
          hasSpeed: true,
          hasDevices: true,
          hasReset: true,
          hasSlots: true,
        )));
    expect(find.text('Speed limit: Unlimited'), findsOneWidget);
    expect(find.text('Device limit: Unlimited'), findsOneWidget);
    expect(find.text('Remaining sales slots: Unlimited'), findsOneWidget);
    expect(find.text('Traffic reset: Follows system settings'), findsOneWidget);
  });

  testWidgets('zero limits are unlimited but zero sales slots stay zero',
      (tester) async {
    await _pump(tester, _catalog(_plan(speed: 0, devices: 0, slots: 0)));
    expect(find.text('Speed limit: Unlimited'), findsOneWidget);
    expect(find.text('Device limit: Unlimited'), findsOneWidget);
    expect(find.text('Remaining sales slots: 0'), findsOneWidget);
    expect(find.textContaining('0 GiB'), findsOneWidget);
  });

  testWidgets('positive limits and server tags are retained without new claims',
      (tester) async {
    await _pump(
        tester,
        _catalog(_plan(
          speed: 300,
          devices: 5,
          slots: 12,
          tags: ['多设备', '<b>原始标签</b>', '重复', '重复', ''],
        )));
    expect(find.text('Speed limit: 300 Mbps'), findsOneWidget);
    expect(find.text('Device limit: 5'), findsOneWidget);
    expect(find.text('Remaining sales slots: 12'), findsOneWidget);
    expect(find.text('多设备'), findsOneWidget);
    expect(find.text('<b>原始标签</b>'), findsOneWidget);
    expect(find.text('重复'), findsNWidgets(2));
    expect(find.text('Recommended'), findsNothing);
  });

  for (final (code, label) in [
    (0, 'On the 1st of each month'),
    (1, 'Monthly on the expiry day'),
    (2, 'Does not reset automatically'),
    (3, 'On January 1 each year'),
    (4, 'Yearly on the expiry month and day'),
    (99, 'Unknown rule (99)'),
    (-1, 'Unknown rule (-1)'),
  ]) {
    testWidgets('renders traffic reset code $code explicitly', (tester) async {
      await _pump(tester, _catalog(_plan(reset: code)));
      expect(find.text('Traffic reset: $label'), findsOneWidget);
    });
  }

  for (final (amount, label) in [
    (0, '0.00'),
    (1, '0.01'),
    (9000000000000000, '90000000000000.00'),
  ]) {
    testWidgets('reset price $amount remains separate and informational',
        (tester) async {
      await _pump(tester, _catalog(_plan(resetPrice: amount)));
      expect(find.text('Traffic based'), findsOneWidget);
      expect(find.text('150.00'), findsOneWidget);
      expect(find.text('Traffic reset · listed price'), findsOneWidget);
      expect(find.text(label), findsOneWidget);
      expect(find.byType(ButtonStyleButton), findsNothing);
    });
  }

  testWidgets('Markdown renders structure and emphasis, not literal markup',
      (tester) async {
    await _pump(tester, const PurchasePlanContent(data: '''
## 套餐特点
这是 **加粗权益**、*强调说明* 和 ~~删除内容~~。

- 第一项
- 第二项

1. 使用步骤
2. 完成步骤

| 项目 | 说明 |
| --- | --- |
| 流量 | 200 GiB |

<u>下划线与 **嵌套粗体**</u>
'''));
    expect(find.text('套餐特点', findRichText: true), findsOneWidget);
    expect(find.text('第一项', findRichText: true), findsOneWidget);
    expect(find.text('使用步骤', findRichText: true), findsOneWidget);
    expect(find.byType(Table), findsOneWidget);
    expect(find.text('200 GiB', findRichText: true), findsOneWidget);
    expect(
        _textSpans(tester, '加粗权益')
            .any((span) => span.style?.fontWeight == FontWeight.bold),
        isTrue);
    expect(
        _textSpans(tester, '强调说明')
            .any((span) => span.style?.fontStyle == FontStyle.italic),
        isTrue);
    expect(
        _textSpans(tester, '删除内容').any((span) =>
            span.style?.decoration?.contains(TextDecoration.lineThrough) ??
            false),
        isTrue);
    expect(
        _textSpans(tester, '嵌套粗体').any((span) =>
            span.style?.fontWeight == FontWeight.bold &&
            (span.style?.decoration?.contains(TextDecoration.underline) ??
                false)),
        isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('only exact attribute-free underline is interpreted',
      (tester) async {
    await _pump(
        tester,
        const PurchasePlanContent(
            data: '<u onclick="evil()">属性内容</u>\n\n'
                '`<u>代码原文</u>`\n\n'
                '<script>alert("never run")</script>\n\n'
                '<iframe src="https://external.example"></iframe>'));
    expect(find.textContaining('<u onclick="evil()">', findRichText: true),
        findsOneWidget);
    expect(find.text('<u>代码原文</u>', findRichText: true), findsOneWidget);
    expect(find.textContaining('<script>', findRichText: true), findsOneWidget);
    expect(find.byType(ButtonStyleButton), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('HTTPS links require explicit clicks and support keyboard',
      (tester) async {
    final opened = <Uri>[];
    await _pump(
        tester,
        PurchasePlanContent(
          data: '[使用说明](https://support.example/help?a=1)',
          openLink: (uri) async => opened.add(uri),
        ));
    expect(opened, isEmpty);
    await tester.tap(find.text('使用说明'));
    expect(opened, [Uri.parse('https://support.example/help?a=1')]);
    opened.clear();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(opened, [Uri.parse('https://support.example/help?a=1')]);
  });

  testWidgets('unsafe and relative links stay readable without actions',
      (tester) async {
    final opened = <Uri>[];
    const targets = [
      'javascript:alert%281%29',
      'data:text/html,evil',
      'file:///tmp/local',
      'http://plain.example/help',
      '/relative',
      '//relative.example',
      'https://user:pass@support.example',
      'https:missing-host',
    ];
    await _pump(
        tester,
        PurchasePlanContent(
          data: [
            for (var i = 0; i < targets.length; i++)
              '[Blocked$i](${targets[i]})'
          ].join('\n\n'),
          openLink: (uri) async => opened.add(uri),
        ));
    for (var i = 0; i < targets.length; i++) {
      expect(find.text('Blocked$i'), findsOneWidget);
      await tester.tap(find.text('Blocked$i'));
    }
    expect(find.byType(TextButton), findsNothing);
    expect(opened, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all image origins and malformed image URLs use alt placeholders',
      (tester) async {
    final network = _NoResourceRequests();
    await HttpOverrides.runZoned(() async {
      await _pump(tester, const PurchasePlanContent(data: '''
![远程图片](https://image.example/track.png)
![本地图片](file:///C:/private.png)
![内嵌图片](data:image/png;base64,AAAA)
![坏地址](https://[invalid)
'''));
      for (final alt in ['远程图片', '本地图片', '内嵌图片', '坏地址']) {
        expect(find.text('External image not loaded · $alt'), findsOneWidget);
      }
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    }, createHttpClient: network.createHttpClient);
    expect(network.requests, 0);
  });

  testWidgets(
      'linked images retain alt text and compound underline stays readable',
      (tester) async {
    final opened = <Uri>[];
    await _pump(tester, PurchasePlanContent(data: '''
[![客服二维码](https://img.example/a.png)](https://support.example)

[查看 ![说明图](https://img.example/b.png) 文档](https://support.example/docs)

[<u>**高速线路**</u>](https://support.example/plan)
''', openLink: (uri) async => opened.add(uri)));
    expect(find.text('External image not loaded · 客服二维码'), findsOneWidget);
    expect(find.text('查看 External image not loaded · 说明图 文档'), findsOneWidget);
    expect(find.text('高速线路'), findsOneWidget);
    expect(find.textContaining('**高速线路**'), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(opened, isEmpty);
    await tester.tap(find.text('External image not loaded · 客服二维码'));
    await tester.tap(find.text('高速线路'));
    expect(opened, [
      Uri.parse('https://support.example'),
      Uri.parse('https://support.example/plan')
    ]);
  });

  testWidgets('unclosed underline has a bounded scan and retains all text',
      (tester) async {
    await _pump(tester, const PurchasePlanContent(data: 'Seed'));
    final syntax =
        tester.widget<MarkdownBody>(find.byType(MarkdownBody)).inlineSyntaxes;
    final document = md.Document(inlineSyntaxes: syntax, encodeHtml: false);
    final source = 'prefix ${List.filled(50000, '<u>').join()}';
    final clock = Stopwatch()..start();
    final nodes = md.InlineParser(source, document).parse();
    clock.stop();
    expect(nodes.map((node) => node.textContent).join(), source);
    expect(clock.elapsed, lessThan(const Duration(seconds: 5)));
    // Reusing the syntax must not carry an unmatched tail into another block.
    final next = md.InlineParser('<u>**有效内容**</u>', document).parse();
    expect(next.single, isA<md.Element>());
    final underline = next.single as md.Element;
    expect(underline.tag, 'u');
    expect(underline.textContent, '有效内容');
    expect((underline.children!.single as md.Element).tag, 'strong');
  });

  testWidgets(
      '320px and 2x text retain long tags, content and scrollable tables',
      (tester) async {
    final longTag = List.filled(12, '完整套餐说明').join();
    final longWord = List.filled(120, 'A').join();
    await _pump(
        tester,
        _catalog(_plan(
          content: '## 完整说明\n\n$longWord\n\n'
              '| 项目 | 使用说明 | 第三列 |\n| --- | --- | --- |\n'
              '| 流量 | 横向滚动可读 | 完整内容 |\n\n'
              '1. 第一步\n2. 第二步\n\n最后一段仍然可读',
          tags: [longTag, for (var i = 0; i < 19; i++) '标签$i'],
          reset: 4,
          resetPrice: 9000000000000000,
        )),
        width: 320,
        scale: 2);
    expect(find.text(longTag), findsOneWidget);
    expect(find.text(longWord, findRichText: true), findsOneWidget);
    expect(find.text('90000000000000.00'), findsOneWidget);
    final horizontal = tester
        .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .where((scroll) => scroll.scrollDirection == Axis.horizontal);
    expect(horizontal, hasLength(1));
    for (final label in ['1.', '2.']) {
      final marker = find.descendant(
          of: find.text(label), matching: find.byType(RichText));
      final paragraph = tester.renderObject<RenderParagraph>(marker);
      expect(
          paragraph.getBoxesForSelection(
              const TextSelection(baseOffset: 0, extentOffset: 2)),
          hasLength(1),
          reason: 'The number and period must stay on the same line at 2x');
    }
    await tester.ensureVisible(find.text('最后一段仍然可读', findRichText: true));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final (locale, details, reset) in [
    (
      const Locale('en'),
      'Plan details',
      'Traffic reset: Does not reset automatically'
    ),
    (const Locale('zh', 'CN'), '套餐说明', '流量重置: 不自动重置'),
    (const Locale('ja'), 'プランの詳細', '通信量のリセット: 自動リセットなし'),
    (
      const Locale('ru'),
      'Описание тарифа',
      'Сброс трафика: Без автоматического сброса'
    ),
  ]) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets('catalogue is localized in $locale $brightness',
          (tester) async {
        await _pump(
            tester,
            _catalog(
                _plan(reset: 2, content: '## Details\n\nPublic description.')),
            locale: locale,
            brightness: brightness,
            width: 320,
            scale: 2);
        expect(find.text(details), findsOneWidget);
        expect(find.text(reset), findsOneWidget);
        expect(find.text('Public description.', findRichText: true),
            findsOneWidget);
        expect(find.textContaining('purchasePlan'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}

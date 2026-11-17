import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/theme.dart';
import 'package:flclashx/controller.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/views/dashboard/dashboard.dart';
import 'package:flclashx/widgets/scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _DashboardRenderController implements AppController {
  @override
  void changeMode(Mode mode) {}

  @override
  Future<void> updateStatus(bool isStart) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Optional synthetic render evidence for Dashboard cards.
/// Set DASHBOARD_RENDER_DIR to a private output directory (and optionally
/// DASHBOARD_RENDER_FONT to C:\Windows\Fonts\msyh.ttc) and run this file.
void main() {
  final output = Platform.environment['DASHBOARD_RENDER_DIR'];
  if (output == null || output.isEmpty) return;

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final fontPath = Platform.environment['DASHBOARD_RENDER_FONT'];
    final font = FontLoader('DashboardRender')
      ..addFont(
        fontPath == null
            ? rootBundle.load('assets/fonts/Unbounded-Regular.ttf')
            : File(fontPath).readAsBytes().then(ByteData.sublistView),
      );
    await font.load();

    final emojiFont = FontLoader(FontFamily.twEmoji.value)
      ..addFont(rootBundle.load('assets/fonts/Twemoji.Mozilla.ttf'));
    await emojiFont.load();

    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  Future<void> capturePng(WidgetTester tester, Key key, String fileName) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(key),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.5);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final dir = await Directory(output).create(recursive: true);
        await File('${dir.path}/$fileName').writeAsBytes(
          bytes!.buffer.asUint8List(),
          flush: true,
        );
      } finally {
        image.dispose();
      }
    });
  }

  testWidgets('render dashboard 480x920 dark zh_CN (admin unlimited + announce)',
      (tester) async {
    const size = Size(480, 920);
    await AppLocalizations.load(const Locale('zh', 'CN'));
    globalState.appController = _DashboardRenderController();

    final traffics = FixedList<Traffic>(30);
    const wave = <int>[
      0,
      0,
      420,
      9800,
      28400,
      6400,
      320,
      200,
      680,
      220,
      890,
      260,
      310,
      920,
      280,
      240,
      760,
      300,
      2551,
    ];
    for (final s in wave) {
      traffics.add(Traffic(up: 288, down: s));
    }

    globalState.config = Config(
      themeProps: defaultThemeProps,
      profiles: [
        Profile(
          id: 'admin',
          label: 'admin',
          url: 'https://example.com/sub/admin',
          lastUpdateDate: DateTime(2026, 11, 1, 0, 42),
          autoUpdateDuration: const Duration(hours: 24),
          overrideData: const OverrideData(
            enable: true,
            rule: OverrideRule(
              addedRules: [
                Rule(id: 'r1', value: 'DOMAIN-SUFFIX,openai.com,Proxy'),
                Rule(id: 'r2', value: 'DOMAIN-SUFFIX,claude.ai,Proxy'),
              ],
            ),
          ),
          subscriptionInfo: const SubscriptionInfo(
            upload: 181843394,
            download: 33093222000,
            total: 0,
            expire: 0,
          ),
          providerHeaders: {
            'announce':
                'base64:${base64.encode(utf8.encode('高速专线已完成晚高峰扩容，推荐优先选择 IEPL 低延迟节点 https://status.example.com'))}',
            'flclashx-servicename': base64.encode(utf8.encode('星云旗舰专线')),
            'support-url': 'https://support.example.com',
          },
        ),
      ],
      currentProfileId: 'admin',
    );
    globalState.appState = AppState(
      pageLabel: PageLabel.dashboard,
      viewSize: size,
      isInit: true,
      version: 1,
      requests: FixedList(5),
      logs: FixedList(5),
      traffics: traffics,
      totalTraffic: Traffic(up: 181843394, down: 33093222),
      groups: const [
        Group(
          name: 'Proxy',
          type: GroupType.Selector,
          now: '🇭🇰 香港 IEPL 01',
          all: [
            Proxy(name: '🇭🇰 香港 IEPL 01', type: 'Shadowsocks'),
            Proxy(name: '🇸🇬 新加坡 BGP 02', type: 'Trojan'),
            Proxy(name: '🇯🇵 东京专线 03', type: 'VLESS'),
          ],
        ),
      ],
      delayMap: const {
        defaultTestUrl: {'🇭🇰 香港 IEPL 01': 28},
      },
    );

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final baseDark = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorSchemeSeed: const Color(0xFF4FC3F7),
      fontFamily: 'DashboardRender',
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: baseDark,
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.delegate.supportedLocales,
          home: RepaintBoundary(
            key: const ValueKey('dashboard-dark-admin'),
            child: Builder(
              builder: (context) {
                globalState.measure = Measure.of(context, 1.0);
                globalState.theme = CommonTheme.of(context, 1.0);
                return const CommonScaffold(
                  title: '仪表盘',
                  body: DashboardView(),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await capturePng(
      tester,
      const ValueKey('dashboard-dark-admin'),
      'dashboard-480x920-dark-admin.png',
    );
  });

  testWidgets('render dashboard 520x960 light zh_CN (capped quota + warnings)',
      (tester) async {
    const size = Size(520, 960);
    await AppLocalizations.load(const Locale('zh', 'CN'));
    globalState.appController = _DashboardRenderController();

    final traffics = FixedList<Traffic>(30);
    for (final s in const <int>[120, 650, 4200, 18500, 9200, 14500, 6800, 11200]) {
      traffics.add(Traffic(up: 1024, down: s));
    }
    final expireEpoch =
        DateTime(2026, 11, 28, 18, 0).millisecondsSinceEpoch ~/ 1000;

    globalState.config = Config(
      themeProps: defaultThemeProps,
      profiles: [
        Profile(
          id: 'pro',
          label: '旗舰企业订阅 Pro',
          url: 'https://example.com/sub/pro',
          lastUpdateDate: DateTime(2026, 11, 1, 0, 50),
          autoUpdateDuration: const Duration(hours: 12),
          subscriptionInfo: SubscriptionInfo(
            upload: 12884901888,
            download: 64424509440,
            total: 214748364800,
            expire: expireEpoch,
          ),
          providerHeaders: {
            'announce': base64.encode(
              utf8.encode('【重要通知】双十一期间赠送额外 50GB 高速流量包，点击更新订阅即可生效！'),
            ),
            'support-url': 'https://support.example.com',
            'x-hwid-max-devices-reached': 'true',
          },
        ),
      ],
      currentProfileId: 'pro',
    );
    globalState.appState = AppState(
      pageLabel: PageLabel.dashboard,
      viewSize: size,
      isInit: true,
      version: 1,
      requests: FixedList(5),
      logs: FixedList(5),
      traffics: traffics,
      totalTraffic: Traffic(up: 67108864, down: 536870912),
      groups: const [
        Group(
          name: 'Proxy',
          type: GroupType.Selector,
          now: '🇸🇬 新加坡 BGP 02',
          all: [
            Proxy(name: '🇭🇰 香港 IEPL 01', type: 'Shadowsocks'),
            Proxy(name: '🇸🇬 新加坡 BGP 02', type: 'Trojan'),
          ],
        ),
      ],
      delayMap: const {
        defaultTestUrl: {'🇸🇬 新加坡 BGP 02': 45},
      },
    );

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final baseLight = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorSchemeSeed: const Color(0xFF0277BD),
      fontFamily: 'DashboardRender',
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: baseLight,
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.delegate.supportedLocales,
          home: RepaintBoundary(
            key: const ValueKey('dashboard-light-pro'),
            child: Builder(
              builder: (context) {
                globalState.measure = Measure.of(context, 1.0);
                globalState.theme = CommonTheme.of(context, 1.0);
                return const CommonScaffold(
                  title: '仪表盘',
                  body: DashboardView(),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await capturePng(
      tester,
      const ValueKey('dashboard-light-pro'),
      'dashboard-520x960-light-pro.png',
    );
  });
}

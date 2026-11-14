import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/theme.dart';
import 'package:flclashx/controller.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/views/dashboard/dashboard.dart';
import 'package:flclashx/views/dashboard/widgets/metainfo_widget.dart';
import 'package:flclashx/views/dashboard/widgets/network_speed.dart';
import 'package:flclashx/views/dashboard/widgets/start_button.dart';
import 'package:flclashx/widgets/card.dart';
import 'package:flclashx/widgets/donut_chart.dart';
import 'package:flclashx/widgets/earth_proxy_switch.dart';
import 'package:flclashx/widgets/line_chart.dart';
import 'package:flclashx/widgets/scaffold.dart';
import 'package:flclashx/widgets/super_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.root);
  final String root;

  @override
  Future<String> getApplicationSupportPath() async => root;

  @override
  Future<String> getTemporaryPath() async => root;

  @override
  Future<String> getDownloadsPath() async => root;
}

class _TestDashboardController implements AppController {
  ProviderContainer? container;
  int updateProfileCalls = 0;
  Profile? lastUpdatedProfile;
  Completer<void>? pendingUpdate;
  Exception? updateError;
  final List<bool> statusUpdates = [];
  Future<void> Function({required bool isStart})? onUpdateStatus;

  @override
  Future<void> updateProfile(
    Profile profile, {
    bool shouldSendHeaders = true,
  }) async {
    updateProfileCalls++;
    lastUpdatedProfile = profile;
    if (pendingUpdate != null) {
      await pendingUpdate!.future;
    }
    if (updateError != null) {
      throw updateError!;
    }
    final latest = globalState.config.profiles.getProfile(profile.id);
    if (latest != null) {
      setProfile(
        latest.copyWith(
          isUpdating: false,
          lastUpdateDate: DateTime(2026, 11, 1, 0, 30),
        ),
      );
    }
  }

  @override
  void setProfile(Profile profile) {
    if (container != null) {
      container!.read(profilesProvider.notifier).setProfile(profile);
      return;
    }
    final next = List<Profile>.from(globalState.config.profiles);
    final idx = next.indexWhere((item) => item.id == profile.id);
    if (idx >= 0) {
      next[idx] = profile;
    } else {
      next.add(profile);
    }
    globalState.config = globalState.config.copyWith(profiles: next);
  }

  @override
  void changeMode(Mode mode) {}

  @override
  Future<void> updateStatus(bool isStart) async {
    statusUpdates.add(isStart);
    if (onUpdateStatus != null) {
      await onUpdateStatus!(isStart: isStart);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Widget _buildTestHarness({
  required Widget child,
  ProviderContainer? container,
  bool attachNavigatorKey = false,
  Locale locale = const Locale('zh', 'CN'),
  double textScale = 1.0,
  Size viewSize = const Size(480, 900),
}) {
  final app = MaterialApp(
    navigatorKey: attachNavigatorKey ? globalState.navigatorKey : null,
    locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        theme: ThemeData.dark(useMaterial3: true),
        home: MediaQuery(
          data: MediaQueryData(
            size: viewSize,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Builder(
            builder: (context) {
              globalState.measure = Measure.of(context, textScale);
              globalState.theme = CommonTheme.of(context, textScale);
              return CommonScaffold(
                title: 'Dashboard',
                body: child,
              );
            },
          ),
        ),
      );
  if (container != null) {
    return UncontrolledProviderScope(
      container: container,
      child: app,
    );
  }
  return ProviderScope(child: app);
}

void _seedGlobalState({
  required List<Profile> profiles,
  String? currentProfileId,
  Size viewSize = const Size(480, 900),
  List<Traffic>? traffics,
  Traffic? totalTraffic,
  List<Group> groups = const [],
  Map<String, Map<String, int?>> delayMap = const {},
  AppSettingProps? appSetting,
}) {
  final trafficList = FixedList<Traffic>(30);
  (traffics ?? [Traffic(up: 288, down: 2263)]).forEach(trafficList.add);
  globalState.config = Config(
    themeProps: defaultThemeProps,
    profiles: profiles,
    currentProfileId: currentProfileId,
    appSetting: appSetting ?? defaultAppSettingProps,
  );
  globalState.appState = AppState(
    pageLabel: PageLabel.dashboard,
    viewSize: viewSize,
    isInit: false,
    version: 1,
    requests: FixedList(5),
    logs: FixedList(5),
    traffics: trafficList,
    totalTraffic: totalTraffic ?? Traffic(up: 181843394, down: 33093222),
    groups: groups,
    delayMap: delayMap,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('flclashx_dashboard_test_');
    PathProviderPlatform.instance = _TestPaths(tempDir.path);
  });

  tearDownAll(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test(
    'Req 1 config contract: merged networkSpeed is shown by default, legacy trafficUsage/announce migrate once, and subsequent hide preference persists',
    () {
      // 1. Fresh install defaults show metainfo + merged networkSpeed + outboundModeV2
      expect(
        defaultDashboardWidgets,
        equals(const [
          DashboardWidget.metainfo,
          DashboardWidget.networkSpeed,
          DashboardWidget.outboundModeV2,
        ]),
      );

      // 2. Legacy unmigrated default config promotes merged networkSpeed and drops duplicate announce
      final migratedLegacyDefault = Config.compatibleFromJson(<String, Object?>{
        'themeProps': const <String, Object?>{},
        'appSetting': const <String, Object?>{
          'dashboardWidgets': <Object?>[
            'announce',
            'metainfo',
            'outboundModeV2',
          ],
        },
      });
      expect(
        migratedLegacyDefault.appSetting.dashboardWidgets,
        equals(const [
          DashboardWidget.metainfo,
          DashboardWidget.networkSpeed,
          DashboardWidget.outboundModeV2,
        ]),
      );

      // 3. Legacy config with both networkSpeed and trafficUsage deduplicates to single networkSpeed
      final migratedBoth = Config.compatibleFromJson(<String, Object?>{
        'themeProps': const <String, Object?>{},
        'appSetting': const <String, Object?>{
          'dashboardWidgets': <Object?>[
            'metainfo',
            'trafficUsage',
            'networkSpeed',
            'memoryInfo',
          ],
        },
      });
      expect(
        migratedBoth.appSetting.dashboardWidgets,
        equals(const [
          DashboardWidget.metainfo,
          DashboardWidget.networkSpeed,
          DashboardWidget.memoryInfo,
        ]),
      );

      // 4. After user hides networkSpeed and saves config, reload preserves hidden state
      final hiddenSaved = jsonDecode(
        jsonEncode(
          migratedLegacyDefault.copyWith(
            appSetting: migratedLegacyDefault.appSetting.copyWith(
              dashboardWidgets: const [
                DashboardWidget.metainfo,
                DashboardWidget.outboundModeV2,
              ],
            ),
          ),
        ),
      ) as Map<String, Object?>;
      final reloadedAfterHide = Config.compatibleFromJson(hiddenSaved);
      expect(
        reloadedAfterHide.appSetting.dashboardWidgets,
        equals(const [
          DashboardWidget.metainfo,
          DashboardWidget.outboundModeV2,
        ]),
      );

      // 5. Provider header layout parser also deduplicates trafficUsage -> networkSpeed
      expect(
        DashboardWidgetParser.parseLayout(
          'metainfo,trafficUsage,networkSpeed,outboundModeV2',
        ),
        equals(const [
          DashboardWidget.metainfo,
          DashboardWidget.networkSpeed,
          DashboardWidget.outboundModeV2,
        ]),
      );
    },
  );

  testWidgets(
    'Req 1 UI & edit/hide: unified card renders both 网络速度 and 流量统计 by default, and supports hide & re-add in Dashboard edit mode',
    (tester) async {
      await AppLocalizations.load(const Locale('zh', 'CN'));
      final controller = _TestDashboardController();
      globalState.appController = controller;
      const size = Size(480, 900);
      _seedGlobalState(
        viewSize: size,
        profiles: [
          const Profile(
            id: 'admin',
            label: 'admin',
            url: 'https://example.com/sub',
            autoUpdateDuration: Duration(hours: 24),
            subscriptionInfo: SubscriptionInfo(
              upload: 10485760,
              download: 52428800,
              total: 0,
              expire: 0,
            ),
          ),
        ],
        currentProfileId: 'admin',
      );

      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestHarness(
          viewSize: size,
          child: const DashboardView(),
        ),
      );
      await tester.pumpAndSettle();

      // Unified card is displayed by default with both NetworkSpeed and TrafficUsage visuals
      expect(
        find.byKey(const ValueKey('dashboard-network-traffic-card')),
        findsOneWidget,
      );
      expect(find.text('网络速度'), findsOneWidget);
      expect(find.text('流量统计'), findsOneWidget);
      expect(find.byType(LineChart), findsOneWidget);
      expect(find.byType(DonutChart), findsOneWidget);
      expect(find.text('上传'), findsOneWidget);
      expect(find.text('下载'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Enter Edit mode -> hide unified card -> Save
      await tester.tap(find.byIcon(Icons.edit));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      final cardInEdit =
          find.byKey(const ValueKey('dashboard-network-traffic-card'));
      expect(cardInEdit, findsOneWidget);

      // Delete unified card via its close button
      final closeButtons = find.byIcon(Icons.close);
      expect(closeButtons, findsWidgets);
      // Find the close button nearest to dashboard-network-traffic-card
      final cardTopRight = tester.getTopRight(cardInEdit);
      Finder? targetClose;
      var bestDist = double.infinity;
      for (var i = 0; i < closeButtons.evaluate().length; i++) {
        final candidate = closeButtons.at(i);
        final dist = (tester.getCenter(candidate) - cardTopRight).distance;
        if (dist < bestDist) {
          bestDist = dist;
          targetClose = candidate;
        }
      }
      await tester.tap(targetClose!);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('dashboard-network-traffic-card')),
        findsNothing,
      );
      expect(
        globalState.config.appSetting.dashboardWidgets
            .contains(DashboardWidget.networkSpeed),
        isFalse,
      );

      // Standalone trafficUsage is disabled across all platforms (never duplicable)
      expect(DashboardWidget.trafficUsage.platforms, isEmpty);

      // Re-enter Edit mode -> verify add_circle action is available -> re-add unified card -> Save
      await tester.tap(find.byIcon(Icons.edit));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byIcon(Icons.add_circle), findsOneWidget);

      tester
          .state<SuperGridState>(find.byType(SuperGrid))
          .handleAdd(DashboardWidget.networkSpeed.widget);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('dashboard-network-traffic-card')),
        findsOneWidget,
      );
      expect(
        globalState.config.appSetting.dashboardWidgets
            .contains(DashboardWidget.networkSpeed),
        isTrue,
      );
    },
  );

  testWidgets(
    'Req 2 UI & sync: MetainfoWidget renders announcement on Row 1, replaces circular sync icon with text button "点击更新订阅", shows all profile info, and guards sync lifecycle',
    (tester) async {
      await AppLocalizations.load(const Locale('zh', 'CN'));
      final controller = _TestDashboardController();
      globalState.appController = controller;
      const size = Size(520, 960);
      final encodedAnnounce =
          'base64:${base64.encode(utf8.encode('系统升级通知：新高速入口已上线 https://status.example.com'))}';
      final encodedService = base64.encode(utf8.encode('星云旗舰专线'));

      _seedGlobalState(
        viewSize: size,
        profiles: [
          Profile(
            id: 'admin',
            label: 'admin',
            url: 'https://example.com/sub/admin',
            lastUpdateDate: DateTime(2026, 10, 31, 23, 45),
            autoUpdateDuration: const Duration(hours: 24),
            overrideData: const OverrideData(
              enable: true,
              rule: OverrideRule(
                addedRules: [Rule(id: 'r1', value: 'DOMAIN,example.com,DIRECT')],
              ),
            ),
            subscriptionInfo: const SubscriptionInfo(
              upload: 181843394,
              download: 585920000000,
              total: 0,
              expire: 0,
            ),
            providerHeaders: {
              'announce': encodedAnnounce,
              'flclashx-servicename': encodedService,
              'support-url': 'https://support.example.com',
              'x-hwid-max-devices-reached': 'true',
            },
          ),
        ],
        currentProfileId: 'admin',
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
          defaultTestUrl: {'🇭🇰 香港 IEPL 01': 36},
        },
      );

      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestHarness(
          viewSize: size,
          child: const SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: MetainfoWidget(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Announcement MUST be rendered on Row 1 (strictly above profile title & update button)
      final announceFinder =
          find.byKey(const ValueKey('metainfo-announce-row'));
      final updateBtnFinder =
          find.byKey(const ValueKey('metainfo-update-subscription-button'));
      expect(announceFinder, findsOneWidget);
      expect(updateBtnFinder, findsOneWidget);
      expect(
        find.textContaining('系统升级通知：新高速入口已上线', findRichText: true),
        findsOneWidget,
      );

      // 2. Old circular sync arrows MUST be completely replaced by "点击更新订阅" text button
      expect(find.byIcon(Icons.sync), findsNothing);
      expect(find.text('点击更新订阅'), findsOneWidget);

      final announceRect = tester.getRect(announceFinder);
      final titleRect = tester.getRect(find.text('admin'));
      final updateRect = tester.getRect(updateBtnFinder);
      expect(announceRect.top, lessThan(titleRect.top));
      expect(announceRect.bottom, lessThanOrEqualTo(titleRect.top + 4));
      expect(announceRect.top, lessThan(updateRect.top));

      // 3. All available profile/subscription/runtime information is displayed
      expect(find.textContaining('星云旗舰专线'), findsOneWidget);
      expect(find.textContaining('自动更新 24h'), findsOneWidget);
      expect(find.textContaining('规则覆写 1'), findsOneWidget);
      expect(find.textContaining('已达设备数量上限'), findsOneWidget);
      expect(find.textContaining('不限流量'), findsOneWidget);
      // Even on unlimited plan, cumulative upload & download breakdown is shown
      expect(find.textContaining('↑'), findsWidgets);
      expect(find.textContaining('↓'), findsWidgets);
      expect(find.textContaining('长期有效'), findsOneWidget);
      expect(find.textContaining('2026-10-31 23:45'), findsOneWidget);
      expect(
        find.textContaining('香港 IEPL 01', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('共 3 个节点'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('metainfo-support-button')),
        findsOneWidget,
      );

      // 4. Clicking "点击更新订阅" invokes updateProfile once and blocks duplicate taps while in flight
      final completer = Completer<void>();
      controller.pendingUpdate = completer;
      await tester.tap(updateBtnFinder);
      await tester.pump();
      expect(controller.updateProfileCalls, 1);
      expect(find.textContaining('更新中'), findsOneWidget);

      // Second tap while syncing must be ignored
      await tester.tap(updateBtnFinder, warnIfMissed: false);
      await tester.pump();
      expect(controller.updateProfileCalls, 1);

      completer.complete();
      await tester.pumpAndSettle();
      expect(find.text('点击更新订阅'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Req 1 & 2 responsive 320px @ 2.0x textScale across zh_CN and ru: zero overflow for both cards and capped/unsynced profiles',
    (tester) async {
      final controller = _TestDashboardController();
      globalState.appController = controller;
      const narrowSize = Size(320, 960);
      final expireEpoch =
          DateTime.now().add(const Duration(days: 25)).millisecondsSinceEpoch ~/
              1000;

      for (final locale in const [Locale('zh', 'CN'), Locale('ru')]) {
        await AppLocalizations.load(locale);
        _seedGlobalState(
          viewSize: narrowSize,
          profiles: [
            Profile(
              id: 'pro',
              label: 'Pro Subscription Very Long Name 2026',
              url: 'https://example.com/sub/pro',
              autoUpdateDuration: const Duration(hours: 12),
              subscriptionInfo: SubscriptionInfo(
                upload: 2147483648,
                download: 10737418240,
                total: 107374182400,
                expire: expireEpoch,
              ),
              providerHeaders: {
                'announce': base64.encode(
                  utf8.encode('重要维护公告：今晚 02:00 线路例行优化升级'),
                ),
                'support-url': 'https://support.example.com',
              },
            ),
          ],
          currentProfileId: 'pro',
        );

        tester.view.physicalSize = narrowSize;
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          _buildTestHarness(
            locale: locale,
            textScale: 2.0,
            viewSize: narrowSize,
            child: const SingleChildScrollView(
              padding: EdgeInsets.all(12),
              child: Column(
                children: [
                  MetainfoWidget(),
                  SizedBox(height: 12),
                  NetworkSpeed(),
                ],
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
      }

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    },
  );

  testWidgets(
    'Req 2 edge cases: unsynced URL profile renders before first sync, local profile omits sync button, sync failure rolls back isUpdating, and Dashboard suppresses duplicate AnnounceWidget',
    (tester) async {
      await AppLocalizations.load(const Locale('zh', 'CN'));
      final controller = _TestDashboardController()
        ..updateError = Exception('network timeout');
      globalState.appController = controller;
      const size = Size(480, 900);

      // Unsynced URL profile (subscriptionInfo == null, lastUpdateDate == null) + announce header
      _seedGlobalState(
        viewSize: size,
        appSetting: defaultAppSettingProps.copyWith(
          dashboardWidgets: const [
            DashboardWidget.announce,
            DashboardWidget.metainfo,
            DashboardWidget.networkSpeed,
          ],
        ),
        profiles: [
          Profile(
            id: 'unsynced',
            label: '待首次同步订阅',
            url: 'https://example.com/sub/unsynced',
            autoUpdate: false,
            autoUpdateDuration: const Duration(hours: 24),
            providerHeaders: {
              'announce': base64.encode(utf8.encode('首次导入公告只显示一次')),
            },
          ),
        ],
        currentProfileId: 'unsynced',
      );

      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      controller.container = container;

      await tester.pumpWidget(
        _buildTestHarness(
          container: container,
          attachNavigatorKey: true,
          viewSize: size,
          child: const DashboardView(),
        ),
      );
      await tester.pumpAndSettle();

      // Announcement appears once inside MetainfoWidget (standalone AnnounceWidget suppressed)
      expect(
        find.textContaining('首次导入公告只显示一次', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('待首次同步订阅'), findsOneWidget);
      expect(find.textContaining('手动更新'), findsOneWidget);
      expect(find.textContaining('同步时间：尚未同步'), findsOneWidget);
      expect(find.text('点击更新订阅'), findsOneWidget);

      // Failed sync rolls back isUpdating cleanly and re-enables "点击更新订阅"
      await tester.tap(
        find.byKey(const ValueKey('metainfo-update-subscription-button')),
      );
      await tester.pumpAndSettle();
      expect(controller.updateProfileCalls, 1);
      expect(
        globalState.config.profiles.getProfile('unsynced')?.isUpdating,
        isFalse,
      );
      // Error dialog is presented via safeRun(silence: false) and dismissible
      expect(find.textContaining('network timeout'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('点击更新订阅'), findsOneWidget);

      // Local file profile omits "点击更新订阅" and shows "本地配置"
      controller.container = null;
      _seedGlobalState(
        viewSize: size,
        profiles: const [
          Profile(
            id: 'local-yaml',
            label: '本地 YAML 配置',
            url: '',
            autoUpdateDuration: Duration.zero,
          ),
        ],
        currentProfileId: 'local-yaml',
      );
      await tester.pumpWidget(
        _buildTestHarness(
          viewSize: size,
          child: const SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: MetainfoWidget(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('本地 YAML 配置'), findsOneWidget);
      expect(find.textContaining('本地配置'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('metainfo-update-subscription-button')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'Dashboard floating tactile proxy switch: replaces full-width green bar with bottom-center FloatingProxyDock matching Overview, auto-slides on click, rejects drag, clears bottom cards on scroll, and hides in edit/empty modes',
    (tester) async {
      await AppLocalizations.load(const Locale('zh', 'CN'));
      const size = Size(480, 480);
      final controller = _TestDashboardController();
      globalState.appController = controller;

      const adminProfile = Profile(
        id: 'admin',
        label: 'admin',
        url: 'https://example.com/sub/admin',
        autoUpdateDuration: Duration(hours: 24),
        subscriptionInfo: SubscriptionInfo(
          upload: 10485760,
          download: 52428800,
          total: 107374182400,
          expire: 0,
        ),
      );
      const dashboardAppSetting = defaultAppSettingProps;

      _seedGlobalState(
        viewSize: size,
        appSetting: dashboardAppSetting,
        profiles: const [adminProfile],
        currentProfileId: 'admin',
      );
      globalState.appState = globalState.appState.copyWith(isInit: true);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      controller
        ..container = container
        ..onUpdateStatus = ({required isStart}) async {
          container.read(runTimeProvider.notifier).value = isStart ? 1000 : null;
        };

      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestHarness(
          container: container,
          viewSize: size,
          child: const DashboardView(),
        ),
      );
      await tester.pumpAndSettle();

      final dockFinder = find.byKey(
        const ValueKey('dashboard-floating-proxy-dock'),
      );
      final switchFinder = find.byKey(
        const ValueKey('dashboard-proxy-toggle'),
      );
      final earthFinder = find.byType(EarthProxySwitch);
      final scrollFinder = find.byKey(const ValueKey('dashboard-scroll-view'));

      expect(dockFinder, findsOneWidget);
      expect(switchFinder, findsOneWidget);
      expect(earthFinder, findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(StartButton),
          matching: find.byType(FilledButton),
        ),
        findsNothing,
      );

      final initialDockRect = tester.getRect(dockFinder);
      final scrollRect = tester.getRect(scrollFinder);
      expect(initialDockRect.center.dx, closeTo(scrollRect.center.dx, 1.5));
      final expectedBottomMargin = math.min(
        16.0,
        math.max(6.0, scrollRect.height * 0.03),
      );
      expect(
        initialDockRect.bottom,
        closeTo(scrollRect.bottom - expectedBottomMargin, 1.5),
      );
      expect(initialDockRect.width, lessThan(220));
      expect(find.text('开启代理'), findsNothing);

      // Manual 3D drag rotates the globe without triggering toggle.
      final yawBeforeDrag =
          EarthProxySwitch.debugSnapshotOf(tester.element(earthFinder))!.yaw;
      await tester.drag(switchFinder, const Offset(90, 0));
      await tester.pumpAndSettle();
      expect(controller.statusUpdates, isEmpty);
      expect(
        (EarthProxySwitch.debugSnapshotOf(tester.element(earthFinder))!.yaw -
                yawBeforeDrag)
            .abs(),
        greaterThan(0.1),
      );

      // Single click turns Earth ON immediately without rendering stopwatch or pill text.
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();
      expect(controller.statusUpdates, [true]);
      expect(tester.widget<EarthProxySwitch>(earthFinder).isRunning, isTrue);
      expect(
        EarthProxySwitch.debugSnapshotOf(tester.element(earthFinder))!.activeMix,
        closeTo(1.0, 0.01),
      );
      expect(find.text('运行中'), findsNothing);
      expect(find.text('00:00:01'), findsNothing);

      // Mouse hover over active Earth does not render capsule captions or trigger extra toggle.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(switchFinder));
      await tester.pumpAndSettle();
      expect(find.text('关闭代理'), findsNothing);
      expect(find.text('运行中'), findsNothing);
      expect(controller.statusUpdates, [true]);
      await mouse.moveTo(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(find.text('关闭代理'), findsNothing);
      expect(find.text('运行中'), findsNothing);
      expect(controller.statusUpdates, [true]);

      // Scrolling keeps dock anchored and leaves bottom-most card unobstructed at maxScrollExtent.
      await tester.drag(scrollFinder, const Offset(0, -120));
      await tester.pumpAndSettle();
      expect(tester.getRect(dockFinder), initialDockRect);

      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: scrollFinder,
          matching: find.byType(Scrollable),
        ).first,
      );
      expect(scrollable.position.maxScrollExtent, greaterThan(0));
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final lastGridCardFinder = find.byType(CommonCard).last;
      expect(lastGridCardFinder, findsOneWidget);
      expect(
        tester.getRect(lastGridCardFinder).bottom,
        lessThanOrEqualTo(initialDockRect.top),
      );

      // Edit mode hides the floating dock; saving restores it.
      await tester.tap(find.byIcon(Icons.edit));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(dockFinder, findsNothing);
      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();
      expect(dockFinder, findsOneWidget);

      // Empty profiles hides the floating dock.
      await tester.pumpWidget(const SizedBox.shrink());
      _seedGlobalState(
        viewSize: size,
        appSetting: dashboardAppSetting,
        profiles: const <Profile>[],
      );
      globalState.appState = globalState.appState.copyWith(isInit: true);
      final emptyContainer = ProviderContainer();
      addTearDown(emptyContainer.dispose);
      await tester.pumpWidget(
        _buildTestHarness(
          container: emptyContainer,
          viewSize: size,
          child: const DashboardView(),
        ),
      );
      await tester.pumpAndSettle();
      expect(dockFinder, findsNothing);

      // Responsive 320px @ 2.0x text scaling across locales and brightness stays within bounds.
      for (final (locale, brightness) in [
        (const Locale('ru'), Brightness.dark),
        (const Locale('zh', 'CN'), Brightness.light),
      ]) {
        await AppLocalizations.load(locale);
        await tester.pumpWidget(const SizedBox.shrink());
        const narrowSize = Size(320, 720);
        tester.view.physicalSize = narrowSize;
        tester.view.devicePixelRatio = 1.0;
        _seedGlobalState(
          viewSize: narrowSize,
          appSetting: dashboardAppSetting,
          profiles: const [adminProfile],
          currentProfileId: 'admin',
        );
        globalState.appState = globalState.appState.copyWith(isInit: true);
        final scaledContainer = ProviderContainer();
        addTearDown(scaledContainer.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: scaledContainer,
            child: MaterialApp(
              locale: locale,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.delegate.supportedLocales,
              theme: ThemeData(brightness: brightness, useMaterial3: true),
              home: MediaQuery(
                data: const MediaQueryData(
                  size: narrowSize,
                  textScaler: TextScaler.linear(2.0),
                ),
                child: Builder(
                  builder: (context) {
                    globalState.measure = Measure.of(context, 2.0);
                    globalState.theme = CommonTheme.of(context, 2.0);
                    return const CommonScaffold(
                      title: 'Dashboard',
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
        expect(dockFinder, findsOneWidget);
        final scaledDockRect = tester.getRect(dockFinder);
        final scaledScrollRect = tester.getRect(scrollFinder);
        expect(scaledDockRect.left, greaterThanOrEqualTo(scaledScrollRect.left));
        expect(scaledDockRect.right, lessThanOrEqualTo(scaledScrollRect.right));
      }
    },
  );
}

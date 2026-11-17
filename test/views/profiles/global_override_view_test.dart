import 'package:flclashx/common/common.dart';
import 'package:flclashx/controller.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/views/config/network.dart';
import 'package:flclashx/views/profiles/override_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingAppController implements AppController {
  int setupConfigCalls = 0;
  int savePrefsCalls = 0;

  @override
  void setupClashConfigDebounce() {
    setupConfigCalls++;
  }

  @override
  void savePreferencesDebounce() {
    savePrefsCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _TestGlobalState extends GlobalState {
  _TestGlobalState() : super.forTesting();

  @override
  Future<Map<String, dynamic>> getProfileConfig(String profileId) async => {
        'proxy-groups': [
          {
            'name': '🚀 节点选择',
            'type': 'select',
            'proxies': ['HK-01', 'DIRECT'],
          },
        ],
        'rules': ['MATCH,🚀 节点选择'],
      };
}

Widget _buildTestHarness({
  required Widget child,
}) =>
    ProviderScope(
      key: UniqueKey(),
      child: MaterialApp(
        navigatorKey: globalState.navigatorKey,
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        theme: ThemeData.dark(useMaterial3: true),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(960, 760)),
          child: Builder(
            builder: (context) {
              globalState.measure = Measure.of(context, 1.0);
              return child;
            },
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingAppController controller;

  setUp(() {
    controller = _RecordingAppController();
    globalState.appController = controller;
    globalState.config = Config(
      themeProps: defaultThemeProps,
      currentProfileId: 'p1',
      profiles: const [
        Profile(
          id: 'p1',
          label: 'TestSub',
          autoUpdateDuration: Duration.zero,
        ),
      ],
      globalOverrideData: const OverrideData(enable: false),
    );
    globalState.appState = AppState(
      pageLabel: PageLabel.profiles,
      viewSize: const Size(960, 760),
      isInit: true,
      version: 1,
      requests: FixedList(5),
      logs: FixedList(5),
      traffics: FixedList(5),
      totalTraffic: Traffic(),
      groups: const [
        Group(
          type: GroupType.Selector,
          name: '🚀 节点选择',
          now: 'HK-01',
          all: [Proxy(name: 'HK-01', type: 'Trojan')],
        ),
      ],
      delayMap: const {},
    );
  });

  testWidgets(
    'GlobalOverrideView auto-persists added rule with DEFAULT_PROXY and auto-enables switch without separate save button',
    (tester) async {
      await tester.pumpWidget(
        _buildTestHarness(
          child: const GlobalOverrideView(),
        ),
      );
      await tester.pumpAndSettle();

      // Legacy manual save icon trap must be gone
      expect(find.byIcon(Icons.save), findsNothing);

      // Tap Add rule button
      await tester.tap(find.byKey(const ValueKey('override-add-rule-button')));
      await tester.pumpAndSettle();

      // Enter domain content; default action is DOMAIN-SUFFIX and default target is DEFAULT_PROXY
      await tester.enterText(
        find.byKey(const ValueKey('add-rule-content-field')),
        'claude.ai',
      );
      await tester.tap(find.byKey(const ValueKey('add-rule-confirm-button')));
      await tester.pumpAndSettle();

      expect(globalState.config.globalOverrideData.enable, isTrue);
      expect(
        globalState.config.globalOverrideData.runningRule,
        ['DOMAIN-SUFFIX,claude.ai,$semanticDefaultProxyTarget'],
      );
      expect(controller.setupConfigCalls, greaterThanOrEqualTo(1));
      expect(controller.savePrefsCalls, greaterThanOrEqualTo(1));
    },
  );

  testWidgets(
    'OverrideProfileView auto-persists added rule immediately into profilesProvider and auto-enables switch',
    (tester) async {
      final fakeState = _TestGlobalState()
        ..config = globalState.config
        ..appController = controller;

      await tester.pumpWidget(
        _buildTestHarness(
          child: OverrideProfileView(
            profileId: 'p1',
            loadProfileConfig: fakeState.getProfileConfig,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.save), findsNothing);

      await tester.tap(find.byKey(const ValueKey('override-add-rule-button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('add-rule-content-field')),
        'corp.internal',
      );
      await tester.tap(find.byKey(const ValueKey('add-rule-confirm-button')));
      await tester.pumpAndSettle();

      final savedProfile = globalState.config.profiles.first;
      expect(savedProfile.overrideData.enable, isTrue);
      expect(
        savedProfile.overrideData.runningRule,
        ['DOMAIN-SUFFIX,corp.internal,🚀 节点选择'],
      );
      expect(controller.setupConfigCalls, greaterThanOrEqualTo(1));
      expect(controller.savePrefsCalls, greaterThanOrEqualTo(1));
    },
  );

  testWidgets(
    'LocalSplitModeItem updates localSplitMode between auto, always, and off',
    (tester) async {
      await tester.pumpWidget(
        _buildTestHarness(
          child: const Scaffold(body: LocalSplitModeItem()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        globalState.config.networkProps.localSplitMode,
        LocalSplitMode.auto,
      );

      await tester.tap(find.byType(LocalSplitModeItem));
      await tester.pumpAndSettle();

      await tester.tap(find.text('关闭').last);
      await tester.pumpAndSettle();

      expect(
        globalState.config.networkProps.localSplitMode,
        LocalSplitMode.off,
      );
      expect(controller.setupConfigCalls, greaterThanOrEqualTo(1));
    },
  );
}

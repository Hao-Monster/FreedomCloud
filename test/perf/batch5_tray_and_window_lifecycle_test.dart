import 'dart:async';
import 'dart:io';

import 'package:flclashx/common/fixed.dart';
import 'package:flclashx/common/tray.dart';
import 'package:flclashx/common/window.dart';
import 'package:flclashx/controller.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _baseTrayState = TrayState(
  mode: Mode.rule,
  port: 7890,
  autoLaunch: false,
  systemProxy: false,
  tunEnable: false,
  isStart: true,
  locale: null,
  brightness: Brightness.light,
  groups: [
    Group(
      name: 'Proxy',
      type: GroupType.Selector,
      hidden: false,
      all: [
        Proxy(name: 'HK-01', type: 'Shadowsocks'),
        Proxy(name: 'SG-01', type: 'Shadowsocks'),
      ],
    ),
  ],
  selectedMap: {'Proxy': 'HK-01'},
);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('tray_manager');

  setUp(() async {
    await AppLocalizations.load(const Locale('en'));
    globalState.config = const Config(themeProps: defaultThemeProps);
    globalState.appState = AppState(
      viewSize: Size.zero,
      version: 1,
      requests: FixedList(1),
      logs: FixedList(1),
      traffics: FixedList(1),
      totalTraffic: Traffic(),
    );
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  testWidgets(
    'P1-3: background updateTray skips setContextMenu on Windows, deduplicates unchanged icon, and preserves live traffic tooltip',
    (tester) async {
      final calls = <MethodCall>[];
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async {
          calls.add(call);
          return null;
        },
      );

      final stateHolder = ValueNotifier<TrayState>(_baseTrayState);
      addTearDown(stateHolder.dispose);
      AppController? controller;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trayStateProvider.overrideWith((ref) {
              void sub() => ref.invalidateSelf();
              stateHolder.addListener(sub);
              ref.onDispose(() => stateHolder.removeListener(sub));
              return stateHolder.value;
            }),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              controller ??= AppController(context, ref);
              globalState.appController = controller!;
              return const SizedBox();
            },
          ),
        ),
      );

      // Reset shared tray singleton icon/tooltip state via forced update first.
      await tester.runAsync(() => controller!.updateTray(true));
      expect(
        calls.where((c) => c.method == 'setContextMenu'),
        hasLength(1),
        reason: 'focus=true must push context menu',
      );
      calls.clear();

      // Update live traffic tooltip.
      await tester.runAsync(
        () => tray.updateTrayTitle(Traffic(up: 2048, down: 4096)),
      );
      if (Platform.isWindows) {
        expect(calls.map((c) => c.method), ['setToolTip']);
      }
      calls.clear();

      // Background state change (mode changed, icon brightness/isStart unchanged).
      stateHolder.value = _baseTrayState.copyWith(mode: Mode.global);
      await tester.pump();
      await tester.runAsync(() => controller!.updateTray());

      if (Platform.isWindows) {
        expect(
          calls,
          isEmpty,
          reason:
              'Unchanged icon during background updateTray() on Windows must skip setContextMenu, skip duplicate setIcon, and not clobber traffic tooltip',
        );
      } else {
        expect(
          calls.where((c) => c.method == 'setContextMenu'),
          hasLength(1),
        );
        calls.clear();
      }

      // Right-click on-demand tray.update(trayState: ...) builds and pushes fresh menu.
      await tester.runAsync(() => tray.update(trayState: stateHolder.value));
      expect(
        calls.where((c) => c.method == 'setContextMenu'),
        hasLength(1),
        reason: 'On-demand popup refresh must build latest context menu',
      );
    },
  );

  test(
    'P1-3: updateTrayTitle skips duplicate setToolTip IPC when formatted rate string is unchanged',
    () async {
      final calls = <MethodCall>[];
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async {
          calls.add(call);
          return null;
        },
      );

      final localTray = Tray();
      await localTray.updateTrayTitle(Traffic(up: 1024, down: 2048));
      await localTray.updateTrayTitle(Traffic(up: 1024, down: 2048));

      if (Platform.isWindows) {
        expect(
          calls.map((c) => c.method),
          ['setToolTip'],
          reason: 'Identical tooltip string must not re-invoke Shell_NotifyIconW',
        );
      } else {
        expect(calls, isEmpty);
      }

      await localTray.updateTrayTitle(Traffic(up: 8192, down: 16384));
      if (Platform.isWindows) {
        expect(calls.map((c) => c.method), ['setToolTip', 'setToolTip']);
      }
    },
  );

  test(
    'P1-3: prepareWindowTermination destroys tray and flushes logger even when destroyTray fails or stalls',
    () async {
      final events = <String>[];
      await prepareWindowTermination(
        destroyTray: () async {
          events.add('destroyTray');
          throw StateError('simulated tray failure');
        },
        disposeLogger: () async {
          events.add('disposeLogger');
        },
      );
      expect(events, ['destroyTray', 'disposeLogger']);

      final timeoutEvents = <String>[];
      final hung = Completer<void>();
      final sw = Stopwatch()..start();
      await prepareWindowTermination(
        destroyTray: () {
          timeoutEvents.add('destroyTrayStart');
          return hung.future;
        },
        disposeLogger: () async {
          timeoutEvents.add('disposeLoggerAfterTimeout');
        },
      );
      sw.stop();
      expect(
        timeoutEvents,
        ['destroyTrayStart', 'disposeLoggerAfterTimeout'],
      );
      expect(sw.elapsedMilliseconds, lessThan(1500));
    },
  );
}

import 'dart:async';

import 'package:flclashx/common/fixed.dart';
import 'package:flclashx/common/tray.dart';
import 'package:flclashx/common/tun_runtime.dart';
import 'package:flclashx/controller.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/manager/tray_manager.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/providers/tun.dart';
import 'package:flclashx/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tray_manager/tray_manager.dart' as native_tray;

const initialTrayState = TrayState(
  mode: Mode.rule,
  port: 7890,
  autoLaunch: false,
  systemProxy: false,
  tunEnable: false,
  isStart: false,
  locale: null,
  brightness: Brightness.light,
  groups: [],
  selectedMap: {},
);

TunStatus status({int revision = 1, bool active = false}) => TunStatus(
      instanceId: 'test-core',
      revision: revision,
      state: active ? 'on' : 'off',
      listenerActive: active,
      interfaceState: active ? 'up' : 'missing',
      privilege: 'elevated',
      requestedEnabled: active,
    );

class CountingController extends AppController {
  CountingController(super.context, super.ref);
  int updates = 0;

  @override
  Future<void> updateTray([bool focus = false]) async {
    updates++;
  }
}

Future<CountingController> mountTrayManager(
  WidgetTester tester,
  TunRuntimeController runtime,
) async {
  CountingController? controller;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        trayStateProvider.overrideWithValue(initialTrayState),
        tunRuntimeProvider.overrideWith((ref) => runtime),
      ],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) {
            controller ??= CountingController(context, ref);
            globalState.appController = controller!;
            return const TrayManager(child: SizedBox());
          },
        ),
      ),
    ),
  );
  return controller!;
}

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

  testWidgets('popup cancellation leaves no monitor and permits another open',
      (tester) async {
    var popups = 0;
    final entered = Completer<void>();
    final release = Completer<int>();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'popUpContextMenu') {
        popups++;
        if (popups == 1) {
          entered.complete();
          return release.future;
        }
        return 0;
      }
      return null;
    });
    await mountTrayManager(tester, TunRuntimeController());
    final listener =
        tester.state(find.byType(TrayManager)) as native_tray.TrayListener;
    listener.onTrayIconRightMouseDown();
    listener.onTrayIconRightMouseDown();
    await tester.runAsync(() => entered.future);
    expect(popups, 1);
    release.complete(0);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    listener.onTrayIconRightMouseDown();
    await tester.pumpAndSettle();
    expect(popups, 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('unchanged TUN observations do not rebuild the tray menu', (
    tester,
  ) async {
    final runtime = TunRuntimeController();
    final controller = await mountTrayManager(tester, runtime);
    runtime.accept(status(active: true), runtime.observationEpoch);
    await tester.pump();
    final initialUpdates = controller.updates;
    expect(initialUpdates, greaterThan(0));
    for (var revision = 2; revision <= 12; revision++) {
      runtime.accept(
        status(revision: revision, active: true),
        runtime.observationEpoch,
      );
      await tester.pump();
    }
    expect(controller.updates, initialUpdates);
  });

  testWidgets('TUN busy and failure changes refresh with the same enabled flag',
      (
    tester,
  ) async {
    final runtime = TunRuntimeController();
    runtime.accept(status(), runtime.observationEpoch);
    final controller = await mountTrayManager(tester, runtime);
    final before = controller.updates;
    final release = Completer<void>();
    final operation = runtime.request(true, (_) => release.future);
    try {
      await tester.pump();
      expect(controller.updates, greaterThan(before));
      final busyUpdates = controller.updates;
      runtime.fail('permissionDenied');
      await tester.pump();
      expect(controller.updates, greaterThan(busyUpdates));
      final failedUpdates = controller.updates;
      release.complete();
      await operation;
      await tester.pump();
      expect(controller.updates, greaterThan(failedUpdates));
    } finally {
      if (!release.isCompleted) release.complete();
      await operation;
    }
  });

  testWidgets('unknown transport failure and recovery refresh while TUN is off',
      (
    tester,
  ) async {
    final runtime = TunRuntimeController();
    runtime.accept(status(), runtime.observationEpoch);
    final controller = await mountTrayManager(tester, runtime);
    final before = controller.updates;
    runtime.invalidate('statusUnavailable');
    await tester.pump();
    expect(controller.updates, greaterThan(before));
    final failedUpdates = controller.updates;
    runtime.accept(status(revision: 2), runtime.observationEpoch);
    await tester.pump();
    expect(controller.updates, greaterThan(failedUpdates));
    expect(runtime.failure, isNull);
  });

  testWidgets('controller update waits for the native menu and forwards focus',
      (
    tester,
  ) async {
    final menuEntered = Completer<void>();
    final release = Completer<void>();
    final calls = <String>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call.method);
      if (call.method == 'setContextMenu') {
        menuEntered.complete();
        await release.future;
      }
      return null;
    });
    AppController? controller;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [trayStateProvider.overrideWithValue(initialTrayState)],
        child: Consumer(
          builder: (context, ref, _) {
            controller ??= AppController(context, ref);
            return const SizedBox();
          },
        ),
      ),
    );
    var completed = false;
    final update = controller!.updateTray(true).then((_) => completed = true);
    try {
      await tester.runAsync(() => menuEntered.future);
      expect(completed, isFalse);
      expect(calls, contains('destroy'));
    } finally {
      release.complete();
      await tester.runAsync(() => update);
    }
    expect(completed, isTrue);
  });

  test('menu updates serialize and coalesce to the latest state and force',
      () async {
    final firstEntered = Completer<void>();
    final releaseFirst = Completer<void>();
    final finalEntered = Completer<void>();
    final releaseFinal = Completer<void>();
    final menus = <Map<Object?, Object?>>[];
    var destroys = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'destroy') destroys++;
      if (call.method == 'setContextMenu') {
        menus.add((call.arguments as Map)['menu'] as Map<Object?, Object?>);
        if (menus.length == 1) {
          firstEntered.complete();
          await releaseFirst.future;
        } else if (menus.length == 2) {
          finalEntered.complete();
          await releaseFinal.future;
        }
      }
      return null;
    });
    final localTray = Tray();
    final first = localTray.update(trayState: initialTrayState);
    await firstEntered.future;
    var pendingCompleted = 0;
    final intermediate = localTray
        .update(
            trayState: initialTrayState.copyWith(mode: Mode.direct),
            focus: true)
        .then((_) => pendingCompleted++);
    final latest = localTray
        .update(trayState: initialTrayState.copyWith(mode: Mode.global))
        .then((_) => pendingCompleted++);
    try {
      await Future<void>.delayed(Duration.zero);
      expect(menus, hasLength(1));
      releaseFirst.complete();
      await finalEntered.future;
      expect(pendingCompleted, 0);
      final items = menus.last['items']! as List;
      final global =
          items.cast<Map>().singleWhere((item) => item['label'] == 'Global');
      final direct =
          items.cast<Map>().singleWhere((item) => item['label'] == 'Direct');
      expect(global['checked'], isTrue);
      expect(direct['checked'], isFalse);
      expect(destroys, 1);
    } finally {
      if (!releaseFirst.isCompleted) releaseFirst.complete();
      if (!releaseFinal.isCompleted) releaseFinal.complete();
      await Future.wait([first, intermediate, latest]);
    }
    expect(menus, hasLength(2));
    expect(pendingCompleted, 2);
  });

  test('coalesced native failures reach every waiter and later updates recover',
      () async {
    final firstEntered = Completer<void>();
    final releaseFirst = Completer<void>();
    var menus = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'setContextMenu') {
        menus++;
        if (menus == 1) {
          firstEntered.complete();
          await releaseFirst.future;
        } else if (menus == 2) {
          throw PlatformException(code: 'menu_failed', message: 'test failure');
        }
      }
      return null;
    });
    final localTray = Tray();
    final first = localTray.update(trayState: initialTrayState);
    await firstEntered.future;
    final pending = expectLater(
      localTray.update(trayState: initialTrayState.copyWith(mode: Mode.direct)),
      throwsA(isA<PlatformException>()
          .having((error) => error.code, 'code', 'menu_failed')),
    );
    final latest = expectLater(
      localTray.update(trayState: initialTrayState.copyWith(mode: Mode.global)),
      throwsA(isA<PlatformException>()
          .having((error) => error.code, 'code', 'menu_failed')),
    );
    releaseFirst.complete();
    await Future.wait([first, pending, latest]);
    expect(menus, 2);
    await localTray.update(trayState: initialTrayState);
    expect(menus, 3);
  });

  test('Windows traffic tooltips remain separate from native menu rebuilding',
      () async {
    final calls = <MethodCall>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      return null;
    });
    await Tray().updateTrayTitle(Traffic(up: 1024, down: 2048));
    expect(calls.map((call) => call.method), ['setToolTip']);
    final text = (calls.single.arguments as Map)['toolTip'] as String;
    expect(text, contains('↑'));
    expect(text, contains('↓'));
    expect(text, contains('/s'));
  });

  testWidgets('explicit menu refresh updates node latency with equal TrayState',
      (
    tester,
  ) async {
    const testUrl = 'https://example.invalid/tray-test';
    final menus = <Map<Object?, Object?>>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'setContextMenu') {
        menus.add((call.arguments as Map)['menu'] as Map<Object?, Object?>);
      }
      return null;
    });
    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(
          builder: (context, ref, _) {
            globalState.appController = AppController(context, ref);
            return const SizedBox();
          },
        ),
      ),
    );
    final state = initialTrayState.copyWith(
      isStart: true,
      groups: [
        const Group(
          name: 'qa-group',
          type: GroupType.Selector,
          testUrl: testUrl,
          all: [Proxy(name: 'qa-node', type: 'Direct')],
        ),
      ],
    );
    final localTray = Tray();
    globalState.appState = globalState.appState.copyWith(
      delayMap: {
        testUrl: {'qa-node': 31}
      },
    );
    await tester.runAsync(() => localTray.update(trayState: state));
    globalState.appState = globalState.appState.copyWith(
      delayMap: {
        testUrl: {'qa-node': 72}
      },
    );
    await tester.runAsync(() => localTray.update(trayState: state));
    expect(menus, hasLength(2));
    List<dynamic> groupItems(Map<Object?, Object?> menu) {
      final items = menu['items']! as List;
      final group = items.cast<Map>().singleWhere(
            (item) => (item['label'] as String).startsWith('qa-group'),
          );
      return (group['submenu'] as Map)['items'] as List;
    }

    expect(
        groupItems(menus.first).cast<Map>().last['label'], 'qa-node · 31 ms');
    expect(groupItems(menus.last).cast<Map>().last['label'], 'qa-node · 72 ms');
  });
}

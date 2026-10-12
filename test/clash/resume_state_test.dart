import 'dart:async';

import 'package:flclashx/common/fixed.dart';
import 'package:flclashx/common/tun_runtime.dart';
import 'package:flclashx/common/ui_activity.dart';
import 'package:flclashx/common/windows_tun_startup.dart';
import 'package:flclashx/controller.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _StopEffects implements WindowsTunStartupEffects {
  int stops = 0;
  @override
  Future<void> stopProxy() async {
    stops++;
    globalState.startTime = null;
    globalState.stopUpdateTasks();
  }

  @override
  Future<TunStatus?> observe() async => const TunStatus(
      instanceId: 'isolated-test',
      revision: 1,
      state: 'off',
      listenerActive: false,
      interfaceState: 'missing',
      privilege: 'unprivileged',
      requestedEnabled: false);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    globalState.config = const Config(themeProps: defaultThemeProps);
    globalState.appState = AppState(
        viewSize: Size.zero,
        version: 1,
        requests: FixedList(1),
        logs: FixedList(1),
        traffics: FixedList(1),
        totalTraffic: Traffic());
    globalState.startTime = null;
    globalState.stopUpdateTasks();
    uiActivity.setVisible(true);
    uiActivity.setMinimized(false);
    uiActivity.setLifecycle(AppLifecycleState.resumed);
  });
  tearDown(() {
    globalState.stopUpdateTasks();
    globalState.tasks = [];
    globalState.startTime = null;
    uiActivity.setLifecycle(AppLifecycleState.resumed);
  });

  Future<AppController> fixture(WidgetTester tester,
      Future<DateTime?> Function() probe, _StopEffects effects) async {
    AppController? controller;
    final runtime = TunRuntimeController();
    addTearDown(runtime.dispose);
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(home: Consumer(builder: (context, ref, _) {
      controller ??= AppController(context, ref,
          windowsStartupEffects: effects,
          tunRuntimeController: runtime,
          nativeRunTimeProbe: probe);
      return const SizedBox();
    }))));
    addTearDown(controller!.stopRunTimeTimer);
    return controller!;
  }

  for (final resumeAgain in [false, true]) {
    testWidgets(
        'a late resume probe cannot revive a paused UI (resumedAgain=$resumeAgain)',
        (tester) async {
      final reply = Completer<DateTime?>();
      var samples = 0;
      globalState.tasks = [() => samples++];
      final controller =
          await fixture(tester, () => reply.future, _StopEffects());
      final pending = controller.syncVpnStateOnResume();
      await tester.pump();
      uiActivity.setLifecycle(AppLifecycleState.paused);
      globalState.stopUpdateTasks();
      if (resumeAgain) uiActivity.setLifecycle(AppLifecycleState.resumed);
      reply.complete(DateTime.now().subtract(const Duration(minutes: 1)));
      await pending;
      final committed = globalState.startTime;
      await tester.pump(const Duration(seconds: 6));
      final observedSamples = samples;
      globalState.stopUpdateTasks();
      controller.stopRunTimeTimer();
      expect(committed, isNull);
      expect(observedSamples, 0);
    });
  }

  testWidgets('a manual stop supersedes an earlier native running probe',
      (tester) async {
    final reply = Completer<DateTime?>();
    var samples = 0;
    globalState.tasks = [() => samples++];
    final effects = _StopEffects();
    final controller = await fixture(tester, () => reply.future, effects);
    final pending = controller.syncVpnStateOnResume();
    await tester.pump();
    await controller.updateStatus(false);
    reply.complete(DateTime.now().subtract(const Duration(minutes: 1)));
    await pending;
    final committed = globalState.startTime;
    await tester.pump(const Duration(seconds: 6));
    final observedSamples = samples;
    globalState.stopUpdateTasks();
    controller.stopRunTimeTimer();
    expect(effects.stops, 1);
    expect(committed, isNull);
    expect(observedSamples, 0);
  });

  testWidgets('a current resume probe restores UI sampling without VPN actions',
      (tester) async {
    final started = DateTime.now().subtract(const Duration(minutes: 1));
    var samples = 0;
    globalState.tasks = [() => samples++];
    final effects = _StopEffects();
    final controller = await fixture(tester, () async => started, effects);
    await controller.syncVpnStateOnResume();
    await tester.pump(const Duration(seconds: 3));
    final observedSamples = samples;
    globalState.stopUpdateTasks();
    controller.stopRunTimeTimer();
    expect(globalState.startTime, started);
    expect(observedSamples, greaterThanOrEqualTo(2));
    expect(effects.stops, 0);
  });
}

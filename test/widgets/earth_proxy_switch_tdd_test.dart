import 'dart:math' as math;

import 'package:flclashx/common/common.dart';
import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/widgets/earth_proxy_switch.dart';
import 'package:flclashx/widgets/tactile_proxy_switch.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    EarthDockPositionStore.instance.resetForTest();
    await AppLocalizations.load(const Locale('zh', 'CN'));
    globalState.appState = AppState(
      viewSize: const Size(1200, 800),
      version: 1,
      requests: FixedList(1),
      logs: FixedList(1),
      traffics: FixedList(1),
      totalTraffic: Traffic(),
      isInit: true,
    );
    detectionState.state.value = const NetworkDetectionState(
      isLoading: false,
      isTesting: false,
      ipInfo: null,
    );
  });

  tearDown(() {
    EarthDockPositionStore.instance.resetForTest();
    detectionState.state.value = const NetworkDetectionState(
      isLoading: false,
      isTesting: false,
      ipInfo: null,
    );
  });

  Widget wrapDock({
    required Widget child,
    Size viewportSize = const Size(1200, 800),
    bool tickerEnabled = true,
  }) =>
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: viewportSize),
          child: TickerMode(
            enabled: tickerEnabled,
            child: Scaffold(body: Center(child: child)),
          ),
        ),
      );

  test(
    'computeFloatingEarthDiameter scales cleanly across desktop and narrow mobile panes',
    () {
      expect(
        computeFloatingEarthDiameter(
          viewportWidth: 1200,
          viewportHeight: 800,
        ),
        152.0,
      );
      expect(
        computeFloatingEarthDiameter(
          viewportWidth: 480,
          viewportHeight: 480,
        ),
        134.0,
      );
      expect(
        computeFloatingEarthDiameter(
          viewportWidth: 320,
          viewportHeight: 720,
        ),
        112.0,
      );
    },
  );

  testWidgets(
    'Naked circular silhouette: no stadium pill shell or static labels, corner taps pass through, edge feather absorbs stray taps, busy badge preserves stopping state',
    (tester) async {
      final semanticsHandle = tester.ensureSemantics();
      try {
        var underCornerTaps = 0;
        var underBezelTaps = 0;
        var toggleCount = 0;
        bool? pendingTarget;
        var isRunning = false;

        await tester.pumpWidget(
          wrapDock(
            child: StatefulBuilder(
              builder: (context, setState) => Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 152,
                    height: 152,
                    child: Stack(
                      children: [
                        Positioned(
                          left: 0,
                          top: 0,
                          child: GestureDetector(
                            key: const ValueKey('corner-underlay'),
                            behavior: HitTestBehavior.opaque,
                            onTap: () => underCornerTaps++,
                            child: const SizedBox(width: 24, height: 24),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          top: 64,
                          child: GestureDetector(
                            key: const ValueKey('bezel-underlay'),
                            behavior: HitTestBehavior.opaque,
                            onTap: () => underBezelTaps++,
                            child: const SizedBox(width: 24, height: 24),
                          ),
                        ),
                      ],
                    ),
                  ),
                  FloatingProxyDock(
                    key: const ValueKey('test-dock'),
                    switchKey: const ValueKey('test-earth-toggle'),
                    isRunning: isRunning,
                    pendingTarget: pendingTarget,
                    startCancelable: false,
                    onToggle: () => toggleCount++,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final dockFinder = find.byKey(const ValueKey('test-dock'));
        final toggleFinder = find.byKey(const ValueKey('test-earth-toggle'));
        final earthFinder = find.byType(EarthProxySwitch);
        expect(dockFinder, findsOneWidget);
        expect(toggleFinder, findsOneWidget);
        expect(earthFinder, findsOneWidget);

        // No dark capsule border or static pill captions in normal OFF/ON state.
        expect(
          find.descendant(of: dockFinder, matching: find.byType(DecoratedBox)),
          findsNothing,
        );
        expect(find.text('开启代理'), findsNothing);
        expect(find.text('运行中'), findsNothing);

        final rect = tester.getRect(dockFinder);
        expect(rect.width, closeTo(152.0, 1.0));
        expect(rect.height, closeTo(152.0, 1.0));

        expect(
          tester.getSemantics(toggleFinder),
          matchesSemantics(
            label: appLocalizations.nodeOverviewTurnOnProxy,
            isButton: true,
            isFocusable: true,
            hasToggledState: true,
            isToggled: false,
            hasEnabledState: true,
            isEnabled: true,
            hasTapAction: true,
            hasFocusAction: true,
          ),
        );

        // Tap outside the circular orb (top-left square corner): MUST pass through.
        await tester.tapAt(Offset(rect.left + 3.0, rect.top + 3.0));
        await tester.pump();
        expect(underCornerTaps, 1);
        expect(toggleCount, 0);

        // Tap inside the outer feather margin (2px inside left center, rNorm > 0.84):
        // MUST absorb tap (not leak underneath AND not toggle proxy).
        await tester.tapAt(Offset(rect.left + 2.0, rect.center.dy));
        await tester.pump();
        expect(underBezelTaps, 0);
        expect(toggleCount, 0);

        // Tap center of Earth: invokes onToggle immediately at 0ms.
        await tester.tap(toggleFinder);
        await tester.pump();
        expect(toggleCount, 1);

        // Busy pendingTarget renders compact status badge & retains visualActive during graceful stop.
        pendingTarget = false;
        isRunning = false;
        await tester.pumpWidget(
          wrapDock(
            child: FloatingProxyDock(
              key: const ValueKey('test-dock'),
              switchKey: const ValueKey('test-earth-toggle'),
              isRunning: isRunning,
              pendingTarget: pendingTarget,
              startCancelable: false,
              onToggle: () => toggleCount++,
            ),
          ),
        );
        await tester.pump();
        expect(find.text(appLocalizations.tunStatusStopping), findsOneWidget);
        final snapStopping = EarthProxySwitch.debugSnapshotOf(
          tester.element(earthFinder),
        )!;
        expect(snapStopping.visualActive, isTrue);

        pendingTarget = true;
        await tester.pumpWidget(
          wrapDock(
            child: FloatingProxyDock(
              key: const ValueKey('test-dock'),
              switchKey: const ValueKey('test-earth-toggle'),
              isRunning: false,
              pendingTarget: pendingTarget,
              startCancelable: false,
              onToggle: () => toggleCount++,
            ),
          ),
        );
        await tester.pump();
        expect(find.text(appLocalizations.tunStatusStarting), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      } finally {
        semanticsHandle.dispose();
      }
    },
  );

  testWidgets(
    'Connected Earth self-rotates continuously while OFF settles to 0fps and startup pending frames without spinning',
    (tester) async {
      // 1. Disconnected (OFF): stationary yaw and 0fps.
      await tester.pumpWidget(
        wrapDock(
          child: EarthProxySwitch(
            key: const ValueKey('earth-spin-off'),
            isRunning: false,
            pendingTarget: null,
            startCancelable: false,
            canPress: true,
            semanticsLabel: '开启代理',
            continuousAnimationInTests: true,
            onToggle: () {},
          ),
        ),
      );
      await tester.pump();
      final offFinder = find.byKey(const ValueKey('earth-spin-off'));
      final offYaw0 =
          EarthProxySwitch.debugSnapshotOf(tester.element(offFinder))!.yaw;
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final offSnap1 =
          EarthProxySwitch.debugSnapshotOf(tester.element(offFinder))!;
      expect(offSnap1.isTickerActive, isFalse);
      expect(offSnap1.yaw, closeTo(offYaw0, 1e-6));

      // 2. Startup pending (isRunning: false, pendingTarget: true): illuminates and frames without continuous spin.
      await tester.pumpWidget(
        wrapDock(
          child: EarthProxySwitch(
            key: const ValueKey('earth-spin-pending'),
            isRunning: false,
            pendingTarget: true,
            startCancelable: false,
            canPress: false,
            semanticsLabel: '正在启动...',
            continuousAnimationInTests: true,
            onToggle: () {},
          ),
        ),
      );
      await tester.pump();
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      final pendingFinder = find.byKey(const ValueKey('earth-spin-pending'));
      final pendingYaw1 =
          EarthProxySwitch.debugSnapshotOf(tester.element(pendingFinder))!.yaw;
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      final pendingYaw2 =
          EarthProxySwitch.debugSnapshotOf(tester.element(pendingFinder))!.yaw;
      final pendingDrift = math.atan2(
        math.sin(pendingYaw2 - pendingYaw1),
        math.cos(pendingYaw2 - pendingYaw1),
      );
      expect(
        pendingDrift.abs(),
        lessThan(0.12),
        reason: 'Connecting globe should frame the route rather than continuously spinning before connection succeeds',
      );

      // 3. Connected (isRunning: true): continuously self-rotates West-to-East across consecutive seconds.
      await tester.pumpWidget(
        wrapDock(
          child: EarthProxySwitch(
            key: const ValueKey('earth-spin-on'),
            isRunning: true,
            pendingTarget: null,
            startCancelable: false,
            canPress: true,
            semanticsLabel: '关闭代理',
            continuousAnimationInTests: true,
            onToggle: () {},
          ),
        ),
      );
      await tester.pump();
      final onFinder = find.byKey(const ValueKey('earth-spin-on'));
      final yaw0 =
          EarthProxySwitch.debugSnapshotOf(tester.element(onFinder))!.yaw;
      for (var i = 0; i < 32; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      final yaw1 =
          EarthProxySwitch.debugSnapshotOf(tester.element(onFinder))!.yaw;
      for (var i = 0; i < 32; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      final yaw2 =
          EarthProxySwitch.debugSnapshotOf(tester.element(onFinder))!.yaw;

      final delta1 = math.atan2(math.sin(yaw1 - yaw0), math.cos(yaw1 - yaw0));
      final delta2 = math.atan2(math.sin(yaw2 - yaw1), math.cos(yaw2 - yaw1));
      expect(delta1, greaterThan(0.30));
      expect(delta2, greaterThan(0.30));

      // Keyboard focus + Space still toggles connected globe.
      var keyboardToggled = 0;
      await tester.pumpWidget(
        wrapDock(
          child: EarthProxySwitch(
            key: const ValueKey('earth-spin-kbd'),
            isRunning: true,
            pendingTarget: null,
            startCancelable: false,
            canPress: true,
            semanticsLabel: '关闭代理',
            onToggle: () => keyboardToggled++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(keyboardToggled, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'FloatingProxyDockOverlay keeps undragged Earth bottom-centered across window resizes, supports free position dragging with clamping, and persists position across cold relaunch',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var toggleCount = 0;

      Widget buildHost({required double width, required double height}) {
        tester.view.physicalSize = Size(width, height);
        return MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: Size(width, height)),
            child: Scaffold(
              body: SizedBox(
                width: width,
                height: height,
                child: FloatingProxyDockOverlay(
                  key: const ValueKey('test-overlay'),
                  viewportWidth: width,
                  viewportHeight: height,
                  dock: FloatingProxyDock(
                    key: const ValueKey('overlay-dock'),
                    switchKey: const ValueKey('overlay-earth-toggle'),
                    isRunning: true,
                    pendingTarget: null,
                    startCancelable: false,
                    onToggle: () => toggleCount++,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        );
      }

      // 1. Undragged dock stays horizontally centered at bottom across narrow/wide resizes.
      for (final (width, height) in const [
        (1200.0, 800.0),
        (960.0, 800.0),
        (640.0, 800.0),
        (360.0, 720.0),
        (1440.0, 900.0),
      ]) {
        await tester.pumpWidget(buildHost(width: width, height: height));
        await tester.pumpAndSettle();

        final dockRect =
            tester.getRect(find.byKey(const ValueKey('overlay-dock')));
        expect(dockRect.center.dx, closeTo(width * 0.5, 0.5));
        expect(
          dockRect.bottom,
          closeTo(height - computeFloatingProxyDockBottomMargin(height), 0.5),
        );
      }

      // 2. Dragging >= 5px moves Earth freely on screen without triggering onToggle.
      await tester.pumpWidget(buildHost(width: 1200.0, height: 800.0));
      await tester.pumpAndSettle();
      final dockFinder = find.byKey(const ValueKey('overlay-dock'));
      final toggleFinder = find.byKey(const ValueKey('overlay-earth-toggle'));
      final beforeDragRect = tester.getRect(dockFinder);

      await tester.drag(toggleFinder, const Offset(-260, -320));
      await tester.pumpAndSettle();
      expect(
        toggleCount,
        0,
        reason: 'Dragging the Earth position must never trigger onToggle',
      );
      final draggedRect = tester.getRect(dockFinder);
      expect(draggedRect.left, closeTo(beforeDragRect.left - 260, 1.5));
      expect(draggedRect.top, closeTo(beforeDragRect.top - 320, 1.5));

      // 3. Single click (< 5px) at the new dragged location still triggers onToggle immediately.
      await tester.tap(toggleFinder);
      await tester.pump();
      expect(toggleCount, 1);

      // 4. Cold relaunch simulation: wipe in-memory store, reload from SharedPreferences, and verify frame-1 restoration.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      EarthDockPositionStore.instance.resetForTest();
      await EarthDockPositionStore.instance.ensureLoaded();

      await tester.pumpWidget(buildHost(width: 1200.0, height: 800.0));
      await tester.pump();
      final restoredRect = tester.getRect(dockFinder);
      expect(restoredRect.left, closeTo(draggedRect.left, 0.5));
      expect(restoredRect.top, closeTo(draggedRect.top, 0.5));

      // 5. Extreme drag clamps cleanly inside viewport edgeMargin.
      await tester.drag(toggleFinder, const Offset(-5000, -5000));
      await tester.pumpAndSettle();
      final clampedTopLeftRect = tester.getRect(dockFinder);
      expect(clampedTopLeftRect.left, closeTo(8.0, 0.5));
      expect(clampedTopLeftRect.top, closeTo(8.0, 0.5));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'Origin stays CN while dynamic exit IP country updates target and frames great-circle route with XYZ Euler math across HK/JP/SG/KR/US/DE/GB/AU',
    (tester) async {
      await tester.pumpWidget(
        wrapDock(
          child: EarthProxySwitch(
            key: const ValueKey('earth-geo'),
            isRunning: true,
            pendingTarget: null,
            startCancelable: false,
            canPress: true,
            semanticsLabel: '关闭代理',
            fallbackCountryCode: 'HK',
            onToggle: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final earthFinder = find.byKey(const ValueKey('earth-geo'));

      // 1. Null ipInfo or stale CN ipInfo while ON falls back to node country ('HK').
      detectionState.state.value = const NetworkDetectionState(
        isLoading: true,
        isTesting: false,
        ipInfo: IpInfo(ip: '114.114.114.114', countryCode: 'CN'),
      );
      await tester.pumpAndSettle();
      final fallbackSnap =
          EarthProxySwitch.debugSnapshotOf(tester.element(earthFinder))!;
      expect(fallbackSnap.originCountryCode, kEarthOriginCountryCode);
      expect(fallbackSnap.targetCountryCode, 'HK');

      // 2. Live exit IPs across 8 representative countries frame mid(CN, target) forward (+Z).
      final vStart = latLonToUnitVec3(kEarthOriginLon, kEarthOriginLat);
      for (final code in const [
        'HK',
        'JP',
        'SG',
        'KR',
        'US',
        'DE',
        'GB',
        'AU',
      ]) {
        detectionState.state.value = NetworkDetectionState(
          isLoading: false,
          isTesting: false,
          ipInfo: IpInfo(ip: '198.51.100.1', countryCode: code),
        );
        await tester.pumpAndSettle();

        final snap =
            EarthProxySwitch.debugSnapshotOf(tester.element(earthFinder))!;
        expect(snap.originCountryCode, 'CN');
        expect(snap.targetCountryCode, code);

        final coord = kEarthCountryCentroids[code]!;
        final vEnd = latLonToUnitVec3(coord.lon, coord.lat);
        final vMid = (vStart + vEnd).normalized();

        final worldMid = transformByEulerXYZ(vMid, snap.pitch, snap.yaw);
        final worldStart = transformByEulerXYZ(vStart, snap.pitch, snap.yaw);
        final worldEnd = transformByEulerXYZ(vEnd, snap.pitch, snap.yaw);

        expect(
          worldMid.z,
          greaterThan(0.88),
          reason: '$code great-circle midpoint must face camera',
        );
        expect(
          worldMid.x.abs(),
          lessThan(0.08),
          reason: '$code midpoint must stay horizontally centered',
        );
        expect(
          worldStart.z,
          greaterThan(0.35),
          reason: '$code origin CN must stay on front hemisphere',
        );
        expect(
          worldEnd.z,
          greaterThan(0.35),
          reason: '$code target must stay on front hemisphere',
        );
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'Performance & power gates: 0 fps when OFF, 0 fps when TickerMode disabled or app hidden, single shared GPU texture rasterization, and 30fps steady throttling',
    (tester) async {
      // 1. Mount 2 Earth switches across OFF/ON and assert shared texture cache rasterizes once.
      await tester.pumpWidget(
        wrapDock(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              EarthProxySwitch(
                key: const ValueKey('perf-earth-a'),
                isRunning: false,
                pendingTarget: null,
                startCancelable: false,
                canPress: true,
                semanticsLabel: '开启代理',
                onToggle: () {},
              ),
              EarthProxySwitch(
                key: const ValueKey('perf-earth-b'),
                isRunning: false,
                pendingTarget: null,
                startCancelable: false,
                canPress: true,
                semanticsLabel: '开启代理',
                onToggle: () {},
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(EarthProxySwitch.debugSharedTextureRasterizeCount, 1);

      final earthA = find.byKey(const ValueKey('perf-earth-a'));
      final offSnap =
          EarthProxySwitch.debugSnapshotOf(tester.element(earthA))!;
      expect(offSnap.isTickerActive, isFalse);
      final offPaintBaseline = offSnap.paintCount;

      // Advance 5s in settled OFF state -> 0 repaints.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(
        EarthProxySwitch.debugSnapshotOf(tester.element(earthA))!.paintCount,
        offPaintBaseline,
      );

      // 2. Active continuous ON animation throttles steady state (~30fps) & triggers ripples.
      await tester.pumpWidget(
        wrapDock(
          tickerEnabled: true,
          child: EarthProxySwitch(
            key: const ValueKey('perf-earth-on'),
            isRunning: true,
            pendingTarget: null,
            startCancelable: false,
            canPress: true,
            semanticsLabel: '关闭代理',
            continuousAnimationInTests: true,
            onToggle: () {},
          ),
        ),
      );
      await tester.pump();
      // Advance 800ms to exit initial camera convergence / sweep transition into steady state.
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final earthOn = find.byKey(const ValueKey('perf-earth-on'));
      final beforeWindowSnap =
          EarthProxySwitch.debugSnapshotOf(tester.element(earthOn))!;
      expect(beforeWindowSnap.isTickerActive, isTrue);
      final paintsAtStart = beforeWindowSnap.paintCount;

      // Pump 60 vsync ticks of 16ms (= 960ms ~ 1s); 30fps gate limits repaints well below 42.
      var sawRipple = false;
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final s = EarthProxySwitch.debugSnapshotOf(tester.element(earthOn))!;
        if (s.targetRipple > 0.05) {
          sawRipple = true;
        }
      }
      final afterWindowSnap =
          EarthProxySwitch.debugSnapshotOf(tester.element(earthOn))!;
      final deltaPaints = afterWindowSnap.paintCount - paintsAtStart;
      expect(deltaPaints, greaterThan(15));
      expect(
        deltaPaints,
        lessThanOrEqualTo(38),
        reason: 'Steady-state ON globe must throttle to ~30fps instead of 60fps',
      );
      expect(
        sawRipple,
        isTrue,
        reason: 'Streaming particles must periodically trigger landing ripples',
      );

      // 3. TickerMode(enabled: false) pauses ticker completely (0 repaints).
      await tester.pumpWidget(
        wrapDock(
          tickerEnabled: false,
          child: EarthProxySwitch(
            key: const ValueKey('perf-earth-on'),
            isRunning: true,
            pendingTarget: null,
            startCancelable: false,
            canPress: true,
            semanticsLabel: '关闭代理',
            continuousAnimationInTests: true,
            onToggle: () {},
          ),
        ),
      );
      await tester.pump();
      final mutedSnap =
          EarthProxySwitch.debugSnapshotOf(tester.element(earthOn))!;
      expect(mutedSnap.isTickerActive, isFalse);
      final mutedPaints = mutedSnap.paintCount;
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        EarthProxySwitch.debugSnapshotOf(tester.element(earthOn))!.paintCount,
        mutedPaints,
      );

      // 4. AppLifecycleState.hidden / paused pauses active ticker; resumed restarts it.
      await tester.pumpWidget(
        wrapDock(
          tickerEnabled: true,
          child: EarthProxySwitch(
            key: const ValueKey('perf-earth-on'),
            isRunning: true,
            pendingTarget: null,
            startCancelable: false,
            canPress: true,
            semanticsLabel: '关闭代理',
            continuousAnimationInTests: true,
            onToggle: () {},
          ),
        ),
      );
      await tester.pump();
      expect(
        EarthProxySwitch.debugSnapshotOf(tester.element(earthOn))!
            .isTickerActive,
        isTrue,
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      final hiddenSnap =
          EarthProxySwitch.debugSnapshotOf(tester.element(earthOn))!;
      expect(hiddenSnap.isTickerActive, isFalse);
      final hiddenPaints = hiddenSnap.paintCount;
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        EarthProxySwitch.debugSnapshotOf(tester.element(earthOn))!.paintCount,
        hiddenPaints,
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(
        EarthProxySwitch.debugSnapshotOf(tester.element(earthOn))!
            .isTickerActive,
        isTrue,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}

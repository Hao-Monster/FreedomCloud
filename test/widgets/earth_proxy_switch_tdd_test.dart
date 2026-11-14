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

void main() {
  setUp(() async {
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
    '3D mouse drag rotates Earth without toggling proxy, auto-recovers after 1.8s when ON, and supports keyboard activation',
    (tester) async {
      var toggleCount = 0;

      await tester.pumpWidget(
        wrapDock(
          child: EarthProxySwitch(
            key: const ValueKey('earth-drag'),
            isRunning: true,
            pendingTarget: null,
            startCancelable: false,
            canPress: true,
            semanticsLabel: '关闭代理',
            onToggle: () => toggleCount++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final earthFinder = find.byKey(const ValueKey('earth-drag'));
      final initialSnap =
          EarthProxySwitch.debugSnapshotOf(tester.element(earthFinder))!;
      expect(toggleCount, 0);

      await tester.drag(earthFinder, const Offset(80, -24));
      await tester.pump();

      final draggedSnap =
          EarthProxySwitch.debugSnapshotOf(tester.element(earthFinder))!;
      expect(
        toggleCount,
        0,
        reason: 'Dragging the 3D globe must never toggle proxy state',
      );
      expect(
        (draggedSnap.yaw - initialSnap.yaw).abs(),
        greaterThan(0.25),
      );

      // Hold gently, then glide back once 1.8s post-drag cooldown elapses.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pumpAndSettle();

      final recoveredSnap =
          EarthProxySwitch.debugSnapshotOf(tester.element(earthFinder))!;
      final yawDiff = math.atan2(
        math.sin(recoveredSnap.yaw - initialSnap.yaw),
        math.cos(recoveredSnap.yaw - initialSnap.yaw),
      );
      expect(yawDiff.abs(), lessThan(0.12));

      // Keyboard focus + Space triggers onToggle without requiring pointer click.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(toggleCount, 1);

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

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flclashx/common/process_icon.dart';
import 'package:flclashx/common/process_icon_activity.dart';
import 'package:flclashx/views/connection/item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

late Uint8List _png;

class ObservedActivity extends ValueNotifier<bool> {
  ObservedActivity(super.value);

  bool get subscribed => hasListeners;
}

MemoryImage iconImage() => MemoryImage(Uint8List.fromList(_png));

Widget host(Widget child) => MaterialApp(
      home: SingleChildScrollView(child: child),
    );

Future<void> pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  expect(condition(), isTrue,
      reason: 'Icon work did not settle within 200 turns');
  await tester.pump(const Duration(milliseconds: 1));
}

Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(Uint8List.fromList([0, 0, 255, 255]), 1, 1,
        ui.PixelFormat.bgra8888, completer.complete);
    final image = await completer.future;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      _png = data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  });

  testWidgets('unmount cancels queued icons behind a blocked extraction',
      (tester) async {
    final first = Completer<ImageProvider?>();
    var calls = 0;
    final loader = WindowsProcessIconLoader(load: (_) async {
      calls++;
      return calls == 1 ? first.future : null;
    });
    addTearDown(loader.dispose);

    await tester.pumpWidget(MaterialApp(
      home: SingleChildScrollView(
        child: Column(children: [
          for (var i = 0; i < 80; i++)
            ProcessIcon.forTestingWindows(
              process: 'app$i',
              processPath: 'C:/qa/app$i.exe',
              loader: loader,
              size: 8,
            ),
        ]),
      ),
    ));
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    first.complete(null);
    for (var i = 0; i < 85; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(calls, 1, reason: 'No queued icon has a remaining mounted consumer');
    expect(tester.takeException(), isNull);
  });

  testWidgets('66 visible icons recover capacity without parent rebuild',
      (tester) async {
    final first = Completer<ImageProvider?>();
    final calls = <String>[];
    final image = iconImage();
    final loader = WindowsProcessIconLoader(load: (path) async {
      calls.add(path);
      return calls.length == 1 ? first.future : image;
    });
    addTearDown(loader.dispose);
    Widget icons() => host(Column(children: [
          for (var i = 0; i < 66; i++)
            ProcessIcon.forTestingWindows(
              key: ValueKey(i),
              process: '$i',
              processPath: 'C:/qa/$i.exe',
              loader: loader,
              size: 8,
            ),
        ]));
    await tester.pumpWidget(icons());
    // Rebuilds while waiting must not add leases or requests for the same path.
    for (var i = 0; i < 5; i++) {
      await tester.pumpWidget(icons());
    }
    expect(calls, ['C:/qa/0.exe']);
    first.complete(image);
    await pumpUntil(tester, () => find.byType(Image).evaluate().length == 66);
    expect(calls, [for (var i = 0; i < 66; i++) 'C:/qa/$i.exe']);
    expect(find.byIcon(Icons.apps_rounded), findsNothing);
    await unmount(tester);
  });

  testWidgets('equivalent Windows paths share one native request',
      (tester) async {
    final first = Completer<ImageProvider?>();
    final calls = <String>[];
    final loader = WindowsProcessIconLoader(load: (path) {
      calls.add(path);
      return first.future;
    });
    addTearDown(loader.dispose);
    await tester.pumpWidget(host(Row(children: [
      ProcessIcon.forTestingWindows(
        process: 'app',
        processPath: r'  \\server\Share\APP.exe  ',
        loader: loader,
      ),
      ProcessIcon.forTestingWindows(
        process: 'app',
        processPath: '//server/share/app.exe',
        loader: loader,
      ),
    ])));
    expect(calls, [r'\\server\Share\APP.exe'],
        reason:
            'Normalization deduplicates keys but preserves the native path');
    first.complete(iconImage());
    await pumpUntil(tester, () => find.byType(Image).evaluate().length == 2);
    expect(calls, hasLength(1));
    await unmount(tester);
  });

  testWidgets('UNC and current-drive-rooted paths load different icons',
      (tester) async {
    const uncPath = r'\\server\share\APP.exe';
    const rootedPath = r'\server\share\APP.exe';
    final calls = <String>[];
    final uncImage = iconImage();
    final rootedImage = iconImage();
    final loader = WindowsProcessIconLoader(load: (path) async {
      calls.add(path);
      return path == uncPath ? uncImage : rootedImage;
    });
    addTearDown(loader.dispose);
    await tester.pumpWidget(host(Row(children: [
      ProcessIcon.forTestingWindows(
        process: 'unc',
        processPath: uncPath,
        loader: loader,
      ),
      ProcessIcon.forTestingWindows(
        process: 'rooted',
        processPath: rootedPath,
        loader: loader,
      ),
    ])));
    await pumpUntil(tester, () => find.byType(Image).evaluate().length == 2);
    expect(calls, [uncPath, rootedPath],
        reason: 'A network share and a current-drive path are different files');
    expect(
        tester
            .widgetList<Image>(find.byType(Image))
            .map((image) => image.image),
        [uncImage, rootedImage]);
    await unmount(tester);
  });

  for (final throwsError in [false, true]) {
    testWidgets(
        'failed icon stays stable on rebuild and retries after re-entry '
        '(throws=$throwsError)', (tester) async {
      var attempts = 0;
      final image = iconImage();
      final loader = WindowsProcessIconLoader(load: (_) async {
        attempts++;
        if (attempts == 1) {
          if (throwsError) throw StateError('fixture extraction failure');
          return null;
        }
        return image;
      });
      addTearDown(loader.dispose);
      Widget icon({double size = 44}) => host(ProcessIcon.forTestingWindows(
            process: 'retry',
            processPath: 'C:/qa/retry.exe',
            loader: loader,
            size: size,
          ));
      await tester.pumpWidget(icon());
      await tester.pumpAndSettle();
      for (var i = 0; i < 5; i++) {
        await tester.pumpWidget(icon(size: 40.0 + i));
      }
      expect(attempts, 1);
      expect(find.byIcon(Icons.apps_rounded), findsOneWidget);
      await unmount(tester);
      await tester.pumpWidget(icon());
      await pumpUntil(tester, () => find.byType(Image).evaluate().isNotEmpty);
      expect(attempts, 2);
      expect(tester.widget<Image>(find.byType(Image)).image, image);
      await unmount(tester);
    });
  }

  testWidgets('changing A to B ignores the late A result', (tester) async {
    final old = Completer<ImageProvider?>();
    final calls = <String>[];
    final imageA = iconImage();
    final imageB = iconImage();
    final loader = WindowsProcessIconLoader(load: (path) async {
      calls.add(path);
      return path.endsWith('a.exe') ? old.future : imageB;
    });
    addTearDown(loader.dispose);
    Widget icon(String path) => host(ProcessIcon.forTestingWindows(
          key: const ValueKey('reused-row'),
          process: 'app',
          processPath: path,
          loader: loader,
        ));
    await tester.pumpWidget(icon('C:/qa/a.exe'));
    await tester.pumpWidget(icon('C:/qa/b.exe'));
    expect(calls, ['C:/qa/a.exe']);
    old.complete(imageA);
    await pumpUntil(tester, () => find.byType(Image).evaluate().isNotEmpty);
    expect(calls, ['C:/qa/a.exe', 'C:/qa/b.exe']);
    expect(tester.widget<Image>(find.byType(Image)).image, imageB);
    await unmount(tester);
  });

  testWidgets('disable cancels queued work and enabling retries',
      (tester) async {
    final first = Completer<ImageProvider?>();
    final calls = <String>[];
    final image = iconImage();
    final loader = WindowsProcessIconLoader(load: (path) async {
      calls.add(path);
      return path.endsWith('first.exe') ? first.future : image;
    });
    addTearDown(loader.dispose);
    final blocker = loader.acquire('C:/qa/first.exe')!;
    Widget icon(bool enabled) => host(ProcessIcon.forTestingWindows(
          process: 'queued',
          processPath: 'C:/qa/queued.exe',
          enabled: enabled,
          loader: loader,
        ));
    await tester.pumpWidget(icon(true));
    await tester.pumpWidget(icon(false));
    blocker.release();
    first.complete(null);
    await tester.pumpAndSettle();
    expect(calls, ['C:/qa/first.exe']);
    await tester.pumpWidget(icon(true));
    await pumpUntil(tester, () => find.byType(Image).evaluate().isNotEmpty);
    expect(calls, ['C:/qa/first.exe', 'C:/qa/queued.exe']);
    await unmount(tester);
  });

  for (final windowSignal in [false, true]) {
    testWidgets(
        'kept mounted icons cancel and resume using '
        '${windowSignal ? 'window activity without a page scope' : 'page scope'}',
        (tester) async {
      final page = ObservedActivity(true);
      final window = ObservedActivity(true);
      final first = Completer<ImageProvider?>();
      final calls = <String>[];
      final image = iconImage();
      final loader = WindowsProcessIconLoader(load: (path) async {
        calls.add(path);
        return calls.length == 1 ? first.future : image;
      });
      addTearDown(loader.dispose);
      addTearDown(page.dispose);
      addTearDown(window.dispose);
      final icons = Column(children: [
        for (final name in ['first', 'queued'])
          ProcessIcon.forTestingWindows(
            key: ValueKey(name),
            process: name,
            processPath: 'C:/qa/$name.exe',
            loader: loader,
            windowActivity: window,
          ),
      ]);
      await tester.pumpWidget(host(windowSignal
          ? icons
          : ProcessIconActivityScope(activity: page, child: icons)));
      final signal = windowSignal ? window : page;
      signal.value = false;
      await tester.pump();
      expect(find.byType(ProcessIcon), findsNWidgets(2),
          reason: 'This must exercise keep-alive, not unmount cancellation');
      first.complete(image);
      await tester.pumpAndSettle();
      expect(calls, ['C:/qa/first.exe']);
      expect(find.byType(Image), findsNothing);
      signal.value = true;
      await pumpUntil(tester, () => find.byType(Image).evaluate().length == 2);
      // Inherited dependencies may resume in either order; each visible icon
      // must be requested exactly once after reactivation.
      expect(calls.skip(1),
          unorderedEquals(['C:/qa/first.exe', 'C:/qa/queued.exe']));
      final completedCalls = List<String>.of(calls);
      await unmount(tester);
      expect(window.subscribed, isFalse);
      expect(page.subscribed, isFalse);
      window.value = false;
      page.value = false;
      window.value = true;
      page.value = true;
      await tester.pumpAndSettle();
      expect(calls, completedCalls,
          reason:
              'Unmounted consumers must not resubscribe on activity changes');
    });
  }

  testWidgets('page and window activity must both allow admission',
      (tester) async {
    final page = ValueNotifier(false);
    final window = ValueNotifier(false);
    var calls = 0;
    final image = iconImage();
    final loader = WindowsProcessIconLoader(load: (_) async {
      calls++;
      return image;
    });
    addTearDown(loader.dispose);
    addTearDown(page.dispose);
    addTearDown(window.dispose);
    await tester.pumpWidget(host(ProcessIconActivityScope(
      activity: page,
      child: ProcessIcon.forTestingWindows(
        process: 'app',
        processPath: 'C:/qa/app.exe',
        loader: loader,
        windowActivity: window,
      ),
    )));
    window.value = true;
    await tester.pump();
    expect(calls, 0);
    page.value = true;
    await pumpUntil(tester, () => find.byType(Image).evaluate().isNotEmpty);
    expect(calls, 1);
    await unmount(tester);
  });
}

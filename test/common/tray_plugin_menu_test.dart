import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tray_manager/tray_manager.dart';

class _MenuListener with TrayListener {
  final clicks = <MenuItem>[];

  @override
  void onTrayMenuItemClick(MenuItem item) => clicks.add(item);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('tray_manager');
  late _MenuListener listener;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    listener = _MenuListener();
    trayManager.addListener(listener);
  });

  tearDown(() {
    trayManager.removeListener(listener);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('Windows popup dispatches its displayed menu after multiple updates',
      () async {
    var originalClicks = 0;
    var newClicks = 0;
    final original =
        MenuItem(label: 'original', onClick: (_) => originalClicks++);
    final replacement = MenuItem(label: 'new', onClick: (_) => newClicks++);
    final entered = Completer<void>();
    final selected = Completer<int>();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'popUpContextMenu') {
        entered.complete();
        return selected.future;
      }
      return null;
    });
    await trayManager.setContextMenu(Menu(items: [original]));
    final popup = trayManager.popUpContextMenu();
    await entered.future;
    await trayManager.setContextMenu(Menu(items: [replacement]));
    await trayManager.setContextMenu(Menu(items: [MenuItem(label: 'latest')]));
    selected.complete(original.id);
    await popup;
    expect(originalClicks, 1);
    expect(newClicks, 0);
    expect(listener.clicks, [original]);
  });

  test('failed native replacement preserves the successful menu action map',
      () async {
    var originalClicks = 0;
    var failReplacement = false;
    final original =
        MenuItem(label: 'original', onClick: (_) => originalClicks++);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'setContextMenu' && failReplacement) {
        throw PlatformException(code: 'menu_creation_failed');
      }
      if (call.method == 'popUpContextMenu') return original.id;
      return null;
    });
    await trayManager.setContextMenu(Menu(items: [original]));
    failReplacement = true;
    await expectLater(
      trayManager.setContextMenu(Menu(items: [MenuItem(label: 'failed')])),
      throwsA(isA<PlatformException>()),
    );
    await trayManager.popUpContextMenu();
    expect(originalClicks, 1);
    expect(listener.clicks, [original]);
  });

  test('popup waits for an in-flight setter and setter ordering stays FIFO',
      () async {
    var firstClicks = 0;
    final first = MenuItem(label: 'first', onClick: (_) => firstClicks++);
    final second = MenuItem(label: 'second');
    final setterEntered = Completer<void>();
    final releaseSetter = Completer<void>();
    final popupEntered = Completer<void>();
    final releasePopup = Completer<int>();
    final calls = <String>[];
    var setters = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call.method);
      if (call.method == 'setContextMenu' && ++setters == 1) {
        setterEntered.complete();
        await releaseSetter.future;
      }
      if (call.method == 'popUpContextMenu') {
        popupEntered.complete();
        return releasePopup.future;
      }
      return null;
    });
    final setter = trayManager.setContextMenu(Menu(items: [first]));
    await setterEntered.future;
    final popup = trayManager.popUpContextMenu();
    final nextSetter = trayManager.setContextMenu(Menu(items: [second]));
    try {
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['setContextMenu']);
    } finally {
      releaseSetter.complete();
      await setter;
      await popupEntered.future;
      await nextSetter;
      releasePopup.complete(first.id);
      await popup;
    }
    expect(calls, ['setContextMenu', 'popUpContextMenu', 'setContextMenu']);
    expect(firstClicks, 1);
  });

  test('second Windows popup is rejected and a cancelled popup recovers',
      () async {
    final entered = Completer<void>();
    final release = Completer<int>();
    var popups = 0;
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
    await trayManager.setContextMenu(Menu(items: [MenuItem(label: 'menu')]));
    final first = trayManager.popUpContextMenu();
    await entered.future;
    try {
      await expectLater(
        trayManager.popUpContextMenu(),
        throwsA(isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'menu_unavailable',
        )),
      );
    } finally {
      release.complete(0);
      await first;
    }
    await trayManager.popUpContextMenu();
    expect(popups, 2);
    expect(listener.clicks, isEmpty);
  });

  test('failed popup resets the guard and allows a subsequent popup', () async {
    var popups = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'popUpContextMenu' && ++popups == 1) {
        throw PlatformException(code: 'menu_unavailable');
      }
      return 0;
    });
    await trayManager.setContextMenu(Menu(items: [MenuItem(label: 'menu')]));
    await expectLater(
        trayManager.popUpContextMenu(), throwsA(isA<PlatformException>()));
    await trayManager.popUpContextMenu();
    expect(popups, 2);
  });

  test('popup guard is set before waiting for an in-flight setter', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    var popups = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'setContextMenu') {
        entered.complete();
        await release.future;
      }
      if (call.method == 'popUpContextMenu') popups++;
      return 0;
    });
    final setter =
        trayManager.setContextMenu(Menu(items: [MenuItem(label: 'new')]));
    await entered.future;
    final first = trayManager.popUpContextMenu();
    try {
      await expectLater(
          trayManager.popUpContextMenu(), throwsA(isA<PlatformException>()));
      expect(popups, 0);
    } finally {
      release.complete();
      await setter;
      await first;
    }
    expect(popups, 1);
  });

  test('old checkbox action cannot overwrite a newer accepted menu', () async {
    final original = MenuItem.checkbox(label: 'original', checked: false)
      ..onClick = (item) => item.checked = true;
    final newer = MenuItem(label: 'newer');
    final entered = Completer<void>();
    final release = Completer<int>();
    var setters = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'setContextMenu') setters++;
      if (call.method == 'popUpContextMenu') {
        entered.complete();
        return release.future;
      }
      return null;
    });
    await trayManager.setContextMenu(Menu(items: [original]));
    final popup = trayManager.popUpContextMenu();
    await entered.future;
    await trayManager.setContextMenu(Menu(items: [newer]));
    release.complete(original.id);
    await popup;
    expect(original.checked, isTrue);
    expect(setters, 2);
    expect(listener.clicks, [original]);
  });

  test('old checkbox cannot supersede a requested setter still in flight',
      () async {
    final original = MenuItem.checkbox(label: 'original', checked: false)
      ..onClick = (item) => item.checked = true;
    final popupEntered = Completer<void>();
    final select = Completer<int>();
    final setterEntered = Completer<void>();
    final releaseSetter = Completer<void>();
    var setters = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'setContextMenu' && ++setters == 2) {
        setterEntered.complete();
        await releaseSetter.future;
      }
      if (call.method == 'popUpContextMenu') {
        popupEntered.complete();
        return select.future;
      }
      return null;
    });
    await trayManager.setContextMenu(Menu(items: [original]));
    final popup = trayManager.popUpContextMenu();
    await popupEntered.future;
    final pending =
        trayManager.setContextMenu(Menu(items: [MenuItem(label: 'new')]));
    await setterEntered.future;
    try {
      select.complete(original.id);
      await popup;
      expect(original.checked, isTrue);
      expect(setters, 2);
    } finally {
      releaseSetter.complete();
      await pending;
    }
  });

  test('non-Windows keeps legacy native event callback delivery', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    var clicks = 0;
    final item = MenuItem(label: 'legacy', onClick: (_) => clicks++);
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    await trayManager.setContextMenu(Menu(items: [item]));
    await trayManager.popUpContextMenu();
    final delivered = Completer<void>();
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('onTrayMenuItemClick', {'id': item.id}),
      ),
      (_) => delivered.complete(),
    );
    await delivered.future;
    expect(clicks, 1);
    expect(listener.clicks, [item]);
  });

  test(
      'legacy checkbox callback refreshes the latest replaced menu per listener',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final replacementItem = MenuItem(label: 'replacement');
    final replacement = Menu(items: [replacementItem]);
    final original = MenuItem.checkbox(label: 'original', checked: false)
      ..onClick = (item) {
        unawaited(trayManager.setContextMenu(replacement));
        item.checked = true;
      };
    final submittedIds = <int>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'setContextMenu') {
        final menu = (call.arguments as Map)['menu'] as Map;
        submittedIds.add(((menu['items'] as List).single as Map)['id'] as int);
      }
      return null;
    });
    await trayManager.setContextMenu(Menu(items: [original]));
    final secondListener = _MenuListener();
    trayManager.addListener(secondListener);
    try {
      final delivered = Completer<void>();
      await binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('onTrayMenuItemClick', {'id': original.id}),
        ),
        (_) => delivered.complete(),
      );
      await delivered.future;
      expect(
          submittedIds, [original.id, replacementItem.id, replacementItem.id]);
      expect(listener.clicks, [original]);
      expect(secondListener.clicks, isEmpty);
    } finally {
      trayManager.removeListener(secondListener);
    }
  });
}

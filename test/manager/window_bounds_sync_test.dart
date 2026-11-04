import 'dart:io';

import 'package:flclashx/common/common.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/manager/window_manager.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/config.dart';
import 'package:flclashx/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.root);
  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;

  @override
  Future<String?> getDownloadsPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final originalPaths = PathProviderPlatform.instance;
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('flclashx-window-bounds-');
    PathProviderPlatform.instance = _TestPaths(tempDir.path);
  });

  tearDownAll(() {
    PathProviderPlatform.instance = originalPaths;
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  const windowChannel = MethodChannel('window_manager');
  const windowExtChannel = MethodChannel('window_ext');

  var currentBounds = const <String, double>{
    'x': 200.0,
    'y': 150.0,
    'width': 1024.0,
    'height': 720.0,
  };
  var minimized = false;
  var maximized = false;
  var fullScreen = false;

  Future<void> emitWindowEvent(String eventName) async {
    const codec = StandardMethodCodec();
    final encoded = codec.encodeMethodCall(
      MethodCall('onEvent', <String, dynamic>{'eventName': eventName}),
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage('window_manager', encoded, (_) {});
  }

  setUp(() {
    currentBounds = const <String, double>{
      'x': 200.0,
      'y': 150.0,
      'width': 1024.0,
      'height': 720.0,
    };
    minimized = false;
    maximized = false;
    fullScreen = false;

    globalState.config = const Config(
      themeProps: defaultThemeProps,
      windowProps: WindowProps(
        width: 1024,
        height: 720,
        left: 200,
        top: 150,
      ),
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowExtChannel, (call) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowChannel, (call) async {
      switch (call.method) {
        case 'getBounds':
          return currentBounds;
        case 'isMinimized':
          return minimized;
        case 'isMaximized':
          return maximized;
        case 'isFullScreen':
          return fullScreen;
        default:
          return false;
      }
    });
  });

  tearDown(() {
    debouncer.cancel(FunctionTag.windowBounds);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowExtChannel, null);
  });

  testWidgets(
      'minimizing or maximizing window never overwrites saved normal window bounds',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: WindowManager(
            child: SizedBox.shrink(),
          ),
        ),
      ),
    );

    // 1. Normal user move/resize updates saved bounds after 250ms debounce.
    currentBounds = const <String, double>{
      'x': 260.0,
      'y': 180.0,
      'width': 1100.0,
      'height': 760.0,
    };
    await emitWindowEvent('moved');
    await emitWindowEvent('resized');
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      container.read(windowSettingProvider),
      const WindowProps(
        width: 1100,
        height: 760,
        left: 260,
        top: 180,
      ),
    );

    // 2. Win32 minimize sequence sends WM_MOVE (-32000, -32000) + WM_SIZE (160x28)
    // alongside minimize notification. Normal bounds MUST NOT be overwritten!
    minimized = true;
    currentBounds = const <String, double>{
      'x': -32000.0,
      'y': -32000.0,
      'width': 160.0,
      'height': 28.0,
    };
    await emitWindowEvent('moved');
    await emitWindowEvent('resized');
    await emitWindowEvent('minimize');
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      container.read(windowSettingProvider),
      const WindowProps(
        width: 1100,
        height: 760,
        left: 260,
        top: 180,
      ),
    );

    // 3. Restore and then maximize: Win32 sends monitor bounds (-8, -8, 2560x1440).
    // Normal bounds MUST remain preserved!
    minimized = false;
    await emitWindowEvent('restore');
    maximized = true;
    currentBounds = const <String, double>{
      'x': -8.0,
      'y': -8.0,
      'width': 2560.0,
      'height': 1440.0,
    };
    await emitWindowEvent('maximize');
    await emitWindowEvent('moved');
    await emitWindowEvent('resized');
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      container.read(windowSettingProvider),
      const WindowProps(
        width: 1100,
        height: 760,
        left: 260,
        top: 180,
      ),
    );
  });
}

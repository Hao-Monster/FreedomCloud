import 'package:flclashx/common/tun_runtime.dart';
import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/widgets/tun_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() async {
    await AppLocalizations.load(const Locale('zh', 'CN'));
  });

  Future<void> show(WidgetTester tester, TunRuntimeController runtime,
          void Function(bool) change) =>
      tester.pumpWidget(MaterialApp(
          home: Material(
              child: AnimatedBuilder(
                  animation: runtime,
                  builder: (_, __) => Column(children: [
                        Text(tunStatusLabel(runtime)),
                        TunStatusSwitch(runtime: runtime, onChanged: change),
                      ])))));

  testWidgets('saved enabled preference does not check an unknown switch',
      (tester) async {
    final runtime = TunRuntimeController()..desiredEnabled = true;
    await show(tester, runtime, (_) {});
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(find.text('状态未知'), findsOneWidget);
  });
  testWidgets('pending enable can be cancelled while the proxy is stopped',
      (tester) async {
    final runtime = TunRuntimeController()..desiredEnabled = true;
    runtime.accept(
        const TunStatus(
            instanceId: 'one',
            revision: 1,
            state: 'off',
            listenerActive: false,
            interfaceState: 'missing',
            privilege: 'elevated',
            requestedEnabled: false),
        0);
    bool? requested;
    await show(tester, runtime, (value) {
      requested = value;
    });
    await tester.tap(find.byTooltip('请求关闭'));
    expect(requested, isFalse);
  });
  testWidgets('failed start remains off and a new click requests enable',
      (tester) async {
    final runtime = TunRuntimeController();
    runtime.accept(
        const TunStatus(
            instanceId: 'one',
            revision: 1,
            state: 'failed',
            listenerActive: false,
            interfaceState: 'missing',
            privilege: 'unprivileged',
            requestedEnabled: true,
            errorCode: 'permissionDenied'),
        0);
    bool? requested;
    await show(tester, runtime, (value) {
      requested = value;
    });
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(find.textContaining('管理员授权'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    expect(requested, isTrue);
  });
  testWidgets('failed close stays checked and loss revokes checked state',
      (tester) async {
    final runtime = TunRuntimeController();
    runtime.accept(
        const TunStatus(
            instanceId: 'one',
            revision: 1,
            state: 'failed',
            listenerActive: true,
            interfaceState: 'up',
            privilege: 'elevated',
            requestedEnabled: false,
            errorCode: 'closeFailed'),
        0);
    await show(tester, runtime, (_) {});
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    runtime.invalidate('statusUnavailable');
    await tester.pump();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(find.textContaining('无法确认状态'), findsOneWidget);
  });
}

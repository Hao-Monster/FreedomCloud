import 'package:flclashx/clash/interface.dart';
import 'package:flutter_test/flutter_test.dart';

class SilentTransport extends ClashHandlerInterface {
  @override
  void sendMessage(String message) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('getTunStatus has a three second bound when Core never replies',
      (tester) async {
    final transport = SilentTransport();
    final checked = expectLater(transport.getTunStatus(), throwsException);
    await tester.pump(const Duration(seconds: 3));
    await checked;
    // The IPC helper separately removes callback bookkeeping after its grace
    // period. The failure above must already have completed at the 3s bound.
    await tester.pump(const Duration(milliseconds: 300));
    expect(transport.callbackCompleterMap, isEmpty);
  });
}

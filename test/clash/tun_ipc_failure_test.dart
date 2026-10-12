import 'dart:async';
import 'dart:convert';

import 'package:flclashx/clash/interface.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

class FailedTransport extends ClashHandlerInterface {
  FailedTransport(this.reply);
  final String reply;

  @override
  void sendMessage(String message) {
    final action = Action.fromJson(jsonDecode(message));
    if (reply == 'noReply') return;
    scheduleMicrotask(() {
      if (reply == 'disconnect') {
        callbackCompleterMap[action.id]!
            .complete(callbackDefaultMap[action.id]);
      } else {
        handleResult(ActionResult(
          method: action.method,
          id: action.id,
          data: reply == 'invalid' ? true : '',
          code: reply == 'rejected' ? ResultType.error : ResultType.success,
        ));
      }
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final failure in ['disconnect', 'invalid', 'rejected']) {
    test('updateConfig $failure cannot report success', () async {
      final result = await FailedTransport(failure).updateConfig(
          const UpdateParams(
              tun: Tun(enable: true),
              mixedPort: 7890,
              allowLan: false,
              findProcessMode: FindProcessMode.always,
              mode: Mode.rule,
              logLevel: LogLevel.error,
              ipv6: true,
              tcpConcurrent: true,
              externalController: ExternalControllerStatus.close,
              unifiedDelay: true));
      expect(result, isNotEmpty);
    });
    test('setupConfig $failure cannot report success', () async {
      final transport = FailedTransport(failure);
      final result = await transport.setupConfig(const SetupParams(
        config: {},
        selectedMap: {},
        testUrl: '',
      ));
      expect(result, isNotEmpty);
    });
  }
  test('unknown getTunStatus from an older Core is not an off observation',
      () async {
    await expectLater(
        FailedTransport('rejected').getTunStatus(), throwsException);
  });
}

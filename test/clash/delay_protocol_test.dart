import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flclashx/clash/interface.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

class _Transport extends ClashHandlerInterface {
  _Transport(this.send);
  final void Function(_Transport, Action) send;
  @override
  void sendMessage(String message) =>
      send(this, Action.fromJson(jsonDecode(message)));
  void reply(Action action, dynamic data) =>
      unawaited(handleResult(ActionResult(
          id: action.id,
          method: action.method,
          data: data,
          code: ResultType.success)));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
      'delay request and cancel use the same request-id with queue-inclusive timeout',
      () => fakeAsync((clock) {
            final requests = <Action>[];
            final transport = _Transport((self, action) {
              requests.add(action);
              self.reply(
                  action,
                  action.method == ActionMethod.cancelTestDelay
                      ? true
                      : jsonEncode({
                          'name': 'node',
                          'url': 'https://test.invalid',
                          'value': -1,
                          'reason': 'overloaded'
                        }));
            });
            String? result;
            transport
                .asyncTestDelay('https://test.invalid', 'node',
                    requestId: 'batch-1',
                    timeout: const Duration(milliseconds: 1250))
                .then((value) => result = value);
            clock.flushMicrotasks();
            expect(jsonDecode(requests.first.data as String), {
              'proxy-name': 'node',
              'request-id': 'batch-1',
              'timeout': 1250,
              'test-url': 'https://test.invalid',
            });
            expect((jsonDecode(result!) as Map)['reason'], 'overloaded');
            unawaited(transport.cancelTestDelay('batch-1'));
            clock.flushMicrotasks();
            expect(requests.last.method, ActionMethod.cancelTestDelay);
            expect(requests.last.data, 'batch-1');
            expect(transport.callbackCompleterMap, isEmpty);
            expect(clock.nonPeriodicTimerCount, 0);
          }));

  test(
      'lost delay response cancels Core work and returns a typed deadline reason',
      () => fakeAsync((clock) {
            final requests = <Action>[];
            final transport = _Transport((self, action) {
              requests.add(action);
              if (action.method == ActionMethod.cancelTestDelay)
                self.reply(action, true);
            });
            String? result;
            transport
                .asyncTestDelay('url', 'node',
                    requestId: 'deadline-1',
                    timeout: const Duration(milliseconds: 20))
                .then((value) => result = value);
            clock.elapse(const Duration(milliseconds: 20));
            expect(requests.length, 2);
            expect(requests.last.method, ActionMethod.cancelTestDelay);
            expect(requests.last.data, 'deadline-1');
            expect(jsonDecode(result!), {
              'name': 'node',
              'url': 'url',
              'value': -1,
              'reason': 'deadlineExceeded'
            });
            expect(transport.callbackCompleterMap, isEmpty);
            expect(clock.nonPeriodicTimerCount, 0);
          }));
}

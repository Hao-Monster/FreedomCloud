import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flclashx/clash/interface.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

class _Transport extends ClashHandlerInterface {
  _Transport(this.send);
  final FutureOr<void> Function(_Transport, Action) send;
  @override
  dynamic sendMessage(String message) =>
      send(this, Action.fromJson(jsonDecode(message)));
  void reply(Action action, dynamic data) => handleResult(ActionResult(
      id: action.id,
      method: action.method,
      data: data,
      code: ResultType.success));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final timeout in [
    const Duration(seconds: 30),
    const Duration(minutes: 2)
  ]) {
    test(
        'successful RPC releases 60 responses with timeout $timeout',
        () => fakeAsync((clock) {
              final transport = _Transport((self, action) {
                scheduleMicrotask(() => self.reply(action, 'x' * 100000));
              });
              final calls = List.generate(
                  60,
                  (_) => transport.invoke<String>(
                      method: ActionMethod.getConnections, timeout: timeout));
              List<String>? values;
              Future.wait(calls).then((result) => values = result);
              clock.flushMicrotasks();
              expect(values!.every((value) => value.length == 100000), isTrue);
              expect(clock.nonPeriodicTimerCount, 0,
                  reason:
                      'Successful RPCs must not retain timeout or cleanup timers');
              final pending = transport.callbackCompleterMap.length;
              final defaults = transport.callbackDefaultMap.length;
              // Keep the Red run free from unrelated pending-timer teardown failures.
              clock.elapse(timeout + const Duration(seconds: 1));
              expect(pending, 0);
              expect(defaults, 0);
            }));
  }

  test(
      'synchronous response remains available and late duplicate is ignored',
      () => fakeAsync((clock) {
            Action? request;
            final transport = _Transport((self, action) {
              request = action;
              self.reply(action, true);
            });
            bool? result;
            transport.forceGc().then((value) => result = value);
            clock.flushMicrotasks();
            expect(result, isTrue);
            final pending = transport.callbackCompleterMap.length;
            transport.reply(request!, false);
            clock.elapse(const Duration(seconds: 31));
            expect(pending, 0);
            expect(transport.callbackDefaultMap, isEmpty);
          }));

  for (final asyncFailure in [false, true]) {
    test(
        'send failure async=$asyncFailure releases pending and returns default',
        () => fakeAsync((clock) {
              final transport = _Transport((_, __) {
                if (asyncFailure)
                  return Future<void>.error(
                      StateError('transport unavailable'));
                throw StateError('transport unavailable');
              });
              bool? result;
              transport.forceGc().then((value) => result = value);
              clock.flushMicrotasks();
              expect(result, isFalse);
              expect(transport.callbackCompleterMap, isEmpty);
              expect(transport.callbackDefaultMap, isEmpty);
            }));
  }

  test(
      'wrong reply type yields typed default and releases state',
      () => fakeAsync((clock) {
            final transport =
                _Transport((self, action) => self.reply(action, 123));
            bool? result;
            transport.forceGc().then((value) => result = value);
            clock.flushMicrotasks();
            expect(result, isFalse);
            final pending = transport.callbackCompleterMap.length;
            clock.elapse(const Duration(seconds: 31));
            expect(pending, 0);
          }));

  test(
      'timeout releases state and late reply cannot recreate it',
      () => fakeAsync((clock) {
            Action? request;
            final transport = _Transport((_, action) => request = action);
            final future = transport.invoke<bool>(
                method: ActionMethod.forceGc,
                timeout: const Duration(milliseconds: 20));
            bool? result;
            future.then((value) => result = value);
            clock.elapse(const Duration(milliseconds: 20));
            expect(result, isFalse);
            final pending = transport.callbackCompleterMap.length;
            transport.reply(request!, true);
            clock.elapse(const Duration(seconds: 1));
            expect(pending, 0);
            expect(transport.callbackCompleterMap, isEmpty);
          }));

  test(
      'disconnect completion releases state without delayed cleanup',
      () => fakeAsync((clock) {
            final transport = _Transport((self, action) {
              scheduleMicrotask(() {
                self.callbackCompleterMap[action.id]!
                    .complete(self.callbackDefaultMap[action.id]);
              });
            });
            bool? result;
            transport.forceGc().then((value) => result = value);
            clock.flushMicrotasks();
            expect(result, isFalse);
            final pending = transport.callbackCompleterMap.length;
            clock.elapse(const Duration(seconds: 31));
            expect(pending, 0);
          }));
}

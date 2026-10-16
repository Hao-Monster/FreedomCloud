import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flclashx/clash/core.dart';
import 'package:flclashx/clash/interface.dart';
import 'package:flclashx/common/delay_test_coordinator.dart';
import 'package:flclashx/common/node_catalog_codec.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

class _Transport extends ClashHandlerInterface {
  _Transport(this.send);
  final void Function(_Transport, Action) send;
  @override
  void sendMessage(String message) =>
      send(this, Action.fromJson(jsonDecode(message)));
  void reply(Action action, dynamic data, {bool success = true}) =>
      unawaited(handleResult(ActionResult.fromJson(ActionResult(
        id: action.id,
        method: action.method,
        data: data,
        code: success ? ResultType.success : ResultType.error,
      ).toJson())));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailedCancellation extends _Transport {
  _FailedCancellation() : super((_, __) {});
  @override
  Future<bool> cancelTestDelay(String requestId) async =>
      throw const FormatException('synthetic cancellation failure');
}

void main() {
  test('provider parser bridge uses compressed envelope in both directions',
      () async {
    final payload = {
      'proxies': [
        for (var i = 0; i < 12000; i++)
          {
            'name': 'Node $i',
            'password': 'PRIVATE',
            'server': 'fixture.invalid'
          }
      ],
      'rejected': 0
    };
    final response = await encodeCatalogPayload(jsonEncode(payload));
    final requests = <Action>[];
    final transport = _Transport((self, action) {
      requests.add(action);
      self.reply(action, response);
    });
    final parsed = await transport.catalogParseProvider(
        base64Encode(utf8.encode('proxies: []')), {'type': 'http'});
    expect(jsonDecode(parsed), payload);
    expect(requests.single.method, ActionMethod.catalogParseProvider);
    expect(
        jsonDecode(await decodeCatalogPayload(requests.single.data as String)),
        {
          'content-base64': base64Encode(utf8.encode('proxies: []')),
          'definition': {'type': 'http'}
        });
    expect(ClashCore.existingInterface, isNull);
    expect(transport.callbackCompleterMap, isEmpty);
  });

  test('oversized prepare never reaches transport', () async {
    final transport = _Transport((_, __) => fail('No transport call expected'));
    await expectLater(
        transport.catalogPrepare('c', [
          {'password': 'x' * (512 * 1024)}
        ], []),
        throwsA(isA<CatalogCoreException>()
            .having((e) => e.reason, 'reason', 'providerTooLarge')));
  });
  test('timeout cancellation failure does not escape as an asynchronous error',
      () {
    final errors = <Object>[];
    runZonedGuarded(
        () => fakeAsync((clock) {
              final transport = _FailedCancellation();
              DelayTestResult? result;
              unawaited(transport
                  .catalogTestDelay('c', 0, 'url',
                      requestId: 'r', timeout: const Duration(milliseconds: 10))
                  .then((value) => result = value));
              clock.elapse(const Duration(milliseconds: 10));
              expect(result!.reason, 'deadlineExceeded');
              expect(transport.callbackCompleterMap, isEmpty);
            }),
        (error, _) => errors.add(error));
    expect(errors, isEmpty);
  });

  test('unencodable catalog input produces a typed safe error before transport',
      () async {
    final transport = _Transport((_, __) => fail('No transport call expected'));
    await expectLater(
        Future.sync(() => transport.catalogPrepare('c', [
              {'value': Object()}
            ], [])),
        throwsA(isA<CatalogCoreException>()
            .having((e) => e.reason, 'reason', 'invalidParameters')));
  });

  test('catalog bridge sends isolated payloads and keeps singleton absent',
      () async {
    final requests = <Action>[];
    final transport = _Transport((self, action) {
      requests.add(action);
      self.reply(
          action,
          switch (action.method) {
            ActionMethod.catalogPrepare =>
              '{"catalog-id":"c1","nodes":[],"providers":[]}',
            ActionMethod.catalogTestDelay => '{"value":45}',
            ActionMethod.catalogRelease => true,
            _ => throw StateError('Unexpected call'),
          });
    });
    final core = ClashCore.forTesting(transport);
    expect(ClashCore.existingInterface, isNull);
    await core.catalogPrepare('c1', [
      {'type': 'ss'}
    ], [
      {'name': 'p', 'path': 'cache'}
    ]);
    final result = await core.catalogTestDelay('c1', 4, 'https://test.invalid',
        requestId: 'request-1', timeout: const Duration(milliseconds: 1200));
    expect(result.value, 45);
    expect(await core.catalogRelease('c1'), isTrue);
    expect(requests.map((a) => a.method), [
      ActionMethod.catalogPrepare,
      ActionMethod.catalogTestDelay,
      ActionMethod.catalogRelease
    ]);
    expect(jsonDecode(requests[0].data as String), {
      'catalog-id': 'c1',
      'proxies': [
        {'type': 'ss'}
      ],
      'providers': [
        {'name': 'p', 'path': 'cache'}
      ]
    });
    expect(jsonDecode(requests[1].data as String), {
      'catalog-id': 'c1',
      'index': 4,
      'request-id': 'request-1',
      'timeout': 1200,
      'test-url': 'https://test.invalid'
    });
    expect(jsonDecode(requests[2].data as String), {'catalog-id': 'c1'});
    expect(ClashCore.existingInterface, isNull);
    expect(transport.callbackCompleterMap, isEmpty);
  });

  for (final reason in [
    'tooManyNodes',
    'catalogNotFound',
    'https://secret.invalid/token'
  ]) {
    test(
        'catalog bridge rejects error envelope safely: ${reason.startsWith('https') ? 'unknown' : reason}',
        () async {
      final transport = _Transport(
          (self, action) => self.reply(action, reason, success: false));
      final expected = reason.startsWith('https') ? 'unknown' : reason;
      final matcher = isA<CatalogCoreException>()
          .having((e) => e.reason, 'reason', expected)
          .having(
              (e) => e.toString(), 'safe message', isNot(contains('secret')));
      await expectLater(
          transport.catalogPrepare('c', [], []), throwsA(matcher));
      await expectLater(transport.catalogRelease('c'), throwsA(matcher));
      final result =
          await transport.catalogTestDelay('c', 0, 'url', requestId: 'r');
      expect(result.value, -1);
      expect(result.reason, expected);
      expect(transport.callbackCompleterMap, isEmpty);
    });
  }

  test('invalid response shapes and unknown reason never escape as raw errors',
      () async {
    for (final raw in [
      true,
      '{"value":-1,"reason":"secret-token"}',
      'secret-token',
      '{"value":0}'
    ]) {
      final transport = _Transport((self, action) => self.reply(action, raw));
      final result =
          await transport.catalogTestDelay('c', 0, 'url', requestId: 'r');
      expect(result.value, -1);
      expect(result.reason, isIn(['invalidResponse', 'unknown']));
      expect(transport.callbackCompleterMap, isEmpty);
    }
  });

  test(
      'catalog request timeout cancels matching ID and yields deadline only',
      () => fakeAsync((clock) {
            final requests = <Action>[];
            final transport = _Transport((self, action) {
              requests.add(action);
              if (action.method == ActionMethod.cancelTestDelay) {
                self.reply(action, true);
              }
            });
            DelayTestResult? result;
            unawaited(transport
                .catalogTestDelay('c', 0, 'url',
                    requestId: 'timed',
                    timeout: const Duration(milliseconds: 10))
                .then((value) => result = value));
            clock.elapse(const Duration(milliseconds: 10));
            expect(result!.reason, 'deadlineExceeded');
            expect(requests.last.method, ActionMethod.cancelTestDelay);
            expect(requests.last.data, 'timed');
            expect(clock.nonPeriodicTimerCount, 0);
          }));

  test('synchronous send failure is typed and redacted', () async {
    final transport = _Transport((_, __) => throw StateError('secret-token'));
    await expectLater(
        transport.catalogPrepare('c', [], []),
        throwsA(isA<CatalogCoreException>()
            .having((e) => e.reason, 'reason', 'transportFailure')));
    expect(
        (await transport.catalogTestDelay('c', 0, 'url', requestId: 'r'))
            .reason,
        'transportFailure');
  });

  test(
      'prepare and release timeouts are typed without retaining callbacks',
      () => fakeAsync((clock) {
            final transport = _Transport((_, __) {});
            final errors = <CatalogCoreException>[];
            unawaited(transport.catalogPrepare('c', [], []).then<void>(
                (_) => fail('prepare success'),
                onError: (Object error) =>
                    errors.add(error as CatalogCoreException)));
            unawaited(transport.catalogRelease('c').then<void>(
                (_) => fail('release success'),
                onError: (Object error) =>
                    errors.add(error as CatalogCoreException)));
            clock.elapse(const Duration(seconds: 30));
            expect(errors.map((e) => e.reason),
                ['deadlineExceeded', 'deadlineExceeded']);
            expect(transport.callbackCompleterMap, isEmpty);
            expect(clock.nonPeriodicTimerCount, 0);
          }));

  test('catalog transport rejects invalid indexes and IDs before sending',
      () async {
    var calls = 0;
    final transport = _Transport((_, __) {
      calls++;
    });
    for (final (id, index, requestId) in [
      ('c', -1, 'r'),
      ('', 0, 'r'),
      ('c', 0, '')
    ]) {
      final result = await transport.catalogTestDelay(id, index, 'url',
          requestId: requestId);
      expect(result.reason, 'invalidParameters');
    }
    expect(calls, 0);
  });
}

import 'dart:async';

import 'package:flclashx/common/admin_authorization.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('concurrent requests share one authorization operation', () async {
    final gate = AdminAuthorizationGate();
    final release = Completer<AuthorizeCode>();
    var attempts = 0;

    Future<AuthorizeCode> authorize() {
      attempts++;
      return release.future;
    }

    final first = gate.request(authorize);
    final second = gate.request(authorize);
    expect(identical(first, second), isTrue);
    expect(attempts, 1);

    release.complete(AuthorizeCode.success);
    expect(await first, AuthorizeCode.success);
    expect(await second, AuthorizeCode.success);
    expect(attempts, 1);
  });

  test('failed authorization is latched until explicit retry', () async {
    final gate = AdminAuthorizationGate();
    var attempts = 0;

    Future<AuthorizeCode> authorize() async {
      attempts++;
      return AuthorizeCode.error;
    }

    expect(await gate.request(authorize), AuthorizeCode.error);
    expect(gate.isFailureLatched, isTrue);
    expect(await gate.request(authorize), AuthorizeCode.error);
    expect(attempts, 1);

    gate.clearFailure();
    expect(await gate.request(authorize), AuthorizeCode.error);
    expect(attempts, 2);
  });

  test('clearFailure prevents an in-flight failure from re-latching', () async {
    final gate = AdminAuthorizationGate();
    final release = Completer<AuthorizeCode>();

    final pending = gate.request(() => release.future);
    gate.clearFailure();
    release.complete(AuthorizeCode.error);
    expect(await pending, AuthorizeCode.error);
    expect(gate.isFailureLatched, isFalse);
  });
}

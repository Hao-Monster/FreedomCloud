import 'package:flclashx/common/print.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('redacts complete HTTP URLs before they enter exported logs', () {
    const input =
        'fetch https://account:credential@example.invalid/subscription?token=abc123';

    final output = redactSensitiveLogData(input);

    expect(output, contains('<redacted-url>'));
    expect(output, isNot(contains('account')));
    expect(output, isNot(contains('credential')));
    expect(output, isNot(contains('example.invalid')));
  });

  test('redacts authorization and credential-style fields', () {
    const input =
        'Authorization: Bearer abc.def; password=secret-value token=abc123';

    final output = redactSensitiveLogData(input);

    expect(output, contains('Authorization: <redacted>'));
    expect(output, contains('password=<redacted>'));
    expect(output, contains('token=<redacted>'));
    expect(output, isNot(contains('abc.def')));
    expect(output, isNot(contains('secret-value')));
  });

  test('keeps ordinary diagnostic text unchanged', () {
    expect(redactSensitiveLogData('core started pid=123'),
        'core started pid=123');
  });
}

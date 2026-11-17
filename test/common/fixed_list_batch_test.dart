import 'package:flclashx/common/fixed.dart';
import 'package:flclashx/common/log_redaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FixedList batching and cached unmodifiable view', () {
    test('list getter returns cached unmodifiable reference until mutated', () {
      final fixed = FixedList<int>(4, list: [1, 2]);
      final view1 = fixed.list;
      final view2 = fixed.list;
      expect(identical(view1, view2), isTrue);

      fixed.add(3);
      final view3 = fixed.list;
      expect(identical(view1, view3), isFalse);
      expect(view3, [1, 2, 3]);
    });

    test('addAll and copyWithAdded retain tail within maxLength', () {
      final base = FixedList<int>(4, list: [1, 2, 3]);
      final next = base.copyWithAdded([4, 5, 6]);
      expect(base.list, [1, 2, 3]);
      expect(next.list, [3, 4, 5, 6]);

      final oversized = next.copyWithAdded([10, 11, 12, 13, 14]);
      expect(oversized.list, [11, 12, 13, 14]);

      base.addAll([4, 5]);
      expect(base.list, [2, 3, 4, 5]);
      base.addAll([20, 21, 22, 23, 24]);
      expect(base.list, [21, 22, 23, 24]);
    });
  });

  group('redactSensitiveLogData fast-path and security parity', () {
    test('leaves ordinary TCP/UDP connection logs untouched via fast-path', () {
      const line =
          '[INFO] [TCP] 198.18.0.1:54123 --> www.google.com:443 match DomainSuffix(google.com) using 伦敦';
      expect(redactSensitiveLogData(line), same(line));
    });

    test('redacts URLs, Bearer/Basic headers, and key-value credentials', () {
      expect(
        redactSensitiveLogData(
          'GET https://sub.example.com/api/v1/client/subscribe?token=abc123 failed',
        ),
        'GET <redacted-url> failed',
      );
      expect(
        redactSensitiveLogData('sent via Bearer eyJhbGciOiJIUzI1NiJ9.payload'),
        'sent via <redacted-authorization>',
      );
      expect(
        redactSensitiveLogData('header Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.payload'),
        'header Authorization: <redacted>',
      );
      expect(
        redactSensitiveLogData('login password=mySecretPassword123, refresh_token: tok_999'),
        'login password=<redacted>, refresh_token: <redacted>',
      );
    });
  });
}

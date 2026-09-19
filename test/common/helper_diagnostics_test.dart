import 'package:flclashx/common/helper_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats status and helper error text on one bounded line', () {
    final message = formatHelperFailure(
      operation: 'start',
      statusCode: 403,
      responseBody: 'access denied\r\nrun as administrator',
    );

    expect(message, 'helper.start failed http=403 '
        'detail=access denied run as administrator');
  });

  test('caps untrusted helper detail and reports missing detail', () {
    final message = formatHelperFailure(
      operation: 'stop',
      responseBody: 'x' * 300,
    );
    expect(
      message.length,
      lessThanOrEqualTo(240 + 'helper.stop failed detail='.length),
    );
    expect(message, endsWith('...'));
    expect(formatHelperFailure(operation: 'start'),
        'helper.start failed detail=unknown');
  });
}

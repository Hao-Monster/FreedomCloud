import 'package:flclashx/views/connection/settings.dart';
import 'package:flclashx/models/config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes persisted table columns without losing valid order', () {
    expect(
      normalizeConnectionTableColumns([
        'host',
        'host',
        'not-a-column',
        'process',
      ]),
      ['host', 'process'],
    );
  });

  test('falls back to defaults when persisted columns are empty or invalid',
      () {
    expect(
      normalizeConnectionTableColumns(['unknown']),
      defaultConnectionTableColumns,
    );
    expect(normalizeConnectionTableColumns(const []),
        defaultConnectionTableColumns);
  });
}

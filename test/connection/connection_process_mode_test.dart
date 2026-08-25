import 'package:flclashx/common/connection_process_mode.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/connection_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('process view forces metadata lookup even when profile disables it', () {
    expect(
      effectiveConnectionFindProcessMode(
        configured: FindProcessMode.off,
        listMode: ConnectionListMode.process,
        supportsProcessLookup: true,
      ),
      FindProcessMode.always,
    );
  });

  test('classic view preserves the configured process lookup policy', () {
    expect(
      effectiveConnectionFindProcessMode(
        configured: FindProcessMode.strict,
        listMode: ConnectionListMode.classic,
        supportsProcessLookup: true,
      ),
      FindProcessMode.strict,
    );
  });

  test('unsupported platforms never enable process lookup implicitly', () {
    expect(
      effectiveConnectionFindProcessMode(
        configured: FindProcessMode.off,
        listMode: ConnectionListMode.process,
        supportsProcessLookup: false,
      ),
      FindProcessMode.off,
    );
  });
}

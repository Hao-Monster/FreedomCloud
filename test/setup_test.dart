import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../setup.dart' as setup;

void main() {
  test('release hashing streams large binaries within the build budget',
      () async {
    final directory = await Directory.systemTemp.createTemp('flclashx-hash-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}core.bin');
    final bytes = List<int>.generate(
      12 * 1024 * 1024,
      (index) => index & 0xff,
      growable: false,
    );
    await file.writeAsBytes(bytes, flush: true);
    final expected = sha256.convert(bytes).toString();

    final stopwatch = Stopwatch()..start();
    final actual = await setup.Build.calcSha256(file.path);
    stopwatch.stop();

    expect(actual, expected);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
  }, timeout: const Timeout(Duration(seconds: 10)));
}

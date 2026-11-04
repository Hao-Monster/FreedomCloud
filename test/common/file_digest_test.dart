import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flclashx/common/file_digest.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('file-digest-test-');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('missing file throws FileSystemException', () async {
    final missing = p.join(tempDir.path, 'missing.exe');
    await expectLater(fileSha256(missing), throwsA(isA<FileSystemException>()));
  });

  test('small files hash accurately and reflect immediate same-length overwrites',
      () async {
    final file = File(p.join(tempDir.path, 'small.bin'));
    await file.writeAsBytes([1, 2, 3, 4]);
    expect(
      await fileSha256(file.path),
      sha256.convert([1, 2, 3, 4]).toString(),
    );

    await file.writeAsBytes([9, 8, 7, 6]);
    expect(
      await fileSha256(file.path),
      sha256.convert([9, 8, 7, 6]).toString(),
    );
  });

  test('large binaries cache by stat, deduplicate concurrent calls, and invalidate on change',
      () async {
    final file = File(p.join(tempDir.path, 'FlClashCore.exe'));
    final initialBytes = Uint8List.fromList(
      List<int>.generate(128 * 1024, (i) => i & 0xff),
    );
    await file.writeAsBytes(initialBytes, flush: true);
    final expectedInitial = sha256.convert(initialBytes).toString();

    var computeCount = 0;
    final gate = Completer<void>();
    final cache = FileSha256Cache(
      isolateThresholdBytes: 64 * 1024,
      computeDigest: (path) async {
        computeCount++;
        await gate.future;
        return fileSha256InBackground(path);
      },
    );

    final first = cache.hashFile(file.path);
    final second = cache.hashFile(file.path);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    gate.complete();

    final results = await Future.wait([first, second]);
    expect(results, [expectedInitial, expectedInitial]);
    expect(computeCount, 1);

    expect(await cache.hashFile(file.path), expectedInitial);
    expect(computeCount, 1);

    final updatedBytes = Uint8List.fromList(
      List<int>.generate(130 * 1024, (i) => (i * 7) & 0xff),
    );
    await file.writeAsBytes(updatedBytes, flush: true);
    final expectedUpdated = sha256.convert(updatedBytes).toString();
    expect(await cache.hashFile(file.path), expectedUpdated);
    expect(computeCount, 2);
  });

  test(
      'mid-stream file modification discards torn digest without poisoning cache',
      () async {
    final file = File(p.join(tempDir.path, 'MidWriteCore.exe'));
    final initialBytes = Uint8List.fromList(
      List<int>.generate(128 * 1024, (i) => i & 0xff),
    );
    final updatedBytes = Uint8List.fromList(
      List<int>.generate(136 * 1024, (i) => (i * 13) & 0xff),
    );
    await file.writeAsBytes(initialBytes, flush: true);
    final expectedUpdated = sha256.convert(updatedBytes).toString();
    final syntheticTornDigest = '0' * 64;

    var calls = 0;
    final cache = FileSha256Cache(
      isolateThresholdBytes: 64 * 1024,
      computeDigest: (path) async {
        calls++;
        if (calls == 1) {
          // Simulate an external installer overwriting the binary while the
          // background stream reader is mid-flight, yielding a torn digest.
          await File(path).writeAsBytes(updatedBytes, flush: true);
          return syntheticTornDigest;
        }
        return fileSha256InBackground(path);
      },
    );

    expect(await cache.hashFile(file.path), expectedUpdated);
    expect(calls, 2);
    // Subsequent call must hit the verified updated cache entry cleanly.
    expect(await cache.hashFile(file.path), expectedUpdated);
    expect(calls, 2);
  });
}

import 'dart:async';
import 'dart:io';

import 'package:flclashx/common/file_logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('legacy oversized logs are brought under the total byte budget',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('flclashx-log-legacy-');
    addTearDown(() => directory.delete(recursive: true));
    await File('${directory.path}/FlClashX_2026-10-08.log')
        .writeAsString('x' * 2000);
    final foreign = File('${directory.path}/foreign.log');
    await foreign.writeAsString('retain foreign data');
    final logger = FileLogger.forTesting(() async => directory.path,
        now: () => DateTime(2026, 10, 9),
        fileSizeLimit: 512,
        fileCountLimit: 3);
    addTearDown(logger.dispose);
    logger.log('new bounded data');
    await _waitUntil(() async {
      final current = File('${directory.path}/FlClashX_2026-10-09.log');
      return await current.exists() &&
          (await current.readAsString()).contains('new bounded data');
    });
    await logger.dispose();
    final files = await directory
        .list()
        .where((entry) => entry is File && entry.path.contains('FlClashX_'))
        .cast<File>()
        .toList();
    final lengths = await Future.wait(files.map((file) => file.length()));
    expect(lengths.fold<int>(0, (sum, length) => sum + length),
        lessThanOrEqualTo(1536));
    expect(await foreign.readAsString(), 'retain foreign data');
  });

  test('redacts direct file logger writes and bounds message size', () async {
    final directory = await Directory.systemTemp.createTemp('flclashx-logs-');
    addTearDown(() => directory.delete(recursive: true));
    final logger = FileLogger.forTesting(() async => directory.path);
    addTearDown(logger.dispose);

    logger.log(
      'fetch https://user:password@example.invalid/path?token=secret '
      '${'x' * (FileLogger.maxMessageLength + 100)}',
    );
    await _waitUntil(() async {
      final files = await directory
          .list()
          .where((entity) => entity is File)
          .cast<File>()
          .toList();
      return files.isNotEmpty;
    });

    final files = await directory
        .list()
        .where((entity) => entity is File)
        .cast<File>()
        .toList();
    final content = await files.single.readAsString();
    expect(content, contains('<redacted-url>'));
    expect(content, isNot(contains('example.invalid')));
    expect(content, isNot(contains('secret')));
    expect(content.length, lessThan(20 * 1024));
  });

  test('write failure schedules bounded backoff instead of a hot retry loop',
      () async {
    final logger = FileLogger.forTesting(() async {
      throw const FileSystemException('logs unavailable');
    });
    addTearDown(logger.dispose);

    logger.log('connection diagnostic');
    await _waitUntil(() async => logger.retryScheduled);

    expect(logger.pendingMessageCount, 1);
    expect(logger.retryScheduled, isTrue);
  });

  test('same-day rotation keeps its file budget and never deletes foreign logs',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('flclashx-rotation-');
    addTearDown(() => directory.delete(recursive: true));
    final foreign = File('${directory.path}/connections_diagnostic.log');
    await foreign.writeAsString('keep diagnostics');
    await foreign.setLastModified(DateTime(2000));
    final external = File('${directory.path}/external.log');
    await external.writeAsString('keep external');
    await external.setLastModified(DateTime(2000));
    final logger = FileLogger.forTesting(() async => directory.path,
        now: () => DateTime(2026, 10, 9), fileSizeLimit: 1, fileCountLimit: 3);
    addTearDown(logger.dispose);
    for (var index = 0; index < 8; index++) {
      logger.log('marker-$index');
      // On Windows a test's own read handle can temporarily block deletion.
      // Observe completed writes rather than racing the writer/retention pass.
      await logger.pendingWrites;
      final contents = await Future.wait((await directory
              .list()
              .where((entry) => entry is File)
              .cast<File>()
              .toList())
          .map((file) => file.readAsString()));
      expect(contents.join(), contains('marker-$index'));
    }
    final own = await directory
        .list()
        .where((entry) => entry is File && entry.path.contains('FlClashX_'))
        .toList();
    expect(own.length, lessThanOrEqualTo(3));
    expect(await foreign.readAsString(), 'keep diagnostics');
    expect(await external.readAsString(), 'keep external');
  });

  test('midnight switches an unfilled file and restart appends the correct day',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('flclashx-midnight-');
    addTearDown(() => directory.delete(recursive: true));
    var now = DateTime(2026, 10, 9, 23, 59);
    final logger =
        FileLogger.forTesting(() async => directory.path, now: () => now);
    addTearDown(logger.dispose);
    final dayOne = File('${directory.path}/FlClashX_2026-10-09.log');
    final dayTwo = File('${directory.path}/FlClashX_2026-10-10.log');
    logger.log('before midnight');
    await _waitUntil(() async =>
        await dayOne.exists() &&
        (await dayOne.readAsString()).contains('before midnight'));
    now = DateTime(2026, 10, 10, 0, 1);
    logger.log('after midnight');
    await _waitUntil(() async => logger.pendingMessageCount == 0);
    await logger.dispose();
    expect(await dayTwo.exists(), isTrue);
    expect(await dayOne.readAsString(), isNot(contains('after midnight')));
    final restarted =
        FileLogger.forTesting(() async => directory.path, now: () => now);
    addTearDown(restarted.dispose);
    restarted.log('after restart');
    await _waitUntil(() async =>
        await dayTwo.exists() &&
        (await dayTwo.readAsString()).contains('after restart'));
    expect(await dayTwo.readAsString(), contains('after midnight'));
  });

  test('one large queue drain respects byte and file budgets before dispose',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('flclashx-log-burst-');
    addTearDown(() => directory.delete(recursive: true));
    final logger = FileLogger.forTesting(() async => directory.path,
        now: () => DateTime(2026, 10, 9),
        fileSizeLimit: 512,
        fileCountLimit: 3);
    addTearDown(logger.dispose);
    for (var i = 0; i < 40; i++) {
      logger.log('burst-$i ${'界' * 80}');
    }
    await _waitUntil(() async => logger.pendingMessageCount == 0);
    await logger.dispose();
    final files = await directory
        .list()
        .where((entry) => entry is File)
        .cast<File>()
        .toList();
    expect(files.length, lessThanOrEqualTo(3));
    for (final file in files) {
      expect(await file.length(), lessThanOrEqualTo(512));
    }
    final contents =
        await Future.wait(files.map((file) => file.readAsString()));
    expect(contents.join(), contains('burst-39'));
  });

  test(
      'failed owned-file deletion keeps queue bounded and creates no extra file',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('flclashx-log-delete-fail-');
    addTearDown(() => directory.delete(recursive: true));
    final old = File('${directory.path}/FlClashX_2026-10-08.log');
    await old.writeAsString('old owned log');
    var attempts = 0;
    final logger = FileLogger.forTesting(() async => directory.path,
        now: () => DateTime(2026, 10, 9),
        fileCountLimit: 1,
        deleteFile: (_) async {
          attempts++;
          throw const FileSystemException('synthetic sharing violation');
        });
    addTearDown(logger.dispose);
    logger.log('pending new log');
    await logger.pendingWrites;
    expect(attempts, 1);
    expect(logger.retryScheduled, isTrue);
    expect(logger.pendingMessageCount, 1);
    expect(await old.readAsString(), 'old owned log');
    expect(await directory.list().length, 1);
    await logger.dispose();
    expect(logger.retryScheduled, isFalse);
    expect(logger.pendingMessageCount, 0);
  });
}

Future<void> _waitUntil(FutureOr<bool> Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(deadline)) {
    if (await predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('condition was not met before timeout');
}

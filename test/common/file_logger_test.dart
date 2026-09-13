import 'dart:async';
import 'dart:io';

import 'package:flclashx/common/file_logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
      final files = await directory.list()
          .where((entity) => entity is File)
          .cast<File>()
          .toList();
      return files.isNotEmpty;
    });

    final files = await directory.list()
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
}

Future<void> _waitUntil(FutureOr<bool> Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(deadline)) {
    if (await predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('condition was not met before timeout');
}

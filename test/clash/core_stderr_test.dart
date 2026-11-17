import 'dart:convert';

import 'package:flclashx/clash/service.dart';
import 'package:flclashx/common/file_logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('split UTF-8 timing lines and long unterminated stderr stay bounded', () async {
    const record = '[startup-timing] 设备';
    final data = utf8.encode('$record\r\nerror at EOF');
    final lines = await coreStderrLines(Stream.fromIterable(
      data.map((byte) => [byte]),
    )).toList();
    expect(lines, [record, 'error at EOF']);

    final long = List.filled(FileLogger.maxMessageLength + 7, 65);
    final parts = await coreStderrLines(Stream.value(long)).toList();
    expect(parts.map((line) => line.length), [FileLogger.maxMessageLength, 7]);
  });
}

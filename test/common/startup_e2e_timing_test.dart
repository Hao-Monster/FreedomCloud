import 'package:flclashx/common/startup_timing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('End-to-end startup timing milestones and schema=2 UI format', () {
    late DebugPrintCallback originalDebugPrint;
    late List<String> capturedLogs;

    setUp(() {
      capturedLogs = <String>[];
      originalDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) {
        if (message != null) {
          capturedLogs.add(message);
        }
      };
      resetStartupTimingForTest();
      markStartupLaunchEntry();
    });

    tearDown(() {
      resetStartupTimingForTest();
      debugPrint = originalDebugPrint;
    });

    test(
      'emits e2e.first_frame and e2e.tunnel_ready at most once per launch with schema=2 source=ui and stage-first prefix',
      () {
        final fakeWatch = Stopwatch()..start();
        setStartupTimingCorrelationId(
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
        );

        expect(logStartupFirstFrameOnce(watchOverride: fakeWatch), isTrue);
        expect(logStartupFirstFrameOnce(watchOverride: fakeWatch), isFalse);

        expect(
          logStartupTunnelReadyOnce(
            mode: 'tun',
            outcome: 'on',
            corePid: 7788,
            tunAttempt: 2,
            watchOverride: fakeWatch,
          ),
          isTrue,
        );
        expect(
          logStartupTunnelReadyOnce(
            mode: 'proxy_only',
            outcome: 'ready',
            watchOverride: fakeWatch,
          ),
          isFalse,
        );

        final bindLines = capturedLogs
            .where((l) => l.contains('event=correlation_bind'))
            .toList();
        expect(bindLines, hasLength(1));
        expect(bindLines.single, contains('schema=2'));
        expect(bindLines.single, contains('source=ui'));

        final firstFrameLines = capturedLogs
            .where((l) => l.contains('[startup-timing] stage=e2e.first_frame '))
            .toList();
        expect(firstFrameLines, hasLength(1));
        expect(firstFrameLines.single, contains('outcome=rendered'));
        expect(firstFrameLines.single, contains('schema=2'));
        expect(firstFrameLines.single, contains('source=ui'));
        expect(firstFrameLines.single, contains('uiRunId='));

        final tunnelReadyLines = capturedLogs
            .where(
              (l) => l.contains('[startup-timing] stage=e2e.tunnel_ready '),
            )
            .toList();
        expect(tunnelReadyLines, hasLength(1));
        expect(tunnelReadyLines.single, contains('outcome=on'));
        expect(tunnelReadyLines.single, contains('corePid=7788'));
        expect(tunnelReadyLines.single, contains('tunAttempt=2'));
        expect(tunnelReadyLines.single, contains('detail=mode=tun'));
        expect(tunnelReadyLines.single, contains('schema=2'));
        expect(tunnelReadyLines.single, contains('source=ui'));
      },
    );
  });
}

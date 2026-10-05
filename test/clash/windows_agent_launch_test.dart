import 'dart:io';

import 'package:flclashx/clash/windows_agent_launch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late String agent;
  late String core;
  late String service;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('strict-launch-');
    agent = p.join(root.path, 'FlClashAgent.exe');
    core = p.join(root.path, 'FlClashCore.exe');
    await File(agent).writeAsString('agent');
    await File(core).writeAsString('core');
    service = p.join(root.path, 'protected');
    await Directory(service).create();
  });
  tearDown(() => root.delete(recursive: true));
  Future<({String agent, String core})> resolve() => windowsAgentLaunchPaths(
        bundledAgent: agent,
        bundledCore: core,
        serviceDirectory: service,
      );
  Future<void> install() async {
    await File(p.join(service, 'FlClashStrictBroker.exe'))
        .writeAsString('broker');
    await File(agent).copy(p.join(service, 'FlClashAgent.exe'));
    await File(core).copy(p.join(service, 'FlClashCore.exe'));
  }

  test('ordinary portable launch uses bundled components', () async {
    expect(await resolve(), (agent: agent, core: core));
  });
  test('strict installation launches both protected components', () async {
    await install();
    expect(await resolve(), (
      agent: p.join(service, 'FlClashAgent.exe'),
      core: p.join(service, 'FlClashCore.exe'),
    ));
  });
  for (final name in ['FlClashAgent.exe', 'FlClashCore.exe']) {
    test('rejects mismatched $name without portable fallback', () async {
      await install();
      await File(p.join(service, name)).writeAsString('other build');
      await expectLater(resolve(), throwsStateError);
    });
    test('rejects missing $name without portable fallback', () async {
      await install();
      await File(p.join(service, name)).delete();
      await expectLater(resolve(), throwsA(isA<FileSystemException>()));
    });
  }

  group('launch and reconnection failure boundary', () {
    late List<Object> errors;
    late List<(String, List<String>)> starts;
    Future<bool> launch() => tryStartAgentProcess(
          resolvePaths: resolve,
          buildArguments: (corePath) async => ['--core', corePath],
          onError: errors.add,
          startProcess: (agentPath, arguments) async {
            starts.add((agentPath, arguments));
          },
        );

    setUp(() {
      errors = [];
      starts = [];
    });

    test('ordinary launch passes bundled paths to process boundary', () async {
      expect(await launch(), isTrue);
      expect(starts, hasLength(1));
      expect(starts.single.$1, agent);
      expect(starts.single.$2, ['--core', core]);
      expect(errors, isEmpty);
    });

    test('strict launch passes protected paths to process boundary', () async {
      await install();
      expect(await launch(), isTrue);
      expect(starts, hasLength(1));
      expect(starts.single.$1, p.join(service, 'FlClashAgent.exe'));
      expect(starts.single.$2, ['--core', p.join(service, 'FlClashCore.exe')]);
      expect(errors, isEmpty);
    });

    for (final name in ['FlClashAgent.exe', 'FlClashCore.exe']) {
      test(
        'mismatched $name reports failure on every retry without launch',
        () async {
          await install();
          await File(p.join(service, name)).writeAsString('other build');
          expect(await launch(), isFalse);
          expect(await launch(), isFalse);
          expect(starts, isEmpty);
          expect(errors, [isA<StateError>(), isA<StateError>()]);
        },
      );

      test('missing $name reports failure without launch', () async {
        await install();
        await File(p.join(service, name)).delete();
        expect(await launch(), isFalse);
        expect(starts, isEmpty);
        expect(errors, [isA<FileSystemException>()]);
      });
    }

    test('argument preparation failure does not start a process', () async {
      expect(
        await tryStartAgentProcess(
          resolvePaths: resolve,
          buildArguments: (_) async => throw StateError('home unavailable'),
          onError: errors.add,
          startProcess: (_, __) async => fail('must not launch'),
        ),
        isFalse,
      );
      expect(errors, [isA<StateError>()]);
    });

    test('process launch failure returns false with diagnostic', () async {
      expect(
        await tryStartAgentProcess(
          resolvePaths: resolve,
          buildArguments: (_) async => [],
          onError: errors.add,
          startProcess: (_, __) async =>
              throw const ProcessException('test-agent', [], 'blocked'),
        ),
        isFalse,
      );
      expect(errors, [isA<ProcessException>()]);
    });
  });
}

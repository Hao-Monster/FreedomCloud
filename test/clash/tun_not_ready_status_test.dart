import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flclashx/clash/agent_protocol.dart';
import 'package:flclashx/clash/interface.dart';
import 'package:flclashx/clash/service.dart';
import 'package:flclashx/common/tun_runtime.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _FakeTransport extends ClashHandlerInterface {
  _FakeTransport({
    this.notReadyReason,
    required this.onSend,
  });

  String? notReadyReason;
  final void Function(_FakeTransport transport, Action action) onSend;

  @override
  String? get tunTransportNotReadyReason => notReadyReason;

  @override
  void sendMessage(String message) {
    final action = Action.fromJson(jsonDecode(message) as Map<String, dynamic>);
    onSend(this, action);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ControllableAgentServer {
  _ControllableAgentServer({
    required this.endpointPath,
    required this.pid,
    required this.agentExecutable,
    required this.coreExecutable,
    this.initialCoreState = AgentCoreState.ready,
  }) : coreState = initialCoreState;

  final String endpointPath;
  final int pid;
  final String agentExecutable;
  final String coreExecutable;
  final AgentCoreState initialCoreState;
  AgentCoreState coreState;

  Completer<void>? holdShutdownReply;
  ServerSocket? _server;
  final List<Socket> _clients = [];

  static const _token =
      'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210';
  static const _instanceId =
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

  Future<void> start() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    await File(endpointPath).writeAsString(
      jsonEncode({
        'protocol': agentProtocolVersion,
        'port': server.port,
        'token': _token,
        'pid': pid,
        'agentInstanceId': _instanceId,
      }),
    );

    server.listen((client) {
      _clients.add(client);
      var authenticated = false;
      utf8.decoder
          .bind(client)
          .transform(const LineSplitter())
          .listen((line) async {
        final decoded = jsonDecode(line) as Map<String, dynamic>;
        if (!authenticated) {
          authenticated = true;
          _sendEvent(client, type: AgentEventType.ready);
          return;
        }
        final agentCmd = decoded['_agent'];
        if (agentCmd is Map<String, dynamic>) {
          final id = agentCmd['id'] as String;
          final command = agentCmd['command'] as String;
          if (command == AgentCommand.shutdownAgent.name) {
            if (holdShutdownReply != null) {
              await holdShutdownReply!.future;
            }
            coreState = AgentCoreState.stopped;
            _sendEvent(
              client,
              type: AgentEventType.commandResult,
              id: id,
              ok: true,
            );
            final file = File(endpointPath);
            if (file.existsSync()) {
              await file.delete();
            }
            await client.flush();
            await close();
            return;
          }
          _sendEvent(
            client,
            type: AgentEventType.commandResult,
            id: id,
            ok: true,
          );
          return;
        }
        final id = decoded['id'] as String;
        final method = decoded['method'] as String;
        if (coreState != AgentCoreState.ready) {
          _sendEvent(client, type: AgentEventType.coreUnavailable, id: id);
          return;
        }
        if (method == 'getTunStatus') {
          client.write(
            '${jsonEncode({
              'id': id,
              'method': method,
              'code': 0,
              'data': {
                'schemaVersion': 1,
                'coreInstanceId': 'core-$pid',
                'revision': 1,
                'observedAt': DateTime.now().millisecondsSinceEpoch,
                'requestedEnabled': false,
                'listenerActive': false,
                'state': 'off',
                'interfaceState': 'notApplicable',
                'privilege': 'elevated',
              },
            })}\n',
          );
          return;
        }
        client.write(
          '${jsonEncode({
            'id': id,
            'method': method,
            'code': 0,
            'data': true,
          })}\n',
        );
      });
    });
  }

  void publishCoreState(AgentCoreState next) {
    coreState = next;
    for (final client in _clients.toList()) {
      try {
        _sendEvent(client, type: AgentEventType.coreState);
      } catch (_) {}
    }
  }

  void _sendEvent(
    Socket client, {
    required AgentEventType type,
    String? id,
    bool? ok,
  }) {
    client.write(
      '${jsonEncode({
        '_agent': {
          'type': type.name,
          'coreState': coreState.name,
          'generation': 1,
          if (id != null) 'id': id,
          if (ok != null) 'ok': ok,
          if (type == AgentEventType.ready || type == AgentEventType.coreState)
            'proxyRunning': false,
          'privilegedBackend': true,
          'agentInstanceId': _instanceId,
          'agentPid': pid,
          'agentExecutable': agentExecutable,
          'coreExecutable': coreExecutable,
          'backendSource': 'helper',
        },
      })}\n',
    );
  }

  Future<void> close() async {
    for (final client in _clients.toList()) {
      try {
        client.destroy();
      } catch (_) {}
    }
    _clients.clear();
    await _server?.close();
    _server = null;
  }
}

TunStatus _sampleTunStatus(String instanceId, {bool active = true}) =>
    TunStatus(
      instanceId: instanceId,
      revision: 1,
      state: active ? 'on' : 'off',
      listenerActive: active,
      interfaceState: active ? 'up' : 'notApplicable',
      privilege: 'elevated',
      requestedEnabled: active,
    );

void main() {
  late DebugPrintCallback originalDebugPrint;
  late List<String> capturedLogs;

  setUp(() {
    capturedLogs = <String>[];
    originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        capturedLogs.add(message);
      }
    };
  });

  tearDown(() {
    debugPrint = originalDebugPrint;
  });

  group('Issue 1: getTunStatus not_ready logging and runtime semantics', () {
    test(
      'preflight not_ready fast-fails with TunNotReadyException and logs outcome=not_ready with explicit reason',
      () async {
        var sentCount = 0;
        final transport = _FakeTransport(
          notReadyReason: 'core_starting',
          onSend: (_, __) => sentCount++,
        );

        final watch = Stopwatch()..start();
        await expectLater(
          transport.getTunStatus(),
          throwsA(
            isA<TunNotReadyException>().having(
              (e) => e.reason,
              'reason',
              'core_starting',
            ),
          ),
        );
        watch.stop();

        expect(sentCount, 0);
        expect(watch.elapsedMilliseconds, lessThan(100));
        final timingLogs = capturedLogs
            .where((line) => line.contains('[startup-timing] stage=getTunStatus'))
            .toList();
        expect(timingLogs, hasLength(1));
        expect(timingLogs.single, contains('outcome=not_ready'));
        expect(timingLogs.single, contains('detail=reason=core_starting'));
        expect(timingLogs.single, isNot(contains('outcome=error')));

        // Repeated idle preflight polls with identical reason are deduplicated.
        await expectLater(
          transport.getTunStatus(),
          throwsA(isA<TunNotReadyException>()),
        );
        expect(
          capturedLogs
              .where((line) => line.contains('[startup-timing] stage=getTunStatus'))
              .length,
          1,
        );

        // Changing the preflight reason logs immediately.
        transport.notReadyReason = 'ipc_disconnected';
        await expectLater(
          transport.getTunStatus(),
          throwsA(
            isA<TunNotReadyException>()
                .having((e) => e.reason, 'reason', 'ipc_disconnected'),
          ),
        );
        expect(
          capturedLogs
              .where((line) => line.contains('[startup-timing] stage=getTunStatus'))
              .length,
          2,
        );
      },
    );

    test(
      'in-flight IPC disconnect logs outcome=not_ready with ipc_disconnected instead of generic error',
      () async {
        final transport = _FakeTransport(
          onSend: (self, action) {
            scheduleMicrotask(() {
              self.callbackCompleterMap
                  .remove(action.id)
                  ?.complete(self.callbackDefaultMap.remove(action.id));
            });
          },
        );

        await expectLater(
          transport.getTunStatus(),
          throwsA(
            isA<TunNotReadyException>().having(
              (e) => e.reason,
              'reason',
              'ipc_disconnected',
            ),
          ),
        );

        final timingLogs = capturedLogs
            .where((line) => line.contains('[startup-timing] stage=getTunStatus'))
            .toList();
        expect(timingLogs, hasLength(1));
        expect(timingLogs.single, contains('outcome=not_ready'));
        expect(timingLogs.single, contains('detail=reason=ipc_disconnected'));
      },
    );

    test(
      'genuine Core error and invalid schema log outcome=error with explicit detail reason',
      () async {
        final rejectedTransport = _FakeTransport(
          onSend: (self, action) {
            scheduleMicrotask(() {
              self.handleResult(
                ActionResult(
                  method: action.method,
                  id: action.id,
                  data: '',
                  code: ResultType.error,
                ),
              );
            });
          },
        );

        await expectLater(
          rejectedTransport.getTunStatus(),
          throwsA(
            isA<TunFailure>().having((e) => e.code, 'code', 'statusUnavailable'),
          ),
        );
        expect(
          capturedLogs.last,
          allOf(
            contains('[startup-timing] stage=getTunStatus'),
            contains('outcome=error'),
            contains('detail=reason=core_rejected'),
          ),
        );

        capturedLogs.clear();
        final invalidTransport = _FakeTransport(
          onSend: (self, action) {
            scheduleMicrotask(() {
              self.handleResult(
                ActionResult(
                  method: action.method,
                  id: action.id,
                  data: {'unexpected': true},
                  code: ResultType.success,
                ),
              );
            });
          },
        );

        await expectLater(
          invalidTransport.getTunStatus(),
          throwsA(
            isA<TunFailure>().having((e) => e.code, 'code', 'invalidStatus'),
          ),
        );
        expect(
          capturedLogs.last,
          allOf(
            contains('[startup-timing] stage=getTunStatus'),
            contains('outcome=error'),
            contains('detail=reason=invalidStatus'),
          ),
        );
      },
    );

    test(
      'TunStatusObserver revokes stale live status on TunNotReadyException without stamping statusUnavailable failure',
      () async {
        final runtime = TunRuntimeController();
        runtime.accept(_sampleTunStatus('live-1'), 0);
        expect(runtime.isEnabled, isTrue);
        expect(runtime.failure, isNull);

        final notReadyObserver = TunStatusObserver(
          runtime: runtime,
          read: () async => throw const TunNotReadyException('backend_migrating'),
        );
        expect(await notReadyObserver.refresh(fresh: true), isNull);
        expect(runtime.observed, TunObservedState.unknown);
        expect(runtime.failure, isNull);

        // If a previous observation error set statusUnavailable, a subsequent
        // not_ready transition clears the false observation error while
        // preserving any latched explicit requestFailure.
        runtime.invalidate('statusUnavailable');
        expect(runtime.failure, 'statusUnavailable');
        expect(await notReadyObserver.refresh(fresh: true), isNull);
        expect(runtime.failure, isNull);

        runtime.fail('permissionDenied');
        expect(runtime.requestFailure, 'permissionDenied');
        expect(await notReadyObserver.refresh(fresh: true), isNull);
        expect(runtime.failure, 'permissionDenied');
        expect(runtime.requestFailure, 'permissionDenied');
      },
    );

    test(
      'ClashService fast-returns not_ready during backend migration and core_stopped without 3s hang or 20s sendMessage timeout',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'fcx-tun-not-ready-',
        );
        addTearDown(() async {
          if (tempDir.existsSync()) {
            await tempDir.delete(recursive: true);
          }
        });
        final endpointPath = p.join(tempDir.path, 'agent.json');
        final bundledAgent = p.join(tempDir.path, 'FlClashAgent.exe');
        final bundledCore = p.join(tempDir.path, 'FlClashCore.exe');
        final bundledHelper = p.join(tempDir.path, 'FlClashHelperService.exe');
        final serviceDir = p.join(tempDir.path, 'service');
        final serviceHelper = p.join(serviceDir, 'FlClashHelperService.exe');
        final serviceCore = p.join(serviceDir, 'FlClashCore.exe');
        await Directory(serviceDir).create(recursive: true);
        for (final file in [
          bundledAgent,
          bundledCore,
          bundledHelper,
          serviceHelper,
          serviceCore,
        ]) {
          await File(file).writeAsString('binary-v1');
        }

        final server = _ControllableAgentServer(
          endpointPath: endpointPath,
          pid: 4100,
          agentExecutable: bundledAgent,
          coreExecutable: serviceCore,
        );
        await server.start();
        addTearDown(server.close);

        final service = ClashService.forTesting(
          isWindowsPlatform: true,
          agentBinaryExists: () async => true,
          applyPendingCoreUpdate: () async {},
          resolveEndpointPath: () async => endpointPath,
          resolveHomeDirPath: () async => tempDir.path,
          resolveBundledAgentPath: () => bundledAgent,
          resolveBundledCorePath: () => bundledCore,
          resolveBundledHelperPath: () => bundledHelper,
          resolveServiceDirectory: () => serviceDir,
          resolveServiceHelperPath: () => serviceHelper,
          resolveServiceCorePath: () => serviceCore,
          checkIsAdmin: () async => true,
          tryStartExistingHelper: () async => true,
          pingHelper: () async => true,
          readTunDesired: () => true,
          endpointPollInterval: const Duration(milliseconds: 20),
        );

        expect(await service.preload(), isTrue);
        expect((await service.getTunStatus()).privilege, 'elevated');

        // Transition Core into starting state (simulating mid-restart/handover).
        capturedLogs.clear();
        server.publishCoreState(AgentCoreState.starting);
        await Future<void>.delayed(const Duration(milliseconds: 30));

        final watch = Stopwatch()..start();
        await expectLater(
          service.getTunStatus(),
          throwsA(
            isA<TunNotReadyException>().having(
              (e) => e.reason,
              'reason',
              'core_starting',
            ),
          ),
        );
        watch.stop();
        expect(watch.elapsedMilliseconds, lessThan(150));
        expect(
          capturedLogs.where((l) => l.contains('stage=getTunStatus')),
          contains(
            allOf(
              contains('outcome=not_ready'),
              contains('detail=reason=core_starting'),
            ),
          ),
        );

        // Hold destroy()/shutdownAgent mid-flight so _stopping == true, and
        // verify getTunStatus + sendMessage fast-fail without hanging.
        server.publishCoreState(AgentCoreState.ready);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        server.holdShutdownReply = Completer<void>();
        final destroyFuture = service.destroy();
        await Future<void>.delayed(const Duration(milliseconds: 30));

        capturedLogs.clear();
        final stoppingWatch = Stopwatch()..start();
        await expectLater(
          service.getTunStatus(),
          throwsA(
            isA<TunNotReadyException>().having(
              (e) => e.reason,
              'reason',
              'backend_migrating',
            ),
          ),
        );
        final initWhileStopping = await service.isInit;
        stoppingWatch.stop();

        expect(initWhileStopping, isFalse);
        expect(stoppingWatch.elapsedMilliseconds, lessThan(150));
        expect(
          capturedLogs.where((l) => l.contains('stage=getTunStatus')),
          contains(
            allOf(
              contains('outcome=not_ready'),
              contains('detail=reason=backend_migrating'),
            ),
          ),
        );

        server.holdShutdownReply!.complete();
        await destroyFuture;
      },
    );

    test(
      'steady-state getTunStatus stays silent when desiredEnabled=false and observed=off, but logs unexpected states',
      () async {
        final previousDesired = tunRuntime.desiredEnabled;
        final previousOp = tunRuntime.operation;
        addTearDown(() {
          tunRuntime.desiredEnabled = previousDesired;
          tunRuntime.operation = previousOp;
        });

        tunRuntime.desiredEnabled = false;
        tunRuntime.operation = TunOperation.idle;
        var reportedState = 'off';
        var listenerActive = false;
        var interfaceState = 'missing';

        final transport = _FakeTransport(
          onSend: (self, action) {
            scheduleMicrotask(() {
              self.handleResult(
                ActionResult(
                  method: action.method,
                  id: action.id,
                  data: {
                    'schemaVersion': 1,
                    'coreInstanceId': 'steady-core-1',
                    'corePid': 4321,
                    'tunAttempt': 2,
                    'revision': 5,
                    'observedAt': 1700000000000,
                    'requestedEnabled': false,
                    'state': reportedState,
                    'listenerActive': listenerActive,
                    'device': 'Meta',
                    'interfaceState': interfaceState,
                    'privilege': 'unprivileged',
                  },
                  code: ResultType.success,
                ),
              );
            });
          },
        );

        capturedLogs.clear();
        final offStatus = await transport.getTunStatus();
        expect(offStatus.observed, TunObservedState.off);
        expect(
          capturedLogs.where((l) => l.contains('stage=getTunStatus')),
          isEmpty,
        );

        // Unexpected live TUN while desiredEnabled=false must still be logged.
        reportedState = 'on';
        listenerActive = true;
        interfaceState = 'up';
        final unexpectedOn = await transport.getTunStatus();
        expect(unexpectedOn.observed, TunObservedState.on);
        expect(
          capturedLogs.where(
            (l) => l.contains('[startup-timing] stage=getTunStatus'),
          ),
          hasLength(1),
        );
      },
    );
  });
}

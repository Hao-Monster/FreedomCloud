import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flclashx/clash/agent_protocol.dart';
import 'package:flclashx/clash/service.dart';
import 'package:flclashx/clash/windows_agent_launch.dart';
import 'package:flclashx/common/startup_timing.dart';
import 'package:flclashx/common/tun_runtime.dart';
import 'package:flclashx/main.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _FakeAgentServer {
  _FakeAgentServer({
    required this.endpointPath,
    required this.pid,
    required this.agentExecutable,
    required this.coreExecutable,
    required this.privilegedBackend,
    required this.backendSource,
    this.instanceId =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    this.tunPrivilege = 'unprivileged',
  });

  final String endpointPath;
  final int pid;
  final String agentExecutable;
  final String coreExecutable;
  final bool privilegedBackend;
  final String backendSource;
  final String? instanceId;
  AgentCoreState coreState = AgentCoreState.ready;
  String tunPrivilege;

  ServerSocket? _server;
  final List<Socket> _clients = [];
  final List<String> agentCommands = [];
  final List<String> coreMethods = [];

  static const _token =
      'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210';

  Future<void> start() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    final endpointJson = <String, dynamic>{
      'protocol': agentProtocolVersion,
      'port': server.port,
      'token': _token,
      'pid': pid,
      if (instanceId != null) 'agentInstanceId': instanceId,
    };
    await File(endpointPath).writeAsString(jsonEncode(endpointJson));

    server.listen((client) {
      _clients.add(client);
      var authenticated = false;
      utf8.decoder
          .bind(client)
          .transform(const LineSplitter())
          .listen((line) async {
        final decoded = jsonDecode(line) as Map<String, dynamic>;
        if (!authenticated) {
          if (decoded['token'] != _token ||
              decoded['protocol'] != agentProtocolVersion) {
            client.destroy();
            return;
          }
          authenticated = true;
          _sendEvent(client, type: AgentEventType.ready);
          return;
        }
        final agentCmd = decoded['_agent'];
        if (agentCmd is Map<String, dynamic>) {
          final id = agentCmd['id'] as String;
          final command = agentCmd['command'] as String;
          agentCommands.add(command);
          if (command == AgentCommand.shutdownAgent.name) {
            _sendEvent(
              client,
              type: AgentEventType.commandResult,
              id: id,
              ok: true,
              stateOverride: AgentCoreState.stopped,
            );
            final file = File(endpointPath);
            if (file.existsSync()) {
              await file.delete();
            }
            await client.flush();
            await close();
            return;
          }
          if (command == AgentCommand.stopCore.name) {
            coreState = AgentCoreState.stopped;
            _sendEvent(
              client,
              type: AgentEventType.commandResult,
              id: id,
              ok: true,
            );
            return;
          }
          if (command == AgentCommand.restartCore.name) {
            coreState = AgentCoreState.ready;
            _sendEvent(
              client,
              type: AgentEventType.commandResult,
              id: id,
              ok: true,
            );
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
        coreMethods.add(method);
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
                'privilege': tunPrivilege,
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

  void _sendEvent(
    Socket client, {
    required AgentEventType type,
    String? id,
    bool? ok,
    AgentCoreState? stateOverride,
  }) {
    final effectiveState = stateOverride ?? coreState;
    client.write(
      '${jsonEncode({
        '_agent': {
          'type': type.name,
          'coreState': effectiveState.name,
          'generation': 1,
          if (id != null) 'id': id,
          if (ok != null) 'ok': ok,
          if (type == AgentEventType.ready || type == AgentEventType.coreState)
            'proxyRunning': false,
          'privilegedBackend': privilegedBackend,
          if (instanceId != null) 'agentInstanceId': instanceId,
          'agentPid': pid,
          'agentExecutable': agentExecutable,
          'coreExecutable': coreExecutable,
          'backendSource': backendSource,
        },
      })}\n',
    );
  }

  Future<void> close() async {
    for (final client in List<Socket>.of(_clients)) {
      try {
        client.destroy();
      } catch (_) {}
    }
    _clients.clear();
    await _server?.close();
    _server = null;
  }
}

void main() {
  group('Defect A: Windows cold-start config readiness and tunDesired', () {
    test(
      'GlobalState.forTesting starts uninitialized and resolveWindowsTunDesiredForLaunch does not throw',
      () {
        final state = GlobalState.forTesting();
        final runtime = TunRuntimeController();

        expect(state.isConfigInitialized, isFalse);
        expect(() => state.config, throwsStateError);
        expect(
          resolveWindowsTunDesiredForLaunch(
            runtime: runtime,
            isConfigInitialized: state.isConfigInitialized,
            readPersistedTunEnabled: () =>
                state.config.patchClashConfig.tun.enable,
          ),
          isFalse,
        );
      },
    );

    test(
      'reads persisted tun.enable=true after GlobalState config init before TunRuntime observation starts',
      () {
        final state = GlobalState.forTesting()
          ..config = Config(
            themeProps: defaultThemeProps,
            patchClashConfig: defaultClashConfig.copyWith.tun(enable: true),
          );
        final runtime = TunRuntimeController();

        expect(state.isConfigInitialized, isTrue);
        expect(runtime.desiredEnabled, isFalse);
        expect(runtime.intentRevision, 0);
        expect(
          resolveWindowsTunDesiredForLaunch(
            runtime: runtime,
            isConfigInitialized: state.isConfigInitialized,
            readPersistedTunEnabled: () =>
                state.config.patchClashConfig.tun.enable,
          ),
          isTrue,
        );
      },
    );

    test(
      'explicit runtime intent overrides stale persisted tun.enable during same session',
      () async {
        final state = GlobalState.forTesting()
          ..config = Config(
            themeProps: defaultThemeProps,
            patchClashConfig: defaultClashConfig.copyWith.tun(enable: true),
          );
        final runtime = TunRuntimeController();
        await runtime.request(false, (_) async {});

        expect(runtime.intentRevision, greaterThan(0));
        expect(
          resolveWindowsTunDesiredForLaunch(
            runtime: runtime,
            isConfigInitialized: state.isConfigInitialized,
            readPersistedTunEnabled: () =>
                state.config.patchClashConfig.tun.enable,
          ),
          isFalse,
        );
      },
    );

    test(
      'bootstrapCoreAndState awaits initApp before triggering desktop preload',
      () async {
        final events = <String>[];
        var configReady = false;
        final preloadDone = Completer<void>();

        await bootstrapCoreAndState(
          isAndroid: false,
          initApp: () async {
            events.add('initApp:start');
            await Future<void>.delayed(const Duration(milliseconds: 10));
            configReady = true;
            events.add('initApp:done');
          },
          preloadCore: () async {
            events.add('preload:configReady=$configReady');
            preloadDone.complete();
            return true;
          },
        );
        await preloadDone.future;

        expect(
          events,
          ['initApp:start', 'initApp:done', 'preload:configReady=true'],
        );
      },
    );

    test(
      'bootstrapCoreAndState preserves Android preload-before-initApp order',
      () async {
        final events = <String>[];

        await bootstrapCoreAndState(
          isAndroid: true,
          preloadCore: () async {
            events.add('preload');
            return true;
          },
          initApp: () async {
            events.add('initApp');
          },
        );

        expect(events, ['preload', 'initApp']);
      },
    );
  });

  group('Defect B: Windows cold-start Agent deferral and single-Core lifecycle',
      () {
    late Directory tempDir;
    late String bundledAgent;
    late String bundledCore;
    late String bundledHelper;
    late String serviceDir;
    late String serviceHelper;
    late String serviceCore;
    late String endpointPath;
    final servers = <_FakeAgentServer>[];

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('win-cold-start-');
      bundledAgent = p.join(tempDir.path, 'FlClashAgent.exe');
      bundledCore = p.join(tempDir.path, 'FlClashCore.exe');
      bundledHelper = p.join(tempDir.path, 'FlClashHelperService.exe');
      serviceDir = p.join(tempDir.path, 'service');
      serviceHelper = p.join(serviceDir, 'FlClashHelperService.exe');
      serviceCore = p.join(serviceDir, 'FlClashCore.exe');
      endpointPath = p.join(tempDir.path, agentEndpointFileName);

      await Directory(serviceDir).create(recursive: true);
      await File(bundledAgent).writeAsString('agent-v1');
      await File(bundledCore).writeAsString('core-v1');
      await File(bundledHelper).writeAsString('helper-v1');
    });

    tearDown(() async {
      for (final server in servers) {
        await server.close();
      }
      servers.clear();
      await tempDir.delete(recursive: true);
    });

    test(
      'planWindowsAgentColdStart defers only on cold start when TUN is desired and Helper needs UAC',
      () async {
        expect(
          await planWindowsAgentColdStart(
            tunDesired: true,
            allowDeferForTunAuthorization: true,
            isHelperRunning: () async => false,
            installedFilesMatch: () async => false,
            tryStartExistingHelper: () async => false,
          ),
          WindowsAgentColdStartAction.deferForTunAuthorization,
        );

        expect(
          await planWindowsAgentColdStart(
            tunDesired: true,
            allowDeferForTunAuthorization: false,
            isHelperRunning: () async => false,
            installedFilesMatch: () async => false,
            tryStartExistingHelper: () async => false,
          ),
          WindowsAgentColdStartAction.launchLocal,
        );

        expect(
          await planWindowsAgentColdStart(
            tunDesired: false,
            allowDeferForTunAuthorization: true,
            isHelperRunning: () async => false,
            installedFilesMatch: () async => true,
            tryStartExistingHelper: () async => true,
          ),
          WindowsAgentColdStartAction.launchLocal,
        );

        expect(
          await planWindowsAgentColdStart(
            tunDesired: true,
            allowDeferForTunAuthorization: true,
            isHelperRunning: () async => false,
            installedFilesMatch: () async => true,
            tryStartExistingHelper: () async => true,
          ),
          WindowsAgentColdStartAction.launchWithHelper,
        );
      },
    );

    test(
      'cold start with stopped matching Helper and tunDesired=true starts Helper without UAC and spawns single --use-helper Agent',
      () async {
        await File(bundledHelper).copy(serviceHelper);
        await File(bundledCore).copy(serviceCore);

        var helperRunning = false;
        var startExistingHelperCalls = 0;
        final spawnedArgs = <List<String>>[];

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
          checkIsAdmin: () async => helperRunning,
          tryStartExistingHelper: () async {
            startExistingHelperCalls++;
            helperRunning = true;
            return true;
          },
          pingHelper: () async => helperRunning,
          readTunDesired: () => true,
          endpointPollInterval: const Duration(milliseconds: 5),
          startAgentProcess: (agentPath, arguments) async {
            spawnedArgs.add(arguments);
            final useHelper = arguments.contains('--use-helper');
            final server = _FakeAgentServer(
              endpointPath: endpointPath,
              pid: 4100,
              agentExecutable: agentPath,
              coreExecutable: useHelper ? serviceCore : bundledCore,
              privilegedBackend: useHelper,
              backendSource: useHelper ? 'helper' : 'local',
              tunPrivilege: useHelper ? 'elevated' : 'unprivileged',
            );
            servers.add(server);
            await server.start();
          },
        );

        expect(await service.preload(), isTrue);
        expect(startExistingHelperCalls, 1);
        expect(spawnedArgs, hasLength(1));
        expect(spawnedArgs.single, contains('--use-helper'));
        expect(service.hasDeferredAgentLaunch, isFalse);
        expect(service.agentCoreReady, isTrue);
        expect(
          await service.ensureWindowsTunBackend(isCurrent: () => true),
          isFalse,
        );
        expect(spawnedArgs, hasLength(1));
        await service.destroy();
      },
    );

    test(
      'cold start with missing/mismatched Helper defers local Agent and launches single --use-helper Agent in ensureWindowsTunBackend',
      () async {
        var helperRunning = false;
        final spawnedArgs = <List<String>>[];

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
          checkIsAdmin: () async => helperRunning,
          tryStartExistingHelper: () async => false,
          pingHelper: () async => helperRunning,
          readTunDesired: () => true,
          endpointPollInterval: const Duration(milliseconds: 5),
          startAgentProcess: (agentPath, arguments) async {
            spawnedArgs.add(arguments);
            final useHelper = arguments.contains('--use-helper');
            final server = _FakeAgentServer(
              endpointPath: endpointPath,
              pid: 5200 + spawnedArgs.length,
              agentExecutable: agentPath,
              coreExecutable: useHelper ? serviceCore : bundledCore,
              privilegedBackend: useHelper,
              backendSource: useHelper ? 'helper' : 'local',
              tunPrivilege: useHelper ? 'elevated' : 'unprivileged',
            );
            servers.add(server);
            await server.start();
          },
        );

        expect(await service.preload(), isTrue);
        expect(spawnedArgs, isEmpty);
        expect(service.hasDeferredAgentLaunch, isTrue);
        expect(service.agentCoreReady, isFalse);
        expect(service.windowsAgentSupportsMigration, isTrue);

        // Passive status/IPC calls while deferred must settle immediately, not hang.
        final watch = Stopwatch()..start();
        final deferredStatus = await service.getTunStatus();
        final deferredIsInit = await service.isInit;
        watch.stop();
        expect(watch.elapsedMilliseconds, lessThan(250));
        expect(deferredStatus.observed, TunObservedState.off);
        expect(deferredStatus.privilege, 'unprivileged');
        expect(deferredIsInit, isFalse);

        // Simulate UAC authorize() installing and starting the matching Helper.
        await File(bundledHelper).copy(serviceHelper);
        await File(bundledCore).copy(serviceCore);
        helperRunning = true;

        final replaced = await service.ensureWindowsTunBackend(
          isCurrent: () => true,
        );
        expect(replaced, isTrue);
        expect(spawnedArgs, hasLength(1));
        expect(spawnedArgs.single, contains('--use-helper'));
        expect(servers.single.agentCommands, isNot(contains('shutdownAgent')));
        expect(service.hasDeferredAgentLaunch, isFalse);
        expect(service.agentCoreReady, isTrue);
        expect((await service.getTunStatus()).privilege, 'elevated');
        await service.destroy();
      },
    );

    test(
      'UAC denial fallback materializes local Agent on demand via recoverCoreForUser without UAC',
      () async {
        final spawnedArgs = <List<String>>[];

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
          checkIsAdmin: () async => false,
          tryStartExistingHelper: () async => false,
          pingHelper: () async => false,
          readTunDesired: () => true,
          endpointPollInterval: const Duration(milliseconds: 5),
          startAgentProcess: (agentPath, arguments) async {
            spawnedArgs.add(arguments);
            final server = _FakeAgentServer(
              endpointPath: endpointPath,
              pid: 6100,
              agentExecutable: agentPath,
              coreExecutable: bundledCore,
              privilegedBackend: false,
              backendSource: 'local',
              tunPrivilege: 'unprivileged',
            );
            servers.add(server);
            await server.start();
          },
        );

        expect(await service.preload(), isTrue);
        expect(spawnedArgs, isEmpty);
        expect(service.hasDeferredAgentLaunch, isTrue);

        // User cancelled UAC (TD04), then manually started proxy without TUN.
        await service.recoverCoreForUser();
        expect(spawnedArgs, hasLength(1));
        expect(spawnedArgs.single, isNot(contains('--use-helper')));
        expect(service.hasDeferredAgentLaunch, isFalse);
        expect(service.agentCoreReady, isTrue);
        expect(await service.windowsComponentsMatch(), isTrue);
        await service.destroy();
      },
    );

    test(
      'attaching to a live legacy Agent never sets hasDeferredAgentLaunch and preserves legacyAgent guard',
      () async {
        await File(bundledHelper).copy(serviceHelper);
        await File(bundledCore).copy(serviceCore);
        final legacyServer = _FakeAgentServer(
          endpointPath: endpointPath,
          pid: 7100,
          agentExecutable: bundledAgent,
          coreExecutable: bundledCore,
          privilegedBackend: false,
          backendSource: 'local',
          instanceId: null,
        );
        servers.add(legacyServer);
        await legacyServer.start();

        var spawned = 0;
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
          endpointPollInterval: const Duration(milliseconds: 5),
          startAgentProcess: (_, __) async {
            spawned++;
          },
        );

        expect(await service.preload(), isTrue);
        expect(spawned, 0);
        expect(service.hasDeferredAgentLaunch, isFalse);
        expect(service.windowsAgentSupportsMigration, isFalse);
        await expectLater(
          service.ensureWindowsTunBackend(isCurrent: () => true),
          throwsA(
            isA<TunFailure>().having((e) => e.code, 'code', 'legacyAgent'),
          ),
        );
        await service.destroy();
      },
    );

    test(
      'destroy and shutdown while deferred complete cleanly without spawning Agent',
      () async {
        var spawned = 0;
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
          checkIsAdmin: () async => false,
          tryStartExistingHelper: () async => false,
          pingHelper: () async => false,
          readTunDesired: () => true,
          endpointPollInterval: const Duration(milliseconds: 5),
          startAgentProcess: (_, __) async {
            spawned++;
          },
        );

        expect(await service.preload(), isTrue);
        expect(service.hasDeferredAgentLaunch, isTrue);
        expect(await service.shutdown(), isTrue);
        expect(service.hasDeferredAgentLaunch, isFalse);
        expect(await service.destroy(), isTrue);
        expect(spawned, 0);
      },
    );

    test(
      'materializeDeferredAgent and reStart launch local Agent once without duplicate spawns',
      () async {
        final spawnedArgs = <List<String>>[];
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
          checkIsAdmin: () async => false,
          tryStartExistingHelper: () async => false,
          pingHelper: () async => false,
          readTunDesired: () => true,
          endpointPollInterval: const Duration(milliseconds: 5),
          startAgentProcess: (agentPath, arguments) async {
            spawnedArgs.add(arguments);
            final server = _FakeAgentServer(
              endpointPath: endpointPath,
              pid: 8100,
              agentExecutable: agentPath,
              coreExecutable: bundledCore,
              privilegedBackend: false,
              backendSource: 'local',
            );
            servers.add(server);
            await server.start();
          },
        );
        addTearDown(service.destroy);

        expect(await service.preload(), isTrue);
        expect(service.hasDeferredAgentLaunch, isTrue);
        expect(await service.materializeDeferredAgent(), isTrue);
        expect(await service.materializeDeferredAgent(), isTrue);
        expect(spawnedArgs, hasLength(1));
        expect(spawnedArgs.single, isNot(contains('--use-helper')));
        await service.reStart();
        expect(spawnedArgs, hasLength(1));
        expect(servers.single.agentCommands, contains('restartCore'));
      },
    );

    test(
      'post-startup fallback materializes local Agent after profileRequired or permissionDenied while preserving TUN failure and correlationId',
      () async {
        const expectedInstanceId =
            'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789';
        final spawnedArgs = <List<String>>[];
        final runtime = TunRuntimeController()..desiredEnabled = true;

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
          checkIsAdmin: () async => false,
          tryStartExistingHelper: () async => false,
          pingHelper: () async => false,
          readTunDesired: () => true,
          endpointPollInterval: const Duration(milliseconds: 5),
          startAgentProcess: (agentPath, arguments) async {
            spawnedArgs.add(arguments);
            final server = _FakeAgentServer(
              endpointPath: endpointPath,
              pid: 9100,
              agentExecutable: agentPath,
              coreExecutable: bundledCore,
              privilegedBackend: false,
              backendSource: 'local',
              instanceId: expectedInstanceId,
            );
            servers.add(server);
            await server.start();
          },
        );
        service.onTunTransportChanged = () {
          if (service.hasIntentionalOrInitialNotReady) {
            runtime.markNotReady();
          } else {
            runtime.invalidate('statusUnavailable');
          }
        };

        expect(await service.preload(), isTrue);
        expect(service.hasDeferredAgentLaunch, isTrue);
        expect(startupTimingCorrelationId, isNull);

        // Simulate fresh-install startup failing with profileRequired before UAC.
        await runtime.request(true, (_) async {
          throw const TunFailure('profileRequired');
        });
        expect(runtime.failure, 'profileRequired');
        expect(runtime.requestFailure, 'profileRequired');
        expect(runtime.desiredEnabled, isTrue);

        final logs = <String>[];
        await reconcileDeferredWindowsAgentAfterStartup(
          pendingProxyStop: false,
          hasDeferredAgentLaunch: () => service.hasDeferredAgentLaunch,
          initializeDeferredAgent: () async {
            expect(await service.materializeDeferredAgent(), isTrue);
            expect(await service.init(InitParams(homeDir: tempDir.path, version: 1)), isTrue);
          },
          log: logs.add,
        );

        expect(logs, isEmpty);
        expect(spawnedArgs, hasLength(1));
        expect(spawnedArgs.single, isNot(contains('--use-helper')));
        expect(service.hasDeferredAgentLaunch, isFalse);
        expect(service.agentCoreReady, isTrue);
        expect(startupTimingCorrelationId, expectedInstanceId);
        // Latched profileRequired and desiredEnabled=true must remain intact!
        expect(runtime.failure, 'profileRequired');
        expect(runtime.requestFailure, 'profileRequired');
        expect(runtime.desiredEnabled, isTrue);

        // Unprivileged status poll also preserves profileRequired.
        final observed = await service.getTunStatus();
        expect(runtime.accept(observed, runtime.observationEpoch), isTrue);
        expect(runtime.observed, TunObservedState.off);
        expect(runtime.failure, 'profileRequired');
        expect(runtime.requestFailure, 'profileRequired');

        await service.destroy();
        expect(startupTimingCorrelationId, isNull);
      },
    );

    test(
      'in-flight IPC calls started before preload decides deferForTunAuthorization do not hang on orphaned _coreReadyCompleter',
      () async {
        final checkIsAdminEntered = Completer<void>();
        final allowCheckIsAdminToFinish = Completer<bool>();
        var helperRunning = false;
        final spawnedArgs = <List<String>>[];

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
          checkIsAdmin: () async {
            if (!checkIsAdminEntered.isCompleted) {
              checkIsAdminEntered.complete();
              return allowCheckIsAdminToFinish.future;
            }
            return helperRunning;
          },
          tryStartExistingHelper: () async => false,
          pingHelper: () async => helperRunning,
          readTunDesired: () => true,
          endpointPollInterval: const Duration(milliseconds: 5),
          startAgentProcess: (agentPath, arguments) async {
            spawnedArgs.add(arguments);
            final useHelper = arguments.contains('--use-helper');
            final server = _FakeAgentServer(
              endpointPath: endpointPath,
              pid: 9500 + spawnedArgs.length,
              agentExecutable: agentPath,
              coreExecutable: useHelper ? serviceCore : bundledCore,
              privilegedBackend: useHelper,
              backendSource: useHelper ? 'helper' : 'local',
              tunPrivilege: useHelper ? 'elevated' : 'unprivileged',
            );
            servers.add(server);
            await server.start();
          },
        );
        addTearDown(service.destroy);

        // Wait until preload() is inside planWindowsAgentColdStart (before
        // hasDeferredAgentLaunch becomes true).
        await checkIsAdminEntered.future;
        expect(service.hasDeferredAgentLaunch, isFalse);

        // Issue early IPC calls in the exact window where AppStateManager
        // calls setUiActive(true) before preload() finishes.
        final earlyUiActiveFuture = service.setUiActive(true);
        final earlySendMessageFuture = service.sendMessage(
          jsonEncode({
            'id': 'early-msg-1',
            'method': 'setUiActive',
            'data': true,
          }),
        );

        // Let preload() decide deferForTunAuthorization.
        allowCheckIsAdminToFinish.complete(false);
        expect(await service.preload(), isTrue);
        expect(service.hasDeferredAgentLaunch, isTrue);

        // Both the RPC completer and the sendMessage Future itself must settle
        // immediately on deferral rather than hanging for 20s on an orphaned
        // _coreReadyCompleter.
        await expectLater(
          earlyUiActiveFuture.timeout(const Duration(milliseconds: 500)),
          completion(isFalse),
        );
        await expectLater(
          earlySendMessageFuture.timeout(const Duration(milliseconds: 500)),
          completes,
        );

        // Now materialize via ensureWindowsTunBackend and verify an in-flight
        // sendMessage started during materialization also completes as soon as
        // the new Core is ready.
        await File(bundledHelper).copy(serviceHelper);
        await File(bundledCore).copy(serviceCore);
        helperRunning = true;

        expect(
          await service.ensureWindowsTunBackend(isCurrent: () => true),
          isTrue,
        );
        expect(await service.setUiActive(true), isTrue);
      },
    );
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flclashx/clash/agent_protocol.dart';
import 'package:flclashx/clash/interface.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/models/core.dart';
import 'package:flclashx/state.dart';

class ClashService extends ClashHandlerInterface {
  factory ClashService() {
    _instance ??= ClashService._internal();
    return _instance!;
  }

  ClashService._internal() {
    unawaited(_initialize());
  }
  static ClashService? _instance;

  Completer<ServerSocket> serverCompleter = Completer();

  Completer<Socket> socketCompleter = Completer();

  final Completer<bool> _preloadCompleter = Completer();
  Completer<void> _agentAttachedCompleter = Completer();
  Completer<void> _coreReadyCompleter = Completer();
  final Map<String, Completer<bool>> _agentCommandCompleters = {};
  final AgentStrictPolicyStatusCache _strictPolicyStatusCache =
      AgentStrictPolicyStatusCache();
  final StreamController<AgentStrictPolicyStatus>
      _strictPolicyStatusController =
      StreamController<AgentStrictPolicyStatus>.broadcast();
  bool _agentMode = false;
  bool _detaching = false;
  bool _agentRecovering = false;
  int? _agentPid;
  AgentCoreState _agentCoreState = AgentCoreState.starting;
  bool? _agentProxyRunning;
  bool _agentUsingHelper = false;

  bool isStarting = false;

  Process? process;
  StreamSubscription? _socketSubscription;
  StreamSubscription? _stdoutSubscription;
  StreamSubscription? _stderrSubscription;

  static const int _maxCrashRetries = 5;
  int _crashCount = 0;
  DateTime? _lastCrashTime;
  bool _recovering = false;
  // Set while an intentional teardown is in flight (shutdown/destroy, e.g. from
  // handleRestart/handleExit). The socket EOF that a deliberate stop produces
  // must NOT be mistaken for a core crash — otherwise the recovery path fires a
  // restart that races the app restart and leaves the core offline / the UI
  // wedged. On Windows the helper kills the core before we cancel the socket
  // subscription, so this window is real.
  bool _stopping = false;

  /// Set by AppController to a guarded restartCore(). A crashed desktop core is a
  /// dead child process whose whole state is gone (unlike Android, where :remote
  /// survives an AIDL rebind), so recovery must respawn AND re-init/re-apply — not
  /// just relaunch a blank core.
  Future<void> Function(String reason)? onCoreCrash;

  bool get usesAgent => _agentMode;

  bool? get agentProxyRunning => _agentProxyRunning;

  /// Latest strict-capture status reported by the Agent.  The value is
  /// fail-closed by default and is never inferred from `proxyRunning`.
  AgentStrictPolicyStatus get strictPolicyStatus =>
      _strictPolicyStatusCache.value;

  /// Emits accepted strict-capture status changes for strategy/UI consumers.
  /// A reconnect status from an older generation is discarded by the cache.
  Stream<AgentStrictPolicyStatus> get strictPolicyStatusChanges =>
      _strictPolicyStatusController.stream;

  void _publishStrictPolicyStatus(AgentStrictPolicyStatus status) {
    if (_strictPolicyStatusCache.update(status)) {
      _strictPolicyStatusController.add(_strictPolicyStatusCache.value);
    }
  }

  Future<void> _initialize() async {
    try {
      _agentMode = await File(appPath.agentPath).exists();
      if (_agentMode) {
        await coreUpdater.applyPending();
        final connected = await _connectOrLaunchAgent();
        if (!_preloadCompleter.isCompleted) {
          _preloadCompleter.complete(connected);
        }
        return;
      }

      // Developer/source checkouts built before M2 may not contain the Agent
      // binary. Keep the old host as a compatibility path; release packaging
      // installs FlClashAgent and therefore never takes this branch.
      unawaited(_initServer());
      unawaited(reStart());
      try {
        await serverCompleter.future;
        if (!_preloadCompleter.isCompleted) {
          _preloadCompleter.complete(true);
        }
      } catch (e) {
        if (!_preloadCompleter.isCompleted) {
          _preloadCompleter.complete(false);
        }
      }
    } catch (e) {
      commonPrint.log('ClashService initialization failed: $e');
      if (!_preloadCompleter.isCompleted) {
        _preloadCompleter.complete(false);
      }
    }
  }

  Future<bool> _connectOrLaunchAgent() async {
    if (await _tryConnectAgent()) return _ensureAgentCoreReady();

    final homeDirPath = await appPath.homeDirPath;
    final arguments = <String>[
      '--home',
      homeDirPath,
      '--core',
      appPath.corePath,
    ];
    if (Platform.isWindows && await system.checkIsAdmin()) {
      arguments.addAll([
        '--service-core',
        appPath.windowsServiceCorePath,
        '--use-helper',
      ]);
    }
    try {
      await Process.start(
        appPath.agentPath,
        arguments,
        mode: ProcessStartMode.detached,
      );
    } catch (e) {
      commonPrint.log('unable to launch FlClashAgent: $e');
      return false;
    }

    for (var attempt = 0; attempt < 80; attempt++) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (await _tryConnectAgent()) return _ensureAgentCoreReady();
    }
    commonPrint.log('FlClashAgent did not publish a usable endpoint');
    return false;
  }

  Future<bool> _tryConnectAgent() async {
    try {
      final endpointFile = File(await appPath.agentEndpointPath);
      if (!await endpointFile.exists()) return false;
      final endpoint = AgentEndpoint.fromJson(
        json.decode(await endpointFile.readAsString()) as Map<String, dynamic>,
      );
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        endpoint.port,
        timeout: const Duration(milliseconds: 750),
      );
      await _socketSubscription?.cancel();
      _socketSubscription = null;
      if (socketCompleter.isCompleted) {
        try {
          (await socketCompleter.future).destroy();
        } catch (_) {}
      }
      socketCompleter = Completer<Socket>()..complete(socket);
      _agentAttachedCompleter = Completer<void>();
      _detaching = false;
      _socketSubscription = socket
          .transform(uint8ListToListIntConverter)
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            _handleAgentLine,
            onError: (Object error) => _onAgentLost('socket error: $error'),
            onDone: () => _onAgentLost('socket closed'),
            cancelOnError: true,
          );
      socket.writeln(json.encode({
        'token': endpoint.token,
        'protocol': agentProtocolVersion,
      }));
      await _agentAttachedCompleter.future.timeout(
        const Duration(seconds: 2),
      );
      _agentPid = endpoint.pid;
      return true;
    } catch (_) {
      return false;
    }
  }

  void _handleAgentLine(String line) {
    try {
      final value = json.decode(line.trim());
      if (value is! Map<String, dynamic>) return;
      final event = AgentEvent.tryParse(value);
      if (event != null) {
        _handleAgentEvent(event);
        return;
      }
      unawaited(handleResult(ActionResult.fromJson(value)));
    } catch (e) {
      commonPrint.log('Agent socket parse error: $e');
    }
  }

  void _handleAgentEvent(AgentEvent event) {
    _agentCoreState = event.coreState;
    _publishStrictPolicyStatus(
      strictPolicyStatusForCore(
        status: event.strictPolicyStatus,
        coreState: event.coreState,
      ),
    );
    if (event.type == AgentEventType.ready &&
        !_agentAttachedCompleter.isCompleted) {
      _agentAttachedCompleter.complete();
    }
    if (event.coreState == AgentCoreState.ready) {
      _agentProxyRunning = event.proxyRunning;
      _agentUsingHelper = event.privilegedBackend ?? _agentUsingHelper;
      if (!_coreReadyCompleter.isCompleted) {
        _coreReadyCompleter.complete();
      }
    } else if (_coreReadyCompleter.isCompleted) {
      _coreReadyCompleter = Completer<void>();
    }
    if (event.type == AgentEventType.commandResult && event.id != null) {
      final completer = _agentCommandCompleters.remove(event.id);
      if (completer != null && !completer.isCompleted) {
        completer.complete(event.ok ?? false);
      }
    } else if (event.type == AgentEventType.coreUnavailable &&
        event.id != null) {
      _completePendingWithDefault(event.id!, 'Agent Core unavailable');
    }
  }

  Future<bool> _ensureAgentCoreReady() async {
    if (_agentCoreState == AgentCoreState.starting) {
      try {
        await _coreReadyCompleter.future.timeout(const Duration(seconds: 20));
        return true;
      } catch (_) {
        // A hung start is recovered through the explicit bounded restart below.
      }
    }
    if (_agentCoreState != AgentCoreState.ready) {
      final restarted = await _agentCommand(AgentCommand.restartCore);
      if (!restarted) return false;
    }
    try {
      await _coreReadyCompleter.future.timeout(const Duration(seconds: 20));
      return true;
    } catch (e) {
      commonPrint.log('FlClashAgent Core readiness timed out: $e');
      return false;
    }
  }

  Future<bool> _agentCommand(
    AgentCommand command, {
    String? path,
    Map<String, dynamic>? policy,
  }) async {
    final id = 'agent-${command.name}-${utils.id}';
    final completer = Completer<bool>();
    _agentCommandCompleters[id] = completer;
    try {
      final socket = await socketCompleter.future;
      socket.writeln(
        encodeAgentCommand(
          id: id,
          command: command,
          path: path,
          policy: policy,
        ),
      );
      return await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => false,
      );
    } catch (_) {
      return false;
    } finally {
      _agentCommandCompleters.remove(id);
    }
  }

  /// Requests the privileged Windows backend to block a selected executable.
  /// The result is reported as a fail-closed `blocking` strict state; this is
  /// intentionally separate from the future signed redirect backend.
  Future<bool> applyStrictBlock(String executablePath) => _agentCommand(
        AgentCommand.applyStrictBlock,
        path: executablePath,
      );

  /// Removes the deterministic strict block for a selected executable.
  Future<bool> clearStrictBlock(String executablePath) => _agentCommand(
        AgentCommand.clearStrictBlock,
        path: executablePath,
      );

  /// Arms the complete signed Windows strict-capture policy transaction.
  /// The policy map must match the versioned strict-contract JSON shape.
  Future<bool> applyStrictPolicy(Map<String, dynamic> policy) => _agentCommand(
        AgentCommand.applyStrictPolicy,
        policy: policy,
      );

  /// Disables strict capture and revokes Core ingress before filter cleanup.
  Future<bool> clearStrictPolicy() =>
      _agentCommand(AgentCommand.clearStrictPolicy);

  void _onAgentLost(String reason) {
    // Socket loss invalidates any previously armed claim.  Keep the status
    // fail-closed while the bounded reconnect loop runs; never leave an armed
    // snapshot visible to policy consumers during an outage.
    final current = strictPolicyStatus;
    _publishStrictPolicyStatus(
      AgentStrictPolicyStatus(
        state: AgentStrictPolicyState.blocking,
        generation: current.generation,
        failureReason: AgentStrictPolicyFailureReason.coreUnavailable,
      ),
    );
    if (_detaching || _stopping || _agentRecovering) return;
    _agentRecovering = true;
    final previousAgentPid = _agentPid;
    _flushPendingCompleters();
    unawaited(() async {
      commonPrint.log('FlClashAgent connection lost ($reason), reconnecting');
      try {
        for (var attempt = 0; attempt < _maxCrashRetries; attempt++) {
          await Future.delayed(
            Duration(milliseconds: 250 * (1 << attempt).clamp(1, 16)),
          );
          if (await _connectOrLaunchAgent()) {
            // A transport interruption to the same Agent requires no Core
            // restart: Agent still owns and has replayed its state. A new PID
            // means the Agent journal was lost, so rebuild Core from Flutter's
            // persisted state through the existing recovery callback.
            if (_agentPid != previousAgentPid) {
              final callback = onCoreCrash;
              if (callback != null) await callback(reason);
            }
            return;
          }
        }
        globalState.showNotifier('Background Agent stopped unexpectedly');
      } finally {
        _agentRecovering = false;
      }
    }());
  }

  Future<void> _initServer() async {
    runZonedGuarded(() async {
      final address = !Platform.isWindows
          ? InternetAddress(
              unixSocketPath,
              type: InternetAddressType.unix,
            )
          : InternetAddress(
              localhost,
              type: InternetAddressType.IPv4,
            );
      await _deleteSocketFile();
      final server = await ServerSocket.bind(
        address,
        0,
        shared: true,
      );
      serverCompleter.complete(server);
      await for (final socket in server) {
        await _destroySocket();
        socketCompleter.complete(socket);
        _socketSubscription = socket
            .transform(uint8ListToListIntConverter)
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
          (data) {
            try {
              handleResult(
                ActionResult.fromJson(
                  json.decode(data.trim()),
                ),
              );
            } catch (e) {
              commonPrint.log('socket parse error: $e');
            }
          },
          onError: (Object e) {
            commonPrint.log('socket error: $e');
            _onCoreLost('socket error');
          },
          // EOF on the IPC socket means the core process died. An intentional
          // teardown cancels this subscription first, so onDone won't fire then.
          onDone: () => _onCoreLost('socket closed'),
        );
      }
    }, (error, stack) {
      commonPrint.log(error.toString());
      // A failed ServerSocket.bind here never completes serverCompleter, so
      // preload()/reStart()/destroy() would await it forever (app stuck at
      // launch). Surface the failure to those awaiters so they degrade instead.
      if (!serverCompleter.isCompleted) {
        serverCompleter.completeError(error);
      }
      if (error is SocketException) {
        globalState.showNotifier(error.toString());
      }
    });
  }

  @override
  Future<void> reStart() async {
    if (isStarting == true) {
      return;
    }
    isStarting = true;
    try {
      if (_agentMode) {
        if (Platform.isWindows &&
            await system.checkIsAdmin() != _agentUsingHelper) {
          await _agentCommand(AgentCommand.shutdownAgent);
          await detach();
          await Future.delayed(const Duration(milliseconds: 250));
          if (!await _connectOrLaunchAgent()) return;
          return;
        }
        if (!await _agentCommand(AgentCommand.restartCore)) return;
        await _coreReadyCompleter.future.timeout(const Duration(seconds: 20));
        return;
      }
      if (process != null) {
        await shutdown();
      }
      // Swap in a downloaded core update before anything spawns the binary — a
      // spawn-first order either locks the exe (Windows) or leaves the whole
      // session on the old core (macOS/Linux).
      await coreUpdater.applyPending();
      // Reset AFTER shutdown(): shutdown -> _destroySocket flushes/closes the
      // live socket via its `socketCompleter.isCompleted` guard, which a fresh
      // (incomplete) completer would otherwise defeat.
      socketCompleter = Completer();
      final ServerSocket serverSocket;
      try {
        serverSocket = await serverCompleter.future;
      } catch (e) {
        commonPrint.log('reStart aborted: server unavailable: $e');
        return;
      }
      final arg = Platform.isWindows
          ? "${serverSocket.port}"
          : serverSocket.address.address;
      if (Platform.isWindows && await system.checkIsAdmin()) {
        final isSuccess = await request.startCoreByHelper(arg);
        if (isSuccess) {
          return;
        }
      }

      final homeDirPath = await appPath.homeDirPath;
      final environment = Map<String, String>.from(Platform.environment);
      environment['SAFE_PATHS'] = homeDirPath;

      final started = await Process.start(
        appPath.corePath,
        [
          arg,
        ],
        environment: environment,
      );
      process = started;
      _stdoutSubscription = started.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            fileLogger.log('[FlClashCore stdout] $line');
          });
      _stderrSubscription = started.stderr.listen((e) {
        final error = utf8.decode(e);
        if (error.isNotEmpty) {
          commonPrint.log(error);
        }
      });
      _watchProcess(started);
    } finally {
      isStarting = false;
    }
  }

  @override
  Future<bool> destroy() async {
    if (_agentMode) {
      _stopping = true;
      try {
        final result = await _agentCommand(AgentCommand.shutdownAgent);
        await detach();
        return result;
      } finally {
        _stopping = false;
      }
    }
    // No reset: destroy() only runs on paths that end the process
    // (handleRestart/handleExit), so any trailing socket EOF stays suppressed.
    _stopping = true;
    try {
      final server = await serverCompleter.future;
      await server.close();
    } catch (e) {
      // bind failed: there is no server to close, but still clean up the socket
      // file and resolve instead of hanging on serverCompleter forever.
      commonPrint.log('destroy: server unavailable: $e');
    }
    await _deleteSocketFile();
    return true;
  }

  @override
  Future<void> sendMessage(String message) async {
    try {
      if (_agentMode) {
        await _coreReadyCompleter.future.timeout(const Duration(seconds: 20));
      }
      final socket = await socketCompleter.future;
      socket.writeln(message);
    } catch (e) {
      // Writing to a dead socket used to throw into an unawaited future and
      // strand this call until its 30s safeFuture timeout. Fail it fast with the
      // typed default; the crash handler respawns the core.
      commonPrint.log('sendMessage error: $e');
      _failPendingCompleter(message, '$e');
    }
  }

  /// Watches a spawned core process; an exit while it is still the current
  /// process is an unexpected crash. Intentional shutdown()/reStart() nulls or
  /// replaces `process` before the kill, so those exits are ignored here. The
  /// Windows helper-started core has no local `process`, so the socket onDone
  /// path covers that case.
  void _watchProcess(Process p) {
    p.exitCode.then((code) {
      if (!identical(p, process)) return;
      commonPrint.log('core process exited unexpectedly (code=$code)');
      _onCoreLost('process exit $code');
    });
  }

  void _onCoreLost(String reason) {
    if (_recovering || isStarting || _stopping) return;
    _recovering = true;
    _flushPendingCompleters();
    unawaited(_handleCrashRestart(reason));
  }

  /// Backoff-guarded crash recovery mirroring the Android ClashLib path: at most
  /// [_maxCrashRetries] restarts, the counter resetting after 60s of stability.
  Future<void> _handleCrashRestart(String reason) async {
    try {
      final now = DateTime.now();
      if (_lastCrashTime != null &&
          now.difference(_lastCrashTime!).inSeconds > 60) {
        _crashCount = 0;
      }
      _lastCrashTime = now;
      _crashCount++;
      if (_crashCount > _maxCrashRetries) {
        commonPrint.log(
          'core crash loop: $_crashCount crashes, giving up until manual restart',
        );
        globalState.showNotifier('Core stopped unexpectedly');
        return;
      }
      final delayMs = 1000 * (1 << (_crashCount - 1)).clamp(1, 16);
      commonPrint.log(
        'core crash #$_crashCount/$_maxCrashRetries ($reason), '
        'retrying in ${delayMs}ms',
      );
      await Future.delayed(Duration(milliseconds: delayMs));
      final cb = onCoreCrash;
      if (cb != null) {
        await cb(reason);
      } else {
        // Pre-init phase (controller hasn't wired the callback yet): at least
        // respawn the process; there's no applied config to restore yet.
        await reStart();
      }
    } catch (e) {
      commonPrint.log('core crash restart error: $e');
    } finally {
      _recovering = false;
    }
  }

  void _failPendingCompleter(String message, String reason) {
    try {
      final decoded = json.decode(message);
      if (decoded is Map<String, dynamic>) {
        final id = decoded['id'] as String?;
        if (id != null) {
          _completePendingWithDefault(id, reason);
        }
      }
    } catch (e) {
      commonPrint.log('_failPendingCompleter parse error: $e');
    }
  }

  void _completePendingWithDefault(String id, String reason) {
    final completer = callbackCompleterMap.remove(id);
    final def = callbackDefaultMap.remove(id);
    if (completer != null && !completer.isCompleted) {
      commonPrint.log('_completePendingWithDefault: reason=$reason');
      completer.complete(def);
    }
  }

  Future<void> _deleteSocketFile() async {
    if (!Platform.isWindows) {
      final file = File(unixSocketPath);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  Future<void> _destroySocket() async {
    await _socketSubscription?.cancel();
    _socketSubscription = null;
    if (socketCompleter.isCompleted) {
      _flushPendingCompleters();
      final lastSocket = await socketCompleter.future;
      await lastSocket.close();
      socketCompleter = Completer();
    }
  }

  void _flushPendingCompleters() {
    for (final entry in callbackCompleterMap.entries.toList()) {
      if (!entry.value.isCompleted) {
        // Mirror _failPendingCompleter / handleResult: settle with the typed
        // default rather than completeError, which throws into callers and
        // causes TypeErrors/hangs on non-nullable completers.
        entry.value.complete(callbackDefaultMap[entry.key]);
      }
    }
    callbackCompleterMap.clear();
    callbackDefaultMap.clear();
  }

  @override
  Future<bool> shutdown() async {
    // Guard the whole teardown: the EOF from killing the core (helper stop on
    // Windows arrives before we cancel the subscription below) must not trip the
    // crash-recovery path into a restart that races an intentional stop/restart.
    _stopping = true;
    try {
      if (_agentMode) {
        return _agentCommand(AgentCommand.stopCore);
      }
      if (Platform.isWindows) {
        await request.stopCoreByHelper();
      }
      await _stdoutSubscription?.cancel();
      _stdoutSubscription = null;
      await _stderrSubscription?.cancel();
      _stderrSubscription = null;
      await _destroySocket();
      process?.kill();
      process = null;
      return true;
    } finally {
      _stopping = false;
    }
  }

  @override
  Future<bool> preload() => _preloadCompleter.future;

  /// Disconnects only the Flutter UI. The Agent and Core deliberately remain
  /// alive so TUN/system-proxy operation survives a closed desktop window.
  Future<bool> detach() async {
    _detaching = true;
    try {
      if (_agentMode && _agentCoreState == AgentCoreState.ready) {
        try {
          await setUiActive(false);
        } catch (_) {}
      }
      await _socketSubscription?.cancel();
      _socketSubscription = null;
      if (socketCompleter.isCompleted) {
        try {
          (await socketCompleter.future).destroy();
        } catch (_) {}
      }
      socketCompleter = Completer<Socket>();
      _flushPendingCompleters();
      return true;
    } finally {
      _detaching = false;
    }
  }
}

final clashService = system.isDesktop ? ClashService() : null;

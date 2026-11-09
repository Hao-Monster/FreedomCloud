import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart' as crypto;

import 'package:flclashx/clash/agent_lifecycle.dart';
import 'package:flclashx/clash/agent_protocol.dart';
import 'package:flclashx/clash/interface.dart';
import 'package:flclashx/clash/windows_agent_launch.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/file_digest.dart';
import 'package:flclashx/common/tun_runtime.dart';
import 'package:flclashx/models/common.dart';
import 'package:flclashx/models/core.dart';
import 'package:flclashx/state.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

void _writeSocketLine(Socket socket, String line) {
  socket.add(utf8.encode('$line\n'));
}

void _enableTcpNoDelayBestEffort(Socket socket) {
  try {
    socket.setOption(SocketOption.tcpNoDelay, true);
  } catch (_) {
    // Unix domain sockets do not support TCP_NODELAY; ignore safely.
  }
}

class ClashService extends ClashHandlerInterface {
  factory ClashService() {
    _instance ??= ClashService._internal();
    return _instance!;
  }

  ClashService._internal()
      : _isWindowsPlatform = Platform.isWindows,
        _agentBinaryExists =
            (() async => File(appPath.agentPath).existsSync()),
        _applyPendingCoreUpdate = coreUpdater.applyPending,
        _resolveEndpointPath = (() => appPath.agentEndpointPath),
        _resolveHomeDirPath = (() => appPath.homeDirPath),
        _resolveBundledAgentPath = (() => appPath.agentPath),
        _resolveBundledCorePath = (() => appPath.corePath),
        _resolveBundledHelperPath = (() => appPath.helperPath),
        _resolveServiceDirectory = (() => appPath.windowsServiceDirectory),
        _resolveServiceHelperPath = (() => appPath.windowsServiceHelperPath),
        _resolveServiceCorePath = (() => appPath.windowsServiceCorePath),
        _checkIsAdmin = system.checkIsAdmin,
        _tryStartExistingHelper =
            (() async => (await windows?.tryStartExistingService()) ?? false),
        _pingHelper = request.pingHelper,
        _readTunDesired = (() => resolveWindowsTunDesiredForLaunch(
              runtime: tunRuntime,
              isConfigInitialized: globalState.isConfigInitialized,
              readPersistedTunEnabled: () =>
                  globalState.config.patchClashConfig.tun.enable,
            )),
        _endpointPollInterval = const Duration(milliseconds: 100),
        _startAgentProcess = null {
    unawaited(_initialize());
  }

  @visibleForTesting
  ClashService.forTesting({
    bool? isWindowsPlatform,
    Future<bool> Function()? agentBinaryExists,
    Future<void> Function()? applyPendingCoreUpdate,
    Future<String> Function()? resolveEndpointPath,
    Future<String> Function()? resolveHomeDirPath,
    String Function()? resolveBundledAgentPath,
    String Function()? resolveBundledCorePath,
    String Function()? resolveBundledHelperPath,
    String Function()? resolveServiceDirectory,
    String Function()? resolveServiceHelperPath,
    String Function()? resolveServiceCorePath,
    Future<bool> Function()? checkIsAdmin,
    Future<bool> Function()? tryStartExistingHelper,
    Future<bool> Function()? pingHelper,
    bool Function()? readTunDesired,
    Duration endpointPollInterval = const Duration(milliseconds: 100),
    Future<void> Function(String agent, List<String> arguments)?
        startAgentProcess,
  })  : _isWindowsPlatform = isWindowsPlatform ?? Platform.isWindows,
        _agentBinaryExists = agentBinaryExists ??
            (() async => File(appPath.agentPath).existsSync()),
        _applyPendingCoreUpdate =
            applyPendingCoreUpdate ?? coreUpdater.applyPending,
        _resolveEndpointPath =
            resolveEndpointPath ?? (() => appPath.agentEndpointPath),
        _resolveHomeDirPath =
            resolveHomeDirPath ?? (() => appPath.homeDirPath),
        _resolveBundledAgentPath =
            resolveBundledAgentPath ?? (() => appPath.agentPath),
        _resolveBundledCorePath =
            resolveBundledCorePath ?? (() => appPath.corePath),
        _resolveBundledHelperPath =
            resolveBundledHelperPath ?? (() => appPath.helperPath),
        _resolveServiceDirectory =
            resolveServiceDirectory ?? (() => appPath.windowsServiceDirectory),
        _resolveServiceHelperPath = resolveServiceHelperPath ??
            (() => appPath.windowsServiceHelperPath),
        _resolveServiceCorePath =
            resolveServiceCorePath ?? (() => appPath.windowsServiceCorePath),
        _checkIsAdmin = checkIsAdmin ?? system.checkIsAdmin,
        _tryStartExistingHelper = tryStartExistingHelper ??
            (() async => (await windows?.tryStartExistingService()) ?? false),
        _pingHelper = pingHelper ?? request.pingHelper,
        _readTunDesired = readTunDesired ??
            (() => resolveWindowsTunDesiredForLaunch(
                  runtime: tunRuntime,
                  isConfigInitialized: globalState.isConfigInitialized,
                  readPersistedTunEnabled: () =>
                      globalState.config.patchClashConfig.tun.enable,
                )),
        _endpointPollInterval = endpointPollInterval,
        _startAgentProcess = startAgentProcess {
    unawaited(_initialize());
  }

  static ClashService? _instance;

  final bool _isWindowsPlatform;
  final Future<bool> Function() _agentBinaryExists;
  final Future<void> Function() _applyPendingCoreUpdate;
  final Future<String> Function() _resolveEndpointPath;
  final Future<String> Function() _resolveHomeDirPath;
  final String Function() _resolveBundledAgentPath;
  final String Function() _resolveBundledCorePath;
  final String Function() _resolveBundledHelperPath;
  final String Function() _resolveServiceDirectory;
  final String Function() _resolveServiceHelperPath;
  final String Function() _resolveServiceCorePath;
  final Future<bool> Function() _checkIsAdmin;
  final Future<bool> Function() _tryStartExistingHelper;
  final Future<bool> Function() _pingHelper;
  final bool Function() _readTunDesired;
  final Duration _endpointPollInterval;
  final Future<void> Function(String agent, List<String> arguments)?
      _startAgentProcess;

  Completer<ServerSocket> serverCompleter = Completer();

  Completer<Socket> socketCompleter = Completer();

  final Completer<bool> _preloadCompleter = Completer();
  Completer<void> _agentAttachedCompleter = Completer();
  Completer<void> _coreReadyCompleter = Completer();
  final Map<String, Completer<bool>> _agentCommandCompleters = {};
  final Map<String, Completer<StrictIdentityResolution?>>
      _strictIdentityCompleters = {};
  final AgentStrictPolicyStatusCache _strictPolicyStatusCache =
      AgentStrictPolicyStatusCache();
  final StreamController<AgentStrictPolicyStatus>
      _strictPolicyStatusController =
      StreamController<AgentStrictPolicyStatus>.broadcast();
  bool _agentMode = false;
  List<int>? _macCoreKey;
  bool _macCoreVerified = false;

  bool _acceptMacCoreHandshake(Map<String, dynamic> value, Socket socket) {
    final frame = value['_macCore'];
    final key = _macCoreKey;
    if (frame is! Map || key == null || frame['protocol'] != 1) return false;
    final nonce = frame['nonce'];
    final proof = frame['proof'];
    if (nonce is! String ||
        proof is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(nonce) ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(proof)) return false;
    final mac = crypto.Hmac(crypto.sha256, key);
    final expected =
        mac.convert(utf8.encode('FCX-MAC-CORE/1/core/$nonce')).toString();
    var difference = 0;
    for (var i = 0; i < expected.length; i++) {
      difference |= expected.codeUnitAt(i) ^ proof.codeUnitAt(i);
    }
    if (difference != 0) return false;
    _writeSocketLine(
      socket,
      jsonEncode({
        '_macCore': {
          'protocol': 1,
          'nonce': nonce,
          'proof':
              mac.convert(utf8.encode('FCX-MAC-CORE/1/host/$nonce')).toString()
        }
      }),
    );
    return true;
  }

  bool _detaching = false;
  bool _agentRecovering = false;
  bool _agentLaunchDeferred = false;
  bool _loggedDeferredTunNotReady = false;
  int? _agentPid;
  AgentCoreState _agentCoreState = AgentCoreState.starting;
  bool? _agentProxyRunning;
  bool _agentUsingHelper = false;
  AgentEvent? _agentIdentity;
  int? _agentGeneration;
  int _connectionEpoch = 0;
  Completer<void> _agentDisconnected = Completer<void>();
  void Function()? onTunTransportChanged;

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
  bool get agentCoreReady => _agentCoreState == AgentCoreState.ready;
  bool get hasDeferredAgentLaunch =>
      _agentMode &&
      _agentLaunchDeferred &&
      _agentPid == null &&
      _agentIdentity == null;

  /// True when the transport transition is an expected startup, deferral,
  /// migration, or teardown state rather than an unexpected live Core loss.
  bool get hasIntentionalOrInitialNotReady =>
      _detaching ||
      _stopping ||
      !_preloadCompleter.isCompleted ||
      hasDeferredAgentLaunch ||
      (_agentMode &&
          !_agentRecovering &&
          _agentCoreState == AgentCoreState.starting);

  @override
  String? get tunTransportNotReadyReason {
    if (_detaching) return 'ipc_detaching';
    if (_stopping) {
      return _agentMode ? 'backend_migrating' : 'backend_stopping';
    }
    if (!_preloadCompleter.isCompleted) return 'preload_initializing';
    if (_agentMode) {
      if (hasDeferredAgentLaunch) return 'deferred_cold_start';
      if (_agentRecovering) return 'agent_recovering';
      if (!socketCompleter.isCompleted) return 'ipc_disconnected';
      if (_agentCoreState == AgentCoreState.starting ||
          !_coreReadyCompleter.isCompleted) {
        return 'core_starting';
      }
      if (_agentCoreState == AgentCoreState.stopped) return 'core_stopped';
      if (_agentCoreState != AgentCoreState.ready) return 'core_unavailable';
      return null;
    }
    if (_recovering) return 'core_recovering';
    if (isStarting) return 'core_starting';
    if (!socketCompleter.isCompleted) return 'ipc_disconnected';
    return null;
  }
  bool get windowsAgentSupportsMigration =>
      hasDeferredAgentLaunch ||
      (_agentIdentity?.agentInstanceId != null &&
          RegExp(r'^[0-9a-f]{64}$').hasMatch(_agentIdentity!.agentInstanceId!) &&
          _agentIdentity?.agentPid == _agentPid &&
          _agentIdentity?.agentExecutable != null &&
          _agentIdentity?.coreExecutable != null);
  final _agentConnections = AgentConnectionCoordinator();

  bool? get agentProxyRunning => _agentProxyRunning;

  // The Agent republishes proxyRunning only on Core state transitions. Keep
  // the cache aligned with listener commands acknowledged by the same Core;
  // otherwise a running proxy looks stopped after an ordinary stop/start and
  // a TUN-only enable falls back to a full profile reload.
  bool _sameAgentCore(int epoch, int? generation) =>
      _agentMode &&
      epoch == _connectionEpoch &&
      generation == _agentGeneration &&
      agentCoreReady;

  @override
  Future<bool> startListener() async {
    final epoch = _connectionEpoch;
    final generation = _agentGeneration;
    final started = await super.startListener();
    if (started && _sameAgentCore(epoch, generation)) {
      _agentProxyRunning = true;
    }
    return started;
  }

  @override
  Future<bool> stopListener() async {
    final epoch = _connectionEpoch;
    final generation = _agentGeneration;
    final stopped = await super.stopListener();
    // An unacknowledged stop leaves the previous claim; the next Agent state
    // event or TUN observation remains authoritative.
    if (stopped && _sameAgentCore(epoch, generation)) {
      _agentProxyRunning = false;
    }
    return stopped;
  }

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
      _agentMode = await _agentBinaryExists();
      if (_agentMode) {
        await _applyPendingCoreUpdate();
        final connected = await _connectOrLaunchAgent(
          allowDeferForTunAuthorization: true,
        );
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

  Future<bool> _connectOrLaunchAgent({
    bool recovery = false,
    bool allowDeferForTunAuthorization = false,
  }) =>
      _agentConnections.connect(() async {
        if (recovery && (_stopping || _detaching)) return false;
        return _connectOrLaunchAgentImpl(
          allowDeferForTunAuthorization:
              allowDeferForTunAuthorization && !recovery,
        );
      }, recovery: recovery);

  Future<bool> _connectOrLaunchAgentImpl({
    bool allowDeferForTunAuthorization = false,
  }) async {
    if (await _tryConnectAgent()) {
      _agentLaunchDeferred = false;
      if (!_isWindowsPlatform) return _ensureAgentCoreReady();
      await _observeAgentCoreReady();
      return true;
    }

    var useHelper = false;
    if (_isWindowsPlatform) {
      final tunDesired = _readTunDesired();
      final action = await planWindowsAgentColdStart(
        tunDesired: tunDesired,
        allowDeferForTunAuthorization: allowDeferForTunAuthorization,
        isHelperRunning: _checkIsAdmin,
        installedFilesMatch: () => windowsInstalledHelperFilesMatch(
          bundledHelper: _resolveBundledHelperPath(),
          bundledCore: _resolveBundledCorePath(),
          installedHelper: _resolveServiceHelperPath(),
          installedCore: _resolveServiceCorePath(),
        ),
        tryStartExistingHelper: _tryStartExistingHelper,
      );
      if (action == WindowsAgentColdStartAction.deferForTunAuthorization) {
        _agentLaunchDeferred = true;
        _agentCoreState = AgentCoreState.stopped;
        _agentUsingHelper = false;
        _agentProxyRunning = null;
        commonPrint.log(
          'FlClashAgent cold-start launch deferred until TUN authorization',
        );
        onTunTransportChanged?.call();
        return true;
      }
      useHelper = action == WindowsAgentColdStartAction.launchWithHelper;
    }

    final launched = await tryStartAgentProcess(
      resolvePaths: () async => _isWindowsPlatform
          ? windowsAgentLaunchPaths(
              bundledAgent: _resolveBundledAgentPath(),
              bundledCore: _resolveBundledCorePath(),
              serviceDirectory: _resolveServiceDirectory(),
            )
          : (
              agent: _resolveBundledAgentPath(),
              core: _resolveBundledCorePath(),
            ),
      buildArguments: (corePath) async {
        final arguments = <String>[
          '--home',
          await _resolveHomeDirPath(),
          '--core',
          corePath,
        ];
        if (_isWindowsPlatform && useHelper) {
          arguments.addAll([
            '--service-core',
            _resolveServiceCorePath(),
            '--use-helper',
          ]);
        }
        return arguments;
      },
      onError: (error) =>
          commonPrint.log('unable to launch FlClashAgent: $error'),
      startProcess: _startAgentProcess,
    );
    if (!launched) return false;

    for (var attempt = 0; attempt < 80; attempt++) {
      await Future.delayed(_endpointPollInterval);
      if (await _tryConnectAgent()) {
        _agentLaunchDeferred = false;
        return _isWindowsPlatform
            ? _observeAgentCoreReady()
            : _ensureAgentCoreReady();
      }
    }
    commonPrint.log('FlClashAgent did not publish a usable endpoint');
    return false;
  }

  Future<bool> _tryConnectAgent() async {
    try {
      final endpointFile = File(await _resolveEndpointPath());
      if (!await endpointFile.exists()) return false;
      final endpoint = AgentEndpoint.fromJson(
        json.decode(await endpointFile.readAsString()) as Map<String, dynamic>,
      );
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        endpoint.port,
        timeout: const Duration(milliseconds: 750),
      );
      _enableTcpNoDelayBestEffort(socket);
      await _socketSubscription?.cancel();
      _socketSubscription = null;
      if (socketCompleter.isCompleted) {
        try {
          (await socketCompleter.future).destroy();
        } catch (_) {}
      }
      socketCompleter = Completer<Socket>()..complete(socket);
      final connectionEpoch = ++_connectionEpoch;
      final disconnected = Completer<void>();
      _agentDisconnected = disconnected;
      _agentIdentity = null;
      _agentGeneration = null;
      onTunTransportChanged?.call();
      _agentAttachedCompleter = Completer<void>();
      _socketSubscription = socket
          .transform(uint8ListToListIntConverter)
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              if (connectionEpoch == _connectionEpoch) _handleAgentLine(line);
            },
            onError: (Object error) {
              if (!disconnected.isCompleted) disconnected.complete();
              if (connectionEpoch == _connectionEpoch) {
                _onAgentLost('socket error: $error');
              }
            },
            onDone: () {
              if (!disconnected.isCompleted) disconnected.complete();
              if (connectionEpoch == _connectionEpoch) {
                _onAgentLost('socket closed');
              }
            },
            cancelOnError: true,
          );
      _writeSocketLine(
        socket,
        json.encode({
          'token': endpoint.token,
          'protocol': agentProtocolVersion,
        }),
      );
      await _agentAttachedCompleter.future.timeout(
        const Duration(seconds: 2),
      );
      if (endpoint.instanceId != null &&
          (_agentIdentity?.agentInstanceId != endpoint.instanceId ||
              _agentIdentity?.agentPid != endpoint.pid)) {
        await _socketSubscription?.cancel();
        socket.destroy();
        return false;
      }
      _agentPid = endpoint.pid;
      return true;
    } catch (_) {
      return false;
    }
  }

  void _handleAgentLine(String line) {
    try {
      if (tryHandleRawActionResultLine(line)) return;
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

  bool? _mergeProxyRunning(AgentEvent event, bool sameReadyCore) =>
      mergeAgentProxyRunning(event,
          cached: _agentProxyRunning, sameReadyCore: sameReadyCore);

  void _handleAgentEvent(AgentEvent event) {
    final identity = _agentIdentity;
    if (identity?.agentInstanceId != null &&
        (event.agentInstanceId != identity!.agentInstanceId ||
            event.generation < (_agentGeneration ?? 0))) {
      return;
    }
    if (_agentGeneration != event.generation ||
        _agentIdentity?.agentInstanceId != event.agentInstanceId ||
        event.coreState != AgentCoreState.ready) {
      onTunTransportChanged?.call();
    }
    final sameReadyCore = _agentGeneration == event.generation &&
        _agentIdentity?.agentInstanceId == event.agentInstanceId &&
        _agentCoreState == AgentCoreState.ready;
    _agentGeneration = event.generation;
    _agentIdentity = event;
    _agentCoreState = event.coreState;
    _agentProxyRunning = _mergeProxyRunning(event, sameReadyCore);
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
      final identityCompleter = _strictIdentityCompleters.remove(event.id);
      if (identityCompleter != null && !identityCompleter.isCompleted) {
        identityCompleter.complete(event.ok == true ? event.identity : null);
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

  Future<bool> _observeAgentCoreReady({bool explicitRecovery = false}) =>
      reconcileAgentCore(
        state: () => _agentCoreState,
        waitReady: () =>
            _coreReadyCompleter.future.timeout(const Duration(seconds: 20)),
        restart: () => _agentCommand(AgentCommand.restartCore),
        explicitRecovery: explicitRecovery,
      );

  Future<bool> materializeDeferredAgent() async {
    if (!hasDeferredAgentLaunch) return agentCoreReady;
    return _agentConnections.connect(() async {
      if (!hasDeferredAgentLaunch) {
        return _observeAgentCoreReady(explicitRecovery: true);
      }
      return _materializeDeferredAgentLocked();
    });
  }

  Future<bool> _materializeDeferredAgentLocked() async {
    _agentLaunchDeferred = false;
    _agentCoreState = AgentCoreState.starting;
    _coreReadyCompleter = Completer<void>();
    onTunTransportChanged?.call();
    final connected = await _connectOrLaunchAgentImpl(
      allowDeferForTunAuthorization: false,
    );
    if (!connected && _agentPid == null && _agentIdentity == null) {
      _agentLaunchDeferred = true;
      _agentCoreState = AgentCoreState.stopped;
      onTunTransportChanged?.call();
    }
    return connected;
  }

  Future<void> recoverCoreForUser() async {
    final ready = await _agentConnections.connect(() async {
      if (hasDeferredAgentLaunch) {
        return _materializeDeferredAgentLocked();
      }
      return _observeAgentCoreReady(explicitRecovery: true);
    });
    if (!ready) throw const TunFailure('startFailed');
  }

  Future<bool> _agentCommand(
    AgentCommand command, {
    String? path,
    Map<String, dynamic>? policy,
  }) async {
    if (_agentMode &&
        (hasDeferredAgentLaunch || !socketCompleter.isCompleted)) {
      return false;
    }
    final id = 'agent-${command.name}-${utils.id}';
    final completer = Completer<bool>();
    _agentCommandCompleters[id] = completer;
    try {
      final socket = await socketCompleter.future;
      _writeSocketLine(
        socket,
        encodeAgentCommand(
          id: id,
          command: command,
          path: path,
          policy: policy,
        ),
      );
      return await completer.future.timeout(
        const {
          AgentCommand.applyStrictPolicy,
          AgentCommand.migrateStrictPolicy,
          AgentCommand.clearStrictPolicy,
        }.contains(command)
            ? const Duration(seconds: 310)
            : const Duration(seconds: 10),
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

  /// The Broker re-verifies the replacement and retains all old App-IDs.
  Future<bool> migrateStrictIdentity(
    String previousPath,
    StrictIdentityResolution replacement,
  ) =>
      _agentCommand(
        AgentCommand.migrateStrictPolicy,
        path: previousPath,
        policy: {
          'revision': DateTime.now().microsecondsSinceEpoch,
          'replacement': {
            'identityId': replacement.identityId,
            'canonicalPath': replacement.canonicalPath,
            'wfpAppIdSha256': replacement.wfpAppIdSha256,
            'publisherCertificateSha256':
                replacement.publisherCertificateSha256,
            'verifiedChildren': replacement.verifiedChildren
                .map((child) => {
                      'canonicalPath': child.canonicalPath,
                      'wfpAppIdSha256': child.wfpAppIdSha256,
                      'publisherCertificateSha256':
                          child.publisherCertificateSha256,
                    })
                .toList(growable: false),
          },
        },
      );

  /// Disables strict capture and revokes Core ingress before filter cleanup.
  Future<bool> clearStrictPolicy() =>
      _agentCommand(AgentCommand.clearStrictPolicy);

  /// Resolves a selected executable through the elevated Helper. The returned
  /// digest evidence is produced by the trusted boundary; this method never
  /// accepts caller-provided App-ID or publisher hashes.
  Future<StrictIdentityResolution?> inspectStrictIdentity(
    String executablePath,
  ) async {
    if (_agentMode &&
        (hasDeferredAgentLaunch || !socketCompleter.isCompleted)) {
      return null;
    }
    final id = 'agent-${AgentCommand.inspectStrictIdentity.name}-${utils.id}';
    final completer = Completer<StrictIdentityResolution?>();
    _strictIdentityCompleters[id] = completer;
    try {
      final socket = await socketCompleter.future;
      _writeSocketLine(
        socket,
        encodeAgentCommand(
          id: id,
          command: AgentCommand.inspectStrictIdentity,
          path: executablePath,
        ),
      );
      return await completer.future.timeout(const Duration(seconds: 10));
    } catch (_) {
      return null;
    } finally {
      _strictIdentityCompleters.remove(id);
    }
  }

  void _onAgentLost(String reason) {
    ++_connectionEpoch;
    _agentProxyRunning = null;
    onTunTransportChanged?.call();
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
    final recoveryEpoch = _agentConnections.epoch;
    _flushPendingCompleters();
    unawaited(() async {
      commonPrint.log('FlClashAgent connection lost ($reason), reconnecting');
      try {
        for (var attempt = 0; attempt < _maxCrashRetries; attempt++) {
          await Future.delayed(
            Duration(milliseconds: 250 * (1 << attempt).clamp(1, 16)),
          );
          if (_stopping ||
              _detaching ||
              recoveryEpoch != _agentConnections.epoch) return;
          if (await _connectOrLaunchAgent(recovery: true)) {
            if (_stopping ||
                _detaching ||
                recoveryEpoch != _agentConnections.epoch) return;
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
        _enableTcpNoDelayBestEffort(socket);
        await _destroySocket();
        _macCoreVerified = false;
        if (!Platform.isMacOS) socketCompleter.complete(socket);
        if (Platform.isMacOS) {
          Timer(const Duration(seconds: 10), () {
            if (!_macCoreVerified) socket.destroy();
          });
        }
        _socketSubscription = socket
            .transform(uint8ListToListIntConverter)
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
          (data) {
            try {
              if (Platform.isMacOS && !_macCoreVerified) {
                if (data.length > 4096 ||
                    !_acceptMacCoreHandshake(
                        Map<String, dynamic>.from(jsonDecode(data) as Map),
                        socket)) {
                  socket.destroy();
                  return;
                }
                _macCoreVerified = true;
                if (!socketCompleter.isCompleted) {
                  socketCompleter.complete(socket);
                }
                return;
              }
              if (tryHandleRawActionResultLine(data)) return;
              handleResult(ActionResult.fromJson(json.decode(data.trim())));
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
        // Backend migration belongs to an explicit TUN operation. A normal
        // recovery must not replace a privileged Core with a local Core just
        // because a transient Helper health check failed.
        final restarted = await _agentConnections.connect(() async {
          if (hasDeferredAgentLaunch) {
            return _materializeDeferredAgentLocked();
          }
          if (!await _agentCommand(AgentCommand.restartCore)) return false;
          await _coreReadyCompleter.future.timeout(const Duration(seconds: 20));
          return _agentCoreState == AgentCoreState.ready;
        });
        if (!restarted && _isWindowsPlatform) {
          throw const TunFailure('startFailed');
        }
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

      String? macToken;
      if (Platform.isMacOS) {
        final random = Random.secure();
        _macCoreKey = List.generate(32, (_) => random.nextInt(256));
        macToken = _macCoreKey!
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join();
      }
      final started = await Process.start(
        appPath.corePath,
        [arg, if (macToken != null) "@stdin"],
        environment: environment,
      );
      process = started;
      try {
        if (macToken != null) {
          started.stdin.writeln(macToken);
          await started.stdin.close();
        }
      } catch (_) {
        started.kill();
        process = null;
        rethrow;
      }
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

  Future<bool> windowsComponentsMatch() async {
    final watch = Stopwatch()..start();
    void report(bool matching, {String? outcome}) {
      logStartupTiming(
        'componentsMatch',
        watch,
        outcome: outcome ?? (matching ? 'match' : 'mismatch'),
      );
    }

    if (!_isWindowsPlatform) {
      report(true);
      return true;
    }
    final identity = _agentIdentity;
    final connectionEpoch = _connectionEpoch;
    final generation = _agentGeneration;
    if (!_agentMode ||
        identity == null ||
        identity.agentPid != _agentPid ||
        identity.agentInstanceId == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(identity.agentInstanceId!) ||
        identity.agentExecutable == null ||
        identity.coreExecutable == null) {
      report(false);
      return false;
    }
    try {
      for (final pair in [
        (_resolveBundledAgentPath(), identity.agentExecutable!),
        (_resolveBundledCorePath(), identity.coreExecutable!),
      ]) {
        if (!await binaryFilesMatch(pair.$1, pair.$2)) {
          report(false);
          return false;
        }
      }
      final helperMatches =
          identity.backendSource != 'helper' || await _pingHelper();
      final matching = helperMatches &&
          connectionEpoch == _connectionEpoch &&
          generation == _agentGeneration &&
          identity.agentInstanceId == _agentIdentity?.agentInstanceId;
      report(matching);
      return matching;
    } catch (_) {
      report(false, outcome: 'error');
      return false;
    }
  }

  /// Called only after an explicit user request prepared a matching Helper.
  /// Returns whether the Core was replaced and therefore needs configuration.
  Future<bool> ensureWindowsTunBackend({bool Function()? isCurrent}) async {
    bool current() => isCurrent?.call() ?? true;
    if (!current()) return false;
    if (!_isWindowsPlatform || !_agentMode) {
      throw const TunFailure('componentsMismatch');
    }
    if (_agentUsingHelper && await windowsComponentsMatch()) {
      if (!current()) return false;
      try {
        if ((await getTunStatus()).privilege == 'elevated') return false;
      } on TunFailure {
        /* Reconcile a claimed Helper with the actual Core. */
      } on TunNotReadyException {
        /* Reconcile an unready Core with the expected elevated Helper. */
      }
    }
    if (!await _checkIsAdmin()) {
      throw const TunFailure('permissionDenied');
    }
    if (!current()) return false;
    // Old Agents acknowledged shutdown before confirming Core exit. Never
    // use that acknowledgement to replace a potentially still-live Core.
    if (!windowsAgentSupportsMigration) throw const TunFailure('legacyAgent');
    if (!await _pingHelper()) {
      throw const TunFailure('componentsMismatch');
    }
    if (!current()) return false;
    // Verify the replacement can be selected before stopping a usable backend.
    try {
      await windowsAgentLaunchPaths(
        bundledAgent: _resolveBundledAgentPath(),
        bundledCore: _resolveBundledCorePath(),
        serviceDirectory: _resolveServiceDirectory(),
      );
    } catch (_) {
      throw const TunFailure('componentsMismatch');
    }
    if (!current()) return false;
    _stopping = true;
    try {
      return await _agentConnections.replace(() async {
        if (!current()) return false;
        return _replaceWindowsTunBackend(isCurrent: current);
      });
    } finally {
      _stopping = false;
    }
  }

  Future<bool> _replaceWindowsTunBackend({
    required bool Function() isCurrent,
  }) async {
    if (!windowsAgentSupportsMigration || !await _pingHelper()) {
      throw const TunFailure('componentsMismatch');
    }
    if (!isCurrent()) return false;
    if (hasDeferredAgentLaunch) {
      _agentLaunchDeferred = false;
      _agentCoreState = AgentCoreState.starting;
      _coreReadyCompleter = Completer<void>();
      onTunTransportChanged?.call();
      final connected = await _connectOrLaunchAgentImpl(
        allowDeferForTunAuthorization: false,
      );
      if (!connected ||
          _agentPid == null ||
          !_agentUsingHelper ||
          !await windowsComponentsMatch()) {
        if (_agentPid == null && _agentIdentity == null) {
          _agentLaunchDeferred = true;
          _agentCoreState = AgentCoreState.stopped;
          onTunTransportChanged?.call();
        }
        throw const TunFailure('componentsMismatch');
      }
      return true;
    }
    final previousPid = _agentPid;
    final previousInstance = _agentIdentity?.agentInstanceId;
    final disconnected = _agentDisconnected.future;
    _stopping = true;
    onTunTransportChanged?.call();
    try {
      if (!await _agentCommand(AgentCommand.shutdownAgent)) {
        throw const TunFailure('backendStopFailed');
      }
      await disconnected.timeout(const Duration(seconds: 20));
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      var endpointReleased = false;
      while (DateTime.now().isBefore(deadline)) {
        final file = File(await _resolveEndpointPath());
        if (!await file.exists()) {
          endpointReleased = true;
          break;
        }
        try {
          final endpoint =
              AgentEndpoint.fromJson(jsonDecode(await file.readAsString()));
          if (endpoint.pid != previousPid) {
            endpointReleased = true;
            break;
          }
        } catch (_) {
          /* A partial endpoint is not proof of ownership release. */
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (!endpointReleased) throw const TunFailure('backendStopFailed');
      await _detachAgentSocket();
      _coreReadyCompleter = Completer<void>();
      if (!await _connectOrLaunchAgentImpl() ||
          _agentPid == previousPid ||
          (previousInstance != null &&
              _agentIdentity?.agentInstanceId == previousInstance) ||
          !_agentUsingHelper ||
          !await windowsComponentsMatch()) {
        throw const TunFailure('componentsMismatch');
      }
      return true;
    } on TimeoutException {
      throw const TunFailure('backendStopFailed');
    } finally {
      _stopping = false;
    }
  }

  @override
  Future<bool> destroy() async {
    if (_agentMode) {
      _stopping = true;
      try {
        return await _agentConnections.replace(() async {
          if (hasDeferredAgentLaunch || !socketCompleter.isCompleted) {
            _agentLaunchDeferred = false;
            await _detachAgentSocket();
            return true;
          }
          final result = await _agentCommand(AgentCommand.shutdownAgent);
          await _detachAgentSocket();
          return result;
        });
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
  Future<TunStatus> getTunStatus() async {
    if (hasDeferredAgentLaunch) {
      if (!_loggedDeferredTunNotReady || tunRuntime.busy) {
        _loggedDeferredTunNotReady = true;
        final watch = Stopwatch()..start();
        logStartupTiming(
          'getTunStatus',
          watch,
          outcome: 'not_ready',
          detail: 'reason=deferred_cold_start',
        );
      }
      return const TunStatus(
        instanceId: 'deferred-cold-start',
        revision: 0,
        state: 'off',
        listenerActive: false,
        interfaceState: 'notApplicable',
        privilege: 'unprivileged',
        requestedEnabled: false,
      );
    }
    _loggedDeferredTunNotReady = false;
    return super.getTunStatus();
  }

  @override
  Future<void> sendMessage(String message) async {
    if (hasDeferredAgentLaunch) {
      _failPendingCompleter(message, 'Agent launch deferred');
      return;
    }
    if (_stopping || _detaching) {
      _failPendingCompleter(
        message,
        _detaching ? 'Agent socket detaching' : 'Backend stopping',
      );
      return;
    }
    try {
      if (_agentMode) {
        await _coreReadyCompleter.future.timeout(const Duration(seconds: 20));
        if (_stopping || _detaching || !socketCompleter.isCompleted) {
          _failPendingCompleter(message, 'Agent socket unavailable');
          return;
        }
      }
      final socket = await socketCompleter.future;
      _writeSocketLine(socket, message);
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
    final fastId = extractActionIdFast(message);
    if (fastId != null) {
      _completePendingWithDefault(fastId, reason);
      return;
    }
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
    var def = callbackDefaultMap.remove(id);
    if (def is Result &&
        def.isError &&
        def.message.startsWith('not_ready:') &&
        reason == 'Agent Core unavailable') {
      def = Result.error('not_ready:core_unavailable');
    }
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
    for (final completer in _strictIdentityCompleters.values) {
      if (!completer.isCompleted) completer.complete(null);
    }
    _strictIdentityCompleters.clear();
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
        return await _agentConnections.replace(() async {
          if (hasDeferredAgentLaunch || !socketCompleter.isCompleted) {
            _agentLaunchDeferred = false;
            await _detachAgentSocket();
            return true;
          }
          return _agentCommand(AgentCommand.stopCore);
        });
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
    return _agentConnections.replace(() async {
      _agentLaunchDeferred = false;
      return _detachAgentSocket();
    });
  }

  Future<bool> _detachAgentSocket() async {
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
      onTunTransportChanged?.call();
    }
  }
}

final clashService = system.isDesktop ? ClashService() : null;

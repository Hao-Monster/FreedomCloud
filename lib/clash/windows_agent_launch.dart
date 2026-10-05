import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

typedef AgentLaunchPaths = ({String agent, String core});

/// Resolving protected files is part of launching, so failures follow the same
/// retry/reporting path as Process.start, including background reconnection.
Future<bool> tryStartAgentProcess({
  required Future<AgentLaunchPaths> Function() resolvePaths,
  required Future<List<String>> Function(String core) buildArguments,
  required void Function(Object error) onError,
  Future<void> Function(String agent, List<String> arguments)? startProcess,
}) async {
  try {
    final paths = await resolvePaths();
    final arguments = await buildArguments(paths.core);
    if (startProcess != null) {
      await startProcess(paths.agent, arguments);
    } else {
      await Process.start(
        paths.agent,
        arguments,
        mode: ProcessStartMode.detached,
      );
    }
    return true;
  } catch (error) {
    onError(error);
    return false;
  }
}

/// Select the protected strict components only when they match this app's bundle.
/// Broker still independently enforces the directory ACL, signature and manifest.
Future<AgentLaunchPaths> windowsAgentLaunchPaths({
  required String bundledAgent,
  required String bundledCore,
  required String serviceDirectory,
}) async {
  if (!File(p.join(serviceDirectory, 'FlClashStrictBroker.exe')).existsSync()) {
    return (agent: bundledAgent, core: bundledCore);
  }
  final agent = p.join(serviceDirectory, 'FlClashAgent.exe');
  final core = p.join(serviceDirectory, 'FlClashCore.exe');
  for (final pair in [(bundledAgent, agent), (bundledCore, core)]) {
    final bundled = await sha256.bind(File(pair.$1).openRead()).first;
    final installed = await sha256.bind(File(pair.$2).openRead()).first;
    if (bundled != installed) {
      throw StateError(
        'Strict component does not match this portable package: '
        '${pair.$2}. Update the protected installation before launching.',
      );
    }
  }
  return (agent: agent, core: core);
}

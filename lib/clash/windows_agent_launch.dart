import 'dart:io';

import 'package:flclashx/common/file_digest.dart';
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
    final digests = await Future.wait([
      fileSha256(pair.$1),
      fileSha256(pair.$2),
    ]);
    if (digests[0] != digests[1]) {
      throw StateError(
        'Strict component does not match this portable package: '
        '${pair.$2}. Update the protected installation before launching.',
      );
    }
  }
  return (agent: agent, core: core);
}

Future<bool> windowsInstalledHelperFilesMatch({
  required String bundledHelper,
  required String bundledCore,
  required String installedHelper,
  required String installedCore,
}) async {
  try {
    if (!File(installedHelper).existsSync() ||
        !File(installedCore).existsSync()) {
      return false;
    }
    final (helperExpected, helperActual, coreExpected, coreActual) = await (
      fileSha256(bundledHelper),
      fileSha256(installedHelper),
      fileSha256(bundledCore),
      fileSha256(installedCore),
    ).wait;
    return helperExpected == helperActual && coreExpected == coreActual;
  } catch (_) {
    return false;
  }
}

Future<bool> shouldLaunchWindowsAgentWithHelper({
  required bool tunDesired,
  required Future<bool> Function() isHelperRunning,
  required Future<bool> Function() installedFilesMatch,
  required Future<bool> Function() tryStartExistingHelper,
}) async {
  if (await isHelperRunning()) return true;
  if (!tunDesired) return false;
  if (!await installedFilesMatch()) return false;
  return tryStartExistingHelper();
}

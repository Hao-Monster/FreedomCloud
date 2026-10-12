import 'dart:io';

import 'package:crypto/crypto.dart';

/// A compatibility preflight, not an authentication or signature assertion.
/// The Helper's existing authenticated start/stop endpoints remain authoritative.
Future<bool> windowsHelperIsCompatible({
  required Future<Object?> Function() readCapabilities,
  required Future<String?> Function() bundledCoreSha256,
  required String bundledHelper,
  required String installedHelper,
  required String installedCore,
}) async {
  try {
    final capabilities = await readCapabilities();
    final expectedCore = await bundledCoreSha256();
    if (expectedCore == null ||
        capabilities is! Map ||
        capabilities['schemaVersion'] != 1 ||
        capabilities['stopAcknowledgesExit'] != true ||
        capabilities['ownedStop'] != true ||
        capabilities['allowedCoreSha256'] != expectedCore) return false;
    final actualCore = await sha256.bind(File(installedCore).openRead()).first;
    if (actualCore.toString() != expectedCore) return false;
    final bundled = await sha256.bind(File(bundledHelper).openRead()).first;
    final installed = await sha256.bind(File(installedHelper).openRead()).first;
    return bundled == installed;
  } catch (_) {
    return false;
  }
}

import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flclashx/common/windows_helper_compatibility.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late File bundledHelper, installedHelper, installedCore;
  final coreBytes = [1, 2, 3];
  final coreHash = sha256.convert(coreBytes).toString();
  final good = {
    'schemaVersion': 1,
    'stopAcknowledgesExit': true,
    'ownedStop': true,
    'allowedCoreSha256': coreHash
  };
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('tun-helper-test-');
    bundledHelper = File('${directory.path}/bundle-helper');
    installedHelper = File('${directory.path}/service-helper');
    installedCore = File('${directory.path}/service-core');
    await bundledHelper.writeAsBytes([4, 5, 6]);
    await installedHelper.writeAsBytes([4, 5, 6]);
    await installedCore.writeAsBytes(coreBytes);
  });
  tearDown(() => directory.delete(recursive: true));
  Future<bool> verify(Object? metadata) => windowsHelperIsCompatible(
        readCapabilities: () async => metadata,
        bundledCoreSha256: () async => coreHash,
        bundledHelper: bundledHelper.path,
        installedHelper: installedHelper.path,
        installedCore: installedCore.path,
      );
  test('current capability and all installed bytes match', () async {
    expect(await verify(good), isTrue);
  });
  for (final metadata in [
    null,
    {},
    {...good, 'stopAcknowledgesExit': false},
    {...good, 'ownedStop': null},
    {...good, 'schemaVersion': 2},
    {...good, 'allowedCoreSha256': 'other'}
  ]) {
    test('old or incompatible Helper metadata $metadata is rejected', () async {
      expect(await verify(metadata), isFalse);
    });
  }
  test('installed Core mismatch is found before migration', () async {
    await installedCore.writeAsBytes([9]);
    expect(await verify(good), isFalse);
  });
  test('old installed Helper is rejected even with matching metadata',
      () async {
    await installedHelper.writeAsBytes([9]);
    expect(await verify(good), isFalse);
  });
  test('missing service Core is rejected', () async {
    await installedCore.delete();
    expect(await verify(good), isFalse);
  });
}

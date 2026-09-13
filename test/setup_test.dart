import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../setup.dart' as setup;

void main() {
  test('release hashing streams large binaries within the build budget',
      () async {
    final directory = await Directory.systemTemp.createTemp('flclashx-hash-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}core.bin');
    final bytes = List<int>.generate(
      12 * 1024 * 1024,
      (index) => index & 0xff,
      growable: false,
    );
    await file.writeAsBytes(bytes, flush: true);
    final expected = sha256.convert(bytes).toString();

    final stopwatch = Stopwatch()..start();
    final actual = await setup.Build.calcSha256(file.path);
    stopwatch.stop();

    expect(actual, expected);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
  }, timeout: const Timeout(Duration(seconds: 10)));

  test('desktop release packaging always carries the background Agent', () {
    final root = Directory.current.path;
    final setupSource =
        File('$root${Platform.pathSeparator}setup.dart').readAsStringSync();
    final windowsCmake = File(
      '$root${Platform.pathSeparator}windows${Platform.pathSeparator}CMakeLists.txt',
    ).readAsStringSync();
    final linuxCmake = File(
      '$root${Platform.pathSeparator}linux${Platform.pathSeparator}CMakeLists.txt',
    ).readAsStringSync();
    final macProject = File(
      '$root${Platform.pathSeparator}macos${Platform.pathSeparator}Runner.xcodeproj${Platform.pathSeparator}project.pbxproj',
    ).readAsStringSync();

    expect(setupSource, contains('Build.buildAgent(target, arch: arch)'));
    expect(windowsCmake, contains('FlClashAgent.exe'));
    expect(linuxCmake, contains('FlClashAgent'));
    expect(macProject, contains('FlClashAgent in CopyFiles'));
  });

  test('Windows test package embeds immutable build identity and VM checklist',
      () async {
    final directory = await Directory.systemTemp.createTemp('flclashx-meta-');
    addTearDown(() => directory.delete(recursive: true));
    const commit = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final builtAt = DateTime.utc(2026, 8, 29, 1, 2, 3);

    await setup.Build.writeWindowsTestPackageMetadata(
      directory.path,
      commit: commit,
      builtAt: builtAt,
      flutterVersion: '3.47.4',
    );

    final buildInfo = File(
      '${directory.path}${Platform.pathSeparator}BUILD-INFO.txt',
    ).readAsStringSync();
    final checklist = File(
      '${directory.path}${Platform.pathSeparator}WINDOWS-VM-CHECKLIST.md',
    );
    final collector = File(
      '${directory.path}${Platform.pathSeparator}Collect-FlClashXLogs.ps1',
    );
    expect(buildInfo, contains('Source commit: $commit'));
    expect(buildInfo, contains('2026-08-29T01:02:03.000Z'));
    expect(buildInfo, contains('Flutter: 3.47.4'));
    expect(buildInfo, isNot(contains('{{')));
    expect(await checklist.exists(), isTrue);
    expect(await collector.exists(), isTrue);
    expect(collector.readAsStringSync(), contains('log-inventory.json'));
  });

  test('Windows portable package manifest is sorted and excludes itself',
      () async {
    final directory = await Directory.systemTemp.createTemp('flclashx-sums-');
    addTearDown(() => directory.delete(recursive: true));
    await File('${directory.path}${Platform.pathSeparator}z.txt')
        .writeAsString('z', flush: true);
    final nested = Directory(
      '${directory.path}${Platform.pathSeparator}data',
    )..createSync();
    await File('${nested.path}${Platform.pathSeparator}a.txt')
        .writeAsString('a', flush: true);

    await setup.Build.writeWindowsPackageChecksums(directory.path);

    final manifest = File(
      '${directory.path}${Platform.pathSeparator}SHA256SUMS.txt',
    ).readAsLinesSync();
    expect(manifest, hasLength(2));
    expect(manifest[0], endsWith('data/a.txt'));
    expect(manifest[1], endsWith('z.txt'));
    expect(manifest.join('\n'), isNot(contains('SHA256SUMS.txt')));
  });
}

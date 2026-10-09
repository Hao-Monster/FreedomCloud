import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flclashx/common/zashboard.dart';
import 'package:flclashx/common/file_logger.dart';
import 'package:flclashx/common/zashboard_archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.directory);
  final String directory;
  @override
  Future<String> getApplicationSupportPath() async => directory;
  @override
  Future<String> getTemporaryPath() async => directory;
  @override
  Future<String> getDownloadsPath() async => directory;
}

class _ArchiveAdapter implements HttpClientAdapter {
  _ArchiveAdapter(this.bytes, {this.gate, this.advertisedBytes});
  final List<int> bytes;
  final Future<void>? gate;
  final int? advertisedBytes;
  int requests = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests++;
    expect(options.uri.toString(), zashboardDistUrl);
    if (gate != null) await gate;
    return ResponseBody.fromBytes(bytes, 200, headers: {
      if (advertisedBytes != null)
        Headers.contentLengthHeader: ['$advertisedBytes'],
    });
  }

  @override
  void close({bool force = false}) {}
}

List<int> zip(List<ArchiveFile> files) {
  final archive = Archive();
  for (final file in files) {
    archive.addFile(file);
  }
  return ZipEncoder().encode(archive);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late String target;
  late Dio client;
  late Directory logs;
  final originalPaths = PathProviderPlatform.instance;
  setUpAll(() async {
    logs = await Directory.systemTemp.createTemp('flclashx-zip-logs-');
    PathProviderPlatform.instance = _Paths(logs.path);
  });
  tearDownAll(() async {
    await fileLogger.dispose();
    PathProviderPlatform.instance = originalPaths;
    await logs.delete(recursive: true);
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('flclashx-zip-test-');
    target = p.join(root.path, 'panel');
    client = Dio();
  });
  tearDown(() async {
    client.close(force: true);
    await root.delete(recursive: true);
  });

  Future<bool> install(
    List<int> bytes, {
    ZashboardLimits limits = const ZashboardLimits(),
    CancelToken? cancel,
  }) {
    client.httpClientAdapter = _ArchiveAdapter(bytes);
    return ensureZashboardUi(
        directory: target, client: client, cancelToken: cancel, limits: limits);
  }

  test('nested bundle installs only after all files validate', () async {
    expect(
        await install(zip([
          ArchiveFile.string('dist/index.html', '<html>ready</html>'),
          ArchiveFile.string(r'dist\assets\app.js', 'ok'),
        ])),
        isTrue);
    expect(await File(p.join(target, 'assets', 'app.js')).readAsString(), 'ok');
    expect(await root.list().length, 1);
  });

  for (final path in [
    'dist/../escaped.txt',
    r'dist\..\escaped.txt',
    '/absolute.txt',
    r'C:\escape.txt',
    r'\\server\share\bad.txt',
    'dist/file:stream',
    'dist/NUL.txt',
    'dist/trailing.'
  ]) {
    test('reject unsafe archive path $path before installing index', () async {
      expect(
          await install(zip([
            ArchiveFile.string('dist/index.html', 'ready'),
            ArchiveFile.string(path, 'bad'),
          ])),
          isFalse);
      expect(await File(p.join(target, 'index.html')).exists(), isFalse);
      expect(await root.list().isEmpty, isTrue);
    });
  }

  test('reject symlink entries before reading their contents', () async {
    expect(
        await install(zip([
          ArchiveFile.string('dist/index.html', 'ready'),
          ArchiveFile.string('dist/link', '../outside')..mode = 0xa1ff,
        ])),
        isFalse);
    expect(await root.list().isEmpty, isTrue);
  });

  test('reject case-colliding paths on all platforms', () async {
    expect(
        await install(zip([
          ArchiveFile.string('dist/index.html', 'ready'),
          ArchiveFile.string('dist/asset.js', 'one'),
          ArchiveFile.string('dist/ASSET.js', 'two'),
        ])),
        isFalse);
  });

  test('missing index and corrupt ZIP leave no installed directory', () async {
    expect(
        await install(zip([ArchiveFile.string('dist/a.js', 'one')])), isFalse);
    expect(await install([1, 2, 3]), isFalse);
    expect(await root.list().isEmpty, isTrue);
  });

  test('enforces download, file, total and actual entry budgets', () async {
    final bytes = zip([
      ArchiveFile.string('dist/index.html', '12345678'),
      ArchiveFile.string('dist/a.js', '12345678'),
    ]);
    for (final limits in [
      const ZashboardLimits(downloadBytes: 10),
      const ZashboardLimits(fileBytes: 4),
      const ZashboardLimits(totalBytes: 12),
      const ZashboardLimits(entries: 1),
    ]) {
      expect(await install(bytes, limits: limits), isFalse);
      expect(await root.list().isEmpty, isTrue);
    }
  });

  test('lying uncompressed size cannot overrun the extraction sink', () async {
    final bytes = Uint8List.fromList(zip([
      ArchiveFile.string('dist/index.html', 'x' * 1000),
    ]));
    final data = ByteData.sublistView(bytes);
    data.setUint32(22, 1, Endian.little);
    for (var i = 0; i + 46 < bytes.length; i++) {
      if (data.getUint32(i, Endian.little) == 0x02014b50) {
        data.setUint32(i + 24, 1, Endian.little);
        break;
      }
    }
    expect(await install(bytes), isFalse);
    expect(await root.list().isEmpty, isTrue);
  });

  test('reject comment containing a second EOCD before decoder selection',
      () async {
    final original = zip([ArchiveFile.string('index.html', 'ready')]);
    final bytes = Uint8List(original.length + 22)..setAll(0, original);
    final data = ByteData.sublistView(bytes);
    data.setUint16(original.length - 2, 22, Endian.little);
    data.setUint32(original.length, 0x06054b50, Endian.little);
    // This fake EOCD is not self-consistent, but archive's backward signature
    // search would select it unless we reject comments before parsing.
    data.setUint16(bytes.length - 2, 1, Endian.little);
    expect(await install(bytes), isFalse);
    expect(await root.list().isEmpty, isTrue);
  });

  test('reject long local filename and encrypted headers before parsing',
      () async {
    for (final offset in [26, 6]) {
      final bytes =
          Uint8List.fromList(zip([ArchiveFile.string('index.html', 'ready')]));
      ByteData.sublistView(bytes)
          .setUint16(offset, offset == 26 ? 65535 : 1, Endian.little);
      expect(await install(bytes), isFalse);
      expect(await root.list().isEmpty, isTrue);
    }
  });

  test('reject oversized Content-Length without installing', () async {
    client.httpClientAdapter = _ArchiveAdapter([0], advertisedBytes: 1000);
    expect(
        await ensureZashboardUi(
            directory: target,
            client: client,
            limits: const ZashboardLimits(downloadBytes: 100)),
        isFalse);
    expect(await root.list().isEmpty, isTrue);
  });

  test('existing complete or unrelated directory is preserved', () async {
    await Directory(target).create();
    final index = File(p.join(target, 'index.html'));
    await index.writeAsString('old panel');
    expect(await install([0]), isTrue);
    expect(await index.readAsString(), 'old panel');
    await index.delete();
    final unrelated = File(p.join(target, 'keep.txt'));
    await unrelated.writeAsString('keep');
    expect(
        await install(zip([ArchiveFile.string('index.html', 'new')])), isFalse);
    expect(await unrelated.readAsString(), 'keep');
  });

  test('same target shares one in-flight download and installation', () async {
    final gate = Completer<void>();
    final adapter = _ArchiveAdapter(
        zip([ArchiveFile.string('dist/index.html', 'ready')]),
        gate: gate.future);
    client.httpClientAdapter = adapter;
    final first = ensureZashboardUi(directory: target, client: client);
    final second = ensureZashboardUi(directory: target, client: client);
    expect(identical(first, second), isTrue);
    gate.complete();
    expect(await Future.wait([first, second]), [true, true]);
    expect(adapter.requests, 1);
  });

  test(
      'cancelled and timed-out downloads do not install or occupy single-flight',
      () async {
    final cancelled = CancelToken()..cancel();
    expect(await install([0], cancel: cancelled), isFalse);
    final gate = Completer<void>();
    client.httpClientAdapter = _ArchiveAdapter([0], gate: gate.future);
    expect(
        await ensureZashboardUi(
            directory: target,
            client: client,
            limits: const ZashboardLimits(timeout: Duration(milliseconds: 20))),
        isFalse);
    gate.complete();
    expect(await root.list().isEmpty, isTrue);
    expect(await install(zip([ArchiveFile.string('index.html', 'ready')])),
        isTrue);
  });

  test('filesystem failure preserves the existing file', () async {
    await File(target).writeAsString('unrelated file');
    expect(await install(zip([ArchiveFile.string('index.html', 'ready')])),
        isFalse);
    expect(await File(target).readAsString(), 'unrelated file');
    expect(await root.list().length, 1);
  });
}

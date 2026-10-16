import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flclashx/common/node_catalog_provider_resolver.dart';
import 'package:flclashx/common/node_catalog_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _NativeHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context);
}

void main() {
  late Directory home;
  late int fetched;
  late Uint8List parsed;
  late CatalogProviderResolver resolver;
  setUp(() async {
    home = await Directory.systemTemp.createTemp('catalog-provider-fixture-');
    fetched = 0;
    parsed = Uint8List(0);
    resolver = CatalogProviderResolver(
      homeDirectory: () async => home.path,
      httpCachePath: (id, url) async =>
          p.join(home.path, 'profiles', 'providers', id, 'proxies', 'cache'),
      fetch: (uri, headers, limit, current) async {
        fetched++;
        return Uint8List.fromList(utf8.encode('download'));
      },
      parse: (content, definition) async {
        parsed = base64Decode(content);
        return jsonEncode({
          'proxies': [
            {
              'name': 'A',
              'type': 'ss',
              'server': 'fixture.invalid',
              'port': 443,
              'password': 'PRIVATE'
            }
          ],
          'rejected': 0
        });
      },
    );
  });
  tearDown(() async {
    await home.delete(recursive: true);
  });

  test(
      'managed cache is read and missing HTTP cache downloads only into memory',
      () async {
    final definition = {
      'type': 'http',
      'url': 'https://fixture.invalid/private-token'
    };
    final path = await resolver.httpCachePath('p', definition['url']!);
    final first = await resolver.resolve('p', 'remote', definition,
        isCurrent: () => true);
    expect(first.issues, isEmpty);
    expect(fetched, 1);
    expect(await File(path).exists(), isFalse);
    await File(path).parent.create(recursive: true);
    await File(path).writeAsString('cached');
    await resolver.resolve('p', 'remote', definition, isCurrent: () => true);
    expect(utf8.decode(parsed), 'cached');
    expect(fetched, 1);
    expect(await File(path).readAsString(), 'cached');
  });

  test('inline and local file never download; outside home is rejected',
      () async {
    await File(p.join(home.path, 'nodes.yaml')).writeAsString('file-data');
    final local = await resolver.resolve(
        'p', 'local', {'type': 'file', 'path': 'nodes.yaml'},
        isCurrent: () => true);
    expect(local.issues, isEmpty);
    expect(utf8.decode(parsed), 'file-data');
    final inline = await resolver.resolve(
        'p', 'inline', {'type': 'inline', 'payload': []},
        isCurrent: () => true);
    expect(inline.issues, isEmpty);
    expect(parsed, isEmpty);
    final bad = await resolver.resolve(
        'p', 'escape', {'type': 'file', 'path': '../PRIVATE'},
        isCurrent: () => true);
    expect(bad.issues.single.reason, 'providerUnsafePath');
    expect(fetched, 0);
  });

  test('unknown source and missing local file are explicit provider issues',
      () async {
    final unknown = await resolver.resolve('p', 'x', {'type': 'other'},
        isCurrent: () => true);
    expect(unknown.issues.single.reason, 'providerOptionsUnsupported');
    final missing = await resolver.resolve(
        'p', 'x', {'type': 'file', 'path': 'missing'},
        isCurrent: () => true);
    expect(missing.issues.single.reason, 'providerNotCached');
  });

  test('parse failures and rejected URI counts contain no raw secrets',
      () async {
    final reject = CatalogProviderResolver(
        homeDirectory: () async => home.path,
        httpCachePath: (_, __) async => '',
        parse: (_, __) async => jsonEncode({'proxies': [], 'rejected': 2}));
    final result = await reject.resolve('p', 'source', {'type': 'inline'},
        isCurrent: () => true);
    expect(result.issues.single.count, 2);
    final fail = CatalogProviderResolver(
        homeDirectory: () async => home.path,
        httpCachePath: (_, __) async => '',
        parse: (_, __) async => throw Exception('PRIVATE'));
    final failed = await fail.resolve('p', 'source', {'type': 'inline'},
        isCurrent: () => true);
    expect(failed.issues.single.reason, 'parseFailed');
  });

  test('cancelled parse cannot return nodes', () async {
    var current = true;
    final gate = Completer<String>();
    final delayed = CatalogProviderResolver(
        homeDirectory: () async => home.path,
        httpCachePath: (_, __) async => '',
        parse: (_, __) => gate.future);
    final future = delayed.resolve('p', 'source', {'type': 'inline'},
        isCurrent: () => current);
    current = false;
    gate.complete(jsonEncode({'proxies': [], 'rejected': 0}));
    await expectLater(
        future,
        throwsA(isA<CatalogBuildException>()
            .having((e) => e.reason, 'reason', 'cancelled')));
  });

  test(
      'HTTP boundary enforces size and refuses cross-origin credential forwarding',
      () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final destination =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final source = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var forwarded = 0;
      destination.listen((r) {
        forwarded++;
        r.response.close();
      });
      source.listen((r) {
        if (r.uri.path == '/redirect') {
          r.response.statusCode = 302;
          r.response.headers.set(HttpHeaders.locationHeader,
              'http://127.0.0.1:${destination.port}/private');
        } else {
          r.response.write('12345');
        }
        r.response.close();
      });
      try {
        final base = Uri.parse('http://127.0.0.1:${source.port}');
        await expectLater(
            fetchCatalogProvider(base.resolve('/large'), {}, 4, () => true),
            throwsA(isA<CatalogBuildException>()
                .having((e) => e.reason, 'reason', 'providerTooLarge')));
        await expectLater(
            fetchCatalogProvider(
                base.resolve('/redirect'),
                {
                  'Authorization': ['PRIVATE']
                },
                100,
                () => true),
            throwsA(isA<CatalogBuildException>()
                .having((e) => e.reason, 'reason', 'providerUnsafeUrl')));
        expect(forwarded, 0);
      } finally {
        await source.close(force: true);
        await destination.close(force: true);
      }
    }, _NativeHttp());
  });

  test('HTTP cancellation aborts a pending body without a late success',
      () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final arrived = Completer<void>();
      server.listen((request) {
        arrived.complete();
      });
      var current = true;
      try {
        final future = fetchCatalogProvider(
            Uri.parse('http://127.0.0.1:${server.port}/'),
            {},
            100,
            () => current);
        await arrived.future;
        current = false;
        await expectLater(
            future.timeout(const Duration(seconds: 2)),
            throwsA(isA<CatalogBuildException>()
                .having((e) => e.reason, 'reason', 'cancelled')));
      } finally {
        await server.close(force: true);
      }
    }, _NativeHttp());
  });
}

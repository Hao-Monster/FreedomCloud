import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/models/xboard.dart';
import 'package:flclashx/views/purchase/plan_catalog.dart';
import 'package:flclashx/views/purchase/plan_content.dart';
import 'package:flclashx/views/purchase/plan_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _source = 'https://images.test.invalid/plan.png';

Uint8List _png({int width = 1, int height = 1, bool headerOnly = false}) {
  final dimensions = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8)
    ..setUint8(9, 6);
  final output = BytesBuilder()..add([137, 80, 78, 71, 13, 10, 26, 10]);
  void chunk(String name, List<int> data) {
    final contents = [...ascii.encode(name), ...data];
    var crc = 0xffffffff;
    for (final byte in contents) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0);
      }
    }
    output
      ..add((ByteData(4)..setUint32(0, data.length)).buffer.asUint8List())
      ..add(contents)
      ..add((ByteData(4)..setUint32(0, crc ^ 0xffffffff)).buffer.asUint8List());
  }

  chunk('IHDR', dimensions.buffer.asUint8List());
  chunk(
      'IDAT',
      ZLibEncoder()
          .convert(Uint8List(headerOnly ? 5 : (width * 4 + 1) * height)));
  chunk('IEND', []);
  return output.takeBytes();
}

class _Headers implements HttpHeaders {
  final values = <String, List<String>>{};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      values[name.toLowerCase()] = [value.toString()];

  @override
  void removeAll(String name) => values.remove(name.toLowerCase());

  @override
  String? value(String name) => values[name.toLowerCase()]?.join(',');

  @override
  ContentType? get contentType => value(HttpHeaders.contentTypeHeader) == null
      ? null
      : ContentType.parse(value(HttpHeaders.contentTypeHeader)!);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(
    this.body, {
    this.statusCode = 200,
    this.contentLength = -1,
    String? mime = 'image/png',
    String? encoding,
  }) {
    if (mime != null) headers.set(HttpHeaders.contentTypeHeader, mime);
    if (encoding != null) {
      headers.set(HttpHeaders.contentEncodingHeader, encoding);
    }
  }

  final Stream<List<int>> body;
  @override
  final int statusCode;
  @override
  final int contentLength;
  @override
  final _Headers headers = _Headers();
  int subscriptions = 0;
  int cancellations = 0;

  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    subscriptions++;
    return _Subscription(
        body.listen(onData,
            onError: onError, onDone: onDone, cancelOnError: cancelOnError),
        () => cancellations++);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Subscription<T> implements StreamSubscription<T> {
  _Subscription(this.inner, this.onCancel);
  final StreamSubscription<T> inner;
  final void Function() onCancel;

  @override
  Future<void> cancel() {
    onCancel();
    return inner.cancel();
  }

  @override
  Future<E> asFuture<E>([E? futureValue]) => inner.asFuture(futureValue);
  @override
  bool get isPaused => inner.isPaused;
  @override
  void onData(void Function(T)? handleData) => inner.onData(handleData);
  @override
  void onDone(void Function()? handleDone) => inner.onDone(handleDone);
  @override
  void onError(Function? handleError) => inner.onError(handleError);
  @override
  void pause([Future<void>? resumeSignal]) => inner.pause(resumeSignal);
  @override
  void resume() => inner.resume();
}

class _Request implements HttpClientRequest {
  _Request(this.response);
  final Future<HttpClientResponse> response;
  @override
  final _Headers headers = _Headers();
  @override
  final List<Cookie> cookies = [];
  @override
  bool followRedirects = true;
  @override
  int maxRedirects = 5;
  int aborts = 0;

  @override
  Future<HttpClientResponse> close() => response;
  @override
  void abort([Object? exception, StackTrace? stackTrace]) => aborts++;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements HttpClient {
  _Client(this.request, {this.pendingRequest});
  final _Request request;
  final Future<HttpClientRequest>? pendingRequest;
  final requests = <Uri>[];
  bool closed = false;
  bool forceClosed = false;
  bool Function(X509Certificate, String, int)? certificateCallback;
  String Function(Uri)? proxy;
  @override
  Duration? connectionTimeout;
  @override
  bool autoUncompress = true;
  @override
  Future<bool> Function(Uri, String, String?)? authenticate;

  @override
  set badCertificateCallback(
          bool Function(X509Certificate, String, int)? value) =>
      certificateCallback = value;
  @override
  set findProxy(String Function(Uri)? value) => proxy = value;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requests.add(url);
    return pendingRequest ?? request;
  }

  @override
  void close({bool force = false}) {
    closed = true;
    forceClosed = force;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Certificate implements X509Certificate {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, Widget child,
    {double? width, double scale = 1}) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.delegate.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, child) => MediaQuery(
      data:
          MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        child: Center(child: SizedBox(width: width, child: child)),
      ),
    ),
  ));
  await tester.pump();
}

Widget _image({String source = _source, String alt = 'Plan diagram'}) =>
    PurchasePlanImage(source: source, alt: alt, maxWidth: 120);

Widget _gallery(Iterable<int> indexes) => Wrap(
      children: [
        for (final index in indexes)
          PurchasePlanImage(
            key: ValueKey('gallery-$index'),
            source: '$_source?image=$index',
            alt: 'Diagram $index',
            maxWidth: 120,
          ),
      ],
    );

Future<void> _waitUntil(
    WidgetTester tester, bool Function() ready, String description) async {
  for (var frame = 0; frame < 100; frame++) {
    if (ready()) return;
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
  fail(description);
}

Future<void> _waitForImage(WidgetTester tester, {int count = 1}) async {
  for (var frame = 0; frame < 100; frame++) {
    if (tester
            .widgetList<RawImage>(find.byType(RawImage))
            .where((image) => image.image != null)
            .length >=
        count) {
      return;
    }
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
  fail('The synthetic raster did not render');
}

void main() {
  testWidgets('HTTPS raster renders within card width with alt semantics',
      (tester) async {
    final response = _Response(Stream.value(_png()));
    final client = _Client(_Request(Future.value(response)));
    await HttpOverrides.runZoned(() async {
      await _pump(tester, _image());
      await _waitForImage(tester);
      expect(
          tester.getSize(find.byType(RawImage)).width, lessThanOrEqualTo(120));
      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel('Plan diagram'), findsOneWidget);
      semantics.dispose();
      expect(find.textContaining(_source), findsNothing);
      expect(client.closed, isTrue);
      expect(client.requests, [Uri.parse(_source)]);
    }, createHttpClient: (_) => client);
  });

  testWidgets('rejects global trust-all but retains proxy and sends no secrets',
      (tester) async {
    final client =
        _Client(_Request(Future.value(_Response(Stream.value(_png())))))
          ..badCertificateCallback = ((_, __, ___) => true)
          ..findProxy = ((_) => 'PROXY localhost:7890');
    client.request
      ..headers.set(HttpHeaders.authorizationHeader, 'Bearer fixture')
      ..headers.set(HttpHeaders.cookieHeader, 'session=fixture')
      ..headers.set(HttpHeaders.refererHeader, 'https://account.test.invalid')
      ..cookies.add(Cookie('session', 'fixture'));
    await HttpOverrides.runZoned(() async {
      await _pump(tester, _image());
      await _waitForImage(tester);
      expect(client.certificateCallback?.call(_Certificate(), 'x.invalid', 443),
          isFalse);
      expect(client.proxy?.call(Uri.parse(_source)), 'PROXY localhost:7890');
      for (final name in [
        HttpHeaders.authorizationHeader,
        HttpHeaders.cookieHeader,
        HttpHeaders.refererHeader,
      ]) {
        expect(client.request.headers.value(name), isNull);
      }
      expect(client.request.cookies, isEmpty);
      expect(client.request.followRedirects, isFalse);
      expect(client.request.maxRedirects, 0);
      expect(client.autoUncompress, isFalse);
      expect(client.connectionTimeout, isNotNull);
    }, createHttpClient: (_) => client);
  });

  testWidgets('unsafe and malformed sources never construct a network client',
      (tester) async {
    var clients = 0;
    await HttpOverrides.runZoned(() async {
      for (final source in [
        'http://images.test.invalid/a.png',
        'file:///private/image.png',
        'data:image/png;base64,fixture',
        '/relative/image.png',
        '//images.test.invalid/a.png',
        'https://name:secret@images.test.invalid/a.png',
        'https://',
        'https://[invalid/image.png',
        'https://bad host/image.png',
        'https://images.test.invalid:invalid/image.png',
        r'https://images.test.invalid\other/image.png',
        '',
      ]) {
        await _pump(tester, _image(source: source));
        expect(find.textContaining('Plan diagram'), findsOneWidget);
        expect(find.byType(RawImage), findsNothing);
      }
      expect(clients, 0);
    }, createHttpClient: (_) {
      clients++;
      throw StateError('Unsafe URLs must not reach the network');
    });
  });

  testWidgets('redirect responses are not followed', (tester) async {
    final response = _Response(Stream.value(_png()), statusCode: 302)
      ..headers.set(HttpHeaders.locationHeader, 'https://other.invalid/a.png');
    final client = _Client(_Request(Future.value(response)));
    await HttpOverrides.runZoned(() async {
      await _pump(tester, _image());
      await tester.pumpAndSettle();
      expect(client.requests, hasLength(1));
      expect(client.request.followRedirects, isFalse);
      expect(response.subscriptions, 0);
      expect(find.byType(RawImage), findsNothing);
      expect(find.textContaining('Plan diagram'), findsOneWidget);
      expect(client.forceClosed, isTrue);
    }, createHttpClient: (_) => client);
  });

  testWidgets('oversize declared response is rejected before reading its body',
      (tester) async {
    final response = _Response(Stream.value(_png()), contentLength: 4194305);
    final client = _Client(_Request(Future.value(response)));
    await HttpOverrides.runZoned(() async {
      await _pump(tester, _image());
      await tester.pumpAndSettle();
      expect(response.subscriptions, 0);
      expect(client.forceClosed, isTrue);
      expect(find.byType(RawImage), findsNothing);
    }, createHttpClient: (_) => client);
  });

  testWidgets('streamed response cannot bypass the four MiB download limit',
      (tester) async {
    final response = _Response(Stream.fromIterable([
      Uint8List(2097152),
      Uint8List(2097152),
      Uint8List(1),
    ]));
    final client = _Client(_Request(Future.value(response)));
    await HttpOverrides.runZoned(() async {
      await _pump(tester, _image());
      await tester.pumpAndSettle();
      expect(response.subscriptions, 1);
      expect(response.cancellations, greaterThanOrEqualTo(1));
      expect(client.request.aborts, greaterThanOrEqualTo(1));
      expect(client.forceClosed, isTrue);
      expect(find.byType(RawImage), findsNothing);
    }, createHttpClient: (_) => client);
  });

  testWidgets('HTTP compression does not bypass the encoded byte limit',
      (tester) async {
    final response = _Response(Stream.value(_png()), encoding: 'gzip');
    final client = _Client(_Request(Future.value(response)));
    await HttpOverrides.runZoned(() async {
      await _pump(tester, _image());
      await tester.pumpAndSettle();
      expect(response.subscriptions, 0);
      expect(client.autoUncompress, isFalse);
      expect(find.byType(RawImage), findsNothing);
    }, createHttpClient: (_) => client);
  });

  testWidgets('response stream failures close the client and release its slot',
      (tester) async {
    final response = _Response(
        Stream<List<int>>.error(const SocketException('Synthetic disconnect')));
    final client = _Client(_Request(Future.value(response)));
    await HttpOverrides.runZoned(() async {
      await _pump(tester, _image());
      await tester.pumpAndSettle();
      expect(response.subscriptions, 1);
      expect(client.forceClosed, isTrue);
      expect(PurchasePlanImage.debugResources.activeLoads, 0);
      expect(PurchasePlanImage.debugResources.reservedPixels, 0);
      expect(find.byType(RawImage), findsNothing);
      expect(find.textContaining('Plan diagram'), findsOneWidget);
      expect(find.textContaining(_source), findsNothing);
      expect(tester.takeException(), isNull);
    }, createHttpClient: (_) => client);
  });

  testWidgets('HTML and unsupported SVG responses remain readable fallbacks',
      (tester) async {
    for (final mime in ['text/html', 'image/svg+xml']) {
      final response = _Response(Stream.value(_png()), mime: mime);
      final client = _Client(_Request(Future.value(response)));
      await HttpOverrides.runZoned(() async {
        await _pump(tester, _image(source: '$_source?case=$mime'));
        await tester.pumpAndSettle();
        expect(response.subscriptions, 0);
        expect(find.byType(RawImage), findsNothing);
        expect(find.textContaining('Plan diagram'), findsOneWidget);
        expect(client.closed, isTrue);
      }, createHttpClient: (_) => client);
    }
  });

  testWidgets('corrupt raster bytes fail without URL disclosure or exceptions',
      (tester) async {
    final response = _Response(Stream.value(utf8.encode('not a PNG')));
    final client = _Client(_Request(Future.value(response)));
    await HttpOverrides.runZoned(() async {
      await _pump(tester, _image());
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.byType(RawImage), findsNothing);
      expect(find.textContaining('Plan diagram'), findsOneWidget);
      expect(find.textContaining(_source), findsNothing);
      expect(tester.takeException(), isNull);
    }, createHttpClient: (_) => client);
  });

  testWidgets('source dimensions are bounded before pixel decoding',
      (tester) async {
    final response = _Response(
        Stream.value(_png(width: 65535, height: 65535, headerOnly: true)));
    final client = _Client(_Request(Future.value(response)));
    await HttpOverrides.runZoned(() async {
      await _pump(tester, _image());
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.byType(RawImage), findsNothing);
      expect(find.textContaining('Plan diagram'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, createHttpClient: (_) => client);
  });

  testWidgets('accepted large source is decoded at a bounded raster size',
      (tester) async {
    final response = _Response(Stream.value(_png(width: 4096)));
    final client = _Client(_Request(Future.value(response)));
    await HttpOverrides.runZoned(() async {
      await _pump(tester, _image());
      await _waitForImage(tester);
      final rendered = tester.widget<RawImage>(find.byType(RawImage));
      expect(rendered.image!.width, lessThanOrEqualTo(2048));
      expect(rendered.image!.height, lessThanOrEqualTo(2048));
      expect(
          tester.getSize(find.byType(RawImage)).width, lessThanOrEqualTo(120));
    }, createHttpClient: (_) => client);
  });

  testWidgets('a stalled request times out and closes its connection',
      (tester) async {
    final client = _Client(_Request(Completer<HttpClientResponse>().future),
        pendingRequest: Completer<HttpClientRequest>().future);
    await HttpOverrides.runZoned(() async {
      await _pump(tester, _image());
      await tester.pump(const Duration(seconds: 16));
      await tester.pump();
      expect(client.forceClosed, isTrue);
      expect(find.textContaining('Plan diagram'), findsOneWidget);
      expect(find.byType(RawImage), findsNothing);
    }, createHttpClient: (_) => client);
  });

  testWidgets('dispose cancels a stalled response and closes the client',
      (tester) async {
    final body = StreamController<List<int>>();
    final response = _Response(body.stream);
    final client = _Client(_Request(Future.value(response)));
    await HttpOverrides.runZoned(() async {
      await _pump(tester, _image());
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(response.cancellations, greaterThanOrEqualTo(1));
      expect(client.request.aborts, greaterThanOrEqualTo(1));
      expect(client.forceClosed, isTrue);
      unawaited(body.close());
      await tester.pump();
    }, createHttpClient: (_) => client);
  });

  testWidgets('changing source cancels old load and ignores a late response',
      (tester) async {
    final oldResponse = Completer<HttpClientResponse>();
    final first = _Client(_Request(oldResponse.future));
    final second = _Client(
        _Request(Future.value(_Response(Stream.value(_png(width: 2))))));
    var clients = 0;
    await HttpOverrides.runZoned(() async {
      await _pump(tester, _image());
      await _pump(tester, _image(source: '$_source?new', alt: 'New diagram'));
      await _waitForImage(tester);
      expect(first.forceClosed, isTrue);
      expect(tester.widget<RawImage>(find.byType(RawImage)).image!.width, 2);
      oldResponse.complete(_Response(Stream.value(_png(width: 3))));
      await tester.pumpAndSettle();
      expect(tester.widget<RawImage>(find.byType(RawImage)).image!.width, 2);
      expect(tester.takeException(), isNull);
    }, createHttpClient: (_) => clients++ == 0 ? first : second);
  });

  testWidgets('Markdown images render in links underline table and list',
      (tester) async {
    final clients = <_Client>[];
    final links = <Uri>[];
    const data = '![Ordinary]($_source?plain)\n\n'
        '[![Linked]($_source?linked)](https://help.test.invalid/plan)\n\n'
        '<u>![Underlined]($_source?underline)</u>\n\n'
        '| Graphic |\n| --- |\n| ![Table]($_source?table) |\n\n'
        '- ![List]($_source?list)\n\n'
        '[Read ![Mixed]($_source?mixed) docs](https://help.test.invalid/mixed)';
    Widget content() => PurchasePlanContent(
          data: data,
          openLink: (uri) async => links.add(uri),
        );
    await HttpOverrides.runZoned(() async {
      await _pump(tester, content(), width: 320);
      await _waitForImage(tester, count: 6);
      expect(find.byType(RawImage), findsNWidgets(6));
      expect(clients, hasLength(6));
      expect(clients.expand((client) => client.requests).toSet(), {
        for (final query in [
          'plain',
          'linked',
          'underline',
          'table',
          'list',
          'mixed'
        ])
          Uri.parse('$_source?$query'),
      });
      final semantics = tester.ensureSemantics();
      for (final alt in ['Ordinary', 'Linked', 'Underlined', 'Table', 'List']) {
        expect(find.bySemanticsLabel(alt), findsOneWidget);
      }
      final mixedLabel = tester
          .getSemantics(find.byType(TextButton).last)
          .getSemanticsData()
          .label;
      for (final part in ['Read', 'Mixed', 'docs']) {
        expect(mixedLabel, contains(part));
      }
      semantics.dispose();
      await tester.tap(find.byType(TextButton).first);
      await tester.pump();
      expect(links, [Uri.parse('https://help.test.invalid/plan')]);
      await tester.tap(find.byType(TextButton).last);
      await tester.pump();
      expect(links.last, Uri.parse('https://help.test.invalid/mixed'));
      await _pump(tester, content(), width: 320);
      await tester.pumpAndSettle();
      expect(clients, hasLength(6),
          reason: 'Markdown parent builders must not reload nested images');
      expect(tester.takeException(), isNull);
    }, createHttpClient: (_) {
      final client = _Client(_Request(
          Future.value(_Response(Stream.value(_png(width: 24, height: 12))))));
      clients.add(client);
      return client;
    });
  });

  testWidgets('320px plan card contains wide linked images at 2x text',
      (tester) async {
    final clients = <_Client>[];
    await HttpOverrides.runZoned(() async {
      await _pump(
        tester,
        PurchasePlanCatalog(
          catalog: const XboardPlanCatalog(plans: [
            XboardPlanOffer(
              id: 1,
              name: 'Illustrated plan',
              transferGiB: 200,
              prices: [XboardPlanPrice(period: 'monthly', amount: 1000)],
              content: '# Service guide\n\n'
                  '[Read ![Wide diagram]($_source) docs](https://help.test.invalid/plan)'
                  '\n\nThe full description remains below the picture.',
            ),
          ]),
          loading: false,
          failed: false,
          retry: () {},
          openLink: (_) async {},
        ),
        width: 320,
        scale: 2,
      );
      await _waitForImage(tester);
      expect(
          tester.getSize(find.byType(RawImage)).width, lessThanOrEqualTo(280));
      expect(find.text('The full description remains below the picture.'),
          findsOneWidget);
      expect(clients, hasLength(1));
      expect(tester.takeException(), isNull);
    }, createHttpClient: (_) {
      final client = _Client(_Request(Future.value(
          _Response(Stream.value(_png(width: 1024, height: 16))))));
      clients.add(client);
      return client;
    });
  });

  testWidgets(
      'twenty stalled images open only four connections and cancel queue',
      (tester) async {
    final clients = <_Client>[];
    await HttpOverrides.runZoned(() async {
      await _pump(tester, _gallery(List.generate(20, (index) => index)),
          width: 320);
      expect(clients, hasLength(4));
      expect(PurchasePlanImage.debugResources.activeLoads, 4);
      expect(PurchasePlanImage.debugResources.queuedLoads, 16);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(clients, hasLength(4),
          reason: 'Unmounted queued images must never start requests');
      expect(clients.every((client) => client.forceClosed), isTrue);
      expect(PurchasePlanImage.debugResources.activeLoads, 0);
      expect(PurchasePlanImage.debugResources.queuedLoads, 0);
    }, createHttpClient: (_) {
      final client = _Client(_Request(Completer<HttpClientResponse>().future));
      clients.add(client);
      return client;
    });
  });

  testWidgets('released slot starts a queued image with its own full timeout',
      (tester) async {
    final clients = <_Client>[];
    final responses = <Completer<HttpClientResponse>>[];
    await HttpOverrides.runZoned(() async {
      await _pump(tester, _gallery(List.generate(20, (index) => index)),
          width: 320);
      expect(clients, hasLength(4));
      await tester.pump(const Duration(seconds: 14));
      responses.first
          .complete(_Response(const Stream.empty(), statusCode: 404));
      await tester.pump();
      expect(clients, hasLength(5));
      await tester.pump(const Duration(seconds: 2));
      expect(clients[4].closed, isFalse,
          reason: 'Queue wait time must not consume the new request timeout');
      expect(clients, hasLength(8));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(clients, hasLength(8));
      expect(clients.every((client) => client.forceClosed), isTrue);
    }, createHttpClient: (_) {
      final response = Completer<HttpClientResponse>();
      responses.add(response);
      final client = _Client(_Request(response.future));
      clients.add(client);
      return client;
    });
  });

  testWidgets('shared raster budget refuses excess and frees on image disposal',
      (tester) async {
    final bytes = _png(width: 2048, height: 2048);
    final clients = <_Client>[];
    final decodesBefore = PurchasePlanImage.debugResources.decodes;
    await HttpOverrides.runZoned(() async {
      await _pump(tester, _gallery([0, 1, 2, 3, 4]), width: 320);
      await _waitForImage(tester, count: 4);
      await _waitUntil(
          tester,
          () => clients.length == 5 && clients.every((client) => client.closed),
          'All five bounded downloads should finish');
      expect(find.byType(RawImage), findsNWidgets(4));
      expect(PurchasePlanImage.debugResources.reservedPixels, 16 * 1024 * 1024);
      expect(PurchasePlanImage.debugResources.decodes - decodesBefore, 4,
          reason: 'The over-budget image must be rejected before decoding');
      expect(find.textContaining('Diagram 4'), findsOneWidget);
      await _pump(tester, _gallery([1, 2, 3, 5]), width: 320);
      await _waitForImage(tester, count: 4);
      expect(clients, hasLength(6));
      expect(find.textContaining('Diagram 5'), findsNothing,
          reason: 'The replacement must acquire released raster memory');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(PurchasePlanImage.debugResources.reservedPixels, 0);
    }, createHttpClient: (_) {
      final client =
          _Client(_Request(Future.value(_Response(Stream.value(bytes)))));
      clients.add(client);
      return client;
    });
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Tristate;

import 'package:flclashx/clash/core.dart';
import 'package:flclashx/clash/interface.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/node_catalog_tester.dart';
import 'package:flclashx/common/theme.dart';
import 'package:flclashx/controller.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/models/node_catalog.dart';
import 'package:flclashx/providers/node_overview.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/services/secure_subscription.dart';
import 'package:flclashx/services/xboard_api.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/views/dashboard/widgets/hero_connect.dart';
import 'package:flclashx/views/dashboard/widgets/network_speed.dart';
import 'package:flclashx/views/dashboard/widgets/start_button.dart';
import 'package:flclashx/views/proxies/overview/overview.dart';
import 'package:flclashx/views/purchase/plan_image.dart';
import 'package:flclashx/widgets/tactile_proxy_switch.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _planImageUrl = 'https://images.test.invalid/plan-diagram.png';

Uint8List _validPng({int width = 2, int height = 2}) {
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
  chunk('IDAT', ZLibEncoder().convert(Uint8List((width * 4 + 1) * height)));
  chunk('IEND', []);
  return output.takeBytes();
}

class _ProbeHeaders implements HttpHeaders {
  final values = <String, List<String>>{};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      values[name.toLowerCase()] = [value.toString()];

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) =>
      (values[name.toLowerCase()] ??= <String>[]).add(value.toString());

  @override
  void removeAll(String name) => values.remove(name.toLowerCase());

  @override
  String? value(String name) => values[name.toLowerCase()]?.join(',');

  @override
  void forEach(void Function(String name, List<String> values) action) =>
      values.forEach(action);

  @override
  ContentType? get contentType => value(HttpHeaders.contentTypeHeader) == null
      ? null
      : ContentType.parse(value(HttpHeaders.contentTypeHeader)!);

  @override
  set contentType(ContentType? value) {
    if (value == null) {
      removeAll(HttpHeaders.contentTypeHeader);
    } else {
      set(HttpHeaders.contentTypeHeader, value.toString());
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProbeHttpResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _ProbeHttpResponse(
    this.body, {
    this.statusCode = 200,
    String? mime = 'image/png',
    Map<String, String> extraHeaders = const {},
  }) {
    if (mime != null) {
      headers.set(HttpHeaders.contentTypeHeader, mime);
    }
    extraHeaders.forEach(headers.set);
  }

  final Stream<List<int>> body;
  @override
  final int statusCode;
  @override
  final int contentLength = -1;
  @override
  final _ProbeHeaders headers = _ProbeHeaders();
  @override
  bool get isRedirect =>
      const {301, 302, 303, 307, 308}.contains(statusCode);
  @override
  List<RedirectInfo> get redirects => const [];
  @override
  String get reasonPhrase => statusCode == 200 ? 'OK' : 'Error';

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      body.listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProbeHttpRequest implements HttpClientRequest {
  _ProbeHttpRequest(this._responseFuture, {required this.uri});

  final Future<HttpClientResponse> _responseFuture;
  @override
  final Uri uri;
  @override
  final String method = 'GET';
  @override
  final _ProbeHeaders headers = _ProbeHeaders();
  @override
  final List<Cookie> cookies = <Cookie>[];
  @override
  bool followRedirects = true;
  @override
  int maxRedirects = 5;
  @override
  bool persistentConnection = true;
  @override
  int contentLength = -1;
  int aborts = 0;

  @override
  void add(List<int> data) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await stream.drain<void>();
  }

  @override
  Future<HttpClientResponse> close() => _responseFuture;

  @override
  Future<HttpClientResponse> get done => _responseFuture;

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    aborts++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProbeHttpClient implements HttpClient {
  _ProbeHttpClient({
    required this.onOpen,
  });

  final Future<HttpClientRequest> Function(_ProbeHttpClient client, Uri url)
      onOpen;
  final List<Uri> requestedUrls = <Uri>[];
  final List<Completer<HttpClientRequest>> _inFlightOpeners =
      <Completer<HttpClientRequest>>[];
  bool closed = false;
  bool forceClosed = false;
  String? proxyDecisionForSample;
  bool Function(X509Certificate, String, int)? _badCert;

  @override
  Duration? connectionTimeout;
  @override
  Duration idleTimeout = const Duration(seconds: 15);
  @override
  bool autoUncompress = true;
  @override
  int? maxConnectionsPerHost;
  @override
  String? userAgent;
  @override
  Future<bool> Function(Uri, String, String?)? authenticate;
  @override
  Future<bool> Function(String, int, String, String?)? authenticateProxy;
  @override
  set connectionFactory(
    Future<ConnectionTask<Socket>> Function(Uri, String?, int?)? f,
  ) {}
  @override
  set keyLog(void Function(String line)? callback) {}

  @override
  set badCertificateCallback(
    bool Function(X509Certificate, String, int)? callback,
  ) {
    _badCert = callback;
  }

  bool Function(X509Certificate, String, int)? get badCertificateCallbackGetter =>
      _badCert;

  @override
  set findProxy(String Function(Uri)? f) {
    if (f != null) {
      proxyDecisionForSample = f(Uri.parse('https://fast.hjy.ca:8443'));
    }
  }

  Completer<HttpClientRequest> registerCancellableOpen() {
    final completer = Completer<HttpClientRequest>();
    _inFlightOpeners.add(completer);
    return completer;
  }

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    requestedUrls.add(url);
    if (closed) {
      return Future<HttpClientRequest>.error(
        const SocketException('HttpClient is already closed'),
      );
    }
    return onOpen(this, url);
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);

  @override
  void close({bool force = false}) {
    closed = true;
    forceClosed = forceClosed || force;
    for (final opener in _inFlightOpeners) {
      if (!opener.isCompleted) {
        opener.completeError(
          const SocketException('Connection aborted by HttpClient.close'),
        );
      }
    }
    _inFlightOpeners.clear();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.root);
  final String root;

  @override
  Future<String> getApplicationSupportPath() async => root;

  @override
  Future<String> getTemporaryPath() async => root;

  @override
  Future<String> getDownloadsPath() async => root;
}

class _StubCoreTransport extends ClashHandlerInterface {
  @override
  Future<bool> get isInit async => true;

  @override
  FutureOr<String> validateConfig(String data) => '';

  @override
  Future<String> setupConfig(SetupParams params) async => '';

  @override
  Future<String> updateConfig(
    UpdateParams updateParams, {
    String? controllerAddress,
    bool? controllerEnabled,
  }) async =>
      '';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _TddOverviewCatalogTester extends ChangeNotifier
    implements NodeCatalogTester {
  @override
  bool busy = true;

  @override
  int total = 10;

  @override
  int completed = 3;

  final Set<String> pendingKeys = {'node-pending'};

  @override
  Set<String> pendingIdentitySnapshot(String profileId) =>
      profileId == 'sub-b' ? pendingKeys : const <String>{};

  @override
  bool pending(String profileId, String identityKey) =>
      profileId == 'sub-b' && pendingKeys.contains(identityKey);

  @override
  void disposeScope() {}

  @override
  Future<void> cancel({String reason = 'cancelled'}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<SemanticsNode> _collectSemanticsNodesWithValue(SemanticsNode? root) {
  final matches = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    if (data.value.trim().isNotEmpty) {
      matches.add(node);
    }
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  if (root != null) {
    visit(root);
  }
  return matches;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  final originalPaths = PathProviderPlatform.instance;

  setUpAll(() async {
    tempRoot = await Directory.systemTemp.createTemp('fcx-leak-uia-tdd-');
    PathProviderPlatform.instance = _TestPaths(tempRoot.path);
    globalState.packageInfo = PackageInfo(
      appName: 'FlClashX',
      packageName: 'com.pluralplay.flclashx',
      version: '0.4.1',
      buildNumber: '1',
    );
  });

  tearDownAll(() async {
    await fileLogger.dispose();
    ClashCore.instanceForTesting = null;
    PathProviderPlatform.instance = originalPaths;
    if (tempRoot.existsSync()) {
      await tempRoot.delete(recursive: true);
    }
  });

  group('Resource Leak & Windows UIA Stability TDD Suite', () {
    testWidgets(
      'TDD-1: PurchasePlanImage force-closes its HttpClient immediately when response bytes finish, before native raster decode completes',
      (tester) async {
        var streamDone = false;
        final controller = StreamController<List<int>>();
        final response = _ProbeHttpResponse(
          controller.stream.map((chunk) => chunk),
        );
        final client = _ProbeHttpClient(
          onOpen: (_, url) async => _ProbeHttpRequest(
            Future<HttpClientResponse>.value(response),
            uri: url,
          ),
        );

        await HttpOverrides.runZoned(
          () async {
            await tester.pumpWidget(
              MaterialApp(
                locale: const Locale('zh', 'CN'),
                supportedLocales: AppLocalizations.delegate.supportedLocales,
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                home: const Scaffold(
                  body: PurchasePlanImage(
                    source: _planImageUrl,
                    alt: '架构示意图',
                    maxWidth: 160,
                  ),
                ),
              ),
            );
            await tester.pump();

            controller.add(_validPng(width: 4, height: 4));
            await controller.close().then((_) => streamDone = true);
            await tester.pump();

            expect(streamDone, isTrue);
            // At this exact point in fake-async, HTTP download has finished and
            // execution is parked at native ui.ImmutableBuffer.fromUint8List.
            // Network HttpClient MUST already be force-closed instead of being
            // held open across CPU/GPU decoding.
            expect(
              client.forceClosed,
              isTrue,
              reason:
                  'HttpClient must be force-closed in a network-scoped finally block as soon as response bytes are read',
            );

            // Let native decode finish and verify image still renders cleanly.
            for (var i = 0; i < 60; i++) {
              if (tester
                  .widgetList<RawImage>(find.byType(RawImage))
                  .any((img) => img.image != null)) {
                break;
              }
              await tester.runAsync(() => Future<void>.delayed(Duration.zero));
              await tester.pump();
            }
            expect(find.byType(RawImage), findsOneWidget);
            expect(PurchasePlanImage.debugResources.activeLoads, 0);
          },
          createHttpClient: (_) => client,
        );
      },
    );

    test(
      'TDD-2: DioXboardApi.close() aborts in-flight proxy request without spawning or leaking a fallback _directDio HttpClient',
      () async {
        final createdClients = <_ProbeHttpClient>[];
        final firstOpenEntered = Completer<void>();

        await HttpOverrides.runZoned(
          () async {
            final api = DioXboardApi(
              shouldFallbackToDirect: () => true,
            );

            final pending = api.getPlanCatalog();
            final pendingThrows = expectLater(
              pending,
              throwsA(isA<XboardException>()),
            );
            // Deterministically wait until Dio enters openUrl on primary proxy client.
            await firstOpenEntered.future;
            expect(createdClients, hasLength(1));
            expect(createdClients.single.closed, isFalse);

            // Simulate PurchaseView.dispose() -> PurchaseManager.dispose() -> api.close()
            // while the initial proxy connection is still handshaking.
            api.close();

            await pendingThrows;

            expect(
              createdClients,
              hasLength(1),
              reason:
                  'Closing DioXboardApi must NOT trigger dead-proxy fallback or allocate a leaked _directDio HttpClient',
            );
            expect(createdClients.single.forceClosed, isTrue);

            // Subsequent calls on a closed API must fail fast without opening new transports.
            await expectLater(
              api.getPlanCatalog(),
              throwsA(isA<XboardException>()),
            );
            expect(createdClients, hasLength(1));
          },
          createHttpClient: (_) {
            final clientIndex = createdClients.length;
            final probe = _ProbeHttpClient(
              onOpen: (client, _) {
                if (clientIndex == 0) {
                  if (!firstOpenEntered.isCompleted) {
                    firstOpenEntered.complete();
                  }
                  return client.registerCancellableOpen().future;
                }
                return Future<HttpClientRequest>.error(
                  const SocketException('Unexpected direct fallback probe after close'),
                );
              },
            );
            createdClients.add(probe);
            return probe;
          },
        );
      },
    );

    test(
      'TDD-3: SecureSubscriptionDownloader exposes close(), closes owned transports, and never spawns a leaked direct fallback client after close()',
      () async {
        final createdClients = <_ProbeHttpClient>[];
        final firstOpenEntered = Completer<void>();

        await HttpOverrides.runZoned(
          () async {
            final downloader = SecureSubscriptionDownloader(
              shouldFallbackToDirect: (_) => true,
            );

            final pending = downloader.download(
              Uri.parse('https://fast.hjy.ca:8443/api/v1/client/subscribe?token=t1'),
              const {'User-Agent': 'FlClashX/test'},
            );
            final pendingThrows = expectLater(
              pending,
              throwsA(isA<FormatException>()),
            );
            await firstOpenEntered.future;
            expect(createdClients, hasLength(1));

            // Expose static close() and abort cleanly without spawning _directDio.
            downloader.close();

            await pendingThrows;

            expect(
              createdClients,
              hasLength(1),
              reason:
                  'SecureSubscriptionDownloader.close() must not fall back to _ensureDirectDio() after disposal',
            );
            expect(createdClients.single.forceClosed, isTrue);

            // Subsequent downloads on a closed downloader fail fast without opening new transports.
            await expectLater(
              downloader.download(
                Uri.parse('https://fast.hjy.ca:8443/api/v1/client/subscribe?token=t1'),
                const {'User-Agent': 'FlClashX/test'},
              ),
              throwsA(isA<FormatException>()),
            );
            expect(createdClients, hasLength(1));
          },
          createHttpClient: (_) {
            final clientIndex = createdClients.length;
            final probe = _ProbeHttpClient(
              onOpen: (client, _) {
                if (clientIndex == 0) {
                  if (!firstOpenEntered.isCompleted) {
                    firstOpenEntered.complete();
                  }
                  return client.registerCancellableOpen().future;
                }
                return Future<HttpClientRequest>.error(
                  const SocketException('Unexpected direct fallback probe after close'),
                );
              },
            );
            createdClients.add(probe);
            return probe;
          },
        );
      },
    );

    testWidgets(
      'TDD-4: Silent background autoUpdateProfiles does not flip isUpdating or rebuild catalog/UI on 403 dead profiles, commits healthy updates in 1 step, and preserves interactive isUpdating',
      (tester) async {
        SharedPreferences.setMockInitialValues({'sendDeviceHeaders': false});
        ClashCore.instanceForTesting = ClashCore.forTesting(_StubCoreTransport());

        final baseTime = DateTime.utc(2026, 11, 13, 12, 0, 0);
        final activeFresh = Profile(
          id: 'active-fresh',
          label: '伦敦主力',
          url: 'https://sub.test.invalid/active',
          autoUpdate: true,
          autoUpdateDuration: const Duration(hours: 24),
          lastUpdateDate: baseTime.subtract(const Duration(minutes: 5)),
        );
        final deadBackground = Profile(
          id: 'dead-bg',
          label: '历史废弃订阅',
          url: 'https://sub.test.invalid/dead-403',
          autoUpdate: true,
          autoUpdateDuration: const Duration(hours: 6),
          lastUpdateDate: baseTime.subtract(const Duration(hours: 12)),
        );
        final healthyBackground = Profile(
          id: 'ok-bg',
          label: '备用有效订阅',
          url: 'https://sub.test.invalid/ok-200',
          autoUpdate: true,
          autoUpdateDuration: const Duration(hours: 6),
          lastUpdateDate: baseTime.subtract(const Duration(hours: 12)),
        );

        const validYaml = 'proxies:\n'
            '  - {name: HK-01, type: ss, server: hk.test.invalid, port: 443, cipher: aes-128-gcm, password: p}\n'
            'proxy-groups:\n'
            '  - {name: PROXY, type: select, proxies: [HK-01]}\n'
            'rules:\n'
            '  - MATCH,PROXY\n';

        // Seed on-disk files inside real async zone (dart:io File futures deadlock in FakeAsync).
        await tester.runAsync(() async {
          for (final p in [activeFresh, deadBackground, healthyBackground]) {
            final file = await p.getFile();
            await file.writeAsString(validYaml);
          }
        });

        globalState.config = Config(
          themeProps: defaultThemeProps,
          profiles: [activeFresh, deadBackground, healthyBackground],
          currentProfileId: activeFresh.id,
        );
        globalState.appState = AppState(
          isInit: true,
          viewSize: const Size(800, 900),
          requests: FixedList(10),
          version: 0,
          logs: FixedList(10),
          traffics: FixedList(10),
          totalTraffic: Traffic(),
        );

        AppController? controller;
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              locale: const Locale('zh', 'CN'),
              supportedLocales: AppLocalizations.delegate.supportedLocales,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: Consumer(
                builder: (context, ref, _) {
                  controller ??= AppController(context, ref);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
        await tester.pump();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(SizedBox)),
        );

        final deadProfileSnapshots = <bool>[];
        final okProfileSnapshots = <bool>[];
        var deadCatalogSelectorChanges = 0;

        final subDead = container.listen<bool?>(
          profilesProvider.select(
            (list) => list.getProfile('dead-bg')?.isUpdating,
          ),
          (_, next) {
            if (next != null) deadProfileSnapshots.add(next);
          },
        );
        final subOk = container.listen<Profile?>(
          profilesProvider.select((list) => list.getProfile('ok-bg')),
          (_, next) {
            if (next != null) okProfileSnapshots.add(next.isUpdating);
          },
        );
        final subDeadCatalogTrigger = container.listen(
          profilesProvider.select((profiles) {
            final p = profiles.getProfile('dead-bg');
            return (p?.url, p?.lastUpdateDate, p?.isUpdating);
          }),
          (_, __) => deadCatalogSelectorChanges++,
        );
        addTearDown(() {
          subDead.close();
          subOk.close();
          subDeadCatalogTrigger.close();
        });

        await tester.runAsync(() async {
          await HttpOverrides.runZoned(
            () async {
              await controller!.autoUpdateProfiles(now: baseTime);
            },
            createHttpClient: (_) => _ProbeHttpClient(
              onOpen: (_, url) async {
                if (url.path.contains('dead-403')) {
                  return _ProbeHttpRequest(
                    Future<HttpClientResponse>.value(
                      _ProbeHttpResponse(
                        Stream<List<int>>.value(utf8.encode('Forbidden')),
                        statusCode: 403,
                        mime: 'text/plain',
                      ),
                    ),
                    uri: url,
                  );
                }
                return _ProbeHttpRequest(
                  Future<HttpClientResponse>.value(
                    _ProbeHttpResponse(
                      Stream<List<int>>.value(utf8.encode(validYaml)),
                      statusCode: 200,
                      mime: 'text/yaml',
                      extraHeaders: const {
                        'subscription-userinfo':
                            'upload=10; download=20; total=1000; expire=1999999999',
                      },
                    ),
                  ),
                  uri: url,
                );
              },
            ),
          );
        });

        // 1. Dead background subscription (403) must produce ZERO isUpdating flips
        // and ZERO catalog selector invalidations during silent autoUpdateProfiles!
        expect(
          deadProfileSnapshots,
          isEmpty,
          reason:
              'Silent background autoUpdateProfiles must not flip isUpdating true->false on failing dead profiles',
        );
        expect(
          deadCatalogSelectorChanges,
          0,
          reason:
              'Failing silent auto-update must not invalidate profileCatalogProvider watch tuple',
        );

        // 2. Healthy background subscription commits atomically once with isUpdating=false.
        expect(
          okProfileSnapshots,
          equals([false]),
          reason:
              'Silent background auto-update should commit once with isUpdating=false without intermediate true state',
        );

        // 3. Explicit manual updateProfile still surfaces isUpdating: true -> false!
        final manualUpdatingStates = <bool>[];
        final subManual = container.listen<bool?>(
          profilesProvider.select(
            (list) => list.getProfile('dead-bg')?.isUpdating,
          ),
          (_, next) {
            if (next != null) manualUpdatingStates.add(next);
          },
        );
        addTearDown(subManual.close);

        await tester.runAsync(() async {
          await HttpOverrides.runZoned(
            () async {
              await expectLater(
                controller!.updateProfile(
                  container.read(profilesProvider).getProfile('dead-bg')!,
                ),
                throwsA(anything),
              );
            },
            createHttpClient: (_) => _ProbeHttpClient(
              onOpen: (_, url) async => _ProbeHttpRequest(
                Future<HttpClientResponse>.value(
                  _ProbeHttpResponse(
                    Stream<List<int>>.value(utf8.encode('Forbidden')),
                    statusCode: 403,
                    mime: 'text/plain',
                  ),
                ),
                uri: url,
              ),
            ),
          );
        });
        expect(manualUpdatingStates, equals([true, false]));
      },
    );

    testWidgets(
      'TDD-5: HeroConnect, StartButton, and NetworkSpeed update 1Hz visual telemetry without mutating SemanticsNodes on every tick',
      (tester) async {
        tester.view.physicalSize = const Size(800, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await AppLocalizations.load(const Locale('zh', 'CN'));
        const profile = Profile(
          id: 'uia-1',
          label: '自由云主力',
          url: 'https://sub.test.invalid/uia',
          autoUpdateDuration: Duration(hours: 24),
        );
        final initialTraffics = FixedList<Traffic>(30)
          ..add(Traffic(up: 1024, down: 2048));

        globalState.config = Config(
          themeProps: defaultThemeProps,
          profiles: const [profile],
          currentProfileId: profile.id,
        );
        globalState.appState = AppState(
          isInit: true,
          runTime: 1000,
          viewSize: const Size(800, 900),
          requests: FixedList(10),
          version: 0,
          logs: FixedList(10),
          traffics: initialTraffics,
          totalTraffic: Traffic(),
          groups: const [
            Group(
              name: 'PROXY',
              type: GroupType.Selector,
              now: 'HK-01',
              all: [Proxy(name: 'HK-01', type: 'ss')],
            ),
          ],
        );

        final container = ProviderContainer();
        addTearDown(container.dispose);

        final semanticsHandle = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                locale: const Locale('zh', 'CN'),
                supportedLocales: AppLocalizations.delegate.supportedLocales,
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                home: MediaQuery(
                  data: const MediaQueryData(size: Size(800, 900)),
                  child: Builder(
                    builder: (context) {
                      globalState.measure = Measure.of(context, 1.0);
                      globalState.theme = CommonTheme.of(context, 1.0);
                      return const Scaffold(
                        body: Column(
                          children: [
                            SizedBox(height: 360, child: HeroConnect()),
                            SizedBox(height: 180, child: NetworkSpeed()),
                            StartButton(),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          final dashboardDockFinder = find.byKey(
            const ValueKey('dashboard-floating-proxy-dock'),
          );
          final dashboardSwitchFinder = find.byKey(
            const ValueKey('dashboard-proxy-toggle'),
          );

          // Initial visual uptime 00:00:01 renders on HeroConnect; StartButton renders FloatingProxyDock in running state.
          expect(find.text('00:00:01'), findsOneWidget);
          expect(dashboardDockFinder, findsOneWidget);
          expect(
            tester.widget<EarthProxySwitch>(dashboardSwitchFinder).isRunning,
            isTrue,
          );
          expect(
            tester
                .getSemantics(dashboardSwitchFinder)
                .flagsCollection
                .isToggled,
            Tristate.isTrue,
          );
          expect(
            find.bySemanticsLabel(appLocalizations.nodeOverviewTurnOffProxy),
            findsWidgets,
          );

          final semanticsOwner =
              tester.renderObject(find.byType(Scaffold)).owner!.semanticsOwner!;
          var semanticsMutationsDuringSteadyTicks = 0;
          void onSemanticsUpdated() {
            semanticsMutationsDuringSteadyTicks++;
          }

          semanticsOwner.addListener(onSemanticsUpdated);
          try {
            // Simulate 4 consecutive 1-second ticks of both runTimeProvider AND trafficsProvider.
            for (var sec = 2; sec <= 5; sec++) {
              container.read(runTimeProvider.notifier).value = sec * 1000;
              final nextTraffics = FixedList<Traffic>(30);
              container.read(trafficsProvider).list.forEach(nextTraffics.add);
              nextTraffics.add(Traffic(up: sec * 4096, down: sec * 16384));
              container.read(trafficsProvider.notifier).value = nextTraffics;
              await tester.pump();
            }

            // Visual 1Hz telemetry MUST still update accurately!
            expect(find.text('00:00:05'), findsOneWidget);
            expect(
              tester.widget<EarthProxySwitch>(dashboardSwitchFinder).isRunning,
              isTrue,
            );

            // Semantics tree MUST emit ZERO mutations across steady-state 1Hz ticks,
            // eliminating the 1Hz UiaRaiseAutomationEvent / get_accValue storm!
            expect(
              semanticsMutationsDuringSteadyTicks,
              0,
              reason:
                  '1Hz uptime stopwatch and live speed telemetry must not mutate AXNodeData / SemanticsOwner on every tick',
            );

            // Transitioning connection state (running -> disconnected) MUST still emit a real semantic update!
            container.read(runTimeProvider.notifier).value = null;
            await tester.pump();
            expect(
              semanticsMutationsDuringSteadyTicks,
              greaterThan(0),
              reason:
                  'Genuine proxy state transitions must still update accessibility semantics',
            );
            expect(
              tester.widget<EarthProxySwitch>(dashboardSwitchFinder).isRunning,
              isFalse,
            );
            expect(
              tester
                  .getSemantics(dashboardSwitchFinder)
                  .flagsCollection
                  .isToggled,
              Tristate.isFalse,
            );
            expect(
              find.bySemanticsLabel(appLocalizations.nodeOverviewTurnOnProxy),
              findsWidgets,
            );
          } finally {
            semanticsOwner.removeListener(onSemanticsUpdated);
          }
        } finally {
          semanticsHandle.dispose();
        }
      },
    );

    testWidgets(
      'TDD-6: NodeOverviewView isolates decorative progress indicators from AXStringAttribute kValue semantics while preserving readable labels',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));

        await AppLocalizations.load(const Locale('zh', 'CN'));

        const activeProfile = Profile(
          id: 'sub-a',
          label: '主力订阅',
          autoUpdateDuration: Duration.zero,
          subscriptionInfo: SubscriptionInfo(
            upload: 1024 * 1024 * 1024,
            download: 2 * 1024 * 1024 * 1024,
            total: 10 * 1024 * 1024 * 1024,
          ),
        );
        const updatingProfile = Profile(
          id: 'sub-b',
          label: '备用订阅',
          autoUpdateDuration: Duration.zero,
          isUpdating: true,
        );

        globalState.config = Config(
          themeProps: defaultThemeProps,
          profiles: const [activeProfile, updatingProfile],
          currentProfileId: activeProfile.id,
        );
        globalState.appState = AppState(
          isInit: true,
          viewSize: const Size(1280, 900),
          requests: FixedList(4),
          version: 0,
          logs: FixedList(4),
          traffics: FixedList(4),
          totalTraffic: Traffic(),
          groups: const [
            Group(
              name: 'PROXY',
              type: GroupType.Selector,
              now: 'HK-01',
              all: [Proxy(name: 'HK-01', type: 'ss')],
            ),
          ],
        );

        final activeCatalog = ProfileCatalog(
          profileId: activeProfile.id,
          fingerprint: 'fp-a',
          status: ProfileCatalogStatus.ready,
          nodes: const [
            CatalogNode(
              identityKey: 'node-active',
              endpointKey: 'ep-active',
              name: 'HK-01',
              type: 'ss',
              source: CatalogNodeSource.inline,
            ),
          ],
        );
        final standbyCatalog = ProfileCatalog(
          profileId: updatingProfile.id,
          fingerprint: 'fp-b',
          status: ProfileCatalogStatus.ready,
          nodes: const [
            CatalogNode(
              identityKey: 'node-pending',
              endpointKey: 'ep-pending',
              name: 'JP-Pending',
              type: 'ss',
              source: CatalogNodeSource.inline,
            ),
          ],
        );

        final testerDouble = _TddOverviewCatalogTester();

        final semanticsHandle = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                nodeOverviewEnabledProvider.overrideWithValue(true),
                proxiesScopeProvider.overrideWith((ref) => ProxiesScope.all),
                nodeCatalogTesterProvider.overrideWith((ref) => testerDouble),
                activeNodeCatalogProvider.overrideWithValue(activeCatalog),
                cachedProfileCatalogsProvider.overrideWith(
                  (ref) => {
                    activeProfile.id: activeCatalog,
                    updatingProfile.id: standbyCatalog,
                  },
                ),
                profileCatalogProvider.overrideWith((ref, id) async {
                  return id == activeProfile.id
                      ? activeCatalog
                      : standbyCatalog;
                }),
                nodeHealthEntriesProvider.overrideWith((ref, id) => const {}),
              ],
              child: MaterialApp(
                locale: const Locale('zh', 'CN'),
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                supportedLocales: AppLocalizations.delegate.supportedLocales,
                home: Builder(
                  builder: (context) {
                    globalState.measure = Measure.of(context, 1.0);
                    globalState.theme = CommonTheme.of(context, 1.0);
                    return const Scaffold(body: NodeOverviewView());
                  },
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));

          expect(find.byType(LinearProgressIndicator), findsAtLeastNWidgets(2));
          expect(find.byType(CircularProgressIndicator), findsAtLeastNWidgets(1));
          expect(find.text('70%'), findsWidgets);

          final semanticsOwner =
              tester.renderObject(find.byType(Scaffold)).owner!.semanticsOwner!;
          final valueNodes = _collectSemanticsNodesWithValue(
            semanticsOwner.rootSemanticsNode,
          );
          expect(
            valueNodes,
            isEmpty,
            reason:
                'Decorative progress indicators must not emit UIA AXStringAttribute kValue nodes that race AccessibilityBridgeWindows',
          );
        } finally {
          semanticsHandle.dispose();
        }
      },
    );

    test(
      'TDD-7: Windows runner wires UIA guard across CMakeLists, FlutterWindow lifecycle, and desktop_multi_window',
      () {
        final cmakeContent =
            File('windows/runner/CMakeLists.txt').readAsStringSync();
        expect(cmakeContent, contains('"uia_guard.cpp"'));
        expect(cmakeContent, contains('"comctl32.lib"'));

        final flutterWindowContent =
            File('windows/runner/flutter_window.cpp').readAsStringSync();
        expect(flutterWindowContent, contains('#include "uia_guard.h"'));
        expect(
          flutterWindowContent,
          contains('DesktopMultiWindowSetWindowCreatedCallback'),
        );
        expect(
          flutterWindowContent,
          contains('InstallFlutterWindowTreeUiaGuard'),
        );
        expect(
          flutterWindowContent,
          contains('ShouldInterceptWindowMessageForUiaGuard'),
        );
        expect(
          flutterWindowContent,
          contains('UninstallFlutterWindowTreeUiaGuard'),
        );
      },
    );
  });
}

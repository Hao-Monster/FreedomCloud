import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flclashx/clash/core.dart';
import 'package:flclashx/clash/interface.dart';
import 'package:flclashx/common/fixed.dart';
import 'package:flclashx/common/function.dart';
import 'package:flclashx/common/node_country.dart';
import 'package:flclashx/common/tun_runtime.dart';
import 'package:flclashx/common/windows_tun_startup.dart';
import 'package:flclashx/controller.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/manager/clash_manager.dart';
import 'package:flclashx/manager/purchase_manager.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/models/xboard.dart';
import 'package:flclashx/services/purchase_storage.dart';
import 'package:flclashx/services/xboard_api.dart';
import 'package:flclashx/state.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingRawTransport extends ClashHandlerInterface {
  final List<String> rawMessages = [];
  Object? trafficResponse = const {'up': 1024, 'down': 2048};
  Object? totalTrafficResponse = const {'up': 4096, 'down': 8192};
  Object? externalProviderResponse = const {
    'name': 'prov-a',
    'type': 'Proxy',
    'path': '/tmp/prov-a.yaml',
    'count': 12,
    'subscription-info': {
      'Upload': 10,
      'Download': 20,
      'Total': 100,
      'Expire': 1893456000,
    },
    'vehicle-type': 'HTTP',
    'update-at': '2026-01-01T00:00:00.000Z',
  };
  final List<bool> requestsActiveCalls = [];

  @override
  Future<void> sendMessage(String message) async {
    rawMessages.add(message);
    final decoded = jsonDecode(message) as Map<String, dynamic>;
    final id = decoded['id'] as String;
    final method = ActionMethod.values.byName(decoded['method'] as String);
    Object? replyData = '';
    switch (method) {
      case ActionMethod.getTraffic:
        replyData = trafficResponse;
      case ActionMethod.getTotalTraffic:
        replyData = totalTrafficResponse;
      case ActionMethod.getExternalProvider:
        replyData = externalProviderResponse;
      case ActionMethod.setRequestsActive:
        requestsActiveCalls.add(decoded['data'] as bool);
        replyData = true;
      case ActionMethod.initClash:
      case ActionMethod.setState:
        replyData = true;
      default:
        replyData = '';
    }
    await handleResult(
      ActionResult(
        id: id,
        method: method,
        data: replyData,
        code: ResultType.success,
      ),
    );
  }

  @override
  Future<bool> preload() async => true;

  @override
  Future<bool> destroy() async => true;

  @override
  void reStart() {}
}

class _ConcurrentRefreshApi implements XboardApi {
  int currentInFlight = 0;
  int maxObservedInFlight = 0;
  final Completer<void> barrier = Completer<void>();

  Future<T> _track<T>(T value) async {
    currentInFlight++;
    if (currentInFlight > maxObservedInFlight) {
      maxObservedInFlight = currentInFlight;
    }
    await barrier.future;
    currentInFlight--;
    return value;
  }

  @override
  Uri get baseUri => Uri.parse('https://panel.example.test');

  @override
  Future<XboardPlanCatalog> getPlanCatalog() async =>
      const XboardPlanCatalog(plans: []);

  @override
  Future<String> login(String email, String password) async => 'Bearer tok';

  @override
  Future<XboardAccount> getAccount(String authorization) async =>
      const XboardAccount(id: 7, email: 'u@example.test');

  @override
  Future<XboardSubscription> getSubscription(String authorization) => _track(
        XboardSubscription(
          valid: true,
          url: Uri.parse('https://panel.example.test/s/token'),
        ),
      );

  @override
  Future<GiftHistoryPage> getGiftHistory(
    String authorization, {
    int page = 1,
  }) =>
      _track(
        GiftHistoryPage(
          entries: const [],
          page: 1,
          lastPage: 1,
          total: 0,
        ),
      );

  @override
  Future<Uri?> getCardStore(String authorization) =>
      _track(Uri.parse('https://store.example.test'));

  @override
  Future<GiftPreview> checkGift(String authorization, String code) =>
      throw UnimplementedError();

  @override
  Future<GiftReceipt> redeemGift(String authorization, String code) =>
      throw UnimplementedError();

  @override
  Future<void> logout(String authorization) async {}

  @override
  void close() {}
}

class _InMemoryPurchaseStorage implements PurchaseStorage {
  PurchaseSession? session = const PurchaseSession(7, 'Bearer tok');

  @override
  Future<void> clearPending(int accountId) async {}

  @override
  Future<void> clearSession() async => session = null;

  @override
  Future<PendingGiftRedemption?> readPending(int accountId) async => null;

  @override
  Future<String?> readProfileId(int accountId) async => null;

  @override
  Future<PurchaseSession?> readSession() async => session;

  @override
  Future<void> savePending(int accountId, PendingGiftRedemption pending) async {}

  @override
  Future<void> saveProfileId(int accountId, String profileId) async {}

  @override
  Future<void> saveSession(PurchaseSession value) async => session = value;
}

void main() {
  group('P0-1: log-level default preservation, clamping & UI Agent dedup', () {
    test('hasExplicitTopLevelLogLevel detects only top-level YAML/JSON keys', () {
      expect(
        hasExplicitTopLevelLogLevel(
          '# log-level: debug\nproxies:\n  - name: n1\n    log-level: debug\nmode: rule\n',
        ),
        isFalse,
      );
      expect(
        hasExplicitTopLevelLogLevel('\uFEFFlog-level: info\nmode: rule\n'),
        isTrue,
      );
      expect(
        hasExplicitTopLevelLogLevel('{"mode":"rule","log-level":"debug"}'),
        isTrue,
      );
    });

    test('resolveEffectiveLogLevel preserves local error default and clamps debug/info', () {
      // Unspecified in YAML (Mihomo DefaultRawConfig populated "info") -> local error wins
      expect(
        resolveEffectiveLogLevel(
          isOverride: false,
          hasExplicitProfileLogLevel: false,
          profileLogLevel: 'info',
          userLogLevel: LogLevel.error,
        ),
        'error',
      );
      // Subscription explicitly pushes debug while user kept default error -> clamped to warning
      expect(
        resolveEffectiveLogLevel(
          isOverride: false,
          hasExplicitProfileLogLevel: true,
          profileLogLevel: 'debug',
          userLogLevel: LogLevel.error,
        ),
        'warning',
      );
      // Subscription explicitly pushes info while user kept default error -> clamped to warning
      expect(
        resolveEffectiveLogLevel(
          isOverride: false,
          hasExplicitProfileLogLevel: true,
          profileLogLevel: 'info',
          userLogLevel: LogLevel.error,
        ),
        'warning',
      );
      // User explicitly chose debug locally -> allows subscription debug
      expect(
        resolveEffectiveLogLevel(
          isOverride: false,
          hasExplicitProfileLogLevel: true,
          profileLogLevel: 'debug',
          userLogLevel: LogLevel.debug,
        ),
        'debug',
      );
      // Override enabled -> user setting wins unconditionally
      expect(
        resolveEffectiveLogLevel(
          isOverride: true,
          hasExplicitProfileLogLevel: true,
          profileLogLevel: 'silent',
          userLogLevel: LogLevel.info,
        ),
        'info',
      );
    });

    test('shouldPersistCoreLogOnUiSide deduplicates info/debug when Agent owns Core stdout', () {
      expect(
        shouldPersistCoreLogOnUiSide(LogLevel.debug, usesAgent: true),
        isFalse,
      );
      expect(
        shouldPersistCoreLogOnUiSide(LogLevel.info, usesAgent: true),
        isFalse,
      );
      expect(
        shouldPersistCoreLogOnUiSide(LogLevel.warning, usesAgent: true),
        isTrue,
      );
      expect(
        shouldPersistCoreLogOnUiSide(LogLevel.error, usesAgent: true),
        isTrue,
      );
      expect(
        shouldPersistCoreLogOnUiSide(LogLevel.info, usesAgent: false),
        isTrue,
      );
    });
  });

  group('P0-3: Zero-double-encode IPC framing & raw slice fast-path', () {
    test('tryExtractRawDataActionResult slices large getConnections payload without decoding', () {
      const payload =
          '{"downloadTotal":123,"uploadTotal":456,"connections":[{"id":"c1","metadata":{"process":"a\\"b\\\\c{}"}}]}';
      const line =
          '{"id":"getConnections#42","method":"getConnections","data":$payload,"code":0}';
      final extracted = tryExtractRawDataActionResult(line);
      expect(extracted, isNotNull);
      expect(extracted!.id, 'getConnections#42');
      expect(extracted.method, ActionMethod.getConnections);
      expect(extracted.code, 0);
      expect(extracted.rawData, payload);

      // Agent event lines must never be misclassified
      expect(
        tryExtractRawDataActionResult(
          '{"type":"state","generation":1,"coreState":"ready"}',
        ),
        isNull,
      );
    });

    test('setupConfig sends raw object in Isolate and ClashCore accepts raw Map traffic/provider', () async {
      final transport = _RecordingRawTransport();
      final core = ClashCore.forTesting(transport);
      addTearDown(core.destroy);

      const setup = SetupParams(
        config: {'mixed-port': 7890, 'mode': 'rule'},
        selectedMap: {'GLOBAL': 'DIRECT'},
        testUrl: 'https://www.gstatic.com/generate_204',
      );
      expect(await core.setupConfig(setup, profileId: 'p1'), isEmpty);

      final sentFrame =
          jsonDecode(transport.rawMessages.single) as Map<String, dynamic>;
      expect(sentFrame['method'], 'setupConfig');
      // Must be a raw JSON object on the wire, NOT a double-escaped JSON string!
      expect(sentFrame['data'], isA<Map<String, dynamic>>());
      expect((sentFrame['data'] as Map)['test-url'], setup.testUrl);

      final traffic = await core.getTraffic();
      expect(traffic.up.value, 1024);
      expect(traffic.down.value, 2048);

      final total = await core.getTotalTraffic();
      expect(total.up.value, 4096);
      expect(total.down.value, 8192);

      final provider = await core.getExternalProvider('prov-a');
      expect(provider, isNotNull);
      expect(provider!.name, 'prov-a');
      expect(provider.count, 12);

      await core.setRequestsActive(true);
      await core.setRequestsActive(false);
      expect(transport.requestsActiveCalls, [true, false]);
    });
  });

  group('P0-4: Canonical config digest independent of map key order', () {
    test('computeCanonicalConfigDigest matches identical nested structures with different key order', () {
      final mapA = <String, dynamic>{
        'b': 2,
        'a': <String, dynamic>{'y': true, 'x': [1, 2, 3]},
      };
      final mapB = <String, dynamic>{
        'a': <String, dynamic>{'x': [1, 2, 3], 'y': true},
        'b': 2,
      };
      expect(
        computeCanonicalConfigDigest(mapA),
        computeCanonicalConfigDigest(mapB),
      );
    });
  });

  group('P1-1: TunRuntimeController notification dedup & idle poll backoff', () {
    test('accept suppresses notifyListeners when revision increments without displayState change', () {
      final runtime = TunRuntimeController()..desiredEnabled = true;
      var notifications = 0;
      runtime.addListener(() => notifications++);

      Map<String, Object?> frame(int rev) => {
            'schemaVersion': 1,
            'coreInstanceId': 'core-1',
            'revision': rev,
            'observedAt': rev,
            'requestedEnabled': true,
            'state': 'on',
            'listenerActive': true,
            'interfaceState': 'up',
            'privilege': 'elevated',
            'errorCode': null,
          };

      expect(runtime.accept(TunStatus.fromJson(frame(1)), 0), isTrue);
      expect(notifications, 1);
      // Subsequent identical poll with higher revision must not wake UI listeners
      expect(runtime.accept(TunStatus.fromJson(frame(2)), 0), isTrue);
      expect(notifications, 1);
    });

    test('nextTunObservationSchedule pauses tray polling when proxy is stopped or UAC failed', () {
      final stoppedRuntime = TunRuntimeController()..desiredEnabled = true;
      expect(
        nextTunObservationSchedule(
          runtime: stoppedRuntime,
          uiActive: false,
          repairActive: false,
          proxyRunning: false,
        ),
        isNull,
      );
      expect(
        nextTunObservationSchedule(
          runtime: stoppedRuntime,
          uiActive: true,
          repairActive: false,
          proxyRunning: false,
        ),
        const Duration(seconds: 30),
      );

      final deniedRuntime = TunRuntimeController()
        ..desiredEnabled = true
        ..fail('permissionDenied');
      expect(
        nextTunObservationSchedule(
          runtime: deniedRuntime,
          uiActive: false,
          repairActive: false,
          proxyRunning: true,
        ),
        isNull,
      );
      expect(
        nextTunObservationSchedule(
          runtime: deniedRuntime,
          uiActive: true,
          repairActive: false,
          proxyRunning: true,
        ),
        const Duration(seconds: 30),
      );
    });
  });

  group('P2-1, P2-2, P2-6, P2-7, P2-8, P2-9 fixes', () {
    test('P2-1: retry awaits delay between attempts instead of spinning at 0ms', () {
      fakeAsync((clock) {
        var calls = 0;
        int? finalResult;
        retry<int>(
          task: () async => ++calls,
          maxAttempts: 3,
          retryIf: (res) => res < 3,
          delay: const Duration(seconds: 2),
        ).then((value) => finalResult = value);

        clock.flushMicrotasks();
        expect(calls, 1);
        expect(finalResult, isNull);

        clock.elapse(const Duration(seconds: 2));
        expect(calls, 2);
        expect(finalResult, isNull);

        clock.elapse(const Duration(seconds: 2));
        expect(calls, 3);
        expect(finalResult, 3);
      });
    });

    test('P2-2: deleteProfileFilesInIsolate awaits recursive deletion before Isolate exits', () async {
      final tempDir = await Directory.systemTemp.createTemp('fcx-p2-2-');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final profileFile = File('${tempDir.path}/profile.yaml');
      await profileFile.writeAsString('mode: rule\n');
      final providersDir = Directory('${tempDir.path}/providers');
      await providersDir.create(recursive: true);
      await File('${providersDir.path}/sub.yaml').writeAsString('proxies: []\n');

      await deleteProfileFilesInIsolate(profileFile.path, providersDir.path);
      expect(await profileFile.exists(), isFalse);
      expect(await providersDir.exists(), isFalse);
    });

    test('P2-6: NodeCountryResolver bounds cached endpoints and servers', () async {
      final resolver = NodeCountryResolver(
        resolveServerCountry: (_) async => 'US',
        maxCachedEndpoints: 8,
      );
      addTearDown(resolver.dispose);

      final proxies = List.generate(
        24,
        (i) => <String, Object?>{
          'name': 'Node-$i',
          'type': 'ss',
          'server': 'edge-$i.example.com',
          'port': 443,
        },
      );
      resolver.registerProxyMaps('p1', proxies);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(resolver.cachedEndpointCount, lessThanOrEqualTo(8));
      expect(resolver.cachedServerCountryCount, lessThanOrEqualTo(8));
    });

    test('P2-7: FixedMap evicts oldest entry in O(1) and exposes live unmodifiable view', () {
      final fixed = FixedMap<String, int>(3);
      fixed.updateCacheValue('a', () => 1);
      fixed.updateCacheValue('b', () => 2);
      fixed.updateCacheValue('c', () => 3);
      fixed.updateCacheValue('d', () => 4);
      expect(fixed.length, 3);
      expect(fixed.containsKey('a'), isFalse);
      expect(fixed.map.keys.toList(), ['b', 'c', 'd']);
      expect(() => fixed.map['x'] = 9, throwsUnsupportedError);
    });

    test('P2-8: isReadableWindowsStartupProfile stops after first non-empty chunk', () async {
      final tempDir = await Directory.systemTemp.createTemp('fcx-p2-8-');
      addTearDown(() => tempDir.delete(recursive: true));
      final bigFile = File('${tempDir.path}/large.yaml');
      final prefix = utf8.encode('mode: rule\n${'#' * (256 * 1024)}\n');
      final builder = BytesBuilder(copy: false)
        ..add(prefix)
        // Trailing invalid UTF-8 at +256KB proves openRead() stopped after chunk 1!
        ..add(const [0xff, 0xfe]);
      await bigFile.writeAsBytes(builder.takeBytes(), flush: true);
      expect(await isReadableWindowsStartupProfile(bigFile.path), isTrue);
    });

    test('P2-9: PurchaseManager.refresh issues subscription, history, and cardStore concurrently', () async {
      final api = _ConcurrentRefreshApi();
      final storage = _InMemoryPurchaseStorage();
      final manager = PurchaseManager(
        api: api,
        storage: storage,
        synchronize: (_, __) async {},
      );
      addTearDown(manager.dispose);

      final initFuture = manager.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(api.maxObservedInFlight, 3);
      api.barrier.complete();
      await initFuture;
      expect(manager.loggedIn, isTrue);
      expect(manager.subscription?.valid, isTrue);
      expect(manager.cardStoreUrl, Uri.parse('https://store.example.test'));
    });
  });
}

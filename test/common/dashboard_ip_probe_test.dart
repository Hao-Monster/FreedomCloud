import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flclashx/common/fixed.dart';
import 'package:flclashx/common/http.dart';
import 'package:flclashx/common/request.dart';
import 'package:flclashx/common/tun_runtime.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Probe extends Fake implements Request {
  final calls = <Completer<Result<IpCheckProbeResult?>>>[];
  final tokens = <CancelToken>[];

  @override
  Future<Result<IpCheckProbeResult?>> checkIpWithHost({
    CancelToken? cancelToken,
    Duration keepAliveHold = const Duration(milliseconds: 4500),
    Duration connectTimeout = const Duration(seconds: 5),
    Duration? attemptTimeout,
    String Function(Uri)? proxyResolver,
    bool forceHoldSocket = false,
    void Function(Set<String>)? onSocketConnected,
  }) {
    final call = Completer<Result<IpCheckProbeResult?>>();
    calls.add(call);
    tokens.add(cancelToken!);
    return call.future;
  }

  void succeed(int index, String ip) => calls[index].complete(Result.success((
        ipInfo: IpInfo(ip: ip, countryCode: 'SG'),
        host: 'example.test',
        sourcePorts: {'43211'},
        routedViaClash: true,
      )));
}

void main() {
  setUp(() {
    globalState
      ..config = const Config(
        themeProps: defaultThemeProps,
        patchClashConfig: ClashConfig(globalUa: 'FlClashX/test'),
      )
      ..appState = AppState(
        isInit: true,
        version: 1,
        viewSize: Size.zero,
        requests: FixedList(2),
        logs: FixedList(2),
        traffics: FixedList(2),
        totalTraffic: Traffic(),
      )
      ..lastRuntimeConfig = null
      ..lastRuntimeProfileId = null;
  });

  test('dashboard requests the first IP when initialization finishes', () {
    globalState.appState = globalState.appState.copyWith(isInit: false);
    final container = ProviderContainer(overrides: [
      newDashboardEnabledProvider.overrideWithValue(true),
    ]);
    addTearDown(container.dispose);
    final ready = <bool>[];
    container.listen(checkIpProvider, (_, next) => ready.add(next.b),
        fireImmediately: true);
    expect(ready, [false]);
    container.read(initProvider.notifier).value = true;
    expect(container.read(checkIpProvider).b, isTrue);
    expect(ready, [false, true]);
  });

  test('manual and automatic checks share one probe and reject the old route',
      () async {
    final probe = _Probe();
    final detection = DetectionState.forTesting(probe)..startCheck();
    expect(detection.forceCheck(), isTrue);
    expect(probe.calls, hasLength(1));
    globalState.appState = globalState.appState.copyWith(runTime: 0);
    detection
      ..notifyRoutingChanged()
      ..startCheck();
    expect(probe.calls, hasLength(2));
    expect(probe.tokens.first.isCancelled, isTrue);
    probe
      ..succeed(1, '203.0.113.2')
      ..succeed(0, '203.0.113.1');
    await Future<void>.delayed(Duration.zero);
    expect(detection.state.value.ipInfo?.ip, '203.0.113.2');
    expect(detection.state.value.isTesting, isFalse);
    expect(detection.lastCompletedRoutingEpoch, detection.routingEpoch);
    expect(detection.lastProbeSourcePorts, {'43211'});
    expect(detection.forceCheck(), isFalse);
  });

  test('manual refresh probes again with the proxy off and clears failures',
      () async {
    final probe = _Probe();
    final detection = DetectionState.forTesting(probe)..startCheck();
    probe.succeed(0, '203.0.113.1');
    await Future<void>.delayed(Duration.zero);
    expect(detection.forceCheck(), isTrue);
    expect(probe.calls, hasLength(2));
    probe.calls[1].complete(Result.error('cancelled'));
    await Future<void>.delayed(Duration.zero);
    expect(detection.state.value.ipInfo, isNull);
    expect(detection.state.value.isLoading, isFalse);
    expect(detection.state.value.isTesting, isFalse);
  });

  test(
      'a stalled IP source is closed at its deadline; fallback keeps its own port',
      () async {
    final stalled = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(stalled.close);
    final stalledClosed = Completer<void>();
    stalled.listen((socket) {
      socket.listen((_) {}, onDone: () {
        socket.destroy();
        stalledClosed.complete();
      });
    });
    final fallback = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => fallback.close(force: true));
    int? fallbackPort;
    fallback.listen((req) async {
      fallbackPort = req.connectionInfo!.remotePort;
      req.response
        ..headers.contentType = ContentType.json
        ..write('{"ip":"198.51.100.22","country_code":"SG"}');
      await req.response.close();
    });
    final probe = Request(ipInfoSources: {
      'http://127.0.0.1:${stalled.port}/ip': IpInfo.fromIpSbJson,
      'http://127.0.0.1:${fallback.port}/ip': IpInfo.fromIpSbJson,
    });
    final res = await probe
        .checkIpWithHost(
          attemptTimeout: const Duration(milliseconds: 300),
          keepAliveHold: Duration.zero,
        )
        .timeout(const Duration(seconds: 2));
    expect(res.data?.ipInfo.ip, '198.51.100.22');
    expect(res.data?.sourcePorts, {'$fallbackPort'});
    await stalledClosed.future.timeout(const Duration(seconds: 1));
  });

  test(
      'transient null probe right after tunnel bring-up schedules one warm-up retry',
      () async {
    globalState.appState = globalState.appState.copyWith(runTime: 0);
    final probe = _Probe();
    final detection = DetectionState.forTesting(
      probe,
      warmupRetryDelay: const Duration(milliseconds: 25),
    )..startCheck();

    expect(probe.calls, hasLength(1));
    probe.calls[0].complete(Result.success(null));
    await Future<void>.delayed(Duration.zero);
    expect(detection.state.value.ipInfo, isNull);
    // During the warm-up retry window, keep loading/testing active instead of
    // flashing a false timeout failure card for 1.5s.
    expect(detection.state.value.isLoading, isTrue);
    expect(detection.state.value.isTesting, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 45));
    expect(probe.calls, hasLength(2));
    probe.succeed(1, '203.0.113.99');
    await Future<void>.delayed(Duration.zero);
    expect(detection.state.value.ipInfo?.ip, '203.0.113.99');
    expect(detection.state.value.isLoading, isFalse);
    expect(detection.state.value.isTesting, isFalse);
  });

  test(
      'IP probe uses the Windows System Proxy when TUN is only observed active',
      () async {
    if (!Platform.isWindows) return;
    final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => proxy.close(force: true));
    proxy.listen((request) async {
      await request.drain();
      request.response
        ..headers.contentType = ContentType.json
        ..write('{"ip":"198.51.100.42","country_code":"SG"}');
      await request.response.close();
    });

    globalState
      ..config = Config(
        themeProps: defaultThemeProps,
        networkProps: const NetworkProps(systemProxy: true),
        patchClashConfig: ClashConfig(mixedPort: proxy.port),
      )
      ..appState = globalState.appState.copyWith(runTime: 0)
      ..lastRuntimeConfig = <String, dynamic>{'mixed-port': proxy.port}
      ..lastRuntimeProfileId = null;
    final epoch = tunRuntime.observationEpoch;
    tunRuntime.accept(
      const TunStatus(
        instanceId: 'probe',
        revision: 1,
        state: 'on',
        listenerActive: true,
        interfaceState: 'up',
        privilege: 'elevated',
        requestedEnabled: true,
      ),
      epoch,
    );
    addTearDown(tunRuntime.invalidate);

    expect(
      FlClashHttpOverrides.handleFindProxy(
          Uri.parse('http://probe.invalid/ip')),
      'PROXY 127.0.0.1:${proxy.port}',
    );
    final result = await Request(ipInfoSources: {
      'http://probe.invalid/ip': IpInfo.fromIpSbJson,
    }).checkIpWithHost(
      attemptTimeout: const Duration(seconds: 1),
      keepAliveHold: Duration.zero,
    );

    expect(result.data?.ipInfo.ip, '198.51.100.42');
    expect(result.data?.ipInfo.countryCode, 'SG');
  });
}

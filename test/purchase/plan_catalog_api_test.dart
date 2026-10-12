import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flclashx/models/xboard.dart';
import 'package:flclashx/services/xboard_api.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _offer({
  int id = 7,
  String name = 'Public plan',
  bool purchasable = true,
  Map<String, Object?>? prices,
}) =>
    {
      'id': id,
      'name': name,
      'transfer_enable': 150,
      'speed_limit': 100,
      'device_limit': 3,
      'can_purchase': purchasable,
      'prices': prices ?? {'monthly': 990},
    };

Map<String, Object?> _success(Object? data) => {
      'status': 'success',
      'data': data,
    };

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handle);

  final Future<ResponseBody> Function(RequestOptions) handle;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    requests.add(options);
    return handle(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object? value, {int status = 200}) =>
    ResponseBody.fromString(jsonEncode(value), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });

void main() {
  late _Adapter adapter;
  late DioXboardApi api;

  void respond(Object? body, {int status = 200}) {
    adapter = _Adapter((_) async => _json(body, status: status));
    api = DioXboardApi(dio: Dio()..httpClientAdapter = adapter);
    addTearDown(api.close);
  }

  Matcher invalidResponse() => throwsA(isA<XboardException>()
      .having((error) => error.code, 'code', 'invalid_response'));

  test('public catalog uses the guest GET endpoint without account credentials',
      () async {
    respond(_success([_offer()]));
    final catalog = await api.getPlanCatalog();
    final request = adapter.requests.single;
    expect(
        request.uri, Uri.parse('https://fast.hjy.ca:8443/api/v1/guest/plans'));
    expect(request.method, 'GET');
    expect(request.headers.keys.map((key) => key.toLowerCase()),
        isNot(contains('authorization')));
    expect(request.data, isNull);
    expect(request.queryParameters, isEmpty);
    expect(request.followRedirects, isFalse);
    final plan = catalog.plans.single;
    expect(plan.id, 7);
    expect(plan.name, 'Public plan');
    expect(plan.transferGiB, 150);
    expect(plan.speedLimit, 100);
    expect(plan.deviceLimit, 3);
    expect(plan.prices.single.period, 'monthly');
    expect(plan.prices.single.amount, 990);
  });

  test('keeps server plan order and uses the defined purchase-period order',
      () async {
    respond(_success([
      _offer(id: 9, prices: {
        'onetime': 8000,
        'three_yearly': 7000,
        'two_yearly': 6000,
        'yearly': 5000,
        'half_yearly': 4000,
        'quarterly': 3000,
        'monthly': 2000,
      }),
      _offer(id: 2),
    ]));
    final catalog = await api.getPlanCatalog();
    expect(catalog.plans.map((plan) => plan.id), [9, 2]);
    expect(catalog.plans.first.prices.map((price) => price.period), [
      'monthly',
      'quarterly',
      'half_yearly',
      'yearly',
      'two_yearly',
      'three_yearly',
      'onetime',
    ]);
    expect(catalog.plans.first.prices.map((price) => price.amount),
        [2000, 3000, 4000, 5000, 6000, 7000, 8000]);
  });

  test('a prior authenticated request never leaks its bearer into the catalog',
      () async {
    adapter = _Adapter(
        (request) async => _json(_success(request.path == '/api/v1/auth/session'
            ? {
                'id': 4,
                'email': 'catalog@example.test',
                'is_distributor': false,
              }
            : [_offer()])));
    api = DioXboardApi(dio: Dio()..httpClientAdapter = adapter);
    addTearDown(api.close);
    await api.getAccount('Bearer catalog_fixture');
    await api.getPlanCatalog();
    expect(adapter.requests.first.headers['Authorization'],
        'Bearer catalog_fixture');
    expect(adapter.requests.last.headers.keys.map((key) => key.toLowerCase()),
        isNot(contains('authorization')));
  });

  test('only exposes purchasable plans with a new-purchase price', () async {
    respond(_success([
      _offer(id: 1, purchasable: false),
      _offer(id: 2, prices: {'reset_traffic': 100}),
      _offer(id: 3, prices: {'monthly': null}),
      _offer(id: 4, prices: {}),
      _offer(id: 5, prices: {
        'monthly': 0,
        'quarterly': null,
        'reset_traffic': 100,
        'unconfigured_future_period': null,
      }),
      _offer(id: 6, prices: {'reset_traffic': 0}),
    ]));
    final catalog = await api.getPlanCatalog();
    expect(catalog.plans.map((plan) => plan.id), [5]);
    expect(catalog.plans.single.prices.single.period, 'monthly');
    expect(catalog.plans.single.prices.single.amount, 0);
    expect(catalog.plans.single.resetTrafficPrice, 100);
  });

  test('nullable limits do not invent zero limits or byte conversions',
      () async {
    respond(_success([
      _offer()
        ..['speed_limit'] = null
        ..['device_limit'] = null,
    ]));
    final plan = (await api.getPlanCatalog()).plans.single;
    expect(plan.speedLimit, isNull);
    expect(plan.deviceLimit, isNull);
    expect(plan.transferGiB, 150);
  });

  test('preserves public content, tag order and additional plan metadata',
      () async {
    const content = '<p>套餐说明 &amp; details</p><ul><li>200 GiB</li></ul>';
    const tags = ['低延迟', '', ' 原样空格 ', '低延迟', '<b>Public tag</b>'];
    respond(_success([
      _offer(prices: {'monthly': 990, 'reset_traffic': 1234})
        ..['content'] = content
        ..['tags'] = tags
        ..['reset_traffic_method'] = 3
        ..['capacity_remaining'] = 12,
    ]));
    final plan = (await api.getPlanCatalog()).plans.single;
    expect(plan.content, content);
    expect(plan.tags, tags);
    expect(plan.resetTrafficMethod, 3);
    expect(plan.capacityRemaining, 12);
    expect(plan.resetTrafficPrice, 1234);
    expect(plan.hasSpeedLimit, isTrue);
    expect(plan.hasDeviceLimit, isTrue);
    expect(plan.hasResetTrafficMethod, isTrue);
    expect(plan.hasCapacityRemaining, isTrue);
    expect(plan.prices.map((price) => price.period), ['monthly']);
    expect(plan.prices.single.amount, 990);
  });

  test('missing optional fields retain legacy values and absent markers',
      () async {
    respond(_success([
      _offer()
        ..remove('speed_limit')
        ..remove('device_limit'),
    ]));
    final plan = (await api.getPlanCatalog()).plans.single;
    expect(plan.content, isEmpty);
    expect(plan.tags, isEmpty);
    expect(plan.speedLimit, isNull);
    expect(plan.deviceLimit, isNull);
    expect(plan.resetTrafficMethod, isNull);
    expect(plan.capacityRemaining, isNull);
    expect(plan.resetTrafficPrice, isNull);
    expect(plan.hasSpeedLimit, isFalse);
    expect(plan.hasDeviceLimit, isFalse);
    expect(plan.hasResetTrafficMethod, isFalse);
    expect(plan.hasCapacityRemaining, isFalse);
    expect(plan.prices.single.amount, 990);
  });

  test('explicit null metadata differs from omitted limit and reset fields',
      () async {
    respond(_success([
      _offer()
        ..['content'] = null
        ..['tags'] = null
        ..['speed_limit'] = null
        ..['device_limit'] = null
        ..['reset_traffic_method'] = null
        ..['capacity_remaining'] = null,
    ]));
    final plan = (await api.getPlanCatalog()).plans.single;
    expect(plan.content, isEmpty);
    expect(plan.tags, isEmpty);
    expect(plan.speedLimit, isNull);
    expect(plan.deviceLimit, isNull);
    expect(plan.resetTrafficMethod, isNull);
    expect(plan.capacityRemaining, isNull);
    expect(plan.hasSpeedLimit, isTrue);
    expect(plan.hasDeviceLimit, isTrue);
    expect(plan.hasResetTrafficMethod, isTrue);
    expect(plan.hasCapacityRemaining, isTrue);
  });

  test('zero limits, reset method and remaining capacity remain explicit zeros',
      () async {
    respond(_success([
      _offer()
        ..['speed_limit'] = 0
        ..['device_limit'] = 0
        ..['reset_traffic_method'] = 0
        ..['capacity_remaining'] = 0,
    ]));
    final plan = (await api.getPlanCatalog()).plans.single;
    expect(plan.speedLimit, 0);
    expect(plan.deviceLimit, 0);
    expect(plan.resetTrafficMethod, 0);
    expect(plan.capacityRemaining, 0);
    expect(plan.hasSpeedLimit, isTrue);
    expect(plan.hasDeviceLimit, isTrue);
    expect(plan.hasResetTrafficMethod, isTrue);
    expect(plan.hasCapacityRemaining, isTrue);
  });

  test(
      'model presence defaults infer non-null values and accept explicit flags',
      () {
    const legacy = XboardPlanOffer(
        id: 1, name: 'Legacy plan', transferGiB: 150, prices: []);
    expect(legacy.content, isEmpty);
    expect(legacy.tags, isEmpty);
    expect(legacy.hasSpeedLimit, isFalse);
    expect(legacy.hasDeviceLimit, isFalse);
    expect(legacy.hasResetTrafficMethod, isFalse);
    expect(legacy.hasCapacityRemaining, isFalse);
    const inferred = XboardPlanOffer(
      id: 2,
      name: 'Explicit zero plan',
      transferGiB: 150,
      prices: [],
      speedLimit: 0,
      deviceLimit: 0,
      resetTrafficMethod: 0,
      capacityRemaining: 0,
    );
    expect(inferred.hasSpeedLimit, isTrue);
    expect(inferred.hasDeviceLimit, isTrue);
    expect(inferred.hasResetTrafficMethod, isTrue);
    expect(inferred.hasCapacityRemaining, isTrue);
    const explicitNull = XboardPlanOffer(
      id: 3,
      name: 'Explicit null plan',
      transferGiB: 150,
      prices: [],
      hasSpeedLimit: true,
      hasDeviceLimit: true,
      hasResetTrafficMethod: true,
      hasCapacityRemaining: true,
    );
    expect(explicitNull.hasSpeedLimit, isTrue);
    expect(explicitNull.hasDeviceLimit, isTrue);
    expect(explicitNull.hasResetTrafficMethod, isTrue);
    expect(explicitNull.hasCapacityRemaining, isTrue);
    const explicitMissing = XboardPlanOffer(
      id: 4,
      name: 'Explicit absent markers',
      transferGiB: 150,
      prices: [],
      speedLimit: 0,
      deviceLimit: 0,
      resetTrafficMethod: 0,
      capacityRemaining: 0,
      hasSpeedLimit: false,
      hasDeviceLimit: false,
      hasResetTrafficMethod: false,
      hasCapacityRemaining: false,
    );
    expect(explicitMissing.hasSpeedLimit, isFalse);
    expect(explicitMissing.hasDeviceLimit, isFalse);
    expect(explicitMissing.hasResetTrafficMethod, isFalse);
    expect(explicitMissing.hasCapacityRemaining, isFalse);
  });

  for (final resetMethod in [0, 1, 2, 3, 4, 9, -1]) {
    test('retains reset method code $resetMethod without guessing a policy',
        () async {
      respond(_success([
        _offer()..['reset_traffic_method'] = resetMethod,
      ]));
      final plan = (await api.getPlanCatalog()).plans.single;
      expect(plan.resetTrafficMethod, resetMethod);
      expect(plan.hasResetTrafficMethod, isTrue);
    });
  }

  for (final invalidContent in <Object>[
    1,
    true,
    <Object>[],
    <String, Object>{}
  ]) {
    test('rejects non-string plan content $invalidContent', () async {
      respond(_success([
        _offer()..['content'] = invalidContent,
      ]));
      await expectLater(api.getPlanCatalog(), invalidResponse());
    });
  }

  for (final invalidTags in <Object>['one tag', 1, true, <String, Object>{}]) {
    test('rejects a non-array plan tag collection $invalidTags', () async {
      respond(_success([
        _offer()..['tags'] = invalidTags,
      ]));
      await expectLater(api.getPlanCatalog(), invalidResponse());
    });
  }

  for (final invalidTag in <Object?>[
    1,
    null,
    true,
    <String, Object>{},
    <Object>[]
  ]) {
    test('rejects a non-string member in plan tags $invalidTag', () async {
      respond(_success([
        _offer()..['tags'] = ['valid tag', invalidTag],
      ]));
      await expectLater(api.getPlanCatalog(), invalidResponse());
    });
  }

  for (final invalidMethod in <Object>[
    0.0,
    '0',
    true,
    <Object>[],
    <String, Object>{}
  ]) {
    test('rejects a non-integer reset method $invalidMethod', () async {
      respond(_success([
        _offer()..['reset_traffic_method'] = invalidMethod,
      ]));
      await expectLater(api.getPlanCatalog(), invalidResponse());
    });
  }

  for (final invalidCapacity in <Object>[
    -1,
    0.5,
    '1',
    true,
    <Object>[],
    <String, Object>{}
  ]) {
    test('rejects malformed remaining capacity $invalidCapacity', () async {
      respond(_success([
        _offer()..['capacity_remaining'] = invalidCapacity,
      ]));
      await expectLater(api.getPlanCatalog(), invalidResponse());
    });
  }

  for (final field in ['speed_limit', 'device_limit']) {
    for (final invalidLimit in <Object>[-1, 0.5, '1', true]) {
      test('rejects malformed $field value $invalidLimit', () async {
        respond(_success([
          _offer()..[field] = invalidLimit,
        ]));
        await expectLater(api.getPlanCatalog(), invalidResponse());
      });
    }
  }

  for (final resetPrice in [0, 1, 9000000000000000]) {
    test('retains exact reset traffic price $resetPrice outside sale periods',
        () async {
      respond(_success([
        _offer(prices: {'monthly': 990, 'reset_traffic': resetPrice}),
      ]));
      final plan = (await api.getPlanCatalog()).plans.single;
      expect(plan.resetTrafficPrice, resetPrice);
      expect(plan.prices.map((price) => price.period), ['monthly']);
      expect(plan.prices.single.amount, 990);
    });
  }

  test('missing and null reset prices never become free reset offers',
      () async {
    respond(_success([
      _offer(id: 1),
      _offer(id: 2, prices: {'monthly': 990, 'reset_traffic': null}),
    ]));
    final plans = (await api.getPlanCatalog()).plans;
    expect(plans, hasLength(2));
    expect(plans.map((plan) => plan.resetTrafficPrice), [null, null]);
    expect(
        plans.map((plan) => plan.prices.single.period), ['monthly', 'monthly']);
  });

  for (final invalidResetPrice in <Object>[
    -1,
    0.5,
    '1',
    true,
    <Object>[],
    9000000000000001
  ]) {
    test('rejects malformed or out-of-range reset price $invalidResetPrice',
        () async {
      respond(_success([
        _offer(prices: {'monthly': 990, 'reset_traffic': invalidResetPrice}),
      ]));
      await expectLater(api.getPlanCatalog(), invalidResponse());
    });
  }

  test('an explicitly empty public catalog is a valid empty result', () async {
    respond(_success([]));
    expect((await api.getPlanCatalog()).plans, isEmpty);
  });

  test('retains the exact maximum supported integer price in minor units',
      () async {
    respond(_success([
      _offer(prices: {'monthly': 9000000000000000}),
    ]));
    expect((await api.getPlanCatalog()).plans.single.prices.single.amount,
        9000000000000000);
  });

  test('rejects an integer price beyond the supported monetary bound',
      () async {
    respond(_success([
      _offer(prices: {'monthly': 9000000000000001}),
    ]));
    await expectLater(api.getPlanCatalog(), invalidResponse());
  });

  test('duplicate public plan identifiers fail instead of producing two quotes',
      () async {
    respond(_success([
      _offer(),
      _offer(prices: {'monthly': 100})
    ]));
    await expectLater(api.getPlanCatalog(), invalidResponse());
  });

  test('missing price map fails instead of inventing free or empty plans',
      () async {
    respond(_success([_offer()..remove('prices')]));
    await expectLater(api.getPlanCatalog(), invalidResponse());
  });

  for (final invalidPrice in <Object>[-1, 9.9, '990', true, <Object>[]]) {
    test('rejects malformed price $invalidPrice instead of showing zero',
        () async {
      respond(_success([
        _offer(prices: {'monthly': invalidPrice}),
      ]));
      await expectLater(api.getPlanCatalog(), invalidResponse());
    });
  }

  test('rejects a priced unknown period instead of silently hiding its quote',
      () async {
    respond(_success([
      _offer(prices: {'monthly': 100, 'weekly': 40}),
    ]));
    await expectLater(api.getPlanCatalog(), invalidResponse());
  });

  for (final invalidBody in <Object?>[
    _success(null),
    _success({}),
    {'data': <Object>[]},
    _success([null]),
  ]) {
    test('rejects invalid catalog envelope $invalidBody', () async {
      respond(invalidBody);
      await expectLater(api.getPlanCatalog(), invalidResponse());
    });
  }

  test('does not turn an unavailable guest endpoint into an empty catalog',
      () async {
    respond({'status': 'fail', 'message': 'Temporarily unavailable'},
        status: 503);
    await expectLater(api.getPlanCatalog(), throwsA(isA<XboardException>()));
    expect(adapter.requests, hasLength(1));
  });
}

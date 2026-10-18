import 'dart:async';
import 'dart:convert';

import 'package:flclashx/common/node_catalog_provider_resolver.dart';
import 'package:flclashx/common/node_catalog_service.dart';
import 'package:flclashx/models/node_catalog.dart';
import 'package:flclashx/models/profile.dart';
import 'package:flutter_test/flutter_test.dart';

Profile _profile(String id, {bool updating = false}) => Profile(
      id: id,
      autoUpdateDuration: Duration.zero,
      isUpdating: updating,
    );

Map<String, dynamic> _config([String name = 'Node']) => {
      'proxies': [
        {'name': name, 'type': 'ss', 'server': 'private.example', 'port': 443},
        {'name': 'DIRECT', 'type': 'direct'},
        {'name': 'REJECT', 'type': 'reject'},
        {'name': 'DROP', 'type': 'reject-drop'},
        {'name': 'PASS', 'type': 'pass'},
        {'name': 'DNS', 'type': 'dns'},
        {'name': 'COMPATIBLE', 'type': 'compatible'},
      ],
      'proxy-groups': [
        {
          'name': 'First',
          'type': 'select',
          'proxies': [name]
        },
        {
          'name': 'Auto',
          'type': 'url-test',
          'proxies': [name]
        },
        {
          'name': 'Second',
          'type': 'select',
          'proxies': [name]
        },
      ],
      'proxy-providers': {
        'Provider': {'type': 'http', 'url': 'https://private.example/token'},
      },
    };

void main() {
  late int reads;
  late int evaluations;
  late ({int modifiedMicros, int size})? metadata;
  late String script;
  late NodeCatalogService service;

  setUp(() {
    reads = 0;
    evaluations = 0;
    metadata = (modifiedMicros: 100, size: 200);
    script = 'script-id|safe-hash';
    service = NodeCatalogService(
      readProfileConfig: (id) async {
        reads++;
        return _config();
      },
      evaluate: (raw) async {
        evaluations++;
        return raw;
      },
      fileMetadata: (id) async => metadata,
      scriptFingerprint: () => script,
    );
  });

  test(
      'uses read then evaluate, keeps leaves, select order and unknown providers',
      () async {
    final catalog = await service.load(_profile('a'));
    expect(catalog.status, ProfileCatalogStatus.ready);
    expect(catalog.nodes.map((node) => node.name), ['Node']);
    expect(catalog.nodes.single.selectGroups, ['First', 'Second']);
    expect(catalog.providerNodeCounts, {'Provider': -1});
    expect(catalog.fingerprint, '100|200|script-id|safe-hash');
    expect(reads, 1);
    expect(evaluations, 1);
  });

  test('script output determines the catalog nodes', () async {
    service = NodeCatalogService(
      readProfileConfig: (id) async => _config('Before'),
      evaluate: (raw) async {
        expect((raw['proxies'] as List).first['name'], 'Before');
        return _config('After');
      },
      fileMetadata: (id) async => metadata,
      scriptFingerprint: () => script,
    );
    expect((await service.load(_profile('a'))).nodes.single.name, 'After');
  });

  test('script bridge maps with dynamic keys keep the same safe projection',
      () {
    final raw = _config();
    raw['proxies'] = [
      <dynamic, dynamic>{
        'name': 'Script',
        'type': 'ss',
        'server': 'private.example',
        'port': '443',
        'password': 'secret',
      },
    ];
    final catalog = buildProfileCatalog(
      profileId: 'a',
      fingerprint: 'f',
      raw: raw,
    );
    expect(catalog.nodes.single.name, 'Script');
    expect(catalog.toString(), isNot(contains('private.example')));
    expect(catalog.toString(), isNot(contains('secret')));
  });

  test(
      'file missing does not parse; updating reuses old catalog without parsing',
      () async {
    metadata = null;
    expect((await service.load(_profile('a'))).status,
        ProfileCatalogStatus.fileMissing);
    expect(reads, 0);
    metadata = (modifiedMicros: 100, size: 200);
    expect((await service.load(_profile('a', updating: true))).status,
        ProfileCatalogStatus.updating);
    expect(reads, 0);
    final cached = await service.load(_profile('a'));
    final updating = await service.load(_profile('a', updating: true));
    expect(updating.status, ProfileCatalogStatus.updating);
    expect(updating.nodes, cached.nodes);
    expect(reads, 1);
  });

  test('metadata, script and explicit invalidation rebuild the catalog',
      () async {
    final first = await service.load(_profile('a'));
    expect(await service.load(_profile('a')), same(first));
    expect(reads, 1);
    metadata = (modifiedMicros: 101, size: 200);
    await service.load(_profile('a'));
    metadata = (modifiedMicros: 101, size: 201);
    await service.load(_profile('a'));
    script = 'other-script|other-hash';
    await service.load(_profile('a'));
    service.invalidate('a');
    expect(service.peek('a'), isNull);
    await service.load(_profile('a'));
    expect(reads, 5);
    service.clear();
    expect(service.peek('a'), isNull);
  });

  test(
      'updating retains an invalidated snapshot but never makes it a ready hit',
      () async {
    final first = await service.load(_profile('a'));
    service.invalidate('a', keepCached: true);
    expect(service.peek('a'), same(first));
    final updating = await service.load(_profile('a', updating: true));
    expect(updating.status, ProfileCatalogStatus.updating);
    expect(updating.nodes, first.nodes);
    expect(reads, 1);
    final refreshed = await service.load(_profile('a'));
    expect(refreshed.status, ProfileCatalogStatus.ready);
    expect(reads, 2);
    expect(await service.load(_profile('a')), same(refreshed));
    expect(reads, 2);
  });

  test('LRU keeps at most eight catalogs and hits refresh recency', () async {
    for (var i = 0; i < 8; i++) {
      await service.load(_profile('$i'));
    }
    await service.load(_profile('0'));
    await service.load(_profile('8'));
    expect(service.peek('0'), isNotNull);
    expect(service.peek('1'), isNull);
    expect(service.peek('8'), isNotNull);
    expect(reads, 9);
  });

  test('same-profile loads share a future and all builds are limited to two',
      () async {
    final pendingReads = <String, Completer<Map<String, dynamic>>>{};
    var active = 0;
    var maximum = 0;
    service = NodeCatalogService(
      readProfileConfig: (id) async {
        active++;
        if (active > maximum) maximum = active;
        final pending = Completer<Map<String, dynamic>>();
        pendingReads[id] = pending;
        final raw = await pending.future;
        active--;
        return raw;
      },
      evaluate: (raw) async => raw,
      fileMetadata: (id) async => metadata,
      scriptFingerprint: () => script,
    );
    final first = service.load(_profile('a'));
    expect(service.load(_profile('a')), same(first));
    final second = service.load(_profile('b'));
    final third = service.load(_profile('c'));
    await Future<void>.delayed(Duration.zero);
    expect(pendingReads.keys, ['a', 'b']);
    pendingReads['a']!.complete(_config());
    await first;
    await Future<void>.delayed(Duration.zero);
    expect(pendingReads.keys, ['a', 'b', 'c']);
    pendingReads['b']!.complete(_config());
    pendingReads['c']!.complete(_config());
    await Future.wait([second, third]);
    expect(maximum, 2);
  });

  test('invalidating an in-flight build prevents it from overwriting a new one',
      () async {
    final oldRead = Completer<Map<String, dynamic>>();
    service = NodeCatalogService(
      readProfileConfig: (id) {
        reads++;
        return reads == 1 ? oldRead.future : Future.value(_config('New'));
      },
      evaluate: (raw) async => raw,
      fileMetadata: (id) async => metadata,
      scriptFingerprint: () => script,
    );
    final first = service.load(_profile('a'));
    await Future<void>.delayed(Duration.zero);
    service.invalidate('a');
    final current = await service.load(_profile('a'));
    expect(current.nodes.single.name, 'New');
    oldRead.complete(_config('Old'));
    await first;
    expect(service.peek('a')!.nodes.single.name, 'New');
  });

  test(
      'errors never expose parser secrets; malformed lists are not empty success',
      () async {
    for (final raw in [
      null,
      {'proxies': 'not-a-list'},
      {'proxy-groups': 'not-a-list'},
      {
        'proxy-providers': ['not-a-map']
      },
    ]) {
      service = NodeCatalogService(
        readProfileConfig: (id) async {
          if (raw == null) {
            throw StateError(
                'password secret-value private.example https://x/token');
          }
          return raw;
        },
        evaluate: (raw) async => raw,
        fileMetadata: (id) async => metadata,
        scriptFingerprint: () => script,
      );
      final catalog = await service.load(_profile('a'));
      expect(catalog.status, ProfileCatalogStatus.parseFailed);
      expect(catalog.errorSummary, 'parseFailed');
      expect(catalog.toString(), isNot(contains('secret-value')));
      expect(catalog.toString(), isNot(contains('private.example')));
    }
  });

  test('one malformed leaf preserves healthy leaves with a safe placeholder',
      () async {
    final raw = _config();
    (raw['proxies'] as List).insert(1, {
      'name': 'Broken',
      'type': 'ss',
      'server': 'private-broken.example',
      'password': 'secret-broken-password',
    });
    service = NodeCatalogService(
      readProfileConfig: (id) async => raw,
      evaluate: (raw) async => raw,
      fileMetadata: (id) async => metadata,
      scriptFingerprint: () => script,
    );
    final catalog = await service.load(_profile('a'));
    expect(catalog.status, ProfileCatalogStatus.ready);
    expect(catalog.nodes.map((node) => node.name), ['Node', 'Broken']);
    expect(catalog.nodes.first.unsupported, CatalogUnsupportedReason.none);
    expect(catalog.nodes.first.selectGroups, ['First', 'Second']);
    final broken = catalog.nodes.last;
    expect(broken.unsupported, CatalogUnsupportedReason.parseFailed);
    expect(broken.identityKey, startsWith('invalid:v1:'));
    expect(broken.identityKey, isNot(matches(RegExp(r'^[a-f0-9]{32}$'))));
    expect(broken.endpointKey, isEmpty);
    expect(broken.selectGroups, isEmpty);
    final output = '${catalog.toString()} ${jsonEncode(catalog.toJson())}';
    expect(output, isNot(contains('private-broken.example')));
    expect(output, isNot(contains('secret-broken-password')));
  });

  test('peers-only WireGuard and malformed items stay visible without secrets',
      () {
    final raw = <String, dynamic>{
      'proxies': [
        {'name': 'Healthy', 'type': 'ss', 'server': 'ok.invalid', 'port': 443},
        {
          'name': 'Peers-only',
          'type': 'wireguard',
          'private-key': 'secret-private-key',
          'peers': [
            {
              'server': 'private-peer.invalid',
              'port': 51820,
              'public-key': 'secret-peer-key'
            }
          ],
        },
        'secret-malformed-value',
        {
          'name': 42,
          'type': ['secret-type-value'],
          'uuid': 'secret-uuid'
        },
        {'name': 'No endpoint', 'type': 'ss'},
      ],
    };
    ProfileCatalog parse() =>
        buildProfileCatalog(profileId: 'a', fingerprint: 'f', raw: raw);
    final catalog = parse();
    expect(catalog.status, ProfileCatalogStatus.ready);
    expect(catalog.nodes.map((node) => node.name),
        ['Healthy', 'Peers-only', '#3', '#4', 'No endpoint']);
    expect(catalog.nodes.skip(1).map((node) => node.unsupported),
        everyElement(CatalogUnsupportedReason.parseFailed));
    expect(catalog.nodes.skip(1).map((node) => node.endpointKey),
        everyElement(isEmpty));
    expect(catalog.nodes.map((node) => node.identityKey).toSet(), hasLength(5));
    expect(parse().nodes, catalog.nodes);
    final output = '${catalog.toString()} ${jsonEncode(catalog.toJson())}';
    for (final secret in [
      'secret-private-key',
      'private-peer.invalid',
      'secret-peer-key',
      'secret-malformed-value',
      'secret-type-value',
      'secret-uuid',
      'ok.invalid',
    ]) {
      expect(output, isNot(contains(secret)));
    }
    expect(catalog.nodes[2].type, 'unknown');
    expect(catalog.nodes[3].type, 'unknown');
  });

  test('malformed placeholders count toward the same 2000-node limit', () {
    final raw = <String, dynamic>{'proxies': List.filled(2000, null)};
    final catalog = buildProfileCatalog(
        profileId: 'a', fingerprint: 'f', raw: raw, maxNodes: 2000);
    expect(catalog.nodes, hasLength(2000));
    expect(
        catalog.nodes.map((node) => node.identityKey).toSet(), hasLength(2000));
    raw['proxies'] = List.filled(2001, null);
    expect(
        () => buildProfileCatalog(
            profileId: 'a', fingerprint: 'f', raw: raw, maxNodes: 2000),
        throwsA(isA<CatalogBuildException>()
            .having((error) => error.reason, 'reason', 'tooManyNodes')));
  });

  test('display projects over 2000 leaves while legacy prepare stays bounded',
      () async {
    service = NodeCatalogService(
      readProfileConfig: (id) async => {
        'proxies': List.generate(
          2001,
          (i) => {'name': 'N$i', 'type': 'ss', 'server': 'x', 'port': 443},
        ),
      },
      evaluate: (raw) async => raw,
      fileMetadata: (id) async => metadata,
      scriptFingerprint: () => script,
      prepareCatalog: (_, __, ___) async =>
          throw StateError('Oversized legacy catalog must not be sent'),
      releaseCatalog: (_) async => true,
    );
    final catalog = await service.load(_profile('a'));
    expect(catalog.status, ProfileCatalogStatus.ready);
    expect(catalog.nodes, hasLength(2001));
    expect(catalog.nodes.last.name, 'N2000');
    await expectLater(
        service.ensurePrepared(_profile('a')),
        throwsA(isA<CatalogBuildException>()
            .having((e) => e.reason, 'reason', 'tooManyNodes')));
  });

  test(
      'selectGroups resolves explicit proxies, include-all flags, and provider use across build and resolveForTestAll',
      () async {
    ProfileCatalog? preparedSnapshot;
    service = NodeCatalogService(
      readProfileConfig: (id) async => {
        'proxies': [
          {
            'name': 'Inline A',
            'type': 'ss',
            'server': 'inline.invalid',
            'port': 443,
          },
        ],
        'proxy-groups': [
          {
            'name': 'Explicit',
            'type': 'select',
            'proxies': ['Inline A'],
          },
          {
            'name': 'InlineAll',
            'type': 'select',
            'include-all-proxies': true,
          },
          {
            'name': 'ProviderUse',
            'type': 'select',
            'use': ['FeedA'],
          },
          {
            'name': 'ProviderAll',
            'type': 'select',
            'include-all-providers': true,
          },
          {
            'name': 'GlobalSelect',
            'type': 'select',
            'include-all': true,
          },
        ],
        'proxy-providers': {
          'FeedA': {'type': 'inline'},
        },
      },
      evaluate: (raw) async => raw,
      fileMetadata: (id) async => metadata,
      scriptFingerprint: () => script,
      onPrepared: (catalog) => preparedSnapshot = catalog,
      providerResolver: CatalogProviderResolver(
        homeDirectory: () async => '/tmp',
        httpCachePath: (id, url) async => '/tmp/unused',
        parse: (_, __) async => jsonEncode({
          'rejected': 0,
          'proxies': [
            {
              'name': 'Provider B',
              'type': 'vmess',
              'server': 'provider.invalid',
              'port': 443,
              'uuid': '00000000-0000-0000-0000-000000000000',
            },
          ],
        }),
      ),
    );
    final initial = await service.load(_profile('a'));
    expect(
      initial.nodes.single.selectGroups,
      ['Explicit', 'InlineAll', 'GlobalSelect'],
    );
    final plan = await service.resolveForTestAll(
      _profile('a'),
      isCurrent: () => true,
    );
    addTearDown(plan.dispose);
    expect(plan.nodes, hasLength(2));
    expect(
      plan.nodes[0].selectGroups,
      ['Explicit', 'InlineAll', 'GlobalSelect'],
    );
    expect(
      plan.nodes[1].selectGroups,
      ['ProviderUse', 'ProviderAll', 'GlobalSelect'],
    );
    expect(
      preparedSnapshot?.nodes.map((n) => n.selectGroups).toList(),
      [
        ['Explicit', 'InlineAll', 'GlobalSelect'],
        ['ProviderUse', 'ProviderAll', 'GlobalSelect'],
      ],
    );
  });

  test(
      'selectGroups preserves declaration order and applies hidden, filter, exclude-filter, and exclude-type rules',
      () {
    final catalog = buildProfileCatalog(
      profileId: 'a',
      fingerprint: 'f',
      raw: {
        'proxies': [
          {
            'name': 'HK Premium 01',
            'type': 'ss',
            'server': 'hk.invalid',
            'port': 443,
          },
          {
            'name': 'US Trial 01',
            'type': 'vmess',
            'server': 'us.invalid',
            'port': 443,
            'uuid': '00000000-0000-0000-0000-000000000000',
          },
        ],
        'proxy-groups': [
          {
            'name': 'HiddenSelect',
            'type': 'select',
            'hidden': true,
            'include-all': true,
          },
          {
            'name': 'PrimaryIncludeAll',
            'type': 'select',
            'include-all': true,
            'exclude-filter': '(?i)trial',
          },
          {
            'name': 'HKManual',
            'type': 'select',
            'include-all-proxies': true,
            'filter': '(?i)hk`hongkong',
          },
          {
            'name': 'NoVmess',
            'type': 'select',
            'include-all': true,
            'exclude-type': 'vmess|trojan',
          },
          {
            'name': 'SecondaryExplicit',
            'type': 'select',
            'proxies': ['HK Premium 01', 'US Trial 01'],
          },
        ],
      },
    );
    expect(
      catalog.nodes[0].selectGroups,
      ['PrimaryIncludeAll', 'HKManual', 'NoVmess', 'SecondaryExplicit'],
    );
    expect(
      catalog.nodes[1].selectGroups,
      ['SecondaryExplicit'],
    );
  });

  test(
      'selectGroups maps YAML proxy types to Mihomo AdapterType names for exclude-type and supports PCRE filter syntax with fail-closed fallback',
      () {
    final catalog = buildProfileCatalog(
      profileId: 'a',
      fingerprint: 'f',
      raw: {
        'proxies': [
          {
            'name': 'HK SS',
            'type': 'ss',
            'server': 'hk.invalid',
            'port': 443,
            'cipher': 'aes-128-gcm',
            'password': 'secret',
          },
          {
            'name': 'US SS',
            'type': 'ss',
            'server': 'us.invalid',
            'port': 443,
            'cipher': 'aes-128-gcm',
            'password': 'secret',
          },
          {
            'name': 'HK SSR',
            'type': 'ssr',
            'server': 'ssr.invalid',
            'port': 443,
            'cipher': 'aes-256-cfb',
            'password': 'secret',
            'protocol': 'origin',
            'obfs': 'plain',
          },
        ],
        'proxy-groups': [
          {
            'name': 'NoShadowsocks',
            'type': 'select',
            'include-all': true,
            'exclude-type': 'Shadowsocks|ShadowsocksR',
          },
          {
            'name': 'ScopedIgnoreCaseHK',
            'type': 'select',
            'include-all': true,
            'filter': '(?i:hk)',
          },
          {
            'name': 'AtomicGroupHK',
            'type': 'select',
            'include-all': true,
            'filter': '(?i)^(?>HK|Hong Kong)',
          },
          {
            'name': 'BrokenFilterFailClosed',
            'type': 'select',
            'include-all': true,
            'filter': '[unclosed',
          },
          {
            'name': 'BrokenExcludeFilterFailClosed',
            'type': 'select',
            'include-all': true,
            'exclude-filter': '[unclosed',
          },
          {
            'name': 'Fallback',
            'type': 'select',
            'include-all': true,
          },
        ],
      },
    );
    expect(
      catalog.nodes[0].selectGroups,
      ['ScopedIgnoreCaseHK', 'Fallback'],
    );
    expect(
      catalog.nodes[1].selectGroups,
      ['Fallback'],
    );
    expect(
      catalog.nodes[2].selectGroups,
      ['ScopedIgnoreCaseHK', 'Fallback'],
    );
  });

  test(
      'selectGroups preserves Core regex semantics for start anchors and escaped characters under scoped ignore-case and fails closed on atomic groups',
      () {
    for (final fixture in [
      (node: 'HK', key: 'filter', pattern: r'^(?>HK|H)K$'),
      (node: 'HK node', key: 'exclude-filter', pattern: r'\AHK'),
      (node: 'HKX', key: 'exclude-filter', pattern: r'(?i)^\x68k(?-i)X$'),
    ]) {
      final catalog = buildProfileCatalog(
        profileId: 'fixture',
        fingerprint: 'f',
        raw: {
          'proxies': [
            {
              'name': fixture.node,
              'type': 'ss',
              'server': 'fixture.invalid',
              'port': 443,
              'cipher': 'aes-128-gcm',
              'password': 'secret',
            },
          ],
          'proxy-groups': [
            {
              'name': 'Primary',
              'type': 'select',
              'include-all': true,
              fixture.key: fixture.pattern,
            },
            {
              'name': 'Fallback',
              'type': 'select',
              'proxies': [fixture.node],
            },
          ],
        },
      );
      expect(catalog.nodes.single.selectGroups, ['Fallback']);
    }
  });

  test(
      'selectGroups preserves regex alternation, quantifiers, and Core Unicode shorthand semantics',
      () {
    for (final fixture in [
      (node: 'HK', key: 'filter', pattern: 'HK|JP', expected: ['Primary', 'Fallback']),
      (node: 'HK', key: 'exclude-filter', pattern: 'HK|JP', expected: ['Fallback']),
      (node: 'HK01', key: 'exclude-filter', pattern: r'^HK.*$', expected: ['Fallback']),
      (node: 'HK01', key: 'exclude-filter', pattern: r'^HK[0-9]{2}$', expected: ['Fallback']),
      (node: '港', key: 'exclude-filter', pattern: r'^\w$', expected: ['Fallback']),
      (node: '١', key: 'exclude-filter', pattern: r'^\d$', expected: ['Fallback']),
      (node: '港', key: 'exclude-filter', pattern: r'\b港\b', expected: ['Fallback']),
      (node: 'HK|JP', key: 'exclude-filter', pattern: r'HK\|JP', expected: ['Fallback']),
      (node: '港', key: 'exclude-filter', pattern: r'^[\w]$', expected: ['Fallback']),
      (node: '١', key: 'exclude-filter', pattern: r'^[\d]$', expected: ['Fallback']),
    ]) {
      final catalog = buildProfileCatalog(
        profileId: 'fixture',
        fingerprint: 'f',
        raw: {
          'proxies': [
            {
              'name': fixture.node,
              'type': 'ss',
              'server': 'fixture.invalid',
              'port': 443,
              'cipher': 'aes-128-gcm',
              'password': 'secret',
            },
          ],
          'proxy-groups': [
            {
              'name': 'Primary',
              'type': 'select',
              'include-all': true,
              fixture.key: fixture.pattern,
            },
            {
              'name': 'Fallback',
              'type': 'select',
              'proxies': [fixture.node],
            },
          ],
        },
      );
      expect(
        catalog.nodes.single.selectGroups,
        fixture.expected,
        reason: '${fixture.key}: ${fixture.pattern} on ${fixture.node}',
      );
    }
  });

  test(
      'selectGroups aligns Unicode case equivalence and newline anchor boundaries with Core regexp2.None',
      () {
    for (final fixture in [
      (node: 'İstanbul', key: 'exclude-filter', pattern: r'(?i)^istanbul$', expected: ['Fallback']),
      (node: 'ſ', key: 'filter', pattern: r'(?i)^s$', expected: ['Fallback']),
      (node: 'SX', key: 'filter', pattern: r'(?i:ſ)X', expected: ['Fallback']),
      (node: 'ẞ', key: 'exclude-filter', pattern: r'(?i)^ß$', expected: ['Fallback']),
      (node: 'K', key: 'filter', pattern: r'(?i)^k$', expected: ['Primary', 'Fallback']),
      (node: 'ς', key: 'filter', pattern: r'(?i)^σ$', expected: ['Fallback']),
      (node: 'σ', key: 'filter', pattern: r'(?i)^ς$', expected: ['Fallback']),
      (node: 'İ', key: 'exclude-filter', pattern: r'(?i)^[a-z]$', expected: ['Fallback']),
      (node: 'ſ', key: 'filter', pattern: r'(?i)^[a-z]$', expected: ['Fallback']),
      (node: 'HK\n', key: 'exclude-filter', pattern: r'^HK$', expected: ['Fallback']),
      (node: 'HK\r\n', key: 'exclude-filter', pattern: r'^HK.*$', expected: ['Fallback']),
      (node: 'HK\r', key: 'filter', pattern: r'(?m)^HK$', expected: ['Fallback']),
      (node: 'HK\nX', key: 'filter', pattern: r'(?m)^HK$', expected: ['Primary', 'Fallback']),
      (node: 'x\nHK', key: 'filter', pattern: r'(?m)^HK$', expected: ['Primary', 'Fallback']),
      (node: 'x\rHK', key: 'filter', pattern: r'(?m)^HK$', expected: ['Fallback']),
      (node: '\r\n', key: 'exclude-filter', pattern: r'^\W$', expected: ['Fallback']),
    ]) {
      final catalog = buildProfileCatalog(
        profileId: 'fixture',
        fingerprint: 'f',
        raw: {
          'proxies': [
            {
              'name': fixture.node,
              'type': 'ss',
              'server': 'fixture.invalid',
              'port': 443,
              'cipher': 'aes-128-gcm',
              'password': 'secret',
            },
          ],
          'proxy-groups': [
            {
              'name': 'Primary',
              'type': 'select',
              'include-all': true,
              fixture.key: fixture.pattern,
            },
            {
              'name': 'Fallback',
              'type': 'select',
              'proxies': [fixture.node],
            },
          ],
        },
      );
      expect(
        catalog.nodes.single.selectGroups,
        fixture.expected,
        reason: '${fixture.key}: ${fixture.pattern} on ${fixture.node}',
      );
    }
  });

  test(
      r'selectGroups aligns \w, \W, \d, \D, \b, and \B with Core Go Unicode 15.0.0 tables instead of newer Dart Unicode properties',
      () {
    for (final fixture in [
      (node: '\u1C89', key: 'filter', pattern: r'^\w$', expected: ['Fallback']),
      (node: '\u1C89', key: 'filter', pattern: r'^[\w]$', expected: ['Fallback']),
      (node: '\u1C89', key: 'exclude-filter', pattern: r'^\W$', expected: ['Fallback']),
      (node: '\u1C89', key: 'filter', pattern: r'\b\u1C89\b', expected: ['Fallback']),
      (node: '\u1C89', key: 'exclude-filter', pattern: r'^\B\u1C89\B$', expected: ['Fallback']),
      (node: '\u{10D40}', key: 'filter', pattern: r'^\d$', expected: ['Fallback']),
      (node: '\u{10D40}', key: 'filter', pattern: r'^[\d]$', expected: ['Fallback']),
      (node: '\u{10D40}', key: 'exclude-filter', pattern: r'^\D$', expected: ['Fallback']),
      (node: '\u{10D40}', key: 'exclude-filter', pattern: r'^[\D]$', expected: ['Fallback']),
      (node: '\u{1CCF0}', key: 'exclude-filter', pattern: r'^\D$', expected: ['Fallback']),
      (node: '\u{1CCF0}', key: 'exclude-filter', pattern: r'^[\D]$', expected: ['Fallback']),
      (node: '\u{1CCF0}', key: 'filter', pattern: r'^\d$', expected: ['Fallback']),
      (node: '\uA7CB', key: 'filter', pattern: r'^\w$', expected: ['Fallback']),
      (node: '\u{105C0}', key: 'filter', pattern: r'^\w$', expected: ['Fallback']),
      (node: '\u{13460}', key: 'filter', pattern: r'^\w$', expected: ['Fallback']),
      (node: '\u{2EBF0}', key: 'filter', pattern: r'^\w$', expected: ['Fallback']),
      (node: '港', key: 'exclude-filter', pattern: r'^\w$', expected: ['Fallback']),
      (node: '١', key: 'exclude-filter', pattern: r'^\d$', expected: ['Fallback']),
      (node: '5', key: 'filter', pattern: r'^[\D\w]$', expected: ['Fallback']),
      (node: '5', key: 'filter', pattern: r'^[\D\d]$', expected: ['Fallback']),
      (node: '.', key: 'filter', pattern: r'^[\--0]$', expected: ['Fallback']),
      (node: '"', key: 'filter', pattern: r'^[!-\-]$', expected: ['Fallback']),
      (node: '-', key: 'filter', pattern: r'^[a\-z]$', expected: ['Primary', 'Fallback']),
      (node: 'HK', key: 'filter', pattern: r'(?I)^hk$', expected: ['Primary', 'Fallback']),
    ]) {
      final catalog = buildProfileCatalog(
        profileId: 'fixture',
        fingerprint: 'f',
        raw: {
          'proxies': [
            {
              'name': fixture.node,
              'type': 'ss',
              'server': 'fixture.invalid',
              'port': 443,
              'cipher': 'aes-128-gcm',
              'password': 'secret',
            },
          ],
          'proxy-groups': [
            {
              'name': 'Primary',
              'type': 'select',
              'include-all': true,
              fixture.key: fixture.pattern,
            },
            {
              'name': 'Fallback',
              'type': 'select',
              'proxies': [fixture.node],
            },
          ],
        },
      );
      expect(
        catalog.nodes.single.selectGroups,
        fixture.expected,
        reason: '${fixture.key}: ${fixture.pattern} on ${fixture.node.runes.map((r) => 'U+${r.toRadixString(16).toUpperCase()}').join(' ')}',
      );
    }

    final invalidFilterWithExplicit = buildProfileCatalog(
      profileId: 'fixture-explicit',
      fingerprint: 'f',
      raw: {
        'proxies': [
          {
            'name': 'HK',
            'type': 'ss',
            'server': 'fixture.invalid',
            'port': 443,
            'cipher': 'aes-128-gcm',
            'password': 'secret',
          },
        ],
        'proxy-groups': [
          {
            'name': 'Primary',
            'type': 'select',
            'proxies': ['HK'],
            'filter': r'^(?>HK|H)K$',
          },
          {
            'name': 'Fallback',
            'type': 'select',
            'proxies': ['HK'],
          },
        ],
      },
    );
    expect(invalidFilterWithExplicit.nodes.single.selectGroups, ['Fallback']);
  });

  test(
      'selectGroups resolves empty-fallback when filtering empties group candidates and guards against non-empty or unresolved groups',
      () async {
    final fallbackMatched = buildProfileCatalog(
      profileId: 'p',
      fingerprint: 'f',
      raw: {
        'proxies': [
          {
            'name': 'HK',
            'type': 'ss',
            'server': '1.1.1.1',
            'port': 443,
            'cipher': 'aes-128-gcm',
            'password': 'secret',
          },
        ],
        'proxy-groups': [
          {
            'name': 'Primary',
            'type': 'select',
            'include-all-proxies': true,
            'filter': r'^JP$',
            'empty-fallback': 'HK',
          },
          {
            'name': 'TypeFiltered',
            'type': 'select',
            'include-all': true,
            'exclude-type': 'ss',
            'empty-fallback': 'HK',
          },
        ],
      },
    );
    expect(fallbackMatched.nodes.single.selectGroups, [
      'Primary',
      'TypeFiltered',
    ]);

    final nonEmptyOrUnresolved = buildProfileCatalog(
      profileId: 'p-guard',
      fingerprint: 'f',
      raw: {
        'proxies': [
          {
            'name': 'HK',
            'type': 'ss',
            'server': '1.1.1.1',
            'port': 443,
            'cipher': 'aes-128-gcm',
            'password': 'secret',
          },
          {
            'name': 'JP',
            'type': 'ss',
            'server': '1.1.1.2',
            'port': 443,
            'cipher': 'aes-128-gcm',
            'password': 'secret',
          },
        ],
        'proxy-providers': {
          'remote': {'type': 'http', 'path': './remote.yaml'},
        },
        'proxy-groups': [
          {
            'name': 'HasMatchingMember',
            'type': 'select',
            'include-all-proxies': true,
            'filter': r'^JP$',
            'empty-fallback': 'HK',
          },
          {
            'name': 'HasExplicitDirect',
            'type': 'select',
            'proxies': ['DIRECT'],
            'include-all-proxies': true,
            'filter': r'^US$',
            'empty-fallback': 'HK',
          },
          {
            'name': 'UnresolvedProviderGroup',
            'type': 'select',
            'include-all': true,
            'filter': r'^US$',
            'empty-fallback': 'HK',
          },
        ],
      },
    );
    final hkGuard =
        nonEmptyOrUnresolved.nodes.firstWhere((node) => node.name == 'HK');
    final jpGuard =
        nonEmptyOrUnresolved.nodes.firstWhere((node) => node.name == 'JP');
    expect(hkGuard.selectGroups, isEmpty);
    expect(jpGuard.selectGroups, ['HasMatchingMember']);

    final service = NodeCatalogService(
      readProfileConfig: (_) async => {
        'proxies': [
          {
            'name': 'HK',
            'type': 'ss',
            'server': '1.1.1.1',
            'port': 443,
            'cipher': 'aes-128-gcm',
            'password': 'secret',
          },
        ],
        'proxy-providers': {
          'remote': {'type': 'inline'},
        },
        'proxy-groups': [
          {
            'name': 'ProviderBackedPrimary',
            'type': 'select',
            'include-all': true,
            'filter': r'^US$',
            'empty-fallback': 'HK',
          },
        ],
      },
      evaluate: (raw) async => raw,
      fileMetadata: (_) async => metadata,
      scriptFingerprint: () => script,
      providerResolver: CatalogProviderResolver(
        homeDirectory: () async => '/tmp',
        httpCachePath: (id, url) async => '/tmp/unused',
        parse: (_, __) async => jsonEncode({
          'rejected': 0,
          'proxies': [
            {
              'name': 'SG',
              'type': 'ss',
              'server': '1.1.1.3',
              'port': 443,
              'cipher': 'aes-128-gcm',
              'password': 'secret',
            },
          ],
        }),
      ),
    );
    final plan = await service.resolveForTestAll(
      _profile('p-resolved'),
      isCurrent: () => true,
    );
    addTearDown(plan.dispose);
    final hkResolved = plan.nodes.firstWhere((node) => node.name == 'HK');
    expect(hkResolved.selectGroups, ['ProviderBackedPrimary']);

    final matchingCustomDirect = buildProfileCatalog(
      profileId: 'p-custom-direct-match',
      fingerprint: 'f',
      raw: {
        'proxies': [
          {
            'name': 'HK',
            'type': 'socks5',
            'server': 'fixture.invalid',
            'port': 443,
          },
          {'name': 'Bypass', 'type': 'direct'},
        ],
        'proxy-groups': [
          {
            'name': 'Primary',
            'type': 'select',
            'include-all-proxies': true,
            'filter': r'^Bypass$',
            'empty-fallback': 'HK',
          },
        ],
      },
    );
    expect(matchingCustomDirect.nodes.single.selectGroups, isEmpty);

    final excludedCustomDirect = buildProfileCatalog(
      profileId: 'p-custom-direct-excluded',
      fingerprint: 'f',
      raw: {
        'proxies': [
          {
            'name': 'HK',
            'type': 'socks5',
            'server': 'fixture.invalid',
            'port': 443,
          },
          {'name': 'Bypass', 'type': 'direct'},
        ],
        'proxy-groups': [
          {
            'name': 'Primary',
            'type': 'select',
            'proxies': ['Bypass'],
            'exclude-filter': r'^Bypass$',
            'empty-fallback': 'HK',
          },
        ],
      },
    );
    expect(excludedCustomDirect.nodes.single.selectGroups, ['Primary']);
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flclashx/common/constant.dart';
import 'package:flclashx/common/file_logger.dart';
import 'package:flclashx/common/rule_compiler.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

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

class _RoutingTestState extends GlobalState {
  _RoutingTestState(this.configsById) : super.forTesting();

  final Map<String, Map<String, dynamic>> configsById;

  @override
  Future<Map<String, dynamic>> getProfileConfig(String profileId) async {
    final source = configsById[profileId]!;
    return Map<String, dynamic>.fromEntries(
      source.entries.map((entry) {
        final v = entry.value;
        if (v is List) {
          return MapEntry(entry.key, List<dynamic>.from(v));
        }
        if (v is Map) {
          return MapEntry(entry.key, Map<String, dynamic>.from(v));
        }
        return MapEntry(entry.key, v);
      }),
    );
  }

  @override
  Future<Map<String, dynamic>> handleEvaluate(Map<String, dynamic> raw) async =>
      raw;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  final originalPaths = PathProviderPlatform.instance;

  setUpAll(() async {
    tempRoot = await Directory.systemTemp.createTemp('fcx-global-override-');
    PathProviderPlatform.instance = _TestPaths(tempRoot.path);
    await File(p.join(tempRoot.path, geoSiteFileName))
        .writeAsBytes(const [1, 2, 3, 4]);
    await File(p.join(tempRoot.path, mmdbFileName))
        .writeAsBytes(const [1, 2, 3, 4]);
  });

  tearDownAll(() async {
    await fileLogger.dispose();
    PathProviderPlatform.instance = originalPaths;
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('Config.compatibleFromJson defaults localSplitMode=auto and globalOverrideData.enable=true', () {
    final migrated = Config.compatibleFromJson(<String, Object?>{
      'themeProps': defaultThemeProps.toJson(),
    });

    expect(migrated.networkProps.localSplitMode, LocalSplitMode.auto);
    expect(migrated.globalOverrideData.enable, isTrue);
    expect(migrated.globalOverrideData.runningRule, isEmpty);

    final customized = migrated.copyWith(
      networkProps: migrated.networkProps.copyWith(
        localSplitMode: LocalSplitMode.always,
      ),
      globalOverrideData: OverrideData(
        enable: true,
        rule: OverrideRule(
          addedRules: [
            Rule.value('DOMAIN-SUFFIX,claude.ai,$semanticDefaultProxyTarget'),
          ],
        ),
      ),
    );
    final roundTripped = Config.compatibleFromJson(
      jsonDecode(jsonEncode(customized.toJson())) as Map<String, Object?>,
    );
    expect(roundTripped.networkProps.localSplitMode, LocalSplitMode.always);
    expect(
      roundTripped.globalOverrideData.runningRule,
      ['DOMAIN-SUFFIX,claude.ai,$semanticDefaultProxyTarget'],
    );
  });

  test('patchRawConfig applies global override and bare-profile local split across profile switches without re-editing', () async {
    const profileA = Profile(
      id: 'bare-a',
      label: 'BareA',
      autoUpdateDuration: Duration.zero,
    );
    const profileB = Profile(
      id: 'bare-b',
      label: 'BareB',
      autoUpdateDuration: Duration.zero,
    );
    const profileC = Profile(
      id: 'full-c',
      label: 'FullC',
      autoUpdateDuration: Duration.zero,
    );

    final config = Config(
      themeProps: defaultThemeProps,
      profiles: const [profileA, profileB, profileC],
      currentProfileId: 'bare-a',
      globalOverrideData: OverrideData(
        enable: true,
        rule: OverrideRule(
          addedRules: [
            Rule.value('DOMAIN-SUFFIX,claude.ai,$semanticDefaultProxyTarget'),
            Rule.value('DOMAIN-SUFFIX,corp.cn,DIRECT'),
          ],
        ),
      ),
    );

    final state = _RoutingTestState({
      'bare-a': {
        'proxies': [
          {'name': 'n1', 'type': 'ss', 'server': 'a.example', 'port': 443},
        ],
        'proxy-groups': [
          {
            'name': 'PROXY',
            'type': 'select',
            'proxies': ['n1', 'DIRECT'],
          },
        ],
        'rules': ['MATCH,PROXY'],
      },
      'bare-b': {
        'proxies': [
          {'name': 'n2', 'type': 'vless', 'server': 'b.example', 'port': 443},
        ],
        'proxy-groups': [
          {
            'name': '🚀 节点选择',
            'type': 'select',
            'proxies': ['n2', 'DIRECT'],
          },
        ],
        'rules': ['MATCH,🚀 节点选择'],
      },
      'full-c': {
        'proxies': [
          {'name': 'n3', 'type': 'trojan', 'server': 'c.example', 'port': 443},
        ],
        'proxy-groups': [
          {
            'name': '🚀 节点选择',
            'type': 'select',
            'proxies': ['n3', 'DIRECT'],
          },
          {
            'name': 'Streaming',
            'type': 'select',
            'proxies': ['n3'],
          },
        ],
        'rules': [
          'DOMAIN-SUFFIX,netflix.com,Streaming',
          'GEOSITE,cn,DIRECT',
          'MATCH,🚀 节点选择',
        ],
      },
    })
      ..config = config;
    globalState.config = config;

    final patchedA = await state.patchRawConfig(
      patchConfig: const ClashConfig(),
      profile: profileA,
    );
    final rulesA = (patchedA['rule'] as List).cast<String>();
    expect(rulesA, contains('DOMAIN-SUFFIX,claude.ai,PROXY'));
    expect(rulesA, contains('DOMAIN-SUFFIX,corp.cn,DIRECT'));
    expect(rulesA, contains('GEOSITE,cn,DIRECT'));
    expect(rulesA, contains('GEOSITE,geolocation-!cn,PROXY'));
    expect(rulesA, contains('GEOIP,CN,DIRECT'));
    expect(rulesA.last, 'MATCH,PROXY');

    // Switch directly to profileB without modifying globalOverrideData at all!
    final patchedB = await state.patchRawConfig(
      patchConfig: const ClashConfig(),
      profile: profileB,
    );
    final rulesB = (patchedB['rule'] as List).cast<String>();
    expect(rulesB, contains('DOMAIN-SUFFIX,claude.ai,🚀 节点选择'));
    expect(rulesB, contains('DOMAIN-SUFFIX,corp.cn,DIRECT'));
    expect(rulesB, contains('GEOSITE,cn,DIRECT'));
    expect(rulesB, contains('GEOSITE,geolocation-!cn,🚀 节点选择'));
    expect(rulesB, contains('GEOIP,CN,DIRECT'));
    expect(rulesB.last, 'MATCH,🚀 节点选择');

    // Switch to full profileC: global override applies, provider rules stay intact, no redundant geolocation-!cn injected.
    final patchedC = await state.patchRawConfig(
      patchConfig: const ClashConfig(),
      profile: profileC,
    );
    final rulesC = (patchedC['rule'] as List).cast<String>();
    expect(rulesC.first, 'DOMAIN-SUFFIX,claude.ai,🚀 节点选择');
    expect(rulesC[1], 'DOMAIN-SUFFIX,corp.cn,DIRECT');
    expect(rulesC, contains('DOMAIN-SUFFIX,netflix.com,Streaming'));
    expect(
      rulesC.any((r) => r.startsWith('GEOSITE,geolocation-!cn,')),
      isFalse,
    );
    expect(rulesC.last, 'MATCH,🚀 节点选择');
  });
}

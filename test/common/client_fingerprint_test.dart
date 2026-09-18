import 'package:flclashx/common/client_fingerprint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('migrates the removed global fingerprint to TLS proxies', () {
    final config = <String, dynamic>{
      'global-client-fingerprint': 'chrome',
      'proxies': [
        {'name': 'vless-node', 'type': 'vless'},
        {'name': 'http-node', 'type': 'http'},
        {'name': 'custom-tls', 'type': 'custom', 'tls': true},
      ],
    };

    expect(migrateDeprecatedGlobalClientFingerprint(config), isTrue);
    expect(config.containsKey('global-client-fingerprint'), isFalse);
    expect(config['proxies'][0]['client-fingerprint'], 'chrome');
    expect(config['proxies'][1].containsKey('client-fingerprint'), isFalse);
    expect(config['proxies'][2]['client-fingerprint'], 'chrome');
  });

  test('preserves explicit proxy fingerprints and leaves unsupported config', () {
    final config = <String, dynamic>{
      'global-client-fingerprint': 'chrome',
      'proxies': [
        {
          'name': 'vless-node',
          'type': 'vless',
          'client-fingerprint': 'firefox',
        },
      ],
    };

    expect(migrateDeprecatedGlobalClientFingerprint(config), isFalse);
    expect(config.containsKey('global-client-fingerprint'), isFalse);
    expect(config['proxies'][0]['client-fingerprint'], 'firefox');
  });
}

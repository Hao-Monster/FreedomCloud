import 'package:flclashx/common/per_app_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('application policies compile ahead-of-profile Mihomo rules', () {
    final policies = [
      const PerAppPolicy(
        path: r'C:\Apps\browser.exe',
        name: 'browser.exe',
        policy: ApplicationRoutingPolicy.proxy,
      ),
      const PerAppPolicy(
        path: r'C:\Apps\updater.exe',
        name: 'updater.exe',
        policy: ApplicationRoutingPolicy.direct,
      ),
      const PerAppPolicy(
        path: r'C:\Apps\blocked.exe',
        name: 'blocked.exe',
        policy: ApplicationRoutingPolicy.block,
      ),
    ];

    expect(
      compilePerAppPolicyRules(policies),
      [
        r'PROCESS-PATH,C:\Apps\browser.exe,GLOBAL',
        r'PROCESS-PATH,C:\Apps\updater.exe,DIRECT',
        r'PROCESS-PATH,C:\Apps\blocked.exe,REJECT',
      ],
    );
    expect(
      mergePerAppPolicyRules(policies, ['DOMAIN,example.com,DIRECT']),
      [
        r'PROCESS-PATH,C:\Apps\browser.exe,GLOBAL',
        r'PROCESS-PATH,C:\Apps\updater.exe,DIRECT',
        r'PROCESS-PATH,C:\Apps\blocked.exe,REJECT',
        'DOMAIN,example.com,DIRECT',
      ],
    );
  });

  test('inherit emits no rule and invalid rule-breaking paths are rejected',
      () {
    expect(
      compilePerAppPolicyRules([
        const PerAppPolicy(
          path: r'C:\Apps\browser.exe',
          name: 'browser.exe',
          policy: ApplicationRoutingPolicy.inherit,
        ),
      ]),
      isEmpty,
    );
    expect(
      () => PerAppPolicy.validatePath(r'C:\Apps\bad,rule.exe'),
      throwsArgumentError,
    );
    expect(
      () => PerAppPolicy.validatePath('C:\\Apps\\bad\nrule.exe'),
      throwsArgumentError,
    );
  });

  test('JSON decoding ignores malformed entries and enforces the bound', () {
    final decoded = decodePerAppPolicies({
      'version': 1,
      'entries': [
        for (var index = 0; index < 140; index++)
          {
            'path': 'C:\\Apps\\app-$index.exe',
            'name': 'app-$index.exe',
            'policy': 'direct',
          },
        {'path': 'bad,rule', 'name': 'bad', 'policy': 'block'},
        {'path': r'C:\Apps\unknown.exe', 'policy': 'unknown'},
      ],
    });

    expect(decoded, hasLength(maxPerAppPolicies));
    expect(decoded.first.name, 'app-12.exe');
    expect(decoded.last.name, 'app-139.exe');
  });
}

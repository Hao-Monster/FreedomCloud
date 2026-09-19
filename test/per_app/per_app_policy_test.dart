import 'package:flclashx/common/per_app_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('strict policy blocks on capture or forwarding failure', () {
    final unavailable = evaluateStrictPolicy(
      policy: ApplicationRoutingPolicy.proxy,
      state: StrictPolicyState.blocking,
      captureOwned: false,
      forwardingHealthy: false,
      failureReason: StrictPolicyFailureReason.proxyRouteUnavailable,
    );
    expect(unavailable.route, StrictPolicyRoute.block);
    expect(unavailable.failureReason,
        StrictPolicyFailureReason.proxyRouteUnavailable);
    expect(unavailable.isBlocking, isTrue);

    final direct = evaluateStrictPolicy(
      policy: ApplicationRoutingPolicy.direct,
      state: StrictPolicyState.armed,
      captureOwned: true,
      forwardingHealthy: true,
    );
    expect(direct.route, StrictPolicyRoute.direct);
    expect(direct.failureReason, isNull);
  });

  test('strict policy never treats an explicit proxy failure as direct', () {
    final decision = evaluateStrictPolicy(
      policy: ApplicationRoutingPolicy.proxy,
      state: StrictPolicyState.armed,
      captureOwned: true,
      forwardingHealthy: false,
      failureReason: StrictPolicyFailureReason.coreUnavailable,
    );
    expect(decision.route, StrictPolicyRoute.block);
    expect(decision.route, isNot(StrictPolicyRoute.direct));
  });

  test('strict state transitions reject unsafe recovery shortcuts', () {
    expect(
      canTransitionStrictPolicyState(
        StrictPolicyState.blocking,
        StrictPolicyState.armed,
      ),
      isFalse,
    );
    expect(
      canTransitionStrictPolicyState(
        StrictPolicyState.blocking,
        StrictPolicyState.recovering,
      ),
      isTrue,
    );
    expect(
      canTransitionStrictPolicyState(
        StrictPolicyState.recovering,
        StrictPolicyState.armed,
      ),
      isTrue,
    );
  });

  test('strict failure codes are stable and transport-safe', () {
    expect(
      strictPolicyFailureCode(StrictPolicyFailureReason.brokerUnavailable),
      'broker_unavailable',
    );
    expect(
      strictPolicyFailureCode(StrictPolicyFailureReason.recoveryExhausted),
      'recovery_exhausted',
    );
  });

  test('application policies compile ahead-of-profile Mihomo rules', () {
    final policies = [
      const PerAppPolicy(
        path: r'C:\Apps\browser.exe',
        name: 'browser.exe',
        policy: ApplicationRoutingPolicy.proxy,
        targetGroup: 'Work',
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
      compilePerAppPolicyRules(
        policies,
        availableTargetGroups: const {'GLOBAL', 'Work'},
      ),
      [
        r'PROCESS-PATH,C:\Apps\browser.exe,Work',
        r'PROCESS-PATH,C:\Apps\updater.exe,DIRECT',
        r'PROCESS-PATH,C:\Apps\blocked.exe,REJECT',
      ],
    );
    expect(
      mergePerAppPolicyRules(
        policies,
        ['DOMAIN,example.com,DIRECT'],
        availableTargetGroups: const {'GLOBAL', 'Work'},
      ),
      [
        r'PROCESS-PATH,C:\Apps\browser.exe,Work',
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

  test('active application policies require process lookup', () {
    expect(
      perAppPoliciesRequireProcessLookup(const [
        PerAppPolicy(
          path: r'C:\Apps\edge.exe',
          name: 'edge.exe',
          policy: ApplicationRoutingPolicy.inherit,
        ),
      ]),
      isFalse,
    );
    expect(
      perAppPoliciesRequireProcessLookup(const [
        PerAppPolicy(
          path: r'C:\Apps\edge.exe',
          name: 'edge.exe',
          policy: ApplicationRoutingPolicy.proxy,
        ),
      ]),
      isTrue,
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

  test('version 1 proxy entries migrate to GLOBAL without changing behavior',
      () {
    final decoded = decodePerAppPolicies({
      'version': 1,
      'entries': [
        {
          'path': r'C:\Apps\legacy.exe',
          'name': 'legacy.exe',
          'policy': 'proxy',
        },
      ],
    });

    expect(decoded.single.targetGroup, 'GLOBAL');
    expect(
      compilePerAppPolicyRules(
        decoded,
        availableTargetGroups: const {'GLOBAL'},
      ),
      [r'PROCESS-PATH,C:\Apps\legacy.exe,GLOBAL'],
    );
  });

  test('missing proxy target blocks safely instead of breaking Core startup',
      () {
    const policy = PerAppPolicy(
      path: r'C:\Apps\browser.exe',
      name: 'browser.exe',
      policy: ApplicationRoutingPolicy.proxy,
      targetGroup: 'Missing',
    );

    final unavailable = <String>[];
    expect(
      compilePerAppPolicyRules(
        [policy],
        availableTargetGroups: const {'GLOBAL', 'Work'},
        onUnavailableTarget: unavailable.add,
      ),
      [r'PROCESS-PATH,C:\Apps\browser.exe,REJECT'],
    );
    expect(unavailable, ['Missing']);
    expect(
      () => PerAppPolicy.validateTargetGroup('bad,group'),
      throwsArgumentError,
    );
    expect(
      () => PerAppPolicy.validateTargetGroup('bad\ngroup'),
      throwsArgumentError,
    );
  });

  test('target group choices preserve profile order and reject rule injection',
      () {
    expect(
      availablePerAppTargetGroups(
        const ['Work', 'GLOBAL', 'Work', 'bad,group', 'Streaming'],
      ),
      const ['GLOBAL', 'Work', 'Streaming'],
    );
  });

  test('persisted target remains visible when its provider group disappears',
      () {
    final options = perAppTargetGroupOptions(
      const ['Work', 'Streaming'],
      selectedGroup: 'OldProvider',
    );

    expect(options.first.value, 'OldProvider');
    expect(options.first.available, isFalse);
    expect(
      options.skip(1).map((option) => option.value).toList(),
      ['GLOBAL', 'Work', 'Streaming'],
    );
  });

  test('JSON decoding collapses duplicate canonical paths deterministically',
      () {
    final decoded = decodePerAppPolicies({
      'version': 1,
      'entries': [
        {
          'path': r'C:\Apps\browser.exe',
          'name': 'old label',
          'policy': 'direct',
        },
        {
          'path': r'C:\Apps\browser.exe',
          'name': 'new label',
          'policy': 'proxy',
        },
      ],
    });

    expect(decoded, hasLength(1));
    expect(decoded.single.name, 'new label');
    expect(decoded.single.policy, ApplicationRoutingPolicy.proxy);
  });

  test('blank application names fall back to the executable name', () {
    final decoded = decodePerAppPolicies({
      'version': 1,
      'entries': [
        {
          'path': r'C:\Apps\browser.exe',
          'name': '  ',
          'policy': 'direct',
        },
      ],
    });

    expect(decoded.single.name, 'browser.exe');
  });

  test('application policy filtering matches name, path and policy', () {
    const policies = [
      PerAppPolicy(
        path: r'C:\Apps\Microsoft\msedge.exe',
        name: 'msedge.exe',
        policy: ApplicationRoutingPolicy.proxy,
      ),
      PerAppPolicy(
        path: r'C:\Tools\sync.exe',
        name: 'sync.exe',
        policy: ApplicationRoutingPolicy.direct,
      ),
      PerAppPolicy(
        path: r'C:\Games\blocked.exe',
        name: 'blocked.exe',
        policy: ApplicationRoutingPolicy.block,
      ),
    ];

    expect(filterPerAppPolicies(policies, 'EDGE').single.name, 'msedge.exe');
    expect(filterPerAppPolicies(policies, 'tools').single.name, 'sync.exe');
    expect(filterPerAppPolicies(policies, 'block').single.name, 'blocked.exe');
    expect(filterPerAppPolicies(policies, 'missing'), isEmpty);
    expect(filterPerAppPolicies(policies, '  '), hasLength(3));
  });
}

import 'package:flclashx/clash/agent_protocol.dart';
import 'package:flclashx/common/per_app_policy.dart';
import 'package:flclashx/common/strict_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const identity = StrictIdentityResolution(
    canonicalPath: r'C:\Apps\edge.exe',
    wfpAppIdSha256:
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    publisherCertificateSha256:
        'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
  );

  test('identity id is stable and UUID-shaped', () {
    expect(identity.identityId, '01234567-89ab-cdef-0123-456789abcdef');
  });

  test('strict bundle serializes Helper evidence for proxy entry', () {
    const entry = PerAppPolicy(
      path: r'C:\Apps\edge.exe',
      name: 'edge.exe',
      policy: ApplicationRoutingPolicy.proxy,
      targetGroup: 'GLOBAL',
    );
    final bundle = buildStrictPolicyBundle(
      entries: const [entry],
      identities: const {r'c:\apps\edge.exe': identity},
      revision: 1,
    );
    expect(bundle['protocol'], 2);
    final payload = (bundle['entries']! as List).single as Map;
    expect((payload['identity'] as Map)['wfpAppIdSha256'],
        identity.wfpAppIdSha256);
    expect(payload['action'], 'proxy');
    expect(payload['targetGroup'], 'GLOBAL');
  });

  test('direct policy is rejected instead of being treated as proxy', () {
    const entry = PerAppPolicy(
      path: r'C:\Apps\edge.exe',
      name: 'edge.exe',
      policy: ApplicationRoutingPolicy.direct,
    );
    expect(
      () => buildStrictPolicyBundle(
        entries: const [entry],
        identities: const {r'c:\apps\edge.exe': identity},
        revision: 1,
      ),
      throwsStateError,
    );
  });
}


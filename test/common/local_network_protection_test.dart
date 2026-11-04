import 'package:flclashx/common/local_network_protection.dart';
import 'package:flclashx/common/per_app_policy.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mergeEssentialFakeIpFilter', () {
    test('preserves custom entries while adding Windows NCSI and LAN safeguards',
        () {
      final merged = mergeEssentialFakeIpFilter([
        '*.lan',
        'localhost.ptlogin2.qq.com',
        '+.corp.example',
      ]);

      expect(merged.take(3), [
        '*.lan',
        'localhost.ptlogin2.qq.com',
        '+.corp.example',
      ]);
      expect(merged, contains('+.msftconnecttest.com'));
      expect(merged, contains('+.msftncsi.com'));
      expect(merged, contains('*.local'));
      expect(merged, contains('*.localhost'));
      expect(
        merged.where((item) => item.toLowerCase() == '*.lan'),
        hasLength(1),
      );
    });
  });

  group('applyDesktopBypassPrivateRules', () {
    test('inserts private and Tailscale DIRECT rules before bare MATCH,PROXY on desktop',
        () {
      final compiled = applyDesktopBypassPrivateRules(
        const ['MATCH,PROXY'],
        isDesktop: true,
        routeMode: RouteMode.bypassPrivate,
      );

      expect(compiled.last, 'MATCH,PROXY');
      expect(compiled, contains('IP-CIDR,192.168.0.0/16,DIRECT,no-resolve'));
      expect(compiled, contains('IP-CIDR,100.64.0.0/10,DIRECT,no-resolve'));
      expect(compiled, contains('IP-CIDR,127.0.0.0/8,DIRECT,no-resolve'));
      expect(
        compiled.any((r) => r.toString().contains('198.18.')),
        isFalse,
        reason: 'Fake-IP range 198.18.0.0/16 must remain routed into Clash',
      );
    });

    test('preserves precedence of explicit corporate IP-CIDR and per-app BLOCK policies',
        () {
      final withBypass = applyDesktopBypassPrivateRules(
        const [
          'IP-CIDR,10.8.0.0/16,CorpVPN,no-resolve',
          'MATCH,PROXY',
        ],
        isDesktop: true,
        routeMode: RouteMode.bypassPrivate,
      );
      final finalRules = mergePerAppPolicyRules(
        const [
          PerAppPolicy(
            path: r'C:\Apps\Restricted.exe',
            name: 'Restricted.exe',
            policy: ApplicationRoutingPolicy.block,
          ),
        ],
        withBypass,
      );

      expect(finalRules.first, r'PROCESS-PATH,C:\Apps\Restricted.exe,REJECT');
      expect(finalRules[1], 'IP-CIDR,10.8.0.0/16,CorpVPN,no-resolve');
      expect(
        finalRules.indexOf('IP-CIDR,10.0.0.0/8,DIRECT,no-resolve'),
        greaterThan(1),
      );
      expect(finalRules.last, 'MATCH,PROXY');
    });

    test('leaves rules untouched when RouteMode.config is selected or on mobile',
        () {
      const original = ['MATCH,PROXY'];
      expect(
        applyDesktopBypassPrivateRules(
          original,
          isDesktop: true,
          routeMode: RouteMode.config,
        ),
        original,
      );
      expect(
        applyDesktopBypassPrivateRules(
          original,
          isDesktop: false,
          routeMode: RouteMode.bypassPrivate,
        ),
        original,
      );
    });
  });
}

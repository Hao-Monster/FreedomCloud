import 'dart:convert';
import 'dart:io';

import 'package:flclashx/controller.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

class _DnsTestState extends GlobalState {
  _DnsTestState(this.configsById) : super.forTesting();

  final Map<String, Map<String, dynamic>> configsById;

  @override
  Future<Map<String, dynamic>> getProfileConfig(String profileId) async {
    final source = configsById[profileId]!;
    return jsonDecode(jsonEncode(source)) as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> handleEvaluate(Map<String, dynamic> raw) async =>
      raw;
}

class _RecordingStartupController extends AppController {
  _RecordingStartupController(super.context, super.ref);

  final List<String> updatedProfileIds = <String>[];
  int checkUpdateCalls = 0;

  @override
  Future<void> updateProfile(
    Profile profile, {
    bool isManual = false,
  }) async {
    updatedProfileIds.add(profile.id);
  }

  @override
  Future<void> autoCheckUpdate() async {
    checkUpdateCalls++;
  }
}

void main() {
  group('Item 1a: Startup +4s due-only subscription refresh', () {
    test('isProfileAutoUpdateDue respects autoUpdateDuration, file type, and flags', () {
      final now = DateTime.utc(2026, 11, 7, 16, 0, 0);

      final freshUrlProfile = Profile(
        id: 'fresh',
        url: 'https://sub.example.com/fresh',
        autoUpdate: true,
        autoUpdateDuration: const Duration(hours: 24),
        lastUpdateDate: now.subtract(const Duration(minutes: 10)),
      );
      expect(isProfileAutoUpdateDue(freshUrlProfile, now: now), isFalse);

      final exactBoundaryProfile = freshUrlProfile.copyWith(
        lastUpdateDate: now.subtract(const Duration(hours: 24)),
      );
      expect(isProfileAutoUpdateDue(exactBoundaryProfile, now: now), isTrue);

      const neverUpdatedProfile = Profile(
        id: 'never',
        url: 'https://sub.example.com/never',
        autoUpdate: true,
        autoUpdateDuration: Duration(hours: 24),
      );
      expect(isProfileAutoUpdateDue(neverUpdatedProfile, now: now), isTrue);

      final disabledAutoUpdate = neverUpdatedProfile.copyWith(autoUpdate: false);
      expect(isProfileAutoUpdateDue(disabledAutoUpdate, now: now), isFalse);

      final fileProfile = neverUpdatedProfile.copyWith(url: '');
      expect(isProfileAutoUpdateDue(fileProfile, now: now), isFalse);

      final inFlightProfile = neverUpdatedProfile.copyWith(isUpdating: true);
      expect(isProfileAutoUpdateDue(inFlightProfile, now: now), isFalse);
    });

    testWidgets(
      'runDeferredStartupChecks skips non-due current subscription and refreshes due current profile first',
      (tester) async {
        final now = DateTime.now();
        final freshCurrent = Profile(
          id: 'current-fresh',
          label: 'Current Fresh',
          url: 'https://sub.example.com/current',
          autoUpdate: true,
          autoUpdateDuration: const Duration(hours: 24),
          lastUpdateDate: now.subtract(const Duration(minutes: 5)),
        );
        final expiredSecondary = Profile(
          id: 'secondary-due',
          label: 'Secondary Due',
          url: 'https://sub.example.com/secondary',
          autoUpdate: true,
          autoUpdateDuration: const Duration(hours: 6),
          lastUpdateDate: now.subtract(const Duration(hours: 7)),
        );

        globalState.config = Config(
          themeProps: defaultThemeProps,
          profiles: [expiredSecondary, freshCurrent],
          currentProfileId: freshCurrent.id,
        );

        _RecordingStartupController? controller;
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Consumer(
                builder: (context, ref, _) {
                  controller ??= _RecordingStartupController(context, ref);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );

        await controller!.runDeferredStartupChecks();
        expect(
          controller!.updatedProfileIds,
          equals(['secondary-due']),
          reason: 'Not-yet-due current subscription must not be force-fetched on startup',
        );
        expect(controller!.checkUpdateCalls, 1);

        // Now mark current profile as expired as well and verify current profile runs first.
        controller!.updatedProfileIds.clear();
        final expiredCurrent = freshCurrent.copyWith(
          lastUpdateDate: DateTime.now().subtract(const Duration(hours: 25)),
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(SizedBox)),
        );
        container.read(profilesProvider.notifier).value = [
          expiredSecondary,
          expiredCurrent,
        ];

        await controller!.runDeferredStartupChecks();
        expect(
          controller!.updatedProfileIds,
          equals(['current-fresh', 'secondary-due']),
        );
      },
    );
  });

  group('Item 1b: Default Dns.respectRules and legacy untouched Dns migration', () {
    test('defaultDns and desktopDefaultClashConfig enable respectRules with non-empty proxyServerNameserver', () {
      expect(const Dns().respectRules, isTrue);
      expect(defaultDns.respectRules, isTrue);
      expect(desktopDefaultClashConfig().dns.respectRules, isTrue);
      expect(defaultDns.proxyServerNameserver, isNotEmpty);
      expect(
        Dns.fromJson(<String, Object?>{}).respectRules,
        isTrue,
      );
    });

    test('Config.compatibleFromJson upgrades untouched legacy default Dns once while preserving custom Dns', () {
      final legacyUntouchedDns = jsonDecode(
        jsonEncode(const Dns(respectRules: false)),
      ) as Map<String, Object?>;
      final defaultThemeJson = jsonDecode(
        jsonEncode(defaultThemeProps),
      ) as Map<String, Object?>;
      final migrated = Config.compatibleFromJson(<String, Object?>{
        'themeProps': defaultThemeJson,
        'appSetting': <String, Object?>{
          'dashboardDefaultV2Migrated': true,
          'tunDesktopStackGvisorRestored': true,
        },
        'patchClashConfig': <String, Object?>{
          'dns': legacyUntouchedDns,
        },
      }, isDesktop: true);

      expect(migrated.patchClashConfig.dns.respectRules, isTrue);
      expect(migrated.appSetting.dnsRespectRulesDefaultMigrated, isTrue);

      // Subsequent save where user explicitly turned off respect-rules AFTER migration must be respected.
      final explicitUserDisableAfterMigration = Config.compatibleFromJson(
        <String, Object?>{
          'themeProps': defaultThemeJson,
          'appSetting': <String, Object?>{
            'dashboardDefaultV2Migrated': true,
            'tunDesktopStackGvisorRestored': true,
            'dnsRespectRulesDefaultMigrated': true,
          },
          'patchClashConfig': <String, Object?>{
            'dns': legacyUntouchedDns,
          },
        },
        isDesktop: true,
      );
      expect(
        explicitUserDisableAfterMigration.patchClashConfig.dns.respectRules,
        isFalse,
      );

      // Legacy config where user customized fallback or nameserver is NOT overwritten.
      final customizedLegacyDns = jsonDecode(
        jsonEncode(
          const Dns(
            respectRules: false,
            fallback: <String>['https://dns.google/dns-query'],
          ),
        ),
      ) as Map<String, Object?>;
      final preservedCustom = Config.compatibleFromJson(<String, Object?>{
        'themeProps': defaultThemeJson,
        'appSetting': <String, Object?>{
          'dashboardDefaultV2Migrated': true,
          'tunDesktopStackGvisorRestored': true,
        },
        'patchClashConfig': <String, Object?>{
          'dns': customizedLegacyDns,
        },
      }, isDesktop: true);
      expect(preservedCustom.patchClashConfig.dns.respectRules, isFalse);
      expect(
        preservedCustom.patchClashConfig.dns.fallback,
        equals(<String>['https://dns.google/dns-query']),
      );
      expect(preservedCustom.appSetting.dnsRespectRulesDefaultMigrated, isTrue);
    });

    test('patchRawConfig guarantees non-empty proxy-server-nameserver when respect-rules is enabled', () async {
      final tempDir = await Directory.systemTemp.createTemp('fcx_dns_test_');
      final originalPaths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _TestPaths(tempDir.path);
      addTearDown(() async {
        PathProviderPlatform.instance = originalPaths;
        await tempDir.delete(recursive: true);
      });

      const profile = Profile(
        id: 'p1',
        url: 'https://sub.example.com/p1',
        autoUpdateDuration: Duration(hours: 24),
      );
      final state = _DnsTestState(<String, Map<String, dynamic>>{
        'p1': <String, dynamic>{
          'proxies': <Map<String, dynamic>>[],
          'proxy-groups': <Map<String, dynamic>>[],
          'rules': <String>['MATCH,DIRECT'],
        },
      })
        ..config = Config(
          themeProps: defaultThemeProps,
          overrideDns: true,
          patchClashConfig: defaultClashConfig.copyWith(
            dns: defaultDns.copyWith(
              respectRules: true,
              proxyServerNameserver: const <String>[],
            ),
          ),
        );
      globalState.config = state.config;

      final patched = await state.patchRawConfig(
        patchConfig: state.config.patchClashConfig,
        profile: profile,
      );
      final rawDns = patched['dns'] as Map<String, dynamic>;
      expect(rawDns['respect-rules'], isTrue);
      expect(
        rawDns['proxy-server-nameserver'],
        equals(defaultDns.proxyServerNameserver),
      );
    });
  });
}

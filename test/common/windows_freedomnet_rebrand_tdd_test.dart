import 'dart:io';

import 'package:flclashx/clash/agent_protocol.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/windows_service_command.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/views/about.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../setup.dart' as setup;

Set<String> _parseIslKeys(String content) {
  final keys = <String>{};
  var section = '';
  for (final rawLine in content.split(RegExp(r'\r?\n'))) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith(';')) continue;
    if (line.startsWith('[') && line.endsWith(']')) {
      section = line.substring(1, line.length - 1).trim();
      continue;
    }
    if (section != 'Messages' && section != 'CustomMessages') continue;
    final eqIndex = line.indexOf('=');
    if (eqIndex > 0) {
      keys.add('$section:${line.substring(0, eqIndex).trim()}');
    }
  }
  return keys;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Inno Setup Simplified Chinese + English & FreedomNet isolation', () {
    test(
      'ChineseSimplified.isl uses UTF-8 BOM, LCID 0804, and covers every key in Russian.isl',
      () {
        final zhFile = File('windows/packaging/exe/ChineseSimplified.isl');
        final ruFile = File('windows/packaging/exe/Russian.isl');
        expect(zhFile.existsSync(), isTrue);
        expect(ruFile.existsSync(), isTrue);

        final bytes = zhFile.readAsBytesSync();
        expect(bytes.length, greaterThan(3));
        expect(bytes.sublist(0, 3), equals([0xEF, 0xBB, 0xBF]));

        final zhContent = zhFile.readAsStringSync();
        expect(zhContent, contains('LanguageName=<7B80><4F53><4E2D><6587>'));
        expect(zhContent, contains(r'LanguageID=$0804'));
        expect(zhContent, contains('LanguageCodePage=936'));

        final zhKeys = _parseIslKeys(zhContent);
        final ruKeys = _parseIslKeys(ruFile.readAsStringSync());
        final missingKeys = ruKeys.difference(zhKeys);
        expect(missingKeys, isEmpty);
      },
    );

    test(
      'make_config.yaml declares zh default + en, no ru, and FreedomNet identity',
      () {
        final yaml =
            File('windows/packaging/exe/make_config.yaml').readAsStringSync();
        expect(
            yaml, contains('app_id: 8F4E9C2A-6D1B-4A73-9E52-3C8B1D7F4A90'));
        expect(yaml, contains('app_name: FreedomNet'));
        expect(yaml, contains('publisher: FreedomNet'));
        expect(yaml, contains('publisher_url: https://fast.hjy.ca:8443/'));
        expect(yaml, contains('display_name: 自由云 · FreedomNet'));
        expect(yaml, contains('executable_name: FreedomNet.exe'));
        expect(yaml, contains('lang: zh'));
        expect(yaml, contains('file: ChineseSimplified.isl'));
        expect(yaml, contains('lang: en'));
        expect(RegExp(r'lang:\s*ru\b').hasMatch(yaml), isFalse);
      },
    );

    test(
      'setup.Build.renderWindowsInnoSetupScript puts chineseSimplified first, removes Russian, and isolates all FreedomNet Windows paths',
      () {
        final template =
            File('windows/packaging/exe/inno_setup.iss').readAsStringSync();
        final rendered = setup.Build.renderWindowsInnoSetupScript(
          template: template,
          version: '0.4.2',
          archName: 'amd64',
          buildDir: r'E:\build\windows\x64\runner\Release',
          setupIconFile: r'E:\repo\windows\runner\resources\app_icon.ico',
          chineseIslPath:
              r'E:\repo\windows\packaging\exe\ChineseSimplified.isl',
          strict: false,
        );

        expect(rendered, contains('AppId={{8F4E9C2A-6D1B-4A73-9E52-3C8B1D7F4A90}'));
        expect(rendered, contains('AppName=自由云 · FreedomNet'));
        expect(rendered, contains('AppPublisher=FreedomNet'));
        expect(rendered, contains('AppPublisherURL=https://fast.hjy.ca:8443/'));
        expect(rendered, contains('AppSupportURL=https://fast.hjy.ca:8443/'));
        expect(rendered, contains('AppUpdatesURL=https://fast.hjy.ca:8443/'));
        expect(rendered, contains(r'DefaultDirName={autopf}\FreedomNet'));
        expect(
          rendered,
          contains('OutputBaseFilename=FreedomNet-windows-amd64-setup'),
        );
        expect(rendered, contains('ShowLanguageDialog=yes'));
        expect(RegExp(r'\{\{[A-Z_]+\}\}').hasMatch(rendered), isFalse);
        expect(rendered, isNot(contains('{%')));

        final zhIdx = rendered.indexOf('Name: "chineseSimplified"');
        final enIdx = rendered.indexOf('Name: "english"');
        expect(zhIdx, greaterThan(0));
        expect(enIdx, greaterThan(zhIdx));
        expect(rendered.toLowerCase(), isNot(contains('russian')));
        expect(RegExp(r'[\u0400-\u04FF]').hasMatch(rendered), isFalse);

        // Coexistence isolation: installer only stops/removes FreedomNet binaries/service.
        expect(rendered, contains("'FreedomNet.exe'"));
        expect(rendered, contains("'FreedomNetAgent.exe'"));
        expect(rendered, contains("'FreedomNetCore.exe'"));
        expect(rendered, contains("'FreedomNetHelperService.exe'"));
        expect(rendered, isNot(contains("'FlClashX.exe'")));
        expect(rendered, isNot(contains("'FlClashAgent.exe'")));
        expect(rendered, isNot(contains("'FlClashCore.exe'")));
        expect(rendered, isNot(contains("'FlClashHelperService.exe'")));
        expect(rendered, contains(r'{commonpf}\FreedomNet Service'));
        expect(rendered, contains('"FreedomNetHelperService"'));
        expect(rendered, contains(r'{userappdata}\FreedomNet\FreedomNet'));

        // Every CustomMessage(...) in [Code] must exist in both languages.
        final referencedMessages = RegExp(r"CustomMessage\('([^']+)'\)")
            .allMatches(rendered)
            .map((m) => m.group(1)!)
            .toSet();
        expect(referencedMessages, isNotEmpty);
        for (final key in referencedMessages) {
          expect(rendered, contains('chineseSimplified.$key='));
          expect(rendered, contains('english.$key='));
        }

        // Strict variant keeps kernel driver/broker names inside FreedomNet Service dir.
        final strictRendered = setup.Build.renderWindowsInnoSetupScript(
          template: template,
          version: '0.4.2',
          archName: 'amd64',
          buildDir: r'E:\build\windows\x64\runner\Release',
          setupIconFile: r'E:\repo\windows\runner\resources\app_icon.ico',
          chineseIslPath:
              r'E:\repo\windows\packaging\exe\ChineseSimplified.isl',
          strict: true,
        );
        expect(strictRendered, contains('FlClashStrictBroker'));
        expect(strictRendered, contains('FlClashStrictCallout'));
        expect(strictRendered, contains(r'{commonpf}\FreedomNet Service'));
        expect(strictRendered, contains(r'{commonappdata}\FreedomNet.StrictBroker'));
        expect(strictRendered, contains('FreedomNetAgent.exe'));
      },
    );
  });

  group('Windows runtime coexistence & non-Windows preservation', () {
    test('Windows constants, Tun normalization, virtual filter, and paths are isolated',
        () {
      expect(appName, equals('FreedomNet'));
      expect(brandNameZh, equals('自由云'));
      expect(brandNameEn, equals('FreedomNet'));
      expect(brandDisplayName, equals('自由云 · FreedomNet'));
      expect(officialWebsiteUrl, equals('https://fast.hjy.ca:8443/'));
      expect(appHelperService, equals('FreedomNetHelperService'));
      expect(helperPort, equals(47895));
      expect(windowsHelperServiceName, equals('FreedomNetHelperService'));
      expect(
        windowsHelperDefaultLogDirectory,
        equals(r'%ProgramData%\FreedomNet\logs'),
      );

      expect(const Tun().device, equals('FreedomNet'));
      expect(const Tun(device: 'FlClashX').effectiveDevice, equals('FreedomNet'));
      expect(const Tun(device: 'flclash').effectiveDevice, equals('FreedomNet'));
      expect(const Tun(device: '').effectiveDevice, equals('FreedomNet'));
      expect(const Tun(device: 'CustomTun').effectiveDevice, equals('CustomTun'));
      if (Platform.isWindows) {
        expect(
          const Tun(device: 'FlClashX')
              .getRealTun(RouteMode.config)
              .device,
          equals('FreedomNet'),
        );
        expect(agentEndpointFileName, equals('freedomnet-agent-v1.json'));
        expect(appPath.corePath, endsWith('FreedomNetCore.exe'));
        expect(appPath.agentPath, endsWith('FreedomNetAgent.exe'));
        expect(appPath.helperPath, endsWith('FreedomNetHelperService.exe'));
        expect(appPath.windowsServiceDirectory, endsWith('FreedomNet Service'));
        expect(
          appPath.windowsServiceCorePath,
          endsWith('FreedomNetCore.exe'),
        );
      }

      expect(isVirtualOrTunnelInterfaceName('FreedomNet'), isTrue);
      expect(isVirtualOrTunnelInterfaceName('FreedomNet Tunnel'), isTrue);

      // Non-Windows build targets remain untouched.
      expect(setup.Build.appNameFor(setup.Target.windows), equals('FreedomNet'));
      expect(setup.Build.appNameFor(setup.Target.macos), equals('FlClashX'));
      expect(setup.Build.appNameFor(setup.Target.linux), equals('FlClashX'));
      expect(setup.Build.coreNameFor(setup.Target.windows),
          equals('FreedomNetCore'));
      expect(setup.Build.coreNameFor(setup.Target.macos), equals('FlClashCore'));
      expect(setup.Build.agentNameFor(setup.Target.windows),
          equals('FreedomNetAgent'));
      expect(
          setup.Build.agentNameFor(setup.Target.linux), equals('FlClashAgent'));
    });

    test('Windows native Runner.rc, CMakeLists.txt, and URL scheme avoid FlClash collision while preserving User-Agent',
        () {
      final runnerRc = File('windows/runner/Runner.rc').readAsStringSync();
      expect(runnerRc, contains('VALUE "CompanyName", "FreedomNet"'));
      expect(runnerRc, contains('VALUE "ProductName", "FreedomNet"'));
      expect(runnerRc, contains('VALUE "FileDescription", "自由云 · FreedomNet"'));
      expect(runnerRc, contains('VALUE "OriginalFilename", "FreedomNet.exe"'));

      final windowsCmake = File('windows/CMakeLists.txt').readAsStringSync();
      expect(windowsCmake, contains('project(FreedomNet LANGUAGES CXX)'));
      expect(windowsCmake, contains('set(BINARY_NAME "FreedomNet")'));
      expect(windowsCmake, contains('FreedomNetCore.exe'));
      expect(windowsCmake, contains('FreedomNetAgent.exe'));
      expect(windowsCmake, contains('FreedomNetHelperService.exe'));

      final windowDart = File('lib/common/window.dart').readAsStringSync();
      expect(windowDart, contains('protocol.register("freedomnet")'));
      expect(windowDart, isNot(contains('protocol.register("flclash")')));
      expect(windowDart, isNot(contains('protocol.register("flclashx")')));

      // Subscription User-Agent contract stays FlClash X/v...
      final info = PackageInfo(
        appName: 'FreedomNet',
        packageName: 'FreedomNet',
        version: '0.4.2',
        buildNumber: '1',
      );
      expect(
        info.ua(appVersion: '0.4.2', coreVersion: 'v1.19.32'),
        startsWith('FlClash X/v0.4.2 '),
      );
    });

    testWidgets('AboutView displays official website https://fast.hjy.ca:8443/ and bilingual FreedomNet branding',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await AppLocalizations.load(const Locale('zh', 'CN'));
      globalState.packageInfo = PackageInfo(
        appName: 'FreedomNet',
        packageName: 'FreedomNet',
        version: '0.4.2',
        buildNumber: '1',
      );
      globalState.coreVersion = 'v1.19.32';
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('zh', 'CN'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.delegate.supportedLocales,
            home: const Scaffold(body: AboutView()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final siteTile = find.byKey(const ValueKey('about-official-website'));
      expect(siteTile, findsOneWidget);
      expect(
        find.descendant(
          of: siteTile,
          matching: find.text('自由云 · FreedomNet'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: siteTile,
          matching: find.text('https://fast.hjy.ca:8443/'),
        ),
        findsOneWidget,
      );
    });
  });
}

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

    test(
      'Inno Setup installer displays Terms of Service popup with exact wording, Accept/Decline buttons, and unconditional continuation',
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

        expect(
          rendered,
          contains('chineseSimplified.TermsDialogInstruction=服务条款'),
        );
        expect(
          rendered,
          contains('english.TermsDialogInstruction=Terms of Service'),
        );
        expect(
          rendered,
          contains(
            'chineseSimplified.TermsDialogBody=本软件只供人们用于Ai和用于学习,用于跨境电商和游戏加速,禁止用于传播违法资料禁止用于发表违法言论,请务必遵守国家法律,一旦发现有违法行为本软件有权利结束服务',
          ),
        );
        expect(rendered, contains('english.TermsDialogBody='));
        expect(
          rendered,
          contains('chineseSimplified.TermsAcceptButton=接受'),
        );
        expect(rendered, contains('english.TermsAcceptButton=Accept'));
        expect(
          rendered,
          contains('chineseSimplified.TermsDeclineButton=不接受'),
        );
        expect(rendered, contains('english.TermsDeclineButton=Decline'));

        final fmtIdx = rendered.indexOf('function FormatSetupText(');
        final tosIdx = rendered.indexOf('procedure ShowTermsOfServiceDialog;');
        final initIdx = rendered.indexOf('function InitializeSetup(): Boolean;');
        final initWizIdx = rendered.indexOf('procedure InitializeWizard();');
        expect(fmtIdx, greaterThan(0));
        expect(tosIdx, greaterThan(fmtIdx));
        expect(initIdx, greaterThan(tosIdx));
        expect(initWizIdx, greaterThan(initIdx));

        final tosAndInitBlock = rendered.substring(tosIdx, initWizIdx);
        expect(tosAndInitBlock, contains('SuppressibleTaskDialogMsgBox('));
        expect(tosAndInitBlock, contains('MB_YESNO'));
        expect(
          tosAndInitBlock,
          contains('if (not WizardSilent) and (not IsManagedUpdate()) then'),
        );
        expect(tosAndInitBlock, contains('ShowTermsOfServiceDialog'));
        expect(tosAndInitBlock, contains('Result := True;'));
        expect(tosAndInitBlock, isNot(contains('Result := False')));
        expect(tosAndInitBlock, isNot(contains('Abort')));
      },
    );

    test(
      'HIGH-2: InitializeSetup never stops services or kills processes before confirmation; CurStepChanged(ssInstall) performs teardown',
      () {
        final template =
            File('windows/packaging/exe/inno_setup.iss').readAsStringSync();
        for (final strict in [false, true]) {
          final rendered = setup.Build.renderWindowsInnoSetupScript(
            template: template,
            version: '0.4.2',
            archName: 'amd64',
            buildDir: r'E:\build\windows\x64\runner\Release',
            setupIconFile: r'E:\repo\windows\runner\resources\app_icon.ico',
            chineseIslPath:
                r'E:\repo\windows\packaging\exe\ChineseSimplified.isl',
            strict: strict,
          );

          expect(rendered, contains('CloseApplications=no'));
          expect(rendered, contains('RestartApplications=no'));

          final initStart =
              rendered.indexOf('function InitializeSetup(): Boolean;');
          final initEnd = rendered.indexOf('procedure InitializeWizard();');
          expect(initStart, greaterThan(0));
          expect(initEnd, greaterThan(initStart));

          final initBlock = rendered.substring(initStart, initEnd);
          expect(
            initBlock,
            contains('if (not WizardSilent) and (not IsManagedUpdate()) then'),
          );
          expect(initBlock, contains('ShowTermsOfServiceDialog;'));
          expect(initBlock, contains('IsUpgrade := IsAppInstalled();'));
          expect(initBlock, contains('PreviousVersion := GetInstalledVersion();'));
          expect(initBlock, contains('Result := True;'));
          expect(initBlock, isNot(contains('KillProcesses')));
          expect(initBlock, isNot(contains('FreedomNetHelperService')));
          expect(initBlock, isNot(contains('StopStrictService')));
          expect(initBlock, isNot(contains('FlClashStrictBroker')));
          expect(initBlock, isNot(contains('FlClashStrictCallout')));
          expect(initBlock.toLowerCase(), isNot(contains('sc.exe')));
          expect(initBlock.toLowerCase(), isNot(contains('taskkill')));

          final curStepStart = rendered
              .indexOf('procedure CurStepChanged(CurStep: TSetupStep);');
          final curUninstallStart = rendered.indexOf(
            'procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);',
          );
          expect(curStepStart, greaterThan(initEnd));
          expect(curUninstallStart, greaterThan(curStepStart));

          final curStepBlock =
              rendered.substring(curStepStart, curUninstallStart);
          final ssInstallIdx =
              curStepBlock.indexOf('if CurStep = ssInstall then');
          final ssPostInstallIdx =
              curStepBlock.indexOf('if CurStep = ssPostInstall then');
          expect(ssInstallIdx, greaterThan(0));
          expect(ssPostInstallIdx, greaterThan(ssInstallIdx));

          final ssInstallBlock =
              curStepBlock.substring(ssInstallIdx, ssPostInstallIdx);
          final stopHelperIdx = ssInstallBlock.indexOf(
            'stop "FreedomNetHelperService"',
          );
          final sleepIdx = ssInstallBlock.indexOf('Sleep(1000);');
          final killIdx = ssInstallBlock.indexOf(
            'if not IsManagedUpdate() then KillProcesses;',
          );
          expect(stopHelperIdx, greaterThan(0));
          expect(sleepIdx, greaterThan(stopHelperIdx));
          expect(killIdx, greaterThan(sleepIdx));

          if (strict) {
            final stopBrokerIdx = ssInstallBlock.indexOf(
              "StopStrictService('FlClashStrictBroker');",
            );
            final stopCalloutIdx = ssInstallBlock.indexOf(
              "StopStrictService('FlClashStrictCallout');",
            );
            expect(stopBrokerIdx, greaterThan(stopHelperIdx));
            expect(stopCalloutIdx, greaterThan(stopBrokerIdx));
            expect(sleepIdx, greaterThan(stopCalloutIdx));
          } else {
            expect(
              ssInstallBlock,
              isNot(contains("StopStrictService('FlClashStrictBroker')")),
            );
          }
        }
      },
    );

    test(
      r'MED-1: elevated Inno Setup script uses {sys}\sc.exe and {sys}\taskkill.exe for every Exec call (CWE-426)',
      () {
        final template =
            File('windows/packaging/exe/inno_setup.iss').readAsStringSync();
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

        expect(
          RegExp(r"Exec\s*\(\s*'taskkill", caseSensitive: false)
              .hasMatch(strictRendered),
          isFalse,
        );
        expect(
          RegExp(r"Exec\s*\(\s*'sc\.exe", caseSensitive: false)
              .hasMatch(strictRendered),
          isFalse,
        );
        expect(
          RegExp(r'ShellExec\s*\(', caseSensitive: false)
              .hasMatch(strictRendered),
          isFalse,
        );

        final execMatches =
            RegExp(r'Exec\s*\(([^,]+),').allMatches(strictRendered).toList();
        expect(execMatches.length, greaterThanOrEqualTo(10));
        for (final match in execMatches) {
          final firstArg = match.group(1)!.trim();
          expect(
            firstArg,
            anyOf(
              equals(r"ExpandConstant('{sys}\sc.exe')"),
              equals(r"ExpandConstant('{sys}\taskkill.exe')"),
            ),
            reason: 'Untrusted Exec path in Inno Setup script: $firstArg',
          );
        }

        final killStart = strictRendered.indexOf('procedure KillProcesses;');
        final killEnd =
            strictRendered.indexOf('function IsAppInstalled(): Boolean;');
        final killBlock = strictRendered.substring(killStart, killEnd);
        expect(
          killBlock,
          contains(
            r"Exec(ExpandConstant('{sys}\taskkill.exe'), '/im ' + Processes[i]",
          ),
        );
        expect(
          killBlock,
          contains(
            r"Exec(ExpandConstant('{sys}\taskkill.exe'), '/f /im ' + Processes[i]",
          ),
        );
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

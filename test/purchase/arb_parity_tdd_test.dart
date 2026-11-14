import 'dart:convert';
import 'dart:io';

import 'package:flclashx/l10n/l10n.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

({Map<String, dynamic> data, List<String> duplicateKeys}) _readArb(
  String fileName,
) {
  final file = File('arb/$fileName');
  expect(
    file.existsSync(),
    isTrue,
    reason: 'Expected ARB file at ${file.path}',
  );
  final raw = file.readAsStringSync();
  final decoded = jsonDecode(raw);
  expect(
    decoded,
    isA<Map<String, dynamic>>(),
    reason: 'Expected JSON object in $fileName',
  );
  return (
    data: decoded as Map<String, dynamic>,
    duplicateKeys: _findTopLevelDuplicateKeys(raw),
  );
}

List<String> _findTopLevelDuplicateKeys(String rawJson) {
  final seen = <String>{};
  final duplicates = <String>[];
  var depth = 0;
  var inString = false;
  var escaped = false;
  var expectingKey = false;
  final currentString = StringBuffer();

  for (var i = 0; i < rawJson.length; i++) {
    final codeUnit = rawJson.codeUnitAt(i);
    if (inString) {
      if (escaped) {
        currentString.writeCharCode(codeUnit);
        escaped = false;
      } else if (codeUnit == 0x5C /* \ */) {
        escaped = true;
      } else if (codeUnit == 0x22 /* " */) {
        inString = false;
        if (expectingKey) {
          final key = currentString.toString();
          if (!seen.add(key)) {
            duplicates.add(key);
          }
          expectingKey = false;
        }
      } else {
        currentString.writeCharCode(codeUnit);
      }
      continue;
    }

    if (codeUnit == 0x22 /* " */) {
      inString = true;
      currentString.clear();
      continue;
    }

    if (codeUnit == 0x7B /* { */) {
      depth++;
      if (depth == 1) {
        expectingKey = true;
      }
    } else if (codeUnit == 0x7D /* } */) {
      depth--;
      expectingKey = false;
    } else if (codeUnit == 0x2C /* , */ && depth == 1) {
      expectingKey = true;
    }
  }
  return duplicates;
}

Set<String> _extractPlaceholders(String template) {
  final matches = RegExp(r'\{([a-zA-Z0-9_]+)\}').allMatches(template);
  return matches.map((m) => m.group(1)!).toSet();
}

Map<String, String> _samplePurchaseAndSupportGetters(AppLocalizations l10n) =>
    {
      'purchaseTitle': l10n.purchaseTitle,
      'purchaseCenterTitle': l10n.purchaseCenterTitle,
      'purchaseCenterDescription': l10n.purchaseCenterDescription,
      'purchaseAccount': l10n.purchaseAccount,
      'purchaseLoginTitle': l10n.purchaseLoginTitle,
      'purchaseLogin': l10n.purchaseLogin,
      'purchaseRegister': l10n.purchaseRegister,
      'purchaseAvailablePlans': l10n.purchaseAvailablePlans,
      'purchaseRedeemTitle': l10n.purchaseRedeemTitle,
      'purchaseConfirmRedeem': l10n.purchaseConfirmRedeem,
      'purchaseBalance': l10n.purchaseBalance,
      'purchaseUnresolved': l10n.purchaseUnresolved,
      'purchaseSync': l10n.purchaseSync,
      'purchaseSyncSucceeded': l10n.purchaseSyncSucceeded,
      'purchaseHistory': l10n.purchaseHistory,
      'purchaseGetCard': l10n.purchaseGetCard,
      'purchaseCardStore': l10n.purchaseCardStore,
      'purchasePeriodMonthly': l10n.purchasePeriodMonthly,
      'purchasePeriodQuarterly': l10n.purchasePeriodQuarterly,
      'purchasePeriodHalfYearly': l10n.purchasePeriodHalfYearly,
      'purchasePeriodYearly': l10n.purchasePeriodYearly,
      'purchasePeriodTwoYearly': l10n.purchasePeriodTwoYearly,
      'purchasePeriodThreeYearly': l10n.purchasePeriodThreeYearly,
      'purchasePeriodOnetime': l10n.purchasePeriodOnetime,
      'purchaseGenericError': l10n.purchaseGenericError,
      'purchaseStorageError': l10n.purchaseStorageError,
      'purchaseCodeFormatError': l10n.purchaseCodeFormatError,
      'purchaseChannelError': l10n.purchaseChannelError,
      'purchaseOnlineSupport': l10n.purchaseOnlineSupport,
      'supportSheetTitle': l10n.supportSheetTitle,
    };

void main() {
  group('P1-9: 4-locale ARB key parity and brand cleanup', () {
    test(
      'every purchase* and support* key and @metadata in en/zh_CN exists with non-empty localized text and matching placeholders in ja and ru',
      () {
        final enParsed = _readArb('intl_en.arb');
        final zhParsed = _readArb('intl_zh_CN.arb');
        final jaParsed = _readArb('intl_ja.arb');
        final ruParsed = _readArb('intl_ru.arb');

        expect(enParsed.duplicateKeys, isEmpty);
        expect(zhParsed.duplicateKeys, isEmpty);
        expect(jaParsed.duplicateKeys, isEmpty);
        expect(ruParsed.duplicateKeys, isEmpty);

        final en = enParsed.data;
        final zhCn = zhParsed.data;
        final ja = jaParsed.data;
        final ru = ruParsed.data;

        bool isTargetMessageKey(String key) =>
            !key.startsWith('@') &&
            (key.startsWith('purchase') || key.startsWith('support'));

        final enKeys = en.keys.where(isTargetMessageKey).toSet();
        final zhKeys = zhCn.keys.where(isTargetMessageKey).toSet();
        expect(
          zhKeys,
          equals(enKeys),
          reason:
              'Expected intl_en.arb and intl_zh_CN.arb to share identical purchase*/support* keys',
        );

        final targetKeys = enKeys.toList()..sort();

        for (final localeEntry in <String, Map<String, dynamic>>{
          'intl_ja.arb': ja,
          'intl_ru.arb': ru,
        }.entries) {
          final fileName = localeEntry.key;
          final arb = localeEntry.value;

          final missingKeys = <String>[];
          final emptyKeys = <String>[];
          final untranslatedEnglishKeys = <String>[];
          final placeholderMismatches = <String>[];
          final missingMetadata = <String>[];
          final metadataMismatches = <String>[];

          for (final key in targetKeys) {
            if (!arb.containsKey(key)) {
              missingKeys.add(key);
              continue;
            }
            final value = arb[key];
            if (value is! String || value.trim().isEmpty) {
              emptyKeys.add(key);
              continue;
            }
            final enValue = en[key] as String;
            if (value.trim() == enValue.trim()) {
              untranslatedEnglishKeys.add(key);
            }
            final enPlaceholders = _extractPlaceholders(enValue);
            final targetPlaceholders = _extractPlaceholders(value);
            if (enPlaceholders.length != targetPlaceholders.length ||
                !enPlaceholders.containsAll(targetPlaceholders)) {
              placeholderMismatches.add(
                '$key (expected $enPlaceholders, got $targetPlaceholders)',
              );
            }

            final metaKey = '@$key';
            final enMeta = en[metaKey] ?? zhCn[metaKey];
            if (enMeta != null) {
              if (!arb.containsKey(metaKey)) {
                missingMetadata.add(metaKey);
              } else if (jsonEncode(arb[metaKey]) != jsonEncode(enMeta)) {
                metadataMismatches.add(metaKey);
              }
            }
          }

          expect(
            missingKeys,
            isEmpty,
            reason: '$fileName is missing purchase*/support* keys: $missingKeys',
          );
          expect(
            emptyKeys,
            isEmpty,
            reason: '$fileName has empty purchase*/support* keys: $emptyKeys',
          );
          expect(
            untranslatedEnglishKeys,
            isEmpty,
            reason:
                '$fileName has untranslated English purchase*/support* keys: $untranslatedEnglishKeys',
          );
          expect(
            placeholderMismatches,
            isEmpty,
            reason:
                '$fileName has placeholder mismatches: $placeholderMismatches',
          );
          expect(
            missingMetadata,
            isEmpty,
            reason: '$fileName is missing @metadata entries: $missingMetadata',
          );
          expect(
            metadataMismatches,
            isEmpty,
            reason:
                '$fileName has @metadata mismatches against en: $metadataMismatches',
          );
        }
      },
    );

    test(
      'intl_ja.arb and intl_ru.arb contain zero (自由云) Chinese brand residue',
      () {
        final ja = _readArb('intl_ja.arb').data;
        final ru = _readArb('intl_ru.arb').data;

        for (final entry in <String, Map<String, dynamic>>{
          'intl_ja.arb': ja,
          'intl_ru.arb': ru,
        }.entries) {
          final fileName = entry.key;
          final arb = entry.value;

          final residueKeys = <String>[];
          for (final kv in arb.entries) {
            final value = kv.value;
            if (value is String &&
                (value.contains('自由云') ||
                    value.contains('(自由云)') ||
                    value.contains('（自由云）'))) {
              residueKeys.add('${kv.key}: $value');
            }
          }

          expect(
            residueKeys,
            isEmpty,
            reason:
                '$fileName still contains Chinese brand residue: $residueKeys',
          );

          for (final brandKey in const [
            'tributeFlclashxBody',
            'tributeGeminiBody',
            'brandShowcaseHeroBody',
          ]) {
            expect(
              arb[brandKey],
              isA<String>(),
              reason: '$fileName missing $brandKey',
            );
            expect(
              arb[brandKey] as String,
              contains('FreedomNet'),
              reason: '$fileName $brandKey must mention FreedomNet',
            );
            expect(
              arb[brandKey] as String,
              isNot(contains('自由云')),
              reason: '$fileName $brandKey must not contain 自由云',
            );
          }
        }
      },
    );

    test(
      'AppLocalizations loads Japanese and Russian translations for backfilled purchase keys instead of English fallbacks',
      () async {
        final en = await AppLocalizations.load(const Locale('en'));
        addTearDown(() => AppLocalizations.load(const Locale('en')));
        final enSamples = _samplePurchaseAndSupportGetters(en);

        Future<void> verifyLocale(Locale locale, String arbFileName) async {
          final arb = _readArb(arbFileName).data;
          final l10n = await AppLocalizations.load(locale);
          final samples = _samplePurchaseAndSupportGetters(l10n);
          final tag = locale.languageCode;

          for (final entry in samples.entries) {
            final key = entry.key;
            final actual = entry.value;
            expect(
              actual,
              isNot(equals(enSamples[key])),
              reason: '$tag AppLocalizations.$key fell back to English ("$actual")',
            );
            expect(
              actual,
              equals(arb[key]),
              reason: '$tag AppLocalizations.$key must match regenerated $arbFileName',
            );
          }

          expect(
            l10n.purchasePlanResetUnknown(42),
            equals((arb['purchasePlanResetUnknown'] as String)
                .replaceAll('{code}', '42')),
          );
          expect(l10n.tributeFlclashxBody, isNot(contains('自由云')));
          expect(l10n.tributeGeminiBody, isNot(contains('自由云')));
          expect(l10n.brandShowcaseHeroBody, isNot(contains('自由云')));
        }

        await verifyLocale(const Locale('ja'), 'intl_ja.arb');
        await verifyLocale(const Locale('ru'), 'intl_ru.arb');
      },
    );
  });
}

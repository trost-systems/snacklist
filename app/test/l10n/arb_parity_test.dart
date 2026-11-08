import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keys whose English text is the same as the German one on purpose.
const sameInBothLanguages = {
  'appTitle': 'brand name',
  'lifetimeTitle': 'product name',
  'premiumTitle': 'product name',
  'premiumStatusLifetime': 'product name',
  'premiumLifetimeTitle': 'product name (Lifetime)',
  'premiumManageApple': 'store name',
  'premiumManageGoogle': 'store name',
  'inviteCodeLabel': '"Code" is English too',
  'themeSystem': '"System" is the word in both (job 57 theme control)',
  'inviteLinkLabel': '"Link" is English too',
  'householdRoleAdmin': '"Admin" is the German role name too (job 169b W2)',
  'tokenHint': 'only an ellipsis and the token hint',
  'tokenName': '"Name" is English too',
  'apiHeader': '"API" is the word in both (job 73)',
  'categoryName': '"Name" is English too',
  'appVersion': '"Version" is English too',
  'feedbackSection': '"Feedback" is German too',
  'feedbackCategoryBug': '"Bug" is what German testers say',
  'feedbackCounter': 'only numbers',
  'siriHeader': 'product name',
  'syncOffline': '"Offline" is German too (job 161)',
};

Map<String, Object?> readArb(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;

Set<String> messageKeys(Map<String, Object?> arb) =>
    arb.keys.where((key) => !key.startsWith('@')).toSet();

/// Names of the top-level ICU arguments in [message]: `{name}`,
/// `{count, plural, ...}`, `{gender, select, ...}`. Arguments nested inside
/// plural or select branches repeat a top-level one and are skipped.
Set<String> argumentNames(String message) {
  final names = <String>{};
  var depth = 0;
  for (var i = 0; i < message.length; i++) {
    switch (message[i]) {
      case '{':
        if (depth == 0) {
          final end = message.indexOf(RegExp('[,}]'), i + 1);
          names.add(message.substring(i + 1, end).trim());
        }
        depth++;
      case '}':
        depth--;
    }
  }
  return names;
}

Set<String> declaredPlaceholders(Map<String, Object?> arb, String key) {
  final meta = arb['@$key'] as Map<String, Object?>?;
  final placeholders = meta?['placeholders'] as Map<String, Object?>?;
  return placeholders?.keys.toSet() ?? const {};
}

void main() {
  final de = readArb('l10n/app_de.arb');
  final en = readArb('l10n/app_en.arb');

  test('German and English define the same messages', () {
    expect(messageKeys(en), messageKeys(de));
  });

  test('every message uses and declares the same placeholders in both', () {
    for (final key in messageKeys(de).intersection(messageKeys(en))) {
      expect(
        argumentNames(en[key]! as String),
        argumentNames(de[key]! as String),
        reason: '$key: arguments in the message text',
      );
      expect(
        declaredPlaceholders(en, key),
        declaredPlaceholders(de, key),
        reason: '@$key.placeholders',
      );
    }
  });

  test('every English message is translated', () {
    final untranslated = [
      for (final key in messageKeys(de).intersection(messageKeys(en)))
        if (en[key] == de[key] && !sameInBothLanguages.containsKey(key)) key,
    ];
    expect(
      untranslated,
      isEmpty,
      reason:
          'English equals German; translate it or add it to '
          'sameInBothLanguages with a reason',
    );
  });
}

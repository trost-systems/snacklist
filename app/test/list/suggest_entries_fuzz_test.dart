import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:family_groceries/list/add_sheet/suggestion.dart';
import 'package:family_groceries/list/catalog/catalog_index.dart';
import 'package:family_groceries/list/catalog/household_index.dart';
import 'package:family_groceries/list/catalog/suggest_entries.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter_test/flutter_test.dart';

/// Typing runs suggestEntries on every key (job 274): no line may throw.
void main() {
  final parity = jsonDecode(
    File('../supabase/tests/suggest_parity.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final household = HouseholdIndex.fromJson(parity['index'])!;
  final texts = [
    for (final row in (parity['cases']! as List<Object?>))
      if (row case [final String text, ...]) text,
  ];

  List<Suggestion> rank(String text) => suggestEntries(
    text,
    catalog: CatalogIndex.bundled,
    household: household,
    categories: const Catalog(),
    known: const {},
  );

  test('a size too large for an integer offers no size rows', () {
    for (final text in [
      'Windeln Größe 99999999999999999999',
      'Windeln größe99999999999999999999',
      'Windeln gr. 99999999999999999999',
      'Windeln Größe 9223372036854775808',
    ]) {
      expect(
        rank(text).where((row) => row.source == SuggestionSource.size),
        isEmpty,
        reason: text,
      );
    }
  });

  test('random lines of words, numbers and punctuation never throw', () {
    final words = {
      for (final text in texts) ...text.split(' '),
      ...'Größe größe gr gr. groesse 99999999999999999999 0 00 007 1 9 20 21 '
              '2147483648 x × X 6x1,5 1/2 ½ % 3,5% , ; ,; . .. - -lagig lagig '
              '4er Pack er Rollen rolle Vol fett zwei ZWEI Zwölf eineinhalb '
              'l ml kg g Stk ß İ Ǆ ﬃ 🍌 ‍ \t'
          .split(' '),
    }.toList();
    final random = Random(274);
    for (var i = 0; i < 4000; i++) {
      final line = [
        for (var w = random.nextInt(5); w >= 0; w--)
          words[random.nextInt(words.length)],
      ].join(random.nextBool() ? ' ' : '');
      expect(() => rank(line), returnsNormally, reason: line);
    }
  });
}

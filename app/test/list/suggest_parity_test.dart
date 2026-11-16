import 'dart:convert';
import 'dart:io';

import 'package:family_groceries/list/catalog/catalog_index.dart';
import 'package:family_groceries/list/catalog/household_index.dart';
import 'package:family_groceries/list/catalog/suggest_entries.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rows whose category the device guesses differently from the server,
/// by text and row name, with the reason. Every other row the device
/// guesses agrees, and an exception that agrees again fails the test.
const _categoryExceptions = <String, String>{
  'Bratschlauc|Bratschlauc': _typo,
  'Geflegel|Geflegel': _typo,
  'Geflgel|Geflgel': _typo,
  'Gefülgel|Gefülgel': _typo,
  'Kerneeife|Kerneeife': _typo,
  'Kerneife|Kerneife': _typo,
  'Kücheneücher|Kücheneücher': _typo,
  'Küchenücher|Küchenücher': _typo,
  'Küchetnücher|Küchetnücher': _typo,
  'Pizzaotmaten|Pizzaotmaten': _typo,
  'Pizzatematen|Pizzatematen': _typo,
  'Pizzatmaten|Pizzatmaten': _typo,
  'Schaumeucker|Schaumeucker': _typo,
  'Schaumucker|Schaumucker': _typo,
  'Spülmasceinengel|Spülmasceinengel': _typo,
  'Spülmascinengel|Spülmascinengel': _typo,
  'Spülmashcinengel|Spülmashcinengel': _typo,
  'Wassereelone|Wassereelone': _typo,
  'Wasserelone|Wasserelone': _typo,
  'Tortillaa chips|Tortillaa Chipstüte': _typo,
  'Apfelsaf|Apfelsaf': _partial,
  'Bratschlau|Bratschlau': _partial,
  'Butternu|Butternu': _partial,
  'Grapefr|Grapefr': _partial,
  'Hackfleis|Hackfleis': _partial,
  'Nagelhär|Nagelhär': _partial,
  'Nagelhärt|Nagelhärt': _partial,
  'Nagelhärte|Nagelhärte': _partial,
  'Pizzatoma|Pizzatoma': _partial,
  'Plim|Plim': _partial,
  'Sham|Sham': _partial,
  'Thunfischsal|Thunfischsal': _partial,
  'Thunfischsala|Thunfischsala': _partial,
  'Catrice|Catrice': _brandAlone,
};

const _typo =
    'a typo: public.classify_item_detail corrects it (lexicon_fuzzy), '
    'guessCategory has no typo path and finds a part of another word';
const _partial =
    'a word typed halfway: the server matches it against the unfolded '
    "terms, guessCategory against the lexicon's folded forms, and they "
    'end or start differently';
const _brandAlone =
    'a brand without a product: the server knows no item, guessCategory '
    'finds a term the brand ends with (rice)';

/// The device's rows for every text of supabase/tests/suggest_parity.json
/// are the server's (job 274): the same source, name, brand, details and
/// Menge in the same order. The db gate's
/// supabase/functions/_shared/suggest_parity_integration_test.ts holds the
/// server to the same file.
void main() {
  final parity = jsonDecode(
    File('../supabase/tests/suggest_parity.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final household = HouseholdIndex.fromJson(parity['index'])!;
  final seeds = (parity['categories']! as List<Object?>).cast<String>();
  final categories = Catalog(
    categories: [
      for (final (i, seed) in seeds.indexed)
        Category(id: seed, name: seed, sortOrder: i, seedKey: seed),
    ],
  );
  // The category each name's latest item got on its insert, as
  // householdCategories reads the list.
  final latest = <String, (num, String)>{};
  for (final row in parity['history']! as List<Object?>) {
    if (row case [
      final String name,
      _,
      _,
      _,
      final num age,
      final String seed,
    ]) {
      final key = foldName(name);
      if (latest[key] case (final newer, _) when newer <= age) {
        continue;
      }
      latest[key] = (age, seed);
    }
  }
  final known = {
    for (final MapEntry(:key, value: (_, seed)) in latest.entries) key: seed,
  };
  final cases = [
    for (final c in parity['cases']! as List<Object?>)
      if (c case [final String text, final List<Object?> rows]) (text, rows),
  ];

  test('the device ranks every text as the server does', () {
    final differing = <String>[];
    var rows = 0;
    for (final (text, expected) in cases) {
      rows += expected.length;
      final actual = [
        for (final (source, e) in suggestRows(
          text,
          catalog: CatalogIndex.bundled,
          household: household,
        ))
          [source.name, e.name, e.brand, e.properties, e.quantity],
      ];
      final server = [
        for (final row in expected) (row! as List<Object?>).sublist(0, 5),
      ];
      if (jsonEncode(actual) != jsonEncode(server)) {
        differing.add(
          '${jsonEncode(text)}\n  server ${jsonEncode(server)}\n'
          '  device ${jsonEncode(actual)}',
        );
      }
    }
    // ignore: avoid_print -- the table's size, for the record
    print('suggest parity: ${cases.length} texts, $rows rows');
    expect(differing, isEmpty, reason: differing.take(30).join('\n'));
  });

  test('the device guesses the server category of every row it can', () {
    var agree = 0;
    var guessed = 0;
    var rows = 0;
    final differing = <String>[];
    for (final (text, expected) in cases) {
      final actual = suggestEntries(
        text,
        catalog: CatalogIndex.bundled,
        household: household,
        categories: categories,
        known: known,
      );
      for (final (i, row) in expected.indexed) {
        rows++;
        final server = (row! as List<Object?>)[5] as String?;
        final device = i < actual.length ? actual[i].entry.categoryId : null;
        if (device == null) {
          continue;
        }
        guessed++;
        final excepted = _categoryExceptions.containsKey(
          '$text|${actual[i].entry.name}',
        );
        if (device == server) {
          agree++;
          if (excepted) {
            differing.add('${jsonEncode(text)}: agrees, drop the exception');
          }
        } else if (!excepted) {
          differing.add(
            '${jsonEncode(text)} ${actual[i].entry.name}: server $server, '
            'device $device',
          );
        }
      }
    }
    // ignore: avoid_print -- the agreement, for the record
    print(
      'suggest parity categories: $agree of $guessed guessed rows agree; '
      '$rows rows in all',
    );
    expect(differing, isEmpty, reason: differing.join('\n'));
  });
}

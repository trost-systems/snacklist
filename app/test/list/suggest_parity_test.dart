import 'dart:convert';
import 'dart:io';

import 'package:family_groceries/list/catalog/catalog_index.dart';
import 'package:family_groceries/list/catalog/household_index.dart';
import 'package:family_groceries/list/catalog/suggest_entries.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'suggest_parity_stores.dart';

/// Rows whose category the device guesses differently from the server,
/// by text and row name, with the reason. Every other row the device
/// guesses agrees, and an exception that agrees again fails the test.
const _categoryExceptions = <String, String>{
  'Bratschlauc|Bratschlauc': _typo,
  'Quarkbellchen|Quarkbellchen': _typo,
  'Quarkbllchen|Quarkbllchen': _typo,
  'Quarkäbllchen|Quarkäbllchen': _typo,
  'Schaumeucker|Schaumeucker': _typo,
  'Schaumucker|Schaumucker': _typo,
  'Spülmasceinengel|Spülmasceinengel': _typo,
  'Spülmascinengel|Spülmascinengel': _typo,
  'Spülmashcinengel|Spülmashcinengel': _typo,
  'Wassereelone|Wassereelone': _typo,
  'Wasserelone|Wasserelone': _typo,
  'Tortillaa chips|Tortillaa Chipstüte': _typo,
  'Ftea|Ftea': _typo,
  'Hundenack|Hundenack': _typo,
  'Hundsenack|Hundsenack': _typo,
  'Hundeenack|Hundeenack': _typo,
  'Kräutrtee|Kräutrtee': _typo,
  'Kräuetrtee|Kräuetrtee': _typo,
  'Kräutartee|Kräutartee': _typo,
  'Milchbötchen|Milchbötchen': _typo,
  'Milchrbötchen|Milchrbötchen': _typo,
  'Milchbeötchen|Milchbeötchen': _typo,
  'Nagelkipser|Nagelkipser': _typo,
  'Nagelnkipser|Nagelnkipser': _typo,
  'Nagelkeipser|Nagelkeipser': _typo,
  'Reißzecke|Reißzecke': _typo,
  'Reißwzecke|Reißwzecke': _typo,
  'Reißzeecke|Reißzeecke': _typo,
  'Apfelsaf|Apfelsaf': _partial,
  'Bratschlau|Bratschlau': _partial,
  'Butternu|Butternu': _partial,
  'Grapefr|Grapefr': _partial,
  'Hackfleis|Hackfleis': _partial,
  'Plim|Plim': _partial,
  'Quarkbäl|Quarkbäl': _partial,
  'Quarkbäll|Quarkbäll': _partial,
  'Sham|Sham': _partial,
  'Thunfischsal|Thunfischsal': _partial,
  'Thunfischsala|Thunfischsala': _partial,
  'Kaffeesa|Kaffeesa': _partial,
  'Kaffeesah|Kaffeesah': _partial,
  'Kräutersei|Kräutersei': _partial,
  'Lidstric|Lidstric': _partial,
  'Nagelkl|Nagelkl': _partial,
  'Nagelkle|Nagelkle': _partial,
  'Nagelkleb|Nagelkleb': _partial,
  'Nagelklebe|Nagelklebe': _partial,
  'Peperon|Peperon': _partial,
  'Topf|Topf': _homograph,
  'Apfelmu|Apfelmu': _partial,
  'Butterschma|Butterschma': _partial,
  'Butterschmal|Butterschmal': _partial,
  'Estric|Estric': _partial,
  'Polent|Polent': _partial,
  'Curryurst|Curryurst': _typo,
  'Curryeurst|Curryeurst': _typo,
  'Kucheform|Kucheform': _typo,
  'Kuchneform|Kuchneform': _typo,
  'Kucheeform|Kucheeform': _typo,
  'Milchulver|Milchulver': _typo,
  'Milcheulver|Milcheulver': _typo,
  'Nagelflege|Nagelflege': _typo,
  'Nageleflege|Nageleflege': _typo,
  'Pomeär|Pomeär': _typo,
  'Schnekel|Schnekel': _typo,
  'To|Topf': _homograph,
  'Kohlenschauf|Kohlenschauf': _typo,
  'Kohlenschaufe|Kohlenschaufe': _typo,
  'Schäufele|Schäufele': _homograph,
  'Mozzareleakugeln|Mozzareleakugeln': _typo,
  'Nagelinsel|Nagelinsel': _typo,
  'Nageleinsel|Nageleinsel': _typo,
  'Rohrudel|Rohrudel': _typo,
  'Rohreudel|Rohreudel': _typo,
  'Fleckent|Fleckent': _tailGuard,
  'Heringssal|Heringssal': _partial,
  'Heringssala|Heringssala': _partial,
  'Kräuterto|Kräuterto': _partial,
  'Colate|Colate': _partial,
  'Chef Select|Chef Select': _tailGuard,
  'Catrice|Catrice': _brandAlone,
};

const _homograph =
    'a word the stemmer folds onto another word (Topf and Topfen): the server '
    'reads the typed spelling (job 282), guessCategory has no homographs yet';
const _tailGuard =
    'a word that only ends like a short term (ent, gel): the server ignores the '
    'tail unless the typed word spells it, guessCategory has no typed text';
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
  List<(String, List<Object?>)> casesOf(Object? json) => [
    for (final c in json! as List<Object?>)
      if (c case [final String text, final List<Object?> rows]) (text, rows),
  ];
  final cases = casesOf(parity['cases']);
  final pendingTable = parity['pending']! as Map<String, Object?>;
  final pending = HouseholdIndex.fromJson({
    'history': pendingTable['items'],
    'brands': const <Object?>[],
    'unserved': const <Object?>[],
    'known': const <Object?>[],
  })!.history;
  final deltaTable = parity['delta']! as Map<String, Object?>;
  final delta = CatalogIndex.bundled.apply(
    parseCatalogDelta(deltaTable['answer'])!,
  );

  /// The three tables: the household as indexed; with items the index
  /// has not seen yet; with a term the catalog gained since the build.
  final tables = [
    (
      name: 'cases',
      cases: cases,
      catalog: CatalogIndex.bundled,
      pending: <HistoryRow>[],
    ),
    (
      name: 'pending',
      cases: casesOf(pendingTable['cases']),
      catalog: CatalogIndex.bundled,
      pending: pending,
    ),
    (
      name: 'delta',
      cases: casesOf(deltaTable['cases']),
      catalog: delta,
      pending: <HistoryRow>[],
    ),
  ];

  test('the device ranks every text as the server does', () {
    final differing = <String>[];
    var rows = 0;
    var texts = 0;
    for (final table in tables) {
      for (final (text, expected) in table.cases) {
        texts++;
        rows += expected.length;
        final actual = [
          for (final (source, e) in suggestRows(
            text,
            catalog: table.catalog,
            household: household,
            pending: table.pending,
          ))
            [source.name, e.name, e.brand, e.properties, e.quantity],
        ];
        final server = [
          for (final row in expected) (row! as List<Object?>).sublist(0, 5),
        ];
        if (jsonEncode(actual) != jsonEncode(server)) {
          differing.add(
            '${table.name} ${jsonEncode(text)}\n'
            '  server ${jsonEncode(server)}\n'
            '  device ${jsonEncode(actual)}',
          );
        }
      }
    }
    // ignore: avoid_print -- the table's size, for the record
    print('suggest parity: $texts texts, $rows rows');
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

  // The store reads the row's category (public.guess_store, the category's
  // usual store and its dm or Baumarkt store), and the device reads its
  // guess: a row whose guess is not the server's category may get another
  // store, and those rows are pinned in suggest_parity_stores.dart. Every
  // other row gets the server's.
  for (final categoryStore in [false, true]) {
    test('the device gives every row the server store, '
        'p_category_store $categoryStore', () {
      var agree = 0;
      var rows = 0;
      final byCategory = <String>[];
      final differing = <String>[];
      for (final table in tables) {
        for (final (text, expected) in table.cases) {
          final actual = suggestEntries(
            text,
            catalog: table.catalog,
            household: household,
            categories: categories,
            known: known,
            pending: table.pending,
            categoryStore: categoryStore,
          );
          for (final (i, row) in expected.indexed) {
            rows++;
            final server = row! as List<Object?>;
            final device = actual[i].entry;
            final store = server[categoryStore ? 7 : 6];
            final line =
                '${table.name}|$text|${device.name}|$store|${device.storeId}';
            if (device.storeId == store) {
              agree++;
            } else if (device.categoryId != server[5]) {
              byCategory.add(line);
            } else {
              differing.add(line);
            }
          }
        }
      }
      // ignore: avoid_print -- the agreement, for the record
      print(
        'suggest parity stores (p_category_store $categoryStore): '
        '$agree of $rows rows agree, ${byCategory.length} differ with the '
        'category guess, ${differing.length} otherwise',
      );
      final pinned = {
        ...storeExceptions,
        if (categoryStore)
          ...categoryStoreExceptions
        else
          ...categoryStoreOffExceptions,
      };
      expect([
        for (final line in byCategory)
          if (!pinned.contains(line)) 'not pinned: $line',
        for (final line in pinned)
          if (!byCategory.contains(line)) 'agrees now, unpin: $line',
        for (final line in differing) 'same category: $line',
      ], isEmpty);
    });
  }
}

import 'dart:io';

import 'package:family_groceries/list/catalog/catalog_index.dart';
import 'package:family_groceries/list/catalog/household_index.dart';
import 'package:family_groceries/list/catalog/suggest_entries.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter_test/flutter_test.dart';

/// How long [suggestEntries] takes per key (job 274): every prefix of 60
/// lines typed against the bundled catalog and a household of 2,000
/// history rows. Prints p50, p95 and max. Runs only with SUGGEST_BENCH=1:
/// `SUGGEST_BENCH=1 flutter test test/list/suggest_bench_test.dart`.
void main() {
  test(
    'suggestEntries per key',
    skip: Platform.environment['SUGGEST_BENCH'] != '1',
    () {
      final catalog = CatalogIndex.bundled;
      final terms = catalog.terms.keys.toList();
      final brands = catalog.brands.values.map((b) => b.brand).toList();
      final start = DateTime.utc(2026, 11, 16);
      final history = <HistoryRow>[
        for (var i = 0; i < 2000; i++)
          (
            name: _capital(terms[(i * 7) % terms.length]),
            brand: i.isEven ? brands[(i * 13) % brands.length] : null,
            properties: i % 3 == 0 ? 'Bio, ${i % 9 + 1}er Pack' : null,
            quantity: i % 4 == 0 ? '${i % 5 + 1}' : null,
            normalizedName: normalizeItemName(terms[(i * 7) % terms.length]),
            at: start.subtract(Duration(minutes: i * 250)),
          ),
      ];
      final household = HouseholdIndex(history: history);
      final categories = Catalog(
        categories: [
          for (final (i, seed) in const [
            'produce', 'chilled', 'pantry', 'drinks', 'bakery', 'meat', //
            'frozen', 'sweets', 'household', 'drugstore', 'other',
          ].indexed)
            Category(id: seed, name: seed, sortOrder: i, seedKey: seed),
        ],
      );
      final lines = [
        ..._lines,
        for (var i = 0; i < 60 - _lines.length; i++)
          _capital(terms[(i * 31) % terms.length]),
      ];
      final times = <int>[];
      var rows = 0;
      var first = -1;
      for (final run in [1, 2]) {
        for (final line in lines) {
          for (var n = 1; n <= line.length; n++) {
            final watch = Stopwatch()..start();
            rows += suggestEntries(
              line.substring(0, n),
              catalog: catalog,
              household: household,
              categories: categories,
              known: const {},
            ).length;
            if (first < 0) {
              first = watch.elapsedMicroseconds;
            }
            if (run == 2) {
              times.add(watch.elapsedMicroseconds);
            }
          }
        }
      }
      times.sort();
      String ms(int us) => (us / 1000).toStringAsFixed(2);
      // ignore: avoid_print -- the benchmark's result
      print(
        'suggestEntries: ${times.length} keys, '
        'p50 ${ms(times[times.length ~/ 2])} ms, '
        'p95 ${ms(times[times.length * 95 ~/ 100])} ms, '
        'max ${ms(times.last)} ms; the first key, with the lookups, '
        '${ms(first)} ms; ${rows ~/ 2} rows per pass',
      );
      expect(rows, greaterThan(times.length * 2));
    },
  );
}

String _capital(String word) => word[0].toUpperCase() + word.substring(1);

const _lines = [
  '2 Weihenstephan Milch 1,5%', 'Windeln Größe 4', 'Rote Bete', //
  'Hafermilch Barista', 'Spülmittel Pril 2x', 'Kaffee ganze Bohne',
  'Joghurt Erdbeere 4er Pack', 'Toilettenpapier 3-lagig 16 Rollen',
  'Mineralwasser still 6x1,5 l', 'Schokolade Zartbitter', 'Hackfleisch 500 g',
  'Äpfel 1 kg bio', 'Karotten 2', 'zwei Liter Milch', 'Pampers Baby Dry',
];

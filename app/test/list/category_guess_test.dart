import 'dart:io';

import 'package:family_groceries/list/catalog/catalog_index.dart';
import 'package:family_groceries/list/catalog/catalog_index.g.dart';
import 'package:family_groceries/list/category_guess.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter_test/flutter_test.dart';

/// The `name<TAB>seed_key` rows of a table in supabase/classifier.
List<(String, String)> _table(String file) => [
  for (final line in File('../supabase/classifier/$file').readAsLinesSync())
    if (line.trim().isNotEmpty && !line.startsWith('#'))
      switch (line.split('\t')) {
        [final name, final seed] => (name, seed),
        _ => throw FormatException('not name<TAB>seed_key', line),
      },
];

/// A household with the ten grocery categories a new one gets and
/// Sonstiges, without the Baumarkt's.
final _groceries = Catalog(
  categories: [
    for (final (i, seed) in const [
      'produce',
      'bakery',
      'chilled',
      'meat',
      'pantry',
      'sweets',
      'drinks',
      'frozen',
      'household',
      'drugstore',
      'other',
    ].indexed)
      Category(id: 'c-$seed', name: seed, sortOrder: i, seedKey: seed),
  ],
);

final _at = DateTime.utc(2026, 11, 15);

Item _item(String name, String? categoryId, {DateTime? updatedAt}) => Item(
  id: name,
  name: name,
  categoryId: categoryId,
  status: ItemStatus.bought,
  createdAt: _at,
  updatedAt: updatedAt ?? _at,
);

/// What the guess gets right of [rows], with the rows it gets wrong.
(double, List<String>) _agreement(
  List<(String, String)> rows,
  String? Function(String name) guess,
  String? Function(String seed) expected,
) {
  final wrong = [
    for (final (name, seed) in rows)
      if (guess(name) case final got when got != expected(seed))
        '$name: $got, not ${expected(seed)}',
  ];
  return (1 - wrong.length / rows.length, wrong);
}

final _index = CatalogIndex.bundled;

String? _seed(String name) => lexiconSeed(name, _index);

void main() {
  // Measured on job 272's lexicon: dictionary.tsv 1617 of 1617 seed keys,
  // sweep.tsv 344 of 345 categories (Briefmarken, which the server files
  // under Sonstiges, stays unsorted on the device).
  test('every dictionary term gets its own seed key', () {
    final (agreement, wrong) = _agreement(
      _table('dictionary.tsv'),
      _seed,
      (seed) => seed,
    );
    expect(agreement, greaterThanOrEqualTo(0.99), reason: wrong.join('\n'));
  });

  for (final file in ['dictionary.tsv', 'sweep.tsv']) {
    test("$file sorts into the grocery household's categories", () {
      final (agreement, wrong) = _agreement(
        _table(file),
        (name) => guessCategory(
          name,
          catalog: _groceries,
          known: const {},
          index: _index,
        ),
        (seed) => switch (seed) {
          'other' => null,
          _ when hardwareSeedKeys.contains(seed) => 'c-household',
          _ => 'c-$seed',
        },
      );
      expect(agreement, greaterThanOrEqualTo(0.99), reason: wrong.join('\n'));
    });
  }

  test("the household's own category for a name beats the lexicon", () {
    expect(
      guessCategory(
        'milch',
        catalog: _groceries,
        known: householdCategories([
          _item('Milch', 'c-drinks', updatedAt: _at),
          _item(
            'Milch',
            'c-sweets',
            updatedAt: _at.add(const Duration(days: 1)),
          ),
          _item('Hafermilch', 'c-produce'),
          _item('Milch', null, updatedAt: _at.add(const Duration(days: 2))),
        ]),
        index: _index,
      ),
      'c-sweets',
      reason: 'the latest item by that name with a category',
    );
    expect(
      guessCategory(
        'Milch',
        catalog: _groceries,
        known: const {},
        index: _index,
      ),
      'c-chilled',
    );
  });

  test("a DIY word goes to Haushalt without the Baumarkt's categories", () {
    expect(
      guessCategory(
        'Kabelbinder',
        catalog: _groceries,
        known: const {},
        index: _index,
      ),
      'c-household',
    );
    final hardware = Catalog(
      categories: [
        ..._groceries.categories,
        const Category(
          id: 'c-electrical',
          name: 'Elektro',
          sortOrder: 20,
          seedKey: 'electrical',
        ),
      ],
    );
    expect(
      guessCategory(
        'Kabelbinder',
        catalog: hardware,
        known: const {},
        index: _index,
      ),
      'c-electrical',
    );
  });

  test('a word the lexicon does not know stays unsorted', () {
    expect(
      guessCategory(
        'Briefmarken',
        catalog: _groceries,
        known: const {},
        index: _index,
      ),
      isNull,
    );
    expect(
      guessCategory(
        'Milch',
        catalog: const Catalog(),
        known: const {},
        index: _index,
      ),
      isNull,
      reason: 'no category of that seed in the household',
    );
  });

  test('amounts and frozen markers read as the server reads them', () {
    expect(_seed('500 g Erbsen'), 'frozen');
    expect(_seed('TK Spinat'), 'frozen');
    expect(_seed('2 Liter Milch'), 'chilled');
    expect(_seed('Kräutertee'), 'pantry');
    expect(_seed('Fußcreme'), 'drugstore');
  });
}

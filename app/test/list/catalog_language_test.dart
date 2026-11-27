import 'dart:io';

import 'package:family_groceries/list/add_sheet/suggestion.dart';
import 'package:family_groceries/list/catalog/catalog_index.dart';
import 'package:family_groceries/list/catalog/catalog_index.g.dart';
import 'package:family_groceries/list/catalog/household_index.dart';
import 'package:family_groceries/list/catalog/suggest_entries.dart';
import 'package:family_groceries/list/category_guess.dart';
import 'package:flutter_test/flutter_test.dart';

/// Job 470: the catalog follows the app's language. English offers English
/// words, a language without words gets English (Peter, ML1), German keeps
/// its terms, and names sort into the same aisles whatever language they
/// are typed in.
void main() {
  final bundled = CatalogIndex.bundled;

  List<String> catalogRows(String text, String language) => [
    for (final (source, entry) in suggestRows(
      text,
      catalog: bundled,
      household: HouseholdIndex.empty,
      language: language,
    ))
      if (source == SuggestionSource.catalog) entry.name,
  ];

  Map<String, String> table(String path) => {
    for (final line in File(path).readAsLinesSync())
      if (line.isNotEmpty && !line.startsWith('#'))
        line.split('\t')[0]: line.split('\t')[1],
  };

  test('the catalog language is the app language when the catalog has it, '
      'else English, never German for another language', () {
    expect(bundled.languageFor('de'), 'de');
    expect(bundled.languageFor('en'), 'en');
    expect(bundled.languageFor('hu'), 'en');
    expect(bundled.languageFor('fr'), 'en');
    expect(catalogRows('mil', 'hu'), catalogRows('mil', 'en'));
  });

  test('English offers English words, written as an English list writes '
      'them, and no German term', () {
    final english = bundled.termsIn('en').keys.toSet();
    final germanOnly = bundled.terms.keys.toSet().difference(english);
    final expected = {
      'mil': 'Milk',
      'milk': null,
      'tomat': 'Tomatoes',
      'bana': 'Bananas',
      'peanut butt': 'Peanut butter',
      'organic peanut butt': 'Organic peanut butter',
      'eggpl': 'Eggplant',
      'aubergi': 'Aubergines',
      'kitch': 'Kitchen roll',
      '2 appl': 'Apples',
    };
    for (final MapEntry(key: text, value: row) in expected.entries) {
      final rows = catalogRows(text, 'en');
      if (row != null) {
        expect(rows, contains(row), reason: '"$text" offers $row: $rows');
      }
      for (final name in rows) {
        expect(
          germanOnly.contains(name.toLowerCase()),
          isFalse,
          reason: '"$text" offers the German term $name',
        );
        expect(
          english.any((word) => name.toLowerCase().endsWith(word)),
          isTrue,
          reason: '"$text" offers $name, no English word',
        );
      }
    }
    expect(catalogRows('mil', 'de'), contains('Milch'));
    expect(catalogRows('mil', 'en'), isNot(contains('Milch')));
  });

  test('an English phrase completes from its first words, and a word '
      'attaches to the words before it only as a phrase', () {
    final expected = {
      'toilet p': ['Toilet paper'],
      'toilet pap': ['Toilet paper'],
      'chicken br': ['Chicken breast'],
      'olive o': ['Olive oil'],
      'paper t': ['Paper towels'],
      'orange j': ['Orange juice'],
      'bell pep': ['Bell peppers'],
      'cat f': ['Cat food'],
      'tortilla ch': ['Tortilla chips'],
      'ice cr': ['Ice cream', 'Ice cream cake'],
      'dish so': ['Dish soap'],
      'kitchen ro': ['Kitchen roll'],
      '2 toilet p': ['Toilet paper'],
      'peanut butter': ['Peanut butter cups'],
      'oat milk': <String>[],
      'Milch': <String>[],
    };
    for (final MapEntry(key: text, value: rows) in expected.entries) {
      expect(catalogRows(text, 'en'), rows, reason: text);
    }
  });

  test("the German catalog is dictionary.tsv's terms, nothing else", () {
    final dictionary = table('../supabase/classifier/dictionary.tsv');
    expect(
      {for (final (term, _, category) in catalogTerms) term: category},
      {for (final MapEntry(:key, :value) in dictionary.entries) key: value},
    );
  });

  test('the English words are dictionary.en.tsv, each in its aisle', () {
    final words = table('../supabase/classifier/dictionary.en.tsv');
    expect({
      for (final MapEntry(key: _, value: w) in bundled.words.entries)
        if (w.lang == 'en') w.word: w.category,
    }, words);
  });

  test('the device files the English exam as the server does: never in '
      'a wrong aisle, and only typos wait for the server', () {
    // sweep.sh requires every row of the server; the device's guess has no
    // typo path (lexiconSeed), so a typo gets none and the server files it.
    final exam = table('../supabase/classifier/expected.en.tsv');
    expect(exam.length, greaterThanOrEqualTo(150));
    final guesses = {
      for (final text in exam.keys) text: lexiconSeed(text, bundled),
    };
    expect([
      for (final MapEntry(key: text, value: seed) in guesses.entries)
        if (seed != null && seed != exam[text])
          '$text: $seed, not ${exam[text]}',
    ], isEmpty);
    final unguessed = [
      for (final MapEntry(key: text, value: seed) in guesses.entries)
        if (seed == null) text,
    ];
    expect(
      unguessed.length,
      lessThanOrEqualTo(exam.length ~/ 20),
      reason: '$unguessed',
    );
  });

  test('a German and an English name of one product are one item', () {
    for (final (english, german) in [
      ('milk', 'Milch'),
      ('eggplant', 'Aubergine'),
      ('aubergine', 'Aubergine'),
      ('tomatoes', 'Tomate'),
      ('apples', 'Äpfel'),
    ]) {
      expect(
        canonicalKeyOf(english, bundled),
        canonicalKeyOf(german, bundled),
        reason: '$english, $german',
      );
    }
  });

  group('a catalog delta', () {
    CatalogDelta delta(Object? words, {bool full = false}) =>
        parseCatalogDelta({
          'version': '0123456789abcdef',
          'full': full,
          'terms': {'put': <Object?>[], 'drop': <Object?>[]},
          'forms': {'put': <Object?>[], 'drop': <Object?>[]},
          'brands': {'put': <Object?>[], 'drop': <Object?>[]},
          'words': ?words,
        })!;

    test('puts and drops words', () {
      final next = bundled.apply(
        delta({
          'put': [
            ['en:zwurbelquix', 'zwurbelquix', 'produce', true],
          ],
          'drop': ['en:milk'],
        }),
      );
      expect(next.termsIn('en').keys, contains('zwurbelquix'));
      expect(next.termsIn('en').keys, isNot(contains('milk')));
      expect(next.terms, bundled.terms);
    });

    test('without words keeps the words, also in a full answer', () {
      expect(bundled.apply(delta(null)).words, bundled.words);
      final full = bundled.apply(delta(null, full: true));
      expect(full.words, bundled.words);
      expect(full.terms, isEmpty);
    });

    test('with one bad word row is refused whole', () {
      Object? answer(List<Object?> row) => {
        'version': '0123456789abcdef',
        'full': false,
        'words': {
          'put': [row],
          'drop': <Object?>[],
        },
      };
      expect(
        parseCatalogDelta(answer(['milk', 'milk', 'chilled', false])),
        isNull,
      );
      expect(parseCatalogDelta(answer(['en:milk', 'milk', 'chilled'])), isNull);
      expect(
        parseCatalogDelta(answer(['en:milk', 'milk', 'chilled', false])),
        isNotNull,
      );
    });
  });
}

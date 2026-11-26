import 'package:family_groceries/list/add_sheet/suggestion.dart';
import 'package:family_groceries/list/catalog/catalog_index.dart';
import 'package:family_groceries/list/catalog/household_index.dart';
import 'package:family_groceries/list/catalog/suggest_entries.dart';
import 'package:flutter_test/flutter_test.dart';

HistoryRow _bought(
  String name, {
  required int day,
  String? brand,
  String? properties,
}) => (
  name: name,
  brand: brand,
  properties: properties,
  quantity: null,
  normalizedName: normalizeItemName(name),
  at: DateTime.utc(2026, 11, day),
);

/// The add sheet's rows on the device (job 274) as public.suggest_entries
/// orders them: history by match tier, then similarity from the "holds it"
/// tier on, then recency; one brand row per brand key, the household's
/// latest spelling first; details and sizes next to what was typed.
void main() {
  List<String> texts(
    String text,
    List<HistoryRow> history,
    SuggestionSource only,
  ) => [
    for (final (source, entry) in suggestRows(
      text,
      catalog: CatalogIndex.bundled,
      household: HouseholdIndex(history: history),
    ))
      if (source == only)
        [entry.name, ?entry.brand, ?entry.properties].join(' · '),
  ];

  test('a name starting with the text ranks before one holding it, however '
      'recent; within holding it, the closer name first', () {
    final history = [
      _bought('Hafermilch Barista Edition', day: 9),
      _bought('Frische Vollmilch', day: 1),
      _bought('Milchreis', day: 2),
    ];
    expect(texts('milch', history, SuggestionSource.history), [
      'Milchreis',
      'Frische Vollmilch',
      'Hafermilch Barista Edition',
    ]);
  });

  test('a brand bought under two spellings offers the latest, whatever '
      'order the history comes in', () {
    for (final (older, newer) in [
      ('weihenstephan', 'Weihenstephan'),
      ('Weihenstephan', 'weihenstephan'),
    ]) {
      final history = [
        _bought('Milch', brand: older, properties: 'laktosefrei', day: 1),
        _bought('Milch', brand: newer, properties: 'bio', day: 5),
      ];
      for (final order in [history, history.reversed.toList()]) {
        expect(texts('Milch', order, SuggestionSource.brand), [
          'Milch · $newer',
        ]);
      }
    }
  });

  test("the household's spelling of a catalog brand wins and comes first", () {
    final history = [
      _bought('Kaffee', brand: 'DALLMAYR', properties: 'gemahlen', day: 1),
    ];
    final brands = texts('kaffee', history, SuggestionSource.brand);
    expect(brands.first, 'kaffee · DALLMAYR');
    expect(brands, isNot(contains('kaffee · Dallmayr')));
  });

  test('a detail bought again counts from its latest purchase', () {
    final again = [
      _bought('Milch', brand: 'A', properties: 'bio', day: 1),
      _bought('Milch', brand: 'B', properties: 'laktosefrei', day: 2),
      _bought('Milch', brand: 'C', properties: 'bio', day: 3),
    ];
    for (final order in [again, again.reversed.toList()]) {
      expect(texts('Milch', order, SuggestionSource.variant), [
        'Milch · bio',
        'Milch · laktosefrei',
      ]);
    }
    expect(texts('Milch', again.sublist(0, 2), SuggestionSource.variant), [
      'Milch · laktosefrei',
      'Milch · bio',
    ]);
  });

  test('sizes offer their neighbours from 1 to 8', () {
    expect(texts('Windeln Größe 7', [], SuggestionSource.size), [
      'Windeln · Größe 8',
      'Windeln · Größe 6',
    ]);
    expect(texts('Windeln Größe 8', [], SuggestionSource.size), [
      'Windeln · Größe 7',
    ]);
    expect(texts('Windeln Größe 1', [], SuggestionSource.size), [
      'Windeln · Größe 2',
    ]);
  });
}

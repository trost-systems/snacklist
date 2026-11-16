import 'dart:convert';

import 'package:family_groceries/list/catalog/household_index.dart';
import 'package:flutter_test/flutter_test.dart';

// As public.suggest_index writes it: timestamptz in jsonb, nulls as null.
const _answer = '''
{
  "history": [
    ["Milch", "Weihenstephan", "1,5 %", "2", "milch", "2026-11-16T01:38:20.746118+00:00"],
    ["Äpfel", null, null, null, "aepfel", "2026-01-01T00:00:00+00:00"]
  ],
  "brands": [["Hofgut", "hofgut"]],
  "unserved": ["paint", "tools"],
  "known": ["butter", "aepfel"],
  "memory": [["milch", "milch", "s-dm"], ["kaffe", null, "s-krume"]],
  "cleared": ["brot"],
  "stores": [["dm", "s-dm"]],
  "categories": [["c-drugstore", null, "s-dm"], ["c-chilled", "s-krume", null]]
}''';

/// An index cached before job 274's review added the store keys.
const _cachedBeforeStores = '''
{"history": [], "brands": [], "unserved": [], "known": ["butter"]}''';

void main() {
  test('the answer becomes typed rows', () {
    final index = HouseholdIndex.fromJson(jsonDecode(_answer))!;
    expect(index.history, hasLength(2));
    final milk = index.history.first;
    expect(milk.name, 'Milch');
    expect(milk.brand, 'Weihenstephan');
    expect(milk.properties, '1,5 %');
    expect(milk.quantity, '2');
    expect(milk.normalizedName, 'milch');
    expect(milk.at, DateTime.utc(2026, 11, 16, 1, 38, 20, 746, 118));
    expect(index.history.last.brand, isNull);
    expect(index.brands.single, (brand: 'Hofgut', key: 'hofgut'));
    expect(index.unserved, ['paint', 'tools']);
    expect(index.known, ['butter', 'aepfel']);
    expect(index.memory, [
      (itemKey: 'milch', canonicalKey: 'milch', storeId: 's-dm'),
      (itemKey: 'kaffe', canonicalKey: null, storeId: 's-krume'),
    ]);
    expect(index.cleared, ['brot']);
    expect(index.stores, [(seedKey: 'dm', storeId: 's-dm')]);
    expect(index.categories, [
      (categoryId: 'c-drugstore', usual: null, seeded: 's-dm'),
      (categoryId: 'c-chilled', usual: 's-krume', seeded: null),
    ]);
  });

  test('an index cached without the store keys reads them as empty', () {
    final index = HouseholdIndex.fromJson(jsonDecode(_cachedBeforeStores))!;
    expect(index.known, ['butter']);
    expect(index.memory, isEmpty);
    expect(index.cleared, isEmpty);
    expect(index.stores, isEmpty);
    expect(index.categories, isEmpty);
  });

  test('what it writes it reads back the same', () {
    final index = HouseholdIndex.fromJson(jsonDecode(_answer))!;
    final again = HouseholdIndex.fromJson(
      jsonDecode(jsonEncode(index.toJson())),
    )!;
    expect(again.history, index.history);
    expect(again.brands, index.brands);
    expect(again.unserved, index.unserved);
    expect(again.known, index.known);
    expect(again.memory, index.memory);
    expect(again.cleared, index.cleared);
    expect(again.stores, index.stores);
    expect(again.categories, index.categories);
    expect(HouseholdIndex.fromJson(HouseholdIndex.empty.toJson()), isNotNull);
  });

  test('one bad row rejects the answer', () {
    Map<String, Object?> answer() =>
        jsonDecode(_answer) as Map<String, Object?>;
    for (final (i, bad) in <Object?>[
      null,
      'history',
      answer()..remove('known'),
      answer()
        ..['history'] = [
          ['Milch', null, null, null, 'milch', 'yesterday'],
        ],
      answer()
        ..['history'] = [
          ['Milch', null, null, null, 'milch'],
        ],
      answer()
        ..['history'] = [
          [null, null, null, null, 'milch', '2026-01-01T00:00:00Z'],
        ],
      answer()
        ..['brands'] = [
          ['Hofgut'],
        ],
      answer()..['unserved'] = [''],
      answer()..['known'] = [1],
      answer()..['known'] = ['x' * 301],
      answer()..['known'] = List.filled(20001, 'milch'),
      answer()..['memory'] = 'milch',
      answer()
        ..['memory'] = [
          ['milch', 'milch'],
        ],
      answer()
        ..['memory'] = [
          ['milch', 'milch', ''],
        ],
      answer()..['cleared'] = [null],
      answer()
        ..['stores'] = [
          ['dm', null],
        ],
      answer()
        ..['categories'] = [
          ['c', 1, null],
        ],
    ].indexed) {
      expect(HouseholdIndex.fromJson(bad), isNull, reason: 'case $i');
    }
  });
}

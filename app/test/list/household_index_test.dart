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
  "known": ["butter", "aepfel"]
}''';

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
    ].indexed) {
      expect(HouseholdIndex.fromJson(bad), isNull, reason: 'case $i');
    }
  });
}

import 'dart:io';

import 'package:family_groceries/list/model.dart';

/// The frozen hc-suggest-cpu workload (seed 131,
/// `tool/hillclimb/hc-suggest-cpu/gen_fixture.py`).
final class SuggestFixture._(
  final List<Usual> usuals,
  final List<Item> onList,
  final List<String> queries,
) {
  factory load() {
    List<String> lines(String file) =>
        File('test/list/suggest_fixture/$file')
            .readAsLinesSync()
            .where((l) => l.isNotEmpty)
            .toList();
    final at = DateTime.utc(2026, 11);
    final names = lines('catalog.txt');
    return SuggestFixture._(
      [
        for (final (i, name) in names.indexed)
          Usual(
            name: name,
            due: i % 7 == 0,
            quantity: i % 5 == 0 ? '${i % 4 + 1}' : null,
            lastUsed: at.subtract(Duration(hours: i)),
          ),
      ],
      [
        for (final (i, name) in lines('on_list.txt').indexed)
          Item(
            id: 'on-list-$i',
            name: name,
            status: ItemStatus.active,
            createdAt: at,
            updatedAt: at,
          ),
      ],
      lines('queries.txt'),
    );
  }

  /// Each query's top [limit] names; 5 is what the add sheet shows offline.
  Map<String, List<String>> ranked({int limit = 5}) => {
    for (final query in queries)
      query: [
        for (final usual in suggestUsuals(usuals, onList, query, limit: limit))
          usual.name,
      ],
  };
}

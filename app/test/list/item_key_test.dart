import 'dart:io';

import 'package:family_groceries/list/entry.dart';
import 'package:flutter_test/flutter_test.dart';

/// Job 470: itemKey and foldKey write supabase/tests/item_keys.tsv as
/// public.item_key and public.fold_key do: German, English, and the letters
/// of other languages folded, never splitting a word.
void main() {
  test('itemKey and foldKey are the server keys of item_keys.tsv', () {
    final rows = [
      for (final line in File(
        '../supabase/tests/item_keys.tsv',
      ).readAsLinesSync())
        if (line.isNotEmpty && !line.startsWith('#')) line.split('\t'),
    ];
    expect(rows.length, greaterThan(30));
    expect([
      for (final [name, ..._] in rows)
        [name, itemKey(name), foldKey(itemKey(name))],
    ], rows);
  });
}

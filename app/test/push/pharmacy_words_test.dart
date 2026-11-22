import 'dart:convert';
import 'dart:io';

import 'package:family_groceries/list/model.dart';
import 'package:flutter_test/flutter_test.dart';

/// The words of [Store.pharmacyWords] are the file the server's pin reads
/// too (`supabase/functions/_shared/pharmacy_words_test.ts` checks them
/// against `push_item_sensitive`, Legal N-423).
void main() {
  test('Store.pharmacyWords are the words of pharmacy_words.json', () {
    final words = (jsonDecode(
      File('../supabase/tests/pharmacy_words.json').readAsStringSync(),
    ) as List<Object?>).cast<String>();

    expect([...words]..sort(), [...Store.pharmacyWords]..sort());
  });
}

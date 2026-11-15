import 'package:flutter_test/flutter_test.dart';

import '../l10n/arb_parity_test.dart' show messageKeys, readArb;

/// Job 199: the English grocery log calls one visit to a store a "trip",
/// never a "shop", which reads as the store itself.
void main() {
  test('every English grocery-log string says trip, not shop', () {
    final en = readArb('l10n/app_en.arb');
    final log = messageKeys(en)
        .where((k) => k.startsWith('trip') || k.startsWith('history'));
    expect(log, contains('tripAdd'));
    final shop = RegExp(r'\bshops?\b', caseSensitive: false);
    expect({
      for (final k in log)
        if (shop.hasMatch('${en[k]}')) k: en[k],
    }, isEmpty);
  });
}

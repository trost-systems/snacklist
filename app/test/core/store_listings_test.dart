import 'dart:io';

import 'package:family_groceries/core/store_listings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Job 271: the web app's „Öffnen“ card and the join page link the same
/// listings, and only public ones; join.js decides.
void main() {
  final js = File('web/join/join.js').readAsStringSync();

  String constant(String name) {
    final match = RegExp('const $name = (.+);').firstMatch(js);
    expect(match, isNotNull, reason: 'web/join/join.js has no const $name');
    return match![1]!;
  }

  test('store_listings.dart mirrors web/join/join.js', () {
    final listings = RegExp(
      r'^\{ appStore: (true|false), googlePlay: (true|false) \}$',
    ).firstMatch(constant('storeListings'));
    expect(listings, isNotNull, reason: 'storeListings changed its shape');
    expect(
      (appStore: listings![1] == 'true', googlePlay: listings[2] == 'true'),
      storeListings,
      reason: 'storeListings differs between join.js and store_listings.dart',
    );
    expect(constant('appStoreId'), "'$appStoreId'");
    expect(constant('playPackage'), "'$playPackage'");
  });
}

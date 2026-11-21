import 'dart:convert';

import 'package:family_groceries/list/list_cache.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/retailer.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

const lidlPlus = RetailerApp(
  name: 'Lidl Plus',
  android: 'com.lidl.eci.lidlplus',
  ios: '1238611143',
);
const billa = RetailerApp(name: 'BILLA', android: 'at.billa', ios: '111');
const joe = RetailerApp(
  name: 'jö',
  android: 'at.joe',
  ios: '222',
  universalLink: 'https://www.joe-club.at/app',
);

/// Job 313: stores linked to a chain, as the server's embed and the
/// device copy carry them.
void main() {
  test('a store row with its chain reads as the server sends it', () {
    final store = Store.fromJson({
      'id': 's1',
      'name': 'Billa ums Eck',
      'sort_order': 10,
      'seed_key': null,
      'retailer_app': 'at.joe',
      'retailer_answered': true,
      'retailer': {
        'chain': 'billa',
        'country': 'AT',
        'name': 'BILLA',
        'apps': [billa.toJson(), joe.toJson()],
      },
    });
    expect(store.retailer?.key, (chain: 'billa', country: 'AT'));
    expect(store.retailerAnswered, isTrue);
    expect(store.app?.name, 'jö');
    expect(store.app?.universalLink, 'https://www.joe-club.at/app');
  });

  test('a linked store survives the device copy unchanged', () {
    const store = Store(
      id: 's1',
      name: 'Billa',
      sortOrder: 10,
      retailer: Retailer(
        chain: 'billa',
        country: 'AT',
        name: 'BILLA',
        apps: [billa, joe],
      ),
      retailerApp: 'at.joe',
      retailerAnswered: true,
    );
    const snapshot = ListSnapshot(
      catalog: Catalog(stores: [store]),
      server: [],
      pending: [],
    );
    final json = jsonEncode(snapshot.toJson());
    final back = ListSnapshot.fromJson(jsonDecode(json) as Map<String, Object?>)
        .catalog
        .stores
        .single;
    expect(back.toJson(), store.toJson());
    expect(back.app?.android, 'at.joe');
  });

  test('a device copy from before chains reads as unlinked, unanswered', () {
    final store = Store.fromJson(const {
      'id': 'dm',
      'name': 'dm',
      'sort_order': 10,
      'seed_key': 'dm',
    });
    expect(store.retailer, isNull);
    expect(store.retailerApp, isNull);
    expect(store.retailerAnswered, isFalse);
    expect(store.app, isNull);
  });

  group("the store's app", () {
    Store linked(List<RetailerApp> apps, {String? picked}) => Store(
      id: 's',
      name: 'Billa',
      sortOrder: 10,
      retailer: Retailer(
        chain: 'billa',
        country: 'AT',
        name: 'BILLA',
        apps: apps,
      ),
      retailerApp: picked,
    );

    test('is the picked one', () {
      expect(linked([billa, joe], picked: 'at.joe').app, joe);
    });

    test("is the chain's first without a pick", () {
      expect(linked([billa, joe]).app, billa);
    });

    test("is the chain's first when the pick is no longer listed", () {
      expect(linked([billa, joe], picked: 'at.gone').app, billa);
    });

    test('is none for a chain without an app, or no chain', () {
      expect(linked([]).app, isNull);
      expect(
        const Store(id: 's', name: 'Wochenmarkt', sortOrder: 10).app,
        isNull,
      );
    });
  });

  test('an app entry without its store ids is left out, not fatal', () {
    final retailer = Retailer.fromJson({
      'chain': 'lidl',
      'country': 'DE',
      'name': 'Lidl',
      'apps': [
        const {'name': 'Broken', 'android': 'x'},
        'nonsense',
        lidlPlus.toJson(),
      ],
    });
    expect(retailer.apps.map((a) => a.android), [lidlPlus.android]);
  });

  test('a scheme comes through; one that is no bare scheme counts as '
      'none', () {
    RetailerApp? parse(Object? scheme) =>
        RetailerApp.tryParse({...lidlPlus.toJson(), 'scheme': scheme});
    expect(parse('lidlplus')?.scheme, 'lidlplus');
    expect(RetailerApp.tryParse(lidlPlus.toJson())?.scheme, isNull);
    for (final bad in ['', 'lidlplus://', 'Lidl Plus', '1app', 7]) {
      expect(parse(bad)?.scheme, isNull, reason: '$bad');
    }
  });

  test('an empty universal link counts as none', () {
    final app = RetailerApp.tryParse({
      ...lidlPlus.toJson(),
      'universalLink': '',
    });
    expect(app?.universalLink, isNull);
  });

  test('a prefix match names the store after the chain, an exact one keeps '
      'the typed name', () {
    const lidl = Retailer(chain: 'lidl', country: 'DE', name: 'Lidl');
    expect(const RetailerMatch(lidl, exact: false).storeName('Li'), 'Lidl');
    expect(
      const RetailerMatch(lidl, exact: true).storeName(' Lidl am Markt '),
      'Lidl am Markt',
    );
  });

  test('question rows group per store, in their order', () {
    Map<String, Object?> row(String store, String chain) => {
      'store_id': store,
      'chain': chain,
      'country': 'DE',
      'name': chain,
      'apps': [lidlPlus.toJson()],
    };
    final questions = StoreQuestion.group([
      row('s2', 'aldi-nord'),
      row('s1', 'lidl'),
      row('s2', 'aldi-sued'),
    ]);
    expect(
      [
        for (final q in questions)
          '${q.storeId}: ${[for (final c in q.chains) c.chain].join(', ')}',
      ],
      ['s2: aldi-nord, aldi-sued', 's1: lidl'],
    );
  });

  group('the phone region', () {
    for (final (locale, region) in [
      (const Locale('de', 'AT'), 'AT'),
      (const Locale('de', 'DE'), 'DE'),
      (const Locale('en', 'US'), 'DE'),
      (const Locale('en'), 'DE'),
    ]) {
      testWidgets('$locale ranks the chains of $region first', (tester) async {
        tester.platformDispatcher.localeTestValue = locale;
        addTearDown(tester.platformDispatcher.clearLocaleTestValue);
        expect(phoneRegion(), region);
      });
    }
  });
}

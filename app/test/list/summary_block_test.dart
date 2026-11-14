import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/app/router.dart' show listPath;
import 'package:family_groceries/list/list_view/item_row.dart';
import 'package:family_groceries/list/list_view/price_views.dart';
import 'package:family_groceries/list/list_view/summary_block.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/pricing.dart';
import 'package:family_groceries/trip/trip_cubit.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../design/fonts.dart';
import '../trip/list_trip_widget_test.dart' show pumpList;
import 'fake_repository.dart';

const _nbsp = ' ';
const _flags = {listDeclutterFlag, pricesFlag, tripModeFlag};
const _market = 'Wochenmarkt am Kollwitzplatz (Samstag)';

Price _price(int cents, {PricePer per = PricePer.piece}) => Price(
  unitMicros: cents * microsPerCent,
  basis: PriceBasis.unit,
  per: per,
  currency: 'EUR',
  pricedAt: DateTime.now(),
);

/// dm: Seife 0,95 €; Lidl: Milch 1,19 €, Brot 2,49 €, Käse without a
/// price; no store: Pinsel 3,00 €; Kaffee ticked before, under „Zuletzt
/// verwendet“.
void _seed(FakeRepository repo) => repo
  ..remoteAdd(
    'Kaffee',
    storeId: 'lidl',
    price: _price(499),
    status: ItemStatus.bought,
  )
  ..remoteAdd('Seife', storeId: 'dm', price: _price(95))
  ..remoteAdd('Milch', storeId: 'lidl', price: _price(119))
  ..remoteAdd('Brot', storeId: 'lidl', price: _price(249))
  ..remoteAdd('Käse', storeId: 'lidl')
  ..remoteAdd('Pinsel', price: _price(300));

/// Job 237, ST3 behind `list-declutter`: the block above „Zuletzt
/// verwendet“ with a line per store and „Gesamt“, Peter's rules (t874u).
void main() {
  setUpAll(loadAppFonts);
  setUp(
    () => VisibilityDetectorController.instance.updateInterval = Duration.zero,
  );

  Finder key(String k) => find.byKey(ValueKey(k));
  Finder row(String name) =>
      find.byWidgetPredicate((w) => w is ItemRow && w.item.name == name);
  final block = find.byType(SummaryBlock);

  String? text(WidgetTester tester, String k) =>
      switch (tester.widget<Text>(key(k))) {
        Text(:final data?) => data,
        Text(:final textSpan) => textSpan?.toPlainText(),
      };

  Future<void> toBlock(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      block,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  Future<void> tick(WidgetTester tester, String name) async {
    await tester.ensureVisible(row(name));
    await tester.pumpAndSettle();
    await tester.tap(row(name));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  testWidgets('a line per store with its subtotal, „Ohne Laden“ its own, '
      'then Gesamt; unpriced items make a floor', (tester) async {
    await pumpList(tester, flags: _flags, seed: _seed);
    await toBlock(tester);
    expect(find.text('EINKAUFSSUMME'), findsOneWidget);
    expect(text(tester, 'subtotal-amount-dm'), '0,95$_nbsp€');
    expect(text(tester, 'subtotal-amount-lidl'), 'mind. 3,68$_nbsp€');
    expect(text(tester, 'subtotal-amount-none'), '3,00$_nbsp€');
    expect(text(tester, 'total-amount'), 'mind. 7,63$_nbsp€');
    expect(
      find.descendant(
        of: key('subtotal-lidl'),
        matching: find.text('1 ohne Preis'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: key('subtotal-none'),
        matching: find.text('Ohne Laden'),
      ),
      findsOneWidget,
    );
    expect(find.text('Gesamt'), findsOneWidget);
    expect(find.text('4 mit Preis · 1 offen'), findsOneWidget);
    final lines = [
      for (final k in ['subtotal-dm', 'subtotal-lidl', 'subtotal-none'])
        tester.getRect(key(k)),
    ];
    expect(lines[0].bottom, lessThanOrEqualTo(lines[1].top));
    expect(lines[1].bottom, lessThanOrEqualTo(lines[2].top));
    expect(
      lines[2].bottom,
      lessThanOrEqualTo(tester.getRect(key('total-bar')).top),
    );
    expect(
      tester.getRect(block).bottom,
      lessThanOrEqualTo(tester.getRect(key('recently-used')).top),
    );
    // No section foot under ST3: the sums sit in the block only.
    expect(find.byType(StoreSubtotal), findsNothing);
    expect(find.byType(TotalBar), findsNothing);
  });

  testWidgets('every price set: no floor', (tester) async {
    await pumpList(
      tester,
      flags: _flags,
      seed: (repo) => repo
        ..remoteAdd('Seife', storeId: 'dm', price: _price(95))
        ..remoteAdd('Milch', storeId: 'lidl', price: _price(119)),
    );
    await toBlock(tester);
    expect(text(tester, 'subtotal-amount-lidl'), '1,19$_nbsp€');
    expect(text(tester, 'total-amount'), '2,14$_nbsp€');
  });

  testWidgets('one store: no store lines, only the total', (tester) async {
    await pumpList(
      tester,
      flags: _flags,
      seed: (repo) => repo
        ..remoteAdd('Milch', storeId: 'lidl', price: _price(119))
        ..remoteAdd('Brot', storeId: 'lidl', price: _price(249)),
    );
    await toBlock(tester);
    expect(key('subtotal-lidl'), findsNothing);
    expect(find.text('EINKAUFSSUMME'), findsNothing);
    expect(find.text('Einkaufssumme'), findsOneWidget);
    expect(text(tester, 'total-amount'), '3,68$_nbsp€');
  });

  testWidgets('only „Ohne Laden“: one group, only the total', (tester) async {
    await pumpList(
      tester,
      flags: _flags,
      seed: (repo) => repo..remoteAdd('Pinsel', price: _price(300)),
    );
    await toBlock(tester);
    expect(key('subtotal-none'), findsNothing);
    expect(text(tester, 'total-amount'), '3,00$_nbsp€');
  });

  testWidgets('a price per kg on the planned weight reads „≈“ on its row, '
      'its store and the total, until it is ticked', (tester) async {
    await pumpList(
      tester,
      flags: _flags,
      seed: (repo) => repo
        ..remoteAdd(
          'Bananen',
          storeId: 'lidl',
          quantity: '846 g',
          price: _price(179, per: PricePer.kg),
        )
        ..remoteAdd('Seife', storeId: 'dm', price: _price(95)),
    );
    final chip = find.descendant(
      of: row('Bananen'),
      matching: find.byType(PriceChip),
    );
    expect(
      find.descendant(of: chip, matching: find.text('≈ 1,51$_nbsp€')),
      findsWidgets,
    );
    await toBlock(tester);
    expect(text(tester, 'subtotal-amount-lidl'), '≈ 1,51$_nbsp€');
    expect(text(tester, 'subtotal-amount-dm'), '0,95$_nbsp€');
    expect(text(tester, 'total-amount'), '≈ 2,46$_nbsp€');

    // Ticked on a trip, it is in the cart: no estimate any more.
    await tick(tester, 'Bananen');
    await tester.tap(key('trip-ask-yes'));
    await tester.pumpAndSettle();
    await toBlock(tester);
    expect(text(tester, 'subtotal-amount-lidl'), '1,51$_nbsp€');
    expect(text(tester, 'total-amount'), '2,46$_nbsp€');
    expect(find.textContaining('≈'), findsNothing);
  });

  testWidgets('a floor and an estimate together: „mind. ≈“', (tester) async {
    await pumpList(
      tester,
      flags: _flags,
      seed: (repo) => repo
        ..remoteAdd(
          'Bananen',
          storeId: 'lidl',
          quantity: '846 g',
          price: _price(179, per: PricePer.kg),
        )
        ..remoteAdd('Käse', storeId: 'lidl'),
    );
    await toBlock(tester);
    expect(text(tester, 'total-amount'), 'mind. ≈ 1,51$_nbsp€');
  });

  group('no trip', () {
    testWidgets('a tick takes the item out of the sums (Nein, nur '
        'abgehakt)', (tester) async {
      final shop = await pumpList(tester, flags: _flags, seed: _seed);
      await tick(tester, 'Milch');
      await tester.tap(key('trip-ask-no'));
      await tester.pumpAndSettle();
      expect(shop.trips.state, isA<NoTrip>());
      await toBlock(tester);
      expect(text(tester, 'subtotal-amount-lidl'), 'mind. 2,49$_nbsp€');
      expect(text(tester, 'total-amount'), 'mind. 6,44$_nbsp€');
      expect(find.textContaining('gekauft'), findsNothing);
    });

    testWidgets('trip-mode off: a tick never splits, the sums drop it', (
      tester,
    ) async {
      final shop = await pumpList(
        tester,
        flags: const {listDeclutterFlag, pricesFlag},
        seed: _seed,
      );
      await tick(tester, 'Seife');
      expect(find.text('Kaufst du gerade ein?'), findsNothing);
      expect(shop.trips.state, isA<NoTrip>());
      await toBlock(tester);
      expect(key('subtotal-dm'), findsNothing, reason: 'nothing open at dm');
      expect(text(tester, 'total-amount'), 'mind. 6,68$_nbsp€');
      expect(find.textContaining('gekauft'), findsNothing);
    });
  });

  group('while a trip runs', () {
    testWidgets('each line splits bought and open; a store bought in full '
        'stays, marked „alles gekauft“', (tester) async {
      final shop = await pumpList(tester, flags: _flags, seed: _seed);
      await tick(tester, 'Seife');
      await tester.tap(key('trip-ask-yes'));
      await tester.pumpAndSettle();
      expect(shop.trips.state, isA<Running>());
      await tick(tester, 'Milch');
      await toBlock(tester);

      // dm: everything bought on the trip.
      expect(text(tester, 'subtotal-amount-dm'), '0,95$_nbsp€');
      expect(
        find.descendant(
          of: key('subtotal-dm'),
          matching: find.textContaining('alles gekauft'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: key('subtotal-dm'),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(key('subtotal-dm')),
        isSemantics(isButton: false, hasTapAction: false),
        reason: 'no section to go to',
      );
      // Lidl: Milch bought, Brot and Käse open.
      expect(text(tester, 'subtotal-amount-lidl'), 'mind. 3,68$_nbsp€');
      expect(
        find.descendant(
          of: key('subtotal-lidl'),
          matching: find.text(
            '1,19$_nbsp€ gekauft · 2,49$_nbsp€ offen · 1 ohne Preis',
          ),
        ),
        findsOneWidget,
      );
      // The total: everything on the list, bought on the trip or open.
      expect(text(tester, 'total-amount'), 'mind. 7,63$_nbsp€');
      expect(
        find.text('2,14$_nbsp€ gekauft · 5,49$_nbsp€ offen · 1 ohne Preis'),
        findsOneWidget,
      );
    });

    testWidgets('open items without a price: no „0,00 € offen“, the count '
        'says it', (tester) async {
      await pumpList(
        tester,
        flags: _flags,
        seed: (repo) => repo
          ..remoteAdd('Seife', storeId: 'dm', price: _price(95))
          ..remoteAdd('Käse', storeId: 'lidl'),
      );
      await tick(tester, 'Seife');
      await tester.tap(key('trip-ask-yes'));
      await tester.pumpAndSettle();
      await toBlock(tester);
      expect(text(tester, 'total-amount'), 'mind. 0,95$_nbsp€');
      expect(find.text('0,95$_nbsp€ gekauft · 1 ohne Preis'), findsOneWidget);
    });

    testWidgets('a trip on another list of the household splits nothing '
        'here', (tester) async {
      final shop = await pumpList(
        tester,
        flags: _flags,
        seed: (repo) {
          repo.lists = const [
            HouseholdList(id: 'weekly', name: 'Wocheneinkauf', position: 0),
            HouseholdList(id: 'diy', name: 'Baumarkt', position: 1),
          ];
          _seed(repo);
          repo
            ..remoteAdd('Schrauben', listId: 'diy', price: _price(450))
            ..remoteAdd('Dübel', listId: 'diy', price: _price(199));
        },
      );
      await tick(tester, 'Seife');
      await tester.tap(key('trip-ask-yes'));
      await tester.pumpAndSettle();
      expect(shop.trips.state, isA<Running>());
      shop.list.showList('diy');
      await tester.pumpAndSettle();
      await tick(tester, 'Schrauben');
      await toBlock(tester);
      expect(text(tester, 'total-amount'), '1,99$_nbsp€');
      expect(find.textContaining('gekauft'), findsNothing);
    });

    testWidgets('after the trip ends, ticked items drop out again', (
      tester,
    ) async {
      final shop = await pumpList(tester, flags: _flags, seed: _seed);
      await tick(tester, 'Seife');
      await tester.tap(key('trip-ask-yes'));
      await tester.pumpAndSettle();
      await toBlock(tester);
      expect(text(tester, 'total-amount'), 'mind. 7,63$_nbsp€');
      await shop.trips.finish();
      await tester.pumpAndSettle();
      shop.router.go(listPath);
      await tester.pumpAndSettle();
      expect(shop.trips.state, isNot(isA<Running>()));
      await toBlock(tester);
      expect(text(tester, 'total-amount'), 'mind. 6,68$_nbsp€');
      expect(find.textContaining('gekauft'), findsNothing);
    });
  });

  testWidgets('a tap on a store line brings its section under the header', (
    tester,
  ) async {
    await pumpList(
      tester,
      flags: _flags,
      seed: (repo) {
        for (var i = 0; i < 8; i++) {
          repo.remoteAdd('Seife $i', storeId: 'dm', price: _price(95));
        }
        for (var i = 0; i < 8; i++) {
          repo.remoteAdd('Milch $i', storeId: 'lidl', price: _price(119));
        }
      },
    );
    await toBlock(tester);
    expect(
      tester.getSemantics(key('subtotal-lidl')),
      isSemantics(
        label: 'Lidl, 9,52$_nbsp€',
        hint: 'Zum Laden in der Liste',
        isButton: true,
        hasTapAction: true,
      ),
    );
    await tester.tap(key('subtotal-lidl'));
    await tester.pumpAndSettle();
    final divider = tester.getRect(key('store-lidl'));
    final header = tester.getRect(key('list-header'));
    expect(divider.top, greaterThanOrEqualTo(header.bottom - 1));
    expect(divider.top, lessThan(header.bottom + 24), reason: '$divider');
  });

  testWidgets('a tap on the line of a folded store unfolds it', (tester) async {
    final shop = await pumpList(tester, flags: _flags, seed: _seed);
    shop.list.toggleFold('lidl');
    await tester.pumpAndSettle();
    expect(row('Milch'), findsNothing);
    await toBlock(tester);
    await tester.tap(key('subtotal-lidl'));
    await tester.pumpAndSettle();
    expect(row('Milch'), findsOneWidget);
    expect(
      tester.getRect(key('store-lidl')).top,
      greaterThanOrEqualTo(tester.getRect(key('list-header')).bottom - 1),
    );
  });

  testWidgets('English', (tester) async {
    final shop = await pumpList(
      tester,
      flags: _flags,
      seed: _seed,
      locale: const Locale('en'),
    );
    await tick(tester, 'Seife');
    await tester.tap(key('trip-ask-yes'));
    await tester.pumpAndSettle();
    expect(shop.trips.state, isA<Running>());
    await toBlock(tester);
    expect(find.text('SHOPPING TOTAL'), findsOneWidget);
    expect(find.text('Total'), findsOneWidget);
    expect(
      find.descendant(
        of: key('subtotal-none'),
        matching: find.text('No store'),
      ),
      findsOneWidget,
    );
    expect(text(tester, 'subtotal-amount-lidl'), 'at least €3.68');
    expect(text(tester, 'total-amount'), 'at least €7.63');
    expect(find.textContaining('all bought'), findsOneWidget);
    expect(find.text('€0.95 bought · €6.68 open · 1 unpriced'), findsOneWidget);
  });

  for (final (locale, brightness) in const [
    (Locale('de'), Brightness.light),
    (Locale('en'), Brightness.dark),
  ]) {
    testWidgets('160 % text on 358 px, ${locale.languageCode} '
        '${brightness.name}: a long store name wraps, nothing overflows', (
      tester,
    ) async {
      await pumpList(
        tester,
        flags: _flags,
        locale: locale,
        brightness: brightness,
        textScale: 1.6,
        size: const Size(358, 740),
        seed: (repo) {
          repo.stores = [
            ...repo.stores,
            const Store(id: 'market', name: _market, sortOrder: 30),
          ];
          _seed(repo);
          repo.remoteAdd(
            'Kartoffeln',
            storeId: 'market',
            quantity: '2 kg',
            price: _price(180, per: PricePer.kg),
          );
        },
      );
      await toBlock(tester);
      await tester.scrollUntilVisible(
        key('total-bar'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final name = find.descendant(
        of: key('subtotal-market'),
        matching: find.text(_market),
      );
      expect(name, findsOneWidget);
      expect(
        tester.renderObject<RenderParagraph>(name).didExceedMaxLines,
        isFalse,
      );
      for (final k in [
        'subtotal-amount-market',
        'subtotal-amount-lidl',
        'total-amount',
      ]) {
        final rect = tester.getRect(key(k));
        expect(rect.right, lessThanOrEqualTo(358), reason: k);
        expect(
          tester.renderObject<RenderParagraph>(key(k)).didExceedMaxLines,
          isFalse,
          reason: k,
        );
      }
      expect(
        tester.getSize(key('subtotal-dm')).height,
        greaterThanOrEqualTo(48),
      );
    });
  }

  testWidgets("list-declutter off: the bar at the bottom and each store's "
      "sum at its section's end, as before", (tester) async {
    await pumpList(
      tester,
      flags: const {pricesFlag, tripModeFlag},
      seed: (repo) => repo
        ..remoteAdd(
          'Bananen',
          storeId: 'lidl',
          quantity: '846 g',
          price: _price(179, per: PricePer.kg),
        )
        ..remoteAdd('Käse', storeId: 'lidl')
        ..remoteAdd('Seife', storeId: 'dm', price: _price(95)),
    );
    expect(block, findsNothing);
    expect(find.byType(TotalBar), findsOneWidget);
    expect(text(tester, 'total-amount'), '2,46$_nbsp€');
    expect(find.text('Summe Lidl 1,51$_nbsp€'), findsOneWidget);
    expect(find.text('Summe dm 0,95$_nbsp€'), findsOneWidget);
    expect(find.textContaining('≈'), findsNothing);
  });
}

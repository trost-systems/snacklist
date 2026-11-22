import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/list/list_view/item_row.dart';
import 'package:family_groceries/list/list_view/summary_block.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/pricing.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../design/fonts.dart';
import '../trip/list_trip_widget_test.dart' show pumpList;
import 'fake_repository.dart';

const _nbsp = '\u00A0';
const _off = {listDeclutterFlag, pricesFlag, tripModeFlag};
const _on = {..._off, totalPricedOnlyFlag};

Price _price(int cents, {PricePer per = PricePer.piece, String c = 'EUR'}) =>
    Price(
      unitMicros: cents * microsPerCent,
      basis: PriceBasis.unit,
      per: per,
      currency: c,
      pricedAt: DateTime.now(),
    );

/// Three stores and „Ohne Laden“: dm and Rewe without a price, Lidl with
/// Milch 1,19 € and Käse without, Pinsel without a store at 3,00 €.
void _partly(FakeRepository repo) {
  repo.stores = [
    ...repo.stores,
    const Store(id: 'rewe', name: 'Rewe', sortOrder: 30),
  ];
  repo
    ..remoteAdd('Seife', storeId: 'dm')
    ..remoteAdd('Milch', storeId: 'lidl', price: _price(119))
    ..remoteAdd('Käse', storeId: 'lidl')
    ..remoteAdd('Nudeln', storeId: 'rewe')
    ..remoteAdd('Pinsel', price: _price(300));
}

/// Job 348, TE1 behind `total-priced-only`: the ST3 block shows only what
/// has a price. Every case runs with the flag off too, where job 237's block
/// stays as it was.
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

  String detailsOf(WidgetTester tester, String store) => [
    for (final w in tester.widgetList<Text>(
      find.descendant(of: key('subtotal-$store'), matching: find.byType(Text)),
    ))
      w.data ?? w.textSpan?.toPlainText() ?? '',
  ].join(' | ');

  Future<void> toEnd(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      key('recently-used'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

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

  for (final on in [true, false]) {
    final flag = 'total-priced-only ${on ? 'on' : 'off'}';

    testWidgets('no item priced, $flag', (tester) async {
      await pumpList(
        tester,
        flags: on ? _on : _off,
        seed: (repo) => repo
          ..remoteAdd('Seife', storeId: 'dm')
          ..remoteAdd('Milch', storeId: 'lidl')
          ..remoteAdd('Pinsel')
          // Bought before: under „Zuletzt verwendet“, the list's end.
          ..remoteAdd(
            'Kaffee',
            storeId: 'lidl',
            price: _price(499),
            status: ItemStatus.bought,
          ),
      );
      if (on) {
        await toEnd(tester);
        expect(block, findsNothing, reason: 'nothing at all without a price');
        expect(find.text('3 ohne Preis'), findsNothing);
        expect(find.text('Einkaufssumme'), findsNothing);
      } else {
        await toBlock(tester);
        expect(text(tester, 'total-counts'), '3 ohne Preis');
        expect(detailsOf(tester, 'dm'), 'dm | 1 ohne Preis');
        expect(detailsOf(tester, 'none'), 'Ohne Laden | 1 ohne Preis');
      }
    });

    testWidgets('partly priced: a line only for a store with a price, one '
        'count under Gesamt, $flag', (tester) async {
      await pumpList(tester, flags: on ? _on : _off, seed: _partly);
      await toBlock(tester);
      expect(find.text('EINKAUFSSUMME'), findsOneWidget);
      expect(text(tester, 'subtotal-amount-lidl'), 'mind. 1,19$_nbsp€');
      expect(text(tester, 'subtotal-amount-none'), '3,00$_nbsp€');
      expect(text(tester, 'total-amount'), 'mind. 4,19$_nbsp€');
      if (on) {
        expect(key('subtotal-dm'), findsNothing);
        expect(key('subtotal-rewe'), findsNothing);
        expect(detailsOf(tester, 'lidl'), 'Lidl | mind. 1,19$_nbsp€');
        expect(text(tester, 'total-counts'), '3 ohne Preis');
        expect(
          tester.getSemantics(key('total-bar')).label,
          'Gesamt, mindestens 4,19$_nbsp€, 3 ohne Preis',
        );
        expect(find.textContaining('mit Preis'), findsNothing);
      } else {
        expect(detailsOf(tester, 'dm'), 'dm | 1 ohne Preis');
        expect(detailsOf(tester, 'rewe'), 'Rewe | 1 ohne Preis');
        expect(
          detailsOf(tester, 'lidl'),
          'Lidl | 1 ohne Preis | mind. 1,19$_nbsp€',
        );
        expect(text(tester, 'total-counts'), '2 mit Preis · 3 ohne Preis');
      }
    });

    testWidgets('one store priced among unpriced ones: only the total '
        '(TE-Q6), $flag', (tester) async {
      await pumpList(
        tester,
        flags: on ? _on : _off,
        seed: (repo) => repo
          ..remoteAdd('Seife', storeId: 'dm')
          ..remoteAdd('Milch', storeId: 'lidl', price: _price(119)),
      );
      await toBlock(tester);
      expect(text(tester, 'total-amount'), 'mind. 1,19$_nbsp€');
      if (on) {
        expect(key('subtotal-lidl'), findsNothing);
        expect(find.text('Einkaufssumme'), findsOneWidget);
        expect(text(tester, 'total-counts'), '1 ohne Preis');
      } else {
        expect(key('subtotal-lidl'), findsOneWidget);
        expect(key('subtotal-dm'), findsOneWidget);
        expect(text(tester, 'total-counts'), '1 mit Preis · 1 ohne Preis');
      }
    });

    testWidgets('every item priced: every line, no count, $flag', (
      tester,
    ) async {
      await pumpList(
        tester,
        flags: on ? _on : _off,
        seed: (repo) => repo
          ..remoteAdd('Seife', storeId: 'dm', price: _price(95))
          ..remoteAdd('Milch', storeId: 'lidl', price: _price(119))
          ..remoteAdd('Pinsel', price: _price(300)),
      );
      await toBlock(tester);
      expect(text(tester, 'subtotal-amount-dm'), '0,95$_nbsp€');
      expect(text(tester, 'subtotal-amount-lidl'), '1,19$_nbsp€');
      expect(text(tester, 'subtotal-amount-none'), '3,00$_nbsp€');
      expect(text(tester, 'total-amount'), '5,14$_nbsp€');
      if (on) {
        expect(key('total-counts'), findsNothing, reason: 'TE-Q5');
      } else {
        expect(text(tester, 'total-counts'), '3 mit Preis');
      }
    });

    testWidgets('a weighed item: „≈“ on its store and the total, $flag', (
      tester,
    ) async {
      await pumpList(
        tester,
        flags: on ? _on : _off,
        seed: (repo) => repo
          ..remoteAdd(
            'Bananen',
            storeId: 'lidl',
            quantity: '846 g',
            price: _price(179, per: PricePer.kg),
          )
          ..remoteAdd('Seife', storeId: 'dm', price: _price(95))
          ..remoteAdd('Käse', storeId: 'dm'),
      );
      await toBlock(tester);
      expect(text(tester, 'subtotal-amount-lidl'), '≈ 1,51$_nbsp€');
      expect(text(tester, 'subtotal-amount-dm'), 'mind. 0,95$_nbsp€');
      expect(text(tester, 'total-amount'), 'mind. ≈ 2,46$_nbsp€');
      expect(
        text(tester, 'total-counts'),
        on ? '1 ohne Preis' : '2 mit Preis · 1 ohne Preis',
      );
    });

    testWidgets('no store: its own line with a price, none without, $flag', (
      tester,
    ) async {
      await pumpList(
        tester,
        flags: on ? _on : _off,
        seed: (repo) => repo
          ..remoteAdd('Seife', storeId: 'dm', price: _price(95))
          ..remoteAdd('Milch', storeId: 'lidl', price: _price(119))
          ..remoteAdd('Pinsel'),
      );
      await toBlock(tester);
      expect(key('subtotal-none'), on ? findsNothing : findsOneWidget);
      expect(text(tester, 'total-amount'), 'mind. 2,14$_nbsp€');
      expect(
        text(tester, 'total-counts'),
        on ? '1 ohne Preis' : '2 mit Preis · 1 ohne Preis',
      );
    });

    testWidgets('a trip runs: bought and open split; a store bought in full '
        'without a price gets no line (TE-Q7), $flag', (tester) async {
      await pumpList(
        tester,
        flags: on ? _on : _off,
        seed: (repo) => _partly(
          repo..remoteAdd('Brot', storeId: 'lidl', price: _price(249)),
        ),
      );
      await tick(tester, 'Seife');
      await tester.tap(key('trip-ask-yes'));
      await tester.pumpAndSettle();
      await tick(tester, 'Milch');
      await toBlock(tester);
      expect(text(tester, 'subtotal-amount-lidl'), 'mind. 3,68$_nbsp€');
      expect(text(tester, 'total-amount'), 'mind. 6,68$_nbsp€');
      expect(
        text(tester, 'total-counts'),
        '1,19$_nbsp€ gekauft · 5,49$_nbsp€ offen · 3 ohne Preis',
      );
      if (on) {
        expect(key('subtotal-dm'), findsNothing);
        expect(key('subtotal-rewe'), findsNothing);
        expect(
          detailsOf(tester, 'lidl'),
          'Lidl | 1,19$_nbsp€ gekauft · 2,49$_nbsp€ offen '
          '| mind. 3,68$_nbsp€',
        );
      } else {
        expect(detailsOf(tester, 'dm'), contains('alles gekauft'));
        expect(
          detailsOf(tester, 'lidl'),
          'Lidl | 1,19$_nbsp€ gekauft · 2,49$_nbsp€ offen · 1 ohne Preis '
          '| mind. 3,68$_nbsp€',
        );
      }
    });

    testWidgets('a trip runs: a priced store bought in full stays „alles '
        'gekauft“, $flag', (tester) async {
      await pumpList(
        tester,
        flags: on ? _on : _off,
        seed: (repo) => repo
          ..remoteAdd('Seife', storeId: 'dm', price: _price(95))
          ..remoteAdd('Milch', storeId: 'lidl', price: _price(119))
          ..remoteAdd('Käse', storeId: 'lidl'),
      );
      await tick(tester, 'Seife');
      await tester.tap(key('trip-ask-yes'));
      await tester.pumpAndSettle();
      await toBlock(tester);
      expect(text(tester, 'subtotal-amount-dm'), '0,95$_nbsp€');
      expect(detailsOf(tester, 'dm'), contains('alles gekauft'));
      expect(
        text(tester, 'total-counts'),
        '0,95$_nbsp€ gekauft · 1,19$_nbsp€ offen · 1 ohne Preis',
      );
    });

    testWidgets('a price in another currency, $flag', (tester) async {
      await pumpList(
        tester,
        flags: on ? _on : _off,
        seed: (repo) => repo
          ..remoteAdd(
            'Seife',
            storeId: 'dm',
            price: _price(95, c: 'CHF'),
          )
          ..remoteAdd('Milch', storeId: 'lidl', price: _price(119))
          ..remoteAdd('Brot', storeId: 'lidl', price: _price(249)),
      );
      await toBlock(tester);
      expect(text(tester, 'total-amount'), 'mind. 3,68$_nbsp€');
      if (on) {
        // TE-Q10: a store priced only in another currency has no line, and
        // the count names its item with the unpriced ones.
        expect(key('subtotal-dm'), findsNothing);
        expect(find.text('Einkaufssumme'), findsOneWidget);
        expect(text(tester, 'total-counts'), '1 ohne Preis');
      } else {
        expect(key('subtotal-dm'), findsOneWidget);
        expect(text(tester, 'total-counts'), '2 mit Preis');
      }
    });

    testWidgets('310 % text on 390 px: the amounts stay whole, $flag', (
      tester,
    ) async {
      await pumpList(
        tester,
        flags: on ? _on : _off,
        textScale: 3.1,
        seed: (repo) => repo
          ..remoteAdd(
            'Bananen',
            storeId: 'lidl',
            quantity: '846 g',
            price: _price(179, per: PricePer.kg),
          )
          ..remoteAdd('Käse', storeId: 'lidl')
          ..remoteAdd('Seife', storeId: 'dm', price: _price(495)),
      );
      await toBlock(tester);
      await tester.scrollUntilVisible(
        key('total-bar'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Whether the number and its currency sign sit on one line.
      bool whole(String k) {
        final p = tester.renderObject<RenderParagraph>(key(k));
        final shown = p.text.toPlainText();
        final money = RegExp(r'[0-9][0-9,.]*\u00A0€').firstMatch(shown);
        if (money == null) {
          return false;
        }
        final tops = {
          for (final box in p.getBoxesForSelection(
            TextSelection(baseOffset: money.start, extentOffset: money.end),
          ))
            box.top,
        };
        return tops.length == 1;
      }

      final title = find.descendant(
        of: key('total-bar'),
        matching: find.text('Gesamt'),
      );
      if (on) {
        // TE-Q9: too wide beside the name, the amount goes under it whole.
        for (final k in [
          'total-amount',
          'subtotal-amount-lidl',
          'subtotal-amount-dm',
        ]) {
          expect(whole(k), isTrue, reason: '$k broken');
        }
        expect(
          tester.getRect(key('total-amount')).top,
          greaterThanOrEqualTo(tester.getRect(title).bottom),
        );
      } else {
        expect(whole('total-amount'), isFalse, reason: 'as before');
        expect(
          tester.getRect(key('total-amount')).top,
          lessThan(tester.getRect(title).bottom),
        );
      }
    });
  }
}

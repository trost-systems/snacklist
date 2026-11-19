import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/household/currency_section.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/list/list_view/item_row.dart';
import 'package:family_groceries/list/list_view/price_views.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/pricing.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../design/fonts.dart';
import 'fake_repository.dart';
import 'memory_cache.dart';

final _now = DateTime(2026, 11, 13, 18);

Price _price(int cents, {PricePer per = PricePer.piece, String c = 'EUR'}) =>
    Price(
      unitMicros: cents * microsPerCent,
      basis: PriceBasis.unit,
      per: per,
      currency: c,
      pricedAt: _now,
    );

/// Job 190: the price chip, the open row's editor, the total bar, the
/// per-store subtotals and the household currency, behind their flag.
void main() {
  late FakeRepository repo;
  late ListCubit cubit;

  setUp(
    () => VisibilityDetectorController.instance.updateInterval = Duration.zero,
  );
  // Real glyph widths, for the compact layout.
  setUpAll(loadAppFonts);

  Future<void> pumpList(
    WidgetTester tester, {
    void Function(FakeRepository repo)? seed,
    bool flag = true,
    bool currency = false,
    Size size = const Size(390, 844),
  }) async {
    tester.view
      ..devicePixelRatio = 3
      ..physicalSize = size * 3;
    addTearDown(tester.view.reset);
    repo = FakeRepository();
    seed?.call(repo);
    cubit = ListCubit(
      repo,
      MemoryListCache(),
      userId: 'peter',
      clock: () => _now,
    )..start();
    addTearDown(cubit.close);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => Flags(forced: {if (flag) pricesFlag})),
          BlocProvider.value(value: cubit),
        ],
        child: MaterialApp.router(
          theme: appTheme(Brightness.light),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: listPath,
                // The shell's scaffold makes room for the keyboard.
                builder: (_, _) => Scaffold(
                  body: Column(
                    children: [
                      const Expanded(child: ShoppingList()),
                      if (currency) const CurrencySection(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder row(String name) =>
      find.byWidgetPredicate((w) => w is ItemRow && w.item.name == name);

  /// The row's chip; the other copy only holds its room in the row.
  Finder chip(String name) =>
      find.descendant(of: row(name), matching: find.byType(PriceChip)).last;
  Item named(String name) =>
      cubit.state.allItems.values.firstWhere((i) => i.name == name);

  /// intl puts a no-break space before the currency.
  String nbsp(String text) =>
      text.replaceAllMapped(RegExp(' (€|CHF)'), (m) => '\u00a0${m[1]}');

  Future<void> openPrice(WidgetTester tester, String name) async {
    await tester.tap(chip(name).hitTestable());
    await tester.pumpAndSettle();
  }

  testWidgets('with the flag off nothing of prices shows', (tester) async {
    await pumpList(
      tester,
      flag: false,
      currency: true,
      seed: (repo) =>
          repo..remoteAdd('Milch', storeId: 'lidl', price: _price(119)),
    );
    expect(row('Milch'), findsOneWidget);
    expect(find.byType(PriceChip), findsNothing);
    expect(find.byType(TotalBar), findsNothing);
    expect(find.byType(StoreSubtotal), findsNothing);
    expect(find.text('Währung'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Preis für')), findsNothing);
  });

  testWidgets('saving a price does not tick; the chip and total show it', (
    tester,
  ) async {
    await pumpList(
      tester,
      seed: (repo) => repo
        ..remoteAdd('Milch', storeId: 'lidl', quantity: '2')
        ..remoteAdd('Brot', storeId: 'lidl'),
    );
    expect(find.text('Preis').hitTestable(), findsNWidgets(2));
    expect(find.text('Einkaufssumme'), findsOneWidget);
    expect(find.text(nbsp('0,00 €')), findsOneWidget);
    expect(find.text('0 mit Preis · 2 offen'), findsOneWidget);

    await openPrice(tester, 'Milch');
    await tester.enterText(find.byKey(const ValueKey('price-field')), '1,19');
    await tester.pump();
    expect(
      find.text(nbsp('Zusammen 2,38 € · Summe danach 2,38 €')),
      findsOneWidget,
    );
    // The total moves on save, not while typing.
    expect(find.text(nbsp('0,00 €')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('price-done')));
    await tester.pumpAndSettle();

    expect(named('Milch').status, ItemStatus.active);
    expect(repo.rows[named('Milch').id]!.status, ItemStatus.active);
    expect(
      repo.rows[named('Milch').id]!.price?.unitMicros,
      119 * microsPerCent,
    );
    expect(find.byType(PricePanel), findsNothing);
    expect(
      find
          .descendant(of: row('Milch'), matching: find.text(nbsp('2,38 €')))
          .hitTestable(),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('total-amount')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('total-amount'))).data,
      nbsp('2,38 €'),
    );
    expect(find.text('1 mit Preis · 1 offen'), findsOneWidget);
  });

  testWidgets('a tap on the row ticks it, without a price', (tester) async {
    await pumpList(
      tester,
      seed: (repo) => repo..remoteAdd('Brot', storeId: 'lidl'),
    );
    await tester.tap(row('Brot'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(named('Brot').status, ItemStatus.bought);
    expect(named('Brot').price, isNull);
    expect(find.byType(PricePanel), findsNothing);
  });

  testWidgets('the chip is its own button; the row keeps its name', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpList(
      tester,
      seed: (repo) => repo
        ..remoteAdd('Milch', quantity: '2', price: _price(119))
        ..remoteAdd('Brot'),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Preis für Brot')),
      matchesSemantics(
        label: 'Preis für Brot',
        isButton: true,
        hasTapAction: true,
      ),
    );
    expect(
      find.bySemanticsLabel(nbsp('Preis für Milch: 2,38 €, ändern')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp(r'^Milch\n2$')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the total sums every store; each store shows its subtotal', (
    tester,
  ) async {
    await pumpList(
      tester,
      seed: (repo) => repo
        ..remoteAdd('Milch', storeId: 'lidl', quantity: '3', price: _price(119))
        ..remoteAdd(
          'Butter',
          storeId: 'lidl',
          price: _price(249),
          status: ItemStatus.bought,
        )
        ..remoteAdd('Joghurt', storeId: 'lidl')
        ..remoteAdd('Shampoo', storeId: 'dm', price: _price(295))
        ..remoteAdd('Brot', price: _price(-25)),
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('total-amount'))).data,
      nbsp('8,76 €'),
    );
    expect(find.text('4 mit Preis · 1 offen'), findsOneWidget);
    expect(find.text(nbsp('Summe Lidl 6,06 €')), findsOneWidget);
    expect(find.text(nbsp('Summe dm 2,95 €')), findsOneWidget);
    expect(find.text(nbsp('Summe Ohne Laden -0,25 €')), findsOneWidget);
  });

  testWidgets('letters cannot be typed into the price', (tester) async {
    await pumpList(tester, seed: (repo) => repo..remoteAdd('Milch'));
    await openPrice(tester, 'Milch');
    final field = find.byKey(const ValueKey('price-field'));
    await tester.enterText(field, 'abc');
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, '');
    await tester.enterText(field, '-0,25');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('price-done')));
    await tester.pumpAndSettle();
    expect(named('Milch').price?.unitMicros, -25 * microsPerCent);
  });

  testWidgets('empty and too large prices say so; nothing is saved', (
    tester,
  ) async {
    await pumpList(tester, seed: (repo) => repo..remoteAdd('Milch'));
    await openPrice(tester, 'Milch');
    await tester.tap(find.byKey(const ValueKey('price-done')));
    await tester.pump();
    expect(find.text('Gib einen Preis ein.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('price-field')), '10000');
    await tester.tap(find.byKey(const ValueKey('price-done')));
    await tester.pump();
    String money(int cents) =>
        formatMoney(cents, currency: 'EUR', locale: 'de');
    final range =
        'Zwischen ${money(minPriceCents)} und ${money(maxPriceCents)} '
        'pro Artikel.';
    expect(find.text(range), findsOneWidget);
    expect(range, contains(nbsp('9.999,00 €')));
    await tester.enterText(find.byKey(const ValueKey('price-field')), '-10000');
    await tester.tap(find.byKey(const ValueKey('price-done')));
    await tester.pump();
    expect(find.text(range), findsOneWidget, reason: 'below the minimum too');
    expect(named('Milch').price, isNull);
  });

  testWidgets('a weighed item: the scale weight replaces the planned one', (
    tester,
  ) async {
    await pumpList(
      tester,
      seed: (repo) => repo..remoteAdd('Bananen', quantity: '846 g'),
    );
    await openPrice(tester, 'Bananen');
    expect(find.text('pro kg'), findsOneWidget);
    final weight = find.byKey(const ValueKey('amount-field'));
    expect(
      find.descendant(of: weight, matching: find.text('0,846')),
      findsOneWidget,
    );
    // The label's total.
    await tester.tap(find.text('Gesamt'));
    await tester.enterText(find.byKey(const ValueKey('price-field')), '2,47');
    await tester.enterText(weight, '1,24');
    await tester.pump();
    expect(
      find.text(nbsp('Das sind 1,99 € pro kg · Summe danach 2,47 €')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('price-done')));
    await tester.pumpAndSettle();
    expect(named('Bananen').quantity, '1,24 kg');
    expect(microsToCents(named('Bananen').price!.unitMicros), 199);
    expect(named('Bananen').price?.basis, PriceBasis.line);
    expect(named('Bananen').price?.per, PricePer.kg);
    expect(
      find
          .descendant(of: row('Bananen'), matching: find.text(nbsp('2,47 €')))
          .hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('a typed total stays a unit price: more packs, a longer line', (
    tester,
  ) async {
    await pumpList(
      tester,
      seed: (repo) => repo..remoteAdd('Wasser', quantity: '2 Packungen'),
    );
    await openPrice(tester, 'Wasser');
    expect(find.text('pro Stück'), findsOneWidget);
    await tester.tap(find.text('Gesamt'));
    await tester.enterText(find.byKey(const ValueKey('price-field')), '1,38');
    await tester.pump();
    expect(
      find.text(nbsp('Das sind 0,69 € pro Stück · Summe danach 1,38 €')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('price-done')));
    await tester.pumpAndSettle();
    cubit.edit(
      named('Wasser').id,
      const ItemChanges(quantity: SetTo('3 Packungen')),
    );
    await tester.pumpAndSettle();
    expect(
      find
          .descendant(of: row('Wasser'), matching: find.text(nbsp('2,07 €')))
          .hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('a volume is priced per litre', (tester) async {
    await pumpList(
      tester,
      seed: (repo) => repo..remoteAdd('Apfelsaft', quantity: '1,5 l'),
    );
    await openPrice(tester, 'Apfelsaft');
    expect(find.text('pro l'), findsOneWidget);
    final volume = find.byKey(const ValueKey('amount-field'));
    expect(
      find.descendant(of: volume, matching: find.text('1,5')),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const ValueKey('price-field')), '1,80');
    await tester.enterText(volume, '2');
    await tester.tap(find.byKey(const ValueKey('price-done')));
    await tester.pumpAndSettle();
    expect(named('Apfelsaft').quantity, '2 l');
    expect(named('Apfelsaft').lineCentsNow, 360);
  });

  testWidgets('a currency change formats every amount in the new code', (
    tester,
  ) async {
    await pumpList(
      tester,
      currency: true,
      seed: (repo) =>
          repo..remoteAdd('Milch', storeId: 'lidl', price: _price(119)),
    );
    expect(find.text(nbsp('Summe Lidl 1,19 €')), findsOneWidget);
    expect(find.text('EUR · €'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('household-currency')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('currency-CHF')));
    await tester.pumpAndSettle();
    expect(repo.catalogCalls, contains('setCurrency(CHF)'));
    expect(find.text('CHF'), findsWidgets);
    // A euro price shows in euros and leaves the franc total.
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('total-amount'))).data,
      nbsp('0,00 CHF'),
    );
    expect(
      find
          .descendant(of: row('Milch'), matching: find.text(nbsp('1,19 €')))
          .hitTestable(),
      findsOneWidget,
    );

    await openPrice(tester, 'Milch');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('price-field')),
        matching: find.text('CHF'),
      ),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const ValueKey('price-field')), '1,40');
    await tester.tap(find.byKey(const ValueKey('price-done')));
    await tester.pumpAndSettle();
    expect(find.text(nbsp('Summe Lidl 1,40 CHF')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('total-amount'))).data,
      nbsp('1,40 CHF'),
    );
  });

  testWidgets('358 x 740 with the keyboard up: the open row and the total '
      'both fit and take taps', (tester) async {
    await pumpList(
      tester,
      size: const Size(358, 740),
      seed: (repo) {
        for (final name in ['Äpfel', 'Brot', 'Käse', 'Milch', 'Eier']) {
          repo.remoteAdd(name, storeId: 'lidl');
        }
        // With a price: the editor shows all three buttons.
        repo.remoteAdd(
          'Wasser',
          storeId: 'lidl',
          quantity: '2 Pack',
          price: _price(69),
        );
      },
    );
    await tester.ensureVisible(chip('Wasser'));
    await openPrice(tester, 'Wasser');
    tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
    await tester.pumpAndSettle();

    const visible = Rect.fromLTWH(0, 0, 358, 740 - 300);
    final panel = tester.getRect(find.byType(PricePanel));
    final total = tester.getRect(find.byType(TotalBar));
    expect(visible.contains(panel.topLeft), isTrue, reason: '$panel');
    expect(panel.bottom, lessThanOrEqualTo(total.top), reason: '$panel $total');
    expect(total.bottom, lessThanOrEqualTo(visible.bottom), reason: '$total');
    expect(
      find.byKey(const ValueKey('add-item-field')).hitTestable(),
      findsNothing,
    );
    for (final key in [
      'price-remove',
      'price-field',
      'price-done',
      'price-cancel',
      'price-basis',
      'price-unit',
    ]) {
      expect(
        find.byKey(ValueKey(key)).hitTestable(),
        findsOneWidget,
        reason: key,
      );
    }
    expect(find.byType(TotalBar).hitTestable(), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('price-cancel')));
    await tester.pumpAndSettle();
    expect(find.byType(PricePanel), findsNothing);
    expect(
      find.byKey(const ValueKey('add-item-field')).hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('with the add bar aside, the total keeps clear of the tab band', (
    tester,
  ) async {
    await pumpList(
      tester,
      seed: (repo) => repo.remoteAdd('Milch', storeId: 'lidl'),
    );
    // The shell hands its pill band to the page as bottom padding.
    tester.view.padding = const FakeViewPadding(bottom: 76 * 3);
    addTearDown(tester.view.resetPadding);
    await tester.pumpAndSettle();
    await openPrice(tester, 'Milch');

    const band = 844 - 76.0;
    expect(
      tester.getRect(find.byKey(const ValueKey('total-amount'))).bottom,
      lessThanOrEqualTo(band),
    );
    expect(
      tester.getRect(find.text('Einkaufssumme')).bottom,
      lessThanOrEqualTo(band),
    );
  });

  testWidgets('a partner ticks the item being priced: the editor closes and '
      'the add bar is back', (tester) async {
    await pumpList(
      tester,
      seed: (repo) => repo.remoteAdd('Milch', storeId: 'lidl'),
    );
    final field = find.byKey(const ValueKey('add-item-field'));
    await openPrice(tester, 'Milch');
    expect(field.hitTestable(), findsNothing);

    final milk = named('Milch');
    final ticked = Item.fromJson({
      ...milk.toJson(),
      'status': ItemStatus.bought.name,
      'bought_at': _now.toIso8601String(),
      'updated_at': milk.updatedAt
          .add(const Duration(seconds: 5))
          .toIso8601String(),
    });
    repo.rows[milk.id] = ticked;
    repo.emitItem!(ticked);
    await tester.pumpAndSettle();
    expect(find.byType(PricePanel), findsNothing);
    expect(field.hitTestable(), findsOneWidget);
  });

  testWidgets('a weighed item priced per piece keeps its quantity', (
    tester,
  ) async {
    await pumpList(
      tester,
      seed: (repo) =>
          repo.remoteAdd('Hackfleisch', storeId: 'lidl', quantity: '500 g'),
    );
    await openPrice(tester, 'Hackfleisch');
    await tester.tap(find.byKey(const ValueKey('price-unit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stück').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('price-field')), '3,99');
    await tester.tap(find.byKey(const ValueKey('price-done')));
    await tester.pumpAndSettle();
    expect(named('Hackfleisch').quantity, '500 g');
    expect(named('Hackfleisch').price?.per, PricePer.piece);
    expect(named('Hackfleisch').lineCentsNow, 399);
  });

  testWidgets('a reopened total follows the stepper; the unit price stays', (
    tester,
  ) async {
    await pumpList(
      tester,
      seed: (repo) => repo..remoteAdd('Wasser', quantity: '2 Packungen'),
    );
    await openPrice(tester, 'Wasser');
    await tester.tap(find.text('Gesamt'));
    await tester.enterText(find.byKey(const ValueKey('price-field')), '1,38');
    await tester.tap(find.byKey(const ValueKey('price-done')));
    await tester.pumpAndSettle();

    await openPrice(tester, 'Wasser');
    final field = find.byKey(const ValueKey('price-field'));
    expect(find.descendant(of: field, matching: find.text('1,38')), findsOne);
    await tester.tap(find.byTooltip('Eins mehr'));
    await tester.pump();
    expect(find.descendant(of: field, matching: find.text('2,07')), findsOne);
    await tester.tap(find.byKey(const ValueKey('price-done')));
    await tester.pumpAndSettle();
    expect(named('Wasser').quantity, '3 Packungen');
    expect(named('Wasser').price?.unitMicros, 690000);
    expect(named('Wasser').lineCentsNow, 207);
  });

  testWidgets('the stepper changes only the count; other quantities stay', (
    tester,
  ) async {
    await pumpList(
      tester,
      seed: (repo) => repo
        ..remoteAdd('Nudeln', storeId: 'lidl', quantity: '2 x 500 g')
        ..remoteAdd('Eier', storeId: 'lidl', quantity: '6er')
        ..remoteAdd('Sahne', storeId: 'lidl', quantity: '1,5')
        ..remoteAdd('Kuchen', storeId: 'lidl', quantity: '1/2'),
    );
    final more = find.byKey(const ValueKey('price-count-more'));
    Future<void> price(String name, {bool step = true}) async {
      await openPrice(tester, name);
      if (step) {
        await tester.tap(more);
        await tester.pump();
      } else {
        expect(more, findsNothing, reason: '$name has no count to change');
      }
      await tester.enterText(find.byKey(const ValueKey('price-field')), '1');
      await tester.tap(find.byKey(const ValueKey('price-done')));
      await tester.pumpAndSettle();
    }

    await price('Nudeln');
    expect(named('Nudeln').quantity, '3 x 500 g');
    expect(named('Nudeln').lineCentsNow, 300);
    await price('Eier');
    expect(named('Eier').quantity, '7er');
    await price('Sahne', step: false);
    expect(named('Sahne').quantity, '1,5');
    await price('Kuchen', step: false);
    expect(named('Kuchen').quantity, '1/2');
    expect(named('Kuchen').lineCentsNow, 100);
  });
}

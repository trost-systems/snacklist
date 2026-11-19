// Goldens of prices on the list (job 190): rows with their price chips, the
// per-store subtotals and the total bar, and the open price editor at the
// 358 px compact width with a 300 px keyboard up, light and dark. After a
// deliberate look change:
//   flutter test --update-goldens test/design/prices_golden_test.dart
import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/theme.dart';
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

import '../list/fake_repository.dart';
import '../list/memory_cache.dart';
import 'fonts.dart';

final _now = DateTime(2026, 11, 13, 18);

Price _price(int cents, {PricePer per = PricePer.piece}) => Price(
  unitMicros: cents * microsPerCent,
  basis: PriceBasis.unit,
  per: per,
  currency: 'EUR',
  pricedAt: _now,
);

void main() {
  setUpAll(() async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await loadAppFonts();
  });

  Future<void> pump(
    WidgetTester tester,
    Brightness brightness,
    Size size,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = size;
    addTearDown(tester.view.reset);
    final repo = FakeRepository()
      ..remoteAdd(
        'Vollmilch',
        storeId: 'lidl',
        quantity: '3',
        price: _price(119),
      )
      ..remoteAdd('Butter', storeId: 'lidl', price: _price(249))
      ..remoteAdd('Joghurt', storeId: 'lidl', quantity: '4')
      ..remoteAdd(
        'Bananen',
        storeId: 'lidl',
        categoryId: 'produce',
        quantity: '846 g',
      )
      ..remoteAdd('Mineralwasser', storeId: 'lidl', quantity: '2 Pack')
      ..remoteAdd('Shampoo', storeId: 'dm', price: _price(295))
      // Last week's butter, for the comparison.
      ..remoteAdd(
        'Butter',
        storeId: 'lidl',
        status: ItemStatus.bought,
        price: Price(
          unitMicros: 2190000,
          basis: PriceBasis.unit,
          per: PricePer.piece,
          currency: 'EUR',
          pricedAt: _now.subtract(const Duration(days: 7)),
        ),
      );
    final cubit = ListCubit(
      repo,
      MemoryListCache(),
      userId: 'peter',
      clock: () => _now,
    )..start();
    addTearDown(cubit.close);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => Flags(forced: {pricesFlag})),
          BlocProvider.value(value: cubit),
        ],
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: appTheme(brightness),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: listPath,
                builder: (_, _) => const Scaffold(body: ShoppingList()),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The checklist card would push the rows below the fold.
    await tester.tap(find.byTooltip('Erste Schritte ausblenden'));
    await tester.pumpAndSettle();
  }

  for (final brightness in Brightness.values) {
    final mode = brightness.name;
    testWidgets('prices on the list, $mode', (tester) async {
      await pump(tester, brightness, const Size(390, 844));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/prices-list-$mode.png'),
      );
    });

    for (final (name, typed, slug) in [
      ('Bananen', '1,99', 'weight'),
      ('Butter', '2,49', 'priced'),
    ]) {
      testWidgets('price editor ($slug), compact with the keyboard up, $mode', (
        tester,
      ) async {
        await pump(tester, brightness, const Size(358, 740));
        final chip = find
            .descendant(
              of: find.byWidgetPredicate(
                (w) =>
                    w is ItemRow &&
                    w.item.name == name &&
                    w.item.status == ItemStatus.active,
              ),
              matching: find.byType(PriceChip),
            )
            .last;
        await tester.ensureVisible(chip);
        await tester.pumpAndSettle();
        await tester.tap(chip);
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('price-field')),
          typed,
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/prices-editor-$slug-compact-$mode.png'),
        );
      });
    }
  }
}

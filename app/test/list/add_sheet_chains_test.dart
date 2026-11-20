import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/chain_suggestions.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_repository.dart';
import 'memory_cache.dart';
import 'retailer_fixtures.dart';

/// Job 313 (flag `open-store-app`): a store made in the add sheet's store
/// picker gets chains offered while its name is typed, and a plain name
/// that is a chain's is asked about in place, the store already picked.
void main() {
  late FakeRepository repo;
  Finder key(String k) => find.byKey(ValueKey(k));

  Future<void> pump(WidgetTester tester, {bool flag = true}) async {
    tester.view
      ..devicePixelRatio = 3
      ..physicalSize = const Size(390 * 3, 844 * 3);
    addTearDown(tester.view.reset);
    repo = FakeRepository();
    seedRetailers(repo);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: MultiBlocProvider(
          providers: [
            BlocProvider(
              create: (_) => Flags(forced: {if (flag) openStoreAppFlag}),
            ),
            BlocProvider(
              create: (_) => ListCubit(
                repo,
                MemoryListCache(),
                userId: 'peter',
                grace: Duration.zero,
                region: () => 'DE',
              )..start(),
            ),
          ],
          child: const ShoppingList(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final add = key('add-item-field');
    await tester.tap(add);
    await tester.enterText(add, 'Gurken');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    await tester.tap(key('chip-store'));
    await tester.pumpAndSettle();
    await tester.tap(key('store-option-new'));
    await tester.pumpAndSettle();
  }

  /// Types the new store's name; the chains for it have shown.
  Future<void> name(WidgetTester tester, String text) async {
    await tester.enterText(key('store-new-field'), text);
    await tester.pump();
    await tester.pump(chainSuggestionDelay);
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(key('store-new-confirm'));
    await tester.pumpAndSettle();
  }

  Finder chip(String text) =>
      find.descendant(of: key('chip-store'), matching: find.text(text));

  Store? named(String name) =>
      repo.stores.where((s) => s.name == name).firstOrNull;

  testWidgets('a chain offered under the name: a tap adds it linked and '
      'picks it', (tester) async {
    await pump(tester);
    await name(tester, 'Re');
    expect(find.bySemanticsLabel('REWE (Deutschland) wählen'), findsOne);

    await tester.tap(key('chain-suggestion-rewe-DE'));
    await tester.pumpAndSettle();
    expect(repo.catalogCalls, [
      'addStore(REWE)',
      'answerStoreRetailer(new-REWE, rewe, DE, null)',
    ]);
    expect(named('REWE')?.retailer?.key, rewe.key);
    expect(chip('REWE'), findsOne);
    expect(key('store-new-field'), findsNothing, reason: 'folded back');
  });

  testWidgets('a plain chain name is picked and asked about in place; Ja '
      'links it', (tester) async {
    await pump(tester);
    await name(tester, 'Lidl am Markt');
    await confirm(tester);
    expect(chip('Lidl am Markt'), findsOne, reason: 'picked already');
    expect(find.byType(Dialog), findsNothing, reason: 'no popup');
    expect(key('store-new-field'), findsNothing);
    expect(find.text('Ist das Lidl (Deutschland)?'), findsOne);
    expect(tester.takeAnnouncements(), [
      isAccessibilityAnnouncement(
        'Lidl am Markt angelegt und ausgewählt Ist das Lidl (Deutschland)?',
      ),
    ], reason: 'focus is back in the add field: the question is said');

    await tester.tap(find.text('Ja'));
    await tester.pumpAndSettle();
    expect(named('Lidl am Markt')?.retailer?.key, lidl.key);
    expect(key('chain-question'), findsNothing);
    expect(key('store-option-new'), findsNothing, reason: 'folded back');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      repo.rows.values.where((i) => i.name == 'Gurken').single.storeId,
      'new-Lidl am Markt',
    );
  });

  testWidgets('Nein, so lassen keeps the store plain and answered', (
    tester,
  ) async {
    await pump(tester);
    await name(tester, 'Rewe');
    await confirm(tester);
    await tester.tap(find.text('Nein, so lassen'));
    await tester.pumpAndSettle();
    expect(named('Rewe')?.retailer, isNull);
    expect(named('Rewe')?.retailerAnswered, isTrue);
    expect(chip('Rewe'), findsOne);
  });

  testWidgets('a name of two chains asks which', (tester) async {
    await pump(tester);
    await name(tester, 'Aldi');
    await confirm(tester);
    expect(find.text('Welches Aldi?'), findsOne);
    await tester.tap(find.text('ALDI Nord'));
    await tester.pumpAndSettle();
    expect(named('Aldi')?.retailer?.key, aldiNord.key);
  });

  testWidgets('a name of no chain is picked as before, unasked', (
    tester,
  ) async {
    await pump(tester);
    await name(tester, 'Wochenmarkt');
    expect(find.textContaining('wählen'), findsNothing);
    await confirm(tester);
    expect(key('chain-question'), findsNothing);
    expect(key('store-option-new'), findsNothing, reason: 'folded back');
    expect(chip('Wochenmarkt'), findsOne);
    expect(repo.catalogCalls, ['addStore(Wochenmarkt)']);
  });

  testWidgets('flag off: as before', (tester) async {
    await pump(tester, flag: false);
    await name(tester, 'Rewe');
    expect(find.textContaining('wählen'), findsNothing);
    await confirm(tester);
    expect(key('chain-question'), findsNothing);
    expect(chip('Rewe'), findsOne);
    expect(repo.retailerCountries, isEmpty);
    expect(repo.catalogCalls, ['addStore(Rewe)']);
  });
}

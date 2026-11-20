import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/list/chain_suggestions.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../more/more_harness.dart';
import 'fake_repository.dart';
import 'retailer_fixtures.dart';

/// Job 313 (flag `open-store-app`): chains offered while a store is added
/// on Anpassen, the question after a plain name, and the store screen's
/// app card and chain line.
void main() {
  late FakeRepository repo;
  late FakeStoreApps apps;
  Finder key(String k) => find.byKey(ValueKey(k));

  setUpAll(fakeSupabase);

  Future<void> pump(
    WidgetTester tester, {
    String location = editPath,
    bool flag = true,
    void Function(FakeRepository repo)? seed,
  }) async {
    // The phone's region (phoneRegion) reads the main locale.
    tester.platformDispatcher.localeTestValue = const Locale('de', 'DE');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    apps = FakeStoreApps();
    repo = (await pumpMore(
      tester,
      location: location,
      size: const Size(358, 800),
      routes: listTabRoutes(),
      flags: {if (flag) openStoreAppFlag},
      storeApps: apps,
      seed: (repo) {
        seedRetailers(repo);
        seed?.call(repo);
      },
    )).repo;
  }

  /// Opens Laden hinzufügen and types [name]; the suggestions have shown.
  Future<void> type(WidgetTester tester, String name) async {
    await tester.tap(key('store-add'));
    await tester.pumpAndSettle();
    await tester.enterText(key('name-dialog-field'), name);
    await tester.pump();
    await tester.pump(chainSuggestionDelay);
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(key('name-dialog-confirm'));
    await tester.pumpAndSettle();
  }

  Store stored(String id) => repo.stores.firstWhere((s) => s.id == id);

  Store? named(String name) =>
      repo.stores.where((s) => s.name == name).firstOrNull;

  group('adding a store on Anpassen', () {
    testWidgets('two letters offer the chain; a tap adds it linked', (
      tester,
    ) async {
      await pump(tester);
      await type(tester, 'Re');
      expect(find.bySemanticsLabel('REWE (Deutschland) wählen'), findsOne);
      expect(find.text('Deutschland'), findsOne);

      await tester.tap(key('chain-suggestion-rewe-DE'));
      await tester.pumpAndSettle();
      expect(key('name-dialog-field'), findsNothing);
      expect(named('REWE')?.retailer?.key, rewe.key, reason: 'the name');
      expect(repo.catalogCalls, [
        'addStore(REWE)',
        'answerStoreRetailer(new-REWE, rewe, DE, null)',
      ]);
      expect(key('chain-question'), findsNothing, reason: 'asked by the tap');
    });

    testWidgets('one letter offers nothing', (tester) async {
      await pump(tester);
      await type(tester, 'R');
      expect(find.textContaining('wählen'), findsNothing);
      expect(key('chain-suggestion-rewe-DE'), findsNothing);
    });

    testWidgets("a name of another country's chain finds it", (tester) async {
      await pump(tester);
      await type(tester, 'Hofer');
      expect(find.bySemanticsLabel('HOFER (Österreich) wählen'), findsOne);
      expect(repo.retailerCountries.last, 'DE');
    });

    testWidgets('a plain name that is a chain is asked about; Ja links it', (
      tester,
    ) async {
      await pump(tester);
      await type(tester, 'Lidl am Markt');
      await save(tester);
      expect(named('Lidl am Markt')?.retailer, isNull);
      expect(find.text('Ist das Lidl (Deutschland)?'), findsOne);
      expect(
        find.text('Dann kannst du Lidl Plus direkt aus der Liste öffnen.'),
        findsOne,
      );

      await tester.tap(find.text('Ja'));
      await tester.pumpAndSettle();
      expect(key('chain-question'), findsNothing);
      expect(named('Lidl am Markt')?.retailer?.key, lidl.key);
      expect(named('Lidl am Markt')?.name, 'Lidl am Markt', reason: 'kept');
    });

    testWidgets('Nein, so lassen keeps it plain and answered', (tester) async {
      await pump(tester);
      await type(tester, 'Rewe');
      await save(tester);
      await tester.tap(find.text('Nein, so lassen'));
      await tester.pumpAndSettle();
      expect(named('Rewe')?.retailer, isNull);
      expect(named('Rewe')?.retailerAnswered, isTrue);
      expect(
        repo.catalogCalls.last,
        'answerStoreRetailer(new-Rewe, null, null, null)',
      );
    });

    testWidgets('closing the question answers nothing', (tester) async {
      await pump(tester);
      await type(tester, 'Rewe');
      await save(tester);
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(key('chain-question'), findsNothing);
      expect(named('Rewe')?.retailerAnswered, isFalse);
      expect(repo.catalogCalls, ['addStore(Rewe)']);
    });

    testWidgets('a name of two chains asks which', (tester) async {
      await pump(tester);
      await type(tester, 'Aldi');
      await save(tester);
      expect(find.text('Welches Aldi?'), findsOne);
      expect(find.text('ALDI Nord'), findsOne);
      expect(find.text('Keins davon'), findsOne);

      await tester.tap(key('chain-question-aldi-sued-DE'));
      await tester.pumpAndSettle();
      expect(named('Aldi')?.retailer?.key, aldiSued.key);
    });

    testWidgets('a name of no chain is saved as it was, unasked', (
      tester,
    ) async {
      await pump(tester);
      await type(tester, 'Wochenmarkt');
      expect(find.textContaining('wählen'), findsNothing);
      await save(tester);
      expect(key('chain-question'), findsNothing);
      expect(repo.catalogCalls, ['addStore(Wochenmarkt)']);
    });

    testWidgets('flag off: no suggestion, no question', (tester) async {
      await pump(tester, flag: false);
      await type(tester, 'Rewe');
      expect(find.textContaining('wählen'), findsNothing);
      await save(tester);
      expect(key('chain-question'), findsNothing);
      expect(repo.retailerCountries, isEmpty);
      expect(repo.catalogCalls, ['addStore(Rewe)']);
    });

    testWidgets('offline: no suggestion, typing goes on', (tester) async {
      await pump(tester);
      repo.online = false;
      await type(tester, 'Rewe');
      expect(find.textContaining('wählen'), findsNothing);
      expect(key('name-dialog-field'), findsOne);
    });
  });

  group('the store screen', () {
    void linked(FakeRepository repo) => repo.stores = [
      for (final s in repo.stores)
        if (s.id == 'lidl')
          s.copyWith(retailer: () => lidl, retailerAnswered: true)
        else
          s,
      const Store(
        id: 'billa',
        name: 'Billa',
        sortOrder: 30,
        retailer: billa,
        retailerAnswered: true,
      ),
    ];

    testWidgets('a linked store shows its app; Öffnen opens it', (
      tester,
    ) async {
      await pump(tester, location: storeDetailsPath('lidl'), seed: linked);
      expect(
        find.descendant(
          of: key('store-app-card'),
          matching: find.text('Lidl Plus'),
        ),
        findsOne,
      );
      expect(find.text('Zugeordnet: Lidl · Deutschland'), findsOne);
      expect(key('store-app-choice-${lidlPlus.android}'), findsNothing);

      await tester.tap(find.bySemanticsLabel('Lidl Plus öffnen'));
      await tester.pumpAndSettle();
      expect(apps.opened, [lidlPlus.android]);
    });

    testWidgets('a chain with two apps: the second is picked and kept', (
      tester,
    ) async {
      await pump(tester, location: storeDetailsPath('billa'), seed: linked);
      expect(find.bySemanticsLabel('BILLA öffnen'), findsOne);

      await tester.tap(key('store-app-choice-${joe.android}'));
      await tester.pumpAndSettle();
      expect(stored('billa').retailerApp, joe.android);
      expect(find.bySemanticsLabel('jö öffnen'), findsOne);
      expect(find.bySemanticsLabel('BILLA öffnen'), findsNothing);

      await tester.tap(find.bySemanticsLabel('jö öffnen'));
      await tester.pumpAndSettle();
      expect(apps.opened, [joe.android]);
    });

    testWidgets('Zuordnung aufheben: no card, a button to match one', (
      tester,
    ) async {
      await pump(tester, location: storeDetailsPath('lidl'), seed: linked);
      await tester.tap(find.bySemanticsLabel('Zuordnung zur Kette aufheben'));
      await tester.pumpAndSettle();
      expect(stored('lidl').retailer, isNull);
      expect(stored('lidl').retailerAnswered, isTrue);
      expect(key('store-app-card'), findsNothing);
      expect(find.text('Kette zuordnen'), findsOne);
    });

    testWidgets('the picker lists the region first and finds abroad', (
      tester,
    ) async {
      await pump(tester, location: storeDetailsPath('dm'));
      expect(key('store-app-card'), findsNothing);
      await tester.tap(find.text('Kette zuordnen'));
      await tester.pumpAndSettle();
      final listed = [
        for (final r in [lidl, rewe, hofer])
          tester.getTopLeft(key('chain-pick-${r.chain}-${r.country}')).dy,
      ];
      expect(listed[0] < listed[2] && listed[1] < listed[2], isTrue);

      await tester.enterText(key('chain-picker-search'), 'Hofer');
      await tester.pump();
      await tester.pump(chainSuggestionDelay);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('HOFER (Österreich)'), findsOne);
      expect(key('chain-pick-lidl-DE'), findsNothing);

      await tester.tap(find.bySemanticsLabel('HOFER (Österreich)'));
      await tester.pumpAndSettle();
      expect(stored('dm').retailer?.key, hofer.key);
      expect(find.text('Zugeordnet: HOFER · Österreich'), findsOne);
      expect(find.bySemanticsLabel('HOFER öffnen'), findsOne);
    });

    testWidgets('Ändern picks another chain', (tester) async {
      await pump(tester, location: storeDetailsPath('lidl'), seed: linked);
      await tester.tap(find.bySemanticsLabel('Kette ändern'));
      await tester.pumpAndSettle();
      await tester.enterText(key('chain-picker-search'), 'rew');
      await tester.pump();
      await tester.pump(chainSuggestionDelay);
      await tester.pumpAndSettle();
      await tester.tap(key('chain-pick-rewe-DE'));
      await tester.pumpAndSettle();
      expect(stored('lidl').retailer?.key, rewe.key);
      expect(find.text('Zugeordnet: REWE · Deutschland'), findsOne);
    });

    testWidgets('Ohne Laden has no chain', (tester) async {
      await pump(tester, location: storeDetailsPath(null), seed: linked);
      expect(key('store-app-card'), findsNothing);
      expect(find.textContaining('Kette'), findsNothing);
    });

    testWidgets('flag off: as before', (tester) async {
      await pump(
        tester,
        location: storeDetailsPath('lidl'),
        seed: linked,
        flag: false,
      );
      expect(key('store-app-card'), findsNothing);
      expect(find.textContaining('Kette'), findsNothing);
    });
  });
}

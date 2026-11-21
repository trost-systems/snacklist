import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/language.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/store_badge.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../more/more_harness.dart';
import 'fake_repository.dart';

/// The List tab's Anpassen (job 78): the stores, "Ohne Laden" pinned where
/// its section sits on the list, and the button that adds a store.
void main() {
  late FakeRepository repo;
  Finder key(String k) => find.byKey(ValueKey(k));

  setUpAll(fakeSupabase);

  Future<void> pump(
    WidgetTester tester, {
    void Function(FakeRepository repo)? seed,
    AppLanguage? language,
    Set<String> flags = const {},
  }) async {
    repo = (await pumpMore(
      tester,
      location: editPath,
      size: const Size(358, 800),
      routes: listTabRoutes(),
      language: language,
      seed: seed,
      flags: flags,
    )).repo;
  }

  List<String> names() => [for (final s in repo.stores) s.name];

  Future<void> addStore(WidgetTester tester, String name) async {
    await tester.tap(key('store-add'));
    await tester.pumpAndSettle();
    await tester.enterText(key('name-dialog-field'), name);
    await tester.tap(key('name-dialog-confirm'));
    await tester.pumpAndSettle();
  }

  testWidgets('a store row is one hex: its name, no badge inside', (
    tester,
  ) async {
    await pump(tester);
    final row = key('store-row-lidl');
    expect(
      find.descendant(of: row, matching: find.text('Lidl')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.byType(StoreBadge)),
      findsNothing,
      reason: 'job 148: the inner hexagon went',
    );
  });

  testWidgets('"Ohne Laden" holds its categories, which the hint names', (
    tester,
  ) async {
    await pump(tester);
    expect(key('store-row-none'), findsOneWidget);
    expect(find.textContaining('Kategorien'), findsWidgets);
  });

  testWidgets('flag hide-categories: the stores alone, no "Ohne Laden" and no '
      'word of categories', (tester) async {
    await pump(tester, flags: {hideCategoriesFlag});
    expect(key('store-row-lidl'), findsOneWidget);
    expect(key('store-row-none'), findsNothing);
    expect(find.textContaining('Kategorie'), findsNothing);
  });

  testWidgets('flag hide-categories: no stores yet still says what one does', (
    tester,
  ) async {
    await pump(
      tester,
      seed: (repo) => repo.stores = const [],
      flags: {hideCategoriesFlag},
    );
    expect(key('stores-empty'), findsOneWidget);
  });

  testWidgets('the button adds a store below the others', (tester) async {
    await pump(tester);
    await addStore(tester, 'Rewe');
    expect(names(), ['dm', 'Lidl', 'Rewe']);
    expect(key('name-dialog-field'), findsNothing);
    expect(key('store-row-new-Rewe'), findsOneWidget);
    expect(tester.takeAnnouncements(), [
      isAccessibilityAnnouncement('Rewe angelegt'),
    ]);
  });

  testWidgets('a name the household has stays in the dialog with why', (
    tester,
  ) async {
    await pump(tester);
    await addStore(tester, 'lidl');
    expect(names(), ['dm', 'Lidl']);
    expect(repo.catalogCalls, isEmpty);
    expect(key('name-dialog-field'), findsOneWidget);
    expect(
      find.text('Einen Laden „Lidl“ gibt es schon.').hitTestable(),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeAnnouncements(), isEmpty);

    await tester.enterText(key('name-dialog-field'), 'Lidl Express');
    await tester.pump();
    expect(find.text('Einen Laden „Lidl“ gibt es schon.'), findsNothing);
    await tester.tap(key('name-dialog-confirm'));
    await tester.pumpAndSettle();
    expect(names(), ['dm', 'Lidl', 'Lidl Express']);
    expect(key('name-dialog-field'), findsNothing);
  });

  testWidgets('a taken name in English, upper case with umlauts', (
    tester,
  ) async {
    await pump(
      tester,
      language: AppLanguage.en,
      seed: (repo) => repo.stores = [
        ...repo.stores,
        const Store(id: 'muller', name: 'Müller', sortOrder: 30),
      ],
    );
    await addStore(tester, 'MÜLLER');
    expect(key('name-dialog-field'), findsOneWidget);
    expect(
      find.text('A store named “Müller” already exists.').hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('offline, the name stays in the dialog to try again', (
    tester,
  ) async {
    await pump(tester);
    repo.online = false;
    await addStore(tester, 'Rewe');
    expect(key('name-dialog-field'), findsOneWidget);
    expect(names(), ['dm', 'Lidl']);
    expect(
      find.text('Die Änderung konnte nicht gespeichert werden.').hitTestable(),
      findsOneWidget,
      reason: 'the reason shows above the dialog, not under its barrier',
    );
  });

  testWidgets('a store opens its details; back returns to the stores', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Lidl'));
    await tester.pumpAndSettle();
    expect(key('store-details'), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Lidl'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(key('stores-screen'), findsOneWidget);
  });

  testWidgets('Ohne Laden is pinned last: no trash, no handle, opens the '
      'route order', (tester) async {
    await pump(tester);
    final none = key('store-row-none');
    expect(find.text('Ohne Laden'), findsOneWidget);
    expect(
      tester.getTopLeft(none).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(key('store-row-lidl')).dy),
    );
    expect(
      find.descendant(of: none, matching: find.byIcon(Icons.drag_handle)),
      findsNothing,
    );
    expect(
      find.descendant(of: none, matching: find.byType(IconButton)),
      findsNothing,
    );
    await tester.tap(none);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Ohne Laden'), findsOneWidget);
    expect(find.textContaining('unter „Ohne Laden“'), findsOneWidget);
  });

  testWidgets('a store row has its trash and handle, no menu', (tester) async {
    await pump(tester);
    expect(find.byTooltip('dm löschen'), findsOneWidget);
    expect(find.bySemanticsLabel('dm verschieben'), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsNothing);
    expect(find.text('Reihenfolge bearbeiten'), findsNothing);
  });

  testWidgets('delete says how many open items lose their store, on every '
      'list, then they have none', (tester) async {
    late Item milk;
    await pump(
      tester,
      seed: (repo) {
        repo.lists = const [
          HouseholdList(id: 'weekly', name: 'Wocheneinkauf', position: 0),
          HouseholdList(id: 'party', name: 'Sommerfest', position: 1),
        ];
        milk = repo.remoteAdd('Milch', storeId: 'lidl');
        repo.remoteAdd('Käse', storeId: 'lidl', listId: 'party');
      },
    );
    await tester.tap(find.byTooltip('Lidl löschen'));
    await tester.pumpAndSettle();
    expect(find.text('Lidl löschen?'), findsOneWidget);
    expect(
      find.text(
        '2 offene Artikel kommen zu „Ohne Laden“. Sein Laufweg geht mit.',
      ),
      findsOneWidget,
    );
    await tester.tap(key('store-delete-confirm'));
    await tester.pumpAndSettle();
    expect(names(), ['dm']);
    expect(repo.rows[milk.id]!.storeId, isNull);
    expect(key('store-row-lidl'), findsNothing);
  });

  testWidgets('cancelling the delete keeps the store', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('dm löschen'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'In diesem Laden sind keine offenen Artikel. Sein Laufweg geht mit.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(names(), ['dm', 'Lidl']);
    expect(repo.catalogCalls, isEmpty);
  });

  testWidgets('no store-name disclaimer here (onboarding has it)', (
    tester,
  ) async {
    await pump(tester);
    expect(find.textContaining('Ladennamen wie'), findsNothing);
    expect(
      find.text(
        'Ziehe die Läden in die Reihenfolge, in der sie auf der Liste '
        'stehen. Tippe auf einen Laden, um ihn umzubenennen und seine '
        'Kategorien zu ordnen.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a household without stores sees why and can add one', (
    tester,
  ) async {
    await pump(tester, seed: (repo) => repo.stores = const []);
    expect(key('stores-empty'), findsOneWidget);
    expect(find.textContaining('Noch keine Läden.'), findsOneWidget);
    await addStore(tester, 'Rewe');
    expect(names(), ['Rewe']);
    expect(key('stores-empty'), findsNothing);
  });

  testWidgets('the button never covers the last handle', (tester) async {
    await pump(
      tester,
      seed: (repo) => repo.stores = [
        for (var i = 0; i < 12; i++)
          Store(id: 's$i', name: 'Laden $i', sortOrder: i),
      ],
    );
    await tester.scrollUntilVisible(
      key('store-row-none'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
    await tester.pumpAndSettle();
    final handle = find.bySemanticsLabel('Laden 11 verschieben');
    expect(
      tester.getRect(handle).overlaps(tester.getRect(key('store-add'))),
      isFalse,
    );
  });

  testWidgets('in English', (tester) async {
    await pump(tester, language: AppLanguage.en);
    expect(find.widgetWithText(AppBar, 'Stores'), findsOneWidget);
    expect(find.text('Add store'), findsOneWidget);
    expect(find.text('No store'), findsOneWidget);
    expect(find.byTooltip('Delete Lidl'), findsOneWidget);
  });
}

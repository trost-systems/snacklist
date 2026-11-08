import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/store_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../more/more_harness.dart';
import 'fake_repository.dart';

/// One store's details, and the same screen for the section without a
/// store (job 78): rename, the category order, and the household's
/// categories themselves.
void main() {
  late FakeRepository repo;
  Finder key(String k) => find.byKey(ValueKey(k));

  setUpAll(fakeSupabase);

  Future<void> pump(
    WidgetTester tester,
    String? storeId, {
    List<Locale> device = const [Locale('de', 'DE')],
  }) async {
    repo = (await pumpMore(
      tester,
      location: storeDetailsPath(storeId),
      size: const Size(358, 800),
      routes: listTabRoutes(),
      device: device,
    )).repo;
  }

  List<String> names() => [for (final c in repo.categories) c.name];

  /// The rows' names top to bottom.
  List<String> shown(WidgetTester tester) =>
      [
        for (final name in ['Obst & Gemüse', 'Kühlregal', 'Sonstiges'])
          if (find.text(name).evaluate().isNotEmpty) name,
      ]..sort(
        (a, b) => tester
            .getTopLeft(find.text(a))
            .dy
            .compareTo(tester.getTopLeft(find.text(b)).dy),
      );

  Future<void> enterName(WidgetTester tester, String name) async {
    await tester.enterText(key('name-dialog-field'), name);
    await tester.tap(key('name-dialog-confirm'));
    await tester.pumpAndSettle();
  }

  Future<void> drag(WidgetTester tester, String label, double dy) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.bySemanticsLabel(label)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(Offset(0, dy / 10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  group('a store', () {
    testWidgets('shows its walking order under its name', (tester) async {
      await pump(tester, 'lidl');
      expect(find.widgetWithText(AppBar, 'Lidl'), findsOneWidget);
      expect(shown(tester), ['Sonstiges', 'Kühlregal', 'Obst & Gemüse']);
      expect(
        find.text(
          'Ordne die Kategorien so, wie du durch den Laden gehst. Tippe auf '
          'eine Kategorie, um sie umzubenennen.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('is renamed at the top', (tester) async {
      await pump(tester, 'dm');
      expect(find.bySemanticsLabel('dm umbenennen'), findsOneWidget);
      await tester.tap(key('store-rename'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(key('name-dialog-field')).controller!.text,
        'dm',
      );
      await enterName(tester, 'Rossmann');
      expect(repo.catalogCalls, ['renameStore(dm, Rossmann)']);
      expect(find.widgetWithText(AppBar, 'Rossmann'), findsOneWidget);
    });

    testWidgets('shows no numbers; a screen reader hears each place', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, 'lidl');
      // The order shows as the order (job 148): no step numbers.
      for (final n in ['1', '2', '3']) {
        expect(find.text(n), findsNothing);
      }
      for (final (place, name) in [
        (1, 'Sonstiges'),
        (2, 'Kühlregal'),
        (3, 'Obst & Gemüse'),
      ]) {
        expect(
          find.semantics.byPredicate(
            (node) => node.label == name && node.hint == '$place von 3',
          ),
          findsOne,
          reason: name,
        );
      }
      semantics.dispose();
    });

    testWidgets('its name field holds the name centered, no badge, no hint', (
      tester,
    ) async {
      await pump(tester, 'dm');
      final pill = key('store-rename');
      final face = find.descendant(
        of: pill,
        matching: find.byType(InputDecorator),
      );
      final name = find.descendant(of: pill, matching: find.text('dm'));
      expect(
        tester.getCenter(name).dy,
        moreOrLessEquals(tester.getCenter(face).dy, epsilon: 0.5),
      );
      expect(
        find.descendant(of: pill, matching: find.byType(Text)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: pill, matching: find.byType(StoreBadge)),
        findsNothing,
        reason: 'one hex: the field, no badge inside (job 148)',
      );
      expect(
        find.descendant(of: pill, matching: find.byIcon(Icons.edit_outlined)),
        findsOneWidget,
      );
    });

    testWidgets("a rename onto another store's name keeps the dialog", (
      tester,
    ) async {
      await pump(tester, 'dm');
      await tester.tap(key('store-rename'));
      await tester.pumpAndSettle();
      await enterName(tester, 'lidl');
      expect(key('name-dialog-field'), findsOneWidget);
      expect(find.text('Einen Laden „Lidl“ gibt es schon.'), findsOneWidget);
      expect([for (final s in repo.stores) s.name], ['dm', 'Lidl']);
    });

    testWidgets('a reorder keeps the categories it does not carry', (
      tester,
    ) async {
      await pump(tester, 'dm');
      expect(shown(tester), ['Sonstiges', 'Obst & Gemüse', 'Kühlregal']);
      await drag(tester, 'Sonstiges verschieben', 2.5 * 60);
      expect(repo.catalogCalls, [
        'layout(dm: produce, chilled, other; produce, chilled)',
      ]);
      expect(shown(tester), ['Obst & Gemüse', 'Kühlregal', 'Sonstiges']);
    });

    testWidgets('deleted on another device: back to the stores', (
      tester,
    ) async {
      final more = await pumpMore(
        tester,
        location: editPath,
        size: const Size(358, 800),
        routes: listTabRoutes(),
      );
      await tester.tap(find.text('dm'));
      await tester.pumpAndSettle();
      expect(key('store-details'), findsOneWidget);
      more.repo.stores = [...more.repo.stores.where((s) => s.id != 'dm')];
      await tester.element(key('store-details')).read<ListCubit>().resync();
      await tester.pumpAndSettle();
      expect(key('store-details'), findsNothing);
      expect(key('stores-screen'), findsOneWidget);
      expect(find.text('dm'), findsNothing);
    });

    testWidgets('a store that does not exist goes to the stores', (
      tester,
    ) async {
      await pump(tester, 'gone');
      expect(key('store-details'), findsNothing);
      expect(key('stores-screen'), findsOneWidget);
    });
  });

  group('without a store', () {
    testWidgets('a row is named by its category; its drag handle apart', (
      tester,
    ) async {
      await pump(tester, null);
      expect(find.widgetWithText(AppBar, 'Ohne Laden'), findsOneWidget);
      expect(key('store-rename'), findsNothing);
      expect(
        tester.getSemantics(find.text('Kühlregal')),
        isSemantics(label: 'Kühlregal', isButton: true),
      );
      expect(find.bySemanticsLabel('Kühlregal verschieben'), findsOneWidget);
    });

    testWidgets('a reorder changes the route order', (tester) async {
      await pump(tester, null);
      await drag(tester, 'Obst & Gemüse verschieben', 1.5 * 60);
      expect(repo.catalogCalls, ['reorder(chilled, produce, other)']);
    });

    testWidgets('tapping a category renames it', (tester) async {
      await pump(tester, null);
      await tester.tap(find.text('Kühlregal'));
      await tester.pumpAndSettle();
      await enterName(tester, 'Kühlung');
      expect(names(), ['Obst & Gemüse', 'Kühlung', 'Sonstiges']);
      expect(find.text('Kühlung'), findsOneWidget);
    });

    testWidgets('a name that starts with an emoji shows it once, as the '
        'icon', (tester) async {
      await pump(tester, null);
      await tester.tap(find.text('Kühlregal'));
      await tester.pumpAndSettle();
      await enterName(tester, '👶 Baby');
      expect(find.text('Baby'), findsOneWidget);
      expect(find.text('👶'), findsOneWidget);
      expect(find.text('👶 Baby'), findsNothing);
    });

    testWidgets('a new category is added; a taken name says so', (
      tester,
    ) async {
      await pump(tester, null);
      await tester.tap(find.text('Kategorie hinzufügen'));
      await tester.pumpAndSettle();
      await enterName(tester, 'Tiernahrung');
      expect(names(), contains('Tiernahrung'));
      expect(find.text('Tiernahrung'), findsOneWidget);

      await tester.tap(find.text('Kategorie hinzufügen'));
      await tester.pumpAndSettle();
      await enterName(tester, 'sonstiges ');
      expect(names().where((n) => n.toLowerCase() == 'sonstiges'), [
        'Sonstiges',
      ]);
      expect(
        find.text('Eine Kategorie „Sonstiges“ gibt es schon.'),
        findsOneWidget,
      );
      expect(key('name-dialog-field'), findsOneWidget);
      await tester.enterText(key('name-dialog-field'), 'Sonstiges 2');
      await tester.pump();
      expect(
        find.text('Eine Kategorie „Sonstiges“ gibt es schon.'),
        findsNothing,
        reason: 'typing clears the message',
      );
    });

    testWidgets("a rename onto another category's name in another case "
        'keeps the dialog and says so', (tester) async {
      await pump(tester, null);
      await tester.tap(find.text('Kühlregal'));
      await tester.pumpAndSettle();
      await enterName(tester, 'obst & GEMÜSE');
      expect(key('name-dialog-field'), findsOneWidget);
      expect(names(), ['Obst & Gemüse', 'Kühlregal', 'Sonstiges']);
      expect(
        find.text('Eine Kategorie „Obst & Gemüse“ gibt es schon.'),
        findsOneWidget,
      );
    });

    testWidgets('in English a seed is taken under its English name too', (
      tester,
    ) async {
      await pump(tester, null, device: const [Locale('en', 'US')]);
      await tester.tap(find.text('Kühlregal'));
      await tester.pumpAndSettle();
      await enterName(tester, 'other');
      expect(find.text('A category named “Other” already exists.'), findsOne);
      expect(names(), ['Obst & Gemüse', 'Kühlregal', 'Sonstiges']);
    });

    testWidgets('offline, a rename closes the dialog and says it failed', (
      tester,
    ) async {
      await pump(tester, null);
      repo.online = false;
      await tester.tap(find.text('Kühlregal'));
      await tester.pumpAndSettle();
      await enterName(tester, 'Kühlung');
      expect(key('name-dialog-field'), findsNothing);
      expect(
        find.text('Die Änderung konnte nicht gespeichert werden.'),
        findsOneWidget,
      );
      expect(find.text('Kühlregal'), findsOneWidget);
    });

    testWidgets('a category may change its own case', (tester) async {
      await pump(tester, null);
      await tester.tap(find.text('Kühlregal'));
      await tester.pumpAndSettle();
      await enterName(tester, 'KÜHLREGAL');
      expect(names(), ['Obst & Gemüse', 'KÜHLREGAL', 'Sonstiges']);
    });
  });

  testWidgets('deleting says it leaves every store and moves the items to '
      'the fallback by default', (tester) async {
    await pump(tester, 'lidl');
    final milk = repo.remoteAdd('Milch');
    expect(find.byTooltip('Sonstiges löschen'), findsNothing);

    await tester.tap(find.byTooltip('Kühlregal löschen'));
    await tester.pumpAndSettle();
    expect(find.text('Sie verschwindet aus allen Läden.'), findsOneWidget);
    expect(find.text('Artikel verschieben nach'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Löschen'));
    await tester.pumpAndSettle();

    expect(names(), ['Obst & Gemüse', 'Sonstiges']);
    expect(repo.rows[milk.id]!.categoryId, 'other');
    expect(find.text('Kühlregal'), findsNothing);
  });
}

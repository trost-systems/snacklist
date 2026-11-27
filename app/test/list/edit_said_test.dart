import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/edit_item_sheet.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/list/list_view/item_row.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_repository.dart';
import 'memory_cache.dart';

/// Job 474: after the edit sheet saves, a screen reader hears what changed.
void main() {
  const catalog = Catalog(
    categories: [Category(id: 'chilled', name: 'Kühlregal', sortOrder: 30)],
    stores: [
      Store(id: 'dm', name: 'dm', sortOrder: 10, seedKey: 'dm'),
      Store(id: 'edeka', name: 'Edeka', sortOrder: 20, seedKey: 'edeka'),
    ],
    lists: [
      HouseholdList(id: 'main', name: 'Einkauf', position: 0),
      HouseholdList(id: 'party', name: 'Party', position: 1),
    ],
  );
  final de = lookupAppLocalizations(const Locale('de'));
  final en = lookupAppLocalizations(const Locale('en'));

  List<String> said(AppLocalizations l10n, ItemEdit edit) =>
      editSaid(l10n, edit, catalog: catalog);

  group('what is said', () {
    test('one field', () {
      const store = ItemEdit(changes: ItemChanges(storeId: SetTo('dm')));
      expect(said(de, store), ['Laden auf dm geändert']);
      expect(said(en, store), ['Changed store to dm']);
      const quantity = ItemEdit(changes: ItemChanges(quantity: SetTo('2')));
      expect(said(de, quantity), ['Menge auf 2 geändert']);
      expect(said(en, quantity), ['Changed quantity to 2']);
    });

    test('several, joined naturally in the sheet order', () {
      const edit = ItemEdit(
        changes: ItemChanges(
          storeId: SetTo('edeka'),
          quantity: SetTo('2'),
          name: 'Kosmetiktücher',
        ),
      );
      expect(said(de, edit), [
        'Name auf Kosmetiktücher, Menge auf 2 und Laden auf Edeka geändert',
      ]);
      expect(said(en, edit), [
        'Changed name to Kosmetiktücher, quantity to 2 and store to Edeka',
      ]);
      const two = ItemEdit(
        changes: ItemChanges(brand: SetTo('Tempo'), quantity: SetTo('3')),
      );
      expect(said(de, two), ['Marke auf Tempo und Menge auf 3 geändert']);
      expect(said(en, two), ['Changed brand to Tempo and quantity to 3']);
    });

    test('an emptied field is removed, after what was set', () {
      const edit = ItemEdit(
        changes: ItemChanges(
          quantity: SetTo(null),
          storeId: SetTo(null),
          properties: SetTo('bio'),
        ),
      );
      expect(said(de, edit), [
        'Eigenschaften auf bio geändert',
        'Menge und Laden entfernt',
      ]);
      expect(said(en, edit), [
        'Changed details to bio',
        'Removed quantity and store',
      ]);
    });

    test('the place and the list in their own words, after the fields', () {
      final milk = Item(
        id: 'milk',
        name: 'Milch',
        status: ItemStatus.active,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      List<String> placed(AppLocalizations l10n, ItemEdit edit) =>
          editSaid(l10n, edit, catalog: catalog, placeRun: [milk]);
      const next = ItemEdit(
        changes: ItemChanges(quantity: SetTo('2')),
        place: PlaceAfter('milk'),
        listId: 'party',
      );
      expect(placed(de, next), [
        'Menge auf 2 geändert',
        'Neben Milch gesetzt',
        'Auf die Liste Party verschoben',
      ]);
      expect(placed(en, next), [
        'Changed quantity to 2',
        'Moved next to Milch',
        'Moved to the list Party',
      ]);
      const first = ItemEdit(place: PlaceFirst());
      expect(placed(de, first), ['Nach vorne gesetzt']);
      expect(placed(en, first), ['Moved to the top']);
    });

    test('nothing for no change, or only the claim', () {
      expect(said(de, const ItemEdit()), isEmpty);
      expect(said(de, const ItemEdit(claim: Unclaimed())), isEmpty);
    });
  });

  group('on the list', () {
    late FakeRepository repo;

    Future<void> pumpList(
      WidgetTester tester,
      Locale locale, {
      List<String> more = const [],
    }) async {
      tester.view
        ..devicePixelRatio = 3
        ..physicalSize = const Size(390, 844) * 3;
      addTearDown(tester.view.reset);
      repo = FakeRepository()
        ..stores = const [
          Store(id: 'dm', name: 'dm', sortOrder: 10, seedKey: 'dm'),
          Store(id: 'edeka', name: 'Edeka', sortOrder: 20, seedKey: 'edeka'),
        ]
        ..remoteAdd('Taschentücher', storeId: 'dm');
      for (final name in more) {
        repo.remoteAdd(name, storeId: 'dm');
      }
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          home: BlocProvider(
            create: (_) =>
                ListCubit(repo, MemoryListCache(), userId: 'peter')..start(),
            child: const ShoppingList(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder key(String k) => find.byKey(ValueKey(k));

    Future<void> openEdit(WidgetTester tester) async {
      await tester.tap(
        find.widgetWithText(ItemRow, 'Taschentücher'),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      expect(key('edit-sheet'), findsOne);
    }

    for (final (locale, words) in [
      (
        const Locale('de'),
        'Name auf Kosmetiktücher, Menge auf 2 und Laden auf Edeka geändert',
      ),
      (
        const Locale('en'),
        'Changed name to Kosmetiktücher, quantity to 2 and store to Edeka',
      ),
    ]) {
      testWidgets('saving name, quantity and store says "$words"', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        await pumpList(tester, locale);
        await openEdit(tester);
        await tester.enterText(key('edit-name'), 'Kosmetiktücher');
        await tester.enterText(key('edit-quantity'), '2');
        await tester.tap(key('chip-store'));
        await tester.pumpAndSettle();
        await tester.tap(key('store-option-edeka'));
        await tester.pumpAndSettle();
        tester.takeAnnouncements();
        await tester.tap(key('edit-done'));
        await tester.pumpAndSettle();
        expect(tester.takeAnnouncements(), [
          isAccessibilityAnnouncement(words),
        ]);
        semantics.dispose();
      });
    }

    testWidgets('a rename onto an open item merges it and says nothing '
        'more than the merge snackbar', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpList(tester, const Locale('de'), more: ['Kosmetiktücher']);
      await openEdit(tester);
      await tester.enterText(key('edit-name'), 'Kosmetiktücher');
      await tester.enterText(key('edit-quantity'), '3');
      tester.takeAnnouncements();
      await tester.tap(key('edit-done'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Zusammengeführt'), findsOne);
      expect(
        [for (final a in tester.takeAnnouncements()) a.message],
        isEmpty,
        reason: 'nothing was renamed, and the quantity is not 3',
      );
      semantics.dispose();
    });

    testWidgets('saving without a change says nothing', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpList(tester, const Locale('de'));
      await openEdit(tester);
      tester.takeAnnouncements();
      await tester.tap(key('edit-done'));
      await tester.pumpAndSettle();
      expect(key('edit-sheet'), findsNothing);
      expect(tester.takeAnnouncements(), isEmpty);
      semantics.dispose();
    });
  });
}

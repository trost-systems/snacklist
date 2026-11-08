import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/edit_item_sheet.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Job 169b K and L in the edit sheet: the "Liste" picker and "Ich bringe
/// das".
void main() {
  const lists = [
    HouseholdList(id: 'weekly', name: 'Wocheneinkauf', position: 0),
    HouseholdList(id: 'party', name: 'Sommerfest', position: 1),
  ];
  const catalog = Catalog(
    categories: [Category(id: 'other', name: 'Sonstiges', sortOrder: 1000)],
    lists: lists,
  );
  final cake = Item(
    id: 'cake',
    name: 'Kuchen',
    categoryId: 'other',
    status: ItemStatus.active,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    listId: 'party',
  );

  Finder key(String k) => find.byKey(ValueKey(k));

  /// Opens the sheet; [act] works on it and closes it, and the sheet's
  /// answer comes back.
  Future<ItemEdit?> run(
    WidgetTester tester,
    Future<void> Function()? act, {
    Catalog shown = catalog,
    Claim? mine,
    String? others,
  }) async {
    ItemEdit? result;
    tester.view
      ..physicalSize = const Size(400, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => result = await showEditItemSheet(
                  context,
                  item: cake,
                  catalog: shown,
                  onCreateStore: (_) async => null,
                  listId: 'party',
                  myClaim: mine,
                  othersBring: others,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    if (act != null) {
      await act();
      await tester.pumpAndSettle();
      expect(key('edit-sheet'), findsNothing, reason: 'closed');
    }
    return result;
  }

  Future<void> done(WidgetTester tester) async {
    await tester.ensureVisible(key('edit-done'));
    await tester.tap(key('edit-done'));
  }

  testWidgets('one list: no picker', (tester) async {
    await run(
      tester,
      null,
      shown: const Catalog(
        lists: [HouseholdList(id: 'a', name: 'A', position: 0)],
      ),
    );
    expect(key('edit-list'), findsNothing);
  });

  testWidgets('another list picked moves the item there', (tester) async {
    final edit = await run(tester, () async {
      expect(
        tester.getSemantics(key('edit-list-party')),
        matchesSemantics(
          label: 'Sommerfest',
          isSelected: true,
          hasSelectedState: true,
          isButton: true,
          hasTapAction: true,
        ),
      );
      await tester.tap(key('edit-list-weekly'));
      await tester.pump();
      await done(tester);
    });
    expect(edit?.listId, 'weekly');
    expect(edit?.changes.isEmpty, isTrue);
    expect(edit?.claim, isNull);
  });

  testWidgets('the same list picked again is no change', (tester) async {
    final edit = await run(tester, () async {
      await tester.tap(key('edit-list-party'));
      await done(tester);
    });
    expect(edit, isNull);
  });

  testWidgets('"Ich bringe das" with an amount, others named above', (
    tester,
  ) async {
    final edit = await run(others: 'Lea bringt 1', tester, () async {
      expect(key('edit-claim-others'), findsOneWidget);
      expect(find.text('Lea bringt 1'), findsOneWidget);
      expect(key('edit-claim-amount'), findsNothing, reason: 'not yet');
      await tester.tap(key('edit-claim'));
      await tester.pump();
      await tester.enterText(key('edit-claim-amount'), ' 2 ');
      await done(tester);
    });
    expect(edit?.claim, isA<Claimed>());
    expect((edit!.claim! as Claimed).quantity, '2');
    expect(edit.listId, isNull);
  });

  testWidgets('a claim taken back, or its amount changed', (tester) async {
    final mine = Claim(
      itemId: 'cake',
      userId: 'peter',
      quantity: '2',
      createdAt: DateTime.utc(2026),
    );
    final back = await run(mine: mine, tester, () async {
      expect(
        tester.widget<TextField>(key('edit-claim-amount')).controller!.text,
        '2',
      );
      await tester.tap(key('edit-claim'));
      await done(tester);
    });
    expect(back?.claim, isA<Unclaimed>());

    final more = await run(mine: mine, tester, () async {
      await tester.enterText(key('edit-claim-amount'), '3');
      await done(tester);
    });
    expect((more!.claim! as Claimed).quantity, '3');

    final same = await run(mine: mine, tester, () => done(tester));
    expect(same, isNull, reason: 'nothing changed');
  });
}

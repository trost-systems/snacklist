import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/chain_suggestions.dart';
import 'package:family_groceries/list/edit_item_sheet.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/retailer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'retailer_fixtures.dart';

/// Job 313 (flag `open-store-app`): the edit sheet's store picker makes a
/// store the way the add sheet's does, its chain offered while typing.
void main() {
  Finder key(String k) => find.byKey(ValueKey(k));

  testWidgets('a chain picked under a new store name: the store is made '
      'linked, shows on the chip and is saved for the item', (tester) async {
    final linked = <(String, String)>[];
    final chains = StoreChains(
      match: (name) async => [
        if ('rewe'.startsWith(name.toLowerCase()))
          const RetailerMatch(rewe, exact: false),
      ],
      addLinked: (name, retailer) async {
        linked.add((name, retailer.chain));
        return Store(id: 'new-rewe', name: name, sortOrder: 30);
      },
      link: (_, _) async => true,
      decline: (_) async => true,
    );
    ItemEdit? edit;
    tester.view
      ..physicalSize = const Size(400, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  edit = await showEditItemSheet(
                    context,
                    item: Item(
                      id: 'milk',
                      name: 'Milch',
                      status: ItemStatus.active,
                      createdAt: DateTime.utc(2026),
                      updatedAt: DateTime.utc(2026),
                    ),
                    catalog: const Catalog(),
                    onCreateStore: (name) async =>
                        Store(id: 'plain', name: name, sortOrder: 30),
                    chains: chains,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(key('chip-store'));
    await tester.pumpAndSettle();
    await tester.tap(key('store-option-new'));
    await tester.pumpAndSettle();
    await tester.enterText(key('store-new-field'), 'Re');
    await tester.pump();
    await tester.pump(chainSuggestionDelay);
    await tester.pumpAndSettle();

    await tester.tap(key('chain-suggestion-rewe-DE'));
    await tester.pumpAndSettle();
    expect(linked, [('REWE', 'rewe')]);
    expect(
      find.descendant(of: key('chip-store'), matching: find.text('REWE')),
      findsOne,
    );

    await tester.tap(key('edit-done'));
    await tester.pumpAndSettle();
    expect(edit?.changes.toColumns(), {'store_id': 'new-rewe'});
  });
}

import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/edit_item_sheet.dart';
import 'package:family_groceries/list/list_cache.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_repository.dart';
import 'memory_cache.dart';

/// The app doesn't clamp the text scale: 2.0 is Android's largest font size,
/// 3.0 iOS's largest accessibility size. A layout overflow or a NaN in a
/// painter fails the test on its own.
void main() {
  const scales = [2.0, 3.0];
  const phones = [Size(360, 640), Size(320, 568)];

  void phone(WidgetTester tester, Size size, double scale) {
    tester.view
      ..devicePixelRatio = 3
      ..physicalSize = size * 3;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  Future<FakeRepository> pumpList(
    WidgetTester tester, {
    void Function(FakeRepository repo)? seed,
    ListPrefs? prefs,
  }) async {
    final repo = FakeRepository();
    seed?.call(repo);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: BlocProvider(
          create: (_) =>
              ListCubit(repo, MemoryListCache()..prefs = prefs, userId: 'peter')
                ..start(),
          child: const ShoppingList(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repo;
  }

  void groceries(FakeRepository repo) {
    repo
      ..remoteAdd(
        'Milch',
        storeId: 'lidl',
        quantity: '2',
        brand: 'Weihenstephan',
      )
      ..remoteAdd(
        'Vollkornbrot mit Sonnenblumenkernen',
        storeId: 'lidl',
        properties: 'geschnitten, 500 g',
      )
      ..remoteAdd('Zahnpasta', storeId: 'dm', quantity: '3 Tuben')
      ..remoteAdd('Bananen');
  }

  Finder field() => find.byKey(const ValueKey('add-item-field'));

  for (final scale in scales) {
    for (final size in phones) {
      final on = '(${size.width.toInt()}x${size.height.toInt()})';

      testWidgets('at text scale $scale the Erste Schritte card fits $on', (
        tester,
      ) async {
        phone(tester, size, scale);
        await pumpList(tester, seed: groceries);
        final dismiss = find.byKey(const ValueKey('list-hint-dismiss'));
        await tester.ensureVisible(dismiss);
        await tester.pumpAndSettle();
        await tester.tap(dismiss);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('list-hint')), findsNothing);
      });

      testWidgets('at text scale $scale store headers and rows fit $on', (
        tester,
      ) async {
        phone(tester, size, scale);
        await pumpList(
          tester,
          seed: groceries,
          prefs: const ListPrefs(hintDismissed: true),
        );
        for (final store in ['store-dm', 'store-lidl']) {
          await tester.scrollUntilVisible(
            find.byKey(ValueKey(store)),
            100,
            scrollable: find
                .descendant(
                  of: find.byType(CustomScrollView),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.pumpAndSettle();
        }
      });

      testWidgets('at text scale $scale an add from the sheet fits $on', (
        tester,
      ) async {
        phone(tester, size, scale);
        final repo = await pumpList(
          tester,
          prefs: const ListPrefs(hintDismissed: true),
        );
        await tester.tap(field());
        await tester.pumpAndSettle();
        await tester.enterText(field(), 'Eier');
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(repo.rows.values.single.name, 'Eier');
      });

      testWidgets('at text scale $scale the edit sheet fits $on', (
        tester,
      ) async {
        phone(tester, size, scale);
        const catalog = Catalog(
          categories: [
            Category(id: 'chilled', name: 'Kühlregal', sortOrder: 30),
            Category(id: 'other', name: 'Sonstiges', sortOrder: 1000),
          ],
          stores: [
            Store(id: 'edeka', name: 'Edeka', sortOrder: 10, seedKey: 'edeka'),
            Store(id: 'dm', name: 'dm-Markt', sortOrder: 20, seedKey: 'dm'),
          ],
        );
        final milk = Item(
          id: 'milk',
          name: 'Milch',
          quantity: '2',
          brand: 'Weihenstephan',
          properties: '1,5 %, 1 l',
          categoryId: 'chilled',
          storeId: 'edeka',
          status: ItemStatus.active,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        );
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('de'),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => showEditItemSheet(
                      context,
                      item: milk,
                      catalog: catalog,
                      onCreateStore: (name) async =>
                          Store(id: 'new', name: name, sortOrder: 30),
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
        final scrollables = find.byType(Scrollable);
        if (scrollables.evaluate().isNotEmpty) {
          await tester.drag(scrollables.last, const Offset(0, -1500));
          await tester.pumpAndSettle();
        }
      });
    }
  }
}

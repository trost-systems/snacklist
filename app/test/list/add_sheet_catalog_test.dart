import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/app/localizations.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/add_sheet/add_sheet_cubit.dart';
import 'package:family_groceries/list/add_sheet/suggestion.dart';
import 'package:family_groceries/list/catalog/catalog_index.dart';
import 'package:family_groceries/list/catalog/household_index.dart';
import 'package:family_groceries/list/catalog/suggest_entries.dart';
import 'package:family_groceries/list/category_guess.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_repository.dart';
import 'memory_cache.dart';

/// Job 274: with the flag `on-device-catalog` every key shows the rows
/// public.suggest_entries would answer, ranked on the device; the server's
/// answer only fills in what they lack.
void main() {
  final parity = jsonDecode(
    File('../supabase/tests/suggest_parity.json').readAsStringSync(),
  ) as Map<String, Object?>;
  // The parity fixture's household: Kaffee from Tchibo, Eier from Hofgut
  // Sonnenschein, its taught brands.
  final household = HouseholdIndex.fromJson(parity['index'])!;
  final categories = [
    for (final (i, seed)
        in (parity['categories']! as List<Object?>).cast<String>().indexed)
      Category(id: seed, name: seed, sortOrder: i, seedKey: seed),
  ];

  late FakeRepository repo;

  Future<void> pumpList(
    WidgetTester tester, {
    void Function(FakeRepository repo)? seed,
  }) async {
    tester.view
      ..devicePixelRatio = 3
      ..physicalSize = const Size(390, 1400) * 3
      ..padding = const FakeViewPadding(top: 47.0 * 3, bottom: 34.0 * 3);
    addTearDown(tester.view.reset);
    repo = FakeRepository()
      ..categories = categories
      ..householdIndex = household;
    seed?.call(repo);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: MultiBlocProvider(
          providers: [
            BlocProvider(create: (_) => Flags(forced: {onDeviceCatalogFlag})),
            BlocProvider(
              create: (_) => ListCubit(
                repo,
                MemoryListCache(),
                userId: 'peter',
                householdIndex: () => true,
              )..start(),
            ),
          ],
          child: const ShoppingList(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder field() => find.byKey(const ValueKey('add-item-field'));

  ListCubit list(WidgetTester tester) =>
      tester.element(field()).read<ListCubit>();

  /// The device's rows for [text], as the sheet should show them.
  List<Suggestion> ranked(WidgetTester tester, String text) {
    final state = list(tester).state;
    return suggestEntries(
      text,
      catalog: CatalogIndex.bundled,
      household: state.householdIndex,
      categories: state.catalog,
      known: householdCategories(state.allItems.values),
    );
  }

  /// The keys of the rows shown, top to bottom.
  List<String> shown(WidgetTester tester) {
    final keys = [
      for (final element in find.byWidgetPredicate((_) => true).evaluate())
        if (element.widget.key case ValueKey<String>(:final value)
            // A row's key is its suggestion's, which has two '|'; the
            // dimming inside each row is keyed `suggestion-stale`.
            when value.startsWith('suggestion-') && value.contains('|'))
          value,
    ];
    double top(String key) => tester.getTopLeft(find.byKey(ValueKey(key))).dy;
    return [
      for (final key in keys..sort((a, b) => top(a).compareTo(top(b))))
        key.substring('suggestion-'.length),
    ];
  }

  Finder rowFor(Suggestion row) =>
      find.byKey(ValueKey('suggestion-${row.key}'));

  String label(WidgetTester tester, Suggestion row) =>
      tester.getSemantics(rowFor(row)).label;

  Future<void> open(WidgetTester tester) async {
    await tester.tap(field());
    await tester.pumpAndSettle();
  }

  /// Types [text] and lets its typing pause run out.
  Future<void> typeAndPause(WidgetTester tester, String text) async {
    await tester.enterText(field(), text);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
  }

  List<Item> items(WidgetTester tester) => [...list(tester).state.items.values];

  testWidgets('every key shows the ranking for what is typed now, in the '
      'same frame, with the server held back', (tester) async {
    await pumpList(tester);
    expect(list(tester).state.householdIndex, same(household));
    repo.suggestGate = Completer<void>();
    await open(tester);
    final sources = <SuggestionSource>{};
    for (final text in ['K', 'Ka', 'Kaf', 'Kaff', 'Kaffe', 'Kaffee']) {
      await tester.enterText(field(), text);
      await tester.pump();
      final expected = ranked(tester, text);
      expect(shown(tester), [
        for (final row in expected) row.key,
      ], reason: 'the rows for "$text"');
      sources.addAll([for (final row in expected) row.source]);
    }
    expect(
      sources,
      containsAll([
        SuggestionSource.typed,
        SuggestionSource.history,
        SuggestionSource.brand,
        SuggestionSource.catalog,
      ]),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(repo.suggestCalls, ['Kaffee'], reason: 'the server is still asked');
    repo.suggestGate!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets("the server's answer in another order keeps the shown rows "
      'and fills in their store', (tester) async {
    await pumpList(tester);
    final gate = repo.suggestGate = Completer<void>();
    await open(tester);
    await typeAndPause(tester, 'Kaffee');
    final device = ranked(tester, 'Kaffee');
    expect(shown(tester), [for (final row in device) row.key]);
    final history = device.firstWhere(
      (r) => r.source == SuggestionSource.history,
    );
    final before = label(tester, history);
    repo.suggestions['Kaffee'] = [
      for (final row in device.reversed)
        Suggestion(
          row.source,
          ParsedEntry(
            name: row.entry.name,
            brand: row.entry.brand,
            properties: row.entry.properties,
            quantity: row.entry.quantity,
            storeId: 'lidl',
          ),
        ),
    ];
    gate.complete();
    await tester.pumpAndSettle();
    expect(shown(tester), [for (final row in device) row.key]);
    expect(label(tester, history), '$before, Lidl');
  });

  testWidgets('a row under a finger stays until the finger lifts', (
    tester,
  ) async {
    await pumpList(tester);
    final gate = repo.suggestGate = Completer<void>();
    await open(tester);
    await typeAndPause(tester, 'Kaffee');
    final device = ranked(tester, 'Kaffee');
    final history = device.firstWhere(
      (r) => r.source == SuggestionSource.history,
    );
    final before = label(tester, history);
    repo.suggestions['Kaffee'] = [
      for (final row in device)
        Suggestion(
          row.source,
          ParsedEntry(
            name: row.entry.name,
            brand: row.entry.brand,
            properties: row.entry.properties,
            storeId: 'lidl',
          ),
        ),
    ];
    final gesture = await tester.startGesture(
      tester.getCenter(rowFor(history)),
    );
    gate.complete();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(label(tester, history), before);
    await gesture.cancel();
    await tester.pump();
    expect(label(tester, history), '$before, Lidl');
  });

  testWidgets('offline, the device rows stay', (tester) async {
    await pumpList(tester);
    repo.online = false;
    await open(tester);
    await typeAndPause(tester, 'Kaffee');
    await tester.pump(const Duration(seconds: 1));
    expect(repo.suggestCalls, ['Kaffee']);
    expect(shown(tester), [
      for (final row in ranked(tester, 'Kaffee')) row.key,
    ]);
  });

  testWidgets("Enter adds the device's first row without waiting for the "
      'server', (tester) async {
    await pumpList(tester);
    final gate = repo.suggestGate = Completer<void>();
    await open(tester);
    await tester.enterText(field(), '2 Kaffee');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    final added = items(tester).single;
    expect((added.name, added.quantity), ('Kaffee', '2'));
    expect(gate.isCompleted, isFalse);
    gate.complete();
    await tester.pumpAndSettle();
  });

  group('a line naming an open item says it is on the list', () {
    void openItem(FakeRepository r, String name, String brand) {
      final now = DateTime.utc(2026, 11, 16);
      r.rows['m1'] = Item(
        id: 'm1',
        name: name,
        brand: brand,
        status: ItemStatus.active,
        createdAt: now,
        updatedAt: now,
      );
    }

    for (final (line, name, brand, how) in [
      ('Hofgut Sonnenschein Eier', 'Eier', 'Hofgut Sonnenschein', 'split'),
      // A brand the index does not hold (taught since): one name.
      ('Gläserne Molkerei Milch', 'Milch', 'Gläserne Molkerei', 'unsplit'),
    ]) {
      testWidgets('$how on the device: "$line"', (tester) async {
        await pumpList(tester, seed: (r) => openItem(r, name, brand));
        repo.suggestGate = Completer<void>();
        await open(tester);
        await tester.enterText(field(), line);
        await tester.pump();
        expect(
          ranked(tester, line).first.entry.brand,
          how == 'split' ? brand : isNull,
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(find.text('$name steht schon auf der Liste'), findsOneWidget);
        expect(items(tester), hasLength(1));
        repo.suggestGate!.complete();
        await tester.pumpAndSettle();
      });
    }
  });

  test('a ranking that throws shows the rows made without it', () {
    final list = ListCubit(
      FakeRepository()..categories = categories,
      MemoryListCache(),
      userId: 'peter',
    );
    addTearDown(list.close);
    var reads = 0;
    final sheet = AddSheetCubit(
      list,
      onDeviceCatalog: () => true,
      // The ranking's read of the index throws; the fallback's does not.
      catalogIndex: () => reads++ == 0
          ? throw StateError('broken index')
          : CatalogIndex.bundled,
    );
    addTearDown(sheet.close);
    sheet.key('Windeln');
    expect(sheet.state.suggestions.map((s) => s.entry.name), ['Windeln']);
  });
}

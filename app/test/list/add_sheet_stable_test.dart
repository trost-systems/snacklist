import 'dart:async';

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/add_sheet/suggestion.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/list/list_view/dividers.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/store_badge.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_repository.dart';
import 'memory_cache.dart';

/// [FakeRepository] whose suggest_entries answer for a text waits for that
/// text's gate: answers arrive in any order.
class _GatedRepository() extends FakeRepository {
  final gates = <String, Completer<void>>{};

  @override
  Future<List<Suggestion>> suggest(String text) async {
    await gates[text]?.future;
    return await super.suggest(text);
  }
}

/// Job 272: the add sheet's rows while typing, with the flag
/// `input-stable-rows` on and off.
void main() {
  late _GatedRepository repo;

  Future<void> pumpList(
    WidgetTester tester, {
    required bool stable,
    void Function(FakeRepository repo)? seed,
  }) async {
    tester.view
      ..devicePixelRatio = 3
      ..physicalSize = const Size(390, 844) * 3
      ..padding = const FakeViewPadding(top: 47.0 * 3, bottom: 34.0 * 3);
    addTearDown(tester.view.reset);
    repo = _GatedRepository();
    seed?.call(repo);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: MultiBlocProvider(
          providers: [
            BlocProvider(
              create: (_) => Flags(forced: {if (stable) inputStableRowsFlag}),
            ),
            BlocProvider(
              create: (_) =>
                  ListCubit(repo, MemoryListCache(), userId: 'peter')..start(),
            ),
          ],
          child: const ShoppingList(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder field() => find.byKey(const ValueKey('add-item-field'));

  /// The row at [i], keyed by position (flag off).
  Finder row(int i) => find.byKey(ValueKey('suggestion-$i'));

  /// The row that adds [name] with no brand or details (flag on).
  Finder rowFor(String name) =>
      find.byKey(ValueKey('suggestion-${foldName(name)}||'));

  String label(WidgetTester tester, Finder row) =>
      tester.getSemantics(row).label;

  /// The names of the rows that add a bare name, top to bottom.
  List<String> order(WidgetTester tester) {
    final names = {
      for (final name in ['Milch', 'Hafermilch', 'Milchreis', 'Vollmilch'])
        if (rowFor(name).evaluate().isNotEmpty)
          name: tester.getTopLeft(rowFor(name)).dy,
    };
    return names.keys.toList()..sort((a, b) => names[a]!.compareTo(names[b]!));
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(field());
    await tester.pumpAndSettle();
  }

  /// One key 50 ms after the last: faster than the 120 ms typing pause.
  Future<void> key(WidgetTester tester, String text) async {
    await tester.enterText(field(), text);
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// Types [text] and lets its typing pause run out; the answer waits for
  /// its gate.
  Future<void> typeAndPause(WidgetTester tester, String text) async {
    await tester.enterText(field(), text);
    await tester.pump(const Duration(milliseconds: 200));
  }

  List<Item> items(WidgetTester tester) => [
    ...tester.element(field()).read<ListCubit>().state.items.values,
  ];

  const letters = ['M', 'Mi', 'Mil', 'Milc', 'Milch'];

  group('typing "Milch" faster than the typing pause', () {
    testWidgets('flag on: the typed row is the field after every key, and a '
        'tap adds "Milch"', (tester) async {
      await pumpList(tester, stable: true);
      repo.suggestGate = Completer<void>();
      await open(tester);
      for (final text in letters) {
        await key(tester, text);
        expect(label(tester, rowFor(text)), '$text, Wie getippt');
      }
      expect(row(0), findsNothing, reason: 'rows are keyed by what they add');
      await tester.tap(rowFor('Milch'));
      repo.suggestGate!.complete();
      await tester.pumpAndSettle();
      expect([for (final item in items(tester)) item.name], ['Milch']);
    });

    testWidgets('flag off (as before job 272): the typed row stays at the '
        'first letter, and a tap adds "M"', (tester) async {
      await pumpList(tester, stable: false);
      repo.suggestGate = Completer<void>();
      await open(tester);
      for (final text in letters) {
        await key(tester, text);
        expect(label(tester, row(0)), 'M, Wie getippt');
      }
      await tester.tap(row(0));
      repo.suggestGate!.complete();
      await tester.pumpAndSettle();
      expect([for (final item in items(tester)) item.name], ['M']);
    });
  });

  group('a row under a finger stays until the finger lifts', () {
    Future<TestGesture> pressHafermilch(WidgetTester tester) async {
      await pumpList(
        tester,
        stable: true,
        seed: (r) => r
          ..usuals = [const Usual(name: 'Hafermilch', due: false)]
          ..suggestions['Milch'] = const [
            Suggestion(SuggestionSource.typed, ParsedEntry(name: 'Milch')),
            Suggestion(
              SuggestionSource.history,
              ParsedEntry(name: 'Milchreis'),
            ),
            Suggestion(
              SuggestionSource.history,
              ParsedEntry(name: 'Hafermilch', storeId: 'lidl'),
            ),
          ],
      );
      final gate = repo.gates['Milch'] = Completer<void>();
      await open(tester);
      await typeAndPause(tester, 'Milch');
      expect(
        label(tester, rowFor('Hafermilch')),
        'Hafermilch, Schon mal gekauft',
      );
      // The sheet grows to its new rows before a finger finds one.
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(rowFor('Hafermilch')),
      );
      gate.complete();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        label(tester, rowFor('Hafermilch')),
        'Hafermilch, Schon mal gekauft',
        reason: 'the answer gives it a store, not while it is pressed',
      );
      expect(
        find.descendant(
          of: rowFor('Hafermilch'),
          matching: find.byType(StoreBadge),
        ),
        findsNothing,
      );
      expect(rowFor('Milchreis'), findsNothing);
      return gesture;
    }

    testWidgets('and its tap adds the row as it was shown', (tester) async {
      final gesture = await pressHafermilch(tester);
      await gesture.up();
      await tester.pumpAndSettle();
      final added = items(tester).single;
      expect((added.name, added.storeId), ('Hafermilch', null));
      expect(find.text('✓ Hinzugefügt: Hafermilch'), findsOneWidget);
    });

    testWidgets('but a finger on a chip holds nothing', (tester) async {
      await pumpList(
        tester,
        stable: true,
        seed: (r) => r
          ..usuals = [const Usual(name: 'Hafermilch', due: false)]
          ..suggestions['Milch'] = const [
            Suggestion(SuggestionSource.typed, ParsedEntry(name: 'Milch')),
            Suggestion(
              SuggestionSource.history,
              ParsedEntry(name: 'Hafermilch', storeId: 'lidl'),
            ),
          ],
      );
      final gate = repo.gates['Milch'] = Completer<void>();
      await open(tester);
      await typeAndPause(tester, 'Milch');
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('chip-category'))),
      );
      gate.complete();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        label(tester, rowFor('Hafermilch')),
        'Hafermilch, Schon mal gekauft, Lidl',
      );
      await gesture.cancel();
    });

    testWidgets('then shows the answer', (tester) async {
      final gesture = await pressHafermilch(tester);
      await gesture.cancel();
      await tester.pump();
      expect(
        label(tester, rowFor('Hafermilch')),
        'Hafermilch, Schon mal gekauft, Lidl',
      );
      expect(rowFor('Milchreis'), findsOneWidget);
      expect(items(tester), isEmpty, reason: 'a cancelled press adds nothing');
    });
  });

  group('with no finger down, the answer', () {
    testWidgets('keeps the shown rows where they are and adds its own '
        'below', (tester) async {
      await pumpList(
        tester,
        stable: true,
        seed: (r) => r
          ..usuals = [const Usual(name: 'Hafermilch', due: false)]
          ..suggestions['Milch'] = const [
            Suggestion(
              SuggestionSource.history,
              ParsedEntry(name: 'Milchreis'),
            ),
            Suggestion(
              SuggestionSource.history,
              ParsedEntry(name: 'Hafermilch', storeId: 'lidl'),
            ),
            Suggestion(SuggestionSource.typed, ParsedEntry(name: 'Milch')),
            Suggestion(
              SuggestionSource.history,
              ParsedEntry(name: 'Vollmilch'),
            ),
          ],
      );
      final gate = repo.gates['Milch'] = Completer<void>();
      await open(tester);
      await typeAndPause(tester, 'Milch');
      await tester.pumpAndSettle();
      expect(order(tester), ['Milch', 'Hafermilch']);
      gate.complete();
      await tester.pumpAndSettle();
      expect(label(tester, rowFor('Milch')), 'Milch, Wie getippt');
      expect(
        label(tester, rowFor('Hafermilch')),
        'Hafermilch, Schon mal gekauft, Lidl',
      );
      expect(
        order(tester),
        ['Milch', 'Hafermilch', 'Milchreis', 'Vollmilch'],
        reason:
            "the shown rows first as they were, the server's own after "
            'them in its order',
      );
    });
  });

  group('the typed line read on the device', () {
    void weihenstephan(FakeRepository r) {
      final now = DateTime.utc(2026, 11, 15);
      r.rows['m1'] = Item(
        id: 'm1',
        name: 'Milch',
        brand: 'Weihenstephan',
        status: ItemStatus.active,
        createdAt: now,
        updatedAt: now,
      );
    }

    for (final enter in [false, true]) {
      final how = enter ? 'Enter' : 'a tap';
      testWidgets('flag on: $how on "Weihenstephan Milch" with that milk '
          'open says it is on the list', (tester) async {
        await pumpList(tester, stable: true, seed: weihenstephan);
        repo.parsed['Weihenstephan Milch'] = const ParsedEntry(
          name: 'Milch',
          brand: 'Weihenstephan',
        );
        await open(tester);
        await typeAndPause(tester, 'Weihenstephan Milch');
        await tester.pumpAndSettle();
        expect(
          label(tester, rowFor('Weihenstephan Milch')),
          'Weihenstephan Milch, Wie getippt',
          reason: "the typed row keeps the device's reading",
        );
        if (enter) {
          await tester.testTextInput.receiveAction(TextInputAction.done);
        } else {
          await tester.tap(rowFor('Weihenstephan Milch'));
        }
        await tester.pumpAndSettle();
        expect(find.text('Milch steht schon auf der Liste'), findsOneWidget);
        expect(items(tester), hasLength(1));
        expect(repo.rows.keys, ['m1'], reason: 'nothing was queued');
      });
    }

    testWidgets('flag on: another line still adds', (tester) async {
      await pumpList(tester, stable: true, seed: weihenstephan);
      await open(tester);
      await typeAndPause(tester, 'Weihenstephan Joghurt');
      await tester.pumpAndSettle();
      await tester.tap(rowFor('Weihenstephan Joghurt'));
      await tester.pumpAndSettle();
      expect(find.text('✓ Hinzugefügt: Weihenstephan Joghurt'), findsOneWidget);
      expect(items(tester), hasLength(2));
    });
  });

  for (final stable in [true, false]) {
    final flag = stable ? 'on' : 'off';
    testWidgets("flag $flag: an older text's answer arriving last never "
        'replaces the rows for the newer one', (tester) async {
      await pumpList(
        tester,
        stable: stable,
        seed: (r) => r.suggestions
          ..['Mil'] = const [
            Suggestion(SuggestionSource.typed, ParsedEntry(name: 'Mil')),
            Suggestion(SuggestionSource.history, ParsedEntry(name: 'Mildessa')),
          ]
          ..['Milch'] = const [
            Suggestion(SuggestionSource.typed, ParsedEntry(name: 'Milch')),
            Suggestion(
              SuggestionSource.history,
              ParsedEntry(name: 'Milch', brand: 'Weihenstephan'),
            ),
          ],
      );
      final older = repo.gates['Mil'] = Completer<void>();
      final newer = repo.gates['Milch'] = Completer<void>();
      await open(tester);
      await typeAndPause(tester, 'Mil');
      await typeAndPause(tester, 'Milch');
      newer.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('Weihenstephan'), findsOneWidget);
      older.complete();
      await tester.pumpAndSettle();
      expect(find.text('Mildessa'), findsNothing);
      expect(find.textContaining('Weihenstephan'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('add-sheet')),
          matching: find.text('Mil'),
        ),
        findsNothing,
      );
    });
  }

  group('an add made offline', () {
    void groceryCategories(FakeRepository r) => r.categories = const [
      Category(
        id: 'produce',
        name: 'Obst & Gemüse',
        sortOrder: 10,
        seedKey: 'produce',
      ),
      Category(
        id: 'chilled',
        name: 'Kühlregal',
        sortOrder: 30,
        seedKey: 'chilled',
      ),
      Category(
        id: 'other',
        name: 'Sonstiges',
        sortOrder: 1000,
        seedKey: 'other',
      ),
    ];

    /// The category of the list's block that holds [name].
    String? blockOf(WidgetTester tester, String name) => tester
        .widgetList<CategoryDivider>(find.byType(CategoryDivider))
        .where((d) => d.block.items.any((i) => i.name == name))
        .single
        .block
        .category
        ?.id;

    testWidgets('flag on: sorts into the Kühlregal at once', (tester) async {
      await pumpList(tester, stable: true, seed: groceryCategories);
      repo.online = false;
      await open(tester);
      await typeAndPause(tester, 'Milch');
      await tester.tap(rowFor('Milch'));
      await tester.pumpAndSettle();
      expect(repo.rows, isEmpty, reason: 'nothing reached the server');
      expect(items(tester).single.categoryId, 'chilled');
      expect(blockOf(tester, 'Milch'), 'chilled');
    });

    testWidgets('flag off: waits unsorted for the server', (tester) async {
      await pumpList(tester, stable: false, seed: groceryCategories);
      repo.online = false;
      await open(tester);
      await typeAndPause(tester, 'Milch');
      await tester.tap(row(0));
      await tester.pumpAndSettle();
      expect(repo.rows, isEmpty, reason: 'nothing reached the server');
      expect(items(tester).single.categoryId, isNull);
      expect(blockOf(tester, 'Milch'), isNull);
    });
  });
}

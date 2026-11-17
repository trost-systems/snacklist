import 'dart:async';

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/app/localizations.dart';
import 'package:family_groceries/app/open_app.dart';
import 'package:family_groceries/household/household_switcher.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/add_sheet/add_sheet.dart';
import 'package:family_groceries/list/add_sheet/suggestion.dart';
import 'package:family_groceries/list/list_cache.dart' show noStoreKey;
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/list/list_view/dividers.dart';
import 'package:family_groceries/list/list_view/glide.dart';
import 'package:family_groceries/list/list_view/item_row.dart';
import 'package:family_groceries/list/list_view/shopping_list_view.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_repository.dart';
import 'memory_cache.dart';

/// [FakeRepository] whose suggest_entries answer for a text waits for that
/// text's gate.
class _GatedRepository() extends FakeRepository {
  final gates = <String, Completer<void>>{};

  @override
  Future<List<Suggestion>> suggest(String text) async {
    await gates[text]?.future;
    return await super.suggest(text);
  }
}

/// Job 276, flag `add-feedback-list`: each add lands in the list behind the
/// sheet, the sheet shows the item's details after an add, and a line and
/// dimmed rows tell that suggestions are loading.
void main() {
  late _GatedRepository repo;

  Future<void> pumpList(
    WidgetTester tester, {
    bool feedback = true,
    bool stable = true,
    bool still = false,
    void Function(FakeRepository repo)? seed,
  }) async {
    tester.view
      ..devicePixelRatio = 3
      ..physicalSize = const Size(390, 844) * 3
      ..padding = const FakeViewPadding(top: 47.0 * 3, bottom: 34.0 * 3);
    addTearDown(tester.view.reset);
    if (still) {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
    }
    repo = _GatedRepository()
      ..remoteAdd('Äpfel', storeId: 'lidl', categoryId: 'produce')
      ..remoteAdd('Joghurt', storeId: 'lidl', categoryId: 'chilled')
      ..remoteAdd('Seife', storeId: 'dm', categoryId: 'other');
    seed?.call(repo);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: MultiBlocProvider(
          providers: [
            BlocProvider(
              create: (_) => Flags(
                forced: {
                  if (feedback) addFeedbackListFlag,
                  if (stable) inputStableRowsFlag,
                },
              ),
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
  Finder justAdded() => find.byKey(const ValueKey('just-added'));
  Finder rowOf(String name) => find.widgetWithText(ItemRow, name);
  Finder suggestionFor(String name) =>
      find.byKey(ValueKey('suggestion-${foldName(name)}||'));

  ListCubit list(WidgetTester tester) =>
      tester.element(field()).read<ListCubit>();

  Item item(WidgetTester tester, String name) =>
      list(tester).state.items.values.singleWhere((i) => i.name == name);

  Future<void> open(WidgetTester tester) async {
    await tester.tap(field());
    await tester.pumpAndSettle();
  }

  Future<void> add(WidgetTester tester, String name) async {
    await tester.enterText(field(), name);
    await tester.pumpAndSettle();
    await tester.tap(suggestionFor(name));
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('add-sheet-close')));
  }

  /// How far [name]'s row is painted from its place in the layout.
  Offset shiftOf(WidgetTester tester, String name) => tester
      .renderObject<RenderGlide>(
        find.ancestor(of: rowOf(name), matching: find.byType(Glide)).first,
      )
      .paintShift;

  /// The top of the open sheet.
  double sheetTop(WidgetTester tester) =>
      tester.getTopLeft(find.byKey(const ValueKey('add-sheet-surface'))).dy;

  group('the list behind the open sheet', () {
    testWidgets('drops its headings, and each add lands under „Gerade '
        'hinzugefügt“ just above the sheet', (tester) async {
      await pumpList(tester);
      expect(find.byType(CategoryDivider), findsWidgets);
      expect(find.byType(StoreDivider), findsWidgets);

      await open(tester);
      expect(find.byType(CategoryDivider), findsNothing);
      expect(find.byType(StoreDivider), findsNothing);
      expect(rowOf('Joghurt'), findsOneWidget, reason: 'items stay');
      expect(justAdded(), findsNothing, reason: 'nothing added yet');

      await add(tester, 'Milch');
      expect(justAdded(), findsOneWidget);
      final milk = tester.getRect(rowOf('Milch'));
      expect(milk.top, greaterThan(tester.getRect(justAdded()).top));
      expect(milk.bottom, lessThanOrEqualTo(sheetTop(tester)));
      expect(milk.top, greaterThan(0), reason: 'in view');

      await add(tester, 'Brot');
      final bread = tester.getRect(rowOf('Brot'));
      expect(
        bread.top,
        greaterThanOrEqualTo(tester.getRect(rowOf('Milch')).bottom - 1),
        reason: 'in the order added',
      );
      expect(bread.bottom, lessThanOrEqualTo(sheetTop(tester)));
      expect(find.byType(CategoryDivider), findsNothing);
    });

    testWidgets('closing glides back into stores and categories, the adds '
        'in their places', (tester) async {
      await pumpList(tester);
      await open(tester);
      await add(tester, 'Milch');
      final landed = tester.getRect(rowOf('Milch'));
      await close(tester);
      await tester.pump();
      expect(
        tester.getTopLeft(rowOf('Milch')) + shiftOf(tester, 'Milch'),
        landed.topLeft,
        reason: 'the glide starts where the add was painted',
      );
      await tester.pump(glideDuration ~/ 2);
      expect(justAdded(), findsNothing);
      expect(find.byType(CategoryDivider), findsWidgets);
      expect(shiftOf(tester, 'Milch'), isNot(Offset.zero), reason: 'moving');
      await tester.pumpAndSettle();
      expect(shiftOf(tester, 'Milch'), Offset.zero);
      expect(justAdded(), findsNothing);
      expect(find.byType(StoreDivider), findsWidgets);
      final milk = item(tester, 'Milch');
      final block = find.byKey(
        ValueKey('category-${milk.storeId ?? noStoreKey}-${milk.categoryId}'),
      );
      expect(block, findsOneWidget);
      expect(
        tester.getTopLeft(rowOf('Milch')).dy,
        greaterThan(tester.getTopLeft(block).dy),
      );
    });

    testWidgets('reduced motion: back at once', (tester) async {
      await pumpList(tester, still: true);
      await open(tester);
      await add(tester, 'Milch');
      await close(tester);
      await tester.pump();
      expect(find.byType(CategoryDivider), findsWidgets);
      expect(justAdded(), findsNothing);
      expect(shiftOf(tester, 'Milch'), Offset.zero, reason: 'no glide');
      await tester.pumpAndSettle();
    });

    testWidgets("a partner's add while the sheet is open keeps the last "
        'add above the sheet', (tester) async {
      await pumpList(
        tester,
        seed: (r) {
          for (final name in ['Reis', 'Mehl', 'Zucker', 'Salz', 'Nudeln']) {
            r
              ..remoteAdd(name, storeId: 'dm', categoryId: 'other')
              ..remoteAdd('$name 2', storeId: 'lidl', categoryId: 'other');
          }
        },
      );
      await open(tester);
      await add(tester, 'Milch');
      expect(
        tester.getRect(rowOf('Milch')).bottom,
        moreOrLessEquals(sheetTop(tester), epsilon: 6),
      );
      repo.emitItem!(repo.remoteAdd('Kaffee', storeId: 'dm'));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(rowOf('Milch')).bottom,
        moreOrLessEquals(sheetTop(tester), epsilon: 6),
      );
      // Lea's add counts as seen after three seconds on screen, and the
      // list saves that.
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('flag off: the headings stay', (tester) async {
      await pumpList(tester, feedback: false);
      await open(tester);
      await add(tester, 'Milch');
      expect(find.byType(CategoryDivider), findsWidgets);
      expect(justAdded(), findsNothing);
    });
  });

  group('the details of the item just added', () {
    testWidgets('replace the rows until the next letter, at the same '
        'height', (tester) async {
      await pumpList(tester);
      await open(tester);
      await tester.enterText(field(), 'Milch');
      await tester.pumpAndSettle();
      final typing = tester.getRect(
        find.byKey(const ValueKey('add-sheet-surface')),
      );
      await tester.tap(suggestionFor('Milch'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('added-quantity')), findsOneWidget);
      expect(find.byKey(const ValueKey('added-brand')), findsOneWidget);
      expect(find.byKey(const ValueKey('added-properties')), findsOneWidget);
      expect(suggestionFor('Milch'), findsNothing);
      final details = tester.getRect(
        find.byKey(const ValueKey('add-sheet-surface')),
      );
      expect(details, typing, reason: 'the sheet does not jump');

      await tester.enterText(field(), 'B');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('added-quantity')), findsNothing);
      expect(suggestionFor('B'), findsOneWidget);
      expect(
        tester.getRect(find.byKey(const ValueKey('add-sheet-surface'))),
        typing,
      );
    });

    testWidgets('a stepper saves at once', (tester) async {
      await pumpList(tester);
      await open(tester);
      await add(tester, 'Milch');
      final plus = find.byKey(const ValueKey('added-quantity-plus'));
      await tester.ensureVisible(plus);
      await tester.pumpAndSettle();
      await tester.tap(plus);
      await tester.pump();
      expect(item(tester, 'Milch').quantity, '2');
    });

    testWidgets('typing saves after a pause', (tester) async {
      await pumpList(tester);
      await open(tester);
      await add(tester, 'Milch');
      await tester.enterText(
        find.byKey(const ValueKey('added-brand')),
        'Weihenstephan',
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(item(tester, 'Milch').brand, isNull);
      await tester.pump(const Duration(milliseconds: 150));
      expect(item(tester, 'Milch').brand, 'Weihenstephan');
    });

    testWidgets('the next letter in the input saves at once', (tester) async {
      await pumpList(tester);
      await open(tester);
      await add(tester, 'Milch');
      await tester.enterText(find.byKey(const ValueKey('added-quantity')), '3');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.enterText(field(), 'B');
      await tester.pump();
      expect(item(tester, 'Milch').quantity, '3');
    });

    testWidgets('typing while the sheet slides away is saved', (tester) async {
      await pumpList(tester);
      await open(tester);
      await add(tester, 'Milch');
      final quantity = find.byKey(const ValueKey('added-quantity'));
      await tester.enterText(quantity, '2');
      await close(tester);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.enterText(quantity, '3');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      expect(item(tester, 'Milch').quantity, '3');
    });

    testWidgets('closing the sheet saves at once', (tester) async {
      await pumpList(tester);
      await open(tester);
      await add(tester, 'Milch');
      await tester.enterText(
        find.byKey(const ValueKey('added-properties')),
        'laktosefrei',
      );
      await tester.pump(const Duration(milliseconds: 50));
      await close(tester);
      await tester.pump();
      expect(item(tester, 'Milch').properties, 'laktosefrei');
      await tester.pumpAndSettle();
    });
  });

  // Job 288: the store and category are picked in the added item's
  // details; the sheet has no chip row of its own.
  group('the store and category', () {
    Finder key(String key) => find.byKey(ValueKey(key));
    double sheetHeight(WidgetTester tester) =>
        tester.getSize(key('add-sheet-surface')).height;

    testWidgets('are not at the top of the sheet, also while typing, and '
        'the sheet keeps its height', (tester) async {
      await pumpList(tester);
      await open(tester);
      expect(key('chip-store'), findsNothing);
      expect(key('chip-category'), findsNothing);
      expect(key('add-sheet-close'), findsOneWidget);
      final first = sheetHeight(tester);

      await tester.enterText(field(), 'Mil');
      await tester.pumpAndSettle();
      expect(key('chip-store'), findsNothing);
      expect(key('chip-category'), findsNothing);
      expect(sheetHeight(tester), first);
    });

    testWidgets("sit in the added item's details, in one scrolling line "
        'with Menge', (tester) async {
      await pumpList(tester);
      await open(tester);
      await add(tester, 'Milch');
      final line = find.ancestor(
        of: key('chip-store'),
        matching: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
        ),
      );
      expect(line, findsOneWidget);
      for (final inside in ['chip-category', 'added-quantity', 'added-brand']) {
        expect(find.descendant(of: line, matching: key(inside)), findsOne);
      }
    });

    testWidgets('picked in the details save at once', (tester) async {
      await pumpList(tester);
      await open(tester);
      await add(tester, 'Milch');
      expect(item(tester, 'Milch').storeId, isNot('dm'));

      await tester.tap(key('chip-store'));
      await tester.pumpAndSettle();
      await tester.tap(key('store-option-dm'));
      await tester.pump();
      expect(item(tester, 'Milch').storeId, 'dm');
      await tester.pumpAndSettle();

      // Past the store's chip, at the line's end on a phone.
      await tester.ensureVisible(key('chip-category'));
      await tester.pumpAndSettle();
      await tester.tap(key('chip-category'));
      await tester.pumpAndSettle();
      final option = key('category-option-other');
      expect(
        option.hitTestable(),
        findsOneWidget,
        reason: 'the options come into view',
      );
      await tester.tap(option);
      await tester.pump();
      expect(item(tester, 'Milch').categoryId, 'other');
      expect(key('added-quantity'), findsOneWidget, reason: 'details stay');
      await tester.pumpAndSettle();
    });

    testWidgets('a chip opened out of view, by a screen reader, scrolls '
        'into view with its options', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpList(tester);
      await open(tester);
      await add(tester, 'Milch');
      final sheet = tester.getRect(
        find.byKey(const ValueKey('add-sheet-surface')),
      );
      expect(
        tester.getRect(key('chip-category')).right,
        greaterThan(sheet.right),
        reason: 'past the line end on a phone',
      );

      tester.semantics.tap(find.semantics.byLabel(RegExp('^Kategorie')));
      await tester.pumpAndSettle();
      final chip = tester.getRect(key('chip-category'));
      expect(chip.right, lessThanOrEqualTo(sheet.right));
      expect(chip.left, greaterThanOrEqualTo(sheet.left));
      expect(key('category-option-other').hitTestable(), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('flag off: the chips stay at the top', (tester) async {
      await pumpList(tester, feedback: false);
      await open(tester);
      expect(key('chip-store'), findsOneWidget);
      expect(key('chip-category'), findsOneWidget);
    });
  });

  group("the list's top bar while the sheet is open", () {
    const statusBar = 47.0;
    Finder edit() => find.byKey(const ValueKey('list-edit'));

    /// How strongly [finder] is painted: its ancestors' opacities.
    double shownOf(WidgetTester tester, Finder finder) {
      var alpha = 1.0;
      RenderObject? node = tester.renderObject(finder);
      while (node != null) {
        alpha *= switch (node) {
          RenderAnimatedOpacity(:final opacity) => opacity.value,
          RenderOpacity(:final opacity) => opacity,
          _ => 1.0,
        };
        node = node.parent;
      }
      return alpha;
    }

    testWidgets("goes, and the list's top starts under the status bar", (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpList(tester);
      expect(edit().hitTestable(), findsOneWidget);
      // The first thing below the bar: the hints' slot, then the rows.
      Finder listTop() => find.byType(OpenAppSlot, skipOffstage: false);
      expect(
        tester.getTopLeft(listTop()).dy,
        greaterThan(statusBar + 50),
        reason: 'below the bar',
      );

      await open(tester);
      expect(shownOf(tester, edit()), 0);
      expect(shownOf(tester, find.byType(HouseholdChip)), 0);
      expect(edit().hitTestable(), findsNothing);
      expect(find.semantics.byLabel('Anpassen'), findsNothing);
      expect(
        tester.getTopLeft(listTop()).dy,
        moreOrLessEquals(statusBar),
        reason: "the bar's room is the list's",
      );
      semantics.dispose();
    });

    testWidgets('comes back as the sheet closes, fading in', (tester) async {
      await pumpList(tester);
      await open(tester);
      await close(tester);
      await tester.pump();
      await tester.pump(glideDuration ~/ 2);
      expect(shownOf(tester, edit()), inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(shownOf(tester, edit()), 1);
      expect(edit().hitTestable(), findsOneWidget);
    });

    testWidgets('reduced motion: goes and comes back at once', (tester) async {
      await pumpList(tester, still: true);
      await tester.tap(field());
      await tester.pump();
      expect(shownOf(tester, edit()), 0);
      await tester.pumpAndSettle();
      await close(tester);
      await tester.pump();
      expect(shownOf(tester, edit()), 1);
      await tester.pumpAndSettle();
      expect(edit().hitTestable(), findsOneWidget);
    });

    testWidgets('flag off: stays', (tester) async {
      await pumpList(tester, feedback: false);
      final before = tester.getRect(edit());
      await open(tester);
      expect(shownOf(tester, edit()), 1);
      expect(tester.getRect(edit()), before);
    });
  });

  group('while suggestions load', () {
    double opacityOf(WidgetTester tester, Finder row) => tester
        .widget<AnimatedOpacity>(
          find.descendant(
            of: row,
            matching: find.byKey(const ValueKey('suggestion-stale')),
          ),
        )
        .opacity;

    Finder line() => find.byKey(const ValueKey('add-sheet-loading'));

    testWidgets('rows from an earlier text are dimmed, and the line shows '
        'after a short delay', (tester) async {
      await pumpList(tester, stable: false);
      await open(tester);
      await tester.enterText(field(), 'Mi');
      await tester.pumpAndSettle();
      final gate = repo.gates['Mil'] = Completer<void>();
      await tester.enterText(field(), 'Mil');
      await tester.pump();
      final row = find.byKey(const ValueKey('suggestion-0'));
      expect(opacityOf(tester, row), lessThan(1), reason: 'stale');
      // The typing pause, then the request.
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump();
      await tester.pump(loadLineDelay - const Duration(milliseconds: 10));
      expect(line(), findsNothing, reason: 'not before 150 ms');
      await tester.pump(const Duration(milliseconds: 10));
      expect(line(), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(line(), findsNothing);
      expect(opacityOf(tester, row), 1);
    });

    testWidgets('rows made on the device stay at full strength', (
      tester,
    ) async {
      await pumpList(tester);
      await open(tester);
      final gate = repo.gates['Mil'] = Completer<void>();
      await tester.enterText(field(), 'Mil');
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump();
      await tester.pump(loadLineDelay);
      expect(opacityOf(tester, suggestionFor('Mil')), 1);
      expect(line(), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(line(), findsNothing);
    });

    testWidgets('a quick answer never shows the line', (tester) async {
      await pumpList(tester);
      await open(tester);
      await tester.enterText(field(), 'Mil');
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        expect(line(), findsNothing);
      }
    });
  });
}

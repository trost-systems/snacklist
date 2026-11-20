import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/add_sheet/add_sheet_cubit.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/list/list_view/item_row.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/store_name_field.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../design/fonts.dart';
import 'fake_repository.dart';
import 'memory_cache.dart';

/// Job 322, AS1, flag `add-sheet-compact` on top of `add-feedback-list`: no
/// close key, no added note and no Rückgängig after an add, one row of
/// chips for the item just added, the list behind only the last two adds,
/// and a sheet that closes by a tap beside it, its handle, a swipe down,
/// the system back or Enter in the empty field.
void main() {
  late FakeRepository repo;

  // Real glyphs: the in-view proof measures the app's text, not boxes.
  setUpAll(loadAppFonts);

  const phone = Size(390, 844);

  Future<void> pumpList(
    WidgetTester tester, {
    bool compact = true,
    Size size = phone,
    double textScale = 1,
    double keyboard = 0,
    void Function(FakeRepository repo)? seed,
  }) async {
    tester.view
      ..devicePixelRatio = 3
      ..physicalSize = size * 3
      ..padding = FakeViewPadding(
        top: 47.0 * 3,
        bottom: keyboard > 0 ? 0 : 34.0 * 3,
      )
      ..viewInsets = FakeViewPadding(bottom: keyboard * 3);
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    repo = FakeRepository()
      ..canonical.addAll({'Möhren': 'mohr', 'Karotten': 'mohr'})
      ..remoteAdd('Äpfel', storeId: 'lidl', categoryId: 'produce')
      ..remoteAdd('Joghurt', storeId: 'lidl', categoryId: 'chilled')
      ..remoteAdd('Seife', storeId: 'dm', categoryId: 'other');
    seed?.call(repo);
    final list = ListCubit(repo, MemoryListCache(), userId: 'peter')..start();
    final flags = Flags(
      forced: {
        addFeedbackListFlag,
        inputStableRowsFlag,
        if (compact) addSheetCompactFlag,
      },
    );
    addTearDown(list.close);
    addTearDown(flags.close);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: flags),
          BlocProvider.value(value: list),
        ],
        child: MaterialApp.router(
          theme: appTheme(Brightness.light),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                // The shell's scaffold makes room for the keyboard.
                builder: (_, _) => const Scaffold(body: ShoppingList()),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder key(String key) => find.byKey(ValueKey(key));
  Finder field() => key('add-item-field');
  Finder sheet() => key('add-sheet');
  Finder inSheet(Finder f) => find.descendant(of: sheet(), matching: f);
  Finder rowOf(String name) =>
      find.byWidgetPredicate((w) => w is ItemRow && w.item.name == name);
  Finder suggestionFor(String name) => key('suggestion-${foldName(name)}||');

  AddSheetCubit sheetCubit(WidgetTester tester) =>
      tester.element(field()).read<AddSheetCubit>();
  Item item(WidgetTester tester, String name) => tester
      .element(field())
      .read<ListCubit>()
      .state
      .items
      .values
      .singleWhere((i) => i.name == name);

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

  Future<void> expectClosed(WidgetTester tester) async {
    await tester.pumpAndSettle();
    expect(sheetCubit(tester).state.open, isFalse);
    expect(sheet(), findsNothing);
  }

  group('after an add', () {
    testWidgets('no close key, no added note, no Rückgängig: one row of '
        'chips', (tester) async {
      await pumpList(tester);
      await open(tester);
      expect(key('add-sheet-close'), findsNothing);
      await add(tester, 'Milch');
      expect(key('add-sheet-close'), findsNothing);
      expect(key('added-note'), findsNothing);
      expect(key('added-undo'), findsNothing);
      expect(find.textContaining('Hinzugefügt'), findsNothing);
      for (final control in [
        'added-quantity-minus',
        'added-quantity',
        'added-quantity-plus',
        'chip-store',
        'chip-category',
        'chip-details',
      ]) {
        expect(inSheet(key(control)).hitTestable(), findsOneWidget);
      }
      expect(key('added-brand'), findsNothing, reason: 'no brand field');
      expect(key('added-properties'), findsNothing, reason: 'folded');
      final chips = [
        for (final k in ['added-quantity', 'chip-store', 'chip-category'])
          tester.getRect(key(k)),
      ];
      expect(
        chips.map((r) => r.center.dy.round()).toSet(),
        hasLength(1),
        reason: 'one row on a phone',
      );
    });

    testWidgets('the steppers save at once', (tester) async {
      await pumpList(tester);
      await open(tester);
      await add(tester, 'Milch');
      final minus = tester.widget<IconButton>(key('added-quantity-minus'));
      expect(minus.onPressed, isNull, reason: 'nothing below one');
      await tester.tap(key('added-quantity-plus'));
      await tester.pump();
      expect(item(tester, 'Milch').quantity, '2');
      await tester.tap(key('added-quantity-plus'));
      await tester.pump();
      await tester.tap(key('added-quantity-minus'));
      await tester.pump();
      expect(item(tester, 'Milch').quantity, '2');
      await tester.pumpAndSettle();
    });

    testWidgets('typing a quantity saves after a pause', (tester) async {
      await pumpList(tester);
      await open(tester);
      await add(tester, 'Milch');
      await tester.enterText(key('added-quantity'), '3');
      await tester.pump(const Duration(milliseconds: 400));
      expect(item(tester, 'Milch').quantity, isNull);
      await tester.pump(const Duration(milliseconds: 150));
      expect(item(tester, 'Milch').quantity, '3');
    });

    testWidgets('a store and a category picked save at once; one picker '
        'opens at a time, its options in one sideways line', (tester) async {
      await pumpList(tester);
      await open(tester);
      await add(tester, 'Milch');

      await tester.tap(key('chip-store'));
      await tester.pumpAndSettle();
      expect(key('options-line'), findsOneWidget);
      expect(_scrollsSideways(tester, key('store-option-dm')), isTrue);
      await tester.tap(key('chip-category'));
      await tester.pumpAndSettle();
      expect(key('store-option-dm'), findsNothing, reason: 'one at a time');
      expect(_scrollsSideways(tester, key('category-option-other')), isTrue);
      await tester.tap(key('chip-details'));
      await tester.pumpAndSettle();
      expect(key('options-line'), findsNothing);
      expect(key('added-properties'), findsOneWidget);
      await tester.tap(key('chip-store'));
      await tester.pumpAndSettle();
      expect(key('added-properties'), findsNothing);

      await tester.tap(key('store-option-dm'));
      await tester.pump();
      expect(item(tester, 'Milch').storeId, 'dm');
      await tester.pumpAndSettle();
      expect(key('options-line'), findsNothing, reason: 'a pick folds it');

      await tester.tap(key('chip-category'));
      await tester.pumpAndSettle();
      await tester.tap(key('category-option-other'));
      await tester.pump();
      expect(item(tester, 'Milch').categoryId, 'other');
      await tester.pumpAndSettle();
      expect(key('added-quantity'), findsOneWidget, reason: 'the chips stay');
    });

    testWidgets("the open picker shows the item's own option", (tester) async {
      await pumpList(
        tester,
        seed: (repo) => repo
          ..categories = [
            for (var i = 0; i < 14; i++)
              Category(id: 'c$i', name: 'Kategorie $i', sortOrder: i),
          ]
          ..parsed['Milch'] = const ParsedEntry(
            name: 'Milch',
            categoryId: 'c13',
          ),
      );
      await open(tester);
      await add(tester, 'Milch');
      expect(item(tester, 'Milch').categoryId, 'c13');
      await tester.tap(key('chip-category'));
      await tester.pumpAndSettle();
      final surface = tester.getRect(key('add-sheet-surface'));
      final own = tester.getRect(key('category-option-c13'));
      expect(own.left, greaterThanOrEqualTo(surface.left));
      expect(own.right, lessThanOrEqualTo(surface.right));
      expect(key('category-option-c13').hitTestable(), findsOneWidget);
      expect(
        tester.getRect(key('category-option-c0')).right,
        lessThan(surface.left),
        reason: 'the line scrolled to it',
      );
    });

    testWidgets('the details chip shows brand and details; its field edits '
        'only the details', (tester) async {
      await pumpList(
        tester,
        seed: (repo) => repo.parsed['Milch'] = const ParsedEntry(
          name: 'Milch',
          brand: 'Weihenstephan',
          properties: 'laktosefrei',
          categoryId: 'chilled',
        ),
      );
      await open(tester);
      await add(tester, 'Milch');
      expect(item(tester, 'Milch').brand, 'Weihenstephan');
      expect(
        find.descendant(
          of: key('chip-details'),
          matching: find.text('Weihenstephan, laktosefrei'),
        ),
        findsOneWidget,
      );
      expect(key('added-brand'), findsNothing);

      await tester.tap(key('chip-details'));
      await tester.pumpAndSettle();
      final properties = key('added-properties');
      expect(
        find
            .descendant(of: properties, matching: find.byType(EditableText))
            .evaluate()
            .single
            .widget,
        isA<EditableText>().having((e) => e.focusNode.hasFocus, 'focus', true),
      );
      await tester.enterText(properties, 'Bio, 1 l');
      await tester.pump(const Duration(milliseconds: 550));
      expect(item(tester, 'Milch').properties, 'Bio, 1 l');
      expect(item(tester, 'Milch').brand, 'Weihenstephan');

      await tester.enterText(properties, 'Bio');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(item(tester, 'Milch').properties, 'Bio', reason: 'Enter saves');
      expect(properties, findsNothing, reason: 'Enter folds it');
      final input = tester.widget<EditableText>(
        find.descendant(of: field(), matching: find.byType(EditableText)),
      );
      expect(input.focusNode.hasFocus, isTrue, reason: 'back to the input');
    });
  });

  group('duplicates, as without the flag', () {
    testWidgets('an item already on the list says so, without Rückgängig', (
      tester,
    ) async {
      await pumpList(tester);
      await open(tester);
      await add(tester, 'Äpfel');
      expect(
        inSheet(find.text('Äpfel steht schon auf der Liste')),
        findsOneWidget,
      );
      expect(key('added-undo'), findsNothing);
    });

    testWidgets('the merge hint with Zusammenführen, and the merge with '
        'its Rückgängig', (tester) async {
      await pumpList(
        tester,
        seed: (repo) =>
            repo.remoteAdd('Möhren', categoryId: 'produce', quantity: '500 g'),
      );
      await open(tester);
      repo.parsed['1 kg Karotten'] = const ParsedEntry(
        name: 'Karotten',
        quantity: '1 kg',
        categoryId: 'produce',
      );
      await tester.enterText(field(), '1 kg Karotten');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
      expect(key('dedupe-hint'), findsOneWidget);
      expect(
        inSheet(find.text('Möhren steht schon auf der Liste')),
        findsOneWidget,
      );
      expect(
        tester.getRect(key('dedupe-hint')).bottom,
        lessThanOrEqualTo(tester.getRect(key('chip-store')).top),
        reason: 'above the chips',
      );
      await tester.tap(key('dedupe-merge'));
      await tester.pumpAndSettle();
      expect(
        inSheet(find.text('Zusammengeführt: 1,5 kg Möhren')),
        findsOneWidget,
      );
      await tester.tap(key('dedupe-undo'));
      await tester.pumpAndSettle();
      expect(
        repo.rows.values
            .where((i) => i.status == ItemStatus.active)
            .map((i) => i.name),
        containsAll(['Möhren', 'Karotten']),
      );
    });
  });

  group('closing', () {
    testWidgets('a tap beside the sheet', (tester) async {
      await pumpList(tester);
      await open(tester);
      await tester.tapAt(const Offset(200, 150));
      await expectClosed(tester);
    });

    testWidgets('a tap on a row behind it', (tester) async {
      await pumpList(tester);
      await open(tester);
      await add(tester, 'Milch');
      await tester.tapAt(tester.getCenter(rowOf('Milch')));
      await expectClosed(tester);
      expect(item(tester, 'Milch').status, ItemStatus.active);
    });

    testWidgets('a tap on the handle', (tester) async {
      await pumpList(tester);
      await open(tester);
      await tester.tap(key('add-sheet-grabber'));
      await expectClosed(tester);
    });

    testWidgets('the handle is Schließen for a screen reader', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpList(tester);
      await open(tester);
      expect(
        tester.getSemantics(key('add-sheet-grabber')),
        matchesSemantics(
          label: 'Schließen',
          isButton: true,
          hasTapAction: true,
        ),
      );
      tester.semantics.tap(find.semantics.byLabel('Schließen'));
      await expectClosed(tester);
      semantics.dispose();
    });

    testWidgets('a swipe down', (tester) async {
      await pumpList(tester);
      await open(tester);
      await add(tester, 'Milch');
      await tester.drag(key('chip-category'), const Offset(0, 120));
      await expectClosed(tester);
    });

    testWidgets('a short swipe up keeps it open', (tester) async {
      await pumpList(tester);
      await open(tester);
      await add(tester, 'Milch');
      await tester.drag(key('chip-category'), const Offset(0, -60));
      await tester.pumpAndSettle();
      expect(sheetCubit(tester).state.open, isTrue);
    });

    testWidgets('the system back', (tester) async {
      await pumpList(tester);
      await open(tester);
      await add(tester, 'Milch');
      expect(await tester.binding.handlePopRoute(), isTrue);
      await expectClosed(tester);
    });

    testWidgets("the system back first cancels a new store's name", (
      tester,
    ) async {
      await pumpList(tester);
      await open(tester);
      await add(tester, 'Milch');
      await tester.tap(key('chip-store'));
      await tester.pumpAndSettle();
      await tester.tap(key('store-option-new'));
      await tester.pumpAndSettle();
      expect(find.byType(StoreNameField), findsOneWidget);
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.byType(StoreNameField), findsNothing);
      expect(sheetCubit(tester).state.open, isTrue);
      expect(await tester.binding.handlePopRoute(), isTrue);
      await expectClosed(tester);
    });

    testWidgets('Enter in the empty field; with text it adds', (tester) async {
      await pumpList(tester);
      await open(tester);
      await tester.enterText(field(), 'Milch');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
      expect(sheetCubit(tester).state.open, isTrue);
      expect(item(tester, 'Milch').status, ItemStatus.active);
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await expectClosed(tester);
    });
  });

  group('the list behind the sheet', () {
    testWidgets('is empty before the first add, then shows only the last '
        'two adds right above the sheet, without a heading', (tester) async {
      await pumpList(tester);
      expect(rowOf('Äpfel'), findsOneWidget);
      await open(tester);
      for (final name in ['Äpfel', 'Joghurt', 'Seife']) {
        expect(rowOf(name), findsNothing, reason: name);
      }
      await add(tester, 'Milch');
      expect(rowOf('Milch'), findsOneWidget);
      expect(rowOf('Äpfel'), findsNothing);
      expect(key('just-added'), findsNothing);
      await add(tester, 'Brot');
      await add(tester, 'Eier');
      expect(rowOf('Milch'), findsNothing);
      expect(rowOf('Brot'), findsOneWidget);
      expect(rowOf('Eier'), findsOneWidget);
      expect(key('just-added'), findsNothing);
      final top = tester.getRect(key('add-sheet-surface')).top;
      expect(
        tester.getRect(rowOf('Brot')).bottom,
        lessThanOrEqualTo(tester.getRect(rowOf('Eier')).top),
        reason: 'the newest lowest',
      );
      expect(tester.getRect(rowOf('Eier')).bottom, closeTo(top - 4, 2));
    });

    testWidgets('starts empty again when the sheet opens again', (
      tester,
    ) async {
      await pumpList(tester);
      await open(tester);
      await add(tester, 'Milch');
      await tester.tap(key('add-sheet-grabber'));
      await tester.pumpAndSettle();
      expect(rowOf('Äpfel'), findsOneWidget);
      await open(tester);
      expect(rowOf('Milch'), findsNothing);
    });
  });

  testWidgets('typing shows at most three rows, then the chips come back', (
    tester,
  ) async {
    await pumpList(tester);
    await open(tester);
    await add(tester, 'Milch');
    final afterAdd = tester.getRect(key('add-sheet-surface'));
    await tester.enterText(field(), 'B');
    await tester.pumpAndSettle();
    expect(key('chip-store'), findsNothing);
    final rows = tester.getRect(key('add-suggestions'));
    expect(rows.height, lessThanOrEqualTo(3 * 60 + 0.5));
    expect(
      tester.getRect(key('add-sheet-surface')).top,
      closeTo(rows.top - 12, 0.5),
      reason: 'as tall as the handle and the rows',
    );
    await tester.tap(suggestionFor('B'));
    await tester.pumpAndSettle();
    expect(key('chip-store'), findsOneWidget);
    expect(tester.getRect(key('add-sheet-surface')), afterAdd);
  });

  group('every control in view above the keyboard', () {
    for (final (size, keyboard, scales) in [
      (phone, 336.0, [1.0, 2.0, 3.1]),
      (const Size(360, 640), 280.0, [2.0]),
    ]) {
      for (final scale in scales) {
        // The fake's names are the shortest the app shows; the demo
        // household's own store and a common category are what wraps.
        for (final long in [false, true]) {
          testWidgets('${size.width.toInt()}×${size.height.toInt()}, text '
              '$scale${long ? ', long names' : ''}', (tester) async {
            await pumpList(
              tester,
              size: size,
              textScale: scale,
              keyboard: keyboard,
              seed: (repo) {
                repo.parsed['Milch'] = const ParsedEntry(
                  name: 'Milch',
                  properties: 'laktosefrei',
                  categoryId: 'chilled',
                  storeId: 'lidl',
                );
                if (long) {
                  repo
                    ..stores = Catalog(stores: repo.stores)
                        .withStoreName('lidl', 'Hofladen Sonnenhang')
                        .stores
                    ..categories = Catalog(categories: repo.categories)
                        .withName('chilled', 'Vorrat & Konserven')
                        .categories;
                }
              },
            );
            await open(tester);
            await add(tester, 'Milch');
            final view = Rect.fromLTRB(
              0,
              47,
              size.width,
              size.height - keyboard,
            );
            void inView(String state, List<String> keys) {
              for (final k in keys) {
                final rect = tester.getRect(key(k));
                expect(
                  view.contains(rect.topLeft) &&
                      view.contains(
                        rect.bottomRight - const Offset(0.01, 0.01),
                      ),
                  isTrue,
                  reason: '$state: $k at $rect, outside $view',
                );
              }
              for (final scrollable in tester.stateList<ScrollableState>(
                inSheet(find.byType(Scrollable)),
              )) {
                final position = scrollable.position;
                if (position.axis == Axis.vertical) {
                  expect(position.maxScrollExtent, 0, reason: state);
                }
              }
            }

            const chips = [
              'add-item-field',
              'added-quantity-minus',
              'added-quantity',
              'added-quantity-plus',
              'chip-store',
              'chip-category',
              'chip-details',
            ];
            inView('folded', chips);
            final height =
                (size.height - keyboard) -
                tester.getRect(key('add-sheet-surface')).top;
            debugPrint(
              'compact sheet after an add, $size at $scale: '
              '${height.toStringAsFixed(1)} px from its top to the keyboard',
            );
            for (final (chip, panel) in [
              ('chip-store', 'store-option-lidl'),
              ('chip-category', 'category-option-chilled'),
              ('chip-details', 'added-properties'),
            ]) {
              await tester.tap(key(chip));
              await tester.pumpAndSettle();
              inView('$chip open', [...chips, panel]);
              if (panel != 'added-properties') {
                inView('$chip open', ['options-line']);
              }
              await tester.tap(key(chip));
              await tester.pumpAndSettle();
            }
          });
        }
      }
    }
  });

  group('flag off', () {
    testWidgets('the close key, the added note with Rückgängig and „Gerade '
        'hinzugefügt“ stay', (tester) async {
      await pumpList(tester, compact: false);
      await open(tester);
      expect(key('add-sheet-close'), findsOneWidget);
      expect(key('add-sheet-grabber'), findsNothing);
      await add(tester, 'Milch');
      expect(key('added-note'), findsOneWidget);
      expect(key('added-undo'), findsOneWidget);
      expect(key('just-added'), findsOneWidget);
      expect(rowOf('Äpfel'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
      expect(sheetCubit(tester).state.open, isTrue, reason: 'Enter keeps it');
    });
  });
}

/// Whether [option] sits in a line that scrolls sideways.
bool _scrollsSideways(WidgetTester tester, Finder option) => find
    .ancestor(
      of: option,
      matching: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
      ),
    )
    .evaluate()
    .isNotEmpty;

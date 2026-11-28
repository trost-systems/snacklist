import 'dart:io';

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/add_sheet/add_sheet_cubit.dart';
import 'package:family_groceries/list/add_sheet/suggestion.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/list/list_view/item_row.dart';
import 'package:family_groceries/list/list_view/shopping_list_view.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../design/fonts.dart';
import 'fake_repository.dart';
import 'memory_cache.dart';

/// Review screenshots, only when it is set:
///   SCREENSHOT_DIR=/tmp/490 flutter test --update-goldens \
///     test/list/add_ae2_list_peeks_test.dart
final _screenshots = Platform.environment['SCREENSHOT_DIR'];

/// Job 490, AE2, flag `add-ae2-list-peeks` on top of `add-sheet-compact`
/// and `add-match-rows`: the real list stays above the open add sheet with
/// its top bar, adds marked „Neu“ in their places and kept in view, a tap on
/// the list closes the sheet, the sheet shows two rows, and an item already
/// on the list is one row that merges (Enter's) or ticks it off.
void main() {
  late FakeRepository repo;

  setUpAll(loadAppFonts);

  const phone = Size(390, 844);

  Future<void> pumpList(
    WidgetTester tester, {
    bool peeks = true,
    Size size = phone,
    double textScale = 1,
    double keyboard = 0,
    Locale locale = const Locale('de'),
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
      ..remoteAdd('Äpfel', storeId: 'lidl', categoryId: 'produce')
      ..remoteAdd('Joghurt', storeId: 'lidl', categoryId: 'chilled')
      ..remoteAdd('Seife', storeId: 'dm', categoryId: 'other')
      ..parsed['Milch'] = const ParsedEntry(
        name: 'Milch',
        categoryId: 'chilled',
        storeId: 'lidl',
      );
    seed?.call(repo);
    final list = ListCubit(repo, MemoryListCache(), userId: 'peter')..start();
    final flags = Flags(
      forced: {
        addFeedbackListFlag,
        inputStableRowsFlag,
        addSheetCompactFlag,
        addMatchRowsFlag,
        if (peeks) addAe2ListPeeksFlag,
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
          locale: locale,
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => const Scaffold(body: ShoppingList()),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Twenty more items in Lidl's produce, the list's last group, so the
  /// list scrolls and its end is below the open sheet.
  void long(FakeRepository repo) {
    for (var i = 0; i < 20; i++) {
      repo.remoteAdd('Obst $i', storeId: 'lidl', categoryId: 'produce');
    }
    repo.parsed
      ..['Zitronen'] = const ParsedEntry(
        name: 'Zitronen',
        categoryId: 'produce',
        storeId: 'lidl',
      )
      ..['Zahnpasta'] = const ParsedEntry(
        name: 'Zahnpasta',
        categoryId: 'other',
        storeId: 'dm',
      );
  }

  Finder key(String key) => find.byKey(ValueKey(key));
  Finder field() => key('add-item-field');
  Finder rowOf(String name) =>
      find.byWidgetPredicate((w) => w is ItemRow && w.item.name == name);
  Finder suggestionFor(String name) => key('suggestion-${foldName(name)}||');
  Finder tagOf(String name, String text) =>
      find.descendant(of: rowOf(name), matching: find.text(text));

  AddSheetCubit sheetCubit(WidgetTester tester) =>
      tester.element(field()).read<AddSheetCubit>();
  List<Item> active(WidgetTester tester, String name) => [
    for (final item
        in tester.element(field()).read<ListCubit>().state.items.values)
      if (item.name == name && item.status == ItemStatus.active) item,
  ];
  ScrollPosition listScroll(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.descendant(
                of: find.byType(ShoppingListView),
                matching: find.byType(CustomScrollView),
              ),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;
  Finder split() => find.byWidgetPredicate((w) {
    final k = w.key;
    return k is ValueKey<String> && k.value.startsWith('match-split-remote');
  });

  Future<void> shoot(String name) async {
    if (_screenshots case final dir?) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(Uri.file('$dir/$name.png')),
      );
    }
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(field());
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(field(), text);
    await tester.pumpAndSettle();
  }

  Future<void> add(WidgetTester tester, String name) async {
    await type(tester, name);
    await tester.tap(suggestionFor(name));
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester) async {
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
  }

  /// The rows' room: below the top bar, above the sheet.
  Rect band(WidgetTester tester) => Rect.fromLTRB(
    0,
    tester.getRect(key('list-header')).bottom,
    phone.width,
    tester.getRect(key('add-sheet-surface')).top,
  );

  void expectInBand(WidgetTester tester, String name) {
    final row = tester.getRect(rowOf(name));
    final room = band(tester);
    expect(row.top, greaterThanOrEqualTo(room.top - 0.5), reason: name);
    expect(row.bottom, lessThanOrEqualTo(room.bottom + 0.5), reason: name);
  }

  group('the list above the open sheet', () {
    testWidgets('stays whole, with its top bar: no scrim, no swap', (
      tester,
    ) async {
      await pumpList(tester);
      await open(tester);
      expect(sheetCubit(tester).state.open, isTrue);
      expect(key('add-sheet-scrim'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == sheetBarrier,
        ),
        findsNothing,
      );
      for (final name in ['Seife', 'Joghurt']) {
        expectInBand(tester, name);
      }
      expect(rowOf('Äpfel'), findsOneWidget);
      expect(key('list-header'), findsOneWidget);
      expect(tester.getRect(key('list-header')).top, greaterThanOrEqualTo(0));
      await add(tester, 'Milch');
      expect(key('just-added'), findsNothing);
      expect(rowOf('Äpfel'), findsOneWidget, reason: 'no last-two swap');
    });

    for (final (locale, tag) in [
      (const Locale('de'), 'Neu'),
      (const Locale('en'), 'New'),
    ]) {
      testWidgets('an add lands in its place marked „$tag“ until the sheet '
          'closes (${locale.languageCode})', (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpList(tester, locale: locale);
        await open(tester);
        await add(tester, 'Milch');
        final joghurt = tester.getRect(rowOf('Joghurt'));
        final milch = tester.getRect(rowOf('Milch'));
        expect(milch.top, joghurt.bottom, reason: 'chilled, after Joghurt');
        expect(
          milch.bottom,
          lessThanOrEqualTo(tester.getRect(rowOf('Äpfel')).top),
          reason: "in Lidl's chilled, above its produce",
        );
        expect(
          milch.top,
          greaterThan(tester.getRect(rowOf('Seife')).bottom),
          reason: "below dm's section",
        );
        expect(tagOf('Milch', tag), findsOneWidget);
        expect(tagOf('Joghurt', tag), findsNothing);
        final milchId = active(tester, 'Milch').single.id;
        expect(
          tester
              .getSemantics(
                find.byWidgetPredicate(
                  (w) =>
                      w is Semantics &&
                      w.properties.identifier == itemSemanticsId(milchId),
                ),
              )
              .label,
          endsWith('\n$tag'),
        );
        await add(tester, 'Brot');
        await shoot('two-adds-${locale.languageCode}');
        expect(tagOf('Milch', tag), findsOneWidget, reason: 'still marked');
        expect(tagOf('Brot', tag), findsOneWidget);
        await tester.tap(key('add-sheet-grabber'));
        await tester.pumpAndSettle();
        expect(sheetCubit(tester).state.open, isFalse);
        expect(tagOf('Milch', tag), findsNothing);
        expect(tagOf('Brot', tag), findsNothing);
        await open(tester);
        expect(tagOf('Milch', tag), findsNothing, reason: 'a new opening');
        semantics.dispose();
      });
    }

    testWidgets('a tap on a row closes the sheet and ticks nothing', (
      tester,
    ) async {
      await pumpList(tester);
      await open(tester);
      await tester.tapAt(tester.getCenter(rowOf('Äpfel')));
      await tester.pumpAndSettle();
      expect(sheetCubit(tester).state.open, isFalse);
      expect(active(tester, 'Äpfel'), hasLength(1));
    });

    testWidgets('a screen reader still reads the rows, but cannot tick them '
        'while the sheet is open', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpList(tester);
      final id = active(tester, 'Joghurt').single.id;
      final row = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.identifier == itemSemanticsId(id),
      );
      expect(
        tester
            .getSemantics(row)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      await open(tester);
      final data = tester.getSemantics(row).getSemanticsData();
      expect(data.label, startsWith('Joghurt'));
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      semantics.dispose();
    });

    testWidgets('a tap on the top bar closes the sheet', (tester) async {
      await pumpList(tester);
      await open(tester);
      await tester.tapAt(tester.getCenter(key('list-edit')));
      await tester.pumpAndSettle();
      expect(sheetCubit(tester).state.open, isFalse);
      expect(find.byType(BottomSheet), findsNothing, reason: 'no Anpassen');
    });

    testWidgets('a drag scrolls the list and keeps the sheet open', (
      tester,
    ) async {
      await pumpList(tester, seed: long);
      await open(tester);
      final before = listScroll(tester).pixels;
      await tester.dragFrom(
        tester.getCenter(rowOf('Joghurt')),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      expect(sheetCubit(tester).state.open, isTrue);
      expect(listScroll(tester).pixels, greaterThan(before + 100));
      expect(active(tester, 'Joghurt'), hasLength(1));
    });

    testWidgets('an add in view scrolls nothing; one below the sheet '
        'scrolls just into view', (tester) async {
      await pumpList(tester, seed: long);
      await open(tester);
      final start = listScroll(tester).pixels;
      await add(tester, 'Zahnpasta');
      expectInBand(tester, 'Zahnpasta');
      expect(listScroll(tester).pixels, start, reason: 'next to Seife');
      await add(tester, 'Zitronen');
      expectInBand(tester, 'Zitronen');
      expect(listScroll(tester).pixels, greaterThan(start));
      expect(
        tester.getRect(rowOf('Zitronen')).bottom,
        closeTo(band(tester).bottom - 4, 2),
        reason: 'just far enough: right above the sheet',
      );
    });

    testWidgets('a match below the sheet scrolls into view while typing', (
      tester,
    ) async {
      await pumpList(
        tester,
        seed: (repo) {
          long(repo);
          repo.remoteAdd('Rhabarber', storeId: 'lidl', categoryId: 'produce');
        },
      );
      await open(tester);
      await type(tester, 'Rhabarber');
      expectInBand(tester, 'Rhabarber');
    });
  });

  group('an item already on the list (AE-Q2)', () {
    void bananen(FakeRepository repo) =>
        repo.remoteAdd('Bananen', quantity: '6', storeId: 'lidl');

    testWidgets('one row: merge and tick off; the + row second; the list '
        'row outlined with its Menge to be', (tester) async {
      await pumpList(tester, seed: bananen);
      await open(tester);
      await type(tester, 'Bananen');
      expect(split(), findsOneWidget);
      expect(
        find.descendant(of: split(), matching: find.text('7× Bananen')),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate((w) {
          final k = w.key;
          return k is ValueKey<String> && k.value.startsWith('match-TickRow');
        }),
        findsNothing,
        reason: 'the tick off is part of the one row',
      );
      final plus = tester.getRect(
        find.byWidgetPredicate((w) {
          final k = w.key;
          return k is ValueKey<String> && k.value.startsWith('suggestion-');
        }).first,
      );
      expect(plus.top, closeTo(tester.getRect(split()).bottom, 0.5));
      final id = active(tester, 'Bananen').single.id;
      expect(key('peek-match-$id'), findsOneWidget);
      expect(tagOf('Bananen', '→ 7×'), findsOneWidget);
      expectInBand(tester, 'Bananen');
      await shoot('duplicate-typing');
    });

    testWidgets('a tap on the merge part raises the Menge, no second row, '
        'and the list row shows the merge', (tester) async {
      await pumpList(tester, seed: bananen);
      await open(tester);
      await type(tester, 'Bananen');
      await tester.tap(key('match-split-merge'));
      await tester.pumpAndSettle();
      expect(active(tester, 'Bananen').single.quantity, '7');
      await shoot('duplicate-merged');
      expect(
        find.descendant(
          of: rowOf('Bananen'),
          matching: find.byIcon(Icons.call_merge),
        ),
        findsOneWidget,
      );
      expect(sheetCubit(tester).state.open, isTrue);
    });

    testWidgets('a tap on the tick button ticks it off', (tester) async {
      await pumpList(tester, seed: bananen);
      await open(tester);
      await type(tester, 'Bananen');
      await tester.tap(key('match-split-tick'));
      await tester.pumpAndSettle();
      expect(active(tester, 'Bananen'), isEmpty);
    });

    testWidgets('Enter merges: one row, 7×', (tester) async {
      await pumpList(tester, seed: bananen);
      await open(tester);
      await type(tester, 'Bananen');
      final merge = tester.widget<Container>(
        find
            .descendant(
              of: key('match-split-merge'),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(merge.foregroundDecoration, isNotNull, reason: "Enter's outline");
      await enter(tester);
      expect(active(tester, 'Bananen').single.quantity, '7');
      expect(repo.rows.values.where((i) => i.name == 'Bananen'), hasLength(1));
    });

    testWidgets('a Menge too long to merge: the tick row alone, Enter adds', (
      tester,
    ) async {
      await pumpList(
        tester,
        seed: (repo) => repo.remoteAdd(
          'Bananen',
          quantity: '1 Packung + 2 Tüten + 3 Beutel + 4 Dosen',
          storeId: 'lidl',
        ),
      );
      await open(tester);
      await type(tester, '5 Bananen');
      expect(split(), findsNothing);
      expect(
        find.byWidgetPredicate((w) {
          final k = w.key;
          return k is ValueKey<String> && k.value.startsWith('match-TickRow');
        }),
        findsOneWidget,
      );
      await enter(tester);
      expect(active(tester, 'Bananen'), hasLength(2));
    });

    for (final (locale, merge, tick) in [
      (const Locale('de'), 'Zusammenführen, 7× Bananen', 'Abhaken, Bananen'),
      (const Locale('en'), 'Merge, 7× Bananen', 'Tick off, Bananen'),
    ]) {
      testWidgets('two buttons for a screen reader '
          '(${locale.languageCode})', (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpList(tester, locale: locale, seed: bananen);
        await open(tester);
        await type(tester, 'Bananen');
        expect(
          tester.getSemantics(key('match-split-merge')),
          matchesSemantics(
            label: '$merge, Lidl',
            isButton: true,
            hasTapAction: true,
          ),
        );
        expect(
          tester.getSemantics(key('match-split-tick')),
          matchesSemantics(label: tick, isButton: true, hasTapAction: true),
        );
        semantics.dispose();
      });
    }

    testWidgets('Tab from the field reaches the merge and the tick button', (
      tester,
    ) async {
      await pumpList(tester, seed: bananen);
      await open(tester);
      await type(tester, 'Bananen');
      final reached = <String>{};
      for (var i = 0; i < 12; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        final focused = FocusManager.instance.primaryFocus?.context;
        for (final part in ['match-split-merge', 'match-split-tick']) {
          if (focused != null &&
              find
                  .ancestor(
                    of: find.byElementPredicate((e) => e == focused),
                    matching: key(part),
                  )
                  .evaluate()
                  .isNotEmpty) {
            reached.add(part);
          }
        }
      }
      expect(reached, {'match-split-merge', 'match-split-tick'});
    });

    testWidgets('200 % text with the keyboard: no overflow, both buttons '
        'whole and tappable', (tester) async {
      await pumpList(tester, seed: bananen, textScale: 2, keyboard: 336);
      await open(tester);
      await type(tester, 'Bananen');
      expect(tester.takeException(), isNull);
      await shoot('duplicate-200');
      final screen = Offset.zero & phone;
      for (final part in ['match-split-merge', 'match-split-tick']) {
        final rect = tester.getRect(key(part));
        expect(screen.intersect(rect), rect, reason: part);
        expect(rect.height, greaterThanOrEqualTo(48), reason: part);
        expect(rect.width, greaterThanOrEqualTo(48), reason: part);
      }
      await tester.tap(key('match-split-tick'));
      await tester.pumpAndSettle();
      expect(active(tester, 'Bananen'), isEmpty);
    });
  });

  testWidgets('two suggestion rows, typed or not, before the list scrolls', (
    tester,
  ) async {
    const names = ['Joghu', 'Joghurtdrink', 'Sojajoghurt', 'Trinkjoghurt'];
    await pumpList(
      tester,
      seed: (repo) => repo
        ..usuals = [
          for (final name in ['Hafermilch', 'Butter', 'Käse', 'Brot'])
            Usual(name: name, due: true),
        ]
        ..suggestions['Joghu'] = [
          for (final (i, name) in names.indexed)
            Suggestion(
              i == 0 ? SuggestionSource.typed : SuggestionSource.catalog,
              ParsedEntry(name: name),
            ),
        ],
    );
    await open(tester);
    final opened = tester.getRect(key('add-suggestions'));
    expect(opened.height, closeTo(2 * 60, 1));
    await type(tester, 'Joghu');
    final typing = tester.getRect(key('add-suggestions'));
    expect(typing.height, closeTo(2 * 60, 1));
  });

  group('flag off, as before', () {
    testWidgets('the scrim and the last two adds; Enter on a duplicate adds '
        'a second row', (tester) async {
      await pumpList(
        tester,
        peeks: false,
        seed: (repo) => repo.remoteAdd('Bananen', quantity: '6'),
      );
      await open(tester);
      expect(key('add-sheet-scrim'), findsOneWidget);
      expect(rowOf('Äpfel'), findsNothing);
      await type(tester, 'Bananen');
      expect(split(), findsNothing);
      await enter(tester);
      expect(active(tester, 'Bananen'), hasLength(2));
      expect(rowOf('Äpfel'), findsNothing);
    });
  });
}

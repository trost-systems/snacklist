import 'dart:io';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/analytics/events.dart';
import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/design/look.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/add_sheet/add_sheet_cubit.dart';
import 'package:family_groceries/list/add_sheet/match_rows.dart';
import 'package:family_groceries/list/add_sheet/suggestion.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../design/fonts.dart';
import 'fake_repository.dart';
import 'memory_cache.dart';

/// Job 473's review screenshots, only when it is set:
///   SCREENSHOT_DIR=$PWD/../docs/screenshots/473 flutter test --update-goldens \
///     test/list/add_match_rows_test.dart
final _screenshots = Platform.environment['SCREENSHOT_DIR'];

/// Every event the list sends, checked against the allow-list.
class _Tracked() implements Analytics {
  final events = <(String, Map<String, Object>)>[];

  @override
  void track(String event, [Map<String, Object> properties = const {}]) {
    checkEvent(event, properties);
    events.add((event, properties));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Job 324, AM2, flag `add-match-rows` on top of `add-sheet-compact`: while
/// typing, the items already on the list that are the same thing show as
/// rows in the sheet (merge, tick off, back on the list), above the + row,
/// which, like Enter, adds the typed item separately.
void main() {
  late FakeRepository repo;
  late _Tracked tracked;

  setUpAll(loadAppFonts);

  const phone = Size(390, 844);

  Future<void> pumpList(
    WidgetTester tester, {
    required void Function(FakeRepository repo) seed,
    bool matchRows = true,
    Size size = phone,
    double textScale = 1,
    double keyboard = 0,
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
    tracked = _Tracked();
    repo = FakeRepository()
      ..remoteAdd('Joghurt', storeId: 'lidl', categoryId: 'chilled');
    seed(repo);
    final list = ListCubit(
      repo,
      MemoryListCache(),
      userId: 'peter',
      analytics: tracked,
    )..start();
    final flags = Flags(
      forced: {
        addFeedbackListFlag,
        inputStableRowsFlag,
        addSheetCompactFlag,
        if (matchRows) addMatchRowsFlag,
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
                builder: (_, _) => const Scaffold(body: ShoppingList()),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder keyed(bool Function(String) test) => find.byWidgetPredicate((w) {
    final k = w.key;
    return k is ValueKey<String> && test(k.value);
  });

  /// The [n]th widget [keyed] finds, or nothing: `.at` throws past the end.
  Finder nth(bool Function(String) test, int n) {
    final found = keyed(test).evaluate().toList();
    return n < found.length
        ? find.byWidget(found[n].widget)
        : find.byKey(const ValueKey('no-such-row'));
  }

  /// 'match-N': the Nth match tile (keyed by content since job 340);
  /// 'match-plus': the first suggestion row, the + row.
  Finder key(String key) {
    if (RegExp(r'^match-\d+$').hasMatch(key)) {
      return nth(
        (v) => v.startsWith('match-') && v != 'match-note',
        int.parse(key.substring(6)),
      );
    }
    if (key == 'match-plus') {
      return nth((v) => v.startsWith('suggestion-'), 0);
    }
    return find.byKey(ValueKey(key));
  }

  Finder field() => key('add-item-field');
  Finder sheet() => key('add-sheet');
  Finder inSheet(Finder f) => find.descendant(of: sheet(), matching: f);
  Finder textIn(String k, String text) =>
      find.descendant(of: key(k), matching: find.text(text));

  ListState listState(WidgetTester tester) =>
      tester.element(field()).read<ListCubit>().state;
  List<Item> named(WidgetTester tester, String name) => [
    for (final item in listState(tester).items.values)
      if (item.name == name) item,
  ];
  List<Item> active(WidgetTester tester, String name) => [
    for (final item in named(tester, name))
      if (item.status == ItemStatus.active) item,
  ];
  String typed(WidgetTester tester) => tester
      .widget<EditableText>(
        find.descendant(of: field(), matching: find.byType(EditableText)),
      )
      .controller
      .text;

  /// The match events, an outcome after a colon.
  List<String> matchEvents() => [
    for (final (event, properties) in tracked.events)
      if (event.startsWith('add_match'))
        [event, ?properties['outcome']].join(':'),
  ];

  Future<void> type(WidgetTester tester, String text) async {
    await tester.tap(field());
    await tester.pumpAndSettle();
    await tester.enterText(field(), text);
    await tester.pumpAndSettle();
  }

  Future<void> shoot(String name) async {
    if (_screenshots case final dir?) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(Uri.file('$dir/$name.png')),
      );
    }
  }

  Future<void> enter(WidgetTester tester) async {
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
  }

  group('an open match', () {
    testWidgets('merge, tick off and a + row; Enter adds a second Nudeln, '
        'without the duplicate note', (tester) async {
      await pumpList(tester, seed: (repo) => repo.remoteAdd('Nudeln'));
      await type(tester, 'Nudeln');
      expect(textIn('match-0', '2× Nudeln'), findsOneWidget);
      expect(textIn('match-1', 'Nudeln'), findsOneWidget);
      final struck = tester.widget<Text>(textIn('match-1', 'Nudeln'));
      expect(struck.style?.decoration, TextDecoration.lineThrough);
      expect(key('match-2'), findsNothing);
      expect(key('match-plus'), findsOneWidget);
      expect(
        tester.getRect(key('match-1')).bottom,
        lessThanOrEqualTo(tester.getRect(key('match-plus')).top),
        reason: 'the + row below the matches',
      );
      expect(
        tester.getRect(key('match-plus')).bottom,
        lessThanOrEqualTo(tester.getRect(field()).top),
        reason: 'and above the field',
      );
      for (final k in ['match-0', 'match-1', 'match-plus']) {
        final rect = tester.getRect(key(k));
        final list = tester.getRect(key('add-suggestions'));
        expect(rect.left, list.left, reason: '$k is full width');
        expect(rect.right, list.right, reason: '$k is full width');
      }
      final materials = tester.widgetList<Material>(
        find.descendant(
          of: key('add-suggestions'),
          matching: find.byType(Material),
        ),
      );
      expect(materials, hasLength(greaterThan(1)));
      // Job 497: the first row takes the sheet's top corners, the
      // add_sheet_top_row_test pins how they look.
      expect(
        materials.first.borderRadius,
        BorderRadius.vertical(top: Radius.circular(sheetRadius)),
        reason: 'the top row follows the sheet',
      );
      for (final material in materials.skip(1)) {
        expect(material.borderRadius, isNull, reason: 'square rows');
        expect(material.shape, isNull, reason: 'no rounded tiles');
      }
      expect(
        tester.getRect(key('match-1')).top,
        tester.getRect(key('match-0')).bottom,
        reason: 'rows touch: no gap between tiles',
      );
      expect(
        inSheet(find.byIcon(Icons.keyboard_return)),
        findsNothing,
        reason: 'no return key any more (job 340)',
      );
      expect(matchEvents(), ['add_match_shown']);

      await enter(tester);
      expect(active(tester, 'Nudeln'), hasLength(2));
      final add = repo.sent.whereType<AddItem>().last;
      expect(add.separate, isTrue);
      expect(repo.rows.values.where((i) => i.name == 'Nudeln'), hasLength(2));
      expect(key('match-0'), findsNothing, reason: 'the field cleared');
      expect(key('dedupe-hint'), findsNothing);
      expect(find.textContaining('schon auf der Liste'), findsNothing);
      expect(matchEvents().last, 'add_match_outcome:separate');
    });

    testWidgets('one list: matches, the + row, then the other suggestions', (
      tester,
    ) async {
      await pumpList(
        tester,
        seed: (repo) => repo
          ..remoteAdd('Nudeln')
          ..suggestions['Nudeln'] = [
            const Suggestion(
              SuggestionSource.typed,
              ParsedEntry(name: 'Nudeln'),
            ),
            const Suggestion(
              SuggestionSource.history,
              ParsedEntry(name: 'Nudeln Vollkorn'),
            ),
          ],
      );
      await type(tester, 'Nudeln');
      final list = key('add-suggestions');
      expect(find.byType(Scrollable), findsWidgets);
      expect(
        find.descendant(of: list, matching: find.byType(Scrollable)),
        findsOneWidget,
        reason: 'one scrollable list',
      );
      expect(key('match-note'), findsNothing);
      final tops = [
        tester.getRect(key('match-0')).top,
        tester.getRect(key('match-1')).top,
        tester.getRect(key('match-plus')).top,
      ];
      expect(tops, orderedEquals([...tops]..sort()), reason: 'in order');
      expect(tops.toSet(), hasLength(3));
      await tester.drag(list, const Offset(0, -300));
      await tester.pumpAndSettle();
      final other = find.descendant(
        of: list,
        matching: find.textContaining('Vollkorn', findRichText: true),
      );
      expect(other, findsWidgets, reason: 'other suggestions stay visible');
      expect(
        tester.getRect(other.first).top,
        greaterThan(tester.getRect(key('match-plus')).top),
        reason: 'below the + row',
      );
    });

    testWidgets('a tap on the + row adds separately too', (tester) async {
      await pumpList(tester, seed: (repo) => repo.remoteAdd('Nudeln'));
      await type(tester, 'Nudeln');
      await tester.tap(key('match-plus'));
      await tester.pumpAndSettle();
      expect(active(tester, 'Nudeln'), hasLength(2));
    });

    testWidgets('merge: one Nudeln with the Menge merged, and a note until '
        'the next letter', (tester) async {
      await pumpList(tester, seed: (repo) => repo.remoteAdd('Nudeln'));
      await type(tester, 'Nudeln');
      await tester.tap(key('match-0'));
      await tester.pumpAndSettle();
      expect(active(tester, 'Nudeln').single.quantity, '2');
      expect(repo.rows.values.where((i) => i.name == 'Nudeln'), hasLength(1));
      expect(typed(tester), isEmpty);
      expect(inSheet(find.text('Zusammengeführt: 2× Nudeln')), findsOneWidget);
      expect(key('match-0'), findsNothing);
      expect(key('dedupe-undo'), findsNothing, reason: 'no Rückgängig');
      expect(matchEvents().last, 'add_match_outcome:merge');

      await tester.enterText(field(), 'B');
      await tester.pumpAndSettle();
      expect(key('match-note'), findsNothing);
    });

    testWidgets('a typed Menge merges into the open one', (tester) async {
      await pumpList(
        tester,
        seed: (repo) => repo.remoteAdd('Mehl', quantity: '500 g'),
      );
      await type(tester, 'Mehl 1 kg');
      expect(textIn('match-0', '1,5 kg Mehl'), findsOneWidget);
      await tester.tap(key('match-0'));
      await tester.pumpAndSettle();
      expect(active(tester, 'Mehl').single.quantity, '1,5 kg');
    });

    testWidgets('tick off', (tester) async {
      await pumpList(tester, seed: (repo) => repo.remoteAdd('Nudeln'));
      await type(tester, 'Nudeln');
      await tester.tap(key('match-1'));
      await tester.pumpAndSettle();
      expect(named(tester, 'Nudeln').single.status, ItemStatus.bought);
      expect(inSheet(find.text('Nudeln abgehakt')), findsOneWidget);
      expect(typed(tester), isEmpty);
      expect(matchEvents().last, 'add_match_outcome:tick');
    });

    testWidgets('each row is one button for a screen reader', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpList(
        tester,
        seed: (repo) =>
            repo.remoteAdd('Nudeln', storeId: 'lidl', brand: 'Barilla'),
      );
      await type(tester, 'Nudeln');
      expect(
        tester.getSemantics(key('match-0')),
        matchesSemantics(
          label: 'Zusammenführen, 2× Nudeln, Lidl · Barilla',
          isButton: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(key('match-1')),
        matchesSemantics(
          label: 'Abhaken, Nudeln, Lidl · Barilla',
          isButton: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(key('match-plus')),
        matchesSemantics(
          label: 'Nudeln, Wie getippt',
          isButton: true,
          hasTapAction: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('a plural: Apfel finds 1 kg Äpfel, whose Menge stays', (
      tester,
    ) async {
      await pumpList(
        tester,
        seed: (repo) =>
            repo.remoteAdd('Äpfel', quantity: '1 kg', categoryId: 'produce'),
      );
      await type(tester, 'Apfel');
      expect(textIn('match-0', '1 kg Äpfel'), findsOneWidget);
      expect(textIn('match-1', 'Äpfel'), findsOneWidget);
      expect(key('match-plus'), findsOneWidget);
    });

    testWidgets('several matches: three rows at most, and the + row', (
      tester,
    ) async {
      await pumpList(
        tester,
        seed: (repo) => repo
          ..remoteAdd('Milch', storeId: 'lidl', properties: '1,5 %')
          ..remoteAdd('Milch', storeId: 'dm', properties: '3,5 %')
          ..remoteAdd('Milch', storeId: 'dm', properties: 'laktosefrei'),
      );
      await type(tester, 'Milch');
      expect(textIn('match-0', '2× Milch'), findsOneWidget);
      expect(textIn('match-0', 'Lidl · 1,5 %'), findsOneWidget);
      expect(textIn('match-1', 'Milch'), findsOneWidget);
      expect(textIn('match-2', 'dm · 3,5 %'), findsOneWidget);
      expect(key('match-3'), findsNothing);
      expect(key('match-plus'), findsNothing, reason: 'the 4th row, scrolled');
      await tester.drag(key('add-suggestions'), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(key('match-plus'), findsOneWidget);
    });
  });

  group('the list changes while the rows show (review 0)', () {
    testWidgets('another member deletes the item: the rows go, no note', (
      tester,
    ) async {
      late Item oat;
      await pumpList(
        tester,
        seed: (repo) => oat = repo.remoteAdd('Hafermilch'),
      );
      await type(tester, 'Hafermilch');
      expect(key('match-0'), findsOneWidget);
      repo.rows.remove(oat.id);
      repo.emitDelete!(oat.id);
      await tester.pumpAndSettle();
      expect(key('match-0'), findsNothing, reason: 'rows follow');
      expect(key('match-note'), findsNothing);
      expect(typed(tester), 'Hafermilch', reason: 'the text stays');
      expect(matchEvents(), ['add_match_shown']);
    });

    testWidgets('a row taken after its item went says nothing happened', (
      tester,
    ) async {
      late Item oat;
      await pumpList(
        tester,
        seed: (repo) => oat = repo.remoteAdd('Hafermilch', quantity: '2'),
      );
      await type(tester, 'Hafermilch');
      final cubit = tester.element(field()).read<AddSheetCubit>();
      final stale = [...cubit.state.matches];
      repo.rows.remove(oat.id);
      repo.emitDelete!(oat.id);
      await tester.pumpAndSettle();
      for (final row in stale) {
        expect(cubit.takeMatch(row), isFalse, reason: '${row.runtimeType}');
      }
      await tester.pumpAndSettle();
      expect(key('match-note'), findsNothing);
      expect(inSheet(find.textContaining('abgehakt')), findsNothing);
      expect(named(tester, 'Hafermilch'), isEmpty);
      expect(matchEvents(), ['add_match_shown']);
    });

    testWidgets('a ticked one put back meanwhile is no back-on-the-list row', (
      tester,
    ) async {
      late Item eggs;
      await pumpList(
        tester,
        seed: (repo) => eggs = repo.remoteAdd(
          'Eier',
          quantity: '10',
          status: ItemStatus.bought,
        ),
      );
      await type(tester, 'Eier');
      final cubit = tester.element(field()).read<AddSheetCubit>();
      final stale = cubit.state.matches.single;
      expect(stale, isA<ReaddRow>());
      repo.emitItem!(
        repo.rows[eggs.id] = eggs.copyWith(status: ItemStatus.active),
      );
      await tester.pumpAndSettle();
      expect(cubit.state.matches.first, isA<MergeRow>(), reason: 'open now');
      expect(cubit.takeMatch(stale), isFalse);
      await tester.pumpAndSettle();
      expect(key('match-note'), findsNothing);
    });

    testWidgets('another member adds the same item: rows without a key, and '
        'Enter adds a separate one', (tester) async {
      await pumpList(tester, seed: (_) {});
      await type(tester, 'Kakao');
      expect(key('match-0'), findsNothing);
      repo.emitItem!(repo.remoteAdd('Kakao'));
      await tester.pumpAndSettle();
      expect(textIn('match-0', '2× Kakao'), findsOneWidget);
      await enter(tester);
      expect(active(tester, 'Kakao'), hasLength(2));
      expect(find.textContaining('schon auf der Liste'), findsNothing);
    });
  });

  group('two alike', () {
    testWidgets('two plain Kefir: one merge row, not two that read alike', (
      tester,
    ) async {
      await pumpList(
        tester,
        seed: (repo) => repo
          ..remoteAdd('Kefir')
          ..remoteAdd('Kefir'),
      );
      await type(tester, 'Kefir');
      expect(textIn('match-0', '2× Kefir'), findsOneWidget);
      expect(textIn('match-1', 'Kefir'), findsOneWidget);
      expect(key('match-2'), findsNothing);
    });
  });

  group('a ticked match', () {
    void eggs(FakeRepository repo) => repo.remoteAdd(
      'Eier',
      quantity: '10',
      storeId: 'lidl',
      status: ItemStatus.bought,
    );

    testWidgets('a back-on-the-list row; Enter puts it back as it was', (
      tester,
    ) async {
      await pumpList(tester, seed: eggs);
      await type(tester, 'Eier');
      expect(textIn('match-0', '10× Eier'), findsOneWidget);
      expect(textIn('match-0', 'Lidl'), findsOneWidget);
      expect(inSheet(find.byIcon(Icons.keyboard_return)), findsNothing);
      expect(
        find.descendant(
          of: key('match-plus'),
          matching: find.byIcon(Icons.keyboard_return),
        ),
        findsNothing,
      );
      await enter(tester);
      final back = named(tester, 'Eier').single;
      expect(back.status, ItemStatus.active);
      expect((back.quantity, back.storeId), ('10', 'lidl'));
      expect(
        inSheet(find.text('Wieder auf der Liste: 10× Eier')),
        findsOneWidget,
      );
      expect(typed(tester), isEmpty);
      expect(matchEvents().last, 'add_match_outcome:readd');
    });

    testWidgets('a tap on the row puts it back too', (tester) async {
      await pumpList(tester, seed: eggs);
      await type(tester, 'Eier');
      await tester.tap(key('match-0'));
      await tester.pumpAndSettle();
      expect(named(tester, 'Eier').single.status, ItemStatus.active);
    });
  });

  group('no match', () {
    for (final (onList, typedText) in [
      ('Hafermilch', 'Milch'),
      ('Oat milk', 'Milk'),
      ('Milch', 'Hafermilch'),
      ('Schaufel', 'Schäufele'),
      ('Schäufele', 'Schaufel'),
      ('beer', 'Beeren'),
    ]) {
      testWidgets('$onList open, $typedText typed: the rows as without the '
          'flag', (tester) async {
        await pumpList(tester, seed: (repo) => repo.remoteAdd(onList));
        await type(tester, typedText);
        await shoot('no-match-$typedText');
        expect(key('match-0'), findsNothing);
        expect(key('add-suggestions'), findsOneWidget);
        expect(matchEvents(), isEmpty);
      });
    }
  });

  testWidgets('a near-duplicate still offers the merge: Tomate open, '
      'Tomaten typed', (tester) async {
    await pumpList(tester, seed: (repo) => repo.remoteAdd('Tomate'));
    await type(tester, 'Tomaten');
    await shoot('merge-Tomaten');
    expect(textIn('match-0', '2× Tomate'), findsOneWidget);
    await tester.tap(key('match-0'));
    await tester.pumpAndSettle();
    expect(active(tester, 'Tomate').single.quantity, '2');
    expect(active(tester, 'Tomaten'), isEmpty);
  });

  testWidgets('flag off: no match rows; Enter says it is on the list and '
      'adds nothing', (tester) async {
    await pumpList(
      tester,
      matchRows: false,
      seed: (repo) => repo.remoteAdd('Nudeln'),
    );
    await type(tester, 'Nudeln');
    expect(key('match-0'), findsNothing);
    await enter(tester);
    expect(
      inSheet(find.text('Nudeln steht schon auf der Liste')),
      findsOneWidget,
    );
    expect(active(tester, 'Nudeln'), hasLength(1));
    expect(repo.sent.whereType<AddItem>(), isEmpty);
    expect(matchEvents(), isEmpty);
  });

  testWidgets('nothing behind the sheet scrolls on any outcome', (
    tester,
  ) async {
    await pumpList(
      tester,
      seed: (repo) {
        for (var i = 0; i < 30; i++) {
          repo.remoteAdd('Artikel $i', storeId: 'lidl');
        }
        repo
          ..remoteAdd('Nudeln', storeId: 'lidl')
          ..remoteAdd('Reis', storeId: 'dm');
      },
    );
    final list = tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .firstWhere((s) => s.position.axis == Axis.vertical)
        .position;
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    final before = list.pixels;
    expect(before, greaterThan(0));
    await type(tester, 'Nudeln');
    final opened = list.pixels;
    await tester.tap(key('match-0'));
    await tester.pumpAndSettle();
    expect(list.pixels, opened, reason: 'a merge moves nothing');
    await tester.enterText(field(), 'Reis');
    await tester.pumpAndSettle();
    await tester.tap(key('match-1'));
    await tester.pumpAndSettle();
    expect(list.pixels, opened, reason: 'a tick moves nothing');
    expect(named(tester, 'Reis').single.status, ItemStatus.bought);
    await tester.enterText(field(), 'Reis');
    await tester.pumpAndSettle();
    await tester.tap(key('match-0'));
    await tester.pumpAndSettle();
    expect(list.pixels, opened, reason: 'back on the list moves nothing');
    expect(named(tester, 'Reis').single.status, ItemStatus.active);
    await tester.enterText(field(), 'Reis');
    await tester.pumpAndSettle();
    await enter(tester);
    expect(list.pixels, opened, reason: 'a separate add moves nothing');
    expect(active(tester, 'Reis'), hasLength(2));
  });

  group('large text, above the keyboard', () {
    for (final (size, keyboard) in [
      (phone, 336.0),
      (const Size(360, 640), 280.0),
    ]) {
      testWidgets('${size.width.toInt()}×${size.height.toInt()} at 200 %: '
          'the + row and the field stay in view', (tester) async {
        await pumpList(
          tester,
          size: size,
          textScale: 2,
          keyboard: keyboard,
          seed: (repo) {
            repo
              ..stores = Catalog(stores: repo.stores)
                  .withStoreName('lidl', 'Hofladen Sonnenhang')
                  .stores
              ..categories = Catalog(categories: repo.categories)
                  .withName('chilled', 'Vorrat & Konserven')
                  .categories
              ..remoteAdd(
                'Milch',
                storeId: 'lidl',
                brand: 'Weihenstephan',
                properties: '1,5 %',
                categoryId: 'chilled',
              )
              ..remoteAdd('Milch', storeId: 'lidl', properties: 'laktosefrei');
          },
        );
        await type(tester, 'Milch');
        expect(key('match-0'), findsOneWidget);
        final view = Rect.fromLTRB(0, 47, size.width, size.height - keyboard);
        for (final k in ['add-suggestions', 'add-item-field']) {
          final rect = tester.getRect(key(k));
          expect(
            view.contains(rect.topLeft) &&
                view.contains(rect.bottomRight - const Offset(0.01, 0.01)),
            isTrue,
            reason: '$k at $rect, outside $view',
          );
        }
        final rows = tester.getRect(key('add-suggestions'));
        expect(rows.top, greaterThanOrEqualTo(view.top));
        expect(
          rows.bottom,
          lessThanOrEqualTo(tester.getRect(field()).top + 0.5),
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}

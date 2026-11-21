import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/list/list_view/dividers.dart';
import 'package:family_groceries/list/list_view/item_row.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_repository.dart';
import 'memory_cache.dart';

/// Job 350, flag `hide-categories`: no category shows in the list, the add
/// sheet or the edit sheet, and the list keeps its order.
void main() {
  late FakeRepository repo;

  Future<void> pumpList(
    WidgetTester tester, {
    required bool hidden,
    Set<String> flags = const {},
  }) async {
    tester.view
      ..devicePixelRatio = 3
      ..physicalSize = const Size(390, 1400) * 3
      ..padding = const FakeViewPadding(top: 47.0 * 3, bottom: 34.0 * 3);
    addTearDown(tester.view.reset);
    repo = FakeRepository()
      ..remoteAdd('Äpfel', storeId: 'lidl', categoryId: 'produce')
      ..remoteAdd('Joghurt', storeId: 'lidl', categoryId: 'chilled')
      ..remoteAdd('Spülmittel', storeId: 'lidl', categoryId: 'other')
      ..remoteAdd('Bananen', storeId: 'lidl', categoryId: 'produce')
      ..remoteAdd('Seife', storeId: 'dm', categoryId: 'other')
      ..remoteAdd('Quark', categoryId: 'chilled')
      ..remoteAdd('Birnen', categoryId: 'produce')
      ..remoteAdd(
        'Butter',
        categoryId: 'chilled',
        storeId: 'lidl',
        status: ItemStatus.bought,
      );
    final list = ListCubit(repo, MemoryListCache(), userId: 'peter')..start();
    final on = Flags(forced: {...flags, if (hidden) hideCategoriesFlag});
    addTearDown(list.close);
    addTearDown(on.close);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: on),
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

  Finder key(String k) => find.byKey(ValueKey(k));
  Finder field() => key('add-item-field');
  Finder row(String name) =>
      find.byWidgetPredicate((w) => w is ItemRow && w.item.name == name);

  /// The list's rows top to bottom.
  List<String> order(WidgetTester tester) {
    final rows = tester.widgetList<ItemRow>(find.byType(ItemRow)).toList()
      ..sort(
        (a, b) => tester
            .getTopLeft(find.byWidget(a))
            .dy
            .compareTo(tester.getTopLeft(find.byWidget(b)).dy),
      );
    return [for (final r in rows) r.item.name];
  }

  /// Every text painted and every screen-reader label, lower case.
  List<String> everything(WidgetTester tester) => [
    for (final text in tester.widgetList<RichText>(
      find.byType(RichText, skipOffstage: false),
    ))
      text.text.toPlainText().toLowerCase(),
    for (final s in tester.widgetList<Semantics>(
      find.byType(Semantics, skipOffstage: false),
    ))
      ?s.properties.label?.toLowerCase(),
  ];

  /// What on screen names a category: the fake household's categories,
  /// the chip's „Kategorie“ and the divider of items being sorted.
  List<String> categoryText(WidgetTester tester) {
    final words = [
      for (final c in repo.categories) c.name.toLowerCase(),
      'kategorie',
      'einsortiert',
    ];
    return [
      for (final text in everything(tester))
        if (words.any(text.contains)) text,
    ];
  }

  Future<void> showUsed(WidgetTester tester) async {
    final title = find.text('Zuletzt verwendet');
    await tester.ensureVisible(title);
    await tester.pumpAndSettle();
    await tester.tap(title);
    await tester.pumpAndSettle();
    expect(
      key('used-${repo.rows.values.firstWhere((i) => i.name == 'Butter').id}'),
      findsOneWidget,
    );
  }

  group('the list', () {
    const lidl = ['Spülmittel', 'Joghurt', 'Äpfel', 'Bananen'];
    for (final (name, flags) in [
      ('plain', <String>{}),
      ('with trip mode and prices on', {tripModeFlag, pricesFlag}),
      ('decluttered', {listDeclutterFlag, pricesFlag, tripModeFlag}),
    ]) {
      testWidgets('$name: the same rows in the same order, no category', (
        tester,
      ) async {
        await pumpList(tester, hidden: false, flags: flags);
        final before = order(tester);
        expect(find.byType(CategoryDivider), findsWidgets);
        expect(categoryText(tester), isNotEmpty, reason: 'headings show');
        expect(
          [
            for (final name in before)
              if (lidl.contains(name)) name,
          ],
          lidl,
          reason: "Lidl's walk: Sonstiges, Kühlregal, Obst & Gemüse",
        );

        await pumpList(tester, hidden: true, flags: flags);
        expect(order(tester), before);
        expect(find.byType(CategoryDivider), findsNothing);
        expect(find.byType(StoreDivider), findsWidgets);
        expect(categoryText(tester), isEmpty);
        await showUsed(tester);
        expect(categoryText(tester), isEmpty);
      });
    }

    testWidgets('a section reads as one run: only its last row has no rule', (
      tester,
    ) async {
      await pumpList(tester, hidden: true);
      expect(
        [for (final name in lidl) tester.widget<ItemRow>(row(name)).last],
        [false, false, false, true],
      );
    });
  });

  group('the add sheet', () {
    Future<void> openAndType(WidgetTester tester, String text) async {
      await tester.tap(field());
      await tester.pumpAndSettle();
      await tester.enterText(field(), text);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
    }

    Future<void> addMilk(WidgetTester tester) async {
      await openAndType(tester, 'Milch');
      await tester.tap(key('suggestion-${foldName('Milch')}||'));
      await tester.pumpAndSettle();
    }

    for (final hidden in [false, true]) {
      final shows = hidden ? findsNothing : findsOneWidget;
      testWidgets('without add-feedback-list: the header has '
          '${hidden ? 'no' : 'its'} category chip', (tester) async {
        await pumpList(tester, hidden: hidden);
        await openAndType(tester, 'Milch');
        expect(key('chip-store'), findsOneWidget);
        expect(key('chip-category'), shows);
        if (hidden) {
          expect(categoryText(tester), isEmpty);
        }
      });

      testWidgets("with add-feedback-list: the added item's details have "
          '${hidden ? 'no' : 'a'} category chip', (tester) async {
        await pumpList(
          tester,
          hidden: hidden,
          flags: {addFeedbackListFlag, inputStableRowsFlag},
        );
        await addMilk(tester);
        expect(key('chip-store'), findsOneWidget);
        expect(key('chip-category'), shows);
        if (hidden) {
          expect(categoryText(tester), isEmpty);
        }
      });

      testWidgets('compact: the chip row has ${hidden ? 'no' : 'a'} '
          'category chip', (tester) async {
        await pumpList(
          tester,
          hidden: hidden,
          flags: {
            addFeedbackListFlag,
            inputStableRowsFlag,
            addSheetCompactFlag,
          },
        );
        await addMilk(tester);
        expect(key('chip-store'), findsOneWidget);
        expect(key('chip-details'), findsOneWidget);
        expect(key('chip-category'), shows);
        if (hidden) {
          expect(categoryText(tester), isEmpty);
        }
      });
    }

    testWidgets('an add sends the same category with the flag as without', (
      tester,
    ) async {
      final sent = <String?>[];
      for (final hidden in [false, true]) {
        await pumpList(tester, hidden: hidden);
        await openAndType(tester, 'Milch');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        sent.add(
          repo.sent
              .whereType<AddItem>()
              .singleWhere((op) => op.item.name == 'Milch')
              .item
              .categoryId,
        );
      }
      expect(sent.first, isNotNull);
      expect(sent.last, sent.first);
    });
  });

  group('the edit sheet', () {
    for (final hidden in [false, true]) {
      testWidgets('${hidden ? 'hidden' : 'shown'}: the store chip, '
          '${hidden ? 'no' : 'and the'} category chip', (tester) async {
        await pumpList(tester, hidden: hidden);
        await tester.longPress(row('Joghurt'));
        await tester.pumpAndSettle();
        expect(key('edit-sheet'), findsOneWidget);
        expect(key('chip-store'), findsOneWidget);
        expect(key('chip-category'), hidden ? findsNothing : findsOneWidget);
        if (hidden) {
          expect(categoryText(tester), isEmpty);
        }
      });
    }

    testWidgets('hidden, a save keeps the category', (tester) async {
      await pumpList(tester, hidden: true);
      await tester.longPress(row('Joghurt'));
      await tester.pumpAndSettle();
      await tester.tap(key('chip-store'));
      await tester.pumpAndSettle();
      await tester.tap(key('store-option-dm'));
      await tester.pumpAndSettle();
      await tester.tap(key('edit-done'));
      await tester.pumpAndSettle();
      final yoghurt = repo.rows.values.singleWhere((i) => i.name == 'Joghurt');
      expect((yoghurt.storeId, yoghurt.categoryId), ('dm', 'chilled'));
    });
  });
}

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cache.dart';
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

/// Job 352 (IO4), flag `learned-order`: the household switches to the
/// learned order, each store runs as one walk without category headings,
/// and the edit sheet's „Neben …“ chip places an item.
void main() {
  late FakeRepository repo;
  late ListCubit list;

  /// Lidl's items in learned walk order (by sort key), across categories.
  const lidlWalk = ['Spülmittel', 'Äpfel', 'Joghurt', 'Bananen', 'Quark'];

  void seed() {
    repo = FakeRepository();
    final keys = <String, double>{};
    for (final (i, (name, category)) in [
      ('Joghurt', 'chilled'),
      ('Äpfel', 'produce'),
      ('Spülmittel', 'other'),
      ('Bananen', 'produce'),
      ('Quark', 'chilled'),
    ].indexed) {
      final item = repo.remoteAdd(name, storeId: 'lidl', categoryId: category);
      keys[item.id] = (lidlWalk.indexOf(name) + 1) * 1000.0 + i;
    }
    repo
      ..remoteAdd('Seife', storeId: 'dm', categoryId: 'other')
      ..remoteAdd('Birnen', categoryId: 'produce');
    for (final MapEntry(:key, :value) in keys.entries) {
      repo.rows[key] = repo.rows[key]!.copyWith(sortKey: () => value);
    }
  }

  Future<void> pumpList(
    WidgetTester tester, {
    bool flag = true,
    Size size = const Size(390, 1400),
    bool hintDismissed = false,
  }) async {
    tester.view
      ..devicePixelRatio = 3
      ..physicalSize = size * 3
      ..padding = const FakeViewPadding(top: 47.0 * 3, bottom: 34.0 * 3);
    addTearDown(tester.view.reset);
    list = ListCubit(
      repo,
      MemoryListCache()..prefs = ListPrefs(hintDismissed: hintDismissed),
      userId: 'peter',
      learnedOrder: () => flag,
    )..start();
    final flags = Flags(forced: {if (flag) learnedOrderFlag});
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

  Finder key(String k) => find.byKey(ValueKey(k));
  Finder row(String name) =>
      find.byWidgetPredicate((w) => w is ItemRow && w.item.name == name);
  String idOf(String name) =>
      repo.rows.values.singleWhere((i) => i.name == name).id;

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

  List<String> lidl(WidgetTester tester) => [
    for (final name in order(tester))
      if (lidlWalk.contains(name)) name,
  ];

  group('the sort', () {
    testWidgets('flag on, the server answers learned: each store one walk '
        'by sort key, no category heading; stores and No store stay', (
      tester,
    ) async {
      seed();
      await pumpList(tester);
      expect(repo.orderModeAsks, [OrderMode.learned]);
      expect(lidl(tester), lidlWalk);
      expect(find.byType(CategoryDivider), findsNothing);
      expect(key('store-dm'), findsOneWidget);
      expect(key('store-lidl'), findsOneWidget);
      expect(key('store-none'), findsOneWidget);
      expect(order(tester), ['Seife', ...lidlWalk, 'Birnen']);
    });

    testWidgets('flag on, the server answers categories: the category walk '
        'with its headings', (tester) async {
      seed();
      repo.orderModeAnswer = OrderMode.categories;
      await pumpList(tester);
      expect(repo.orderModeAsks, [OrderMode.learned]);
      expect(find.byType(CategoryDivider), findsWidgets);
      expect(lidl(tester), isNot(lidlWalk));
      expect(lidl(tester), [
        'Spülmittel',
        'Joghurt',
        'Quark',
        'Äpfel',
        'Bananen',
      ], reason: "Lidl's category walk: Sonstiges, Kühlregal, Obst");
    });

    testWidgets('flag off: no switch asked, the category walk', (tester) async {
      seed();
      await pumpList(tester, flag: false);
      expect(repo.orderModeAsks, isEmpty);
      expect(find.byType(CategoryDivider), findsWidgets);
    });

    testWidgets('asked once per list, also over later resyncs', (tester) async {
      seed();
      await pumpList(tester);
      await list.resync();
      await list.resumed();
      await tester.pumpAndSettle();
      expect(repo.orderModeAsks, [OrderMode.learned]);
    });

    testWidgets('a failed ask is asked again with the next resync', (
      tester,
    ) async {
      seed();
      repo.orderModeFails = 1;
      await pumpList(tester);
      expect(find.byType(CategoryDivider), findsWidgets);
      await list.resync();
      await tester.pumpAndSettle();
      expect(repo.orderModeAsks, [OrderMode.learned, OrderMode.learned]);
      expect(find.byType(CategoryDivider), findsNothing);
      expect(lidl(tester), lidlWalk);
    });

    testWidgets('the switch shows the replayed sort keys with the learned '
        'sort: no state mixes it with the category keys', (tester) async {
      seed();
      final walkKeys = {
        for (final MapEntry(:key, :value) in repo.rows.entries)
          key: value.sortKey,
      };
      for (final (i, id) in repo.rows.keys.toList().indexed) {
        repo.rows[id] = repo.rows[id]!.copyWith(sortKey: () => -i * 1000.0);
      }
      repo.onLearned = () {
        for (final MapEntry(:key, :value) in walkKeys.entries) {
          repo.rows[key] = repo.rows[key]!.copyWith(sortKey: () => value);
        }
      };
      list = ListCubit(
        repo,
        MemoryListCache(),
        userId: 'peter',
        learnedOrder: () => true,
      );
      addTearDown(list.close);
      final mixed = <String>[];
      final watching = list.stream.listen((state) {
        if (state.prefs.learnedOrder) {
          mixed.addAll([
            for (final item in state.items.values)
              if (item.sortKey != walkKeys[item.id]) item.name,
          ]);
        }
      });
      addTearDown(watching.cancel);
      list.start();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(list.state.prefs.learnedOrder, isTrue);
      expect(mixed, isEmpty);
    });

    testWidgets('a failed read after the switch keeps the category walk and '
        'asks again with the next resync', (tester) async {
      seed();
      repo.onLearned = () => repo.fetchTrouble = true;
      await pumpList(tester);
      expect(list.state.prefs.learnedOrder, isFalse);
      expect(find.byType(CategoryDivider), findsWidgets);
      repo.fetchTrouble = false;
      await list.resync();
      await tester.pumpAndSettle();
      expect(repo.orderModeAsks, [OrderMode.learned, OrderMode.learned]);
      expect(list.state.prefs.learnedOrder, isTrue);
      expect(lidl(tester), lidlWalk);
    });
  });

  group('the edit sheet', () {
    Future<void> edit(WidgetTester tester, String name) async {
      await tester.longPress(row(name));
      await tester.pumpAndSettle();
      expect(key('edit-sheet'), findsOneWidget);
    }

    String chipText(WidgetTester tester) => tester
        .widgetList<Text>(
          find.descendant(of: key('chip-place'), matching: find.byType(Text)),
        )
        .map((t) => t.data)
        .join();

    testWidgets('the place chip names the item before it, „Ganz vorne“ for '
        'the first; no category chip', (tester) async {
      seed();
      await pumpList(tester);
      await edit(tester, 'Joghurt');
      expect(key('chip-category'), findsNothing);
      expect(chipText(tester), 'Neben Äpfel');
      await tester.tap(key('edit-cancel'));
      await tester.pumpAndSettle();
      await edit(tester, 'Spülmittel');
      expect(chipText(tester), 'Ganz vorne');
    });

    testWidgets('its options: „Ganz vorne“, then the others in walk order, '
        'the current neighbour marked', (tester) async {
      seed();
      await pumpList(tester);
      await edit(tester, 'Joghurt');
      await tester.tap(key('chip-place'));
      await tester.pumpAndSettle();
      final options = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('place-option-'),
      );
      final keys = [
        for (final w in tester.widgetList(options))
          (w.key! as ValueKey<String>).value,
      ];
      expect(keys, [
        'place-option-start',
        for (final name in lidlWalk)
          if (name != 'Joghurt') 'place-option-${idOf(name)}',
      ]);
      expect(
        tester.getSemantics(key('place-option-${idOf('Äpfel')}')),
        isSemantics(isSelected: true),
      );
      expect(
        tester.getSemantics(key('place-option-start')),
        isSemantics(isSelected: false),
      );
      expect(key('place-filter'), findsNothing);
    });

    testWidgets("a pick sends a place after the picked item with the gap's "
        'midpoint, and the row moves before the server answers', (
      tester,
    ) async {
      seed();
      await pumpList(tester);
      await edit(tester, 'Spülmittel');
      await tester.tap(key('chip-place'));
      await tester.pumpAndSettle();
      await tester.tap(key('place-option-${idOf('Bananen')}'));
      await tester.pumpAndSettle();
      expect(chipText(tester), 'Neben Bananen');
      repo.online = false;
      await tester.tap(key('edit-done'));
      await tester.pumpAndSettle();
      final place = list.state.pending.whereType<PlaceItem>().single;
      expect(
        (place.itemId, place.anchorId, place.edge),
        (idOf('Spülmittel'), idOf('Bananen'), Edge.after),
      );
      final bananen = repo.rows[idOf('Bananen')]!.sortKey!;
      final quark = repo.rows[idOf('Quark')]!.sortKey!;
      expect(place.sortKey, (bananen + quark) / 2);
      expect(place.categoryId, 'other', reason: 'its own category stays');
      expect(lidl(tester), [
        'Äpfel',
        'Joghurt',
        'Bananen',
        'Spülmittel',
        'Quark',
      ]);
    });

    testWidgets('„Ganz vorne“ places it before the first item', (tester) async {
      seed();
      await pumpList(tester);
      await edit(tester, 'Quark');
      await tester.tap(key('chip-place'));
      await tester.pumpAndSettle();
      await tester.tap(key('place-option-start'));
      await tester.pumpAndSettle();
      await tester.tap(key('edit-done'));
      await tester.pumpAndSettle();
      final place = repo.sent.whereType<PlaceItem>().single;
      expect((place.anchorId, place.edge), (idOf('Spülmittel'), Edge.before));
      expect(lidl(tester).first, 'Quark');
    });

    testWidgets('a store change drops the place chip and sends no place', (
      tester,
    ) async {
      seed();
      await pumpList(tester);
      await edit(tester, 'Quark');
      await tester.tap(key('chip-place'));
      await tester.pumpAndSettle();
      await tester.tap(key('place-option-start'));
      await tester.pumpAndSettle();
      await tester.tap(key('chip-store'));
      await tester.pumpAndSettle();
      await tester.tap(key('store-option-dm'));
      await tester.pumpAndSettle();
      expect(key('chip-place'), findsNothing);
      await tester.tap(key('edit-done'));
      await tester.pumpAndSettle();
      expect(repo.sent.whereType<PlaceItem>(), isEmpty);
      expect(repo.rows[idOf('Quark')]!.storeId, 'dm');
    });

    for (final (others, filtered) in [(15, false), (16, true)]) {
      testWidgets('$others other items: ${filtered ? 'a' : 'no'} filter '
          'field', (tester) async {
        repo = FakeRepository();
        for (var i = 0; i <= others; i++) {
          repo.remoteAdd('Ding $i', storeId: 'lidl', categoryId: 'other');
        }
        await pumpList(tester, size: const Size(390, 3000));
        await edit(tester, 'Ding 0');
        await tester.tap(key('chip-place'));
        await tester.pumpAndSettle();
        expect(key('place-filter'), filtered ? findsOneWidget : findsNothing);
        if (filtered) {
          await tester.enterText(key('place-filter'), 'ding 1');
          await tester.pumpAndSettle();
          expect(
            [
              for (var i = 1; i <= others; i++)
                if (tester.any(key('place-option-${idOf('Ding $i')}'))) i,
            ],
            [1, 10, 11, 12, 13, 14, 15, 16],
          );
          expect(key('place-option-start'), findsOneWidget);
        }
      });
    }
  });

  testWidgets('390 × 844, one store with 18 items: 12 rows on the first '
      'screen where the category walk shows 9', (tester) async {
    final shown = <bool, int>{};
    for (final flag in [false, true]) {
      repo = FakeRepository()
        ..categories = const [
          Category(id: 'produce', name: 'Obst & Gemüse', sortOrder: 10),
          Category(id: 'bakery', name: 'Brot', sortOrder: 20),
          Category(id: 'chilled', name: 'Kühlregal', sortOrder: 30),
          Category(id: 'pantry', name: 'Vorrat', sortOrder: 40),
          Category(id: 'drinks', name: 'Getränke', sortOrder: 50),
          Category(id: 'other', name: 'Sonstiges', sortOrder: 1000),
        ]
        ..stores = const [Store(id: 'edeka', name: 'EDEKA', sortOrder: 10)];
      // Three items a category, as round IO's 18-item EDEKA list.
      const categories = [
        'produce',
        'bakery',
        'chilled',
        'pantry',
        'drinks',
        'other',
      ];
      for (var i = 0; i < 18; i++) {
        repo.remoteAdd(
          'Artikel $i',
          storeId: 'edeka',
          categoryId: categories[i * categories.length ~/ 18],
        );
      }
      await pumpList(
        tester,
        flag: flag,
        size: const Size(390, 844),
        hintDismissed: true,
      );
      final screen = tester.getRect(find.byType(Scaffold).first);
      final field = tester.getRect(key('add-item-field'));
      shown[flag] = [
        for (final element in find.byType(ItemRow).evaluate())
          if (tester.getRect(find.byWidget(element.widget)) case final r
              when r.top >= screen.top && r.bottom <= field.top)
            r,
      ].length;
    }
    expect(shown, {false: 9, true: 12});
  });

  test('a place goes out for items without a category: the learned order '
      'needs none', () async {
    repo = FakeRepository();
    for (final (i, name) in ['Kerzen', 'Servietten'].indexed) {
      final row = repo.remoteAdd(name, storeId: 'lidl');
      repo.rows[row.id] = Item(
        id: row.id,
        name: name,
        storeId: 'lidl',
        status: ItemStatus.active,
        sortKey: (i + 1) * 1000,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
        listId: row.listId,
      );
    }
    list = ListCubit(
      repo,
      MemoryListCache(),
      userId: 'peter',
      learnedOrder: () => true,
    )..start();
    addTearDown(list.close);
    await pumpEventQueue();
    list.place(idOf('Servietten'), const PlaceFirst());
    await pumpEventQueue();
    final place = repo.sent.whereType<PlaceItem>().single;
    expect(
      (place.itemId, place.anchorId, place.edge),
      (idOf('Servietten'), idOf('Kerzen'), Edge.before),
    );
  });
}

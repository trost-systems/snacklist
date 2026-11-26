import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cache.dart';
import 'package:family_groceries/list/list_view/item_icon.dart';
import 'package:family_groceries/list/list_view/item_row.dart';
import 'package:family_groceries/list/list_view/sections.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'model_test.dart' show item;

const catalog = Catalog(
  categories: [
    Category(id: 'produce', name: 'produce', sortOrder: 10),
    Category(id: 'chilled', name: 'chilled', sortOrder: 20),
    Category(id: 'pantry', name: 'pantry', sortOrder: 30),
    Category(id: 'new', name: 'new', sortOrder: 40),
    Category(id: 'other', name: 'other', sortOrder: 1000),
  ],
  stores: [
    Store(id: 'lidl', name: 'Lidl', sortOrder: 20),
    Store(id: 'dm', name: 'dm', sortOrder: 10),
  ],
  // Neither store has a row for 'new' yet.
  layout: [
    StoreCategory(storeId: 'lidl', categoryId: 'other', sortOrder: 10),
    StoreCategory(storeId: 'lidl', categoryId: 'pantry', sortOrder: 20),
    StoreCategory(storeId: 'lidl', categoryId: 'chilled', sortOrder: 30),
    StoreCategory(storeId: 'lidl', categoryId: 'produce', sortOrder: 40),
    StoreCategory(storeId: 'dm', categoryId: 'pantry', sortOrder: 10),
    StoreCategory(storeId: 'dm', categoryId: 'other', sortOrder: 20),
    StoreCategory(
      storeId: 'dm',
      categoryId: 'produce',
      sortOrder: 30,
      hidden: true,
    ),
    StoreCategory(
      storeId: 'dm',
      categoryId: 'chilled',
      sortOrder: 40,
      hidden: true,
    ),
  ],
);

/// `section| category: ids; ...` per section.
List<String> describe(List<StoreSection> sections) => [
  for (final s in sections)
    '${s.key}| ${[for (final b in s.blocks) _block(b)].join('; ')}',
];

String _block(CategoryBlock b) =>
    '${b.category?.id ?? '?'}: ${b.items.map((i) => i.id).join(' ')}';

void main() {
  group('sections', () {
    test('stores in household order, then no store; one block per '
        "category in the store's walking order", () {
      final sections = sectionsOf([
        item('apple', category: 'produce'),
        item('milk', category: 'chilled', at: 1),
        item('yoghurt', category: 'chilled', store: 'dm', at: 2),
        item('rice', category: 'pantry'),
        item('noodles', category: 'new'),
        item('soap', category: 'other', store: 'dm', at: 1),
        item('beer', category: 'other', store: 'lidl', at: 2),
        item('chips', category: 'pantry', store: 'lidl', key: 2048),
        item('nuts', category: 'pantry', store: 'lidl', key: 1024, at: 9),
        item('typed', category: null),
        item('lost', category: 'deleted'),
        item('closed', category: 'pantry', store: 'deleted-store'),
        item('bought', category: 'pantry', status: ItemStatus.bought),
      ], catalog);
      expect(describe(sections), [
        // A store carries every category its items are in, even one its
        // layout hides.
        'dm| other: soap; chilled: yoghurt',
        // Walk order inside a block: sort key, not age.
        // Then every item without a store, deleted stores' too.
        'lidl| other: beer; pantry: nuts chips',
        '$noStoreKey| ${[
          '?: typed', 'produce: apple', 'chilled: milk', //
          'pantry: closed rice', 'new: noodles', '?: lost',
        ].join('; ')}',
      ]);
      expect([for (final s in sections) s.count], [2, 3, 7]);
    });

    test('an empty list still has every store and the no-store section', () {
      expect(describe(sectionsOf(const [], catalog)), [
        'dm| ',
        'lidl| ',
        '$noStoreKey| ',
      ]);
    });

    test('stores on the same sort order keep one order, whatever order the '
        'rows came in', () {
      const tied = [
        Store(id: 's2', name: 'rewe', sortOrder: 10),
        Store(id: 's1', name: 'Aldi', sortOrder: 10),
        Store(id: 's0', name: 'dm', sortOrder: 5),
      ];
      List<String?> order(List<Store> stores) => [
        for (final s in sectionsOf(const [], Catalog(stores: stores)))
          s.store?.id,
      ];
      expect(order(tied), ['s0', 's1', 's2', null]);
      expect(order(tied.reversed.toList()), ['s0', 's1', 's2', null]);
    });

    test('a changed catalog walks its own order, not a remembered one', () {
      List<String> route(Catalog c) => [
        for (final s in walkingOrder(c, null)) s.category.id,
      ];
      final before = route(catalog);
      final reordered = catalog.withRouteOrder(before.reversed.toList());
      expect(route(reordered), before.reversed);
      expect(route(catalog), before);
    });

    test('an unknown store walks the route order', () {
      expect(
        [for (final s in walkingOrder(catalog, 'gone')) s.category.id],
        ['produce', 'chilled', 'pantry', 'new', 'other'],
      );
      expect(
        [for (final s in walkingOrder(catalog, 'lidl')) s.category.id],
        ['other', 'pantry', 'chilled', 'produce', 'new'],
      );
    });
  });

  group('columns', () {
    StoreSection section(String id, int items) => StoreSection(
      store: Store(id: id, name: id, sortOrder: 0),
      blocks: [
        CategoryBlock(null, [for (var i = 0; i < items; i++) item('$id$i')]),
      ],
    );
    List<List<String>> ids(List<List<StoreSection>> columns) => [
      for (final c in columns) [for (final s in c) s.key],
    ];
    double count(StoreSection s) => s.count.toDouble();

    test('runs of whole stores in order, the tallest as short as can be', () {
      final sections = [
        section('a', 8),
        section('b', 2),
        section('c', 3),
        section('d', 6),
      ];
      expect(ids(columnsOf(sections, 1, count)), [
        ['a', 'b', 'c', 'd'],
      ]);
      expect(ids(columnsOf(sections, 2, count)), [
        ['a', 'b'],
        ['c', 'd'],
      ]);
      expect(ids(columnsOf(sections, 3, count)), [
        ['a'],
        ['b', 'c'],
        ['d'],
      ]);
    });

    test('never more columns than stores', () {
      expect(ids(columnsOf([section('a', 1)], 3, count)), [
        ['a'],
      ]);
      expect(ids(columnsOf(const [], 2, count)), [<String>[]]);
    });
  });

  group('shown sections', () {
    test('only sections with active items', () {
      final sections = sectionsOf([
        item('soap', category: 'other', store: 'dm'),
        item('bought', category: 'pantry', status: ItemStatus.bought),
      ], catalog);
      expect(
        [for (final s in shownSections(sections)) s.key],
        ['dm'],
        reason: 'a bought item does not keep its section on the list',
      );
      expect(shownSections(sectionsOf(const [], catalog)), isEmpty);
    });
  });

  group('rows', () {
    test(
      'a count shows as "6×", other quantities as typed, one not at all',
      () {
        expect(quantityLabel('6'), '6×');
        expect(quantityLabel('500 g'), '500 g');
        expect(quantityLabel('1'), isNull);
        expect(quantityLabel(null), isNull);
      },
    );

    test('a category shows its leading emoji and its name without it', () {
      const chilled = Category(
        id: 'c',
        name: 'Kühlregal',
        sortOrder: 1,
        seedKey: 'chilled',
      );
      const baby = Category(
        id: 'd',
        name: '👶 Drogerie',
        sortOrder: 2,
        seedKey: 'drugstore',
      );
      expect(categoryIcon(baby), '👶');
      expect(categoryIcon(chilled), '🥛', reason: 'the seeded one');
      expect(categoryIcon(null), '🧺');
      final de = lookupAppLocalizations(const Locale('de'));
      final en = lookupAppLocalizations(const Locale('en'));
      expect(categoryLabel(baby, de), 'Drogerie');
      expect(categoryLabel(chilled, de), 'Kühlregal');
      expect(categoryLabel(baby, en), 'Drugstore', reason: 'seeded, unrenamed');
      expect(categoryLabel(chilled, en), 'Chilled');
      expect(
        categoryLabel(
          const Category(
            id: 'c',
            name: 'Kühlung',
            sortOrder: 1,
            seedKey: 'chilled',
          ),
          en,
        ),
        'Kühlung',
        reason: 'a renamed category keeps what the household wrote',
      );
    });

    test('a Baumarkt category shows its icon and its name for the UI '
        'language', () {
      const tools = Category(
        id: 't',
        name: 'Werkzeug',
        sortOrder: 4,
        seedKey: 'tools',
      );
      expect(categoryIcon(tools), '🔨');
      expect(
        categoryLabel(tools, lookupAppLocalizations(const Locale('en'))),
        'Tools',
      );
      expect(
        categoryLabel(tools, lookupAppLocalizations(const Locale('de'))),
        'Werkzeug',
      );
    });
  });
}

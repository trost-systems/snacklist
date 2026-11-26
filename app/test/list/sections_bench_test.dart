import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:family_groceries/list/list_view/sections.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter_test/flutter_test.dart';

/// The frozen measure of hc-category-sorting (job 459,
/// docs/hillclimb/hc-category-sorting.md): the order the list shows with
/// categories hidden (one run per store), checked on fixed cases, for
/// stability, and timed on a large household. Prints one JSON line. Runs
/// only with SECTIONS_BENCH=1:
/// `SECTIONS_BENCH=1 flutter test test/list/sections_bench_test.dart`.
void main() {
  test('the frozen order fixture holds and the order is stable', () {
    expect(_correctness().failed, isEmpty);
    expect(_stability().failed, isEmpty);
  });

  test(
    'sections order and regroup time',
    skip: Platform.environment['SECTIONS_BENCH'] != '1',
    () {
      final correctness = _correctness();
      final stability = _stability();
      final timing = _timing(
        int.tryParse(Platform.environment['SECTIONS_BENCH_N'] ?? '') ?? 2000,
      );
      final result = {
        'correctness_cases': correctness.cases,
        'correctness_failures': correctness.failures,
        'correctness_failed': correctness.failed,
        'stability_checks': stability.cases,
        'stability_failures': stability.failures,
        'stability_failed': stability.failed,
        ...timing,
      };
      // ignore: avoid_print -- the benchmark's result
      print('SECTIONS_BENCH ${jsonEncode(result)}');
    },
  );
}

typedef _Tally = ({int cases, int failures, List<String> failed});

/// What the list shows with categories hidden: per shown section, its key
/// and the item ids in order.
List<String> _shown(Iterable<Item> items, Catalog catalog) => [
  for (final s in shownSections(sectionsOf(items, catalog)))
    [
      '${s.key}:',
      for (final b in s.blocks)
        for (final i in b.items) i.id,
    ].join(' '),
];

final _t0 = DateTime.utc(2026, 11);

Item _item(
  String id, {
  String? category,
  String? store,
  double? key,
  int minute = 0,
  ItemStatus status = ItemStatus.active,
}) => Item(
  id: id,
  name: id,
  status: status,
  createdAt: _t0.add(Duration(minutes: minute)),
  updatedAt: _t0.add(Duration(minutes: minute)),
  categoryId: category,
  storeId: store,
  sortKey: key,
);

const _cats = [
  Category(id: 'produce', name: 'Obst', sortOrder: 10),
  Category(id: 'bakery', name: 'Brot', sortOrder: 20),
  Category(id: 'chilled', name: 'Kühl', sortOrder: 30),
  Category(id: 'pantry', name: 'Vorrat', sortOrder: 40),
  Category(id: 'drugstore', name: 'Drogerie', sortOrder: 50),
  Category(id: 'custom', name: 'Eigene', sortOrder: 60),
  Category(id: 'other', name: 'Sonstiges', sortOrder: 1000),
];

const _fixture = Catalog(
  categories: _cats,
  stores: [
    Store(id: 'lidl', name: 'Lidl', sortOrder: 20),
    Store(id: 'dm', name: 'dm', sortOrder: 10),
    Store(id: 'edeka', name: 'Edeka', sortOrder: 30),
  ],
  layout: [
    StoreCategory(storeId: 'lidl', categoryId: 'bakery', sortOrder: 10),
    StoreCategory(storeId: 'lidl', categoryId: 'produce', sortOrder: 20),
    StoreCategory(storeId: 'lidl', categoryId: 'pantry', sortOrder: 30),
    StoreCategory(storeId: 'lidl', categoryId: 'chilled', sortOrder: 40),
    StoreCategory(storeId: 'lidl', categoryId: 'other', sortOrder: 50),
    StoreCategory(storeId: 'lidl', categoryId: 'drugstore', sortOrder: 60),
    StoreCategory(storeId: 'dm', categoryId: 'drugstore', sortOrder: 10),
    StoreCategory(storeId: 'dm', categoryId: 'pantry', sortOrder: 20),
    StoreCategory(storeId: 'dm', categoryId: 'other', sortOrder: 30),
    StoreCategory(
      storeId: 'dm',
      categoryId: 'produce',
      sortOrder: 40,
      hidden: true,
    ),
  ],
);

/// Fixed households and the order a shopper must see, written from
/// SPEC 2/3 and docs/STORE_LAYOUTS.md, not from the code's output.
_Tally _correctness() {
  final cases = <(String, List<Item>, Catalog, List<String>)>[
    (
      'stores in household order, no-store last, walk order inside',
      [
        _item('apfel', category: 'produce', store: 'lidl', key: 1024),
        _item('brot', category: 'bakery', store: 'lidl', key: 1024),
        _item('milch', category: 'chilled', store: 'lidl', key: 1024),
        _item('shampoo', category: 'drugstore', store: 'dm', key: 1024),
        _item('reis', category: 'pantry', key: 1024),
        _item('birne', category: 'produce', key: 1024),
      ],
      _fixture,
      ['dm: shampoo', 'lidl: brot apfel milch', 'none: birne reis'],
    ),
    (
      'sort keys order a group; null keys last, by creation, then id',
      [
        _item('c', category: 'pantry', store: 'lidl', key: 3072),
        _item('a', category: 'pantry', store: 'lidl', key: 1024),
        _item('z', category: 'pantry', store: 'lidl', minute: 2),
        _item('y', category: 'pantry', store: 'lidl', minute: 1),
        _item('x', category: 'pantry', store: 'lidl', minute: 1),
        _item('b', category: 'pantry', store: 'lidl', key: 2048),
      ],
      _fixture,
      ['lidl: a b c x y z'],
    ),
    (
      'items still being classified lead their store, unknown categories '
          'trail it',
      [
        _item('gone', category: 'deleted-cat', store: 'lidl', key: 1),
        _item('brot', category: 'bakery', store: 'lidl', key: 1024),
        _item('neu', store: 'lidl', minute: 5),
      ],
      _fixture,
      ['lidl: neu brot gone'],
    ),
    (
      'a category the store has no row for follows its rows in route order',
      [
        _item('eigen', category: 'custom', store: 'dm', key: 1024),
        _item('kühl', category: 'chilled', store: 'dm', key: 1024),
        _item('dusch', category: 'drugstore', store: 'dm', key: 1024),
        _item('nudeln', category: 'pantry', store: 'dm', key: 1024),
      ],
      _fixture,
      ['dm: dusch nudeln kühl eigen'],
    ),
    (
      'a hidden category still shows its items, at its row',
      [
        _item('apfel', category: 'produce', store: 'dm', key: 1024),
        _item('rest', category: 'other', store: 'dm', key: 1024),
        _item('dusch', category: 'drugstore', store: 'dm', key: 1024),
      ],
      _fixture,
      ['dm: dusch rest apfel'],
    ),
    (
      'an item of a deleted store shows without a store',
      [
        _item('alt', category: 'pantry', store: 'rewe-deleted', key: 1024),
        _item('obst', category: 'produce', key: 1024),
      ],
      _fixture,
      ['none: obst alt'],
    ),
    (
      'bought items are not in the list; empty stores are not shown',
      [
        _item(
          'weg',
          category: 'pantry',
          store: 'dm',
          status: ItemStatus.bought,
        ),
        _item('da', category: 'pantry', store: 'edeka', key: 1024),
      ],
      _fixture,
      ['edeka: da'],
    ),
    (
      'a store without layout rows walks the route order',
      [
        _item('sonst', category: 'other', store: 'edeka', key: 1024),
        _item('dusch', category: 'drugstore', store: 'edeka', key: 1024),
        _item('obst', category: 'produce', store: 'edeka', key: 1024),
        _item('brot', category: 'bakery', store: 'edeka', key: 1024),
      ],
      _fixture,
      ['edeka: obst brot dusch sonst'],
    ),
  ];
  final failed = <String>[];
  for (final (name, items, catalog, expected) in cases) {
    final got = _shown(items, catalog);
    if (!_same(got, expected)) {
      failed.add('$name: got $got');
    }
  }
  return (cases: cases.length, failures: failed.length, failed: failed);
}

bool _same(List<String> a, List<String> b) =>
    a.length == b.length &&
    [for (var i = 0; i < a.length; i++) i].every((i) => a[i] == b[i]);

/// The same household always shows the same order: computed again, from
/// rows in another order (realtime appends, a refetch returns ties in heap
/// order), and right after an edit that moves an item, as the server's
/// answer will show it.
_Tally _stability() {
  final failed = <String>[];
  var cases = 0;
  final random = Random(459);
  for (var round = 0; round < 40; round++) {
    final (items, catalog) = _household(
      random,
      items: 60 + round * 5,
      stores: 2 + round % 5,
      // Every fourth household has two stores with the same sort order:
      // two members adding a store at once both get max + 10.
      tiedStores: round % 4 == 3,
    );
    final first = _shown(items, catalog);
    cases++;
    if (!_same(first, _shown(items, catalog))) {
      failed.add('round $round: a second run differs');
    }
    for (var p = 0; p < 5; p++) {
      cases++;
      final shuffled = Catalog(
        categories: [...catalog.categories]..shuffle(random),
        stores: [...catalog.stores]..shuffle(random),
        layout: [...catalog.layout]..shuffle(random),
      );
      final got = _shown([...items]..shuffle(random), shuffled);
      if (!_same(first, got)) {
        failed.add('round $round shuffle $p: order depends on row order');
        break;
      }
    }
    // Moves to another store or category: the optimistic view must already
    // be the order the server's row will give (put last in its new group,
    // items_before_write: max + 1024 when the group changes).
    final known = {for (final c in catalog.categories) c.id};
    final active = items
        .where(
          (i) => i.status == ItemStatus.active && known.contains(i.categoryId),
        )
        .toList();
    for (var m = 0; m < 5; m++) {
      cases++;
      final moved = active[random.nextInt(active.length)];
      final toStore = random.nextBool()
          ? catalog.stores[random.nextInt(catalog.stores.length)].id
          : moved.storeId;
      final toCategory = toStore == moved.storeId
          ? catalog.categories
                .where((c) => c.id != moved.categoryId)
                .elementAt(random.nextInt(catalog.categories.length - 1))
                .id
          : moved.categoryId;
      final changes = ItemChanges(
        categoryId: toCategory == moved.categoryId ? null : toCategory,
        storeId: toStore == moved.storeId ? null : SetTo(toStore),
      );
      final optimistic = EditItem(moved.id, changes).apply(moved)!;
      final groupMax = items
          .where(
            (i) =>
                i.id != moved.id &&
                i.categoryId == toCategory &&
                i.storeId == toStore,
          )
          .map((i) => i.sortKey ?? 0)
          .fold<double>(0, max);
      final acked = optimistic.copyWith(sortKey: () => groupMax + 1024);
      List<Item> withItem(Item it) => [
        for (final i in items)
          if (i.id == moved.id) it else i,
      ];
      if (!_same(
        _shown(withItem(optimistic), catalog),
        _shown(withItem(acked), catalog),
      )) {
        failed.add(
          'round $round move $m: the item jumps when the server answers',
        );
      }
    }
  }
  return (cases: cases, failures: failed.length, failed: failed);
}

(List<Item>, Catalog) _household(
  Random random, {
  required int items,
  required int stores,
  bool tiedStores = false,
}) {
  final categories = [
    for (var c = 0; c < 25; c++)
      Category(id: 'cat$c', name: 'Kategorie $c', sortOrder: (c + 1) * 10),
  ];
  final storeList = [
    for (var s = 0; s < stores; s++)
      Store(
        id: 'store$s',
        name: 'Laden $s',
        sortOrder: tiedStores && s == stores - 1 ? s * 10 : (s + 1) * 10,
      ),
  ];
  final layout = [
    for (final store in storeList)
      for (final (i, c) in ([...categories]..shuffle(random)).indexed)
        if (i < 20)
          StoreCategory(
            storeId: store.id,
            categoryId: c.id,
            sortOrder: (i + 1) * 10,
            hidden: i % 7 == 6,
          ),
  ];
  final keys = <(String?, String?), double>{};
  final list = <Item>[
    for (var i = 0; i < items; i++)
      () {
        final store = random.nextInt(stores + 1) == stores
            ? null
            : storeList[random.nextInt(stores)].id;
        final pending = random.nextInt(40) == 0;
        final category = pending
            ? null
            : random.nextInt(50) == 0
            ? 'deleted$i'
            : categories[random.nextInt(categories.length)].id;
        // The server numbers every row it writes: only an add it has not
        // classified yet has no key.
        final key = pending
            ? null
            : keys.update(
                (store, category),
                (k) => k + 1024,
                ifAbsent: () => 1024,
              );
        return _item(
          'i${i.toString().padLeft(4, '0')}',
          category: category,
          store: store,
          key: key,
          minute: random.nextInt(600),
          status: random.nextInt(6) == 0
              ? ItemStatus.bought
              : ItemStatus.active,
        );
      }(),
  ];
  return (
    list,
    Catalog(categories: categories, stores: storeList, layout: layout),
  );
}

/// p50 and p95 µs of what the list does after an add or a category
/// change: the items map changes, and sections are computed again.
Map<String, Object> _timing(int n) {
  final random = Random(4590);
  final (base, catalog) = _household(random, items: 1000, stores: 12);
  final byId = {for (final i in base) i.id: i};
  final ids = byId.keys.toList();
  final adds = <int>[];
  final changes = <int>[];
  var shown = 0;
  final watch = Stopwatch();
  for (var r = 0; r < n + n ~/ 10; r++) {
    final add = _item('new$r', store: catalog.stores[r % 12].id, minute: 700);
    final afterAdd = {...byId, add.id: add};
    watch
      ..reset()
      ..start();
    shown += shownSections(sectionsOf(afterAdd.values, catalog)).length;
    watch.stop();
    if (r >= n ~/ 10) {
      adds.add(watch.elapsedMicroseconds);
    }
    final id = ids[r % ids.length];
    final moved = byId[id]!.copyWith(categoryId: catalog.categories[r % 25].id);
    final afterChange = {...byId, id: moved};
    watch
      ..reset()
      ..start();
    shown += shownSections(sectionsOf(afterChange.values, catalog)).length;
    watch.stop();
    if (r >= n ~/ 10) {
      changes.add(watch.elapsedMicroseconds);
    }
  }
  int pct(List<int> xs, double p) =>
      (xs..sort())[((xs.length - 1) * p).round()];
  return {
    'n': n,
    'items': base.length,
    'sections_built': shown,
    'add_p50_us': pct(adds, 0.5),
    'add_p95_us': pct(adds, 0.95),
    'change_p50_us': pct(changes, 0.5),
    'change_p95_us': pct(changes, 0.95),
    'regroup_p50_us': pct([...adds, ...changes], 0.5),
  };
}

import 'package:family_groceries/list/list_view/sections.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter_test/flutter_test.dart';

Item item(
  String id, {
  String? category = 'a',
  String? store,
  ItemStatus status = ItemStatus.active,
  int at = 0,
  int updated = 0,
  String? by,
  double? key,
}) => Item(
  id: id,
  name: id,
  categoryId: category,
  storeId: store,
  sortKey: key,
  status: status,
  createdAt: DateTime.utc(2026).add(Duration(minutes: at)),
  updatedAt: DateTime.utc(2026).add(Duration(minutes: updated)),
  boughtAt: status == ItemStatus.bought
      ? DateTime.utc(2026).add(Duration(minutes: at))
      : null,
  addedBy: by,
);

Duration minutes(int n) => Duration(minutes: n);

void main() {
  test('Legal GL-2: pharmacies by name or seed key, in any case; drugstores '
      'are not', () {
    Store store(String name, {String? seed}) =>
        Store(id: name, name: name, sortOrder: 0, seedKey: seed);
    for (final name in [
      'Apotheke',
      'APOTHEKE am Markt',
      'Shop-Apotheke',
      'Boots Pharmacy',
      'Pharmacie du Centre',
      'Farmacia Roma',
      'Apteka',
      'Eczane',
    ]) {
      expect(store(name).isPharmacy, isTrue, reason: name);
    }
    expect(store('Ecke', seed: 'apotheke').isPharmacy, isTrue);
    for (final name in ['dm', 'Rossmann', 'Lidl', 'Müller', 'DocMorris']) {
      expect(store(name).isPharmacy, isFalse, reason: name);
    }
  });

  const categories = [
    Category(id: 'b', name: 'B', sortOrder: 20),
    Category(id: 'a', name: 'A', sortOrder: 10),
  ];

  /// The blocks of a list without stores.
  List<CategoryBlock> blocksOf(Iterable<Item> items) =>
      sectionsOf(items, const Catalog(categories: categories)).single.blocks;

  test('a parse without a name keeps the typed one (job 111)', () {
    final typed = item('x').copyWith(name: ',');
    expect(const ParsedEntry(name: '').onto(typed, noStore: false).name, ',');
    expect(
      const ParsedEntry(
        name: 'Windeln',
        storeId: 'dm',
      ).onto(typed.copyWith(storeId: () => null), noStore: true).storeId,
      isNull,
      reason: 'Ohne Laden keeps the parsed store out',
    );
    expect(
      const ParsedEntry(name: ' ')
          .ontoRename(const ItemChanges(name: ','))
          .name,
      ',',
    );
  });

  test('pending ops fold over server rows in order', () {
    final server = {'x': item('x'), 'y': item('y')};
    final view = visibleItems(server, [
      SetStatus('x', ItemStatus.bought, DateTime.utc(2026)),
      const DeleteItem('y'),
      AddItem(item('z')),
      const EditItem(
        'z',
        ItemChanges(name: 'Zitronen', quantity: SetTo('3'), categoryId: 'b'),
      ),
    ]);
    expect(view['x']!.status, ItemStatus.bought);
    expect(view.containsKey('y'), isFalse);
    expect(view['z']!.name, 'Zitronen');
    expect(view['z']!.quantity, '3');
    expect(view['z']!.categoryId, 'b');
    expect(server['x']!.status, ItemStatus.active, reason: 'server untouched');
  });

  test('an add of a row the server already has keeps the server row', () {
    final server = {'x': item('x', category: 'b')};
    expect(visibleItems(server, [AddItem(item('x'))])['x']!.categoryId, 'b');
  });

  test('stale echoes do not overwrite newer rows', () {
    final server = {'x': item('x', updated: 5)};
    final stale = item('x', status: ItemStatus.bought, updated: 4);
    expect(mergeServerRow(server, stale), same(server));
    final fresh = item('x', status: ItemStatus.bought, updated: 6);
    expect(mergeServerRow(server, fresh)['x']!.status, ItemStatus.bought);
  });

  test('groups follow category sort order; unclassified items lead', () {
    final groups = blocksOf([
      item('b1', category: 'b', at: 1),
      item('a2', at: 2),
      item('a1', at: 1),
      item('new', category: null),
      item('gone', status: ItemStatus.bought),
      item('orphan', category: 'deleted-category'),
    ]);
    expect([for (final g in groups) g.category?.id], [null, 'a', 'b', null]);
    expect([for (final i in groups[1].items) i.id], ['a1', 'a2']);
    expect(groups.last.items.single.id, 'orphan');
  });

  test('a tick with a store tags the item; a plain tick keeps its tag', () {
    final at = DateTime.utc(2026);
    final tagged = {'x': item('x', store: 'dm')};
    final atLidl = SetStatus('x', ItemStatus.bought, at, storeId: 'lidl');
    expect(visibleItems(tagged, [atLidl])['x']!.storeId, 'lidl');
    final anywhere = SetStatus('x', ItemStatus.bought, at);
    expect(visibleItems(tagged, [anywhere])['x']!.storeId, 'dm');
  });

  test('an edit changes only its columns, null clearing one', () {
    final server = {
      'x': item(
        'x',
        store: 'dm',
        key: 5,
      ).copyWith(quantity: () => '2', brand: () => 'Ja!'),
    };
    Item edited(ItemChanges changes) =>
        visibleItems(server, [EditItem('x', changes)])['x']!;
    final brand = edited(
      const ItemChanges(brand: SetTo('Weihenstephan'), quantity: SetTo('3')),
    );
    expect(
      (brand.name, brand.brand, brand.quantity, brand.storeId, brand.sortKey),
      ('x', 'Weihenstephan', '3', 'dm', 5),
    );
    final cleared = edited(
      const ItemChanges(storeId: SetTo(null), brand: SetTo(null)),
    );
    expect((cleared.storeId, cleared.brand), (null, null));
    expect(cleared.quantity, '2', reason: 'untouched');
    expect(const ItemChanges().isEmpty, isTrue);
    expect(const ItemChanges(properties: SetTo(null)).isEmpty, isFalse);
  });

  test('a move changes store and category and goes last', () {
    final server = {
      'x': item('x', store: 'dm', at: 3, key: 1),
      'y': item('y', category: 'b', key: 5000),
    };
    final view = visibleItems(server, [
      const MoveItem('x', categoryId: 'b', storeId: null),
    ]);
    final moved = view['x']!;
    expect((moved.categoryId, moved.storeId), ('b', null));
    expect(moved.createdAt, server['x']!.createdAt);
    final groups = blocksOf(view.values);
    expect([for (final i in groups.single.items) i.id], ['y', 'x']);
    expect(
      visibleItems({}, [
        const MoveItem('gone', categoryId: 'b', storeId: null),
      ]),
      isEmpty,
    );
  });

  test('a group walks by sort key, unnumbered last, then by age', () {
    final groups = blocksOf([
      item('late', at: 1, key: 3072),
      item('early', at: 9, key: 1024),
      item('typed2', at: 5),
      item('typed1', at: 4),
      item('tie-b', at: 2, key: 2048),
      item('tie-a', at: 2, key: 2048),
    ]);
    expect(
      [for (final i in groups.single.items) i.id],
      ['early', 'tie-a', 'tie-b', 'late', 'typed1', 'typed2'],
    );
  });

  test("a queued place shows the item in its anchor's group at its key", () {
    final placed = visibleItems(
      {'x': item('x', store: 'dm', key: 1)},
      [
        const PlaceItem(
          'x',
          anchorId: 'b',
          edge: Edge.before,
          categoryId: 'b',
          storeId: null,
          sortKey: 1536,
        ),
      ],
    )['x']!;
    expect(
      (placed.categoryId, placed.storeId, placed.sortKey),
      ('b', null, 1536),
    );
  });

  test('every op survives its JSON', () {
    final at = DateTime.utc(2026, 10, 22, 12);
    final ops = <ItemOp>[
      AddItem(
        item('x', key: 2048).copyWith(
          brand: () => 'Pampers',
          properties: () => 'Größe 3',
          quantity: () => '2',
        ),
      ),
      SetStatus('x', ItemStatus.bought, at, storeId: 'dm'),
      const EditItem(
        'x',
        ItemChanges(
          name: 'Windeln',
          quantity: SetTo(null),
          brand: SetTo('Pampers'),
          properties: SetTo('Größe 3, Big Pack'),
          categoryId: 'b',
          storeId: SetTo(null),
        ),
      ),
      const EditItem('x', ItemChanges(storeId: SetTo('dm'))),
      const EditItem(
        'x',
        ItemChanges(name: 'Windeln'),
        keyBefore: 'windel',
        deviceParsed: true,
      ),
      const MoveItem('x', categoryId: 'b', storeId: 'dm'),
      const PlaceItem(
        'x',
        anchorId: 'y',
        edge: Edge.after,
        categoryId: 'a',
        storeId: null,
        sortKey: null,
      ),
      const DeleteItem('x'),
      const MergeItems(
        'x',
        mergeId: 'm',
        otherId: 'y',
        quantity: '1,5 kg',
        brand: null,
        properties: 'Bio',
      ),
      UnmergeItems('x', mergeId: 'm', kept: item('x'), merged: item('y')),
      AddItem(item('x'), autoCategory: true),
      AddItem(item('x'), deviceParsed: true),
      AddItem(item('x'), restored: true),
      AddItem(item('x'), noStore: true),
    ];
    for (final op in ops) {
      final back = ItemOp.fromJson(op.toJson());
      expect(back.runtimeType, op.runtimeType);
      expect(back.toJson(), op.toJson());
    }
    expect(
      (ItemOp.fromJson(ops[ops.length - 2].toJson()) as AddItem).restored,
      isTrue,
    );
    expect((ItemOp.fromJson(ops.last.toJson()) as AddItem).noStore, isTrue);
    expect(
      (ItemOp.fromJson(ops[ops.length - 4].toJson()) as AddItem).autoCategory,
      isTrue,
    );
    expect((ItemOp.fromJson(ops.first.toJson()) as AddItem).restored, isFalse);
    expect(
      (ItemOp.fromJson(ops[ops.length - 3].toJson()) as AddItem).deviceParsed,
      isTrue,
    );
    expect(
      (ItemOp.fromJson(ops.last.toJson()) as AddItem).deviceParsed,
      isFalse,
    );
    expect(
      ops.whereType<EditItem>().map(
        (op) => (ItemOp.fromJson(op.toJson()) as EditItem).deviceParsed,
      ),
      [false, false, true],
    );
    final both = ItemOp.fromJson(ops.whereType<EditItem>().last.toJson());
    expect(
      both is EditItem && both.keyBefore == 'windel' && both.deviceParsed,
      isTrue,
      reason: 'keyBefore (job 104) and deviceParsed (job 111) both survive',
    );
    expect(
      Item.fromJson({...item('x').toJson(), 'categorized_via': 'synonym'})
          .categorizedVia,
      'synonym',
    );
    final edit = ItemOp.fromJson(ops[3].toJson()) as EditItem;
    expect(edit.changes, const ItemChanges(storeId: SetTo('dm')));
    expect(
      Item.fromJson({...item('x').toJson(), 'sort_key': 2048}).sortKey,
      2048.0,
      reason: 'PostgREST sends a whole double as an int',
    );
  });

  group('duplicate hint (job 32b)', () {
    Item named(
      String id,
      String name, {
      String? key,
      String? brand,
      String? properties,
      String? quantity,
      ItemStatus status = ItemStatus.active,
      int at = 0,
    }) => Item(
      id: id,
      name: name,
      quantity: quantity,
      brand: brand,
      properties: properties,
      categoryId: 'a',
      status: status,
      createdAt: DateTime.utc(2026).add(minutes(at)),
      updatedAt: DateTime.utc(2026),
      canonicalKey: key,
    );

    test('similar items share the canonical key, open, oldest first', () {
      final karotten = named('k', 'Karotten', key: 'mohr', at: 5);
      final items = [
        named('m2', 'Mohrrüben', key: 'mohr', at: 2),
        named('m1', 'Möhren', key: 'mohr', at: 1),
        named('t', 'Möhren', key: 'mohr', status: ItemStatus.bought),
        named('x', 'Milch', key: 'milch'),
        karotten,
      ];
      expect(similarItems(karotten, items).map((i) => i.id), ['m1', 'm2']);
      expect(similarItems(named('n', 'Neu'), items), isEmpty);
      expect(similarItems(named('e', 'Emoji', key: ''), items), isEmpty);
    });

    test('details set on both and different tell items apart', () {
      final size3 = named('3', 'Windeln', key: 'windel', properties: 'Größe 3');
      final size4 = named('4', 'Windeln', key: 'windel', properties: 'Größe 4');
      final plain = named('p', 'Windeln', key: 'windel');
      expect(detailsDiffer(size3, size4), isTrue);
      expect(detailsDiffer(size3, plain), isFalse);
      expect(
        detailsDiffer(
          named('a', 'x', properties: 'Bio, 1 l'),
          named('b', 'x', properties: '1 L,bio'),
        ),
        isFalse,
      );
      expect(
        detailsDiffer(
          named('a', 'x', brand: 'Ja!'),
          named('b', 'x', brand: 'Rewe'),
        ),
        isTrue,
      );
      expect(
        detailsDiffer(named('a', 'x', brand: 'Ja!'), named('b', 'x')),
        isFalse,
      );
      expect(similarItems(size4, [size3, size4, plain]).map((i) => i.id), [
        'p',
      ]);
    });

    test('a pending merge shows one item at once; its undo shows both', () {
      final moehren = named('m', 'Möhren', key: 'mohr', quantity: '500 g');
      final karotten = named('k', 'Karotten', key: 'mohr', quantity: '1 kg');
      final server = {'m': moehren, 'k': karotten};
      const merge = MergeItems(
        'm',
        mergeId: 'x',
        otherId: 'k',
        quantity: '1,5 kg',
        brand: null,
        properties: null,
      );
      final merged = visibleItems(server, [merge]);
      expect(merged.keys, ['m']);
      expect(merged['m']!.quantity, '1,5 kg');
      expect(merged['m']!.name, 'Möhren');

      final undone = visibleItems(server, [
        merge,
        UnmergeItems('m', mergeId: 'x', kept: moehren, merged: karotten),
      ]);
      expect(undone.keys.toSet(), {'m', 'k'});
      expect(undone['m']!.quantity, '500 g');
      expect(undone['k']!.quantity, '1 kg');
    });
  });

  test('a parsed entry reads the parse_item row', () {
    final parsed = ParsedEntry.fromJson(const {
      'name': 'Windeln',
      'brand': 'Pampers',
      'properties': 'Größe 3',
      'quantity': '2',
      'store_id': 'dm',
      'category_id': 'drugstore',
    });
    expect(
      (
        parsed.name,
        parsed.brand,
        parsed.properties,
        parsed.quantity,
        parsed.storeId,
        parsed.categoryId,
      ),
      ('Windeln', 'Pampers', 'Größe 3', '2', 'dm', 'drugstore'),
    );
  });

  test('a store reorder renumbers the stores', () {
    const catalog = Catalog(
      stores: [
        Store(id: 'dm', name: 'dm', sortOrder: 10),
        Store(id: 'lidl', name: 'Lidl', sortOrder: 20),
      ],
    );
    final next = catalog.withStoreOrder(['lidl', 'dm']);
    expect(
      [for (final s in next.stores) (s.id, s.sortOrder)],
      [('lidl', 10), ('dm', 20)],
    );
  });

  test('a renamed chain stops being its chain, a renamed Baumarkt stays the '
      'hardware store', () {
    const catalog = Catalog(
      stores: [
        Store(id: 'dm', name: 'dm', sortOrder: 10, seedKey: 'dm'),
        Store(id: 'b', name: 'Baumarkt', sortOrder: 20, seedKey: 'hardware'),
      ],
    );
    final renamed = catalog
        .withStoreName('dm', 'Drogerie')
        .withStoreName('b', 'Baumarkt Nord');
    expect(
      [for (final s in renamed.stores) (s.name, s.seedKey)],
      [('Drogerie', null), ('Baumarkt Nord', 'hardware')],
    );
    expect(
      catalog.withStoreName('dm', ' DM ').store('dm')?.seedKey,
      'dm',
      reason: 'the same name in another case is still the chain',
    );
  });

  test('recently used is newest first', () {
    final bought = recentlyUsed([
      item('old', status: ItemStatus.bought, at: 1),
      item('new', status: ItemStatus.bought, at: 2),
      item('active'),
    ]);
    expect([for (final i in bought) i.id], ['new', 'old']);
  });

  test('recently used shows a thing once, its newest purchase, and not '
      'while it is on the list again', () {
    Item named(
      String id,
      String name, {
      required int at,
      ItemStatus status = ItemStatus.bought,
      String? canonical,
    }) => Item(
      id: id,
      name: name,
      status: status,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026).add(Duration(minutes: at)),
      canonicalKey: canonical,
    );
    final used = recentlyUsed([
      named('b1', 'Bananen', at: 1),
      named('b2', 'Bananen', at: 3),
      named('k1', 'Karotten', at: 2, canonical: 'mohr'),
      named('m1', 'Möhren', at: 4, canonical: 'mohr'),
      named('e1', 'Eier', at: 5),
      named('e2', 'Eier', at: 6, status: ItemStatus.active),
    ]);
    expect([for (final i in used) i.id], ['m1', 'b2']);
  });

  test('a member is found by id', () {
    const catalog = Catalog(
      members: [Member(id: 'l', displayName: 'Lea')],
    );
    expect(catalog.member('l')?.displayName, 'Lea');
    expect(catalog.member('unknown'), isNull);
  });

  group('seen mark', () {
    final items = [
      item('old', by: 'lea', at: 1),
      item('a', by: 'lea', at: 5),
      item('b', by: 'lea', at: 6),
      item('mine', by: 'peter', at: 7),
      item('pending', at: 8),
      item('gone', by: 'lea', at: 9, status: ItemStatus.bought),
    ];
    final baseline = SeenMark(until: DateTime.utc(2026).add(minutes(2)));
    List<Item> withStatus(String id, ItemStatus status) => [
      for (final i in items)
        if (i.id == id) i.copyWith(status: status) else i,
    ];

    test('fresh is what a partner added after the mark', () {
      expect(baseline.fresh(items, 'peter'), {'a', 'b'});
      expect(const SeenMark().fresh(items, 'peter'), {'old', 'a', 'b'});
      expect(baseline.fresh(items, 'lea'), {'mine'});
    });

    test('marking some keeps their ids, marking all moves the mark', () {
      final some = baseline.marking({'a', 'mine'}, items, 'peter');
      expect(some.fresh(items, 'peter'), {'b'});
      expect(some.ids, {'a'});
      final all = some.marking({'b'}, items, 'peter');
      expect(all.fresh(items, 'peter'), isEmpty);
      expect(all.ids, isEmpty);
      expect(all.until, DateTime.utc(2026).add(minutes(6)));
    });

    test('ids of items that are gone are pruned', () {
      final some = baseline.marking({'a'}, items, 'peter');
      final later = some.marking(const {}, [items[2]], 'peter');
      expect(later.ids, isEmpty);
      expect(later.fresh(items, 'peter'), {'a', 'b'});
    });

    test('a seen item ticked and put back is no news', () {
      final seen = baseline.marking({'a'}, items, 'peter');
      final ticked = withStatus('a', ItemStatus.bought);
      final afterTick = seen.marking(const {}, ticked, 'peter');
      expect(afterTick.fresh(items, 'peter'), {'b'});
    });

    test('an unseen partner item that comes back is news', () {
      final all = baseline.marking({'a', 'b'}, items, 'peter');
      expect(all.until, DateTime.utc(2026).add(minutes(6)));
      final back = withStatus('gone', ItemStatus.active);
      expect(all.fresh(back, 'peter'), {'gone'});
    });
  });

  test('suggestions match names, then word starts, then inside', () {
    const usuals = [
      Usual(name: 'Bio-Milch', due: false),
      Usual(name: 'Hafermilch', due: false),
      Usual(name: 'Milch', due: true),
      Usual(name: 'Käse', due: true),
      Usual(name: 'Brot', due: true),
    ];
    List<String> names(List<Usual> list) => [for (final u in list) u.name];
    expect(names(suggestUsuals(usuals, const [], ' MILCH ')), [
      'Milch',
      'Bio-Milch',
      'Hafermilch',
    ]);
    expect(names(suggestUsuals(usuals, const [], 'kae')), ['Käse']);
    expect(names(suggestUsuals(usuals, const [], 'Kä')), ['Käse']);
    expect(suggestUsuals(usuals, const [], '  '), isEmpty);
    final brot = Item(
      id: 'x',
      name: 'brot',
      status: ItemStatus.active,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    expect(names(dueUsualsOf(usuals, [brot])), ['Milch', 'Käse']);
  });

  group('typos and part of a word, as the server matches them', () {
    List<String> names(List<Usual> list) => [for (final u in list) u.name];
    const usuals = [
      Usual(name: 'Hafermilch', due: false),
      Usual(name: 'Milchreis', due: false),
      Usual(name: 'Tomte', due: false),
      Usual(name: 'Cocktailtomate', due: false),
      Usual(name: 'Tomatensoße', due: false),
      Usual(name: 'Tomate', due: false),
      Usual(name: 'Reis', due: false),
      Usual(name: 'Joghurt', due: false),
    ];

    test('Hafermlch and milch find Hafermilch', () {
      expect(names(suggestUsuals(usuals, const [], 'Hafermlch')), [
        'Hafermilch',
      ]);
      expect(names(suggestUsuals(usuals, const [], 'milch')), [
        'Milchreis',
        'Hafermilch',
      ]);
    });

    test('exact, prefix, inside a word, then a typo', () {
      expect(names(suggestUsuals(usuals, const [], 'Tomate')), [
        'Tomate',
        'Tomatensoße',
        'Cocktailtomate',
        'Tomte',
      ]);
    });

    test('under 3 letters prefixes only; in-word from 4', () {
      expect(names(suggestUsuals(usuals, const [], 'af')), isEmpty);
      expect(names(suggestUsuals(usuals, const [], 'Hf')), isEmpty);
      expect(names(suggestUsuals(usuals, const [], 'Ris')), ['Reis']);
      expect(names(suggestUsuals(usuals, const [], 'eis')), isEmpty);
    });

    test('one edit up to 5 letters, two from 6, same first letter', () {
      expect(suggestionMatch('mlc', 'milch'), isNull);
      expect(suggestionMatch('mlch', 'milch'), 4);
      expect(suggestionMatch('jogurt', 'joghurt'), 4);
      expect(suggestionMatch('tomatn', 'tomte'), 4);
      expect(suggestionMatch('tomat', 'tomte'), isNull);
      expect(suggestionMatch('eis', 'reis'), isNull);
      expect(suggestionMatch('bete', 'rote beete'), 4);
      expect(suggestionMatch('rote bte', 'rote bete'), 4);
    });
  });

  test('used lately: the last 30 days, not due, not on the list', () {
    final now = DateTime.utc(2026, 11);
    Usual used(String name, int days, {bool due = false}) => Usual(
      name: name,
      due: due,
      lastUsed: now.subtract(Duration(days: days)),
    );
    final usuals = [
      used('Brot', 3),
      used('Milch', 1, due: true),
      used('Mehl', 31),
      used('Käse', 1),
      const Usual(name: 'Salz', due: false),
      used('Butter', 2),
    ];
    final butter = Item(
      id: 'x',
      name: 'Butter',
      status: ItemStatus.active,
      createdAt: now,
      updatedAt: now,
    );
    expect(
      [
        for (final u in recentUsualsOf(usuals, [butter], now)) u.name,
      ],
      ['Käse', 'Brot'],
    );
    expect(recentUsualsOf(usuals, const [], now, limit: 1), hasLength(1));
    final back = Usual.fromJson(used('Brot', 3).toJson());
    expect(back.lastUsed, now.subtract(const Duration(days: 3)));
    expect(
      Usual.fromJson(const {'name': 'Brot', 'due': false}).lastUsed,
      isNull,
      reason: 'a cache from before has no last use',
    );
  });

  test('an edit to the same value is the same edit', () {
    expect(const SetTo('2 l'), const SetTo('2 l'));
    expect(const SetTo<String?>(null), const SetTo<String?>(null));
    expect(const SetTo('2 l'), isNot(const SetTo('3 l')));
  });

  group('an op once its add turned out to be the open item kept', () {
    final at = DateTime.utc(2026, 10, 28);

    test('an op on another item stays as it is', () {
      final op = SetStatus('other', ItemStatus.bought, at);
      expect(op.ontoKept('copy', 'kept'), same(op));
    });

    test('a place next to the copy moves next to the kept item', () {
      const op = PlaceItem(
        'other',
        anchorId: 'copy',
        edge: Edge.before,
        categoryId: 'c1',
        storeId: null,
        sortKey: 2,
      );
      final moved = op.ontoKept('copy', 'kept')! as PlaceItem;
      expect(moved.itemId, 'other');
      expect(moved.anchorId, 'kept');
      expect(moved.edge, Edge.before);
    });
  });

  test('four typed letters inside a name match it', () {
    expect(suggestionMatch('ilch', 'vollmilch'), 3);
    expect(suggestionMatch('lch', 'vollmilch'), isNull);
  });

  test('categories a store has no row for follow its layout, in route '
      'order', () {
    const catalog = Catalog(
      categories: [
        Category(id: 'fruit', name: 'Obst', sortOrder: 10),
        Category(id: 'bread', name: 'Brot', sortOrder: 20),
        Category(id: 'dairy', name: 'Milch', sortOrder: 30),
      ],
      layout: [
        StoreCategory(storeId: 'lidl', categoryId: 'dairy', sortOrder: 10),
        StoreCategory(
          storeId: 'lidl',
          categoryId: 'fruit',
          sortOrder: 20,
          hidden: true,
        ),
      ],
    );
    expect(
      [
        for (final stop in walkingOrder(catalog, 'lidl'))
          '${stop.category.id}${stop.hidden ? ' (hidden)' : ''}',
      ],
      ['dairy', 'fruit (hidden)', 'bread'],
    );
  });
}

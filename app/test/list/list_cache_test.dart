import 'dart:convert';

import 'package:family_groceries/list/list_cache.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final at = DateTime.utc(2026, 10, 22, 12);
  final milk = Item(
    id: 'milk',
    name: 'Milch',
    quantity: '2',
    brand: 'Weihenstephan',
    properties: '1,5 %',
    categoryId: 'chilled',
    storeId: 'lidl',
    sortKey: 1536.5,
    status: ItemStatus.bought,
    createdAt: at,
    updatedAt: at.add(const Duration(minutes: 1)),
    boughtAt: at.add(const Duration(minutes: 1)),
    addedBy: 'lea',
  );
  final bread = Item(
    id: 'bread',
    name: 'Brot',
    status: ItemStatus.active,
    createdAt: DateTime(2026, 10, 22, 14),
    updatedAt: DateTime(2026, 10, 22, 14),
  );
  final snapshot = ListSnapshot(
    catalog: const Catalog(
      categories: [
        Category(id: 'chilled', name: 'Kühlregal', sortOrder: 30),
        Category(
          id: 'other',
          name: 'Sonstiges',
          sortOrder: 1000,
          seedKey: 'other',
        ),
      ],
      stores: [Store(id: 'lidl', name: 'Lidl', sortOrder: 20, seedKey: 'lidl')],
      layout: [
        StoreCategory(
          storeId: 'lidl',
          categoryId: 'other',
          sortOrder: 10,
          hidden: true,
        ),
      ],
      members: [
        Member(id: 'peter', displayName: 'Peter'),
        Member(id: 'lea', displayName: 'Lea'),
      ],
    ),
    server: [milk],
    pending: [
      AddItem(bread),
      SetStatus('bread', ItemStatus.bought, at, storeId: 'lidl'),
      SetStatus('milk', ItemStatus.active, at),
      const EditItem(
        'milk',
        ItemChanges(
          name: 'Hafermilch',
          quantity: SetTo(null),
          brand: SetTo('Alpro'),
          categoryId: 'other',
        ),
      ),
      const MoveItem('bread', categoryId: 'other', storeId: null),
      const PlaceItem(
        'bread',
        anchorId: 'milk',
        edge: Edge.before,
        categoryId: 'chilled',
        storeId: 'lidl',
        sortKey: 768.25,
      ),
      const DeleteItem('milk'),
    ],
    usuals: const [
      Usual(name: 'Gurken', quantity: '2', due: true),
      Usual(name: 'Brot', due: false),
    ],
  );

  ListSnapshot roundTrip(ListSnapshot s) => ListSnapshot.fromJson(
    jsonDecode(jsonEncode(s.toJson())) as Map<String, Object?>,
  );

  test('a snapshot survives encoding, with every op kind', () {
    final back = roundTrip(snapshot);
    expect(back.toJson(), snapshot.toJson());
    expect(back.pending.map((op) => op.runtimeType), [
      AddItem,
      SetStatus,
      SetStatus,
      EditItem,
      MoveItem,
      PlaceItem,
      DeleteItem,
    ]);
    final edit = back.pending[3] as EditItem;
    expect(edit.changes.toColumns(), {
      'name': 'Hafermilch',
      'quantity': null,
      'brand': 'Alpro',
      'category_id': 'other',
    }, reason: 'only the changed columns, a cleared one as null');
    expect(back.server.single.sortKey, 1536.5);
    expect(back.server.single.brand, 'Weihenstephan');
    expect(back.server.single.properties, '1,5 %');
    expect(back.catalog.fallback?.id, 'other');
    expect(back.catalog.layout.single.hidden, isTrue);
    expect(back.server.single.boughtAt, milk.boughtAt);
    expect(back.server.single.createdAt.isUtc, isTrue);
    expect(back.pending.first.apply(null)!.createdAt, bread.createdAt);
    expect(back.server.single.addedBy, 'lea');
    expect(
      [for (final m in back.catalog.members) m.displayName],
      ['Peter', 'Lea'],
    );
    expect(
      [for (final u in back.usuals) (u.name, u.quantity, u.due)],
      [('Gurken', '2', true), ('Brot', null, false)],
    );
  });

  test('a version 1 snapshot loads with its queued ops', () {
    // As the app before who-added and usuals wrote it.
    const v1 = '''
{"version":1,
 "catalog":{"categories":[{"id":"chilled","name":"Kühlregal","sort_order":30,"seed_key":null}],
            "stores":[],"layout":[]},
 "server":[{"id":"milk","name":"Milch","quantity":null,"category_id":"chilled",
            "store_id":null,"status":"active","created_at":"2026-10-22T12:00:00.000Z",
            "updated_at":"2026-10-22T12:00:00.000Z","bought_at":null}],
 "pending":[{"item_id":"bread","op":"add","item":{"id":"bread","name":"Brot",
              "quantity":"2","category_id":null,"store_id":null,"status":"active",
              "created_at":"2026-10-22T12:01:00.000Z",
              "updated_at":"2026-10-22T12:01:00.000Z","bought_at":null}},
            {"item_id":"milk","op":"status","status":"bought",
             "at":"2026-10-22T12:02:00.000Z","store_id":null}]}''';
    final loaded = ListSnapshot.fromJson(
      jsonDecode(v1) as Map<String, Object?>,
    );
    expect(loaded.pending.map((op) => op.runtimeType), [AddItem, SetStatus]);
    expect(
      loaded.toJson()['version'],
      ListSnapshot.version,
      reason: 'upgraded through v2',
    );
    expect(loaded.server.single.addedBy, isNull);
    expect(loaded.server.single.sortKey, isNull);
    expect(loaded.catalog.members, isEmpty);
    expect(loaded.usuals, isEmpty);
    final visible = visibleItems({
      for (final item in loaded.server) item.id: item,
    }, loaded.pending);
    expect(visible['bread']!.quantity, '2');
    expect(visible['milk']!.status, ItemStatus.bought);
    expect(roundTrip(loaded).toJson(), loaded.toJson());
  });

  test('a version 2 snapshot loads with its queued edits and moves', () {
    // As the app before brand, properties and walk order wrote it.
    const v2 = '''
{"version":2,
 "catalog":{"categories":[{"id":"chilled","name":"Kühlregal","sort_order":30,"seed_key":null},
                          {"id":"other","name":"Sonstiges","sort_order":1000,"seed_key":"other"}],
            "stores":[{"id":"dm","name":"dm","sort_order":10,"seed_key":"dm"}],"layout":[],
            "members":[{"id":"lea","display_name":"Lea"}]},
 "server":[{"id":"milk","name":"Milch","quantity":"1","category_id":"chilled",
            "store_id":"dm","status":"active","created_at":"2026-10-22T12:00:00.000Z",
            "updated_at":"2026-10-22T12:00:00.000Z","bought_at":null,"added_by":"lea"},
           {"id":"tea","name":"Tee","quantity":null,"category_id":"other",
            "store_id":null,"status":"active","created_at":"2026-10-22T12:00:00.000Z",
            "updated_at":"2026-10-22T12:00:00.000Z","bought_at":null,"added_by":"lea"}],
 "pending":[{"item_id":"milk","op":"edit","name":"Hafermilch","quantity":null,
             "category_id":"other","store_id":null},
            {"item_id":"tea","op":"move","category_id":"chilled"},
            {"item_id":"tea","op":"delete"}],
 "usuals":[{"name":"Brot","quantity":null,"due":true}]}''';
    final loaded = ListSnapshot.fromJson(
      jsonDecode(v2) as Map<String, Object?>,
    );
    expect(loaded.pending.map((op) => op.runtimeType), [
      EditItem,
      EditItem,
      DeleteItem,
    ]);
    expect((loaded.pending[0] as EditItem).changes.toColumns(), {
      'name': 'Hafermilch',
      'quantity': null,
      'category_id': 'other',
      'store_id': null,
    }, reason: 'a v2 edit wrote all four columns');
    expect((loaded.pending[1] as EditItem).changes.toColumns(), {
      'category_id': 'chilled',
    }, reason: 'a v2 move only changed the category');
    expect(
      [
        for (final item in loaded.server)
          (item.brand, item.properties, item.sortKey),
      ],
      [(null, null, null), (null, null, null)],
    );
    final visible = visibleItems({
      for (final item in loaded.server) item.id: item,
    }, loaded.pending.take(2));
    final hafer = visible['milk']!;
    expect(
      (hafer.name, hafer.quantity, hafer.categoryId, hafer.storeId),
      ('Hafermilch', null, 'other', null),
    );
    expect(visible['tea']!.categoryId, 'chilled');
    expect(roundTrip(loaded).toJson(), loaded.toJson());
  });

  test('folding the decoded ops shows the same list', () {
    Map<String, Item> visible(ListSnapshot s) => visibleItems({
      for (final item in s.server) item.id: item,
    }, s.pending.take(5));
    final before = visible(snapshot);
    final after = visible(roundTrip(snapshot));
    expect(after.keys, before.keys);
    expect(
      [for (final i in after.values) i.toJson()],
      [for (final i in before.values) i.toJson()],
    );
    expect(after['milk']!.name, 'Hafermilch');
    expect(after['bread']!.status, ItemStatus.bought);
  });

  test('an unknown version or op is refused', () {
    final json = snapshot.toJson();
    expect(
      () => ListSnapshot.fromJson({...json, 'version': 0}),
      throwsFormatException,
    );
    expect(
      () =>
          ListSnapshot.fromJson({...json, 'version': ListSnapshot.version + 1}),
      throwsFormatException,
      reason: 'a downgraded app cannot read a newer snapshot',
    );
    expect(
      () => ItemOp.fromJson({'item_id': 'x', 'op': 'teleport'}),
      throwsFormatException,
    );
  });

  test('prefs saved before the explainer card existed keep it showing', () {
    final prefs = ListPrefs.fromJson(const {
      'folded': ['dm'],
    });
    expect(prefs.folded, {'dm'});
    expect(prefs.hintDismissed, isFalse);
    expect(ListPrefs.fromJson(const {}).folded, isEmpty);
  });
}

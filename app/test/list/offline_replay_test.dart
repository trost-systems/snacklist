import 'dart:async';

import 'package:family_groceries/list/entry.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_repository.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/pricing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_repository.dart';
import 'memory_cache.dart';

Item _item(String id, {ItemStatus status = ItemStatus.active}) => Item(
  id: id,
  name: id,
  status: status,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

void main() {
  // Job 64b: an add replayed after the partner added the same thing lands on
  // the partner's open item (`put_item`); every op queued behind it that
  // names the offline copy must follow onto that item.
  group('ops queued behind an add that lands on an open twin', () {
    const from = 'mine';
    const kept = 'leas';
    final at = DateTime.utc(2026, 3, 1, 9);

    test('go to the kept item, keeping what they do', () {
      final moved = {
        SetStatus(from, ItemStatus.bought, at, storeId: 's1'): SetStatus(
          kept,
          ItemStatus.bought,
          at,
          storeId: 's1',
        ),
        const MoveItem(from, categoryId: 'c', storeId: null): const MoveItem(
          kept,
          categoryId: 'c',
          storeId: null,
        ),
        const MoveToList(from, listId: 'l2'): const MoveToList(
          kept,
          listId: 'l2',
        ),
        ClaimItem(from, userId: 'peter', at: at, quantity: '2'): ClaimItem(
          kept,
          userId: 'peter',
          at: at,
          quantity: '2',
        ),
        const UnclaimItem(from, userId: 'peter'): const UnclaimItem(
          kept,
          userId: 'peter',
        ),
        DeclineShop(from, at): DeclineShop(kept, at),
      };
      for (final MapEntry(key: op, value: want) in moved.entries) {
        expect(
          op.ontoKept(from, kept)?.toJson(),
          want.toJson(),
          reason: '${op.runtimeType}',
        );
      }
      final edit = const EditItem(
        from,
        ItemChanges(quantity: SetTo('3')),
        keyBefore: 'butter',
        deviceParsed: true,
      ).ontoKept(from, kept)!;
      expect(
        edit.toJson(),
        const EditItem(
          kept,
          ItemChanges(quantity: SetTo('3')),
          keyBefore: 'butter',
          deviceParsed: true,
        ).toJson(),
      );
    });

    test('a delete is dropped: it removed only the offline copy', () {
      expect(const DeleteItem(from).ontoKept(from, kept), isNull);
    });

    test("an undone delete's price is dropped; a typed price follows", () {
      final price = Price(
        unitMicros: 1990000,
        basis: PriceBasis.unit,
        per: PricePer.piece,
        currency: 'EUR',
        pricedAt: at,
      );
      expect(
        SetPrice(from, price: price, restored: true).ontoKept(from, kept),
        isNull,
      );
      expect(
        SetPrice(
          from,
          price: price,
          quantity: const SetTo('500 g'),
        ).ontoKept(from, kept)?.toJson(),
        SetPrice(kept, price: price, quantity: const SetTo('500 g')).toJson(),
      );
    });

    test('a placement next to the offline copy is next to the kept item', () {
      final place = const PlaceItem(
        'brot',
        anchorId: from,
        edge: Edge.after,
        categoryId: 'c',
        storeId: null,
        sortKey: 1.5,
      ).ontoKept(from, kept);
      expect(place, isA<PlaceItem>());
      expect(place!.itemId, 'brot');
      expect((place as PlaceItem).anchorId, kept);
    });

    test(
      'a placement of the offline copy next to the kept item is dropped',
      () {
        expect(
          const PlaceItem(
            from,
            anchorId: kept,
            edge: Edge.before,
            categoryId: null,
            storeId: null,
            sortKey: null,
          ).ontoKept(from, kept),
          isNull,
        );
      },
    );

    test('a merge of the offline copy into another item merges the kept '
        'one; a merge of the two into each other is dropped', () {
      final merge = const MergeItems(
        'milch',
        mergeId: 'm1',
        otherId: from,
        quantity: '2 l',
        brand: null,
        properties: null,
      ).ontoKept(from, kept);
      expect(merge, isA<MergeItems>());
      expect((merge! as MergeItems).otherId, kept);
      expect(merge.itemId, 'milch');
      expect(
        const MergeItems(
          kept,
          mergeId: 'm2',
          otherId: from,
          quantity: '2',
          brand: null,
          properties: null,
        ).ontoKept(from, kept),
        isNull,
      );
    });

    test('ops of other items stay as they are', () {
      final other = SetStatus('brot', ItemStatus.bought, at);
      expect(identical(other.ontoKept(from, kept), other), isTrue);
      final add = AddItem(_item(from));
      expect(identical(add.ontoKept(from, kept), add), isTrue);
    });
  });

  group('a queued "Nein, nur abgehakt"', () {
    test('survives the device queue and applies to nothing', () {
      final decline = DeclineShop('brot', DateTime.utc(2026, 3, 1, 9, 30));
      final back = ItemOp.fromJson(decline.toJson());
      expect(back, isA<DeclineShop>());
      expect(back.itemId, 'brot');
      expect((back as DeclineShop).at, decline.at);
      final bought = _item('brot', status: ItemStatus.bought);
      expect(back.apply(bought), same(bought));
      expect(back.apply(null), isNull);
    });
  });

  group('a tick and its undo, shown before the server answers', () {
    final at = DateTime.utc(2026, 3, 1, 9);
    final leasTick = _item(
      'brot',
      status: ItemStatus.bought,
    ).copyWith(boughtAt: () => at, boughtBy: () => 'lea');

    test('an undo clears when and by whom it was bought', () {
      final open = SetStatus('brot', ItemStatus.active, at).apply(leasTick)!;
      expect(open.status, ItemStatus.active);
      expect(open.boughtAt, isNull);
      expect(open.boughtBy, isNull);
    });

    test('a tick takes its time and leaves who to the server', () {
      final later = at.add(const Duration(minutes: 5));
      final ticked = SetStatus(
        'brot',
        ItemStatus.bought,
        later,
        storeId: 'rewe',
      ).apply(leasTick)!;
      expect(ticked.boughtAt, later);
      expect(ticked.boughtBy, 'lea');
      expect(ticked.storeId, 'rewe');
      expect(
        SetStatus('brot', ItemStatus.bought, later).apply(ticked)!.storeId,
        'rewe',
        reason: 'a tick without a store keeps the one the item has',
      );
    });
  });

  group('replayed after the partner added the same item', () {
    late FakeRepository repo;
    late MemoryListCache cache;
    late ListCubit cubit;

    Future<void> settle() => pumpEventQueue();

    Future<void> reconnect() async {
      repo.online = true;
      repo.emitStatus!(ConnectionStatus.online);
      await settle();
    }

    setUp(() async {
      repo = FakeRepository();
      cache = MemoryListCache();
      cubit = ListCubit(repo, cache, userId: 'peter', grace: Duration.zero)
        ..start();
      await settle();
    });

    tearDown(() => cubit.close());

    String add(String text) =>
        (cubit.addEntry(parseEntry(text)) as Added).item.id;

    List<ItemOp> sentButAdds() => [
      for (final op in repo.sent)
        if (op is! AddItem) op,
    ];

    test("a placement of the offline add moves the partner's item", () async {
      add('Brot');
      add('Milch');
      await settle();
      repo.online = false;
      final butter = add('Butter');
      cubit.place(butter, const PlaceFirst());
      await settle();
      final leas = repo.remoteAdd('Butter');

      await reconnect();
      expect(cubit.state.pending, isEmpty);
      final place = repo.sent.whereType<PlaceItem>().single;
      expect(place.itemId, leas.id);
      expect(
        repo.sent.where((op) => op.itemId == butter && op is! AddItem),
        isEmpty,
        reason: 'nothing is sent for the copy the server never kept',
      );
      expect(
        cubit.state.items.values.where((i) => i.name == 'Butter').single.id,
        leas.id,
      );
    });

    test("a placement next to the offline add is next to the partner's "
        'item', () async {
      final brot = add('Brot');
      await settle();
      repo.online = false;
      final butter = add('Butter');
      cubit.place(brot, PlaceAfter(butter));
      await settle();
      final leas = repo.remoteAdd('Butter');

      await reconnect();
      expect(cubit.state.pending, isEmpty);
      final place = repo.sent.whereType<PlaceItem>().single;
      expect(place.itemId, brot);
      expect(place.anchorId, leas.id);
      expect(sentButAdds(), [place]);
    });

    test('a tick and its "Nein, nur abgehakt" survive a restart offline and '
        "go to the partner's item, in order", () async {
      repo.online = false;
      final butter = add('Butter');
      cubit
        ..tick(butter)
        ..declineShop(butter);
      await settle();
      await cubit.close();
      cubit = ListCubit(repo, cache, userId: 'peter', grace: Duration.zero)
        ..start();
      await settle();
      expect(
        [for (final op in cubit.state.pending) op.runtimeType],
        [AddItem, SetStatus, DeclineShop],
      );
      final leas = repo.remoteAdd('Butter');

      await reconnect();
      expect(cubit.state.pending, isEmpty);
      expect(
        [for (final op in sentButAdds()) (op.runtimeType, op.itemId)],
        [(SetStatus, leas.id), (DeclineShop, leas.id)],
      );
      expect(repo.rows[leas.id]!.status, ItemStatus.bought);
    });

    test('a merge whose kept item the partner deleted moves nothing queued '
        'for it onto the other item', () async {
      final moehren = add('2 Möhren');
      final karotten = add('1 Karotten');
      await settle();
      repo.online = false;
      final items = cubit.state.items;
      expect(
        cubit.merge(DedupeHint(items[karotten]!, items[moehren]!)),
        isNotNull,
      );
      cubit.edit(moehren, const ItemChanges(quantity: SetTo('5')));
      await settle();
      repo.rows.remove(moehren);

      await reconnect();
      expect(cubit.state.pending, isEmpty);
      expect(repo.rows[karotten]!.quantity, '1');
      expect(repo.sent.whereType<EditItem>().single.itemId, moehren);
    });
  });

  // Job 99 (hc-sync): an answer may have read its rows before a delete
  // realtime missed, so a row in it that the list's last snapshot lacked
  // asks for one more resync; a row the snapshot had asks for none.
  group('an answer that arrives after a resync showed the list', () {
    late FakeRepository repo;
    late ListCubit cubit;

    Future<void> settle() => pumpEventQueue();

    setUp(() async {
      repo = FakeRepository();
      cubit = ListCubit(
        repo,
        MemoryListCache(),
        userId: 'peter',
        grace: Duration.zero,
      )..start();
      await settle();
    });

    tearDown(() => cubit.close());

    test('with a row the snapshot had asks for no further resync', () async {
      final brot = (cubit.addEntry(parseEntry('Brot')) as Added).item.id;
      await settle();
      final answer = repo.gate = Completer<void>();
      cubit.tick(brot);
      await settle();
      await cubit.resync();
      final fetches = repo.itemFetches;

      repo.gate = null;
      answer.complete();
      await settle();
      expect(cubit.state.pending, isEmpty);
      expect(repo.itemFetches, fetches);
      expect(cubit.state.items[brot]!.status, ItemStatus.bought);
    });

    test("with the partner's item the add turned out to be, which the "
        'snapshot lacked, resyncs once', () async {
      final answer = repo.gate = Completer<void>();
      final mine = (cubit.addEntry(parseEntry('Butter')) as Added).item.id;
      await settle();
      await cubit.resync();
      final leas = repo.remoteAdd('Butter');
      final fetches = repo.itemFetches;

      repo.gate = null;
      answer.complete();
      await settle();
      expect(cubit.state.pending, isEmpty);
      expect(repo.itemFetches, fetches + 1);
      expect(cubit.state.items.keys, isNot(contains(mine)));
      expect(cubit.state.items[leas.id]?.name, 'Butter');
    });
  });
}

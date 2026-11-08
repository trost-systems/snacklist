import 'dart:async';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/list/entry.dart';
import 'package:family_groceries/list/list_cache.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/model.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_repository.dart';
import 'memory_cache.dart';

class _Tracked() implements Analytics {
  final events = <(String, Map<String, Object>)>[];

  @override
  void track(String event, [Map<String, Object> properties = const {}]) =>
      events.add((event, properties));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _weekly = HouseholdList(id: 'weekly', name: 'Wocheneinkauf', position: 0);
const _diy = HouseholdList(id: 'diy', name: 'Baumarkt', position: 1);
const _party = HouseholdList(id: 'party', name: 'Sommerfest', position: 2);

/// Job 169b K and L: several lists per household, and "Ich bringe" claims.
void main() {
  late FakeRepository repo;
  late MemoryListCache cache;
  late _Tracked tracked;
  late ListCubit cubit;

  Future<void> settle() => pumpEventQueue();

  ListCubit start() =>
      cubit = ListCubit(repo, cache, userId: 'peter', analytics: tracked)
        ..start();

  List<String> shown() => [
    for (final i in cubit.state.items.values)
      if (i.status == ItemStatus.active) i.name,
  ]..sort();

  List<String> events() => [for (final (e, _) in tracked.events) e];

  setUp(() async {
    tracked = _Tracked();
    cache = MemoryListCache();
    repo = FakeRepository()
      ..lists = const [_weekly, _diy, _party]
      ..remoteAdd('Milch')
      ..remoteAdd('Schrauben', listId: 'diy')
      ..remoteAdd('Kuchen', listId: 'party');
    start();
    await settle();
  });

  tearDown(() => cubit.close());

  group('lists', () {
    test('the first list shows; another shows once picked, and stays '
        'picked on this device', () async {
      expect(cubit.state.shownList?.id, 'weekly');
      expect(shown(), ['Milch']);

      cubit.showList('diy');
      expect(shown(), ['Schrauben']);
      expect(events(), ['list_switched']);
      expect(tracked.events.single.$2, isEmpty, reason: 'never a list name');

      cubit.showList('diy');
      expect(events(), ['list_switched'], reason: 'the shown one again');

      await cubit.close();
      start();
      await settle();
      expect(cubit.state.shownList?.id, 'diy', reason: 'remembered');
      expect(shown(), ['Schrauben']);
    });

    test('a deleted shown list falls back to the first', () async {
      cubit.showList('party');
      repo.lists = const [_weekly, _diy];
      await cubit.resync();
      expect(cubit.state.shownList?.id, 'weekly');
      expect(shown(), ['Milch']);
    });

    test('an add goes to the shown list; the same name may be open on '
        'another list', () async {
      cubit.showList('diy');
      expect(cubit.addEntry(parseEntry('Milch')), isA<Added>());
      await settle();
      final added = repo.rows.values.where((i) => i.name == 'Milch').toList();
      expect({for (final i in added) i.listId}, {'weekly', 'diy'});
      expect(shown(), ['Milch', 'Schrauben']);
      expect(cubit.addEntry(parseEntry('milch')), isA<AlreadyOnList>());
    });

    test('a move to another list made offline shows at once and is sent '
        'once back online', () async {
      final milk = repo.rows.values.firstWhere((i) => i.name == 'Milch');
      repo.online = false;
      cubit.moveToList(milk.id, 'party');
      expect(shown(), isEmpty, reason: 'gone from the shown list');
      cubit.showList('party');
      expect(shown(), ['Kuchen', 'Milch']);
      await settle();
      expect(repo.rows[milk.id]!.listId, 'weekly', reason: 'not sent yet');
      expect(cubit.state.pending, hasLength(1));

      repo.online = true;
      await cubit.retry();
      await settle();
      expect(repo.rows[milk.id]!.listId, 'party');
      expect(cubit.state.pending, isEmpty);
      expect(shown(), ['Kuchen', 'Milch']);
    });

    test('a move onto a list where the item is open already is refused '
        'and says where', () async {
      repo.remoteAdd('Milch', listId: 'party');
      await cubit.resync();
      final milk = repo.rows.values.firstWhere(
        (i) => i.name == 'Milch' && i.listId == 'weekly',
      );
      final told = <Rejected>[];
      final sub = cubit.rejections.listen(told.add);
      cubit.moveToList(milk.id, 'party');
      await settle();
      expect(cubit.state.pending, isEmpty);
      expect(repo.rows[milk.id]!.listId, 'weekly');
      expect(told.single, isA<OnListAlready>());
      expect((told.single as OnListAlready).listName, 'Sommerfest');
      await sub.cancel();
    });

    test('lists are added, renamed, moved and deleted on the server; the new '
        'list shows', () async {
      final list = await cubit.createList('  Grillen ');
      expect(list?.name, 'Grillen');
      expect(cubit.state.shownList?.id, list!.id);
      expect(events(), ['list_created']);
      expect(repo.lists.map((l) => l.name), [
        'Wocheneinkauf',
        'Baumarkt',
        'Sommerfest',
        'Grillen',
      ]);

      expect(await cubit.renameList('diy', 'Werkzeug'), isTrue);
      expect(await cubit.moveList('party', 0), isTrue);
      expect(cubit.state.catalog.lists.map((l) => l.name), [
        'Sommerfest',
        'Wocheneinkauf',
        'Werkzeug',
        'Grillen',
      ]);
      expect(repo.catalogCalls, contains('moveList(party, 0)'));

      expect(await cubit.deleteList('party'), isTrue);
      expect(
        repo.rows.values.map((i) => i.name),
        isNot(contains('Kuchen')),
        reason: 'its items go with it',
      );
      expect(cubit.state.catalog.lists.map((l) => l.id), [
        'weekly',
        'diy',
        list.id,
      ]);
    });

    test('offline, list changes are refused with a reason', () async {
      repo.online = false;
      await cubit.resync();
      final told = <Rejected>[];
      final sub = cubit.rejections.listen(told.add);
      expect(await cubit.createList('Grillen'), isNull);
      expect(await cubit.renameList('diy', 'Werkzeug'), isFalse);
      await settle();
      expect(told, everyElement(isA<ListsNeedConnection>()));
      expect(told, hasLength(2));
      expect(cubit.state.catalog.lists.map((l) => l.name), [
        'Wocheneinkauf',
        'Baumarkt',
        'Sommerfest',
      ]);
      await sub.cancel();
    });

    test('the last list is not deleted', () async {
      repo.lists = const [_weekly];
      await cubit.resync();
      expect(await cubit.deleteList('weekly'), isFalse);
      expect(repo.catalogCalls, isEmpty);
    });

    test('a device copy from before lists shows its items on the first list '
        'and keeps its queued ops', () async {
      await cubit.close();
      final old = {
        'version': 3,
        'catalog': {
          'categories': const <Object?>[],
          'stores': const <Object?>[],
          'layout': const <Object?>[],
          'members': const <Object?>[],
        },
        'server': [
          {
            'id': 'old-1',
            'name': 'Brot',
            'status': 'active',
            'created_at': '2026-10-01T10:00:00.000Z',
            'updated_at': '2026-10-01T10:00:00.000Z',
          },
        ],
        'pending': [
          {
            'item_id': 'old-2',
            'op': 'add',
            'item': {
              'id': 'old-2',
              'name': 'Eier',
              'status': 'active',
              'created_at': '2026-10-01T10:00:00.000Z',
              'updated_at': '2026-10-01T10:00:00.000Z',
            },
          },
        ],
        'usuals': const <Object?>[],
      };
      cache = MemoryListCache(ListSnapshot.fromJson(old));
      repo.online = false;
      start();
      await settle();
      expect(shown(), ['Brot', 'Eier'], reason: 'one list until lists load');

      repo
        ..online = true
        ..rows['old-1'] = cubit.state.server['old-1']!.copyWith(
          listId: 'weekly',
        );
      await cubit.retry();
      await settle();
      expect(repo.rows['old-2']!.listId, 'weekly', reason: 'sent, first list');
      expect(cubit.state.shownList?.id, 'weekly');
      expect(shown(), ['Brot', 'Eier', 'Milch']);
    });
  });

  group('claims', () {
    Item kuchen() => repo.rows.values.firstWhere((i) => i.name == 'Kuchen');

    test('a claim shows at once, is retried until the server has it, and '
        'can be taken back', () async {
      final id = kuchen().id;
      repo.online = false;
      cubit.claim(id, quantity: ' 2 ');
      expect(cubit.state.claims[id]?.single.quantity, '2');
      expect(events(), ['item_claimed']);
      await settle();
      expect(repo.claims, isEmpty, reason: 'offline');

      repo.online = true;
      await cubit.retry();
      await settle();
      expect(repo.claims[(id, 'peter')]?.quantity, '2');
      expect(cubit.state.pending, isEmpty);
      expect(cubit.state.claims[id]?.single.userId, 'peter');

      cubit.claim(id, quantity: '3');
      expect(events(), ['item_claimed'], reason: 'a new amount is no claim');
      cubit.unclaim(id);
      expect(cubit.state.claims[id], isNull);
      await settle();
      expect(repo.claims, isEmpty);
      expect(cubit.state.claims[id], isNull);
    });

    test('a claim sent twice (lost answer) is one claim', () async {
      final id = kuchen().id;
      repo.loseNextAnswer = true;
      cubit.claim(id);
      await settle();
      await cubit.retry();
      await settle();
      expect(repo.claims.keys, [(id, 'peter')]);
      expect(cubit.state.claims[id], hasLength(1));
    });

    test('ticking ends the claims, as the server does', () async {
      final id = kuchen().id;
      repo.remoteClaim(id, quantity: '1');
      await cubit.resync();
      cubit.claim(id);
      await settle();
      expect(cubit.state.claims[id], hasLength(2));
      cubit.tick(id);
      expect(cubit.state.claims[id], isNull, reason: 'optimistic');
      await settle();
      expect(repo.claims, isEmpty);
      cubit.untick(id);
      await settle();
      expect(cubit.state.claims[id], isNull);
    });

    test('claims of other members come and go over realtime, also during '
        'a resync', () async {
      final id = kuchen().id;
      final claim = repo.remoteClaim(id, quantity: '2');
      repo.emitClaim!(claim);
      expect(cubit.state.claims[id]?.single.userId, 'lea');

      repo.itemsGate = Completer();
      final resync = cubit.resync();
      repo.claims.clear();
      repo.emitClaimDeleted!((id, 'lea'));
      final mia = repo.remoteClaim(id, userId: 'mia');
      repo.emitClaim!(mia);
      repo.itemsGate!.complete();
      await resync;
      expect(cubit.state.claims[id]?.map((c) => c.userId), ['mia']);
    });

    test('a claim from a member who joined after the start reads their '
        'name', () {
      fakeAsync((async) {
        final id = kuchen().id;
        repo.members = [
          ...repo.members,
          const Member(id: 'mia', displayName: 'Mia'),
        ];
        repo.emitClaim!(repo.remoteClaim(id, userId: 'mia'));
        expect(cubit.state.catalog.member('mia'), isNull);
        async.elapse(const Duration(seconds: 1));
        expect(cubit.state.catalog.member('mia')?.displayName, 'Mia');
      });
    });

    test('claims survive a restart offline', () async {
      final id = kuchen().id;
      cubit.claim(id, quantity: '2');
      await settle();
      await cubit.close();
      repo.online = false;
      start();
      await settle();
      expect(cubit.state.claims[id]?.single.quantity, '2');
    });
  });
}

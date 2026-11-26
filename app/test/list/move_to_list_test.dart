import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_repository.dart';
import 'memory_cache.dart';

class _Tracked() implements Analytics {
  final events = <String>[];

  @override
  void track(String event, [Map<String, Object> properties = const {}]) =>
      events.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _weekly = HouseholdList(id: 'weekly', name: 'Wocheneinkauf', position: 0);
const _party = HouseholdList(id: 'party', name: 'Sommerfest', position: 1);

/// Job 169b K and L: the same thing may be open on two lists, but one list
/// holds it once. The device decides that itself, so an offline move onto a
/// list that has it open is refused before anything is queued.
void main() {
  late FakeRepository repo;
  late _Tracked tracked;
  late ListCubit cubit;
  late List<Rejected> told;

  Future<void> settle() => pumpEventQueue();

  Item weeklyMilk() => repo.rows.values.firstWhere(
    (i) => i.name == 'Milch' && i.listId == 'weekly',
  );

  Future<void> start() async {
    tracked = _Tracked();
    cubit = ListCubit(
      repo,
      MemoryListCache(),
      userId: 'peter',
      analytics: tracked,
      grace: Duration.zero,
    )..start();
    await settle();
    told = [];
    final sub = cubit.rejections.listen(told.add);
    addTearDown(sub.cancel);
  }

  setUp(() {
    repo = FakeRepository()
      ..lists = const [_weekly, _party]
      ..remoteAdd('Milch')
      ..remoteAdd('Kuchen', listId: 'party');
  });

  tearDown(() => cubit.close());

  test('offline, a move onto a list where it is open among other items is '
      'refused at once and nothing is queued', () async {
    repo.remoteAdd('Milch', listId: 'party');
    await start();
    repo.online = false;

    cubit.moveToList(weeklyMilk().id, 'party');
    expect(cubit.state.pending, isEmpty);
    await settle();
    expect(told.single, isA<OnListAlready>());
    expect((told.single as OnListAlready).list.id, 'party');
    expect(cubit.state.allItems[weeklyMilk().id]?.listId, 'weekly');
  });

  test('a ticked twin on the other list does not stop an open item', () async {
    repo.remoteAdd('Milch', listId: 'party', status: ItemStatus.bought);
    await start();
    repo.online = false;

    cubit.moveToList(weeklyMilk().id, 'party');
    await settle();
    expect(told, isEmpty);
    expect(cubit.state.pending.single, isA<MoveToList>());
    expect(cubit.state.allItems[weeklyMilk().id]?.listId, 'party');
  });

  test('a ticked item moves onto a list where the same is open', () async {
    final ticked = repo.remoteAdd(
      'Kuchen',
      listId: 'weekly',
      status: ItemStatus.bought,
    );
    await start();

    cubit.moveToList(ticked.id, 'party');
    await settle();
    expect(told, isEmpty);
    expect(cubit.state.pending, isEmpty);
    expect(repo.rows[ticked.id]!.listId, 'party');
  });

  test("a claim next to a partner's is one claim told, however often the "
      'amount changes', () async {
    await start();
    final kuchen = repo.rows.values.firstWhere((i) => i.name == 'Kuchen');
    repo.emitClaim!(repo.remoteClaim(kuchen.id, quantity: '1'));
    await settle();

    cubit
      ..claim(kuchen.id, quantity: '2')
      ..claim(kuchen.id, quantity: '3');
    await settle();
    expect(tracked.events.where((e) => e == 'item_claimed'), hasLength(1));
    expect(
      {for (final c in cubit.state.claims[kuchen.id]!) c.userId},
      {'lea', 'peter'},
    );
  });
}

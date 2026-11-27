// The frozen correctness fixture of hc-tick-untick (job 458): a tick, its
// undo from "Zuletzt verwendet" and a tick again, online and offline across
// a restart. tool/hillclimb/hc-tick-untick/measure.sh counts its failures.
import 'dart:convert';

import 'package:family_groceries/analytics/events.dart';
import 'package:family_groceries/list/entry.dart';
import 'package:family_groceries/list/list_cache.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_repository.dart';
import 'memory_cache.dart';

/// What the device keeps over a restart: the snapshot as its JSON text.
ListSnapshot? restarted(ListSnapshot? saved) => saved == null
    ? null
    : ListSnapshot.fromJson(jsonDecode(saved.encode()) as Map<String, Object?>);

void main() {
  late FakeRepository repo;
  late MemoryListCache cache;
  late DateTime now;
  late List<ListCubit> cubits;
  late List<ListActivity> heard;

  Future<void> settle() => pumpEventQueue();

  ListCubit open() {
    final cubit = ListCubit(
      repo,
      cache,
      userId: repo.me,
      clock: () => now,
      grace: Duration.zero,
    )..start();
    cubits.add(cubit);
    cubit.activity.listen(heard.add);
    return cubit;
  }

  /// The app killed and started again on the same device.
  Future<ListCubit> restart(ListCubit cubit) async {
    await cubit.close();
    cache = MemoryListCache(restarted(cache.saved));
    final next = open();
    await settle();
    return next;
  }

  Future<String> added(ListCubit cubit, String name) async {
    final id = (cubit.addEntry(parseEntry(name)) as Added).item.id;
    await settle();
    return id;
  }

  /// A tap on the row, then the row closes.
  void tap(ListCubit cubit, String id) => cubit
    ..willTick(id)
    ..tick(id);

  List<(String, ItemStatus)> statusSends() => [
    for (final op in repo.sent)
      if (op case SetStatus(:final itemId, :final status)) (itemId, status),
  ];

  int adds() => heard
      .where((a) => a is OwnItemAdded && a.source == AddSource.suggestion)
      .length;

  setUp(() {
    repo = FakeRepository();
    cache = MemoryListCache();
    now = DateTime.utc(2026, 11, 26, 9);
    cubits = [];
    heard = [];
  });

  tearDown(() async {
    for (final cubit in cubits) {
      await cubit.close();
    }
  });

  test('tick, undo, tick again: three writes in order, no add', () async {
    final cubit = open();
    await settle();
    final milk = await added(cubit, 'Milch');
    tap(cubit, milk);
    expect(cubit.state.items[milk]!.status, ItemStatus.bought);
    await settle();
    now = now.add(const Duration(seconds: 20));
    cubit.readd(milk);
    expect(cubit.state.items[milk]!.status, ItemStatus.active);
    expect(cubit.state.items[milk]!.boughtAt, isNull);
    await settle();
    now = now.add(const Duration(seconds: 5));
    tap(cubit, milk);
    await settle();
    expect(statusSends(), [
      (milk, ItemStatus.bought),
      (milk, ItemStatus.active),
      (milk, ItemStatus.bought),
    ]);
    expect(repo.rows[milk]!.status, ItemStatus.bought);
    expect(cubit.state.items[milk]!.status, ItemStatus.bought);
    expect(cubit.state.pending, isEmpty);
    expect(adds(), 0, reason: 'an undo is no add');
    expect(heard.whereType<OwnItemTicked>(), hasLength(2));
  });

  test('a re-add after the undo window is an add', () async {
    final cubit = open();
    await settle();
    final milk = await added(cubit, 'Milch');
    tap(cubit, milk);
    await settle();
    now = now.add(ListCubit.undoWindow + const Duration(seconds: 1));
    cubit.readd(milk);
    await settle();
    expect(repo.rows[milk]!.status, ItemStatus.active);
    expect(adds(), 1);
  });

  test('undo of a tick the server already acknowledged is an undo', () async {
    final cubit = open();
    await settle();
    final milk = await added(cubit, 'Milch');
    // The server's bought_at lags the tap: its clock, not the device's.
    repo.boughtAtDelay = const Duration(seconds: 3);
    tap(cubit, milk);
    await settle();
    expect(cubit.state.pending, isEmpty);
    now = now.add(const Duration(minutes: 9));
    cubit.readd(milk);
    await settle();
    expect(adds(), 0);
    expect(repo.rows[milk]!.status, ItemStatus.active);
  });

  test('offline: tick, undo, tick again, restart, back online', () async {
    var cubit = open();
    await settle();
    final milk = await added(cubit, 'Milch');
    final bread = await added(cubit, 'Brot');
    final eggs = await added(cubit, 'Eier');
    repo.online = false;
    tap(cubit, milk);
    tap(cubit, bread);
    now = now.add(const Duration(seconds: 10));
    cubit.readd(milk);
    now = now.add(const Duration(seconds: 10));
    tap(cubit, milk);
    tap(cubit, eggs);
    cubit.readd(eggs);
    await settle();
    expect(repo.sent.whereType<SetStatus>(), isEmpty);
    cubit = await restart(cubit);
    // The queue came back with the device's copy, folded on top.
    expect(cubit.state.items[milk]!.status, ItemStatus.bought);
    expect(cubit.state.items[bread]!.status, ItemStatus.bought);
    expect(cubit.state.items[eggs]!.status, ItemStatus.active);
    repo.online = true;
    await cubit.retry();
    await settle();
    expect(statusSends(), [
      (milk, ItemStatus.bought),
      (bread, ItemStatus.bought),
      (milk, ItemStatus.active),
      (milk, ItemStatus.bought),
      (eggs, ItemStatus.bought),
      (eggs, ItemStatus.active),
    ]);
    expect(repo.rows[milk]!.status, ItemStatus.bought);
    expect(repo.rows[bread]!.status, ItemStatus.bought);
    expect(repo.rows[eggs]!.status, ItemStatus.active);
    expect(cubit.state.pending, isEmpty);
    expect(adds(), 0);
  });

  test('killed while the row closes: the tick survives a restart', () async {
    var cubit = open();
    await settle();
    final milk = await added(cubit, 'Milch');
    repo.online = false;
    cubit.willTick(milk);
    cubit = await restart(cubit);
    expect(cubit.state.items[milk]!.status, ItemStatus.bought);
    repo.online = true;
    await cubit.retry();
    await settle();
    expect(repo.rows[milk]!.status, ItemStatus.bought);
    expect(cubit.state.pending, isEmpty);
  });

  test('offline undo after a restart is still an undo', () async {
    var cubit = open();
    await settle();
    final milk = await added(cubit, 'Milch');
    repo.online = false;
    tap(cubit, milk);
    await settle();
    cubit = await restart(cubit);
    now = now.add(const Duration(minutes: 2));
    cubit.readd(milk);
    expect(cubit.state.items[milk]!.status, ItemStatus.active);
    repo.online = true;
    await cubit.retry();
    await settle();
    expect(repo.rows[milk]!.status, ItemStatus.active);
    expect(adds(), 0);
  });

  test('a lost answer: the retried tick and undo land once each', () async {
    final cubit = open();
    await settle();
    final milk = await added(cubit, 'Milch');
    repo.loseNextAnswer = true;
    tap(cubit, milk);
    await settle();
    cubit.readd(milk);
    await cubit.retry();
    await settle();
    expect(repo.rows[milk]!.status, ItemStatus.active);
    expect(cubit.state.items[milk]!.status, ItemStatus.active);
    expect(cubit.state.pending, isEmpty);
    expect(statusSends().last, (milk, ItemStatus.active));
    expect(adds(), 0);
  });

  test('a partner ticks the item meanwhile: my undo still wins', () async {
    final cubit = open();
    await settle();
    final milk = await added(cubit, 'Milch');
    repo.online = false;
    tap(cubit, milk);
    cubit.readd(milk);
    await settle();
    final ticked = repo.rows[milk]!.copyWith(
      status: ItemStatus.bought,
      boughtAt: () => now,
      boughtBy: () => 'lea',
    );
    repo.rows[milk] = ticked;
    repo.online = true;
    await cubit.retry();
    await settle();
    expect(repo.rows[milk]!.status, ItemStatus.active);
    expect(cubit.state.items[milk]!.status, ItemStatus.active);
    expect(cubit.state.pending, isEmpty);
  });
}

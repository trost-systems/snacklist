import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:family_groceries/app/network.dart';
import 'package:family_groceries/list/entry.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_repository.dart';
import 'package:family_groceries/list/list_view/sections.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_repository.dart';
import 'memory_cache.dart';

void main() {
  late FakeRepository repo;
  late ListCubit cubit;
  late MemoryListCache cache;

  Future<void> settle() => pumpEventQueue();

  /// Lets [time] pass, then lets the cubit finish what its timers started.
  /// Timers that come due together run back to back before any microtask,
  /// so a stalled box would otherwise resume the test mid-reload.
  Future<void> elapse(Duration time) async {
    // ast-grep-ignore: no-wall-time-wait-in-tests -- settle drains it
    await Future<void>.delayed(time);
    await settle();
  }

  List<String> activeNames() => [
    for (final i in cubit.state.items.values)
      if (i.status == ItemStatus.active) i.name,
  ];

  setUp(() async {
    repo = FakeRepository();
    cache = MemoryListCache();
    cubit = ListCubit(repo, cache, userId: 'peter')..start();
    await settle();
  });

  tearDown(() => cubit.close());

  test('an add shows at once, then takes the server category', () async {
    repo.gate = Completer();
    final result = cubit.addEntry(parseEntry('2 Vollmilch'));
    expect(result, isA<Added>());
    final id = (result as Added).item.id;
    expect(cubit.state.items[id]!.categoryId, isNull);
    expect(cubit.state.items[id]!.quantity, '2');

    repo.gate!.complete();
    await settle();
    expect(cubit.state.items[id]!.categoryId, 'chilled');
    expect(cubit.state.pending, isEmpty);
  });

  test('duplicates of active items are refused, case-insensitively', () async {
    cubit.addEntry(parseEntry('Butter'));
    await settle();
    expect(cubit.addEntry(parseEntry('butter')), isA<AlreadyOnList>());
    expect(cubit.addEntry(parseEntry('   ')), isA<NothingToAdd>());
    expect(activeNames(), ['Butter']);
  });

  test('the same name, brand and details is a duplicate, details in any '
      'order', () async {
    cubit.addParsed(
      const ParsedEntry(
        name: 'Windeln',
        brand: 'Pampers',
        properties: 'Größe 3, sensitiv',
      ),
    );
    await settle();
    expect(
      cubit.addParsed(
        const ParsedEntry(
          name: 'windeln',
          brand: 'pampers',
          properties: 'sensitiv,  größe 3',
        ),
      ),
      isA<AlreadyOnList>(),
    );
    expect(
      cubit.addParsed(
        const ParsedEntry(
          name: 'Windeln',
          brand: 'Pampers',
          properties: 'Größe 4',
        ),
      ),
      isA<Added>(),
      reason: 'other details are another item',
    );
  });

  test('tick and undo round-trip through the server', () async {
    final id = (cubit.addEntry(parseEntry('Brot')) as Added).item.id;
    await settle();
    cubit.tick(id);
    expect(activeNames(), isEmpty, reason: 'optimistic');
    await settle();
    expect(repo.rows[id]!.status, ItemStatus.bought);
    cubit.untick(id);
    await settle();
    expect(repo.rows[id]!.status, ItemStatus.active);
    expect(activeNames(), ['Brot']);
  });

  test('an add typed offline and renamed before it syncs is split under its '
      'new name (job 111)', () async {
    repo
      ..parsed['Windeln Pampers Größe 3'] = const ParsedEntry(
        name: 'Windeln',
        brand: 'Pampers',
        properties: 'Größe 3',
      )
      ..parsed['Windeln Pampers Größe 4'] = const ParsedEntry(
        name: 'Windeln',
        brand: 'Pampers',
        properties: 'Größe 4',
      )
      ..online = false;
    final added = cubit.addParsed(
      const ParsedEntry(name: 'Windeln Pampers Größe 3', deviceParsed: true),
    );
    final id = (added as Added).item.id;
    cubit.edit(id, const ItemChanges(name: 'Windeln Pampers Größe 4'));
    await settle();

    repo.online = true;
    repo.emitStatus!(ConnectionStatus.online);
    await settle();
    final row = repo.rows[id]!;
    expect(
      (row.name, row.brand, row.properties),
      ('Windeln', 'Pampers', 'Größe 4'),
    );
  });

  test('a rename of an add still queued offline keeps keyBefore and is '
      'marked for the server parse (jobs 104, 111)', () async {
    repo.online = false;
    final id = (cubit.addParsed(
      const ParsedEntry(name: 'Windeln Pampers Größe 3', deviceParsed: true),
    ) as Added).item.id;
    // The add's answer was lost but realtime brought the keyed row: the
    // add is still queued, the item already has its key.
    repo.emitItem!(
      Item(
        id: id,
        name: 'Windeln',
        brand: 'Pampers',
        properties: 'Größe 3',
        status: ItemStatus.active,
        createdAt: DateTime.utc(2026, 11, 5),
        updatedAt: DateTime.utc(2026, 11, 5),
        canonicalKey: 'windel pampers grosse 3',
      ),
    );
    await settle();
    expect(cubit.state.pending.whereType<AddItem>(), hasLength(1));
    cubit.edit(id, const ItemChanges(name: 'Windeln Pampers Größe 4'));
    await settle();
    final edit = cubit.state.pending.whereType<EditItem>().single;
    expect(edit.deviceParsed, isTrue);
    expect(edit.keyBefore, 'windel pampers grosse 3');
  });

  test('a queued offline add renamed onto an open item folds into it once '
      'parsed, neither dropped nor doubled (jobs 104, 111, 114)', () async {
    final rejections = <Rejected>[];
    final sub = cubit.rejections.listen(rejections.add);
    addTearDown(sub.cancel);
    repo
      ..parsed['Windeln Pampers Größe 3'] = const ParsedEntry(
        name: 'Windeln',
        brand: 'Pampers',
        properties: 'Größe 3',
      )
      ..parsed['Windeln Pampers Größe 4'] = const ParsedEntry(
        name: 'Windeln',
        brand: 'Pampers',
        properties: 'Größe 4',
      );
    cubit.addParsed(
      const ParsedEntry(
        name: 'Windeln',
        brand: 'Pampers',
        properties: 'Größe 4',
      ),
    );
    await settle();
    repo.online = false;
    final id = (cubit.addParsed(
      const ParsedEntry(name: 'Windeln Pampers Größe 3', deviceParsed: true),
    ) as Added).item.id;
    cubit.edit(id, const ItemChanges(name: 'Windeln Pampers Größe 4'));
    await settle();

    repo.online = true;
    repo.emitStatus!(ConnectionStatus.online);
    await settle();
    expect(rejections, isEmpty);
    expect(cubit.state.pending, isEmpty);
    expect(
      repo.rows.values.map((i) => (i.name, i.brand, i.properties, i.quantity)),
      [('Windeln', 'Pampers', 'Größe 4', '2')],
    );
  });

  test('a queued offline add renamed onto an open item, then renamed again: '
      'the later name is parsed too (jobs 111, 114)', () async {
    final rejections = <Rejected>[];
    final sub = cubit.rejections.listen(rejections.add);
    addTearDown(sub.cancel);
    for (final size in ['3', '4', '5']) {
      repo.parsed['Windeln Pampers Größe $size'] = ParsedEntry(
        name: 'Windeln',
        brand: 'Pampers',
        properties: 'Größe $size',
      );
    }
    cubit.addParsed(
      const ParsedEntry(
        name: 'Windeln',
        brand: 'Pampers',
        properties: 'Größe 4',
      ),
    );
    await settle();
    repo.online = false;
    final id = (cubit.addParsed(
      const ParsedEntry(name: 'Windeln Pampers Größe 3', deviceParsed: true),
    ) as Added).item.id;
    cubit
      ..edit(id, const ItemChanges(name: 'Windeln Pampers Größe 4'))
      ..edit(id, const ItemChanges(name: 'Windeln Pampers Größe 5'));
    await settle();

    repo.online = true;
    repo.emitStatus!(ConnectionStatus.online);
    await settle();
    expect(rejections, isEmpty);
    expect(cubit.state.pending, isEmpty);
    expect(
      repo.rows.values.map((i) => (i.name, i.brand, i.properties)),
      unorderedEquals([
        ('Windeln', 'Pampers', 'Größe 4'),
        ('Windeln', 'Pampers', 'Größe 5'),
      ]),
    );
  });

  test('offline ops stay visible, queue, and flush on reconnect', () async {
    final id = (cubit.addEntry(parseEntry('Brot')) as Added).item.id;
    await settle();

    repo.online = false;
    cubit
      ..tick(id)
      ..addEntry(parseEntry('Käse'));
    await settle();
    expect(cubit.state.connection, ConnectionStatus.offline);
    expect(cubit.state.pending, hasLength(2));
    expect(activeNames(), ['Käse']);

    repo.online = true;
    repo.emitStatus!(ConnectionStatus.online);
    await settle();
    expect(cubit.state.pending, isEmpty);
    expect(repo.rows[id]!.status, ItemStatus.bought);
    expect(activeNames(), ['Käse']);
  });

  // Job 122, review 1: a send that is slow to answer must not be overtaken.
  // Writes are last-write-wins, so a tick that lands after a later untick
  // would leave the item ticked although the user unticked last.
  test('a later op waits for a slow send, so the last change wins', () {
    fakeAsync((async) {
      final ordered = ListCubit(repo, MemoryListCache(), userId: 'peter')
        ..start();
      async.elapse(Duration.zero);
      final brot = (ordered.addEntry(parseEntry('Brot')) as Added).item.id;
      async.elapse(const Duration(seconds: 1));
      expect(repo.rows[brot]!.status, ItemStatus.active);
      final slow = repo.gate = Completer<void>();
      ordered.tick(brot);
      async.elapse(const Duration(seconds: 16));
      repo.gate = null;
      async.elapse(const Duration(seconds: 30));
      ordered.untick(brot);
      async.elapse(const Duration(seconds: 30));
      expect(
        repo.rows[brot]!.status,
        ItemStatus.active,
        reason: 'still waiting',
      );
      slow.complete();
      async.elapse(const Duration(seconds: 30));
      expect(ordered.state.pending, isEmpty);
      expect(
        repo.rows[brot]!.status,
        ItemStatus.active,
        reason: 'the user unticked last',
      );
      unawaited(ordered.close());
      async.flushMicrotasks();
    });
  });

  test('a rejected op is dropped, reported, and the view resyncs', () async {
    final rejections = <Rejected>[];
    final sub = cubit.rejections.listen(rejections.add);
    repo.reject = true;
    cubit.addEntry(parseEntry('Wein'));
    await settle();
    expect(rejections.single, isA<ItemRejected>());
    expect((rejections.single as ItemRejected).itemName, 'Wein');
    expect(cubit.state.pending, isEmpty);
    expect(activeNames(), isEmpty);
    await sub.cancel();
  });

  test('remote changes and deletes arrive through realtime', () {
    final remote = repo.remoteAdd('Äpfel');
    repo.emitItem!(remote);
    expect(activeNames(), ['Äpfel']);
    repo.emitDelete!(remote.id);
    expect(activeNames(), isEmpty);
    repo.emitDelete!('unknown-id');
  });

  test('resync picks up changes missed while disconnected', () async {
    repo.remoteAdd('Tee');
    await cubit.resync();
    expect(activeNames(), ['Tee']);
  });

  test('overlapping resyncs both land and the list stays online', () async {
    repo.remoteAdd('Tee');
    // The channel subscribes while the opening resync is still in flight.
    repo.emitStatus!(ConnectionStatus.online);
    await cubit.resync();
    await settle();
    expect(cubit.state.connection, ConnectionStatus.online);
    expect(activeNames(), ['Tee']);
  });

  test('a resync that answers after a failed one clears offline', () async {
    repo.emitStatus!(ConnectionStatus.online);
    await settle();
    repo.online = false;
    await cubit.resync();
    expect(cubit.state.connection, ConnectionStatus.offline);
    repo.online = true;
    await cubit.resync();
    expect(cubit.state.connection, ConnectionStatus.online);
  });

  group('a server in trouble (job 161)', () {
    setUp(() async {
      repo.emitStatus!(ConnectionStatus.online);
      await settle();
    });

    test('a send answered with a 5xx again on the retry is failing; the '
        'change stays queued and is not refused', () async {
      final rejections = <Rejected>[];
      final sub = cubit.rejections.listen(rejections.add);
      repo.sendTrouble = true;
      cubit.addEntry(parseEntry('Kaffee'));
      await settle();
      await cubit.retry();
      expect(cubit.state.trouble, SyncTrouble.failing);
      expect(cubit.state.connection, isNot(ConnectionStatus.offline));
      expect(cubit.state.pending, hasLength(1));
      expect(activeNames(), ['Kaffee']);
      expect(rejections, isEmpty);
      await sub.cancel();
    });

    test('a send with no answer is offline, not failing', () async {
      repo.online = false;
      cubit.addEntry(parseEntry('Kaffee'));
      await settle();
      expect(cubit.state.trouble, SyncTrouble.offline);
      expect(cubit.state.failing, isFalse);
    });

    test(
      'a fetch answered with a 5xx again on the retry is failing too',
      () async {
        repo.fetchTrouble = true;
        await cubit.resync();
        await cubit.retry();
        expect(cubit.state.trouble, SyncTrouble.failing);
      },
    );

    test('an acknowledged send clears failing', () async {
      repo.sendTrouble = true;
      cubit.addEntry(parseEntry('Kaffee'));
      await settle();
      await cubit.retry();
      expect(cubit.state.trouble, SyncTrouble.failing);
      repo.sendTrouble = false;
      await cubit.retry();
      expect(cubit.state.pending, isEmpty);
      expect(cubit.state.trouble, isNull);
    });

    test('offline wins over failing', () async {
      expect(
        const ListState(
          connection: ConnectionStatus.offline,
          failing: true,
        ).trouble,
        SyncTrouble.offline,
      );
      repo.sendTrouble = true;
      cubit.addEntry(parseEntry('Kaffee'));
      await settle();
      await cubit.retry();
      expect(cubit.state.trouble, SyncTrouble.failing);
      repo.emitStatus!(ConnectionStatus.offline);
      await settle();
      expect(cubit.state.trouble, SyncTrouble.offline);
    });

    test('retry says whether the list syncs again', () async {
      repo.sendTrouble = true;
      cubit.addEntry(parseEntry('Kaffee'));
      await settle();
      expect(await cubit.retry(), isFalse);
      expect(cubit.state.trouble, SyncTrouble.failing);
      repo.sendTrouble = false;
      expect(await cubit.retry(), isTrue);
      expect(repo.rows.values.map((i) => i.name), contains('Kaffee'));
    });

    test('a server failing every write stays failing across the 3 s '
        'retries, never clear in between', () {
      fakeAsync((async) {
        final looping = ListCubit(repo, MemoryListCache(), userId: 'peter')
          ..start();
        async.elapse(Duration.zero);
        repo
          ..emitStatus!(ConnectionStatus.online)
          ..sendTrouble = true;
        final seen = <bool>[];
        final sub = looping.stream.listen((s) => seen.add(s.failing));
        looping.addEntry(parseEntry('Kaffee'));
        async.elapse(const Duration(seconds: 20));
        expect(seen.skipWhile((f) => !f), everyElement(isTrue));
        expect(seen, contains(true));
        expect(looping.state.pending, hasLength(1));
        repo.sendTrouble = false;
        async.elapse(const Duration(seconds: 4));
        expect(looping.state.trouble, isNull, reason: 'the loop got through');
        unawaited(sub.cancel());
        unawaited(looping.close());
        async.flushMicrotasks();
      });
    });

    group('one failure is no failing server (job 165)', () {
      /// A list cubit under fake time, online, with every state it emits.
      (ListCubit, List<ListState>) online(FakeAsync async) {
        final c = ListCubit(repo, MemoryListCache(), userId: 'peter')..start();
        async.elapse(Duration.zero);
        repo.emitStatus!(ConnectionStatus.online);
        async.elapse(Duration.zero);
        final seen = <ListState>[];
        c.stream.listen(seen.add);
        return (c, seen);
      }

      void close(FakeAsync async, ListCubit c) {
        unawaited(c.close());
        async.flushMicrotasks();
      }

      Iterable<SyncTrouble?> troubles(List<ListState> seen) =>
          seen.map((s) => s.trouble);

      test('a send answered with one 5xx goes through on the 3 s retry and '
          'never shows failing', () {
        fakeAsync((async) {
          final (c, seen) = online(async);
          repo.sendTrouble = true;
          c.addEntry(parseEntry('Kaffee'));
          async.elapse(Duration.zero);
          expect(c.state.pending, hasLength(1), reason: 'the send failed');
          repo.sendTrouble = false;
          async.elapse(const Duration(seconds: 4));
          expect(c.state.pending, isEmpty);
          expect(repo.rows.values.map((i) => i.name), contains('Kaffee'));
          expect(troubles(seen), isNot(contains(SyncTrouble.failing)));
          close(async, c);
        });
      });

      test('a fetch answered with one 5xx goes through on the 3 s retry and '
          'never shows failing', () {
        fakeAsync((async) {
          final (c, seen) = online(async);
          repo.fetchTrouble = true;
          final brot = repo.remoteAdd('Brot').id;
          bool? fetched;
          unawaited(c.resync().then((ok) => fetched = ok));
          async.elapse(Duration.zero);
          expect(fetched, isFalse);
          repo.fetchTrouble = false;
          async.elapse(const Duration(seconds: 4));
          expect(c.state.server.keys, contains(brot), reason: 'refetched');
          expect(c.state.trouble, isNull);
          expect(troubles(seen), isNot(contains(SyncTrouble.failing)));
          close(async, c);
        });
      });

      test('a send failing and the 3 s retry failing too shows failing, '
          'only after the retry', () {
        fakeAsync((async) {
          final (c, _) = online(async);
          repo
            ..sendTrouble = true
            ..fetchTrouble = true;
          c.addEntry(parseEntry('Kaffee'));
          async.elapse(const Duration(milliseconds: 2900));
          expect(c.state.trouble, isNull);
          async.elapse(const Duration(milliseconds: 200));
          expect(c.state.trouble, SyncTrouble.failing);
          close(async, c);
        });
      });

      test('reads that work and writes that all fail end up failing', () {
        fakeAsync((async) {
          final (c, _) = online(async);
          repo.sendTrouble = true;
          c.addEntry(parseEntry('Kaffee'));
          async.elapse(const Duration(seconds: 4));
          expect(c.state.trouble, SyncTrouble.failing);
          expect(c.state.pending, hasLength(1));
          close(async, c);
        });
      });

      test('a fetch and a send failing in the same round are one failure', () {
        fakeAsync((async) {
          final (c, _) = online(async);
          repo
            ..sendTrouble = true
            ..fetchTrouble = true;
          unawaited(c.resync());
          c.addEntry(parseEntry('Kaffee'));
          async.elapse(Duration.zero);
          expect(repo.sent, isEmpty, reason: 'both failed');
          expect(c.state.trouble, isNull);
          async.elapse(const Duration(seconds: 2));
          expect(c.state.trouble, isNull);
          async.elapse(const Duration(seconds: 2));
          expect(c.state.trouble, SyncTrouble.failing, reason: 'retry failed');
          close(async, c);
        });
      });

      test('a send started before the retry that fails after it is no second '
          'failure', () {
        fakeAsync((async) {
          final (c, _) = online(async);
          repo
            ..fetchTrouble = true
            ..sendTrouble = true
            ..gate = Completer();
          unawaited(c.resync());
          c.addEntry(parseEntry('Kaffee'));
          async.elapse(Duration.zero);
          repo.fetchTrouble = false;
          async.elapse(const Duration(seconds: 4));
          expect(c.state.pending, hasLength(1), reason: 'still in flight');
          repo.gate!.complete();
          async.elapse(Duration.zero);
          expect(c.state.trouble, isNull);
          async.elapse(const Duration(seconds: 4));
          expect(c.state.trouble, SyncTrouble.failing);
          close(async, c);
        });
      });

      test('a failure a refused rename got past is forgotten: the next '
          'single 5xx shows nothing', () {
        fakeAsync((async) {
          final (c, seen) = online(async);
          final papier = repo.remoteAdd(
            'Papier',
            quantity: 'Kleinpackung mit vielen Rollen',
          );
          unawaited(c.resync());
          async.elapse(Duration.zero);
          // A copy the list does not show yet: the server refuses the rename.
          repo.remoteAdd(
            'Klopapier',
            quantity: 'Großpackung mit vielen Rollen',
          );
          // The refusal's resync fails once; the 3 s retry folds the rename
          // ("already on the list") and leaves nothing queued, unacked.
          repo.beforeSend = (op) {
            if (op is EditItem) {
              repo
                ..fetchTrouble = true
                ..beforeSend = null;
            }
          };
          c.edit(papier.id, const ItemChanges(name: 'Klopapier'));
          async.elapse(Duration.zero);
          repo.fetchTrouble = false;
          async.elapse(const Duration(seconds: 4));
          expect(c.state.pending, isEmpty);
          repo.sendTrouble = true;
          c.addEntry(parseEntry('Kaffee'));
          async.elapse(Duration.zero);
          expect(c.state.trouble, isNull, reason: 'one 5xx, a new outage');
          repo.sendTrouble = false;
          async.elapse(const Duration(seconds: 4));
          expect(c.state.pending, isEmpty);
          expect(troubles(seen), isNot(contains(SyncTrouble.failing)));
          close(async, c);
        });
      });
    });
  });

  group('the OS network (job 166)', () {
    late StreamController<Network> network;

    /// A list cubit under fake time that follows [network], online, with
    /// every state it emits.
    (ListCubit, List<ListState>) following(FakeAsync async) {
      network = StreamController<Network>();
      final c = ListCubit(
        repo,
        MemoryListCache(),
        userId: 'peter',
        network: network.stream,
      )..start();
      async.elapse(Duration.zero);
      repo.emitStatus!(ConnectionStatus.online);
      network.add(Network.up);
      async.elapse(Duration.zero);
      final seen = <ListState>[];
      c.stream.listen(seen.add);
      return (c, seen);
    }

    /// The device loses its network: nothing reaches the server, and the
    /// channel has not noticed yet.
    void down(FakeAsync async) {
      repo.online = false;
      network.add(Network.down);
      async.elapse(Duration.zero);
    }

    void up(FakeAsync async) {
      repo.online = true;
      network.add(Network.up);
      async.elapse(Duration.zero);
    }

    void close(FakeAsync async, ListCubit c) {
      unawaited(c.close());
      unawaited(network.close());
      async.flushMicrotasks();
    }

    test('down shows offline at once, with no request and no tap', () {
      fakeAsync((async) {
        final (c, _) = following(async);
        final fetches = repo.itemFetches;
        down(async);
        expect(c.state.trouble, SyncTrouble.offline);
        expect(repo.itemFetches, fetches, reason: 'the OS told, not a fetch');
        close(async, c);
      });
    });

    test('back up, it retries once the network held for 1.5 s and clears '
        'offline, before the 3 s retry would', () {
      fakeAsync((async) {
        final (c, _) = following(async);
        down(async);
        c.addEntry(parseEntry('Kaffee'));
        // The 3 s retry fails at 3 s and comes due again at 6 s.
        async.elapse(const Duration(milliseconds: 3500));
        expect(c.state.trouble, SyncTrouble.offline);
        up(async);
        async.elapse(networkSettle - const Duration(milliseconds: 100));
        expect(c.state.trouble, SyncTrouble.offline, reason: 'not settled');
        expect(c.state.pending, hasLength(1));
        async.elapse(const Duration(milliseconds: 200));
        expect(c.state.trouble, isNull);
        expect(c.state.pending, isEmpty, reason: 'the queue was sent');
        expect(repo.rows.values.map((i) => i.name), contains('Kaffee'));
        close(async, c);
      });
    });

    test('a flapping network shows offline once and retries once, after '
        'the last change', () {
      fakeAsync((async) {
        final (c, seen) = following(async);
        down(async);
        // All within the 3 s retry's first wait, which keeps running.
        for (var i = 0; i < 3; i++) {
          async.elapse(const Duration(milliseconds: 150));
          up(async);
          async.elapse(const Duration(milliseconds: 150));
          down(async);
        }
        async.elapse(const Duration(milliseconds: 150));
        up(async);
        final fetches = repo.itemFetches;
        async.elapse(networkSettle - const Duration(milliseconds: 100));
        expect(repo.itemFetches, fetches, reason: 'nothing while it flaps');
        expect(
          seen.map((s) => s.trouble).toList(),
          everyElement(SyncTrouble.offline),
          reason: 'never cleared in between',
        );
        async.elapse(const Duration(milliseconds: 200));
        expect(repo.itemFetches, fetches + 1, reason: 'one retry');
        expect(c.state.trouble, isNull);
        close(async, c);
      });
    });

    test('a channel that dropped meanwhile is subscribed again at once, '
        'not after its backoff', () {
      fakeAsync((async) {
        final (c, _) = following(async);
        down(async);
        repo.emitStatus!(ConnectionStatus.offline);
        // Two failed resubscribes: the next waits 12 s.
        async.elapse(const Duration(seconds: 10));
        final watches = repo.watches;
        up(async);
        async.elapse(networkSettle);
        expect(repo.watches, watches + 1);
        expect(c.state.trouble, SyncTrouble.offline, reason: 'channel not up');
        repo.emitStatus!(ConnectionStatus.online);
        async.elapse(Duration.zero);
        expect(c.state.trouble, isNull);
        close(async, c);
      });
    });

    test('a reconnect while a resubscribe waits on the old channel '
        'subscribes once', () {
      fakeAsync((async) {
        final (c, _) = following(async);
        down(async);
        repo.emitStatus!(ConnectionStatus.offline);
        final closing = Completer<void>();
        repo.unwatchGates.add(closing);
        final watches = repo.watches;
        // The 3 s resubscribe starts and waits for the old channel to close.
        async.elapse(const Duration(seconds: 3));
        up(async);
        async.elapse(networkSettle);
        closing.complete();
        async.elapse(Duration.zero);
        expect(repo.watches - watches, 1, reason: 'one live channel');
        close(async, c);
      });
    });

    test('after a reconnect, a channel that drops again is retried at the '
        'first backoff, not the grown one', () {
      fakeAsync((async) {
        final (c, _) = following(async);
        down(async);
        // Two failed resubscribes, at 3 s and 6 s later: the next waits 12 s.
        repo.emitStatus!(ConnectionStatus.offline);
        async.elapse(const Duration(seconds: 3));
        repo.emitStatus!(ConnectionStatus.offline);
        async.elapse(const Duration(seconds: 6));
        repo.emitStatus!(ConnectionStatus.offline);
        up(async);
        async.elapse(networkSettle);
        final watches = repo.watches;
        repo.emitStatus!(ConnectionStatus.offline);
        async.elapse(const Duration(milliseconds: 6100));
        expect(repo.watches, watches + 1);
        close(async, c);
      });
    });

    test('a closed list follows the network no more', () {
      fakeAsync((async) {
        final (c, _) = following(async);
        down(async);
        up(async);
        unawaited(c.close());
        async.flushMicrotasks();
        final fetches = repo.itemFetches;
        network
          ..add(Network.down)
          ..add(Network.up);
        async.elapse(const Duration(seconds: 10));
        expect(repo.itemFetches, fetches);
        unawaited(network.close());
        async.flushMicrotasks();
      });
    });

    test('up while the server is out of reach still goes offline on the '
        'first failed request', () {
      fakeAsync((async) {
        final (c, _) = following(async);
        repo.online = false;
        c.addEntry(parseEntry('Kaffee'));
        async.elapse(Duration.zero);
        expect(c.state.trouble, SyncTrouble.offline);
        repo.online = true;
        async.elapse(const Duration(seconds: 4));
        expect(c.state.trouble, isNull, reason: 'the 3 s retry got through');
        close(async, c);
      });
    });

    test('up with nothing lost before fetches nothing', () {
      fakeAsync((async) {
        final (c, _) = following(async);
        final fetches = repo.itemFetches;
        up(async);
        async.elapse(const Duration(seconds: 5));
        expect(repo.itemFetches, fetches);
        close(async, c);
      });
    });

    test('a 503 on the reconnect is no failing server yet (job 165)', () {
      fakeAsync((async) {
        final (c, seen) = following(async);
        down(async);
        repo.fetchTrouble = true;
        up(async);
        async.elapse(networkSettle);
        expect(c.state.trouble, isNot(SyncTrouble.failing));
        repo.fetchTrouble = false;
        async.elapse(const Duration(seconds: 4));
        expect(c.state.trouble, isNull);
        expect(
          seen.map((s) => s.trouble),
          isNot(contains(SyncTrouble.failing)),
        );
        close(async, c);
      });
    });
  });

  test('a resync does not claim online while the channel is down', () async {
    repo.emitStatus!(ConnectionStatus.offline);
    await cubit.resync();
    expect(cubit.state.connection, ConnectionStatus.offline);
  });

  test('an add acked during a catalog reload survives the reload', () async {
    repo.catalogGate = Completer();
    final rename = cubit.renameCategory('produce', 'Obst');
    await settle();
    cubit.addEntry(parseEntry('Brot'));
    await settle();
    expect(cubit.state.pending, isEmpty);
    repo.catalogGate!.complete();
    await rename;
    expect(cubit.state.pending, isEmpty);
    expect(activeNames(), ['Brot']);
    expect(cubit.state.catalog.categories.first.name, 'Obst');
  });

  test('a closed channel is subscribed again until it is live', () async {
    final retrying = ListCubit(
      repo,
      cache,
      userId: 'peter',
      resubscribeAfter: const Duration(milliseconds: 10),
    )..start();
    await settle();
    final before = repo.watches;
    repo.emitStatus!(ConnectionStatus.offline);
    await elapse(const Duration(milliseconds: 30));
    expect(repo.watches, before + 1);
    repo.emitStatus!(ConnectionStatus.online);
    await settle();
    expect(retrying.state.connection, ConnectionStatus.online);
    await elapse(const Duration(milliseconds: 50));
    expect(repo.watches, before + 1, reason: 'no more resubscribes once live');
    await retrying.close();
  });

  test('a channel back before the retry is not subscribed again', () async {
    final retrying = ListCubit(
      repo,
      cache,
      userId: 'peter',
      resubscribeAfter: const Duration(milliseconds: 10),
    )..start();
    await settle();
    final before = repo.watches;
    repo
      ..emitStatus!(ConnectionStatus.offline)
      ..emitStatus!(ConnectionStatus.online);
    await elapse(const Duration(milliseconds: 30));
    expect(repo.watches, before);
    expect(retrying.state.connection, ConnectionStatus.online);
    await retrying.close();
  });

  test(
    'a list closed while its old channel closes subscribes no more',
    () async {
      final retrying = ListCubit(
        repo,
        cache,
        userId: 'peter',
        resubscribeAfter: const Duration(milliseconds: 10),
      )..start();
      await settle();
      final before = repo.watches;
      final closing = Completer<void>();
      repo.unwatchGates.add(closing);
      repo.emitStatus!(ConnectionStatus.offline);
      await elapse(const Duration(milliseconds: 30));
      await retrying.close();
      closing.complete();
      await settle();
      expect(repo.watches, before);
    },
  );

  test('due and recent usuals fill ten rows together', () async {
    final now = DateTime.utc(2026, 10, 30, 9);
    repo.usuals = [
      for (var i = 0; i < 3; i++) Usual(name: 'Fällig $i', due: true),
      for (var i = 0; i < 9; i++)
        Usual(
          name: 'Neulich $i',
          due: false,
          lastUsed: now.subtract(Duration(days: i + 1)),
        ),
    ];
    final withUsuals = ListCubit(repo, cache, userId: 'peter', clock: () => now)
      ..start();
    await settle();
    expect(withUsuals.dueUsuals, hasLength(3));
    expect(
      [for (final u in withUsuals.recentUsuals) u.name],
      [for (var i = 0; i < 7; i++) 'Neulich $i'],
    );
    await withUsuals.close();
  });

  test('a renamed store is on the device once the list settles', () {
    fakeAsync((async) {
      final memory = MemoryListCache();
      final renaming = ListCubit(repo, memory, userId: 'peter')..start();
      async.elapse(const Duration(seconds: 1));
      unawaited(renaming.renameStore('dm', 'Rossmann'));
      async.elapse(const Duration(seconds: 1));
      expect([
        for (final s in memory.saved!.catalog.stores) s.name,
      ], contains('Rossmann'));
      unawaited(renaming.close());
      async.flushMicrotasks();
    });
  });

  test('an op is on the device before the server answers it', () async {
    final bread = (cubit.addEntry(parseEntry('Brot')) as Added).item.id;
    await settle();
    repo.gate = Completer();
    cubit.tick(bread);
    await settle();
    expect(cache.saved!.pending.single, isA<SetStatus>());
    repo.gate!.complete();
    await settle();
    expect(cache.saved!.pending, isEmpty);
  });

  test('a delete can be undone with the same id', () async {
    final item = (cubit.addEntry(parseEntry('Milch')) as Added).item;
    await settle();
    final saved = cubit.state.items[item.id]!;
    cubit.delete(item.id);
    await settle();
    expect(repo.rows, isEmpty);
    cubit.restore(saved);
    await settle();
    expect(repo.rows[item.id]!.categoryId, 'chilled');
  });
  group('an add that is already on the list (job 64b)', () {
    // The partner's rows land on the server without realtime, as on a
    // phone whose channel dropped: the answer to the add is all the app
    // hears.
    Item? open(String name) => cubit.state.items.values
        .where((i) => i.name == name && i.status == ItemStatus.active)
        .firstOrNull;

    test('an undone delete whose item the partner added again shows the '
        "partner's item, unchanged", () async {
      final mine = (cubit.addEntry(parseEntry('2 Milch')) as Added).item;
      await settle();
      final saved = cubit.state.items[mine.id]!;
      cubit.delete(mine.id);
      await settle();
      final leas = repo.remoteAdd('Milch', quantity: '1 l');
      cubit.restore(saved);
      await settle();
      expect(open('Milch')?.id, leas.id);
      expect(open('Milch')?.quantity, '1 l');
      expect(cubit.state.pending, isEmpty);
      expect(repo.rows.values.where((i) => i.name == 'Milch'), hasLength(1));
    });

    test('an offline add replayed after the partner added it is the '
        "partner's item, and what was done offline goes to it", () async {
      repo.online = false;
      final butter = (cubit.addEntry(parseEntry('Butter')) as Added).item;
      cubit
        ..edit(butter.id, const ItemChanges(quantity: SetTo('2')))
        ..tick(butter.id);
      final cheese = (cubit.addEntry(parseEntry('Käse')) as Added).item;
      cubit.delete(cheese.id);
      await settle();
      final leasButter = repo.remoteAdd('butter');
      final leasCheese = repo.remoteAdd('Käse');

      repo.online = true;
      repo.emitStatus!(ConnectionStatus.online);
      await settle();
      expect(cubit.state.pending, isEmpty);
      expect(repo.rows.keys, unorderedEquals([leasButter.id, leasCheese.id]));
      expect(repo.rows[leasButter.id]!.status, ItemStatus.bought);
      expect(repo.rows[leasButter.id]!.quantity, '2');
      expect(
        open('Käse')?.id,
        leasCheese.id,
        reason: "deleting my offline copy leaves the partner's Käse",
      );
    });

    test('a retried add whose answer was lost keeps its own item', () async {
      repo.loseNextAnswer = true;
      final id = (cubit.addEntry(parseEntry('Brot')) as Added).item.id;
      await settle();
      repo.emitStatus!(ConnectionStatus.online);
      await elapse(const Duration(seconds: 4));
      expect(open('Brot')?.id, id);
      expect(cubit.state.pending, isEmpty);
    });
  });

  test('adds carry no store; a tick keeps the store an item has', () async {
    final id = (cubit.addEntry(parseEntry('Brot')) as Added).item.id;
    await settle();
    expect(repo.rows[id]!.storeId, isNull);
    repo.remoteAdd('Seife', storeId: 'dm');
    await cubit.resync();
    final soap = cubit.state.items.values.firstWhere((i) => i.name == 'Seife');
    cubit
      ..tick(id)
      ..tick(soap.id);
    await settle();
    expect(repo.rows[id]!.storeId, isNull);
    expect(repo.rows[soap.id]!.storeId, 'dm');
  });

  test('folded stores and the dismissed card survive a restart', () async {
    cubit
      ..toggleFold('dm')
      ..toggleFold('none')
      ..toggleFold('none')
      ..dismissHint();
    await settle();
    expect(cubit.state.prefs.folded, {'dm'});
    final restarted = ListCubit(repo, cache, userId: 'peter')..start();
    await settle();
    expect(restarted.state.prefs.folded, {'dm'});
    expect(restarted.state.prefs.hintDismissed, isTrue);
    await restarted.close();
  });

  group('own stores', () {
    List<String> storeNames() => [
      for (final s in cubit.state.catalog.stores) s.name,
    ];

    test('a new store is created, shown last and returned', () async {
      final store = await cubit.addStore('  Rewe   City ');
      expect(store?.name, 'Rewe City');
      expect(storeNames(), ['dm', 'Lidl', 'Rewe City']);
      expect(
        store!.sortOrder,
        greaterThan(cubit.state.catalog.store('lidl')!.sortOrder),
      );
      await settle();
      expect(repo.catalogCalls, ['addStore(Rewe City)']);
      expect(storeNames(), ['dm', 'Lidl', 'Rewe City']);
    });

    test('a name the household has, in any case, picks that store', () async {
      final store = await cubit.addStore(' LIDL ');
      expect(store?.id, 'lidl');
      expect(repo.catalogCalls, isEmpty);
    });

    test('an empty name makes nothing', () async {
      expect(await cubit.addStore('   '), isNull);
      expect(repo.catalogCalls, isEmpty);
    });

    test('a store someone else just made under another spelling is the one '
        'returned', () async {
      repo.stores = [
        ...repo.stores,
        const Store(id: 'rewe', name: 'REWE', sortOrder: 30),
      ];
      final store = await cubit.addStore('Rewe');
      expect(store?.id, 'rewe');
      await settle();
      expect(storeNames(), ['dm', 'Lidl', 'REWE']);
    });

    test('offline, adding, renaming and deleting a store is refused', () async {
      final rejections = <Rejected>[];
      final sub = cubit.rejections.listen(rejections.add);
      repo.online = false;
      await cubit.resync();
      expect(await cubit.addStore('Rewe'), isNull);
      expect(await cubit.renameStore('dm', 'Rossmann'), isFalse);
      expect(await cubit.deleteStore('dm'), isFalse);
      await settle();
      expect(storeNames(), ['dm', 'Lidl']);
      expect(rejections, [
        isA<StoreNeedsConnection>(),
        isA<StoreNeedsConnection>(),
        isA<StoreNeedsConnection>(),
      ]);
      await sub.cancel();
    });

    test('offline, a store the household has is still picked', () async {
      repo.online = false;
      await cubit.resync();
      expect((await cubit.addStore('dm'))?.id, 'dm');
    });

    test('a rename shows at once; a preset store renamed is no longer its '
        'chain', () async {
      final saved = cubit.renameStore('dm', ' Rossmann ');
      expect(storeNames(), ['Rossmann', 'Lidl']);
      expect(await saved, isTrue);
      expect(repo.catalogCalls, ['renameStore(dm, Rossmann)']);
      expect(cubit.state.catalog.store('dm')?.seedKey, isNull);
    });

    test("renaming onto another store's name is refused and undone", () async {
      final rejections = <Rejected>[];
      final sub = cubit.rejections.listen(rejections.add);
      expect(await cubit.renameStore('dm', 'lidl'), isFalse);
      await settle();
      expect(storeNames(), ['dm', 'Lidl']);
      expect(
        rejections.single,
        isA<StoreNameTaken>().having((r) => r.name, 'name', 'lidl'),
      );
      await sub.cancel();
    });

    test('a deleted store goes, and its items have no store', () async {
      final milk = repo.remoteAdd('Milch', storeId: 'lidl');
      await cubit.resync();
      expect(await cubit.deleteStore('lidl'), isTrue);
      expect(storeNames(), ['dm']);
      expect(cubit.state.items[milk.id]!.storeId, isNull);
    });
  });

  test('a store reorder shows at once and is saved', () async {
    final saved = cubit.reorderStores(['lidl', 'dm']);
    expect([for (final s in cubit.state.catalog.stores) s.id], ['lidl', 'dm']);
    await saved;
    expect(repo.catalogCalls, ['reorderStores(lidl, dm)']);
    expect([for (final s in cubit.state.catalog.stores) s.id], ['lidl', 'dm']);
  });

  test('a dictated add leaves the category to the server', () async {
    await cubit.addSpoken('Milch und Brot');
    await settle();
    expect(
      [for (final op in repo.sent.cast<AddItem>()) op.autoCategory],
      [true, true],
    );
  });

  test('a restored item keeps its place', () async {
    for (final name in ['Äpfel', 'Birnen']) {
      repo.remoteAdd(name, categoryId: 'produce');
    }
    await cubit.resync();
    final apples = cubit.state.items.values.firstWhere(
      (i) => i.name == 'Äpfel',
    );
    cubit.delete(apples.id);
    await settle();
    cubit.restore(apples);
    await settle();
    expect(repo.rows[apples.id]!.sortKey, apples.sortKey);
    expect((repo.sent.last as AddItem).item.sortKey, apples.sortKey);
  });

  List<String> routeOrder() => [
    for (final c in cubit.state.catalog.categories) c.id,
  ];

  test('a reorder shows at once and is saved', () async {
    final saved = cubit.reorderCategories(['chilled', 'produce', 'other']);
    expect(routeOrder(), ['chilled', 'produce', 'other']);
    await saved;
    expect(repo.catalogCalls, ['reorder(chilled, produce, other)']);
    expect(routeOrder(), ['chilled', 'produce', 'other']);
  });

  test('a refused reorder is reported and reverts', () async {
    final rejections = <Rejected>[];
    final sub = cubit.rejections.listen(rejections.add);
    repo.reject = true;
    final saved = cubit.reorderCategories(['chilled', 'produce', 'other']);
    expect(routeOrder(), ['chilled', 'produce', 'other']);
    await saved;
    await settle();
    expect(routeOrder(), ['produce', 'chilled', 'other']);
    expect(rejections.single, isA<CatalogRejected>());
    await sub.cancel();
  });

  test('a store layout change is saved and sorts the store', () async {
    await cubit.setStoreLayout(
      'dm',
      ['produce', 'other', 'chilled'],
      {'chilled'},
    );
    final dm = sectionsOf([
      repo.remoteAdd('Milch', storeId: 'dm'),
      repo.remoteAdd('Äpfel', categoryId: 'produce', storeId: 'dm'),
    ], cubit.state.catalog).first;
    expect([for (final b in dm.blocks) b.category!.id], ['produce', 'chilled']);
    expect(repo.layout.where((r) => r.storeId == 'dm' && r.hidden), [
      isA<StoreCategory>().having((r) => r.categoryId, 'id', 'chilled'),
    ]);
  });

  test('a duplicate category name is reported by name', () async {
    final rejections = <Rejected>[];
    final sub = cubit.rejections.listen(rejections.add);
    expect(await cubit.renameCategory('chilled', ' sonstiges'), isFalse);
    await settle();
    expect(
      rejections.single,
      isA<NameTaken>().having((r) => r.name, 'name', 'sonstiges'),
    );
    expect(cubit.state.catalog.categories[1].name, 'Kühlregal');
    await sub.cancel();
  });

  test('a category may change its own case; a new name is cleaned', () async {
    expect(await cubit.renameCategory('chilled', 'KÜHLREGAL'), isTrue);
    expect(await cubit.createCategory('  Tier   futter '), isTrue);
    expect(repo.catalogCalls, [
      'rename(chilled, KÜHLREGAL)',
      'create(Tier futter)',
    ]);
  });

  test('a deleted category moves its items to the chosen one', () async {
    final id = (cubit.addEntry(parseEntry('Vollmilch')) as Added).item.id;
    await settle();
    await cubit.deleteCategory('chilled', reassignTo: 'produce');
    expect(routeOrder(), ['produce', 'other']);
    expect(cubit.state.items[id]!.categoryId, 'produce');
  });

  test('offline, a store or category reorder is refused, not shown', () async {
    final rejections = <Rejected>[];
    final sub = cubit.rejections.listen(rejections.add);
    repo.online = false;
    await cubit.resync();
    expect(cubit.state.connection, ConnectionStatus.offline);
    await cubit.reorderStores(['lidl', 'dm']);
    await cubit.setStoreLayout('dm', ['chilled', 'other', 'produce'], {});
    await settle();
    expect([for (final s in cubit.state.catalog.stores) s.id], ['dm', 'lidl']);
    expect(repo.catalogCalls, isEmpty);
    expect(rejections, [isA<NeedsConnection>(), isA<NeedsConnection>()]);
    await sub.cancel();
  });

  test('a store reorder that fails on the way is undone', () async {
    final rejections = <Rejected>[];
    final sub = cubit.rejections.listen(rejections.add);
    // The list still thinks it is online; the write is what fails.
    repo.online = false;
    final saved = cubit.reorderStores(['lidl', 'dm']);
    expect([for (final s in cubit.state.catalog.stores) s.id], ['lidl', 'dm']);
    await saved;
    await settle();
    expect([for (final s in cubit.state.catalog.stores) s.id], ['dm', 'lidl']);
    expect(rejections.single, isA<CatalogRejected>());
    await sub.cancel();
  });

  group('across restarts', () {
    // Longer than the cubit's save debounce.
    Future<void> saved() => elapse(const Duration(milliseconds: 400));

    Future<void> restart() async {
      await cubit.close();
      cubit = ListCubit(repo, cache, userId: 'peter')..start();
      await settle();
    }

    test('an offline start shows the cached list and its queued ops', () async {
      final bread = (cubit.addEntry(parseEntry('Brot')) as Added).item.id;
      await settle();
      repo.online = false;
      cubit
        ..tick(bread)
        ..addEntry(parseEntry('Käse'));
      await saved();

      await restart();
      expect(cubit.state.loaded, isTrue);
      expect(cubit.state.connection, ConnectionStatus.offline);
      expect(cubit.state.server.keys, [bread]);
      expect(cubit.state.pending, hasLength(2));
      expect(activeNames(), ['Käse']);
    });

    test('ops queued during an offline start survive the next restart, '
        'then flush on reconnect', () async {
      final bread = (cubit.addEntry(parseEntry('Brot')) as Added).item.id;
      await settle();
      repo.online = false;
      await saved();

      await restart();
      cubit
        ..tick(bread)
        ..addEntry(parseEntry('Eier'));
      // No wait for the debounce: the app may be killed right after a tap.
      await settle();
      await restart();
      expect(cubit.state.pending, hasLength(2));
      expect(activeNames(), ['Eier']);

      repo.online = true;
      repo.emitStatus!(ConnectionStatus.online);
      await settle();
      expect(cubit.state.pending, isEmpty);
      expect(repo.rows[bread]!.status, ItemStatus.bought);
      expect([for (final i in repo.rows.values) i.name], ['Brot', 'Eier']);

      await saved();
      expect(cache.saved!.pending, isEmpty, reason: 'the flush is saved too');
    });
  });

  Future<void> startAgain() async {
    await cubit.close();
    cubit = ListCubit(repo, cache, userId: 'peter')..start();
    await settle();
  }

  group('who added what', () {
    test('rows carry who added them', () async {
      final theirs = repo.remoteAdd('Tee').id;
      final mine = (cubit.addEntry(parseEntry('Brot')) as Added).item.id;
      expect(cubit.state.items[mine]!.addedBy, isNull, reason: 'unconfirmed');
      await cubit.resync();
      expect(cubit.state.items[theirs]!.addedBy, 'lea');
      expect(cubit.state.items[mine]!.addedBy, 'peter');
      expect(cubit.state.catalog.member('lea')?.displayName, 'Lea');
    });

    test('a first start highlights nothing that was already there', () async {
      repo
        ..remoteAdd('Tee')
        ..remoteAdd('Äpfel');
      cache = MemoryListCache();
      await startAgain();
      expect(cubit.fresh, isEmpty);
      expect(cache.seen, isNotNull, reason: 'the baseline is stored');
    });

    test('a later partner add is fresh, an own add never', () async {
      final tea = repo.remoteAdd('Tee').id;
      cubit.addEntry(parseEntry('Brot'));
      await cubit.resync();
      expect(cubit.fresh, {tea});
    });

    test('a live partner insert becomes fresh', () {
      final tea = repo.remoteAdd('Tee');
      repo.emitItem!(tea);
      expect(cubit.fresh, {tea.id});
    });

    test('marking seen clears and survives a restart', () async {
      final tea = repo.remoteAdd('Tee').id;
      final apples = repo.remoteAdd('Äpfel').id;
      await cubit.resync();
      cubit.markSeen({tea});
      expect(cubit.fresh, {apples});
      cubit.markSeen({apples, 'not-fresh'});
      expect(cubit.fresh, isEmpty);
      await settle();

      await startAgain();
      expect(cubit.fresh, isEmpty);
      final later = repo.remoteAdd('Käse').id;
      await cubit.resync();
      expect(cubit.fresh, {later});
    });

    test('a cached list alone sets no baseline', () async {
      repo.remoteAdd('Tee');
      await cubit.resync();
      await elapse(const Duration(milliseconds: 400));
      cache.seen = null;
      repo.online = false;
      await startAgain();
      expect(cubit.state.loaded, isTrue);
      expect(cubit.state.seen, isNull);
      expect(cubit.fresh, isEmpty);

      repo.online = true;
      await cubit.resync();
      expect(cubit.fresh, isEmpty, reason: 'the first resync is the baseline');
    });

    test('an add by an unknown member reloads the catalog', () async {
      repo.members = [
        ...repo.members,
        const Member(id: 'ana', displayName: 'Ana'),
      ];
      repo.emitItem!(repo.remoteAdd('Tee', addedBy: 'ana'));
      expect(cubit.state.catalog.member('ana'), isNull);
      await elapse(const Duration(milliseconds: 300));
      expect(cubit.state.catalog.member('ana')?.displayName, 'Ana');
    });
  });

  group('usuals', () {
    List<String> names(List<Usual> usuals) => [for (final u in usuals) u.name];

    setUp(() async {
      repo.usuals = [
        const Usual(name: 'Milch', quantity: '2', due: true),
        const Usual(name: 'Mehl', due: false),
        const Usual(name: 'Hafer-Milch', due: true),
        const Usual(name: 'Möhren', quantity: '1 kg', due: true),
        const Usual(name: 'Mais', due: false),
        const Usual(name: 'Mango', due: false),
        const Usual(name: 'Müsli', due: false),
        const Usual(name: 'Käse', due: false),
      ];
      await cubit.resync();
      await settle();
    });

    test('suggestions fold, rank whole names first and leave out the list', () {
      expect(names(cubit.suggestionsFor('mi')), ['Milch', 'Hafer-Milch']);
      expect(names(cubit.suggestionsFor(' MILCH')), ['Milch', 'Hafer-Milch']);
      expect(names(cubit.suggestionsFor('moe')), ['Möhren']);
      expect(names(cubit.suggestionsFor('kä')), ['Käse']);
      expect(names(cubit.suggestionsFor('m')), [
        'Milch',
        'Mehl',
        'Möhren',
        'Mais',
        'Mango',
      ]);
      expect(cubit.suggestionsFor(''), isEmpty);

      cubit.addEntry(parseEntry('milch'));
      expect(names(cubit.suggestionsFor('milch')), ['Hafer-Milch']);
    });

    test('due usuals leave out what is on the list', () {
      expect(names(cubit.dueUsuals), ['Milch', 'Hafer-Milch', 'Möhren']);
      cubit.addEntry(parseEntry('Möhren'));
      expect(names(cubit.dueUsuals), ['Milch', 'Hafer-Milch']);
    });

    test('adding a usual takes its quantity', () async {
      final result = cubit.addUsual(cubit.suggestionsFor('möh').single);
      expect(result, isA<Added>());
      await settle();
      final row = repo.rows.values.single;
      expect((row.name, row.quantity), ('Möhren', '1 kg'));
      expect(cubit.addUsual(cubit.state.usuals[3]), isA<AlreadyOnList>());
    });

    test('cached usuals work offline', () async {
      await elapse(const Duration(milliseconds: 400));
      repo.online = false;
      await startAgain();
      expect(cubit.state.connection, ConnectionStatus.offline);
      expect(names(cubit.suggestionsFor('mi')), ['Milch', 'Hafer-Milch']);
      expect(names(cubit.dueUsuals), hasLength(3));
    });

    test('a failed refresh keeps them and the list stays online', () async {
      repo
        ..usualsFail = true
        ..usuals = [];
      await cubit.resync();
      await settle();
      expect(cubit.state.connection, isNot(ConnectionStatus.offline));
      expect(cubit.state.usuals, hasLength(8));
    });

    test('an add made while they load survives the refresh', () async {
      repo.usualsGate = Completer();
      unawaited(cubit.resync());
      await settle();
      final id = (cubit.addEntry(parseEntry('Brot')) as Added).item.id;
      await settle();
      expect(repo.rows, contains(id));
      repo.usualsGate!.complete();
      await settle();
      expect(activeNames(), ['Brot']);
      expect(cubit.state.pending, isEmpty);
    });

    test('they refresh once the list settles after a change', () {
      // Fake time: on a stalled box the real 1.5 s debounce could pass
      // before the first check.
      fakeAsync((async) {
        final settling = ListCubit(repo, MemoryListCache(), userId: 'peter')
          ..start();
        async.elapse(Duration.zero);
        final before = repo.usualsCalls;
        final id = (settling.addEntry(parseEntry('Brot')) as Added).item.id;
        async.elapse(Duration.zero);
        settling.tick(id);
        async.elapse(const Duration(milliseconds: 1499));
        expect(repo.usualsCalls, before, reason: 'not while it settles');
        repo.usuals = [const Usual(name: 'Brot', due: true)];
        async.elapse(const Duration(milliseconds: 2));
        expect(repo.usualsCalls, before + 1);
        expect(names(settling.dueUsuals), ['Brot']);
        unawaited(settling.close());
        async.flushMicrotasks();
      });
    });
  });

  group('duplicate hint (job 32b)', () {
    late List<DedupeHint> hints;
    late StreamSubscription<DedupeHint> listening;

    setUp(() {
      repo.canonical.addAll({'Möhren': 'mohr', 'Karotten': 'mohr'});
      hints = [];
      listening = cubit.hints.listen(hints.add);
    });

    tearDown(() => listening.cancel());

    Future<Item> addMoehren() async {
      final added = cubit.addEntry(const Entry('Möhren', '500 g')) as Added;
      await settle();
      return cubit.state.items[added.item.id]!;
    }

    test('an own add of another spelling is added and hinted once the server '
        'keyed it', () async {
      final moehren = await addMoehren();
      expect(hints, isEmpty);
      repo.gate = Completer();
      final result = cubit.addEntry(const Entry('Karotten', '1 kg'));
      expect(result, isA<Added>(), reason: 'never refused as a duplicate');
      await settle();
      expect(hints, isEmpty, reason: 'the key comes with the acknowledgement');
      repo.gate!.complete();
      await settle();
      expect(activeNames(), ['Möhren', 'Karotten']);
      expect(hints.single.onList.id, moehren.id);
      expect(hints.single.added.name, 'Karotten');
    });

    test("no hint for a partner's add or a restored delete", () async {
      await addMoehren();
      repo.emitItem!(repo.remoteAdd('Karotten'));
      await settle();
      final karotten = cubit.state.items.values.firstWhere(
        (i) => i.name == 'Karotten',
      );
      cubit.delete(karotten.id);
      await settle();
      cubit.restore(karotten);
      await settle();
      expect(activeNames(), ['Möhren', 'Karotten']);
      expect(hints, isEmpty);
    });

    test(
      'a merge and its undo made offline land in order once online',
      () async {
        final moehren = await addMoehren();
        cubit.addEntry(const Entry('Karotten', '1 kg'));
        await settle();
        final karotten = repo.rows.values.firstWhere(
          (i) => i.name == 'Karotten',
        );
        repo.online = false;
        final merge = cubit.merge(hints.single)!;
        expect(merge.result.quantity, '1,5 kg');
        expect(activeNames(), ['Möhren']);
        expect(cubit.state.items[moehren.id]!.quantity, '1,5 kg');
        cubit.unmerge(merge);
        expect(activeNames(), ['Möhren', 'Karotten']);
        expect(cubit.state.items[moehren.id]!.quantity, '500 g');

        repo.online = true;
        await cubit.resync();
        await settle();
        expect(cubit.state.pending, isEmpty);
        expect(repo.rows[moehren.id]!.quantity, '500 g');
        expect(repo.rows[karotten.id]!.quantity, '1 kg');
        expect(repo.rows[karotten.id]!.addedBy, karotten.addedBy);
        expect(repo.sent.whereType<MergeItems>(), hasLength(1));
        expect(repo.sent.whereType<UnmergeItems>(), hasLength(1));
      },
    );

    test('a merge whose answer is lost is retried as the same merge', () async {
      final moehren = await addMoehren();
      cubit.addEntry(const Entry('Karotten', '1 kg'));
      await settle();
      repo.loseNextAnswer = true;
      cubit.merge(hints.single);
      await settle();
      await cubit.resync();
      await settle();
      expect(repo.rows[moehren.id]!.quantity, '1,5 kg');
      expect(repo.merges, hasLength(1));
      expect(repo.sent.whereType<MergeItems>(), hasLength(2));
      expect(activeNames(), ['Möhren']);
    });

    test(
      'merging after an item was ticked is refused; nothing is lost',
      () async {
        final moehren = await addMoehren();
        cubit.addEntry(const Entry('Karotten', '1 kg'));
        await settle();
        final refused = <Rejected>[];
        final sub = cubit.rejections.listen(refused.add);
        addTearDown(sub.cancel);
        cubit.tick(moehren.id);
        await settle();
        expect(cubit.merge(hints.single), isNull);
        await settle();
        expect(refused.single, isA<MergeRefused>());
        expect(repo.sent.whereType<MergeItems>(), isEmpty);
      },
    );

    test('a merge too long for the quantity column is refused', () async {
      repo.canonical.addAll({
        'Klopapier': 'klopapier',
        'Toilettenpapier': 'klopapier',
      });
      cubit.addEntry(const Entry('Klopapier', 'Großpackung mit vielen Rollen'));
      await settle();
      cubit.addEntry(
        const Entry('Toilettenpapier', 'Kleinpackung mit vielen Rollen'),
      );
      await settle();
      final refused = <Rejected>[];
      final sub = cubit.rejections.listen(refused.add);
      addTearDown(sub.cancel);
      expect(cubit.merge(hints.single), isNull);
      await settle();
      expect(refused.single, isA<MergeRefused>());
      expect(activeNames(), ['Klopapier', 'Toilettenpapier']);
    });

    test('pending merges survive a restart', () async {
      await addMoehren();
      cubit.addEntry(const Entry('Karotten', '1 kg'));
      await settle();
      repo.online = false;
      cubit.merge(hints.single);
      await settle();
      await cubit.close();
      cubit = ListCubit(repo, cache, userId: 'peter')..start();
      await settle();
      expect(cubit.state.pending.single, isA<MergeItems>());
      expect(activeNames(), ['Möhren']);
      repo.online = true;
      await cubit.resync();
      await settle();
      expect(repo.rows.values.map((i) => i.quantity), ['1,5 kg']);
    });
  });
  group('a rename onto an open item (job 104)', () {
    late List<Merge> merges;
    late List<Rejected> refused;

    setUp(() {
      repo.canonical.addAll({'Möhren': 'mohr', 'Karotten': 'mohr'});
      merges = [];
      refused = [];
      final subs = [
        cubit.renameMerges.listen(merges.add),
        cubit.rejections.listen(refused.add),
      ];
      addTearDown(() => Future.wait([for (final s in subs) s.cancel()]));
    });

    Future<Item> add(String name, [String? quantity]) async {
      final added = cubit.addEntry(Entry(name, quantity)) as Added;
      await settle();
      return cubit.state.items[added.item.id]!;
    }

    for (final typed in ['Mineralwasser', '  mineralWASSER ']) {
      test('"$typed" folds Apfelsaft into the open Mineralwasser', () async {
        final wasser = await add('Mineralwasser', '6');
        final saft = await add('Apfelsaft', '2');
        cubit.edit(saft.id, ItemChanges(name: typed));
        expect(activeNames(), ['Mineralwasser'], reason: 'at once');
        await settle();
        expect(cubit.state.pending, isEmpty);
        expect(repo.rows.values.map((i) => (i.id, i.name, i.quantity)), [
          (wasser.id, 'Mineralwasser', '8'),
        ]);
        expect(merges.single.result.name, 'Mineralwasser');
        expect(merges.single.result.quantity, '8');
        expect(repo.sent.whereType<EditItem>(), isEmpty);
        expect(refused, isEmpty);
      });
    }

    test(
      'Rückgängig brings the renamed item back under its old name',
      () async {
        final wasser = await add('Mineralwasser', '6');
        final saft = await add('Apfelsaft', '2');
        cubit.edit(saft.id, const ItemChanges(name: 'Mineralwasser'));
        await settle();
        cubit.unmerge(merges.single);
        await settle();
        expect(activeNames(), ['Mineralwasser', 'Apfelsaft']);
        expect(repo.rows[wasser.id]!.quantity, '6');
        expect(repo.rows[saft.id]!.name, 'Apfelsaft');
      },
    );

    test('umlauts folded, "Broetchen" is the open Brötchen', () async {
      final broetchen = await add('Brötchen', '4');
      final saft = await add('Apfelsaft');
      cubit.edit(saft.id, const ItemChanges(name: 'Broetchen'));
      await settle();
      expect(repo.rows.values.map((i) => (i.id, i.name, i.quantity)), [
        (broetchen.id, 'Brötchen', '5'),
      ]);
      expect(merges.single.result.name, 'Brötchen');
    });

    test('a quantity typed in the same edit is added up', () async {
      final wasser = await add('Mineralwasser', '6');
      final saft = await add('Apfelsaft', '2');
      cubit.edit(
        saft.id,
        const ItemChanges(name: 'Mineralwasser', quantity: SetTo('3')),
      );
      await settle();
      expect(repo.rows.values.map((i) => (i.id, i.quantity)), [
        (wasser.id, '9'),
      ]);
    });

    test('its own name in another case is a plain rename', () async {
      final saft = await add('Apfelsaft');
      await add('Mineralwasser');
      cubit.edit(saft.id, const ItemChanges(name: 'APFELSAFT'));
      await settle();
      expect(activeNames(), ['APFELSAFT', 'Mineralwasser']);
      expect(merges, isEmpty);
      expect(refused, isEmpty);
    });

    test('a ticked copy or other details keep it a rename', () async {
      final brot = await add('Brot');
      cubit.tick(brot.id);
      final saft = await add('Apfelsaft');
      final wasser = await add('Mineralwasser');
      cubit
        ..edit(saft.id, const ItemChanges(name: 'Brot'))
        ..edit(wasser.id, const ItemChanges(brand: SetTo('Gerolsteiner')));
      await settle();
      expect(activeNames(), ['Brot', 'Mineralwasser']);
      expect(merges, isEmpty);
    });

    // Addendum 3: only the same name merges. A synonym or a longer name is
    // offered as for an add (DedupeHint), never merged.
    group('a rename to a synonym or a longer name', () {
      late List<DedupeHint> hints;

      setUp(() {
        repo.canonical.addAll({'Semmeln': 'brot', 'Brötchen': 'brot'});
        hints = [];
        final sub = cubit.hints.listen(hints.add);
        addTearDown(sub.cancel);
      });

      List<(String, String)> offered() => [
        for (final h in hints) (h.added.name, h.onList.name),
      ];

      test(
        'is offered once the server keyed the new name, never merged',
        () async {
          await add('Möhren', '500 g');
          final rueben = await add('Rüben', '1 kg');
          repo.gate = Completer();
          cubit.edit(rueben.id, const ItemChanges(name: 'Karotten'));
          await settle();
          expect(hints, isEmpty, reason: 'no key yet');
          repo.gate!.complete();
          await settle();
          expect(activeNames(), ['Möhren', 'Karotten']);
          expect(offered(), [('Karotten', 'Möhren')]);
          expect(merges, isEmpty);
          expect(repo.sent.whereType<MergeItems>(), isEmpty);
        },
      );

      test(
        'also when its new key arrived before the acknowledgement',
        () async {
          await add('Möhren', '500 g');
          final rueben = await add('Rüben', '1 kg');
          repo.gate = Completer();
          cubit.edit(rueben.id, const ItemChanges(name: 'Karotten'));
          await settle();
          repo.emitItem!(
            Item.fromJson({
              ...repo.rows[rueben.id]!.toJson(),
              'name': 'Karotten',
              'canonical_key': 'mohr',
            }),
          );
          await settle();
          repo.gate!.complete();
          await settle();
          expect(activeNames(), ['Möhren', 'Karotten']);
          expect(offered(), [('Karotten', 'Möhren')]);
        },
      );

      test('also when made offline and sent after a restart', () async {
        await add('Möhren', '500 g');
        final rueben = await add('Rüben', '1 kg');
        repo.online = false;
        cubit.edit(rueben.id, const ItemChanges(name: 'Karotten'));
        await settle();
        await cubit.close();
        cubit = ListCubit(repo, cache, userId: 'peter')..start();
        final sub = cubit.hints.listen(hints.add);
        addTearDown(sub.cancel);
        await settle();
        repo.online = true;
        await cubit.resync();
        await settle();
        expect(activeNames(), ['Möhren', 'Karotten']);
        expect(offered(), [('Karotten', 'Möhren')]);
        expect(repo.sent.whereType<MergeItems>(), isEmpty);
      });

      test(
        '"Butter" next to an open "Butter" Kerrygold stays two rows',
        () async {
          final kerrygold = cubit.addParsed(
            const ParsedEntry(name: 'Butter', brand: 'Kerrygold'),
          ) as Added;
          await settle();
          final saft = await add('Apfelsaft');
          cubit.edit(saft.id, const ItemChanges(name: 'Butter'));
          await settle();
          expect(
            [
              for (final i in repo.rows.values)
                if (i.status == ItemStatus.active) (i.name, i.brand),
            ],
            [('Butter', 'Kerrygold'), ('Butter', null)],
          );
          expect(merges, isEmpty);
          expect(repo.sent.whereType<MergeItems>(), isEmpty);
          expect(hints.map((h) => h.onList.id), [kerrygold.item.id]);
        },
      );

      test('an add still queued, then a brand: no merge', () async {
        await add('Brötchen', '4');
        repo.online = false;
        final semmeln = cubit.addEntry(const Entry('Semmeln', null)) as Added;
        cubit.edit(semmeln.item.id, const ItemChanges(brand: SetTo('Kamps')));
        await settle();
        repo.online = true;
        await cubit.resync();
        await settle();
        expect(activeNames(), ['Brötchen', 'Semmeln']);
        expect(repo.sent.whereType<MergeItems>(), isEmpty);
        expect(offered(), [('Semmeln', 'Brötchen')], reason: 'the add');
      });

      test('an add still queued, then renamed to a synonym: offered', () async {
        repo.canonical['Rundstück'] = 'rund';
        await add('Brötchen', '4');
        repo.online = false;
        final added = cubit.addEntry(const Entry('Rundstück', null)) as Added;
        cubit.edit(added.item.id, const ItemChanges(name: 'Semmeln'));
        await settle();
        repo.online = true;
        await cubit.resync();
        await settle();
        expect(activeNames(), ['Brötchen', 'Semmeln']);
        expect(repo.sent.whereType<MergeItems>(), isEmpty);
        expect(offered(), [('Semmeln', 'Brötchen')]);
      });

      test('a change of case beside an older synonym offers nothing', () async {
        await add('Möhren');
        final karotten = await add('Karotten');
        hints.clear();
        cubit.edit(karotten.id, const ItemChanges(name: 'karotten'));
        await settle();
        expect(activeNames(), ['Möhren', 'karotten']);
        expect(hints, isEmpty);
      });
    });

    test(
      'a merged quantity too long is refused with "already on the list"',
      () async {
        await add('Klopapier', 'Großpackung mit vielen Rollen');
        final other = await add('Papier', 'Kleinpackung mit vielen Rollen');
        cubit.edit(other.id, const ItemChanges(name: 'Klopapier'));
        await settle();
        expect(activeNames(), ['Klopapier', 'Papier']);
        expect(refused.single, isA<RenameTaken>());
        expect((refused.single as RenameTaken).name, 'Klopapier');
        expect(repo.sent.whereType<EditItem>(), isEmpty);
      },
    );

    test('a copy only the server has yet: the rename folds into it', () async {
      final saft = await add('Apfelsaft', '2');
      final copy = repo.remoteAdd('Mineralwasser', quantity: '6');
      cubit.edit(saft.id, const ItemChanges(name: 'Mineralwasser'));
      await settle();
      expect(cubit.state.pending, isEmpty);
      expect(repo.rows.values.map((i) => (i.id, i.name, i.quantity)), [
        (copy.id, 'Mineralwasser', '8'),
      ]);
      expect(activeNames(), ['Mineralwasser']);
      expect(merges.single.result.quantity, '8');
      expect(refused, isEmpty);
    });

    test('renamed offline after the partner added it: one item on sync, '
        'with the quantity typed in the same edit', () async {
      final saft = await add('Apfelsaft', '2');
      repo.online = false;
      cubit.edit(
        saft.id,
        const ItemChanges(name: 'mineralwasser', quantity: SetTo('3')),
      );
      await settle();
      final copy = repo.remoteAdd('Mineralwasser', quantity: '6');
      repo.online = true;
      repo.emitStatus!(ConnectionStatus.online);
      await settle();
      expect(cubit.state.pending, isEmpty);
      expect(repo.rows.values.map((i) => (i.id, i.name, i.quantity)), [
        (copy.id, 'Mineralwasser', '9'),
      ]);
      expect(activeNames(), ['Mineralwasser']);
      expect(refused, isEmpty);
    });

    test('the other phone renamed onto that name first, not shown yet: the '
        'rename folds into theirs, and Rückgängig brings it back', () async {
      // One after the other; the fuzz and the e2e race real interleavings.
      final saft = await add('Apfelsaft', '2');
      final leas = repo.remoteAdd('Sprudel', quantity: '6');
      repo.rows[leas.id] = leas.copyWith(name: 'Mineralwasser');
      cubit.edit(saft.id, const ItemChanges(name: 'Mineralwasser'));
      await settle();
      expect(repo.rows.values.map((i) => (i.id, i.name, i.quantity)), [
        (leas.id, 'Mineralwasser', '8'),
      ]);
      cubit.unmerge(merges.single);
      await settle();
      expect(activeNames()..sort(), ['Apfelsaft', 'Mineralwasser']);
      expect(repo.rows[leas.id]!.quantity, '6');
    });

    test('renamed and ticked offline after the partner added it: the tick '
        'goes to their item, as for an add', () async {
      final saft = await add('Apfelsaft', '2');
      repo.online = false;
      cubit
        ..edit(saft.id, const ItemChanges(name: 'Mineralwasser'))
        ..tick(saft.id);
      await settle();
      final copy = repo.remoteAdd('Mineralwasser', quantity: '6');
      repo.online = true;
      repo.emitStatus!(ConnectionStatus.online);
      await settle();
      expect(cubit.state.pending, isEmpty);
      expect(repo.rows.values.map((i) => (i.id, i.quantity, i.status)), [
        (copy.id, '8', ItemStatus.bought),
      ]);
    });

    test("renamed and deleted offline: the partner's item stays", () async {
      final saft = await add('Apfelsaft', '2');
      repo.online = false;
      cubit
        ..edit(saft.id, const ItemChanges(name: 'Mineralwasser'))
        ..delete(saft.id);
      await settle();
      final copy = repo.remoteAdd('Mineralwasser', quantity: '6');
      repo.online = true;
      repo.emitStatus!(ConnectionStatus.online);
      await settle();
      expect(cubit.state.pending, isEmpty);
      expect(activeNames(), ['Mineralwasser']);
      expect(repo.rows.keys, [copy.id]);
      expect(repo.rows[copy.id]!.quantity, '6', reason: 'nothing merged');
      expect(repo.sent.whereType<MergeItems>(), isEmpty);
      expect(merges, isEmpty);
      expect(refused, isEmpty);
    });

    test(
      'the copy ticked before the list showed it: the rename lands',
      () async {
        final saft = await add('Apfelsaft');
        final copy = repo.remoteAdd('Mineralwasser');
        final fetch = repo.itemsGate = Completer();
        cubit.edit(saft.id, const ItemChanges(name: 'Mineralwasser'));
        await settle();
        expect(repo.sent.whereType<EditItem>(), isEmpty, reason: 'refused');
        repo.rows[copy.id] = copy.copyWith(status: ItemStatus.bought);
        repo.itemsGate = null;
        fetch.complete();
        await settle();
        expect(cubit.state.pending, isEmpty);
        expect(repo.rows[saft.id]!.name, 'Mineralwasser');
        expect(activeNames(), ['Mineralwasser']);
        expect(refused, isEmpty);
      },
    );

    test('a refusal the list cannot match to a copy is sent once more, '
        'then "already on the list"', () async {
      // Postgres lowercases letters Dart leaves alone (U+13A0 Ꭰ to ꭰ).
      var refusals = 0;
      repo
        ..remoteAdd('ꭰ')
        ..beforeSend = (op) {
          if (op case EditItem(changes: ItemChanges(name: 'Ꭰ'))) {
            refusals++;
            throw const RejectedOp('already_on_list', nameTaken: true);
          }
        };
      final saft = await add('Apfelsaft');
      final milk = await add('Milch');
      cubit
        ..edit(saft.id, const ItemChanges(name: 'Ꭰ'))
        ..tick(milk.id);
      await settle();
      expect(refusals, 2);
      expect((refused.single as RenameTaken).name, 'Ꭰ');
      expect(cubit.state.pending, isEmpty);
      expect(repo.rows[saft.id]!.name, 'Apfelsaft');
      expect(
        repo.rows[milk.id]!.status,
        ItemStatus.bought,
        reason: 'not stuck',
      );
    });

    test("renamed offline twice: the second name wins, the partner's item "
        'stays as it is', () async {
      final saft = await add('Apfelsaft', '2');
      repo.online = false;
      cubit
        ..edit(
          saft.id,
          const ItemChanges(
            name: 'Mineralwasser',
            quantity: SetTo('3'),
            brand: SetTo('Gerolsteiner'),
            properties: SetTo('still'),
          ),
        )
        ..edit(saft.id, const ItemChanges(name: 'Orangensaft'));
      await settle();
      final shown = cubit.state.items[saft.id]!;
      final copy = repo.remoteAdd(
        'Mineralwasser',
        quantity: '6',
        brand: 'Gerolsteiner',
        properties: 'still',
      );
      // Apfelsaft with that brand is open too: only the combined edit fits.
      final other = repo.remoteAdd(
        'Apfelsaft',
        brand: 'Gerolsteiner',
        properties: 'still',
      );
      repo.online = true;
      repo.emitStatus!(ConnectionStatus.online);
      await settle();
      expect(cubit.state.pending, isEmpty);
      String row(Item i) =>
          '${i.id} ${i.name} ${i.quantity} ${i.brand} ${i.properties}';
      expect(
        repo.rows.values.map(row),
        unorderedEquals([
          '${copy.id} Mineralwasser 6 Gerolsteiner still',
          '${other.id} Apfelsaft null Gerolsteiner still',
          '${saft.id} Orangensaft 3 Gerolsteiner still',
        ]),
      );
      expect(row(cubit.state.items[saft.id]!), row(shown), reason: 'as shown');
      expect(merges, isEmpty);
      expect(refused, isEmpty);
    });

    test('the copy ticked before the merge reached the server: the rename '
        'lands on its own', () async {
      final saft = await add('Apfelsaft', '2');
      final copy = repo.remoteAdd('Mineralwasser', quantity: '6');
      repo.beforeSend = (op) {
        if (op is MergeItems) {
          repo.rows[copy.id] = repo.rows[copy.id]!.copyWith(
            status: ItemStatus.bought,
          );
        }
      };
      cubit.edit(saft.id, const ItemChanges(name: 'Mineralwasser'));
      await settle();
      expect(merges, isEmpty, reason: 'no "merged" for a refused merge');
      repo.beforeSend = null;
      await cubit.resync();
      await settle();
      expect(cubit.state.pending, isEmpty);
      expect(repo.rows[saft.id]!.name, 'Mineralwasser');
      expect(repo.rows[copy.id]!.status, ItemStatus.bought);
      expect(activeNames(), ['Mineralwasser']);
      expect(refused, isEmpty);
    });

    test('the connection lost right after the refusal: the rename stays '
        'shown and folds once back online', () async {
      final saft = await add('Apfelsaft', '2');
      final copy = repo.remoteAdd('Mineralwasser', quantity: '6');
      repo.beforeSend = (op) {
        if (op is EditItem) {
          repo
            ..online = false
            ..beforeSend = null;
          throw const RejectedOp('already_on_list', nameTaken: true);
        }
      };
      cubit.edit(saft.id, const ItemChanges(name: 'Mineralwasser'));
      await settle();
      expect(cubit.state.items[saft.id]!.name, 'Mineralwasser');
      expect(cubit.state.pending, hasLength(1));
      repo.online = true;
      repo.emitStatus!(ConnectionStatus.online);
      await settle();
      expect(cubit.state.pending, isEmpty);
      expect(repo.rows.values.map((i) => (i.id, i.quantity)), [(copy.id, '8')]);
      expect(merges.single.result.quantity, '8');
      expect(refused, isEmpty);
    });

    test('a copy only the server has, too long to merge: "already on the '
        'list", the old name stays', () async {
      final papier = await add('Papier', 'Kleinpackung mit vielen Rollen');
      repo.remoteAdd('Klopapier', quantity: 'Großpackung mit vielen Rollen');
      cubit.edit(papier.id, const ItemChanges(name: 'Klopapier'));
      await settle();
      expect((refused.single as RenameTaken).name, 'Klopapier');
      expect(activeNames()..sort(), ['Klopapier', 'Papier']);
      expect(repo.rows[papier.id]!.name, 'Papier');
    });

    test('made offline, the merge lands once online', () async {
      final wasser = await add('Mineralwasser', '6');
      final saft = await add('Apfelsaft', '2');
      repo.online = false;
      cubit.edit(saft.id, const ItemChanges(name: 'Mineralwasser'));
      await settle();
      expect(activeNames(), ['Mineralwasser']);
      expect(merges, hasLength(1));
      repo.online = true;
      await cubit.resync();
      await settle();
      expect(repo.rows.values.map((i) => (i.id, i.quantity)), [
        (wasser.id, '8'),
      ]);
    });
  });

  group('activity for the rating prompt', () {
    late List<ListActivity> heard;
    late StreamSubscription<ListActivity> listening;

    setUp(() {
      heard = [];
      listening = cubit.activity.listen(heard.add);
    });

    tearDown(() => listening.cancel());

    Future<String> added(String name) async {
      final id = (cubit.addEntry(parseEntry(name)) as Added).item.id;
      await settle();
      return id;
    }

    List<int> trips() => [
      for (final a in heard)
        if (a case TripCompleted(:final ticked)) ticked,
    ];

    test(
      'the tick that empties the list completes a trip of my ticks',
      () async {
        final ids = [
          for (final n in ['Milch', 'Brot', 'Eier']) await added(n),
        ]..forEach(cubit.tick);
        await settle();
        expect(trips(), [3]);
        // Put back from "recently used" (the tick's undo) and ticked off
        // again, twice: still that one trip.
        for (var i = 0; i < 2; i++) {
          cubit
            ..readd(ids.first)
            ..tick(ids.first);
          await settle();
        }
        expect(trips(), [3]);
      },
    );

    test('a list emptied again after the undo window is a new trip', () async {
      var now = DateTime.utc(2026, 11, 6, 9);
      final clocked = ListCubit(
        FakeRepository(),
        MemoryListCache(),
        userId: 'peter',
        clock: () => now,
      )..start();
      addTearDown(clocked.close);
      final done = <int>[];
      final sub = clocked.activity.listen((a) {
        if (a case TripCompleted(:final ticked)) {
          done.add(ticked);
        }
      });
      addTearDown(sub.cancel);
      await settle();
      final milk = (clocked.addEntry(parseEntry('Milch')) as Added).item.id;
      await settle();
      clocked.tick(milk);
      await settle();
      now = now.add(ListCubit.undoWindow + const Duration(minutes: 1));
      final bread = (clocked.addEntry(parseEntry('Brot')) as Added).item.id;
      await settle();
      clocked.tick(bread);
      await settle();
      expect(done, [1, 1]);
    });

    test('no trip when a partner empties the list, and their emptying '
        'starts the count over', () async {
      final milk = await added('Milch');
      final bread = await added('Brot');
      cubit.tick(milk);
      repo.rows.remove(bread);
      repo.emitDelete!(bread);
      await settle();
      expect(trips(), isEmpty);

      final eggs = await added('Eier');
      cubit.tick(eggs);
      await settle();
      expect(trips(), [1]);
    });

    test('an item unticked and ticked again counts once', () async {
      final milk = await added('Milch');
      final bread = await added('Brot');
      cubit
        ..tick(milk)
        ..untick(milk)
        ..tick(milk)
        ..tick(bread);
      await settle();
      expect(trips(), [2]);
    });

    test(
      'my adds and re-adds are told; an undo, a retry and an echo not',
      () async {
        final milk = await added('Milch');
        cubit
          ..addEntry(parseEntry('milch'))
          ..tick(milk)
          ..readd(milk);
        await settle();
        repo.emitItem!(repo.rows[milk]!);
        repo.remoteAdd('Tee');
        await cubit.resync();
        expect(heard.whereType<OwnItemAdded>(), hasLength(1));
      },
    );

    test('a re-add after the undo window is an add', () async {
      var now = DateTime.utc(2026, 11, 6, 9);
      final clocked = ListCubit(
        FakeRepository(),
        MemoryListCache(),
        userId: 'peter',
        clock: () => now,
      )..start();
      addTearDown(clocked.close);
      final adds = <ListActivity>[];
      final sub = clocked.activity.listen(adds.add);
      addTearDown(sub.cancel);
      await settle();
      final id = (clocked.addEntry(parseEntry('Milch')) as Added).item.id;
      await settle();
      clocked.tick(id);
      await settle();
      now = now.add(ListCubit.undoWindow + const Duration(minutes: 1));
      clocked.readd(id);
      await settle();
      expect(adds.whereType<OwnItemAdded>(), hasLength(2));
    });
  });
}

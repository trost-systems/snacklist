import 'dart:async';

import 'package:fake_async/fake_async.dart';
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

  test('a placed item shows between its neighbours at once', () async {
    for (final name in ['Äpfel', 'Birnen', 'Kiwis', 'Trauben']) {
      repo.remoteAdd(name, categoryId: 'produce');
    }
    await cubit.resync();
    String idOf(String name) =>
        cubit.state.items.values.firstWhere((i) => i.name == name).id;
    List<String> produce() => [
      for (final i in sectionsOf(
        cubit.state.items.values,
        cubit.state.catalog,
      ).last.blocks.single.items)
        i.name,
    ];
    expect(produce(), ['Äpfel', 'Birnen', 'Kiwis', 'Trauben']);

    repo.gate = Completer();
    cubit.place(idOf('Trauben'), anchorId: idOf('Birnen'), edge: Edge.before);
    expect(produce(), ['Äpfel', 'Trauben', 'Birnen', 'Kiwis']);
    final place = cubit.state.pending.single as PlaceItem;
    final birnen = cubit.state.items[idOf('Birnen')]!.sortKey!;
    final apples = cubit.state.items[idOf('Äpfel')]!.sortKey!;
    expect(place.sortKey, (apples + birnen) / 2);

    repo.gate!.complete();
    await settle();
    expect(cubit.state.pending, isEmpty);
    expect(produce(), ['Äpfel', 'Trauben', 'Birnen', 'Kiwis']);

    cubit.place(idOf('Äpfel'), anchorId: idOf('Kiwis'), edge: Edge.after);
    await settle();
    expect(produce(), ['Trauben', 'Birnen', 'Kiwis', 'Äpfel']);
  });

  test('placing next to an item of another group takes its group', () async {
    final milk = repo.remoteAdd('Milch', storeId: 'lidl');
    final soap = repo.remoteAdd('Seife', categoryId: 'other', storeId: 'dm');
    await cubit.resync();
    cubit.place(soap.id, anchorId: milk.id, edge: Edge.after);
    final shown = cubit.state.items[soap.id]!;
    expect((shown.categoryId, shown.storeId), ('chilled', 'lidl'));
    expect(shown.sortKey, greaterThan(milk.sortKey!));
    await settle();
    expect(
      (repo.rows[soap.id]!.categoryId, repo.rows[soap.id]!.storeId),
      ('chilled', 'lidl'),
    );
  });

  group('own stores', () {
    List<String> storeNames() => [
      for (final s in cubit.state.catalog.stores) s.name,
    ];

    test('a new store is created, shown last and returned', () async {
      final store = await cubit.addStore('  Rewe   City ');
      expect(store?.name, 'Rewe City');
      expect(storeNames(), ['dm', 'Lidl', 'Rewe City']);
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
    await cubit.renameCategory('chilled', 'Sonstiges');
    await settle();
    expect(rejections.single, isA<NameTaken>());
    expect(cubit.state.catalog.categories[1].name, 'Kühlregal');
    await sub.cancel();
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
}

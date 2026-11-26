// The list CPU bench (job 130, ported in job 451, docs/done/451.md): the
// in-memory list model on a large household, timed bench by bench. Run
// through tool/hillclimb/hc-list-cpu/bench.sh; it prints one
// `HC130_RESULT {...}` line.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:family_groceries/list/list_cache.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_repository.dart';
import 'package:family_groceries/list/list_view/sections.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/list/fake_repository.dart';
import 'fixture.dart';

const _warmup = 5;
const _samples = 21;

/// Saves as the device cache does: the snapshot's JSON, encoded.
final class _EncodingCache(var ListSnapshot? saved, var SeenMark? seen)
    implements ListCache {
  var bytes = 0;

  @override
  Future<ListSnapshot?> load() async => saved;

  @override
  Future<void> save(ListSnapshot snapshot) {
    bytes = snapshot.encode().length;
    saved = snapshot;
    return Future.value();
  }

  @override
  Future<SeenMark?> loadSeen() async => seen;

  @override
  Future<void> saveSeen(SeenMark mark) async => seen = mark;

  @override
  Future<ListPrefs?> loadPrefs() async => null;

  @override
  Future<void> savePrefs(ListPrefs prefs) async {}
}

typedef _Result = ({List<double> ms, Object? work});

Future<_Result> _bench<S>(
  Future<S> Function() setup,
  FutureOr<Object?> Function(S state) run, {
  Future<void> Function(S state)? teardown,

  /// Runs per sample for ops too short to time alone on a shared host; a
  /// sample is the mean of its runs.
  int reps = 1,
}) async {
  final ms = <double>[];
  Object? work;
  for (var i = 0; i < _warmup + _samples; i++) {
    final state = await setup();
    final watch = Stopwatch()..start();
    for (var r = 0; r < reps; r++) {
      final out = run(state);
      work = out is Future ? await out : out;
    }
    watch.stop();
    await teardown?.call(state);
    if (i >= _warmup) {
      ms.add(watch.elapsedMicroseconds / 1000 / reps);
    }
  }
  return (ms: ms, work: work);
}

double _quantile(List<double> values, double q) {
  final sorted = [...values]..sort();
  final rank = (q * sorted.length).ceil().clamp(1, sorted.length);
  return sorted[rank - 1];
}

void main() {
  test('list cpu bench', timeout: const Timeout.factor(40), () async {
    final catalog = fixtureCatalog();
    final items = fixtureItems();
    final usuals = fixtureUsuals();
    final server = {for (final item in items) item.id: item};
    final open = [
      for (final item in items)
        if (item.status == ItemStatus.active) item,
    ];
    final seenUntil = SeenMark(
      until: fixtureNow.subtract(const Duration(days: 60)),
    );
    // 40 queued ops, as after a while offline: ticks, edits, moves, adds.
    final pending = <ItemOp>[
      for (var i = 0; i < 10; i++)
        SetStatus(
          open[(i * 37) % open.length].id,
          ItemStatus.bought,
          fixtureNow,
        ),
      for (var i = 0; i < 10; i++)
        EditItem(
          open[(i * 41 + 5) % open.length].id,
          ItemChanges(quantity: SetTo('${i + 2}')),
        ),
      for (var i = 0; i < 10; i++)
        MoveItem(
          open[(i * 43 + 7) % open.length].id,
          categoryId: 'cat-${i % 23}',
          storeId: 'store-${i % 6}',
        ),
      for (var i = 0; i < 10; i++)
        AddItem(
          Item(
            id: 'pending-add-$i',
            name: 'Neu $i',
            status: ItemStatus.active,
            createdAt: fixtureNow,
            updatedAt: fixtureNow,
          ),
        ),
    ];
    final visible = visibleItems(server, pending);
    final snapshotJson = jsonEncode(
      ListSnapshot(
        catalog: catalog,
        server: items,
        pending: pending,
        usuals: usuals,
      ).toJson(),
    );

    FakeRepository repoWith(Iterable<Item> rows) {
      final repo = FakeRepository()
        ..categories = catalog.categories
        ..stores = catalog.stores
        ..layout = catalog.layout
        ..members = catalog.members
        ..usuals = usuals;
      repo.rows.addAll({for (final row in rows) row.id: row});
      return repo;
    }

    Future<(ListCubit, FakeRepository, _EncodingCache)> loadedCubit() async {
      final repo = repoWith(items);
      final cache = _EncodingCache(
        ListSnapshot(
          catalog: catalog,
          server: items,
          pending: const [],
          usuals: usuals,
        ),
        seenUntil,
      );
      final cubit = ListCubit(
        repo,
        cache,
        userId: 'peter',
        clock: () => fixtureNow,
      )..start();
      await pumpEventQueue();
      repo.emitStatus?.call(ConnectionStatus.online);
      await pumpEventQueue();
      if (cubit.state.server.length != items.length) {
        throw StateError('cubit did not load the fixture');
      }
      return (cubit, repo, cache);
    }

    Future<void> close((ListCubit, FakeRepository, _EncodingCache) s) =>
        s.$1.close();

    Object? screenRead(ListCubit cubit) {
      final shown = cubit.state.items;
      return (
        shownSections(sectionsOf(shown.values, cubit.state.catalog)).length,
        cubit.fresh.length,
      );
    }

    final queries = [
      'm',
      'mi',
      'milch',
      'brot',
      'kase',
      'käse',
      'tomaten',
      'zwieb',
      'mlich',
      'schokolade',
      'bio',
      'frische a',
    ];
    final tickIds = [
      for (var i = 0; i < 30; i++) open[(i * 97 + 3) % open.length].id,
    ];
    final similarOf = [
      for (var i = 0; i < 20; i++) open[(i * 131 + 11) % open.length],
    ];

    final results = <String, _Result>{
      'sections': await _bench(
        reps: 10,
        () async => visible,
        (v) => shownSections(sectionsOf(v.values, catalog)).length,
      ),
      'visible': await _bench(
        reps: 100,
        () async => null,
        (_) => visibleItems(server, pending).length,
      ),
      'walk_sort': await _bench(reps: 10, () async => null, (_) {
        final list = [...open];
        var stops = 0;
        for (final id in [...catalog.stores.map((s) => s.id), null]) {
          stops += walkingOrder(catalog, id).length;
        }
        list.sort(compareWalk);
        return stops + list.length;
      }),
      'suggest': await _bench(() async => null, (_) {
        var n = 0;
        for (final q in queries) {
          n += suggestUsuals(usuals, visible.values, q).length;
        }
        return n;
      }),
      'recent': await _bench(
        reps: 4,
        () async => null,
        (_) =>
            recentlyUsed(visible.values).length +
            dueUsualsOf(usuals, visible.values).length +
            recentUsualsOf(usuals, visible.values, fixtureNow).length +
            seenUntil.fresh(visible.values, 'peter').length,
      ),
      'similar': await _bench(reps: 4, () async => null, (_) {
        var n = 0;
        for (final item in similarOf) {
          n += similarItems(item, visible.values).length;
        }
        return n;
      }),
      'tick_batch': await _bench(
        () async {
          final s = await loadedCubit();
          // The first tick's send never answers: the rest queue behind it.
          s.$2.gate = Completer();
          return s;
        },
        (s) {
          Object? last;
          for (final id in tickIds) {
            s.$1.tick(id);
            last = screenRead(s.$1);
          }
          return (last, s.$1.state.pending.length, s.$3.bytes);
        },
        teardown: close,
      ),
      'sync_batch': await _bench(loadedCubit, (s) {
        final (cubit, repo, _) = s;
        for (var i = 0; i < 250; i++) {
          final row = open[(i * 11) % open.length];
          repo.emitItem!(
            row
                .copyWith(quantity: () => '${i % 9 + 1}')
                .withUpdatedAt(fixtureNow.add(Duration(seconds: i))),
          );
        }
        for (var i = 0; i < 50; i++) {
          repo.emitItem!(
            Item(
              id: 'remote-$i',
              name: 'Neu von Lea $i',
              status: ItemStatus.active,
              categoryId: 'cat-${i % 23}',
              storeId: i.isEven ? null : 'store-${i % 6}',
              sortKey: 1e7 + i,
              createdAt: fixtureNow,
              updatedAt: fixtureNow,
              addedBy: 'lea',
            ),
          );
        }
        for (var i = 0; i < 50; i++) {
          repo.emitDelete!(open[(i * 17 + 1) % open.length].id);
        }
        return (screenRead(cubit), cubit.state.server.length);
      }, teardown: close),
      'resync': await _bench(
        () async {
          final s = await loadedCubit();
          for (var i = 0; i < 100; i++) {
            final row = open[(i * 29) % open.length];
            s.$2.rows[row.id] = row
                .copyWith(name: '${row.name} $i')
                .withUpdatedAt(fixtureNow);
          }
          return s;
        },
        reps: 5,
        (s) async {
          await s.$1.resync();
          return s.$1.state.server.length;
        },
        teardown: close,
      ),
      'cache_save': await _bench(
        () async => null,
        (_) => ListSnapshot(
          catalog: catalog,
          server: [...server.values],
          pending: pending,
          usuals: usuals,
        ).encode().length,
      ),
      'cache_load': await _bench(
        () async => null,
        (_) => ListSnapshot.fromJson(
          jsonDecode(snapshotJson) as Map<String, Object?>,
        ).server.length,
      ),
    };

    final parts = <String, Object?>{
      for (final MapEntry(:key, :value) in results.entries)
        key: {
          'p50_ms': _quantile(value.ms, 0.5),
          'p90_ms': _quantile(value.ms, 0.9),
          'work': '${value.work}',
        },
    };
    final result = {
      'parts': parts,
      'items': {
        'open': openCount,
        'bought': boughtCount,
        'pending_ops': pending.length,
        'usuals': usuals.length,
        'categories': catalog.categories.length,
        'stores': catalog.stores.length,
        'snapshot_bytes': snapshotJson.length,
      },
      'seed': fixtureSeed,
      'samples': {'warmup': _warmup, 'measured': _samples},
    };
    stdout.writeln('HC130_RESULT ${jsonEncode(result)}');
  });
}

extension on Item {
  Item withUpdatedAt(DateTime at) => Item(
    id: id,
    name: name,
    status: status,
    createdAt: createdAt,
    updatedAt: at,
    quantity: quantity,
    brand: brand,
    properties: properties,
    categoryId: categoryId,
    storeId: storeId,
    sortKey: sortKey,
    boughtAt: boughtAt,
    addedBy: addedBy,
    categorizedVia: categorizedVia,
    canonicalKey: canonicalKey,
  );
}

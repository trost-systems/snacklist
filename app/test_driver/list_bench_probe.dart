// hc-list-cpu (job 221): what the list computes and saves per build and per
// tick, without rendering, on the hc-ui-perf household (300 open items,
// 10 stores), in a profile (AOT) build. Prints one JSON line and exits.
// tool/hillclimb/hc-list-cpu/measure.sh builds and runs it.
//
//   LIST_BENCH_FIXTURE  the household as JSON (fake_supabase.py dump)
//   LIST_BENCH_ENCODE   `whole`: the cubit's saves encode the whole snapshot
//                       (jsonEncode(toJson()), as before job 221), for an A/B
//                       in one binary. Otherwise ListSnapshot.encode().
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:family_groceries/list/add_sheet/suggestion.dart';
import 'package:family_groceries/list/list_cache.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_view/sections.dart';
import 'package:family_groceries/list/model.dart';

import '../test/list/fake_repository.dart';

typedef Json = Map<String, Object?>;

Object? sink;

/// Median, min and max µs per call over [batches] batches of [n] calls.
Map<String, Object> bench(
  Object? Function() body, {
  int n = 200,
  int batches = 15,
}) {
  for (var i = 0; i < 3 * n; i++) {
    sink = body();
  }
  final per = <double>[];
  for (var b = 0; b < batches; b++) {
    final watch = Stopwatch()..start();
    for (var i = 0; i < n; i++) {
      sink = body();
    }
    per.add(watch.elapsedMicroseconds / n);
  }
  per.sort();
  double r(double v) => (v * 10).round() / 10;
  return {
    'median_us': r(per[per.length ~/ 2]),
    'min_us': r(per.first),
    'max_us': r(per.last),
    'n': n,
    'batches': batches,
  };
}

final wholeList = Platform.environment['LIST_BENCH_ENCODE'] == 'whole';

/// As the device's cache: the JSON string of every save.
class EncodingCache() implements ListCache {
  var saves = 0;
  var bytes = 0;
  var encodeMicros = 0;
  ListSnapshot? last;

  @override
  Future<ListSnapshot?> load() async => null;

  @override
  Future<void> save(ListSnapshot snapshot) async {
    last = snapshot;
    final watch = Stopwatch()..start();
    bytes =
        (wholeList ? jsonEncode(snapshot.toJson()) : snapshot.encode()).length;
    encodeMicros += watch.elapsedMicroseconds;
    saves++;
  }

  @override
  Future<SeenMark?> loadSeen() async => null;

  @override
  Future<void> saveSeen(SeenMark mark) async {}

  @override
  Future<ListPrefs?> loadPrefs() async => null;

  @override
  Future<void> savePrefs(ListPrefs prefs) async {}
}

Future<void> main() async {
  final path = Platform.environment['LIST_BENCH_FIXTURE']!;
  final fixture = jsonDecode(File(path).readAsStringSync()) as Json;
  List<T> rows<T>(String key, T Function(Json) parse) => [
    for (final row in fixture[key]! as List<Object?>) parse(row! as Json),
  ];
  final catalog = Catalog(
    categories: rows('categories', Category.fromJson),
    stores: rows('stores', Store.fromJson),
    layout: rows('store_category_order', StoreCategory.fromJson),
    lists: rows('lists', HouseholdList.fromJson),
  );
  final items = rows('items', Item.fromJson);
  final usuals = rows('usuals', Usual.fromJson);
  final server = {for (final item in items) item.id: item};
  final at = DateTime.utc(2026, 11, 2, 10);
  final plain = ListState(
    catalog: catalog,
    server: server,
    loaded: true,
    usuals: usuals,
  );
  // 40 of the 300 ticked (they fill "recently used"), 2 ops not acked yet.
  final ticked = ListState(
    catalog: catalog,
    server: {
      for (final (i, item) in items.indexed)
        item.id: i % 8 == 0
            ? item.copyWith(
                status: ItemStatus.bought,
                boughtAt: () => at.add(Duration(seconds: i)),
              )
            : item,
    },
    pending: [
      SetStatus(items[1].id, ItemStatus.bought, at),
      SetStatus(items[2].id, ItemStatus.bought, at),
    ],
    loaded: true,
    usuals: usuals,
  );
  final result = <String, Object>{};
  result['fixture'] = {
    'items': items.length,
    'stores': catalog.stores.length,
    'categories': catalog.categories.length,
  };
  for (final (name, state) in [('plain', plain), ('ticked', ticked)]) {
    final shownItems = state.items;
    result['$name.state.allItems'] = bench(() => state.allItems);
    result['$name.state.items'] = bench(() => state.items);
    result['$name.state.claims'] = bench(() => state.claims);
    result['$name.sectionsOf'] = bench(
      () => shownSections(sectionsOf(shownItems.values, state.catalog)),
    );
    result['$name.recentlyUsed'] = bench(() => recentlyUsed(shownItems.values));
    // What one build of the list works out (_scrollView in
    // shopping_list_view.dart): items twice, sections, recently used,
    // claims.
    result['$name.list_build_derivation'] = bench(() {
      final used = recentlyUsed(state.items.values);
      final shown = shownSections(
        sectionsOf(state.items.values, state.catalog),
      );
      return [used, shown, state.claims];
    });
    // sheetRows per build of the add sheet while text is typed: the keys of
    // what is on the list.
    result['$name.sheet_on_list_keys'] = bench(
      () => {
        for (final item in state.items.values)
          if (item.status == ItemStatus.active)
            Suggestion(
              SuggestionSource.typed,
              ParsedEntry(
                name: item.name,
                brand: item.brand,
                properties: item.properties,
              ),
            ).key,
      },
    );
  }
  final snapshot = ListSnapshot(
    catalog: catalog,
    server: items,
    pending: const [],
    usuals: usuals,
  );
  final encoded = jsonEncode(snapshot.toJson());
  result['snapshot.bytes'] = encoded.length;
  result['snapshot.toJson'] = bench(snapshot.toJson, n: 50);
  result['snapshot.toJson+jsonEncode'] = bench(
    () => jsonEncode(snapshot.toJson()),
    n: 50,
  );
  // The save's text as the device cache makes it now. Warm: nothing changed
  // since the last save. One row: what a tick leaves, one new Item.
  if (snapshot.encode() != encoded) {
    stderr.writeln('list_bench_probe: encode() differs from jsonEncode');
    exit(4);
  }
  result['snapshot.encode.warm'] = bench(snapshot.encode, n: 50);
  var flip = 0;
  result['snapshot.encode.one_row'] = bench(() {
    final at = flip++ % items.length;
    return ListSnapshot(
      catalog: catalog,
      server: [
        for (final (i, item) in items.indexed)
          if (i == at) item.copyWith(status: ItemStatus.bought) else item,
      ],
      pending: [SetStatus(items[at].id, ItemStatus.bought, DateTime.utc(2026))],
      usuals: usuals,
    ).encode();
  }, n: 50);
  result['snapshot.jsonDecode+fromJson'] = bench(
    () => ListSnapshot.fromJson(jsonDecode(encoded) as Json),
    n: 50,
  );

  // Cubit level: the real ListCubit over an in-memory server, one tick.
  final repo = FakeRepository()
    ..categories = catalog.categories
    ..stores = catalog.stores
    ..layout = catalog.layout
    ..lists = catalog.lists
    ..usuals = usuals;
  repo.rows.addAll(server);
  final cache = EncodingCache();
  final cubit = ListCubit(repo, cache, userId: repo.me)..start();
  final loaded = Stopwatch()..start();
  while (!(cubit.state.loaded && cubit.state.resynced)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    if (loaded.elapsed > const Duration(seconds: 10)) {
      stderr.writeln('list_bench_probe: the cubit never loaded');
      exit(3);
    }
  }
  final open = [
    for (final item in cubit.state.items.values)
      if (item.status == ItemStatus.active) item.id,
  ];
  // Each call: tick (the optimistic op, its emit, the save's text), then the
  // untick, so the list stays as it was. The server's answers are awaited
  // outside the timed part.
  final sync = <double>[];
  final settle = <double>[];
  var emits = 0;
  final count = cubit.stream.listen((_) => emits++);
  for (var round = 0; round < 60; round++) {
    final id = open[round % open.length];
    final watch = Stopwatch()..start();
    cubit.tick(id);
    final tickSync = watch.elapsedMicroseconds;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    watch
      ..reset()
      ..start();
    cubit.untick(id);
    final untickSync = watch.elapsedMicroseconds;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    if (round >= 20) {
      sync.add(tickSync.toDouble());
      settle.add(untickSync.toDouble());
    }
  }
  await Future<void>.delayed(const Duration(milliseconds: 500));
  await count.cancel();
  sync.sort();
  settle.sort();
  result['cubit.tick_sync'] = {
    'median_us': sync[sync.length ~/ 2],
    'min_us': sync.first,
    'max_us': sync.last,
    'n': sync.length,
  };
  result['cubit.untick_sync'] = {
    'median_us': settle[settle.length ~/ 2],
    'min_us': settle.first,
    'max_us': settle.last,
    'n': settle.length,
  };
  result['cubit.encode'] = wholeList ? 'whole' : 'rows';
  result['cubit.saves'] = cache.saves;
  result['cubit.emits'] = emits;
  result['cubit.sent_ops'] = repo.sent.length;
  result['cubit.save_bytes'] = cache.bytes;
  result['cubit.encode_us_per_save'] = cache.saves == 0
      ? 0
      : cache.encodeMicros ~/ cache.saves;
  // Cold: every row new, as the first save after a load. Last, because its
  // 270,000 short-lived items would be in the cubit's numbers otherwise.
  result['snapshot.encode.cold'] = bench(
    () => ListSnapshot(
      catalog: catalog,
      server: [for (final item in items) item.copyWith()],
      pending: const [],
      usuals: usuals,
    ).encode(),
    n: 50,
  );
  stdout.writeln(jsonEncode(result));
  await stdout.flush();
  exit(0);
}

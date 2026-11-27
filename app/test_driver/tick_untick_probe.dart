// hc-tick-untick (job 458): what a tick and its undo cost on the UI isolate,
// without rendering, in a profile (AOT) build: the real ListCubit over an
// in-memory server, the hc-ui-perf household (300 items, 10 stores) and the
// same household ten times over (3000 items). Prints one JSON line and exits.
// tool/hillclimb/hc-tick-untick/measure.sh builds and runs it.
//
//   LIST_BENCH_FIXTURE  the household as JSON (fake_supabase.py dump)
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:family_groceries/list/list_cache.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/model.dart';

import '../test/list/fake_repository.dart';

typedef Json = Map<String, Object?>;

/// The device cache's work in the same turn as the save: the snapshot's
/// text (the device cache makes it in a later turn; it is UI-isolate time
/// either way).
class EncodingCache() implements ListCache {
  var saves = 0;
  var bytes = 0;
  var encodeMicros = 0;

  @override
  Future<ListSnapshot?> load() async => null;

  @override
  Future<void> save(ListSnapshot snapshot) async {
    final watch = Stopwatch()..start();
    bytes = snapshot.encode().length;
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

Map<String, Object> stats(List<double> samples) {
  final sorted = [...samples]..sort();
  double r(double v) => (v * 10).round() / 10;
  return {
    'p50_us': r(sorted[sorted.length ~/ 2]),
    'p90_us': r(sorted[(sorted.length * 9) ~/ 10]),
    'min_us': r(sorted.first),
    'n': sorted.length,
  };
}

Future<void> idle() => Future<void>.delayed(const Duration(milliseconds: 8));

/// [copies] of the household's items, every eighth one bought (they fill
/// "Zuletzt verwendet").
Future<Json> measure(
  Catalog catalog,
  List<Item> items,
  List<Usual> usuals, {
  required int copies,
  required int rounds,
}) async {
  final at = DateTime.utc(2026, 11, 1, 10);
  final repo = FakeRepository()
    ..categories = catalog.categories
    ..stores = catalog.stores
    ..layout = catalog.layout
    ..lists = catalog.lists
    ..usuals = usuals;
  var n = 0;
  for (var copy = 0; copy < copies; copy++) {
    for (final item in items) {
      final i = n++;
      final copied = copy == 0
          ? item
          : Item.fromJson({
              ...item.toJson(),
              'id': '${item.id}-$copy',
              'name': '${item.name} $copy',
            });
      final row = copied.copyWith(
        status: i % 8 == 0 ? ItemStatus.bought : null,
        boughtAt: i % 8 == 0 ? () => at.subtract(Duration(minutes: i)) : null,
      );
      repo.rows[row.id] = row;
    }
  }
  var now = DateTime.utc(2026, 11, 26, 10);
  final cache = EncodingCache();
  final cubit = ListCubit(repo, cache, userId: repo.me, clock: () => now)
    ..start();
  final loaded = Stopwatch()..start();
  while (!(cubit.state.loaded && cubit.state.resynced)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    if (loaded.elapsed > const Duration(seconds: 20)) {
      stderr.writeln('tick_untick_probe: the cubit never loaded');
      exit(3);
    }
  }
  final open = [
    for (final item in cubit.state.items.values)
      if (item.status == ItemStatus.active) item.id,
  ];
  final tick = <double>[];
  final undo = <double>[];
  final offlineTick = <double>[];
  final offlineUndo = <double>[];
  final tickEncode = <double>[];
  final undoEncode = <double>[];
  var errors = 0;
  final watch = Stopwatch();
  var encoded = 0.0;
  double timed(void Function() body) {
    final before = cache.encodeMicros;
    watch
      ..reset()
      ..start();
    body();
    encoded = (cache.encodeMicros - before).toDouble();
    return watch.elapsedMicroseconds.toDouble();
  }

  // One round: a tap ticks (willTick at the tap, tick once the row has
  // closed), the undo from "Zuletzt verwendet" puts it back. The server
  // answers in between, outside the timed part.
  Future<void> round(
    int r,
    List<double> ticks,
    List<double> undos, [
    List<double>? encodes,
    List<double>? undoEncodes,
  ]) async {
    final id = open[r % open.length];
    now = now.add(const Duration(seconds: 7));
    final t = timed(
      () => cubit
        ..willTick(id)
        ..tick(id),
    );
    encodes?.add(encoded);
    if (cubit.state.allItems[id]?.status != ItemStatus.bought) {
      errors++;
    }
    await idle();
    now = now.add(const Duration(seconds: 3));
    final u = timed(() => cubit.readd(id));
    undoEncodes?.add(encoded);
    if (cubit.state.allItems[id]?.status != ItemStatus.active) {
      errors++;
    }
    await idle();
    ticks.add(t);
    undos.add(u);
  }

  const warmup = 20;
  for (var r = 0; r < warmup + rounds; r++) {
    final kept = r >= warmup;
    await round(
      r,
      kept ? tick : [],
      kept ? undo : [],
      kept ? tickEncode : null,
      kept ? undoEncode : null,
    );
  }
  // In a shop without signal: the queue grows with every tap.
  repo.online = false;
  await cubit.retry();
  for (var r = 0; r < rounds; r++) {
    await round(r + 1, offlineTick, offlineUndo);
  }
  final queued = cubit.state.pending.length;
  repo.online = true;
  await cubit.retry();
  await idle();
  final drained = cubit.state.pending.isEmpty;
  for (final id in open) {
    if (repo.rows[id]?.status != ItemStatus.active ||
        cubit.state.allItems[id]?.status != ItemStatus.active) {
      errors++;
    }
  }
  await cubit.close();
  return {
    'items': repo.rows.length,
    'tick': stats(tick),
    'undo': stats(undo),
    'tick_encode': stats(tickEncode),
    'undo_encode': stats(undoEncode),
    'offline_tick': stats(offlineTick),
    'offline_undo': stats(offlineUndo),
    'offline_queued': queued,
    'drained': drained,
    'errors': errors + (drained ? 0 : 1),
    'saves': cache.saves,
    'save_bytes': cache.bytes,
  };
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
  final result = <String, Object>{
    'n300': await measure(catalog, items, usuals, copies: 1, rounds: 60),
    'n3000': await measure(catalog, items, usuals, copies: 10, rounds: 60),
  };
  stdout.writeln(jsonEncode(result));
  await stdout.flush();
  exit(0);
}

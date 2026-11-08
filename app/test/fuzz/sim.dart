import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_repository.dart';
import 'package:family_groceries/list/model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../list/memory_cache.dart';
import 'fake_backend.dart';

enum Act(final int weight) {
  net(8),
  restart(2),
  add(14),
  tick(12),
  untick(5),
  readd(4),
  rename(6),
  quantity(6),
  brand(3),
  moveStore(6),
  moveCategory(5),
  delete(8),
  restore(4),
  merge(4),
  unmerge(2),
}

/// One user or network event: after [delayMs], on device [client]. [a] picks
/// the item (an index into what the device shows), [b] the value.
final class const Step(
  final int delayMs,
  final int client,
  final Act act,
  final int a,
  final int b,
) {
  @override
  String toString() => '+${delayMs}ms c$client ${act.name}($a, $b)';
}

const names = [
  'Milch',
  'Brot',
  'Äpfel',
  'Karotten',
  'Möhren',
  'Butter',
  'Brötchen',
  'Semmeln',
  'Joghurt',
  'Käse',
  'Eier',
  'Nudeln',
];
const quantities = [null, '2', '1 l', '500 g', '3 Stück'];
const brands = [null, 'Weihenstephan', 'Ja!', 'Bio'];
const storeIds = [null, 'dm', 'lidl'];
const categoryIds = ['produce', 'chilled', 'bakery', 'other'];

/// The steps for [seed]; they depend on nothing but the seed, so a subset of
/// them is a smaller scenario (for shrinking).
List<Step> scenario(int seed, {int clients = 3, int steps = 60}) {
  final rng = Random(seed);
  final total = Act.values.fold(0, (sum, a) => sum + a.weight);
  Act pick() {
    var n = rng.nextInt(total);
    for (final act in Act.values) {
      if ((n -= act.weight) < 0) {
        return act;
      }
    }
    throw StateError('unreachable');
  }

  int delay() => switch (rng.nextInt(10)) {
    < 4 => rng.nextInt(200),
    < 8 => 200 + rng.nextInt(1800),
    _ => 2000 + rng.nextInt(6000),
  };

  return [
    for (var i = 0; i < steps; i++)
      Step(
        delay(),
        rng.nextInt(clients),
        pick(),
        rng.nextInt(1000),
        rng.nextInt(1000),
      ),
  ];
}

final class const RunResult(
  final List<String> failures,
  final List<String> trace,
) {
  bool get failed => failures.isNotEmpty;
}

/// A deliberately broken device for the harness's own test: it never hears
/// a partner's delete over realtime.
enum Plant() {
  none,
  dropRealtimeDeletes,
}

final _http = [for (var i = 0; i < 3; i++) FakeHttpClient(i)];

/// One SupabaseClient per device slot, made once: each spawns a JSON isolate.
final _clients = [
  for (final http in _http)
    SupabaseClient(
      'http://fuzz.invalid',
      'publishable-fuzz',
      httpClient: http,
      postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    ),
];

/// The app's repository with its realtime channel replaced by the fake's;
/// every other call goes through PostgREST over [FakeHttpClient].
final class SimRepository(final Device device) extends SupabaseListRepository {
  this : super(_clients[device.slot], householdId);

  @override
  Future<Map<String, Item?>> send(ItemOp op) async {
    try {
      final rows = await runZoned(
        () => super.send(op),
        zoneValues: {opZoneKey: op},
      );
      device.acked[op] = rows;
      return rows;
    } on RejectedOp catch (e) {
      device.rejected.add(op);
      if (op is EditItem && e.nameTaken) {
        device.refusedRenames.add(op);
      }
      rethrow;
    }
  }

  @override
  Future<void> Function() watch({
    required void Function(Item item) onItem,
    required void Function(String id, DateTime at) onItemDeleted,
    required void Function(Claim claim) onClaim,
    required void Function(ClaimKey key) onClaimDeleted,
    required void Function() onCatalogChanged,
    required void Function(ConnectionStatus status) onStatus,
  }) {
    final net = device.net;
    final sub = device.backend.subscribe(
      device.slot,
      (row) => onItem(Item.fromJson(row)),
      (id, at) {
        if (device.plant != Plant.dropRealtimeDeletes) {
          onItemDeleted(id, at);
        }
      },
    );
    final channel = (sub: sub, onStatus: onStatus);
    device.channels.add(channel);
    final epoch = net.epoch;
    Timer(Duration(milliseconds: net.latency()), () {
      if (sub.closed) {
        return;
      }
      if (net.up && net.epoch == epoch && device.joinGap) {
        // The join is confirmed before the Postgres listener runs, which
        // announces itself later (DECISIONS 2b.9).
        onStatus(ConnectionStatus.online);
        Timer(Duration(milliseconds: 200 + net.rng.nextInt(2500)), () {
          if (sub.closed) {
            return;
          }
          if (net.up && net.epoch == epoch) {
            sub.live = true;
          } else {
            sub.closed = true;
          }
          onStatus(
            sub.live ? ConnectionStatus.online : ConnectionStatus.offline,
          );
        });
      } else if (net.up && net.epoch == epoch) {
        sub.live = true;
        onStatus(ConnectionStatus.online);
      } else {
        sub.closed = true;
        onStatus(ConnectionStatus.offline);
      }
    });
    return () async {
      sub
        ..live = false
        ..closed = true;
      device.channels.remove(channel);
    };
  }
}

typedef Channel = ({
  Subscription sub,
  void Function(ConnectionStatus status) onStatus,
});

/// One phone: its network, its device cache and the list cubit on it.
final class Device(
  final int slot,
  final FakeBackend backend,
  final Net net,
  final DateTime Function() clock,
  final Plant plant,
  final void Function(String line) log,
  final void Function(String failure) fail, {

  /// Realtime's gap between the join and the Postgres listener.
  final bool joinGap = false,
}) {
  final cache = MemoryListCache();
  final channels = <Channel>[];
  final acked = Map<ItemOp, Map<String, Item?>>.identity();
  final rejected = Set<ItemOp>.identity();

  /// Renames the server refused for an open copy: the list folds them.
  final refusedRenames = Set<EditItem>.identity();
  final _movedOntoCopy = <ItemOp>[];

  /// Each op moved away from an item with a refused rename: the item was
  /// folded into its copy on the server, or deleted before the fold (the
  /// merge then answers that it is gone, and the op went to the copy).
  void checkMoved() {
    final mergedIds = {
      for (final merge in backend.merges.values)
        (merge['merged_row']! as Map)['id'],
    };
    for (final op in _movedOntoCopy) {
      if (!mergedIds.contains(op.itemId) && !backend.wasDeleted(op.itemId)) {
        fail('c$slot lost an op without an answer: ${_describe(op)}');
      }
    }
  }

  /// Ops the user made that have not been acknowledged, refused or folded
  /// away by a documented rule yet.
  final open = Set<ItemOp>.identity();
  late ListCubit cubit;
  StreamSubscription<ListState>? _states;
  StreamSubscription<DedupeHint>? _hints;
  StreamSubscription<Rejected>? _rejections;
  var _seen = const <ItemOp>[];
  DedupeHint? hint;
  Merge? lastMerge;
  final deleted = <Item>[];

  String get user => 'u$slot';

  void start() {
    final cubit = this.cubit = ListCubit(
      SimRepository(this),
      cache,
      userId: user,
      clock: clock,
    );
    _seen = cubit.state.pending;
    _states = cubit.stream.listen(_onState);
    _hints = cubit.hints.listen((h) => hint = h);
    _rejections = cubit.rejections.listen((r) {
      if (r is RenameTaken) {
        fail('c$slot kept a rename apart from the open ${r.name}');
      }
    });
    cubit.start();
  }

  /// Every op that leaves the queue must have an answer from the server, a
  /// refusal, or be one `ontoKept` folded away with the add or refused
  /// rename it followed.
  void _onState(ListState state) {
    final next = state.pending;
    if (identical(next, _seen)) {
      return;
    }
    final now = Set<ItemOp>.identity()..addAll(next);
    final before = Set<ItemOp>.identity()..addAll(_seen);
    final folded = <String>{};
    for (final op in _seen) {
      if (!now.contains(op) && op is AddItem) {
        final rows = acked[op];
        if (rows != null && rows[op.itemId] == null && rows.length > 1) {
          folded.add(op.itemId);
        }
      }
    }
    final renamed = {for (final op in refusedRenames) op.itemId};
    final added = [
      for (final op in next)
        if (!before.contains(op)) op,
    ];
    for (final op in _seen) {
      if (now.contains(op) || !open.remove(op)) {
        continue;
      }
      final explained =
          acked.containsKey(op) ||
          rejected.contains(op) ||
          folded.contains(op.itemId) ||
          (op is PlaceItem && folded.contains(op.anchorId)) ||
          (op is MergeItems && folded.contains(op.otherId));
      if (explained) {
        continue;
      }
      if (renamed.contains(op.itemId)) {
        // Job 114: after a refused rename a later rename is replaced by one
        // carrying both, or ontoKept moves the op onto the copy the item
        // folds into, which the server must then have merged.
        if (!added.any((a) => a.itemId == op.itemId && a is EditItem)) {
          _movedOntoCopy.add(op);
        }
        continue;
      }
      fail('c$slot lost an op without an answer: ${_describe(op)}');
    }
    for (final op in next) {
      if (!before.contains(op)) {
        open.add(op);
      }
    }
    _seen = next;
  }

  String _describe(ItemOp op) => jsonEncode(op.toJson()..remove('item_id'));

  /// The app is killed and opened again: the queue must come back from the
  /// device cache as it was.
  void restart() {
    final queued = [
      for (final op in cubit.state.pending) jsonEncode(op.toJson()),
    ];
    open.clear();
    unawaited(_states?.cancel());
    unawaited(_hints?.cancel());
    unawaited(_rejections?.cancel());
    unawaited(cubit.close());
    for (final channel in [...channels]) {
      channel.sub
        ..live = false
        ..closed = true;
    }
    channels.clear();
    hint = null;
    lastMerge = null;
    start();
    _restored = queued;
  }

  List<String>? _restored;

  /// After the cache answered: the queue the killed app left.
  void checkRestored() {
    final queued = _restored;
    if (queued == null) {
      return;
    }
    _restored = null;
    final loaded = [
      for (final op in cubit.state.pending) jsonEncode(op.toJson()),
    ];
    if (loaded.length < queued.length || !_prefixEquals(loaded, queued)) {
      fail(
        'c$slot restart lost queued ops: had ${queued.length}, '
        'got back ${loaded.length}',
      );
    }
    open.addAll(cubit.state.pending);
    _seen = cubit.state.pending;
  }

  static bool _prefixEquals(List<String> a, List<String> prefix) {
    for (var i = 0; i < prefix.length; i++) {
      if (a[i] != prefix[i]) {
        return false;
      }
    }
    return true;
  }

  void goOffline() {
    net
      ..up = false
      ..epoch += 1;
    for (final channel in [...channels]) {
      final sub = channel.sub;
      final wasLive = sub.live || !sub.closed;
      sub
        ..live = false
        ..closed = true;
      if (wasLive) {
        Timer(Duration(milliseconds: 50 + net.rng.nextInt(500)), () {
          if (channels.contains(channel)) {
            channel.onStatus(ConnectionStatus.offline);
          }
        });
      }
    }
  }

  void goOnline() => net.up = true;
}

String _itemName(Item item) => '"${item.name}"(${item.status.name})';

/// Runs [steps] for [seed] under a fake clock and checks the oracle once
/// every device is online and quiet.
RunResult runScenario(
  int seed,
  List<Step> steps, {
  int clients = 3,
  Plant plant = Plant.none,

  /// Also fail when a replayed add put back an item deleted after it.
  bool strict = false,
  bool deleteWins = false,
  bool joinGap = false,
}) {
  final failures = <String>[];
  final trace = <String>[];
  fakeAsync((fake) {
    final base = DateTime.utc(2026, 11, 5, 12);
    DateTime now() => base.add(fake.elapsed);
    void log(String line) =>
        trace.add('${fake.elapsed.inMilliseconds.toString().padLeft(7)} $line');
    final skew = Random(seed ^ 0x5eed);
    final nets = [for (var i = 0; i < clients; i++) Net(Random(seed * 31 + i))];
    final backend = FakeBackend(now, nets, log, deleteWins: deleteWins);
    final devices = <Device>[];
    for (var i = 0; i < clients; i++) {
      final http = _http[i]
        ..backend = backend
        ..net = nets[i]
        ..user = 'u$i'
        ..log = log;
      assert(http.slot == i, 'slot');
      final offset = Duration(seconds: skew.nextInt(600) - 300);
      devices.add(
        Device(
          i,
          backend,
          nets[i],
          () => now().add(offset),
          plant,
          log,
          failures.add,
          joinGap: joinGap,
        ),
      );
    }
    try {
      for (final device in devices) {
        device.start();
      }
      fake.elapse(const Duration(seconds: 2));
      for (final step in steps) {
        fake.elapse(Duration(milliseconds: step.delayMs));
        final device = devices[step.client];
        final line = _act(device, step);
        log('c${step.client} $line');
        fake.flushMicrotasks();
        device.checkRestored();
      }
      for (final device in devices) {
        device.goOnline();
      }
      log('all online');
      fake.elapse(const Duration(seconds: 100));
      for (final device in devices) {
        device.checkMoved();
      }
      _check(backend, devices, failures);
      if (strict) {
        for (final name in backend.resurrected) {
          failures.add('a replayed add put back $name after its delete');
        }
        for (final key in backend.reopened) {
          failures.add('an untick opened $key a second time');
        }
      }
      for (final device in devices) {
        unawaited(device.cubit.close());
      }
      fake.flushMicrotasks();
    } on Object catch (e, s) {
      failures.add('crash: $e\n${s.toString().split('\n').take(8).join('\n')}');
    }
  });
  return RunResult(failures, trace);
}

String _act(Device device, Step step) {
  final cubit = device.cubit;
  List<Item> shown(bool Function(Item i) where) => [
    ...cubit.state.items.values.where(where),
  ];
  Item? pick(bool Function(Item i) where) {
    final items = shown(where);
    return items.isEmpty ? null : items[step.a % items.length];
  }

  bool active(Item i) => i.status == ItemStatus.active;
  bool bought(Item i) => i.status == ItemStatus.bought;
  String edit(Item? item, ItemChanges changes) {
    if (item == null) {
      return '${step.act.name}: nothing to edit';
    }
    cubit.edit(item.id, changes);
    return '${step.act.name} ${_itemName(item)} $changes';
  }

  switch (step.act) {
    case Act.net:
      if (device.net.up) {
        device.goOffline();
        return 'network down';
      }
      device.goOnline();
      return 'network up';
    case Act.restart:
      device.restart();
      return 'app restarted';
    case Act.add:
      final name = names[step.a % names.length];
      final brand = brands[step.b % brands.length];
      final result = cubit.addParsed(
        ParsedEntry(
          name: name,
          brand: brand,
          quantity: quantities[step.b ~/ 7 % quantities.length],
          storeId: storeIds[step.b ~/ 3 % storeIds.length],
        ),
      );
      return 'add "$name" ${brand ?? ''}: ${result.runtimeType}';
    case Act.tick:
      final item = pick(active);
      if (item == null) {
        return 'tick: nothing open';
      }
      cubit.tick(item.id);
      return 'tick ${_itemName(item)}';
    case Act.untick:
      final item = pick(bought);
      if (item == null) {
        return 'untick: nothing bought';
      }
      cubit.untick(item.id);
      return 'untick ${_itemName(item)}';
    case Act.readd:
      final item = pick(bought);
      if (item == null) {
        return 'readd: nothing bought';
      }
      cubit.readd(item.id);
      return 'readd ${_itemName(item)}';
    case Act.rename:
      return edit(
        pick(active),
        ItemChanges(name: names[step.b % names.length]),
      );
    case Act.quantity:
      return edit(
        pick(active),
        ItemChanges(quantity: SetTo(quantities[step.b % quantities.length])),
      );
    case Act.brand:
      return edit(
        pick(active),
        ItemChanges(brand: SetTo(brands[step.b % brands.length])),
      );
    case Act.moveStore:
      return edit(
        pick(active),
        ItemChanges(storeId: SetTo(storeIds[step.b % storeIds.length])),
      );
    case Act.moveCategory:
      return edit(
        pick(active),
        ItemChanges(categoryId: categoryIds[step.b % categoryIds.length]),
      );
    case Act.delete:
      final item = pick((_) => true);
      if (item == null) {
        return 'delete: nothing there';
      }
      device.deleted.add(item);
      if (device.deleted.length > 3) {
        device.deleted.removeAt(0);
      }
      cubit.delete(item.id);
      return 'delete ${_itemName(item)}';
    case Act.restore:
      if (device.deleted.isEmpty) {
        return 'restore: nothing deleted';
      }
      final item = device.deleted.removeAt(step.a % device.deleted.length);
      cubit.restore(item);
      return 'restore ${_itemName(item)}';
    case Act.merge:
      final hint = device.hint;
      if (hint == null) {
        return 'merge: no hint';
      }
      device
        ..hint = null
        ..lastMerge = cubit.merge(hint);
      return 'merge ${_itemName(hint.added)} into ${_itemName(hint.onList)}: '
          '${device.lastMerge == null ? 'refused' : 'queued'}';
    case Act.unmerge:
      final merge = device.lastMerge;
      if (merge == null) {
        return 'unmerge: nothing merged';
      }
      device.lastMerge = null;
      cubit.unmerge(merge);
      return 'unmerge ${_itemName(merge.merged)}';
  }
}

/// What `fetchItems` answers: the open items and the 50 latest bought.
Map<String, Map<String, Object?>> _serverList(FakeBackend backend) {
  final bought =
      [
        for (final row in backend.rows.values)
          if (row['status'] == 'bought') row,
      ]..sort(
        (a, b) =>
            (b['bought_at']! as String).compareTo(a['bought_at']! as String),
      );
  return {
    for (final row in [
      for (final row in backend.rows.values)
        if (row['status'] == 'active') row,
      ...bought.take(50),
    ])
      row['id']! as String: Item.fromJson(row).toJson(),
  };
}

void _check(FakeBackend backend, List<Device> devices, List<String> failures) {
  final server = _serverList(backend);
  for (final device in devices) {
    final state = device.cubit.state;
    final c = 'c${device.slot}';
    if (state.pending.isNotEmpty) {
      failures.add('$c still has ${state.pending.length} ops queued');
    }
    if (state.connection != ConnectionStatus.online) {
      failures.add('$c is ${state.connection.name} after quiescing');
    }
    final shown = {
      for (final item in state.items.values) item.id: item.toJson(),
    };
    for (final id in {...server.keys, ...shown.keys}) {
      final (want, got) = (server[id], shown[id]);
      // A device may know more bought rows than a load fetches (50).
      if (backend.rows[id] case final row?
          when want == null &&
              row['status'] == 'bought' &&
              jsonEncode(Item.fromJson(row).toJson()) == jsonEncode(got)) {
        continue;
      }
      if (want == null) {
        failures.add(
          '$c shows ${got!['name']}(${got['status']}), gone on the server',
        );
      } else if (got == null) {
        failures.add('$c misses ${want['name']}(${want['status']})');
      } else if (jsonEncode(want) != jsonEncode(got)) {
        final diff = [
          for (final key in want.keys)
            if (jsonEncode(want[key]) != jsonEncode(got[key]))
              '$key: server ${want[key]}, shown ${got[key]}',
        ];
        failures.add('$c shows ${want['name']} stale: ${diff.join('; ')}');
      }
    }
  }
  final open = <String, String>{};
  for (final row in backend.rows.values) {
    if (row['status'] != 'active') {
      continue;
    }
    final key = FakeBackend.openKey(row);
    if (open[key] case final twin? when !backend.reopened.contains(key)) {
      failures.add('server has $twin open twice');
    }
    open[key] = row['name']! as String;
  }
  // Each committed column holds its value unless a later commit wrote it or
  // deleted the row: the server is last-writer-wins per column.
  final last = <String, int>{};
  for (final commit in backend.commits) {
    if (commit.deleted) {
      last['${commit.itemId}/*'] = commit.seq;
    }
    for (final column in commit.columns.keys) {
      last['${commit.itemId}/$column'] = commit.seq;
    }
  }
  for (final commit in backend.commits) {
    final row = backend.rows[commit.itemId];
    if (row == null || commit.deleted) {
      continue;
    }
    if ((last['${commit.itemId}/*'] ?? 0) > commit.seq) {
      continue;
    }
    for (final MapEntry(:key, :value) in commit.columns.entries) {
      if (last['${commit.itemId}/$key'] == commit.seq &&
          jsonEncode(row[key]) != jsonEncode(value)) {
        failures.add('server lost the write of $key on ${row['name']}');
      }
    }
  }
}

/// Removes steps while [seed] still fails (delta debugging), up to [budget]
/// runs; the steps that are left are the repro.
List<Step> shrink(
  int seed,
  List<Step> steps, {
  int budget = 300,
  Plant plant = Plant.none,
  bool strict = false,
  bool deleteWins = false,
  bool joinGap = false,
}) {
  var current = steps;
  var chunk = current.length ~/ 2;
  var runs = 0;
  while (chunk >= 1 && runs < budget) {
    var removed = false;
    for (
      var start = 0;
      start < current.length && runs < budget;
      start += chunk
    ) {
      final candidate = [
        ...current.take(start),
        ...current.skip(start + chunk),
      ];
      runs++;
      if (candidate.isNotEmpty &&
          runScenario(
            seed,
            candidate,
            plant: plant,
            strict: strict,
            deleteWins: deleteWins,
            joinGap: joinGap,
          ).failed) {
        current = candidate;
        removed = true;
        start -= chunk;
      }
    }
    if (!removed) {
      chunk ~/= 2;
    }
  }
  return current;
}

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/quantity.dart';
import 'package:http/http.dart' as http;

/// The op a request is sent for, read from the zone by [FakeHttpClient] so
/// the server can tag the commits it makes.
const opZoneKey = #fuzzOp;

/// Waits [ms] fake milliseconds; tests may not use `Future.delayed`.
Future<void> sleep(int ms) {
  final done = Completer<void>();
  Timer(Duration(milliseconds: ms), done.complete);
  return done.future;
}

const householdId = 'h1';

const categoryRows = [
  {
    'id': 'produce',
    'name': 'Obst & Gemüse',
    'sort_order': 10,
    'seed_key': null,
  },
  {'id': 'chilled', 'name': 'Kühlregal', 'sort_order': 30, 'seed_key': null},
  {'id': 'bakery', 'name': 'Brot', 'sort_order': 40, 'seed_key': null},
  {'id': 'other', 'name': 'Sonstiges', 'sort_order': 1000, 'seed_key': 'other'},
];

const storeRows = [
  {'id': 'dm', 'name': 'dm', 'sort_order': 10, 'seed_key': 'dm'},
  {'id': 'lidl', 'name': 'Lidl', 'sort_order': 20, 'seed_key': 'lidl'},
];

/// What the server's classifier gives a name; the fuzz names cover each.
String classify(String name) {
  final folded = foldName(name);
  if (['milch', 'butter', 'joghurt', 'kaese'].any(folded.contains)) {
    return 'chilled';
  }
  if (['aepfel', 'karotten', 'moehren'].any(folded.contains)) {
    return 'produce';
  }
  if (['brot', 'semmel'].any(folded.contains)) {
    return 'bakery';
  }
  return 'other';
}

/// `public.canonical_key` for the fuzz names: two synonym pairs, else the
/// folded name.
String canonicalKey(String name) => switch (foldName(name)) {
  'karotten' || 'moehren' => 'mohr',
  'broetchen' || 'semmeln' => 'broetchen',
  final folded => folded,
};

/// `public.open_item_key`.
String openItemKey(String name, String? brand, String? properties) => [
  foldName(name),
  foldName(brand ?? ''),
  ((properties ?? '')
          .split(',')
          .map(foldName)
          .where((p) => p.isNotEmpty)
          .toList()
        ..sort())
      .join(','),
].join('|');

String? _clean(Object? value) => switch (value) {
  final String s when s.trim().isNotEmpty => s.trim(),
  _ => null,
};

/// One commit's effect on one item, for the oracle.
final class Commit(
  final int seq,
  final String itemId,

  /// Columns written, with the values the row has after the commit; empty
  /// for a delete.
  final Map<String, Object?> columns, {
  final bool deleted = false,
  final Object? op,
});

/// One realtime subscription of a client's channel.
final class Subscription(
  final int slot,
  final void Function(Map<String, Object?> row) onRow,
  final void Function(String id, DateTime at) onDelete,
) {
  var live = false;
  var closed = false;
  var _lastDelivery = 0;
}

/// A client's network: [up] or not; [epoch] counts the drops, so a request
/// in flight across a drop fails.
final class Net(final Random rng) {
  var up = true;
  var epoch = 0;

  int latency() =>
      5 + rng.nextInt(120) + (rng.nextInt(10) == 0 ? rng.nextInt(2000) : 0);

  int realtimeLatency() =>
      10 + rng.nextInt(300) + (rng.nextInt(10) == 0 ? rng.nextInt(2000) : 0);
}

/// The household's Postgres as the list sees it through PostgREST and
/// Realtime: the items table with its triggers (`items_before_write`,
/// `items_skip_duplicate`, `items_rename_duplicate`), `put_item`,
/// `merge_items`, `unmerge_items`, and one channel per client that delivers
/// each commit in commit order.
final class FakeBackend(
  final DateTime Function() _now,
  final List<Net> nets,
  final void Function(String line) log, {

  /// The NEEDS_LEAD proposal (docs/hillclimb/hc-sync-proposals): `put_item`
  /// answers "gone" for a new add whose id was deleted, and inserts again
  /// only for a restore. The app does not send `p_restored` yet; the fake
  /// reads it from the op.
  final bool deleteWins = false,
}) {
  final rows = <String, Map<String, Object?>>{};
  final merges = <String, Map<String, Object?>>{};
  final commits = <Commit>[];

  /// Ids deleted at some point, and the names of items a new (not restored)
  /// add inserted again after their delete: a replayed add undoing a
  /// partner's delete. Counted, not a divergence (docs/hillclimb/hc-sync.md).
  final _deleted = <String>{};
  final resurrected = <String>[];

  /// The open-item keys an untick gave a second open row: the server lets
  /// that through (job 104) and only renames are folded. Counted, not a
  /// failure, unless strict.
  final reopened = <String>{};
  final _names = <String, String>{};

  /// The name the item [id] had last, also once it is gone.
  String nameOf(String id) => _names[id] ?? '?';
  final subscriptions = <Subscription>[];
  var _seq = 0;
  DateTime? _last;

  static const members = ['u0', 'u1', 'u2'];

  /// `now()`: the transaction's time, strictly increasing here.
  DateTime _stamp() {
    var t = _now().toUtc();
    final last = _last;
    if (last != null && !t.isAfter(last)) {
      t = last.add(const Duration(microseconds: 1));
    }
    return _last = t;
  }

  // Realtime ------------------------------------------------------------

  Subscription subscribe(
    int slot,
    void Function(Map<String, Object?> row) onRow,
    void Function(String id, DateTime at) onDelete,
  ) {
    final sub = Subscription(slot, onRow, onDelete);
    subscriptions.add(sub);
    return sub;
  }

  /// [row] null: a delete, committed at [at] (`commit_timestamp`).
  void _broadcast(Map<String, Object?>? row, String id, [DateTime? at]) {
    final payload = row == null ? null : jsonDecode(jsonEncode(row));
    for (final sub in subscriptions) {
      if (!sub.live) {
        continue;
      }
      final now = _now().millisecondsSinceEpoch;
      final due = max(
        sub._lastDelivery,
        now + nets[sub.slot].realtimeLatency(),
      );
      sub._lastDelivery = due;
      Timer(Duration(milliseconds: due - now), () {
        if (!sub.live) {
          log('c${sub.slot} realtime dropped for "${nameOf(id)}"');
          return;
        }
        final what = payload is Map ? 'row ${payload['status']}' : 'delete';
        log('c${sub.slot} realtime $what "${nameOf(id)}"');
        if (payload is Map<String, Object?>) {
          sub.onRow(payload);
        } else {
          sub.onDelete(id, at!);
        }
      });
    }
  }

  // Writes ----------------------------------------------------------------

  void _commit(String id, Map<String, Object?> columns, Object? op) {
    _names[id] = rows[id]!['name']! as String;
    commits.add(Commit(++_seq, id, columns, op: op));
    _broadcast(rows[id], id);
  }

  void _commitDelete(String id, Object? op) {
    _deleted.add(id);
    rows.remove(id);
    commits.add(Commit(++_seq, id, const {}, deleted: true, op: op));
    // At or after every earlier commit's start, before every later one.
    _broadcast(null, id, _last);
  }

  double _endOf(Map<String, Object?> row) {
    var top = 0.0;
    var any = false;
    for (final other in rows.values) {
      if (other['id'] != row['id'] &&
          other['category_id'] == row['category_id'] &&
          other['store_id'] == row['store_id'] &&
          other['sort_key'] != null) {
        final key = (other['sort_key']! as num).toDouble();
        top = any ? max(top, key) : key;
        any = true;
      }
    }
    return (any ? top : 0) + 1024;
  }

  String? _openTwin(Map<String, Object?> row) {
    if (row['status'] != 'active') {
      return null;
    }
    final key = openKey(row);
    final open =
        [
          for (final other in rows.values)
            if (other['id'] != row['id'] &&
                other['status'] == 'active' &&
                openKey(other) == key)
              other,
        ]..sort(
          (a, b) => (a['created_at']! as String).compareTo(
            b['created_at']! as String,
          ),
        );
    return open.firstOrNull?['id'] as String?;
  }

  static String openKey(Map<String, Object?> row) => openItemKey(
    row['name']! as String,
    row['brand'] as String?,
    row['properties'] as String?,
  );

  /// `items_before_write` and `items_skip_duplicate` on insert; null when the
  /// insert is skipped for the open item it already is (its id in [twin]).
  Map<String, Object?>? _insert(
    Map<String, Object?> values,
    String user,
    Object? op, {
    void Function(String id)? twin,
    bool keepTimes = false,
  }) {
    final now = _stamp().toIso8601String();
    final name = (values['name']! as String).trim();
    final status = values['status'] as String? ?? 'active';
    final row = <String, Object?>{
      'id': values['id'],
      'name': name,
      'quantity': _clean(values['quantity']),
      'brand': _clean(values['brand']),
      'properties': _clean(values['properties']),
      'category_id': values['category_id'] ?? classify(name),
      // suggest_store: the fuzz household remembers no stores.
      'store_id': values['store_id'],
      'sort_key': values['sort_key'],
      'status': status,
      'created_at': keepTimes ? values['created_at'] : now,
      'updated_at': now,
      'bought_at': status == 'bought' ? now : null,
      'added_by': keepTimes ? values['added_by'] : user,
      'categorized_via': keepTimes
          ? values['categorized_via']
          : values['category_id'] == null
          ? 'exact'
          : 'picked',
      'canonical_key': canonicalKey(name),
    };
    row['sort_key'] ??= _endOf(row);
    if (_openTwin(row) case final open?) {
      twin?.call(open);
      return null;
    }
    rows[row['id']! as String] = row;
    _commit(row['id']! as String, Map.of(row), op);
    return row;
  }

  /// A PATCH through `items_before_write`; null when no row has [id].
  Map<String, Object?>? _update(
    String id,
    Map<String, Object?> patch,
    Object? op, {
    bool keepSortKey = false,
  }) {
    final old = rows[id];
    if (old == null) {
      return null;
    }
    final next = {...old, ...patch};
    next['name'] = (next['name']! as String).trim();
    for (final column in ['quantity', 'brand', 'properties']) {
      next[column] = _clean(next[column]);
    }
    if (next['name'] != old['name']) {
      next['canonical_key'] = canonicalKey(next['name']! as String);
    }
    if (next['sort_key'] == null ||
        ((next['store_id'], next['category_id']) !=
                (old['store_id'], old['category_id']) &&
            next['sort_key'] == old['sort_key'] &&
            !keepSortKey)) {
      next['sort_key'] = _endOf(next);
    }
    final now = _stamp().toIso8601String();
    next['created_at'] = old['created_at'];
    next['added_by'] = old['added_by'];
    next['updated_at'] = now;
    if (next['status'] == 'bought' && old['status'] != 'bought') {
      next['bought_at'] = now;
    } else if (next['status'] == 'active') {
      next['bought_at'] = null;
    }
    if (next['status'] == 'active' &&
        openKey(next) != openKey(old) &&
        _openTwin(next) != null) {
      // items_rename_duplicate (job 104).
      throw const _PgError(409, '23505', 'already_on_list');
    }
    if (next['status'] == 'active' &&
        old['status'] != 'active' &&
        _openTwin(next) != null) {
      reopened.add(openKey(next));
    }
    rows[id] = next;
    _commit(id, {
      for (final key in next.keys)
        if (patch.containsKey(key) || next[key] != old[key]) key: next[key],
    }, op);
    return next;
  }

  // PostgREST -----------------------------------------------------------

  /// Answers one request as PostgREST would: status and JSON body.
  (int, Object?) handle(
    String user,
    String method,
    Uri url,
    Object? body,
    Object? op,
  ) {
    final path = url.path.replaceFirst('/rest/v1/', '');
    final query = url.queryParameters;
    String? eq(String column) => switch (query[column]) {
      final String v when v.startsWith('eq.') => v.substring(3),
      _ => null,
    };
    try {
      return switch ((method, path)) {
        ('GET', 'categories') => (200, categoryRows),
        ('GET', 'stores') => (200, storeRows),
        ('GET', 'store_category_order') => (200, const <Object?>[]),
        ('POST', 'rpc/household_members_of') => (
          200,
          [
            for (final (i, m) in members.indexed)
              {
                'user_id': m,
                'display_name': 'User $m',
                'role': i == 0 ? 'owner' : 'member',
              },
          ],
        ),
        ('GET', 'items') => (200, _select(eq('id'), eq('status'), query)),
        ('PATCH', 'items') => (
          200,
          [?_update(eq('id')!, (body! as Map).cast<String, Object?>(), op)],
        ),
        ('DELETE', 'items') => (200, _delete(eq('id')!, op)),
        ('POST', 'rpc/put_item') => (
          200,
          _putItem(user, (body! as Map).cast(), op),
        ),
        ('POST', 'rpc/merge_items') => (
          200,
          _mergeItems((body! as Map).cast(), op),
        ),
        ('POST', 'rpc/unmerge_items') => (
          200,
          _unmergeItems((body! as Map).cast(), op),
        ),
        ('POST', 'rpc/suggest_items') => (200, const <Object?>[]),
        _ => throw const _PgError(404, 'PGRST202', 'not in the fake'),
      };
    } on _PgError catch (e) {
      return (
        e.status,
        {'code': e.code, 'message': e.message, 'details': null, 'hint': null},
      );
    }
  }

  List<Map<String, Object?>> _select(
    String? id,
    String? status,
    Map<String, String> query,
  ) {
    var result = [
      for (final row in rows.values)
        if ((id == null || row['id'] == id) &&
            (status == null || row['status'] == status))
          row,
    ];
    if (query['order'] == 'bought_at.desc') {
      result.sort(
        (a, b) =>
            (b['bought_at']! as String).compareTo(a['bought_at']! as String),
      );
    }
    if (query['limit'] case final limit?) {
      result = result.take(int.parse(limit)).toList();
    }
    return result;
  }

  List<Map<String, Object?>> _delete(String id, Object? op) {
    if (!rows.containsKey(id)) {
      return const [];
    }
    _commitDelete(id, op);
    return [
      {'id': id},
    ];
  }

  List<Map<String, Object?>> _putItem(
    String user,
    Map<String, Object?> body,
    Object? op,
  ) {
    final id = body['p_id']! as String;
    if (rows[id] case final own?) {
      return [own];
    }
    if (deleteWins &&
        _deleted.contains(id) &&
        !(op is AddItem && op.restored)) {
      return const [];
    }
    String? twin;
    final row = _insert(
      {
        'id': id,
        'name': body['p_name'],
        'quantity': body['p_quantity'],
        'brand': body['p_brand'],
        'properties': body['p_properties'],
        'category_id': body['p_category'],
        'store_id': body['p_store'],
        'sort_key': body['p_sort_key'],
        'status': body['p_status'],
      },
      user,
      op,
      twin: (open) => twin = open,
    );
    if (row != null) {
      if (_deleted.contains(id) && op is AddItem && !op.restored) {
        resurrected.add(row['name']! as String);
      }
      if (body['p_no_store'] == true && row['store_id'] != null) {
        return [
          ?_update(id, {'store_id': null}, op),
        ];
      }
      return [row];
    }
    return [?rows[twin]];
  }

  Map<String, Object?> _mergeResult(String kept, String merged) => {
    'kept': rows[kept],
    'merged': rows[merged],
  };

  Map<String, Object?> _mergeItems(Map<String, Object?> body, Object? op) {
    final mergeId = body['p_merge']! as String;
    final keepId = body['p_keep']! as String;
    final otherId = body['p_other']! as String;
    if (merges[mergeId] case final done?) {
      return _mergeResult(
        done['kept_id']! as String,
        (done['merged_row']! as Map)['id']! as String,
      );
    }
    if (keepId == otherId) {
      throw const _PgError(400, '22023', 'same_item');
    }
    final (keep, other) = (rows[keepId], rows[otherId]);
    if (keep == null || other == null) {
      throw const _PgError(404, 'P0002', 'item_not_found');
    }
    if (keep['status'] != 'active' || other['status'] != 'active') {
      throw const _PgError(400, '22023', 'not_open');
    }
    final String quantity;
    try {
      quantity = mergeQuantities(
        keep['quantity'] as String?,
        other['quantity'] as String?,
      );
    } on QuantityTooLong {
      throw const _PgError(400, '22001', 'merged_quantity_too_long');
    }
    final before = Map.of(keep);
    // The other row goes first, as in merge_items: open, it would be the
    // twin items_rename_duplicate refuses the kept row's new details for.
    _commitDelete(otherId, op);
    final after = _update(keepId, {
      'quantity': quantity,
      'brand': keep['brand'] ?? other['brand'],
      'properties': keep['properties'] ?? other['properties'],
    }, op)!;
    merges[mergeId] = {
      'kept_id': keepId,
      'kept_before': before,
      'kept_after': {
        'quantity': after['quantity'],
        'brand': after['brand'],
        'properties': after['properties'],
      },
      'merged_row': other,
      'undone': false,
    };
    return _mergeResult(keepId, otherId);
  }

  Map<String, Object?> _unmergeItems(Map<String, Object?> body, Object? op) {
    final merge = merges[body['p_merge']! as String];
    if (merge == null) {
      throw const _PgError(404, 'P0002', 'merge_not_found');
    }
    final keptId = merge['kept_id']! as String;
    final mergedRow = (merge['merged_row']! as Map).cast<String, Object?>();
    if (merge['undone'] == false) {
      final before = merge['kept_before']! as Map;
      final after = merge['kept_after']! as Map;
      if (rows[keptId] case final kept?
          when [
            'quantity',
            'brand',
            'properties',
          ].every((c) => kept[c] == after[c])) {
        _update(keptId, {
          for (final c in ['quantity', 'brand', 'properties']) c: before[c],
        }, op);
      }
      if (!rows.containsKey(mergedRow['id'])) {
        _insert(mergedRow, '', op, keepTimes: true);
      }
      merge['undone'] = true;
    }
    return _mergeResult(keptId, mergedRow['id']! as String);
  }
}

final class const _PgError(
  final int status,
  final String code,
  final String message,
) implements Exception;

/// The http client one simulated device's SupabaseClient sends through: its
/// [net] decides whether a request reaches [backend] and whether the answer
/// comes back.
final class FakeHttpClient(final int slot) extends http.BaseClient {
  FakeBackend? backend;
  Net? net;
  var user = '';
  void Function(String line)? log;

  String _brief(Uri url, Object? body) {
    final server = backend!;
    final id = switch (url.queryParameters['id']) {
      final String v => v.substring(3),
      _ => switch (body) {
        {'p_id': final String id} => id,
        {'p_keep': final String id} => id,
        _ => null,
      },
    };
    final status = url.queryParameters['status'];
    return [
      if (id != null) '"${server.nameOf(id)}"',
      ?status,
      if (body is Map && body.keys.any((k) => !'$k'.startsWith('p_')))
        jsonEncode(body),
    ].join(' ');
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final (server, net) = (backend!, this.net!);
    final op = Zone.current[opZoneKey];
    final body = request is http.Request && request.body.isNotEmpty
        ? jsonDecode(request.body)
        : null;
    final what =
        '${request.method} ${request.url.path.replaceFirst('/rest/v1/', '')}';
    if (!net.up) {
      await sleep(50);
      throw http.ClientException('offline: $what');
    }
    final epoch = net.epoch;
    await sleep(net.latency());
    if (!net.up || net.epoch != epoch) {
      log?.call('c$slot $what: lost on the way');
      throw http.ClientException('connection lost: $what');
    }
    final (status, answer) = server.handle(
      user,
      request.method,
      request.url,
      body,
      op,
    );
    log?.call('c$slot $what ${_brief(request.url, body)} -> $status');
    await sleep(net.latency());
    if (!net.up || net.epoch != epoch) {
      log?.call('c$slot $what: applied, answer lost');
      throw http.ClientException('answer lost: $what');
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(answer))),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }
}

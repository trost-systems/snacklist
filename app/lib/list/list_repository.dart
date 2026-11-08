import 'dart:async';

import 'package:family_groceries/list/add_sheet/suggestion.dart';
import 'package:family_groceries/list/model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum ConnectionStatus() {
  connecting,
  online,
  offline,
}

/// The list's only door to the backend. Errors from [send] other than a
/// [RejectedOp] are treated as transient and retried: a [ServerTrouble]
/// when the server answered, anything else when it could not be reached.
abstract interface class ListRepository() {
  Future<Catalog> fetchCatalog();

  /// Active items plus the most recently bought ones ("Zuletzt verwendet").
  Future<List<Item>> fetchItems();

  /// What the household buys again and again, best first, without what is
  /// on the list now.
  Future<List<Usual>> fetchUsuals();

  /// Applies [op] on the server and returns the rows it touched, by id: the
  /// resulting row, or null when the item no longer exists. One row for most
  /// ops; a merge and its undo answer for both items.
  Future<Map<String, Item?>> send(ItemOp op);

  Future<void> renameCategory(String id, String name);

  /// Appends the category to the route and to every store layout.
  Future<void> createCategory(String name);

  /// [ids] is every category, in the new route order.
  Future<void> reorderCategories(List<String> ids);

  /// [ids] is every store, in the new order.
  Future<void> reorderStores(List<String> ids);

  /// The id of the household's store named [name] (any case or spacing),
  /// created after the others when there is none.
  Future<String> addStore(String name);

  Future<void> renameStore(String id, String name);

  /// Its items fall back to no store.
  Future<void> deleteStore(String id);

  /// Splits one typed entry into its fields with the server's parser.
  /// Throws when the server can't be reached.
  Future<ParsedEntry> parse(String text);

  /// The add sheet's rows for one typed entry, the parsed entry first
  /// (`public.suggest_entries`). Throws when the server can't be reached.
  Future<List<Suggestion>> suggest(String text);

  /// Moves the category's items to [reassignTo], by default the fallback.
  Future<void> deleteCategory(String id, {String? reassignTo});

  /// [orderedIds] is every category in the store's walking order.
  Future<void> setStoreLayout(
    String storeId,
    List<String> orderedIds,
    Set<String> hiddenIds,
  );

  /// Splits a dictated sentence into entries with the server's German
  /// splitter (the voice endpoint Siri uses), brand and details split off
  /// as for a typed add; empty when it found nothing. `truncated`: it heard
  /// more than the 30 items one sentence takes, and only those came back.
  Future<SpokenSplit> splitSpoken(String text);

  /// Live changes for the household; returns a function that unsubscribes.
  /// [onItemDeleted] gets the delete's commit time.
  Future<void> Function() watch({
    required void Function(Item item) onItem,
    required void Function(String id, DateTime at) onItemDeleted,
    required void Function() onCatalogChanged,
    required void Function(ConnectionStatus status) onStatus,
  });

  /// The device's network was down: the realtime socket may have died with
  /// it, unnoticed until a heartbeat goes unanswered (25 to 50 s). Closes it
  /// as a missed heartbeat does; the client opens a new one and every
  /// channel joins again, which [watch]'s `onStatus` tells.
  void renewRealtime();
}

typedef SpokenSplit = ({List<ParsedEntry> entries, bool truncated});

/// The server refused a write (constraint, policy); retrying will not help.
final class const RejectedOp(
  final String message, {

  /// A category, store or (renamed) open item with that name already
  /// exists.
  final bool nameTaken = false,
}) implements Exception {
  @override
  String toString() => 'RejectedOp($message)';
}

/// The server answered, but with an error a retry may fix: it is
/// overloaded, restarting or lost its database, or the token lapsed in
/// flight. The app is not offline then, and the change is not refused.
final class const ServerTrouble(final String message) implements Exception {
  @override
  String toString() => 'ServerTrouble($message)';
}

/// Whether [e] is the server's trouble rather than a refusal of this
/// request: a JWT (PGRST3xx) or database connection (PGRST0xx) error, a
/// 5xx status (the code when the body is no PostgREST error), or a
/// transient SQLSTATE: connection (08), serialization (40001), deadlock
/// (40P01), resources (53), operator intervention such as a statement
/// timeout (57), system (58) or internal (XX).
bool _isTrouble(PostgrestException e) {
  final code = e.code ?? '';
  if (code.length == 3) {
    return code.startsWith('5');
  }
  return code.startsWith('PGRST0') ||
      code.startsWith('PGRST3') ||
      (code.length == 5 &&
          (const ['08', '53', '57', '58', 'XX'].any(code.startsWith) ||
              code == '40001' ||
              code == '40P01'));
}

/// Runs a read; the server's trouble comes out as a [ServerTrouble].
Future<T> _answered<T>(Future<T> Function() read) async {
  try {
    return await read();
  } on PostgrestException catch (e) {
    if (_isTrouble(e)) {
      throw ServerTrouble(e.message);
    }
    rethrow;
  }
}

/// Sends [request] once: a PostgREST builder sends it again on every await.
Future<T> _sent<T>(Future<T> request) async => await request;

/// Runs a write; a PostgREST answer means the database refused it, unless it
/// is the server's trouble (a [ServerTrouble]), which a retry may get past.
Future<T> _refusable<T>(Future<T> Function() write) async {
  try {
    return await write();
  } on PostgrestException catch (e) {
    if (_isTrouble(e)) {
      throw ServerTrouble(e.message);
    }
    throw RejectedOp(e.message, nameTaken: e.code == '23505');
  }
}

class SupabaseListRepository(
  final SupabaseClient _client,
  final String householdId,
) implements ListRepository {
  static const _itemColumns =
      'id, name, quantity, brand, properties, category_id, store_id, '
      'sort_key, status, created_at, updated_at, bought_at, added_by, '
      'categorized_via, canonical_key';

  @override
  Future<Catalog> fetchCatalog() => _answered(() async {
    final categories = _sent(
      _client.rest
          .from('categories')
          .select('id, name, sort_order, seed_key')
          .eq('household_id', householdId)
          .order('sort_order', ascending: true),
    );
    final stores = _sent(
      _client.rest
          .from('stores')
          .select('id, name, sort_order, seed_key')
          .eq('household_id', householdId)
          .order('sort_order', ascending: true),
    );
    final layout = _sent(
      _client.rest
          .from('store_category_order')
          .select('store_id, category_id, sort_order, hidden')
          .eq('household_id', householdId),
    );
    // Names and roles of this household's members only (job 169b): a
    // user in a club next to their family loads the family's members.
    final members = _sent(
      _client
          .rpc<List<dynamic>>(
            'household_members_of',
            params: {'p_household': householdId},
          )
          .then((rows) => rows.whereType<Map<String, dynamic>>().toList()),
    );
    // Not a record `.wait`: its ParallelWaitError would hide whether the
    // server answered. Future.wait throws the first error once all settled.
    await Future.wait([categories, stores, layout, members]);
    return Catalog(
      categories: (await categories).map(Category.fromJson).toList(),
      stores: (await stores).map(Store.fromJson).toList(),
      layout: (await layout).map(StoreCategory.fromJson).toList(),
      members: [
        for (final row in await members)
          if (row case {'user_id': final String id})
            Member(
              id: id,
              displayName: switch (row['display_name']) {
                final String name => name,
                _ => '',
              },
              role: row['role'] as String?,
            ),
      ],
    );
  });

  @override
  Future<void> renameCategory(String id, String name) => _refusable(
    () => _client.rest.from('categories').update({'name': name}).eq('id', id),
  );

  @override
  Future<void> createCategory(String name) => _refusable(
    () => _client.rpc<void>(
      'create_category',
      params: {'p_household': householdId, 'p_name': name},
    ),
  );

  @override
  Future<void> reorderCategories(List<String> ids) => _refusable(
    () => _client.rpc<void>(
      'reorder_categories',
      params: {'p_household': householdId, 'p_ids': ids},
    ),
  );

  @override
  Future<void> reorderStores(List<String> ids) => _refusable(
    () => _client.rpc<void>(
      'reorder_stores',
      params: {'p_household': householdId, 'p_ids': ids},
    ),
  );

  @override
  Future<String> addStore(String name) => _refusable(
    () => _client.rpc<String>(
      'add_store',
      params: {'p_household': householdId, 'p_name': name},
    ),
  );

  @override
  Future<void> renameStore(String id, String name) => _refusable(
    () => _client.rpc<void>(
      'rename_store',
      params: {'p_store': id, 'p_name': name},
    ),
  );

  @override
  Future<void> deleteStore(String id) => _refusable(
    () => _client.rpc<void>('delete_store', params: {'p_store': id}),
  );

  @override
  Future<ParsedEntry> parse(String text) => _answered(() async {
    final Object? result = await _client.rpc<dynamic>(
      'parse_item',
      params: {'p_household': householdId, 'p_text': text},
    );
    return ParsedEntry.fromJson(_singleRow(result)!);
  });

  @override
  Future<List<Suggestion>> suggest(String text) async {
    final rows = await _client.rpc<List<dynamic>>(
      'suggest_entries',
      params: {'p_household': householdId, 'p_text': text},
    );
    return [
      for (final row in rows) Suggestion.fromJson(row as Map<String, Object?>),
    ];
  }

  @override
  Future<void> deleteCategory(String id, {String? reassignTo}) => _refusable(
    () => _client.rpc<void>(
      'delete_category',
      params: {'p_category': id, 'p_reassign_to': reassignTo},
    ),
  );

  @override
  Future<void> setStoreLayout(
    String storeId,
    List<String> orderedIds,
    Set<String> hiddenIds,
  ) => _refusable(
    () => _client.rpc<void>(
      'set_store_layout',
      params: {
        'p_store': storeId,
        'p_categories': orderedIds,
        'p_hidden': hiddenIds.toList(),
      },
    ),
  );

  @override
  Future<List<Item>> fetchItems() => _answered(() async {
    final results = await Future.wait([
      _client.rest
          .from('items')
          .select(_itemColumns)
          .eq('household_id', householdId)
          .eq('status', 'active'),
      _client.rest
          .from('items')
          .select(_itemColumns)
          .eq('household_id', householdId)
          .eq('status', 'bought')
          .order('bought_at', ascending: false)
          .limit(50),
    ]);
    return [for (final rows in results) ...rows.map(Item.fromJson)];
  });

  @override
  Future<List<Usual>> fetchUsuals() async {
    final rows = await _client.rpc<List<dynamic>>(
      'suggest_items',
      params: {'p_household': householdId, 'p_prefix': '', 'p_limit': 200},
    );
    return [
      for (final row in rows) Usual.fromJson(row as Map<String, Object?>),
    ];
  }

  @override
  Future<Map<String, Item?>> send(ItemOp op) async => switch (op) {
    MergeItems(:final mergeId, :final otherId) => await _merge(
      'merge_items',
      {'p_merge': mergeId, 'p_keep': op.itemId, 'p_other': otherId},
      kept: op.itemId,
      merged: otherId,
    ),
    UnmergeItems(:final mergeId, :final merged) => await _merge(
      'unmerge_items',
      {'p_merge': mergeId},
      kept: op.itemId,
      merged: merged.id,
    ),
    AddItem() => await _add(op),
    _ => {op.itemId: await _sendOne(op)},
  };

  /// `put_item` answers with the row the add is: its own, or the open item
  /// that was already on the list (then this id is gone, answered as null).
  /// No row: the id is taken by a row this user cannot see.
  Future<Map<String, Item?>> _add(AddItem op) => _refusable(() async {
    final AddItem(:noStore, :deviceParsed, :autoCategory) = op;
    final item = deviceParsed
        ? (await parse(op.item.name)).onto(op.item, noStore: noStore)
        : op.item;
    final row = _singleRow(
      await _client.rpc<dynamic>(
        'put_item',
        params: {
          'p_id': item.id,
          'p_household': householdId,
          'p_name': item.name,
          'p_quantity': item.quantity,
          'p_brand': item.brand,
          'p_properties': item.properties,
          // None given: the server classifies the item.
          'p_category': autoCategory ? null : item.categoryId,
          // None given: the server fills in the remembered store.
          'p_store': item.storeId,
          // A restored item keeps its place.
          'p_sort_key': item.sortKey,
          'p_status': item.status.name,
          'p_no_store': noStore,
        },
      ),
    );
    return switch (row == null ? null : Item.fromJson(row)) {
      null => {op.itemId: null},
      final own when own.id == op.itemId => {own.id: own},
      final kept => {op.itemId: null, kept.id: kept},
    };
  });

  /// `merge_items` and `unmerge_items` answer `{kept, merged}`, each the row
  /// or null. `P0002`: an item (or the merge, when it never landed) is gone;
  /// both items' current rows acknowledge the op.
  Future<Map<String, Item?>> _merge(
    String function,
    Map<String, Object?> params, {
    required String kept,
    required String merged,
  }) => _refusable(() async {
    try {
      final Object? result = await _client.rpc<dynamic>(
        function,
        params: params,
      );
      Item? row(Object? json) =>
          json is Map<String, Object?> ? Item.fromJson(json) : null;
      return switch (result) {
        {'kept': final k, 'merged': final m} => {kept: row(k), merged: row(m)},
        _ => throw const RejectedOp('unexpected answer'),
      };
    } on PostgrestException catch (e) {
      if (e.code == 'P0002') {
        final (k, m) = await (_fetchItem(kept), _fetchItem(merged)).wait;
        return {kept: k, merged: m};
      }
      rethrow;
    }
  });

  Future<Item?> _sendOne(ItemOp op) => _refusable(() async {
    final items = _client.rest.from('items');
    final List<Map<String, dynamic>> rows;
    switch (op) {
      case SetStatus(:final status, :final storeId):
        rows = await items
            .update({'status': status.name, 'store_id': ?storeId})
            .eq('id', op.itemId)
            .select(_itemColumns);
      case EditItem(:final changes, :final deviceParsed):
        final sent = deviceParsed
            ? (await parse(changes.name!)).ontoRename(changes)
            : changes;
        rows = await items
            .update(sent.toColumns())
            .eq('id', op.itemId)
            .select(_itemColumns);
      case MoveItem(:final categoryId, :final storeId):
        return await _rpcItem(op, 'move_item', {
          'p_item': op.itemId,
          'p_store': storeId,
          'p_category': categoryId,
        });
      case PlaceItem(:final anchorId, :final edge):
        return await _rpcItem(op, 'place_item', {
          'p_item': op.itemId,
          'p_anchor': anchorId,
          'p_edge': edge.name,
        });
      case DeleteItem():
        await items.delete().eq('id', op.itemId).select('id');
        return null;
      case AddItem() || MergeItems() || UnmergeItems():
        throw StateError('$op goes through _add or _merge');
    }
    // No row back: the item is gone.
    return rows.isEmpty
        ? await _fetchItem(op.itemId)
        : Item.fromJson(rows.single);
  });

  /// An RPC that returns the item's row. `P0002`: the item or the anchor is
  /// gone; the item's current row (or null) acknowledges the op.
  Future<Item?> _rpcItem(
    ItemOp op,
    String function,
    Map<String, Object?> params,
  ) async {
    try {
      final Object? result = await _client.rpc<dynamic>(
        function,
        params: params,
      );
      final row = _singleRow(result);
      return row == null ? await _fetchItem(op.itemId) : Item.fromJson(row);
    } on PostgrestException catch (e) {
      if (e.code == 'P0002') {
        return await _fetchItem(op.itemId);
      }
      rethrow;
    }
  }

  /// A function returning one row answers with an object, a set-returning
  /// one with a list.
  static Map<String, Object?>? _singleRow(Object? result) => switch (result) {
    final Map<String, Object?> row => row,
    [final Map<String, Object?> row, ...] => row,
    _ => null,
  };

  @override
  Future<SpokenSplit> splitSpoken(String text) async {
    try {
      final response = await _client.functions.invoke(
        'voice',
        // The shown household, so stores and categories are this list's
        // (job 169b); without it the server parses for the default.
        body: {
          'text': text,
          'mode': 'parse',
          'split': true,
          'household': householdId,
        },
      );
      final items = switch (response.data) {
        {'items': final List<Object?> items} => items,
        _ => const <Object?>[],
      };
      final entries = [
        for (final item in items)
          if (item case {
            'name': final String name,
            'quantity': final String? quantity,
          })
            ParsedEntry(
              name: name,
              // A voice function from before job 111 answers without them.
              brand: item['brand'] as String?,
              properties: item['properties'] as String?,
              quantity: quantity,
              storeId: item['storeId'] as String?,
              // The server's category, so the row lands in it before the
              // insert trigger confirms (job 150); older functions omit it.
              categoryId: item['categoryId'] as String?,
            ),
      ];
      return (
        entries: entries,
        truncated: switch (response.data) {
          {'truncated': true} => true,
          _ => false,
        },
      );
    } on FunctionException catch (e) {
      if (e.status == 422) {
        return (entries: const <ParsedEntry>[], truncated: false);
      }
      if (e.status >= 500) {
        throw ServerTrouble('${e.status}');
      }
      rethrow;
    }
  }

  Future<Item?> _fetchItem(String id) async {
    final row = await _client.rest
        .from('items')
        .select(_itemColumns)
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : Item.fromJson(row);
  }

  @override
  Future<void> Function() watch({
    required void Function(Item item) onItem,
    required void Function(String id, DateTime at) onItemDeleted,
    required void Function() onCatalogChanged,
    required void Function(ConnectionStatus status) onStatus,
  }) {
    final mine = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'household_id',
      value: householdId,
    );
    final channel = _client.channel('household:$householdId');
    for (final table in ['categories', 'stores', 'store_category_order']) {
      for (final event in [
        PostgresChangeEvent.insert,
        PostgresChangeEvent.update,
      ]) {
        channel.onPostgresChanges(
          event: event,
          schema: 'public',
          table: table,
          filter: mine,
          callback: (_) => onCatalogChanged(),
        );
      }
      // Delete events cannot be filtered; another household's only costs a
      // reload.
      channel.onPostgresChanges(
        event: PostgresChangeEvent.delete,
        schema: 'public',
        table: table,
        callback: (_) => onCatalogChanged(),
      );
    }
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'items',
          filter: mine,
          callback: (p) => onItem(Item.fromJson(p.newRecord)),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'items',
          filter: mine,
          callback: (p) => onItem(Item.fromJson(p.newRecord)),
        )
        // Delete events cannot be filtered; unknown ids are ignored.
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'items',
          callback: (p) => switch (p.oldRecord['id']) {
            final String id => onItemDeleted(id, p.commitTimestamp),
            _ => null,
          },
        )
        // The join is confirmed before the server's Postgres listener runs;
        // "Subscribed to PostgreSQL" says it does, and a resync then picks up
        // what changed in between. Errors arrive as channelError below.
        .onSystemEvents((payload) {
          final Object? system = payload;
          if (system case {'extension': 'postgres_changes', 'status': 'ok'}) {
            onStatus(ConnectionStatus.online);
          }
        })
        .subscribe(
          (status, _) => onStatus(switch (status) {
            RealtimeSubscribeStatus.subscribed => ConnectionStatus.online,
            RealtimeSubscribeStatus.channelError ||
            RealtimeSubscribeStatus.timedOut ||
            RealtimeSubscribeStatus.closed => ConnectionStatus.offline,
          }),
        );
    return () async {
      await _client.removeChannel(channel);
    };
  }

  @override
  void renewRealtime() {
    final socket = _client.realtime;
    if (socket.isConnected) {
      unawaited(socket.conn?.sink.close(1000, 'network changed'));
    }
  }
}

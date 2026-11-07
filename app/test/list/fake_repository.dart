import 'dart:async';
import 'dart:math' as math;

import 'package:family_groceries/list/add_sheet/suggestion.dart';
import 'package:family_groceries/list/entry.dart';
import 'package:family_groceries/list/list_repository.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/quantity.dart';

/// An in-memory server. [online] false makes every call fail like a dropped
/// connection; [reject] makes the next write fail like a refused one;
/// [sendTrouble] and [fetchTrouble] make item writes and list reads fail
/// like a server in trouble (a 5xx).
/// Writes come from [me]; [remoteAdd] is Lea's by default.
///
/// Stores: Lidl walks the route backwards; dm does not carry produce or
/// chilled.
class FakeRepository() implements ListRepository {
  var categories = const [
    Category(id: 'produce', name: 'Obst & Gemüse', sortOrder: 10),
    Category(id: 'chilled', name: 'Kühlregal', sortOrder: 30),
    Category(id: 'other', name: 'Sonstiges', sortOrder: 1000, seedKey: 'other'),
  ];
  var stores = const [
    Store(id: 'dm', name: 'dm', sortOrder: 10, seedKey: 'dm'),
    Store(id: 'lidl', name: 'Lidl', sortOrder: 20, seedKey: 'lidl'),
  ];
  var layout = const [
    StoreCategory(storeId: 'dm', categoryId: 'other', sortOrder: 10),
    StoreCategory(
      storeId: 'dm',
      categoryId: 'produce',
      sortOrder: 20,
      hidden: true,
    ),
    StoreCategory(
      storeId: 'dm',
      categoryId: 'chilled',
      sortOrder: 30,
      hidden: true,
    ),
    StoreCategory(storeId: 'lidl', categoryId: 'other', sortOrder: 10),
    StoreCategory(storeId: 'lidl', categoryId: 'chilled', sortOrder: 20),
    StoreCategory(storeId: 'lidl', categoryId: 'produce', sortOrder: 30),
  ];
  var members = const [
    Member(id: 'peter', displayName: 'Peter'),
    Member(id: 'lea', displayName: 'Lea'),
  ];
  var me = 'peter';

  /// What suggest_items answers; [usualsFail] makes it fail on its own.
  var usuals = <Usual>[];
  var usualsFail = false;
  var usualsCalls = 0;

  /// When set, fetchUsuals waits for it, after the online check.
  Completer<void>? usualsGate;
  final rows = <String, Item>{};
  final sent = <ItemOp>[];

  /// Catalog writes, as `method(args)` strings.
  final catalogCalls = <String>[];
  var online = true;
  var reject = false;
  var sendTrouble = false;
  var fetchTrouble = false;
  var _clock = DateTime.utc(2026, 10, 22, 12);
  void Function(Item item)? emitItem;

  /// A delete, committed now on the fake's clock.
  void Function(String id)? emitDelete;
  void Function(ConnectionStatus status)? emitStatus;
  void Function()? emitCatalogChanged;

  Completer<void>? gate;

  /// Runs as an op reaches the server; may change rows or throw a refusal.
  void Function(ItemOp op)? beforeSend;

  /// What the items trigger reports as `categorized_via` for a new row.
  String? categorizedVia;

  /// Applies the next op, then fails as if its answer was lost.
  var loseNextAnswer = false;

  /// How many times the list subscribed to realtime.
  var watches = 0;

  /// How many times the list asked for its items, answered or not.
  var itemFetches = 0;

  /// Each unsubscribe waits for the next of these, if any.
  final unwatchGates = <Completer<void>>[];

  /// Holds catalog fetches until completed.
  Completer<void>? catalogGate;

  /// Holds item fetches, after the online check, until completed.
  Completer<void>? itemsGate;

  DateTime _tick() => _clock = _clock.add(const Duration(seconds: 1));

  String classify(String name) =>
      name.toLowerCase().contains('milch') ? 'chilled' : 'other';

  void _ensureOnline() {
    if (!online) {
      throw Exception('offline');
    }
  }

  void _ensureFetchable() {
    if (fetchTrouble) {
      throw const ServerTrouble('503');
    }
  }

  @override
  Future<Catalog> fetchCatalog() async {
    _ensureOnline();
    _ensureFetchable();
    await catalogGate?.future;
    return Catalog(
      categories: categories,
      stores: stores,
      layout: layout,
      members: members,
    );
  }

  void _writeCatalog(String call) {
    _ensureOnline();
    if (reject) {
      reject = false;
      throw const RejectedOp('denied');
    }
    catalogCalls.add(call);
  }

  @override
  Future<void> renameCategory(String id, String name) async {
    if (categories.any((c) => c.id != id && nameKey(c.name) == nameKey(name))) {
      throw const RejectedOp('duplicate key', nameTaken: true);
    }
    _writeCatalog('rename($id, $name)');
    categories = Catalog(categories: categories).withName(id, name).categories;
  }

  @override
  /// Like `create_category`: a name the household has in any case or
  /// spacing returns that category.
  Future<void> createCategory(String name) async {
    if (categories.any((c) => nameKey(c.name) == nameKey(name))) {
      return;
    }
    _writeCatalog('create($name)');
    categories = [
      ...categories,
      Category(id: 'new-$name', name: name, sortOrder: 2000),
    ];
  }

  @override
  Future<void> reorderCategories(List<String> ids) async {
    _writeCatalog('reorder(${ids.join(', ')})');
    categories = Catalog(categories: categories).withRouteOrder(ids).categories;
  }

  @override
  Future<void> reorderStores(List<String> ids) async {
    _writeCatalog('reorderStores(${ids.join(', ')})');
    stores = Catalog(stores: stores).withStoreOrder(ids).stores;
  }

  @override
  Future<String> addStore(String name) async {
    _writeCatalog('addStore($name)');
    if (Catalog(stores: stores).storeNamed(name) case final existing?) {
      return existing.id;
    }
    final id = 'new-$name';
    stores = [
      ...stores,
      Store(
        id: id,
        name: name,
        sortOrder: (stores.lastOrNull?.sortOrder ?? 0) + 10,
      ),
    ];
    return id;
  }

  @override
  Future<void> renameStore(String id, String name) async {
    if (stores.any((s) => s.id != id && nameKey(s.name) == nameKey(name))) {
      throw const RejectedOp('store_name_taken', nameTaken: true);
    }
    _writeCatalog('renameStore($id, $name)');
    stores = Catalog(stores: stores).withStoreName(id, name).stores;
  }

  @override
  Future<void> deleteStore(String id) async {
    _writeCatalog('deleteStore($id)');
    stores = [...stores.where((s) => s.id != id)];
    layout = [...layout.where((row) => row.storeId != id)];
    for (final item in [...rows.values]) {
      if (item.storeId == id) {
        rows[item.id] = item.copyWith(storeId: () => null);
      }
    }
  }

  /// What parse_item answers for a text; unknown texts parse to their name.
  final parsed = <String, ParsedEntry>{};

  @override
  Future<ParsedEntry> parse(String text) async {
    _ensureOnline();
    return parsed[text] ?? ParsedEntry(name: text);
  }

  /// What suggest_entries answers per text; else the parse alone.
  final suggestions = <String, List<Suggestion>>{};

  /// Texts asked for, in order.
  final suggestCalls = <String>[];

  /// When set, suggest waits for it.
  Completer<void>? suggestGate;

  @override
  Future<List<Suggestion>> suggest(String text) async {
    suggestCalls.add(text);
    await suggestGate?.future;
    _ensureOnline();
    return suggestions[text] ??
        [
          Suggestion(
            SuggestionSource.typed,
            parsed[text] ?? ParsedEntry(name: text, categoryId: classify(text)),
          ),
        ];
  }

  @override
  Future<void> deleteCategory(String id, {String? reassignTo}) async {
    _writeCatalog('delete($id, $reassignTo)');
    final target = reassignTo ?? 'other';
    categories = [...categories.where((c) => c.id != id)];
    for (final item in [...rows.values]) {
      if (item.categoryId == id) {
        rows[item.id] = item.copyWith(categoryId: target);
      }
    }
  }

  @override
  Future<void> setStoreLayout(
    String storeId,
    List<String> orderedIds,
    Set<String> hiddenIds,
  ) async {
    _writeCatalog(
      'layout($storeId: ${orderedIds.join(', ')}; ${hiddenIds.join(', ')})',
    );
    layout = Catalog(layout: layout)
        .withStoreLayout(storeId, orderedIds, hiddenIds)
        .layout;
  }

  @override
  Future<List<Item>> fetchItems() async {
    itemFetches++;
    _ensureOnline();
    _ensureFetchable();
    await itemsGate?.future;
    return rows.values.toList();
  }

  @override
  Future<List<Usual>> fetchUsuals() async {
    usualsCalls++;
    _ensureOnline();
    await usualsGate?.future;
    if (usualsFail) {
      throw Exception('suggest_items failed');
    }
    return usuals;
  }

  /// The merges the fake server did, by merge id, with both rows as they
  /// were (for the undo) and whether they were undone.
  final merges = <String, ({Item kept, Item merged, bool undone})>{};

  @override
  Future<Map<String, Item?>> send(ItemOp sentOp) async {
    await gate?.future;
    _ensureOnline();
    if (sendTrouble) {
      throw const ServerTrouble('503');
    }
    beforeSend?.call(sentOp);
    if (reject) {
      reject = false;
      throw const RejectedOp('denied');
    }
    // As the repository: a line typed offline is parsed before it is added.
    final op = switch (sentOp) {
      AddItem(deviceParsed: true, :final item, :final noStore) => AddItem(
        (await parse(item.name)).onto(item, noStore: noStore),
        noStore: noStore,
      ),
      EditItem(deviceParsed: true, :final changes, :final keyBefore) =>
        EditItem(
          sentOp.itemId,
          (await parse(changes.name!)).ontoRename(changes),
          keyBefore: keyBefore,
        ),
      _ => sentOp,
    };
    sent.add(op);
    final Map<String, Item?> touched;
    switch (op) {
      case MergeItems(:final mergeId, :final otherId):
        touched = _merge(op, mergeId, otherId);
      case UnmergeItems(:final mergeId, :final merged):
        touched = _unmerge(op, mergeId, merged.id);
      case EditItem(:final changes) when _renamesOntoTwin(op.itemId, changes):
        // items_rename_duplicate (job 104): another open row has that name.
        sent.removeLast();
        throw const RejectedOp('already_on_list', nameTaken: true);
      case AddItem(:final item) when _openTwin(item) != null:
        // put_item: the open item the add already is, unchanged.
        final kept = _openTwin(item)!;
        touched = {op.itemId: null, kept.id: kept};
      default:
        return {op.itemId: _sendOne(op)};
    }
    if (loseNextAnswer) {
      loseNextAnswer = false;
      throw Exception('answer lost');
    }
    return touched;
  }

  /// As `merge_items`: once per merge id, both open; the kept row takes the
  /// merged quantity (the app's mirror of the server's rule).
  Map<String, Item?> _merge(MergeItems op, String mergeId, String otherId) {
    final (kept, other) = (rows[op.itemId], rows[otherId]);
    if (!merges.containsKey(mergeId)) {
      if (kept == null || other == null) {
        return {op.itemId: kept, otherId: other};
      }
      if (kept.status != ItemStatus.active ||
          other.status != ItemStatus.active) {
        throw const RejectedOp('not_open');
      }
      final String quantity;
      try {
        quantity = mergeQuantities(kept.quantity, other.quantity);
      } on QuantityTooLong {
        throw const RejectedOp('merged_quantity_too_long');
      }
      merges[mergeId] = (kept: kept, merged: other, undone: false);
      rows[op.itemId] = _stamp(
        kept.copyWith(
          quantity: () => quantity,
          brand: () => kept.brand ?? other.brand,
          properties: () => kept.properties ?? other.properties,
        ),
      );
      rows.remove(otherId);
    }
    return {op.itemId: rows[op.itemId], otherId: rows[otherId]};
  }

  Map<String, Item?> _unmerge(UnmergeItems op, String mergeId, String otherId) {
    final merge = merges[mergeId];
    if (merge != null && !merge.undone) {
      merges[mergeId] = (kept: merge.kept, merged: merge.merged, undone: true);
      if (rows[op.itemId] case final kept?) {
        rows[op.itemId] = _stamp(
          kept.copyWith(
            quantity: () => merge.kept.quantity,
            brand: () => merge.kept.brand,
            properties: () => merge.kept.properties,
          ),
        );
      }
      rows[otherId] = _stamp(merge.merged);
    }
    return {op.itemId: rows[op.itemId], otherId: rows[otherId]};
  }

  bool _renamesOntoTwin(String id, ItemChanges changes) {
    final current = rows[id];
    return current != null &&
        current.status == ItemStatus.active &&
        _openTwin(changes.apply(current), except: id) != null;
  }

  /// As `items_skip_duplicate`: another open row with the same name, brand
  /// and details (in any order), for a new open item; with [except], for
  /// that row renamed (`items_rename_duplicate`).
  Item? _openTwin(Item item, {String? except}) {
    String key(Item i) => [
      foldName(i.name),
      foldName(i.brand ?? ''),
      ((i.properties ?? '')
              .split(',')
              .map(foldName)
              .where((p) => p.isNotEmpty)
              .toList()
            ..sort())
          .join(','),
    ].join('|');
    if ((except == null && rows.containsKey(item.id)) ||
        item.status != ItemStatus.active) {
      return null;
    }
    return rows.values
        .where(
          (r) =>
              r.id != except &&
              r.status == ItemStatus.active &&
              key(r) == key(item),
        )
        .firstOrNull;
  }

  Item _stamp(Item item) => Item(
    id: item.id,
    name: item.name,
    quantity: item.quantity,
    brand: item.brand,
    properties: item.properties,
    categoryId: item.categoryId,
    storeId: item.storeId,
    sortKey: item.sortKey,
    status: item.status,
    createdAt: item.createdAt,
    updatedAt: _tick(),
    boughtAt: item.boughtAt,
    addedBy: item.addedBy,
    categorizedVia: item.categorizedVia,
    canonicalKey: item.canonicalKey,
  );

  /// What the items trigger sets as `canonical_key` for a name: here the
  /// test's [canonical] table, else the folded name.
  final canonical = <String, String>{};

  String canonicalOf(String name) => canonical[name] ?? foldName(name);

  Item? _sendOne(ItemOp op) {
    final current = rows[op.itemId];
    final next = switch (op) {
      AddItem(:final item) =>
        current ??
            Item(
              id: item.id,
              name: item.name,
              quantity: item.quantity,
              brand: item.brand,
              properties: item.properties,
              categoryId: item.categoryId ?? classify(item.name),
              storeId: item.storeId,
              sortKey: item.sortKey,
              status: item.status,
              createdAt: _tick(),
              updatedAt: _clock,
              addedBy: me,
              categorizedVia: categorizedVia,
              canonicalKey: canonicalOf(item.name),
            ),
      PlaceItem(:final anchorId, :final edge) => _place(
        current,
        anchorId,
        edge,
      ),
      _ => op.apply(current),
    };
    if (next == null) {
      rows.remove(op.itemId);
      return null;
    }
    // The items trigger: a new item, or one whose group changed without a
    // key, goes to the end of its group.
    final regrouped =
        current == null ||
        current.storeId != next.storeId ||
        current.categoryId != next.categoryId;
    final keyed = op is PlaceItem || (op is AddItem && next.sortKey != null);
    final stamped = Item(
      id: next.id,
      name: next.name,
      quantity: next.quantity,
      brand: next.brand,
      properties: next.properties,
      categoryId: next.categoryId,
      storeId: next.storeId,
      sortKey: regrouped && !keyed || next.sortKey == null
          ? _endOf(next)
          : next.sortKey,
      status: next.status,
      createdAt: next.createdAt,
      updatedAt: _tick(),
      boughtAt: next.boughtAt,
      addedBy: next.addedBy,
      categorizedVia: next.categorizedVia,
      canonicalKey: next.name == current?.name
          ? next.canonicalKey
          : canonicalOf(next.name),
    );
    rows[op.itemId] = stamped;
    if (loseNextAnswer) {
      loseNextAnswer = false;
      throw Exception('answer lost');
    }
    return stamped;
  }

  /// The item's (store, category) group on the server, in walk order.
  List<Item> groupOf(Item item) => [
    for (final row in rows.values)
      if (row.id != item.id &&
          row.status == ItemStatus.active &&
          row.storeId == item.storeId &&
          row.categoryId == item.categoryId)
        row,
  ]..sort(compareWalk);

  double _endOf(Item item) =>
      groupOf(item).map((i) => i.sortKey ?? 0).fold<double>(0, math.max) + 1024;

  Item? _place(Item? current, String anchorId, Edge edge) {
    final anchor = rows[anchorId];
    if (current == null || anchor == null) {
      return current;
    }
    final moved = current.copyWith(
      categoryId: anchor.categoryId,
      storeId: () => anchor.storeId,
    );
    return moved.copyWith(
      sortKey: () => _keyNextTo(groupOf(moved), anchor, edge),
    );
  }

  /// Like `place_item`: halfway to the anchor's neighbour in [group], or
  /// 1024 past the anchor at an end.
  static double? _keyNextTo(List<Item> group, Item anchor, Edge edge) {
    final key = anchor.sortKey;
    if (key == null) {
      return null;
    }
    final at = group.indexWhere((i) => i.id == anchor.id);
    final next = switch (edge) {
      Edge.before => at > 0 ? group[at - 1].sortKey : null,
      Edge.after => at + 1 < group.length ? group[at + 1].sortKey : null,
    };
    return switch ((edge, next)) {
      (_, final n?) => (key + n) / 2,
      (Edge.before, null) => key - 1024,
      (Edge.after, null) => key + 1024,
    };
  }

  /// Stands in for the server's splitter: splits on commas and "und", then
  /// reads each part as [parse] does; at most 30, as the server.
  @override
  Future<SpokenSplit> splitSpoken(String text) async {
    _ensureOnline();
    final entries = [
      for (final part in text.split(RegExp(r',|\bund\b')))
        if (parseEntry(part) case Entry(:final name, :final quantity)
            when name.isNotEmpty)
          switch (parsed[name]) {
            final split? => ParsedEntry(
              name: split.name,
              brand: split.brand,
              properties: split.properties,
              quantity: quantity ?? split.quantity,
            ),
            null => ParsedEntry(name: name, quantity: quantity),
          },
    ];
    return (entries: entries.take(30).toList(), truncated: entries.length > 30);
  }

  @override
  Future<void> Function() watch({
    required void Function(Item item) onItem,
    required void Function(String id, DateTime at) onItemDeleted,
    required void Function() onCatalogChanged,
    required void Function(ConnectionStatus status) onStatus,
  }) {
    watches++;
    emitItem = onItem;
    emitDelete = (id) => onItemDeleted(id, _tick());
    emitStatus = onStatus;
    emitCatalogChanged = onCatalogChanged;
    return () async {
      if (unwatchGates.isNotEmpty) {
        await unwatchGates.removeAt(0).future;
      }
    };
  }

  /// A change made by another household member.
  Item remoteAdd(
    String name, {
    String? categoryId,
    String? storeId,
    String? addedBy = 'lea',
    String? brand,
    String? properties,
    String? quantity,
  }) {
    final item = Item(
      id: 'remote-${rows.length}',
      name: name,
      quantity: quantity,
      brand: brand,
      properties: properties,
      categoryId: categoryId ?? classify(name),
      storeId: storeId,
      status: ItemStatus.active,
      createdAt: _tick(),
      updatedAt: _clock,
      addedBy: addedBy,
      canonicalKey: canonicalOf(name),
    );
    return rows[item.id] = item.copyWith(sortKey: () => _endOf(item));
  }
}

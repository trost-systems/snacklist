import 'dart:async';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/analytics/events.dart';
import 'package:family_groceries/list/add_sheet/suggestion.dart';
import 'package:family_groceries/list/entry.dart';
import 'package:family_groceries/list/list_cache.dart';
import 'package:family_groceries/list/list_repository.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/quantity.dart';
import 'package:flutter/foundation.dart' show immutable, listEquals, setEquals;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

@immutable
class const ListState({
  final Catalog catalog = const Catalog(),

  /// Rows as last confirmed by the server.
  final Map<String, Item> server = const {},

  /// Ops not yet acknowledged, oldest first.
  final List<ItemOp> pending = const [],
  final bool loaded = false,
  final ConnectionStatus connection = ConnectionStatus.connecting,

  /// What the household buys again and again, best first.
  final List<Usual> usuals = const [],

  /// Null until loaded from the device or, on a first start, set by the
  /// first resync.
  final SeenMark? seen,

  /// Folded stores and the dismissed explainer, from the device.
  final ListPrefs prefs = const ListPrefs(),
}) {
  Map<String, Item> get items => visibleItems(server, pending);

  ListState copyWith({
    Catalog? catalog,
    Map<String, Item>? server,
    List<ItemOp>? pending,
    bool? loaded,
    ConnectionStatus? connection,
    List<Usual>? usuals,
    SeenMark? seen,
    ListPrefs? prefs,
  }) => ListState(
    catalog: catalog ?? this.catalog,
    server: server ?? this.server,
    pending: pending ?? this.pending,
    loaded: loaded ?? this.loaded,
    connection: connection ?? this.connection,
    usuals: usuals ?? this.usuals,
    seen: seen ?? this.seen,
    prefs: prefs ?? this.prefs,
  );
}

sealed class const AddResult();

final class const Added(final Item item) extends AddResult;

final class const AlreadyOnList(final Item item) extends AddResult;

final class const NothingToAdd() extends AddResult;

/// A write the server refused; the UI tells the user.
sealed class const Rejected();

final class const ItemRejected(final String itemName) extends Rejected;

final class const NameTaken(final String name) extends Rejected;

final class const StoreNameTaken(final String name) extends Rejected;

/// A duplicate-hint merge could not be done: an item is gone or no longer
/// open, or the merged quantity would be too long. Both items stay.
final class const MergeRefused(final String name) extends Rejected;

/// A category or layout change did not save; the catalog was reloaded.
final class const CatalogRejected() extends Rejected;

/// A store or category order change made offline; nothing changed.
final class const NeedsConnection() extends Rejected;

/// A store added, renamed or deleted offline; nothing changed.
final class const StoreNeedsConnection() extends Rejected;

/// Job 32b: [added] just landed, and [onList] (open, another spelling or a
/// synonym of it) was on the list already. The UI offers to merge them.
final class const DedupeHint(final Item added, final Item onList);

/// A merge the UI can undo: both items as they were before it, and the kept
/// item as the merge shows it.
final class const Merge(
  final String id, {
  required final Item kept,
  required final Item merged,
  required final Item result,
});

const _maxResubscribe = Duration(seconds: 30);

class ListCubit(
  final ListRepository _repo,
  final ListCache _cache, {

  /// The signed-in user: their own adds are never news to them.
  required final String userId,
  DateTime Function()? clock,
  Duration resubscribeAfter = const Duration(seconds: 3),

  /// Told once per user action (add, tick, re-add, reorder); never by an
  /// op's retry, a realtime echo or an undo (docs/ANALYTICS.md).
  final Analytics? analytics,
}) extends Cubit<ListState> {
  this : super(const ListState());

  final DateTime Function() _clock = clock ?? DateTime.now;
  final _rejections = StreamController<Rejected>.broadcast();
  final _hints = StreamController<DedupeHint>.broadcast();
  Future<void> Function()? _unwatch;
  Timer? _retry;
  Timer? _catalogReload;
  Timer? _save;
  Timer? _usualsReload;
  var _flushing = false;

  /// Rows acknowledged during each resync in flight; they beat its snapshot.
  /// Resyncs overlap (the opening one and the channel's first subscribe).
  final _resyncAcks = <Map<String, Item?>>{};

  /// Whether the realtime channel is subscribed. A resync that answers only
  /// brings the list back online while it is.
  var _channelUp = false;

  /// A channel the server closed is never rejoined by the client library,
  /// so the list subscribes again itself: after `resubscribeAfter`, doubling
  /// up to 30 s while it stays down.
  final _firstResubscribe = resubscribeAfter;
  late var _resubscribeDelay = _firstResubscribe;
  Timer? _resubscribe;

  /// Bumped on every subscribe, so a replaced channel's late callbacks are
  /// ignored.
  var _watchGeneration = 0;

  /// A resync sets the first seen mark only once the stored one was read.
  var _seenLoaded = false;

  Stream<Rejected> get rejections => _rejections.stream;

  /// A new add of something already open under another spelling, once its
  /// add is acknowledged (the server sets the canonical key). Never for a
  /// restore, a retry or a partner's add.
  Stream<DedupeHint> get hints => _hints.stream;

  /// Shows the cached list, if any, then connects. Ops queued before the
  /// cache answers go after the cached ones.
  void start() => unawaited(_start());

  Future<void> _start() async {
    final (cached, seen, prefs) = await (
      _cache.load(),
      _cache.loadSeen(),
      _cache.loadPrefs(),
    ).wait;
    if (prefs != null) {
      emit(state.copyWith(prefs: prefs));
    }
    if (cached != null) {
      emit(
        state.copyWith(
          catalog: cached.catalog,
          server: {for (final item in cached.server) item.id: item},
          pending: [...cached.pending, ...state.pending],
          loaded: true,
          usuals: cached.usuals,
        ),
      );
    }
    if (seen != null) {
      emit(state.copyWith(seen: seen));
    }
    _seenLoaded = true;
    if (isClosed) {
      return;
    }
    _watch();
    unawaited(resync());
  }

  void _watch() {
    final generation = ++_watchGeneration;
    bool current() => generation == _watchGeneration && !isClosed;
    _unwatch = _repo.watch(
      onItem: (row) {
        if (current()) {
          _setServer(mergeServerRow(state.server, row));
          // A new member: reload so the title can name them.
          if (row.addedBy != null &&
              state.catalog.member(row.addedBy) == null) {
            _scheduleCatalogReload();
          }
        }
      },
      onItemDeleted: (id) {
        if (current() && state.server.containsKey(id)) {
          _setServer({...state.server}..remove(id));
        }
      },
      onCatalogChanged: () {
        if (current()) {
          _scheduleCatalogReload();
        }
      },
      onStatus: (status) {
        if (current()) {
          _onChannelStatus(status);
        }
      },
    );
  }

  void _onChannelStatus(ConnectionStatus status) {
    _channelUp = status == ConnectionStatus.online;
    emit(state.copyWith(connection: status));
    if (_channelUp) {
      _resubscribe?.cancel();
      _resubscribe = null;
      _resubscribeDelay = _firstResubscribe;
      // Covers the first subscribe and every reconnect.
      unawaited(resync());
    } else {
      _resubscribe ??= Timer(_resubscribeDelay, () => unawaited(_rewatch()));
    }
  }

  Future<void> _rewatch() async {
    _resubscribe = null;
    if (isClosed || _channelUp) {
      return;
    }
    final doubled = _resubscribeDelay * 2;
    _resubscribeDelay = doubled < _maxResubscribe ? doubled : _maxResubscribe;
    final previous = _unwatch;
    _watchGeneration++;
    await previous?.call();
    if (!isClosed && !_channelUp) {
      _watch();
    }
  }

  /// A reorder fires one event per row; reload once they settle.
  void _scheduleCatalogReload() {
    _catalogReload?.cancel();
    _catalogReload = Timer(
      const Duration(milliseconds: 200),
      () => unawaited(_reloadCatalog()),
    );
  }

  /// Ids of partner items the user has not looked at yet.
  Set<String> get fresh =>
      state.seen?.fresh(state.items.values, userId) ?? const {};

  /// Marks [ids] as looked at; ids that are not fresh are ignored.
  void markSeen(Set<String> ids) {
    if (state.seen case final seen?) {
      _setSeen(seen.marking(ids, state.items.values, userId));
    }
  }

  void _setSeen(SeenMark seen) {
    emit(state.copyWith(seen: seen));
    unawaited(_cache.saveSeen(seen));
  }

  /// Usuals for what is typed: at most 5, none already on the list.
  List<Usual> suggestionsFor(String text) =>
      suggestUsuals(state.usuals, state.items.values, text);

  /// The add sheet's rows for a typed entry, from the server.
  Future<List<Suggestion>> suggest(String text) => _repo.suggest(text);

  /// Usuals that are due and not on the list, at most 10.
  List<Usual> get dueUsuals => dueUsualsOf(state.usuals, state.items.values);

  AddResult addUsual(Usual usual) =>
      addEntry(Entry(usual.name, usual.quantity), source: AddSource.suggestion);

  /// Splits a dictated sentence on the server and adds each entry.
  /// Throws when the server can't be reached; nothing is added then.
  Future<List<AddResult>> addSpoken(String text) async {
    final entries = await _repo.splitSpoken(text);
    return [
      for (final entry in entries) addEntry(entry, source: AddSource.spoken),
    ];
  }

  AddResult addEntry(Entry entry, {AddSource source = AddSource.typed}) =>
      addParsed(
        ParsedEntry(name: entry.name, quantity: entry.quantity),
        source: source,
      );

  /// Adds [entry] with every field it has. A null store lets the server
  /// pick the remembered one, unless [noStore]: the user chose "Ohne
  /// Laden", so the store is cleared after the add. An item with the same
  /// name, brand and details already on the list is not added twice.
  /// [source] is how the user picked it, for analytics.
  AddResult addParsed(
    ParsedEntry entry, {
    bool noStore = false,
    AddSource source = AddSource.typed,
  }) {
    final name = entry.name.trim();
    if (name.isEmpty) {
      return const NothingToAdd();
    }
    final key = _sameItem(name, entry.brand, entry.properties);
    for (final item in state.items.values) {
      if (item.status == ItemStatus.active &&
          _sameItem(item.name, item.brand, item.properties) == key) {
        return AlreadyOnList(item);
      }
    }
    final now = _clock();
    final item = Item(
      id: const Uuid().v4(),
      name: name,
      quantity: entry.quantity,
      brand: entry.brand,
      properties: entry.properties,
      categoryId: entry.categoryId,
      storeId: noStore ? null : entry.storeId,
      status: ItemStatus.active,
      createdAt: now,
      updatedAt: now,
    );
    _enqueue(AddItem(item));
    if (noStore) {
      _enqueue(EditItem(item.id, const ItemChanges(storeId: SetTo(null))));
    }
    _track('item_added', {'source': source.name, ..._actor()});
    return Added(item);
  }

  /// Details in any order: "Größe 3, sensitiv" is "sensitiv, Größe 3".
  static String _sameItem(String name, String? brand, String? properties) => [
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

  void tick(String id) {
    final active = state.items[id]?.status == ItemStatus.active;
    _enqueue(SetStatus(id, ItemStatus.bought, _clock()));
    if (active) {
      _track('item_ticked', _actor());
    }
  }

  /// Puts a ticked item back: no analytics event.
  void untick(String id) =>
      _enqueue(SetStatus(id, ItemStatus.active, _clock()));

  /// Puts a bought item from "recently used" back on the list: an add, or
  /// the tick's undo within [undoWindow] of the tick (job 29b: the tick has
  /// no undo snackbar any more), which sends nothing, as `suggest_items`
  /// does not count it as a purchase.
  void readd(String id) {
    final item = state.items[id];
    final bought = item?.status == ItemStatus.bought;
    final boughtAt = item?.boughtAt;
    final undo =
        boughtAt != null && _clock().difference(boughtAt) <= undoWindow;
    untick(id);
    if (bought && !undo) {
      _track('item_added', {'source': AddSource.suggestion.name, ..._actor()});
    }
  }

  /// How long after a tick a re-add counts as its undo.
  static const undoWindow = Duration(minutes: 10);

  /// Writes only what [changes] holds; nothing when it holds nothing.
  void edit(String id, ItemChanges changes) {
    if (!changes.isEmpty) {
      _enqueue(EditItem(id, changes));
    }
  }

  /// To the end of group ([storeId], [categoryId]); a null store is no store.
  void move(
    String id, {
    required String categoryId,
    required String? storeId,
  }) => _enqueue(MoveItem(id, categoryId: categoryId, storeId: storeId));

  /// Directly before or after [anchorId], in the anchor's group. Shows it
  /// there at once, halfway between the anchor and its neighbour.
  void place(String id, {required String anchorId, required Edge edge}) {
    final items = state.items;
    final anchor = items[anchorId];
    final categoryId = anchor?.categoryId;
    if (anchor == null || categoryId == null || anchorId == id) {
      return;
    }
    final group = [
      for (final item in items.values)
        if (item.id != id &&
            item.status == ItemStatus.active &&
            item.storeId == anchor.storeId &&
            item.categoryId == categoryId)
          item,
    ]..sort(compareWalk);
    _enqueue(
      PlaceItem(
        id,
        anchorId: anchorId,
        edge: edge,
        categoryId: categoryId,
        storeId: anchor.storeId,
        sortKey: placeKey(group, anchor, edge),
      ),
    );
  }

  void delete(String id) => _enqueue(DeleteItem(id));

  /// The UI showed [DedupeHint]s once.
  void hintShown() => _track('dedupe_hint_shown', _actor());

  /// The hint went away without a merge.
  void hintIgnored() => _track('dedupe_hint_ignored', _actor());

  /// Folds the hint's new item into the open one: the open item keeps its
  /// text, the quantities merge (`public.merge_quantities`), the new item
  /// goes. Null, with a [MergeRefused], when an item is gone or ticked by now
  /// or the merged quantity would not fit.
  Merge? merge(DedupeHint hint) {
    final items = state.items;
    final kept = items[hint.onList.id];
    final other = items[hint.added.id];
    if (kept == null ||
        other == null ||
        kept.status != ItemStatus.active ||
        other.status != ItemStatus.active) {
      _report(MergeRefused(hint.onList.name));
      return null;
    }
    final String quantity;
    try {
      quantity = mergeQuantities(kept.quantity, other.quantity);
    } on QuantityTooLong {
      _report(MergeRefused(kept.name));
      return null;
    }
    final op = MergeItems(
      kept.id,
      mergeId: const Uuid().v4(),
      otherId: other.id,
      quantity: quantity,
      brand: kept.brand ?? other.brand,
      properties: kept.properties ?? other.properties,
    );
    _enqueue(op);
    _track('dedupe_hint_merged', _actor());
    return Merge(
      op.mergeId,
      kept: kept,
      merged: other,
      result: op.apply(kept)!,
    );
  }

  /// Puts both items back as they were before [merge].
  void unmerge(Merge merge) => _enqueue(
    UnmergeItems(
      merge.kept.id,
      mergeId: merge.id,
      kept: merge.kept,
      merged: merge.merged,
    ),
  );

  /// Puts a deleted item back, keeping its id, category and place.
  void restore(Item item) => _enqueue(
    AddItem(
      item.copyWith(status: ItemStatus.active, boughtAt: () => null),
      restored: true,
    ),
  );

  /// Folds or unfolds the section [key] (a store id, or [noStoreKey]).
  void toggleFold(String key) {
    final folded = {...state.prefs.folded};
    if (!folded.remove(key)) {
      folded.add(key);
    }
    _setPrefs(state.prefs.copyWith(folded: folded));
  }

  void dismissHint() => _setPrefs(state.prefs.copyWith(hintDismissed: true));

  void _setPrefs(ListPrefs prefs) {
    emit(state.copyWith(prefs: prefs));
    unawaited(_cache.savePrefs(prefs));
  }

  Future<void> renameCategory(String id, String name) => _changeCatalog(
    state.catalog.withName(id, name),
    () => _repo.renameCategory(id, name),
    taken: NameTaken(name),
  );

  Future<void> createCategory(String name) => _changeCatalog(
    null,
    () => _repo.createCategory(name),
    taken: NameTaken(name),
  );

  /// The household's store named [name] (any case or spacing), created after
  /// the others when there is none, so that creating and picking a store is
  /// one step. Null when there is no name or it could not be saved; the user
  /// is told why. Not queued like item writes: offline it is refused.
  Future<Store?> addStore(String name) async {
    final clean = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.isEmpty) {
      return null;
    }
    if (state.catalog.storeNamed(clean) case final existing?) {
      return existing;
    }
    if (state.connection == ConnectionStatus.offline) {
      _report(const StoreNeedsConnection());
      return null;
    }
    final String id;
    try {
      id = await _repo.addStore(clean);
    } on Object {
      _report(const CatalogRejected());
      await _reloadCatalog();
      return null;
    }
    // Someone else may have made it a moment ago, under another spelling.
    final store =
        state.catalog.store(id) ??
        Store(
          id: id,
          name: clean,
          sortOrder: (state.catalog.stores.lastOrNull?.sortOrder ?? 0) + 10,
        );
    if (state.catalog.store(id) == null) {
      emit(state.copyWith(catalog: state.catalog.withStore(store)));
    }
    unawaited(_reloadCatalog());
    return store;
  }

  /// Whether the server took it.
  Future<bool> renameStore(String id, String name) {
    final clean = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    return _changeStores(
      state.catalog.withStoreName(id, clean),
      () => _repo.renameStore(id, clean),
      taken: StoreNameTaken(clean),
    );
  }

  /// Its items fall back to no store on the server; a resync brings them.
  Future<bool> deleteStore(String id) async {
    final saved = await _changeStores(
      state.catalog.withoutStore(id),
      () => _repo.deleteStore(id),
    );
    if (saved) {
      await resync();
    }
    return saved;
  }

  Future<bool> _changeStores(
    Catalog optimistic,
    Future<void> Function() write, {
    Rejected? taken,
  }) async {
    if (state.connection == ConnectionStatus.offline) {
      _report(const StoreNeedsConnection());
      return false;
    }
    return await _changeCatalog(optimistic, write, taken: taken);
  }

  Future<void> reorderCategories(List<String> ids) async {
    final before = [
      for (final s in walkingOrder(state.catalog, null)) s.category.id,
    ];
    if (await _changeOrder(
          state.catalog.withRouteOrder(ids),
          () => _repo.reorderCategories(ids),
        ) &&
        !listEquals(before, ids)) {
      _track('category_reordered', {'scope': ReorderScope.route.wire});
    }
  }

  Future<void> reorderStores(List<String> ids) async {
    final before = [for (final s in state.catalog.stores) s.id];
    if (await _changeOrder(
          state.catalog.withStoreOrder(ids),
          () => _repo.reorderStores(ids),
        ) &&
        !listEquals(before, ids)) {
      _track('store_reordered');
    }
  }

  /// Items move on the server; a resync brings them over.
  Future<void> deleteCategory(String id, {String? reassignTo}) async {
    await _changeCatalog(
      null,
      () => _repo.deleteCategory(id, reassignTo: reassignTo),
    );
    await resync();
  }

  /// Also hides or shows categories; only a changed order counts as a
  /// reorder for analytics.
  Future<void> setStoreLayout(
    String storeId,
    List<String> orderedIds,
    Set<String> hiddenIds,
  ) async {
    final before = [
      for (final s in walkingOrder(state.catalog, storeId)) s.category.id,
    ];
    if (await _changeOrder(
          state.catalog.withStoreLayout(storeId, orderedIds, hiddenIds),
          () => _repo.setStoreLayout(storeId, orderedIds, hiddenIds),
        ) &&
        !listEquals(before, orderedIds)) {
      _track('category_reordered', {'scope': ReorderScope.store.wire});
    }
  }

  /// Orders are not queued like item writes: offline, the change is refused
  /// with a message instead of showing an order no one else will see.
  /// Whether the server took it.
  Future<bool> _changeOrder(
    Catalog optimistic,
    Future<void> Function() write,
  ) async {
    if (state.connection == ConnectionStatus.offline) {
      _report(const NeedsConnection());
      return false;
    }
    return await _changeCatalog(optimistic, write);
  }

  /// Shows [optimistic] at once, writes, then reloads the catalog. A failed
  /// write is reported and undone, and the reload brings the server's state.
  /// Whether the write went through.
  Future<bool> _changeCatalog(
    Catalog? optimistic,
    Future<void> Function() write, {
    Rejected? taken,
  }) async {
    final before = state.catalog;
    if (optimistic != null) {
      emit(state.copyWith(catalog: optimistic));
    }
    var saved = true;
    try {
      await write();
    } on Object catch (e) {
      saved = false;
      if (optimistic != null && identical(state.catalog, optimistic)) {
        emit(state.copyWith(catalog: before));
      }
      _report(
        e is RejectedOp && e.nameTaken && taken != null
            ? taken
            : const CatalogRejected(),
      );
    }
    await _reloadCatalog();
    return saved;
  }

  void _track(String event, [Map<String, Object> properties = const {}]) =>
      analytics?.track(event, properties);

  /// The acting user's role and the household's size, as far as the
  /// catalog knows them.
  Map<String, Object> _actor() {
    final members = state.catalog.members;
    final role = members.where((m) => m.id == userId).firstOrNull?.role;
    return {
      if (role == 'owner' || role == 'member') 'actor_role': role!,
      if (members.isNotEmpty && members.length <= 100)
        'household_size': members.length,
    };
  }

  void _report(Rejected rejection) {
    if (!_rejections.isClosed) {
      _rejections.add(rejection);
    }
  }

  Future<void> resync() async {
    final acked = <String, Item?>{};
    _resyncAcks.add(acked);
    try {
      final (catalog, rows) = await (
        _repo.fetchCatalog(),
        _repo.fetchItems(),
      ).wait;
      final snapshot = {for (final row in rows) row.id: row};
      for (final MapEntry(:key, :value) in acked.entries) {
        if (value == null) {
          snapshot.remove(key);
        } else {
          snapshot[key] = value;
        }
      }
      emit(
        state.copyWith(
          catalog: catalog,
          server: snapshot,
          loaded: true,
          connection: _channelUp ? ConnectionStatus.online : null,
        ),
      );
      if (state.seen == null && _seenLoaded) {
        // A first start: what is on the list already is not news.
        final created = [for (final row in snapshot.values) row.createdAt]
          ..sort();
        _setSeen(SeenMark(until: created.lastOrNull));
      }
      _usualsReload?.cancel();
      unawaited(_refreshUsuals());
    } on Object {
      _goOffline();
    } finally {
      _resyncAcks.remove(acked);
    }
    unawaited(_flush());
  }

  /// A failure keeps the usuals there are; it says nothing about the list.
  Future<void> _refreshUsuals() async {
    try {
      final usuals = await _repo.fetchUsuals();
      emit(state.copyWith(usuals: usuals));
    } on Object {
      return;
    }
  }

  Future<void> _reloadCatalog() async {
    try {
      // Await first: `state` read before the await would be stale by now.
      final catalog = await _repo.fetchCatalog();
      emit(state.copyWith(catalog: catalog));
    } on Object {
      _goOffline();
    }
  }

  void _enqueue(ItemOp op) {
    emit(state.copyWith(pending: [...state.pending, op]));
    unawaited(_flush());
  }

  Future<void> _flush() async {
    if (_flushing) {
      return;
    }
    _flushing = true;
    try {
      while (state.pending.isNotEmpty && !isClosed) {
        final op = state.pending.first;
        try {
          _ack(op, await _repo.send(op));
        } on RejectedOp {
          _drop(op);
          _report(
            op is MergeItems
                ? MergeRefused(_nameOf(op))
                : ItemRejected(_nameOf(op)),
          );
          unawaited(resync());
        } on Object {
          _goOffline();
          return;
        }
      }
    } finally {
      _flushing = false;
    }
  }

  void _ack(ItemOp op, Map<String, Item?> rows) {
    for (final acked in _resyncAcks) {
      acked.addAll(rows);
    }
    final row = rows[op.itemId];
    // Job 32a: how the server categorized a new add, once per add (an op is
    // acknowledged once, also after a retry whose first answer was lost).
    if (op case AddItem(restored: false)) {
      if (row?.categorizedVia case final via?
          when categorizedVia.contains(via)) {
        _track('item_categorized', {'via': via});
      }
    }
    var server = state.server;
    for (final MapEntry(:key, :value) in rows.entries) {
      server = value == null
          ? ({...server}..remove(key))
          : mergeServerRow(server, value);
    }
    emit(
      state.copyWith(
        server: server,
        pending: [...state.pending.where((p) => !identical(p, op))],
        connection: ConnectionStatus.online,
      ),
    );
    // Job 32b: once the server has keyed a new add, name an open item that
    // is another spelling of it (the add itself went through).
    if (op case AddItem(restored: false)) {
      final added = state.items[op.itemId];
      if (added != null && added.status == ItemStatus.active) {
        final similar = similarItems(added, state.items.values);
        if (similar.isNotEmpty && !_hints.isClosed) {
          _hints.add(DedupeHint(added, similar.first));
        }
      }
    }
  }

  void _drop(ItemOp op) => emit(
    state.copyWith(pending: [...state.pending.where((p) => !identical(p, op))]),
  );

  String _nameOf(ItemOp op) => switch (op) {
    AddItem(:final item) => item.name,
    EditItem(changes: ItemChanges(:final name?)) => name,
    _ => state.server[op.itemId]?.name ?? '',
  };

  void _setServer(Map<String, Item> server) =>
      emit(state.copyWith(server: server));

  void _goOffline() {
    emit(state.copyWith(connection: ConnectionStatus.offline));
    _retry ??= Timer(const Duration(seconds: 3), () {
      _retry = null;
      if (!isClosed) {
        unawaited(resync());
      }
    });
  }

  /// Saves what a restart needs: a change to the queue at once, since the
  /// app may be killed right after a tap, and server churn once it settles.
  /// Not on close: the list closes on sign-out and household switches, which
  /// drop the cache.
  @override
  void onChange(Change<ListState> change) {
    super.onChange(change);
    final next = change.nextState;
    final before = change.currentState;
    if (!identical(next.server, before.server) &&
        !setEquals(_activeNames(next.server), _activeNames(before.server))) {
      _usualsReload?.cancel();
      _usualsReload = Timer(
        const Duration(milliseconds: 1500),
        () => unawaited(_refreshUsuals()),
      );
    }
    if (!next.loaded) {
      return;
    }
    if (!identical(next.pending, before.pending)) {
      _save?.cancel();
      _saveNow(next);
    } else if (!identical(next.catalog, before.catalog) ||
        !identical(next.server, before.server) ||
        !identical(next.usuals, before.usuals)) {
      _save?.cancel();
      _save = Timer(const Duration(milliseconds: 300), () => _saveNow(state));
    }
  }

  void _saveNow(ListState state) => unawaited(
    _cache.save(
      ListSnapshot(
        catalog: state.catalog,
        server: [...state.server.values],
        pending: state.pending,
        usuals: state.usuals,
      ),
    ),
  );

  static Set<String> _activeNames(Map<String, Item> server) => {
    for (final item in server.values)
      if (item.status == ItemStatus.active) item.name.toLowerCase(),
  };

  // Fetches and acks can land after the screen is gone.
  @override
  void emit(ListState state) {
    if (!isClosed) {
      super.emit(state);
    }
  }

  @override
  Future<void> close() async {
    _retry?.cancel();
    _resubscribe?.cancel();
    _catalogReload?.cancel();
    _save?.cancel();
    _usualsReload?.cancel();
    await _unwatch?.call();
    await _rejections.close();
    await _hints.close();
    await super.close();
  }
}

import 'dart:async';
import 'dart:math';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/analytics/events.dart';
import 'package:family_groceries/app/network.dart';
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

  /// A resync since the list started is over, answered or not; before,
  /// [server] is the device's copy and the server may know more.
  final bool resynced = false,
  final ConnectionStatus connection = ConnectionStatus.connecting,

  /// The server answers, but a send or fetch failed with a [ServerTrouble]
  /// and so did one started after the 3 s retry.
  final bool failing = false,

  /// What the household buys again and again, best first.
  final List<Usual> usuals = const [],

  /// Null until loaded from the device or, on a first start, set by the
  /// first resync.
  final SeenMark? seen,

  /// Folded stores and the dismissed explainer, from the device.
  final ListPrefs prefs = const ListPrefs(),
}) {
  Map<String, Item> get items => visibleItems(server, pending);

  /// What keeps the list from syncing, if anything; offline wins.
  SyncTrouble? get trouble => connection == ConnectionStatus.offline
      ? SyncTrouble.offline
      : failing
      ? SyncTrouble.failing
      : null;

  ListState copyWith({
    Catalog? catalog,
    Map<String, Item>? server,
    List<ItemOp>? pending,
    bool? loaded,
    bool? resynced,
    ConnectionStatus? connection,
    bool? failing,
    List<Usual>? usuals,
    SeenMark? seen,
    ListPrefs? prefs,
  }) => ListState(
    catalog: catalog ?? this.catalog,
    server: server ?? this.server,
    pending: pending ?? this.pending,
    loaded: loaded ?? this.loaded,
    resynced: resynced ?? this.resynced,
    connection: connection ?? this.connection,
    failing: failing ?? this.failing,
    usuals: usuals ?? this.usuals,
    seen: seen ?? this.seen,
    prefs: prefs ?? this.prefs,
  );
}

enum SyncTrouble() {
  /// The device has no connection to the server.
  offline,

  /// The server answers with errors (5xx, a database timeout).
  failing,
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

/// A rename onto [name], which is open already, could not be merged into it
/// (the merged quantity would be too long, or the server found the copy
/// first). The item keeps its old name.
final class const RenameTaken(final String name) extends Rejected;

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

/// What the user did on the list that the store rating prompt counts
/// (job 155). Never a retry, a realtime echo or a restore.
sealed class const ListActivity();

/// The user added an item (`item_added`).
final class const OwnItemAdded() extends ListActivity;

/// The user's tick left no item on the list; [ticked] is how many items
/// they ticked since it last had none.
final class const TripCompleted(final int ticked) extends ListActivity;

const _maxResubscribe = Duration(seconds: 30);

/// How long the OS's network stays up before the list reconnects: a
/// network that flaps reconnects once, after the last change.
const networkSettle = Duration(milliseconds: 1500);

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

  /// The OS's network: down shows the list offline at once, back up for
  /// [networkSettle] retries at once. Without it, or when it says up while
  /// the server is out of reach, the list's own requests tell.
  Stream<Network>? network,
}) extends Cubit<ListState> {
  this : super(const ListState());

  final DateTime Function() _clock = clock ?? DateTime.now;
  final _networkChanges = network;
  StreamSubscription<Network>? _network;
  Timer? _networkBack;

  /// Whether the OS's network went down and has not been back for
  /// [networkSettle] since.
  var _networkDown = false;

  /// Whether the channel said up when the network went down and has said
  /// nothing since: its socket may have died with the network, unnoticed
  /// until a heartbeat goes unanswered (25 to 50 s).
  var _channelSuspect = false;
  final _rejections = StreamController<Rejected>.broadcast();
  final _hints = StreamController<DedupeHint>.broadcast();
  final _renameMerges = StreamController<Merge>.broadcast();
  final _activity = StreamController<ListActivity>.broadcast();

  /// The items this user ticked since the list last had no open item; an
  /// untick and a tick again count the item once.
  final _tripTicked = <String>{};

  /// When this user's tick last completed a trip.
  DateTime? _tripDoneAt;

  /// Renames sent again after a refusal; a second refusal is final.
  final _resentRenames = Set<EditItem>.identity();

  /// The rename each rename fold stands for, sent alone if the merge is
  /// refused (the copy was ticked or deleted meanwhile).
  final _foldedRenames = Map<MergeItems, EditItem>.identity();

  /// Folds of refused renames, announced once the server merged them: the
  /// fold happens long after the edit, and its merge may still be refused
  /// (then the rename goes alone and there is nothing to undo).
  final _unannounced = Map<MergeItems, Merge>.identity();
  Future<void> Function()? _unwatch;
  Timer? _retry;

  /// Retry rounds: one per firing of [_retry] and per [retry]. Job 165
  /// (Z104): one transient [ServerTrouble] (a 503, a token refreshed mid
  /// request) is no failing server; failing shows only once a request
  /// started after the retry fails too. Requests of one round fail together
  /// (a resync's two fetches, a write sent before the retry), so a counter
  /// of failures would escalate on one outage.
  var _round = 0;

  /// The round of the first [ServerTrouble] not shown yet.
  int? _troubleRound;
  Timer? _catalogReload;
  Timer? _save;
  Timer? _usualsReload;

  /// The send loop in flight: a second flush joins it.
  Future<void>? _flushRun;

  /// What each resync in flight heard since it started; it beats the
  /// snapshot, which may have been read before. Resyncs overlap (the opening
  /// one and the channel's first subscribe).
  final _resyncsHeard = <_Heard>{};

  /// Resyncs started, and the latest one the list shows: one that started
  /// earlier and answers after it would put older rows back.
  var _resyncsStarted = 0;
  var _resyncShown = 0;

  /// Items heard deleted over realtime: the delete's commit time, or the
  /// newest row known then when that is later (a payload without a commit
  /// time reads as 1970). A row no newer than that is from before the
  /// delete: its `updated_at` is its transaction's start.
  final _gone = <String, DateTime>{};

  /// Ids heard over realtime while the op being sent is in flight; its
  /// answer may have read the row before them.
  Set<String>? _heardInFlight;

  /// The ids of the last snapshot shown while that op was in flight. A row
  /// its answer brings that the snapshot lacked may be from before a delete
  /// realtime missed: the row shows, and another resync settles it.
  Set<String>? _shownInFlight;

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

  /// Set as [close] starts: `isClosed` turns true only once it has
  /// awaited the channel and the network, and a cache read or a rewatch may
  /// resume in between.
  var _closing = false;

  /// Whether the device cache was read: a resync sets the first seen mark
  /// only then, and only then may a save before the first load replace it.
  var _cacheRead = false;

  Stream<Rejected> get rejections => _rejections.stream;

  /// A new add of something already open under another spelling, once its
  /// add is acknowledged (the server sets the canonical key). Never for a
  /// restore, a retry or a partner's add.
  Stream<DedupeHint> get hints => _hints.stream;

  /// Job 104: an edit renamed an item to another open item (the same name,
  /// brand and details, in any case or spacing), so it was folded into that
  /// one. The UI says so, with an undo.
  Stream<Merge> get renameMerges => _renameMerges.stream;

  Stream<ListActivity> get activity => _activity.stream;

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
    _cacheRead = true;
    if (_closing) {
      return;
    }
    _network = _networkChanges?.listen(_onNetwork);
    _watch();
    unawaited(resync());
  }

  void _watch() {
    final generation = ++_watchGeneration;
    bool current() => generation == _watchGeneration && !isClosed;
    _unwatch = _repo.watch(
      onItem: (row) {
        if (current()) {
          _noteDuringResyncs({row.id: row}, answered: false);
          _heardInFlight?.add(row.id);
          _setServer(mergeServerRow(state.server, row));
          // A new member: reload so the title can name them.
          if (row.addedBy != null &&
              state.catalog.member(row.addedBy) == null) {
            _scheduleCatalogReload();
          }
        }
      },
      onItemDeleted: (id, at) {
        if (current()) {
          _noteDuringResyncs({id: null}, answered: false);
          final known = state.server[id];
          // Another household's deletes come too; only ours can be late.
          if (known != null || state.pending.any((op) => op.itemId == id)) {
            _gone[id] = known != null && known.updatedAt.isAfter(at)
                ? known.updatedAt
                : at;
          }
          if (known != null) {
            _setServer({...state.server}..remove(id));
          }
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
    _channelSuspect = false;
    if (status == ConnectionStatus.offline) {
      _troubleRound = null;
    }
    // Offline says nothing of the server: back online, the next send or
    // fetch tells again, so the failing card never flashes up in between.
    emit(
      state.copyWith(
        connection: status,
        failing: status == ConnectionStatus.offline ? false : null,
      ),
    );
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

  void _onNetwork(Network network) {
    _networkBack?.cancel();
    _networkBack = null;
    switch (network) {
      case Network.down:
        _networkDown = true;
        if (_channelUp) {
          // Until it joins again, a resync that answers does not bring the
          // list online.
          _channelUp = false;
          _channelSuspect = true;
        }
        _goOffline();
      case Network.up when _networkDown:
        _networkBack = Timer(networkSettle, _reconnect);
      case Network.up:
        break;
    }
  }

  /// The network is back: subscribe and fetch now, not when the backoff and
  /// the 3 s retry come due. A suspect channel gets a new socket.
  void _reconnect() {
    _networkBack = null;
    _networkDown = false;
    if (_channelSuspect) {
      _channelSuspect = false;
      _repo.renewRealtime();
    } else if (!_channelUp) {
      _resubscribe?.cancel();
      _resubscribeDelay = _firstResubscribe;
      unawaited(_rewatch());
    }
    unawaited(retry());
  }

  Future<void> _rewatch() async {
    _resubscribe = null;
    if (_closing || _channelUp) {
      return;
    }
    final doubled = _resubscribeDelay * 2;
    _resubscribeDelay = doubled < _maxResubscribe ? doubled : _maxResubscribe;
    final previous = _unwatch;
    _unwatch = null;
    // A reconnect may start another rewatch while this one waits; the
    // later one subscribes.
    final generation = ++_watchGeneration;
    await previous?.call();
    if (!_closing && !_channelUp && generation == _watchGeneration) {
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

  /// Usuals used in the last 30 days, not due and not on the list, the
  /// latest first: after the due ones, up to 10 rows in all.
  List<Usual> get recentUsuals => recentUsualsOf(
    state.usuals,
    state.items.values,
    _clock(),
    limit: max(0, 10 - dueUsuals.length),
  );

  AddResult addUsual(Usual usual) =>
      addEntry(Entry(usual.name, usual.quantity), source: AddSource.suggestion);

  /// Splits a dictated sentence on the server and adds each entry.
  /// Throws when the server can't be reached; nothing is added then.
  /// `truncated`: the sentence held more items than the server takes at
  /// once; only the first ones were added.
  Future<({List<AddResult> results, bool truncated})> addSpoken(
    String text,
  ) async {
    final (:entries, :truncated) = await _repo.splitSpoken(text);
    return (
      results: [
        for (final entry in entries)
          addParsed(entry, autoCategory: true, source: AddSource.spoken),
      ],
      truncated: truncated,
    );
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
  /// [source] is how the user picked it, for analytics. [autoCategory]: the
  /// entry's category is the server's guess, not the user's pick.
  AddResult addParsed(
    ParsedEntry entry, {
    bool noStore = false,
    bool autoCategory = false,
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
    _enqueue(
      AddItem(
        item,
        noStore: noStore,
        deviceParsed: entry.deviceParsed,
        autoCategory: autoCategory,
      ),
    );
    _track('item_added', {'source': source.name, ..._actor()});
    _tell(const OwnItemAdded());
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
    // Counted before the enqueue, whose emptied list resets the count.
    if (active) {
      _tripTicked.add(id);
    }
    final ticked = _tripTicked.length;
    _enqueue(SetStatus(id, ItemStatus.bought, _clock()));
    if (active) {
      _track('item_ticked', _actor());
      final now = _clock();
      // Emptied again within the undo window (a re-add from "recently used"
      // ticked off again): the same trip, not a second one.
      final again = switch (_tripDoneAt) {
        final done? => now.difference(done) <= undoWindow,
        null => false,
      };
      if (!_hasOpenItem(state.items) && !again) {
        _tripDoneAt = now;
        _tell(TripCompleted(ticked));
      }
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
      _tell(const OwnItemAdded());
    }
  }

  /// How long after a tick a re-add counts as its undo.
  static const undoWindow = Duration(minutes: 10);

  /// Writes only what [changes] holds; nothing when it holds nothing.
  /// A rename to an item that is open already merges into that item, as the
  /// duplicate hint's Zusammenführen does: it keeps its name, store and
  /// category, and the quantities add up.
  void edit(String id, ItemChanges changes) {
    if (changes.isEmpty) {
      return;
    }
    final item = state.items[id];
    // The add's line is parsed when it syncs; so is its new name.
    final deviceParsed =
        changes.name != null &&
        state.pending.any(
          (op) => op is AddItem && op.itemId == id && op.deviceParsed,
        );
    if (item != null) {
      if (_openCopy(item, changes, state.items) case final onList?) {
        final rename = EditItem(
          id,
          changes,
          keyBefore: item.canonicalKey,
          deviceParsed: deviceParsed,
        );
        if (_renameOnto(item, rename, onList) case final ops?) {
          emit(state.copyWith(pending: [...state.pending, ...ops]));
          unawaited(_flush());
        }
        return;
      }
    }
    _enqueue(
      EditItem(
        id,
        changes,
        keyBefore: changes.name == null ? null : item?.canonicalKey,
        deviceParsed: deviceParsed,
      ),
    );
  }

  /// The other open item of [items] that [item] would be once [changes]
  /// rename it.
  Item? _openCopy(Item item, ItemChanges changes, Map<String, Item> items) {
    if (item.status != ItemStatus.active || !changes.renames) {
      return null;
    }
    final edited = changes.apply(item);
    final key = _sameItem(edited.name, edited.brand, edited.properties);
    return items.values
        .where(
          (other) =>
              other.id != item.id &&
              other.status == ItemStatus.active &&
              _sameItem(other.name, other.brand, other.properties) == key,
        )
        .firstOrNull;
  }

  /// The server refused [refused] for an open copy the list did not show
  /// yet (another phone's rename or add, or a rename made offline). Once a
  /// resync shows the copy, the item folds into it as [edit] would have, and
  /// what was queued after the rename goes to the copy, as for an add that
  /// turned out to be an open item. A delete queued after it wins: the
  /// rename is dropped and the delete removes this item, so the copy keeps
  /// its quantity. A rename queued after it wins too: the item keeps the
  /// other changes (brand and details included) and takes that name. The
  /// rename stays shown until then. A name typed offline is compared as the
  /// server parsed it. False, with [refused] still queued, when the resync
  /// or the parse failed.
  Future<bool> _foldRefusedRename(EditItem refused) async {
    if (!await resync()) {
      return false;
    }
    final EditItem op;
    if (refused.deviceParsed) {
      final round = _round;
      try {
        final parsed = await _repo.parse(refused.changes.name!);
        op = EditItem(
          refused.itemId,
          parsed.ontoRename(refused.changes),
          keyBefore: refused.keyBefore,
        );
      } on ServerTrouble {
        _goFailing(round);
        return false;
      } on Object {
        _goOffline();
        return false;
      }
    } else {
      op = refused;
    }
    _drop(refused);
    final server = state.server;
    final item = server[op.itemId];
    if (item == null) {
      return true;
    }
    if (state.pending.any((p) => p is DeleteItem && p.itemId == op.itemId)) {
      return true;
    }
    final later = state.pending
        .whereType<EditItem>()
        .where((p) => p.itemId == op.itemId && p.changes.renames)
        .firstOrNull;
    if (later != null) {
      // Brand and details ride with the later rename, which may set its own
      // (a name typed offline always does, once parsed); sent with the old
      // name they could be refused again.
      final renamed = EditItem(
        op.itemId,
        ItemChanges.fromColumns({
          if (!later.deviceParsed) ...{
            if (op.changes.brand case SetTo(:final value)) 'brand': value,
            if (op.changes.properties case SetTo(:final value))
              'properties': value,
          },
          ...later.changes.toColumns(),
        }),
        keyBefore: later.keyBefore,
        deviceParsed: later.deviceParsed,
      );
      final rest = ItemChanges(
        quantity: op.changes.quantity,
        categoryId: op.changes.categoryId,
        storeId: op.changes.storeId,
      );
      emit(
        state.copyWith(
          pending: [
            if (!rest.isEmpty) EditItem(op.itemId, rest),
            for (final p in state.pending)
              if (identical(p, later)) renamed else p,
          ],
        ),
      );
      return true;
    }
    final onList = _openCopy(item, op.changes, server);
    if (onList == null) {
      // Ticked, or the copy went, since the refusal: the rename fits now.
      // Sent once more only: the server's folding can differ from
      // [foldName] (Postgres lowercases letters Dart leaves alone).
      _resend(op);
      return true;
    }
    if (_renameOnto(item, op, onList, announce: false) case final ops?) {
      emit(
        state.copyWith(
          pending: [
            ...ops,
            for (final p in state.pending) ?p.ontoKept(item.id, onList.id),
          ],
        ),
      );
    }
    return true;
  }

  void _resend(EditItem rename) {
    _resentRenames.add(rename);
    emit(state.copyWith(pending: [rename, ...state.pending]));
  }

  /// The ops that fold [item], edited by [rename], into [onList]. The
  /// amount typed in the same edit goes first, so the merge adds it up.
  /// Brand and details are [onList]'s already; sent on their own, they would
  /// be the refused rename again. Null, with a [RenameTaken], when the
  /// merged quantity would not fit.
  List<ItemOp>? _renameOnto(
    Item item,
    EditItem rename,
    Item onList, {
    bool announce = true,
  }) {
    final details = ItemChanges(quantity: rename.changes.quantity);
    final ({MergeItems op, Merge merge}) fold;
    try {
      fold = _fold(onList, details.apply(item));
    } on QuantityTooLong {
      _report(RenameTaken(onList.name));
      return null;
    }
    if (announce) {
      _renameMerges.add(fold.merge);
    } else {
      _unannounced[fold.op] = fold.merge;
    }
    _foldedRenames[fold.op] = rename;
    return [if (!details.isEmpty) EditItem(item.id, details), fold.op];
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
    final ({MergeItems op, Merge merge}) fold;
    try {
      fold = _fold(kept, other);
    } on QuantityTooLong {
      _report(MergeRefused(kept.name));
      return null;
    }
    _enqueue(fold.op);
    _track('dedupe_hint_merged', _actor());
    return fold.merge;
  }

  /// The op that folds [other] into [kept] and the merge the UI can undo.
  /// Throws [QuantityTooLong] when the merged quantity would not fit.
  ({MergeItems op, Merge merge}) _fold(Item kept, Item other) {
    final op = MergeItems(
      kept.id,
      mergeId: const Uuid().v4(),
      otherId: other.id,
      quantity: mergeQuantities(kept.quantity, other.quantity),
      brand: kept.brand ?? other.brand,
      properties: kept.properties ?? other.properties,
    );
    return (
      op: op,
      merge: Merge(
        op.mergeId,
        kept: kept,
        merged: other,
        result: op.apply(kept)!,
      ),
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
      noStore: item.storeId == null,
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

  /// Whether the server took it: another category's name, in any case or
  /// spacing, is refused.
  Future<bool> renameCategory(String id, String name) async {
    final clean = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    return await _changeCatalog(
      state.catalog.withName(id, clean),
      () => _repo.renameCategory(id, clean),
      taken: NameTaken(clean),
    );
  }

  /// Whether the server took it. A name the household has already, in any
  /// case or spacing, creates nothing there.
  Future<bool> createCategory(String name) async {
    final clean = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    return await _changeCatalog(
      null,
      () => _repo.createCategory(clean),
      taken: NameTaken(clean),
    );
  }

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
      if (role == 'owner' || role == 'admin' || role == 'member')
        'actor_role': role!,
      if (members.isNotEmpty && members.length <= 100)
        'household_size': members.length,
    };
  }

  void _tell(ListActivity activity) {
    if (!_activity.isClosed) {
      _activity.add(activity);
    }
  }

  static bool _hasOpenItem(Map<String, Item> items) =>
      items.values.any((i) => i.status == ItemStatus.active);

  void _report(Rejected rejection) {
    if (!_rejections.isClosed) {
      _rejections.add(rejection);
    }
  }

  /// False when the list could not be fetched.
  Future<bool> resync() async {
    final number = ++_resyncsStarted;
    final heard = _Heard();
    _resyncsHeard.add(heard);
    var fetched = true;
    final round = _round;
    try {
      final catalog = _repo.fetchCatalog();
      final rows = _repo.fetchItems();
      // Not a record `.wait`: its ParallelWaitError would hide a
      // ServerTrouble.
      await Future.wait([catalog, rows]);
      if (number > _resyncShown) {
        _resyncShown = number;
        _showSnapshot(await catalog, await rows, heard);
      }
      // With ops queued the next send decides: a server that fails every
      // write would otherwise flicker between failing and not.
      if (state.pending.isEmpty) {
        _clearTrouble();
      }
    } on ServerTrouble {
      fetched = false;
      _goFailing(round);
    } on Object {
      fetched = false;
      _goOffline();
    } finally {
      _resyncsHeard.remove(heard);
    }
    if (!state.resynced && !isClosed) {
      emit(state.copyWith(resynced: true));
    }
    unawaited(_flush());
    return fetched;
  }

  void _showSnapshot(Catalog catalog, List<Item> rows, _Heard heard) {
    final snapshot = {for (final row in rows) row.id: row};
    // An answered row the snapshot lacks: the snapshot was read before the
    // write, or after a delete realtime has not told (it may be down). The
    // row shows until another resync settles it.
    final unsure = heard.answered.any(
      (id) => heard.rows[id] != null && !snapshot.containsKey(id),
    );
    for (final MapEntry(:key, :value) in heard.rows.entries) {
      if (value == null) {
        snapshot.remove(key);
      } else {
        snapshot[key] = mergeServerRow(snapshot, value)[key]!;
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
    if (state.seen == null && _cacheRead) {
      // A first start: what is on the list already is not news.
      final created = [for (final row in snapshot.values) row.createdAt]
        ..sort();
      _setSeen(SeenMark(until: created.lastOrNull));
    }
    if (_heardInFlight != null) {
      _shownInFlight = {...snapshot.keys};
    }
    _usualsReload?.cancel();
    unawaited(_refreshUsuals());
    if (unsure) {
      unawaited(resync());
    }
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
    final round = _round;
    try {
      // Await first: `state` read before the await would be stale by now.
      final catalog = await _repo.fetchCatalog();
      emit(state.copyWith(catalog: catalog));
    } on ServerTrouble {
      _goFailing(round);
    } on Object {
      _goOffline();
    }
  }

  void _enqueue(ItemOp op) {
    emit(state.copyWith(pending: [...state.pending, op]));
    unawaited(_flush());
  }

  /// Retries now what the 3 s timer would retry later: a resync, then the
  /// queue. Whether the list syncs again.
  Future<bool> retry() async {
    _retry?.cancel();
    _retry = null;
    _round++;
    await resync();
    await _flush();
    return state.trouble == null;
  }

  Future<void> _flush() async {
    if (_flushRun case final run?) {
      await run;
      return;
    }
    final done = Completer<void>();
    _flushRun = done.future;
    var answered = false;
    try {
      while (state.pending.isNotEmpty && !isClosed) {
        final op = state.pending.first;
        final heard = _heardInFlight = {};
        _shownInFlight = null;
        final round = _round;
        try {
          _ack(op, await _repo.send(op), heard);
          _forget(op);
        } on RejectedOp catch (e) {
          answered = true;
          final resent = op is EditItem && _resentRenames.remove(op);
          if (op is EditItem && e.nameTaken && !resent) {
            if (await _foldRefusedRename(op)) {
              continue;
            }
            return;
          }
          _drop(op);
          if (op is MergeItems) {
            _unannounced.remove(op);
            if (_foldedRenames.remove(op) case final rename?) {
              _resend(rename);
              continue;
            }
          }
          _report(switch (op) {
            MergeItems() => MergeRefused(_nameOf(op)),
            EditItem() when e.nameTaken => RenameTaken(_nameOf(op)),
            _ => ItemRejected(_nameOf(op)),
          });
          unawaited(resync());
        } on ServerTrouble {
          _goFailing(round);
          return;
        } on Object {
          _goOffline();
          return;
        }
      }
      // A refusal can empty the queue with no write acknowledged (a rename
      // folded into "already on the list").
      if (answered && state.pending.isEmpty) {
        _clearTrouble();
      }
    } finally {
      _flushRun = null;
      done.complete();
      _heardInFlight = null;
      _shownInFlight = null;
    }
  }

  /// [heard]: ids realtime brought while [op] was in flight. An answer that
  /// one of them is gone may predate that row (an undone delete), and a
  /// later delete would come over realtime after it.
  void _ack(ItemOp op, Map<String, Item?> answer, Set<String> heard) {
    final rows = {
      for (final MapEntry(:key, :value) in answer.entries)
        if (value == null ? !heard.contains(key) : !_deletedSince(value))
          key: value,
    };
    _noteDuringResyncs(rows, answered: true);
    final shown = _shownInFlight;
    final unsure =
        shown != null &&
        rows.entries.any((e) => e.value != null && !shown.contains(e.key));
    final row = answer[op.itemId];
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
    // Job 64b: the add was on the list already as another item (an undone
    // delete, a replayed add); what is queued for this copy goes to it.
    final kept = op is AddItem && row == null
        ? answer.keys.where((id) => id != op.itemId).firstOrNull
        : null;
    emit(
      state.copyWith(
        server: server,
        pending: [
          for (final p in state.pending)
            if (!identical(p, op))
              ?(kept == null ? p : p.ontoKept(op.itemId, kept)),
        ],
        connection: ConnectionStatus.online,
        failing: false,
      ),
    );
    _troubleRound = null;
    // Job 104: a rename to another spelling or a synonym of an open item
    // (known once the server keyed the new name) is offered, as for an add,
    // never merged on its own. Only a new name gives a new key.
    if (op case EditItem(changes: ItemChanges(name: _?), :final keyBefore)) {
      final renamed = state.items[op.itemId];
      final onList =
          renamed == null ||
              renamed.status != ItemStatus.active ||
              renamed.canonicalKey == keyBefore
          ? null
          : similarItems(renamed, state.items.values).firstOrNull;
      if (renamed != null && onList != null && !_hints.isClosed) {
        _hints.add(DedupeHint(renamed, onList));
      }
    }
    if (unsure) {
      unawaited(resync());
    }
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

  bool _deletedSince(Item row) => switch (_gone[row.id]) {
    final at? => !row.updatedAt.isAfter(at),
    null => false,
  };

  /// Keeps the newer of two rows heard for one id; a gone item stays gone
  /// until a row comes after it.
  void _noteDuringResyncs(Map<String, Item?> rows, {required bool answered}) {
    for (final heard in _resyncsHeard) {
      for (final MapEntry(:key, :value) in rows.entries) {
        final known = heard.rows[key];
        final kept = value == null || known == null
            ? value
            : mergeServerRow({key: known}, value)[key];
        heard.rows[key] = kept;
        if (answered && kept != null && identical(kept, value)) {
          heard.answered.add(key);
        } else {
          heard.answered.remove(key);
        }
      }
    }
  }

  void _forget(ItemOp op) {
    switch (op) {
      case EditItem():
        _resentRenames.remove(op);
      case MergeItems():
        _foldedRenames.remove(op);
        if (_unannounced.remove(op) case final merge?) {
          _renameMerges.add(merge);
        }
      default:
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
    _troubleRound = null;
    emit(state.copyWith(connection: ConnectionStatus.offline, failing: false));
    _retryLater();
  }

  /// The server answered and nothing waits on it.
  void _clearTrouble() {
    _troubleRound = null;
    if (state.failing) {
      emit(state.copyWith(failing: false));
    }
  }

  void _goFailing(int round) {
    final first = _troubleRound ??= round;
    if (round > first) {
      emit(state.copyWith(failing: true));
    }
    _retryLater();
  }

  void _retryLater() {
    _retry ??= Timer(const Duration(seconds: 3), () {
      _retry = null;
      _round++;
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
    if (_tripTicked.isNotEmpty && !_hasOpenItem(next.items)) {
      _tripTicked.clear();
    }
    if (!identical(next.server, before.server) &&
        !setEquals(_activeNames(next.server), _activeNames(before.server))) {
      _usualsReload?.cancel();
      _usualsReload = Timer(
        const Duration(milliseconds: 1500),
        () => unawaited(_refreshUsuals()),
      );
    }
    final queued = !identical(next.pending, before.pending);
    // Before the first load only the queue is worth saving: an op made
    // offline on a first start, with no cached list to lose.
    if (!next.loaded && !(queued && _cacheRead)) {
      return;
    }
    if (queued) {
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
    _closing = true;
    _retry?.cancel();
    _networkBack?.cancel();
    _resubscribe?.cancel();
    _catalogReload?.cancel();
    _save?.cancel();
    _usualsReload?.cancel();
    await _network?.cancel();
    await _unwatch?.call();
    await _rejections.close();
    await _hints.close();
    await _renameMerges.close();
    await _activity.close();
    await super.close();
  }
}

/// What one resync heard while in flight: rows by id (null: gone), and the
/// ids whose row came in the answer to a write rather than over realtime.
final class _Heard() {
  final rows = <String, Item?>{};
  final answered = <String>{};
}

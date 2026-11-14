import 'dart:async';
import 'dart:convert';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/analytics/events.dart'
    show ShopAnswer, ShopMinutes;
import 'package:family_groceries/app/device_cache.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/trip/model.dart';
import 'package:family_groceries/trip/rules.dart';
import 'package:family_groceries/trip/summary.dart';
import 'package:family_groceries/trip/trip_repository.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

/// Where trip mode stands for the signed-in user in one household.
@immutable
sealed class const TripState();

/// No trip runs on this device: an own tick asks.
final class const NoTrip() extends TripState;

/// „Kaufst du gerade ein?“ is up after the tick of [item] (as it was
/// before) at [at] on [listId]; [snapshot] is that list's open items then.
final class const Asking({
  required final Item item,
  required final DateTime at,
  required final String? listId,
  required final Map<String, PlannedItem> snapshot,
}) extends TripState;

/// [trip] runs here (the strip shows); [lastTick] is its newest tick.
final class const Running(final RunningTrip trip, {final DateTime? lastTick})
    extends TripState;

/// How far the save of an ended trip got.
enum TripSave() {
  saving,
  saved,
  failed,

  /// The server refused it for good ([TripRefused]): not tried again.
  refused,
}

/// [trip] ended: the fresh summary page, or with [auto] the list's card
/// „Einkauf automatisch beendet“. [from] is the trip as it ran, for „Weiter
/// einkaufen“. Once [save] is [TripSave.saved], [trip] is the server's
/// answer, so without Premium its lines are null.
final class const Ended(
  final FinishedTrip trip, {
  required final RunningTrip from,
  required final bool auto,
  required final TripSave save,
}) extends TripState {
  bool get saved => save == TripSave.saved;

  /// This end with „War geplant“ [on] for line [key]; null without lines.
  Ended? marked(String key, {required bool on}) => switch (trip.lines) {
    final lines? => Ended(
      trip.withLines([
        for (final l in lines)
          if (l.key == key) l.withMarked(on) else l,
      ]),
      from: from,
      auto: auto,
      save: save,
    ),
    null => null,
  };
}

/// The user's trip runs in another household ([householdId]): here no
/// question and no strip.
final class const RunningElsewhere(final String householdId) extends TripState;

/// Trip mode (job 234) in one household for the signed-in user: the
/// question after each own tick, the running trip with its long-running
/// rule, and its end, saved to the server. The trip lives in
/// [DeviceCache] (per user, so one trip runs per user on the device) until
/// it ends and its end is saved.
class TripCubit(
  final ListCubit _list,
  final TripSessionRepository _repo,
  final DeviceCache _cache, {
  required final String userId,
  required final String householdId,

  /// The `trip-mode` flag: off, nothing asks, restores or saves.
  required final bool Function() enabled,

  /// The `grocery-log` flag: an end writes its Verlauf trips.
  required final bool Function() logs,
  final DateTime Function() clock = DateTime.now,
  final Analytics? analytics,
}) extends Cubit<TripState> {
  this : super(const NoTrip()) {
    _subscriptions = [
      _list.activity.listen((activity) {
        if (activity case OwnItemTicked(:final item)) {
          unawaited(_ticked(item));
        }
      }),
      _list.stream.listen((_) => _rule()),
    ];
  }

  /// How often the long-running rule runs while a trip runs.
  static const checkEvery = Duration(seconds: 30);

  late final List<StreamSubscription<Object?>> _subscriptions;
  Timer? _timer;

  /// This household's ends whose save has not gone through, by trip id.
  final _unsaved = <String, FinishedTrip>{};
  final _saving = <String>{};

  /// The running trip's last end ("Weiter einkaufen"): its marks carry over.
  FinishedTrip? _previous;

  /// Device writes, one after the other.
  Future<void> _writes = Future.value();

  /// Restores the trip from the device, retries unsaved ends and runs the
  /// rule. Call once the cubit is created.
  Future<void> start() => check();

  /// Brings the trip up to date: what the device keeps (a trip started or
  /// ended in another household), unsaved ends, the long-running rule. On
  /// app resume (after the list's own resume) and when the flag turns on.
  Future<void> check() async {
    if (!enabled() || isClosed) {
      return;
    }
    await _sync();
    for (final trip in [..._unsaved.values]) {
      unawaited(_save(trip));
    }
    if (state is Running) {
      _watch();
    }
    _rule();
  }

  /// The stopwatch at [now].
  Duration elapsed(DateTime now) => switch (state) {
    Running(:final trip) => trip.activeAt(now),
    Ended(:final trip) => trip.active,
    _ => Duration.zero,
  };

  /// „Ja, Einkauf starten“.
  void yes() {
    if (state case Asking(
      :final item,
      :final at,
      :final listId,
      :final snapshot,
    )) {
      _track('shop_asked', {'answer': ShopAnswer.yes.wire});
      _begin(at, listId, snapshot, TripSource.ask, startItem: item.id);
    }
  }

  /// „Nein, nur abgehakt“, or the sheet dismissed: nothing is remembered.
  void no() {
    if (state is Asking) {
      _track('shop_asked', {'answer': ShopAnswer.no.wire});
      _set(const NoTrip());
    }
  }

  /// „Zurücknehmen“: the item goes back on the list as the tick's undo.
  void takeBack() {
    if (state case Asking(:final item)) {
      _track('shop_asked', {'answer': ShopAnswer.takeBack.wire});
      _list.readd(item.id);
      _set(const NoTrip());
    }
  }

  /// Mehr › „Einkauf starten“: now, on the shown list.
  void startByHand() {
    if (!enabled() || state is! NoTrip && state is! Ended) {
      return;
    }
    final list = _list.state;
    final listId = list.shownList?.id;
    _begin(
      _clock(),
      listId,
      _snapshot(list.onList(list.allItems, listId).values),
      TripSource.manual,
    );
  }

  void pause() {
    if (state case Running(:final trip) when !trip.paused) {
      _run(trip.withPauses([...trip.pauses, TripPause(from: _clock())]));
    }
  }

  void resume() {
    if (state case Running(:final trip) when trip.paused) {
      final now = _clock();
      _run(trip.withPauses(closePauses(trip.pauses, now), resumedAt: now));
    }
  }

  /// Beenden: now, or auto-paused at the last tick. Completes once the
  /// save was tried; the state is [Ended] at once.
  Future<void> finish() async {
    if (state case Running(:final trip, :final lastTick)) {
      await _end(trip, endAt(trip, lastTick, _clock()), TripEnd.user);
    }
  }

  /// „Erneut versuchen“ on the summary page.
  Future<void> retry() async {
    if (state case Ended(:final trip, save: TripSave.failed)) {
      await _save(trip);
    }
  }

  /// „Einkauf löschen“ on the fresh summary page: the server forgets the
  /// end (and its Verlauf entries), and it is not saved again. Throws when
  /// the server did not take it. The page then leaves ([dismissEnded]).
  Future<void> delete() async {
    if (state case Ended(:final trip)) {
      await _repo.delete(trip.id);
      _unsaved.remove(trip.id);
      _persist();
    }
  }

  /// „Weiter einkaufen“ or „Doch weiter“: the same trip runs again, the
  /// time since its end a pause.
  void keepShopping() {
    if (state case Ended(:final trip, :final from)) {
      final now = _clock();
      _previous = trip;
      _run(
        from.withPauses([
          ...closePauses(from.pauses, trip.endedAt),
          TripPause(from: trip.endedAt, to: now),
        ], resumedAt: now),
      );
    }
  }

  /// The summary page was left, or the card's ×.
  void dismissEnded() {
    if (state is Ended) {
      _set(const NoTrip());
    }
  }

  /// „War geplant“ on the fresh summary page; false when the server did
  /// not take it (the mark is back as it was).
  Future<bool> markPlanned(String key, {required bool planned}) async {
    if (state case final Ended ended) {
      final Ended(:trip, :save) = ended;
      final next = ended.marked(key, on: planned);
      if (next == null || save == TripSave.refused) {
        return false;
      }
      if (save != TripSave.saved) {
        // Not on the server yet: the save carries the mark.
        _unsaved[trip.id] = next.trip;
        _set(next);
        return true;
      }
      _set(next);
      try {
        await _repo.markPlanned(trip.id, key, planned: planned);
        return true;
      } on Object {
        if (state case final Ended now when now.trip.id == trip.id) {
          _set(now.marked(key, on: !planned) ?? now);
        }
        return false;
      }
    }
    return false;
  }

  DateTime _clock() => clock();

  void _track(String event, Map<String, Object> properties) =>
      analytics?.track(event, properties);

  Future<void> _ticked(Item before) async {
    if (!enabled() || state is! NoTrip && state is! Ended) {
      return;
    }
    final list = _list.state;
    // Legal GL-2: a pharmacy's tick asks nothing.
    if (list.catalog.stores.any(
      (s) => s.id == before.storeId && s.isPharmacy,
    )) {
      return;
    }
    final listId = before.listOn(list.catalog.lists.firstOrNull?.id);
    final at = list.allItems[before.id]?.boughtAt ?? _clock();
    final snapshot = _snapshot([
      ...list
          .onList(list.allItems, listId)
          .values
          .where((i) => i.id != before.id),
      before,
    ]);
    await _sync();
    if (isClosed || state is! NoTrip && state is! Ended) {
      return;
    }
    _set(Asking(item: before, at: at, listId: listId, snapshot: snapshot));
  }

  static Map<String, PlannedItem> _snapshot(Iterable<Item> items) {
    final open =
        [
          for (final i in items)
            if (i.status == ItemStatus.active) i,
        ]..sort(
          (a, b) => switch (a.createdAt.compareTo(b.createdAt)) {
            0 => a.id.compareTo(b.id),
            final order => order,
          },
        );
    return {
      for (final i in open)
        i.id: PlannedItem(
          name: i.name,
          quantity: i.quantity,
          storeId: i.storeId,
          price: i.price,
        ),
    };
  }

  void _begin(
    DateTime at,
    String? listId,
    Map<String, PlannedItem> snapshot,
    TripSource source, {
    String? startItem,
  }) {
    _track('shop_started', {'source': source.name});
    _previous = null;
    _run(
      RunningTrip(
        id: const Uuid().v4(),
        householdId: householdId,
        listId: listId,
        startedAt: at,
        source: source,
        snapshot: snapshot,
        startItem: startItem,
      ),
    );
  }

  Iterable<Item> _itemsOf(RunningTrip trip) {
    final list = _list.state;
    return list.onList(list.allItems, trip.listId).values;
  }

  void _run(RunningTrip trip) {
    _watch();
    _set(Running(trip, lastTick: lastTick(trip, _itemsOf(trip))));
  }

  /// Runs [_rule] every [checkEvery].
  void _watch() => _timer ??= Timer.periodic(checkEvery, (_) => _rule());

  /// The long-running rule, once the list has heard from the server (its
  /// device copy may miss the last ticks). With the flag off it stops
  /// until [check].
  void _rule() {
    if (!enabled()) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (state case Running(:final trip, lastTick: final shown)
        when _list.state.resynced && !isClosed) {
      final last = lastTick(trip, _itemsOf(trip));
      switch (checkTrip(trip, last, _clock())) {
        case AutoEndAt(:final at):
          unawaited(_end(trip, at, TripEnd.auto));
        case KeepTrip() when last != shown:
          emit(Running(trip, lastTick: last));
        case KeepTrip():
          break;
        case final change:
          _run(applyCheck(trip, change));
      }
    }
  }

  Future<void> _end(RunningTrip trip, DateTime at, TripEnd end) async {
    final list = _list.state;
    final finished = finishTrip(
      trip,
      items: list.allItems,
      catalog: list.catalog,
      userId: userId,
      endedAt: at,
      end: end,
      previous: _previous,
    );
    _previous = null;
    _track('shop_ended', {
      'reason': end.name,
      'minutes': ShopMinutes.of(finished.active).wire,
    });
    _unsaved[finished.id] = finished;
    _set(
      Ended(
        finished,
        from: trip,
        auto: end == TripEnd.auto,
        save: TripSave.saving,
      ),
    );
    await _save(finished);
  }

  /// Saves [trip]; on success it leaves the unsaved ends and, when shown,
  /// becomes the server's answer.
  Future<void> _save(FinishedTrip trip) async {
    if (!_saving.add(trip.id)) {
      return;
    }
    _showSave(trip.id, TripSave.saving, null);
    FinishedTrip? newer;
    try {
      final saved = await _repo.save(trip, log: logs());
      // „War geplant“ while it was on its way: that copy goes next.
      newer = switch (_unsaved[trip.id]) {
        final copy? when !identical(copy, trip) => copy,
        _ => null,
      };
      if (newer == null) {
        _unsaved.remove(trip.id);
        _showSave(trip.id, TripSave.saved, saved);
      }
    } on TripRefused {
      _unsaved.remove(trip.id);
      _showSave(trip.id, TripSave.refused, null);
    } on Object {
      _showSave(trip.id, TripSave.failed, null);
    } finally {
      _saving.remove(trip.id);
    }
    if (newer != null) {
      await _save(newer);
    } else {
      _persist();
    }
  }

  void _showSave(String id, TripSave save, FinishedTrip? answer) {
    if (isClosed) {
      return;
    }
    if (state case Ended(:final trip, :final from, :final auto, save: final was)
        when trip.id == id && was != save) {
      emit(Ended(answer ?? trip, from: from, auto: auto, save: save));
    }
  }

  void _set(TripState next) {
    if (isClosed) {
      return;
    }
    if (next is! Running) {
      _timer?.cancel();
      _timer = null;
    }
    emit(next);
    _persist();
  }

  /// Takes up what the device keeps: this household's trip after a
  /// restart, a trip started or ended in another household meanwhile, and
  /// this household's unsaved ends.
  Future<void> _sync() async {
    await _writes;
    final kept = _KeptTrips.parse(await _cache.keptTrips(userId));
    if (isClosed) {
      return;
    }
    for (final t in kept.unsaved) {
      if (t.householdId == householdId) {
        _unsaved.putIfAbsent(t.id, () => t);
      }
    }
    final idle = state is NoTrip || state is RunningElsewhere;
    switch (kept.current) {
      case _KeptRunning(:final trip, :final previous)
          when trip.householdId == householdId && idle:
        _previous = previous;
        _watch();
        emit(Running(trip, lastTick: lastTick(trip, _itemsOf(trip))));
      case _KeptRunning(:final trip)
          when trip.householdId != householdId && (idle || state is Ended):
        _set(RunningElsewhere(trip.householdId));
      case _KeptEnded(:final trip, :final from, auto: true)
          when trip.householdId == householdId && state is NoTrip:
        emit(
          Ended(
            trip,
            from: from,
            auto: true,
            save: _unsaved.containsKey(trip.id)
                ? TripSave.failed
                : TripSave.saved,
          ),
        );
      case _ when state is RunningElsewhere:
        _set(const NoTrip());
      case _:
    }
  }

  /// Writes this household's part of the device's trips, keeping another
  /// household's.
  void _persist() {
    if (isClosed) {
      return;
    }
    final current = switch (state) {
      Running(:final trip) => _KeptRunning(trip, previous: _previous),
      Ended(:final trip, :final from, :final auto) => _KeptEnded(
        trip,
        from: from,
        auto: auto,
      ),
      NoTrip() || Asking() || RunningElsewhere() => null,
    };
    final unsaved = [..._unsaved.values];
    _writes = _writes.then((_) async {
      final kept = _KeptTrips.parse(await _cache.keptTrips(userId));
      final theirs = switch (kept.current) {
        final c? when c.householdId != householdId => c,
        _ => null,
      };
      final next = _KeptTrips(
        current: current ?? theirs,
        unsaved: [
          for (final t in kept.unsaved)
            if (t.householdId != householdId) t,
          ...unsaved,
        ],
      );
      await _cache.saveKeptTrips(userId, next.encode());
    });
  }

  /// Writes still queued finish on their own; none starts after this.
  /// The subscriptions are on broadcast streams, whose cancel is done at
  /// once (its future is the root zone's, which a fake clock never runs).
  @override
  Future<void> close() {
    _timer?.cancel();
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    return super.close();
  }
}

extension on FinishedTrip {
  FinishedTrip withLines(List<TripLine> lines) => FinishedTrip(
    id: id,
    householdId: householdId,
    startedAt: startedAt,
    endedAt: endedAt,
    active: active,
    end: end,
    source: source,
    currency: currency,
    lines: lines,
    bought: bought,
    day: day,
    stores: stores,
    listId: listId,
    startedBy: startedBy,
    pauses: pauses,
  );
}

/// What the device keeps of the user's trips (`DeviceCache.keptTrips`):
/// the trip running or ended last, in any household, and ends not saved
/// yet.
@immutable
class const _KeptTrips({
  final _KeptTrip? current,
  final List<FinishedTrip> unsaved = const [],
}) {
  /// A value that cannot be read is none.
  factory parse(String? json) {
    if (json == null) {
      return const _KeptTrips();
    }
    try {
      final value = jsonDecode(json) as Map<String, Object?>;
      return _KeptTrips(
        current: switch (value) {
          {'running': final Map<String, Object?> running} => _KeptRunning(
            RunningTrip.fromJson(running),
            previous: switch (value['previous']) {
              final Map<String, Object?> p => FinishedTrip.fromJson(p),
              _ => null,
            },
          ),
          {
            'ended': final Map<String, Object?> ended,
            'from': final Map<String, Object?> from,
            'auto': final bool auto,
          } =>
            _KeptEnded(
              FinishedTrip.fromJson(ended),
              from: RunningTrip.fromJson(from),
              auto: auto,
            ),
          _ => null,
        },
        unsaved: [
          for (final t in (value['unsaved'] as List<Object?>?) ?? const [])
            FinishedTrip.fromJson(t! as Map<String, Object?>),
        ],
      );
    } on Object {
      return const _KeptTrips();
    }
  }

  String encode() => jsonEncode({
    ...switch (current) {
      _KeptRunning(:final trip, :final previous) => {
        'running': trip.toJson(),
        'previous': ?previous?.toJson(),
      },
      _KeptEnded(:final trip, :final from, :final auto) => {
        'ended': trip.toJson(),
        'from': from.toJson(),
        'auto': auto,
      },
      null => const <String, Object?>{},
    },
    'unsaved': [for (final t in unsaved) t.toJson()],
  });
}

@immutable
sealed class const _KeptTrip() {
  String get householdId;
}

final class const _KeptRunning(
  final RunningTrip trip, {
  final FinishedTrip? previous,
}) extends _KeptTrip {
  @override
  String get householdId => trip.householdId;
}

final class const _KeptEnded(
  final FinishedTrip trip, {
  required final RunningTrip from,
  required final bool auto,
}) extends _KeptTrip {
  @override
  String get householdId => trip.householdId;
}

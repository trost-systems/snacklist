/// The long-running rule of a trip (job 234, TM2's timings) and its
/// stopwatch. Every proposed or automatic end is at the last tick.
library;

import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/trip/model.dart';

/// Quiet time after which a trip pauses itself.
const autoPauseAfter = Duration(minutes: 45);

/// Quiet time after which a trip ends itself, paused or not.
const autoEndAfter = Duration(hours: 4);

/// How far a tick may lie outside a trip and still count on it. Ticks
/// carry the server's `bought_at`, a trip's start and end the device's
/// clock; two clocks a little apart must not drop the starting tick or
/// the last ones.
const tickSlack = Duration(minutes: 2);

/// Whether [at] lies in [trip], up to [end] when it ended, give or take
/// [tickSlack].
bool duringTrip(RunningTrip trip, DateTime at, {DateTime? end}) =>
    !at.isBefore(trip.startedAt.subtract(tickSlack)) &&
    (end == null || !at.isAfter(end.add(tickSlack)));

/// Whether [item] was ticked on [trip] (ended at [end], if it has): bought
/// during it, or the item whose tick started it. A tick in the slack
/// before the start counts only for an item open at the start or added
/// after it: one there and not open had been ticked before the trip
/// („Nein, nur abgehakt“ right before a „Ja“).
bool boughtOnTrip(RunningTrip trip, Item item, {DateTime? end}) =>
    item.status == ItemStatus.bought &&
    switch (item.boughtAt) {
      final at? =>
        item.id == trip.startItem ||
            duringTrip(trip, at, end: end) &&
                (!at.isBefore(trip.startedAt) ||
                    trip.snapshot.containsKey(item.id) ||
                    !item.createdAt.isBefore(trip.startedAt)),
      null => false,
    };

/// The newest tick of [trip]: the latest `boughtAt` among the [items] of
/// its list bought on it, by anyone. Null before any.
DateTime? lastTick(RunningTrip trip, Iterable<Item> items) {
  DateTime? last;
  for (final item in items) {
    final at = item.boughtAt;
    if (at != null &&
        boughtOnTrip(trip, item) &&
        (last == null || at.isAfter(last))) {
      last = at;
    }
  }
  return last;
}

/// The trip's last sign of life: its start, its [last] tick or the last
/// "Weiter", whichever is latest.
DateTime activity(RunningTrip trip, DateTime? last) => [
  trip.startedAt,
  ?last,
  ?trip.resumedAt,
].reduce((a, b) => a.isAfter(b) ? a : b);

/// Where a trip that ends now without a user's say ends: at its [last]
/// tick, else (or when that lies before it, see [tickSlack]) at its start.
DateTime quietEnd(RunningTrip trip, DateTime? last) => switch (last) {
  final last? when !last.isBefore(trip.startedAt) => last,
  _ => trip.startedAt,
};

/// The pause that lasts now and that the trip took itself; null for none
/// or the user's own.
TripPause? autoPause(RunningTrip trip) => switch (trip.pauses.lastOrNull) {
  final p? when p.to == null && p.auto => p,
  _ => null,
};

/// Where Beenden ends [trip] now: auto-paused, at the [last] tick
/// („Beenden um 10:06“); else [now].
DateTime endAt(RunningTrip trip, DateTime? last, DateTime now) =>
    autoPause(trip) == null ? now : quietEnd(trip, last);

/// What the long-running rule does to a running trip.
sealed class const TripCheck();

/// Nothing: the trip runs (or stays paused) as it is.
final class const KeepTrip() extends TripCheck;

/// 45 minutes without a sign of life and no pause running: pause [at]
/// that moment.
final class const AutoPauseAt(final DateTime at) extends TripCheck;

/// A tick came while the trip had paused itself: the pause ends [at] it.
final class const AutoResumeAt(final DateTime at) extends TripCheck;

/// 4 hours without a sign of life: end [at] the last tick.
final class const AutoEndAt(final DateTime at) extends TripCheck;

/// The long-running rule for [trip] at [now], [last] its last tick.
TripCheck checkTrip(RunningTrip trip, DateTime? last, DateTime now) {
  final quiet = now.difference(activity(trip, last));
  final paused = autoPause(trip);
  if (quiet >= autoEndAfter) {
    return AutoEndAt(quietEnd(trip, last));
  }
  if (paused != null && last != null && last.isAfter(paused.from)) {
    return AutoResumeAt(last);
  }
  if (!trip.paused && quiet >= autoPauseAfter) {
    return AutoPauseAt(activity(trip, last).add(autoPauseAfter));
  }
  return const KeepTrip();
}

/// [trip] with [check] applied; the same trip for [KeepTrip] and
/// [AutoEndAt] (which ends it, see [closePauses]).
RunningTrip applyCheck(RunningTrip trip, TripCheck check) => switch (check) {
  AutoPauseAt(:final at) => trip.withPauses([
    ...trip.pauses,
    TripPause(from: at, auto: true),
  ]),
  AutoResumeAt(:final at) => trip.withPauses(closePauses(trip.pauses, at)),
  KeepTrip() || AutoEndAt() => trip,
};

/// [pauses] as they stand at [end]: pauses from [end] on dropped, the rest
/// closed by [end] at the latest.
List<TripPause> closePauses(List<TripPause> pauses, DateTime end) => [
  for (final p in pauses)
    if (p.from.isBefore(end))
      TripPause(
        from: p.from,
        to: switch (p.to) {
          final to? when to.isBefore(end) => to,
          _ => end,
        },
        auto: p.auto,
      ),
];

/// The stopwatch: from [startedAt] to [end] minus [pauses], each clipped
/// to that span (an open one lasts to [end]).
Duration activeTime(DateTime startedAt, DateTime end, List<TripPause> pauses) {
  if (!end.isAfter(startedAt)) {
    return Duration.zero;
  }
  var paused = Duration.zero;
  for (final p in pauses) {
    final from = p.from.isBefore(startedAt) ? startedAt : p.from;
    final to = switch (p.to) {
      final to? when to.isBefore(end) => to,
      _ => end,
    };
    if (to.isAfter(from)) {
      paused += to.difference(from);
    }
  }
  final active = end.difference(startedAt) - paused;
  return active.isNegative ? Duration.zero : active;
}

extension RunningTripChanges on RunningTrip {
  /// This trip with [pauses] and, when given, [resumedAt].
  RunningTrip withPauses(List<TripPause> pauses, {DateTime? resumedAt}) =>
      RunningTrip(
        id: id,
        householdId: householdId,
        listId: listId,
        startedAt: startedAt,
        source: source,
        snapshot: snapshot,
        pauses: pauses,
        resumedAt: resumedAt ?? this.resumedAt,
        startItem: startItem,
      );

  /// The stopwatch at [now].
  Duration activeAt(DateTime now) => activeTime(startedAt, now, pauses);
}

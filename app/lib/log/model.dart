import 'package:family_groceries/list/model.dart' show Store;
import 'package:flutter/foundation.dart' show immutable;

/// One bought line of a trip, a snapshot: never an item id, so a later edit
/// or reuse of the list's row does not change the trip.
@immutable
class const TripItem({required final String name, final String? quantity}) {
  factory fromJson(Map<String, Object?> json) => TripItem(
    name: json['name']! as String,
    quantity: switch (json['quantity']) {
      final String q when q.trim().isNotEmpty => q,
      _ => null,
    },
  );

  /// What `save_trip` takes; the server adds the canonical key.
  Map<String, Object?> toJson() => {'name': name, 'quantity': quantity};

  @override
  bool operator ==(Object other) =>
      other is TripItem && other.name == name && other.quantity == quantity;

  @override
  int get hashCode => Object.hash(name, quantity);
}

/// One shop at one store on one day (`public.trips`, job 199).
@immutable
class const Trip({
  required final String id,

  /// The day, a local date at midnight ([dateOnly]).
  required final DateTime day,
  required final List<TripItem> items,
  required final DateTime createdAt,

  /// The household's store; null without one or when it was deleted.
  final String? storeId,

  /// The store's name when the trip was saved; null with [storeId] null is
  /// "Ohne Laden".
  final String? storeName,
  final String? loggedBy,

  /// The trip-mode trip it came from (job 234); its entry opens that
  /// trip's summary.
  final String? sessionId,
}) {
  factory fromJson(Map<String, Object?> json) => Trip(
    id: json['id']! as String,
    storeId: json['store_id'] as String?,
    storeName: json['store_name'] as String?,
    day: parseDay(json['shopped_on']! as String),
    items: [
      for (final item in json['items']! as List<Object?>)
        TripItem.fromJson(item! as Map<String, Object?>),
    ],
    loggedBy: json['logged_by'] as String?,
    sessionId: json['session_id'] as String?,
    createdAt: DateTime.parse(json['created_at']! as String).toLocal(),
  );
}

/// How far back the history reaches for the signed-in user
/// (`trip_history`, job 199 H1).
@immutable
sealed class const HistoryWindow() {
  /// Whether [day] is before the window: its trips are not shown.
  bool locks(DateTime day) => switch (this) {
    RecentHistory(:final since) => day.isBefore(since),
    AllHistory() => false,
  };
}

/// Premium: every kept trip.
final class const AllHistory() extends HistoryWindow {
  @override
  bool operator ==(Object other) => other is AllHistory;

  @override
  int get hashCode => 0;
}

/// Free: the trips from [since] on (the last 4 weeks, today included);
/// [locked] older ones are kept but not shown.
final class const RecentHistory({
  /// A local date.
  required final DateTime since,
  required final int locked,
}) extends HistoryWindow {
  @override
  bool operator ==(Object other) =>
      other is RecentHistory && other.since == since && other.locked == locked;

  @override
  int get hashCode => Object.hash(since, locked);
}

/// What `trip_history` answers: the trips the user may see, newest first,
/// and the window they come from.
@immutable
class const TripHistory({
  required final List<Trip> trips,
  required final HistoryWindow window,
}) {
  /// Throws a [FormatException] for an answer of another shape.
  factory fromJson(Object? json) {
    if (json case {
      'trips': final List<Object?> trips,
      'premium': final bool premium,
      'since': final String? since,
      'locked': final int locked,
    }) {
      return TripHistory(
        trips: [
          for (final row in trips) Trip.fromJson(row! as Map<String, Object?>),
        ],
        window: switch ((premium, since)) {
          (true, _) => const AllHistory(),
          (false, final String since) => RecentHistory(
            since: parseDay(since),
            locked: locked,
          ),
          (false, null) => throw const FormatException(
            'trip_history: no since without premium',
          ),
        },
      );
    }
    throw FormatException('trip_history: unexpected answer', json);
  }
}

/// Where a logged trip came from, as `trip_logged` reports it.
enum TripSource() {
  /// The history's "Einkauf eintragen".
  manual,

  /// The list's card after a store's section was ticked off.
  prompt,
}

/// The two ways the history shows, cycled by one button (G1, G2).
enum LogView() {
  /// G1: newest first, by week and month, under a month calendar.
  journal,

  /// G2: one block per store.
  stores;

  /// The view the toggle switches to.
  LogView get next => switch (this) {
    journal => stores,
    stores => journal,
  };

  /// A stored name, or null for an unknown one.
  static LogView? parse(String? name) =>
      values.where((v) => v.name == name).firstOrNull;
}

/// [at]'s local calendar day, at midnight.
DateTime dateOnly(DateTime at) => DateTime(at.year, at.month, at.day);

/// A `YYYY-MM-DD` date as a local day.
DateTime parseDay(String wire) {
  final [y, m, d] = [for (final part in wire.split('-')) int.parse(part)];
  return DateTime(y, m, d);
}

/// [day] as `YYYY-MM-DD`, as `save_trip` takes it.
String wireDay(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// Whole days from [from] to [to], both local dates; daylight saving does
/// not shift it.
int daysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// The Monday of [day]'s week.
DateTime mondayOf(DateTime day) =>
    DateTime(day.year, day.month, day.day - (day.weekday - DateTime.monday));

/// Newest day first, the later save first within a day.
int newestFirst(Trip a, Trip b) => switch (b.day.compareTo(a.day)) {
  0 => b.createdAt.compareTo(a.createdAt),
  final c => c,
};

/// A journal section's period.
@immutable
sealed class const JournalPeriod();

final class const ThisWeek() extends JournalPeriod {
  @override
  bool operator ==(Object other) => other is ThisWeek;

  @override
  int get hashCode => 1;
}

final class const LastWeek() extends JournalPeriod {
  @override
  bool operator ==(Object other) => other is LastWeek;

  @override
  int get hashCode => 2;
}

final class const InMonth(final int year, final int month)
    extends JournalPeriod {
  @override
  bool operator ==(Object other) =>
      other is InMonth && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);
}

typedef JournalSection = ({JournalPeriod period, List<Trip> trips});

/// G1's sections, newest first: this week and last week (Monday weeks),
/// then each month. A trip dated after [today] counts as this week.
List<JournalSection> journalSections(List<Trip> trips, DateTime today) {
  final monday = mondayOf(today);
  JournalPeriod periodOf(DateTime day) =>
      switch (daysBetween(mondayOf(day), monday) ~/ 7) {
        <= 0 => const ThisWeek(),
        1 => const LastWeek(),
        _ => InMonth(day.year, day.month),
      };
  final sections = <JournalSection>[];
  for (final trip in [...trips]..sort(newestFirst)) {
    final period = periodOf(trip.day);
    if (sections.lastOrNull case (period: final last, :final trips)
        when last == period) {
      trips.add(trip);
    } else {
      sections.add((period: period, trips: [trip]));
    }
  }
  return sections;
}

/// One G2 block: a household store (`storeId` set), a gone store's trips
/// under the name they were saved with, or "Ohne Laden" (`name` null).
typedef StoreBlock = ({String? storeId, String? name, List<Trip> trips});

/// G2's blocks: every household store in its order, those without trips
/// too, then the trips whose store is gone, grouped by the name they were
/// saved with, then "Ohne Laden" if any trip has none. Newest trip first
/// in each.
List<StoreBlock> storeBlocks(List<Trip> trips, List<Store> stores) {
  final sorted = [...trips]..sort(newestFirst);
  final known = {for (final s in stores) s.id};
  final gone = <String, List<Trip>>{};
  final none = <Trip>[];
  for (final trip in sorted) {
    if (known.contains(trip.storeId)) {
      continue;
    }
    switch (trip.storeName) {
      case final name?:
        (gone[name] ??= []).add(trip);
      case null:
        none.add(trip);
    }
  }
  return [
    for (final s in stores)
      (
        storeId: s.id,
        name: s.name,
        trips: [
          for (final t in sorted)
            if (t.storeId == s.id) t,
        ],
      ),
    for (final MapEntry(key: name, value: trips) in gone.entries)
      (storeId: null, name: name, trips: trips),
    if (none.isNotEmpty) (storeId: null, name: null, trips: none),
  ];
}

/// The most dots a calendar day shows; more trips still show this many.
const maxDayDots = 3;

/// A calendar day's marks: one colour per trip, at most [maxDayDots], and
/// the real number of trips.
typedef DayMark<C> = ({List<C> colours, int count});

/// The marks of [month]'s days (keys 1 to 31) that have trips: the dots in
/// newest-first order of the day's trips, coloured by [colourOf].
Map<int, DayMark<C>> dayMarks<C>(
  List<Trip> trips,
  DateTime month,
  C Function(Trip trip) colourOf,
) {
  final byDay = <int, List<Trip>>{};
  for (final trip in [...trips]..sort(newestFirst)) {
    if (trip.day.year == month.year && trip.day.month == month.month) {
      (byDay[trip.day.day] ??= []).add(trip);
    }
  }
  return {
    for (final MapEntry(key: day, value: trips) in byDay.entries)
      day: (
        colours: [for (final t in trips.take(maxDayDots)) colourOf(t)],
        count: trips.length,
      ),
  };
}

/// How many store colours there are (SnacklistColors brand, tomato, mint,
/// honey, accent, success).
const storePaletteSize = 6;

/// [storeId]'s colour slot: its place in the household's order, round the
/// palette; null for no store or one that is gone (a neutral dot).
int? storeColourIndex(String? storeId, List<Store> stores) {
  final index = stores.indexWhere((s) => s.id == storeId);
  return storeId == null || index < 0 ? null : index % storePaletteSize;
}

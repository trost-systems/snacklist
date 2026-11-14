import 'package:family_groceries/list/pricing.dart';
import 'package:family_groceries/log/model.dart' show parseDay, wireDay;
import 'package:flutter/foundation.dart' show immutable, listEquals, mapEquals;

/// How a trip started: the question after a tick, or Mehr's
/// „Einkauf starten“.
enum TripSource() {
  ask,
  manual,
}

/// How a trip ended: the user's Beenden, or the long-running rule
/// (4 hours without a tick), which ends it at the last tick.
enum TripEnd() {
  user,
  auto,
}

/// An open item as it was when the trip started: the planned part of the
/// summary. [price] is the item's price then, of any day ("geplant").
@immutable
class const PlannedItem({
  required final String name,
  final String? quantity,
  final String? storeId,
  final Price? price,
}) {
  factory fromJson(Map<String, Object?> json) => PlannedItem(
    name: json['name']! as String,
    quantity: json['quantity'] as String?,
    storeId: json['store_id'] as String?,
    price: Price.fromColumns(
      (json['price'] as Map<String, Object?>?) ?? const {},
    ),
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'quantity': ?quantity,
    'store_id': ?storeId,
    'price': ?price?.toColumns(),
  };

  @override
  bool operator ==(Object other) =>
      other is PlannedItem &&
      other.name == name &&
      other.quantity == quantity &&
      other.storeId == storeId &&
      other.price == price;

  @override
  int get hashCode => Object.hash(name, quantity, storeId, price);
}

/// A pause of a running trip; [to] is null while it lasts. [auto]: the
/// trip paused itself 45 minutes after the last tick.
@immutable
class const TripPause({
  required final DateTime from,
  final DateTime? to,
  final bool auto = false,
}) {
  factory fromJson(Map<String, Object?> json) => TripPause(
    from: DateTime.parse(json['from']! as String),
    to: switch (json['to']) {
      final String at => DateTime.parse(at),
      _ => null,
    },
    auto: json['auto'] == true,
  );

  Map<String, Object?> toJson() => {
    'from': from.toUtc().toIso8601String(),
    'to': ?to?.toUtc().toIso8601String(),
    'auto': auto,
  };

  @override
  bool operator ==(Object other) =>
      other is TripPause &&
      other.from.isAtSameMomentAs(from) &&
      switch ((other.to, to)) {
        (null, null) => true,
        (final a?, final b?) => a.isAtSameMomentAs(b),
        _ => false,
      } &&
      other.auto == auto;

  @override
  int get hashCode => Object.hash(
    from.microsecondsSinceEpoch,
    to?.microsecondsSinceEpoch,
    auto,
  );
}

/// The trip running on this device (one per signed-in user, kept in
/// `DeviceCache`). It lives on the device until it ends; the server only
/// learns of it as a [FinishedTrip].
@immutable
class const RunningTrip({
  /// Also the id of the [FinishedTrip] it becomes, so a retried or
  /// repeated end ("Weiter einkaufen", then Beenden again) saves one trip.
  required final String id,
  required final String householdId,

  /// The list it started on; its items are the snapshot and the ticks.
  required final String? listId,

  /// The moment of the tick that raised the question, or of the manual
  /// start.
  required final DateTime startedAt,
  required final TripSource source,

  /// The list's open items just before the starting tick (that item
  /// included), by item id.
  required final Map<String, PlannedItem> snapshot,
  final List<TripPause> pauses = const [],

  /// The last sign of life that is not a tick: "Weiter" after a pause,
  /// "Weiter einkaufen" or "Doch weiter" after an end. The long-running
  /// rule counts quiet time from the later of this and the last tick.
  final DateTime? resumedAt,

  /// The id of the item whose tick raised the question; null for a start
  /// by hand. It counts as bought on the trip whatever the clocks say.
  final String? startItem,
}) {
  factory fromJson(Map<String, Object?> json) => RunningTrip(
    id: json['id']! as String,
    householdId: json['household_id']! as String,
    listId: json['list_id'] as String?,
    startedAt: DateTime.parse(json['started_at']! as String),
    source: TripSource.values.byName(json['source']! as String),
    snapshot: {
      for (final MapEntry(:key, :value)
          in (json['snapshot']! as Map<String, Object?>).entries)
        key: PlannedItem.fromJson(value! as Map<String, Object?>),
    },
    pauses: [
      for (final p in (json['pauses'] as List<Object?>?) ?? const [])
        TripPause.fromJson(p! as Map<String, Object?>),
    ],
    resumedAt: switch (json['resumed_at']) {
      final String at => DateTime.parse(at),
      _ => null,
    },
    startItem: json['start_item'] as String?,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'household_id': householdId,
    'list_id': listId,
    'started_at': startedAt.toUtc().toIso8601String(),
    'source': source.name,
    'snapshot': {
      for (final MapEntry(:key, :value) in snapshot.entries)
        key: value.toJson(),
    },
    'pauses': [for (final p in pauses) p.toJson()],
    'resumed_at': ?resumedAt?.toUtc().toIso8601String(),
    'start_item': ?startItem,
  };

  /// Whether a pause lasts now.
  bool get paused => pauses.lastOrNull?.to == null && pauses.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is RunningTrip &&
      other.id == id &&
      other.householdId == householdId &&
      other.listId == listId &&
      other.startedAt.isAtSameMomentAs(startedAt) &&
      other.source == source &&
      mapEquals(other.snapshot, snapshot) &&
      listEquals(other.pauses, pauses) &&
      other.resumedAt?.microsecondsSinceEpoch ==
          resumedAt?.microsecondsSinceEpoch &&
      other.startItem == startItem;

  @override
  int get hashCode => Object.hash(id, startedAt.microsecondsSinceEpoch);
}

/// One row of a finished trip's summary, frozen at the end: a planned item
/// (in the snapshot) or one that came in since the start. Cents are line
/// totals in the trip's currency; a price in another currency counts as
/// none.
@immutable
class const TripLine({
  /// The item's id at the end, unique in the trip; "War geplant" names it.
  required final String key,
  required final String name,

  /// In the snapshot.
  required final bool planned,

  /// Ticked off between the start and the end, by anyone.
  required final bool bought,
  final String? quantity,

  /// The household store's id; null without one or for a deleted store.
  final String? storeId,

  /// The store's name at the end; null is „Ohne Laden“.
  final String? storeName,

  /// "War geplant": an extra the user counts as planned.
  final bool markedPlanned = false,

  /// Another member wrote it onto the list after the start (PB2a).
  final bool byOther = false,

  /// That member; null once they left the household or deleted the
  /// account (the server forgets them), or for the user's own adds.
  final String? addedBy,

  /// The planned line: the snapshot's price at the snapshot's quantity.
  final int? plannedCents,

  /// The paid line: the price at the end, saved on the trip's day or
  /// later, at the quantity then (PW1: the weighed amount).
  final int? paidCents,
}) {
  factory fromJson(Map<String, Object?> json) => TripLine(
    key: json['key']! as String,
    name: json['name']! as String,
    planned: json['planned']! as bool,
    bought: json['bought']! as bool,
    quantity: json['quantity'] as String?,
    storeId: json['store_id'] as String?,
    storeName: json['store_name'] as String?,
    markedPlanned: json['marked_planned'] == true,
    byOther: json['by_other'] == true,
    addedBy: json['added_by'] as String?,
    plannedCents: json['planned_cents'] as int?,
    paidCents: json['paid_cents'] as int?,
  );

  Map<String, Object?> toJson() => {
    'key': key,
    'name': name,
    'planned': planned,
    'bought': bought,
    'quantity': quantity,
    'store_id': storeId,
    'store_name': storeName,
    'marked_planned': markedPlanned,
    'by_other': byOther,
    'added_by': addedBy,
    'planned_cents': plannedCents,
    'paid_cents': paidCents,
  };

  /// In the summary's planned part: in the snapshot, or marked so.
  bool get countsPlanned => planned || markedPlanned;

  TripLine withMarked(bool marked) => TripLine(
    key: key,
    name: name,
    planned: planned,
    bought: bought,
    quantity: quantity,
    storeId: storeId,
    storeName: storeName,
    markedPlanned: marked,
    byOther: byOther,
    addedBy: addedBy,
    plannedCents: plannedCents,
    paidCents: paidCents,
  );

  @override
  bool operator ==(Object other) =>
      other is TripLine &&
      other.key == key &&
      other.name == name &&
      other.planned == planned &&
      other.bought == bought &&
      other.quantity == quantity &&
      other.storeId == storeId &&
      other.storeName == storeName &&
      other.markedPlanned == markedPlanned &&
      other.byOther == byOther &&
      other.addedBy == addedBy &&
      other.plannedCents == plannedCents &&
      other.paidCents == paidCents;

  @override
  int get hashCode => Object.hash(
    key,
    name,
    planned,
    bought,
    quantity,
    storeId,
    storeName,
    markedPlanned,
    byOther,
    addedBy,
    plannedCents,
    paidCents,
  );
}

/// A trip as the server keeps it (`public.trip_sessions`, job 234): the
/// summary shown at the end and on its Verlauf entries.
@immutable
class const FinishedTrip({
  required final String id,
  required final String householdId,
  required final DateTime startedAt,
  required final DateTime endedAt,

  /// The stopwatch at the end: [endedAt] minus [startedAt] minus pauses.
  required final Duration active,
  required final TripEnd end,
  required final TripSource source,

  /// The household's currency at the end; every cent amount is in it.
  required final String currency,

  /// The summary rows; null when the server withholds them (no Premium,
  /// PB3a). Then [bought] still counts the ticked items.
  required final List<TripLine>? lines,

  /// How many items were ticked off (also without Premium).
  required final int bought,

  /// The local day it is logged on (the start's).
  required final DateTime day,

  /// Store names of the bought items, in store order (also without
  /// Premium).
  final List<String?> stores = const [],
  final String? listId,
  final String? startedBy,

  /// The pauses, closed, for "Weiter einkaufen" after an end.
  final List<TripPause> pauses = const [],
}) {
  /// What `trip_session` and `save_trip_session` answer.
  factory fromJson(Map<String, Object?> json) => FinishedTrip(
    id: json['id']! as String,
    householdId: json['household_id']! as String,
    listId: json['list_id'] as String?,
    startedBy: json['started_by'] as String?,
    startedAt: DateTime.parse(json['started_at']! as String),
    endedAt: DateTime.parse(json['ended_at']! as String),
    active: Duration(seconds: json['active_seconds']! as int),
    end: TripEnd.values.byName(json['end_reason']! as String),
    source: TripSource.values.byName(json['source']! as String),
    currency: json['currency']! as String,
    day: parseDay(json['shopped_on']! as String),
    pauses: [
      for (final p in (json['pauses'] as List<Object?>?) ?? const [])
        TripPause.fromJson(p! as Map<String, Object?>),
    ],
    lines: switch (json['lines']) {
      final List<Object?> lines => [
        for (final l in lines) TripLine.fromJson(l! as Map<String, Object?>),
      ],
      _ => null,
    },
    bought: json['bought']! as int,
    stores: [
      for (final s in (json['stores'] as List<Object?>?) ?? const [])
        s as String?,
    ],
  );

  /// What `save_trip_session` takes as `p_trip`. The server ignores
  /// household_id, started_by, bought and stores: it takes the household
  /// from the call, keeps the first saver and counts from [lines].
  Map<String, Object?> toJson() => {
    'id': id,
    'household_id': householdId,
    'list_id': listId,
    'started_by': startedBy,
    'started_at': startedAt.toUtc().toIso8601String(),
    'ended_at': endedAt.toUtc().toIso8601String(),
    'active_seconds': active.inSeconds,
    'end_reason': end.name,
    'source': source.name,
    'currency': currency,
    'shopped_on': wireDay(day),
    'pauses': [for (final p in pauses) p.toJson()],
    'lines': lines?.map((l) => l.toJson()).toList(),
    'bought': bought,
    'stores': stores,
  };

  @override
  bool operator ==(Object other) =>
      other is FinishedTrip &&
      other.id == id &&
      other.householdId == householdId &&
      other.startedAt.isAtSameMomentAs(startedAt) &&
      other.endedAt.isAtSameMomentAs(endedAt) &&
      other.active == active &&
      other.end == end &&
      other.source == source &&
      other.currency == currency &&
      listEquals(other.lines, lines) &&
      other.bought == bought &&
      other.day == day &&
      listEquals(other.stores, stores) &&
      other.listId == listId &&
      other.startedBy == startedBy &&
      listEquals(other.pauses, pauses);

  @override
  int get hashCode => Object.hash(id, endedAt.microsecondsSinceEpoch, bought);
}

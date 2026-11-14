/// A trip's end (job 234): the [FinishedTrip] computed from the running
/// trip and the list, and the summary page's report of it, by store, with
/// what was planned, what was paid and the difference. No widgets, no
/// words.
library;

import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/pricing.dart';
import 'package:family_groceries/trip/model.dart';
import 'package:family_groceries/trip/rules.dart';
import 'package:flutter/foundation.dart' show immutable;

/// The most lines a trip keeps: `save_trip_session` refuses more
/// (`too_many_lines`, `20261114181718_trip_mode.sql`).
const maxTripLines = 400;

/// [trip] ended at [endedAt] for [end]. [items] are the household's items
/// (`ListState.allItems`); [catalog] gives the stores, the lists and the
/// currency; [userId] is who ends it. [previous] is the same trip's last
/// end ("Weiter einkaufen", then Beenden again): its „War geplant“ marks
/// carry over.
FinishedTrip finishTrip(
  RunningTrip trip, {
  required Map<String, Item> items,
  required Catalog catalog,
  required String userId,
  required DateTime endedAt,
  required TripEnd end,
  FinishedTrip? previous,
}) {
  final currency = catalog.currency;
  final stores = {for (final s in catalog.stores) s.id: s};
  final firstList = catalog.lists.firstOrNull?.id;
  final marked = {
    for (final line in previous?.lines ?? const <TripLine>[])
      if (line.markedPlanned) line.key,
  };

  bool bought(Item i) => boughtOnTrip(trip, i, end: endedAt);

  int? paid(Item i) {
    final price = i.price;
    if (price == null ||
        price.currency != currency ||
        _day(price.pricedAt).isBefore(_day(trip.startedAt))) {
      return null;
    }
    return i.lineCentsNow;
  }

  final planned = [
    for (final MapEntry(key: id, value: p) in trip.snapshot.entries)
      switch (items[id]) {
        final now? => TripLine(
          key: id,
          name: now.name,
          planned: true,
          bought: bought(now),
          quantity: now.quantity,
          storeId: stores[now.storeId]?.id,
          storeName: stores[now.storeId]?.name,
          plannedCents: _plannedCents(p, currency),
          paidCents: bought(now) ? paid(now) : null,
        ),
        null => TripLine(
          key: id,
          name: p.name,
          planned: true,
          bought: false,
          quantity: p.quantity,
          storeId: stores[p.storeId]?.id,
          storeName: stores[p.storeId]?.name,
          plannedCents: _plannedCents(p, currency),
        ),
      },
  ];

  bool cameIn(Item i) => duringTrip(trip, i.createdAt, end: endedAt);
  final extraItems = [
    for (final i in items.values)
      if (!trip.snapshot.containsKey(i.id) &&
          (trip.listId == null || i.listOn(firstList) == trip.listId) &&
          (bought(i) || (i.status == ItemStatus.active && cameIn(i))))
        i,
  ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  final extras = [
    for (final i in extraItems)
      TripLine(
        key: i.id,
        name: i.name,
        planned: false,
        bought: bought(i),
        quantity: i.quantity,
        storeId: stores[i.storeId]?.id,
        storeName: stores[i.storeId]?.name,
        markedPlanned: marked.contains(i.id),
        byOther: _byOther(i, userId, trip),
        addedBy: _byOther(i, userId, trip) ? i.addedBy : null,
        paidCents: bought(i) ? paid(i) : null,
      ),
  ];

  final lines = _capped([...planned, ...extras]);
  final boughtLines = lines.where((l) => l.bought);
  final ordered = [...catalog.stores]
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  final boughtStores = {for (final l in boughtLines) l.storeId};
  final pauses = closePauses(trip.pauses, endedAt);
  return FinishedTrip(
    id: trip.id,
    householdId: trip.householdId,
    startedAt: trip.startedAt,
    endedAt: endedAt,
    active: activeTime(trip.startedAt, endedAt, pauses),
    end: end,
    source: trip.source,
    currency: currency,
    lines: lines,
    bought: boughtLines.length,
    day: _day(trip.startedAt),
    stores: [
      for (final s in ordered)
        if (boughtStores.contains(s.id)) s.name,
      if (boughtStores.contains(null)) null,
    ],
    listId: trip.listId,
    startedBy: userId,
    pauses: pauses,
  );
}

/// [lines] cut to [maxTripLines], in their order: bought lines first,
/// then planned ones, then the rest.
List<TripLine> _capped(List<TripLine> lines) {
  if (lines.length <= maxTripLines) {
    return lines;
  }
  int rank(TripLine l) => l.bought ? 0 : (l.planned ? 1 : 2);
  final kept = {
    for (final (i, _)
        in ([...lines.indexed]..sort(
              (a, b) => switch (rank(a.$2).compareTo(rank(b.$2))) {
                0 => a.$1.compareTo(b.$1),
                final order => order,
              },
            ))
            .take(maxTripLines))
      i,
  };
  return [
    for (final (i, l) in lines.indexed)
      if (kept.contains(i)) l,
  ];
}

bool _byOther(Item i, String me, RunningTrip trip) =>
    i.addedBy != null && i.addedBy != me && duringTrip(trip, i.createdAt);

/// The snapshot's line: its price at its quantity, in [currency] only.
int? _plannedCents(PlannedItem p, String currency) {
  final price = p.price;
  if (price == null || price.currency != currency) {
    return null;
  }
  final amount = amountFor(price.per, measureOf(p.quantity));
  return amount == null ? null : lineCents(price.unitMicros, price.per, amount);
}

DateTime _day(DateTime at) {
  final local = at.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// Where a section's lines were bought.
@immutable
sealed class const SectionStore();

/// One of the household's stores.
final class const HouseholdStore(final Store store) extends SectionStore {
  @override
  bool operator ==(Object other) =>
      other is HouseholdStore && other.store.id == store.id;

  @override
  int get hashCode => store.id.hashCode;
}

/// A store the household deleted since; [name] as the trip kept it.
final class const GoneStore(final String name) extends SectionStore {
  @override
  bool operator ==(Object other) => other is GoneStore && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

/// „Ohne Laden“.
final class const NoStore() extends SectionStore {
  @override
  bool operator ==(Object other) => other is NoStore;

  @override
  int get hashCode => 0;
}

/// Sums over a set of lines; only bought lines count.
@immutable
class const TripTotals({
  /// Σ paid cents („Bezahlt“).
  final int paid = 0,

  /// Σ planned cents of the [compared] lines.
  final int planned = 0,

  /// Σ (paid − planned) of the [compared] lines: positive is more.
  final int difference = 0,

  /// Bought lines with both prices.
  final int compared = 0,

  /// Bought lines without a paid price („2 ohne Preis“).
  final int withoutPrice = 0,

  /// Bought lines with a paid price but no planned one.
  final int withoutPlan = 0,

  /// Bought lines.
  final int bought = 0,

  /// Lines in the planned part (in the snapshot or marked planned).
  final int plannedCount = 0,

  /// Of them, bought.
  final int plannedBought = 0,

  /// Bought lines outside the planned part („1 zusätzlich“).
  final int extraBought = 0,
}) {
  /// The sums over [lines].
  factory of(Iterable<TripLine> lines) {
    var t = const TripTotals();
    for (final l in lines) {
      t = t + TripTotals._line(l);
    }
    return t;
  }

  factory _line(TripLine l) {
    final counts = l.countsPlanned;
    if (!l.bought) {
      return TripTotals(plannedCount: counts ? 1 : 0);
    }
    final (paid, plan) = (l.paidCents, l.plannedCents);
    return TripTotals(
      paid: paid ?? 0,
      planned: paid != null && plan != null ? plan : 0,
      difference: paid != null && plan != null ? paid - plan : 0,
      compared: paid != null && plan != null ? 1 : 0,
      withoutPrice: paid == null ? 1 : 0,
      withoutPlan: paid != null && plan == null ? 1 : 0,
      bought: 1,
      plannedCount: counts ? 1 : 0,
      plannedBought: counts ? 1 : 0,
      extraBought: counts ? 0 : 1,
    );
  }

  TripTotals operator +(TripTotals o) => TripTotals(
    paid: paid + o.paid,
    planned: planned + o.planned,
    difference: difference + o.difference,
    compared: compared + o.compared,
    withoutPrice: withoutPrice + o.withoutPrice,
    withoutPlan: withoutPlan + o.withoutPlan,
    bought: bought + o.bought,
    plannedCount: plannedCount + o.plannedCount,
    plannedBought: plannedBought + o.plannedBought,
    extraBought: extraBought + o.extraBought,
  );

  @override
  bool operator ==(Object other) =>
      other is TripTotals &&
      other.paid == paid &&
      other.planned == planned &&
      other.difference == difference &&
      other.compared == compared &&
      other.withoutPrice == withoutPrice &&
      other.withoutPlan == withoutPlan &&
      other.bought == bought &&
      other.plannedCount == plannedCount &&
      other.plannedBought == plannedBought &&
      other.extraBought == extraBought;

  @override
  int get hashCode => Object.hash(
    paid,
    planned,
    difference,
    compared,
    withoutPrice,
    withoutPlan,
    bought,
    plannedCount,
    plannedBought,
    extraBought,
  );

  @override
  String toString() =>
      'TripTotals(paid $paid, planned $planned, difference $difference, '
      'compared $compared, withoutPrice $withoutPrice, withoutPlan '
      '$withoutPlan, bought $bought, plannedCount $plannedCount, '
      'plannedBought $plannedBought, extraBought $extraBought)';
}

/// One store's part of the summary.
@immutable
class const TripSection({
  required final SectionStore store,

  /// „Beim Start auf der Liste“: snapshot lines and lines marked „War
  /// geplant“ (those have `planned` false), in line order.
  required final List<TripLine> planned,

  /// „Seit dem Start dazugekommen“, in line order.
  required final List<TripLine> extras,
  required final TripTotals totals,
});

/// The summary page's body: a section per store (the household's store
/// order, then gone stores by name, then none) and the overall totals,
/// whose counts are the lede's.
@immutable
class const TripReport({
  required final List<TripSection> sections,
  required final TripTotals totals,
});

/// The report of [lines] for a household with [stores].
TripReport tripReport(List<TripLine> lines, List<Store> stores) {
  final byId = {for (final s in stores) s.id: s};
  SectionStore storeOf(TripLine l) => switch ((byId[l.storeId], l.storeName)) {
    (final store?, _) => HouseholdStore(store),
    (_, final name?) => GoneStore(name),
    _ => const NoStore(),
  };
  final groups = <SectionStore, List<TripLine>>{};
  for (final l in lines) {
    (groups[storeOf(l)] ??= []).add(l);
  }
  final sections = [
    for (final MapEntry(key: store, value: rows) in groups.entries)
      TripSection(
        store: store,
        planned: [...rows.where((l) => l.countsPlanned)],
        extras: [...rows.where((l) => !l.countsPlanned)],
        totals: TripTotals.of(rows),
      ),
  ]..sort((a, b) => _storeOrder(a.store, b.store));
  return TripReport(sections: sections, totals: TripTotals.of(lines));
}

int _storeOrder(SectionStore a, SectionStore b) => switch ((a, b)) {
  (HouseholdStore(store: final x), HouseholdStore(store: final y)) =>
    x.sortOrder.compareTo(y.sortOrder),
  (GoneStore(name: final x), GoneStore(name: final y)) => x.compareTo(y),
  _ => _rank(a).compareTo(_rank(b)),
};

int _rank(SectionStore s) => switch (s) {
  HouseholdStore() => 0,
  GoneStore() => 1,
  NoStore() => 2,
};

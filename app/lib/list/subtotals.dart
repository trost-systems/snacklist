/// The list's totals per store (job 237, ST3 behind `list-declutter`):
/// what the summary block above „Zuletzt verwendet“ shows. Peter's rules
/// (t874u): an unpriced item makes its sums a floor („mind.“), a price per
/// kg or l on the planned weight is an estimate („≈“) and so is every sum
/// holding one, „Ohne Laden“ is a group of its own, and bought items count
/// only while a trip runs on the list (then split from the open ones).
library;

import 'package:family_groceries/list/list_cache.dart' show noStoreKey;
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/pricing.dart';
import 'package:family_groceries/trip/model.dart' show RunningTrip;
import 'package:family_groceries/trip/rules.dart' show boughtOnTrip;
import 'package:flutter/foundation.dart' show immutable;

/// What some items add up to: [cents] over [priced] items, [unpriced]
/// items without today's price, [foreign] ones priced today in another
/// currency than the household's (left out, as job 190's total does; either
/// makes the sum at least [cents]), and whether a line in it is an
/// [estimate].
@immutable
class const Sum({
  final int cents = 0,
  final int priced = 0,
  final int unpriced = 0,
  final int foreign = 0,
  final bool estimate = false,
}) {
  /// One item's part.
  factory of(Item item, {required String currency, required DateTime now}) =>
      switch (item.summedCents(currency, now)) {
        final cents? => Sum(
          cents: cents,
          priced: 1,
          estimate: plannedWeight(item),
        ),
        // Priced today in another currency: left out, but not unpriced. A
        // price per kg on a quantity without a weight sums nothing either:
        // that one counts as unpriced.
        null when (item.currentPrice(now)?.currency ?? currency) != currency =>
          const Sum(foreign: 1),
        null => const Sum(unpriced: 1),
      };

  static const zero = Sum();

  Sum operator +(Sum other) => Sum(
    cents: cents + other.cents,
    priced: priced + other.priced,
    unpriced: unpriced + other.unpriced,
    foreign: foreign + other.foreign,
    estimate: estimate || other.estimate,
  );

  /// Nothing in it has a price: no amount to show.
  bool get empty => priced == 0;

  /// Some of it is not summed: the amount is a floor.
  bool get floor => unpriced > 0 || foreign > 0;

  @override
  bool operator ==(Object other) =>
      other is Sum &&
      other.cents == cents &&
      other.priced == priced &&
      other.unpriced == unpriced &&
      other.foreign == foreign &&
      other.estimate == estimate;

  @override
  int get hashCode => Object.hash(cents, priced, unpriced, foreign, estimate);

  @override
  String toString() =>
      'Sum($cents, priced: $priced, unpriced: $unpriced, '
      'foreign: $foreign, estimate: $estimate)';
}

/// Whether [item]'s line comes from its planned weight or volume: a price
/// per kg or l typed per unit on an item still open. The label's total
/// (basis line) is the weighed line, and a ticked item is in the cart.
bool plannedWeight(Item item) => switch (item.price) {
  Price(per: PricePer.kg || PricePer.l, basis: PriceBasis.unit) =>
    item.status == ItemStatus.active,
  _ => false,
};

/// One line of the block: a store, or „Ohne Laden“ for a null [store].
@immutable
class const StoreTally({
  required final Store? store,
  required final Sum open,

  /// Bought on the running trip; null without one.
  required final Sum? bought,

  /// Open items, for the jump to the section.
  required final int openCount,
}) {
  /// The section's key in `ListPrefs.folded` and its divider's.
  String get key => store?.id ?? noStoreKey;

  Sum get sum => open + (bought ?? Sum.zero);

  /// Everything of it was bought on the trip: it stays, marked.
  bool get allBought => openCount == 0;
}

/// The block: [stores] in the list's section order (household store order,
/// then „Ohne Laden“), each with something open or bought on the trip.
@immutable
class const Summary({
  required final List<StoreTally> stores,

  /// Whether bought and open are split: a trip runs on the list.
  required final bool split,
}) {
  Sum get open => stores.fold(Sum.zero, (s, t) => s + t.open);

  Sum get bought => stores.fold(Sum.zero, (s, t) => s + (t.bought ?? Sum.zero));

  Sum get total => open + bought;

  /// A line per store only with two groups or more: one would repeat the
  /// total.
  bool get perStore => stores.length > 1;
}

/// The block for one list's [items] (open and ticked) in [catalog]'s
/// stores. Without [trip] only open items count; with it the items bought
/// on it too, apart. An item of a store gone from [catalog] counts as
/// without one, as the list shows it.
Summary summaryOf(
  Iterable<Item> items,
  Catalog catalog, {
  required DateTime now,
  RunningTrip? trip,
}) {
  final currency = catalog.currency;
  final storeIds = {for (final s in catalog.stores) s.id};
  final open = <String?, Sum>{};
  final bought = <String?, Sum>{};
  final openCount = <String?, int>{};
  for (final item in items) {
    final storeId = storeIds.contains(item.storeId) ? item.storeId : null;
    final into = switch (item.status) {
      ItemStatus.active => open,
      ItemStatus.bought when trip != null && boughtOnTrip(trip, item) => bought,
      _ => null,
    };
    if (into == null) {
      continue;
    }
    into[storeId] =
        (into[storeId] ?? Sum.zero) +
        Sum.of(item, currency: currency, now: now);
    if (item.status == ItemStatus.active) {
      openCount[storeId] = (openCount[storeId] ?? 0) + 1;
    }
  }
  final stores = [...catalog.stores]
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  return Summary(
    split: trip != null,
    stores: [
      for (final store in [...stores, null])
        if (open.containsKey(store?.id) || bought.containsKey(store?.id))
          StoreTally(
            store: store,
            open: open[store?.id] ?? Sum.zero,
            bought: trip == null ? null : bought[store?.id] ?? Sum.zero,
            openCount: openCount[store?.id] ?? 0,
          ),
    ],
  );
}

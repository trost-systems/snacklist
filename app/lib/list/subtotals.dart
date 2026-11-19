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
/// stores. Without [onTrip] only open items count; with it the items it
/// counts as bought on the running trip too, apart. An item of a store gone
/// from [catalog] counts as without one, as the list shows it.
Summary summaryOf(
  Iterable<Item> items,
  Catalog catalog, {
  required DateTime now,
  bool Function(Item item)? onTrip,
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
      ItemStatus.bought when onTrip?.call(item) ?? false => bought,
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
    split: onTrip != null,
    stores: [
      for (final store in [...stores, null])
        if (open.containsKey(store?.id) || bought.containsKey(store?.id))
          StoreTally(
            store: store,
            open: open[store?.id] ?? Sum.zero,
            bought: onTrip == null ? null : bought[store?.id] ?? Sum.zero,
            openCount: openCount[store?.id] ?? 0,
          ),
    ],
  );
}

/// The shown list's running total in the household's currency: [cents]
/// over [priced] items, [open] open items without a summed price (as
/// [Sum.of] tells), and the same sum per store id ([byStore], null for no
/// store).
@immutable
class const TripTotal({
  required final int cents,
  required final int priced,
  required final int open,
  final Map<String?, int> byStore = const {},
});

/// [items] are one list's (open and bought). [stores]: the household's
/// store ids; an item of another store counts as without one, as the list
/// shows it. Each item counts as in the block (job 277): a price per kg on
/// a quantity without a weight is open, as an unpriced one.
TripTotal tripTotal(
  Iterable<Item> items, {
  required String currency,
  required DateTime now,
  Set<String>? stores,
}) {
  var cents = 0;
  var priced = 0;
  var open = 0;
  final byStore = <String?, int>{};
  for (final item in items) {
    switch (Sum.of(item, currency: currency, now: now)) {
      case Sum(priced: > 0, cents: final line):
        cents += line;
        priced++;
        final store = stores == null || stores.contains(item.storeId)
            ? item.storeId
            : null;
        byStore[store] = (byStore[store] ?? 0) + line;
      case Sum(unpriced: > 0) when item.status == ItemStatus.active:
        open++;
      case _:
    }
  }
  return TripTotal(cents: cents, priced: priced, open: open, byStore: byStore);
}

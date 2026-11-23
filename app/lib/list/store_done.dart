import 'package:family_groceries/list/model.dart';
import 'package:flutter/foundation.dart' show immutable;

/// How long before a store's last tick the user's own tick there may lie
/// for the card to be theirs: they were shopping there.
const storeDoneTickWindow = Duration(minutes: 30);

/// How long after the store's last tick its card shows.
const storeDoneShowFor = Duration(minutes: 60);

/// A linked store whose last open item was ticked [at] (job 399, SC1);
/// [bought] holds the ids of its bought items, that last one among them.
@immutable
class const StoreDone(
  final Store store,
  final DateTime at, {
  final Set<String> bought = const {},
}) {
  @override
  bool operator ==(Object other) =>
      other is StoreDone &&
      other.store.id == store.id &&
      other.at.isAtSameMomentAs(at);

  @override
  int get hashCode => Object.hash(store.id, at.microsecondsSinceEpoch);
}

/// A closed card: the store's bought items then, and when it was finished.
/// Item ids, not the tick's time: the server writes its own `bought_at` over
/// a tick that was still pending when the card was closed.
@immutable
class const StoreDoneDismissal(final DateTime at, final Set<String> items);

/// The „… ist erledigt“ card to show [userId], if any: a store with an
/// app and no open item, finished less than [storeDoneShowFor] before
/// [now], where they ticked something themselves within
/// [storeDoneTickWindow] of the finishing tick (a tick in [tickedHere]
/// still waits for the server, which records who ticked). Not one whose
/// finishing item was bought when its card was [dismissed]: only a new item
/// ticked off brings it back. Of several, the latest finish.
StoreDone? storeDoneCard({
  required Iterable<Item> items,
  required Catalog catalog,
  required String userId,
  required Set<String> tickedHere,
  required Map<String, StoreDoneDismissal> dismissed,
  required DateTime now,
}) {
  final byStore = <String, List<Item>>{};
  for (final item in items) {
    if (item.storeId case final id?) {
      (byStore[id] ??= []).add(item);
    }
  }
  StoreDone? latest;
  for (final MapEntry(key: id, value: run) in byStore.entries) {
    final store = catalog.store(id);
    if (store == null ||
        store.app == null ||
        run.any((i) => i.status == ItemStatus.active)) {
      continue;
    }
    final ticks = [
      for (final i in run)
        if (i.boughtAt case final at?) (item: i, at: at),
    ];
    if (ticks.isEmpty) {
      continue;
    }
    final last = ticks.reduce((a, b) => a.at.isAfter(b.at) ? a : b);
    final at = last.at;
    final from = at.subtract(storeDoneTickWindow);
    final mine = ticks.any(
      (t) =>
          !t.at.isBefore(from) &&
          (tickedHere.contains(t.item.id) || t.item.boughtBy == userId),
    );
    if (!mine ||
        now.difference(at) >= storeDoneShowFor ||
        (dismissed[id]?.items.contains(last.item.id) ?? false)) {
      continue;
    }
    if (latest == null || at.isAfter(latest.at)) {
      latest = StoreDone(store, at, bought: {for (final t in ticks) t.item.id});
    }
  }
  return latest;
}

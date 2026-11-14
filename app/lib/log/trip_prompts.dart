import 'dart:async';

import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

/// One card on the list: log what this device ticked off at `storeId`
/// (null: the section without a store), in tick order.
typedef TripPrompt = ({String? storeId, List<Item> items});

/// What this device ticked off on the shown list, by store section, and
/// which sections offer logging (job 199, H2 and H3). A section offers it
/// once the list shows no open item of it and something ticked there is
/// still bought; one prompt per store. Later ticks there join its prompt.
@immutable
class const TripTicks({
  /// The list the ticks were on; another list starts over.
  final String? listId,

  /// Ticked items as they were before the tick, by store id (null: no
  /// store), then by item id.
  final Map<String?, Map<String, Item>> ticked = const {},

  /// The stores whose prompt shows.
  final Set<String?> offered = const {},
}) {
  /// The section [item] shows in: its store, or none for a store [catalog]
  /// does not have (deleted).
  static String? storeOf(Item item, Catalog catalog) =>
      catalog.stores.any((s) => s.id == item.storeId) ? item.storeId : null;

  /// This device ticked [item] off.
  TripTicks tick(Item item, Catalog catalog) {
    final store = storeOf(item, catalog);
    return TripTicks(
      listId: listId,
      ticked: {
        ...ticked,
        store: {...?ticked[store], item.id: item},
      },
      offered: offered,
    );
  }

  /// Brought up to [list]: a different shown list starts over, an item open
  /// again (unticked, re-added) leaves, a prompt with nothing left goes,
  /// and a store whose section has no open item left offers its prompt.
  /// This same value when nothing changed.
  TripTicks settle(ListState list) {
    final shown = list.shownList?.id;
    if (shown != listId) {
      return TripTicks(listId: shown);
    }
    final all = list.allItems;
    final open = {
      for (final item in list.items.values)
        if (item.status == ItemStatus.active) storeOf(item, list.catalog),
    };
    var changed = false;
    final kept = <String?, Map<String, Item>>{};
    for (final MapEntry(key: store, value: items) in ticked.entries) {
      final bought = {
        for (final MapEntry(:key, :value) in items.entries)
          if (all[key]?.status != ItemStatus.active) key: value,
      };
      changed |= bought.length != items.length;
      if (bought.isNotEmpty) {
        kept[store] = bought;
      }
    }
    // Legal GL-2: a pharmacy's section offers no card.
    final pharmacies = {
      for (final s in list.catalog.stores)
        if (s.isPharmacy) s.id,
    };
    final shownPrompts = {
      for (final store in kept.keys)
        if (!pharmacies.contains(store) &&
            (offered.contains(store) || !open.contains(store)))
          store,
    };
    changed |=
        shownPrompts.length != offered.length ||
        !offered.containsAll(shownPrompts);
    return changed
        ? TripTicks(listId: listId, ticked: kept, offered: shownPrompts)
        : this;
  }

  /// The items [ids] were logged elsewhere (a trip's end): their ticks go,
  /// and a store left with none loses its prompt.
  TripTicks forgetting(Set<String> ids) {
    final kept = <String?, Map<String, Item>>{
      for (final MapEntry(key: store, value: items) in ticked.entries)
        if ({
              for (final MapEntry(:key, :value) in items.entries)
                if (!ids.contains(key)) key: value,
            }
            case final left when left.isNotEmpty)
          store: left,
    };
    return TripTicks(
      listId: listId,
      ticked: kept,
      offered: offered.intersection(kept.keys.toSet()),
    );
  }

  /// [storeId]'s prompt was logged or put off: it goes, with its ticks.
  TripTicks without(String? storeId) => TripTicks(
    listId: listId,
    ticked: {...ticked}..remove(storeId),
    offered: {...offered}..remove(storeId),
  );

  /// The prompts shown, in the household's store order, the one without a
  /// store last.
  List<TripPrompt> prompts(Catalog catalog) {
    final stores = [...catalog.stores]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return [
      for (final store in [...stores.map((s) => s.id), null])
        if (ticked[store] case final items? when offered.contains(store))
          (storeId: store, items: [...items.values]),
    ];
  }
}

/// The list's trip prompts for a list: its own ticks, settled on every
/// change of the list. One per [ListCubit], so a household switch starts
/// over too.
class TripPrompts(final ListCubit _list) extends Cubit<TripTicks> {
  this : super(TripTicks(listId: _list.state.shownList?.id)) {
    _subscriptions = [
      _list.activity.listen((activity) {
        if (activity case OwnItemTicked(:final item)) {
          emit(state.tick(item, _list.state.catalog).settle(_list.state));
        }
      }),
      _list.stream.listen((list) => emit(state.settle(list))),
    ];
  }

  late final List<StreamSubscription<Object?>> _subscriptions;

  /// One trip id per store's prompt, so a second Eintragen after a save
  /// whose answer was lost writes the same trip.
  final _ids = <String?, String>{};

  /// The trip id [storeId]'s prompt logs under.
  String idFor(String? storeId) =>
      _ids.putIfAbsent(storeId, () => const Uuid().v4());

  /// The prompts the list shows now.
  List<TripPrompt> get prompts => state.prompts(_list.state.catalog);

  /// A trip logged the items [ids]: no card offers them again.
  void forget(Set<String> ids) {
    [
      for (final MapEntry(:key, :value) in state.ticked.entries)
        if (value.keys.every(ids.contains)) key,
    ].forEach(_ids.remove);
    emit(state.forgetting(ids));
  }

  /// [storeId]'s prompt was logged, or put off with Später.
  void dismiss(String? storeId) {
    _ids.remove(storeId);
    emit(state.without(storeId));
  }

  @override
  Future<void> close() async {
    for (final s in _subscriptions) {
      await s.cancel();
    }
    await super.close();
  }
}

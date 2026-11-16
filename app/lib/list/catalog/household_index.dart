import 'package:flutter/foundation.dart';

/// A name the household bought in the last year, as public.suggest_history
/// and public.suggest_entries see it: one row per name, brand and details,
/// with the latest row's quantity and its time (bought, else updated).
typedef HistoryRow = ({
  String name,
  String? brand,
  String? properties,
  String? quantity,
  String normalizedName,
  DateTime at,
});

/// A brand the household taught public.parse_item (household_brands), with
/// its public.brand_key.
typedef HouseholdBrand = ({String brand, String key});

/// A row of item_store_memory: the store taught for an item key, and the
/// key's canonical key (public.canonical_of_key), which spelling variants
/// share.
typedef StoreMemory = ({String itemKey, String? canonicalKey, String storeId});

/// A household store with a seed key (dm, lidl, edeka, hardware): a
/// brand's store and public.category_store name it by that key.
typedef SeededStore = ({String seedKey, String storeId});

/// What a category says about the store of an item without one:
/// public.category_usual_store (`usual`) and public.category_store
/// (`seeded`).
typedef CategoryStores = ({String categoryId, String? usual, String? seeded});

/// The household's own data the ranking reads (job 274), what
/// public.suggest_index answers: its [history], its learned [brands], the
/// hardware seed keys it has no category for ([unserved]) and the
/// normalized names of its older items ([known], for public.is_known_name).
/// For each row's store: its store [memory], newest first, the item keys
/// last set to „Ohne Laden“ ([cleared]), its [stores] with a seed key and
/// its [categories]' stores. An index cached before these keys existed
/// reads them as empty.
@immutable
final class const HouseholdIndex({
  final List<HistoryRow> history = const [],
  final List<HouseholdBrand> brands = const [],
  final List<String> unserved = const [],
  final List<String> known = const [],
  final List<StoreMemory> memory = const [],
  final List<String> cleared = const [],
  final List<SeededStore> stores = const [],
  final List<CategoryStores> categories = const [],
}) {
  /// Before the first answer: nothing bought, nothing learned.
  static const empty = HouseholdIndex();

  /// public.suggest_index's answer, or null when anything about it is off:
  /// one bad row rejects it, and the device keeps what it has.
  static HouseholdIndex? fromJson(Object? json) {
    if (json case {
      'history': final List<Object?> history,
      'brands': final List<Object?> brands,
      'unserved': final List<Object?> unserved,
      'known': final List<Object?> known,
    }) {
      final rows = _all(history, _historyRow);
      final learned = _all(brands, _brand);
      final seeds = _all(unserved, _string);
      final names = _all(known, _string);
      final memory = _all(_listOrEmpty(json['memory']), _memory);
      final cleared = _all(_listOrEmpty(json['cleared']), _string);
      final stores = _all(_listOrEmpty(json['stores']), _seededStore);
      final categories = _all(
        _listOrEmpty(json['categories']),
        _categoryStores,
      );
      if (rows == null ||
          learned == null ||
          seeds == null ||
          names == null ||
          memory == null ||
          cleared == null ||
          stores == null ||
          categories == null) {
        return null;
      }
      return HouseholdIndex(
        history: rows,
        brands: learned,
        unserved: seeds,
        known: names,
        memory: memory,
        cleared: cleared,
        stores: stores,
        categories: categories,
      );
    }
    return null;
  }

  /// The shape [fromJson] reads.
  Object? toJson() => {
    'history': [
      for (final row in history)
        [
          row.name,
          row.brand,
          row.properties,
          row.quantity,
          row.normalizedName,
          row.at.toUtc().toIso8601String(),
        ],
    ],
    'brands': [
      for (final b in brands) [b.brand, b.key],
    ],
    'unserved': unserved,
    'known': known,
    'memory': [
      for (final m in memory) [m.itemKey, m.canonicalKey, m.storeId],
    ],
    'cleared': cleared,
    'stores': [
      for (final s in stores) [s.seedKey, s.storeId],
    ],
    'categories': [
      for (final c in categories) [c.categoryId, c.usual, c.seeded],
    ],
  };
}

/// A year of a busy household's distinct items is a few thousand.
const _maxRows = 20000;

/// The longest text a field may hold: items allow 120 characters, and
/// normalizing a name can double its umlauts.
const _maxText = 300;

/// A key absent from an index cached before it existed reads as empty;
/// anything but a list rejects the index.
List<Object?>? _listOrEmpty(Object? json) => switch (json) {
  null => const [],
  final List<Object?> rows => rows,
  _ => null,
};

List<T>? _all<T>(List<Object?>? rows, T? Function(Object? row) parse) {
  if (rows == null || rows.length > _maxRows) {
    return null;
  }
  final parsed = <T>[];
  for (final row in rows) {
    if (parse(row) case final value?) {
      parsed.add(value);
    } else {
      return null;
    }
  }
  return parsed;
}

bool _text(String? value) => value != null && value.length <= _maxText;

bool _optional(String? value) => value == null || _text(value);

String? _string(Object? value) =>
    value is String && value.isNotEmpty && _text(value) ? value : null;

HistoryRow? _historyRow(Object? row) => switch (row) {
  [
    final String name,
    final String? brand,
    final String? properties,
    final String? quantity,
    final String normalizedName,
    final String at,
  ]
      when _text(name) &&
          _optional(brand) &&
          _optional(properties) &&
          _optional(quantity) &&
          _text(normalizedName) =>
    switch (DateTime.tryParse(at)) {
      final at? => (
        name: name,
        brand: brand,
        properties: properties,
        quantity: quantity,
        normalizedName: normalizedName,
        at: at,
      ),
      null => null,
    },
  _ => null,
};

HouseholdBrand? _brand(Object? row) => switch (row) {
  [final String brand, final String key] when _text(brand) && _text(key) => (
    brand: brand,
    key: key,
  ),
  _ => null,
};

StoreMemory? _memory(Object? row) => switch (row) {
  [final String itemKey, final String? canonicalKey, final String storeId]
      when _text(itemKey) &&
          _optional(canonicalKey) &&
          _string(storeId) != null =>
    (itemKey: itemKey, canonicalKey: canonicalKey, storeId: storeId),
  _ => null,
};

SeededStore? _seededStore(Object? row) => switch (row) {
  [final String seedKey, final String storeId]
      when _string(seedKey) != null && _string(storeId) != null =>
    (seedKey: seedKey, storeId: storeId),
  _ => null,
};

CategoryStores? _categoryStores(Object? row) => switch (row) {
  [final String categoryId, final String? usual, final String? seeded]
      when _string(categoryId) != null &&
          _optional(usual) &&
          _optional(seeded) =>
    (categoryId: categoryId, usual: usual, seeded: seeded),
  _ => null,
};

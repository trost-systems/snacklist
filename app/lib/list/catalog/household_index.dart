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

/// The household's own data the ranking reads (job 274), what
/// public.suggest_index answers: its [history], its learned [brands], the
/// hardware seed keys it has no category for ([unserved]) and the
/// normalized names of its older items ([known], for public.is_known_name).
@immutable
final class const HouseholdIndex({
  final List<HistoryRow> history = const [],
  final List<HouseholdBrand> brands = const [],
  final List<String> unserved = const [],
  final List<String> known = const [],
}) {
  /// Before the first answer: nothing bought, nothing learned.
  static const empty = HouseholdIndex();

  /// public.suggest_index's answer, or null when anything about it is off:
  /// one bad row rejects it, and the device keeps what it has.
  static HouseholdIndex? fromJson(Object? json) {
    if (json
        case {
          'history': final List<Object?> history,
          'brands': final List<Object?> brands,
          'unserved': final List<Object?> unserved,
          'known': final List<Object?> known,
        }
        when history.length <= _maxRows &&
            brands.length <= _maxRows &&
            unserved.length <= _maxRows &&
            known.length <= _maxRows) {
      final rows = _all(history, _historyRow);
      final learned = _all(brands, _brand);
      final seeds = _all(unserved, _string);
      final names = _all(known, _string);
      if (rows == null || learned == null || seeds == null || names == null) {
        return null;
      }
      return HouseholdIndex(
        history: rows,
        brands: learned,
        unserved: seeds,
        known: names,
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
  };
}

/// A year of a busy household's distinct items is a few thousand.
const _maxRows = 20000;

/// The longest text a field may hold: items allow 120 characters, and
/// normalizing a name can double its umlauts.
const _maxText = 300;

List<T>? _all<T>(List<Object?> rows, T? Function(Object? row) parse) {
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

import 'package:family_groceries/list/model.dart';
import 'package:flutter/foundation.dart';

/// Why the add sheet offers a row; each row is labelled with it.
enum SuggestionSource() {
  /// What was typed, as the server's parser reads it.
  typed,

  /// Bought before, with that time's brand and details.
  history,

  /// Another pack of what was typed (Big Pack, 4er Pack).
  pack,

  /// What was typed plus a detail bought before (laktosefrei).
  variant,

  /// One size up or down (Größe 4, Größe 2).
  size,

  /// Another brand of the same product.
  brand,

  /// A word from the dictionary that starts like the last word typed.
  catalog,

  /// Bought regularly and due again: shown before anything is typed.
  due,

  /// Used in the last 30 days: shown after the due ones before anything is
  /// typed.
  recent;

  static SuggestionSource byName(String name) =>
      values.where((s) => s.name == name).firstOrNull ?? typed;
}

/// One tappable row of the add sheet: an entry with all its fields.
@immutable
class const Suggestion(final SuggestionSource source, final ParsedEntry entry) {
  /// A row of `public.suggest_entries`.
  factory fromJson(Map<String, Object?> json) => Suggestion(
    SuggestionSource.byName(json['source']! as String),
    ParsedEntry.fromJson(json),
  );

  /// The same item whatever the quantity: rows with one key are one row.
  String get key => [
    foldName(entry.name),
    foldName(entry.brand ?? ''),
    foldName(entry.properties ?? ''),
  ].join('|');
}

/// The server's [server] rows for a text on top of the [local] ones the
/// device showed for it (job 272): no shown row moves or changes its
/// text. The typed row takes the server's category and store for what was
/// typed, or the server's row itself when it reads the same; another shown
/// row takes the category and store of the server's row for the same
/// item, keeping its quantity. The server's other rows follow in its
/// order, up to [mergedRows] in all; its own reading of the typed line only
/// when none was shown.
List<Suggestion> mergeRows(List<Suggestion> local, List<Suggestion> server) {
  final serverTyped = server
      .where((s) => s.source == SuggestionSource.typed)
      .firstOrNull;
  final byKey = <String, Suggestion>{};
  for (final row in server) {
    byKey.putIfAbsent(row.key, () => row);
  }
  final merged = <Suggestion>[];
  final keys = <String>{};
  void add(Suggestion row) {
    if (keys.add(row.key)) {
      merged.add(row);
    }
  }

  for (final row in local) {
    final typed = row.source == SuggestionSource.typed;
    final match = typed ? serverTyped : byKey[row.key];
    if (match == null) {
      add(row);
    } else if (typed &&
        match.key == row.key &&
        match.entry.quantity == row.entry.quantity) {
      add(match);
    } else {
      add(
        Suggestion(
          row.source,
          ParsedEntry(
            name: row.entry.name,
            brand: row.entry.brand,
            properties: row.entry.properties,
            quantity: row.entry.quantity,
            storeId: match.entry.storeId ?? row.entry.storeId,
            categoryId: match.entry.categoryId ?? row.entry.categoryId,
            deviceParsed: row.entry.deviceParsed,
          ),
        ),
      );
    }
  }
  final typedShown = local.any((r) => r.source == SuggestionSource.typed);
  for (final row in server) {
    if (merged.length >= mergedRows) {
      break;
    }
    if (!(typedShown && row.source == SuggestionSource.typed)) {
      add(row);
    }
  }
  return merged;
}

/// As many rows as `public.suggest_entries` answers by default: the
/// server's rows fill up to it after the device's, which all stay.
const mergedRows = 8;

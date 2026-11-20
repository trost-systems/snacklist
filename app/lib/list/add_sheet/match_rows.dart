import 'package:family_groceries/list/catalog/catalog_index.dart';
import 'package:family_groceries/list/catalog/suggest_entries.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/quantity.dart';

/// Job 324 (AM2, flag `add-match-rows`): an item already on the list that
/// is the same thing as what is typed, shown in the add sheet as what one
/// tap does with it.
sealed class const MatchRow() {
  Item get item;
}

/// Folds what is typed into the open [item]: its Menge becomes [quantity].
final class const MergeRow(@override final Item item, final String quantity)
    extends MatchRow;

/// Ticks the open [item] off.
final class const TickRow(@override final Item item) extends MatchRow;

/// Puts the ticked [item] back on the list, as it was.
final class const ReaddRow(@override final Item item) extends MatchRow;

/// The rows for the same items [open] (oldest first) and [ticked] (the
/// list's recently used), [typedQuantity] typed: the first open item merge
/// and tick off, each further one merge, each ticked one back on the list;
/// at most three. An item whose merged Menge would not fit gets no merge,
/// and neither does a further one whose merge row would read exactly like
/// an earlier one (two plain Kefir): the rows could not be told apart.
List<MatchRow> matchRowsFor(
  List<Item> open,
  List<Item> ticked,
  String? typedQuantity,
) {
  final shown = <Object>{};
  return [
    for (final (i, item) in open.indexed) ...[
      if (_merged(item.quantity, typedQuantity) case final quantity?
          when shown.add((
            item.name,
            quantity,
            item.storeId,
            item.brand,
            item.properties,
          )))
        MergeRow(item, quantity),
      if (i == 0) TickRow(item),
    ],
    for (final item in ticked) ReaddRow(item),
  ].take(3).toList();
}

String? _merged(String? open, String? typed) {
  try {
    return mergeQuantities(open, typed);
  } on QuantityTooLong {
    return null;
  }
}

/// Finds the items of a list that are the same thing as a typed name: the
/// same canonical key ([canonicalKeyOf], on the device for both sides),
/// whatever their brand and details. "Milch" is not "Hafermilch".
final class ItemMatcher(final CatalogIndex catalog) {
  final _keys = <String, String>{};

  /// [name]'s key, kept per name: typing asks for every item on each key.
  String keyOf(String name) => _keys[name] ??= canonicalKeyOf(name, catalog);

  (Map<String, Item>, List<Item>)? _recent;

  /// The open items with [name]'s key, oldest first, and the recently used
  /// ones ([recentlyUsed], which leaves out a thing open again).
  ({List<Item> open, List<Item> ticked}) matches(
    String name,
    Map<String, Item> items,
  ) {
    final key = keyOf(name);
    if (key.isEmpty) {
      return (open: const [], ticked: const []);
    }
    final recent = switch (_recent) {
      (final of, final rows) when identical(of, items) => rows,
      _ => recentlyUsed(items.values),
    };
    _recent = (items, recent);
    return (
      open: [
        for (final item in items.values)
          if (item.status == ItemStatus.active && keyOf(item.name) == key) item,
      ]..sort(_oldestFirst),
      ticked: [
        for (final item in recent)
          if (keyOf(item.name) == key) item,
      ],
    );
  }

  static int _oldestFirst(Item a, Item b) {
    final byCreated = a.createdAt.compareTo(b.createdAt);
    return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
  }
}

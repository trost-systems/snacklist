import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter/widgets.dart';

final _de = lookupAppLocalizations(const Locale('de'));

/// Seeded categories carry their German seed names, as
/// `public.seed_household` stores them.
final categories = [
  Category(
    id: 'produce',
    name: _de.categoryProduce,
    sortOrder: 0,
    seedKey: 'produce',
  ),
  Category(
    id: 'bakery',
    name: _de.categoryBakery,
    sortOrder: 1,
    seedKey: 'bakery',
  ),
  Category(
    id: 'chilled',
    name: _de.categoryChilled,
    sortOrder: 2,
    seedKey: 'chilled',
  ),
  Category(
    id: 'drugstore',
    name: _de.categoryDrugstore,
    sortOrder: 3,
    seedKey: 'drugstore',
  ),
];

const seededStores = [
  Store(id: 'lidl', name: 'Lidl', sortOrder: 0, seedKey: 'lidl'),
  Store(id: 'dm', name: 'dm', sortOrder: 1, seedKey: 'dm'),
  Store(id: 'rewe', name: 'REWE', sortOrder: 2, seedKey: 'rewe'),
  Store(id: 'edeka', name: 'EDEKA', sortOrder: 3, seedKey: 'edeka'),
  Store(id: 'aldi', name: 'ALDI', sortOrder: 4, seedKey: 'aldi'),
];

/// Stores the household named itself: a letter in a colour picked by name.
const ownStores = [
  Store(id: 'baecker', name: 'Bäcker Kühn', sortOrder: 5),
  Store(id: 'markt', name: 'Wochenmarkt', sortOrder: 6),
  Store(id: 'apotheke', name: 'Apotheke', sortOrder: 7),
  Store(id: 'getraenke', name: 'Getränke Hoffmann', sortOrder: 8),
];

final catalog = Catalog(
  categories: categories,
  stores: [seededStores[0], seededStores[1], ownStores[0]],
);

/// Over five stores: the store options get a search field.
final manyStores = Catalog(
  categories: catalog.categories,
  stores: [
    ...seededStores,
    ...ownStores,
    for (final (i, name) in const ['Penny', 'Netto', 'Kaufland'].indexed)
      Store(id: name.toLowerCase(), name: name, sortOrder: 100 + i * 10),
  ],
);

Item item(
  String id,
  String name, {
  required String store,
  required String category,
  String? quantity,
  double sortKey = 0,
}) {
  final at = DateTime.utc(2026, 10, 31, 12);
  return Item(
    id: id,
    name: name,
    quantity: quantity,
    status: ItemStatus.active,
    createdAt: at,
    updatedAt: at,
    storeId: store,
    categoryId: category,
    sortKey: sortKey,
  );
}

/// A short list across two stores and three categories.
final items = [
  item('1', 'Bananen', store: 'lidl', category: 'produce', quantity: '6'),
  item('2', 'Äpfel', store: 'lidl', category: 'produce', sortKey: 1),
  item('3', 'Vollmilch', store: 'lidl', category: 'chilled', quantity: '2 l'),
  item('4', 'Butter', store: 'lidl', category: 'chilled', sortKey: 1),
  item('5', 'Zahnpasta', store: 'dm', category: 'drugstore'),
  item('6', 'Brezeln', store: 'baecker', category: 'bakery', quantity: '4'),
];

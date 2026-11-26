import 'dart:io';
import 'dart:math';

import 'package:family_groceries/list/model.dart';

/// A large household for the list CPU bench (job 130): 3,000 open items,
/// 5,000 bought ones, 24 categories, 6 stores with their own walking orders
/// and 400 usuals, all drawn from one seeded [Random]. HC130_OPEN and
/// HC130_BOUGHT set other item counts (job 451 timed a 300-item list).
const fixtureSeed = 130;
final openCount =
    int.tryParse(Platform.environment['HC130_OPEN'] ?? '') ?? 3000;
final boughtCount =
    int.tryParse(Platform.environment['HC130_BOUGHT'] ?? '') ?? 5000;

final _start = DateTime.utc(2025, 11, 5, 8);

const _words = [
  'Milch',
  'Butter',
  'Joghurt',
  'Quark',
  'Sahne',
  'Käse',
  'Gouda',
  'Mozzarella',
  'Eier',
  'Brot',
  'Brötchen',
  'Toast',
  'Mehl',
  'Zucker',
  'Salz',
  'Pfeffer',
  'Reis',
  'Nudeln',
  'Spaghetti',
  'Linsen',
  'Bohnen',
  'Tomaten',
  'Gurken',
  'Paprika',
  'Zwiebeln',
  'Knoblauch',
  'Kartoffeln',
  'Möhren',
  'Karotten',
  'Äpfel',
  'Bananen',
  'Birnen',
  'Orangen',
  'Zitronen',
  'Trauben',
  'Erdbeeren',
  'Salat',
  'Spinat',
  'Brokkoli',
  'Blumenkohl',
  'Zucchini',
  'Aubergine',
  'Pilze',
  'Lauch',
  'Sellerie',
  'Hähnchen',
  'Hackfleisch',
  'Würstchen',
  'Schinken',
  'Salami',
  'Lachs',
  'Thunfisch',
  'Kaffee',
  'Tee',
  'Kakao',
  'Saft',
  'Wasser',
  'Bier',
  'Wein',
  'Limonade',
  'Müsli',
  'Haferflocken',
  'Honig',
  'Marmelade',
  'Nutella',
  'Erdnussbutter',
  'Ketchup',
  'Senf',
  'Mayonnaise',
  'Öl',
  'Essig',
  'Brühe',
  'Chips',
  'Schokolade',
  'Kekse',
  'Gummibärchen',
  'Eis',
  'Pizza',
  'Spülmittel',
  'Waschmittel',
  'Klopapier',
  'Küchenrolle',
  'Zahnpasta',
  'Shampoo',
  'Duschgel',
  'Seife',
  'Windeln',
  'Feuchttücher',
  'Müllbeutel',
  'Alufolie',
  'Backpapier',
  'Batterien',
  'Kerzen',
  'Servietten',
  'Hefe',
  'Vanille',
  'Zimt',
  'Oliven',
  'Mais',
  'Erbsen',
  'Kichererbsen',
  'Tofu',
];
const _adjectives = [
  'frische',
  'rote',
  'grüne',
  'große',
  'kleine',
  'vegane',
  'helle',
  'dunkle',
  'süße',
  'scharfe',
  'fettarme',
  'gesalzene',
];
const _brands = [
  'Weihenstephan',
  'Bärenmarke',
  'Alnatura',
  'dmBio',
  'Barilla',
  'Milka',
  'Haribo',
  'Tchibo',
  'Ja!',
  'Rewe Bio',
];
const _properties = [
  'Bio',
  'laktosefrei',
  '1,5 %',
  '3,5 %',
  'Größe 3',
  'Größe 4',
  'sensitiv',
  'glutenfrei',
  'vegan',
  'XXL',
  'Vollkorn',
  'ungesalzen',
];
const _quantities = [
  '1',
  '2',
  '3',
  '500 g',
  '1 kg',
  '2 l',
  '6 Stück',
  '250 ml',
];

/// The catalog: categories in route order, stores in household order, each
/// store with a shuffled layout that hides a few categories.
Catalog fixtureCatalog() {
  final random = Random(fixtureSeed);
  final categories = [
    for (var i = 0; i < 23; i++)
      Category(id: 'cat-$i', name: 'Kategorie $i', sortOrder: (i + 1) * 10),
    const Category(
      id: 'cat-other',
      name: 'Sonstiges',
      sortOrder: 1000,
      seedKey: 'other',
    ),
  ];
  final stores = [
    for (var i = 0; i < 6; i++)
      Store(id: 'store-$i', name: 'Laden $i', sortOrder: (i + 1) * 10),
  ];
  final layout = <StoreCategory>[];
  for (final store in stores) {
    final ids = [for (final c in categories) c.id]..shuffle(random);
    // Every store but the last has rows for most of the route; the rest
    // follow in route order.
    final placed = store.id == 'store-5' ? 6 : ids.length - 4;
    for (final (i, id) in ids.take(placed).indexed) {
      layout.add(
        StoreCategory(
          storeId: store.id,
          categoryId: id,
          sortOrder: (i + 1) * 10,
          hidden: random.nextInt(8) == 0,
        ),
      );
    }
  }
  return Catalog(
    categories: categories,
    stores: stores,
    layout: layout,
    members: const [
      Member(id: 'peter', displayName: 'Peter', role: 'owner'),
      Member(id: 'lea', displayName: 'Lea', role: 'member'),
    ],
  );
}

/// [openCount] active and [boughtCount] bought items, as the server sends
/// them. A few open items wait for a category, a few belong to a category or
/// store the catalog no longer has.
List<Item> fixtureItems() {
  final random = Random(fixtureSeed + 1);
  String id(int n) =>
      '${n.toRadixString(16).padLeft(8, '0')}-0130-4000-8000-'
      '${(n * 2654435761 % 0xffffffffffff).toRadixString(16).padLeft(12, '0')}';
  T pick<T>(List<T> from) => from[random.nextInt(from.length)];
  final items = <Item>[];
  for (var n = 0; n < openCount + boughtCount; n++) {
    final open = n < openCount;
    final word = pick(_words);
    final name = random.nextInt(4) == 0 ? '${pick(_adjectives)} $word' : word;
    final created = _start.add(
      Duration(minutes: random.nextInt(365 * 24 * 60)),
    );
    final updated = created.add(Duration(minutes: random.nextInt(600)));
    final categoryRoll = random.nextInt(1000);
    final storeRoll = random.nextInt(10);
    items.add(
      Item(
        id: id(n),
        name: name,
        status: open ? ItemStatus.active : ItemStatus.bought,
        createdAt: created,
        updatedAt: updated,
        quantity: random.nextBool() ? pick(_quantities) : null,
        brand: random.nextInt(5) == 0 ? pick(_brands) : null,
        properties: random.nextInt(4) == 0
            ? {
                pick(_properties),
                if (random.nextBool()) pick(_properties),
              }.join(', ')
            : null,
        categoryId: switch (categoryRoll) {
          < 3 when open => null,
          < 6 => 'cat-gone',
          _ =>
            random.nextInt(25) == 0 ? 'cat-other' : 'cat-${random.nextInt(23)}',
        },
        storeId: switch (storeRoll) {
          < 4 => null,
          4 when random.nextInt(20) == 0 => 'store-gone',
          _ => 'store-${random.nextInt(6)}',
        },
        sortKey: random.nextInt(50) == 0 ? null : random.nextDouble() * 1e6,
        boughtAt: open ? null : updated,
        addedBy: random.nextInt(3) == 0 ? 'lea' : 'peter',
        categorizedVia: 'exact',
        canonicalKey: foldName(word),
      ),
    );
  }
  return items;
}

/// What `suggest_items` answers for the household: 400 names, the first 60
/// due.
List<Usual> fixtureUsuals() {
  final random = Random(fixtureSeed + 2);
  final names = <String>{};
  while (names.length < 400) {
    final word = _words[random.nextInt(_words.length)];
    names.add(
      names.length < _words.length
          ? word
          : '${_adjectives[random.nextInt(_adjectives.length)]} $word '
                '${_brands[random.nextInt(_brands.length)]}',
    );
  }
  return [
    for (final (i, name) in names.indexed)
      Usual(
        name: name,
        due: i < 60,
        quantity: i.isEven ? '1' : null,
        lastUsed: _start.add(Duration(days: 300 + random.nextInt(65))),
      ),
  ];
}

/// The bench's "now": the end of the fixture's year.
final fixtureNow = _start.add(const Duration(days: 366));

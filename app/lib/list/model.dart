import 'dart:math';

import 'package:family_groceries/list/pricing.dart';
import 'package:flutter/foundation.dart' show immutable, listEquals, mapEquals;

enum ItemStatus() {
  active,
  bought,
}

@immutable
class const Category({
  required final String id,
  required final String name,
  required final int sortOrder,
  final String? seedKey,
}) {
  factory fromJson(Map<String, Object?> json) => Category(
    id: json['id']! as String,
    name: json['name']! as String,
    sortOrder: json['sort_order']! as int,
    seedKey: json['seed_key'] as String?,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'sort_order': sortOrder,
    'seed_key': seedKey,
  };
}

/// The longest store name the household can give (`public.store_name`); the
/// table keeps longer names households already had.
const maxStoreNameLength = 40;

/// The identity of a store or category name, as `public.store_name_key` and
/// `public.category_name_key`: trimmed, inner whitespace collapsed, case
/// folded. Two stores, or two categories, of a household never share it.
String nameKey(String name) =>
    name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

// Logos: retailer logos wait for a legal check (docs/DECISIONS.md, "Job 58");
// StoreBadgeStyle.logo is their slot, keyed by seedKey. Own stores have none.
@immutable
class const Store({
  required final String id,
  required final String name,
  required final int sortOrder,
  final String? seedKey,
}) {
  factory fromJson(Map<String, Object?> json) => Store(
    id: json['id']! as String,
    name: json['name']! as String,
    sortOrder: json['sort_order']! as int,
    seedKey: json['seed_key'] as String?,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'sort_order': sortOrder,
    'seed_key': seedKey,
  };

  /// Legal GL-2 (N-167): a pharmacy by its name or seed key, in any case.
  /// Its ticks raise no trip question and no "Einkauf eintragen?" card, so
  /// what is bought there is only logged when the user chooses to.
  /// Drugstores (dm, Rossmann) are not pharmacies.
  bool get isPharmacy {
    final words = '$name ${seedKey ?? ''}'.toLowerCase();
    return pharmacyWords.any(words.contains);
  }

  /// The words that mark a pharmacy (Legal GL-2, lead note 2 of job 234).
  static const pharmacyWords = [
    'apotheke',
    'pharmacy',
    'pharmacie',
    'farmacia',
    'apteka',
    'eczane',
  ];
}

/// Where a category sits in one store's walking order, and whether the store
/// carries it at all.
@immutable
class const StoreCategory({
  required final String storeId,
  required final String categoryId,
  required final int sortOrder,
  final bool hidden = false,
}) {
  factory fromJson(Map<String, Object?> json) => StoreCategory(
    storeId: json['store_id']! as String,
    categoryId: json['category_id']! as String,
    sortOrder: json['sort_order']! as int,
    hidden: json['hidden']! as bool,
  );

  Map<String, Object?> toJson() => {
    'store_id': storeId,
    'category_id': categoryId,
    'sort_order': sortOrder,
    'hidden': hidden,
  };
}

const defaultCurrency = 'EUR';

/// The household's categories, stores and store layouts: everything the list
/// is sorted by. [categories] and [stores] are in their sort order.
@immutable
class const Catalog({
  final List<Category> categories = const [],
  final List<Store> stores = const [],
  final List<StoreCategory> layout = const [],
  final List<Member> members = const [],

  /// The household's lists in their order (job 169b K); empty from a server
  /// or a device copy without lists, which shows every item as one list.
  final List<HouseholdList> lists = const [],

  /// The household's currency, an ISO 4217 code (job 190).
  final String currency = defaultCurrency,
}) {
  factory fromJson(Map<String, Object?> json) => Catalog(
    categories: [
      for (final row in json['categories']! as List<Object?>)
        Category.fromJson(row! as Map<String, Object?>),
    ],
    stores: [
      for (final row in json['stores']! as List<Object?>)
        Store.fromJson(row! as Map<String, Object?>),
    ],
    layout: [
      for (final row in json['layout']! as List<Object?>)
        StoreCategory.fromJson(row! as Map<String, Object?>),
    ],
    members: [
      for (final row in json['members']! as List<Object?>)
        Member.fromJson(row! as Map<String, Object?>),
    ],
    lists: [
      for (final row in json['lists']! as List<Object?>)
        HouseholdList.fromJson(row! as Map<String, Object?>),
    ],
    currency: json['currency'] as String? ?? defaultCurrency,
  );

  Map<String, Object?> toJson() => {
    'categories': [for (final c in categories) c.toJson()],
    'stores': [for (final s in stores) s.toJson()],
    'layout': [for (final row in layout) row.toJson()],
    'members': [for (final m in members) m.toJson()],
    'lists': [for (final l in lists) l.toJson()],
    'currency': currency,
  };

  Catalog withCurrency(String currency) => Catalog(
    categories: categories,
    stores: stores,
    layout: layout,
    members: members,
    lists: lists,
    currency: currency,
  );

  HouseholdList? list(String? id) => lists.where((l) => l.id == id).firstOrNull;

  /// [list] added after the others.
  Catalog withList(HouseholdList list) => _withLists([...lists, list]);

  Catalog withListName(String listId, String name) => _withLists([
    for (final l in lists)
      if (l.id == listId)
        HouseholdList(
          id: l.id,
          name: name,
          position: l.position,
          seedKey: l.seedKey,
        )
      else
        l,
  ]);

  Catalog withoutList(String listId) =>
      _withLists([...lists.where((l) => l.id != listId)]);

  /// The list order is the position in [ids].
  Catalog withListOrder(List<String> ids) {
    final byId = {for (final l in lists) l.id: l};
    return _withLists([
      for (final (i, id) in ids.indexed)
        if (byId[id] case final l?)
          HouseholdList(
            id: l.id,
            name: l.name,
            position: i,
            seedKey: l.seedKey,
          ),
    ]);
  }

  Catalog _withLists(List<HouseholdList> lists) => Catalog(
    categories: categories,
    stores: stores,
    layout: layout,
    members: members,
    lists: lists,
    currency: currency,
  );

  Member? member(String? id) => members.where((m) => m.id == id).firstOrNull;

  Category? get fallback =>
      categories.where((c) => c.seedKey == 'other').firstOrNull;

  Store? store(String id) => stores.where((s) => s.id == id).firstOrNull;

  /// The store with [name], in any case or spacing.
  Store? storeNamed(String name) {
    final key = nameKey(name);
    return stores.where((s) => nameKey(s.name) == key).firstOrNull;
  }

  /// [store] added after the others; its layout follows the route order.
  Catalog withStore(Store store) => Catalog(
    categories: categories,
    stores: [...stores, store],
    layout: layout,
    members: members,
    lists: lists,
    currency: currency,
  );

  /// A chain store given another name stops being its chain, as
  /// `public.rename_store` does. The Baumarkt is a store type, not a chain:
  /// it stays the hardware store under any name.
  Catalog withStoreName(String storeId, String name) => Catalog(
    categories: categories,
    stores: [
      for (final s in stores)
        if (s.id == storeId)
          Store(
            id: s.id,
            name: name,
            sortOrder: s.sortOrder,
            seedKey: s.seedKey == 'hardware' || nameKey(name) == nameKey(s.name)
                ? s.seedKey
                : null,
          )
        else
          s,
    ],
    layout: layout,
    members: members,
    lists: lists,
    currency: currency,
  );

  Catalog withoutStore(String storeId) => Catalog(
    categories: categories,
    stores: [...stores.where((s) => s.id != storeId)],
    layout: [...layout.where((row) => row.storeId != storeId)],
    members: members,
    lists: lists,
    currency: currency,
  );

  /// The store order is the position in [ids].
  Catalog withStoreOrder(List<String> ids) {
    final byId = {for (final s in stores) s.id: s};
    return Catalog(
      categories: categories,
      stores: [
        for (final (i, id) in ids.indexed)
          if (byId[id] case final s?)
            Store(
              id: s.id,
              name: s.name,
              sortOrder: (i + 1) * 10,
              seedKey: s.seedKey,
            ),
      ],
      layout: layout,
      members: members,
      lists: lists,
      currency: currency,
    );
  }

  /// The route order is the position in [ids].
  Catalog withRouteOrder(List<String> ids) {
    final byId = {for (final c in categories) c.id: c};
    return Catalog(
      categories: [
        for (final (i, id) in ids.indexed)
          if (byId[id] case final c?)
            Category(
              id: c.id,
              name: c.name,
              sortOrder: (i + 1) * 10,
              seedKey: c.seedKey,
            ),
      ],
      stores: stores,
      layout: layout,
      members: members,
      lists: lists,
      currency: currency,
    );
  }

  Catalog withName(String categoryId, String name) => Catalog(
    categories: [
      for (final c in categories)
        if (c.id == categoryId)
          Category(
            id: c.id,
            name: name,
            sortOrder: c.sortOrder,
            seedKey: c.seedKey,
          )
        else
          c,
    ],
    stores: stores,
    layout: layout,
    members: members,
    lists: lists,
    currency: currency,
  );

  Catalog withStoreLayout(
    String storeId,
    List<String> orderedIds,
    Set<String> hiddenIds,
  ) => Catalog(
    categories: categories,
    stores: stores,
    layout: [
      ...layout.where((row) => row.storeId != storeId),
      for (final (i, id) in orderedIds.indexed)
        StoreCategory(
          storeId: storeId,
          categoryId: id,
          sortOrder: (i + 1) * 10,
          hidden: hiddenIds.contains(id),
        ),
    ],
    members: members,
    lists: lists,
    currency: currency,
  );
}

/// Longest list name the server takes (`lists.name`, 1 to 60).
const maxListNameLength = 60;

/// One of a household's lists (job 169b K): "Wocheneinkauf" next to
/// "Baumarkt". Stores, categories and their order are the household's, not
/// the list's.
@immutable
class const HouseholdList({
  required final String id,
  required final String name,
  required final int position,

  /// `main` on the list the household started with: shown in the UI
  /// language while it keeps its seeded name (`listName`).
  final String? seedKey,
}) {
  factory fromJson(Map<String, Object?> json) => HouseholdList(
    id: json['id']! as String,
    name: json['name']! as String,
    position: json['position']! as int,
    seedKey: json['seed_key'] as String?,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'position': position,
    'seed_key': ?seedKey,
  };
}

/// A member's "Ich bringe das" on an open item (job 169b L), with the
/// amount they bring, if they named one. One per item and member.
///
/// [id] is the server's random key, which a realtime delete names (and
/// nothing else); null for a claim the server has not told yet.
@immutable
class const Claim({
  required final String itemId,
  required final String userId,
  required final DateTime createdAt,
  final String? id,
  final String? quantity,
}) {
  factory fromJson(Map<String, Object?> json) => Claim(
    id: json['id'] as String?,
    itemId: json['item_id']! as String,
    userId: json['user_id']! as String,
    quantity: json['quantity'] as String?,
    createdAt: DateTime.parse(json['created_at']! as String),
  );

  Map<String, Object?> toJson() => {
    'id': ?id,
    'item_id': itemId,
    'user_id': userId,
    'quantity': quantity,
    'created_at': createdAt.toIso8601String(),
  };

  ClaimKey get key => (itemId, userId);
}

/// A claim's identity: the item and the member.
typedef ClaimKey = (String itemId, String userId);

/// The claims the list shows, by item id, oldest first: the server's, with
/// the pending claim ops folded on top. A tick or a delete ends an item's
/// claims, as the server's trigger does; only [items] that are open keep
/// theirs.
Map<String, List<Claim>> visibleClaims(
  Map<ClaimKey, Claim> server,
  Iterable<ItemOp> pending,
  Map<String, Item> items,
) {
  final view = Map.of(server);
  for (final op in pending) {
    switch (op) {
      case ClaimItem(:final userId, :final quantity, :final at):
        view[(op.itemId, userId)] = Claim(
          id: view[(op.itemId, userId)]?.id,
          itemId: op.itemId,
          userId: userId,
          quantity: quantity,
          createdAt: view[(op.itemId, userId)]?.createdAt ?? at,
        );
      case UnclaimItem(:final userId):
        view.remove((op.itemId, userId));
      case SetStatus(status: ItemStatus.bought) || DeleteItem():
        view.removeWhere((key, _) => key.$1 == op.itemId);
      case MergeItems(:final otherId):
        view.removeWhere((key, _) => key.$1 == otherId);
      default:
    }
  }
  final byItem = <String, List<Claim>>{};
  for (final claim in view.values) {
    if (items[claim.itemId]?.status == ItemStatus.active) {
      (byItem[claim.itemId] ??= []).add(claim);
    }
  }
  for (final claims in byItem.values) {
    claims.sort((a, b) {
      final byCreated = a.createdAt.compareTo(b.createdAt);
      return byCreated != 0 ? byCreated : a.userId.compareTo(b.userId);
    });
  }
  return byItem;
}

/// A household member as the list names them.
@immutable
class const Member({
  required final String id,
  required final String displayName,

  /// `owner` or `member`; null in a list cached before job 19.
  final String? role,
}) {
  factory fromJson(Map<String, Object?> json) => Member(
    id: json['id']! as String,
    displayName: json['display_name']! as String,
    role: json['role'] as String?,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'display_name': displayName,
    'role': ?role,
  };
}

/// A category in a store's walking order; `hidden` when the store does not
/// carry it.
typedef Stop = ({Category category, bool hidden});

/// The categories in the order [storeId] walks them, or in route order for
/// no store. A store's layout rows come first; categories it has no row for
/// follow in route order.
List<Stop> walkingOrder(Catalog catalog, String? storeId) {
  final route = [...catalog.categories]
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  if (storeId == null) {
    return [for (final c in route) (category: c, hidden: false)];
  }
  final rows = catalog.layout.where((row) => row.storeId == storeId).toList()
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  final byId = {for (final c in route) c.id: c};
  final placed = {for (final row in rows) row.categoryId};
  return [
    for (final row in rows)
      if (byId[row.categoryId] case final c?) (category: c, hidden: row.hidden),
    for (final c in route)
      if (!placed.contains(c.id)) (category: c, hidden: false),
  ];
}

@immutable
class const Item({
  required final String id,
  required final String name,
  required final ItemStatus status,
  required final DateTime createdAt,
  required final DateTime updatedAt,
  final String? quantity,

  /// Marke.
  final String? brand,

  /// Eigenschaften, parts joined with ", ".
  final String? properties,

  /// Null only while a new item waits for the server to classify it.
  final String? categoryId,
  final String? storeId,

  /// Walk order inside its (store, category) group, lower first. Null only
  /// until the server numbers a new item; it sorts last.
  final double? sortKey,
  final DateTime? boughtAt,

  /// The member who added it; null until the server confirms the add, and
  /// in snapshots older than the field.
  final String? addedBy,

  /// How the server chose the category on insert (`categorized_via`:
  /// household, exact, synonym, fuzzy, fallback, picked); null until it
  /// confirms the add, and on rows from before job 32a. For analytics only.
  final String? categorizedVia,

  /// `items.canonical_key` (job 32a): spelling variants and synonyms share
  /// it ("Karotten" and "Möhren" give "mohr"). Null until the server confirms
  /// the add; the duplicate hint matches on it (job 32b).
  final String? canonicalKey,

  /// The list it is on (job 169b K). Null in a device copy from before
  /// lists, and for an add queued then: it is on the household's first
  /// list, where the server puts an add without one.
  final String? listId,

  /// Its price (job 190); null for none.
  final Price? price,
}) {
  factory fromJson(Map<String, Object?> json) => Item(
    id: json['id']! as String,
    name: json['name']! as String,
    quantity: json['quantity'] as String?,
    brand: json['brand'] as String?,
    properties: json['properties'] as String?,
    categoryId: json['category_id'] as String?,
    storeId: json['store_id'] as String?,
    // PostgREST sends a whole double precision as an int.
    sortKey: (json['sort_key'] as num?)?.toDouble(),
    status: ItemStatus.values.byName(json['status']! as String),
    createdAt: DateTime.parse(json['created_at']! as String),
    updatedAt: DateTime.parse(json['updated_at']! as String),
    boughtAt: switch (json['bought_at']) {
      final String at => DateTime.parse(at),
      _ => null,
    },
    addedBy: json['added_by'] as String?,
    categorizedVia: json['categorized_via'] as String?,
    canonicalKey: json['canonical_key'] as String?,
    listId: json['list_id'] as String?,
    price: Price.fromColumns(json),
  );

  /// The same keys as a server row, so [Item.fromJson] reads it back.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'quantity': quantity,
    'brand': brand,
    'properties': properties,
    'category_id': categoryId,
    'store_id': storeId,
    'sort_key': sortKey,
    'status': status.name,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'bought_at': boughtAt?.toIso8601String(),
    'added_by': addedBy,
    'categorized_via': categorizedVia,
    'canonical_key': canonicalKey,
    'list_id': listId,
    ...price?.toColumns() ?? Price.noColumns,
  };

  Item copyWith({
    String? name,
    String? Function()? quantity,
    String? Function()? brand,
    String? Function()? properties,
    String? categoryId,
    String? Function()? storeId,
    double? Function()? sortKey,
    ItemStatus? status,
    DateTime? Function()? boughtAt,
    String? listId,
    Price? Function()? price,
  }) => Item(
    id: id,
    name: name ?? this.name,
    quantity: quantity == null ? this.quantity : quantity(),
    brand: brand == null ? this.brand : brand(),
    properties: properties == null ? this.properties : properties(),
    categoryId: categoryId ?? this.categoryId,
    storeId: storeId == null ? this.storeId : storeId(),
    sortKey: sortKey == null ? this.sortKey : sortKey(),
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt,
    boughtAt: boughtAt == null ? this.boughtAt : boughtAt(),
    addedBy: addedBy,
    categorizedVia: categorizedVia,
    canonicalKey: canonicalKey,
    listId: listId ?? this.listId,
    price: price == null ? this.price : price(),
  );

  /// The list it is on, where [firstList] is the household's first list.
  String? listOn(String? firstList) => listId ?? firstList;

  /// Added by another member (not by [userId], and not still unconfirmed).
  bool isFromPartner(String userId) => addedBy != null && addedBy != userId;
}

/// Walk order inside a group: [Item.sortKey] (null last), then created,
/// then id, as the server orders it.
int compareWalk(Item a, Item b) {
  final (ka, kb) = (a.sortKey, b.sortKey);
  final byKey = switch ((ka, kb)) {
    (null, null) => 0,
    (null, _) => 1,
    (_, null) => -1,
    (final x?, final y?) => x.compareTo(y),
  };
  if (byKey != 0) {
    return byKey;
  }
  final byCreated = a.createdAt.compareTo(b.createdAt);
  return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
}

/// A nullable column an edit sets, to [value] (null clears it). An edit
/// that leaves the column alone has no [SetTo] for it.
@immutable
final class const SetTo<T>(final T value) {
  @override
  bool operator ==(Object other) => other is SetTo<T> && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'SetTo($value)';
}

/// The columns one edit changes; everything null here is left alone.
@immutable
class const ItemChanges({
  final String? name,
  final SetTo<String?>? quantity,
  final SetTo<String?>? brand,
  final SetTo<String?>? properties,
  final String? categoryId,

  /// `SetTo(null)`: no store.
  final SetTo<String?>? storeId,
}) {
  /// Reads what [toColumns] wrote: a key present is a change.
  factory fromColumns(Map<String, Object?> json) {
    SetTo<String?>? change(String key) =>
        json.containsKey(key) ? SetTo(json[key] as String?) : null;
    return ItemChanges(
      name: json['name'] as String?,
      quantity: change('quantity'),
      brand: change('brand'),
      properties: change('properties'),
      categoryId: json['category_id'] as String?,
      storeId: change('store_id'),
    );
  }

  bool get isEmpty => toColumns().isEmpty;

  /// The name, brand or details change: what tells open items apart.
  bool get renames => name != null || brand != null || properties != null;

  /// Only the changed columns, as the server names them: the PATCH body.
  Map<String, Object?> toColumns() => {
    'name': ?name,
    if (quantity case SetTo(:final value)) 'quantity': value,
    if (brand case SetTo(:final value)) 'brand': value,
    if (properties case SetTo(:final value)) 'properties': value,
    'category_id': ?categoryId,
    if (storeId case SetTo(:final value)) 'store_id': value,
  };

  Item apply(Item item) => item.copyWith(
    name: name,
    quantity: switch (quantity) {
      SetTo(:final value) => () => value,
      null => null,
    },
    brand: switch (brand) {
      SetTo(:final value) => () => value,
      null => null,
    },
    properties: switch (properties) {
      SetTo(:final value) => () => value,
      null => null,
    },
    categoryId: categoryId,
    storeId: switch (storeId) {
      SetTo(:final value) => () => value,
      null => null,
    },
  );

  @override
  bool operator ==(Object other) =>
      other is ItemChanges && mapEquals(other.toColumns(), toColumns());

  @override
  int get hashCode => Object.hashAllUnordered(
    toColumns().entries.map((e) => Object.hash(e.key, e.value)),
  );

  @override
  String toString() => 'ItemChanges(${toColumns()})';
}

enum Edge() {
  before,
  after,
}

/// What `public.parse_item` makes of one typed entry. [deviceParsed]: the
/// device split it alone (offline), into name and quantity only; the
/// server splits off brand and details when the add syncs.
@immutable
class const ParsedEntry({
  required final String name,
  final String? brand,
  final String? properties,
  final String? quantity,
  final String? storeId,
  final String? categoryId,
  final bool deviceParsed = false,
}) {
  factory fromJson(Map<String, Object?> json) => ParsedEntry(
    name: json['name']! as String,
    brand: json['brand'] as String?,
    properties: json['properties'] as String?,
    quantity: json['quantity'] as String?,
    storeId: json['store_id'] as String?,
    categoryId: json['category_id'] as String?,
  );

  /// [item], typed offline, with what parse_item read from its name: the
  /// name, and the brand, details, Menge, store and category the device
  /// left open ("Windeln Pampers Größe 3" is Windeln, Pampers, Größe 3).
  /// [noStore]: the user picked „Ohne Laden“, so no store is taken.
  Item onto(Item item, {required bool noStore}) => item.copyWith(
    // A line parse_item reads no name from keeps the device's.
    name: name.trim().isEmpty ? item.name : name,
    quantity: () => item.quantity ?? quantity,
    brand: () => item.brand ?? brand,
    properties: () => item.properties ?? properties,
    storeId: () => noStore ? null : item.storeId ?? storeId,
    categoryId: item.categoryId ?? categoryId,
  );

  /// [changes], a rename of an add typed offline that has not synced yet,
  /// with what parse_item read from the new name: the name, and the brand
  /// and details it names (none: none), unless the edit set them too.
  ItemChanges ontoRename(ItemChanges changes) => ItemChanges(
    name: name.trim().isEmpty ? changes.name : name,
    quantity: changes.quantity ?? (quantity == null ? null : SetTo(quantity)),
    brand: changes.brand ?? SetTo(brand),
    properties: changes.properties ?? SetTo(properties),
    categoryId: changes.categoryId,
    storeId: changes.storeId,
  );
}

/// A user's intent, applied optimistically on top of the server state until
/// the server acknowledges it. Every op is idempotent so it can be retried.
sealed class const ItemOp(final String itemId) {
  /// Reads what [toJson] wrote; throws on anything else.
  factory fromJson(Map<String, Object?> json) {
    final id = json['item_id']! as String;
    return switch (json['op']) {
      'add' => AddItem(
        Item.fromJson(json['item']! as Map<String, Object?>),
        restored: json['restored'] == true,
        noStore: json['no_store'] == true,
        deviceParsed: json['device_parsed'] == true,
        autoCategory: json['auto_category'] == true,
      ),
      'status' => SetStatus(
        id,
        ItemStatus.values.byName(json['status']! as String),
        DateTime.parse(json['at']! as String),
        storeId: json['store_id'] as String?,
      ),
      'edit' => EditItem(
        id,
        ItemChanges.fromColumns(json['changes']! as Map<String, Object?>),
        keyBefore: json['key_before'] as String?,
        deviceParsed: json['device_parsed'] == true,
      ),
      'move' => MoveItem(
        id,
        categoryId: json['category_id']! as String,
        storeId: json['store_id'] as String?,
      ),
      'place' => PlaceItem(
        id,
        anchorId: json['anchor_id']! as String,
        edge: Edge.values.byName(json['edge']! as String),
        categoryId: json['category_id']! as String,
        storeId: json['store_id'] as String?,
        sortKey: (json['sort_key'] as num?)?.toDouble(),
      ),
      'delete' => DeleteItem(id),
      'merge' => MergeItems(
        id,
        mergeId: json['merge_id']! as String,
        otherId: json['other_id']! as String,
        quantity: json['quantity'] as String?,
        brand: json['brand'] as String?,
        properties: json['properties'] as String?,
      ),
      'unmerge' => UnmergeItems(
        id,
        mergeId: json['merge_id']! as String,
        kept: Item.fromJson(json['kept']! as Map<String, Object?>),
        merged: Item.fromJson(json['merged']! as Map<String, Object?>),
      ),
      'list' => MoveToList(id, listId: json['list_id']! as String),
      'claim' => ClaimItem(
        id,
        userId: json['user_id']! as String,
        quantity: json['quantity'] as String?,
        at: DateTime.parse(json['at']! as String),
      ),
      'unclaim' => UnclaimItem(id, userId: json['user_id']! as String),
      'price' => SetPrice(
        id,
        price: switch (json['price']) {
          final Map<String, Object?> columns => Price.fromColumns(columns),
          _ => null,
        },
        quantity: json.containsKey('quantity')
            ? SetTo(json['quantity'] as String?)
            : null,
        restored: json['restored'] == true,
      ),
      final op => throw FormatException('unknown op', op),
    };
  }

  /// The item as the user should see it once this op lands.
  Item? apply(Item? current);

  /// This op once the add of [from] turned out to be the open item [kept]
  /// (`put_item`, DECISIONS Job 64b): changes go to [kept]; a delete is
  /// dropped, since it removed only this copy and [kept] is someone's entry;
  /// null when nothing is left to do. Adds and merge undos stay as they are.
  ItemOp? ontoKept(String from, String kept) {
    final touches = switch (this) {
      PlaceItem(:final anchorId) => anchorId == from,
      MergeItems(:final otherId) => otherId == from,
      _ => false,
    };
    if (itemId != from && !touches) {
      return this;
    }
    String to(String id) => id == from ? kept : id;
    return switch (this) {
      AddItem() || UnmergeItems() => this,
      DeleteItem() => null,
      SetStatus(:final status, :final at, :final storeId) => SetStatus(
        kept,
        status,
        at,
        storeId: storeId,
      ),
      EditItem(:final changes, :final keyBefore, :final deviceParsed) =>
        EditItem(
          kept,
          changes,
          keyBefore: keyBefore,
          deviceParsed: deviceParsed,
        ),
      MoveItem(:final categoryId, :final storeId) => MoveItem(
        kept,
        categoryId: categoryId,
        storeId: storeId,
      ),
      MoveToList(:final listId) => MoveToList(kept, listId: listId),
      ClaimItem(:final userId, :final quantity, :final at) => ClaimItem(
        kept,
        userId: userId,
        quantity: quantity,
        at: at,
      ),
      UnclaimItem(:final userId) => UnclaimItem(kept, userId: userId),
      // An undone delete's price is that copy's: a partner's open twin
      // keeps its own.
      SetPrice(restored: true) => null,
      SetPrice(:final price, :final quantity) => SetPrice(
        kept,
        price: price,
        quantity: quantity,
      ),
      PlaceItem(
        :final anchorId,
        :final edge,
        :final categoryId,
        :final storeId,
        :final sortKey,
      ) =>
        to(itemId) == to(anchorId)
            ? null
            : PlaceItem(
                to(itemId),
                anchorId: to(anchorId),
                edge: edge,
                categoryId: categoryId,
                storeId: storeId,
                sortKey: sortKey,
              ),
      MergeItems(
        :final mergeId,
        :final otherId,
        :final quantity,
        :final brand,
        :final properties,
      ) =>
        to(itemId) == to(otherId)
            ? null
            : MergeItems(
                to(itemId),
                mergeId: mergeId,
                otherId: to(otherId),
                quantity: quantity,
                brand: brand,
                properties: properties,
              ),
    };
  }

  /// Folds this op into [view], the items by id. Ops on one item apply to
  /// it; a merge or its undo touches two.
  void applyTo(Map<String, Item> view) {
    final next = apply(view[itemId]);
    if (next == null) {
      view.remove(itemId);
    } else {
      view[itemId] = next;
    }
  }

  Map<String, Object?> toJson() => {
    'item_id': itemId,
    ...switch (this) {
      AddItem(
        :final item,
        :final restored,
        :final noStore,
        :final deviceParsed,
        :final autoCategory,
      ) =>
        {
          'op': 'add',
          'item': item.toJson(),
          if (restored) 'restored': true,
          if (noStore) 'no_store': true,
          if (deviceParsed) 'device_parsed': true,
          if (autoCategory) 'auto_category': true,
        },
      SetStatus(:final status, :final at, :final storeId) => {
        'op': 'status',
        'status': status.name,
        'at': at.toIso8601String(),
        'store_id': storeId,
      },
      EditItem(:final changes, :final keyBefore, :final deviceParsed) => {
        'op': 'edit',
        'changes': changes.toColumns(),
        'key_before': ?keyBefore,
        if (deviceParsed) 'device_parsed': true,
      },
      MoveItem(:final categoryId, :final storeId) => {
        'op': 'move',
        'category_id': categoryId,
        'store_id': storeId,
      },
      PlaceItem(
        :final anchorId,
        :final edge,
        :final categoryId,
        :final storeId,
        :final sortKey,
      ) =>
        {
          'op': 'place',
          'anchor_id': anchorId,
          'edge': edge.name,
          'category_id': categoryId,
          'store_id': storeId,
          'sort_key': sortKey,
        },
      DeleteItem() => {'op': 'delete'},
      MoveToList(:final listId) => {'op': 'list', 'list_id': listId},
      ClaimItem(:final userId, :final quantity, :final at) => {
        'op': 'claim',
        'user_id': userId,
        'quantity': quantity,
        'at': at.toIso8601String(),
      },
      UnclaimItem(:final userId) => {'op': 'unclaim', 'user_id': userId},
      SetPrice(:final price, :final quantity, :final restored) => {
        'op': 'price',
        'price': price?.toColumns(),
        if (quantity case SetTo(:final value)) 'quantity': value,
        if (restored) 'restored': true,
      },
      MergeItems(
        :final mergeId,
        :final otherId,
        :final quantity,
        :final brand,
        :final properties,
      ) =>
        {
          'op': 'merge',
          'merge_id': mergeId,
          'other_id': otherId,
          'quantity': quantity,
          'brand': brand,
          'properties': properties,
        },
      UnmergeItems(:final mergeId, :final kept, :final merged) => {
        'op': 'unmerge',
        'merge_id': mergeId,
        'kept': kept.toJson(),
        'merged': merged.toJson(),
      },
    },
  };
}

/// [restored]: a deleted item put back (the delete's undo), not a new add.
/// [noStore]: without a store; otherwise a missing store is the remembered
/// one. [deviceParsed]: the name is a line typed offline, which parse_item
/// splits before the add is sent ([ParsedEntry.onto]). [autoCategory]: the
/// server classifies the item when it inserts it, and [item]'s category only
/// shows until then, so a category correction queued ahead of this add is
/// learned first. The server answers with the open item the add already is
/// when the list has one (`put_item`), and the app folds this item into it
/// ([ItemOp.ontoKept]).
final class AddItem(
  final Item item, {
  final bool restored = false,
  final bool noStore = false,
  final bool deviceParsed = false,
  final bool autoCategory = false,
}) extends ItemOp {
  this : super(item.id);

  @override
  Item? apply(Item? current) => current ?? item;
}

/// Ticking at a store ([storeId] set) also tags the item to that store.
final class const SetStatus(
  super.itemId,
  final ItemStatus status,
  final DateTime at, {
  final String? storeId,
}) extends ItemOp {
  @override
  Item? apply(Item? current) => current?.copyWith(
    status: status,
    boughtAt: () => status == ItemStatus.bought ? at : null,
    storeId: storeId == null ? null : () => storeId,
  );
}

/// Writes only the [changes]; the server puts an item whose store or
/// category changed at the end of its new group. [deviceParsed]: a rename
/// of an add typed offline that had not synced; parse_item splits the new
/// name as it splits the add's ([ParsedEntry.ontoRename]).
final class const EditItem(
  super.itemId,
  final ItemChanges changes, {

  /// The item's `canonical_key` when a rename was made: its acknowledgement
  /// offers a merge with a synonym only when the server keyed the item anew,
  /// also when the new key arrived first (realtime, a resync, a restart).
  /// Null when the server had not keyed it yet (an add still queued).
  final String? keyBefore,
  final bool deviceParsed = false,
}) extends ItemOp {
  @override
  Item? apply(Item? current) => current == null ? null : changes.apply(current);
}

/// To the end of group ([storeId], [categoryId]), with `move_item`. Until
/// the server numbers it, the key is null, which sorts last.
final class const MoveItem(
  super.itemId, {
  required final String categoryId,

  /// Null: no store.
  required final String? storeId,
}) extends ItemOp {
  @override
  Item? apply(Item? current) => current?.copyWith(
    categoryId: categoryId,
    storeId: () => storeId,
    sortKey: () => null,
  );
}

/// Directly before or after [anchorId], with `place_item`. [categoryId],
/// [storeId] and the provisional [sortKey] are the anchor's group and the
/// gap as the app saw them, for the optimistic view; the server decides.
final class const PlaceItem(
  super.itemId, {
  required final String anchorId,
  required final Edge edge,
  required final String categoryId,
  required final String? storeId,

  /// Null when the anchor had no key yet.
  required final double? sortKey,
}) extends ItemOp {
  @override
  Item? apply(Item? current) => current?.copyWith(
    categoryId: categoryId,
    storeId: () => storeId,
    sortKey: () => sortKey,
  );
}

final class const DeleteItem(super.itemId) extends ItemOp {
  @override
  Item? apply(Item? current) => null;
}

/// Onto the household's list [listId] (job 169b K), keeping its store,
/// category and place: an `items.list_id` update.
final class const MoveToList(super.itemId, {required final String listId})
    extends ItemOp {
  @override
  Item? apply(Item? current) => current?.copyWith(listId: listId);
}

/// [userId]'s "Ich bringe das" on the item (job 169b L), with the amount
/// they bring or none: `claim_item`, which replaces their earlier claim.
/// [at] is when they said so, for the order until the server answers.
/// Claims are not part of the item ([visibleClaims] folds this op).
final class const ClaimItem(
  super.itemId, {
  required final String userId,
  required final DateTime at,
  final String? quantity,
}) extends ItemOp {
  @override
  Item? apply(Item? current) => current;
}

/// Takes [userId]'s claim back: `unclaim_item`.
final class const UnclaimItem(super.itemId, {required final String userId})
    extends ItemOp {
  @override
  Item? apply(Item? current) => current;
}

/// Sets or clears the item's [price] (job 190), and its [quantity] when
/// set: the scale weight replaces the planned one, the stepper's count the
/// typed one. Never its status: a price does not tick an item, a tick
/// needs no price (t832u). [restored]: the price of a deleted item put
/// back, dropped when the add lands on an open twin.
final class const SetPrice(
  super.itemId, {
  required final Price? price,
  final SetTo<String?>? quantity,
  final bool restored = false,
}) extends ItemOp {
  /// The PATCH body: all five price columns, and the quantity when set.
  Map<String, Object?> toColumns() => {
    ...price?.toColumns() ?? Price.noColumns,
    if (quantity case SetTo(:final value)) 'quantity': value,
  };

  @override
  Item? apply(Item? current) => current?.copyWith(
    price: () => price,
    quantity: switch (quantity) {
      SetTo(:final value) => () => value,
      null => null,
    },
  );
}

/// Folds the open item [otherId] into the open item [itemId] with
/// `merge_items` (job 32b): the kept item keeps its name and takes the merged
/// [quantity] and details (computed in the app for the optimistic view; the
/// server merges by the same rule), the other one goes. [mergeId] makes a
/// retry the same merge.
final class const MergeItems(
  super.itemId, {
  required final String mergeId,
  required final String otherId,
  required final String? quantity,
  required final String? brand,
  required final String? properties,
}) extends ItemOp {
  @override
  Item? apply(Item? current) => current?.copyWith(
    quantity: () => quantity,
    brand: () => brand,
    properties: () => properties,
  );

  @override
  void applyTo(Map<String, Item> view) {
    super.applyTo(view);
    view.remove(otherId);
  }
}

/// Undoes the merge [mergeId] with `unmerge_items`: [merged] comes back and
/// the kept item gets its quantity and details back, as both were before the
/// merge (the server decides; DECISIONS, Job 32b).
final class const UnmergeItems(
  super.itemId, {
  required final String mergeId,
  required final Item kept,
  required final Item merged,
}) extends ItemOp {
  @override
  Item? apply(Item? current) => current?.copyWith(
    quantity: () => kept.quantity,
    brand: () => kept.brand,
    properties: () => kept.properties,
  );

  @override
  void applyTo(Map<String, Item> view) {
    super.applyTo(view);
    view[merged.id] ??= merged;
  }
}

/// Server truth plus the pending ops folded on top: what the list shows.
Map<String, Item> visibleItems(
  Map<String, Item> server,
  Iterable<ItemOp> pending,
) {
  final view = Map.of(server);
  for (final op in pending) {
    op.applyTo(view);
  }
  return view;
}

/// The other open items the duplicate hint names for [item], oldest first:
/// the same non-empty canonical key and details that do not tell them apart,
/// as `public.similar_items` finds them for MCP and Siri.
List<Item> similarItems(Item item, Iterable<Item> items) {
  final key = item.canonicalKey;
  if (key == null || key.isEmpty) {
    return const [];
  }
  return [
    for (final other in items)
      if (other.id != item.id &&
          other.status == ItemStatus.active &&
          other.canonicalKey == key &&
          !detailsDiffer(item, other))
        other,
  ]..sort((a, b) {
    final byCreated = a.createdAt.compareTo(b.createdAt);
    return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
  });
}

/// Brand or properties set on both and different: "Windeln Größe 3" and
/// "Windeln Größe 4" are two things, "Milch" and "Milch Weihenstephan" may be
/// one (`public.details_differ`).
bool detailsDiffer(Item a, Item b) {
  final (brandA, brandB) = (foldName(a.brand ?? ''), foldName(b.brand ?? ''));
  if (brandA.isNotEmpty && brandB.isNotEmpty && brandA != brandB) {
    return true;
  }
  List<String> parts(String? properties) =>
      (properties ?? '')
          .split(',')
          .where((p) => p.trim().isNotEmpty)
          .map(foldName)
          .toList()
        ..sort();
  final (propsA, propsB) = (parts(a.properties), parts(b.properties));
  return propsA.isNotEmpty && propsB.isNotEmpty && !listEquals(propsA, propsB);
}

/// Merges a server row, ignoring echoes older than what is already known.
Map<String, Item> mergeServerRow(Map<String, Item> server, Item row) {
  final known = server[row.id];
  if (known != null && known.updatedAt.isAfter(row.updatedAt)) {
    return server;
  }
  return {...server, row.id: row};
}

/// Bought items, most recent first: the list's "Zuletzt verwendet". One
/// row per thing (`canonical_key`, else the folded name), its newest
/// purchase, and none for a thing that is on the list again.
List<Item> recentlyUsed(Iterable<Item> items, {int limit = 20}) {
  String thing(Item i) => i.canonicalKey ?? foldName(i.name);
  final open = {
    for (final i in items)
      if (i.status == ItemStatus.active) thing(i),
  };
  final bought = items.where((i) => i.status == ItemStatus.bought).toList()
    ..sort(
      (a, b) =>
          (b.boughtAt ?? b.updatedAt).compareTo(a.boughtAt ?? a.updatedAt),
    );
  final seen = <String>{};
  return [
    for (final i in bought)
      if (!open.contains(thing(i)) && seen.add(thing(i))) i,
  ].take(limit).toList();
}

/// Something the household buys again and again, as `public.suggest_items`
/// ranks it; [due] when its usual interval since the last purchase is up.
@immutable
class const Usual({
  required final String name,
  required final bool due,
  final String? quantity,

  /// When it was last added or bought.
  final DateTime? lastUsed,
}) {
  factory fromJson(Map<String, Object?> json) => Usual(
    name: json['name']! as String,
    quantity: json['quantity'] as String?,
    due: json['due']! as bool,
    lastUsed: switch (json['last_used']) {
      final String at => DateTime.parse(at),
      _ => null,
    },
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'quantity': quantity,
    'due': due,
    'last_used': lastUsed?.toIso8601String(),
  };
}

/// What `public.normalize_item_name` makes of a name.
String foldName(String name) => name
    .trim()
    .toLowerCase()
    .replaceAll('ä', 'ae')
    .replaceAll('ö', 'oe')
    .replaceAll('ü', 'ue')
    .replaceAll('ß', 'ss')
    .replaceAll(RegExp(r'\s+'), ' ');

/// [usuals] matching what is typed, folded as the server folds: the same
/// name, names starting with it, names with a word starting with it, names
/// with it inside, then typos of it (`suggestionMatch`), each in the
/// server's order. Names already on the list are left out.
List<Usual> suggestUsuals(
  List<Usual> usuals,
  Iterable<Item> visible,
  String text, {
  int limit = 5,
}) {
  final typed = foldName(text);
  if (typed.isEmpty) {
    return const [];
  }
  final ranked = [
    for (final (order, usual) in _offList(usuals, visible).indexed)
      if (suggestionMatch(typed, foldName(usual.name)) case final rank?)
        (rank, order, usual),
  ]..sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
  return [for (final (_, _, usual) in ranked.take(limit)) usual];
}

/// How a folded [name] matches folded [typed] text, best first, as
/// `public.suggest_match` on the server: 0 the same name, 1 it starts with
/// it, 2 a word of it does, 3 it has it inside (from 4 letters), 4 a word of
/// it or the whole name is a typo of it (from 3 letters: same first letter,
/// one edit up to 5 letters, two from 6). Null: no match.
int? suggestionMatch(String typed, String name) {
  if (name == typed) {
    return 0;
  }
  if (name.startsWith(typed)) {
    return 1;
  }
  final words = name.split(RegExp('[ -]+'));
  if (words.any((w) => w.startsWith(typed))) {
    return 2;
  }
  if (typed.length < 3) {
    return null;
  }
  if (typed.length >= 4 && name.contains(typed)) {
    return 3;
  }
  final most = typed.length < 6 ? 1 : 2;
  for (final word in {name, ...words}) {
    if (word.isNotEmpty &&
        word[0] == typed[0] &&
        (word.length - typed.length).abs() <= most &&
        _editDistance(typed, word) <= most) {
      return 4;
    }
  }
  return null;
}

/// Inserts, deletes and replacements that turn [a] into [b].
int _editDistance(String a, String b) {
  var previous = [for (var j = 0; j <= b.length; j++) j];
  for (var i = 1; i <= a.length; i++) {
    final current = [i];
    for (var j = 1; j <= b.length; j++) {
      current.add(
        min(
          min(previous[j], current[j - 1]) + 1,
          previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1),
        ),
      );
    }
    previous = current;
  }
  return previous.last;
}

/// The due [usuals] not on the list, in the server's order.
List<Usual> dueUsualsOf(
  List<Usual> usuals,
  Iterable<Item> visible, {
  int limit = 10,
}) => _offList(usuals, visible).where((u) => u.due).take(limit).toList();

/// The [usuals] used in the 30 days before [now] that are not due and not
/// on the list, the latest first.
List<Usual> recentUsualsOf(
  List<Usual> usuals,
  Iterable<Item> visible,
  DateTime now, {
  int limit = 10,
}) {
  final since = now.subtract(const Duration(days: 30));
  final recent = [
    for (final usual in _offList(usuals, visible))
      if (!usual.due && (usual.lastUsed?.isAfter(since) ?? false)) usual,
  ]..sort((a, b) => b.lastUsed!.compareTo(a.lastUsed!));
  return recent.take(limit).toList();
}

Iterable<Usual> _offList(List<Usual> usuals, Iterable<Item> visible) {
  final active = {
    for (final item in visible)
      if (item.status == ItemStatus.active) item.name.toLowerCase(),
  };
  return usuals.where((u) => !active.contains(u.name.toLowerCase()));
}

/// How far a user has looked at partner adds: everything created up to
/// [until] (null: from the beginning), plus the items in [ids] after it.
@immutable
class const SeenMark({
  final DateTime? until,
  final Set<String> ids = const {},
}) {
  factory fromJson(Map<String, Object?> json) => SeenMark(
    until: switch (json['until']) {
      final String at => DateTime.parse(at),
      _ => null,
    },
    ids: {for (final id in json['ids']! as List<Object?>) id! as String},
  );

  Map<String, Object?> toJson() => {
    'until': until?.toIso8601String(),
    'ids': [...ids],
  };

  /// Partner items created after [until], seen or not, ticked or not.
  Iterable<Item> _after(Iterable<Item> visible, String userId) {
    final since = until;
    return visible.where(
      (i) =>
          i.isFromPartner(userId) &&
          (since == null || i.createdAt.isAfter(since)),
    );
  }

  /// Ids of the partner items on the list [userId] has not seen yet.
  Set<String> fresh(Iterable<Item> visible, String userId) => {
    for (final item in _after(visible, userId))
      if (item.status == ItemStatus.active && !ids.contains(item.id)) item.id,
  };

  /// Marks [seenIds] as seen. Once every partner item on the list is seen,
  /// [until] moves past them, so [ids] stays small. A seen item keeps its
  /// id while it is known, so ticking and putting it back is no news.
  SeenMark marking(Set<String> seenIds, Iterable<Item> visible, String userId) {
    final after = _after(visible, userId).toList();
    final seen = {
      ...ids,
      ...seenIds,
    }.intersection({for (final item in after) item.id});
    final active = [
      for (final item in after)
        if (item.status == ItemStatus.active) item,
    ];
    if (active.isEmpty || !active.every((i) => seen.contains(i.id))) {
      return SeenMark(until: until, ids: seen);
    }
    final next = active
        .map((i) => i.createdAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    return SeenMark(
      until: next,
      ids: {
        for (final item in after)
          if (seen.contains(item.id) && item.createdAt.isAfter(next)) item.id,
      },
    );
  }
}

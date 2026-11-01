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

/// The identity of a store name, as `public.store_name_key`: trimmed, inner
/// whitespace collapsed, case folded. Two stores never share it.
String storeNameKey(String name) =>
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

/// The household's categories, stores and store layouts: everything the list
/// is sorted by. [categories] and [stores] are in their sort order.
@immutable
class const Catalog({
  final List<Category> categories = const [],
  final List<Store> stores = const [],
  final List<StoreCategory> layout = const [],
  final List<Member> members = const [],
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
  );

  Map<String, Object?> toJson() => {
    'categories': [for (final c in categories) c.toJson()],
    'stores': [for (final s in stores) s.toJson()],
    'layout': [for (final row in layout) row.toJson()],
    'members': [for (final m in members) m.toJson()],
  };

  Member? member(String? id) => members.where((m) => m.id == id).firstOrNull;

  Category? get fallback =>
      categories.where((c) => c.seedKey == 'other').firstOrNull;

  Store? store(String id) => stores.where((s) => s.id == id).firstOrNull;

  /// The store with [name], in any case or spacing.
  Store? storeNamed(String name) {
    final key = storeNameKey(name);
    return stores.where((s) => storeNameKey(s.name) == key).firstOrNull;
  }

  /// [store] added after the others; its layout follows the route order.
  Catalog withStore(Store store) => Catalog(
    categories: categories,
    stores: [...stores, store],
    layout: layout,
    members: members,
  );

  /// A preset store given another name stops being its chain, as
  /// `public.rename_store` does.
  Catalog withStoreName(String storeId, String name) => Catalog(
    categories: categories,
    stores: [
      for (final s in stores)
        if (s.id == storeId)
          Store(
            id: s.id,
            name: name,
            sortOrder: s.sortOrder,
            seedKey: storeNameKey(name) == storeNameKey(s.name)
                ? s.seedKey
                : null,
          )
        else
          s,
    ],
    layout: layout,
    members: members,
  );

  Catalog withoutStore(String storeId) => Catalog(
    categories: categories,
    stores: [...stores.where((s) => s.id != storeId)],
    layout: [...layout.where((row) => row.storeId != storeId)],
    members: members,
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
  );
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
  );

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

/// The provisional key for an item put [edge] of [anchor]: halfway to the
/// neighbour in [group] (the anchor's group in walk order, without the item),
/// or 1024 past the anchor at an end. Null while the anchor has no key.
double? placeKey(List<Item> group, Item anchor, Edge edge) {
  final key = anchor.sortKey;
  if (key == null) {
    return null;
  }
  final at = group.indexWhere((i) => i.id == anchor.id);
  final next = switch (edge) {
    Edge.before => at > 0 ? group[at - 1].sortKey : null,
    Edge.after => at + 1 < group.length ? group[at + 1].sortKey : null,
  };
  return switch ((edge, next)) {
    (_, final n?) => (key + n) / 2,
    (Edge.before, null) => key - 1024,
    (Edge.after, null) => key + 1024,
  };
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

/// What `public.parse_item` makes of one typed entry.
@immutable
class const ParsedEntry({
  required final String name,
  final String? brand,
  final String? properties,
  final String? quantity,
  final String? storeId,
  final String? categoryId,
}) {
  factory fromJson(Map<String, Object?> json) => ParsedEntry(
    name: json['name']! as String,
    brand: json['brand'] as String?,
    properties: json['properties'] as String?,
    quantity: json['quantity'] as String?,
    storeId: json['store_id'] as String?,
    categoryId: json['category_id'] as String?,
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
      final op => throw FormatException('unknown op', op),
    };
  }

  /// The item as the user should see it once this op lands.
  Item? apply(Item? current);

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
      AddItem(:final item, :final restored) => {
        'op': 'add',
        'item': item.toJson(),
        if (restored) 'restored': true,
      },
      SetStatus(:final status, :final at, :final storeId) => {
        'op': 'status',
        'status': status.name,
        'at': at.toIso8601String(),
        'store_id': storeId,
      },
      EditItem(:final changes) => {
        'op': 'edit',
        'changes': changes.toColumns(),
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
final class AddItem(final Item item, {final bool restored = false})
    extends ItemOp {
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
/// category changed at the end of its new group.
final class const EditItem(super.itemId, final ItemChanges changes)
    extends ItemOp {
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
}) {
  factory fromJson(Map<String, Object?> json) => Usual(
    name: json['name']! as String,
    quantity: json['quantity'] as String?,
    due: json['due']! as bool,
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'quantity': quantity,
    'due': due,
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

/// [usuals] matching what is typed, as the server matches a prefix: names
/// starting with it first, then names with a word starting with it, each in
/// the server's order. Names already on the list are left out.
List<Usual> suggestUsuals(
  List<Usual> usuals,
  Iterable<Item> visible,
  String text, {
  int limit = 5,
}) {
  final prefix = foldName(text);
  if (prefix.isEmpty) {
    return const [];
  }
  final offList = _offList(usuals, visible);
  final words = RegExp('[ -]');
  return [
    ...offList.where((u) => foldName(u.name).startsWith(prefix)),
    ...offList.where((u) {
      final name = foldName(u.name);
      return !name.startsWith(prefix) &&
          name.split(words).any((w) => w.startsWith(prefix));
    }),
  ].take(limit).toList();
}

/// The due [usuals] not on the list, in the server's order.
List<Usual> dueUsualsOf(
  List<Usual> usuals,
  Iterable<Item> visible, {
  int limit = 10,
}) => _offList(usuals, visible).where((u) => u.due).take(limit).toList();

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

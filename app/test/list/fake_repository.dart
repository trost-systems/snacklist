import 'dart:async';
import 'dart:math' as math;

import 'package:family_groceries/list/add_sheet/suggestion.dart';
import 'package:family_groceries/list/catalog/household_index.dart';
import 'package:family_groceries/list/dictation.dart';
import 'package:family_groceries/list/entry.dart';
import 'package:family_groceries/list/list_repository.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/pricing.dart';
import 'package:family_groceries/list/quantity.dart';
import 'package:family_groceries/list/retailer.dart';

/// An in-memory server. [online] false makes every call fail like a dropped
/// connection; [reject] makes the next write fail like a refused one;
/// [sendTrouble] and [fetchTrouble] make item writes and list reads fail
/// like a server in trouble (a 5xx).
/// Writes come from [me]; [remoteAdd] is Lea's by default.
///
/// Stores: Lidl walks the route backwards; dm does not carry produce or
/// chilled.
class FakeRepository() implements ListRepository {
  var categories = const [
    Category(id: 'produce', name: 'Obst & Gemüse', sortOrder: 10),
    Category(id: 'chilled', name: 'Kühlregal', sortOrder: 30),
    Category(id: 'other', name: 'Sonstiges', sortOrder: 1000, seedKey: 'other'),
  ];
  var stores = const [
    Store(id: 'dm', name: 'dm', sortOrder: 10, seedKey: 'dm'),
    Store(id: 'lidl', name: 'Lidl', sortOrder: 20, seedKey: 'lidl'),
  ];
  var layout = const [
    StoreCategory(storeId: 'dm', categoryId: 'other', sortOrder: 10),
    StoreCategory(
      storeId: 'dm',
      categoryId: 'produce',
      sortOrder: 20,
      hidden: true,
    ),
    StoreCategory(
      storeId: 'dm',
      categoryId: 'chilled',
      sortOrder: 30,
      hidden: true,
    ),
    StoreCategory(storeId: 'lidl', categoryId: 'other', sortOrder: 10),
    StoreCategory(storeId: 'lidl', categoryId: 'chilled', sortOrder: 20),
    StoreCategory(storeId: 'lidl', categoryId: 'produce', sortOrder: 30),
  ];
  var members = const [
    Member(id: 'peter', displayName: 'Peter'),
    Member(id: 'lea', displayName: 'Lea'),
  ];
  var me = 'peter';

  /// The household's lists (job 169b K); none, as a server from before
  /// them, by default.
  var lists = const <HouseholdList>[];

  /// The "Ich bringe" claims (job 169b L).
  final claims = <ClaimKey, Claim>{};
  var _claimIds = 0;

  /// The first list, where an add without a list lands.
  String? get firstList => lists.firstOrNull?.id;

  /// What suggest_items answers; [usualsFail] makes it fail on its own.
  var usuals = <Usual>[];
  var usualsFail = false;
  var usualsCalls = 0;

  /// What suggest_index answers (null: a malformed answer), and how often
  /// it was asked.
  HouseholdIndex? householdIndex = HouseholdIndex.empty;
  var householdIndexCalls = 0;

  /// When set, fetchSuggestIndex answers what it held when asked once this
  /// completes.
  Completer<void>? indexGate;

  /// When set, fetchUsuals waits for it, after the online check.
  Completer<void>? usualsGate;
  final rows = <String, Item>{};
  final sent = <ItemOp>[];

  /// Catalog writes, as `method(args)` strings.
  final catalogCalls = <String>[];
  var online = true;
  var reject = false;
  var rejectMessage = 'denied';
  var sendTrouble = false;
  var fetchTrouble = false;
  var _clock = DateTime.utc(2026, 10, 22, 12);
  void Function(Item item)? emitItem;

  /// A delete, committed now on the fake's clock.
  void Function(String id)? emitDelete;
  void Function(ConnectionStatus status)? emitStatus;
  void Function(Claim claim)? emitClaim;
  void Function(String id)? emitClaimDeleted;
  void Function(String id)? emitListDeleted;
  void Function()? emitCatalogChanged;

  Completer<void>? gate;

  /// Runs as an op reaches the server; may change rows or throw a refusal.
  void Function(ItemOp op)? beforeSend;

  /// What the items trigger reports as `categorized_via` for a new row.
  String? categorizedVia;

  /// Applies the next op, then fails as if its answer was lost.
  var loseNextAnswer = false;

  /// How many times the list subscribed to realtime.
  var watches = 0;

  /// How many times the list unsubscribed: once more when it closed.
  var unwatches = 0;

  /// How many times the list asked for its items, answered or not.
  var itemFetches = 0;

  /// How many times the list renewed the realtime socket.
  var renewals = 0;

  /// Whether a renewal drops the channel and joins it again, as the client
  /// does with the server in reach. Off, the channel says nothing.
  var rejoinOnRenew = true;

  /// Each unsubscribe waits for the next of these, if any.
  final unwatchGates = <Completer<void>>[];

  /// Holds catalog fetches until completed.
  Completer<void>? catalogGate;

  /// Holds item fetches, after the online check, until completed.
  Completer<void>? itemsGate;

  DateTime _tick() => _clock = _clock.add(const Duration(seconds: 1));

  String classify(String name) =>
      name.toLowerCase().contains('milch') ? 'chilled' : 'other';

  void _ensureOnline() {
    if (!online) {
      throw Exception('offline');
    }
  }

  void _ensureFetchable() {
    if (fetchTrouble) {
      throw const ServerTrouble('503');
    }
  }

  @override
  Future<Catalog> fetchCatalog() async {
    _ensureOnline();
    _ensureFetchable();
    await catalogGate?.future;
    return Catalog(
      categories: categories,
      stores: stores,
      layout: layout,
      members: members,
      lists: lists,
      currency: currency,
    );
  }

  @override
  Future<List<Claim>> fetchClaims() async {
    _ensureOnline();
    _ensureFetchable();
    return claims.values.toList();
  }

  @override
  Future<void> createList(String id, String name) async {
    if (lists.any((l) => l.id == id)) {
      return;
    }
    _writeCatalog('createList($id, $name)');
    lists = Catalog(lists: lists)
        .withList(HouseholdList(id: id, name: name, position: lists.length))
        .lists;
  }

  @override
  Future<void> renameList(String id, String name) async {
    _writeCatalog('renameList($id, $name)');
    lists = Catalog(lists: lists).withListName(id, name).lists;
  }

  @override
  Future<void> deleteList(String id) async {
    if (lists.length <= 1) {
      throw const RejectedOp('last_list');
    }
    _writeCatalog('deleteList($id)');
    final first = firstList;
    lists = Catalog(lists: lists).withoutList(id).lists;
    rows.removeWhere((_, item) => item.listOn(first) == id);
  }

  @override
  Future<void> moveList(String id, int position) async {
    _writeCatalog('moveList($id, $position)');
    final ids = [
      for (final l in lists)
        if (l.id != id) l.id,
    ]..insert(position, id);
    lists = Catalog(lists: lists).withListOrder(ids).lists;
  }

  void _writeCatalog(String call) {
    _ensureOnline();
    if (reject) {
      reject = false;
      throw RejectedOp(rejectMessage);
    }
    catalogCalls.add(call);
  }

  @override
  Future<void> renameCategory(String id, String name) async {
    if (categories.any((c) => c.id != id && nameKey(c.name) == nameKey(name))) {
      throw const RejectedOp('duplicate key', nameTaken: true);
    }
    _writeCatalog('rename($id, $name)');
    categories = Catalog(categories: categories).withName(id, name).categories;
  }

  @override
  /// Like `create_category`: a name the household has in any case or
  /// spacing returns that category.
  Future<void> createCategory(String name) async {
    if (categories.any((c) => nameKey(c.name) == nameKey(name))) {
      return;
    }
    _writeCatalog('create($name)');
    categories = [
      ...categories,
      Category(id: 'new-$name', name: name, sortOrder: 2000),
    ];
  }

  @override
  Future<void> reorderCategories(List<String> ids) async {
    _writeCatalog('reorder(${ids.join(', ')})');
    categories = Catalog(categories: categories).withRouteOrder(ids).categories;
  }

  /// The household's currency (job 190).
  var currency = defaultCurrency;

  @override
  Future<void> setCurrency(String code) async {
    _writeCatalog('setCurrency($code)');
    currency = code;
  }

  @override
  Future<void> reorderStores(List<String> ids) async {
    _writeCatalog('reorderStores(${ids.join(', ')})');
    stores = Catalog(stores: stores).withStoreOrder(ids).stores;
  }

  @override
  Future<String> addStore(String name) async {
    _writeCatalog('addStore($name)');
    if (Catalog(stores: stores).storeNamed(name) case final existing?) {
      return existing.id;
    }
    final id = 'new-$name';
    stores = [
      ...stores,
      Store(
        id: id,
        name: name,
        sortOrder: (stores.lastOrNull?.sortOrder ?? 0) + 10,
      ),
    ];
    return id;
  }

  @override
  Future<void> renameStore(String id, String name) async {
    if (stores.any((s) => s.id != id && nameKey(s.name) == nameKey(name))) {
      throw const RejectedOp('store_name_taken', nameTaken: true);
    }
    _writeCatalog('renameStore($id, $name)');
    stores = Catalog(stores: stores).withStoreName(id, name).stores;
  }

  @override
  Future<void> deleteStore(String id) async {
    _writeCatalog('deleteStore($id)');
    stores = [...stores.where((s) => s.id != id)];
    layout = [...layout.where((row) => row.storeId != id)];
    for (final item in [...rows.values]) {
      if (item.storeId == id) {
        rows[item.id] = item.copyWith(storeId: () => null);
      }
    }
  }

  /// What parse_item answers for a text; unknown texts parse to their name.
  final parsed = <String, ParsedEntry>{};

  /// The chain registry (`public.retailers`); none by default. Matching
  /// folds case only: a name or `aliases` entry equal to the typed name, or
  /// starting it before a space, is exact; one the typed name starts
  /// (two letters or more) a prefix.
  var retailers = const <Retailer>[];

  /// Lower-case alias words per registry entry.
  var aliases = const <({String chain, String country}), List<String>>{};

  /// The countries matchRetailers and retailerQuestions were asked for.
  final retailerCountries = <String>[];

  /// Like `public.match_retailers`: exact before prefix, [country] first,
  /// then by name; exact matches of [country] drop other countries'.
  @override
  Future<List<RetailerMatch>> matchRetailers(
    String name,
    String country,
  ) async {
    _ensureOnline();
    retailerCountries.add(country);
    return _matches(name, country);
  }

  List<RetailerMatch> _matches(String name, String country) {
    final matches = _ranked(name, country);
    final local = matches.any((m) => m.exact && m.retailer.country == country);
    return [
      for (final m in matches)
        if (!local || !m.exact || m.retailer.country == country) m,
    ].take(5).toList();
  }

  List<RetailerMatch> _ranked(String typed, String country) {
    final key = nameKey(typed);
    return [
      for (final r in retailers)
        if (_words(r) case final words
            when words.any((w) => key == w || key.startsWith('$w ')))
          RetailerMatch(r, exact: true)
        else if (key.length >= 2 && _words(r).any((w) => w.startsWith(key)))
          RetailerMatch(r, exact: false),
    ]..sort(
      (a, b) => [
        (a.exact ? 0 : 1).compareTo(b.exact ? 0 : 1),
        (a.retailer.country == country ? 0 : 1).compareTo(
          b.retailer.country == country ? 0 : 1,
        ),
        a.retailer.name.compareTo(b.retailer.name),
      ].firstWhere((c) => c != 0, orElse: () => 0),
    );
  }

  List<String> _words(Retailer r) => [nameKey(r.name), ...?aliases[r.key]];

  @override
  Future<List<Retailer>> listRetailers({String? country}) async {
    _ensureOnline();
    return [
      for (final r in retailers)
        if (country == null || r.country == country) r,
    ]..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Like `public.answer_store_retailer`: refuses a chain the registry
  /// lacks and an app that is not one of the chain's.
  @override
  Future<void> answerStoreRetailer(
    String storeId,
    Retailer? retailer, {
    String? app,
  }) async {
    final entry = retailers.where((r) => r.key == retailer?.key).firstOrNull;
    if (retailer != null &&
        (entry == null ||
            (app != null && !entry.apps.any((a) => a.android == app)))) {
      _ensureOnline();
      throw const RejectedOp('invalid_retailer');
    }
    _writeCatalog(
      'answerStoreRetailer($storeId, ${retailer?.chain}, '
      '${retailer?.country}, $app)',
    );
    stores = Catalog(stores: stores)
        .withStoreRetailer(storeId, entry, app: app)
        .stores;
  }

  @override
  Future<List<StoreQuestion>> retailerQuestions(String country) async {
    _ensureOnline();
    retailerCountries.add(country);
    return [
      for (final s in stores)
        if (s.retailer == null && !s.retailerAnswered)
          if ([
                for (final m in _matches(s.name, country))
                  if (m.exact && m.retailer.apps.isNotEmpty) m.retailer,
              ]
              case final chains when chains.isNotEmpty)
            StoreQuestion(storeId: s.id, chains: chains),
    ];
  }

  @override
  Future<ParsedEntry> parse(String text) async {
    _ensureOnline();
    return parsed[text] ?? ParsedEntry(name: text);
  }

  /// What suggest_entries answers per text; else the parse alone.
  final suggestions = <String, List<Suggestion>>{};

  /// Texts asked for, in order.
  final suggestCalls = <String>[];

  /// When set, suggest waits for it.
  Completer<void>? suggestGate;

  @override
  Future<List<Suggestion>> suggest(String text) async {
    suggestCalls.add(text);
    await suggestGate?.future;
    _ensureOnline();
    return suggestions[text] ??
        [
          Suggestion(
            SuggestionSource.typed,
            parsed[text] ?? ParsedEntry(name: text, categoryId: classify(text)),
          ),
        ];
  }

  @override
  Future<void> deleteCategory(String id, {String? reassignTo}) async {
    _writeCatalog('delete($id, $reassignTo)');
    final target = reassignTo ?? 'other';
    categories = [...categories.where((c) => c.id != id)];
    for (final item in [...rows.values]) {
      if (item.categoryId == id) {
        rows[item.id] = item.copyWith(categoryId: target);
      }
    }
  }

  @override
  Future<void> setStoreLayout(
    String storeId,
    List<String> orderedIds,
    Set<String> hiddenIds,
  ) async {
    _writeCatalog(
      'layout($storeId: ${orderedIds.join(', ')}; ${hiddenIds.join(', ')})',
    );
    layout = Catalog(layout: layout)
        .withStoreLayout(storeId, orderedIds, hiddenIds)
        .layout;
  }

  @override
  Future<List<Item>> fetchItems() async {
    itemFetches++;
    _ensureOnline();
    _ensureFetchable();
    await itemsGate?.future;
    return rows.values.toList();
  }

  /// The household's order mode (job 352); `set_order_mode` sets it.
  OrderMode orderMode = OrderMode.categories;

  /// When set, `set_order_mode` answers this mode and changes nothing.
  OrderMode? orderModeAnswer;

  /// The modes `set_order_mode` was asked for, in order.
  final orderModeAsks = <OrderMode>[];

  /// How many more asks of `set_order_mode` fail like a dropped connection.
  var orderModeFails = 0;

  /// Runs when `set_order_mode` switches to learned: the server's replay,
  /// which gives the rows new sort keys without a realtime event here.
  void Function()? onLearned;

  @override
  Future<OrderMode> setOrderMode(OrderMode mode) async {
    _ensureOnline();
    orderModeAsks.add(mode);
    if (orderModeFails > 0) {
      orderModeFails--;
      throw Exception('offline');
    }
    if (orderModeAnswer case final answer?) {
      return answer;
    }
    if (mode == OrderMode.learned && orderMode != OrderMode.learned) {
      onLearned?.call();
    }
    return orderMode = mode;
  }

  @override
  Future<HouseholdIndex?> fetchSuggestIndex() async {
    householdIndexCalls++;
    _ensureOnline();
    final answer = householdIndex;
    await indexGate?.future;
    return answer;
  }

  @override
  Future<List<Usual>> fetchUsuals() async {
    usualsCalls++;
    _ensureOnline();
    await usualsGate?.future;
    if (usualsFail) {
      throw Exception('suggest_items failed');
    }
    return usuals;
  }

  /// The merges the fake server did, by merge id, with both rows as they
  /// were (for the undo) and whether they were undone.
  final merges = <String, ({Item kept, Item merged, bool undone})>{};

  @override
  Future<Map<String, Item?>> send(ItemOp sentOp) async {
    await gate?.future;
    _ensureOnline();
    if (sendTrouble) {
      throw const ServerTrouble('503');
    }
    beforeSend?.call(sentOp);
    if (reject) {
      reject = false;
      throw const RejectedOp('denied');
    }
    // As the repository: a line typed offline is parsed before it is added.
    final op = switch (sentOp) {
      AddItem(
        deviceParsed: true,
        :final item,
        :final noStore,
        :final separate,
      ) =>
        AddItem(
          (await parse(item.name)).onto(item, noStore: noStore),
          noStore: noStore,
          separate: separate,
        ),
      EditItem(deviceParsed: true, :final changes, :final keyBefore) =>
        EditItem(
          sentOp.itemId,
          (await parse(changes.name!)).ontoRename(changes),
          keyBefore: keyBefore,
        ),
      _ => sentOp,
    };
    sent.add(op);
    final Map<String, Item?> touched;
    switch (op) {
      case MergeItems(:final mergeId, :final otherId):
        touched = _merge(op, mergeId, otherId);
      case UnmergeItems(:final mergeId, :final merged):
        touched = _unmerge(op, mergeId, merged.id);
      case EditItem(:final changes) when _renamesOntoTwin(op.itemId, changes):
        // items_rename_duplicate (job 104): another open row has that name.
        sent.removeLast();
        throw const RejectedOp('already_on_list', nameTaken: true);
      case MoveToList(:final listId) when _movesOntoTwin(op.itemId, listId):
        // items_rename_duplicate fires on a list_id change too (job 169b K).
        sent.removeLast();
        throw const RejectedOp('already_on_list', nameTaken: true);
      case AddItem(:final item, separate: false) when _openTwin(item) != null:
        // put_item: the open item the add already is, unchanged.
        final kept = _openTwin(item)!;
        touched = {op.itemId: null, kept.id: kept};
      case ClaimItem(:final userId, :final quantity):
        // claim_item: an upsert on an open item; the item stays as it is.
        final item = rows[op.itemId];
        if (item != null && item.status == ItemStatus.active) {
          claims[(op.itemId, userId)] = Claim(
            id: claims[(op.itemId, userId)]?.id ?? 'claim-${++_claimIds}',
            itemId: op.itemId,
            userId: userId,
            quantity: quantity,
            createdAt: claims[(op.itemId, userId)]?.createdAt ?? _tick(),
          );
        }
        touched = {op.itemId: item};
      case UnclaimItem(:final userId):
        claims.remove((op.itemId, userId));
        touched = {op.itemId: rows[op.itemId]};
      case DeclineShop():
        // decline_shop: no row changes.
        touched = const {};
      default:
        return {op.itemId: _sendOne(op)};
    }
    if (loseNextAnswer) {
      loseNextAnswer = false;
      throw Exception('answer lost');
    }
    return touched;
  }

  /// As `merge_items`: once per merge id, both open; the kept row takes the
  /// merged quantity (the app's mirror of the server's rule).
  Map<String, Item?> _merge(MergeItems op, String mergeId, String otherId) {
    final (kept, other) = (rows[op.itemId], rows[otherId]);
    if (!merges.containsKey(mergeId)) {
      if (kept == null || other == null) {
        return {op.itemId: kept, otherId: other};
      }
      if (kept.status != ItemStatus.active ||
          other.status != ItemStatus.active) {
        throw const RejectedOp('not_open');
      }
      final String quantity;
      try {
        quantity = mergeQuantities(kept.quantity, other.quantity);
      } on QuantityTooLong {
        throw const RejectedOp('merged_quantity_too_long');
      }
      merges[mergeId] = (kept: kept, merged: other, undone: false);
      rows[op.itemId] = _stamp(
        kept.copyWith(
          quantity: () => quantity,
          brand: () => kept.brand ?? other.brand,
          properties: () => kept.properties ?? other.properties,
        ),
      );
      rows.remove(otherId);
    }
    return {op.itemId: rows[op.itemId], otherId: rows[otherId]};
  }

  Map<String, Item?> _unmerge(UnmergeItems op, String mergeId, String otherId) {
    final merge = merges[mergeId];
    if (merge != null && !merge.undone) {
      merges[mergeId] = (kept: merge.kept, merged: merge.merged, undone: true);
      if (rows[op.itemId] case final kept?) {
        rows[op.itemId] = _stamp(
          kept.copyWith(
            quantity: () => merge.kept.quantity,
            brand: () => merge.kept.brand,
            properties: () => merge.kept.properties,
          ),
        );
      }
      rows[otherId] = _stamp(merge.merged);
    }
    return {op.itemId: rows[op.itemId], otherId: rows[otherId]};
  }

  bool _movesOntoTwin(String id, String listId) {
    final current = rows[id];
    return current != null &&
        _openTwin(current.copyWith(listId: listId), except: id) != null;
  }

  bool _renamesOntoTwin(String id, ItemChanges changes) {
    final current = rows[id];
    return current != null &&
        current.status == ItemStatus.active &&
        _openTwin(changes.apply(current), except: id) != null;
  }

  /// As `items_skip_duplicate`: another open row with the same name, brand
  /// and details (in any order), for a new open item; with [except], for
  /// that row renamed (`items_rename_duplicate`).
  Item? _openTwin(Item item, {String? except}) {
    String key(Item i) => [
      foldName(i.name),
      foldName(i.brand ?? ''),
      ((i.properties ?? '')
              .split(',')
              .map(foldName)
              .where((p) => p.isNotEmpty)
              .toList()
            ..sort())
          .join(','),
    ].join('|');
    if ((except == null && rows.containsKey(item.id)) ||
        item.status != ItemStatus.active) {
      return null;
    }
    // Job 169b K: per list.
    final list = item.listOn(firstList);
    return rows.values
        .where(
          (r) =>
              r.id != except &&
              r.status == ItemStatus.active &&
              r.listOn(firstList) == list &&
              key(r) == key(item),
        )
        .firstOrNull;
  }

  Item _stamp(Item item) => Item(
    id: item.id,
    name: item.name,
    quantity: item.quantity,
    brand: item.brand,
    properties: item.properties,
    categoryId: item.categoryId,
    storeId: item.storeId,
    sortKey: item.sortKey,
    status: item.status,
    createdAt: item.createdAt,
    updatedAt: _tick(),
    boughtAt: item.boughtAt,
    addedBy: item.addedBy,
    categorizedVia: item.categorizedVia,
    canonicalKey: item.canonicalKey,
    listId: item.listId,
    price: item.price,
  );

  /// What the items trigger sets as `canonical_key` for a name: here the
  /// test's [canonical] table, else the folded name.
  final canonical = <String, String>{};

  String canonicalOf(String name) => canonical[name] ?? foldName(name);

  Item? _sendOne(ItemOp op) {
    final current = rows[op.itemId];
    final next = switch (op) {
      AddItem(:final item) =>
        current ??
            Item(
              id: item.id,
              name: item.name,
              quantity: item.quantity,
              brand: item.brand,
              properties: item.properties,
              categoryId: item.categoryId ?? classify(item.name),
              storeId: item.storeId,
              sortKey: item.sortKey,
              status: item.status,
              createdAt: _tick(),
              updatedAt: _clock,
              addedBy: me,
              categorizedVia: categorizedVia,
              canonicalKey: canonicalOf(item.name),
              listId: item.listId ?? firstList,
            ),
      PlaceItem(:final anchorId, :final edge) => _place(
        current,
        anchorId,
        edge,
      ),
      _ => op.apply(current),
    };
    if (next == null) {
      rows.remove(op.itemId);
      claims.removeWhere((key, _) => key.$1 == op.itemId);
      return null;
    }
    // A claim ends when the item is ticked (the claims trigger).
    if (next.status == ItemStatus.bought) {
      claims.removeWhere((key, _) => key.$1 == op.itemId);
    }
    // The items trigger: a new item, or one whose group changed without a
    // key, goes to the end of its group.
    final regrouped =
        current == null ||
        current.storeId != next.storeId ||
        current.categoryId != next.categoryId;
    final keyed = op is PlaceItem || (op is AddItem && next.sortKey != null);
    final stamped = Item(
      id: next.id,
      name: next.name,
      quantity: next.quantity,
      brand: next.brand,
      properties: next.properties,
      categoryId: next.categoryId,
      storeId: next.storeId,
      sortKey: regrouped && !keyed || next.sortKey == null
          ? _endOf(next)
          : next.sortKey,
      status: next.status,
      createdAt: next.createdAt,
      updatedAt: _tick(),
      boughtAt: next.boughtAt,
      addedBy: next.addedBy,
      categorizedVia: next.categorizedVia,
      canonicalKey: next.name == current?.name
          ? next.canonicalKey
          : canonicalOf(next.name),
      listId: next.listId,
      price: next.price,
    );
    rows[op.itemId] = stamped;
    if (loseNextAnswer) {
      loseNextAnswer = false;
      throw Exception('answer lost');
    }
    return stamped;
  }

  /// The item's (store, category) group on the server, in walk order.
  List<Item> groupOf(Item item) => [
    for (final row in rows.values)
      if (row.id != item.id &&
          row.status == ItemStatus.active &&
          row.storeId == item.storeId &&
          row.categoryId == item.categoryId)
        row,
  ]..sort(compareWalk);

  double _endOf(Item item) =>
      groupOf(item).map((i) => i.sortKey ?? 0).fold<double>(0, math.max) + 1024;

  Item? _place(Item? current, String anchorId, Edge edge) {
    final anchor = rows[anchorId];
    if (current == null || anchor == null) {
      return current;
    }
    // Learned (job 352): within its store's section, its category kept.
    if (orderMode == OrderMode.learned) {
      final section = [
        for (final row in rows.values)
          if (row.id != current.id &&
              row.status == ItemStatus.active &&
              row.storeId == current.storeId)
            row,
      ]..sort(compareWalk);
      return current.copyWith(sortKey: () => _keyNextTo(section, anchor, edge));
    }
    final moved = current.copyWith(
      categoryId: anchor.categoryId,
      storeId: () => anchor.storeId,
    );
    return moved.copyWith(
      sortKey: () => _keyNextTo(groupOf(moved), anchor, edge),
    );
  }

  /// Like `place_item`: halfway to the anchor's neighbour in [group], or
  /// 1024 past the anchor at an end.
  static double? _keyNextTo(List<Item> group, Item anchor, Edge edge) {
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

  /// The language of each [splitSpoken] call, in order.
  final spokenLanguages = <SpokenLanguage>[];

  /// Stands in for the server's splitter: splits on commas and "und", then
  /// reads each part as [parse] does; at most 30, as the server.
  @override
  Future<SpokenSplit> splitSpoken(String text, SpokenLanguage language) async {
    _ensureOnline();
    spokenLanguages.add(language);
    final entries = [
      for (final part in text.split(RegExp(r',|\bund\b')))
        if (parseEntry(part) case Entry(:final name, :final quantity)
            when name.isNotEmpty)
          switch (parsed[name]) {
            final split? => ParsedEntry(
              name: split.name,
              brand: split.brand,
              properties: split.properties,
              quantity: quantity ?? split.quantity,
            ),
            null => ParsedEntry(name: name, quantity: quantity),
          },
    ];
    return (entries: entries.take(30).toList(), truncated: entries.length > 30);
  }

  @override
  Future<void> Function() watch({
    required void Function(Item item) onItem,
    required void Function(String id, DateTime at) onItemDeleted,
    required void Function(Claim claim) onClaim,
    required void Function(String id) onClaimDeleted,
    required void Function() onCatalogChanged,
    required void Function(String id) onListDeleted,
    required void Function(ConnectionStatus status) onStatus,
  }) {
    watches++;
    emitListDeleted = onListDeleted;
    emitItem = onItem;
    emitClaim = onClaim;
    emitClaimDeleted = onClaimDeleted;
    emitDelete = (id) => onItemDeleted(id, _tick());
    emitStatus = onStatus;
    emitCatalogChanged = onCatalogChanged;
    return () async {
      unwatches++;
      if (unwatchGates.isNotEmpty) {
        await unwatchGates.removeAt(0).future;
      }
    };
  }

  @override
  void renewRealtime() {
    renewals++;
    if (rejoinOnRenew) {
      scheduleMicrotask(() {
        emitStatus?.call(ConnectionStatus.offline);
        emitStatus?.call(ConnectionStatus.online);
      });
    }
  }

  /// A change made by another household member.
  Item remoteAdd(
    String name, {
    String? categoryId,
    String? storeId,
    String? addedBy = 'lea',
    String? brand,
    String? properties,
    String? quantity,
    String? listId,
    Price? price,
    ItemStatus status = ItemStatus.active,
  }) {
    final item = Item(
      id: 'remote-${rows.length}',
      name: name,
      quantity: quantity,
      brand: brand,
      properties: properties,
      categoryId: categoryId ?? classify(name),
      storeId: storeId,
      status: status,
      createdAt: _tick(),
      updatedAt: _clock,
      addedBy: addedBy,
      canonicalKey: canonicalOf(name),
      listId: listId ?? firstList,
      price: price,
    );
    return rows[item.id] = item.copyWith(sortKey: () => _endOf(item));
  }

  /// [userId]'s claim on [itemId], made on another phone; not told over
  /// realtime until the test calls [emitClaim].
  Claim remoteClaim(String itemId, {String userId = 'lea', String? quantity}) =>
      claims[(itemId, userId)] = Claim(
        id: 'claim-${++_claimIds}',
        itemId: itemId,
        userId: userId,
        quantity: quantity,
        createdAt: _tick(),
      );
}

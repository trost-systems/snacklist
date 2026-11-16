import 'dart:async';

import 'package:family_groceries/analytics/events.dart';
import 'package:family_groceries/list/add_sheet/suggestion.dart';
import 'package:family_groceries/list/catalog/catalog_index.dart';
import 'package:family_groceries/list/catalog/household_index.dart';
import 'package:family_groceries/list/catalog/suggest_entries.dart';
import 'package:family_groceries/list/category_guess.dart';
import 'package:family_groceries/list/entry.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

@immutable
class const AddSheetState({
  final bool open = false,
  final String text = '',

  /// The store chip's pick. Null: each row keeps its own store;
  /// `SetTo(null)`: Ohne Laden.
  final SetTo<String?>? store,

  /// The category chip's pick. Null: each row keeps its own category.
  final String? category,

  /// The rows for [answered], which lags [text] while the next ones load.
  final List<Suggestion> suggestions = const [],
  final String answered = '',

  /// The last add, shown with Undo until the next keystroke.
  final AddResult? added,

  /// Job 32b: an open item that is another spelling of [added] ("Möhren"
  /// for "Karotten"), offered for a merge in the note while the sheet is
  /// open; and the merge once taken, with its undo.
  final DedupeHint? hint,
  final Merge? merge,

  /// The items added since the sheet opened, in order (flag
  /// `add-feedback-list`): the list behind the sheet shows them last.
  final List<String> session = const [],

  /// The rows answer an earlier text and wait for those of [text]: they
  /// may still change (shown dimmed with the flag `add-feedback-list`).
  final bool carried = false,

  /// What the user changed in the details of the item just added and that
  /// is not saved yet (flag `add-feedback-list`).
  final ItemChanges unsaved = const ItemChanges(),

  /// The server is asked for the rows of [text] and has not answered.
  final bool fetching = false,
}) {
  /// Whether [suggestions] answer what is typed now.
  bool get fresh => answered.isNotEmpty && answered == text.trim();

  /// The server's rows for what is typed are on the way.
  bool get loading => text.trim().isNotEmpty && !fresh;
}

/// The add sheet: what is typed, the rows the server suggests for it, the
/// chip picks, and the add itself. Rows are fetched while typing (after a
/// short pause) and kept per text until the next add or opening. Without
/// the server they are made up from the parse on the device and the
/// household's usuals.
///
/// [stableRows], the flag `input-stable-rows` (job 272): every key shows
/// the rows made on the device for what is typed now, with a category
/// guess, and the server's answer only enriches them and adds its own
/// below ([mergeRows]). Off: the previous text's rows stay until the
/// server answers.
///
/// [deviceRanked], the flag `on-device-catalog` (job 274): the rows
/// every key shows are [suggestEntries]'s, the server's ranking on the
/// device, and they answer the text ([AddSheetState.fresh]) at once. It
/// implies [stableRows].
class AddSheetCubit(
  final ListCubit _list, {
  Duration debounce = const Duration(milliseconds: 120),
  bool Function() stableRows = _off,
  bool Function() onDeviceCatalog = _off,
  CatalogIndex Function() catalogIndex = _bundled,
  bool Function() addFeedback = _off,
  Duration detailsPause = const Duration(milliseconds: 500),
}) extends Cubit<AddSheetState> {
  this : super(const AddSheetState());

  static bool _off() => false;

  static CatalogIndex _bundled() => CatalogIndex.bundled;

  final _debounce = debounce;
  final _stableRows = stableRows;
  final _onDeviceCatalog = onDeviceCatalog;
  final _addFeedback = addFeedback;
  final _detailsPause = detailsPause;

  /// The catalog the device parses and guesses with: the bundled one with
  /// the server's latest changes.
  final _catalogIndex = catalogIndex;

  /// Whether rows stay put while typing now: the flag `input-stable-rows`
  /// or [deviceRanked].
  bool get stableRows => deviceRanked || _stableRows();

  /// Whether the flag `on-device-catalog` is on now.
  bool get deviceRanked => _onDeviceCatalog();

  /// What the timing log reads; the field starts it with [key].
  final clock = AddSheetClock();

  /// Whether the flag `add-feedback-list` is on now.
  bool get addFeedback => _addFeedback();

  final _cache = <String, List<Suggestion>>{};
  Timer? _typing;
  (String, Future<List<Suggestion>>)? _loading;

  /// Bumped by [_forget]: an answer asked for before it is not cached.
  var _epoch = 0;

  /// Opening again starts blank, also when the last close has not
  /// settled yet.
  void show() {
    if (!state.open) {
      saveDetails();
      _forget();
      emit(const AddSheetState(open: true));
      if (deviceRanked) {
        // The ranking's lookups are built on its first call (~20 ms):
        // here, not on the first key.
        Timer.run(() {
          if (!isClosed) {
            _ranked('milch');
          }
        });
      }
    }
  }

  /// The content stays until [settled], so it is there while the sheet
  /// shrinks away. The details typed last are saved first.
  void dismiss() {
    if (state.open) {
      saveDetails();
      emit(_with(open: false));
    }
  }

  /// The sheet finished closing: start blank next time.
  void settled() {
    if (!state.open) {
      // Typed into the details while the sheet slid away.
      saveDetails();
      _typing?.cancel();
      emit(const AddSheetState());
    }
  }

  /// A key in the field: [type] with the timing log's clock started.
  void key(String text) {
    clock.sinceKey
      ..reset()
      ..start();
    type(text);
  }

  /// The item whose details the sheet shows instead of rows: the one just
  /// added, until the next letter (flag `add-feedback-list`).
  Item? get detailsItem {
    if (!addFeedback || state.text.trim().isNotEmpty) {
      return null;
    }
    if (state.added case Added(:final item)) {
      final live = _list.state.items[item.id];
      if (live != null && live.status == ItemStatus.active) {
        return state.unsaved.apply(live);
      }
    }
    return null;
  }

  Timer? _details;

  /// The user changed [changes] in the item's details: a tap or pick saves
  /// [now], typing after a pause, the next letter typed in the input or the
  /// sheet closing, whichever comes first.
  void editDetails(ItemChanges changes, {bool now = false}) {
    if (state.added is! Added) {
      return;
    }
    emit(_with(unsaved: _then(state.unsaved, changes)));
    _details?.cancel();
    if (now) {
      saveDetails();
    } else {
      _details = Timer(_detailsPause, saveDetails);
    }
  }

  /// Writes the details not saved yet, as the edit sheet writes its
  /// changes; only what differs from the item as the list has it now.
  void saveDetails() {
    _details?.cancel();
    final unsaved = state.unsaved;
    if (unsaved.isEmpty || isClosed) {
      return;
    }
    if (state.added case Added(:final item)) {
      final live = _list.state.items[item.id];
      if (live != null && live.status == ItemStatus.active) {
        _list.edit(item.id, _against(unsaved, live));
      }
    }
    emit(_with(unsaved: const ItemChanges()));
  }

  /// [later] over [earlier], field by field.
  static ItemChanges _then(ItemChanges earlier, ItemChanges later) =>
      ItemChanges(
        name: later.name ?? earlier.name,
        quantity: later.quantity ?? earlier.quantity,
        brand: later.brand ?? earlier.brand,
        properties: later.properties ?? earlier.properties,
        categoryId: later.categoryId ?? earlier.categoryId,
        storeId: later.storeId ?? earlier.storeId,
      );

  /// [changes] without what [item] holds already.
  static ItemChanges _against(ItemChanges changes, Item item) {
    SetTo<String?>? differs(SetTo<String?>? change, String? now) =>
        change == null || change.value == now ? null : change;
    return ItemChanges(
      name: changes.name == item.name ? null : changes.name,
      quantity: differs(changes.quantity, item.quantity),
      brand: differs(changes.brand, item.brand),
      properties: differs(changes.properties, item.properties),
      categoryId: changes.categoryId == item.categoryId
          ? null
          : changes.categoryId,
      storeId: differs(changes.storeId, item.storeId),
    );
  }

  void type(String text) {
    _typing?.cancel();
    // The next item's first letter: the last one's details are done.
    saveDetails();
    final key = text.trim();
    clock.rank = null;
    if (key.isEmpty) {
      emit(_with(text: text, added: () => null, suggestions: const []));
      return;
    }
    final known = _cache[key];
    final ranking = Stopwatch()..start();
    final rows =
        known ??
        (deviceRanked
            ? _ranked(key)
            : stableRows
            ? _local(key)
            : state.suggestions.isEmpty
            ? _offline(key)
            : _withTyped(state.suggestions, key));
    if (known == null) {
      clock.rank = ranking.elapsed;
    }
    emit(
      _with(
        open: true,
        text: text,
        added: () => null,
        suggestions: rows,
        answered: known != null || deviceRanked ? key : null,
        carried: known == null && !stableRows && state.suggestions.isNotEmpty,
      ),
    );
    if (known == null) {
      _typing = Timer(_debounce, () => unawaited(_fetch(key)));
    }
  }

  void pickStore(String? id) => emit(_with(store: () => SetTo(id)));

  void pickCategory(String id) => emit(_with(category: () => id));

  /// Adds [suggestion] with the chips' picks, then clears the input for the
  /// next item. The picks start over with it.
  AddResult take(Suggestion suggestion) {
    saveDetails();
    final entry = suggestion.entry;
    final store = state.store;
    final result =
        _openWithSameWords(suggestion) ??
        _list.addParsed(
          ParsedEntry(
            name: entry.name,
            brand: entry.brand,
            properties: entry.properties,
            quantity: entry.quantity,
            storeId: store == null ? entry.storeId : store.value,
            categoryId: state.category ?? entry.categoryId,
            deviceParsed: entry.deviceParsed,
          ),
          noStore: store != null && store.value == null,
          autoCategory: state.category == null,
          source: suggestion.source == SuggestionSource.typed
              ? AddSource.typed
              : AddSource.suggestion,
        );
    if (result is! NothingToAdd) {
      // An add can change what the server suggests next (store memory,
      // history), so answers from before it are not reused.
      _forget();
      emit(
        AddSheetState(
          open: state.open,
          added: result,
          session: [
            ...state.session,
            if (result case Added(:final item)) item.id,
          ],
        ),
      );
    }
    return result;
  }

  /// With the flag `input-stable-rows` the typed row keeps the device's
  /// reading of the line ("Weihenstephan Milch") after the server answers,
  /// where the server's own reading splits off the brand. The open item
  /// with the same words, in any order and field, is the one already on
  /// the list, as the server's reading would have found it. The device's
  /// ranking ([deviceRanked]) splits off a brand the household taught
  /// only once its index holds it.
  AlreadyOnList? _openWithSameWords(Suggestion suggestion) {
    final entry = suggestion.entry;
    final typed = switch (suggestion.source) {
      _ when !stableRows => null,
      _ when entry.deviceParsed => _words([entry.name]),
      SuggestionSource.typed when deviceRanked => _words([
        entry.name,
        ?entry.brand,
        ?entry.properties,
      ]),
      _ => null,
    };
    if (typed == null) {
      return null;
    }
    for (final item in _list.state.items.values) {
      if (item.status == ItemStatus.active &&
          listEquals(
            _words([item.name, ?item.brand, ?item.properties]),
            typed,
          )) {
        return AlreadyOnList(item);
      }
    }
    return null;
  }

  static List<String> _words(List<String> fields) => [
    for (final field in fields)
      for (final word in foldName(field).split(RegExp(r'[\s,]+')))
        if (word.isNotEmpty) word,
  ]..sort();

  /// Enter: the first row for what is typed now, waiting for it if it is
  /// still loading. Null when nothing is typed, or the text changed or the
  /// sheet closed while waiting.
  Future<AddResult?> takeFirst() async {
    final key = state.text.trim();
    if (key.isEmpty) {
      return null;
    }
    if (state.fresh && state.suggestions.isNotEmpty) {
      return take(state.suggestions.first);
    }
    _typing?.cancel();
    final rows = await _fetch(key).timeout(
      const Duration(seconds: 3),
      onTimeout: () => stableRows ? _device(key) : _offline(key),
    );
    if (isClosed || !state.open || state.text.trim() != key || rows.isEmpty) {
      return null;
    }
    return take(rows.first);
  }

  /// Removes what was just added.
  void undo() {
    if (state.added case Added(:final item)) {
      _details?.cancel();
      _list.delete(item.id);
      emit(_with(added: () => null, unsaved: const ItemChanges()));
    }
  }

  /// Shows [hint] in the note, if the note is about its new item and the
  /// sheet is open. Whether it took it; otherwise the list shows it.
  bool offer(DedupeHint hint) {
    if (state.open && state.merge == null) {
      if (state.added case Added(:final item) when item.id == hint.added.id) {
        _list.hintShown();
        emit(_with(hint: () => hint));
        return true;
      }
    }
    return false;
  }

  /// Takes [hint] out of the note: its items are no longer both open.
  void drop(DedupeHint hint) {
    if (state.hint == hint && state.merge == null) {
      emit(_with(hint: () => null));
    }
  }

  /// Zusammenführen in the note.
  void mergeHint() {
    if (state.hint case final hint?) {
      final merge = _list.merge(hint);
      emit(merge == null ? _with(hint: () => null) : _with(merge: () => merge));
    }
  }

  /// Rückgängig after a merge: both items come back, the note says what was
  /// added again.
  void undoMerge() {
    if (state.merge case final merge?) {
      _list.unmerge(merge);
      emit(_with(hint: () => null, merge: () => null));
    }
  }

  /// The sheet closes with a hint or a merge in its note: the list takes
  /// them over (as snackbars), so they are not lost or counted as ignored.
  (DedupeHint?, Merge?) handOver() {
    final open = (state.merge == null ? state.hint : null, state.merge);
    if (open != (null, null)) {
      _handingOver = true;
      emit(_with(hint: () => null, merge: () => null));
      _handingOver = false;
    }
    return open;
  }

  var _handingOver = false;

  /// A hint that leaves the note without a merge (typing on, the add's
  /// undo, a new add) was ignored.
  @override
  void onChange(Change<AddSheetState> change) {
    super.onChange(change);
    final before = change.currentState;
    if (before.hint != null &&
        before.merge == null &&
        change.nextState.hint != before.hint &&
        change.nextState.merge == null &&
        !_handingOver) {
      _list.hintIgnored();
    }
  }

  Future<List<Suggestion>> _fetch(String key) {
    if (!isClosed && state.text.trim() == key && !state.fetching) {
      emit(_with(fetching: true));
    }
    if (_loading case (final text, final future) when text == key) {
      return future;
    }
    final future = _load(key);
    _loading = (key, future);
    return future;
  }

  /// Drops every answer from before now, also those still on the way.
  void _forget() {
    _typing?.cancel();
    _cache.clear();
    _loading = null;
    _epoch++;
  }

  Future<List<Suggestion>> _load(String key) async {
    final epoch = _epoch;
    List<Suggestion> rows;
    try {
      rows = await _list.suggest(key);
      if (stableRows) {
        // On top of the rows shown for [key], as the user sees them.
        rows = mergeRows(_shownFor(key), rows);
      }
      if (epoch == _epoch) {
        _cache[key] = rows;
      }
    } on Object {
      rows = deviceRanked
          ? _shownFor(key)
          : stableRows
          ? _local(key)
          : _offline(key);
    }
    if (_loading?.$1 == key) {
      _loading = null;
    }
    if (!isClosed && state.text.trim() == key) {
      emit(
        _with(
          suggestions: rows,
          answered: key,
          carried: false,
          fetching: false,
        ),
      );
    }
    return rows;
  }

  /// The rows for an earlier text, shown until those for [key] arrive,
  /// with the quantity typed now: a tap on one keeps it ("2 Karotten" while
  /// the rows still answer "Karotten").
  List<Suggestion> _withTyped(List<Suggestion> rows, String key) {
    final quantity = _parse(key).quantity;
    if (quantity == null) {
      return rows;
    }
    return [
      for (final Suggestion(:source, :entry) in rows)
        Suggestion(
          source,
          ParsedEntry(
            name: entry.name,
            brand: entry.brand,
            properties: entry.properties,
            quantity: quantity,
            storeId: entry.storeId,
            categoryId: entry.categoryId,
          ),
        ),
    ];
  }

  /// The typed line as the device reads it: a bare number at the end counts
  /// after a name the household has bought or has on the list.
  Entry _parse(String key) => parseEntry(
    key,
    catalogIndex: _catalogIndex(),
    history: [
      for (final usual in _list.state.usuals) usual.name,
      for (final item in _list.state.items.values) item.name,
    ],
  );

  /// Without the server: the typed line split into name and quantity on
  /// the device, then the usuals that start like it.
  List<Suggestion> _offline(String key) {
    final typed = _parse(key);
    final seen = <String>{};
    return [
      for (final suggestion in [
        Suggestion(
          SuggestionSource.typed,
          ParsedEntry(
            name: typed.name,
            quantity: typed.quantity,
            deviceParsed: true,
          ),
        ),
        for (final usual in _list.suggestionsFor(typed.name))
          Suggestion(
            SuggestionSource.history,
            ParsedEntry(
              name: usual.name,
              quantity: typed.quantity ?? usual.quantity,
            ),
          ),
      ])
        if (suggestion.entry.name.isNotEmpty && seen.add(suggestion.key))
          suggestion,
    ];
  }

  /// [_offline] with a category on each row ([guessCategory]): what every
  /// key shows at once while the flag `input-stable-rows` is on.
  List<Suggestion> _local(String key) => [
    for (final Suggestion(:source, :entry) in _offline(key))
      Suggestion(
        source,
        ParsedEntry(
          name: entry.name,
          quantity: entry.quantity,
          categoryId: guessCategory(
            entry.name,
            catalog: _list.state.catalog,
            known: _householdCategories(),
            index: _catalogIndex(),
          ),
          deviceParsed: entry.deviceParsed,
        ),
      ),
  ];

  /// The rows shown for [key], or the device's when another text is shown.
  List<Suggestion> _shownFor(String key) =>
      state.text.trim() == key ? state.suggestions : _device(key);

  /// What every key shows while rows stay put.
  List<Suggestion> _device(String key) =>
      deviceRanked ? _ranked(key) : _local(key);

  /// public.suggest_entries' rows for [key], ranked on the device. Their
  /// brand and details are split as the server splits them, so they are not
  /// [ParsedEntry.deviceParsed]: an add sends them as they are, and the
  /// server guesses the store as for any row without one.
  ///
  /// A port of SQL on an index the server updates: should it ever throw,
  /// the key shows [_local]'s rows instead of failing.
  List<Suggestion> _ranked(String key) {
    final list = _list.state;
    try {
      return suggestEntries(
        key,
        catalog: _catalogIndex(),
        household: list.householdIndex,
        categories: list.catalog,
        known: _householdCategories(),
        pending: _pending(),
        // The repository sends p_category_store with this flag too.
        categoryStore: _stableRows(),
      );
    } on Object {
      return _local(key);
    }
  }

  /// The list's items of the last year that the household index does not
  /// hold as they are now: added, bought or changed since it was fetched.
  List<HistoryRow> _pending() {
    final list = _list.state;
    if (_unindexed case (final of, final rows) when identical(of, list)) {
      return rows;
    }
    final indexed = {
      for (final row in list.householdIndex.history) _historyKey(row): row.at,
    };
    final yearAgo = DateTime.now().subtract(const Duration(days: 365));
    final rows =
        <HistoryRow>[
          for (final item in list.allItems.values)
            if (item.updatedAt.isAfter(yearAgo))
              (
                name: item.name,
                brand: item.brand,
                properties: item.properties,
                quantity: item.quantity,
                normalizedName: normalizeItemName(item.name),
                at: item.boughtAt ?? item.updatedAt,
              ),
        ]..removeWhere(
          (row) => indexed[_historyKey(row)]?.isBefore(row.at) == false,
        );
    _unindexed = (list, rows);
    return rows;
  }

  (ListState, List<HistoryRow>)? _unindexed;

  static String _historyKey(HistoryRow row) =>
      '${row.name}\u0000${row.brand}\u0000${row.properties}';

  /// [householdCategories] of the list as it is now, made again only after
  /// the list changed: typing reads it on every key.
  Map<String, String> _householdCategories() {
    final list = _list.state;
    if (_known case (final of, final known) when identical(of, list)) {
      return known;
    }
    final known = householdCategories(list.allItems.values);
    _known = (list, known);
    return known;
  }

  (ListState, Map<String, String>)? _known;

  AddSheetState _with({
    bool? open,
    String? text,
    SetTo<String?>? Function()? store,
    String? Function()? category,
    List<Suggestion>? suggestions,
    String? answered,
    AddResult? Function()? added,
    DedupeHint? Function()? hint,
    Merge? Function()? merge,
    bool? carried,
    ItemChanges? unsaved,
    bool? fetching,
  }) => AddSheetState(
    open: open ?? state.open,
    text: text ?? state.text,
    store: store == null ? state.store : store(),
    category: category == null ? state.category : category(),
    suggestions: suggestions ?? state.suggestions,
    answered: answered ?? state.answered,
    added: added == null ? state.added : added(),
    hint: hint == null ? (added == null ? state.hint : null) : hint(),
    merge: merge == null ? (added == null ? state.merge : null) : merge(),
    session: state.session,
    carried: carried ?? (suggestions == null && state.carried),
    unsaved: unsaved ?? state.unsaved,
    // A new text waits for its own request.
    fetching: fetching ?? (text == null && state.fetching),
  );

  @override
  Future<void> close() {
    _typing?.cancel();
    saveDetails();
    return super.close();
  }
}

/// The dev-only `[add-sheet timing]` log's clock (jobs 272 and 274).
final class AddSheetClock() {
  /// Since the last key in the field, before the sheet saw it.
  final sinceKey = Stopwatch();

  /// How long the rows for the last text took to make on the device; null
  /// when they came from the cache.
  Duration? rank;
}

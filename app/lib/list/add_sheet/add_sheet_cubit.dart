import 'dart:async';

import 'package:family_groceries/analytics/events.dart';
import 'package:family_groceries/list/add_sheet/suggestion.dart';
import 'package:family_groceries/list/catalog/catalog_index.dart';
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
}) {
  /// Whether [suggestions] answer what is typed now.
  bool get fresh => answered.isNotEmpty && answered == text.trim();
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
class AddSheetCubit(
  final ListCubit _list, {
  Duration debounce = const Duration(milliseconds: 120),
  bool Function() stableRows = _off,
  CatalogIndex Function() catalogIndex = _bundled,
}) extends Cubit<AddSheetState> {
  this : super(const AddSheetState());

  static bool _off() => false;

  static CatalogIndex _bundled() => CatalogIndex.bundled;

  final _debounce = debounce;
  final _stableRows = stableRows;

  /// The catalog the device parses and guesses with: the bundled one with
  /// the server's latest changes.
  final _catalogIndex = catalogIndex;

  /// Whether the flag `input-stable-rows` is on now.
  bool get stableRows => _stableRows();

  final _cache = <String, List<Suggestion>>{};
  Timer? _typing;
  (String, Future<List<Suggestion>>)? _loading;

  /// Bumped by [_forget]: an answer asked for before it is not cached.
  var _epoch = 0;

  /// Opening again starts blank, also when the last close has not
  /// settled yet.
  void show() {
    if (!state.open) {
      _forget();
      emit(const AddSheetState(open: true));
    }
  }

  /// The content stays until [settled], so it is there while the sheet
  /// shrinks away.
  void dismiss() {
    if (state.open) {
      emit(_with(open: false));
    }
  }

  /// The sheet finished closing: start blank next time.
  void settled() {
    if (!state.open) {
      _typing?.cancel();
      emit(const AddSheetState());
    }
  }

  void type(String text) {
    _typing?.cancel();
    final key = text.trim();
    if (key.isEmpty) {
      emit(_with(text: text, added: () => null, suggestions: const []));
      return;
    }
    final known = _cache[key];
    emit(
      _with(
        open: true,
        text: text,
        added: () => null,
        suggestions:
            known ??
            (stableRows
                ? _local(key)
                : state.suggestions.isEmpty
                ? _offline(key)
                : _withTyped(state.suggestions, key)),
        answered: known == null ? null : key,
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
    final entry = suggestion.entry;
    final store = state.store;
    final result =
        _openWithSameWords(entry) ??
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
      emit(AddSheetState(open: state.open, added: result));
    }
    return result;
  }

  /// With the flag `input-stable-rows` the typed row keeps the device's
  /// reading of the line ("Weihenstephan Milch") after the server answers,
  /// where the server's own reading splits off the brand. The open item
  /// with the same words, in any order and field, is the one already on
  /// the list, as the server's reading would have found it.
  AlreadyOnList? _openWithSameWords(ParsedEntry entry) {
    if (!stableRows || !entry.deviceParsed) {
      return null;
    }
    final typed = _words([entry.name]);
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
      onTimeout: () => stableRows ? _local(key) : _offline(key),
    );
    if (isClosed || !state.open || state.text.trim() != key || rows.isEmpty) {
      return null;
    }
    return take(rows.first);
  }

  /// Removes what was just added.
  void undo() {
    if (state.added case Added(:final item)) {
      _list.delete(item.id);
      emit(_with(added: () => null));
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
        rows = mergeRows(
          state.text.trim() == key ? state.suggestions : _local(key),
          rows,
        );
      }
      if (epoch == _epoch) {
        _cache[key] = rows;
      }
    } on Object {
      rows = stableRows ? _local(key) : _offline(key);
    }
    if (_loading?.$1 == key) {
      _loading = null;
    }
    if (!isClosed && state.text.trim() == key) {
      emit(_with(suggestions: rows, answered: key));
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
  );

  @override
  Future<void> close() {
    _typing?.cancel();
    return super.close();
  }
}

import 'dart:async';

import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/siri/siri_channel.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_bloc/flutter_bloc.dart';

/// The items Siri offers for "Add `<item>` to Hummlist": the household's
/// usuals first, then what is on its lists, then what was bought last; each
/// item once (by name, and by `canonical_key` where the server set one), at
/// most [maxSiriSuggestions].
List<SiriSuggestion> siriSuggestions(ListState state) {
  final items = state.allItems.values;
  final active = [
    for (final item in items)
      if (item.status == ItemStatus.active) item,
  ];
  final bought =
      [
        for (final item in items)
          if (item.status == ItemStatus.bought) item,
      ]..sort(
        (a, b) =>
            (b.boughtAt ?? b.updatedAt).compareTo(a.boughtAt ?? a.updatedAt),
      );
  final keyOf = <String, String>{};
  final namesOf = <String, List<String>>{};
  for (final item in [...active, ...bought]) {
    final key = item.canonicalKey;
    if (key == null || key.isEmpty) {
      continue;
    }
    final folded = foldName(item.name);
    keyOf.putIfAbsent(folded, () => key);
    final names = namesOf.putIfAbsent(key, () => []);
    if (!names.any((name) => foldName(name) == folded)) {
      names.add(item.name);
    }
  }
  final seenNames = <String>{};
  final seenKeys = <String>{};
  final suggestions = <SiriSuggestion>[];
  for (final name in [
    for (final usual in state.usuals) usual.name,
    for (final item in active) item.name,
    for (final item in bought) item.name,
  ]) {
    final folded = foldName(name);
    final key = keyOf[folded];
    if (!seenNames.add(folded) || (key != null && !seenKeys.add(key))) {
      continue;
    }
    suggestions.add(
      SiriSuggestion(
        name,
        synonyms: [
          for (final other in namesOf[key] ?? const <String>[])
            if (foldName(other) != folded) other,
        ].take(maxSiriSynonyms).toList(),
      ),
    );
    if (suggestions.length == maxSiriSuggestions) {
      break;
    }
  }
  return suggestions;
}

/// Sends the list's [siriSuggestions] to Siri when they change, at most
/// once per [debounce], and only once the list has loaded.
class SiriSuggestions(
  final SiriChannel _channel,
  StateStreamable<ListState> list, {
  final Duration debounce = const Duration(seconds: 2),
}) {
  this {
    _states = list.stream.listen(_changed);
    _changed(list.state);
  }

  late final StreamSubscription<ListState> _states;
  Timer? _timer;
  List<SiriSuggestion>? _sent;
  ListState? _latest;

  void _changed(ListState state) {
    if (!state.loaded) {
      return;
    }
    _latest = state;
    _timer ??= Timer(debounce, _send);
  }

  void _send() {
    _timer = null;
    final latest = _latest;
    if (latest == null) {
      return;
    }
    final suggestions = siriSuggestions(latest);
    if (listEquals(suggestions, _sent)) {
      return;
    }
    _sent = suggestions;
    unawaited(
      _channel.suggestions(suggestions).catchError((Object _) {
        // No channel (MissingPluginException) or a failed save: Siri keeps
        // the items it had.
        _sent = null;
      }),
    );
  }

  Future<void> close() async {
    _timer?.cancel();
    await _states.cancel();
  }
}

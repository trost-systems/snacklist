import 'dart:math' as math;

import 'package:family_groceries/list/catalog/catalog_index.dart';
import 'package:family_groceries/list/catalog/catalog_index.g.dart';
import 'package:family_groceries/list/entry.dart';
import 'package:family_groceries/list/model.dart';

/// Each name of [items], folded ([foldName]), with the category of the
/// latest item by that name that has one: what the household's own items
/// say, for [guessCategory].
Map<String, String> householdCategories(Iterable<Item> items) {
  final latest = <String, (DateTime, String)>{};
  for (final item in items) {
    if (item.categoryId case final id?) {
      final name = foldName(item.name);
      if (latest[name] case (final at, _) when !item.updatedAt.isAfter(at)) {
        continue;
      }
      latest[name] = (item.updatedAt, id);
    }
  }
  return {for (final MapEntry(:key, value: (_, id)) in latest.entries) key: id};
}

/// The category the server will most likely give [name] on its insert, for
/// a row made on the device (job 272): the household's own for that name
/// ([known], from [householdCategories]), else the lexicon's ([lexiconSeed]
/// over [index]). Null when neither knows it or the household has no such
/// category; the item then waits unsorted for the server, which decides in
/// any case.
String? guessCategory(
  String name, {
  required Catalog catalog,
  required Map<String, String> known,
  required CatalogIndex index,
}) {
  if (known[foldName(name)] case final id?
      when catalog.categories.any((c) => c.id == id)) {
    return id;
  }
  final seed = lexiconSeed(name, index);
  if (seed == null) {
    return null;
  }
  Category? withSeed(String key) =>
      catalog.categories.where((c) => c.seedKey == key).firstOrNull;
  // Without the Baumarkt's categories a DIY word goes to Haushalt, as in
  // public.classify_item_detail.
  return (withSeed(seed) ??
          (hardwareSeedKeys.contains(seed) ? withSeed('household') : null))
      ?.id;
}

/// The seed key public.classify_item_detail gives [name] from its lexicon,
/// without the household's memory and the typo paths: the dictionary's hit
/// (public.dictionary_hit, here over the lexicon's folded forms) against
/// the last word public.classifier_words recognizes, both from [index].
String? lexiconSeed(String name, CatalogIndex index) {
  final key = itemKey(name);
  if (key.isEmpty) {
    return null;
  }
  final exact = _lastWordHit(foldKey(key).split(' '), index.forms);
  final dict = _dictionaryHit(key.split(' '), index.forms);
  return switch ((dict, exact)) {
    ((tier: 2, :final len, seed: _), (len: final exactLen, :final seed)?)
        when exactLen > len =>
      seed,
    ((:final tier, :final seed, len: _)?, _) when tier >= 2 => seed,
    (_, (:final seed, len: _)?) => seed,
    ((tier: 1, :final seed, len: _)?, null) => seed,
    _ => null,
  };
}

/// public.classifier_words without its fuzzy path: phrases first, longest
/// first, then each word or the longest form of 4+ letters it ends with.
/// The last word with a hit wins.
({String seed, int len})? _lastWordHit(
  List<String> words,
  Map<String, CatalogForm> forms,
) {
  var tokens = words;
  final phrases = <String>[];
  if (words.length > 1) {
    final runs =
        [
            for (var a = 0; a < words.length; a++)
              for (var b = a + 2; b <= words.length; b++)
                words.sublist(a, b).join(' '),
          ].where(forms.containsKey).toList()
          ..sort((x, y) => y.length.compareTo(x.length));
    var folded = ' ${words.join(' ')} ';
    for (final form in runs) {
      if (folded.contains(' $form ')) {
        phrases.add(form);
        folded = folded.replaceAll(' $form ', ' #${phrases.length} ');
      }
    }
    tokens = folded.trim().split(' ');
  }
  ({String seed, int len})? hit;
  for (final token in tokens) {
    final phrase = RegExp(r'^#(\d+)$').firstMatch(token);
    final form = phrase != null
        ? phrases[int.parse(phrase[1]!) - 1]
        : [
            for (var i = 0; i <= math.max(token.length - 4, 0); i++)
              token.substring(i),
          ].where(forms.containsKey).firstOrNull;
    if (form != null) {
      hit = (seed: forms[form]!.category, len: form.length);
    }
  }
  return hit;
}

/// public.dictionary_hit over [words], the name's item key: runs of words
/// (tier 5), the whole name (4), a frozen marker (3), the longest term of
/// 3+ letters a word ends with (2), the longest a word starts with (1);
/// within a tier the longest term, then the later word. The device has
/// the terms folded only, so a part counts when its folding is a form.
({int tier, String seed, int len})? _dictionaryHit(
  List<String> words,
  Map<String, CatalogForm> forms,
) {
  String? term(String part) => forms[foldKey(part)]?.category;
  final hits = <({int tier, String seed, int len, int ord})>[
    for (var a = 0; a < words.length; a++)
      for (var b = a + 2; b <= words.length; b++)
        if (words.sublist(a, b).join(' ') case final run when term(run) != null)
          (tier: 5, seed: term(run)!, len: run.length, ord: 0),
    if (term(words.join(' ')) case final seed?)
      (tier: 4, seed: seed, len: words.join(' ').length, ord: 0),
    for (final (i, w) in words.indexed) ...[
      if (w == 'tk' ||
          w.startsWith('tiefkuhl') ||
          w.startsWith('tiefgekuhl') ||
          w.startsWith('gefror'))
        (tier: 3, seed: 'frozen', len: 0, ord: i + 1),
      for (var s = 0; s <= math.max(w.length - 3, 0); s++)
        if (term(w.substring(s)) case final seed?)
          (tier: 2, seed: seed, len: w.length - s, ord: i + 1),
      for (var e = 4; e <= w.length; e++)
        if (term(w.substring(0, e)) case final seed?)
          (tier: 1, seed: seed, len: e, ord: i + 1),
    ],
  ];
  if (hits.isEmpty) {
    return null;
  }
  hits.sort(
    (x, y) => switch (y.tier.compareTo(x.tier)) {
      0 => switch (y.len.compareTo(x.len)) {
        0 => switch (y.ord.compareTo(x.ord)) {
          0 => x.seed.compareTo(y.seed),
          final c => c,
        },
        final c => c,
      },
      final c => c,
    },
  );
  final best = hits.first;
  return (tier: best.tier, seed: best.seed, len: best.len);
}

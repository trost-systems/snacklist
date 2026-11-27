import 'dart:math' as math;

import 'package:family_groceries/list/catalog/catalog_index.dart';
import 'package:family_groceries/list/catalog/catalog_index.g.dart';
import 'package:family_groceries/list/catalog/suggest_entries.dart';
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
  // The add sheet asks for every row on every key, mostly the same names.
  final seeds = _seeds[index] ??= {};
  if (seeds.length >= 4096) {
    seeds.clear();
  }
  return seeds.containsKey(name)
      ? seeds[name]
      : (seeds[name] = _lexiconSeed(name, index));
}

final _seeds = Expando<Map<String, String?>>();

/// [CatalogIndex.classifierTerms]' categories by key: the first category
/// in byte order where terms of two share a key, as the tie in
/// public.dictionary_hit's order picks it.
Map<String, String> _termKeys(CatalogIndex index) => _keys[index] ??= () {
  final byKey = <String, String>{};
  for (final (term: _, :key, :category) in index.classifierTerms) {
    if (byKey[key] case final other? when other.compareTo(category) <= 0) {
      continue;
    }
    byKey[key] = category;
  }
  return byKey;
}();

final _keys = Expando<Map<String, String>>();

String? _lexiconSeed(String name, CatalogIndex index) {
  final key = itemKey(name);
  if (key.isEmpty) {
    return null;
  }
  final exact = _lastWordHit(foldKey(key).split(' '), name, index);
  final dict = _dictionaryHit(key.split(' '), _termKeys(index));
  return switch ((dict, exact)) {
    // The dictionary's hit on a homograph's form loses to the homograph the
    // typed text spells (beer is not Beere), as in classify_item_detail.
    (
      (tier: 2 || 4, :final len, seed: final dictSeed),
      (len: final exactLen, :final seed, :final form)?,
    )
        when exactLen >= len &&
            seed != dictSeed &&
            index.homographs.containsKey(form) =>
      seed,
    (
      (tier: 2, :final len, seed: _),
      (len: final exactLen, :final seed, form: _)?,
    )
        when exactLen > len =>
      seed,
    ((:final tier, :final seed, len: _)?, _) when tier >= 2 => seed,
    (_, (:final seed, len: _, form: _)?) => seed,
    ((tier: 1, :final seed, len: _)?, null) => seed,
    _ => null,
  };
}

/// public.classifier_words without its fuzzy path: phrases first, longest
/// first, then each word or the longest form of 4+ letters it ends with,
/// a homograph's form read as [name] spells it. The last word with a hit
/// wins.
({String seed, int len, String form})? _lastWordHit(
  List<String> words,
  String name,
  CatalogIndex index,
) {
  final forms = index.forms;
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
  ({String seed, int len, String form})? hit;
  for (final token in tokens) {
    final phrase = RegExp(r'^#(\d+)$').firstMatch(token);
    final form = phrase != null
        ? phrases[int.parse(phrase[1]!) - 1]
        : [
            for (var i = 0; i <= math.max(token.length - 4, 0); i++)
              token.substring(i),
          ].where(forms.containsKey).firstOrNull;
    if (form != null) {
      final spelled = switch (index.homographs[form]) {
        final spellings? => homographPick(spellings, name, form)?.category,
        null => null,
      };
      hit = (
        seed: spelled ?? forms[form]!.category,
        len: form.length,
        form: form,
      );
    }
  }
  return hit;
}

/// public.dictionary_hit over [words], the name's item key: runs of words
/// (tier 5), the whole name (4), a frozen marker (3), the longest term of
/// 3+ letters a word ends with (2), the longest a word starts with (1);
/// within a tier the longest term, then the later word, then the
/// category. Its terms are public.classifier_terms by key, every
/// language's ([CatalogIndex.classifierTerms]); synonyms do not count.
({int tier, String seed, int len})? _dictionaryHit(
  List<String> words,
  Map<String, String> terms,
) {
  String? term(String part) => terms[part];
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

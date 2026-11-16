import 'dart:math' as math;
import 'dart:typed_data';

import 'package:family_groceries/list/add_sheet/suggestion.dart';
import 'package:family_groceries/list/catalog/catalog_index.dart';
import 'package:family_groceries/list/catalog/catalog_index.g.dart';
import 'package:family_groceries/list/catalog/household_index.dart';
import 'package:family_groceries/list/catalog/pg.dart';
import 'package:family_groceries/list/category_guess.dart';
import 'package:family_groceries/list/entry.dart';
import 'package:family_groceries/list/model.dart';

/// The add sheet's rows for [text] as public.suggest_entries ranks them
/// (job 274), on the device: the same rows in the same order with the same
/// source, name, brand, details and Menge, from [catalog] and [household]
/// plus [pending], what the device bought or added that the household
/// index does not hold yet. Each row's category is [guessCategory]'s from
/// [categories] (the household's) and [known] ([householdCategories]).
/// Each row's store is the one public.suggest_entries gives it with
/// `p_category_store` = [categoryStore], from the household's store memory
/// and stores in [household]; the category it reads is the guessed one.
/// `supabase/tests/suggest_parity.json` is the table both sides pass.
///
/// [pending] rows add history, not store memory: the server learns a store
/// from a change, a tick or a pick that differs from its guess, which a
/// list row does not tell, so their stores wait for the next index.
List<Suggestion> suggestEntries(
  String text, {
  required CatalogIndex catalog,
  required HouseholdIndex household,
  required Catalog categories,
  required Map<String, String> known,
  Iterable<HistoryRow> pending = const [],
  bool categoryStore = false,
  int limit = mergedRows,
}) {
  final context = _Context(catalog, household, pending);
  final suggestions = <Suggestion>[];
  for (final (:source, :entry, :storeSeed) in _rows(text, context, limit)) {
    final categoryId = guessCategory(
      entry.name,
      catalog: categories,
      known: known,
      index: catalog,
    );
    final storeId =
        source == SuggestionSource.history ||
            source == SuggestionSource.brand ||
            categoryStore
        ? context.guessStore(
            entry.name,
            entry.brand,
            categoryId,
            categoryStore: categoryStore,
          )
        : context.parsedStore(entry.name, storeSeed, categoryId);
    suggestions.add(
      Suggestion(
        source,
        ParsedEntry(
          name: entry.name,
          brand: entry.brand,
          properties: entry.properties,
          quantity: entry.quantity,
          categoryId: categoryId,
          storeId: storeId,
        ),
      ),
    );
  }
  return suggestions;
}

/// [suggestEntries] without categories and stores: each row's source and
/// its text.
List<(SuggestionSource, ParsedEntry)> suggestRows(
  String text, {
  required CatalogIndex catalog,
  required HouseholdIndex household,
  Iterable<HistoryRow> pending = const [],
  int limit = mergedRows,
}) => [
  for (final (:source, :entry, storeSeed: _) in _rows(
    text,
    _Context(catalog, household, pending),
    limit,
  ))
    (source, entry),
];

/// public.suggest_entries' rows for [text], after the caps and the dedupe.
List<_Row> _rows(String text, _Context context, int limit) {
  final rows = <_Row>[];
  if (_btrim(text).isEmpty) {
    return rows;
  }
  final typed = context.read(text);
  if (typed.entry.name.isEmpty) {
    return rows;
  }
  final taken = <SuggestionSource, int>{};
  final seen = <String>{};
  final left = limit.clamp(1, 20);
  for (final row in _candidates(text, typed, context)) {
    final (:source, :entry, storeSeed: _) = row;
    if ((taken[source] ?? 0) >= _caps[source]!) {
      continue;
    }
    if (!seen.add(_suggestionKey(entry))) {
      continue;
    }
    taken[source] = (taken[source] ?? 0) + 1;
    rows.add(row);
    if (rows.length == left) {
      break;
    }
  }
  return rows;
}

/// A row of public.suggest_entries with the store seed of the global brand
/// public.parse_item found in the text that made it (null for history and
/// brand rows, whose store comes from public.guess_store).
typedef _Row = ({
  SuggestionSource source,
  ParsedEntry entry,
  String? storeSeed,
});

/// public.parse_item's reading: the entry and its global brand's store
/// seed.
typedef _Parsed = ({ParsedEntry entry, String? storeSeed});

/// [text] as public.parse_item reads it, without its category and store:
/// name, brand, details and Menge.
ParsedEntry parseItem(
  String text, {
  required CatalogIndex catalog,
  required HouseholdIndex household,
  Iterable<HistoryRow> pending = const [],
}) => _Context(catalog, household, pending).read(text).entry;

/// How a normalized [name] matches the normalized [typed] text, as
/// public.suggest_match: 0 the same, 1 it starts with it, 2 it holds it
/// (from 4 letters), 3 it or a word of it is a typo of it (from 3 letters:
/// same first letter, one edit up to 5 letters, two from 6). Null: no
/// match. The app's [suggestionMatch] ranks the usuals differently.
int? suggestMatch(String typed, String name) =>
    _match(typed, name, _wordsOf(name));

/// [suggestMatch] with [name]'s [_wordsOf] at hand: the ranking matches
/// every key against the same names, so their words are split once.
int? _match(String typed, String name, List<String>? words) {
  if (name == typed) {
    return 0;
  }
  if (name.startsWith(typed)) {
    return 1;
  }
  final length = typed.length;
  if (length < 3) {
    return null;
  }
  if (length >= 4 && name.contains(typed)) {
    return 2;
  }
  final max = length < 6 ? 1 : 2;
  if (_near(typed, name, max)) {
    return 3;
  }
  if (words != null) {
    for (final word in words) {
      if (_near(typed, word, max)) {
        return 3;
      }
    }
  }
  return null;
}

bool _near(String typed, String word, int max) =>
    word.isNotEmpty &&
    word.codeUnitAt(0) == typed.codeUnitAt(0) &&
    (word.length - typed.length).abs() <= max &&
    withinEdits(typed, word, max);

/// [name] split at spaces and hyphens, null when it has neither.
List<String>? _wordsOf(String name) {
  for (var i = 0; i < name.length; i++) {
    final unit = name.codeUnitAt(i);
    if (unit == 0x20 || unit == 0x2d) {
      return name.split(_nameSeparators);
    }
  }
  return null;
}

final _nameSeparators = RegExp('[ -]+');

/// public.brand_key: [brand] lower-cased, umlauts and accents folded,
/// without spaces, dots, apostrophes and hyphens.
String brandKey(String? brand) =>
    _foldAccents((brand ?? '').toLowerCase()).replaceAll(_brandSeparators, '');

final _brandSeparators = RegExp(r"[\s.'’´`-]+");

/// public.normalize_item_name: lower case, umlauts spelled out, spaces
/// collapsed. [foldName] trims any whitespace, the server only spaces.
String normalizeItemName(String name) =>
    _btrim(name)
        .toLowerCase()
        .replaceAll('ä', 'ae')
        .replaceAll('ö', 'oe')
        .replaceAll('ü', 'ue')
        .replaceAll('ß', 'ss')
        .replaceAll(_spaces, ' ');

final _spaces = RegExp(r'\s+');

/// btrim(text): without leading and trailing spaces (only spaces).
String _btrim(String text) {
  var start = 0;
  var end = text.length;
  while (start < end && text.codeUnitAt(start) == 0x20) {
    start++;
  }
  while (end > start && text.codeUnitAt(end - 1) == 0x20) {
    end--;
  }
  return text.substring(start, end);
}

String _foldAccents(String lower) {
  var v = lower
      .replaceAll('ä', 'a')
      .replaceAll('ö', 'o')
      .replaceAll('ü', 'u')
      .replaceAll('ß', 'ss');
  const accents = 'àáâãåçèéêëìíîïñòóôõùúûýÿ';
  const plain = 'aaaaaceeeeiiiinooooouuuyy';
  if (v.runes.any((r) => r >= 0xc0)) {
    v = String.fromCharCodes(
      v.runes.map((r) {
        final at = accents.indexOf(String.fromCharCode(r));
        return at < 0 ? r : plain.codeUnitAt(at);
      }),
    );
  }
  return v.replaceAll('ae', 'a').replaceAll('oe', 'o').replaceAll('ue', 'u');
}

/// public.suggestion_key: rows with one key are one row.
String _suggestionKey(ParsedEntry entry) => [
  _itemNameKey(entry.name),
  brandKey(entry.brand),
  if (entry.properties case final properties?)
    (properties.split(', ').map(_itemNameKey).toList()..sort()).join(','),
].join('|');

/// public.item_name_key: the [itemKey] and the numbers in [name].
String _itemNameKey(String name) {
  final numbers = _number
      .allMatches(name)
      .map((m) => m[0]!.replaceAll(',', '.'));
  return numbers.isEmpty
      ? itemKey(name)
      : '${itemKey(name)} #${numbers.join(' ')}';
}

final _number = RegExp('[0-9]+(?:[.,][0-9]+)?');

/// Up to how many rows of each source public.suggest_entries answers.
const _caps = {
  SuggestionSource.typed: 1,
  SuggestionSource.history: 3,
  SuggestionSource.pack: 2,
  SuggestionSource.variant: 2,
  SuggestionSource.size: 2,
  SuggestionSource.brand: 3,
  SuggestionSource.catalog: 3,
};

/// public.is_pack_property: a pack size ("4er Pack", "Big Pack", "6x1,5 l").
bool _isPackProperty(String property) => _pack.hasMatch(property);

final _pack = RegExp(
  r'^(\d+er(-?pack| (pack|packung|pck|box|karton))?'
  '|(big|maxi|mega|jumbo|standard|spar|vorteils|familien|mini|duo|multi|'
  'monats|xxl|xl) (pack|packung|box)'
  '|doppelpack|vorteilspack|sparpack|großpackung|grosspackung|'
  'familienpackung|monatsbox|xxl'
  r'|\d+ ?x ?\d+([.,]\d+)? ?\p{L}*'
  r'|\d+ rollen?'
  r')$',
  caseSensitive: false,
  unicode: true,
);

final _sizePart = RegExp(r'^Größe (\d+)$');
final _sizeProperty = RegExp(
  r'^(größe|grösse|groesse|gr\.)(\s|\d)',
  caseSensitive: false,
);
final _lastWord = RegExp(r'\S+$');
final _whitespace = RegExp(r'\s');

/// public.suggest_entries' candidates in its order (source, then rank),
/// before the caps and the dedupe.
Iterable<_Row> _candidates(
  String text,
  _Parsed parsed,
  _Context context,
) sync* {
  final (entry: typed, :storeSeed) = parsed;
  final norm = normalizeItemName(typed.name);
  final parts = typed.properties?.split(', ') ?? const <String>[];
  // A size past PostgreSQL's integer fails the server's whole call; here
  // it offers no size rows.
  final size = [
    for (final part in parts)
      if (_sizePart.firstMatch(part) case final m?) int.tryParse(m[1] ?? ''),
  ].firstOrNull;
  final trimmed = _btrim(text);
  final lastKey = itemKey(_lastWord.firstMatch(trimmed)?[0] ?? '');

  final history = context.matching(norm);
  final sameName = [
    for (final row in history)
      if (row.row.normalizedName == norm) row.row,
  ];

  yield (source: SuggestionSource.typed, entry: typed, storeSeed: storeSeed);

  if (norm.length >= 2) {
    final ranked = [...history]
      ..sort(
        (a, b) => _chain([
          () => a.tier.compareTo(b.tier),
          () => a.tier >= 2 ? b.sim.compareTo(a.sim) : 0,
          () => b.row.at.compareTo(a.row.at),
          () => collate(a.row.name, b.row.name),
          () => collate(a.row.brand, b.row.brand),
          () => collate(a.row.properties, b.row.properties),
        ]),
      );
    for (final (:row, tier: _, sim: _) in ranked) {
      yield (
        source: SuggestionSource.history,
        entry: ParsedEntry(
          name: row.name,
          brand: row.brand,
          properties: row.properties,
          quantity: typed.quantity ?? row.quantity,
        ),
        storeSeed: null,
      );
    }
  }

  final typedParts = {for (final p in parts) p.toLowerCase()};
  final otherParts = <String, (String, DateTime)>{};
  for (final row in sameName) {
    for (final part in row.properties?.split(', ') ?? const <String>[]) {
      final lower = part.toLowerCase();
      if (typedParts.contains(lower) || _sizeProperty.hasMatch(part)) {
        continue;
      }
      if (otherParts[lower] case (_, final at) when !row.at.isAfter(at)) {
        continue;
      }
      otherParts[lower] = (part, row.at);
    }
  }
  final rankedParts = otherParts.values.toList()
    ..sort(
      (a, b) => _chain([() => b.$2.compareTo(a.$2), () => collate(a.$1, b.$1)]),
    );
  for (final (part, _) in rankedParts) {
    final pack = _isPackProperty(part);
    yield (
      source: pack ? SuggestionSource.pack : SuggestionSource.variant,
      storeSeed: storeSeed,
      entry: ParsedEntry(
        name: typed.name,
        brand: typed.brand,
        properties: capText(
          [
            if (pack) ...parts.where((p) => !_isPackProperty(p)) else ...parts,
            part,
          ].join(', '),
          120,
        ),
        quantity: typed.quantity,
      ),
    );
  }

  if (size != null) {
    for (final next in [size + 1, size - 1]) {
      if (next >= 1 && next <= 8) {
        yield (
          source: SuggestionSource.size,
          storeSeed: storeSeed,
          entry: ParsedEntry(
            name: typed.name,
            brand: typed.brand,
            properties: [
              for (final p in parts)
                if (p == 'Größe $size') 'Größe $next' else p,
            ].join(', '),
            quantity: typed.quantity,
          ),
        );
      }
    }
  }

  final typedBrand = brandKey(typed.brand);
  final otherBrands = <String, (String, int, DateTime?)>{};
  void offer(String brand, int tier, DateTime? at) {
    final key = brandKey(brand);
    if (key == typedBrand) {
      return;
    }
    if (otherBrands[key] case (_, final t, final a)
        when t < tier || (t == tier && _laterOrSame(a, at))) {
      return;
    }
    otherBrands[key] = (brand, tier, at);
  }

  for (final row in sameName) {
    if (row.brand case final brand?) {
      offer(brand, 0, row.at);
    }
  }
  for (final brand
      in context.catalog.brandsByProduct[norm] ?? const <CatalogBrand>[]) {
    offer(brand.brand, 1, null);
  }
  final rankedBrands = otherBrands.values.toList()
    ..sort(
      (a, b) => _chain([
        () => a.$2.compareTo(b.$2),
        () => _laterFirst(a.$3, b.$3),
        () => collate(a.$1.toLowerCase(), b.$1.toLowerCase()),
      ]),
    );
  for (final (brand, _, _) in rankedBrands) {
    yield (
      source: SuggestionSource.brand,
      entry: ParsedEntry(
        name: typed.name,
        brand: brand,
        properties: typed.properties,
        quantity: typed.quantity,
      ),
      storeSeed: null,
    );
  }

  for (final term in context.terms(lastKey, typed.name)) {
    final (:entry, :storeSeed) = context.read(
      trimmed.replaceFirst(_lastWord, initcap(term)),
    );
    yield (
      source: SuggestionSource.catalog,
      entry: entry,
      storeSeed: storeSeed,
    );
  }
}

/// Whether [a] sorts before or with [b] in `at desc nulls last`.
bool _laterOrSame(DateTime? a, DateTime? b) => _laterFirst(a, b) <= 0;

int _laterFirst(DateTime? a, DateTime? b) => switch ((a, b)) {
  (null, null) => 0,
  (null, _) => 1,
  (_, null) => -1,
  (final a?, final b?) => b.compareTo(a),
};

int _chain(List<int Function()> comparisons) {
  for (final compare in comparisons) {
    final c = compare();
    if (c != 0) {
      return c;
    }
  }
  return 0;
}

/// A history row the typed name matches, with its public.suggest_match
/// tier and its similarity to the typed name.
typedef _Match = ({HistoryRow row, int tier, double sim});

/// What one ranking reads: the catalog's lookups and the household's.
final class _Context(
  CatalogIndex index,
  HouseholdIndex household,
  Iterable<HistoryRow> pending,
) {
  final catalog = _CatalogLookups.of(index);
  final household = _HouseholdLookups.of(household);

  /// The caller's list as it is: the household lookups keep the history
  /// made with the last one.
  final List<HistoryRow> pending = pending is List<HistoryRow>
      ? pending
      : pending.toList();

  /// The history rows whose name [norm] matches, in the history's order.
  List<_Match> matching(String norm) {
    final history = household.historyWith(pending);
    final names = history.names;
    final tiers = List<int?>.filled(names.length, null);
    final sims = List<double>.filled(names.length, 0);
    final typed = trigrams(norm);
    for (var n = 0; n < names.length; n++) {
      final name = names[n];
      if (_match(norm, name, history.words[n]) case final tier?) {
        tiers[n] = tier;
        sims[n] = similarity(typed, household.trigramsOf(name));
      }
    }
    final rows = history.rows;
    return [
      for (var i = 0; i < rows.length; i++)
        if (tiers[history.nameOf[i]] case final tier?)
          (row: rows[i], tier: tier, sim: sims[history.nameOf[i]]),
    ];
  }

  /// public.is_known_name: the lexicon knows a word of [name], or the
  /// household had an item by that name.
  bool isKnownName(String name) {
    final normalized = normalizeItemName(name);
    return catalog.lexiconKnows(itemKey(name)) ||
        household.names.contains(normalized) ||
        pending.any((row) => row.normalizedName == normalized);
  }

  /// The dictionary terms public.suggest_entries offers for the last word
  /// typed ([lastKey], its item key), best first, up to three.
  List<String> terms(String lastKey, String name) {
    if (lastKey.length < 2) {
      return const [];
    }
    final nameKey = itemKey(name);
    final multiWord = _whitespace.hasMatch(name);
    final unserved = household.index.unserved;
    final lastTrigrams = trigrams(lastKey);
    final found = <({String term, int tier, double sim})>[];
    for (final (:key, :words, :terms) in catalog.termKeys) {
      final tier = _match(lastKey, key, words);
      if (tier == null ||
          key == nameKey ||
          !(tier < 2 || !multiWord || (tier == 2 && !key.contains(' ')))) {
        continue;
      }
      final term = terms
          .where((t) => !unserved.contains(t.category) || lastKey.length >= 4)
          .firstOrNull;
      if (term != null) {
        found.add((
          term: term.term,
          tier: tier,
          sim: tier >= 2
              ? similarity(lastTrigrams, catalog.trigramsOf(key))
              : 0,
        ));
      }
    }
    found.sort(
      (a, b) => _chain([
        () => a.tier.compareTo(b.tier),
        () => a.tier >= 2 ? b.sim.compareTo(a.sim) : 0,
        () => a.term.runes.length.compareTo(b.term.runes.length),
        () => collate(a.term, b.term),
      ]),
    );
    return [for (final t in found.take(3)) t.term];
  }

  /// public.parse_item(household, text) without category and store.
  _Parsed read(String input) {
    var text = _btrim(input).replaceAll(_spaces, ' ');
    for (final (pattern, replacement) in _halves) {
      text = text.replaceFirst(pattern, replacement);
    }
    text = text.replaceAllMapped(
      _multipack,
      (m) => '${m[1]}${m[2]}x${m[3]}${m[4] ?? ''}',
    );

    String? quantity;
    if (_leading.firstMatch(text) case final m?
        when m[3] == null || !_numberName.hasMatch(text.toLowerCase())) {
      final unit = m[2] ?? m[4];
      quantity = [
        m[1] ?? '${numberWords[m[3]!.toLowerCase()]}',
        if ((unit ?? 'x').toLowerCase() != 'x') unit!,
      ].join(' ');
      text = m[5]!;
    }

    if (quantity == null) {
      if (_trailing.firstMatch(text) case final m?) {
        final count = numberWords[m[3]!.toLowerCase()]?.toString() ?? m[3]!;
        final rest = '${m[1] ?? ''}${m[2]}';
        if ((int.tryParse(count) ?? 21) <= 20 &&
            !_digit.hasMatch(m[2]!) &&
            !_sizeWord.hasMatch(
              m[2]!.replaceFirst(_trailingDots, '').toLowerCase(),
            ) &&
            isKnownName(rest)) {
          quantity = count;
          text = rest;
        }
      }
    }

    final tokens = text
        .replaceAllMapped(_listPunctuation, (m) => m[1]!)
        .split(_spaces)
        .where((t) => t.isNotEmpty)
        .toList();
    final n = tokens.length;
    if (n == 0) {
      return (
        entry: ParsedEntry(name: '', quantity: quantity),
        storeSeed: null,
      );
    }
    final suffix = [
      for (final t in tokens) _trailingPunctuation.firstMatch(t)?[0] ?? '',
    ];
    for (var i = 0; i < n; i++) {
      tokens[i] = tokens[i].replaceFirst(_trailingPunctuation, '');
    }
    final low = [for (final t in tokens) normalizeItemName(t)];
    final kind = List<_Kind?>.filled(n, null);

    // Marke: the longest run first, then the leftmost; a global brand
    // before a learned one.
    String? brand;
    CatalogBrand? global;
    var brandAt = -1;
    var brandLength = 0;
    search:
    for (var l = 3; l >= 1; l--) {
      for (var s = 0; s + l <= n; s++) {
        final key = brandKey(tokens.sublist(s, s + l).join(' '));
        final learned = household.brands[key];
        if (catalog.index.brands[key] case final hit?) {
          global = hit;
          brand = hit.brand;
        } else if (learned != null) {
          brand = learned;
        } else {
          continue;
        }
        brandAt = s;
        brandLength = l;
        break search;
      }
    }
    final product = global?.product;
    for (var i = brandAt; i >= 0 && i < brandAt + brandLength; i++) {
      kind[i] = _Kind.brand;
    }

    final properties = <String>[];
    for (var i = 0; i < n; i++) {
      if (kind[i] != null) {
        continue;
      }
      final t1 = low[i];
      final t2 = i + 1 < n && kind[i + 1] == null ? low[i + 1] : null;
      String? property;
      var length = 0;
      if (_sizeWordT1.hasMatch(t1) && t2 != null && _sizeValue.hasMatch(t2)) {
        length = 2;
        property = 'Größe ${t2.toUpperCase()}';
      } else if (_sizeJoined.hasMatch(t1)) {
        length = 1;
        property = 'Größe ${_sizeNumber.firstMatch(t1)![0]}';
      } else if (_percent.hasMatch(t1) ||
          (_decimal.hasMatch(t1) && t2 == '%')) {
        length = t1.endsWith('%') ? 1 : 2;
        property =
            '${t1.replaceFirst(_trailingPercent, '').replaceAll('.', ',')} %';
        final next = i + length;
        if (next < n &&
            kind[next] == null &&
            const {'fett', 'vol', 'vol.'}.contains(low[next])) {
          property = '$property ${tokens[next]}';
          length++;
        }
      } else if (_er.hasMatch(t1) && _packWords.contains(t2)) {
        length = 2;
        property = '${tokens[i]} ${tokens[i + 1]}';
      } else if (_erPack.hasMatch(t1) || _packs.contains(t1)) {
        length = 1;
        property = tokens[i];
      } else if (_packPrefixes.contains(t1) &&
          const {'pack', 'packung', 'box'}.contains(t2)) {
        length = 2;
        property = '${tokens[i]} ${tokens[i + 1]}';
      } else if (_digits.hasMatch(t1) &&
          const {'rolle', 'rollen'}.contains(t2)) {
        length = 2;
        property = '${tokens[i]} ${tokens[i + 1]}';
      } else if (_lagig.hasMatch(t1)) {
        length = 1;
        property = '${_leadingDigits.firstMatch(t1)![0]}-lagig';
      } else if (_digits.hasMatch(t1) && t2 == 'lagig') {
        length = 2;
        property = '$t1-lagig';
      } else if (_multipackToken.hasMatch(tokens[i])) {
        length = 1;
        property = tokens[i]
            .replaceFirstMapped(_multipackSplit, (m) => '${m[1]} ${m[2]}')
            .replaceFirst(_trailingSpaces, '');
      } else if (_decimal.hasMatch(t1) &&
          t2 != null &&
          _trailingUnitWord.hasMatch(tokens[i + 1]) &&
          tokens[i + 1].toLowerCase() != 'x') {
        length = 2;
        property = '${tokens[i]} ${tokens[i + 1]}';
      } else if (_amountToken.hasMatch(tokens[i]) && !_countX.hasMatch(t1)) {
        length = 1;
        property = tokens[i].replaceFirstMapped(
          _amountSplit,
          (m) => '${m[1]} ',
        );
      } else if (quantity == null && _count.hasMatch(t1)) {
        // A count anywhere ("Spülmittel Pril 2x") when none came first.
        quantity = _digitRun.firstMatch(t1)![0];
        kind[i] = _Kind.quantity;
      } else {
        // Descriptors and flavours after a name word or the brand
        // ("Joghurt Erdbeere"); the plain descriptors anywhere ("Bio Eier").
        final named = kind.take(i).any((k) => k == null || k == _Kind.brand);
        for (final (alias, size) in [if (t2 != null) ('$t1 $t2', 2), (t1, 1)]) {
          if (_descriptors[alias] case (final label, final words)
              when words == size &&
                  (named || _plainDescriptors.contains(alias))) {
            property = label;
            length = words;
            break;
          }
        }
      }
      if (property != null) {
        // The first amount with a unit is the Menge, wherever it stands
        // ("Äpfel 1 kg bio"), unless a leading count took it.
        if (quantity == null && _amountProperty.hasMatch(property)) {
          quantity = property;
        } else {
          properties.add(property);
        }
        for (var k = i; k < i + length; k++) {
          kind[k] = _Kind.property;
        }
      }
    }

    var name = [
      for (var i = 0; i < n; i++)
        if (kind[i] == null) '${tokens[i]}${suffix[i]}',
    ].join(' ').replaceFirst(_trailingListPunctuation, '');
    if (product != null &&
        name.isNotEmpty &&
        (catalog.dictionaryCategory(itemKey(name)) == null ||
            (!_whitespace.hasMatch(name) &&
                _domain(catalog.dictionaryCategory(itemKey(name))) !=
                    _domain(catalog.dictionaryCategory(itemKey(product)))))) {
      // "Whiskas Lachs": the one name word is of another kind than the
      // brand's product; "Persil Color": the dictionary knows none of the
      // name. Either way it is the variety.
      properties.insert(0, name);
      name = product;
    } else if (name.isEmpty && product != null) {
      name = product;
    } else if (name.isEmpty && brand != null) {
      // Only a brand and its properties: the brand is the name.
      name = tokens.sublist(brandAt, brandAt + brandLength).join(' ');
      brand = null;
    } else if (name.isEmpty) {
      // Nothing but properties ("Größe 3", "Bio"): nothing is split off.
      name = tokens.join(' ');
      properties.clear();
    }
    return (
      entry: ParsedEntry(
        name: capText(name, 120)!,
        brand: capText(brand, 60),
        properties: capText(switch (properties.join(', ')) {
          '' => null,
          final joined => joined,
        }, 120),
        quantity: capText(quantity, 40),
      ),
      storeSeed: global?.storeSeed,
    );
  }

  /// public.suggest_store: the store taught for [name]'s item key, else for
  /// its canonical key, the newest lesson first.
  String? suggestStore(String name) {
    final key = itemKey(name);
    return household.memoryByKey[key] ??
        (household.index.memory.isEmpty
            ? null
            : household.memoryByCanonical[catalog.canonicalOfKey(key)]);
  }

  /// The store public.parse_item gives a line it read as [name] with
  /// [storeSeed] in the household's [category], without
  /// `p_category_store`: the taught one, the brand's, the category's
  /// (public.category_store).
  String? parsedStore(String name, String? storeSeed, String? category) =>
      suggestStore(name) ??
      household.storeBySeed[storeSeed] ??
      household.seeded[category];

  /// public.guess_store: the taught store; with [categoryStore] none for a
  /// name last set to „Ohne Laden“; else the store of [brand], with
  /// [categoryStore] the one the household uses most for [category], then
  /// the category's own (dm, Baumarkt).
  String? guessStore(
    String name,
    String? brand,
    String? category, {
    required bool categoryStore,
  }) {
    if (suggestStore(name) case final store?) {
      return store;
    }
    if (categoryStore && household.cleared.contains(itemKey(name))) {
      return null;
    }
    return household.storeBySeed[catalog
            .index
            .brands[brandKey(brand)]
            ?.storeSeed] ??
        (categoryStore ? household.usual[category] : null) ??
        household.seeded[category];
  }
}

enum _Kind() {
  brand,
  property,
  quantity,
}

/// public.item_domain: what kind of thing a category's items are.
String? _domain(String? category) => switch (category) {
  'household' || 'drugstore' => 'non-food',
  'drinks' => 'drinks',
  null => null,
  _ => 'food',
};

final _unitAlternation = units.join('|');
// Rolls are an Eigenschaft at the end ("Klopapier 16 Rollen"), a Menge
// only up front.
final _trailingUnits = _unitAlternation.replaceAll('rolle|rollen|', '');
final _wordAlternation = numberWords.keys.join('|');
const _articles = {'ein', 'eine', 'einen', 'einer'};
final _trailingWords = numberWords.keys
    .where((k) => !_articles.contains(k))
    .join('|');

/// PostgreSQL's `\y` after a word: no letter, digit or underscore follows.
const _wordEnd = r'(?![\p{L}\p{N}_])';

final _halves = [
  (
    RegExp(
      r'^(?:(?:ein|eine|einen)\s+)?(?:halbe[snmr]?|halb)\s+'
      '(?=($_unitAlternation)$_wordEnd)',
      caseSensitive: false,
      unicode: true,
    ),
    '0,5 ',
  ),
  (
    RegExp(
      r'^(?:(?:ein|eine|einen)\s+)?(?:halbe[snmr]?|halb)\s+',
      caseSensitive: false,
    ),
    '1/2 ',
  ),
  (RegExp(r'^(?:anderthalb|eineinhalb)\s+', caseSensitive: false), '1,5 '),
];

final _multipack = RegExp(
  r'(^|\s)(\d+)\s*[x×]\s*(\d+(?:[.,]\d+)?)\s*'
  '(?:($_unitAlternation)'
  r'\.?)?(?=\s|$)',
  caseSensitive: false,
);

final _leading = RegExp(
  '^(?:(\\d+(?:[.,/]\\d+)?)(?:\\s*($_unitAlternation)\\.?)?'
  '|($_wordAlternation)(?:\\s+($_unitAlternation)\\.?)?)\\s+(.+)\$',
  caseSensitive: false,
);

final _numberName = RegExp(
  '^(?:${numberNames.join('|')})$_wordEnd',
  unicode: true,
);

final _trailing = RegExp(
  '^(.*\\s)?(\\S+)\\s([1-9]\\d?|$_trailingWords)\$',
  caseSensitive: false,
);
final _digit = RegExp(r'\d');
final _trailingDots = RegExp(r'\.+$');
final _sizeWord = RegExp(
  '^($_unitAlternation|größe|grösse|groesse|gr|stufe|nr|no|size|typ|type|'
  'klasse|pack|pcs|mah|cl|%)'
  r'$',
);

final _listPunctuation = RegExp(r'\s+([,;]+)(?=\s|$)');
final _trailingPunctuation = RegExp(r'[,;]+$');
final _trailingListPunctuation = RegExp(r'[,; ]+$');

final _sizeWordT1 = RegExp(r'^(groesse|grosse|gr\.?)$');
final _sizeValue = RegExp(r'^(\d+(\+|-\d+)?|x{0,3}s|m|x{0,3}l)$');
final _sizeJoined = RegExp(r'^(groesse|grosse|gr\.?)\d+\+?$');
final _sizeNumber = RegExp(r'\d+\+?$');
final _percent = RegExp(r'^\d+([.,]\d+)?%$');
final _decimal = RegExp(r'^\d+([.,]\d+)?$');
final _trailingPercent = RegExp(r'%+$');
final _er = RegExp(r'^\d+er$');
const _packWords = {'pack', 'packung', 'pck', 'box', 'karton'};
final _erPack = RegExp(r'^\d+er(-?pack)?$');
const _packs = {
  'doppelpack', 'vorteilspack', 'sparpack', 'grosspackung', //
  'familienpackung', 'monatsbox', 'xxl',
};
const _packPrefixes = {
  'big', 'maxi', 'mega', 'jumbo', 'standard', 'spar', 'vorteils', //
  'familien', 'mini', 'duo', 'multi', 'monats', 'xxl', 'xl',
};
final _digits = RegExp(r'^\d+$');
final _lagig = RegExp(r'^\d+-?lagig$');
final _leadingDigits = RegExp(r'^\d+');
final _multipackToken = RegExp(
  r'^\d+x\d+([.,]\d+)?'
  '($_unitAlternation)?'
  r'\.?$',
  caseSensitive: false,
);
final _multipackSplit = RegExp(r'^(\d+x\d+(?:[.,]\d+)?)(.*)$');
final _trailingSpaces = RegExp(r' +$');
final _trailingUnitWord = RegExp(
  '^($_trailingUnits)\\.?\$',
  caseSensitive: false,
);
final _amountToken = RegExp(
  '^\\d+([.,]\\d+)?($_trailingUnits)\\.?\$',
  caseSensitive: false,
);
final _countX = RegExp(r'^\d+x$');
final _amountSplit = RegExp(r'^(\d+(?:[.,]\d+)?)\s*');
final _count = RegExp(r'^(\d+x|x\d+)$');
final _digitRun = RegExp(r'\d+');
final _amountProperty = RegExp(
  '^\\d+([.,]\\d+)? ?($_trailingUnits)\\.?\$',
  caseSensitive: false,
);

final _descriptors = {
  for (final (alias, label, words) in descriptors) alias: (label, words),
};
const _plainDescriptors = {
  'bio', 'laktosefrei', 'glutenfrei', 'vegan', 'vegetarisch', 'zuckerfrei', //
  'ohne zucker', 'koffeinfrei', 'entkoffeiniert', 'alkoholfrei', 'fettarm',
};

/// What the ranking reads of a [CatalogIndex], built once per index.
final class _CatalogLookups._(final CatalogIndex index) {
  factory of(CatalogIndex index) => _built[index] ??= _CatalogLookups._(index);

  static final _built = Expando<_CatalogLookups>();

  /// Each term key with its terms, shortest first, then in the database's
  /// order: public.suggest_entries offers the first one.
  late final Map<String, List<CatalogTerm>> termsByKey = () {
    final byKey = <String, List<CatalogTerm>>{};
    for (final term in index.terms.values) {
      (byKey[term.key] ??= []).add(term);
    }
    for (final terms in byKey.values) {
      terms.sort(
        (a, b) => _chain([
          () => a.term.runes.length.compareTo(b.term.runes.length),
          () => collate(a.term, b.term),
        ]),
      );
    }
    return byKey;
  }();

  /// [termsByKey] as a list, each key with its [_wordsOf].
  late final termKeys = [
    for (final MapEntry(:key, value: terms) in termsByKey.entries)
      (key: key, words: _wordsOf(key), terms: terms),
  ];

  /// The global brands by their product, normalized.
  late final Map<String, List<CatalogBrand>> brandsByProduct = () {
    final byProduct = <String, List<CatalogBrand>>{};
    for (final brand in index.brands.values) {
      if (brand.product case final product?) {
        (byProduct[normalizeItemName(product)] ??= []).add(brand);
      }
    }
    return byProduct;
  }();

  /// The one-word lexicon forms by their first letter, for typos.
  late final Map<String, List<CatalogForm>> _formsByHead = () {
    final byHead = <String, List<CatalogForm>>{};
    for (final form in index.forms.values) {
      if (form.form.isNotEmpty && !form.form.contains(' ')) {
        (byHead[form.form.substring(0, 1)] ??= []).add(form);
      }
    }
    return byHead;
  }();

  final _trigrams = <String, Set<String>>{};

  Set<String> trigramsOf(String key) =>
      _trigrams.putIfAbsent(key, () => trigrams(key));

  /// public.dictionary_category of an item key: public.dictionary_hit's
  /// category. Runs of words (tier 5), the whole key (4), a frozen word
  /// (3), the longest term of 3+ letters a word ends with (2), the longest
  /// of 4+ a word starts with (1); within a tier the longest term, then the
  /// later word, then the category.
  String? dictionaryCategory(String key) {
    final words = key.split(' ').where((w) => w.isNotEmpty).toList();
    final hits = <({int tier, int len, int ord, String category})>[];
    void hit(String term, int tier, int ord) {
      for (final t in termsByKey[term] ?? const <CatalogTerm>[]) {
        hits.add((
          tier: tier,
          len: term.length,
          ord: ord,
          category: t.category,
        ));
      }
    }

    for (var a = 0; a < words.length; a++) {
      for (var b = a + 2; b <= words.length; b++) {
        hit(words.sublist(a, b).join(' '), 5, 0);
      }
    }
    hit(key, 4, 0);
    final parts = <String, int>{};
    final starts = <String, int>{};
    for (final (i, w) in words.indexed) {
      if (w == 'tk' ||
          w.startsWith('tiefkuhl') ||
          w.startsWith('tiefgekuhl') ||
          w.startsWith('gefror')) {
        hits.add((tier: 3, len: 0, ord: i + 1, category: 'frozen'));
      }
      for (var s = 0; s < math.max(w.length - 2, 1); s++) {
        parts[w.substring(s)] = i + 1;
      }
      for (var e = 4; e <= w.length; e++) {
        starts[w.substring(0, e)] = i + 1;
      }
    }
    for (final MapEntry(key: part, value: ord) in parts.entries) {
      hit(part, 2, ord);
    }
    for (final MapEntry(key: start, value: ord) in starts.entries) {
      hit(start, 1, ord);
    }
    if (hits.isEmpty) {
      return null;
    }
    hits.sort(
      (x, y) => _chain([
        () => y.tier.compareTo(x.tier),
        () => y.len.compareTo(x.len),
        () => y.ord.compareTo(x.ord),
        () => collate(x.category, y.category),
      ]),
    );
    return hits.first.category;
  }

  /// Whether public.classifier_words finds a word of an item key with a
  /// category: a phrase, a form a word ends with (4+ letters), or a typo
  /// of one (public.lexicon_fuzzy).
  bool lexiconKnows(String key) {
    final words = foldKey(key).split(' ').where((w) => w.isNotEmpty).toList();
    for (var a = 0; a < words.length; a++) {
      for (var b = a + 2; b <= words.length; b++) {
        if (index.forms.containsKey(words.sublist(a, b).join(' '))) {
          return true;
        }
      }
    }
    return words.any(
      (w) =>
          [for (var i = 0; i < math.max(w.length - 3, 1); i++) w.substring(i)]
              .any(index.forms.containsKey) ||
          _hasTypo(w),
    );
  }

  /// public.lexicon_fuzzy(word, 2) answers a row.
  bool _hasTypo(String word) => _fuzzy(word, 2) != null;

  /// public.lexicon_fuzzy(word, max): of the one-word forms with [word]'s
  /// first letter at most [max] edits away (fewer for short words; a swap
  /// of two letters is one), the nearest, when they are all of one
  /// category; the first of them in the database's order.
  CatalogForm? _fuzzy(String word, int max) {
    final length = word.length;
    if (length < 5) {
      return null;
    }
    var best = 3;
    final nearest = <CatalogForm>[];
    for (final form
        in _formsByHead[word.substring(0, 1)] ?? const <CatalogForm>[]) {
      final f = form.form;
      if ((f.length - length).abs() > 2 || f == word) {
        continue;
      }
      final swap = f.length == length && _isSwap(word, f);
      final allowed = math.min(
        max,
        math.min(f.length, length) >= 8
            ? 2
            : math.max(f.length, length) >= 6
            ? 1
            : 0,
      );
      final int distance;
      if (swap && max >= 1) {
        distance = 1;
      } else if (allowed > 0 && withinEdits(word, f, allowed)) {
        distance = withinEdits(word, f, 1) ? 1 : 2;
      } else {
        continue;
      }
      if (distance < best) {
        best = distance;
        nearest.clear();
      }
      if (distance == best) {
        nearest.add(form);
      }
    }
    if (nearest.map((f) => f.category).toSet().length != 1) {
      return null;
    }
    return nearest.reduce((a, b) => collate(a.form, b.form) <= 0 ? a : b);
  }

  /// public.canonical_of_key: the key spelling variants, synonyms and
  /// recognized typos of an item key share, per word of
  /// public.classifier_words.
  String canonicalOfKey(String key) {
    if (_canonical.length >= 4096) {
      _canonical.clear();
    }
    return _canonical[key] ??= _canonicalOfKey(key);
  }

  final _canonical = <String, String>{};

  String _canonicalOfKey(String key) {
    var words = foldKey(key).split(' ').where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) {
      return '';
    }
    final forms = index.forms;
    final phrases = <CatalogForm>[];
    if (words.length > 1) {
      final runs = [
        for (var a = 0; a < words.length; a++)
          for (var b = a + 2; b <= words.length; b++)
            ?forms[words.sublist(a, b).join(' ')],
      ]..sort((x, y) => y.form.length.compareTo(x.form.length));
      var folded = ' ${words.join(' ')} ';
      for (final phrase in runs) {
        if (folded.contains(' ${phrase.form} ')) {
          phrases.add(phrase);
          folded = folded.replaceAll(
            ' ${phrase.form} ',
            ' #${phrases.length} ',
          );
        }
      }
      words = folded.trim().split(' ');
    }
    return [
      for (final word in words)
        if (_phraseToken.firstMatch(word) case final m?)
          phrases[int.parse(m[1]!) - 1].canonical
        else
          _canonicalOfWord(word),
    ].join(' ');
  }

  /// A word's canonical: a typo's form, else the word with the longest
  /// form of 4+ letters it ends with (or itself) replaced by its
  /// canonical, else the word.
  String _canonicalOfWord(String word) {
    CatalogForm? hit;
    for (var i = 0; i < math.max(word.length - 3, 1); i++) {
      if (index.forms[word.substring(i)] case final form?) {
        hit = form;
        break;
      }
    }
    if (hit == null || word.length - hit.form.length >= 4) {
      final fuzzy = _fuzzy(word, hit == null ? 2 : 1);
      if (fuzzy != null &&
          (hit == null ||
              (fuzzy.form.length >= hit.form.length + 4 &&
                  !fuzzy.form.endsWith(hit.form)))) {
        return fuzzy.canonical;
      }
    }
    return hit == null
        ? word
        : word.substring(0, word.length - hit.form.length) + hit.canonical;
  }
}

final _phraseToken = RegExp(r'^#(\d+)$');

/// Whether swapping two neighbouring letters of [word] makes [form].
bool _isSwap(String word, String form) {
  for (var i = 0; i + 1 < word.length; i++) {
    if (word.codeUnitAt(i) != form.codeUnitAt(i)) {
      return word.codeUnitAt(i) == form.codeUnitAt(i + 1) &&
          word.codeUnitAt(i + 1) == form.codeUnitAt(i) &&
          word.substring(i + 2) == form.substring(i + 2);
    }
  }
  return false;
}

/// What the ranking reads of a [HouseholdIndex], built once per index.
final class _HouseholdLookups._(final HouseholdIndex index) {
  factory of(HouseholdIndex index) =>
      _built[index] ??= _HouseholdLookups._(index);

  static final _built = Expando<_HouseholdLookups>();

  /// The learned brands by brand key.
  late final Map<String, String> brands = {
    for (final b in index.brands) b.key: b.brand,
  };

  /// The store taught for each item key, the newest.
  late final Map<String, String> memoryByKey = _newest((m) => m.itemKey);

  /// The store taught for each canonical key, the newest.
  late final Map<String, String> memoryByCanonical = _newest(
    (m) => m.canonicalKey,
  );

  Map<String, String> _newest(String? Function(StoreMemory m) keyOf) => {
    for (final m in index.memory.reversed) ?keyOf(m): m.storeId,
  };

  late final Set<String> cleared = index.cleared.toSet();

  /// The household's stores by seed key.
  late final Map<String?, String> storeBySeed = {
    for (final s in index.stores) s.seedKey: s.storeId,
  };

  /// public.category_usual_store by category.
  late final Map<String?, String> usual = {
    for (final c in index.categories) c.categoryId: ?c.usual,
  };

  /// public.category_store by category.
  late final Map<String?, String> seeded = {
    for (final c in index.categories) c.categoryId: ?c.seeded,
  };

  /// The normalized names of every item the household had.
  late final Set<String> names = {
    ...index.known,
    for (final row in index.history) row.normalizedName,
  };

  final _trigrams = <String, Set<String>>{};

  Set<String> trigramsOf(String name) =>
      _trigrams.putIfAbsent(name, () => trigrams(name));

  /// The history public.suggest_entries reads with [pending] on top, made
  /// again only for another pending list.
  _History historyWith(List<HistoryRow> pending) {
    if (_history case (final of, final history) when identical(of, pending)) {
      return history;
    }
    final history = _History(
      pending.isEmpty ? index.history : _merged(index.history, pending),
    );
    _history = (pending, history);
    return history;
  }

  (List<HistoryRow>, _History)? _history;

  /// One row per name, brand and details, the latest.
  static List<HistoryRow> _merged(
    List<HistoryRow> history,
    List<HistoryRow> pending,
  ) {
    final rows = <String, HistoryRow>{};
    for (final row in [...history, ...pending]) {
      final key = '${row.name}\u0000${row.brand}\u0000${row.properties}';
      if (rows[key] case final kept? when !row.at.isAfter(kept.at)) {
        continue;
      }
      rows[key] = row;
    }
    return rows.values.toList();
  }
}

/// History rows with their normalized names numbered: the ranking matches
/// each name once per key, not each row.
final class _History(final List<HistoryRow> rows) {
  this {
    final numbers = <String, int>{};
    for (final (i, row) in rows.indexed) {
      nameOf[i] = numbers.putIfAbsent(row.normalizedName, () {
        names.add(row.normalizedName);
        words.add(_wordsOf(row.normalizedName));
        return names.length - 1;
      });
    }
  }

  /// The distinct normalized names, in the order they first appear.
  final names = <String>[];

  /// Each name's [_wordsOf].
  final words = <List<String>?>[];

  /// Each row's index in [names].
  final nameOf = Int32List(rows.length);
}

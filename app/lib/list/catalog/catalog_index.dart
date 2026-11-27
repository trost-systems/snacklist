import 'package:family_groceries/list/catalog/catalog_index.g.dart';
import 'package:flutter/foundation.dart';

/// A row of public.classifier_terms: a dictionary term, its item key and
/// the seed key of its category.
typedef CatalogTerm = ({String term, String key, String category});

/// A row of public.catalog_words (job 470): a word another language's
/// catalog offers, its item key, the seed key of its category, and whether
/// it is a concept of its own (a public.classifier_terms row, which
/// public.dictionary_hit reads like a German term).
typedef CatalogWord = ({
  String lang,
  String word,
  String key,
  String category,
  bool own,
});

/// A row of public.classifier_lexicon: a folded form public.classifier_words
/// matches, the term it stands for, its category's seed key, and whether it
/// came from a synonym.
typedef CatalogForm = ({
  String form,
  String canonical,
  String category,
  bool synonym,
});

/// A spelling of a form that words of different categories share, from
/// public.classifier_lexicon.homographs: the spelling as public.surface_word
/// writes it, the canonical and category's seed key it stands for, and
/// whether it came from a synonym. public.homograph_pick reads them.
typedef CatalogHomograph = ({
  String surface,
  String canonical,
  String category,
  bool synonym,
});

/// A row of public.brands: its brand key, the brand as written, the product
/// it names alone ("Tempo": Taschentücher) and the store it is sold in.
typedef CatalogBrand = ({
  String key,
  String brand,
  String? product,
  String? storeSeed,
});

/// The global catalog the device ranks and guesses with (job 274): the
/// tables of public.catalog_rows() under their [version]
/// (public.catalog_version()), each keyed by its primary key in byte order.
/// The bundled one comes from catalog_index.g.dart; [apply] lays the
/// server's changes over it. Its maps are unmodifiable.
final class CatalogIndex._(
  final String version, {
  required Map<String, CatalogTerm> terms,
  required Map<String, CatalogForm> forms,
  required Map<String, CatalogBrand> brands,
  required Map<String, List<CatalogHomograph>> homographs,
  required Map<String, CatalogWord> words,
}) {
  /// The language of [terms], the classifier's own (job 470).
  static const baseLanguage = 'de';

  /// The catalog the app was built with, made on first use.
  static final bundled = CatalogIndex._(
    catalogVersion,
    terms: {
      for (final (term, key, category) in catalogTerms)
        term: (term: term, key: key, category: category),
    },
    forms: {
      for (final (form, canonical, category, synonym) in catalogForms)
        form: (
          form: form,
          canonical: canonical,
          category: category,
          synonym: synonym,
        ),
    },
    brands: {
      for (final (key, brand, product, storeSeed) in catalogBrands)
        key: (key: key, brand: brand, product: product, storeSeed: storeSeed),
    },
    homographs: _byForm(catalogHomographs),
    words: {
      for (final (lang, word, key, category, own) in catalogWords)
        _wordId(lang, word): (
          lang: lang,
          word: word,
          key: key,
          category: category,
          own: own,
        ),
    },
  );

  /// By term.
  final Map<String, CatalogTerm> terms = _sorted(terms);

  /// By form.
  final Map<String, CatalogForm> forms = _sorted(forms);

  /// By brand key.
  final Map<String, CatalogBrand> brands = _sorted(brands);

  /// By the form the spellings share.
  final Map<String, List<CatalogHomograph>> homographs = Map.unmodifiable(
    homographs,
  );

  /// By `lang:word`, as public.catalog_rows lists them.
  final Map<String, CatalogWord> words = _sorted(words);

  /// The words the catalog offers in [language] ([languageFor]) as terms:
  /// German offers its [terms].
  Map<String, CatalogTerm> termsIn(String language) =>
      language == baseLanguage ? terms : _wordTerms[language] ?? const {};

  late final Map<String, Map<String, CatalogTerm>> _wordTerms = () {
    final byLanguage = <String, Map<String, CatalogTerm>>{};
    for (final (:lang, :word, :key, :category, own: _) in words.values) {
      (byLanguage[lang] ??= {})[word] = (
        term: word,
        key: key,
        category: category,
      );
    }
    return {
      for (final MapEntry(:key, :value) in byLanguage.entries)
        key: _sorted(value),
    };
  }();

  /// The catalog's language for an app in [language] (Peter, ML1): German
  /// keeps German, another language its own words, else English.
  String languageFor(String language) =>
      language == baseLanguage || _wordTerms.containsKey(language)
      ? language
      : 'en';

  /// public.classifier_terms: the German terms and every language's words
  /// that are concepts of their own, which public.dictionary_hit reads.
  late final List<CatalogTerm> classifierTerms = [
    ...terms.values,
    for (final w in words.values)
      if (w.own) (term: w.word, key: w.key, category: w.category),
  ];

  /// The forms of more than one word, which a name holds as a phrase.
  late final List<String> phraseForms = [
    for (final form in forms.keys)
      if (form.contains(' ')) form,
  ];

  /// This index with [delta]'s changes, under its version. A full delta
  /// replaces every row. The changes are from the bundled version, so they
  /// apply to [bundled] only. Its homographs, when it has them, replace
  /// these.
  CatalogIndex apply(CatalogDelta delta) {
    Map<String, T> next<T>(
      Map<String, T> rows,
      CatalogChanges<T> changes,
      String Function(T row) keyOf,
    ) => {if (!delta.full) ...rows}
      ..removeWhere((key, _) => changes.drop.contains(key))
      ..addAll({for (final row in changes.put) keyOf(row): row});
    return CatalogIndex._(
      delta.version,
      terms: next(terms, delta.terms, (row) => row.term),
      forms: next(forms, delta.forms, (row) => row.form),
      brands: next(brands, delta.brands, (row) => row.key),
      homographs: switch (delta.homographs) {
        final rows? => _byForm(rows),
        null => homographs,
      },
      words: switch (delta.words) {
        final changes? =>
          {if (!delta.full) ...words}
            ..removeWhere((key, _) => changes.drop.contains(key))
            ..addAll({
              for (final row in changes.put) _wordId(row.lang, row.word): row,
            }),
        null => words,
      },
    );
  }

  static Map<String, List<CatalogHomograph>> _byForm(
    List<(String, String, String, String, bool)> rows,
  ) {
    final byForm = <String, List<CatalogHomograph>>{};
    for (final (form, surface, canonical, category, synonym) in rows) {
      (byForm[form] ??= []).add((
        surface: surface,
        canonical: canonical,
        category: category,
        synonym: synonym,
      ));
    }
    return {
      for (final MapEntry(:key, :value) in byForm.entries)
        key: List.unmodifiable(value),
    };
  }

  static String _wordId(String lang, String word) => '$lang:$word';

  /// In the order of collate "C" (code points), as public.catalog_rows
  /// lists them.
  static Map<String, T> _sorted<T>(Map<String, T> rows) => Map.unmodifiable({
    for (final key in rows.keys.toList()..sort()) key: rows[key],
  });
}

/// What public.catalog_delta answered: the rows to put and the keys to drop
/// per table, from the version the device asked about to [version]. [full]:
/// the server had no snapshot of that version; the puts are every row.
/// [homographs] are every homograph row (form, surface, canonical,
/// category, synonym); null from a server that sends none. [words]: the
/// other languages' words, null from a server that sends none (the device
/// keeps its own then, also in a [full] answer).
@immutable
final class const CatalogDelta({
  required final String version,
  required final bool full,
  final CatalogChanges<CatalogTerm> terms = const CatalogChanges(),
  final CatalogChanges<CatalogForm> forms = const CatalogChanges(),
  final CatalogChanges<CatalogBrand> brands = const CatalogChanges(),
  final List<(String, String, String, String, bool)>? homographs,
  final CatalogChanges<CatalogWord>? words,
});

@immutable
final class const CatalogChanges<T>({
  final List<T> put = const [],
  final Set<String> drop = const {},
});

/// The most rows a table may have in a delta; the bundled tables have
/// about 1,700 each.
const _maxRows = 20000;

/// The longest text a row may hold; the tables' own checks allow 120.
const _maxText = 200;

final _version = RegExp(r'^[0-9a-f]{16}$');

/// public.catalog_delta's answer, or null when anything about it is off:
/// one bad row rejects it, and the device keeps what it has.
CatalogDelta? parseCatalogDelta(Object? json) {
  if (json case {'version': final String version, 'full': final bool full}
      when _version.hasMatch(version)) {
    final terms = _changes(json['terms'], full, _term);
    final forms = _changes(json['forms'], full, _form);
    final brands = _changes(json['brands'], full, _brand);
    final homographs = _homographs(json['homographs']);
    final words = json['words'] == null
        ? null
        : _changes(json['words'], full, _word);
    if (terms == null ||
        forms == null ||
        brands == null ||
        homographs == null ||
        (json['words'] != null && words == null)) {
      return null;
    }
    return CatalogDelta(
      version: version,
      full: full,
      terms: terms,
      forms: forms,
      brands: brands,
      homographs: homographs.rows,
      words: words,
    );
  }
  return null;
}

/// The answer's homograph rows (none from a server that sends none), or
/// null when any row is off.
({List<(String, String, String, String, bool)>? rows})? _homographs(
  Object? json,
) {
  if (json == null) {
    return (rows: null);
  }
  if (json case final List<Object?> rows when rows.length <= _maxRows) {
    final parsed = <(String, String, String, String, bool)>[];
    for (final row in rows) {
      if (row
          case [
            final String form,
            final String surface,
            final String canonical,
            final String category,
            final bool synonym,
          ]
          when _text(form) &&
              _text(surface) &&
              _text(canonical) &&
              _text(category)) {
        parsed.add((form, surface, canonical, category, synonym));
      } else {
        return null;
      }
    }
    return (rows: parsed);
  }
  return null;
}

/// A table's `{"put": [...], "drop": [...]}`; absent when nothing changed,
/// never absent in a full delta.
CatalogChanges<T>? _changes<T extends Record>(
  Object? json,
  bool full,
  T? Function(List<Object?> row) parse,
) {
  if (json == null && !full) {
    return CatalogChanges<T>();
  }
  if (json
      case {'put': final List<Object?> put, 'drop': final List<Object?> drop}
      when put.length <= _maxRows && drop.length <= _maxRows) {
    final rows = <T>[];
    for (final row in put) {
      if (row case final List<Object?> fields) {
        if (parse(fields) case final parsed?) {
          rows.add(parsed);
          continue;
        }
      }
      return null;
    }
    final keys = drop.whereType<String>().where(_text).toSet();
    return keys.length == drop.length
        ? CatalogChanges<T>(put: rows, drop: keys)
        : null;
  }
  return null;
}

bool _text(String? value) =>
    value != null && value.isNotEmpty && value.length <= _maxText;

CatalogTerm? _term(List<Object?> row) => switch (row) {
  [final String term, final String key, final String category]
      when _text(term) && _text(key) && _text(category) =>
    (term: term, key: key, category: category),
  _ => null,
};

CatalogForm? _form(List<Object?> row) => switch (row) {
  [
    final String form,
    final String canonical,
    final String category,
    final bool synonym,
  ]
      when _text(form) && _text(canonical) && _text(category) =>
    (form: form, canonical: canonical, category: category, synonym: synonym),
  _ => null,
};

CatalogBrand? _brand(List<Object?> row) => switch (row) {
  [
    final String key,
    final String brand,
    final String? product,
    final String? storeSeed,
  ]
      when _text(key) &&
          _text(brand) &&
          (product == null || _text(product)) &&
          (storeSeed == null || _text(storeSeed)) =>
    (key: key, brand: brand, product: product, storeSeed: storeSeed),
  _ => null,
};

final _language = RegExp(r'^[a-z]{2}$');

/// A row of `words`: `[lang:word, key, category, own]`, the first element
/// being the key public.catalog_changes drops it by.
CatalogWord? _word(List<Object?> row) => switch (row) {
  [final String id, final String key, final String category, final bool own]
      when _text(id) &&
          _text(key) &&
          _text(category) &&
          _language.hasMatch(id.split(':').first) &&
          id.indexOf(':') == 2 &&
          id.length > 3 =>
    (
      lang: id.substring(0, 2),
      word: id.substring(3),
      key: key,
      category: category,
      own: own,
    ),
  _ => null,
};

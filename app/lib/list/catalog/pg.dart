import 'dart:math' as math;
import 'dart:typed_data';

/// The Postgres built-ins the ranking port (job 274) leans on, as the
/// database computes them: pg_trgm, fuzzystrmatch, the ICU collation text
/// sorts in, and a few text functions.

/// The trigrams pg_trgm's `similarity` compares: each word (a run of
/// letters and digits) lower-cased, padded with two spaces in front and
/// one behind, cut into its three-character runs.
Set<String> trigrams(String text) {
  final grams = <String>{};
  for (final word in _word.allMatches(text.toLowerCase())) {
    final padded = '  ${word[0]} ';
    for (var i = 0; i + 3 <= padded.length; i++) {
      grams.add(padded.substring(i, i + 3));
    }
  }
  return grams;
}

final _word = RegExp(r'[\p{L}\p{N}]+', unicode: true);

/// `extensions.similarity` over two [trigrams] sets: the shared trigrams
/// over all distinct ones, 0 when either has none.
double similarity(Set<String> a, Set<String> b) {
  if (a.isEmpty || b.isEmpty) {
    return 0;
  }
  final (small, large) = a.length <= b.length ? (a, b) : (b, a);
  var shared = 0;
  for (final gram in small) {
    if (large.contains(gram)) {
      shared++;
    }
  }
  return shared / (a.length + b.length - shared);
}

/// Whether `extensions.levenshtein_less_equal(a, b, max) <= max`: at most
/// [max] insertions, deletions or substitutions turn [a] into [b].
bool withinEdits(String a, String b, int max) {
  if ((a.length - b.length).abs() > max) {
    return false;
  }
  var previous = Int32List(b.length + 1);
  var current = Int32List(b.length + 1);
  for (var j = 0; j <= b.length; j++) {
    previous[j] = j;
  }
  for (var i = 1; i <= a.length; i++) {
    current[0] = i;
    var best = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      current[j] = math.min(
        math.min(previous[j] + 1, current[j - 1] + 1),
        previous[j - 1] + cost,
      );
      best = math.min(best, current[j]);
    }
    if (best > max) {
      return false;
    }
    (previous, current) = (current, previous);
  }
  return previous[b.length] <= max;
}

/// `cap_text(text, max)`: [text] cut to [max] characters at its last
/// space, without the trailing spaces and commas; at [max] when a single
/// word is longer.
String? capText(String? text, int max) {
  if (text == null) {
    return null;
  }
  final chars = text.runes.toList();
  if (chars.length <= max) {
    return text;
  }
  final head = String.fromCharCodes(chars.take(max + 1));
  final space = head.lastIndexOf(' ');
  if (head.indexOf(' ') > 0) {
    return head.substring(0, space).replaceFirst(RegExp(r'[ ,]+$'), '');
  }
  return String.fromCharCodes(chars.take(max));
}

/// `initcap` for a dictionary term (lower-case letters and spaces): each
/// word with a capital.
String initcap(String term) =>
    term.replaceAllMapped(RegExp(r'[\p{L}\p{N}]+', unicode: true), (m) {
      final word = m[0]!;
      final first = word.substring(0, 1);
      return '${first == 'ß' ? 'Ss' : first.toUpperCase()}'
          '${word.substring(1).toLowerCase()}';
    });

/// Text in the database's sort order, ICU's root collation (en-US): first
/// by base characters (spaces, then punctuation, then digits, then letters
/// whatever their accents or case), then by accents, then lower before
/// upper case, then by code point. Null after text, as `order by` puts it.
int collate(String? a, String? b) {
  if (a == null || b == null) {
    return a == null ? (b == null ? 0 : 1) : -1;
  }
  if (a == b) {
    return 0;
  }
  final x = _collationKey(a);
  final y = _collationKey(b);
  for (final level in [0, 1, 2]) {
    final c = _compareLists(x[level], y[level]);
    if (c != 0) {
      return c;
    }
  }
  return a.compareTo(b);
}

int _compareLists(List<int> a, List<int> b) {
  for (var i = 0; i < a.length && i < b.length; i++) {
    if (a[i] != b[i]) {
      return a[i].compareTo(b[i]);
    }
  }
  return a.length.compareTo(b.length);
}

/// ICU root's order of the ASCII characters that are no letters or
/// digits, as `order by` on the local stack sorts them.
const _punctuation = r''' _-,;:!?.'"()[]{}@*/\&#%`^+<=>|~$''';

/// Accented Latin letters: their base letters and an accent weight.
const _accents = {
  'à': ('a', 2), 'á': ('a', 1), 'â': ('a', 3), 'ã': ('a', 6), //
  'ä': ('a', 5), 'å': ('a', 4), 'ç': ('c', 7), 'è': ('e', 2), //
  'é': ('e', 1), 'ê': ('e', 3), 'ë': ('e', 5), 'ì': ('i', 2), //
  'í': ('i', 1), 'î': ('i', 3), 'ï': ('i', 5), 'ñ': ('n', 6), //
  'ò': ('o', 2), 'ó': ('o', 1), 'ô': ('o', 3), 'õ': ('o', 6), //
  'ö': ('o', 5), 'ù': ('u', 2), 'ú': ('u', 1), 'û': ('u', 3), //
  'ü': ('u', 5), 'ý': ('y', 1), 'ÿ': ('y', 5),
};

/// Primary weights: punctuation, digits, letters, then anything else.
const _digitBase = 100;
const _letterBase = 200;
const _otherBase = 1000;

List<List<int>> _collationKey(String text) {
  final primary = <int>[];
  final secondary = <int>[];
  final tertiary = <int>[];
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    final lower = char.toLowerCase();
    final upper = lower != char ? 1 : 0;
    if (lower == 'ß') {
      primary.addAll([_letterBase + 18, _letterBase + 18]);
      secondary.addAll([0, 0]);
      tertiary.addAll([2, 2]);
      continue;
    }
    final (base, accent) = _accents[lower] ?? (lower, 0);
    final unit = base.codeUnitAt(0);
    final int weight;
    if (base.length == 1 && unit >= 0x61 && unit <= 0x7a) {
      weight = _letterBase + unit - 0x61;
    } else if (base.length == 1 && unit >= 0x30 && unit <= 0x39) {
      weight = _digitBase + unit - 0x30;
    } else if (_punctuation.indexOf(base) case final at when at >= 0) {
      weight = at + 1;
    } else {
      weight = _otherBase + rune;
    }
    primary.add(weight);
    secondary.add(accent);
    tertiary.add(upper);
  }
  return [primary, secondary, tertiary];
}

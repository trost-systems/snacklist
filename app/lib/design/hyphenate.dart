/// The soft hyphen: a line may break after it, and only then shows a „-“.
const softHyphen = '­';

const _vowels = 'aeiouyäöü';

/// Letter groups that count as one consonant: they stay together at a
/// break („Bü-cher“, „Zu-cker“, „Ta-sche“).
const _units = ['sch', 'ch', 'ck', 'ph', 'th', 'sh', 'qu'];

/// Consonant pairs that start a syllable together, so a break goes before
/// both („Ab-bre-chen“, „er-klä-ren“).
const _onsets = {
  'bl', 'br', 'dr', 'fl', 'fr', 'gl', 'gr', 'kl', 'kr', 'pl', 'pr', 'tr', //
  'schl', 'schm', 'schn', 'schr', 'schw',
};

/// The app's own long words whose compound seam the rule below misses
/// („Schut-zer“, „Erin-ne“), split as the Duden does.
const _exceptions = {
  'datenschutzerklärung': 'da-ten-schutz-er-klä-rung',
  'erinnerungen': 'er-in-ne-run-gen',
  'erinnerung': 'er-in-ne-rung',
  'einkaufserinnerungen': 'ein-kaufs-er-in-ne-run-gen',
  'einkaufserinnerung': 'ein-kaufs-er-in-ne-rung',
};

/// [word] with a [softHyphen] at each syllable break a German or English
/// reader expects: one consonant goes to the next syllable („Be-nach“),
/// of several only the last one or a pair from [_onsets] („nach-rich“,
/// „Ab-bre“), vowels next to each other stay together. At least two
/// letters on either side of a break. A rule of thumb, not a dictionary:
/// a compound's own seam can come out one letter off, so the app's own
/// long words that hit that are in [_exceptions].
String hyphenate(String word) {
  final lower = word.toLowerCase();
  // A letter whose lower case is longer („İ“) would shift every index.
  if (lower.length != word.length) {
    return word;
  }
  if (_exceptions[lower] case final split?) {
    final buffer = StringBuffer();
    var at = 0;
    for (final part in split.split('-')) {
      if (at > 0) {
        buffer.write(softHyphen);
      }
      buffer.write(word.substring(at, at + part.length));
      at += part.length;
    }
    return buffer.toString();
  }
  // Each unit's start in [word], and whether it is a vowel run.
  final starts = <int>[];
  final vowel = <bool>[];
  for (var i = 0; i < lower.length;) {
    final isVowel = _vowels.contains(lower[i]);
    final unit = isVowel
        ? 1
        : _units
              .firstWhere((u) => lower.startsWith(u, i), orElse: () => lower[i])
              .length;
    if (isVowel && vowel.isNotEmpty && vowel.last) {
      i += unit;
      continue;
    }
    starts.add(i);
    vowel.add(isVowel);
    i += unit;
  }
  final isLetter = RegExp(r'^\p{L}+$', unicode: true).hasMatch;
  final breaks = <int>[];
  int? lastNucleus;
  for (var u = 0; u < starts.length; u++) {
    if (!vowel[u]) {
      continue;
    }
    if (lastNucleus case final from? when u - from > 1) {
      final consonants = u - from - 1;
      var at = u - 1;
      if (consonants >= 2 &&
          _onsets.contains(lower.substring(starts[u - 2], starts[u]))) {
        at = u - 2;
      }
      breaks.add(starts[at]);
    }
    lastNucleus = u;
  }
  final buffer = StringBuffer();
  var from = 0;
  for (final at in breaks) {
    if (at >= 2 &&
        word.length - at >= 2 &&
        isLetter(word.substring(at - 2, at + 2))) {
      buffer
        ..write(word.substring(from, at))
        ..write(softHyphen);
      from = at;
    }
  }
  return (buffer..write(word.substring(from))).toString();
}

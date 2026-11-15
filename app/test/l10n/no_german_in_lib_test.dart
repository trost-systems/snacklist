import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files whose German literals are data the app matches user input
/// against, never shown as UI text.
const germanDataFiles = {
  'lib/list/entry.dart': 'item parsing: amounts, sizes, umlaut folding',
  'lib/list/number_words.dart': 'item parsing: German number and unit words',
  'lib/list/quantity.dart': 'quantity merge: German unit words',
  'lib/list/pricing.dart': 'price parsing: unit words',
  'lib/list/model.dart': 'umlaut folding for the dedupe key',
};

/// Single German literals outside [germanDataFiles], each with its reason.
const germanLiterals = {
  ('lib/design/section_label.dart', "'ß'"): 'upper-casing rule for ß',
  ('lib/list/list_view/dividers.dart', "'ß'"): 'upper-casing rule for ß',
  ('lib/household/popular_stores.dart', "'Aldi Süd'"): 'a store name',
  ('lib/settings/delete_account_dialog.dart', "'löschen'"):
      'accepted confirmation word, matched against input',
  ('lib/siri/siri_phrases.dart', "'Etwas auf Snacklist setzen'"):
      "Siri's German phrase, shown when Siri listens in German",
  ('lib/siri/siri_phrases.dart', "'Snacklist, füge etwas hinzu'"):
      "Siri's German phrase, shown when Siri listens in German",
  ('lib/siri/siri_phrases.dart', "'Füge <Eintrag> zu Snacklist hinzu'"):
      "Siri's German phrase, shown when Siri listens in German",
};

final _literal = RegExp(
  r"r?'(?:[^'\\\n]|\\.)*'"
  r'|r?"(?:[^"\\\n]|\\.)*"',
);

/// Umlauts, ß and common German words that rarely appear in English: a
/// heuristic next to the no-hardcoded-ui-text lint, which catches UI text
/// in widgets but not text passed around in variables.
final _german = RegExp(
  r'[äöüÄÖÜß]|\b(?:und|oder|nicht|keine?|[Bb]itte|Liste|Einkaufsliste|'
  'Haushalt|Fehler|Abbrechen|Speichern|Einladung|Mitglieder?|[Dd]eine?|'
  'wird|ist|sind|einen?|mit|auf|noch|jetzt|hier|Laden|Ladens|Artikel|Eintrag|'
  'Konto|Anmelden|Abmelden|'
  r'Einträge|Einstellungen|Mehr|Zurück|Weiter|Fertig)\b',
);

/// German string literals in [source], skipping comment lines.
Iterable<String> germanLiteralsIn(String source) sync* {
  for (final line in source.split('\n')) {
    if (line.trimLeft().startsWith('//')) {
      continue;
    }
    for (final match in _literal.allMatches(line)) {
      final literal = match.group(0)!;
      if (_german.hasMatch(literal)) {
        yield literal;
      }
    }
  }
}

void main() {
  test('the scan finds German literals and skips comments', () {
    expect(
      germanLiteralsIn('''
// Einkaufsliste in a comment
Text('Zurück zur Liste'),
label: "Bitte warten",
tooltip: 'Back to the list',
'''),
      ["'Zurück zur Liste'", '"Bitte warten"'],
    );
  });

  test('UI text in lib/ goes through the ARB files, not German literals', () {
    final found = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => !file.path.startsWith('lib/l10n/'));
    for (final file in files) {
      final path = file.path;
      if (germanDataFiles.containsKey(path)) {
        continue;
      }
      for (final literal in germanLiteralsIn(file.readAsStringSync())) {
        if (!germanLiterals.containsKey((path, literal))) {
          found.add('$path: $literal');
        }
      }
    }
    expect(
      found,
      isEmpty,
      reason:
          'Move UI text into app/l10n/app_de.arb and app_en.arb. Data the '
          'app matches input against goes into germanLiterals or '
          'germanDataFiles with its reason.',
    );
  });

  test('every allow-list entry still exists', () {
    for (final path in germanDataFiles.keys) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
    for (final (path, literal) in germanLiterals.keys) {
      expect(
        germanLiteralsIn(File(path).readAsStringSync()),
        contains(literal),
        reason: '$path no longer has $literal: drop the entry',
      );
    }
  });
}

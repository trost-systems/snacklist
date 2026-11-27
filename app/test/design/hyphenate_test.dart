import 'package:family_groceries/design/hyphenate.dart';
import 'package:family_groceries/design/word_wrap.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('syllable breaks in the long words of More and SR1', () {
    for (final (word, expected) in [
      ('Benachrichtigungen', 'Be-nach-rich-ti-gun-gen'),
      ('Datenschutzerklärung', 'Da-ten-schutz-er-klä-rung'),
      ('Nutzungsbedingungen', 'Nut-zungs-be-din-gun-gen'),
      ('Erinnerungen', 'Er-in-ne-run-gen'),
      ('EINKAUFSERINNERUNGEN', 'EIN-KAUFS-ER-IN-NE-RUN-GEN'),
      ('Einkaufstag', 'Ein-kaufs-tag'),
      ('Abbrechen', 'Ab-bre-chen'),
      ('Speichern', 'Spei-chern'),
      ('Zucker', 'Zu-cker'),
      ('Notifications', 'No-ti-fi-ca-tions'),
      ('Reminders', 'Re-min-ders'),
    ]) {
      expect(hyphenate(word).replaceAll(softHyphen, '-'), expected);
    }
  });

  test('removing the soft hyphens gives the word back', () {
    for (final word in ['Benachrichtigungen', 'Ärger', 'x', '', 'E-Mail']) {
      expect(hyphenate(word).replaceAll(softHyphen, ''), word);
    }
  });

  test('no break next to a non-letter or with one letter alone', () {
    expect(hyphenate('E-Mail'), 'E-Mail');
    expect(hyphenate('„Ab“'), '„Ab“');
    expect(hyphenate('Abend'), 'Abend');
    expect(hyphenate('&'), '&');
  });

  testWidgets('a word too wide for its line gets a real „-“ and a break', (
    tester,
  ) async {
    const style = TextStyle(fontSize: 20);
    double width(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      addTearDown(painter.dispose);
      return painter.width;
    }

    const text = 'Benachrichtigungen & Erinnerungen';
    final room = width('Benachrichti-') + 2;
    final shown = hyphenateToFit(
      text,
      style,
      TextScaler.noScaling,
      room,
      TextDirection.ltr,
    );
    expect(shown, isNot(contains(softHyphen)));
    expect(shown.replaceAll('-\n', ''), text);
    for (final line in shown.split('\n')) {
      if (line.endsWith('-')) {
        expect(width(line), lessThanOrEqualTo(room), reason: line);
      }
    }
    expect(shown, startsWith('Benachrichti-\n'));
    expect(
      hyphenateToFit(
        'kurz und gut',
        style,
        TextScaler.noScaling,
        room,
        TextDirection.ltr,
      ),
      'kurz und gut',
    );
    expect(
      hyphenateToFit(
        'in Datenschutzerklärung',
        style,
        TextScaler.noScaling,
        width('Datenschutz-') + 2,
        TextDirection.ltr,
      ),
      'in\nDatenschutz-\nerklärung',
    );
  });
}

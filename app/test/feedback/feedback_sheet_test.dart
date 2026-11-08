import 'dart:async';

import 'package:family_groceries/app/language.dart';
import 'package:family_groceries/design/hex_checkbox.dart';
import 'package:family_groceries/feedback/feedback_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../more/more_harness.dart';

void main() {
  setUpAll(fakeSupabase);

  Finder key(String k) => find.byKey(ValueKey(k));

  Future<void> tapKey(WidgetTester tester, String k) async {
    await tester.ensureVisible(key(k));
    await tester.pumpAndSettle();
    await tester.tap(key(k));
    await tester.pumpAndSettle();
  }

  /// More, after the list: the tracker has seen `/` and then `/more`.
  Future<More> openForm(
    WidgetTester tester, {
    AppLanguage? language,
    Size size = const Size(390, 844),
  }) async {
    final more = await pumpMore(tester, language: language, size: size);
    more.screens
      ..visit(Uri.parse('/'))
      ..visit(Uri.parse('/more'));
    // The row may sit below what the list has built yet.
    await tester.scrollUntilVisible(
      key('more-feedback'),
      200,
      scrollable: find.descendant(
        of: key('more-screen'),
        matching: find.byType(Scrollable),
      ),
    );
    await tapKey(tester, 'more-feedback');
    expect(key('feedback-sheet'), findsOneWidget);
    return more;
  }

  bool enabled(WidgetTester tester, String k) =>
      tester.widget<FilledButton>(key(k)).onPressed != null;

  testWidgets('German: the row, the form and its strings (AC1, AC10)', (
    tester,
  ) async {
    await pumpMore(tester);
    expect(find.text('Feedback senden'), findsOneWidget);
    await tapKey(tester, 'more-feedback');
    for (final text in [
      'Deine Nachricht',
      'Bug',
      'Idee',
      'Sonstiges',
      'Peter darf mich dazu kontaktieren',
      'Senden',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(
      find.textContaining(
        'App-Version, Gerät, Sprache und aktueller Bildschirm. '
        'Keine Listeneinträge.',
      ),
      findsOneWidget,
    );
    expect(enabled(tester, 'feedback-send'), isFalse, reason: 'nothing typed');
    final contact = tester.widget<HexCheckboxListTile>(key('feedback-contact'));
    expect(contact.value, isFalse, reason: 'off by default');
    for (final c in ['bug', 'idea', 'other']) {
      expect(
        tester.widget<ChoiceChip>(key('feedback-category-$c')).selected,
        isFalse,
        reason: 'no category by default',
      );
    }
  });

  testWidgets('English: the row, the form, the error and the thanks (AC10)', (
    tester,
  ) async {
    final more = await openForm(tester, language: AppLanguage.en);
    for (final text in [
      'Send feedback',
      'Your message',
      'Bug',
      'Idea',
      'Other',
      'Peter may contact me about this',
      'Send',
    ]) {
      expect(find.text(text), findsWidgets, reason: text);
    }
    expect(
      find.textContaining(
        'App version, device, language and current screen. No list items.',
      ),
      findsOneWidget,
    );
    more.feedback.failNext = 1;
    await tester.enterText(key('feedback-message'), 'Offline note');
    await tester.pump();
    await tapKey(tester, 'feedback-send');
    expect(
      find.text('Not sent. Check your connection and try again.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    await tapKey(tester, 'feedback-retry');
    expect(find.text('Thanks!'), findsOneWidget);
    expect(more.feedback.rows.values.single.context.locale, 'en');
  });

  testWidgets('a note with only text: one row with every context field, the '
      'form closes, "Danke!" (AC2, AC3)', (tester) async {
    final more = await openForm(tester);
    await tester.enterText(key('feedback-message'), '  Der Haken hängt.  ');
    await tester.pump();
    await tapKey(tester, 'feedback-send');
    expect(key('feedback-sheet'), findsNothing);
    expect(find.text('Danke!'), findsOneWidget);
    final row = more.feedback.rows.values.single;
    expect(row.message, 'Der Haken hängt.');
    expect(row.category, isNull);
    expect(row.contactOk, isFalse);
    final context = row.context;
    expect(
      [
        context.appVersion,
        context.build,
        context.platform,
        context.osVersion,
        context.locale,
        context.screen,
      ],
      ['1.2.3', '45', 'android', 'Android 14 (SDK 34)', 'de', 'list'],
    );
  });

  testWidgets('category and contact go along', (tester) async {
    final more = await openForm(tester);
    await tester.enterText(key('feedback-message'), 'Idee');
    await tapKey(tester, 'feedback-category-idea');
    await tapKey(tester, 'feedback-contact');
    await tapKey(tester, 'feedback-send');
    final row = more.feedback.rows.values.single;
    expect(row.category, FeedbackCategory.idea);
    expect(row.contactOk, isTrue);
  });

  testWidgets('a double tap on Send sends once', (tester) async {
    final more = await openForm(tester);
    final hold = more.feedback.hold = Completer();
    await tester.enterText(key('feedback-message'), 'Doppelt');
    await tester.pump();
    await tester.tap(key('feedback-send'));
    await tester.tap(key('feedback-send'), warnIfMissed: false);
    await tester.pump();
    expect(find.bySemanticsLabel('Wird gesendet …'), findsOneWidget);
    hold.complete();
    await tester.pumpAndSettle();
    expect(more.feedback.calls, hasLength(1));
    expect(more.feedback.rows, hasLength(1));
  });

  testWidgets('empty and blank are not sendable; over 2000 shows why (AC4)', (
    tester,
  ) async {
    await openForm(tester);
    await tester.enterText(key('feedback-message'), '    \n  ');
    await tester.pump();
    expect(enabled(tester, 'feedback-send'), isFalse);
    expect(key('feedback-counter'), findsNothing);
    await tester.enterText(key('feedback-message'), 'a' * 1799);
    await tester.pump();
    expect(key('feedback-counter'), findsNothing, reason: 'far from the limit');
    await tester.enterText(key('feedback-message'), 'a' * 1950);
    await tester.pump();
    expect(find.text('1950 / 2000'), findsOneWidget);
    expect(enabled(tester, 'feedback-send'), isTrue);
    await tester.enterText(key('feedback-message'), 'a' * 2001);
    await tester.pump();
    expect(find.text('2001 / 2000'), findsOneWidget);
    expect(find.text('Höchstens 2000 Zeichen'), findsOneWidget);
    expect(enabled(tester, 'feedback-send'), isFalse);
    await tester.enterText(key('feedback-message'), '${'a' * 2000}   ');
    await tester.pump();
    expect(enabled(tester, 'feedback-send'), isTrue, reason: 'trimmed: 2000');
  });

  // On the web a new semantics node for the field means a new input
  // element, which dropped the typed text when the limit error appeared.
  testWidgets('the too-long error keeps the field and its text, and is the '
      "field's hint", (tester) async {
    final semantics = tester.ensureSemantics();
    await openForm(tester);
    final field = find.descendant(
      of: key('feedback-message'),
      matching: find.byType(EditableText),
    );
    await tester.enterText(key('feedback-message'), 'a' * 1999);
    await tester.pump();
    final before = tester.getSemantics(field).id;
    await tester.enterText(key('feedback-message'), 'a' * 2001);
    await tester.pump();
    final node = tester.getSemantics(field);
    expect(node.id, before);
    expect(node.getSemanticsData().hint, 'Höchstens 2000 Zeichen');
    expect(node.getSemanticsData().value, 'a' * 2001);
    semantics.dispose();
  });

  testWidgets('offline: the error, the note stays, Retry sends it once '
      '(AC7)', (tester) async {
    final more = await openForm(tester);
    more.feedback.failNext = 1;
    await tester.enterText(key('feedback-message'), 'Im Funkloch');
    await tapKey(tester, 'feedback-category-bug');
    await tapKey(tester, 'feedback-contact');
    await tapKey(tester, 'feedback-send');
    expect(
      find.text(
        'Nicht gesendet. Prüfe die Verbindung und versuch es noch einmal.',
      ),
      findsOneWidget,
    );
    expect(find.text('Im Funkloch'), findsOneWidget);
    expect(
      tester.widget<ChoiceChip>(key('feedback-category-bug')).selected,
      isTrue,
    );
    expect(
      tester.widget<HexCheckboxListTile>(key('feedback-contact')).value,
      isTrue,
    );
    expect(key('feedback-send'), findsNothing);
    expect(more.feedback.rows, isEmpty);
    await tapKey(tester, 'feedback-retry');
    expect(key('feedback-sheet'), findsNothing);
    expect(more.feedback.rows, hasLength(1));
    expect(more.feedback.calls.map((c) => c.id).toSet(), hasLength(1));
  });

  testWidgets('closed after a failure, the note is still there', (
    tester,
  ) async {
    final more = await openForm(tester);
    more.feedback.failNext = 1;
    await tester.enterText(key('feedback-message'), 'Nicht verlieren');
    await tapKey(tester, 'feedback-send');
    await tapKey(tester, 'feedback-close');
    expect(key('feedback-sheet'), findsNothing);
    await tapKey(tester, 'more-feedback');
    expect(find.text('Nicht verlieren'), findsOneWidget);
    expect(key('feedback-retry'), findsOneWidget);
  });

  testWidgets('wide: the form is at most 640 px wide', (tester) async {
    await openForm(tester, size: const Size(1366, 1024));
    expect(tester.getSize(key('feedback-sheet')).width, lessThanOrEqualTo(640));
  });
}

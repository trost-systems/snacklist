// Job 472 (Peter, 26 Nov 2026): More's row and the page title
// „Benachrichtigungen & Erinnerungen“ / "Notifications & Reminders" wrap
// cleanly onto more lines at large text, never cut, never shrunk, and
// broken inside a word only at a syllable with a hyphen, at 390×844 and
// 100 %, 140 % and 200 % text, light and dark, German and English. The same
// holds for every More row. Then SR1 itself.
//   flutter test --update-goldens test/design/notifications_label_golden_test.dart
import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/design/hex_radio.dart';
import 'package:family_groceries/design/hyphenate.dart';
import 'package:family_groceries/push/household_add_alert.dart';
import 'package:family_groceries/settings/shopping_reminders.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../more/more_harness.dart';
import '../push/household_add_alert_test.dart' show FakePrefs;
import '../settings/shopping_reminders_test.dart';
import 'fonts.dart';

/// Every line break of [finder]'s text falls between two words or after a
/// hyphenated word's own „-“ and line break; no soft hyphen is left for
/// the engine (the web engine would break there without a „-“).
void expectWordBreaks(WidgetTester tester, Finder finder) {
  for (final paragraph in tester.renderObjectList<RenderParagraph>(
    find.descendant(of: finder, matching: find.byType(RichText)),
  )) {
    final text = paragraph.text.toPlainText();
    expect(text, isNot(contains(softHyphen)), reason: '"$text"');
    final painter = TextPainter(
      text: paragraph.text,
      textDirection: paragraph.textDirection,
      textScaler: paragraph.textScaler,
      maxLines: paragraph.maxLines,
      textWidthBasis: paragraph.textWidthBasis,
    )..layout(maxWidth: paragraph.constraints.maxWidth);
    addTearDown(painter.dispose);
    final lines = painter.getLineBoundary;
    var offset = 0;
    while (offset < text.length) {
      final line = lines(TextPosition(offset: offset));
      if (line.end <= offset) {
        break;
      }
      if (line.end < text.length) {
        expect(
          text[line.end - 1] == ' ' ||
              text[line.end - 1] == '\n' ||
              text[line.end] == '\n' ||
              text[line.end] == ' ',
          isTrue,
          reason: '"$text" breaks inside a word at ${line.end}',
        );
      }
      offset = line.end;
    }
    expect(paragraph.didExceedMaxLines, isFalse, reason: '"$text" is cut');
  }
}

/// Every text in [finder] but icons renders at [scale], the text scale
/// asked for: neither its text scaler nor a transform above it shrinks it.
void expectFullScale(WidgetTester tester, Finder finder, double scale) {
  final icons = find
      .descendant(of: find.byType(Icon), matching: find.byType(RichText))
      .evaluate()
      .toSet();
  for (final element
      in find
          .descendant(of: finder, matching: find.byType(RichText))
          .evaluate()) {
    if (icons.contains(element)) {
      continue;
    }
    final paragraph = element.renderObject! as RenderParagraph;
    final text = paragraph.text.toPlainText();
    expect(
      paragraph.textScaler.scale(10) / 10,
      closeTo(scale, 0.001),
      reason: '"$text" has its own text scale',
    );
    final drawn = MatrixUtils.transformRect(
      paragraph.getTransformTo(null),
      Offset.zero & paragraph.size,
    );
    expect(
      drawn.height / paragraph.size.height,
      closeTo(1, 0.001),
      reason: '"$text" is scaled by a transform',
    );
  }
}

void main() {
  setUpAll(loadAppFonts);

  for (final scale in [1.0, 1.4, 2.0]) {
    for (final language in ['de', 'en']) {
      for (final mode in ['light', 'dark']) {
        final name = '$language-${(scale * 100).round()}-$mode';
        testWidgets('the row and the page title, $name', (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final alert = HouseholdAddAlert(null, FakePrefs());
          addTearDown(alert.close);
          await pumpMore(
            tester,
            theme: ThemeMode.values.byName(mode),
            device: [Locale(language)],
            flags: const {pushHouseholdAddFlag},
            householdAdd: alert,
          );
          final row = find.byKey(const ValueKey('more-notifications'));
          await tester.scrollUntilVisible(row, 200);
          await tester.pumpAndSettle();
          for (final key in [
            'more-notifications',
            'more-privacy-policy',
            'more-terms',
            'more-settings',
          ]) {
            final found = find.byKey(ValueKey(key));
            if (found.evaluate().isNotEmpty) {
              expectWordBreaks(tester, found);
              expectFullScale(tester, found, scale);
            }
          }
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/notifications-label-row-$name.png'),
          );
          await tester.tap(row);
          await tester.pumpAndSettle();
          expectWordBreaks(tester, find.byType(AppBar));
          final title = tester.getRect(
            find
                .descendant(
                  of: find.byType(AppBar),
                  matching: find.byType(RichText),
                )
                .last,
          );
          final bar = tester.getRect(find.byType(AppBar));
          expect(bar.contains(title.topLeft), isTrue);
          expect(title.bottom, lessThanOrEqualTo(bar.bottom));
          expect(title.right, lessThanOrEqualTo(bar.right));
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/notifications-label-page-$name.png'),
          );
        });
      }
    }
  }

  for (final language in ['de', 'en']) {
    testWidgets('Einstellungen at 200 %, $language', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpMore(
        tester,
        location: appSettingsPath,
        device: [Locale(language)],
      );
      final screen = find.byKey(const ValueKey('settings-screen'));
      expectWordBreaks(tester, screen);
      expectFullScale(tester, screen, 2);
      expect(find.byType(HexRadioTile<ThemeMode>), findsNWidgets(3));
    });
  }

  // SR1 with three reminders across days, two on Saturday.
  for (final (scale, language, mode) in [
    for (final scale in [1.0, 1.4, 2.0])
      for (final language in ['de', 'en']) (scale, language, 'light'),
    (1.0, 'de', 'dark'),
  ]) {
    final name = '$language-${(scale * 100).round()}-$mode';
    testWidgets('SR1, $name', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final alert = HouseholdAddAlert(null, FakePrefs());
      addTearDown(alert.close);
      await pumpMore(
        tester,
        location: notificationsPath,
        theme: ThemeMode.values.byName(mode),
        device: [Locale(language)],
        flags: const {pushHouseholdAddFlag, shoppingRemindersFlag},
        householdAdd: alert,
        shoppingReminders: FakeReminderPush().service(
          FakeRemindersServer(
            initial: [
              slot(2, before, 18),
              slot(6, before, 20),
              slot(6, onDay, 9, 15),
            ],
          ),
        ),
      );
      final section = find.byKey(const ValueKey('shopping-reminders'));
      await tester.scrollUntilVisible(section, 200);
      await tester.pumpAndSettle();
      expectWordBreaks(tester, section);
      expectFullScale(tester, section, scale);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/sr1-list-$name.png'),
      );
      await tester.ensureVisible(find.byKey(const ValueKey('reminder-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reminder-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reminder-day-6')));
      await tester.pumpAndSettle();
      final sheet = find.byKey(const ValueKey('reminder-sheet'));
      expectWordBreaks(tester, sheet);
      expectFullScale(tester, sheet, scale);
      // „Am Tag davor“ / „Am Einkaufstag“: one track at 100 %, stacked
      // rows at 200 % (at 140 % they no longer fit one track either).
      final stacked = find.descendant(
        of: find.byKey(const ValueKey('reminder-offset')),
        matching: find.byType(HexRadioTile<ReminderOffset>),
      );
      if (scale == 1) {
        expect(stacked, findsNothing);
      } else if (scale == 2) {
        expect(stacked, findsNWidgets(2));
      }
      ReminderOffset picked() => tester
          .widget<RadioGroup<ReminderOffset>>(
            find.byType(RadioGroup<ReminderOffset>),
          )
          .groupValue!;
      await tester.tap(find.byKey(const ValueKey('reminder-on-the-day')));
      await tester.pumpAndSettle();
      expect(picked(), ReminderOffset.onTheDay);
      await tester.tap(find.byKey(const ValueKey('reminder-day-before')));
      await tester.pumpAndSettle();
      expect(picked(), ReminderOffset.dayBefore);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/sr1-sheet-$name.png'),
      );
      await tester.tap(find.byKey(const ValueKey('reminder-cancel')));
      await tester.pumpAndSettle();
      final saturday = find.byKey(
        ValueKey('reminder-${slot(6, onDay, 9, 15)}'),
      );
      await tester.ensureVisible(saturday);
      await tester.pumpAndSettle();
      await tester.tap(saturday);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reminder-delete')), findsOneWidget);
      expectWordBreaks(tester, find.byKey(const ValueKey('reminder-sheet')));
    });
  }

  testWidgets('SR1 empty, de-light', (tester) async {
    final alert = HouseholdAddAlert(null, FakePrefs());
    addTearDown(alert.close);
    await pumpMore(
      tester,
      location: notificationsPath,
      theme: ThemeMode.light,
      flags: const {pushHouseholdAddFlag, shoppingRemindersFlag},
      householdAdd: alert,
      shoppingReminders: FakeReminderPush().service(FakeRemindersServer()),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/sr1-empty-de-light.png'),
    );
  });
}

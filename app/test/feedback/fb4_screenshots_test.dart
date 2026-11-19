// Job 268: review screenshots of Feedback & ideas (flag feedback-fb4) on a
// phone: the hub, the form opened from it, a note with a reply and its
// "Fixed in" link, and an idea with the household's +1, each in German
// light, English dark and German at 130 % text. Skipped unless
// SCREENSHOT_DIR is set:
//   SCREENSHOT_DIR=$PWD/../docs/screenshots/268 TZ=UTC flutter test \
//     --update-goldens test/feedback/fb4_screenshots_test.dart
import 'dart:io';

import 'package:family_groceries/core/language.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../design/fonts.dart';
import '../more/more_harness.dart';
import 'fb2_harness.dart' show key, tapKey;
import 'fb4_harness.dart';

final _dir = Platform.environment['SCREENSHOT_DIR'];

void main() {
  setUpAll(() async {
    await fakeSupabase();
    if (_dir != null) {
      await loadAppFonts();
      WidgetsApp.debugAllowBannerOverride = false;
    }
  });

  for (final (name, language, theme, scale) in [
    ('de-light', AppLanguage.de, ThemeMode.light, 1.0),
    ('en-dark', AppLanguage.en, ThemeMode.dark, 1.0),
    ('de-130', AppLanguage.de, ThemeMode.light, 1.3),
  ]) {
    Future<More> open(WidgetTester tester, String location) async {
      final more = await pumpMore(
        tester,
        location: location,
        flags: fb4,
        language: language,
        theme: theme,
        feedback: fb4Server(english: language == AppLanguage.en),
      );
      tester.view
        ..devicePixelRatio = 2
        ..physicalSize = const Size(390, 844) * 2;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      return more;
    }

    Future<void> shot(String what) => expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('$_dir/$what-$name.png'),
    );

    testWidgets(
      'the More row with its badge, the hub, $name',
      skip: _dir == null,
      (tester) async {
        final more = await open(tester, morePath);
        await tester.scrollUntilVisible(
          key('more-feedback'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await shot('1-more-row');
        more.router.go(feedbackPath);
        await tester.pumpAndSettle();
        await shot('2-hub');
      },
    );

    testWidgets('writing from the hub, $name', skip: _dir == null, (
      tester,
    ) async {
      await open(tester, feedbackPath);
      await tapKey(tester, 'feedback-write');
      await tester.enterText(
        key('feedback-message'),
        language == AppLanguage.de
            ? 'Mehr Platz für Notizen an einem Eintrag, bitte.'
            : 'More room for notes on an item, please.',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await shot('3-compose');
    });

    testWidgets('a note with a reply and Fixed in, $name', skip: _dir == null, (
      tester,
    ) async {
      await open(tester, feedbackNotePath('n-fixed'));
      await shot('4-thread');
    });

    testWidgets('an idea with the household +1, $name', skip: _dir == null, (
      tester,
    ) async {
      await open(tester, feedbackPath);
      await tester.scrollUntilVisible(
        key('feedback-ideas-note'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(key('feedback-vote-i-meal'));
      await tester.pumpAndSettle();
      await shot('5-voted');
    });
  }
}

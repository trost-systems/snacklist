// Job 267: review screenshots of feedback with a screenshot (flag
// feedback-fb2) on a phone: the shake question, the annotator, the form
// after a shake and the form from More's row, each in German light,
// English dark and German at 130 % text. Skipped unless SCREENSHOT_DIR is
// set:
//   SCREENSHOT_DIR=$PWD/../docs/screenshots/267 flutter test \
//     --update-goldens test/feedback/feedback_screenshots_test.dart
import 'dart:async';
import 'dart:io';

import 'package:family_groceries/core/language.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../design/fonts.dart';
import '../list/fake_repository.dart';
import '../more/more_harness.dart';
import 'fb2_harness.dart';

final _dir = Platform.environment['SCREENSHOT_DIR'];

void _seed(FakeRepository repo) => [
  'Hafermilch',
  'Bananen',
  'Brot',
  'Joghurt',
  'Äpfel',
].forEach(repo.remoteAdd);

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
    Future<More> open(
      WidgetTester tester,
      StreamController<AccelerometerEvent> samples,
    ) async {
      final more = await pumpMore(
        tester,
        location: listPath,
        app: true,
        flags: fb2,
        language: language,
        theme: theme,
        seed: _seed,
        shakeSamples: samples.stream,
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

    testWidgets('shake: question, annotator, form, $name', skip: _dir == null, (
      tester,
    ) async {
      final samples = StreamController<AccelerometerEvent>.broadcast();
      addTearDown(samples.close);
      await open(tester, samples);
      await shake(tester, samples);
      await until(tester, () => key('shake-sheet').evaluate().isNotEmpty);
      await shot('1-shake-sheet');
      await tapKey(tester, 'shake-with-screenshot');
      await shot('2-annotator');
      await markUpAndFinish(tester);
      await tester.enterText(
        key('feedback-message'),
        language == AppLanguage.de
            ? 'Das Häkchen bei Brot reagiert erst beim zweiten Tippen.'
            : 'Ticking off bread only works on the second tap.',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(key('feedback-screenshot-preview'));
      await tester.pumpAndSettle();
      await shot('3-form-from-shake');
    }, variant: android);

    testWidgets("More's row: the form, $name", skip: _dir == null, (
      tester,
    ) async {
      final samples = StreamController<AccelerometerEvent>.broadcast();
      addTearDown(samples.close);
      final more = await open(tester, samples);
      await tapKey(tester, 'tab-more');
      await until(tester, () => more.capture.beforeMore != null);
      await tester.scrollUntilVisible(
        key('more-feedback'),
        200,
        scrollable: find.descendant(
          of: key('more-screen'),
          matching: find.byType(Scrollable),
        ),
      );
      await tapKey(tester, 'more-feedback');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(key('feedback-add-screenshot'));
      await tester.pumpAndSettle();
      await shot('4-form-from-menu');
    }, variant: android);
  }
}

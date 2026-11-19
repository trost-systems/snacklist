// Job 281: review screenshots of reporting content (flag
// report-content-entry) on a phone: More's row, the hub's and the feedback
// form's entry, the form empty, with its errors, filled in, for child abuse
// material, the picker and the confirmation, each in German light, English
// dark and German at 200 % text. Skipped unless SCREENSHOT_DIR is set:
//   SCREENSHOT_DIR=$PWD/../docs/screenshots/281 TZ=UTC flutter test \
//     --update-goldens test/report/report_screenshots_test.dart
import 'dart:io';

import 'package:family_groceries/app/language.dart';
import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/report/report_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../design/fonts.dart';
import '../feedback/fb2_harness.dart' show key, tapKey;
import '../feedback/fb4_harness.dart' show fb4Server;
import '../more/more_harness.dart';
import 'fakes.dart';
import 'report_harness.dart'
    show fillIn, mia, pickItem, report, reportFb4, seedHousehold, send, show;

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
    ('de-200', AppLanguage.de, ThemeMode.light, 2.0),
  ]) {
    Future<More> open(
      WidgetTester tester, {
      Set<String> flags = reportFb4,
      String location = morePath,
    }) async {
      final more = await pumpMore(
        tester,
        location: location,
        flags: flags,
        language: language,
        theme: theme,
        feedback: fb4Server(english: language == AppLanguage.en),
        report: FakeReportRepository(who: mia),
        seed: seedHousehold,
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

    Future<void> row(WidgetTester tester) async {
      await tester.scrollUntilVisible(
        key('more-feedback'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'the More row, the hub and the feedback form, $name',
      skip: _dir == null,
      (tester) async {
        await open(tester);
        await row(tester);
        await shot('1-more-row');
        await tapKey(tester, 'more-feedback');
        await shot('2-hub');
      },
    );

    testWidgets('the feedback form without FB4, $name', skip: _dir == null, (
      tester,
    ) async {
      await open(tester, flags: report);
      await row(tester);
      await tapKey(tester, 'more-feedback');
      await shot('3-sheet-no-fb4');
    });

    testWidgets('the form, $name', skip: _dir == null, (tester) async {
      await open(tester, location: feedbackPath);
      await tapKey(tester, 'report-entry');
      await shot('4-form');
      await send(tester);
      await shot('5-errors');
      await tapKey(tester, 'report-where-choose');
      await shot('6-picker');
      await tester.tap(key('report-picker-close'));
      await tester.pumpAndSettle();
      await fillIn(tester);
      await show(tester, 'report-picked');
      await shot('7-filled');
      await show(tester, 'report-send');
      await shot('8-filled-bottom');
      await send(tester);
      await shot('9-done');
    });

    testWidgets('child abuse material, $name', skip: _dir == null, (
      tester,
    ) async {
      await open(tester, location: feedbackPath);
      await tapKey(tester, 'report-entry');
      await fillIn(tester, category: ReportCategory.csam);
      await show(tester, 'report-csam-add');
      await shot('10-csam');
      await pickItem(tester, 'remote-1');
    });
  }
}

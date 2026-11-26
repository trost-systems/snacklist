// Job 471: PR screenshots of the tick's undo snackbar, German and English,
// on a phone-size list. Real theme and the app's fonts. Skipped unless
// SCREENSHOT_DIR is set:
//   SCREENSHOT_DIR=/tmp/shots flutter test --update-goldens \
//     test/list/tick_undo_screenshots_test.dart
import 'dart:io';

import 'package:family_groceries/core/language.dart';
import 'package:family_groceries/list/list_view/item_row.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../design/fonts.dart';
import '../more/more_harness.dart';

final _dir = Platform.environment['SCREENSHOT_DIR'];

const _items = {
  AppLanguage.de: ['Milch', 'Brot', 'Eier', 'Äpfel', 'Butter'],
  AppLanguage.en: ['Milk', 'Bread', 'Eggs', 'Apples', 'Butter'],
};

void main() {
  setUpAll(() async {
    await fakeSupabase();
    if (_dir != null) {
      await loadAppFonts();
      WidgetsApp.debugAllowBannerOverride = false;
    }
  });
  setUp(
    () => VisibilityDetectorController.instance.updateInterval = Duration.zero,
  );

  for (final MapEntry(key: language, value: items) in _items.entries) {
    final name = '471-tick-undo-${language.code}';
    testWidgets(name, skip: _dir == null, (tester) async {
      await pumpMore(
        tester,
        location: listPath,
        routes: listTabRoutes(),
        language: language,
        seed: (repo) => items.forEach(repo.remoteAdd),
      );
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is ItemRow && w.item.name == items.first,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(Uri.file('$_dir/$name.png')),
      );
    });
  }
}

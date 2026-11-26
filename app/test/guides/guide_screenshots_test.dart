// Job 462: PR screenshots of the in-app guide view, from the live guides'
// Markdown twins in fixtures/. Skipped unless SCREENSHOT_DIR is set:
//   SCREENSHOT_DIR=/tmp/shots flutter test --update-goldens \
//     test/guides/guide_screenshots_test.dart
import 'dart:io';

import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/guides/guide_page.dart';
import 'package:family_groceries/guides/guide_screen.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../design/fonts.dart';

final _dir = Platform.environment['SCREENSHOT_DIR'];

typedef Scene = ({
  String name,
  String path,
  String? fixture,
  Brightness brightness,
  double height,
});

const _scenes = <Scene>[
  (
    name: 'siri-de',
    path: '/de/anleitungen/siri-kurzbefehl',
    fixture: 'de-anleitungen-siri-kurzbefehl',
    brightness: Brightness.light,
    height: 1800,
  ),
  (
    name: 'alexa-de-dark',
    path: '/de/anleitungen/alexa',
    fixture: 'de-anleitungen-alexa',
    brightness: Brightness.dark,
    height: 844,
  ),
  (
    name: 'guides-en',
    path: '/en/guides',
    fixture: 'en-guides',
    brightness: Brightness.light,
    height: 844,
  ),
  (
    name: 'missing-de',
    path: '/de/anleitungen/gibt-es-nicht',
    fixture: null,
    brightness: Brightness.light,
    height: 844,
  ),
];

void main() {
  setUpAll(() async {
    if (_dir != null) {
      await loadAppFonts();
      // The tester has no system monospace font; Roboto stands in.
      final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
      final bytes = File('${artifacts.path}/material_fonts/Roboto-Regular.ttf')
          .readAsBytesSync();
      await (FontLoader(
        'monospace',
      )..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
      WidgetsApp.debugAllowBannerOverride = false;
    }
  });

  for (final scene in _scenes) {
    testWidgets('guide-${scene.name}', skip: _dir == null, (tester) async {
      tester.view.physicalSize = Size(390, scene.height) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(scene.brightness),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale(scene.path.substring(1, 3)),
          home: GuideScreen(
            page: guidePage(scene.path),
            load: (_) async => switch (scene.fixture) {
              final name? => GuideShown(
                File('test/guides/fixtures/$name.md').readAsStringSync(),
              ),
              null => const GuideMissing(),
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (scene.name.startsWith('alexa')) {
        await tester.ensureVisible(
          find.textContaining('Du sagst', findRichText: true).first,
        );
        await tester.pumpAndSettle();
      }
      await expectLater(
        find.byType(GuideScreen),
        matchesGoldenFile('$_dir/guide-${scene.name}.png'),
      );
    });
  }
}

// Job 234: review screenshots of trip mode at 130 % text, 390 px wide, in
// the app's fonts: the running strip on the list, the question and the
// auto-paused strip, and the Premium summary with two stores and amounts.
// Skipped unless SCREENSHOT_DIR is set:
//   SCREENSHOT_DIR=../docs/screenshots/234 flutter test --update-goldens \
//     test/trip/screenshots_test.dart
import 'dart:io';

import 'package:family_groceries/trip/ask_sheet.dart';
import 'package:family_groceries/trip/model.dart';
import 'package:family_groceries/trip/summary_view.dart';
import 'package:family_groceries/trip/trip_strip.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../design/fonts.dart';
import 'list_trip_widget_test.dart' show pumpList;
import 'parts_widget_test.dart'
    show catalog, finished, line, pumpPart, rewe, running;

final _dir = Platform.environment['SCREENSHOT_DIR'];

const _textScale = 1.3;

/// Two stores, prices on both, an extra by Lea and an own one.
final _shop = [
  line('Vollmilch', plannedCents: 109, paidCents: 119),
  line('Bananen', plannedCents: 150, paidCents: 180),
  line('Brot', bought: false, plannedCents: 200),
  line('Käse', planned: false, byOther: true, addedBy: 'lea'),
  line('Äpfel', store: rewe, plannedCents: 249, paidCents: 249),
  line('Spülmittel', store: rewe),
  line('Eis', planned: false, store: rewe, paidCents: 300),
];

Future<void> _shoot(String name) => expectLater(
  find.byType(MaterialApp),
  matchesGoldenFile(Uri.file('$_dir/scale130-$name.png')),
);

void main() {
  setUpAll(() async {
    if (_dir != null) {
      await loadAppFonts();
      // The item icons' emoji, where the box has the font (not in git).
      final emoji = File('/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf');
      if (emoji.existsSync()) {
        final bytes = emoji.readAsBytesSync();
        await (FontLoader(
          'Noto Color Emoji',
        )..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
      }
    }
    WidgetsApp.debugAllowBannerOverride = false;
  });
  setUp(
    () => VisibilityDetectorController.instance.updateInterval = Duration.zero,
  );

  for (final brightness in Brightness.values) {
    final theme = brightness.name;

    testWidgets(
      'the running strip on the list, de $theme',
      skip: _dir == null,
      (tester) async {
        await pumpList(
          tester,
          brightness: brightness,
          textScale: _textScale,
          seed: (repo) => repo
            ..remoteAdd('Hafermilch Barista', storeId: 'lidl')
            ..remoteAdd('Vollkornbrot', storeId: 'lidl')
            ..remoteAdd('Spülmittel', storeId: 'dm'),
        );
        await tester.tap(find.text('Vollkornbrot'));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('trip-ask-yes')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('trip-strip')), findsOneWidget);
        await _shoot('list-strip-de-$theme');
      },
    );

    testWidgets(
      'the question and the auto-paused strip, de $theme',
      skip: _dir == null,
      (tester) async {
        final last = DateTime(2026, 11, 14, 10, 6);
        await pumpPart(
          tester,
          Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TripStrip(
                trip: running(
                  pauses: [
                    TripPause(
                      from: last.add(const Duration(minutes: 45)),
                      auto: true,
                    ),
                  ],
                ),
                lastTick: last,
                elapsed: (_) => const Duration(minutes: 51, seconds: 12),
                onPause: () {},
                onResume: () {},
                onEnd: () {},
              ),
              const SizedBox(height: 24),
              const TripAskSheet(itemName: 'Hafermilch Barista'),
            ],
          ),
          size: const Size(390, 844),
          brightness: brightness,
          textScale: _textScale,
        );
        await tester.pumpAndSettle();
        await _shoot('sheet-autopause-de-$theme');
      },
    );
  }

  for (final (locale, brightness) in const [
    (Locale('de'), Brightness.light),
    (Locale('en'), Brightness.dark),
  ]) {
    final name = '${locale.languageCode}-${brightness.name}';
    testWidgets('the Premium summary, $name', skip: _dir == null, (
      tester,
    ) async {
      await pumpPart(
        tester,
        TripSummaryView(
          trip: finished(lines: _shop),
          catalog: catalog,
          prices: true,
          onMark: (_, _) {},
        ),
        size: const Size(390, 1600),
        brightness: brightness,
        locale: locale,
        textScale: _textScale,
      );
      await tester.pumpAndSettle();
      await _shoot('summary-$name');
    });
  }
}

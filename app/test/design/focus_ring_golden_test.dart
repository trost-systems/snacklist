// Goldens of FH1's focus ring (job 487): every control of focus_cases.dart
// unfocused and focused side by side, per look and theme. Only one control
// holds focus at a time, so each pair is shot alone and set on one sheet.
// After a deliberate look change:
//   flutter test --update-goldens test/design/focus_ring_golden_test.dart
import 'dart:ui' as ui;

import 'package:family_groceries/design/look.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'focus_cases.dart';
import 'fonts.dart';

void main() {
  setUpAll(() async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await loadAppFonts();
  });
  tearDown(() {
    appLook = Look.hex;
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  // Each shot: the control and 8 px round it, at most this big.
  const cell = Size(380, 80);
  const gap = 8.0;

  for (final look in Look.values) {
    for (final brightness in Brightness.values) {
      final name = '${look.name}-${brightness.name}';
      testWidgets('focus rings, $name', (tester) async {
        appLook = look;
        final shots = <(ui.Image, Rect)>[];
        for (final c in focusCases) {
          await pumpFocusCase(tester, brightness, c);
          FocusManager.instance.highlightStrategy =
              FocusHighlightStrategy.alwaysTraditional;
          await tester.pumpAndSettle();
          final crop = Rect.fromCenter(
            center: c.bounds(tester).center,
            width: cell.width,
            height: cell.height,
          );
          shots.add((await captureFocusCase(tester), crop));
          c.node(tester).requestFocus();
          await tester.pumpAndSettle();
          shots.add((await captureFocusCase(tester), crop));
        }
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        final rows = focusCases.length;
        final sheet = Size(
          2 * cell.width + 3 * gap,
          rows * (cell.height + gap) + gap,
        );
        canvas.drawColor(const Color(0xff808080), BlendMode.src);
        for (final (i, (shot, crop)) in shots.indexed) {
          canvas.drawImageRect(
            shot,
            crop,
            Offset(
                  gap + (i % 2) * (cell.width + gap),
                  gap + (i ~/ 2) * (cell.height + gap),
                ) &
                cell,
            Paint(),
          );
        }
        final image = (await tester.runAsync(
          () => recorder.endRecording().toImage(
            sheet.width.toInt(),
            sheet.height.toInt(),
          ),
        ))!;
        for (final (shot, _) in shots) {
          shot.dispose();
        }
        await expectLater(
          image,
          matchesGoldenFile('goldens/focus-rings-$name.png'),
        );
        image.dispose();
      });
    }
  }
}

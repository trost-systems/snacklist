// FH1 (job 487) for a hex tab: keyboard focus draws the ring inside the
// tab's hex, for shell_tabs_test.dart and list_tabs_test.dart.
import 'package:family_groceries/design/tokens.g.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Focuses [tab] as the keyboard would and expects its hex to draw, in
/// [color], its [contour] (none when 0) and the ring inward from it, while
/// the hex keeps its size and place.
Future<void> expectTabFocusRing(
  WidgetTester tester,
  Finder tab, {
  required Color color,
  required double contour,
}) async {
  // The hex the ring is painted over.
  final hex = find
      .descendant(
        of: tab,
        matching: find.byWidgetPredicate((w) => w is CustomPaint),
      )
      .first;
  final before = tester.getRect(hex);
  FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.alwaysTraditional;
  addTearDown(
    () => FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.automatic,
  );
  Focus.of(tester.element(hex)).requestFocus();
  await tester.pumpAndSettle();
  expect(tester.getRect(hex), before, reason: 'focus moved the tab');
  final mid = before.width / 2;
  final ringFrom = contour;
  // A hex with a contour is the honey one: its face and contour come first.
  final pattern = contour > 0
      ? (paints
          ..path()
          ..path(style: PaintingStyle.stroke, strokeWidth: contour)
          ..path(
            style: PaintingStyle.stroke,
            strokeWidth: contour,
            color: color,
          ))
      : paints;
  expect(
    hex,
    pattern..path(
      style: PaintingStyle.stroke,
      strokeWidth: HlFocus.ringWidth,
      color: color,
      // Its centre line is half the ring in from the contour: the band runs
      // from the contour inward, never past the hex.
      includes: [Offset(mid, ringFrom + HlFocus.ringWidth / 2 + 0.5)],
      excludes: [Offset(mid, ringFrom + HlFocus.ringWidth / 2 - 0.5)],
    ),
  );
}

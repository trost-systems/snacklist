import 'package:family_groceries/more/app_update.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../analytics/fakes.dart' show MemoryAnalyticsStore, loadedAnalytics;
import 'more_harness.dart';

/// The app doesn't clamp the text scale; an overflow fails the test on its
/// own.
void main() {
  setUpAll(fakeSupabase);

  /// More top to bottom in a build that sends usage data: every row, the
  /// version.
  final everything =
      [
        for (final row in menuRows) ...[
          find.byKey(ValueKey(row)),
          if (row == 'more-settings')
            find.byKey(const ValueKey('more-usage-data')),
        ],
        find.byKey(const ValueKey('more-version')),
      ].map(
        (finder) => find.descendant(
          of: find.byKey(const ValueKey('more-screen')),
          matching: finder,
        ),
      );

  for (final scale in [2.0, 3.0]) {
    for (final size in [const Size(360, 640), const Size(320, 568)]) {
      testWidgets('at text scale $scale every Mehr row fits '
          '(${size.width.toInt()}x${size.height.toInt()})', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpMore(
          tester,
          size: size,
          analytics: await loadedAnalytics(MemoryAnalyticsStore()),
        );
        for (final finder in everything) {
          await tester.scrollUntilVisible(finder, 200);
          await tester.pumpAndSettle();
          expect(finder, findsOneWidget);
        }
      });

      testWidgets('at text scale $scale the update card fits '
          '(${size.width.toInt()}x${size.height.toInt()})', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpMore(
          tester,
          size: size,
          updates: FakeAppUpdates(const StoreVersion('1.4.0')),
        );
        expect(find.byKey(const ValueKey('more-update-card')), findsOneWidget);
      });

      testWidgets('at text scale $scale $usageDataPath fits '
          '(${size.width.toInt()}x${size.height.toInt()})', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        // A build that sends usage data, so the page shows its switch.
        await pumpMore(
          tester,
          size: size,
          location: usageDataPath,
          analytics: await loadedAnalytics(MemoryAnalyticsStore()),
        );
        final toggle = find.byKey(const ValueKey('more-analytics'));
        await tester.scrollUntilVisible(toggle, 200);
        await tester.pumpAndSettle();
        expect(toggle, findsOneWidget);
      });
    }
  }

  // From 840 px More's list is a 360 px pane beside the page.
  for (final scale in [1.0, 2.0, 3.0]) {
    for (final size in [const Size(840, 600), const Size(1366, 1024)]) {
      testWidgets('wide at text scale $scale every Mehr row fits in the pane '
          '(${size.width.toInt()}x${size.height.toInt()})', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpMore(
          tester,
          size: size,
          analytics: await loadedAnalytics(MemoryAnalyticsStore()),
        );
        final pane = find.descendant(
          of: find.byKey(const ValueKey('more-screen')),
          matching: find.byType(Scrollable),
        );
        for (final finder in everything) {
          await tester.scrollUntilVisible(finder, 200, scrollable: pane.first);
          await tester.pumpAndSettle();
          expect(finder, findsOneWidget);
        }
      });
    }
  }
}

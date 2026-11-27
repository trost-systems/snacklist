import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:family_groceries/core/screen_reader.dart';
import 'package:family_groceries/list/list_view/item_row.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../core/screen_reader_harness.dart';
import '../more/more_harness.dart';

/// A tick shows `Abgehakt: <name>` with Rückgängig, which puts back only
/// the last tick, at its place (Peter's CP1, job 471).
void main() {
  setUpAll(fakeSupabase);
  setUp(
    () => VisibilityDetectorController.instance.updateInterval = Duration.zero,
  );

  Finder row(String name) =>
      find.byWidgetPredicate((w) => w is ItemRow && w.item.name == name);

  List<String> rowOrder(WidgetTester tester) {
    final rows = tester.widgetList<ItemRow>(find.byType(ItemRow)).toList()
      ..sort(
        (a, b) => tester
            .getTopLeft(find.byWidget(a))
            .dy
            .compareTo(tester.getTopLeft(find.byWidget(b)).dy),
      );
    return [for (final r in rows) r.item.name];
  }

  Future<More> pumpList(WidgetTester tester) => pumpMore(
    tester,
    location: listPath,
    routes: listTabRoutes(),
    seed: (repo) => repo
      ..remoteAdd('Erbsen', categoryId: 'produce')
      ..remoteAdd('Bohnen', categoryId: 'produce')
      ..remoteAdd('Linsen', categoryId: 'produce'),
  );

  ItemStatus status(More more, String name) =>
      more.repo.rows.values.singleWhere((i) => i.name == name).status;

  Future<void> tick(WidgetTester tester, String name) async {
    await tester.tap(row(name));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  Finder undo() => find.widgetWithText(SnackBarAction, 'Rückgängig');

  testWidgets('a tick says „Abgehakt: <name>“ with Rückgängig, which puts '
      'it back in its place at once', (tester) async {
    final more = await pumpList(tester);
    expect(rowOrder(tester), ['Erbsen', 'Bohnen', 'Linsen']);
    await tick(tester, 'Bohnen');
    expect(find.text('Abgehakt: Bohnen'), findsOneWidget);
    expect(undo(), findsOneWidget);
    expect(row('Bohnen'), findsNothing);
    expect(status(more, 'Bohnen'), ItemStatus.bought);

    more.repo.gate = Completer<void>();
    await tester.tap(undo());
    await tester.pump();
    expect(rowOrder(tester), ['Erbsen', 'Bohnen', 'Linsen']);
    expect(
      status(more, 'Bohnen'),
      ItemStatus.bought,
      reason: 'shown in its place before the server has it',
    );
    more.repo.gate!.complete();
    await tester.pumpAndSettle();
    expect(rowOrder(tester), ['Erbsen', 'Bohnen', 'Linsen']);
    expect(status(more, 'Bohnen'), ItemStatus.active);
    expect(find.text('Abgehakt: Bohnen'), findsNothing);
  });

  testWidgets("ticks in a row keep the last one's snackbar; Rückgängig "
      'puts back only that one', (tester) async {
    final more = await pumpList(tester);
    await tick(tester, 'Erbsen');
    await tick(tester, 'Linsen');
    expect(find.text('Abgehakt: Erbsen'), findsNothing);
    expect(find.text('Abgehakt: Linsen'), findsOneWidget);
    expect(undo(), findsOneWidget);

    await tester.tap(undo());
    await tester.pumpAndSettle();
    expect(rowOrder(tester), ['Bohnen', 'Linsen']);
    expect(status(more, 'Linsen'), ItemStatus.active);
    expect(status(more, 'Erbsen'), ItemStatus.bought);
  });

  testWidgets('a refused tick comes back and its message replaces the '
      'undo snackbar', (tester) async {
    final more = await pumpList(tester);
    more.repo.reject = true;
    await tick(tester, 'Bohnen');
    expect(find.text('Änderung abgelehnt: Bohnen'), findsOneWidget);
    expect(find.text('Abgehakt: Bohnen'), findsNothing);
    expect(undo(), findsNothing);
    expect(rowOrder(tester), ['Erbsen', 'Bohnen', 'Linsen']);
    expect(status(more, 'Bohnen'), ItemStatus.active);
  });

  testWidgets('a refused undo ticks the item off again and says so', (
    tester,
  ) async {
    final more = await pumpList(tester);
    await tick(tester, 'Bohnen');
    more.repo
      ..reject = true
      ..gate = Completer<void>();
    await tester.tap(undo());
    await tester.pump();
    expect(row('Bohnen'), findsOneWidget, reason: 'shown back at once');
    more.repo.gate!.complete();
    await tester.pumpAndSettle();
    expect(row('Bohnen'), findsNothing);
    expect(status(more, 'Bohnen'), ItemStatus.bought);
    expect(find.text('Änderung abgelehnt: Bohnen'), findsOneWidget);
  });

  testWidgets('with VoiceOver a tick is said once: the snackbar stays '
      'silent but reachable; Rückgängig says the item is back and puts the '
      'focus on its row (job 474)', (tester) async {
    final semantics = tester.ensureSemantics();
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(accessibleNavigation: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpList(tester);
    final log = screenReaderLog(tester);
    await tick(tester, 'Bohnen');
    await tester.pump(announceSettle);
    expect(log, ['focus: Linsen', 'say: Bohnen abgehakt']);
    expect(
      find.semantics.byPredicate(
        (n) => n.flagsCollection.isLiveRegion && n.label.contains('Bohnen'),
      ),
      findsNothing,
      reason: 'the live region would say it again',
    );
    expect(
      find.semantics.byPredicate((n) => n.label == 'Abgehakt: Bohnen'),
      findsOne,
      reason: 'read when the user goes to the snackbar',
    );
    expect(
      find.semantics.byPredicate(
        (n) =>
            n.label == 'Rückgängig' &&
            n.getSemanticsData().hasAction(SemanticsAction.tap),
      ),
      findsOne,
    );

    log.clear();
    await tester.tap(undo());
    await tester.pumpAndSettle();
    await tester.pump(announceSettle);
    expect(log, ['focus: Bohnen', 'say: Bohnen wieder auf der Liste']);
    semantics.dispose();
  });

  testWidgets('English: "Bohnen ticked off", then "Bohnen back on the list"', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpMore(
      tester,
      location: listPath,
      routes: listTabRoutes(),
      device: const [Locale('en', 'US')],
      seed: (repo) => repo..remoteAdd('Bohnen', categoryId: 'produce'),
    );
    tester.takeAnnouncements();
    await tick(tester, 'Bohnen');
    expect(tester.takeAnnouncements(), [
      isAccessibilityAnnouncement('Bohnen ticked off'),
    ]);
    await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
    await tester.pumpAndSettle();
    expect(tester.takeAnnouncements(), [
      isAccessibilityAnnouncement('Bohnen back on the list'),
    ]);
    semantics.dispose();
  });
}

import 'dart:ui' show Tristate;

import 'package:family_groceries/app/router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../more/more_harness.dart';

/// Back goes where the user came from, across the app's real routes and
/// shell (job 78).
void main() {
  Finder key(String k) => find.byKey(ValueKey(k));

  /// The tab a screen reader announces as selected.
  int tab(WidgetTester tester) => ['tab-list', 'tab-more'].indexWhere(
    (tab) =>
        tester.getSemantics(key(tab)).flagsCollection.isSelected ==
        Tristate.isTrue,
  );

  setUpAll(fakeSupabase);

  Future<void> back(WidgetTester tester) async {
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
  }

  // Job 206: joining is the household sheet's, no longer a row of More.
  testWidgets('List, the household sheet, Mit Code beitreten, back: the '
      'list', (tester) async {
    final more = await pumpMore(tester, location: listPath, app: true);
    await tester.tap(key('household-chip'));
    await tester.pumpAndSettle();
    await tester.tap(key('household-join'));
    await tester.pumpAndSettle();
    expect(key('join-screen'), findsOneWidget);
    expect(more.router.state.uri.path, joinCodePath);
    await back(tester);
    expect(key('join-screen'), findsNothing);
    expect(key('list-header'), findsOneWidget);
    expect(tab(tester), 0);
    expect(more.router.state.uri.path, listPath);
  });

  // Pushed over the list: Android's back returns to it instead of closing
  // the app, on the join screen and on Neuer Haushalt.
  for (final (row, page) in const [
    ('household-join', 'join-screen'),
    ('household-new', 'create-household-screen'),
  ]) {
    testWidgets('List, the household sheet, $row, system back: the list', (
      tester,
    ) async {
      final more = await pumpMore(tester, location: listPath, app: true);
      await tester.tap(key('household-chip'));
      await tester.pumpAndSettle();
      await tester.tap(key(row));
      await tester.pumpAndSettle();
      expect(key(page), findsOneWidget);
      expect(await tester.binding.handlePopRoute(), isTrue, reason: 'popped');
      await tester.pumpAndSettle();
      expect(key(page), findsNothing);
      expect(key('list-header'), findsOneWidget);
      expect(tab(tester), 0);
      expect(more.router.state.uri.path, listPath);
    });
  }

  testWidgets('the old link /more/join opens the join screen', (tester) async {
    final more = await pumpMore(tester, location: '/more/join', app: true);
    expect(more.router.state.uri.path, joinCodePath);
    expect(key('join-screen'), findsOneWidget);
  });

  testWidgets('List, Anpassen, a store, back, back: the list, its tab '
      'selected', (tester) async {
    final more = await pumpMore(tester, location: listPath, app: true);
    await tester.tap(key('list-edit'));
    await tester.pumpAndSettle();
    expect(key('stores-screen'), findsOneWidget);
    expect(tab(tester), 0, reason: 'the tabs stay');
    await tester.tap(find.text('Lidl'));
    await tester.pumpAndSettle();
    expect(key('store-details'), findsOneWidget);
    expect(more.router.state.uri.path, '/edit/lidl');
    expect(more.screens.current, 'stores');

    await back(tester);
    expect(key('stores-screen'), findsOneWidget);
    await back(tester);
    expect(key('stores-screen'), findsNothing);
    expect(key('list-header'), findsOneWidget);
    expect(tab(tester), 0);
    expect(more.router.state.uri.path, listPath);
  });

  // Job 85: Rechtliches was a page; its rows sit on More now.
  testWidgets('the old link /more/legal opens More, its tab selected', (
    tester,
  ) async {
    final more = await pumpMore(tester, location: moreLegalPath, app: true);
    expect(more.router.state.uri.path, morePath);
    expect(key('more-screen'), findsOneWidget);
    await tester.scrollUntilVisible(key('more-imprint'), 200);
    expect(key('more-imprint'), findsOneWidget);
    expect(tab(tester), 1);
  });

  testWidgets('More and back keeps the List tab where it was', (tester) async {
    await pumpMore(tester, location: editPath, app: true);
    await tester.tap(key('tab-more'));
    await tester.pumpAndSettle();
    expect(key('more-screen'), findsOneWidget);
    await tester.tap(key('tab-list'));
    await tester.pumpAndSettle();
    expect(key('stores-screen'), findsOneWidget);
  });
}

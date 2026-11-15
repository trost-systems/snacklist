import 'dart:ui' show Tristate;

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/app/shell.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../design/fonts.dart';
import '../more/more_harness.dart';

/// Job 199: the Verlauf tab exists only while the flag `grocery-log` is on.
void main() {
  setUpAll(() async {
    await fakeSupabase();
    // Real glyphs: the pill's width depends on them.
    await loadAppFonts();
  });

  Finder key(String k) => find.byKey(ValueKey(k));

  testWidgets('flag off: no Verlauf tab, and its path is the list', (
    tester,
  ) async {
    final app = await pumpMore(tester, location: listPath, app: true);
    expect(key('tab-list'), findsOneWidget);
    expect(key('tab-more'), findsOneWidget);
    expect(key('tab-history'), findsNothing);
    app.router.go(historyPath);
    await tester.pumpAndSettle();
    expect(app.router.state.uri.path, listPath);
    expect(key('log-empty'), findsNothing);
    expect(key('list-header'), findsOneWidget);
  });

  testWidgets('flag on: Verlauf sits between Liste and Mehr and opens the '
      'history', (tester) async {
    final app = await pumpMore(
      tester,
      location: listPath,
      app: true,
      flags: {groceryLogFlag},
    );
    final xs = [
      for (final tab in ['tab-list', 'tab-history', 'tab-more'])
        tester.getCenter(key(tab)).dx,
    ];
    expect(xs, [...xs]..sort());
    await tester.tap(key('tab-history'));
    await tester.pumpAndSettle();
    expect(app.router.state.uri.path, historyPath);
    expect(key('log-empty'), findsOneWidget, reason: 'the server has none');
    expect(
      tester.getSemantics(key('tab-history')).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(app.screens.current, 'history');

    // Mehr and back keeps the tabs' own branches.
    await tester.tap(key('tab-more'));
    await tester.pumpAndSettle();
    expect(key('more-screen'), findsOneWidget);
    await tester.tap(key('tab-list'));
    await tester.pumpAndSettle();
    expect(app.router.state.uri.path, listPath);
  });

  testWidgets('the flag going off while Verlauf is shown goes to the list', (
    tester,
  ) async {
    final app = await pumpMore(tester, location: listPath, app: true);
    final flags = tester.element(find.byType(AppShell)).read<Flags>()
      ..replace({groceryLogFlag: true});
    await tester.pumpAndSettle();
    await tester.tap(key('tab-history'));
    await tester.pumpAndSettle();
    expect(app.router.state.uri.path, historyPath);

    flags.replace(const {});
    await tester.pumpAndSettle();
    expect(key('tab-history'), findsNothing);
    expect(app.router.state.uri.path, listPath);
    expect(key('list-header'), findsOneWidget);
    expect(
      tester.getSemantics(key('tab-list')).flagsCollection.isSelected,
      Tristate.isTrue,
    );
  });

  testWidgets('three labelled tabs fit the pill at 358 px, Verlauf on its '
      'hex', (tester) async {
    await pumpMore(
      tester,
      location: historyPath,
      app: true,
      size: const Size(358, 760),
      flags: {groceryLogFlag},
    );
    for (final (tab, label) in [
      ('tab-list', 'Liste'),
      ('tab-history', 'Verlauf'),
      ('tab-more', 'Mehr'),
    ]) {
      final text = find.descendant(of: key(tab), matching: find.text(label));
      expect(
        tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
        isFalse,
        reason: '$label is not cut',
      );
    }
  });

  testWidgets('large text on 358 px: the selected tab keeps its label, the '
      'others their icon and their name for screen readers', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpMore(
      tester,
      location: listPath,
      app: true,
      size: const Size(358, 760),
      flags: {groceryLogFlag},
    );
    expect(tester.takeException(), isNull);
    final selected = find.descendant(
      of: key('tab-list'),
      matching: find.text('Liste'),
    );
    expect(
      tester.renderObject<RenderParagraph>(selected).didExceedMaxLines,
      isFalse,
    );
    expect(
      find.descendant(of: key('tab-history'), matching: find.text('Verlauf')),
      findsNothing,
    );
    expect(tester.getSemantics(key('tab-history')).label, contains('Verlauf'));
    expect(tester.getSemantics(key('tab-more')).label, contains('Mehr'));
    for (final tab in ['tab-list', 'tab-history', 'tab-more']) {
      final rect = tester.getRect(key(tab));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(358));
    }
    await tester.tap(key('tab-history'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.descendant(of: key('tab-history'), matching: find.text('Verlauf')),
      findsOneWidget,
      reason: 'now selected',
    );
  });
}

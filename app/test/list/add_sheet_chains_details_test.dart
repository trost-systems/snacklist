import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/chain_suggestions.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_repository.dart';
import 'memory_cache.dart';
import 'retailer_fixtures.dart';

/// Job 313 on the users' build (flag `add-feedback-list` at 100 %): the
/// store options live in the added item's details, a steady three-row area
/// right above the add field. The chains offered and the question about a
/// new store come into view there and take a tap, on a phone.
void main() {
  late FakeRepository repo;
  Finder key(String k) => find.byKey(ValueKey(k));

  Future<void> pump(WidgetTester tester) async {
    tester.view
      ..devicePixelRatio = 3
      ..physicalSize = const Size(390, 844) * 3
      ..padding = const FakeViewPadding(top: 47.0 * 3, bottom: 34.0 * 3);
    addTearDown(tester.view.reset);
    repo = FakeRepository();
    seedRetailers(repo);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: MultiBlocProvider(
          providers: [
            BlocProvider(
              create: (_) => Flags(
                forced: {
                  openStoreAppFlag,
                  addFeedbackListFlag,
                  inputStableRowsFlag,
                },
              ),
            ),
            BlocProvider(
              create: (_) => ListCubit(
                repo,
                MemoryListCache(),
                userId: 'peter',
                grace: Duration.zero,
                region: () => 'DE',
              )..start(),
            ),
          ],
          child: const ShoppingList(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(key('add-item-field'));
    await tester.pumpAndSettle();
    await tester.enterText(key('add-item-field'), 'Tomaten');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.tap(key('chip-store'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(key('store-option-new'));
    await tester.pumpAndSettle();
    await tester.tap(key('store-option-new'));
    await tester.pumpAndSettle();
  }

  Future<void> name(WidgetTester tester, String text) async {
    await tester.enterText(key('store-new-field'), text);
    await tester.pump();
    await tester.pump(chainSuggestionDelay);
    await tester.pumpAndSettle();
  }

  /// [target] is wholly above the add field and the first thing a tap on
  /// it hits.
  void reachable(WidgetTester tester, Finder target) {
    expect(target.hitTestable(), findsOneWidget);
    expect(
      tester.getRect(target).bottom,
      lessThanOrEqualTo(tester.getRect(key('add-item-field')).top),
      reason: 'not under the add field',
    );
  }

  testWidgets('a chain offered under the new name is in view and takes a '
      'tap', (tester) async {
    await pump(tester);
    await name(tester, 'Re');
    final rewe = key('chain-suggestion-rewe-DE');
    reachable(tester, rewe);

    await tester.tap(rewe);
    await tester.pumpAndSettle();
    expect(
      repo.stores.where((s) => s.name == 'REWE').single.retailer?.chain,
      'rewe',
    );
  });

  testWidgets('the question after a plain chain name is in view: Ja and '
      'Nein take a tap', (tester) async {
    await pump(tester);
    await name(tester, 'Lidl am Markt');
    await tester.tap(key('store-new-confirm'));
    await tester.pumpAndSettle();
    reachable(tester, key('chain-question-yes'));
    reachable(tester, key('chain-question-no'));

    await tester.tap(key('chain-question-yes'));
    await tester.pumpAndSettle();
    expect(
      repo.stores
          .where((s) => s.name == 'Lidl am Markt')
          .single
          .retailer
          ?.chain,
      'lidl',
    );
  });
}

import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/list/list_view/item_row.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'fake_repository.dart';
import 'memory_cache.dart';

const _weekly = HouseholdList(id: 'weekly', name: 'Wocheneinkauf', position: 0);
const _diy = HouseholdList(id: 'diy', name: 'Baumarkt', position: 1);
const _party = HouseholdList(id: 'party', name: 'Sommerfest', position: 2);

/// Job 169b K and L on the list screen: the list tabs, and who brings what.
void main() {
  late FakeRepository repo;
  late ListCubit cubit;

  setUp(
    () => VisibilityDetectorController.instance.updateInterval = Duration.zero,
  );

  Future<void> pumpList(
    WidgetTester tester, {
    required List<HouseholdList> lists,
    double width = 390,
  }) async {
    tester.view
      ..devicePixelRatio = 3
      ..physicalSize = Size(width * 3, 844 * 3);
    addTearDown(tester.view.reset);
    repo = FakeRepository()
      ..lists = lists
      ..remoteAdd('Milch')
      ..remoteAdd('Schrauben', listId: lists.length > 1 ? 'diy' : null)
      ..remoteAdd('Kuchen', listId: lists.length > 2 ? 'party' : null);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: BlocProvider(
          create: (_) =>
              cubit = ListCubit(repo, MemoryListCache(), userId: 'peter')
                ..start(),
          child: const ShoppingList(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder key(String k) => find.byKey(ValueKey(k));
  List<String> rows(WidgetTester tester) => [
    for (final row in tester.widgetList<ItemRow>(find.byType(ItemRow)))
      row.item.name,
  ]..sort();

  testWidgets('one list: no tabs, every item', (tester) async {
    await pumpList(tester, lists: const [_weekly]);
    expect(key('list-tabs'), findsNothing);
    expect(rows(tester), ['Kuchen', 'Milch', 'Schrauben']);
  });

  testWidgets('three lists: a tab each and "+"; a tap shows that list', (
    tester,
  ) async {
    await pumpList(tester, lists: const [_weekly, _diy, _party]);
    expect(key('list-tabs'), findsOneWidget);
    for (final name in ['Wocheneinkauf', 'Baumarkt', 'Sommerfest']) {
      expect(
        find.descendant(of: key('list-tabs'), matching: find.text(name)),
        findsOneWidget,
      );
    }
    expect(key('list-tab-new'), findsOneWidget);
    expect(rows(tester), ['Milch']);
    expect(
      tester.getSemantics(key('list-tab-weekly')),
      matchesSemantics(
        label: 'Wocheneinkauf',
        isSelected: true,
        hasSelectedState: true,
        isButton: true,
        hasTapAction: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );

    // The test font is wide: the last tabs sit past the row's end.
    await tester.ensureVisible(key('list-tab-party'));
    await tester.tap(key('list-tab-party'));
    await tester.pumpAndSettle();
    expect(rows(tester), ['Kuchen']);
    expect(cubit.state.prefs.shownList, 'party');
  });

  testWidgets('"+" names a new list, which then shows', (tester) async {
    await pumpList(tester, lists: const [_weekly, _diy]);
    await tester.ensureVisible(key('list-tab-new'));
    await tester.tap(key('list-tab-new'));
    await tester.pumpAndSettle();
    expect(find.text('Neue Liste'), findsWidgets);
    await tester.enterText(key('name-dialog-field'), 'Grillen');
    await tester.tap(key('name-dialog-confirm'));
    await tester.pumpAndSettle();
    expect(repo.lists.map((l) => l.name), contains('Grillen'));
    expect(
      find.descendant(of: key('list-tabs'), matching: find.text('Grillen')),
      findsOneWidget,
    );
    expect(rows(tester), isEmpty, reason: 'the new list shows, empty');
  });

  testWidgets('at 358 px many lists scroll sideways and the shown one is '
      'in view', (tester) async {
    const many = [
      _weekly,
      _diy,
      _party,
      HouseholdList(id: 'grill', name: 'Grillabend am Samstag', position: 3),
      HouseholdList(id: 'xmas', name: 'Weihnachtsbäckerei', position: 4),
    ];
    await pumpList(tester, lists: many, width: 358);
    expect(tester.takeException(), isNull, reason: 'no overflow');
    cubit.showList('xmas');
    await tester.pumpAndSettle();
    final tab = tester.getRect(key('list-tab-xmas'));
    expect(tab.left, greaterThanOrEqualTo(0));
    expect(tab.right, lessThanOrEqualTo(358));
    final first = tester.getRect(key('list-tab-weekly'));
    expect(first.right, lessThan(16), reason: 'scrolled past the first');
  });

  testWidgets('a row says who brings it', (tester) async {
    await pumpList(tester, lists: const [_weekly]);
    final milk = repo.rows.values.firstWhere((i) => i.name == 'Milch');
    repo.emitClaim!(repo.remoteClaim(milk.id, quantity: '2'));
    cubit.claim(milk.id);
    await tester.pumpAndSettle();
    expect(find.text('Lea bringt 2 · Du bringst'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('^Milch\nLea bringt 2 · Du bringst\$')),
      findsOneWidget,
    );
  });
}

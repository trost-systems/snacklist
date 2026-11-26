import 'dart:async';

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/household/household_page.dart';
import 'package:family_groceries/household/household_switcher.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../list/fake_repository.dart';
import '../list/memory_cache.dart';
import 'harness.dart';

Finder _key(String k) => find.byKey(ValueKey(k));

const _weekly = HouseholdList(id: 'weekly', name: 'Wocheneinkauf', position: 0);
const _party = HouseholdList(id: 'party', name: 'Sommerfest', position: 1);
const _club = Household(id: 'club', name: 'Verein', memberCount: 12);

/// Job 207: which list Siri, Alexa and AI add to when no list is named.
void main() {
  late TestSession session;
  late FakeRepository repo;

  /// Peter in Zuhause (shown, his default) and Verein; Zuhause's lists are
  /// [lists] on its list and on the server, his pick [pick].
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    List<HouseholdList> lists = const [_weekly, _party],
    String? pick,
    bool flag = true,
    Household shown = home,
  }) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 1400);
    addTearDown(tester.view.reset);
    session = TestSession(InHousehold('peter', shown, const [home, _club]))
      ..householdLists['home'] = lists
      ..householdLists['club'] = const [
        HouseholdList(id: 'club-main', name: 'Liste', position: 0),
      ];
    if (pick != null) {
      session.defaultLists['home'] = pick;
    }
    addTearDown(session.close);
    repo = FakeRepository()..lists = [...lists];
    final list = ListCubit(repo, MemoryListCache(), userId: 'peter')..start();
    addTearDown(list.close);
    await tester.pumpWidget(
      RepositoryProvider<InviteRepository>.value(
        value: FakeInvites(),
        child: MultiBlocProvider(
          providers: [
            BlocProvider<SessionCubit>.value(value: session),
            BlocProvider.value(value: list),
            BlocProvider(
              create: (_) => Flags(forced: {if (flag) defaultListFlag}),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('de'),
            home: Scaffold(body: child),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String tile, String listId) async {
    await tester.tap(_key(tile));
    await tester.pumpAndSettle();
    await tester.tap(_key('default-list-$listId'));
    await tester.pumpAndSettle();
  }

  Finder subtitle(String text) => find.descendant(
    of: _key('household-default-list'),
    matching: find.text(text),
  );

  group('household page', () {
    testWidgets('names the pick under Siri, Alexa & KI', (tester) async {
      await pump(tester, const HouseholdPage(), pick: 'party');
      expect(find.text('Liste für Siri, Alexa & KI'), findsOneWidget);
      expect(subtitle('Sommerfest'), findsOneWidget);
    });

    testWidgets('picking another list saves it and shows it', (tester) async {
      await pump(tester, const HouseholdPage());
      expect(subtitle('Wocheneinkauf'), findsOneWidget);
      await tester.tap(_key('household-default-list'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckedPopupMenuItem<String>>(_key('default-list-weekly'))
            .checked,
        isTrue,
      );
      await tester.tap(_key('default-list-party'));
      await tester.pumpAndSettle();
      expect(session.listPicks, ['party']);
      expect(subtitle('Sommerfest'), findsOneWidget);
      expect(
        (session.state as InHousehold).household.id,
        'home',
        reason: 'the shown household stays',
      );
    });

    testWidgets('the pick shows before the server answers; a refusal puts '
        'it back and says why', (tester) async {
      await pump(tester, const HouseholdPage());
      final answer = session.hold = Completer<void>();
      session.fail = HouseholdProblem.offline;
      await choose(tester, 'household-default-list', 'party');
      expect(subtitle('Sommerfest'), findsOneWidget);
      answer.complete();
      await tester.pumpAndSettle();
      expect(subtitle('Wocheneinkauf'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(
            'Keine Internetverbindung. Versuche es erneut, sobald du online '
            'bist.',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('two picks that both fail put back the saved one', (
      tester,
    ) async {
      const camping = HouseholdList(id: 'camping', name: 'Zelten', position: 2);
      await pump(
        tester,
        const HouseholdPage(),
        lists: const [_weekly, _party, camping],
      );
      final first = session.hold = Completer<void>();
      await choose(tester, 'household-default-list', 'party');
      final second = session.hold = Completer<void>();
      await choose(tester, 'household-default-list', 'camping');
      expect(subtitle('Zelten'), findsOneWidget);
      session.fail = HouseholdProblem.offline;
      first.complete();
      await tester.pumpAndSettle();
      expect(subtitle('Zelten'), findsOneWidget, reason: 'still saving');
      session.fail = HouseholdProblem.offline;
      second.complete();
      await tester.pumpAndSettle();
      expect(subtitle('Wocheneinkauf'), findsOneWidget);
    });

    testWidgets('an older pick that saves after a newer one failed shows', (
      tester,
    ) async {
      const camping = HouseholdList(id: 'camping', name: 'Zelten', position: 2);
      await pump(
        tester,
        const HouseholdPage(),
        lists: const [_weekly, _party, camping],
      );
      final first = session.hold = Completer<void>();
      await choose(tester, 'household-default-list', 'party');
      final second = session.hold = Completer<void>();
      await choose(tester, 'household-default-list', 'camping');
      session.fail = HouseholdProblem.offline;
      second.complete();
      await tester.pumpAndSettle();
      expect(subtitle('Wocheneinkauf'), findsOneWidget);
      first.complete();
      await tester.pumpAndSettle();
      expect(subtitle('Sommerfest'), findsOneWidget);
    });

    testWidgets('a rename shows at once', (tester) async {
      await pump(tester, const HouseholdPage(), pick: 'party');
      final list = tester.element(_key('household-page')).read<ListCubit>();
      await list.renameList('party', 'Grillen');
      await tester.pumpAndSettle();
      expect(subtitle('Grillen'), findsOneWidget);
    });

    testWidgets('deleting the pick falls back to the first list', (
      tester,
    ) async {
      await pump(
        tester,
        const HouseholdPage(),
        lists: const [
          _weekly,
          _party,
          HouseholdList(id: 'bbq', name: 'Grillen', position: 2),
        ],
        pick: 'party',
      );
      final list = tester.element(_key('household-page')).read<ListCubit>();
      await list.deleteList('party');
      session.defaultLists.remove('home');
      await tester.pumpAndSettle();
      expect(subtitle('Wocheneinkauf'), findsOneWidget);
    });

    testWidgets('nothing with one list', (tester) async {
      await pump(tester, const HouseholdPage(), lists: const [_weekly]);
      expect(_key('household-default-list'), findsNothing);
    });

    testWidgets('nothing with the flag off', (tester) async {
      await pump(tester, const HouseholdPage(), flag: false);
      expect(_key('household-default-list'), findsNothing);
      expect(find.text('Liste für Siri, Alexa & KI'), findsNothing);
    });
  });

  group('household sheet', () {
    testWidgets("names the default household's pick; a tap picks another", (
      tester,
    ) async {
      await pump(tester, const HouseholdSheet(), shown: _club, pick: 'party');
      expect(find.text('Siri, Alexa & KI nutzen: Zuhause'), findsOneWidget);
      expect(find.text('Liste: Sommerfest'), findsOneWidget);
      await choose(tester, 'household-default-list-row', 'weekly');
      expect(session.listPicks, ['weekly']);
      expect(find.text('Liste: Wocheneinkauf'), findsOneWidget);
    });

    testWidgets('nothing when the default household has one list', (
      tester,
    ) async {
      await pump(tester, const HouseholdSheet(), lists: const [_weekly]);
      expect(_key('household-default-list-row'), findsNothing);
    });

    testWidgets('nothing with the flag off', (tester) async {
      await pump(tester, const HouseholdSheet(), flag: false);
      expect(_key('household-default-list-row'), findsNothing);
    });
  });
}

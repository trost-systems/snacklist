import 'package:family_groceries/household/lists_section.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../list/fake_repository.dart';
import '../list/memory_cache.dart';

/// Job 169b K: the household page's "Listen".
void main() {
  late FakeRepository repo;
  late ListCubit cubit;

  Future<void> pump(WidgetTester tester, List<HouseholdList> lists) async {
    repo = FakeRepository()
      ..lists = lists
      ..remoteAdd('Milch')
      ..remoteAdd('Kuchen', listId: lists.length > 1 ? lists[1].id : null)
      ..remoteAdd('Sahne', listId: lists.length > 1 ? lists[1].id : null);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: BlocProvider(
          create: (_) =>
              cubit = ListCubit(repo, MemoryListCache(), userId: 'peter')
                ..start(),
          child: const Scaffold(
            body: SingleChildScrollView(child: ListsSection()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder key(String k) => find.byKey(ValueKey(k));
  List<String> names() => [for (final l in repo.lists) l.name];

  Future<void> menu(WidgetTester tester, String listId, String action) async {
    await tester.tap(key('list-actions-$listId'));
    await tester.pumpAndSettle();
    await tester.tap(key('list-$action'));
    await tester.pumpAndSettle();
  }

  const weekly = HouseholdList(
    id: 'weekly',
    name: 'Wocheneinkauf',
    position: 0,
  );
  const party = HouseholdList(id: 'party', name: 'Sommerfest', position: 1);

  testWidgets('each list with what is open on it; the last one cannot go', (
    tester,
  ) async {
    await pump(tester, const [weekly]);
    expect(find.text('LISTEN'), findsOneWidget);
    expect(
      find.descendant(
        of: key('list-row-weekly'),
        matching: find.text('3 offen'),
      ),
      findsOneWidget,
    );
    await tester.tap(key('list-actions-weekly'));
    await tester.pumpAndSettle();
    expect(key('list-delete'), findsNothing);
    expect(key('list-up'), findsNothing);
    expect(key('list-down'), findsNothing);
    expect(key('list-rename'), findsOneWidget);
  });

  testWidgets('a new list, renamed and moved up', (tester) async {
    await pump(tester, const [weekly, party]);
    await tester.tap(key('list-new'));
    await tester.pumpAndSettle();
    await tester.enterText(key('name-dialog-field'), 'Baumarkt');
    await tester.tap(key('name-dialog-confirm'));
    await tester.pumpAndSettle();
    expect(names(), ['Wocheneinkauf', 'Sommerfest', 'Baumarkt']);
    final diy = repo.lists.last.id;

    await menu(tester, diy, 'rename');
    await tester.enterText(key('name-dialog-field'), 'Werkzeug');
    await tester.tap(key('name-dialog-confirm'));
    await tester.pumpAndSettle();
    await menu(tester, diy, 'up');
    expect(names(), ['Wocheneinkauf', 'Werkzeug', 'Sommerfest']);
    expect(
      [
        for (final tile in tester.widgetList<ListTile>(
          find.descendant(
            of: key('household-lists'),
            matching: find.byType(ListTile),
          ),
        ))
          if (tile.title case Text(:final data?)) data,
      ],
      ['Wocheneinkauf', 'Werkzeug', 'Sommerfest', 'Neue Liste'],
    );
  });

  testWidgets('delete asks first, naming what goes with it', (tester) async {
    await pump(tester, const [weekly, party]);
    await menu(tester, 'party', 'delete');
    expect(find.text('„Sommerfest“ löschen?'), findsOneWidget);
    expect(
      find.text('Die 2 offenen Artikel darauf werden mit gelöscht.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(names(), ['Wocheneinkauf', 'Sommerfest']);

    await menu(tester, 'party', 'delete');
    await tester.tap(key('list-delete-confirm'));
    await tester.pumpAndSettle();
    expect(names(), ['Wocheneinkauf']);
    expect(key('list-row-party'), findsNothing);
    expect(cubit.state.allItems.values.map((i) => i.name), ['Milch']);
  });
}

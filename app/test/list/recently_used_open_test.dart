import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/list/list_view/item_row.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_repository.dart';
import 'memory_cache.dart';

/// Job 367, flag `recently-used-open`: „Zuletzt verwendet“ starts open, with
/// no count, a tick lands in it and a tap on its row unticks.
void main() {
  late FakeRepository repo;

  Future<void> pumpList(WidgetTester tester, {required bool flag}) async {
    tester.view
      ..devicePixelRatio = 3
      ..physicalSize = const Size(390, 1600) * 3;
    addTearDown(tester.view.reset);
    repo = FakeRepository()
      ..remoteAdd('Erbsen', categoryId: 'produce')
      ..remoteAdd('Bohnen', categoryId: 'produce');
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: MultiBlocProvider(
          providers: [
            BlocProvider(
              create: (_) => Flags(forced: {if (flag) recentlyUsedOpenFlag}),
            ),
            BlocProvider(
              create: (_) =>
                  ListCubit(repo, MemoryListCache(), userId: 'peter')..start(),
            ),
          ],
          child: const ShoppingList(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Item item(String name) => repo.rows.values.firstWhere((i) => i.name == name);
  Finder row(String name) => find.widgetWithText(ItemRow, name);
  Finder usedRow(String name) => find.byKey(ValueKey('used-${item(name).id}'));

  Future<void> tick(WidgetTester tester, String name) async {
    await tester.tap(row(name));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  testWidgets('a tick lands in the open section, which shows no count; a '
      'tap on its row unticks', (tester) async {
    await pumpList(tester, flag: true);
    await tick(tester, 'Bohnen');
    expect(item('Bohnen').status, ItemStatus.bought);
    expect(usedRow('Bohnen'), findsOneWidget, reason: 'open without a tap');
    expect(find.text('Zuletzt verwendet'), findsOneWidget);
    expect(find.textContaining('Zuletzt verwendet ·'), findsNothing);
    expect(find.textContaining('(1)'), findsNothing);

    await tester.tap(usedRow('Bohnen'));
    await tester.pumpAndSettle();
    expect(item('Bohnen').status, ItemStatus.active);
    expect(find.text('Zuletzt verwendet'), findsNothing, reason: 'none left');
  });

  testWidgets('a fold is remembered', (tester) async {
    await pumpList(tester, flag: true);
    await tick(tester, 'Bohnen');
    await tester.tap(find.text('Zuletzt verwendet'));
    await tester.pumpAndSettle();
    expect(usedRow('Bohnen'), findsNothing, reason: 'folded by hand');
    await tick(tester, 'Erbsen');
    expect(usedRow('Bohnen'), findsNothing, reason: 'stays folded');
    await tester.tap(find.text('Zuletzt verwendet'));
    await tester.pumpAndSettle();
    expect(usedRow('Bohnen'), findsOneWidget);
  });

  testWidgets('without the flag it starts closed, as before', (tester) async {
    await pumpList(tester, flag: false);
    await tick(tester, 'Bohnen');
    expect(item('Bohnen').status, ItemStatus.bought);
    expect(find.text('Zuletzt verwendet'), findsOneWidget);
    expect(usedRow('Bohnen'), findsNothing, reason: 'closed as before');
  });
}

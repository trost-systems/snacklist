import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/screen_reader.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cache.dart' show recentlyUsedFoldKey;
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/list/list_view/item_row.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../core/screen_reader_harness.dart';
import 'fake_repository.dart';
import 'memory_cache.dart';

/// Job 367, flag `recently-used-open`: „Zuletzt verwendet“ starts open, with
/// no count, a tick lands in it and a tap on its row unticks.
void main() {
  late FakeRepository repo;
  late Flags flags;
  var cache = MemoryListCache();

  Future<void> pumpList(
    WidgetTester tester, {
    required bool flag,
    bool fresh = true,
    List<String> more = const [],
    Locale locale = const Locale('de'),
  }) async {
    if (fresh) {
      cache = MemoryListCache();
    }
    tester.view
      ..devicePixelRatio = 3
      ..physicalSize = const Size(390, 1600) * 3;
    addTearDown(tester.view.reset);
    if (fresh) {
      repo = FakeRepository()
        ..remoteAdd('Erbsen', categoryId: 'produce')
        ..remoteAdd('Bohnen', categoryId: 'produce');
      for (final name in more) {
        repo.remoteAdd(name, categoryId: 'produce');
      }
    }
    flags = Flags(forced: {if (flag) recentlyUsedOpenFlag});
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: flags),
            BlocProvider(
              create: (_) => ListCubit(repo, cache, userId: 'peter')..start(),
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
    final header = find.ancestor(
      of: find.text('Zuletzt verwendet'),
      matching: find.byType(ListTile),
    );
    expect(
      find.descendant(of: header, matching: find.byType(Text)),
      findsOneWidget,
      reason: 'the title only: no count, badge or subtitle',
    );
    expect(
      tester
          .widget<Text>(
            find.descendant(of: header, matching: find.byType(Text)),
          )
          .data,
      'Zuletzt verwendet',
    );

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
  testWidgets('a flag that arrives after the section is mounted opens it, '
      'and the next fold is stored as closed', (tester) async {
    await pumpList(tester, flag: false);
    await tick(tester, 'Bohnen');
    expect(usedRow('Bohnen'), findsNothing);
    flags.replace({recentlyUsedOpenFlag: true});
    await tester.pumpAndSettle();
    expect(usedRow('Bohnen'), findsOneWidget, reason: 'open by default now');
    await tester.tap(find.text('Zuletzt verwendet'));
    await tester.pumpAndSettle();
    expect(usedRow('Bohnen'), findsNothing);
    expect(cache.prefs?.folded, contains(recentlyUsedFoldKey));
  });

  testWidgets('a fold survives a restart on the same cache', (tester) async {
    await pumpList(tester, flag: true);
    await tick(tester, 'Bohnen');
    await tester.tap(find.text('Zuletzt verwendet'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await pumpList(tester, flag: true, fresh: false);
    expect(find.text('Zuletzt verwendet'), findsOneWidget);
    expect(usedRow('Bohnen'), findsNothing, reason: 'still folded');
    await tester.tap(find.text('Zuletzt verwendet'));
    await tester.pumpAndSettle();
    expect(usedRow('Bohnen'), findsOneWidget);
    expect(cache.prefs?.folded, isNot(contains(recentlyUsedFoldKey)));
  });

  group('screen readers (job 474)', () {
    testWidgets('a put-back says "<Name> wieder auf der Liste" and the focus '
        'stays in Zuletzt verwendet, on its top row, never the top of the '
        'screen; with the section gone it is on the row put back', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(accessibleNavigation: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpList(tester, flag: true, more: ['Milch', 'Brot', 'Äpfel']);
      for (final name in ['Milch', 'Brot', 'Äpfel']) {
        await tick(tester, name);
      }
      await tester.pump(announceSettle);
      final log = screenReaderLog(tester);
      List<String> stops() => tester.semantics
          .simulatedAccessibilityTraversal()
          .map((n) => n.identifier)
          .where((id) => id.startsWith('used-'))
          .toList();
      expect(stops(), [
        'used-${item('Äpfel').id}',
        'used-${item('Brot').id}',
        'used-${item('Milch').id}',
      ], reason: 'newest first');

      Future<void> putBack(String name) async {
        await tester.tap(usedRow(name));
        await tester.pumpAndSettle();
        await tester.pump(announceSettle);
      }

      await putBack('Brot');
      expect(log, [
        'focus: Äpfel\nWieder auf die Liste',
        'say: Brot wieder auf der Liste',
      ]);
      log.clear();
      await putBack('Äpfel');
      expect(log, [
        'focus: Milch\nWieder auf die Liste',
        'say: Äpfel wieder auf der Liste',
      ]);
      log.clear();
      await putBack('Milch');
      expect(find.text('Zuletzt verwendet'), findsNothing);
      expect(log, ['focus: Milch', 'say: Milch wieder auf der Liste']);
      semantics.dispose();
    });

    testWidgets('English: "<Name> back on the list"', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpList(tester, flag: true, locale: const Locale('en'));
      await tick(tester, 'Bohnen');
      tester.takeAnnouncements();
      await tester.tap(usedRow('Bohnen'));
      await tester.pumpAndSettle();
      expect(tester.takeAnnouncements(), [
        isAccessibilityAnnouncement('Bohnen back on the list'),
      ]);
      semantics.dispose();
    });
  });
}

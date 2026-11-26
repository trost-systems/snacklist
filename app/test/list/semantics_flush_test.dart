import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_repository.dart';
import 'memory_cache.dart';

/// A smoke test, not a regression test: the PostHog `TypeError` in
/// `_RenderObjectSemantics._updateSemanticsNodeGeometry` has no known
/// trigger (docs/done/438.md). It runs the list's motions with semantics
/// on, so a flush that throws fails here.
void main() {
  Future<void> pumpList(WidgetTester tester, Size size) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = size;
    addTearDown(tester.view.reset);
    final repo = FakeRepository()
      ..remoteAdd('Äpfel', storeId: 'lidl', categoryId: 'produce')
      ..remoteAdd('Joghurt', storeId: 'lidl', categoryId: 'chilled')
      ..remoteAdd('Seife', storeId: 'dm', categoryId: 'other');
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: MultiBlocProvider(
          providers: [
            BlocProvider(
              create: (_) =>
                  Flags(forced: {addFeedbackListFlag, inputStableRowsFlag}),
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

  Future<void> frames(WidgetTester tester, {int ms = 600}) async {
    for (var t = 0; t < ms; t += 16) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
  }

  for (final (name, size) in [
    ('phone', const Size(390, 844)),
    ('wide, in columns', const Size(1400, 900)),
  ]) {
    testWidgets('add sheet open, add, close and a scroll flush semantics '
        'every frame ($name)', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpList(tester, size);
      final field = find.byKey(const ValueKey('add-item-field'));
      await tester.tap(field);
      await frames(tester);
      await tester.enterText(field, 'Milch');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('suggestion-milch||')));
      await frames(tester);
      await tester.tap(find.byKey(const ValueKey('add-sheet-close')));
      await frames(tester);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
      await frames(tester);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }
}

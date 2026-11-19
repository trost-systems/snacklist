import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/shell/shell.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../list/fake_repository.dart';
import '../list/memory_cache.dart';

/// What the shell and the List tab promise each other through [SheetOpen]:
/// the tab says when its add sheet opens and closes, so the shell can hide
/// its tabs; the shell closing it (leaving the tab) closes the sheet.
/// `AppShell` itself builds the Supabase list scope, so it is not pumped.
void main() {
  late SheetOpenNotifier sheetOpen;

  Future<void> pumpTab(WidgetTester tester, {bool show = true}) async {
    tester.view
      ..devicePixelRatio = 3
      ..physicalSize = const Size(390 * 3, 844 * 3);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: SheetOpen(
          notifier: sheetOpen,
          child: show
              ? BlocProvider(
                  create: (_) => ListCubit(
                    FakeRepository(),
                    MemoryListCache(),
                    userId: 'peter',
                  )..start(),
                  child: const ShoppingList(),
                )
              : const SizedBox(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder sheet() => find.byKey(const ValueKey('add-sheet'));

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('add-item-field')));
    await tester.pumpAndSettle();
  }

  setUp(() => sheetOpen = SheetOpenNotifier());
  tearDown(() => sheetOpen.dispose());

  testWidgets('the shell hears the sheet open and close', (tester) async {
    await pumpTab(tester);
    for (final (how, close) in <(String, Future<void> Function())>[
      ('scrim', () => tester.tapAt(const Offset(195, 120))),
      (
        'Schließen',
        () => tester.tap(find.byKey(const ValueKey('add-sheet-close'))),
      ),
      ('Escape', () => tester.sendKeyEvent(LogicalKeyboardKey.escape)),
    ]) {
      await open(tester);
      expect(sheetOpen.value, isTrue, reason: 'open before $how');
      await close();
      await tester.pumpAndSettle();
      expect(sheetOpen.value, isFalse, reason: 'closed by $how');
      expect(sheet(), findsNothing);
    }
  });

  testWidgets('typing opens the sheet for the shell too', (tester) async {
    await pumpTab(tester);
    await tester.showKeyboard(find.byKey(const ValueKey('add-item-field')));
    expect(sheetOpen.value, isFalse, reason: 'focus alone does not open it');
    tester.testTextInput.enterText('Milch');
    await tester.pumpAndSettle();
    expect(sheetOpen.value, isTrue);
  });

  testWidgets('leaving the tab closes the sheet', (tester) async {
    await pumpTab(tester);
    await open(tester);
    expect(sheet(), findsOneWidget);
    sheetOpen.value = false;
    await tester.pumpAndSettle();
    expect(sheet(), findsNothing);
  });

  testWidgets('a tab that goes away while open gives the tabs back', (
    tester,
  ) async {
    await pumpTab(tester);
    await open(tester);
    expect(sheetOpen.value, isTrue);
    await pumpTab(tester, show: false);
    await tester.pump();
    expect(sheetOpen.value, isFalse);
  });
}

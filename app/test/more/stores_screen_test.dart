import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/more/stores_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../list/fake_repository.dart';
import '../list/memory_cache.dart';

void main() {
  late FakeRepository repo;
  late ListCubit cubit;
  Finder key(String k) => find.byKey(ValueKey(k));

  Future<void> pump(
    WidgetTester tester, {
    void Function(FakeRepository repo)? seed,
    Locale locale = const Locale('de'),
  }) async {
    repo = FakeRepository();
    seed?.call(repo);
    tester.view
      ..physicalSize = const Size(358, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: BlocProvider(
          create: (_) =>
              cubit = ListCubit(repo, MemoryListCache(), userId: 'peter')
                ..start(),
          child: const StoresScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<String> names() => [for (final s in cubit.state.catalog.stores) s.name];

  testWidgets('+ Neuer Laden adds a store below the others', (tester) async {
    await pump(tester);
    await tester.tap(key('store-option-new'));
    await tester.pumpAndSettle();
    await tester.enterText(key('store-new-field'), 'Rewe');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(names(), ['dm', 'Lidl', 'Rewe']);
    expect(key('store-new-field'), findsNothing);
    expect(key('store-row-new-Rewe'), findsOneWidget);
    expect(tester.takeAnnouncements(), [
      isAccessibilityAnnouncement('Rewe angelegt'),
    ]);
  });

  testWidgets('a name the household has adds nothing', (tester) async {
    await pump(tester);
    await tester.tap(key('store-option-new'));
    await tester.pumpAndSettle();
    await tester.enterText(key('store-new-field'), 'LIDL');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(names(), ['dm', 'Lidl']);
    expect(repo.catalogCalls, isEmpty);
  });

  testWidgets('a store is renamed in its row', (tester) async {
    await pump(tester);
    await tester.tap(key('store-menu-dm'));
    await tester.pumpAndSettle();
    await tester.tap(key('store-rename-dm'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(key('store-rename-field'));
    expect(field.controller!.text, 'dm');
    expect(field.focusNode!.hasFocus, isTrue);
    await tester.enterText(key('store-rename-field'), 'Rossmann');
    await tester.pump();
    await tester.tap(key('store-rename-confirm'));
    await tester.pumpAndSettle();
    expect(names(), ['Rossmann', 'Lidl']);
    expect(repo.catalogCalls, ['renameStore(dm, Rossmann)']);
    expect(find.text('Rossmann'), findsOneWidget);
  });

  testWidgets("a rename onto another store's name keeps the field", (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(key('store-menu-dm'));
    await tester.pumpAndSettle();
    await tester.tap(key('store-rename-dm'));
    await tester.pumpAndSettle();
    await tester.enterText(key('store-rename-field'), 'lidl');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(key('store-rename-field'), findsOneWidget);
    expect(names(), ['dm', 'Lidl']);
    await tester.tap(key('store-rename-cancel'));
    await tester.pumpAndSettle();
    expect(key('store-rename-field'), findsNothing);
  });

  testWidgets('delete says how many open items lose their store, then they '
      'have none', (tester) async {
    late Item milk;
    await pump(
      tester,
      seed: (repo) {
        milk = repo.remoteAdd('Milch', storeId: 'lidl');
        repo.remoteAdd('Käse', storeId: 'lidl');
      },
    );
    await tester.tap(key('store-menu-lidl'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Lidl löschen'), findsOneWidget);
    await tester.tap(key('store-delete-lidl'));
    await tester.pumpAndSettle();
    expect(find.text('Lidl löschen?'), findsOneWidget);
    expect(
      find.text(
        '2 offene Artikel kommen zu „Ohne Laden“. Sein Laufweg geht mit.',
      ),
      findsOneWidget,
    );
    await tester.tap(key('store-delete-confirm'));
    await tester.pumpAndSettle();
    expect(names(), ['dm']);
    expect(cubit.state.items[milk.id]!.storeId, isNull);
    expect(key('store-row-lidl'), findsNothing);
  });

  testWidgets('cancelling the delete keeps the store', (tester) async {
    await pump(tester);
    await tester.tap(key('store-menu-dm'));
    await tester.pumpAndSettle();
    await tester.tap(key('store-delete-dm'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'In diesem Laden sind keine offenen Artikel. Sein Laufweg geht mit.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(names(), ['dm', 'Lidl']);
    expect(repo.catalogCalls, isEmpty);
  });

  testWidgets('a household without stores sees why and can add one', (
    tester,
  ) async {
    await pump(tester, seed: (repo) => repo.stores = const []);
    expect(key('stores-empty'), findsOneWidget);
    expect(find.textContaining('Noch keine Läden.'), findsOneWidget);
    await tester.tap(key('store-option-new'));
    await tester.pumpAndSettle();
    await tester.enterText(key('store-new-field'), 'Rewe');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(names(), ['Rewe']);
    expect(key('stores-empty'), findsNothing);
  });

  testWidgets('in English', (tester) async {
    await pump(tester, locale: const Locale('en'));
    expect(find.text('Stores'), findsOneWidget);
    expect(find.text('New store'), findsOneWidget);
    expect(find.bySemanticsLabel('Add a new store'), findsOneWidget);
    expect(find.byTooltip('Options for Lidl'), findsOneWidget);
  });
}

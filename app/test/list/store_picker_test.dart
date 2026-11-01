import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/foldout_chips.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The store options of the add and edit sheets (FoldoutChips): search,
/// "+ Neuer Laden" and its field.
void main() {
  Finder key(String k) => find.byKey(ValueKey(k));

  List<Store> stores(List<String> names) => [
    for (final (i, n) in names.indexed)
      Store(id: n.toLowerCase(), name: n, sortOrder: (i + 1) * 10),
  ];

  late List<String?> picked;
  late List<String> created;

  /// [create] answers the cubit's addStore; by default a new store.
  Future<void> pump(
    WidgetTester tester, {
    List<String> names = const ['dm', 'Lidl', 'Edeka'],
    Future<Store?> Function(String name)? create,
    Locale locale = const Locale('de'),
  }) async {
    picked = [];
    created = [];
    tester.view
      ..physicalSize = const Size(358, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var catalog = Catalog(stores: stores(names));
    String? storeId;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => FoldoutChips(
              catalog: catalog,
              storeId: storeId,
              categoryId: null,
              storeLabel: AppLocalizations.of(context).noStore,
              categoryLabel: 'x',
              onCategory: (_) {},
              onStore: (id) => setState(() {
                picked.add(id);
                storeId = id;
              }),
              onCreateStore: (name) async {
                created.add(name);
                final store =
                    await (create?.call(name) ??
                        Future.value(
                          Store(id: 'new', name: name.trim(), sortOrder: 99),
                        ));
                if (store != null) {
                  setState(() => catalog = catalog.withStore(store));
                }
                return store;
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(key('chip-store'));
    await tester.pumpAndSettle();
  }

  Future<void> openField(WidgetTester tester) async {
    await tester.tap(key('store-option-new'));
    await tester.pumpAndSettle();
  }

  Finder inChip(String text) =>
      find.descendant(of: key('chip-store'), matching: find.text(text));

  testWidgets('+ Neuer Laden opens a focused field; confirming creates the '
      'store and picks it', (tester) async {
    await pump(tester);
    expect(key('store-search'), findsNothing, reason: 'only three stores');
    expect(find.text('Neuer Laden'), findsOneWidget);
    await openField(tester);
    expect(key('store-option-new'), findsNothing, reason: 'the row became it');
    final field = tester.widget<TextField>(key('store-new-field'));
    expect(field.focusNode!.hasFocus, isTrue);
    await tester.enterText(key('store-new-field'), 'Rewe');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(created, ['Rewe']);
    expect(picked, ['new']);
    expect(inChip('Rewe'), findsOneWidget);
    expect(key('store-new-field'), findsNothing, reason: 'folded back');
    expect(tester.takeAnnouncements(), [
      isAccessibilityAnnouncement('Rewe angelegt und ausgewählt'),
    ]);
  });

  testWidgets('the check button confirms too; empty names cannot', (
    tester,
  ) async {
    await pump(tester);
    await openField(tester);
    expect(
      tester.widget<IconButton>(key('store-new-confirm')).onPressed,
      isNull,
    );
    await tester.enterText(key('store-new-field'), '   ');
    await tester.pump();
    expect(
      tester.widget<IconButton>(key('store-new-confirm')).onPressed,
      isNull,
    );
    await tester.enterText(key('store-new-field'), 'Aldi Süd');
    await tester.pump();
    await tester.tap(key('store-new-confirm'));
    await tester.pumpAndSettle();
    expect(created, ['Aldi Süd']);
    expect(inChip('Aldi Süd'), findsOneWidget);
  });

  testWidgets('a name the household has picks that store, nothing is made', (
    tester,
  ) async {
    await pump(tester);
    await openField(tester);
    await tester.enterText(key('store-new-field'), '  LIDL ');
    await tester.pump();
    await tester.tap(key('store-new-confirm'));
    await tester.pumpAndSettle();
    expect(created, isEmpty);
    expect(picked, ['lidl']);
    expect(tester.takeAnnouncements(), isEmpty);
  });

  testWidgets('Escape and the close button cancel; focus goes back to the '
      'row', (tester) async {
    await pump(tester);
    await openField(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(key('store-new-field'), findsNothing);
    expect(key('store-option-new'), findsOneWidget);
    expect(
      Focus.of(
        tester.element(
          find.descendant(
            of: key('store-option-new'),
            matching: find.text('Neuer Laden'),
          ),
        ),
      ).hasFocus,
      isTrue,
    );
    await openField(tester);
    await tester.tap(key('store-new-cancel'));
    await tester.pumpAndSettle();
    expect(key('store-new-field'), findsNothing);
    expect(created, isEmpty);
    expect(picked, isEmpty);
  });

  testWidgets('a store that could not be made keeps the field and its name', (
    tester,
  ) async {
    await pump(tester, create: (_) async => null);
    await openField(tester);
    await tester.enterText(key('store-new-field'), 'Rewe');
    await tester.pump();
    await tester.tap(key('store-new-confirm'));
    await tester.pumpAndSettle();
    expect(created, ['Rewe']);
    expect(picked, isEmpty);
    expect(
      tester.widget<TextField>(key('store-new-field')).controller!.text,
      'Rewe',
    );
  });

  group('over five stores', () {
    const six = ['dm', 'Lidl', 'Edeka', 'Rewe', 'Aldi', 'Netto'];

    testWidgets('the search field filters the stores', (tester) async {
      await pump(tester, names: six);
      expect(key('store-search'), findsOneWidget);
      await tester.enterText(key('store-search'), 'e');
      await tester.pump();
      for (final id in ['edeka', 'rewe', 'netto']) {
        expect(key('store-option-$id'), findsOneWidget, reason: id);
      }
      for (final id in ['dm', 'lidl', 'aldi']) {
        expect(key('store-option-$id'), findsNothing, reason: id);
      }
      expect(key('store-option-none'), findsNothing);
      expect(key('store-option-new'), findsOneWidget);
    });

    testWidgets('Enter on a name the household has picks it', (tester) async {
      await pump(tester, names: six);
      await tester.enterText(key('store-search'), 'netto ');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(picked, ['netto']);
    });

    testWidgets('Enter on a new name opens the field with it; confirming '
        'makes it', (tester) async {
      await pump(tester, names: six);
      await tester.enterText(key('store-search'), 'Penny');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(key('store-new-field'));
      expect(field.controller!.text, 'Penny');
      expect(field.focusNode!.hasFocus, isTrue, reason: 'from the search');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(created, ['Penny']);
      expect(inChip('Penny'), findsOneWidget);
    });

    testWidgets('+ Neuer Laden takes the search text along', (tester) async {
      await pump(tester, names: six);
      await tester.enterText(key('store-search'), 'Kaufland');
      await tester.pump();
      await openField(tester);
      expect(
        tester.widget<TextField>(key('store-new-field')).controller!.text,
        'Kaufland',
      );
    });
  });

  testWidgets('in English', (tester) async {
    await pump(tester, locale: const Locale('en'));
    expect(find.text('No store'), findsWidgets);
    expect(find.text('New store'), findsOneWidget);
    expect(find.bySemanticsLabel('Add a new store'), findsOneWidget);
    await openField(tester);
    expect(find.text('Store name'), findsOneWidget);
    expect(find.byTooltip('Add store'), findsOneWidget);
    await tester.enterText(key('store-new-field'), 'Rewe');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(tester.takeAnnouncements(), [
      isAccessibilityAnnouncement('Rewe added and selected'),
    ]);
  });
}

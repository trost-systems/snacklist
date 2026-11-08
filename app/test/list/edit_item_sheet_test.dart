import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/edit_item_sheet.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const catalog = Catalog(
    categories: [
      Category(id: 'chilled', name: 'Kühlregal', sortOrder: 30),
      Category(id: 'other', name: 'Sonstiges', sortOrder: 1000),
    ],
    stores: [
      Store(id: 'edeka', name: 'Edeka', sortOrder: 10, seedKey: 'edeka'),
      Store(id: 'dm', name: 'dm-Markt', sortOrder: 20, seedKey: 'dm'),
    ],
  );
  final milk = Item(
    id: 'milk',
    name: 'Milch',
    quantity: '2',
    brand: 'Weihenstephan',
    properties: '1,5 %, 1 l',
    categoryId: 'chilled',
    storeId: 'edeka',
    status: ItemStatus.active,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );

  Finder key(String k) => find.byKey(ValueKey(k));
  String text(WidgetTester tester, String k) =>
      tester.widget<TextField>(key(k)).controller!.text;

  /// Opens the sheet for [item], lets [act] work on it, and returns what
  /// the sheet answered once it closed. Without [act] it stays open.
  Future<ItemChanges?> run(
    WidgetTester tester,
    Future<void> Function()? act, {
    Item? item,
    Size size = const Size(400, 900),
    Future<Store?> Function(String name)? onCreateStore,
  }) async {
    ItemChanges? result;
    var closed = false;
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  final edit = await showEditItemSheet(
                    context,
                    item: item ?? milk,
                    catalog: catalog,
                    onCreateStore:
                        onCreateStore ??
                        (name) async =>
                            Store(id: 'new', name: name, sortOrder: 30),
                  );
                  result = edit?.changes;
                  closed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    if (act == null) {
      return null;
    }
    await act();
    await tester.pumpAndSettle();
    expect(closed, isTrue, reason: 'the sheet closed');
    expect(key('edit-sheet'), findsNothing);
    return result;
  }

  /// Opens the sheet for [item]; [run] also closes it.
  Future<void> open(
    WidgetTester tester,
    Item item, {
    Size size = const Size(400, 900),
  }) => run(tester, item: item, size: size, null);

  testWidgets('the fields come prefilled', (tester) async {
    await open(tester, milk);
    expect(text(tester, 'edit-name'), 'Milch');
    expect(text(tester, 'edit-brand'), 'Weihenstephan');
    expect(text(tester, 'edit-quantity'), '2');
    expect(text(tester, 'edit-properties'), '1,5 %, 1 l');
    expect(
      find.descendant(of: key('chip-store'), matching: find.text('Edeka')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: key('chip-category'),
        matching: find.text('Kühlregal'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('only the changed fields are saved', (tester) async {
    final result = await run(tester, () async {
      await tester.enterText(key('edit-brand'), '  Berchtesgadener  ');
      await tester.tap(key('edit-quantity-plus'));
      await tester.pump();
      expect(text(tester, 'edit-quantity'), '3');
      await tester.tap(key('edit-done'));
    });
    expect(result!.toColumns(), {'brand': 'Berchtesgadener', 'quantity': '3'});
  });

  testWidgets('emptied fields are saved as null', (tester) async {
    final result = await run(tester, () async {
      await tester.enterText(key('edit-brand'), ' ');
      await tester.enterText(key('edit-properties'), '');
      await tester.enterText(key('edit-quantity'), '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
    });
    expect(result!.toColumns(), {
      'brand': null,
      'properties': null,
      'quantity': null,
    });
  });

  testWidgets('Fertig without a change, or Abbrechen, saves nothing', (
    tester,
  ) async {
    expect(
      await run(tester, () async {
        await tester.enterText(key('edit-name'), ' Milch ');
        await tester.tap(key('edit-done'));
      }),
      isNull,
    );
    expect(
      await run(tester, () async {
        await tester.enterText(key('edit-name'), 'Hafermilch');
        await tester.tap(key('edit-cancel'));
      }),
      isNull,
    );
  });

  testWidgets('Abbrechen throws away every edit', (tester) async {
    final result = await run(tester, () async {
      await tester.enterText(key('edit-name'), 'Hafermilch');
      await tester.enterText(key('edit-brand'), 'Oatly');
      await tester.tap(key('edit-quantity-plus'));
      await tester.enterText(key('edit-properties'), 'Barista');
      await tester.tap(key('chip-store'));
      await tester.pumpAndSettle();
      await tester.tap(key('store-option-dm'));
      await tester.pumpAndSettle();
      await tester.tap(key('chip-category'));
      await tester.pumpAndSettle();
      await tester.tap(key('category-option-other'));
      await tester.pumpAndSettle();
      await tester.tap(key('edit-cancel'));
    });
    expect(result, isNull, reason: 'no change reaches the list');
  });

  testWidgets('no title, no hint, no Löschen: Abbrechen sits left of '
      'Fertig under the chips', (tester) async {
    await open(tester, milk);
    expect(find.textContaining('Bearbeiten'), findsNothing);
    expect(find.text('Löschen'), findsNothing);
    expect(find.textContaining('Gespeichert'), findsNothing);
    expect(
      find.descendant(of: key('edit-cancel'), matching: find.text('Abbrechen')),
      findsOneWidget,
    );
    expect(find.text('Abbrechen'), findsOneWidget, reason: 'one Abbrechen');
    final cancel = tester.getRect(key('edit-cancel'));
    final done = tester.getRect(key('edit-done'));
    expect(cancel.center.dy, done.center.dy);
    expect(cancel.right, lessThan(done.left));
    expect(cancel.top, greaterThan(tester.getRect(key('chip-store')).bottom));
  });

  testWidgets('the chips name store and category without icons; the '
      'options keep theirs', (tester) async {
    await open(tester, milk);
    for (final chip in ['chip-store', 'chip-category']) {
      expect(
        find.descendant(of: key(chip), matching: find.byType(Icon)),
        findsOneWidget,
        reason: '$chip shows only its fold-out arrow',
      );
      expect(
        find.descendant(
          of: key(chip),
          matching: find.byIcon(Icons.arrow_drop_down),
        ),
        findsOneWidget,
      );
    }
    await tester.tap(key('chip-store'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: key('store-option-none'),
        matching: find.byIcon(Icons.storefront_outlined),
      ),
      findsOneWidget,
    );
  });

  testWidgets('an empty name disables Fertig, Enter included', (tester) async {
    await open(tester, milk);
    await tester.enterText(key('edit-name'), '   ');
    await tester.pump();
    final done = tester.widget<FilledButton>(key('edit-done'));
    expect(done.onPressed, isNull);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(key('edit-sheet'), findsOneWidget, reason: 'still open');
  });

  testWidgets('the chips fold out, pick, and fold back', (tester) async {
    final result = await run(tester, () async {
      expect(key('store-option-dm'), findsNothing);
      await tester.tap(key('chip-store'));
      await tester.pumpAndSettle();
      expect(key('store-option-none'), findsOneWidget);
      expect(key('store-option-edeka'), findsOneWidget);
      await tester.tap(key('store-option-dm'));
      await tester.pumpAndSettle();
      expect(key('store-option-dm'), findsNothing, reason: 'folded back');
      expect(
        find.descendant(of: key('chip-store'), matching: find.text('dm-Markt')),
        findsOneWidget,
      );

      await tester.tap(key('chip-category'));
      await tester.pumpAndSettle();
      expect(key('store-option-dm'), findsNothing);
      await tester.tap(key('category-option-other'));
      await tester.pumpAndSettle();
      expect(key('category-option-other'), findsNothing);
      await tester.tap(key('edit-done'));
    });
    expect(result!.toColumns(), {'store_id': 'dm', 'category_id': 'other'});
  });

  testWidgets('a store made in the sheet is picked and saved', (tester) async {
    final made = <String>[];
    final result = await run(
      tester,
      () async {
        await tester.tap(key('chip-store'));
        await tester.pumpAndSettle();
        await tester.tap(key('store-option-new'));
        await tester.pumpAndSettle();
        await tester.enterText(key('store-new-field'), 'Rewe');
        await tester.pump();
        await tester.tap(key('store-new-confirm'));
        await tester.pumpAndSettle();
        expect(key('store-new-field'), findsNothing, reason: 'folded back');
        expect(
          find.descendant(of: key('chip-store'), matching: find.text('Rewe')),
          findsOneWidget,
        );
        await tester.tap(key('edit-done'));
      },
      onCreateStore: (name) async {
        made.add(name);
        return Store(id: 'rewe', name: name, sortOrder: 30);
      },
    );
    expect(made, ['Rewe']);
    expect(result!.toColumns(), {'store_id': 'rewe'});
  });

  testWidgets('Ohne Laden clears the store', (tester) async {
    final result = await run(tester, () async {
      await tester.tap(key('chip-store'));
      await tester.pumpAndSettle();
      await tester.tap(key('store-option-none'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: key('chip-store'),
          matching: find.text('Ohne Laden'),
        ),
        findsOneWidget,
      );
      await tester.tap(key('edit-done'));
    });
    expect(result!.toColumns(), {'store_id': null});
  });

  testWidgets('a Menge without a number has no steppers', (tester) async {
    await open(tester, milk.copyWith(quantity: () => 'eine Packung'));
    expect(key('edit-quantity-plus'), findsNothing);
    await tester.enterText(key('edit-quantity'), '1');
    await tester.pump();
    expect(key('edit-quantity-plus'), findsOneWidget);
    expect(
      tester
          .widget<ButtonStyleButton>(
            find.descendant(
              of: key('edit-quantity-minus'),
              matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
            ),
          )
          .enabled,
      isFalse,
      reason: 'below 1',
    );
  });

  testWidgets('the steppers are buttons named for what they do', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await open(tester, milk);
    for (final name in ['Eins mehr', 'Eins weniger']) {
      expect(
        find.semantics.byPredicate(
          (node) => node.label == name && node.flagsCollection.isButton,
        ),
        findsOne,
        reason: name,
      );
    }
    handle.dispose();
  });

  testWidgets('the sheet is as tall as its content', (tester) async {
    await open(tester, milk);
    final sheet = tester.getRect(find.byType(BottomSheet));
    final content = tester.getRect(key('edit-sheet'));
    expect(content.height, sheet.height);
    expect(sheet.bottom, 900);
    expect(sheet.height, lessThan(700), reason: 'not a fixed fraction');

    await tester.tap(key('chip-category'));
    await tester.pumpAndSettle();
    final unfolded = tester.getRect(find.byType(BottomSheet));
    expect(unfolded.height, greaterThan(sheet.height));
    expect(tester.getRect(key('edit-sheet')).height, unfolded.height);
  });

  testWidgets('with the keyboard up the sheet sits above it and scrolls', (
    tester,
  ) async {
    await open(tester, milk, size: const Size(400, 600));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    final sheet = tester.getRect(find.byType(BottomSheet));
    expect(sheet.bottom, 600);
    final scroll = tester.getRect(find.byType(SingleChildScrollView));
    expect(scroll.bottom, 300, reason: 'above the keyboard');
    expect(tester.takeException(), isNull, reason: 'no overflow');
  });

  // Desktop platforms default to compact density, which shrank the chips to
  // 36 px on the Linux build.
  testWidgets(
    'every control is at least 44 px',
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.linux,
      TargetPlatform.macOS,
    }),
    (tester) async {
      await open(tester, milk);
      await tester.tap(key('chip-store'));
      await tester.pumpAndSettle();
      for (final k in [
        'edit-cancel',
        'edit-quantity-minus',
        'edit-quantity-plus',
        'chip-store',
        'chip-category',
        'store-option-none',
        'store-option-dm',
        'edit-done',
      ]) {
        final size = tester.getSize(key(k));
        expect(size.height, greaterThanOrEqualTo(44), reason: k);
        expect(size.width, greaterThanOrEqualTo(44), reason: k);
      }
      expect(tester.getSize(key('edit-done')).width, greaterThanOrEqualTo(132));
      expect(tester.getSize(key('edit-done')).height, greaterThanOrEqualTo(52));
      expect(tester.getSize(key('edit-name')).height, 48);
    },
  );

  testWidgets('screen readers see the sheet as one labelled group', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await open(tester, milk);
    final node = tester.getSemantics(find.bySemanticsLabel('Bearbeiten'));
    expect(
      node.rect.size,
      tester.getSize(key('edit-sheet')),
      reason: 'the group covers the sheet',
    );
    expect(find.bySemanticsLabel('Marke'), findsOneWidget);
    handle.dispose();
  });

  // Job 122: a tooltip's overlay joins the semantics tree while it shows, and
  // on the web that moves the sheet's DOM: a click into Menge right after
  // hovering a stepper lost its focus.
  testWidgets('hovering a stepper leaves the semantics tree as it is', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await open(tester, milk);
    String tree() => tester
        .getSemantics(find.bySemanticsLabel('Bearbeiten'))
        .toStringDeep()
        .replaceAll(RegExp(r'SemanticsNode#\d+'), 'SemanticsNode');
    final before = tree();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    for (final stepper in ['edit-quantity-plus', 'edit-quantity-minus']) {
      await mouse.moveTo(tester.getCenter(key(stepper)));
      await tester.pumpAndSettle();
      expect(tree(), before, reason: 'hovering $stepper');
    }
    handle.dispose();
  });
}

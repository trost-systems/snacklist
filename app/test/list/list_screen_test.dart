import 'dart:async';

import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/app/theme.dart';
import 'package:family_groceries/design/sticker.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/add_sheet/suggestion.dart';
import 'package:family_groceries/list/list_cache.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_repository.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/list/list_view/dividers.dart';
import 'package:family_groceries/list/list_view/item_icon.dart';
import 'package:family_groceries/list/list_view/item_row.dart';
import 'package:family_groceries/list/list_view/shopping_list_view.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'fake_repository.dart';
import 'memory_cache.dart';

void main() {
  late FakeRepository repo;
  late MemoryListCache cache;

  setUp(
    () => VisibilityDetectorController.instance.updateInterval = Duration.zero,
  );

  /// [keepCache] starts the list again on the same server and device, like
  /// an app restart.
  Future<void> pumpList(
    WidgetTester tester, {
    void Function(FakeRepository repo)? seed,
    bool keepCache = false,
    bool settle = true,
    ThemeData? theme,
  }) async {
    if (!keepCache) {
      repo = FakeRepository();
      cache = MemoryListCache();
    }
    seed?.call(repo);
    final list = BlocProvider(
      key: UniqueKey(),
      create: (_) => ListCubit(repo, cache, userId: 'peter')..start(),
      child: const ShoppingList(),
    );
    await tester.pumpWidget(
      MaterialApp.router(
        theme: theme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        routerConfig: GoRouter(
          routes: [
            GoRoute(
              path: listPath,
              builder: (_, _) => list,
              routes: [
                // Stands in for the store details (job 78), nested under
                // the list as in the app: says where it is.
                GoRoute(
                  path: 'edit/:store',
                  builder: (_, state) => Text(state.uri.path),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump();
    }
  }

  Finder addField() => find.byKey(const ValueKey('add-item-field'));
  FocusNode fieldFocus(WidgetTester tester) =>
      tester.widget<TextField>(addField()).focusNode!;
  Finder sheet() => find.byKey(const ValueKey('add-sheet'));

  /// A sheet row by what a screen reader says for it.
  Finder sheetRow(String label) => find.descendant(
    of: sheet(),
    matching: find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == label,
    ),
  );

  /// A 390x844 phone. The sheet's first height is half the screen, which
  /// on the test's default 800x600 is too short for its chips.
  void phone(WidgetTester tester) {
    tester.view
      ..devicePixelRatio = 3
      ..physicalSize = const Size(390 * 3, 844 * 3);
    addTearDown(tester.view.reset);
  }

  /// Waits out the typing pause and the server's answer.
  Future<void> settleRows(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
  }

  Finder row(String name) =>
      find.byWidgetPredicate((w) => w is ItemRow && w.item.name == name);
  Finder storeDivider(String key) => find.byKey(ValueKey('store-$key'));

  /// The semantics nodes of a row and a store divider.
  Finder rowNode(String name) => find
      .descendant(
        of: row(name),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && (w.properties.button ?? false),
        ),
      )
      .first;
  Finder storeNode(String key) => find.descendant(
    of: storeDivider(key),
    matching: find.byType(StoreDivider),
  );
  Finder categoryDivider(String text) =>
      find.text(text.toUpperCase().replaceAll('ß', 'SS'));
  Item itemNamed(String name) =>
      repo.rows.values.firstWhere((i) => i.name == name);

  /// An item's row under "Zuletzt verwendet", and the list's row inside it.
  Finder usedRow(String name) =>
      find.byKey(ValueKey('used-${itemNamed(name).id}'));
  Finder usedTile(String name) =>
      find.descendant(of: usedRow(name), matching: row(name));

  /// Opens "Zuletzt verwendet" if it is closed and scrolls to [name] there.
  Future<void> showUsed(WidgetTester tester, String name) async {
    final title = find.text('Zuletzt verwendet');
    await tester.ensureVisible(title);
    await tester.pumpAndSettle();
    if (usedRow(name).evaluate().isEmpty) {
      await tester.tap(title);
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(usedRow(name));
    await tester.pumpAndSettle();
  }

  /// Rows top to bottom, then left to right.
  List<String> rowOrder(WidgetTester tester) {
    final rows = tester.widgetList<ItemRow>(find.byType(ItemRow)).toList()
      ..sort((a, b) {
        final pa = tester.getTopLeft(find.byWidget(a));
        final pb = tester.getTopLeft(find.byWidget(b));
        return pa.dx != pb.dx ? pa.dx.compareTo(pb.dx) : pa.dy.compareTo(pb.dy);
      });
    return [for (final r in rows) r.item.name];
  }

  testWidgets('on a phone the add field waits for a tap; an empty list '
      'says so', (tester) async {
    phone(tester);
    await pumpList(tester);
    expect(
      fieldFocus(tester).hasFocus,
      isFalse,
      reason: 'phones get the keyboard only when asked',
    );
    expect(sheet(), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing, reason: 'no store filter');
    expect(
      find.text('Die Liste ist leer. Tippe unten ein, was fehlt.'),
      findsOneWidget,
    );
    expect(find.text('🧺'), findsNothing, reason: 'no emoji as an icon');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('list-empty-mark')),
        matching: find.byIcon(Icons.shopping_cart_outlined),
      ),
      findsOneWidget,
    );
    expect(find.byType(StoreDivider), findsNothing);

    await tester.tap(addField());
    await tester.pumpAndSettle();
    expect(fieldFocus(tester).hasFocus, isTrue);
    expect(sheet(), findsOneWidget, reason: 'a tap opens the add sheet');
    expect(find.text('Was brauchst du?'), findsOneWidget);
  });

  testWidgets('a category divider is its own node, outside the rows', (
    tester,
  ) async {
    phone(tester);
    await pumpList(tester);
    await tester.enterText(addField(), 'Vollmilch');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-sheet-close')));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(categoryDivider('Kühlregal')),
      isSemantics(label: 'Kühlregal', isHeader: true),
    );
    expect(
      tester.getSemantics(rowNode('Vollmilch')),
      isSemantics(
        label: 'Vollmilch',
        isButton: true,
        hasTapAction: true,
        hasLongPressAction: true,
      ),
    );
  });

  testWidgets('enter adds under its category and keeps focus', (tester) async {
    phone(tester);
    await pumpList(tester);
    await tester.enterText(addField(), 'Vollmilch');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();

    expect(categoryDivider('Kühlregal'), findsOneWidget);
    expect(row('Vollmilch'), findsOneWidget);
    expect(tester.widget<TextField>(addField()).focusNode!.hasFocus, isTrue);
    expect(tester.widget<TextField>(addField()).controller!.text, isEmpty);
  });

  testWidgets('hardware enter adds once per press and keeps focus', (
    tester,
  ) async {
    phone(tester);
    await pumpList(tester);
    for (final name in ['Milch', 'Brot']) {
      await tester.enterText(addField(), name);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
    }
    expect(repo.rows.values.map((i) => i.name), ['Milch', 'Brot']);
    expect(tester.widget<TextField>(addField()).focusNode!.hasFocus, isTrue);
  });

  testWidgets('after a household switch under the open tabs, an add goes to '
      'the new household', (tester) async {
    phone(tester);
    final left = FakeRepository();
    final joined = FakeRepository();
    final first = ListCubit(left, MemoryListCache(), userId: 'peter')..start();
    final second = ListCubit(joined, MemoryListCache(), userId: 'peter')
      ..start();
    final current = ValueNotifier(first);
    addTearDown(current.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: ValueListenableBuilder(
          valueListenable: current,
          builder: (_, cubit, child) =>
              BlocProvider.value(value: cubit, child: child),
          child: const ShoppingList(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    current.value = second;
    await tester.pumpAndSettle();
    await tester.tap(addField());
    await tester.enterText(addField(), 'Brot');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect([for (final i in joined.rows.values) i.name], ['Brot']);
    expect(left.rows, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await first.close();
    await second.close();
  });

  testWidgets('a long paste is capped at the server limit', (tester) async {
    phone(tester);
    await pumpList(tester);
    await tester.enterText(addField(), 'x' * 130);
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(repo.rows.values.single.name, hasLength(120));
  });

  testWidgets('stores are sections in household order, then no store; '
      'each category one block in walk order', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpList(
      tester,
      seed: (repo) => repo
        ..remoteAdd('Äpfel', categoryId: 'produce', storeId: 'lidl')
        ..remoteAdd('Milch', storeId: 'lidl')
        ..remoteAdd('Seife', storeId: 'dm')
        ..remoteAdd('Brot')
        ..remoteAdd('Joghurt', categoryId: 'chilled', storeId: 'lidl'),
    );
    final dm = tester.getTopLeft(storeDivider('dm')).dy;
    final lidl = tester.getTopLeft(storeDivider('lidl')).dy;
    final none = tester.getTopLeft(storeDivider('none')).dy;
    expect(dm < lidl && lidl < none, isTrue, reason: 'dm, Lidl, Ohne Laden');
    // Lidl walks chilled before produce.
    expect(rowOrder(tester), ['Seife', 'Milch', 'Joghurt', 'Äpfel', 'Brot']);
    expect(categoryDivider('Kühlregal'), findsOneWidget);
    expect(
      tester.getSemantics(storeNode('lidl')),
      isSemantics(
        label: 'Lidl, 3 Artikel',
        hint: 'Zuklappen',
        isButton: true,
        hasExpandedState: true,
        isExpanded: true,
      ),
    );
    expect(find.text('Ohne Laden'), findsOneWidget);
  });

  testWidgets('a tap ticks without a snackbar; a tap on it under "Zuletzt '
      'verwendet" puts it back in its place', (tester) async {
    await pumpList(
      tester,
      seed: (repo) => repo
        ..remoteAdd('Erbsen', categoryId: 'produce')
        ..remoteAdd('Bohnen', categoryId: 'produce')
        ..remoteAdd('Linsen', categoryId: 'produce'),
    );
    await tester.tap(row('Bohnen'));
    await tester.pump();
    expect(row('Bohnen'), findsOneWidget, reason: 'it leaves first');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Rückgängig'), findsNothing);
    expect(row('Bohnen'), findsNothing);
    expect(itemNamed('Bohnen').status, ItemStatus.bought);

    await showUsed(tester, 'Bohnen');
    await tester.tap(usedRow('Bohnen'));
    await tester.pumpAndSettle();
    expect(itemNamed('Bohnen').status, ItemStatus.active);
    expect(rowOrder(tester), ['Erbsen', 'Bohnen', 'Linsen']);
    expect(find.text('Zuletzt verwendet'), findsNothing, reason: 'none left');
    expect(find.byType(SnackBar), findsNothing, reason: 'it is back in place');
  });

  testWidgets('the last row of a category takes its divider along as it '
      'closes; put back, the divider is whole again', (tester) async {
    await pumpList(
      tester,
      seed: (repo) => repo
        ..remoteAdd('Erbsen', categoryId: 'produce')
        ..remoteAdd('Milch', categoryId: 'chilled'),
    );
    Finder chilled() => find.byWidgetPredicate(
      (w) => w is CategoryDivider && w.block.category?.id == 'chilled',
    );
    final full = tester.getSize(chilled()).height;
    await tester.tap(row('Milch'));
    await tester.pump();
    await tester.pump(HlDuration.short);
    expect(
      tester.getSize(chilled()).height,
      full,
      reason: 'drawn, not closing',
    );
    await tester.pump(HlDuration.medium ~/ 2);
    expect(
      tester.getSize(chilled()).height,
      inExclusiveRange(0, full),
      reason: 'closing with its row',
    );
    await tester.pumpAndSettle();
    expect(chilled(), findsNothing);

    await showUsed(tester, 'Milch');
    await tester.tap(usedRow('Milch'));
    await tester.pumpAndSettle();
    expect(tester.getSize(chilled()).height, full);
  });

  testWidgets('"Zuletzt verwendet" shows the list\'s own row with its icon, '
      'faded, most recent first', (tester) async {
    await pumpList(
      tester,
      seed: (repo) => repo
        ..remoteAdd('Bananen', categoryId: 'produce', quantity: '6')
        ..remoteAdd('Brot', categoryId: 'bakery'),
    );
    final listed = tester.widget<ItemRow>(row('Bananen'));
    final icon = ItemIcons.bundled.emojiFor(listed.item.name)!;
    for (final name in ['Bananen', 'Brot']) {
      await tester.tap(row(name));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    }
    expect(find.text('Zuletzt gekauft'), findsNothing);
    await showUsed(tester, 'Bananen');

    final used = tester.widget<ItemRow>(usedTile('Bananen'));
    expect(used.category?.id, 'produce');
    expect(used.fresh, isFalse);
    expect(
      find.descendant(of: usedTile('Bananen'), matching: find.text(icon)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: usedRow('Bananen'),
        matching: find.byWidgetPredicate((w) => w is Opacity && w.opacity < 1),
      ),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(usedRow('Brot')).dy,
      lessThan(tester.getTopLeft(usedRow('Bananen')).dy),
      reason: 'the last tick first',
    );
  });

  testWidgets('a used row only puts back: a sideways drag or right click '
      'does nothing, a hold puts it back too', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpList(tester, seed: (repo) => repo.remoteAdd('Brot'));
    await tester.tap(row('Brot'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await showUsed(tester, 'Brot');

    await tester.drag(usedRow('Brot'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    await tester.tap(usedRow('Brot'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('edit-sheet')), findsNothing);
    expect(itemNamed('Brot').status, ItemStatus.bought);
    expect(repo.rows, hasLength(1));

    expect(
      tester.getSemantics(usedRow('Brot')),
      isSemantics(
        label: 'Brot\nWieder auf die Liste',
        isButton: true,
        hasTapAction: true,
      ),
    );
    expect(find.semantics.byLabel('Brot'), findsNothing);
    tester.semantics.tap(find.semantics.byLabel('Brot\nWieder auf die Liste'));
    await tester.pumpAndSettle();
    expect(itemNamed('Brot').status, ItemStatus.active);
    expect(row('Brot'), findsOneWidget);

    await tester.tap(row('Brot'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await showUsed(tester, 'Brot');
    await tester.longPress(usedRow('Brot'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('edit-sheet')), findsNothing);
    expect(itemNamed('Brot').status, ItemStatus.active);
    handle.dispose();
  });

  testWidgets('with animations off a tap shows the struck row, then ticks '
      'without a close', (tester) async {
    await pumpList(tester, seed: (repo) => repo.remoteAdd('Brot'));
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    await tester.pump();
    await tester.tap(row('Brot'));
    await tester.pump();
    expect(itemNamed('Brot').status, ItemStatus.active, reason: 'seen first');
    await tester.pump(HlDuration.medium);
    expect(itemNamed('Brot').status, ItemStatus.bought);
    expect(tester.hasRunningAnimations, isFalse);
    tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
    await tester.pumpAndSettle();
  });

  Finder editSheet() => find.byKey(const ValueKey('edit-sheet'));
  Finder editing(String name) => find.byWidgetPredicate(
    (w) =>
        w is TextField &&
        w.key == const ValueKey('edit-name') &&
        w.controller?.text == name,
  );

  testWidgets('a sideways drag across a row opens nothing, ticks nothing '
      'and moves nothing; an upward one scrolls', (tester) async {
    phone(tester);
    await pumpList(
      tester,
      seed: (repo) {
        for (var i = 0; i < 30; i++) {
          repo.remoteAdd('Artikel $i', categoryId: 'produce');
        }
      },
    );
    final order = rowOrder(tester);
    final before = tester.getRect(row('Artikel 0'));
    final name = tester.getRect(find.text('Artikel 0'));
    for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
      for (final dx in [-200.0, 200.0]) {
        final from = tester.getCenter(row('Artikel 0'));
        final finger = await tester.startGesture(from, kind: kind);
        for (var step = 1; step <= 4; step++) {
          await finger.moveTo(from + Offset(dx * step / 4, 0));
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(
          tester.getRect(find.text('Artikel 0')),
          name,
          reason: 'the row does not follow the finger',
        );
        await finger.up();
        await tester.pumpAndSettle();
      }
    }
    expect(editSheet(), findsNothing);
    expect(itemNamed('Artikel 0').status, ItemStatus.active);
    expect(rowOrder(tester), order);
    expect(repo.sent, isEmpty);

    await tester.drag(row('Artikel 1'), const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(tester.getRect(row('Artikel 0')).top, lessThan(before.top - 50));
    expect(editSheet(), findsNothing);
  });

  testWidgets('the mouse wheel over the add band scrolls the list under it; '
      'a tap on the field still opens the sheet', (tester) async {
    phone(tester);
    await pumpList(
      tester,
      seed: (repo) {
        for (var i = 0; i < 30; i++) {
          repo.remoteAdd('Artikel $i', categoryId: 'produce');
        }
      },
    );
    double top() => tester.getRect(row('Artikel 0')).top;
    final band = tester.getRect(
      find.ancestor(of: addField(), matching: find.byType(SafeArea)).first,
    );
    for (final at in [
      tester.getCenter(addField()),
      Offset(band.left + 4, band.center.dy),
    ]) {
      final before = top();
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(at));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 120)));
      await tester.pumpAndSettle();
      expect(top(), moreOrLessEquals(before - 120), reason: 'wheel at $at');
    }
    final trackpad = TestPointer(2, PointerDeviceKind.trackpad);
    final before = top();
    await tester.sendEventToBinding(
      trackpad.hover(tester.getCenter(addField())),
    );
    await tester.sendEventToBinding(trackpad.scroll(const Offset(0, -60)));
    await tester.pumpAndSettle();
    expect(top(), moreOrLessEquals(before + 60));

    await tester.tap(addField());
    await tester.pumpAndSettle();
    expect(sheet(), findsOneWidget);
    expect(fieldFocus(tester).hasFocus, isTrue);
    final open = top();
    final later = TestPointer(3, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(later.hover(tester.getCenter(addField())));
    await tester.sendEventToBinding(later.scroll(const Offset(0, 120)));
    await tester.pumpAndSettle();
    expect(top(), open, reason: 'the open sheet covers the list');
  });

  testWidgets('Abbrechen in the held-open sheet writes nothing and shows '
      'no message', (tester) async {
    await pumpList(tester, seed: (repo) => repo.remoteAdd('Brot'));
    await tester.longPress(row('Brot'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('edit-name')), 'Toast');
    await tester.tap(find.byKey(const ValueKey('chip-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('category-option-produce')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('edit-cancel')));
    await tester.pumpAndSettle();
    expect(editSheet(), findsNothing);
    expect(repo.sent, isEmpty);
    expect(row('Brot'), findsOneWidget);
    expect(row('Toast'), findsNothing);
    expect(itemNamed('Brot').categoryId, isNot('produce'));
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('an item still being sorted opens the sheet on a hold too', (
    tester,
  ) async {
    phone(tester);
    await pumpList(tester);
    repo.online = false;
    await tester.enterText(addField(), 'Brot');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-sheet-close')));
    await tester.pumpAndSettle();
    expect(tester.widget<ItemRow>(row('Brot')).item.categoryId, isNull);
    await tester.longPress(row('Brot'));
    await tester.pumpAndSettle();
    expect(editing('Brot'), findsOneWidget);
    expect(row('Brot'), findsOneWidget);
  });

  testWidgets('no item action needs a hold: tick, edit and move all work '
      'with taps and a right click', (tester) async {
    await pumpList(
      tester,
      seed: (repo) => repo
        ..remoteAdd('Milch')
        ..remoteAdd('Seife'),
    );
    // Tick: a tap.
    await tester.tap(row('Seife'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(itemNamed('Seife').status, ItemStatus.bought);

    // Edit and move to another category and store: the sheet a right click
    // opens.
    await tester.tap(row('Milch'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chip-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('category-option-produce')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chip-store')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('store-option-lidl')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('edit-done')));
    await tester.pumpAndSettle();
    expect(
      (itemNamed('Milch').categoryId, itemNamed('Milch').storeId),
      ('produce', 'lidl'),
    );
  });

  testWidgets('a hold opens the edit sheet while the finger is still down, '
      'also when the finger drifts a little', (tester) async {
    await pumpList(tester, seed: (repo) => repo.remoteAdd('Milch'));
    final start = tester.getCenter(row('Milch'));
    final finger = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 100));
    await finger.moveTo(start + const Offset(4, 12));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(editing('Milch'), findsOneWidget);
    await finger.up();
    await tester.pumpAndSettle();
    expect(editSheet(), findsOneWidget, reason: 'the lift does not close it');
    expect(repo.sent, isEmpty);
  });

  testWidgets('nothing on the list drags: a hold that moves on edits, '
      'shows no empty store and moves nothing', (tester) async {
    await pumpList(
      tester,
      seed: (repo) => repo
        ..remoteAdd('Seife', storeId: 'dm')
        ..remoteAdd('Milch', storeId: 'lidl'),
    );
    for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
      final from = tester.getCenter(row('Milch'));
      final gesture = await tester.startGesture(from, kind: kind);
      await tester.pump(const Duration(milliseconds: 400));
      await gesture.moveTo(tester.getCenter(storeDivider('dm')));
      await tester.pump();
      expect(storeDivider('none'), findsNothing, reason: 'no drop targets');
      await gesture.up();
      await tester.pumpAndSettle();
      expect(editing('Milch'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('edit-cancel')));
      await tester.pumpAndSettle();
    }
    expect(repo.sent, isEmpty);
    expect(itemNamed('Milch').storeId, 'lidl');
    expect(rowOrder(tester), ['Seife', 'Milch']);
  });

  testWidgets('screen readers get edit and delete as actions', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpList(tester, seed: (repo) => repo.remoteAdd('Brot'));
    const edit = CustomSemanticsAction(label: 'Bearbeiten');
    const delete = CustomSemanticsAction(label: 'Löschen');
    expect(
      tester.getSemantics(rowNode('Brot')),
      isSemantics(
        label: 'Brot',
        hasTapAction: true,
        hasLongPressAction: true,
        customActions: [edit, delete],
      ),
    );
    tester.semantics.customAction(find.semantics.byLabel('Brot'), edit);
    await tester.pumpAndSettle();
    expect(editing('Brot'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('edit-cancel')));
    await tester.pumpAndSettle();

    tester.semantics.customAction(find.semantics.byLabel('Brot'), delete);
    await tester.pumpAndSettle();
    expect(repo.rows, isEmpty);
    expect(find.text('Brot gelöscht'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a tap on a store folds it to its divider, across restarts', (
    tester,
  ) async {
    await pumpList(
      tester,
      seed: (repo) => repo
        ..remoteAdd('Seife', storeId: 'dm')
        ..remoteAdd('Milch', storeId: 'lidl'),
    );
    await tester.tap(storeDivider('dm'));
    await tester.pumpAndSettle();
    expect(row('Seife'), findsNothing);
    expect(categoryDivider('Sonstiges'), findsNothing);
    expect(row('Milch'), findsOneWidget);
    expect(
      tester.getSemantics(storeNode('dm')),
      isSemantics(
        label: 'dm, 1 Artikel',
        hint: 'Aufklappen',
        isExpanded: false,
      ),
    );
    expect(cache.prefs!.folded, {'dm'});

    await pumpList(tester, keepCache: true);
    expect(row('Seife'), findsNothing, reason: 'still folded');
    expect(storeDivider('dm'), findsOneWidget);
    await tester.tap(storeDivider('dm'));
    await tester.pumpAndSettle();
    expect(row('Seife'), findsOneWidget);
  });

  testWidgets('a stale folded store id is ignored', (tester) async {
    await pumpList(tester, seed: (repo) => repo.remoteAdd('Seife'));
    cache.prefs = const ListPrefs(folded: {'gone'});
    repo.remoteAdd('Shampoo', storeId: 'dm');
    await pumpList(tester, keepCache: true);
    expect(row('Seife'), findsOneWidget);
    expect(row('Shampoo'), findsOneWidget);
  });

  testWidgets('a store without items does not show', (tester) async {
    await pumpList(tester, seed: (repo) => repo.remoteAdd('Milch'));
    expect(storeDivider('dm'), findsNothing);
    expect(storeDivider('lidl'), findsNothing);
    expect(find.textContaining(RegExp(r'(^|\D)0 Artikel')), findsNothing);
  });

  testWidgets('ticking the last item hides its store, putting it back shows '
      'it again; with every store empty the empty list shows', (tester) async {
    await pumpList(
      tester,
      seed: (repo) => repo
        ..remoteAdd('Seife', storeId: 'dm')
        ..remoteAdd('Milch', storeId: 'lidl'),
    );
    await tester.tap(row('Seife'));
    await tester.pump();
    expect(storeDivider('dm'), findsOneWidget, reason: 'while it leaves');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(storeDivider('dm'), findsNothing);
    await showUsed(tester, 'Seife');
    await tester.tap(usedRow('Seife'));
    await tester.pumpAndSettle();
    expect(row('Seife'), findsOneWidget);
    expect(storeDivider('dm'), findsOneWidget);

    for (final name in ['Seife', 'Milch']) {
      await tester.tap(row(name));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    }
    expect(find.byType(StoreDivider), findsNothing);
    expect(
      find.text('Die Liste ist leer. Tippe unten ein, was fehlt.'),
      findsOneWidget,
    );
  });

  testWidgets('a right click opens the edit sheet', (tester) async {
    await pumpList(tester, seed: (repo) => repo.remoteAdd('Milch'));
    await tester.tap(row('Milch'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(editing('Milch'), findsOneWidget);
  });

  testWidgets('the edit sheet tags an item to a store', (tester) async {
    await pumpList(tester, seed: (repo) => repo.remoteAdd('Brot'));
    await tester.tap(row('Brot'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chip-store')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('store-option-lidl')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('edit-done')));
    await tester.pumpAndSettle();
    expect(repo.rows.values.single.storeId, 'lidl');
    expect((repo.sent.last as EditItem).changes.toColumns(), {
      'store_id': 'lidl',
    });
  });

  testWidgets('a row: icon, quantity first, brand and properties under the '
      'name, no initial, a long name wrapped in full', (tester) async {
    const long =
        'Glutenfreie Dinkel-Vollkorn-Hafer-Kekse mit Zartbitterschokolade '
        'und Meersalz';
    await pumpList(
      tester,
      seed: (repo) => repo
        ..remoteAdd('Milch', brand: 'Weihenstephan', properties: '1,5 %')
        ..remoteAdd('Brot', quantity: '6')
        ..remoteAdd(long),
    );
    expect(
      find.descendant(
        of: row('Milch'),
        matching: find.text('Weihenstephan · 1,5 %'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row('Brot'), matching: find.text('6× Brot')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row('Milch'), matching: find.text('🥛')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row('Milch'), matching: find.byType(CircleAvatar)),
      findsNothing,
    );
    final name = tester.widget<RichText>(
      find.descendant(of: row(long), matching: find.byType(RichText)).at(1),
    );
    expect(name.maxLines, isNull);
    expect(name.overflow, TextOverflow.clip);
    expect(name.softWrap, isTrue);
    final brot = tester.getSize(row('Brot')).height;
    expect(brot, greaterThanOrEqualTo(48));
    expect(tester.getSize(row(long)).height, greaterThan(brot + 20));
  });

  testWidgets('the explainer card is dismissed for good', (tester) async {
    await pumpList(tester, seed: (repo) => repo.remoteAdd('Brot'));
    expect(find.text('Tippen hakt ab · Halten bearbeitet'), findsOneWidget);
    await tester.tap(find.text('Verstanden'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('list-hint')), findsNothing);
    expect(cache.prefs!.hintDismissed, isTrue);
    await pumpList(tester, keepCache: true);
    expect(find.byKey(const ValueKey('list-hint')), findsNothing);
  });

  testWidgets('a hold or right click on a divider does nothing; a tap on a '
      'store divider only folds it', (tester) async {
    await pumpList(
      tester,
      seed: (repo) => repo
        ..remoteAdd('Seife', storeId: 'dm')
        ..remoteAdd('Milch', storeId: 'lidl')
        ..remoteAdd('Brot'),
    );
    Future<void> inert(Future<void> Function() press, String reason) async {
      await press();
      await tester.pumpAndSettle();
      expect(find.textContaining('/edit/'), findsNothing, reason: reason);
      expect(rowOrder(tester), ['Seife', 'Milch', 'Brot'], reason: reason);
      expect(cache.prefs?.folded ?? const <String>{}, isEmpty, reason: reason);
    }

    await inert(() => tester.longPress(storeDivider('lidl')), 'store hold');
    await inert(() async {
      final press = await tester.startGesture(
        tester.getCenter(storeDivider('lidl')),
      );
      await tester.pump(const Duration(milliseconds: 350));
      await press.up();
    }, 'a hold as long as a row edit');
    await inert(
      () => tester.tap(storeDivider('dm'), buttons: kSecondaryButton),
      'store right click',
    );
    await inert(() => tester.longPress(storeDivider('none')), 'no-store hold');
    await inert(
      () => tester.longPress(categoryDivider('Sonstiges').first),
      'category hold',
    );
    await inert(
      () => tester.tap(categoryDivider('Kühlregal'), buttons: kSecondaryButton),
      'category right click',
    );
    expect(repo.catalogCalls, isEmpty);

    await tester.tap(storeDivider('lidl'));
    await tester.pumpAndSettle();
    expect(row('Milch'), findsNothing);
    expect(rowOrder(tester), ['Seife', 'Brot']);
    expect(find.textContaining('/edit/'), findsNothing);

    await tester.longPress(storeDivider('lidl'));
    await tester.pumpAndSettle();
    expect(row('Milch'), findsNothing, reason: 'a hold does not unfold');
    expect(find.textContaining('/edit/'), findsNothing);
  });

  testWidgets("a screen reader's store divider offers a tap that folds and "
      'no long press, up or down moves', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpList(tester, seed: (repo) => repo.remoteAdd('Milch'));
    expect(
      tester.getSemantics(storeNode('none')),
      isSemantics(
        hasTapAction: true,
        hasLongPressAction: false,
        customActions: [],
      ),
    );
    expect(
      tester.getSemantics(categoryDivider('Kühlregal')),
      isSemantics(hasLongPressAction: false),
    );
    tester.semantics.tap(find.semantics.byLabel('Ohne Laden, 1 Artikel'));
    await tester.pumpAndSettle();
    expect(row('Milch'), findsNothing);
    expect(find.textContaining('/edit/'), findsNothing);
    handle.dispose();
  });

  testWidgets('wide screens lay the stores out in columns', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1366, 1024));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpList(
      tester,
      seed: (repo) => repo
        ..remoteAdd('Seife', storeId: 'dm')
        ..remoteAdd('Shampoo', storeId: 'dm')
        ..remoteAdd('Milch', storeId: 'lidl')
        ..remoteAdd('Brot'),
    );
    final xs = {
      for (final key in ['dm', 'lidl', 'none'])
        tester.getTopLeft(storeDivider(key)).dx,
    };
    expect(xs, hasLength(3), reason: 'three columns from 1200 px');
    expect(tester.getSize(row('Milch')).width, lessThanOrEqualTo(560));

    await tester.binding.setSurfaceSize(const Size(900, 1024));
    await tester.pumpAndSettle();
    final two = {
      for (final key in ['dm', 'lidl']) tester.getTopLeft(storeDivider(key)).dx,
    };
    expect(two, hasLength(2));

    await tester.binding.setSurfaceSize(const Size(700, 1024));
    await tester.pumpAndSettle();
    final one = tester.getRect(row('Milch'));
    expect(one.width, 640);
    expect(one.left, 30, reason: 'one centred column');
  });

  testWidgets('wide screens balance only the stores with items', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1366, 1024));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpList(
      tester,
      seed: (repo) => repo
        ..stores = const [
          Store(id: 'dm', name: 'dm', sortOrder: 10),
          Store(id: 'lidl', name: 'Lidl', sortOrder: 20),
          Store(id: 'edeka', name: 'Edeka', sortOrder: 30),
        ]
        ..remoteAdd('Seife', storeId: 'dm')
        ..remoteAdd('Milch', storeId: 'edeka')
        ..remoteAdd('Brot'),
    );
    expect(storeDivider('lidl'), findsNothing);
    Map<String, double> xs(List<String> keys) => {
      for (final key in keys) key: tester.getTopLeft(storeDivider(key)).dx,
    };
    final resting = xs(['dm', 'edeka', 'none']);
    expect(resting.values.toSet(), hasLength(3), reason: 'one store each');
  });

  testWidgets('wide screens with one section of items show one centred '
      'column', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1366, 1024));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpList(tester, seed: (repo) => repo.remoteAdd('Brot'));
    final brot = tester.getRect(row('Brot'));
    expect(brot.width, 640, reason: 'not one column across the screen');
    expect(brot.left, (1366 - 640) / 2);
  });

  group('who added what', () {
    String rowLabel(WidgetTester tester, String name) =>
        tester.getSemantics(rowNode(name)).label;

    testWidgets('a partner item carries no initial', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpList(tester, seed: (repo) => repo.remoteAdd('Milch'));
      expect(
        find.descendant(of: row('Milch'), matching: find.byType(CircleAvatar)),
        findsNothing,
      );
      expect(
        find.descendant(of: row('Milch'), matching: find.text('L')),
        findsNothing,
      );
      expect(rowLabel(tester, 'Milch'), isNot(contains('hinzugefügt')));
      expect(find.byKey(const ValueKey('new-items-subtitle')), findsNothing);
      handle.dispose();
    });

    testWidgets('live partner adds are new, named in the title', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpList(tester);
      final tea = repo.remoteAdd('Tee');
      repo.emitItem!(tea);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(ValueKey('new-${tea.id}')), findsOneWidget);
      expect(rowLabel(tester, 'Tee'), contains('Neu'));
      expect(find.text('1 neu von Lea'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('new-items-subtitle')))
            .data,
        '1 neu von Lea',
      );

      repo.members = [
        ...repo.members,
        const Member(id: 'ana', displayName: 'Ana'),
      ];
      repo.emitItem!(repo.remoteAdd('Kaffee', addedBy: 'ana'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('2 neu'), findsOneWidget);
      expect(find.byKey(ValueKey('new-${tea.id}')), findsOneWidget);
      expect(
        tester
            .widget<Material>(
              find.descendant(of: row('Tee'), matching: find.byType(Material)),
            )
            .color,
        HummlistColors.of(Theme.of(tester.element(row('Tee'))).brightness)
            .honeySoft,
        reason: 'new is honey; mint is done',
      );
      handle.dispose();
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('a new item clears after three seconds on screen', (
      tester,
    ) async {
      await pumpList(tester);
      await tester.showKeyboard(addField());
      final tea = repo.remoteAdd('Tee');
      repo.emitItem!(tea);
      await tester.pump();
      await tester.pump();
      final mark = find.byKey(ValueKey('new-${tea.id}'));
      await tester.pump(const Duration(seconds: 2));
      expect(mark, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pump();
      expect(mark, findsNothing);
      expect(find.byKey(const ValueKey('new-items-subtitle')), findsNothing);
      expect(tester.widget<TextField>(addField()).focusNode!.hasFocus, isTrue);
    });

    testWidgets('in the background the clock stops', (tester) async {
      await pumpList(tester);
      final tea = repo.remoteAdd('Tee');
      repo.emitItem!(tea);
      await tester.pump();
      await tester.pump();
      final mark = find.byKey(ValueKey('new-${tea.id}'));
      await tester.pump(const Duration(seconds: 2));
      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
        ..handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 5));
      expect(mark, findsOneWidget);
      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 2));
      expect(mark, findsOneWidget, reason: 'the three seconds start again');
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pump();
      expect(mark, findsNothing);
    });
  });

  group('usuals', () {
    void seedUsuals(FakeRepository repo) => repo.usuals = [
      const Usual(name: 'Gurken', quantity: '2', due: true),
      const Usual(name: 'Gurkensalat', due: false),
      const Usual(name: 'Brot', due: true),
    ];
    const typed = Suggestion(
      SuggestionSource.typed,
      ParsedEntry(name: 'Gurken'),
    );
    const salad = Suggestion(
      SuggestionSource.history,
      ParsedEntry(name: 'Gurkensalat'),
    );

    testWidgets('the empty open sheet offers what is due', (tester) async {
      phone(tester);
      await pumpList(tester, seed: seedUsuals);
      await tester.tap(addField());
      await tester.pumpAndSettle();
      expect(sheetRow('2× Gurken, Wieder fällig'), findsOneWidget);
      expect(sheetRow('Brot, Wieder fällig'), findsOneWidget);
      expect(
        find.descendant(of: sheet(), matching: find.textContaining('salat')),
        findsNothing,
        reason: 'Gurkensalat is not due',
      );
    });

    testWidgets('typing offers rows; a tap adds and typing goes on', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      phone(tester);
      await pumpList(
        tester,
        seed: (repo) {
          seedUsuals(repo);
          repo.suggestions['gur'] = const [
            Suggestion(SuggestionSource.typed, ParsedEntry(name: 'Gur')),
            Suggestion(
              SuggestionSource.history,
              ParsedEntry(name: 'Gurken', quantity: '2'),
            ),
            salad,
          ];
        },
      );
      await tester.tap(addField());
      await tester.enterText(addField(), 'gur');
      await settleRows(tester);
      expect(sheetRow('Gur, Wie getippt'), findsOneWidget);
      expect(sheetRow('Gurkensalat, Schon mal gekauft'), findsOneWidget);
      expect(sheetRow('Brot, Wieder fällig'), findsNothing);
      expect(
        find.bySemanticsLabel('2× Gurken, Schon mal gekauft'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('suggestion-1')));
      await tester.pumpAndSettle();
      final row = repo.rows.values.single;
      expect((row.name, row.quantity), ('Gurken', '2'));
      expect(tester.widget<TextField>(addField()).controller!.text, isEmpty);
      expect(fieldFocus(tester).hasFocus, isTrue);
      expect(FocusManager.instance.primaryFocus, fieldFocus(tester));

      // Straight into the field's input connection: no tap that refocuses.
      tester.testTextInput.enterText('Brot');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect([for (final i in repo.rows.values) i.name], ['Gurken', 'Brot']);
      expect(fieldFocus(tester).hasFocus, isTrue);
      handle.dispose();
    });

    testWidgets('picking a store or category hands focus back to the input', (
      tester,
    ) async {
      phone(tester);
      await pumpList(tester, seed: seedUsuals);
      await tester.tap(addField());
      await tester.enterText(addField(), 'Gurken');
      await settleRows(tester);
      for (final (chip, option) in [
        ('chip-store', 'store-option-lidl'),
        ('chip-category', 'category-option-produce'),
      ]) {
        await tester.tap(find.byKey(ValueKey(chip)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey(option)));
        await tester.pumpAndSettle();
        expect(
          FocusManager.instance.primaryFocus,
          fieldFocus(tester),
          reason: 'after $option',
        );
      }
      tester.testTextInput.enterText('Gurken!');
      await tester.pump();
      expect(tester.widget<TextField>(addField()).controller!.text, 'Gurken!');
    });

    testWidgets('a store made in the add sheet is picked for the item; '
        'Escape leaves only the store field', (tester) async {
      phone(tester);
      await pumpList(tester, seed: seedUsuals);
      await tester.tap(addField());
      await tester.enterText(addField(), 'Gurken');
      await settleRows(tester);
      await tester.tap(find.byKey(const ValueKey('chip-store')));
      await tester.pumpAndSettle();
      final newField = find.byKey(const ValueKey('store-new-field'));
      await tester.tap(find.byKey(const ValueKey('store-option-new')));
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus,
        tester.widget<TextField>(newField).focusNode,
        reason: 'from the add field into the store field',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(newField, findsNothing);
      expect(sheetRow('Gurken, Wie getippt'), findsOneWidget, reason: 'open');

      await tester.tap(find.byKey(const ValueKey('store-option-new')));
      await tester.pumpAndSettle();
      await tester.enterText(newField, 'Rewe');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(repo.catalogCalls, ['addStore(Rewe)']);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('chip-store')),
          matching: find.text('Rewe'),
        ),
        findsOneWidget,
      );
      expect(FocusManager.instance.primaryFocus, fieldFocus(tester));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(itemNamed('Gurken').storeId, 'new-Rewe');
    });

    testWidgets('a row goes once its item is on the list; the typed row '
        'stays', (tester) async {
      phone(tester);
      await pumpList(
        tester,
        seed: (repo) => repo.suggestions['gurken'] = const [typed, salad],
      );
      await tester.tap(addField());
      await tester.enterText(addField(), 'gurken');
      await settleRows(tester);
      expect(sheetRow('Gurkensalat, Schon mal gekauft'), findsOneWidget);
      repo
        ..emitItem!(repo.remoteAdd('Gurkensalat', addedBy: 'peter'))
        ..emitItem!(repo.remoteAdd('Gurken', addedBy: 'peter'));
      await tester.pump();
      await tester.pump();
      expect(sheetRow('Gurkensalat, Schon mal gekauft'), findsNothing);
      expect(sheetRow('Gurken, Wie getippt'), findsOneWidget);
    });
  });

  testWidgets('on a wide screen the add field and sheet sit under the '
      'first column', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);
    await pumpList(
      tester,
      seed: (repo) => repo
        ..remoteAdd('Zahnpasta', storeId: 'dm')
        ..remoteAdd('Butter', storeId: 'lidl'),
    );
    final dm = tester.getRect(storeDivider('dm'));
    final lidl = tester.getRect(storeDivider('lidl'));
    expect(lidl.left, greaterThan(dm.right), reason: 'two columns');
    final field = tester.getRect(addField());
    expect(field.left, greaterThan(dm.left));
    expect(field.right, lessThan(dm.right));

    await tester.tap(addField());
    await tester.pumpAndSettle();
    final sheet = tester.getRect(find.byKey(const ValueKey('add-sheet')));
    expect(sheet.left, dm.left);
    expect(sheet.right, dm.right);
  });

  group('the bar above the list', () {
    Finder header() => find.byKey(const ValueKey('list-header'));
    Finder indicator() => find.byKey(const ValueKey('sync-indicator'));
    Finder pill() => find.byKey(const ValueKey('sync-pill'));

    /// The cubit's stream answers a microtask later: one frame to see it,
    /// one to build it.
    Future<void> frames(WidgetTester tester) async {
      await tester.pump();
      await tester.pump();
    }

    testWidgets('keeps its height in every sync state', (tester) async {
      phone(tester);
      // A notch: the bar starts below it.
      tester.view.padding = const FakeViewPadding(top: 47 * 3);
      await pumpList(
        tester,
        seed: (repo) => repo
          ..remoteAdd('Brot')
          ..remoteAdd('Milch'),
      );
      final cubit = BlocProvider.of<ListCubit>(tester.element(header()));
      final edit = find.byKey(const ValueKey('list-edit'));
      final height = tester.getSize(header()).height;
      final editRect = tester.getRect(edit);
      // The list's first entry, the explainer card, stays while items go.
      final card = find.byKey(const ValueKey('list-hint-dismiss'));
      final rowTop = tester.getTopLeft(card).dy;
      // The capsule, its gaps and the shadow below the notch (job 148).
      expect(height, 47 + 68);
      expect(rowTop, greaterThanOrEqualTo(height), reason: 'starts below it');

      void same(String state) {
        expect(tester.getSize(header()).height, height, reason: state);
        expect(tester.getRect(edit), editRect, reason: state);
        expect(tester.getTopLeft(card).dy, rowTop, reason: state);
      }

      same('synced');
      expect(indicator(), findsNothing);
      expect(pill(), findsNothing);

      final held = repo.gate = Completer<void>();
      cubit.tick(repo.rows.values.firstWhere((i) => i.name == 'Milch').id);
      await frames(tester);
      expect(indicator(), findsNothing, reason: 'pending online: nothing');
      same('pending');

      repo.online = false;
      repo.emitStatus!(ConnectionStatus.offline);
      await frames(tester);
      expect(indicator(), findsOneWidget);
      same('offline with a pending change');
      await tester.pump(const Duration(seconds: 4));
      expect(pill(), findsOneWidget);
      same('offline, collapsed');

      repo.emitStatus!(ConnectionStatus.connecting);
      await frames(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(pill(), findsNothing);
      same('reconnecting with a pending change');

      repo
        ..online = true
        ..gate = null;
      held.complete();
      repo.emitStatus!(ConnectionStatus.online);
      await frames(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(cubit.state.pending, isEmpty);
      expect(indicator(), findsNothing);
      expect(pill(), findsNothing);
      same('synced again');

      repo.emitItem!(repo.remoteAdd('Tee'));
      await frames(tester);
      expect(find.byKey(const ValueKey('new-items-subtitle')), findsOneWidget);
      same('a partner add');
      repo.emitStatus!(ConnectionStatus.offline);
      await frames(tester);
      expect(indicator(), findsOneWidget);
      same('a partner add, offline');
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('in dark, the new-adds capsule has the one sticker edge: '
        'hard, in the contour colour', (tester) async {
      phone(tester);
      await pumpList(
        tester,
        theme: appTheme(Brightness.dark),
        seed: (repo) => repo.remoteAdd('Brot'),
      );
      repo.emitItem!(repo.remoteAdd('Tee'));
      await tester.pump(const Duration(seconds: 4));
      final status = find.byKey(const ValueKey('list-status'));
      expect(status, findsOneWidget);
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: status, matching: find.byType(DecoratedBox)).first,
      );
      final shadows = (box.decoration as ShapeDecoration).shadows!;
      expect(shadows, HlSticker.shadow(Brightness.dark, StickerDepth.s));
      for (final s in shadows) {
        expect(s.blurRadius, 0, reason: 'no glow: one hard 3D edge');
        expect(s.color, HummlistColors.dark.border);
      }
    });

    testWidgets('Anpassen stands alone; new adds get their own capsule '
        'beside it, and the sync pill keeps clear of both', (tester) async {
      phone(tester);
      await pumpList(tester, seed: (repo) => repo.remoteAdd('Brot'));
      final edit = find.byKey(const ValueKey('list-edit'));
      final status = find.byKey(const ValueKey('list-status'));
      expect(status, findsNothing, reason: 'synced, nothing new: no frame');

      repo.emitStatus!(ConnectionStatus.offline);
      await frames(tester);
      expect(status, findsNothing, reason: 'offline is the indicator’s');
      repo.emitItem!(repo.remoteAdd('Tee'));
      await tester.pump(const Duration(seconds: 4));
      expect(find.descendant(of: status, matching: edit), findsNothing);
      expect(
        tester.getRect(status).right,
        lessThanOrEqualTo(tester.getRect(edit).left),
        reason: 'beside Anpassen, before it',
      );
      expect(find.descendant(of: header(), matching: pill()), findsNothing);
      expect(
        tester.getRect(pill()).right,
        lessThanOrEqualTo(tester.getRect(status).left),
        reason: 'the pill sits left of the capsule',
      );

      repo.emitStatus!(ConnectionStatus.online);
      await frames(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(pill(), findsNothing);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('stays while the list loads', (tester) async {
      phone(tester);
      final held = Completer<void>();
      await pumpList(
        tester,
        seed: (repo) => repo.itemsGate = held,
        settle: false,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byKey(const ValueKey('list-edit')), findsOneWidget);
      held.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byKey(const ValueKey('list-edit')), findsOneWidget);
    });

    testWidgets('floats: rows scroll on under it, and a row brought into '
        'view stops below it', (tester) async {
      phone(tester);
      await pumpList(
        tester,
        seed: (repo) {
          for (var i = 0; i < 30; i++) {
            repo.remoteAdd('Artikel $i');
          }
        },
      );
      final edit = find.byKey(const ValueKey('list-edit'));
      final bottom = tester.getRect(header()).bottom;
      final at = tester.getRect(edit);
      Rect row(int i) => tester.getRect(find.text('Artikel $i'));
      final first = row(0);
      expect(first.top, greaterThanOrEqualTo(bottom));

      await tester.drag(
        find.byType(ShoppingListView),
        Offset(0, -(first.top - bottom / 2)),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(edit), at, reason: 'the bar stays put');
      expect(
        row(0).top,
        lessThan(bottom),
        reason: 'the first row has scrolled under the bar',
      );
      expect(row(0).bottom, greaterThan(0), reason: 'still painted behind it');

      await tester.ensureVisible(find.text('Artikel 0'));
      await tester.pumpAndSettle();
      expect(
        row(0).top,
        greaterThanOrEqualTo(bottom - 1),
        reason: 'brought into view, it is not hidden under the bar',
      );
      final hit = tester.hitTestOnBinding(tester.getCenter(edit));
      expect(
        hit.path.any((entry) => entry.target == tester.renderObject(edit)),
        isTrue,
        reason: 'Anpassen still takes the tap over the rows',
      );
    });

    testWidgets('shows neither the household name nor the item count, '
        'only Anpassen', (tester) async {
      await pumpList(
        tester,
        seed: (repo) => repo
          ..remoteAdd('Brot')
          ..remoteAdd('Milch'),
      );
      final texts = find.descendant(of: header(), matching: find.byType(Text));
      expect(texts, findsOneWidget);
      expect(tester.widget<Text>(texts).data, 'Anpassen');
      expect(
        tester.getSemantics(texts),
        isSemantics(label: 'Anpassen', isButton: true),
      );
      expect(find.byKey(const ValueKey('list-title')), findsNothing);
      expect(find.byKey(const ValueKey('list-count')), findsNothing);
      expect(
        find.descendant(
          of: header(),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && (w.properties.header ?? false),
          ),
        ),
        findsNothing,
      );
    });
  });
}

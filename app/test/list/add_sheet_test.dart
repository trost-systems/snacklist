import 'dart:async';

import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/add_sheet/suggestion.dart';
import 'package:family_groceries/list/list_cache.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_repository.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_repository.dart';
import 'memory_cache.dart';

void main() {
  late FakeRepository repo;

  /// A 390x844 phone with a notch and a home indicator.
  const screen = Size(390, 844);
  const safeTop = 47.0;
  const safeBottom = 34.0;

  Future<void> pumpList(
    WidgetTester tester, {
    void Function(FakeRepository repo)? seed,
    Size size = screen,
    ListPrefs? prefs,
  }) async {
    tester.view
      ..devicePixelRatio = 3
      ..physicalSize = size * 3
      ..padding = const FakeViewPadding(
        top: safeTop * 3,
        bottom: safeBottom * 3,
      );
    addTearDown(tester.view.reset);
    repo = FakeRepository();
    seed?.call(repo);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: BlocProvider(
          create: (_) =>
              ListCubit(repo, MemoryListCache()..prefs = prefs, userId: 'peter')
                ..start(),
          child: const ShoppingList(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder field() => find.byKey(const ValueKey('add-item-field'));
  Finder content() => find.byKey(const ValueKey('add-sheet'));
  Finder row(int i) => find.byKey(ValueKey('suggestion-$i'));
  FocusNode focus(WidgetTester tester) =>
      tester.widget<TextField>(field()).focusNode!;
  String typed(WidgetTester tester) =>
      tester.widget<TextField>(field()).controller!.text;

  /// The sheet's background: what the user sees grow above the input.
  Rect surface(WidgetTester tester) =>
      tester.getRect(find.byKey(const ValueKey('add-sheet-surface')));

  /// The add bar's top edge, where the sheet stands.
  double barTop(WidgetTester tester) => tester
      .getRect(
        find.ancestor(of: field(), matching: find.byType(SafeArea)).first,
      )
      .top;

  Future<void> open(WidgetTester tester) async {
    await tester.tap(field());
    await tester.pumpAndSettle();
  }

  /// Types [text] and waits out the typing pause and the server's answer.
  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(field(), text);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
  }

  List<Suggestion> rows(int n) => [
    for (var i = 0; i < n; i++)
      Suggestion(
        i == 0 ? SuggestionSource.typed : SuggestionSource.history,
        ParsedEntry(name: 'Wurst $i'),
      ),
  ];

  group('the sheet is as tall as its content, up to the screen top', () {
    for (final n in [0, 1, 2, 4]) {
      testWidgets('$n rows: no gap above the input', (tester) async {
        await pumpList(tester, seed: (r) => r.suggestions['wurst'] = rows(n));
        await open(tester);
        await type(tester, 'wurst');
        final sheet = surface(tester);
        expect(sheet.top, tester.getRect(content()).top);
        expect(sheet.height, tester.getRect(content()).height);
        final last = n == 0
            ? find.byKey(const ValueKey('add-sheet-empty'))
            : row(n - 1);
        expect(last, findsOneWidget);
        expect(
          barTop(tester) - tester.getRect(last).bottom,
          lessThanOrEqualTo(24),
          reason: 'the sheet ends at its last row, right above the input',
        );
        expect(sheet.bottom, closeTo(barTop(tester), 1));
      });
    }

    testWidgets('12 rows reach the top and scroll', (tester) async {
      await pumpList(tester, seed: (r) => r.suggestions['wurst'] = rows(12));
      await open(tester);
      await type(tester, 'wurst');
      expect(surface(tester).top, closeTo(safeTop + 28, 0.5));
      expect(row(11).hitTestable(), findsNothing, reason: 'below the fold');
      await tester.scrollUntilVisible(
        row(11),
        100,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('add-suggestions')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(row(11).hitTestable(), findsOneWidget);
      expect(surface(tester).top, closeTo(safeTop + 28, 0.5));
    });

    testWidgets('the input never moves: closed, open, grown, closed again', (
      tester,
    ) async {
      await pumpList(tester, seed: (r) => r.suggestions['wurst'] = rows(8));
      final closed = tester.getRect(field());
      await open(tester);
      final opened = tester.getRect(field());
      await type(tester, 'wurst');
      final grown = tester.getRect(field());
      await tester.tap(find.byKey(const ValueKey('add-sheet-close')));
      await tester.pumpAndSettle();
      final after = tester.getRect(field());
      for (final (name, rect) in [
        ('open', opened),
        ('grown', grown),
        ('closed again', after),
      ]) {
        expect(rect.top, closeTo(closed.top, 2), reason: name);
        expect(rect.height, closeTo(closed.height, 2), reason: name);
      }
      expect(content(), findsNothing);
    });

    for (final still in [false, true]) {
      testWidgets(
        still
            ? 'with animations off it takes its size in one frame'
            : 'with animations on it grows over several frames',
        (tester) async {
          if (still) {
            tester.platformDispatcher.accessibilityFeaturesTestValue =
                const FakeAccessibilityFeatures(disableAnimations: true);
            addTearDown(
              tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
            );
          }
          await pumpList(tester, seed: (r) => r.suggestions['wurst'] = rows(4));
          await open(tester);
          final gate = repo.suggestGate = Completer<void>();
          await tester.enterText(field(), 'wurst');
          await tester.pump(const Duration(milliseconds: 200));
          await tester.pumpAndSettle();
          final before = surface(tester).height;
          gate.complete();
          await tester.pump();
          await tester.pump();
          final first = surface(tester).height;
          await tester.pumpAndSettle();
          final settled = surface(tester).height;
          expect(settled, greaterThan(before), reason: 'four rows came in');
          if (still) {
            expect(first, settled);
          } else {
            expect(first, lessThan(settled));
          }
        },
      );
    }
  });

  group('the chips apply to the row that is tapped', () {
    const milk = [
      Suggestion(SuggestionSource.typed, ParsedEntry(name: 'Milch')),
      Suggestion(
        SuggestionSource.history,
        ParsedEntry(
          name: 'Milch',
          brand: 'Weihenstephan',
          properties: 'laktosefrei, 1,5 %',
          storeId: 'dm',
          categoryId: 'chilled',
        ),
      ),
    ];

    Future<void> pick(WidgetTester tester, String chip, String option) async {
      await tester.tap(find.byKey(ValueKey(chip)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(option)));
      await tester.pumpAndSettle();
    }

    testWidgets('a picked store and category go with the second row', (
      tester,
    ) async {
      await pumpList(tester, seed: (r) => r.suggestions['milch'] = milk);
      await open(tester);
      await type(tester, 'milch');
      await pick(tester, 'chip-store', 'store-option-lidl');
      await pick(tester, 'chip-category', 'category-option-produce');
      await tester.tap(row(1));
      await tester.pumpAndSettle();
      final add = repo.sent.single as AddItem;
      final item = add.item;
      expect(
        (item.name, item.brand, item.properties, item.storeId, item.categoryId),
        ('Milch', 'Weihenstephan', 'laktosefrei, 1,5 %', 'lidl', 'produce'),
      );
      expect(add.autoCategory, isFalse, reason: 'the pick is sent');
    });

    testWidgets('without a pick the row keeps its own store', (tester) async {
      await pumpList(tester, seed: (r) => r.suggestions['milch'] = milk);
      await open(tester);
      await type(tester, 'milch');
      await tester.tap(row(1));
      await tester.pumpAndSettle();
      final add = repo.sent.single as AddItem;
      expect(add.item.storeId, 'dm');
      expect(add.autoCategory, isTrue, reason: 'the server classifies it');
    });

    testWidgets('Ohne Laden adds without the remembered store, in one op', (
      tester,
    ) async {
      await pumpList(tester, seed: (r) => r.suggestions['milch'] = milk);
      await open(tester);
      await type(tester, 'milch');
      await pick(tester, 'chip-store', 'store-option-none');
      await tester.tap(row(1));
      await tester.pumpAndSettle();
      expect(repo.sent, hasLength(1));
      final add = repo.sent.single as AddItem;
      expect(
        (add.item.storeId, add.item.brand, add.noStore),
        (null, 'Weihenstephan', true),
      );
      expect(repo.rows.values.single.storeId, isNull);
    });
  });

  group('a typo finds what was bought before; a tap adds it', () {
    String label(WidgetTester tester, int i) =>
        tester.getSemantics(row(i)).label;

    /// Adds the second row, then checks the field is empty, focused and
    /// takes the next item straight away.
    Future<void> takeAndGoOn(WidgetTester tester) async {
      await tester.tap(row(1));
      await tester.pumpAndSettle();
      expect(find.text('✓ Hinzugefügt: Hafermilch'), findsOneWidget);
      expect(typed(tester), isEmpty);
      expect(focus(tester).hasFocus, isTrue);
      await tester.enterText(field(), 'Brot');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('✓ Hinzugefügt: Brot'), findsOneWidget);
      expect(focus(tester).hasFocus, isTrue);
    }

    testWidgets('from the server', (tester) async {
      await pumpList(
        tester,
        seed: (r) => r.suggestions['Hafermlch'] = const [
          Suggestion(SuggestionSource.typed, ParsedEntry(name: 'Hafermlch')),
          Suggestion(SuggestionSource.history, ParsedEntry(name: 'Hafermilch')),
        ],
      );
      await open(tester);
      await type(tester, 'Hafermlch');
      expect(label(tester, 1), 'Hafermilch, Schon mal gekauft');
      await takeAndGoOn(tester);
      expect(
        {for (final item in repo.rows.values) item.name},
        {'Hafermilch', 'Brot'},
      );
    });

    testWidgets('without the server, from the usuals on the device', (
      tester,
    ) async {
      await pumpList(
        tester,
        seed: (r) => r.usuals = [const Usual(name: 'Hafermilch', due: false)],
      );
      repo.online = false;
      await open(tester);
      await type(tester, 'Hafermlch');
      expect(label(tester, 0), 'Hafermlch, Wie getippt');
      expect(label(tester, 1), 'Hafermilch, Schon mal gekauft');
      await takeAndGoOn(tester);
    });

    testWidgets('part of a word, without the server', (tester) async {
      await pumpList(
        tester,
        seed: (r) => r.usuals = [const Usual(name: 'Hafermilch', due: false)],
      );
      repo.online = false;
      await open(tester);
      await type(tester, 'milch');
      expect(label(tester, 1), 'Hafermilch, Schon mal gekauft');
    });
  });

  testWidgets('the empty field offers what is due, then what was used lately', (
    tester,
  ) async {
    final now = DateTime.now();
    await pumpList(
      tester,
      seed: (r) => r.usuals = [
        const Usual(name: 'Milch', due: true),
        Usual(
          name: 'Hafermilch',
          due: false,
          lastUsed: now.subtract(const Duration(days: 2)),
        ),
        Usual(
          name: 'Mehl',
          due: false,
          lastUsed: now.subtract(const Duration(days: 40)),
        ),
      ],
    );
    await open(tester);
    expect(tester.getSemantics(row(0)).label, 'Milch, Wieder fällig');
    expect(tester.getSemantics(row(1)).label, 'Hafermilch, Zuletzt verwendet');
    expect(row(2), findsNothing, reason: 'Mehl was last used 40 days ago');
    expect(
      find.descendant(of: row(0), matching: find.byIcon(Icons.keyboard_return)),
      findsNothing,
      reason: 'Enter takes nothing while the field is empty',
    );
    await tester.ensureVisible(row(1));
    await tester.pumpAndSettle();
    await tester.tap(row(1));
    await tester.pumpAndSettle();
    expect(find.text('✓ Hinzugefügt: Hafermilch'), findsOneWidget);
    expect(focus(tester).hasFocus, isTrue);
  });

  group('a tapped row keeps the typed quantity', () {
    for (final text in [
      'Karotten 2',
      '2 Karotten',
      'Karotten x2',
      '2x Karotten',
    ]) {
      testWidgets('"$text", tapped before its rows arrive', (tester) async {
        await pumpList(tester);
        await open(tester);
        await type(tester, 'Karotten');
        final gate = repo.suggestGate = Completer<void>();
        await tester.enterText(field(), text);
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text('Karotten · 2'), findsOneWidget);
        await tester.tap(row(0));
        gate.complete();
        await tester.pumpAndSettle();
        final item = repo.rows.values.single;
        expect((item.name, item.quantity), ('Karotten', '2'));
      });
    }

    testWidgets('without the server, from the parse on the device', (
      tester,
    ) async {
      await pumpList(tester);
      repo.online = false;
      await open(tester);
      await type(tester, 'Karotten 2');
      expect(find.text('Karotten · 2'), findsOneWidget);
      await tester.tap(row(0));
      await tester.pumpAndSettle();
      final item = tester
          .element(field())
          .read<ListCubit>()
          .state
          .items
          .values
          .single;
      expect((item.name, item.quantity), ('Karotten', '2'));
    });
  });
  testWidgets('an add typed offline gets its brand and details once it '
      'syncs, as online (job 111)', (tester) async {
    await pumpList(tester);
    repo
      ..parsed['Windeln Pampers Größe 3'] = const ParsedEntry(
        name: 'Windeln',
        brand: 'Pampers',
        properties: 'Größe 3',
      )
      ..online = false;
    await open(tester);
    // The amount as a word: the device reads it (job 104), the server the rest.
    await type(tester, 'zwei Windeln Pampers Größe 3');
    await tester.tap(row(0));
    await tester.pumpAndSettle();
    expect(repo.rows, isEmpty);

    repo.online = true;
    repo.emitStatus!(ConnectionStatus.online);
    await tester.pumpAndSettle();
    final item = repo.rows.values.single;
    expect(
      (item.name, item.brand, item.properties, item.quantity),
      ('Windeln', 'Pampers', 'Größe 3', '2'),
    );
  });

  // Job 64: on a 360 px phone the chips wrap, and a half-screen cap left
  // one "Wieder fällig" row, cut by the input.
  for (final size in [const Size(360, 640), screen]) {
    testWidgets('the empty field shows three due rows whole above the input, '
        'also after an add (${size.width.toInt()}x${size.height.toInt()})', (
      tester,
    ) async {
      await pumpList(
        tester,
        size: size,
        seed: (r) => r.usuals = [
          for (final name in ['Eier', 'Milch', 'Brot', 'Butter', 'Käse'])
            Usual(name: name, due: true),
        ],
      );
      await open(tester);
      void threeWhole(List<String> names) {
        final sheetTop = surface(tester).top;
        for (final (i, name) in names.indexed) {
          expect(tester.getSemantics(row(i)).label, '$name, Wieder fällig');
          final rect = tester.getRect(row(i));
          expect(rect.top, greaterThanOrEqualTo(sheetTop), reason: name);
          expect(
            rect.bottom,
            lessThanOrEqualTo(barTop(tester) + 0.5),
            reason: '$name is not cut by the input',
          );
        }
        expect(
          row(names.length).hitTestable(),
          findsNothing,
          reason: 'the others scroll',
        );
      }

      threeWhole(['Eier', 'Milch', 'Brot']);
      await tester.tap(row(0));
      await tester.pumpAndSettle();
      expect(find.text('✓ Hinzugefügt: Eier'), findsOneWidget);
      threeWhole(['Milch', 'Brot', 'Butter']);
    });
  }

  // The app doesn't clamp the text scale; 2.0 is the largest Android font
  // size, 3.0 iOS's largest accessibility size.
  for (final scale in [2.0, 3.0]) {
    for (final size in [const Size(360, 640), const Size(320, 568)]) {
      testWidgets('at text scale $scale the third due row scrolls whole into '
          'view above the input (${size.width.toInt()}x'
          '${size.height.toInt()})', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpList(
          tester,
          size: size,
          // The list's explainer card has its own large-text overflow.
          prefs: const ListPrefs(hintDismissed: true),
          seed: (r) => r.usuals = [
            for (final name in ['Eier', 'Milch', 'Brot', 'Butter'])
              Usual(name: name, due: true),
          ],
        );
        await open(tester);
        final third = row(2);
        await tester.scrollUntilVisible(
          third,
          40,
          scrollable: find
              .descendant(of: content(), matching: find.byType(Scrollable))
              .first,
        );
        await tester.ensureVisible(third);
        await tester.pumpAndSettle();
        expect(tester.getSemantics(third).label, 'Brot, Wieder fällig');
        final rect = tester.getRect(third);
        final viewport = tester.getRect(
          find.ancestor(of: third, matching: find.byType(Scrollable)).first,
        );
        expect(rect.top, greaterThanOrEqualTo(viewport.top - 0.5));
        expect(rect.top, greaterThanOrEqualTo(surface(tester).top - 0.5));
        expect(
          rect.bottom,
          lessThanOrEqualTo(viewport.bottom + 0.5),
          reason: 'Brot is not cut by the list',
        );
        expect(
          rect.bottom,
          lessThanOrEqualTo(barTop(tester) + 0.5),
          reason: 'Brot is not cut by the input',
        );
        // A tap would add Brot to the list behind the sheet, whose rows
        // have large-text overflows of their own.
        expect(third.hitTestable(), findsOneWidget, reason: 'Brot is tappable');
      });
    }
  }

  group('Enter takes the first row', () {
    const eggs = [
      Suggestion(
        SuggestionSource.typed,
        ParsedEntry(name: 'Eier', quantity: '10', categoryId: 'chilled'),
      ),
      Suggestion(SuggestionSource.history, ParsedEntry(name: 'Eiernudeln')),
    ];

    testWidgets('and keeps typing going', (tester) async {
      await pumpList(tester, seed: (r) => r.suggestions['10 eier'] = eggs);
      await open(tester);
      await type(tester, '10 eier');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      final item = repo.rows.values.single;
      expect((item.name, item.quantity), ('Eier', '10'));
      expect(typed(tester), isEmpty);
      expect(focus(tester).hasFocus, isTrue);
      expect(content(), findsOneWidget, reason: 'the sheet stays open');
    });

    testWidgets('waiting for rows still loading', (tester) async {
      await pumpList(tester, seed: (r) => r.suggestions['10 eier'] = eggs);
      await open(tester);
      final gate = repo.suggestGate = Completer<void>();
      await tester.enterText(field(), '10 eier');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(repo.sent, isEmpty);
      gate.complete();
      await tester.pumpAndSettle();
      final item = repo.rows.values.single;
      expect((item.name, item.quantity), ('Eier', '10'));
      expect(repo.suggestCalls, ['10 eier'], reason: 'asked once');
      expect(typed(tester), isEmpty);
      expect(focus(tester).hasFocus, isTrue);
    });

    testWidgets('Escape while Enter waits for its rows cancels the add; '
        'the sheet stays closed', (tester) async {
      await pumpList(tester, seed: (r) => r.suggestions['10 eier'] = eggs);
      await open(tester);
      final gate = repo.suggestGate = Completer<void>();
      await tester.enterText(field(), '10 eier');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      gate.complete();
      await tester.pumpAndSettle();
      expect(repo.sent, isEmpty);
      expect(content(), findsNothing, reason: 'nothing reopens it');
      expect(focus(tester).hasFocus, isFalse);
    });

    testWidgets('the note says what was added; Rückgängig removes it', (
      tester,
    ) async {
      await pumpList(
        tester,
        seed: (r) => r.suggestions['seife'] = const [
          Suggestion(
            SuggestionSource.typed,
            ParsedEntry(name: 'Seife', storeId: 'dm'),
          ),
        ],
      );
      await open(tester);
      await type(tester, 'seife');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('added-note')),
          matching: find.text('✓ Hinzugefügt: Seife → dm'),
        ),
        findsOneWidget,
      );
      expect(repo.rows, hasLength(1));
      await tester.tap(find.byKey(const ValueKey('added-undo')));
      await tester.pumpAndSettle();
      expect(repo.rows, isEmpty);
      expect(
        repo.sent.last,
        isA<DeleteItem>().having((op) => op.undoAdd, 'undoAdd', isTrue),
        reason: 'the undo also takes back what the details taught',
      );
      expect(find.byKey(const ValueKey('added-note')), findsNothing);
    });

    testWidgets('an item already on the list is named, not added twice', (
      tester,
    ) async {
      await pumpList(tester, seed: (r) => r.remoteAdd('Seife'));
      await open(tester);
      await type(tester, 'Seife');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Seife steht schon auf der Liste'), findsOneWidget);
      expect(find.byKey(const ValueKey('added-undo')), findsNothing);
      expect(repo.sent, isEmpty);
    });
  });

  testWidgets(
    'an answer still on its way when an item is added is not reused',
    (tester) async {
      await pumpList(tester, seed: (r) => r.suggestions['wurst'] = rows(4));
      await open(tester);
      final gate = repo.suggestGate = Completer<void>();
      await tester.enterText(field(), 'wurst');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(row(0));
      await tester.pump();
      gate.complete();
      await tester.pumpAndSettle();
      final asked = repo.suggestCalls.length;
      await type(tester, 'wurst');
      expect(
        repo.suggestCalls,
        hasLength(asked + 1),
        reason: 'the answer from before the add was not cached',
      );
    },
  );

  testWidgets('the sheet closes on the scrim, Schließen and Escape', (
    tester,
  ) async {
    await pumpList(tester);
    for (final close in <Future<void> Function()>[
      () => tester.tapAt(const Offset(195, 120)),
      () => tester.tap(find.byKey(const ValueKey('add-sheet-close'))),
      () => tester.sendKeyEvent(LogicalKeyboardKey.escape),
    ]) {
      await open(tester);
      expect(content(), findsOneWidget);
      await close();
      await tester.pumpAndSettle();
      expect(content(), findsNothing);
    }
  });

  // Job 64: Escape with a row focused (Tab from the input, or the moment
  // after a tap on the web) is not the field's; the screen takes it.
  testWidgets('Escape closes the sheet while a row has focus', (tester) async {
    await pumpList(tester, seed: (r) => r.suggestions['wurst'] = rows(3));
    await open(tester);
    await type(tester, 'wurst');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(focus(tester).hasFocus, isFalse, reason: 'a row has focus');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(content(), findsNothing);
    expect(focus(tester).hasFocus, isFalse, reason: 'it stays closed');
  });

  // On the web a click on the field can reach the app as a semantics tap or
  // focus instead of pointer events; TextField then requests focus or the
  // keyboard but never calls onTap. After the user closed the sheet, the
  // field getting focus back opens it like a tap (seen in e2e list.spec,
  // "adds are grouped", on the third or fourth add).
  for (final action in [SemanticsAction.tap, SemanticsAction.focus]) {
    testWidgets('after closing, a semantics ${action.name} on the field '
        'opens the sheet again', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpList(tester);
      await open(tester);
      expect(content(), findsOne);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(content(), findsNothing);
      expect(focus(tester).hasFocus, isFalse);

      final node = find.semantics
          .byFlag(SemanticsFlag.isTextField)
          .evaluate()
          .single;
      node.owner!.performAction(node.id, action);
      await tester.pumpAndSettle();
      expect(content(), findsOne);
      expect(focus(tester).hasFocus, isTrue);
      semantics.dispose();
    });
  }

  testWidgets('the field focused at start leaves the sheet closed', (
    tester,
  ) async {
    await pumpList(tester);
    focus(tester).requestFocus();
    await tester.pumpAndSettle();
    expect(focus(tester).hasFocus, isTrue);
    expect(content(), findsNothing);
  });

  // Job 78: the hex around the field is one tap target; no "+" disc.
  group('the compose hex', () {
    testWidgets('a tap beside the field opens the sheet and focuses it', (
      tester,
    ) async {
      await pumpList(tester);
      final left = tester.getRect(field()).centerLeft;
      await tester.tapAt(left - const Offset(8, 0));
      await tester.pumpAndSettle();
      expect(content(), findsOne);
      expect(focus(tester).hasFocus, isTrue);
    });

    testWidgets('a tap beside the field takes dictated text into the sheet', (
      tester,
    ) async {
      await pumpList(tester, seed: (r) => r.suggestions['milch'] = rows(2));
      tester.widget<TextField>(field()).controller!.text = 'milch';
      await tester.tapAt(
        tester.getRect(field()).centerLeft - const Offset(8, 0),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(row(1), findsOne, reason: 'the rows for the dictated text');
    });
  });

  testWidgets('the sheet has no title, only its name for screen readers', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpList(tester);
    await open(tester);
    expect(find.text('Hinzufügen'), findsNothing);
    expect(find.bySemanticsLabel('Hinzufügen'), findsOne);
    expect(find.bySemanticsLabel('Schließen'), findsOne);
    semantics.dispose();
  });

  testWidgets('the chips say automatic until the user picks', (tester) async {
    final semantics = tester.ensureSemantics();
    const milk = [
      Suggestion(
        SuggestionSource.typed,
        ParsedEntry(name: 'Milch', categoryId: 'chilled'),
      ),
    ];
    await pumpList(tester, seed: (r) => r.suggestions['milch'] = milk);
    await open(tester);
    await type(tester, 'milch');
    expect(find.bySemanticsLabel('Laden: automatisch'), findsOne);
    expect(
      find.bySemanticsLabel('Kategorie: automatisch, Kühlregal'),
      findsOne,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('chip-store')),
        matching: find.text('Laden'),
      ),
      findsOne,
      reason: 'the word automatisch is not shown',
    );

    for (final (chip, option) in [
      ('chip-store', 'store-option-lidl'),
      ('chip-category', 'category-option-chilled'),
    ]) {
      await tester.tap(find.byKey(ValueKey(chip)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(option)));
      await tester.pumpAndSettle();
    }
    expect(find.bySemanticsLabel('Laden: Lidl'), findsOne);
    expect(
      find.bySemanticsLabel('Kategorie: Kühlregal'),
      findsOne,
      reason: 'picking the guess is still a pick',
    );
    semantics.dispose();
  });
}

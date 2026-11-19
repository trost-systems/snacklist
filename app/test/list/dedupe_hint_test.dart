import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/entry.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/list/list_view/item_row.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'fake_repository.dart';
import 'memory_cache.dart';

/// Records what the list tracks; the real sender is tested elsewhere.
class _Tracked() implements Analytics {
  final events = <String>[];

  @override
  void track(String event, [Map<String, Object> properties = const {}]) =>
      events.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Job 32b (Spec #8 AC9, AC11): adding "Karotten" while "Möhren" is open
/// adds it and offers a one-tap merge; ignoring keeps both, merging keeps
/// one, undo brings both back.
void main() {
  late FakeRepository repo;
  late _Tracked tracked;
  late ListCubit cubit;

  setUp(
    () => VisibilityDetectorController.instance.updateInterval = Duration.zero,
  );

  Future<void> pumpList(
    WidgetTester tester, {
    String? moehren = '500 g',
  }) async {
    tester.view
      ..devicePixelRatio = 3
      ..physicalSize = const Size(390 * 3, 844 * 3);
    addTearDown(tester.view.reset);
    tracked = _Tracked();
    repo = FakeRepository()
      ..canonical.addAll({
        'Möhren': 'mohr',
        'Karotten': 'mohr',
        'Mohrrüben': 'mohr',
      })
      ..remoteAdd('Möhren', categoryId: 'produce', quantity: moehren);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: BlocProvider(
          create: (_) => cubit = ListCubit(
            repo,
            MemoryListCache(),
            userId: 'peter',
            analytics: tracked,
          )..start(),
          child: const ShoppingList(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder addField() => find.byKey(const ValueKey('add-item-field'));
  Finder row(String name) =>
      find.byWidgetPredicate((w) => w is ItemRow && w.item.name == name);
  Finder sheet() => find.byKey(const ValueKey('add-sheet'));
  Finder hint() => find.byKey(const ValueKey('dedupe-hint'));
  Finder inSheet(Finder f) => find.descendant(of: sheet(), matching: f);
  Finder inSnackBar(Finder f) =>
      find.descendant(of: find.byType(SnackBar), matching: f);
  List<String> dedupeEvents() =>
      tracked.events.where((e) => e.startsWith('dedupe_hint')).toList();
  List<(String, String?)> open() => [
    for (final i in repo.rows.values)
      if (i.status == ItemStatus.active) (i.name, i.quantity),
  ];

  /// Types [text] and sends it; the fake server parses it like the app.
  Future<void> add(WidgetTester tester, String text) async {
    final entry = parseEntry(text);
    repo.parsed[text] = ParsedEntry(
      name: entry.name,
      quantity: entry.quantity,
      categoryId: entry.name == 'Milch' ? 'chilled' : 'produce',
    );
    await tester.enterText(addField(), text);
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
  }

  Future<void> closeSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('add-sheet-close')));
    await tester.pumpAndSettle();
  }

  void accessibleNavigation(WidgetTester tester) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(accessibleNavigation: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }

  testWidgets('adding Karotten with Möhren open adds it and shows the hint '
      'in the sheet, under what was added', (tester) async {
    await pumpList(tester);
    await add(tester, '1 kg Karotten');

    expect(open(), [('Möhren', '500 g'), ('Karotten', '1 kg')]);
    expect(inSheet(hint()), findsOneWidget);
    expect(
      inSheet(find.text('Möhren steht schon auf der Liste')),
      findsOneWidget,
    );
    expect(inSheet(find.text('Zusammenführen')), findsOneWidget);
    expect(inSheet(find.text('✓ Hinzugefügt: Karotten')), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing, reason: 'none over the sheet');
    expect(dedupeEvents(), ['dedupe_hint_shown']);
  });

  testWidgets('Zusammenführen in the sheet sums into Möhren; Rückgängig '
      'there brings both back exactly', (tester) async {
    await pumpList(tester);
    await add(tester, '1 kg Karotten');
    final karotten = repo.rows.values.firstWhere((i) => i.name == 'Karotten');

    await tester.tap(find.byKey(const ValueKey('dedupe-merge')));
    await tester.pumpAndSettle();
    expect(open(), [('Möhren', '1,5 kg')]);
    expect(
      inSheet(find.text('Zusammengeführt: 1,5 kg Möhren')),
      findsOneWidget,
    );
    expect(dedupeEvents(), ['dedupe_hint_shown', 'dedupe_hint_merged']);
    expect(
      tester.widget<TextField>(addField()).focusNode!.hasFocus,
      isTrue,
      reason: 'typing goes on',
    );

    await tester.tap(find.byKey(const ValueKey('dedupe-undo')));
    await tester.pumpAndSettle();
    expect(open(), [('Möhren', '500 g'), ('Karotten', '1 kg')]);
    final back = repo.rows[karotten.id]!;
    expect(
      (back.name, back.quantity, back.categoryId, back.addedBy, back.createdAt),
      (
        karotten.name,
        karotten.quantity,
        karotten.categoryId,
        karotten.addedBy,
        karotten.createdAt,
      ),
    );
    expect(inSheet(find.text('✓ Hinzugefügt: Karotten')), findsOneWidget);
    expect(hint(), findsNothing);
    expect(dedupeEvents(), ['dedupe_hint_shown', 'dedupe_hint_merged']);
  });

  testWidgets('closing the sheet hands the hint to a snackbar; ignored, both '
      'stay', (tester) async {
    await pumpList(tester);
    await add(tester, '1 kg Karotten');
    await closeSheet(tester);
    expect(
      inSnackBar(find.text('Möhren steht schon auf der Liste')),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(hint(), findsNothing);
    expect(row('Möhren'), findsOneWidget);
    expect(row('Karotten'), findsOneWidget);
    expect(open(), [('Möhren', '500 g'), ('Karotten', '1 kg')]);
    expect(dedupeEvents(), ['dedupe_hint_shown', 'dedupe_hint_ignored']);
  });

  for (final accessible in [false, true]) {
    testWidgets('Zusammenführen on the snackbar merges, Rückgängig on the '
        'next one undoes${accessible ? ' (no animations: web, screen '
                  'readers)' : ''}', (tester) async {
      if (accessible) {
        accessibleNavigation(tester);
      }
      await pumpList(tester);
      await add(tester, '1 kg Karotten');
      await closeSheet(tester);

      await tester.tap(inSnackBar(find.text('Zusammenführen')));
      await tester.pumpAndSettle();
      expect(open(), [('Möhren', '1,5 kg')]);
      expect(row('Karotten'), findsNothing);
      expect(
        inSnackBar(find.text('Zusammengeführt: 1,5 kg Möhren')),
        findsOneWidget,
      );
      expect(dedupeEvents(), ['dedupe_hint_shown', 'dedupe_hint_merged']);

      await tester.tap(inSnackBar(find.text('Rückgängig')));
      await tester.pumpAndSettle();
      expect(open(), [('Möhren', '500 g'), ('Karotten', '1 kg')]);
      expect(row('Karotten'), findsOneWidget);
      expect(dedupeEvents(), ['dedupe_hint_shown', 'dedupe_hint_merged']);
    });
  }

  testWidgets('a merge in the sheet keeps its undo after the sheet closes', (
    tester,
  ) async {
    await pumpList(tester);
    await add(tester, '1 kg Karotten');
    await tester.tap(find.byKey(const ValueKey('dedupe-merge')));
    await tester.pumpAndSettle();
    await closeSheet(tester);
    await tester.tap(inSnackBar(find.text('Rückgängig')));
    await tester.pumpAndSettle();
    expect(open(), [('Möhren', '500 g'), ('Karotten', '1 kg')]);
  });

  testWidgets('units that do not convert: the open item keeps its text and '
      'notes the other quantity', (tester) async {
    await pumpList(tester, moehren: '1 Bund');
    await add(tester, '500 g Karotten');
    await tester.tap(find.byKey(const ValueKey('dedupe-merge')));
    await tester.pumpAndSettle();
    expect(open(), [('Möhren', '1 Bund + 500 g')]);
  });

  testWidgets('the typed text is never rewritten and nothing merges by '
      'itself', (tester) async {
    await pumpList(tester);
    await add(tester, 'Mohrrüben');
    await closeSheet(tester);
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(open(), [('Möhren', '500 g'), ('Mohrrüben', null)]);
  });

  testWidgets("typing on, the add's undo, or a ticked Möhren take the hint "
      'away, as ignored', (tester) async {
    await pumpList(tester);
    await add(tester, '1 kg Karotten');
    await tester.enterText(addField(), 'B');
    await tester.pumpAndSettle();
    expect(hint(), findsNothing);

    await tester.enterText(addField(), '');
    await add(tester, '2 Mohrrüben');
    expect(hint(), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('added-undo')));
    await tester.pumpAndSettle();
    expect(hint(), findsNothing);
    expect(open().map((i) => i.$1), ['Möhren', 'Karotten']);

    final moehren = repo.rows.values.firstWhere((i) => i.name == 'Möhren');
    repo.canonical['Gelbe Rüben'] = 'mohr';
    await add(tester, 'Gelbe Rüben');
    await closeSheet(tester);
    expect(hint(), findsOneWidget);
    cubit.tick(moehren.id);
    await tester.pumpAndSettle();
    // Karotten is older than Gelbe Rüben's add, so a ticked Möhren leaves
    // Karotten as the open item; the hint named Möhren and goes.
    expect(find.text('Möhren steht schon auf der Liste'), findsNothing);
    expect(dedupeEvents(), [
      for (var i = 0; i < 3; i++) ...[
        'dedupe_hint_shown',
        'dedupe_hint_ignored',
      ],
    ]);
  });

  testWidgets('no hint for an item without a similar one', (tester) async {
    await pumpList(tester);
    await add(tester, 'Milch');
    expect(hint(), findsNothing);
    expect(dedupeEvents(), isEmpty);
  });

  testWidgets('a merge the server refuses keeps both and says so', (
    tester,
  ) async {
    await pumpList(tester);
    await add(tester, '1 kg Karotten');
    final refused = <Rejected>[];
    final listening = cubit.rejections.listen(refused.add);
    addTearDown(listening.cancel);
    repo.reject = true;
    await tester.tap(find.byKey(const ValueKey('dedupe-merge')));
    await tester.pumpAndSettle();
    expect(open(), [('Möhren', '500 g'), ('Karotten', '1 kg')]);
    // The resync after the refusal shows Karotten again.
    expect(row('Karotten'), findsOneWidget);
    expect(refused, [
      isA<MergeRefused>().having((r) => r.name, 'name', 'Möhren'),
    ]);
  });

  group('a rename onto an open item (job 104)', () {
    Future<void> rename(WidgetTester tester, String from, String to) async {
      repo.emitItem!(
        repo.remoteAdd(from, categoryId: 'produce', quantity: '1 kg'),
      );
      await tester.pumpAndSettle();
      await tester.tap(row(from), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('edit-name')), to);
      await tester.tap(find.byKey(const ValueKey('edit-done')));
      await tester.pumpAndSettle();
    }

    for (final (to, back) in [('möhren', 'Rüben')]) {
      testWidgets('renaming Rüben to "$to" merges into Möhren and says so; '
          'Rückgängig brings $back back', (tester) async {
        await pumpList(tester);
        await rename(tester, 'Rüben', to);
        expect(open(), [('Möhren', '1,5 kg')]);
        expect(row(to), findsNothing);
        expect(
          inSnackBar(find.text('Zusammengeführt: 1,5 kg Möhren')),
          findsOneWidget,
        );
        expect(dedupeEvents(), isEmpty, reason: 'no hint was shown');

        await tester.tap(inSnackBar(find.text('Rückgängig')));
        await tester.pumpAndSettle();
        expect(open(), [('Möhren', '500 g'), (back, '1 kg')]);
        expect(row(back), findsOneWidget);
      });
    }

    testWidgets('renaming Rüben to the synonym "Karotten" only offers the '
        'merge, as an add does', (tester) async {
      await pumpList(tester);
      await rename(tester, 'Rüben', 'Karotten');
      expect(open(), [('Möhren', '500 g'), ('Karotten', '1 kg')]);
      expect(
        inSnackBar(find.text('Möhren steht schon auf der Liste')),
        findsOneWidget,
      );
      expect(find.text('Zusammengeführt: 1,5 kg Möhren'), findsNothing);
      expect(dedupeEvents(), ['dedupe_hint_shown']);
    });

    testWidgets('a merge that cannot be done is refused as on the list', (
      tester,
    ) async {
      await pumpList(tester, moehren: 'eine große Packung vom Wochenmarkt');
      final refused = <Rejected>[];
      final listening = cubit.rejections.listen(refused.add);
      addTearDown(listening.cancel);
      await rename(tester, 'Rüben', 'Möhren');
      expect(open(), [
        ('Möhren', 'eine große Packung vom Wochenmarkt'),
        ('Rüben', '1 kg'),
      ]);
      expect(row('Rüben'), findsOneWidget);
      expect(refused, [
        isA<RenameTaken>().having((r) => r.name, 'name', 'Möhren'),
      ]);
    });

    testWidgets('a rename to another name is just a rename', (tester) async {
      await pumpList(tester);
      await rename(tester, 'Rüben', 'Rote Bete');
      expect(open(), [('Möhren', '500 g'), ('Rote Bete', '1 kg')]);
      expect(find.byType(SnackBar), findsNothing);
    });
  });
}

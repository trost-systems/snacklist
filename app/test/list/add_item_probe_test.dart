import 'dart:convert';
import 'dart:io';

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/catalog/catalog_index.dart';
import 'package:family_groceries/list/catalog/household_index.dart';
import 'package:family_groceries/list/catalog/suggest_entries.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../design/fonts.dart';
import 'fake_repository.dart';
import 'memory_cache.dart';

/// The add-item hill climb's probe (job 457,
/// `tool/hillclimb/hc-add-item-voice/measure.sh`): the add sheet with the
/// flags users have, timed per key and per Enter, and how many keys the
/// device ranking needs before the item meant is the first row. Prints one
/// JSON line. Runs only with HC_ADD_PROBE=1.
void main() {
  final probe = Platform.environment['HC_ADD_PROBE'] == '1';

  setUpAll(loadAppFonts);

  testWidgets('add sheet: per key and per Enter', skip: !probe, (tester) async {
    tester.view
      ..devicePixelRatio = 3
      ..physicalSize = const Size(390, 844) * 3;
    addTearDown(tester.view.reset);
    final repo = FakeRepository();
    _open.forEach(repo.remoteAdd);
    final list = ListCubit(repo, MemoryListCache(), userId: 'peter')..start();
    final flags = Flags(
      forced: {
        inputStableRowsFlag,
        onDeviceCatalogFlag,
        addFeedbackListFlag,
        addSheetCompactFlag,
        addMatchRowsFlag,
        listDeclutterFlag,
        hideCategoriesFlag,
      },
    );
    addTearDown(list.close);
    addTearDown(flags.close);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: flags),
          BlocProvider.value(value: list),
        ],
        child: MaterialApp.router(
          theme: appTheme(Brightness.light),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => const Scaffold(body: ShoppingList()),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('add-item-field'));
    await tester.tap(field);
    await tester.pumpAndSettle();

    final keys = <int>[];
    final enters = <int>[];
    var added = 0;
    for (final (round, line) in [..._lines, ..._lines].indexed) {
      for (var n = 1; n <= line.length; n++) {
        final watch = Stopwatch()..start();
        await tester.enterText(field, line.substring(0, n));
        await tester.pump();
        if (round >= _lines.length) {
          keys.add(watch.elapsedMicroseconds);
        }
      }
      await tester.pump(const Duration(milliseconds: 200));
      final before = _active(list);
      final watch = Stopwatch()..start();
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      final took = watch.elapsedMicroseconds;
      if (_active(list) > before) {
        added++;
        if (round >= _lines.length) {
          enters.add(took);
        }
      }
      await tester.pumpAndSettle();
      // A second round's line is on the list: tick it so Enter adds again.
      for (final item in list.state.items.values.toList()) {
        if (item.status == ItemStatus.active && !_open.contains(item.name)) {
          list.tick(item.id, inAddSheet: true);
        }
      }
      await tester.pumpAndSettle();
    }

    final result = {
      'key_us_p50': _p(keys, 50),
      'key_us_p95': _p(keys, 95),
      'enter_us_p50': _p(enters, 50),
      'enter_us_p95': _p(enters, 95),
      'keys_timed': keys.length,
      'enters_timed': enters.length,
      'adds': added,
      'adds_expected': _lines.length * 2,
      ..._rankKeys(),
    };
    // ignore: avoid_print -- the probe's result
    print('HC_ADD_PROBE ${jsonEncode(result)}');
  });
}

int _active(ListCubit list) => list.state.items.values
    .where((item) => item.status == ItemStatus.active)
    .length;

int _p(List<int> values, int percentile) {
  final sorted = [...values]..sort();
  return sorted.isEmpty ? -1 : sorted[(sorted.length - 1) * percentile ~/ 100];
}

/// Keys typed before the item meant is one of the first three rows, as a
/// share of its length (1: only the whole name; 1.25: never), over every
/// 25th catalog term with no history, then the same terms with the
/// household having bought every fourth of them (the repeat buys).
Map<String, Object> _rankKeys() {
  final catalog = CatalogIndex.bundled;
  final terms = [
    for (final (i, term) in catalog.terms.keys.indexed)
      if (i % 25 == 0 && term.length >= 3) _capital(term),
  ];
  final categories = Catalog(
    categories: [
      for (final (i, seed) in const [
        'produce', 'chilled', 'pantry', 'drinks', 'bakery', 'meat', //
        'frozen', 'sweets', 'household', 'drugstore', 'other',
      ].indexed)
        Category(id: seed, name: seed, sortOrder: i, seedKey: seed),
    ],
  );
  final start = DateTime.utc(2026, 11, 16);
  final bought = [
    for (final (i, term) in terms.indexed)
      if (i % 4 == 0) term,
  ];
  final history = HouseholdIndex(
    history: [
      for (final (i, name) in bought.indexed)
        (
          name: name,
          brand: null,
          properties: null,
          quantity: null,
          normalizedName: normalizeItemName(name),
          at: start.subtract(Duration(days: i % 30)),
        ),
    ],
  );
  double share(String target, HouseholdIndex household) {
    final folded = target.toLowerCase();
    for (var n = 1; n <= target.length; n++) {
      final rows = suggestEntries(
        target.substring(0, n),
        catalog: catalog,
        household: household,
        categories: categories,
        known: const {},
      );
      if (rows.take(3).any((row) => row.entry.name.toLowerCase() == folded)) {
        return n / target.length;
      }
    }
    return 1.25;
  }

  double mean(Iterable<double> values) =>
      values.fold<double>(0, (a, b) => a + b) / values.length;
  const empty = HouseholdIndex.empty;
  return {
    'rank_terms': terms.length,
    'rank_keys_new': double.parse(
      mean(terms.map((t) => share(t, empty))).toStringAsFixed(4),
    ),
    'rank_keys_bought': double.parse(
      mean(bought.map((t) => share(t, history))).toStringAsFixed(4),
    ),
  };
}

String _capital(String word) => word[0].toUpperCase() + word.substring(1);

const _open = [
  'Joghurt', 'Nudeln', 'Bananen', 'Butter', 'Eier', 'Brot', 'Käse', //
  'Tomaten', 'Gurke', 'Reis', 'Kaffee', 'Tee', 'Zwiebeln', 'Kartoffeln',
  'Hackfleisch', 'Spülmittel', 'Toilettenpapier', 'Orangensaft', 'Mehl',
  'Zucker', 'Salz', 'Pfeffer', 'Paprika', 'Möhren', 'Quark', 'Sahne',
  'Haferflocken', 'Honig', 'Marmelade', 'Wasser',
];

const _lines = [
  'Milch',
  '2 Äpfel',
  'Rote Bete',
  'Hafermilch Barista',
  'Spülmaschinentabs',
  'Schokolade Zartbitter',
  'Feta',
  'Brokkoli',
  'Kidneybohnen',
  'Windeln Größe 4',
  'Zitronen',
  'Basilikum',
];

import 'dart:async';

import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cache.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_link.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/list/list_view/item_row.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'fake_repository.dart';
import 'memory_cache.dart';

/// Job 66: `/add` and `/stores/<id>` links, as the router hands them to
/// the list.
void main() {
  /// The top of the list's visible band: below the floating bar, which the
  /// rows scroll on under (job 148).
  double barBottom(WidgetTester tester) =>
      tester.getRect(find.byKey(const ValueKey('list-header'))).bottom;

  late FakeRepository repo;
  late MemoryListCache cache;
  late ListLinks links;

  setUp(() {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    repo = FakeRepository();
    cache = MemoryListCache();
    links = ListLinks();
    addTearDown(links.dispose);
  });

  Future<void> pumpList(
    WidgetTester tester, {
    Size size = const Size(390, 844),
  }) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepositoryProvider.value(
        value: links,
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: BlocProvider(
            create: (_) => ListCubit(repo, cache, userId: 'peter')..start(),
            child: const ShoppingList(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder row(String name) =>
      find.byWidgetPredicate((w) => w is ItemRow && w.item.name == name);
  Finder storeDivider(String key) => find.byKey(ValueKey('store-$key'));

  /// Thirty stores of four items each; `s6` folded and, in every layout,
  /// below the first screen.
  void seedStores() {
    repo.stores = [
      for (var i = 0; i < 30; i++)
        Store(id: 's$i', name: 'Laden $i', sortOrder: i),
    ];
    for (var i = 0; i < 30; i++) {
      for (var j = 0; j < 4; j++) {
        repo.remoteAdd('Ding $i-$j', storeId: 's$i', categoryId: 'other');
      }
    }
    cache.prefs = const ListPrefs(folded: {'s6'});
  }

  test('the list links of a location', () {
    expect(listLinkOf(Uri.parse('/add')), isA<AddLink>());
    expect(
      listLinkOf(Uri.parse('https://app.snacklist.app/stores/s1')),
      isA<StoreLink>().having((l) => l.storeId, 'storeId', 's1'),
    );
    for (final other in ['/', '/list', '/stores', '/stores/a/b', '/more']) {
      expect(listLinkOf(Uri.parse(other)), isNull, reason: other);
    }
  });

  testWidgets('a cold start at /add opens the sheet, the field focused', (
    tester,
  ) async {
    links.pending = const AddLink();
    await pumpList(tester);
    expect(find.byKey(const ValueKey('add-sheet')), findsOneWidget);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('add-item-field')),
    );
    expect(field.focusNode!.hasFocus, isTrue);
  });

  testWidgets('/add while the list is open opens the sheet', (tester) async {
    await pumpList(tester);
    expect(find.byKey(const ValueKey('add-sheet')), findsNothing);
    links.pending = const AddLink();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('add-sheet')), findsOneWidget);
  });

  for (final (layout, size) in const [
    ('one column', Size(390, 844)),
    ('two columns', Size(1000, 800)),
    ('three columns', Size(1400, 800)),
  ]) {
    testWidgets('$layout: /stores/<id> unfolds the store at the top', (
      tester,
    ) async {
      seedStores();
      await pumpList(tester, size: size);
      expect(row('Ding 6-0'), findsNothing);
      links.pending = const StoreLink('s6');
      await tester.pumpAndSettle();
      expect(row('Ding 6-0'), findsOneWidget);
      final divider = tester.getRect(storeDivider('s6'));
      expect(divider.top, moreOrLessEquals(barBottom(tester), epsilon: 1));
      expect(cache.prefs!.folded, isEmpty);
    });
  }

  testWidgets('a cold start at /stores/<id> waits for the list', (
    tester,
  ) async {
    seedStores();
    links.pending = const StoreLink('s6');
    await pumpList(tester);
    expect(row('Ding 6-0'), findsOneWidget);
    expect(
      tester.getRect(storeDivider('s6')).top,
      moreOrLessEquals(barBottom(tester), epsilon: 1),
    );
  });

  testWidgets('a cold start at /stores/<id> waits for the server when the '
      "device's copy lacks the store", (tester) async {
    seedStores();
    cache.saved = ListSnapshot(
      catalog: await repo.fetchCatalog(),
      server: const [],
      pending: const [],
    );
    final items = repo.itemsGate = Completer<void>();
    links.pending = const StoreLink('s6');
    await pumpList(tester);
    expect(row('Ding 0-0'), findsNothing);
    items.complete();
    await tester.pumpAndSettle();
    expect(row('Ding 6-0'), findsOneWidget);
    expect(
      tester.getRect(storeDivider('s6')).top,
      moreOrLessEquals(barBottom(tester), epsilon: 1),
    );
  });

  testWidgets('an offline cold start decides a store link against the '
      "device's copy, and reconnecting leaves the list as it is", (
    tester,
  ) async {
    seedStores();
    cache.saved = ListSnapshot(
      catalog: await repo.fetchCatalog(),
      server: const [],
      pending: const [],
    );
    repo.online = false;
    links.pending = const StoreLink('s6');
    await pumpList(tester);
    expect(links.pending, isNull);
    repo.online = true;
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(row('Ding 0-0'), findsOneWidget);
    expect(row('Ding 6-0'), findsNothing);
    expect(cache.prefs!.folded, {'s6'});
  });

  testWidgets('an unknown store leaves the list as it is', (tester) async {
    seedStores();
    await pumpList(tester);
    links.pending = const StoreLink('gone');
    await tester.pumpAndSettle();
    expect(row('Ding 0-0'), findsOneWidget);
    expect(cache.prefs!.folded, {'s6'});
  });
}

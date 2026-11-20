import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cache.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_repository.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/list/list_view/chain_card.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/retailer.dart';
import 'package:family_groceries/list/store_app.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_repository.dart';
import 'memory_cache.dart';

RetailerApp _app(String name) =>
    RetailerApp(name: name, android: 'app.$name', ios: '1');

final _lidl = Retailer(
  chain: 'lidl',
  country: 'DE',
  name: 'Lidl',
  apps: [_app('Lidl Plus')],
);
final _aldiNord = Retailer(
  chain: 'aldi-nord',
  country: 'DE',
  name: 'ALDI Nord',
  apps: [_app('ALDI Nord')],
);
final _aldiSued = Retailer(
  chain: 'aldi-sued',
  country: 'DE',
  name: 'ALDI SÜD',
  apps: [_app('ALDI SÜD')],
);
const _market = Retailer(chain: 'markt', country: 'DE', name: 'Wochenmarkt');

final class _Opener() implements StoreAppOpener {
  @override
  Future<bool> launchPackage(String package) async => true;

  @override
  Future<bool> openLink(Uri url, {required bool appOnly}) async => true;
}

/// Job 313 (SS5): the list's card asks existing stores for their chain,
/// one at a time, only where the chain has an app.
void main() {
  late FakeRepository repo;

  Future<void> pumpList(
    WidgetTester tester, {
    bool flag = true,
    List<Store>? stores,
  }) async {
    repo = FakeRepository()
      ..retailers = [_lidl, _aldiNord, _aldiSued, _market]
      ..aliases = {
        _aldiNord.key: ['aldi', 'aldi nord'],
        _aldiSued.key: ['aldi', 'aldi süd'],
      }
      ..stores =
          stores ??
          const [
            Store(id: 'dm', name: 'dm', sortOrder: 10),
            Store(id: 'lidl', name: 'Lidl', sortOrder: 20),
            Store(id: 'aldi', name: 'Aldi', sortOrder: 30),
            Store(id: 'markt', name: 'Wochenmarkt', sortOrder: 40),
          ]
      ..remoteAdd('Milch', storeId: 'lidl')
      ..remoteAdd('Brot', storeId: 'aldi');
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: MultiBlocProvider(
          providers: [
            BlocProvider(
              create: (_) => Flags(forced: {if (flag) openStoreAppFlag}),
            ),
            BlocProvider(
              create: (_) => ListCubit(
                repo,
                MemoryListCache()
                  ..prefs = const ListPrefs(
                    hintDismissed: true,
                    storeAppTipClosed: true,
                  ),
                userId: 'peter',
                region: () => 'DE',
              )..start(),
            ),
          ],
          child: RepositoryProvider<StoreAppOpener>.value(
            value: _Opener(),
            child: const ShoppingList(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(ChainCard.settle);
    await tester.pumpAndSettle();
  }

  Finder card() => find.byKey(const ValueKey('chain-question'));
  String progress(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey('chain-card-progress')))
      .data!;

  testWidgets('flag off: no card and nothing asked', (tester) async {
    await pumpList(tester, flag: false);
    expect(card(), findsNothing);
    expect(repo.retailerCountries, isEmpty);
  });

  testWidgets('asks store by store with its progress; Ja links, a chain '
      'button picks one of two', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpList(tester);
    expect(repo.retailerCountries, ['DE'], reason: "the phone's region");
    expect(card(), findsOneWidget);
    expect(
      progress(tester),
      '1 / 2',
      reason:
          'Lidl and Aldi; dm and the '
          'market have no chain with an app',
    );
    expect(find.bySemanticsLabel('Laden 1 von 2'), findsOneWidget);
    expect(
      find.text('Ist dein „Lidl“ die Kette Lidl (Deutschland)?'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Erkannte Läden können einen Knopf für ihre App zeigen. Die Namen '
        'bleiben, wie du sie geschrieben hast.',
      ),
      findsOneWidget,
      reason: 'Legal N-293, word for word',
    );
    tester.takeAnnouncements();

    await tester.tap(find.byKey(const ValueKey('chain-question-yes')));
    await tester.pumpAndSettle();
    expect(tester.takeAnnouncements(), [
      isAccessibilityAnnouncement('Zugeordnet'),
    ]);
    expect(
      repo.catalogCalls,
      contains('answerStoreRetailer(lidl, lidl, DE, null)'),
    );
    expect(progress(tester), '2 / 2');
    expect(
      find.byKey(const ValueKey('store-app-lidl')),
      findsOneWidget,
      reason: 'the linked store gets its key at once',
    );

    await tester.tap(find.byKey(const ValueKey('chain-question-aldi-sued-DE')));
    await tester.pumpAndSettle();
    expect(
      repo.catalogCalls,
      contains('answerStoreRetailer(aldi, aldi-sued, DE, null)'),
    );
    await tester.pump(ChainCard.settle);
    await tester.pumpAndSettle();
    expect(card(), findsNothing, reason: 'every store answered');
    semantics.dispose();
  });

  testWidgets('Nein is stored and never asked again', (tester) async {
    await pumpList(
      tester,
      stores: const [Store(id: 'lidl', name: 'Lidl', sortOrder: 20)],
    );
    expect(progress(tester), '1 / 1');
    await tester.tap(find.byKey(const ValueKey('chain-question-no')));
    await tester.pumpAndSettle();
    expect(
      repo.catalogCalls,
      contains('answerStoreRetailer(lidl, null, null, null)'),
    );
    expect(card(), findsNothing);
    expect(repo.stores.single.retailerAnswered, isTrue);
    expect(find.byKey(const ValueKey('store-app-lidl')), findsNothing);
  });

  testWidgets('asks again when the stores change, not when items do', (
    tester,
  ) async {
    await pumpList(
      tester,
      stores: const [Store(id: 'dm', name: 'dm', sortOrder: 10)],
    );
    expect(card(), findsNothing);
    expect(repo.retailerCountries, hasLength(1));

    repo
      ..remoteAdd('Butter', storeId: 'dm')
      ..emitCatalogChanged?.call();
    await tester.pumpAndSettle();
    await tester.pump(ChainCard.settle);
    await tester.pumpAndSettle();
    expect(repo.retailerCountries, hasLength(1), reason: 'same stores');

    repo
      ..stores = [
        ...repo.stores,
        const Store(id: 'lidl', name: 'Lidl', sortOrder: 20),
      ]
      ..emitCatalogChanged?.call();
    await tester.pumpAndSettle();
    await tester.pump(ChainCard.settle);
    await tester.pumpAndSettle();
    expect(repo.retailerCountries, hasLength(2));
    expect(card(), findsOneWidget, reason: 'the new Lidl is asked about');
  });

  testWidgets('offline or behind the add sheet: no card', (tester) async {
    tester.view
      ..devicePixelRatio = 3
      ..physicalSize = const Size(390 * 3, 844 * 3);
    addTearDown(tester.view.reset);
    await pumpList(tester);
    expect(card(), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('add-item-field')));
    await tester.pumpAndSettle();
    expect(card(), findsNothing, reason: 'the add sheet is open');
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(card(), findsOneWidget, reason: 'the sheet closed');

    repo.online = false;
    await tester.tap(find.text('Milch'));
    await tester.pump(const Duration(seconds: 10));
    expect(
      tester
          .element(find.byType(ShoppingList))
          .read<ListCubit>()
          .state
          .connection,
      ConnectionStatus.offline,
    );
    expect(card(), findsNothing, reason: 'offline');
  });
}

import 'dart:async';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/design/sticker.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cache.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/list/list_view/item_row.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/retailer.dart';
import 'package:family_groceries/list/store_app.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'fake_repository.dart';
import 'memory_cache.dart';

const _lidl = Retailer(
  chain: 'lidl',
  country: 'DE',
  name: 'Lidl',
  apps: [
    RetailerApp(
      name: 'Lidl Plus',
      android: 'com.lidl.eci.lidlplus',
      ios: '1238611143',
    ),
  ],
);

final class _Opener() implements StoreAppOpener {
  final opened = <String>[];

  @override
  Future<bool> launchPackage(String package) async {
    opened.add(package);
    return true;
  }

  @override
  Future<bool> openLink(Uri url, {required bool appOnly}) async {
    opened.add('$url');
    return true;
  }
}

final class _Tracked() implements Analytics {
  final events = <(String, Map<String, Object>)>[];

  @override
  void track(String event, [Map<String, Object> properties = const {}]) =>
      events.add((event, properties));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Job 399 (SC1): the „… ist erledigt“ card after the user ticked a linked
/// store's last open item.
void main() {
  late FakeRepository repo;
  late MemoryListCache cache;
  late _Opener opener;
  late _Tracked tracked;

  setUp(
    () => VisibilityDetectorController.instance.updateInterval = Duration.zero,
  );

  Future<void> pumpList(
    WidgetTester tester, {
    bool flag = true,
    String? addedBy = 'lea',
    String lidlName = 'Lidl',
    bool compact = false,
  }) async {
    repo = FakeRepository()
      ..retailers = const [_lidl]
      ..stores = [
        const Store(id: 'dm', name: 'dm', sortOrder: 10, seedKey: 'dm'),
        Store(
          id: 'lidl',
          name: lidlName,
          sortOrder: 20,
          seedKey: 'lidl',
          retailer: _lidl,
          retailerAnswered: true,
        ),
      ]
      ..remoteAdd('Milch', storeId: 'lidl', addedBy: addedBy)
      ..remoteAdd('Butter', storeId: 'lidl', addedBy: addedBy)
      ..remoteAdd('Seife', storeId: 'dm', addedBy: addedBy)
      ..remoteAdd('Zahnpasta', storeId: 'dm', addedBy: addedBy);
    cache = MemoryListCache()
      ..prefs = const ListPrefs(hintDismissed: true, storeAppTipClosed: true);
    opener = _Opener();
    tracked = _Tracked();
    Widget app(Widget home) => compact
        ? MaterialApp.router(
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('de'),
            routerConfig: GoRouter(
              routes: [GoRoute(path: '/', builder: (_, _) => home)],
            ),
          )
        : MaterialApp(
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('de'),
            home: home,
          );
    await tester.pumpWidget(
      app(
        MultiBlocProvider(
          providers: [
            BlocProvider(
              create: (_) => Flags(
                forced: {
                  if (flag) openStoreAppFlag,
                  if (compact) ...{addFeedbackListFlag, addSheetCompactFlag},
                },
              ),
            ),
            BlocProvider(
              create: (_) => ListCubit(repo, cache, userId: 'peter')..start(),
            ),
          ],
          child: MultiRepositoryProvider(
            providers: [
              RepositoryProvider<StoreAppOpener>.value(value: opener),
              RepositoryProvider<Analytics>.value(value: tracked),
            ],
            child: const Scaffold(body: ShoppingList()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder card([String store = 'lidl']) =>
      find.byKey(ValueKey('store-done-$store'));
  Finder row(String name) =>
      find.byWidgetPredicate((w) => w is ItemRow && w.item.name == name);
  String idOf(String name) =>
      repo.rows.values.firstWhere((i) => i.name == name).id;

  Future<void> tick(WidgetTester tester, String name) async {
    await tester.tap(row(name));
    await tester.pumpAndSettle();
  }

  /// Lea ticks [name] on her phone.
  Future<void> leaTicks(WidgetTester tester, String name) async {
    final id = idOf(name);
    repo.emitItem!(
      repo.rows[id] = repo.rows[id]!.copyWith(
        status: ItemStatus.bought,
        boughtAt: DateTime.now,
        boughtBy: () => 'lea',
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('ticking the last item of a linked store shows the card at '
      "the list's top", (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpList(tester);
    await tick(tester, 'Milch');
    expect(card(), findsNothing, reason: 'Butter is still open');
    await tick(tester, 'Butter');
    expect(card(), findsOneWidget);
    expect(find.text('Lidl ist erledigt'), findsOneWidget);
    expect(find.text('App öffnen'), findsOneWidget);
    expect(
      find.descendant(of: card(), matching: find.byType(Icon)),
      findsOneWidget,
      reason: 'only the X has an icon',
    );
    expect(
      tester.getSemantics(find.byKey(const ValueKey('store-done-open'))),
      matchesSemantics(
        label: 'Lidl Plus öffnen',
        isButton: true,
        isFocusable: true,
        isEnabled: true,
        hasEnabledState: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    expect(
      tester.getTopLeft(card()).dy,
      lessThan(tester.getTopLeft(row('Seife')).dy),
      reason: 'above the stores',
    );
    semantics.dispose();
  });

  testWidgets('flag off: no card', (tester) async {
    await pumpList(tester, flag: false);
    await tick(tester, 'Milch');
    await tick(tester, 'Butter');
    expect(card(), findsNothing);
  });

  testWidgets('a store without an app link gets no card', (tester) async {
    await pumpList(tester);
    await tick(tester, 'Seife');
    await tick(tester, 'Zahnpasta');
    expect(row('Zahnpasta'), findsNothing, reason: 'dm is done');
    expect(card('dm'), findsNothing);
    expect(find.textContaining('ist erledigt'), findsNothing);
  });

  testWidgets('the X closes it for this finish; a new item ticked off '
      'brings it back', (tester) async {
    await pumpList(tester);
    await tick(tester, 'Milch');
    await tick(tester, 'Butter');
    await tester.tap(find.byKey(const ValueKey('store-done-close')));
    await tester.pumpAndSettle();
    expect(card(), findsNothing);
    expect(cache.prefs?.storeDoneDismissed.keys, ['lidl'], reason: 'kept');

    await tick(tester, 'Seife');
    expect(card(), findsNothing, reason: 'stays away');

    repo.emitItem!(repo.remoteAdd('Käse', storeId: 'lidl'));
    await tester.pumpAndSettle();
    expect(card(), findsNothing, reason: 'Lidl has an open item again');
    await tick(tester, 'Käse');
    expect(card(), findsOneWidget, reason: 'done again');
  });

  testWidgets('closed while the tick waits for the server: stays closed '
      'when the server stamps its own time', (tester) async {
    await pumpList(tester);
    repo.boughtAtDelay = const Duration(seconds: 4);
    await tick(tester, 'Milch');
    repo.gate = Completer<void>();
    await tick(tester, 'Butter');
    expect(card(), findsOneWidget, reason: 'shown from the pending tick');
    await tester.tap(find.byKey(const ValueKey('store-done-close')));
    await tester.pumpAndSettle();
    expect(card(), findsNothing);

    repo.gate!.complete();
    repo.gate = null;
    await tester.pumpAndSettle();
    final butter = repo.rows.values.singleWhere((i) => i.name == 'Butter');
    expect(butter.status, ItemStatus.bought, reason: 'acknowledged');
    expect(card(), findsNothing, reason: 'the server time is no new finish');
  });

  testWidgets('„App öffnen“ opens the app, reports the card as the tap, and '
      'leaves the card', (tester) async {
    await pumpList(tester);
    await tick(tester, 'Milch');
    await tick(tester, 'Butter');
    await tester.tap(find.byKey(const ValueKey('store-done-open')));
    await tester.pumpAndSettle();
    expect(opener.opened, ['com.lidl.eci.lidlplus']);
    expect(
      [
        for (final (event, properties) in tracked.events)
          if (event == 'store_app_opened') properties,
      ],
      [
        {'chain': 'lidl', 'country': 'DE', 'outcome': 'app', 'source': 'card'},
      ],
    );
    expect(card(), findsOneWidget);
  });

  Future<void> leave(WidgetTester tester) async {
    final binding = tester.binding;
    [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ].forEach(binding.handleAppLifecycleStateChanged);
    await tester.pumpAndSettle();
    [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ].forEach(binding.handleAppLifecycleStateChanged);
    await tester.pumpAndSettle();
  }

  testWidgets('gone after background and resume; inactive alone keeps it', (
    tester,
  ) async {
    await pumpList(tester);
    await tick(tester, 'Milch');
    await tick(tester, 'Butter');
    expect(card(), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(card(), findsOneWidget, reason: 'control center is still the app');
    await leave(tester);
    expect(card(), findsNothing);
    await tick(tester, 'Seife');
    expect(card(), findsNothing, reason: 'another store: not Lidl again');
  });

  testWidgets('left while the add sheet hides the card: still gone when it '
      'closes', (tester) async {
    await pumpList(tester, compact: true);
    await tick(tester, 'Milch');
    await tick(tester, 'Butter');
    expect(card(), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('add-item-field')));
    await tester.pumpAndSettle();
    expect(card(), findsNothing, reason: 'the compact sheet hides the card');
    await leave(tester);
    await tester.tap(find.byKey(const ValueKey('add-sheet-grabber')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('add-sheet')), findsNothing);
    expect(card(), findsNothing);
  });

  testWidgets('opening the store app takes the card away on return', (
    tester,
  ) async {
    await pumpList(tester);
    await tick(tester, 'Milch');
    await tick(tester, 'Butter');
    await tester.tap(find.byKey(const ValueKey('store-done-open')));
    await tester.pumpAndSettle();
    await leave(tester);
    expect(card(), findsNothing);
  });

  testWidgets('cold start: a store finished a minute ago shows no card', (
    tester,
  ) async {
    await pumpList(tester);
    await tick(tester, 'Milch');
    await tick(tester, 'Butter');
    expect(card(), findsOneWidget);
    final saved = repo.rows.values.where((i) => i.storeId == 'lidl').toList();
    expect(saved.every((i) => i.status == ItemStatus.bought), isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: MultiBlocProvider(
          providers: [
            BlocProvider(create: (_) => Flags(forced: {openStoreAppFlag})),
            BlocProvider(
              create: (_) => ListCubit(repo, cache, userId: 'peter')..start(),
            ),
          ],
          child: MultiRepositoryProvider(
            providers: [
              RepositoryProvider<StoreAppOpener>.value(value: opener),
              RepositoryProvider<Analytics>.value(value: tracked),
            ],
            child: const ShoppingList(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(card(), findsNothing);
  });

  testWidgets('a member who only added the items sees no card', (tester) async {
    await pumpList(tester, addedBy: 'peter');
    await leaTicks(tester, 'Milch');
    await leaTicks(tester, 'Butter');
    expect(row('Butter'), findsNothing, reason: 'Lidl is done');
    expect(card(), findsNothing);
  });

  // The server's longest store name (40 characters), as one word and as
  // several: the title wraps as far as it needs, never cut.
  for (final name in [
    'Lidl',
    'Lebensmittelmarktfilialehauptbahnhofnord',
    'Hofladen Sonnenhang am Kirchplatz Nord 7',
  ]) {
    for (final scale in [1.0, 3.1]) {
      testWidgets('„$name“ at ${(scale * 100).round()} %: the button under '
          'the whole title, both inside the card', (tester) async {
        tester.view
          ..devicePixelRatio = 3
          ..physicalSize = const Size(390, 844) * 3;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpList(tester, lidlName: name);
        BlocProvider.of<ListCubit>(tester.element(find.byType(ShoppingList)))
          ..tick(idOf('Milch'))
          ..tick(idOf('Butter'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final box = tester.getRect(
          find.descendant(of: card(), matching: find.byType(HlSticker)),
        );
        final titleFinder = find.byKey(const ValueKey('store-done-title'));
        final title = tester.getRect(titleFinder);
        final button = tester.getRect(
          find.byKey(const ValueKey('store-done-open')),
        );
        expect(button.top, greaterThanOrEqualTo(title.bottom));
        expect(
          box.contains(title.topLeft) && box.contains(title.bottomRight),
          isTrue,
        );
        expect(
          box.contains(button.topLeft) && box.contains(button.bottomRight),
          isTrue,
        );
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: titleFinder, matching: find.byType(RichText)),
        );
        expect(
          title.height,
          greaterThanOrEqualTo(paragraph.getMaxIntrinsicHeight(title.width)),
          reason: "the title's every line shows",
        );
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(
          paragraph.text.toPlainText(),
          '$name ist erledigt',
          reason: 'the whole name, no ellipsis',
        );
        expect(tester.widget<Text>(titleFinder).maxLines, isNull);
      });
    }
  }
}

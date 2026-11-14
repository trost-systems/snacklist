import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/app/localizations.dart';
import 'package:family_groceries/app/notices.dart';
import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/app/theme.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/list/list_view/item_row.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/log/history_screen.dart';
import 'package:family_groceries/log/model.dart' hide TripSource;
import 'package:family_groceries/log/trip_repository.dart';
import 'package:family_groceries/purchases/entitlements.dart';
import 'package:family_groceries/purchases/premium_server.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/trip/model.dart';
import 'package:family_groceries/trip/summary_page.dart';
import 'package:family_groceries/trip/trip_cubit.dart';
import 'package:family_groceries/trip/trip_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../household/harness.dart' show TestSession;
import '../list/fake_repository.dart';
import '../list/memory_cache.dart';
import '../log/fakes.dart' show FakeTrips;
import '../purchases/fakes.dart' show FakeEntitlementsSource, FakePremiumServer;
import 'trip_cubit_test.dart' show FakeSessions, Tracked, emptyCache;

/// The server's trip sessions, also answering `trip_session` for
/// [fetched].
class Sessions() extends FakeSessions {
  final fetched = <String, FinishedTrip>{};

  /// The grocery log, whose entries of a trip go with it.
  FakeTrips? log;

  @override
  Future<FinishedTrip> fetch(String id) async =>
      fetched[id] ?? (throw StateError('no trip $id'));

  @override
  Future<void> delete(String id) async {
    await super.delete(id);
    fetched.remove(id);
    log?.rows.removeWhere((_, t) => t.sessionId == id);
  }
}

typedef Shop = ({
  FakeRepository repo,
  ListCubit list,
  TripCubit trips,
  Sessions sessions,
  GoRouter router,
  void Function(Duration) wait,
});

const session = InHousehold('peter', Household(id: 'home', name: 'Zuhause'), [
  Household(id: 'home', name: 'Zuhause'),
]);

/// The List tab on a 390x844 phone with the flag `trip-mode` on (and
/// [flags]), with what [seed] puts on the server; [premium] holds
/// Snacklist Premium. `wait` moves the cubits' clock as time passing
/// without the app running would.
Future<Shop> pumpList(
  WidgetTester tester, {
  void Function(FakeRepository repo)? seed,
  Set<String> flags = const {tripModeFlag},
  bool premium = true,
  List<Trip> logged = const [],
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('de'),
  double textScale = 1,
  Size size = const Size(390, 844),
}) async {
  tester.view
    ..devicePixelRatio = 3
    ..physicalSize = size * 3;
  addTearDown(tester.view.reset);
  var offset = Duration.zero;
  DateTime clock() => DateTime.now().add(offset);
  final repo = FakeRepository();
  (seed ??
      (repo) => repo
        ..remoteAdd('Milch', storeId: 'lidl')
        ..remoteAdd('Brot', storeId: 'lidl')
        ..remoteAdd('Seife', storeId: 'dm'))(repo);
  final list = ListCubit(repo, MemoryListCache(), userId: 'peter', clock: clock)
    ..start();
  addTearDown(list.close);
  final shownFlags = Flags(forced: flags);
  addTearDown(shownFlags.close);
  final cache = emptyCache();
  final logTrips = FakeTrips(logged);
  final sessions = Sessions()
    ..premium = premium
    ..log = logTrips;
  final trips = TripCubit(
    list,
    sessions,
    cache,
    userId: 'peter',
    householdId: 'home',
    enabled: () => shownFlags.isOn(tripModeFlag),
    logs: () => shownFlags.isOn(groceryLogFlag),
    clock: clock,
  );
  addTearDown(trips.close);
  await trips.start();
  final testSession = TestSession(session);
  addTearDown(testSession.close);
  final entitlements = Entitlements(
    FakeEntitlementsSource(unlockedNow: premium),
    testSession,
  );
  addTearDown(entitlements.close);
  final popups = Popups();
  addTearDown(popups.dispose);
  final router = GoRouter(
    observers: [popups],
    routes: [
      GoRoute(
        path: listPath,
        builder: (_, _) => const ShoppingList(),
        routes: [
          GoRoute(
            path: 'trip/:id',
            builder: (_, state) =>
                TripSummaryPage(id: state.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: historyPath,
        builder: (_, _) => const HistoryScreen(),
        routes: [
          GoRoute(
            path: 'trip/:id',
            builder: (_, state) =>
                TripSummaryPage(id: state.pathParameters['id']!),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<TripRepository>.value(value: logTrips),
        RepositoryProvider<TripSessionRepository>.value(value: sessions),
        RepositoryProvider<Analytics>.value(value: Tracked()),
        RepositoryProvider<PremiumServer>.value(value: FakePremiumServer()),
        RepositoryProvider.value(value: cache),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: shownFlags),
          BlocProvider.value(value: list),
          BlocProvider.value(value: trips),
          BlocProvider.value(value: entitlements),
          BlocProvider<SessionCubit>.value(value: testSession),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          theme: appTheme(brightness),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: NoticesHost(popups: popups, child: child!),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (
    repo: repo,
    list: list,
    trips: trips,
    sessions: sessions,
    router: router,
    wait: (Duration d) => offset += d,
  );
}

/// Job 234 on the List tab: the question after each own tick, the strip,
/// the end and its summary, the long-running rule's card, Verlauf's
/// entries of a trip.
void main() {
  setUp(
    () => VisibilityDetectorController.instance.updateInterval = Duration.zero,
  );

  Finder key(String k) => find.byKey(ValueKey(k));
  Finder row(String name) =>
      find.byWidgetPredicate((w) => w is ItemRow && w.item.name == name);
  final asked = find.text('Kaufst du gerade ein?');
  final strip = key('trip-strip');

  Future<void> tick(WidgetTester tester, String name) async {
    await tester.tap(row(name));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  Future<void> answer(WidgetTester tester, String button) async {
    await tester.tap(key(button));
    await tester.pumpAndSettle();
  }

  Future<void> startByTick(WidgetTester tester, String name) async {
    await tick(tester, name);
    expect(asked, findsOneWidget);
    await answer(tester, 'trip-ask-yes');
  }

  testWidgets('the flag off: a tick asks nothing and nothing runs', (
    tester,
  ) async {
    final shop = await pumpList(tester, flags: const {});
    await tick(tester, 'Milch');
    expect(asked, findsNothing);
    expect(strip, findsNothing);
    expect(shop.trips.state, isA<NoTrip>());
    expect(shop.sessions.saved, isEmpty);
  });

  testWidgets('every tick asks, also right after Nein', (tester) async {
    final shop = await pumpList(tester);
    await tick(tester, 'Milch');
    expect(asked, findsOneWidget);
    expect(find.text('Milch abgehakt'), findsOneWidget);
    await answer(tester, 'trip-ask-no');
    expect(asked, findsNothing);
    expect(strip, findsNothing);
    expect(shop.list.state.allItems.values.where((i) => i.name == 'Milch'), [
      isA<Item>().having((i) => i.status, 'status', ItemStatus.bought),
    ]);
    await tick(tester, 'Brot');
    expect(asked, findsOneWidget, reason: 'Nein is not remembered');
    expect(find.text('Brot abgehakt'), findsOneWidget);
    await answer(tester, 'trip-ask-no');
    expect(shop.trips.state, isA<NoTrip>());
  });

  testWidgets('Legal GL-2: a pharmacy tick asks nothing; dm and Rossmann ask', (
    tester,
  ) async {
    final shop = await pumpList(
      tester,
      seed: (repo) => repo
        ..stores = [
          ...repo.stores,
          const Store(id: 'apo', name: 'Apotheke', sortOrder: 30),
          const Store(id: 'ross', name: 'Rossmann', sortOrder: 40),
        ]
        ..remoteAdd('Aspirin', storeId: 'apo')
        ..remoteAdd('Seife', storeId: 'dm')
        ..remoteAdd('Zahnpasta', storeId: 'ross'),
    );
    await tick(tester, 'Aspirin');
    expect(asked, findsNothing);
    expect(shop.trips.state, isA<NoTrip>());
    await tick(tester, 'Seife');
    expect(asked, findsOneWidget, reason: 'a drugstore is no pharmacy');
    await answer(tester, 'trip-ask-no');
    await tick(tester, 'Zahnpasta');
    expect(asked, findsOneWidget);
    await answer(tester, 'trip-ask-no');
  });

  testWidgets('a dismissed sheet is Nein', (tester) async {
    final shop = await pumpList(tester);
    await tick(tester, 'Milch');
    await tester.tapAt(const Offset(20, 40));
    await tester.pumpAndSettle();
    expect(asked, findsNothing);
    expect(shop.trips.state, isA<NoTrip>());
  });

  testWidgets('Zurücknehmen puts the item back and starts nothing', (
    tester,
  ) async {
    final shop = await pumpList(tester);
    await tick(tester, 'Milch');
    await answer(tester, 'trip-ask-take-back');
    await tester.pumpAndSettle();
    expect(strip, findsNothing);
    expect(shop.trips.state, isA<NoTrip>());
    expect(
      shop.list.state.items.values.where(
        (i) => i.name == 'Milch' && i.status == ItemStatus.active,
      ),
      hasLength(1),
    );
  });

  testWidgets('Ja starts the strip; pause and resume swap their label', (
    tester,
  ) async {
    final shop = await pumpList(tester);
    await startByTick(tester, 'Milch');
    expect(strip, findsOneWidget);
    expect(find.text('Einkauf läuft'), findsOneWidget);
    final handle = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Pause'), findsOneWidget);
    await tester.tap(key('trip-strip-pause'));
    await tester.pump();
    expect(find.text('Pausiert'), findsOneWidget);
    expect(find.bySemanticsLabel('Weiter'), findsOneWidget);
    await tester.tap(key('trip-strip-pause'));
    await tester.pump();
    expect(find.text('Einkauf läuft'), findsOneWidget);
    handle.dispose();
    expect(shop.trips.state, isA<Running>());
    await tick(tester, 'Brot');
    expect(asked, findsNothing, reason: 'a running trip asks nothing');
  });

  testWidgets("on a wide window the strip spans the add field's column", (
    tester,
  ) async {
    await pumpList(tester, size: const Size(1100, 800));
    await startByTick(tester, 'Milch');
    final field = tester.getRect(find.byType(TextField));
    final bar = tester.getRect(strip);
    expect(bar.width, lessThan(700), reason: 'one column, not the window');
    expect(bar.left, lessThanOrEqualTo(field.left));
    expect(bar.right, greaterThanOrEqualTo(field.right));
    expect(field.left - bar.left, lessThan(48));
  });

  testWidgets('the strip steps aside while typing', (tester) async {
    await pumpList(tester);
    await startByTick(tester, 'Milch');
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(strip, findsNothing);
  });

  testWidgets('Beenden opens the summary; Fertig ends it for good', (
    tester,
  ) async {
    final shop = await pumpList(tester);
    await startByTick(tester, 'Milch');
    await tick(tester, 'Brot');
    await tester.tap(key('trip-strip-end'));
    await tester.pumpAndSettle();
    final id = shop.sessions.saved.single.id;
    expect(shop.router.state.uri.path, tripSummaryPath(id));
    expect(find.text('Geplant und gekauft'), findsOneWidget);
    expect(
      find.text('2 von 3 von der Liste gekauft'),
      findsOneWidget,
      reason: 'Milch, Brot and Seife were open at the start',
    );
    await tester.scrollUntilVisible(key('trip-summary-done'), 200);
    await tester.tap(key('trip-summary-done'));
    await tester.pumpAndSettle();
    expect(shop.router.state.uri.path, listPath);
    expect(strip, findsNothing);
    expect(shop.trips.state, isA<NoTrip>());
  });

  testWidgets('Weiter einkaufen runs the same trip again', (tester) async {
    final shop = await pumpList(tester);
    await startByTick(tester, 'Milch');
    await tester.tap(key('trip-strip-end'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(key('trip-summary-keep-shopping'), 200);
    await tester.tap(key('trip-summary-keep-shopping'));
    await tester.pumpAndSettle();
    expect(shop.router.state.uri.path, listPath);
    expect(strip, findsOneWidget);
    await tester.tap(key('trip-strip-end'));
    await tester.pumpAndSettle();
    expect(
      shop.sessions.saved.map((t) => t.id).toSet(),
      hasLength(1),
      reason: 'the second end saves the same trip',
    );
  });

  testWidgets('Free: the fresh summary shows the count and the card', (
    tester,
  ) async {
    await pumpList(tester, premium: false);
    await startByTick(tester, 'Milch');
    await tester.tap(key('trip-strip-end'));
    await tester.pumpAndSettle();
    expect(find.text('1 Artikel abgehakt'), findsOneWidget);
    expect(find.text('Was war geplant, was kam dazu?'), findsOneWidget);
    expect(find.text('Beim Start auf der Liste'.toUpperCase()), findsNothing);
  });

  testWidgets('quiet for 45 minutes: the strip offers to end at the last '
      'tick', (tester) async {
    final shop = await pumpList(tester);
    await startByTick(tester, 'Milch');
    final last = shop.trips.state is Running
        ? (shop.trips.state as Running).lastTick!
        : DateTime(0);
    shop.wait(const Duration(minutes: 46));
    await shop.trips.check();
    await tester.pump();
    await tester.pump();
    final time = DateFormat.Hm('de').format(last.toLocal());
    expect(find.text('Pause · seit $time nichts abgehakt'), findsOneWidget);
    await tester.tap(find.text('Beenden um $time'));
    await tester.pumpAndSettle();
    expect(shop.sessions.saved.single.endedAt, last);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('quiet for 4 hours: the card, Übersicht and Doch weiter', (
    tester,
  ) async {
    final shop = await pumpList(tester);
    await startByTick(tester, 'Milch');
    shop.wait(const Duration(hours: 4, minutes: 1));
    await shop.trips.check();
    await tester.pumpAndSettle();
    expect(strip, findsNothing);
    expect(find.text('Einkauf automatisch beendet'), findsOneWidget);
    await tester.tap(key('trip-ended-summary'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Beendet beim letzten Abhaken um'),
      findsOneWidget,
    );
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(
      find.text('Einkauf automatisch beendet'),
      findsNothing,
      reason: 'leaving the page lets the trip go',
    );
    expect(shop.trips.state, isA<NoTrip>());
  });

  testWidgets('Doch weiter on the card runs the trip again', (tester) async {
    final shop = await pumpList(tester);
    await startByTick(tester, 'Milch');
    shop.wait(const Duration(hours: 4, minutes: 1));
    await shop.trips.check();
    await tester.pumpAndSettle();
    await tester.tap(key('trip-ended-keep-going'));
    await tester.pumpAndSettle();
    expect(find.text('Einkauf automatisch beendet'), findsNothing);
    expect(strip, findsOneWidget);
  });

  testWidgets("a running trip holds job 199's cards back, its end clears "
      'them', (tester) async {
    await pumpList(
      tester,
      flags: const {tripModeFlag, groceryLogFlag},
      seed: (repo) => repo
        ..remoteAdd('Milch', storeId: 'lidl')
        ..remoteAdd('Seife', storeId: 'dm'),
    );
    await startByTick(tester, 'Milch');
    expect(key('trip-prompt-lidl'), findsNothing);
    await tester.tap(key('trip-strip-end'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(key('trip-summary-done'), 200);
    await tester.tap(key('trip-summary-done'));
    await tester.pumpAndSettle();
    expect(key('trip-prompt-lidl'), findsNothing);
  });

  testWidgets("a trip's ticks are not offered again by job 199's card, also "
      'at a store that still had open items', (tester) async {
    await pumpList(
      tester,
      flags: const {tripModeFlag, groceryLogFlag},
      seed: (repo) => repo
        ..remoteAdd('Reis', storeId: 'lidl')
        ..remoteAdd('Butter', storeId: 'lidl')
        ..remoteAdd('Nudeln', storeId: 'lidl')
        ..remoteAdd('Seife', storeId: 'dm'),
    );
    await tick(tester, 'Reis');
    await answer(tester, 'trip-ask-no');
    await startByTick(tester, 'Seife');
    await tick(tester, 'Butter');
    await tester.tap(key('trip-strip-end'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(key('trip-summary-done'), 200);
    await tester.tap(key('trip-summary-done'));
    await tester.pumpAndSettle();
    expect(key('trip-prompt-dm'), findsNothing, reason: 'the trip logged it');
    await tick(tester, 'Nudeln');
    await answer(tester, 'trip-ask-no');
    expect(key('trip-prompt-lidl'), findsOneWidget);
    expect(find.textContaining('Butter'), findsNothing, reason: 'logged');
    expect(find.textContaining('Reis'), findsOneWidget);
    expect(find.textContaining('Nudeln'), findsOneWidget);
  });

  testWidgets('a Verlauf entry of a trip opens the same summary', (
    tester,
  ) async {
    final shop = await pumpList(
      tester,
      flags: const {tripModeFlag, groceryLogFlag},
      logged: [
        Trip(
          id: 'log-1',
          day: DateTime(2026, 11, 14),
          items: const [TripItem(name: 'Milch')],
          createdAt: DateTime(2026, 11, 14, 10, 30),
          storeId: 'lidl',
          storeName: 'Lidl',
          sessionId: 'trip-9',
        ),
      ],
    );
    shop.sessions.fetched['trip-9'] = FinishedTrip(
      id: 'trip-9',
      householdId: 'home',
      startedAt: DateTime(2026, 11, 14, 10),
      endedAt: DateTime(2026, 11, 14, 10, 25),
      active: const Duration(minutes: 25),
      end: TripEnd.user,
      source: TripSource.ask,
      currency: 'EUR',
      lines: const [
        TripLine(key: 'm', name: 'Milch', planned: true, bought: true),
      ],
      bought: 1,
      day: DateTime(2026, 11, 14),
      stores: const ['Lidl'],
    );
    shop.router.go(historyPath);
    await tester.pumpAndSettle();
    await tester.tap(key('log-trip-log-1'));
    await tester.pumpAndSettle();
    expect(shop.router.state.uri.path, historyTripPath('trip-9'));
    expect(
      shop.router.routeInformationProvider.value.uri.path,
      historyTripPath('trip-9'),
      reason: 'the address bar on the web, for a reload or a link',
    );
    expect(find.text('25 Min. eingekauft'), findsOneWidget);
    expect(find.text('1 von 1 von der Liste gekauft'), findsOneWidget);
    expect(
      key('trip-summary-done'),
      findsNothing,
      reason: 'only the fresh page has a foot',
    );
  });

  Future<void> deleteTrip(WidgetTester tester) async {
    await tester.tap(key('trip-summary-delete'));
    await tester.pumpAndSettle();
    expect(find.text('Einkauf löschen?'), findsOneWidget);
    expect(
      find.text(
        'Der Einkauf verschwindet für alle im Haushalt aus dem Verlauf.',
      ),
      findsOneWidget,
    );
    await tester.tap(key('trip-summary-delete-confirm'));
    await tester.pumpAndSettle();
  }

  testWidgets('Einkauf löschen on a Verlauf entry deletes the trip', (
    tester,
  ) async {
    final shop = await pumpList(
      tester,
      premium: false,
      flags: const {tripModeFlag, groceryLogFlag},
      logged: [
        Trip(
          id: 'log-1',
          day: DateTime(2026, 11, 14),
          items: const [TripItem(name: 'Milch')],
          createdAt: DateTime(2026, 11, 14, 10, 30),
          storeId: 'lidl',
          storeName: 'Lidl',
          sessionId: 'trip-9',
        ),
      ],
    );
    shop.sessions.fetched['trip-9'] = FinishedTrip(
      id: 'trip-9',
      householdId: 'home',
      startedAt: DateTime(2026, 11, 14, 10),
      endedAt: DateTime(2026, 11, 14, 10, 25),
      active: const Duration(minutes: 25),
      end: TripEnd.user,
      source: TripSource.ask,
      currency: 'EUR',
      lines: null,
      bought: 1,
      day: DateTime(2026, 11, 14),
      stores: const ['Lidl'],
    );
    shop.router.go(historyPath);
    await tester.pumpAndSettle();
    await tester.tap(key('log-trip-log-1'));
    await tester.pumpAndSettle();
    await deleteTrip(tester);
    expect(shop.sessions.deleted, ['trip-9']);
    expect(shop.router.state.uri.path, historyPath);
    expect(key('log-trip-log-1'), findsNothing);
  });

  testWidgets('Einkauf löschen on the fresh summary deletes the trip', (
    tester,
  ) async {
    final shop = await pumpList(tester);
    await startByTick(tester, 'Milch');
    await tester.tap(key('trip-strip-end'));
    await tester.pumpAndSettle();
    final id = shop.sessions.saved.single.id;
    await deleteTrip(tester);
    expect(shop.sessions.deleted, [id]);
    expect(shop.router.state.uri.path, listPath);
    expect(shop.trips.state, isA<NoTrip>());
  });

  testWidgets('a trip the server refuses says so, without a retry', (
    tester,
  ) async {
    final shop = await pumpList(tester);
    shop.sessions.refuse = true;
    await startByTick(tester, 'Milch');
    await tester.tap(key('trip-strip-end'));
    await tester.pumpAndSettle();
    expect(
      find.text('Der Einkauf ist noch nicht gespeichert.'),
      findsOneWidget,
    );
    expect(key('trip-summary-retry'), findsNothing);
  });
}

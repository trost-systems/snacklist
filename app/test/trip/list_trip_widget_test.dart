import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/notices.dart';
import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_parts.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/list/list_view/item_row.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/log/history_screen.dart';
import 'package:family_groceries/log/model.dart' hide TripSource;
import 'package:family_groceries/log/trip_repository.dart';
import 'package:family_groceries/purchases/entitlements.dart';
import 'package:family_groceries/purchases/premium_server.dart';
import 'package:family_groceries/review/review_counters.dart';
import 'package:family_groceries/review/review_gates.dart';
import 'package:family_groceries/review/review_prompt.dart';
import 'package:family_groceries/review/review_prompt_trigger.dart';
import 'package:family_groceries/review/trip_signals.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/shell/list_parts.dart';
import 'package:family_groceries/shell/list_scope.dart' show TripCubitSignals;
import 'package:family_groceries/shell/router.dart';
import 'package:family_groceries/trip/detection.dart';
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
import '../review/fakes.dart';
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

  /// The rating prompt the list's trigger feeds, with this cubit's trips.
  ReviewPrompt? reviewPrompt,

  /// The person's trip detection (job 352).
  TripDetectionCubit? detection,
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
    quiet: () => shownFlags.isOn(learnedOrderFlag),
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
        // The shell's parts, as ListScope provides them.
        RepositoryProvider<ListParts>.value(value: const ShellListParts()),
        RepositoryProvider<TripRepository>.value(value: logTrips),
        RepositoryProvider<TripSessionRepository>.value(value: sessions),
        RepositoryProvider<Analytics>.value(value: Tracked()),
        RepositoryProvider<PremiumServer>.value(value: FakePremiumServer()),
        RepositoryProvider.value(value: cache),
        if (reviewPrompt != null) ...[
          RepositoryProvider.value(value: reviewPrompt),
          RepositoryProvider<TripSignals>.value(value: TripCubitSignals(trips)),
        ],
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: shownFlags),
          BlocProvider.value(value: list),
          BlocProvider.value(value: trips),
          BlocProvider.value(value: entitlements),
          BlocProvider<SessionCubit>.value(value: testSession),
          if (detection != null) BlocProvider.value(value: detection),
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

  testWidgets(
    'grocery-log and trip-mode on: ticking the last dm item shows only the '
    'ask sheet, no inline log card',
    (tester) async {
      await pumpList(tester, flags: const {tripModeFlag, groceryLogFlag});
      await tick(tester, 'Seife');
      expect(asked, findsOneWidget);
      expect(find.textContaining('eintragen'), findsNothing);
      expect(key('trip-prompt-dm'), findsNothing);
      await answer(tester, 'trip-ask-no');
      expect(asked, findsNothing);
      expect(find.textContaining('eintragen'), findsNothing);
    },
  );

  testWidgets('grocery-log on, trip-mode off: a tick shows no trip prompt', (
    tester,
  ) async {
    await pumpList(tester, flags: const {groceryLogFlag});
    await tick(tester, 'Seife');
    expect(asked, findsNothing);
    expect(find.textContaining('eintragen'), findsNothing);
    expect(key('trip-prompt-dm'), findsNothing);
  });

  testWidgets('Nein snoozes the question for 60 minutes', (tester) async {
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
    expect(asked, findsNothing, reason: 'Nein holds for an hour');
    shop.wait(const Duration(minutes: 60));
    await tick(tester, 'Seife');
    expect(asked, findsOneWidget);
    expect(find.text('Seife abgehakt'), findsOneWidget);
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
    shop.wait(const Duration(minutes: 60));
    await tick(tester, 'Zahnpasta');
    expect(asked, findsOneWidget);
    await answer(tester, 'trip-ask-no');
  });

  testWidgets('TD-Q4: ticking a walk through the store with learned-order '
      'shows no live "looks like you are at Lidl" hint, only the trip '
      'question (job 352)', (tester) async {
    final shop = await pumpList(
      tester,
      flags: const {tripModeFlag, learnedOrderFlag, groceryLogFlag},
      seed: (repo) {
        for (final name in ['Milch', 'Brot', 'Butter', 'Käse', 'Eier']) {
          repo.remoteAdd(name, storeId: 'lidl');
        }
      },
    );
    Set<String> texts() => {
      for (final t in tester.widgetList<Text>(find.byType(Text)))
        ?t.data ?? t.textSpan?.toPlainText(),
    };
    final before = texts();
    void nothingLive(String after) {
      expect(find.byType(SnackBar), findsNothing, reason: after);
      expect(find.byType(MaterialBanner), findsNothing, reason: after);
      expect(find.byType(BottomSheet), findsNothing, reason: after);
      expect(
        texts().difference(before).where((t) => t.contains('Lidl')),
        isEmpty,
        reason: after,
      );
      expect(find.textContaining('erkannt'), findsNothing, reason: after);
    }

    await tick(tester, 'Milch');
    expect(asked, findsOneWidget);
    await answer(tester, 'trip-ask-no');
    nothingLive('Milch');
    for (final name in ['Brot', 'Butter', 'Käse', 'Eier']) {
      shop.wait(const Duration(minutes: 2));
      await tick(tester, name);
      nothingLive(name);
    }
    expect(
      shop.list.state.allItems.values.where(
        (i) => i.status == ItemStatus.bought,
      ),
      hasLength(5),
    );
  });

  testWidgets('a dismissed sheet is Nein', (tester) async {
    final shop = await pumpList(tester);
    await tick(tester, 'Milch');
    await tester.tapAt(const Offset(20, 40));
    await tester.pumpAndSettle();
    expect(asked, findsNothing);
    expect(shop.trips.state, isA<NoTrip>());
  });

  group('TD-Q5: with learned-order a „Nein“ keeps the shop from being '
      'detected (job 352)', () {
    const flags = {tripModeFlag, learnedOrderFlag};
    List<DeclineShop> declines(Shop shop) =>
        shop.repo.sent.whereType<DeclineShop>().toList();
    String idOf(Shop shop, String name) =>
        shop.list.state.allItems.values.firstWhere((i) => i.name == name).id;

    testWidgets('Nein sends decline_shop for the asked item, after its tick', (
      tester,
    ) async {
      final shop = await pumpList(tester, flags: flags);
      await tick(tester, 'Milch');
      await answer(tester, 'trip-ask-no');
      final milk = idOf(shop, 'Milch');
      expect(declines(shop), [
        isA<DeclineShop>().having((d) => d.itemId, 'item', milk),
      ]);
      final sent = shop.repo.sent;
      expect(
        sent.indexWhere((op) => op is SetStatus && op.itemId == milk),
        lessThan(sent.indexWhere((op) => op is DeclineShop)),
      );
    });

    testWidgets('a dismissed sheet sends it too', (tester) async {
      final shop = await pumpList(tester, flags: flags);
      await tick(tester, 'Milch');
      await tester.tapAt(const Offset(20, 40));
      await tester.pumpAndSettle();
      expect(asked, findsNothing);
      expect(declines(shop).map((d) => d.itemId), [idOf(shop, 'Milch')]);
    });

    testWidgets('Ja and Zurücknehmen send none', (tester) async {
      final shop = await pumpList(tester, flags: flags);
      await tick(tester, 'Milch');
      await answer(tester, 'trip-ask-take-back');
      await tester.pumpAndSettle();
      await tick(tester, 'Brot');
      await answer(tester, 'trip-ask-yes');
      expect(declines(shop), isEmpty);
    });

    testWidgets('without the flag a Nein sends none', (tester) async {
      final shop = await pumpList(tester);
      await tick(tester, 'Milch');
      await answer(tester, 'trip-ask-no');
      await tick(tester, 'Seife');
      expect(asked, findsNothing);
      expect(shop.repo.sent.whereType<SetStatus>(), hasLength(2));
      expect(declines(shop), isEmpty);
    });
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

  group('the rating prompt with rating-triggers-v2 (job 326)', () {
    late FakeStoreReview review;

    /// A due store-build install with the flag on.
    ReviewPrompt due() {
      review = FakeStoreReview();
      final now = DateTime.now();
      return ReviewPrompt(
        MemoryReviewStore()
          ..json = ReviewCounters(
            firstLaunch: now.subtract(const Duration(days: 30)),
            activeDays: 5,
            completedTrips: 4,
            itemsAdded: 60,
          ).toJson(),
        review,
        channel: BuildChannel.store,
        version: Future.value('1.4.0'),
        v2: () => true,
      );
    }

    Future<void> idle(WidgetTester tester, Duration d) async {
      await tester.pump(d);
      await tester.pump();
    }

    testWidgets('the question after the emptying tick keeps the moment; Nein '
        'asks 3 s later (ST2)', (tester) async {
      final shop = await pumpList(tester, reviewPrompt: due());
      for (final name in ['Milch', 'Brot']) {
        await tick(tester, name);
        await answer(tester, 'trip-ask-no');
        shop.wait(const Duration(minutes: 60));
      }
      await tick(tester, 'Seife');
      expect(asked, findsOneWidget);
      await idle(tester, const Duration(seconds: 5));
      expect(review.requests, 0, reason: 'never over the question');
      await answer(tester, 'trip-ask-no');
      await idle(tester, ReviewPromptTrigger.idle);
      expect(review.requests, 1);
    });

    testWidgets('a trip asks nothing at the emptying, but once its summary '
        'is left (SA1, ST1)', (tester) async {
      final shop = await pumpList(tester, reviewPrompt: due());
      await startByTick(tester, 'Milch');
      await tick(tester, 'Brot');
      await tick(tester, 'Seife');
      await idle(tester, const Duration(seconds: 5));
      expect(review.requests, 0, reason: 'the trip still runs');
      await tester.tap(key('trip-strip-end'));
      await tester.pumpAndSettle();
      await idle(tester, const Duration(seconds: 5));
      expect(review.requests, 0, reason: 'not on the summary');
      await tester.scrollUntilVisible(key('trip-summary-done'), 200);
      await tester.tap(key('trip-summary-done'));
      await tester.pumpAndSettle();
      expect(shop.router.state.uri.path, listPath);
      await idle(tester, ReviewPromptTrigger.idle);
      expect(review.requests, 1);
    });

    testWidgets('a summary with a planned item left asks nothing', (
      tester,
    ) async {
      await pumpList(tester, reviewPrompt: due());
      await startByTick(tester, 'Milch');
      await tick(tester, 'Brot');
      await tester.tap(key('trip-strip-end'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(key('trip-summary-done'), 200);
      await tester.tap(key('trip-summary-done'));
      await tester.pumpAndSettle();
      await idle(tester, const Duration(seconds: 10));
      expect(review.requests, 0);
    });
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

  testWidgets('a running trip shows the strip and no prompt on later ticks', (
    tester,
  ) async {
    await pumpList(
      tester,
      flags: const {tripModeFlag, groceryLogFlag},
      seed: (repo) => repo
        ..remoteAdd('Milch', storeId: 'lidl')
        ..remoteAdd('Seife', storeId: 'dm'),
    );
    await startByTick(tester, 'Milch');
    await tick(tester, 'Seife');
    expect(strip, findsOneWidget);
    expect(asked, findsNothing);
    expect(find.textContaining('eintragen'), findsNothing);
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

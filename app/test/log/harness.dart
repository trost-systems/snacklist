import 'package:bloc_test/bloc_test.dart';
import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/device_cache.dart';
import 'package:family_groceries/core/localizations.dart';
import 'package:family_groceries/core/notices.dart';
import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/log/history_screen.dart';
import 'package:family_groceries/log/model.dart';
import 'package:family_groceries/log/trip_repository.dart';
import 'package:family_groceries/purchases/premium_server.dart';
import 'package:family_groceries/purchases/purchase_repository.dart';
import 'package:family_groceries/purchases/store_prices.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/shell/router.dart' show premiumPath;
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../list/fake_repository.dart';
import '../list/memory_cache.dart';
import '../more/more_harness.dart' show FakeSession;
import '../purchases/fakes.dart'
    show
        FakeEntitlementsSource,
        FakePremiumServer,
        FakePurchaseRepository,
        TestPurchases;
import 'fakes.dart';

/// Records what the app sends.
class Tracked() implements Analytics {
  final events = <(String, Map<String, Object>)>[];

  @override
  void track(String event, [Map<String, Object> properties = const {}]) =>
      events.add((event, properties));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A fresh device store; [pumpHistory] with the same one is a restart.
DeviceCache emptyCache() {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
  return DeviceCache(SharedPreferencesAsync());
}

typedef History = ({
  FakeTrips trips,
  DeviceCache cache,
  Tracked analytics,
  GoRouter router,

  /// With `sells`, Peter's purchases and premium over the fakes.
  TestPurchases? purchases,
});

/// The history screen as the Verlauf tab has it, on Thursday 12 November
/// 2026, for a household with [stores] and [trips], at the compact
/// 358 px width by default; a Free user ([premium] false) sees the last 4
/// weeks. The Premium page is a stand-in at its path that shows its
/// `?from=`.
Future<History> pumpHistory(
  WidgetTester tester, {
  List<Trip> trips = const [],
  List<Store> stores = const [lidl, rewe, dm],
  DeviceCache? cache,
  FakeTrips? server,
  bool premium = true,
  PremiumServer? premiumServer,

  /// Why this build cannot sell Premium; null sells it (no PurchaseCubit
  /// otherwise).
  NoSale? noSale,
  Size size = const Size(358, 760),
  Brightness brightness = Brightness.light,
  double textScale = 1,

  /// Whether the tab is on screen; the shell keeps it alive behind others.
  ValueListenable<bool>? shown,

  /// The PostHog flags that are on.
  Set<String> flags = const {},

  /// The real Premium page behind the lock: Peter in Zuhause, free
  /// (`premium` false), with a store that sells and his Entitlements, whose
  /// changes Verlauf follows. Without it there are no Entitlements.
  bool sells = false,
}) async {
  assert(!sells || noSale == null, 'a store that sells has no NoSale');
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = size;
  addTearDown(tester.view.reset);
  final device = cache ?? emptyCache();
  final fake = server ?? FakeTrips(trips, premium);
  final analytics = Tracked();
  final list = ListCubit(
    FakeRepository()..stores = stores,
    MemoryListCache(),
    userId: 'peter',
  )..start();
  addTearDown(list.close);
  final popups = Popups();
  addTearDown(popups.dispose);
  final router = GoRouter(
    observers: [popups],
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => ValueListenableBuilder(
          valueListenable: shown ?? ValueNotifier(true),
          builder: (_, on, _) => TickerMode(
            enabled: on,
            child: const HistoryScreen(clock: clock),
          ),
        ),
      ),
      GoRoute(
        path: premiumPath,
        builder: (_, state) => Scaffold(
          body: Text('premium-page:${state.uri.queryParameters['from']}'),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  TestPurchases? paywall;
  Widget purchasesFor(Widget child) {
    if (sells) {
      final session = FakeSession();
      whenListen(
        session,
        const Stream<Session>.empty(),
        initialState: const InHousehold(
          'peter',
          Household(id: 'home', name: 'Zuhause'),
          [Household(id: 'home', name: 'Zuhause')],
        ),
      );
      final purchases = paywall = TestPurchases(
        session: session,
        source: FakeEntitlementsSource(unlockedNow: premium),
      );
      addTearDown(purchases.close);
      return MultiRepositoryProvider(
        providers: [
          RepositoryProvider<StorePriceReader>.value(
            value: purchases.storePrices,
          ),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<SessionCubit>.value(value: session),
            BlocProvider.value(value: purchases.entitlements),
            BlocProvider.value(value: purchases.purchases),
          ],
          child: child,
        ),
      );
    }
    if (noSale == null) {
      return child;
    }
    final session = FakeSession();
    whenListen(
      session,
      const Stream<Session>.empty(),
      initialState: const SignedOut(),
    );
    final purchases = TestPurchases(
      session: session,
      store: FakePurchaseRepository(withoutStore: noSale),
    );
    addTearDown(purchases.close);
    return BlocProvider.value(value: purchases.purchases, child: child);
  }

  await tester.pumpWidget(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: device),
        RepositoryProvider<TripRepository>.value(value: fake),
        RepositoryProvider<Analytics>.value(value: analytics),
        RepositoryProvider<PremiumServer>.value(
          value: premiumServer ?? FakePremiumServer(),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: list),
          BlocProvider(create: (_) => Flags(forced: flags)),
        ],
        child: purchasesFor(
          MaterialApp.router(
            routerConfig: router,
            theme: appTheme(brightness),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('de'),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: NoticesHost(popups: popups, child: child!),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (
    trips: fake,
    cache: device,
    analytics: analytics,
    router: router,
    purchases: paywall,
  );
}

import 'dart:convert';

import 'package:bloc_test/bloc_test.dart';
import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/app/device_cache.dart';
import 'package:family_groceries/app/language.dart';
import 'package:family_groceries/app/notices.dart';
import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/app/theme.dart';
import 'package:family_groceries/feedback/feedback_context.dart';
import 'package:family_groceries/feedback/feedback_cubit.dart';
import 'package:family_groceries/feedback/screen_tracker.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/invite_share.dart';
import 'package:family_groceries/household/pending_invite.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_scope.dart';
import 'package:family_groceries/more/app_update.dart';
import 'package:family_groceries/more/more_screen.dart';
import 'package:family_groceries/purchases/premium_server.dart';
import 'package:family_groceries/purchases/purchase_repository.dart';
import 'package:family_groceries/purchases/store_prices.dart';
import 'package:family_groceries/review/store_review.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/settings/account_repository.dart';
import 'package:family_groceries/settings/integration_lock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../feedback/fakes.dart';
import '../household/harness.dart'
    show FakeInvites, FakeSharer, MemoryPendingStore;
import '../list/fake_repository.dart';
import '../purchases/fakes.dart';
import '../review/fakes.dart';
import '../settings/fake_account.dart';

class FakeSession() extends MockCubit<Session> implements SessionCubit;

/// An update source that always offers [update] and records what is applied.
final class FakeAppUpdates(final AppUpdate? update) implements AppUpdates {
  final applied = <AppUpdate>[];

  @override
  Future<AppUpdate?> available() async => update;

  @override
  Future<void> apply(AppUpdate update) async => applied.add(update);
}

/// Rows the fake server answers for `personal_access_tokens`.
final serverTokens = <Map<String, Object?>>[];

/// The OAuth grants (connected apps) the fake auth server answers.
final serverGrants = <Map<String, Object?>>[];

/// Supabase against a server that answers every request with `[]`, or
/// [serverTokens] and [serverGrants]: More's access page builds its
/// repository from the global client. Once per test file, in `setUpAll`.
Future<void> fakeSupabase() async {
  // Supabase listens for deep links; with no plugin the listen fails late,
  // inside whichever test runs then.
  TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
      .setMockStreamHandler(
        const EventChannel('com.llfbandit.app_links/events'),
        MockStreamHandler.inline(onListen: (_, _) {}),
      );
  SharedPreferences.setMockInitialValues({});
  PackageInfo.setMockInitialValues(
    appName: 'Hummlist',
    packageName: 'com.hummlist.app',
    version: '1.2.3',
    buildNumber: '45',
    buildSignature: '',
  );
  await Supabase.initialize(
    url: 'http://localhost:54321',
    publishableKey: 'test',
    httpClient: MockClient(
      (request) async => http.Response(
        jsonEncode(switch (request.url.path) {
          final p when p.endsWith('personal_access_tokens') => serverTokens,
          final p when p.endsWith('/user/oauth/grants') => serverGrants,
          _ => const <Object>[],
        }),
        200,
        headers: {'content-type': 'application/json'},
        // postgrest reads the method back from the response.
        request: request,
      ),
    ),
    authOptions: const FlutterAuthClientOptions(
      localStorage: EmptyLocalStorage(),
      autoRefreshToken: false,
    ),
  );
}

typedef More = ({
  FakeRepository repo,
  DeviceCache cache,
  LanguageCubit language,
  ThemeCubit theme,
  GoRouter router,
  Analytics analytics,
  FakeFeedbackRepository feedback,
  ScreenTracker screens,
  TestPurchases purchases,
  FakeSession session,
});

/// More's routes as `buildRouter` has them, without the shell (whose list
/// scope needs the real backend), wired to the language and theme like
/// `App`.
Future<More> pumpMore(
  WidgetTester tester, {
  String location = morePath,
  Size size = const Size(390, 844),
  AppLanguage? language,
  ThemeMode theme = ThemeMode.system,

  /// The device's light or dark setting.
  Brightness deviceBrightness = Brightness.light,

  /// The device's preferred languages.
  List<Locale> device = const [Locale('de', 'DE')],

  /// Analytics as the app has it; a build without a key by default.
  Analytics? analytics,

  /// Instead of `moreTabRoutes()`, e.g. a More built like a release build.
  List<RouteBase>? routes,

  /// The app's own routes and shell (`appRoutes`) behind the auth redirect,
  /// instead of `routes`, for navigation across tabs and screens.
  bool app = false,

  /// The list's server before the list loads.
  void Function(FakeRepository repo)? seed,

  /// The store, the purchases function's claim and the household's entitlement
  /// rows; a store that sells and a household without Lifetime by default.
  FakePurchaseRepository? store,

  /// The real store over a mocked channel, instead of `store`.
  PurchaseRepository? sdk,
  FakeClaimApi? api,
  FakeEntitlementsSource? entitlements,

  /// The premium_offer switch and the caller's yearly plan.
  FakePremiumServer? premium,

  /// The store's prices; both plans in euros by default.
  FakeStorePrices? prices,

  /// The clock premium is computed with.
  DateTime Function()? clock,

  /// The server's invites and archived households.
  FakeInvites? invites,

  /// The `INTEGRATION_LOCK` define (job 50); the switch is `premium.lock`.
  bool integrationLock = false,

  /// More's update source; set, More is the only route (no pages).
  AppUpdates? updates,

  /// The PostHog flags that are on.
  Set<String> flags = const {},

  /// The store's rating prompt and listing.
  FakeStoreReview? storeReview,
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = size;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.localesTestValue = device;
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  tester.platformDispatcher.platformBrightnessTestValue = deviceBrightness;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
  final cache = DeviceCache(SharedPreferencesAsync());
  final languageCubit = LanguageCubit(cache, language);
  addTearDown(languageCubit.close);
  final themeCubit = ThemeCubit(cache, theme);
  addTearDown(themeCubit.close);
  final shownAnalytics = analytics ?? Analytics.off(cache);
  addTearDown(shownAnalytics.close);
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
  final purchases = TestPurchases(
    session: session,
    store: store,
    sdk: sdk,
    api: api,
    source: entitlements,
    premiumServer: premium,
    prices: prices,
    clock: clock,
  );
  addTearDown(purchases.close);
  final lock = IntegrationLockCubit(
    purchases.premium,
    enabled: integrationLock,
  );
  addTearDown(lock.close);
  final repo = FakeRepository();
  seed?.call(repo);
  final feedback = FakeFeedbackRepository();
  final feedbackCubit = FeedbackCubit(feedback, analytics: shownAnalytics);
  addTearDown(feedbackCubit.close);
  final screens = ScreenTracker();
  final popups = Popups();
  final router = GoRouter(
    initialLocation: location,
    observers: [popups],
    redirect: app ? (_, state) => authRedirect(session.state, state.uri) : null,
    routes: app
        ? appRoutes(repositories: (_) => repo)
        : [
            // As in the app, the list sits above the tabs (AppShell's
            // ListScope).
            ShellRoute(
              builder: (_, _, child) =>
                  ListScope(repositories: (_) => repo, child: child),
              routes:
                  routes ??
                  switch (updates) {
                    final updates? => [
                      GoRoute(
                        path: morePath,
                        builder: (_, _) => MoreScreen(updates: updates),
                      ),
                    ],
                    null => [...moreTabRoutes()],
                  },
            ),
          ],
  );
  addTearDown(router.dispose);
  // As App does: the tracker follows the router.
  void visit() => screens.visit(router.routerDelegate.currentConfiguration.uri);
  router.routerDelegate.addListener(visit);
  addTearDown(() => router.routerDelegate.removeListener(visit));
  await tester.pumpWidget(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: cache),
        RepositoryProvider<AccountRepository>.value(
          value: FakeAccountRepository(),
        ),
        RepositoryProvider.value(value: screens),
        RepositoryProvider<FeedbackDevice>.value(value: FakeFeedbackDevice()),
        RepositoryProvider<InviteRepository>.value(
          value: invites ?? FakeInvites(),
        ),
        RepositoryProvider<InviteSharer>.value(value: FakeSharer()),
        RepositoryProvider.value(value: PendingInvite(MemoryPendingStore())),
        RepositoryProvider<PremiumServer>.value(value: purchases.premium),
        RepositoryProvider<StorePriceReader>.value(
          value: purchases.storePrices,
        ),
        RepositoryProvider<StoreReview>.value(
          value: storeReview ?? FakeStoreReview(),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<SessionCubit>.value(value: session),
          BlocProvider.value(value: languageCubit),
          BlocProvider.value(value: themeCubit),
          BlocProvider.value(value: shownAnalytics),
          BlocProvider.value(value: feedbackCubit),
          BlocProvider.value(value: purchases.entitlements),
          BlocProvider.value(value: purchases.purchases),
          BlocProvider.value(value: lock),
          BlocProvider(create: (_) => Flags(forced: flags)),
        ],
        child: Builder(
          builder: (context) => MaterialApp.router(
            theme: appTheme(Brightness.light),
            darkTheme: appTheme(Brightness.dark),
            themeMode: context.watch<ThemeCubit>().state,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: switch (context.watch<LanguageCubit>().state) {
              final picked? => Locale(picked.code),
              null => null,
            },
            localeListResolutionCallback: (preferred, _) =>
                resolveLocale(preferred, null),
            routerConfig: router,
            builder: (_, child) => NoticesHost(popups: popups, child: child!),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (
    repo: repo,
    cache: cache,
    language: languageCubit,
    theme: themeCubit,
    router: router,
    analytics: shownAnalytics,
    feedback: feedback,
    screens: screens,
    purchases: purchases,
    session: session,
  );
}

/// More's rows top to bottom (M-P2, job 85) in [menuGroups]' inset groups,
/// for a household member with Premium offered and the help page published,
/// in a build without analytics (no Nutzungsdaten row).
const menuGroups = [
  ['menu-account', 'more-lifetime'],
  ['more-invite', 'more-join'],
  ['more-access'],
  ['more-settings'],
  ['more-feedback', 'more-rate', 'more-help'],
  legalRows,
  ['more-sign-out'],
];

/// The rows below the „Rechtliches“ label, right on More (DDG §5: the
/// imprint one tap from the tab).
const legalRows = [
  'more-imprint',
  'more-privacy-policy',
  'more-terms',
  'more-licenses',
];

/// [menuGroups] flattened.
final menuRows = [for (final group in menuGroups) ...group];

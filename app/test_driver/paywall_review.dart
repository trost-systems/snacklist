import 'dart:async';
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/app/device_cache.dart';
import 'package:family_groceries/app/language.dart';
import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/app/shell.dart';
import 'package:family_groceries/app/theme.dart';
import 'package:family_groceries/feedback/feedback_context.dart';
import 'package:family_groceries/feedback/feedback_cubit.dart';
import 'package:family_groceries/feedback/screen_tracker.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/invite_share.dart';
import 'package:family_groceries/household/pending_invite.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/purchases/premium_page_cubit.dart';
import 'package:family_groceries/purchases/premium_server.dart';
import 'package:family_groceries/purchases/purchase_repository.dart';
import 'package:family_groceries/purchases/store_prices.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/settings/account_repository.dart';
import 'package:family_groceries/settings/integration_lock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../test/feedback/fakes.dart';
import '../test/household/harness.dart'
    show FakeInvites, FakeSharer, MemoryPendingStore;
import '../test/list/fake_repository.dart';
import '../test/more/more_harness.dart' show FakeSession;
import '../test/purchases/fakes.dart';
import '../test/settings/fake_account.dart';

/// The marks scripts/ios-paywall-shot.sh and the app hand each other: the
/// app writes `ready-<plan>` once the page shows that plan picked, the
/// script `taken-<plan>` once it has the screenshot. The simulator shares
/// the host's file system.
const _marks = '/tmp/hummlist-paywall-shot';

/// Debug entrypoint for the App Store's in-app purchase review screenshot
/// (job 86): the real shell, More tab and Premium page (PW-P4, job 87) as
/// the integration lock opens it. Faked: the server (a household without
/// Premium, the premium_offer switch on) and the prices, the German
/// storefront's; the page still asks StoreKit through its channel. Nothing
/// here buys.
Future<void> main() async {
  if (kReleaseMode) {
    throw StateError('paywall_review.dart is for debug builds.');
  }
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
  final cache = DeviceCache(SharedPreferencesAsync());
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
  final purchases = TestPurchases(session: session);
  final analytics = Analytics.off(cache);
  final router = GoRouter(
    initialLocation: '$premiumPath?from=${PaywallEntry.integrations.name}',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) =>
            AppShell(shell: shell, repositories: (_) => FakeRepository()),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: listPath, builder: (_, _) => const ListScreen()),
            ],
          ),
          StatefulShellBranch(routes: moreTabRoutes()),
        ],
      ),
    ],
  );
  runApp(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: cache),
        RepositoryProvider<AccountRepository>.value(
          value: FakeAccountRepository(),
        ),
        RepositoryProvider.value(value: ScreenTracker()),
        RepositoryProvider<FeedbackDevice>.value(value: FakeFeedbackDevice()),
        RepositoryProvider<InviteRepository>.value(value: FakeInvites()),
        RepositoryProvider<InviteSharer>.value(value: FakeSharer()),
        RepositoryProvider.value(value: PendingInvite(MemoryPendingStore())),
        RepositoryProvider<PremiumServer>.value(value: purchases.premium),
        RepositoryProvider<StorePriceReader>.value(
          value: const _GermanStorefront(ChannelStorePrices()),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<SessionCubit>.value(value: session),
          BlocProvider.value(value: LanguageCubit(cache, AppLanguage.de)),
          BlocProvider.value(value: ThemeCubit(cache, ThemeMode.light)),
          BlocProvider.value(value: analytics),
          BlocProvider.value(value: analytics.flags),
          BlocProvider.value(
            value: FeedbackCubit(
              FakeFeedbackRepository(),
              analytics: analytics,
            ),
          ),
          BlocProvider.value(value: purchases.entitlements),
          BlocProvider.value(value: purchases.purchases),
          BlocProvider.value(
            value: IntegrationLockCubit(purchases.premium, enabled: false),
          ),
        ],
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: appTheme(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          routerConfig: router,
        ),
      ),
    ),
  );
}

/// The German storefront's prices as StoreKit formats them: App Store
/// Connect's base prices (scripts/iap/product.ts, app/ios/Hummlist.storekit).
/// On GitHub's macOS runner StoreKit's local test store does not open and
/// the sandbox answers with the US storefront (DECISIONS, job 86).
const _germanStorefront = {
  PremiumPlan.yearly: StorePrice('9,99\u00a0€', 'EUR'),
  PremiumPlan.lifetime: StorePrice('29,99\u00a0€', 'EUR'),
};

/// Asks StoreKit through the page's real channel (up to six times) and
/// records its answer, then shows the German storefront's prices.
class const _GermanStorefront(final StorePriceReader _store)
    implements StorePriceReader {
  @override
  Future<StorePrices> read() async {
    // The sandbox can miss the page's 10 s timeout right after the
    // simulator boots (run 41790415523): ask again before recording.
    var storeKit = await _store.read();
    for (var retry = 0; retry < 5 && storeKit is PricesUnavailable; retry++) {
      storeKit = await _store.read();
    }
    unawaited(
      _markReady(switch (storeKit) {
        PricesRead(:final prices) => '$prices',
        PricesUnavailable() => 'no answer',
      }),
    );
    return const PricesRead(_germanStorefront);
  }

  /// PW-P4 has one Buy for the picked plan: `ready-yearly` with the yearly
  /// plan picked (the page's default), then, once the script has taken that
  /// screenshot (`taken-yearly`), Lifetime picked as its tile's tap does and
  /// `ready-lifetime`. Each two seconds after the next frame.
  Future<void> _markReady(String storeKit) async {
    Future<void> settle() async {
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(seconds: 2));
    }

    await settle();
    await File('$_marks/ready-yearly')
        .writeAsString('storekit: $storeKit\nshown: $_germanStorefront\n');
    while (!File('$_marks/taken-yearly').existsSync()) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    _lifetimeTile(WidgetsBinding.instance.rootElement!)!
        .read<PremiumPageCubit>()
        .pick(PremiumPlan.lifetime);
    await settle();
    await File('$_marks/ready-lifetime').writeAsString('picked: lifetime\n');
  }

  /// The Lifetime tile, below the page's [PremiumPageCubit].
  static Element? _lifetimeTile(Element element) {
    if (element.widget.key == const ValueKey('premium-card-lifetime')) {
      return element;
    }
    Element? found;
    element.visitChildren((child) => found ??= _lifetimeTile(child));
    return found;
  }

  @override
  Future<bool> manageSubscriptions() => _store.manageSubscriptions();
}

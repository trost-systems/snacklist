import 'dart:async';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/analytics/setup.dart';
import 'package:family_groceries/app/app.dart';
import 'package:family_groceries/app/device_cache.dart';
import 'package:family_groceries/app/early_keys.dart';
import 'package:family_groceries/app/environment.dart';
import 'package:family_groceries/app/language.dart';
import 'package:family_groceries/app/network.dart';
import 'package:family_groceries/app/theme.dart';
import 'package:family_groceries/design/fonts.dart';
import 'package:family_groceries/feedback/feedback_repository.dart';
import 'package:family_groceries/home_widget/home_widget_sync.dart';
import 'package:family_groceries/home_widget/widget_launch.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/pending_invite.dart';
import 'package:family_groceries/list/item_icons_remote.dart';
import 'package:family_groceries/list/list_view/item_icon.dart';
import 'package:family_groceries/onboarding/onboarding_cubit.dart';
import 'package:family_groceries/purchases/entitlements.dart';
import 'package:family_groceries/purchases/premium_server.dart';
import 'package:family_groceries/purchases/purchase_api.dart';
import 'package:family_groceries/purchases/purchase_cubit.dart';
import 'package:family_groceries/purchases/setup.dart';
import 'package:family_groceries/purchases/store_prices.dart';
import 'package:family_groceries/review/review_gates.dart';
import 'package:family_groceries/review/review_prompt.dart';
import 'package:family_groceries/review/store_review.dart';
import 'package:family_groceries/session/mail_language.dart';
import 'package:family_groceries/session/plugin_sign_in.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/session/social_sign_in.dart';
import 'package:family_groceries/settings/access_repository.dart';
import 'package:family_groceries/settings/account_repository.dart';
import 'package:family_groceries/siri/siri_channel.dart';
import 'package:family_groceries/siri/siri_credentials.dart';
import 'package:family_groceries/tips/hint_host.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Set once analytics is loaded; errors before that are not reported.
Analytics? _analytics;

/// Set with analytics; an error holds the rating prompt back.
ReviewPrompt? _reviewPrompt;

Future<void> main() => bootstrap(WidgetsFlutterBinding.ensureInitialized);

/// Starts the app with [binding], which `test_driver/main_marionette.dart`
/// swaps for its own. The binding is initialized in the same zone as
/// `runApp`; Flutter asserts that ("Zone mismatch").
Future<void> bootstrap(WidgetsBinding Function() binding) async {
  // Errors no one caught go to error tracking (job 19): those in this zone
  // here, the framework's through FlutterError.onError, the rest through
  // the platform dispatcher. Analytics sends nothing without consent.
  await runZonedGuarded(() => _main(binding), (error, stack) {
    _analytics?.captureException(error, stack);
    unawaited(_reviewPrompt?.errorSeen());
    Zone.root.print('Uncaught: $error\n$stack');
  });
}

Future<void> _main(WidgetsBinding Function() binding) async {
  // Path URLs (/join/CODE, later /oauth/consent) instead of #-fragments.
  usePathUrlStrategy();
  binding();
  registerFontLicenses();
  if (kIsWeb) {
    // Exposes the widget tree to the DOM for screen readers and Playwright.
    SemanticsBinding.instance.ensureSemantics();
    // Semantics hands a field's input to the app a frame late.
    EarlyKeys();
  }
  await Supabase.initialize(
    url: Environment.supabaseUrl,
    publishableKey: Environment.supabasePublishableKey,
    // The list and session retry on their own (every 3 s, ops until acked);
    // postgrest's GET retries (1 + 2 + 4 s) only hid an offline start.
    // `client.from` ignores this option, so reads go through `client.rest`.
    postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
  );
  final client = Supabase.instance.client;
  final social = SocialSignIn(
    client.auth,
    flows: socialFlows(
      (
        googleWebClientId: Environment.googleWebClientId,
        googleIosClientId: Environment.googleIosClientId,
        apple: Environment.signInWithApple,
      ),
      web: kIsWeb,
      platform: defaultTargetPlatform,
    ),
    native: PluginSignIn(
      googleWebClientId: Environment.googleWebClientId,
      googleIosClientId: defaultTargetPlatform == TargetPlatform.iOS
          ? Environment.googleIosClientId
          : null,
    ),
  );
  final cache = DeviceCache.onDevice();
  final storeReview = InAppStoreReview();
  final analytics = _analytics = await startAnalytics(cache);
  final reviewPrompt = _reviewPrompt = ReviewPrompt(
    cache,
    storeReview,
    channel: BuildChannel.current,
    version: appVersionName(),
    analytics: analytics,
  );
  unawaited(reviewPrompt.load());
  reportUncaughtErrors(
    analytics,
    onError: () => unawaited(reviewPrompt.errorSeen()),
  );
  final account = SupabaseAccountRepository(
    client,
    // Only iOS has Apple's own dialog; elsewhere the server answers
    // `manual` and the user unlinks the app on their iPhone.
    appleCode: !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
        ? appleAuthorizationCode
        : null,
  );
  final language = AppLanguage.byCode(await cache.language());
  final theme = themeModeOf(await cache.theme());
  final pendingInvite = await PendingInvite.load(cache);
  final onboarding = await OnboardingCubit.load(cache, analytics: analytics);
  final siri = switch (siriChannelFor(
    web: kIsWeb,
    platform: defaultTargetPlatform,
  )) {
    final channel? => SiriCredentials(
      SupabaseSiriServer(client),
      channel,
      voiceUrl: Environment.voiceUrl,
    ),
    null => null,
  };
  final session = SessionCubit(
    client,
    cache,
    analytics: analytics,
    pendingInvite: pendingInvite,
    beforeSignOut: siri?.signingOut,
  );
  siri?.follow(session);
  final homeWidgets = homeWidgetSyncFor(
    web: kIsWeb,
    platform: defaultTargetPlatform,
  )?..follow(session);
  final entitlements = Entitlements(
    SupabaseEntitlementsSource(client),
    session,
  );
  // Offline the last answer stands; it names its household, so it never
  // marks another one.
  entitlements.stream.listen((state) {
    if (state case EntitlementsKnown(:final householdId, :final unlocks)) {
      analytics.testerHousehold = unlocks.tester ? householdId : null;
    }
  });
  final itemIcons = ItemIconsCubit();
  if (kIsWeb) {
    warmItemIconFonts(itemIcons.state);
    itemIcons.stream.listen(warmItemIconFonts);
  }
  runApp(
    App(
      mailLanguage: MailLanguageSync(client.auth),
      itemIcons: itemIcons,
      language: language,
      theme: theme,
      session: session,
      entitlements: entitlements,
      // Asks no store until a tap on Buy or Restore (Legal Review H-67).
      purchases: PurchaseCubit(
        purchaseRepository(client),
        SupabaseClaimApi(client),
        entitlements,
        session,
      ),
      premium: SupabasePremiumServer(client),
      storePrices: storePriceReader(),
      analytics: analytics,
      reviewPrompt: reviewPrompt,
      storeReview: storeReview,
      social: social,
      cache: cache,
      account: account,
      feedback: SupabaseFeedbackRepository(client),
      invites: SupabaseInviteRepository(client),
      pendingInvite: pendingInvite,
      onboarding: onboarding,
      onboardingBackend: SupabaseOnboardingBackend(client),
      homeWidgets: homeWidgets,
      hints: HintHost(
        assistantConnected: () =>
            assistantConnected(SupabaseAccessRepository(client)),
        widgetPlaced: homeWidgets == null ? null : homeWidgetPlaced,
      ),
      widgetLaunches: widgetLaunchesFor(
        web: kIsWeb,
        platform: defaultTargetPlatform,
      ),
      network: networkWatchFor(web: kIsWeb, platform: defaultTargetPlatform),
    ),
  );
  // Started after runApp, so the first frame waits for no cache read; the
  // bundled table shows until then.
  final iconClient = http.Client();
  unawaited(
    ItemIconsLoader(
      store: cache,
      cubit: itemIcons,
      client: iconClient,
      url: Environment.itemIconsUrl.isEmpty
          ? null
          : Uri.parse(Environment.itemIconsUrl),
    ).start().whenComplete(iconClient.close),
  );
}

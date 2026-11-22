import 'package:flutter/foundation.dart';

/// Build-time configuration. The only file that reads `--dart-define`s.
/// Defaults point at the production project; its URL and publishable key
/// are public by design.
abstract final class Environment() {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: _productionUrl,
  );
  static const _productionUrl = 'https://jdwqrallbpdbshrdhenk.supabase.co';
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_YMFUFoZ-smly3zDIYTIFRw_vRt6UBk5',
  );

  /// Public web origin for invite links from the mobile apps; empty shows
  /// only the code. Production builds take it from `config/auth.json`.
  static const appUrl = String.fromEnvironment('APP_URL');

  /// Google OAuth "Web application" client ID. Supabase verifies ID tokens
  /// against it and native sign-in passes it as the server client ID; empty
  /// hides the Google button.
  static const googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
  );

  /// Google OAuth "iOS" client ID; empty hides the Google button on iOS.
  static const googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
  );

  /// Whether the Supabase project has Sign in with Apple configured.
  static const signInWithApple = bool.fromEnvironment('SIGN_IN_WITH_APPLE');

  /// PostHog project API key (`phc_…`, Einkauf project 319492). Empty, the
  /// default and what CI builds get, turns analytics and error tracking off
  /// completely (docs/ANALYTICS.md). Never committed: Vercel and release
  /// builds pass it in.
  static const posthogProjectKey = String.fromEnvironment(
    'POSTHOG_PROJECT_API_KEY',
  );

  /// PostHog ingestion host; only https://eu.i.posthog.com (or a stand-in
  /// that can't reach PostHog, for e2e) is accepted. No default.
  static const posthogHost = String.fromEnvironment('POSTHOG_HOST');

  /// Household ids whose events are internal (Peter's family),
  /// comma-separated.
  static const analyticsInternalHouseholds = String.fromEnvironment(
    'ANALYTICS_INTERNAL_HOUSEHOLDS',
  );

  /// E-mail domains whose users are internal besides the reserved test
  /// domains, comma-separated.
  static const analyticsInternalEmailDomains = String.fromEnvironment(
    'ANALYTICS_INTERNAL_EMAIL_DOMAINS',
  );

  /// Every event of this build is internal (Vercel's preview deployments).
  static const analyticsInternalBuild = bool.fromEnvironment(
    'ANALYTICS_INTERNAL_BUILD',
  );

  /// Also sends the PostHog `household` group. Off: group analytics is a
  /// paid add-on (NEEDS_PETER).
  static const analyticsHouseholdGroups = bool.fromEnvironment(
    'ANALYTICS_HOUSEHOLD_GROUPS',
  );

  /// Shows links to snacklist.app pages that are still drafts (the help
  /// page, job 24). On in debug builds, widget tests and e2e
  /// (`config/e2e.json`); off in release builds, where the page answers 404.
  static const legalDrafts = bool.fromEnvironment(
    'LEGAL_DRAFTS',
    defaultValue: kDebugMode,
  );

  /// Offers the last member of an unlocked household to archive it instead
  /// of deleting it, and to re-enable it under More (job 43). Off until the
  /// privacy policy, the support FAQ and the account deletion page say so
  /// (Legal Review); on in e2e (`config/e2e.json`).
  static const householdArchive = bool.fromEnvironment('HOUSEHOLD_ARCHIVE');

  /// Offers Snacklist Lifetime's purchase and restore through RevenueCat on
  /// iOS and Android. Off, the default, the Lifetime page says "coming
  /// soon": the purchase reaches no one until Peter has approved the new
  /// legal texts (Legal Review K.9.9, release gate). Turn it on with
  /// `--dart-define=REVENUECAT_PURCHASES=true` plus the platform's key.
  static const revenueCatPurchases = bool.fromEnvironment(
    'REVENUECAT_PURCHASES',
  );

  /// Native Siri (job 51, with the German fix of PR #194) is live in this
  /// build: the iPhone then gets the Siri hint (tips/hints.dart). Store
  /// builds pass it exactly when `releases/flags.json` releases the
  /// `native-siri` hold (Fastfile).
  static const nativeSiriLive = bool.fromEnvironment('NATIVE_SIRI_LIVE');

  /// This is the public Play production build: outside the iPhone (whose
  /// release builds may always ask, TestFlight never shows the prompt) only
  /// it asks the store for a rating (job 155). Play internal builds must not
  /// pass `--dart-define=STORE_RELEASE=true` (docs/RELEASE.md, "Public
  /// releases").
  static const storeRelease = bool.fromEnvironment('STORE_RELEASE');

  /// QA: outside a store release the rating prompt's gates are skipped and
  /// any completed trip asks (`--dart-define=REVIEW_PROMPT_FORCE=true`).
  /// A store release ignores it.
  static const reviewPromptForce = bool.fromEnvironment('REVIEW_PROMPT_FORCE');

  /// RevenueCat's public SDK keys (`appl_…`, `goog_…`); empty also means
  /// "coming soon". Never committed: release builds pass them in.
  static const revenueCatIosKey = String.fromEnvironment(
    'REVENUECAT_APPLE_API_KEY',
  );
  static const revenueCatAndroidKey = String.fromEnvironment(
    'REVENUECAT_GOOGLE_API_KEY',
  );

  /// Firebase Cloud Messaging's client config (job 376, docs/PUSH.md):
  /// public like the publishable key, but kept out of the repo; release
  /// builds pass them in. Without the project's and the platform's, the
  /// build has no push and never starts Firebase.
  static const firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
  );
  static const firebaseMessagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const firebaseIosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  static const firebaseIosApiKey = String.fromEnvironment(
    'FIREBASE_IOS_API_KEY',
  );
  static const firebaseAndroidAppId = String.fromEnvironment(
    'FIREBASE_ANDROID_APP_ID',
  );
  static const firebaseAndroidApiKey = String.fromEnvironment(
    'FIREBASE_ANDROID_API_KEY',
  );

  /// Replaces RevenueCat and the stores with a fake in debug and profile
  /// builds (release builds ignore it), also with REVENUECAT_PURCHASES off:
  /// `ok`, `pending` (Ask to Buy, approved after 8 s), `cancel`, `error`,
  /// `unavailable` (product not loadable) or `offline` (store unreachable).
  /// Its purchases go to the local stack's `/purchases/test/event`, which
  /// plays RevenueCat's webhook, so it sells on Linux desktop for fg; the web
  /// app never sells (lib/purchases/setup.dart).
  static const fakeStore = String.fromEnvironment('FAKE_STORE');

  /// The MCP server endpoint:for the production project its public URL,
  /// a Vercel proxy to the edge function (docs/MCP.md); for any other
  /// project (the local stack) the edge function itself.
  static const mcpUrl = supabaseUrl == _productionUrl
      ? 'https://mcp.snacklist.app'
      : '$supabaseUrl/functions/v1/mcp';

  /// The public REST API's base URL (job 73, docs/API.md "Base URL").
  static const apiUrl = '$supabaseUrl/functions/v1/api/v1';

  /// The API's base URL behind the flag `api-snacklist-app` (job 398): for
  /// the production project its own domain, a Vercel proxy to the edge
  /// function (docs/DEPLOY.md, mcp-proxy/README.md); for any other project
  /// (the local stack) [apiUrl].
  static const proxiedApiUrl = supabaseUrl == _productionUrl
      ? 'https://api.snacklist.app/v1'
      : apiUrl;

  /// Feature flags on whatever PostHog says, comma-separated
  /// (`FLAGS_ON=public-api`), for local builds and screenshots. A build that
  /// sends to PostHog EU ignores it (`startAnalytics`), so no store or
  /// Vercel build can ship a forced flag.
  static const flagsOn = String.fromEnvironment('FLAGS_ON');

  /// The remote item icon table (job 147), fetched at most once a day;
  /// empty turns the fetch off (e2e: `config/e2e.json`).
  static const itemIconsUrl = String.fromEnvironment(
    'ITEM_ICONS_URL',
    defaultValue: 'https://snacklist.app/data/item-icons.v1.json',
  );

  /// Where native Siri's intents send what was said (job 51).
  static const voiceUrl = '$supabaseUrl/functions/v1/voice';

  /// Prints the add sheet's `[add-sheet timing]` log (jobs 272 and 274) in
  /// a profile or release build too, to measure it there; debug builds
  /// always print it. No shipped build sets it.
  static const addSheetTiming =
      kDebugMode || bool.fromEnvironment('ADD_SHEET_TIMING');
}

/// Where this web app lives; it is always served at the domain root.
String get webRoot => Uri.base.origin;

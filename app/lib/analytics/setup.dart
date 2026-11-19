import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/analytics/events.dart';
import 'package:family_groceries/analytics/internal.dart';
import 'package:family_groceries/analytics/posthog_client.dart';
import 'package:family_groceries/core/environment.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Analytics for this build, loaded: on only with a PostHog project key
/// and an allowed host built in (docs/ANALYTICS.md), off otherwise.
Future<Analytics> startAnalytics(AnalyticsStore store) async {
  const key = Environment.posthogProjectKey;
  const host = Environment.posthogHost;
  final on = projectKeyLike(key) && allowedHost(host);
  if (key.isNotEmpty && !on) {
    debugPrint('analytics: off, the key or host $host is not accepted');
  }
  final analytics = Analytics(
    on ? PostHogClient(host: host, projectKey: key) : null,
    store,
    AnalyticsConfig(
      // A preview deployment counts like a debug build: internal.
      releaseBuild: kReleaseMode && !Environment.analyticsInternalBuild,
      platform: platformName(web: kIsWeb, platform: defaultTargetPlatform),
      appVersion: await _appVersion(),
      internalHouseholds: csvSet(Environment.analyticsInternalHouseholds),
      internalEmailDomains: csvSet(Environment.analyticsInternalEmailDomains),
      householdGroups: Environment.analyticsHouseholdGroups,
      forcedFlags: host == posthogEuHost
          ? const {}
          : csvSet(Environment.flagsOn),
    ),
  );
  await analytics.load();
  return analytics;
}

/// Hands the errors no one caught to [analytics]' error tracking: the
/// framework's through `FlutterError.onError` (still presented as before),
/// the rest through the platform dispatcher. `main` adds its zone's.
/// [onError] hears each of them too (the rating prompt holds back).
void reportUncaughtErrors(Analytics analytics, {void Function()? onError}) {
  final presentError = FlutterError.onError;
  FlutterError.onError = (details) {
    presentError?.call(details);
    analytics.captureException(details.exception, details.stack);
    onError?.call();
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    analytics.captureException(error, stack);
    onError?.call();
    return false;
  };
}

/// `web`, `ios`, `android`, … as events name it.
String platformName({required bool web, required TargetPlatform platform}) =>
    web ? 'web' : platform.name.toLowerCase();

Future<String> _appVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    final version = info.buildNumber.isEmpty
        ? info.version
        : '${info.version}+${info.buildNumber}';
    return versionPattern.hasMatch(version) ? version : '0';
  } on Object {
    return '0';
  }
}

/// The app's version without the build number (`1.4.0`), as the stores
/// show it; `0` when the platform does not say.
Future<String> appVersionName() async {
  try {
    final version = (await PackageInfo.fromPlatform()).version;
    return version.isEmpty ? '0' : version;
  } on Object {
    return '0';
  }
}

/// The one PostHog host Einkauf data may go to: EU Cloud ingestion.
const posthogEuHost = 'https://eu.i.posthog.com';

/// Whether [host] may receive events: PostHog EU, or a stand-in that can
/// never reach PostHog (a `.invalid` host, or this machine) for e2e runs.
/// Any other host, the US cloud included, leaves analytics off.
bool allowedHost(String host) {
  if (host == posthogEuHost) {
    return true;
  }
  final uri = Uri.tryParse(host);
  if (uri == null || uri.path.isNotEmpty && uri.path != '/') {
    return false;
  }
  return (uri.scheme == 'https' || uri.scheme == 'http') &&
      (uri.host.endsWith('.invalid') ||
          uri.host == 'localhost' ||
          uri.host == '127.0.0.1');
}

/// A project API key as PostHog issues them (`phc_` and letters, digits,
/// `_` or `-`). A personal key (`phx_`) is never accepted.
bool projectKeyLike(String key) =>
    RegExp(r'^phc_[A-Za-z0-9_-]{8,64}$').hasMatch(key);

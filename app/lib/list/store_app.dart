import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/core/open_app.dart';
import 'package:family_groceries/core/open_app_platform.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/retailer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Where a store's chain app opens (job 313, DL1).
enum StoreAppPlatform() {
  android,
  ios,

  /// The web app in an iPhone's browser: the App Store's web page.
  iphoneBrowser,

  /// The web app elsewhere, and desktops: Google Play's web page.
  other;

  static StoreAppPlatform get current => kIsWeb
      ? switch (phoneOsOf(browserUserAgent() ?? '')) {
          PhoneOs.ios => iphoneBrowser,
          _ => other,
        }
      : switch (defaultTargetPlatform) {
          TargetPlatform.android => android,
          TargetPlatform.iOS => ios,
          _ => other,
        };
}

/// What a tap opened, as `store_app_opened` reports it ([wire]).
enum StoreAppOutcome(final String wire) {
  /// The chain's app.
  app('app'),

  /// The app's page in Play or the App Store: it is not installed, or
  /// this is no phone app.
  storePage('store_page'),
}

/// One way to open the app; a plan tries them in order until one works.
sealed class const StoreAppStep(final StoreAppOutcome outcome);

/// Android: the package's launcher activity, without asking which apps are
/// installed (no `<queries>`: starting an activity is not filtered by
/// package visibility).
final class const LaunchPackage(final String package) extends StoreAppStep {
  this : super(StoreAppOutcome.app);
}

/// A link. [appOnly]: only an app that claims it may open it (an iOS
/// universal link), never the browser.
final class const OpenLink(
  final Uri url,
  super.outcome, {
  final bool appOnly = false,
}) extends StoreAppStep;

/// The steps that open [app] on [platform], best first; empty without an
/// app. Only the phone opens anything, and only the app or its store page:
/// Snacklist sends nothing to the chain (Legal N-296), so no step is the
/// chain's own site.
///
/// Android: the app, else Play's app, else Play's web page. iOS: the app's
/// universal link, if it has one, then the bare root of its URL scheme, if
/// it has one, else the App Store. The scheme step may not be app-only: iOS
/// opens only universal links that way. It needs nothing in Info.plist,
/// since nothing asks first whether an app takes the scheme; iOS answers
/// false when none does. The web app and desktops: the App Store's web page
/// in an iPhone's browser, else Play's.
List<StoreAppStep> storeAppPlan(RetailerApp? app, StoreAppPlatform platform) {
  if (app == null) {
    return const [];
  }
  final play = OpenLink(
    Uri.https('play.google.com', '/store/apps/details', {'id': app.android}),
    StoreAppOutcome.storePage,
  );
  return switch (platform) {
    StoreAppPlatform.android => [
      LaunchPackage(app.android),
      OpenLink(
        Uri.parse('market://details?id=${app.android}'),
        StoreAppOutcome.storePage,
      ),
      play,
    ],
    StoreAppPlatform.ios => [
      if (Uri.tryParse(app.universalLink ?? '') case final link?
          when link.isScheme('https'))
        OpenLink(link, StoreAppOutcome.app, appOnly: true),
      if (app.scheme case final scheme?)
        OpenLink(Uri(scheme: scheme, host: ''), StoreAppOutcome.app),
      OpenLink(
        Uri.parse('itms-apps://apps.apple.com/app/id${app.ios}'),
        StoreAppOutcome.storePage,
      ),
    ],
    StoreAppPlatform.iphoneBrowser => [
      OpenLink(
        Uri.https('apps.apple.com', '/app/id${app.ios}'),
        StoreAppOutcome.storePage,
      ),
    ],
    StoreAppPlatform.other => [play],
  };
}

/// What carries out a plan's steps. Tests pass their own.
abstract interface class StoreAppOpener() {
  /// Whether the package's app started.
  Future<bool> launchPackage(String package);

  /// Whether something took [url]; with [appOnly] only an app may.
  Future<bool> openLink(Uri url, {required bool appOnly});
}

/// MainActivity.kt's `familygroceries/store_app` channel and url_launcher.
class const PlatformStoreAppOpener() implements StoreAppOpener {
  static const channel = MethodChannel('familygroceries/store_app');

  @override
  Future<bool> launchPackage(String package) async {
    try {
      return await channel.invokeMethod<bool>('launch', {'package': package}) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> openLink(Uri url, {required bool appOnly}) async {
    try {
      return await launchUrl(
        url,
        mode: appOnly
            ? LaunchMode.externalNonBrowserApplication
            : LaunchMode.externalApplication,
      );
    } on PlatformException {
      return false;
    }
  }
}

/// Tries [plan]'s steps in order; what the first that worked opened, or
/// null when none did.
Future<StoreAppOutcome?> runStoreAppPlan(
  List<StoreAppStep> plan,
  StoreAppOpener opener,
) async {
  for (final step in plan) {
    final opened = switch (step) {
      LaunchPackage(:final package) => await opener.launchPackage(package),
      OpenLink(:final url, :final appOnly) => await opener.openLink(
        url,
        appOnly: appOnly,
      ),
    };
    if (opened) {
      return step.outcome;
    }
  }
  return null;
}

/// The tap on a store's app key or „Öffnen“: opens the chain's app the
/// store picked, else its store page, and reports
/// `store_app_opened` with the chain, never the store. Null when nothing
/// opened, or the store has no chain.
Future<StoreAppOutcome?> openStoreApp(
  Store store, {
  required StoreAppOpener opener,
  Analytics? analytics,
  StoreAppPlatform? platform,
}) async {
  final retailer = store.retailer;
  if (retailer == null) {
    return null;
  }
  final outcome = await runStoreAppPlan(
    storeAppPlan(store.app, platform ?? StoreAppPlatform.current),
    opener,
  );
  if (outcome != null) {
    analytics?.track('store_app_opened', {
      'chain': retailer.chain,
      'country': retailer.country,
      'outcome': outcome.wire,
    });
  }
  return outcome;
}

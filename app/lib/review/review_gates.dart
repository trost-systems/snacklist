import 'package:family_groceries/core/environment.dart';
import 'package:family_groceries/review/review_counters.dart';
import 'package:flutter/foundation.dart';

/// Which kind of build this is. Only [store] asks for reviews: TestFlight
/// and Play internal testers ([beta]) have no public listing to rate.
enum BuildChannel() {
  debug,
  beta,
  store;

  static BuildChannel get current => of(
    release: kReleaseMode,
    storeRelease: Environment.storeRelease,
    web: kIsWeb,
    platform: defaultTargetPlatform,
  );

  /// An iPhone release build is [store]: the build the testers had is the
  /// one App Store review gets, and StoreKit never shows the prompt in
  /// TestFlight. Elsewhere (a Play internal install can show it) only a
  /// build with `STORE_RELEASE` is (docs/RELEASE.md, "Public releases").
  static BuildChannel of({
    required bool release,
    required bool storeRelease,
    required bool web,
    required TargetPlatform platform,
  }) {
    if (!release) {
      return debug;
    }
    return storeRelease || (!web && platform == TargetPlatform.iOS)
        ? store
        : beta;
  }
}

/// What must hold before the app asks the store for the rating prompt, in
/// the order [failingGate] checks them.
enum ReviewGate() {
  storeBuild,
  firstLaunchAge,
  activeDays,
  completedTrips,
  itemsAdded,
  noRecentError,
  cooldown,
  versionCap,
  yearCap,
}

const minFirstLaunchAge = Duration(days: 7);
const minActiveDays = 3;
const minCompletedTrips = 2;
const minItemsAdded = 25;
const errorWindow = Duration(hours: 24);
const requestCooldown = Duration(days: 120);
const maxRequestsPerVersion = 2;
const requestWindow = Duration(days: 365);
const maxRequestsPerWindow = 3;

/// The first gate [c] fails at [now], or null when all pass.
ReviewGate? failingGate(
  ReviewCounters c, {
  required DateTime now,
  required String version,
  required BuildChannel channel,
}) {
  final firstLaunch = c.firstLaunch;
  final last = c.requests.lastOrNull;
  final errorSince = switch (c.previousSessionStart) {
    final previous? when previous.isBefore(now.subtract(errorWindow)) =>
      previous,
    _ => now.subtract(errorWindow),
  };
  final lastError = c.lastErrorAt;
  bool passes(ReviewGate gate) => switch (gate) {
    ReviewGate.storeBuild => channel == BuildChannel.store,
    ReviewGate.firstLaunchAge =>
      firstLaunch != null && now.difference(firstLaunch) >= minFirstLaunchAge,
    ReviewGate.activeDays => c.activeDays >= minActiveDays,
    ReviewGate.completedTrips => c.completedTrips >= minCompletedTrips,
    ReviewGate.itemsAdded => c.itemsAdded >= minItemsAdded,
    ReviewGate.noRecentError =>
      lastError == null || lastError.isBefore(errorSince),
    ReviewGate.cooldown =>
      last == null || now.difference(last.at) >= requestCooldown,
    // Requests older than [requestWindow] are pruned on write, so a version
    // older than a year counts only its last year; the cooldown still holds.
    ReviewGate.versionCap =>
      c.requests.where((r) => r.version == version).length <
          maxRequestsPerVersion,
    ReviewGate.yearCap =>
      c.requests.where((r) => now.difference(r.at) < requestWindow).length <
          maxRequestsPerWindow,
  };
  return ReviewGate.values.where((g) => !passes(g)).firstOrNull;
}

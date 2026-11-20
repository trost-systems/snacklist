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

  /// [ReviewRules.v2]: no failed trip save, join or household switch
  /// since the time [noRecentError] looks back to.
  noRecentSetback,

  /// [ReviewRules.v2]: no bug note in the last [bugNoteWindow].
  noRecentBugNote,

  /// [ReviewRules.v2]: no list emptying taken back this session (SA2).
  notReopened,
  cooldown,
  versionCap,
  yearCap,
}

const minFirstLaunchAge = Duration(days: 7);
const minActiveDays = 3;
const minCompletedTrips = 2;
const minItemsAdded = 25;
const errorWindow = Duration(hours: 24);
const bugNoteWindow = Duration(days: 14);
const maxRequestsPerVersion = 2;
const requestWindow = Duration(days: 365);

/// The rules the prompt asks by: [v1] since job 155, [v2] with the flag
/// `rating-triggers-v2` (job 326), which leaves one of the OS's three
/// prompts a year in reserve and holds back after a setback.
enum ReviewRules({
  required final Duration cooldown,
  required final int maxRequestsPerWindow,

  /// The gates [ReviewGate.noRecentSetback], [ReviewGate.noRecentBugNote]
  /// and [ReviewGate.notReopened] hold; off, they pass.
  required final bool setbacks,

  /// The trigger's trip moments: a fresh trip summary left (ST1), the
  /// emptied list once „Kaufst du gerade ein?“ is answered no (ST2), none
  /// while a trip runs (SA1).
  required final bool tripMoments,
}) {
  v1(
    cooldown: Duration(days: 120),
    maxRequestsPerWindow: 3,
    setbacks: false,
    tripMoments: false,
  ),
  v2(
    cooldown: Duration(days: 180),
    maxRequestsPerWindow: 2,
    setbacks: true,
    tripMoments: true,
  ),
}

/// The first gate [c] fails at [now], or null when all pass.
ReviewGate? failingGate(
  ReviewCounters c, {
  required DateTime now,
  required String version,
  required BuildChannel channel,
  required ReviewRules rules,
}) {
  final firstLaunch = c.firstLaunch;
  final last = c.requests.lastOrNull;
  final errorSince = switch (c.previousSessionStart) {
    final previous? when previous.isBefore(now.subtract(errorWindow)) =>
      previous,
    _ => now.subtract(errorWindow),
  };
  final lastError = c.lastErrorAt;
  final lastSetback = c.lastSetbackAt;
  final lastBugNote = c.lastBugNoteAt;
  final lastReopened = c.lastReopenedAt;
  final session = c.sessionStart;
  bool passes(ReviewGate gate) => switch (gate) {
    ReviewGate.storeBuild => channel == BuildChannel.store,
    ReviewGate.firstLaunchAge =>
      firstLaunch != null && now.difference(firstLaunch) >= minFirstLaunchAge,
    ReviewGate.activeDays => c.activeDays >= minActiveDays,
    ReviewGate.completedTrips => c.completedTrips >= minCompletedTrips,
    ReviewGate.itemsAdded => c.itemsAdded >= minItemsAdded,
    ReviewGate.noRecentError =>
      lastError == null || lastError.isBefore(errorSince),
    ReviewGate.noRecentSetback =>
      !rules.setbacks ||
          lastSetback == null ||
          lastSetback.isBefore(errorSince),
    ReviewGate.noRecentBugNote =>
      !rules.setbacks ||
          lastBugNote == null ||
          now.difference(lastBugNote) >= bugNoteWindow,
    ReviewGate.notReopened =>
      !rules.setbacks ||
          lastReopened == null ||
          session == null ||
          lastReopened.isBefore(session),
    ReviewGate.cooldown =>
      last == null || now.difference(last.at) >= rules.cooldown,
    // Requests older than [requestWindow] are pruned on write, so a version
    // older than a year counts only its last year; the cooldown still holds.
    ReviewGate.versionCap =>
      c.requests.where((r) => r.version == version).length <
          maxRequestsPerVersion,
    ReviewGate.yearCap =>
      c.requests.where((r) => now.difference(r.at) < requestWindow).length <
          rules.maxRequestsPerWindow,
  };
  return ReviewGate.values.where((g) => !passes(g)).firstOrNull;
}

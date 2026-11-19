import 'dart:async';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/core/environment.dart';
import 'package:family_groceries/review/review_counters.dart';
import 'package:family_groceries/review/review_gates.dart';
import 'package:family_groceries/review/store_review.dart';
import 'package:flutter/widgets.dart';

/// Asks the store for its rating prompt once this install has been used
/// enough and nothing went wrong lately (job 155, [failingGate]). Counts
/// per install in [ReviewStore]; a failed read or write only resets or
/// loses a count, like the device cache's other values.
class ReviewPrompt(
  final ReviewStore _store,
  final StoreReview _review, {
  required final BuildChannel channel,

  /// The app version the caps count per; read only when the prompt is due.
  required final Future<String> version,
  DateTime Function()? clock,

  /// Skips the gates outside a store build (`REVIEW_PROMPT_FORCE`).
  final bool force = Environment.reviewPromptForce,
  final Analytics? analytics,
}) {
  final DateTime Function() _clock = clock ?? DateTime.now;
  var _counters = const ReviewCounters();

  /// Every change runs after the one before, the load first, so a count
  /// made before the load lands on the loaded counters.
  late Future<void> _last = _load();

  /// Whether the gates are skipped: [force] never applies to a store build.
  bool get forced => force && channel != BuildChannel.store;

  /// Starts this app session: the first launch if there was none, the
  /// session before this one, and today as an active day.
  Future<void> load() => _last;

  Future<void> _load() async {
    _counters = ReviewCounters.parse(await _read());
    final now = _clock();
    _counters = _newSession(
      _counters.copyWith(firstLaunch: _counters.firstLaunch ?? now),
      now,
    );
    await _save();
  }

  /// Starts a session each time the app comes back from the background
  /// ([AppLifecycleListener.onShow]), not from inactive alone: Control
  /// Center, Face ID or a permission dialog make iOS inactive without
  /// ending the session. A launch into the background (iOS prewarming, an
  /// Android background start) shows the app for the first time later: that
  /// is still the session [load] started. The caller disposes it.
  AppLifecycleListener followLifecycle() {
    // The listener does not replay the current state: an app launched in
    // the foreground is resumed already, so its first return counts.
    var shown =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    return AppLifecycleListener(
      onShow: () {
        if (shown) {
          unawaited(resumed());
        }
      },
      onResume: () => shown = true,
    );
  }

  /// The app came back to the foreground: a new session. iOS keeps an app
  /// alive for weeks, so a cold start would make an old error "the last
  /// session's".
  Future<void> resumed() => _change((c) => _newSession(c, _clock()));

  Future<void> itemAdded() =>
      _change((c) => c.copyWith(itemsAdded: c.itemsAdded + 1));

  Future<void> tripCompleted() =>
      _change((c) => c.copyWith(completedTrips: c.completedTrips + 1));

  /// A refused write, the list offline past its grace, or an uncaught
  /// error.
  Future<void> errorSeen() => _change((c) => c.copyWith(lastErrorAt: _clock()));

  /// Asks the store when every gate passes (or [forced]) and the store has
  /// a prompt here; the store decides whether it shows. Returns whether it
  /// asked.
  Future<bool> requestIfDue() {
    final asked = _last.then((_) async {
      final now = _clock();
      final current = await version;
      if (!forced &&
          failingGate(
                _counters,
                now: now,
                version: current,
                channel: channel,
              ) !=
              null) {
        return false;
      }
      try {
        if (!await _review.isAvailable()) {
          return false;
        }
        await _review.requestReview();
      } on Object {
        return false;
      }
      _counters = _counters.copyWith(
        requests: [
          ..._counters.requests.where(
            (r) => now.difference(r.at) < requestWindow,
          ),
          ReviewRequest(now, current),
        ],
      );
      await _save();
      analytics?.track('review_prompt_requested');
      return true;
    });
    // The chain never fails, or every later count would be lost with it.
    _last = asked.then((_) {}, onError: (_) {});
    return asked;
  }

  Future<void> _change(ReviewCounters Function(ReviewCounters) change) =>
      _last = _last.then((_) {
        _counters = change(_counters);
        return _save();
      });

  static ReviewCounters _newSession(ReviewCounters c, DateTime now) =>
      _withActiveDay(
        c.copyWith(previousSessionStart: c.sessionStart, sessionStart: now),
        now,
      );

  static ReviewCounters _withActiveDay(ReviewCounters c, DateTime now) {
    final local = now.toLocal();
    final day =
        '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
    return day == c.lastActiveDay
        ? c
        : c.copyWith(lastActiveDay: day, activeDays: c.activeDays + 1);
  }

  Future<String?> _read() async {
    try {
      return await _store.reviewState();
    } on Object {
      return null;
    }
  }

  Future<void> _save() async {
    try {
      await _store.saveReviewState(_counters.toJson());
    } on Object {
      // A lost write costs one count.
    }
  }
}

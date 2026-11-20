import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/review/review_counters.dart';
import 'package:family_groceries/review/review_gates.dart';
import 'package:family_groceries/review/review_prompt.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../analytics/fakes.dart';
import 'fakes.dart';

void main() {
  late MemoryReviewStore store;
  late FakeStoreReview review;
  late DateTime now;

  setUp(() {
    store = MemoryReviewStore();
    review = FakeStoreReview();
    now = DateTime(2026, 11, 6, 18);
  });

  ReviewPrompt prompt({
    BuildChannel channel = BuildChannel.store,
    String version = '1.4.0',
    bool force = false,
    Analytics? analytics,
    bool v2 = false,
  }) => ReviewPrompt(
    store,
    review,
    channel: channel,
    version: Future.value(version),
    force: force,
    clock: () => now,
    analytics: analytics,
    v2: () => v2,
  );

  /// An install first opened 8 days ago and used on [days] days, the last
  /// one today, with two trips and 25 adds, started again now.
  Future<ReviewPrompt> used({
    int days = 3,
    BuildChannel channel = BuildChannel.store,
    Analytics? analytics,
    bool v2 = false,
  }) async {
    final today = now;
    now = today.subtract(const Duration(days: 8));
    final first = prompt(channel: channel, analytics: analytics);
    await first.load();
    for (var back = days - 2; back >= 1; back--) {
      now = today.subtract(Duration(days: back));
      await first.resumed();
    }
    for (var i = 0; i < 25; i++) {
      await first.itemAdded();
    }
    await first.tripCompleted();
    await first.tripCompleted();
    now = today;
    final p = prompt(channel: channel, analytics: analytics, v2: v2);
    await p.load();
    return p;
  }

  test('asks the store once every gate passes, then waits out the '
      'cooldown', () async {
    final p = await used();
    expect(await p.requestIfDue(), isTrue);
    expect(review.requests, 1);
    expect(await p.requestIfDue(), isFalse);
    expect(review.requests, 1);
  });

  test(
    'the request outlives the app: a new start is still cooling down',
    () async {
      final p = await used();
      await p.requestIfDue();
      now = now.add(const Duration(days: 119));
      final next = prompt();
      await next.load();
      expect(await next.requestIfDue(), isFalse);
      now = now.add(const Duration(days: 1));
      expect(await next.requestIfDue(), isTrue);
      expect(review.requests, 2);
    },
  );

  test('two active days are not enough; one day counts once however often '
      'the app comes back', () async {
    final p = await used(days: 2);
    for (var i = 0; i < 5; i++) {
      await p.resumed();
    }
    expect(await p.requestIfDue(), isFalse);
    now = now.add(const Duration(days: 1));
    await p.resumed();
    expect(await p.requestIfDue(), isTrue);
  });

  test('nothing is asked when the store has no prompt here', () async {
    final p = await used();
    review.available = false;
    expect(await p.requestIfDue(), isFalse);
    expect(review.requests, 0);
  });

  test('an error this session holds the prompt back', () async {
    final p = await used();
    await p.errorSeen();
    expect(await p.requestIfDue(), isFalse);
    expect(review.requests, 0);
  });

  test('sessions are foreground sessions: an error two resumes and a day '
      'back no longer holds the prompt, without a cold start', () async {
    final p = await used();
    await p.errorSeen();
    now = now.add(const Duration(days: 2));
    await p.resumed();
    expect(await p.requestIfDue(), isFalse, reason: 'the last session');
    now = now.add(const Duration(minutes: 5));
    await p.resumed();
    expect(await p.requestIfDue(), isTrue);
  });

  testWidgets('only a return from the background starts a session: an '
      'inactive bounce keeps an old error in the last session', (tester) async {
    final binding = tester.binding;
    await (await used()).errorSeen();
    now = now.add(const Duration(days: 3));
    final p = prompt();
    await p.load();
    final sessions = p.followLifecycle();
    addTearDown(sessions.dispose);
    Future<bool> due() => p.requestIfDue();
    expect(await due(), isFalse, reason: 'the error was in the last session');

    now = now.add(const Duration(seconds: 5));
    binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(await due(), isFalse, reason: 'Control Center is no new session');

    [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ].forEach(binding.handleAppLifecycleStateChanged);
    expect(await due(), isTrue, reason: 'back from the background');
  });

  testWidgets('after a launch in the foreground, the first return from the '
      'background starts a session and counts the day', (tester) async {
    void go(List<AppLifecycleState> states) =>
        states.forEach(tester.binding.handleAppLifecycleStateChanged);
    go([AppLifecycleState.inactive, AppLifecycleState.resumed]);
    final p = prompt();
    await p.load();
    final sessions = p.followLifecycle();
    addTearDown(sessions.dispose);
    final launched = ReviewCounters.parse(store.json);
    now = now.add(const Duration(days: 1));
    go([
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
    await p.itemAdded();
    final back = ReviewCounters.parse(store.json);
    expect(back.activeDays, launched.activeDays + 1);
    expect(back.sessionStart?.isAtSameMomentAs(now), isTrue);
    expect(back.previousSessionStart, launched.sessionStart);
  });

  testWidgets('a launch into the background: its first showing is the '
      'same session', (tester) async {
    void go(List<AppLifecycleState> states) =>
        states.forEach(tester.binding.handleAppLifecycleStateChanged);
    go([AppLifecycleState.inactive, AppLifecycleState.hidden]);
    await (await used()).errorSeen();
    now = now.add(const Duration(days: 3));
    final p = prompt();
    await p.load();
    final sessions = p.followLifecycle();
    addTearDown(sessions.dispose);
    now = now.add(const Duration(seconds: 5));
    go([AppLifecycleState.inactive, AppLifecycleState.resumed]);
    expect(
      await p.requestIfDue(),
      isFalse,
      reason: 'the error is still in the last session',
    );
  });

  test('a failing version read loses that ask, not the later counts', () async {
    final p = ReviewPrompt(
      store,
      review,
      channel: BuildChannel.store,
      version: Future<String>.error(StateError('no version'))..ignore(),
      clock: () => now,
    );
    await p.load();
    await expectLater(p.requestIfDue(), throwsStateError);
    await p.itemAdded();
    expect(ReviewCounters.parse(store.json).itemsAdded, 1);
  });

  test('a beta build never asks', () async {
    final p = await used(channel: BuildChannel.beta);
    expect(await p.requestIfDue(), isFalse);
    expect(review.requests, 0);
  });

  test('forced, a beta build asks on a fresh install; a store build ignores '
      'the force', () async {
    final beta = prompt(channel: BuildChannel.beta, force: true);
    await beta.load();
    expect(await beta.requestIfDue(), isTrue);
    expect(review.requests, 1);

    store = MemoryReviewStore();
    final release = prompt(force: true);
    await release.load();
    expect(await release.requestIfDue(), isFalse);
    expect(review.requests, 1);
  });

  test('counts made before the load are kept on the loaded counters', () async {
    store.json = const ReviewCounters(itemsAdded: 10).toJson();
    final p = prompt();
    final adds = [p.itemAdded(), p.itemAdded()];
    await Future.wait(adds);
    expect(ReviewCounters.parse(store.json).itemsAdded, 12);
  });

  test('unreadable counters start over', () async {
    store.json = '{"items_added": "many"';
    final p = prompt();
    await p.load();
    expect(
      ReviewCounters.parse(store.json).firstLaunch?.isAtSameMomentAs(now),
      isTrue,
    );
  });

  group('review_prompt_requested', () {
    late NativePostHog sink;
    late Analytics analytics;

    setUp(() async {
      sink = NativePostHog()..install();
      analytics = await loadedAnalytics(MemoryAnalyticsStore())
        ..setUser(customer);
    });

    tearDown(() => analytics.close());

    Future<List<String>> sent() async {
      await analytics.flush();
      return [
        for (final name in sink.names)
          if (name != 'first_open') name,
      ];
    }

    test('is tracked with consent', () async {
      await analytics.decide(granted: true);
      final p = await used(analytics: analytics);
      await p.requestIfDue();
      expect(await sent(), ['review_prompt_requested']);
    });

    test('is not sent without consent', () async {
      await analytics.decide(granted: false);
      final p = await used(analytics: analytics);
      await p.requestIfDue();
      expect(await sent(), isEmpty);
      expect(review.requests, 1);
    });
  });

  group('rating-triggers-v2 (job 326)', () {
    test('a setback holds the prompt back for this session under v2, not '
        'v1', () async {
      final v1 = await used();
      await v1.setback();
      expect(await v1.requestIfDue(), isTrue);
      store = MemoryReviewStore();
      review = FakeStoreReview();
      final p = await used(v2: true);
      await p.setback();
      expect(await p.requestIfDue(), isFalse);
      now = now.add(const Duration(hours: 1));
      await p.resumed();
      expect(
        await p.requestIfDue(),
        isFalse,
        reason: 'the session before still had it',
      );
      now = now.add(const Duration(hours: 24));
      await p.resumed();
      expect(await p.requestIfDue(), isTrue);
      expect(review.requests, 1);
    });

    test('a bug note holds it back for 14 days under v2', () async {
      final p = await used(v2: true);
      await p.bugNoted();
      now = now.add(const Duration(days: 13));
      await p.resumed();
      await p.resumed();
      expect(await p.requestIfDue(), isFalse);
      now = now.add(const Duration(days: 1));
      expect(await p.requestIfDue(), isTrue);
    });

    test(
      'an emptying taken back is no trip and ends the chance of this session; '
      'the next session may ask',
      () async {
        final p = await used(v2: true);
        await p.tripCompleted();
        await p.tripReopened();
        expect(
          ReviewCounters.parse(store.json).completedTrips,
          2,
          reason: 'the taken-back emptying does not count',
        );
        await p.tripCompleted();
        expect(await p.requestIfDue(), isFalse);
        now = now.add(const Duration(minutes: 5));
        await p.resumed();
        expect(await p.requestIfDue(), isTrue);
      },
    );

    test('taking back never counts below zero trips', () async {
      final p = prompt(v2: true);
      await p.load();
      await p.tripReopened();
      await p.tripCompleted();
      expect(ReviewCounters.parse(store.json).completedTrips, 1);
    });

    test('v2 waits 180 days between requests', () async {
      final p = await used(v2: true);
      expect(await p.requestIfDue(), isTrue);
      now = now.add(const Duration(days: 179));
      await p.resumed();
      expect(await p.requestIfDue(), isFalse);
      now = now.add(const Duration(days: 1));
      expect(await p.requestIfDue(), isTrue);
      expect(review.requests, 2);
    });
  });
}

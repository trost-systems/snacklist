import 'package:family_groceries/review/review_counters.dart';
import 'package:family_groceries/review/review_gates.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 6, 18);
  final due = ReviewCounters(
    firstLaunch: now.subtract(const Duration(days: 7)),
    activeDays: 3,
    completedTrips: 2,
    itemsAdded: 25,
    sessionStart: now.subtract(const Duration(minutes: 5)),
    previousSessionStart: now.subtract(const Duration(days: 2)),
  );

  ReviewGate? gate(
    ReviewCounters c, {
    String version = '1.4.0',
    BuildChannel channel = BuildChannel.store,
    ReviewRules rules = ReviewRules.v1,
  }) => failingGate(
    c,
    now: now,
    version: version,
    channel: channel,
    rules: rules,
  );

  ReviewRequest daysAgo(int days, [String version = '1.3.0']) =>
      ReviewRequest(now.subtract(Duration(days: days)), version);

  test('a store build at every threshold passes', () {
    expect(gate(due), isNull);
  });

  test('the channel: an iPhone release is a store build, elsewhere only '
      'with STORE_RELEASE', () {
    BuildChannel of({
      bool release = true,
      bool storeRelease = false,
      bool web = false,
      TargetPlatform platform = TargetPlatform.iOS,
    }) => BuildChannel.of(
      release: release,
      storeRelease: storeRelease,
      web: web,
      platform: platform,
    );
    expect(of(), BuildChannel.store);
    expect(of(release: false), BuildChannel.debug);
    expect(of(release: false, storeRelease: true), BuildChannel.debug);
    expect(of(platform: TargetPlatform.android), BuildChannel.beta);
    expect(
      of(platform: TargetPlatform.android, storeRelease: true),
      BuildChannel.store,
    );
    expect(of(web: true), BuildChannel.beta);
  });

  test('beta and debug builds never pass', () {
    expect(gate(due, channel: BuildChannel.beta), ReviewGate.storeBuild);
    expect(gate(due, channel: BuildChannel.debug), ReviewGate.storeBuild);
  });

  test('the first launch must be a week ago', () {
    expect(
      gate(
        due.copyWith(
          firstLaunch: now.subtract(const Duration(days: 7, seconds: -1)),
        ),
      ),
      ReviewGate.firstLaunchAge,
    );
    expect(gate(const ReviewCounters()), ReviewGate.firstLaunchAge);
  });

  test('3 active days, 2 completed trips and 25 added items', () {
    expect(gate(due.copyWith(activeDays: 2)), ReviewGate.activeDays);
    expect(gate(due.copyWith(completedTrips: 1)), ReviewGate.completedTrips);
    expect(gate(due.copyWith(itemsAdded: 24)), ReviewGate.itemsAdded);
  });

  group('an error', () {
    test('in this session blocks', () {
      expect(
        gate(
          due.copyWith(lastErrorAt: now.subtract(const Duration(minutes: 1))),
        ),
        ReviewGate.noRecentError,
      );
    });

    test('in the last session blocks, also days ago', () {
      final c = due.copyWith(
        previousSessionStart: now.subtract(const Duration(days: 5)),
        sessionStart: now.subtract(const Duration(minutes: 5)),
        lastErrorAt: now.subtract(const Duration(days: 4)),
      );
      expect(gate(c), ReviewGate.noRecentError);
    });

    test('in the last 24 hours blocks', () {
      final c = due.copyWith(
        previousSessionStart: now.subtract(const Duration(hours: 2)),
        lastErrorAt: now.subtract(const Duration(hours: 23)),
      );
      expect(gate(c), ReviewGate.noRecentError);
    });

    test('older than the last session and a day passes', () {
      final c = due.copyWith(
        lastErrorAt: now.subtract(const Duration(days: 2, minutes: 1)),
      );
      expect(gate(c), isNull);
    });
  });

  test('v1: a request 119 days ago blocks, 120 days ago does not', () {
    expect(gate(due.copyWith(requests: [daysAgo(119)])), ReviewGate.cooldown);
    expect(gate(due.copyWith(requests: [daysAgo(120)])), isNull);
  });

  test('two requests in this version block, two in an older one do not', () {
    expect(
      gate(
        due.copyWith(requests: [daysAgo(300, '1.4.0'), daysAgo(150, '1.4.0')]),
      ),
      ReviewGate.versionCap,
    );
    expect(gate(due.copyWith(requests: [daysAgo(300), daysAgo(150)])), isNull);
  });

  test('v1: three requests in 365 days block', () {
    expect(
      gate(
        due.copyWith(
          requests: [
            daysAgo(364, '1.1.0'),
            daysAgo(244, '1.2.0'),
            daysAgo(124),
          ],
        ),
      ),
      ReviewGate.yearCap,
    );
    expect(
      gate(
        due.copyWith(
          requests: [
            daysAgo(365, '1.1.0'),
            daysAgo(244, '1.2.0'),
            daysAgo(124),
          ],
        ),
      ),
      isNull,
    );
  });

  group('v2 (job 326)', () {
    ReviewGate? v2(ReviewCounters c) => gate(c, rules: ReviewRules.v2);

    test('a request 179 days ago blocks, 180 days ago does not', () {
      expect(v2(due.copyWith(requests: [daysAgo(179)])), ReviewGate.cooldown);
      expect(v2(due.copyWith(requests: [daysAgo(180)])), isNull);
    });

    test('two requests in 365 days block', () {
      expect(
        v2(due.copyWith(requests: [daysAgo(364, '1.2.0'), daysAgo(184)])),
        ReviewGate.yearCap,
      );
      expect(
        v2(due.copyWith(requests: [daysAgo(365, '1.2.0'), daysAgo(184)])),
        isNull,
      );
    });

    test('a setback blocks for 24 hours or since the last session, as an '
        'error does; v1 ignores it', () {
      final hoursAgo = due.copyWith(
        previousSessionStart: now.subtract(const Duration(hours: 2)),
        lastSetbackAt: now.subtract(const Duration(hours: 23)),
      );
      expect(v2(hoursAgo), ReviewGate.noRecentSetback);
      expect(gate(hoursAgo), isNull);
      final lastSession = due.copyWith(
        previousSessionStart: now.subtract(const Duration(days: 5)),
        lastSetbackAt: now.subtract(const Duration(days: 4)),
      );
      expect(v2(lastSession), ReviewGate.noRecentSetback);
      expect(
        v2(
          due.copyWith(
            lastSetbackAt: now.subtract(const Duration(days: 2, minutes: 1)),
          ),
        ),
        isNull,
      );
    });

    test('a bug note blocks for 14 days; v1 ignores it', () {
      final recent = due.copyWith(
        lastBugNoteAt: now.subtract(const Duration(days: 13, hours: 23)),
      );
      expect(v2(recent), ReviewGate.noRecentBugNote);
      expect(gate(recent), isNull);
      expect(
        v2(due.copyWith(lastBugNoteAt: now.subtract(bugNoteWindow))),
        isNull,
      );
    });

    test('an emptying taken back blocks the rest of the session; v1 '
        'ignores it', () {
      final thisSession = due.copyWith(
        lastReopenedAt: now.subtract(const Duration(minutes: 1)),
      );
      expect(v2(thisSession), ReviewGate.notReopened);
      expect(gate(thisSession), isNull);
      expect(
        v2(
          due.copyWith(
            lastReopenedAt: now.subtract(const Duration(minutes: 10)),
          ),
        ),
        isNull,
      );
    });
  });
}

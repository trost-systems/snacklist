import 'dart:convert';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/analytics/events.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/pending_invite.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../household/harness.dart' show MemoryPendingStore;
import '../session/fake_auth.dart';
import '../session/fake_households.dart';
import 'fakes.dart';

const _home = '0b6f7a52-6c1e-4f4e-9d55-3f1f0c2a9e01';
const _other = '7d0c1c55-1111-4a2b-8c3d-2e9f6a1b0c02';

void main() {
  late FakeAuth auth;
  late FakeHouseholds db;
  late NativePostHog sink;
  late Analytics analytics;
  late SessionCubit cubit;

  setUp(() async {
    auth = FakeAuth()
      ..user = const User(
        id: 'peter',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '2026-10-22T12:00:00Z',
        email: 'kunde@gmail.com',
      );
    db = FakeHouseholds(auth)
      ..nextIds.add(_home)
      ..member('lea', _other, 'Trost')
      ..invites['ABCD2345'] = _other;
    sink = NativePostHog()..install();
    analytics = await loadedAnalytics(MemoryAnalyticsStore());
    cubit = SessionCubit(db, MemorySessionCache(), analytics: analytics);
    await cubit.refresh();
    await analytics.decide(granted: true);
  });

  tearDown(() async {
    await cubit.close();
    await analytics.close();
    await auth.close();
  });

  Future<List<Map<String, Object?>>> sent() async {
    await analytics.flush();
    return [
      for (final e in sink.events)
        if (e['event'] != 'first_open') e,
    ];
  }

  Map<String, Object?> props(Map<String, Object?> e) =>
      e['properties']! as Map<String, Object?>;

  test('the yes reaches the server once, for this install (job 31)', () async {
    await pumpEventQueue();
    expect(
      db.calls.where((c) => c.startsWith('rpc/record_analytics_consent')),
      hasLength(1),
    );
    await cubit.createHousehold('Zuhause');
    await pumpEventQueue();
    expect(
      db.calls.where((c) => c.startsWith('rpc/record_analytics_consent')),
      hasLength(1),
      reason: 'a household change is not a new answer',
    );
  });

  test('first_open before a household has no household_id', () async {
    await analytics.flush();
    expect(sink.names, ['first_open']);
    expect(props(sink.events.single)['household_id'], isNull);
  });

  test('creating a household sends household_created with its id', () async {
    await cubit.createHousehold('Zuhause');
    final events = await sent();
    expect(events.map((e) => e['event']), ['household_created']);
    expect(props(events.single)['household_id'], _home);
    expect(props(events.single)['store_count'], 0);
    expect(props(events.single)['context'], 'onboarding');
  });

  test("the switcher's create says so", () async {
    db.nextIds.add('5e1d2c3b-2222-4a2b-8c3d-2e9f6a1b0c03');
    await cubit.createHousehold('Zuhause');
    await cubit.createHousehold('Eltern', from: HouseholdOrigin.switcher);
    final events = await sent();
    expect(
      [for (final e in events) props(e)['context']],
      ['onboarding', 'switcher'],
    );
    expect(props(events.last)['household_id'], isNot(_home));
  });

  test('a switch sends household_switched in the household shown', () async {
    await cubit.createHousehold('Zuhause');
    await cubit.join('ABCD2345');
    await cubit.switchTo(_home);
    await cubit.switchTo(_home);
    final events = await sent();
    expect(events.map((e) => e['event']), [
      'household_created',
      'invite_accepted',
      'household_switched',
    ]);
    final switched = props(events.last);
    expect(switched['household_id'], _home);
    expect(switched.keys, isNot(contains('household')));
  });

  test('the stores picked in onboarding are counted, not named', () async {
    await cubit.createHousehold('Zuhause', stores: const ['REWE', 'dm']);
    final properties = props((await sent()).single);
    expect(properties['store_count'], 2);
    expect(properties.values, isNot(contains('REWE')));
  });

  test('a create whose answer was lost, retried, is one household and one '
      'event', () async {
    db.dropNextAnswer = true;
    await expectLater(
      cubit.createHousehold('Zuhause', stores: const ['REWE']),
      throwsA(
        isA<HouseholdError>().having(
          (e) => e.problem,
          'problem',
          HouseholdProblem.offline,
        ),
      ),
    );
    expect(cubit.state, isA<NeedsHousehold>());
    // The retry's request id finds the household the first call made.
    await cubit.createHousehold('Zuhause', stores: const ['REWE']);
    expect(cubit.state, isA<InHousehold>());
    expect(db.calls.where((c) => c.contains('create_household')), hasLength(2));
    expect(db.memberships['peter'], [_home]);
    final events = await sent();
    expect(events.map((e) => e['event']), ['household_created']);
    expect(props(events.single)['store_count'], 1);
  });

  test(
    'a second create while one is out (double tap) sends nothing more',
    () async {
      await Future.wait([
        cubit.createHousehold('Zuhause'),
        cubit.createHousehold('Zuhause'),
      ]);
      expect(db.memberships['peter'], [_home]);
      expect((await sent()).map((e) => e['event']), ['household_created']);
    },
  );

  test('a join by link sends invite_accepted, method link', () async {
    await cubit.join('ABCD2345', method: JoinMethod.link);
    final events = await sent();
    expect(events.map((e) => e['event']), ['invite_accepted']);
    expect(props(events.single)['method'], 'link');
    expect(props(events.single)['household_id'], _other);
    expect(jsonEncode(events), isNot(contains('ABCD2345')));
  });

  test('a typed code is method code', () async {
    await cubit.join('ABCD2345');
    expect(props((await sent()).single)['method'], 'code');
  });

  test('joining beside a household is a join too', () async {
    await cubit.createHousehold('Zuhause');
    await cubit.join('ABCD2345', method: JoinMethod.link);
    expect((await sent()).map((e) => e['event']), [
      'household_created',
      'invite_accepted',
    ]);
  });

  test('joining the household one is in already sends nothing', () async {
    await cubit.createHousehold('Zuhause');
    db.invites['ABCD2345'] = _home;
    await cubit.join('ABCD2345', method: JoinMethod.link);
    expect((await sent()).map((e) => e['event']), ['household_created']);
  });

  test('a refused invite sends nothing', () async {
    await expectLater(
      cubit.join('XXXX'),
      throwsA(
        isA<HouseholdError>().having(
          (e) => e.problem,
          'problem',
          HouseholdProblem.invalidInvite,
        ),
      ),
    );
    expect(await sent(), isEmpty);
  });

  test(
    'a join whose answer was lost, retried, sends invite_accepted once',
    () async {
      db.dropNextAnswer = true;
      await expectLater(
        cubit.join('ABCD2345', method: JoinMethod.link),
        throwsA(isA<HouseholdError>()),
      );
      // The retry answers member: the first call joined.
      await cubit.join('ABCD2345', method: JoinMethod.link);
      await cubit.join('ABCD2345', method: JoinMethod.link);
      final events = await sent();
      expect(events.map((e) => e['event']), ['invite_accepted']);
      expect(props(events.single)['method'], 'link');
    },
  );

  test('a join and a sign-out answer the pending invite', () async {
    final pending = PendingInvite(MemoryPendingStore())..remember('ABCD2345');
    final withPending = SessionCubit(
      db,
      MemorySessionCache(),
      pendingInvite: pending,
    );
    addTearDown(withPending.close);
    await withPending.refresh();
    db.invites.remove('ABCD2345');
    await expectLater(withPending.join('ABCD2345'), throwsA(anything));
    expect(pending.code, 'ABCD2345', reason: 'the screen decides on refusals');
    db.invites['ABCD2345'] = _other;
    await withPending.join('ABCD2345', method: JoinMethod.link);
    expect(pending.code, isNull);
    pending.remember('WXYZ6789');
    await withPending.signOut();
    expect(pending.code, isNull);
  });

  test('signing out sends what waits first, then nothing', () async {
    await cubit.createHousehold('Zuhause');
    await cubit.signOut();
    await pumpEventQueue();
    analytics.track('store_reordered');
    expect((await sent()).map((e) => e['event']), ['household_created']);
  });

  test('a household created whose reload fails still counts, in it', () async {
    db.failReads = true;
    await expectLater(cubit.createHousehold('Zuhause'), throwsA(anything));
    final events = await sent();
    expect(events.map((e) => e['event']), ['household_created']);
    expect(props(events.single)['household_id'], _home);
  });
}

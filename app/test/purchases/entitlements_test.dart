import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:family_groceries/purchases/entitlements.dart';
import 'package:family_groceries/purchases/purchase_repository.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../household/harness.dart' show TestSession;
import 'fakes.dart';

void main() {
  Future<(Entitlements, TestSession)> follow(
    FakeEntitlementsSource rows, {
    Session session = const InHousehold(
      'peter',
      Household(id: 'home', name: 'Zuhause'),
      [Household(id: 'home', name: 'Zuhause')],
    ),
  }) async {
    final testSession = TestSession(session);
    addTearDown(testSession.close);
    final entitlements = Entitlements(rows, testSession);
    addTearDown(entitlements.close);
    await pumpEventQueue();
    return (entitlements, testSession);
  }

  test('without a household nothing is known or watched', () async {
    final rows = FakeEntitlementsSource(unlockedNow: true);
    final (entitlements, _) = await follow(
      rows,
      session: const NeedsHousehold('peter'),
    );
    expect(entitlements.state, isA<EntitlementsUnknown>());
    expect(entitlements.has(Entitlement.premium), isFalse);
    expect(rows.watching, isEmpty);
  });

  test("reads the household's rows and follows them", () async {
    final rows = FakeEntitlementsSource();
    final (entitlements, _) = await follow(rows);
    expect(
      entitlements.state,
      isA<EntitlementsKnown>()
          .having((s) => s.householdId, 'household', 'home')
          .having((s) => s.unlocks.rows, 'rows', isEmpty),
    );
    expect(rows.watching, {'home'});
    rows
      ..unlockedNow = true
      ..change();
    await pumpEventQueue();
    expect(entitlements.has(Entitlement.premium), isTrue);
  });

  test('offline it stays unknown until a reconnect reads', () async {
    final rows = FakeEntitlementsSource(unlockedNow: true)..offline = true;
    final (entitlements, _) = await follow(rows);
    expect(entitlements.state, isA<EntitlementsUnknown>());
    rows
      ..offline = false
      ..change();
    await pumpEventQueue();
    expect(entitlements.has(Entitlement.premium), isTrue);
  });

  test('offline later keeps what it knew', () async {
    final rows = FakeEntitlementsSource(unlockedNow: true);
    final (entitlements, _) = await follow(rows);
    rows.offline = true;
    await entitlements.refresh();
    expect(entitlements.has(Entitlement.premium), isTrue);
  });

  test("another household's unlock is not this one's", () async {
    final rows = FakeEntitlementsSource(unlockedNow: true);
    final (entitlements, session) = await follow(rows);
    expect(entitlements.has(Entitlement.premium), isTrue);
    rows.unlockedNow = false;
    await session.join('ABCD2345');
    await pumpEventQueue();
    expect(rows.watching, {'other'});
    expect(
      entitlements.state,
      isA<EntitlementsKnown>()
          .having((s) => s.householdId, 'id', 'other')
          .having((s) => s.unlocks.rows, 'rows', isEmpty),
    );
  });

  test(
    'Buy may be offered only once the household is known to lack it',
    () async {
      final rows = FakeEntitlementsSource()..offline = true;
      final (entitlements, _) = await follow(rows);
      expect(
        entitlements.canOffer(Entitlement.premium, PremiumPlan.lifetime),
        isFalse,
        reason: 'unknown',
      );
      rows
        ..offline = false
        ..change();
      await pumpEventQueue();
      expect(
        entitlements.canOffer(Entitlement.premium, PremiumPlan.lifetime),
        isTrue,
        reason: 'known, locked',
      );
      rows
        ..unlockedNow = true
        ..change();
      await pumpEventQueue();
      expect(
        entitlements.canOffer(Entitlement.premium, PremiumPlan.lifetime),
        isFalse,
        reason: 'unlocked',
      );
    },
  );

  test('a kind this build does not know unlocks nothing', () async {
    final rows = FakeEntitlementsSource()
      ..rowsNow = [
        {'kind': 'plus', 'source': 'purchase'},
      ];
    final (entitlements, _) = await follow(rows);
    expect(entitlements.has(Entitlement.premium), isFalse);
    expect(
      entitlements.canOffer(Entitlement.premium, PremiumPlan.lifetime),
      isTrue,
    );
  });

  test('a premium source this build does not know unlocks nothing', () async {
    final rows = FakeEntitlementsSource()
      ..rowsNow = [
        {'kind': 'premium', 'source': 'purchase', 'premium_source': 'monthly'},
      ];
    final (entitlements, _) = await follow(rows);
    expect(entitlements.has(Entitlement.premium), isFalse);
    expect(
      entitlements.canOffer(Entitlement.premium, PremiumPlan.yearly),
      isTrue,
    );
    rows
      ..rowsNow = [
        {'kind': 'premium', 'source': 'purchase'},
      ]
      ..change();
    await pumpEventQueue();
    expect(
      entitlements.premium,
      isA<ActivePremium>().having(
        (p) => p.source,
        'source',
        PremiumSource.lifetime,
      ),
      reason: 'without premium_source (a server before job 49): Lifetime',
    );
  });

  test('reads finishing out of order: the latest started wins', () async {
    final rows = FakeEntitlementsSource();
    final (entitlements, _) = await follow(rows);
    rows.holdReads = true;
    final older = entitlements.refresh();
    final newer = entitlements.refresh();
    expect(rows.heldReads, hasLength(2));
    rows.heldReads[1].complete(
      unlocksOf([
        {'kind': 'premium', 'source': 'purchase', 'premium_source': 'lifetime'},
      ]),
    );
    await newer;
    expect(entitlements.has(Entitlement.premium), isTrue);
    rows.heldReads[0].complete(unlocksOf([]));
    await older;
    expect(
      entitlements.has(Entitlement.premium),
      isTrue,
      reason: 'the older read, before the purchase, does not undo it',
    );
  });

  test(
    "a promotional grant (a tester's) unlocks premium and is marked",
    () async {
      final rows = FakeEntitlementsSource()..rowsNow = [promotionalRow()];
      final (entitlements, _) = await follow(rows);
      expect(entitlements.has(Entitlement.premium), isTrue);
      expect(
        entitlements.state,
        isA<EntitlementsKnown>().having(
          (s) => s.unlocks.tester,
          'tester',
          isTrue,
        ),
      );
    },
  );

  test(
    'two Lifetime purchases: bought twice; a promotional grant does not count',
    () async {
      final rows = FakeEntitlementsSource()
        ..rowsNow = [
          {'kind': 'lifetime', 'source': 'purchase'},
          promotionalRow(),
        ];
      final (entitlements, _) = await follow(rows);
      expect(entitlements.boughtLifetimeTwice, isFalse);
      rows
        ..rowsNow = [
          {'kind': 'lifetime', 'source': 'purchase'},
          {'kind': 'lifetime', 'source': 'purchase'},
        ]
        ..change();
      await pumpEventQueue();
      expect(entitlements.boughtLifetimeTwice, isTrue);
      expect(
        entitlements.state,
        isA<EntitlementsKnown>().having(
          (s) => s.unlocks.lifetimePurchases,
          'purchases',
          2,
        ),
      );
    },
  );

  test('signing out forgets and stops watching', () async {
    final rows = FakeEntitlementsSource(unlockedNow: true);
    final (entitlements, session) = await follow(rows);
    await session.signOut();
    await pumpEventQueue();
    expect(entitlements.state, isA<EntitlementsUnknown>());
    expect(rows.watching, isEmpty);
  });

  group('premium at read time (the server rule, household_premium)', () {
    final now = DateTime.utc(2026, 11, 1, 12);
    Premium premiumOf(List<Map<String, dynamic>> rows) =>
        unlocksOf(rows).premiumAt(now);

    test('the legacy wire value lifetime reads as premium', () {
      expect(Entitlement.parse('lifetime'), Entitlement.premium);
      expect(Entitlement.parse('premium'), Entitlement.premium);
      expect(Entitlement.parse('plus'), isNull);
      expect(
        premiumOf([
          {'kind': 'lifetime', 'source': 'purchase'},
        ]),
        isA<ActivePremium>().having(
          (p) => p.source,
          'source',
          PremiumSource.lifetime,
        ),
      );
    });

    test('an active yearly plan: premium until its end, renewing', () {
      expect(
        premiumOf([yearlyRow(from: now)]),
        isA<ActivePremium>()
            .having((p) => p.source, 'source', PremiumSource.yearly)
            .having(
              (p) => p.expiresAt,
              'end',
              now.add(const Duration(days: 200)),
            )
            .having((p) => p.renews, 'renews', isTrue),
      );
      expect(
        premiumOf([yearlyRow(from: now, renews: false)]),
        isA<ActivePremium>().having((p) => p.renews, 'renews', isFalse),
      );
    });

    test('an ended yearly plan is no premium, without any event', () {
      expect(premiumOf([yearlyRow(from: now, days: -1)]), isA<NoPremium>());
    });

    test('Lifetime and tester grants win over yearly and never end', () {
      final yearly = yearlyRow(from: now);
      expect(
        premiumOf([
          yearly,
          {
            'kind': 'premium',
            'source': 'purchase',
            'premium_source': 'lifetime',
          },
        ]),
        isA<ActivePremium>()
            .having((p) => p.source, 'source', PremiumSource.lifetime)
            .having((p) => p.expiresAt, 'end', isNull),
      );
      expect(
        premiumOf([yearly, promotionalRow()]),
        isA<ActivePremium>()
            .having((p) => p.source, 'source', PremiumSource.promotional)
            .having((p) => p.expiresAt, 'end', isNull),
      );
    });

    test('two yearly plans: premium runs to the later end', () {
      expect(
        premiumOf([yearlyRow(from: now, days: 10), yearlyRow(from: now)]),
        isA<ActivePremium>().having(
          (p) => p.expiresAt,
          'end',
          now.add(const Duration(days: 200)),
        ),
      );
    });

    test('a promotional grant: premium until its end, then none', () {
      expect(
        premiumOf([promotionalRow(from: now)]),
        isA<ActivePremium>()
            .having((p) => p.source, 'source', PremiumSource.promotional)
            .having(
              (p) => p.expiresAt,
              'end',
              now.add(const Duration(days: 30)),
            )
            .having((p) => p.renews, 'renews', isFalse),
      );
      expect(
        premiumOf([promotionalRow(from: now, days: -1)]),
        isA<NoPremium>(),
      );
    });

    test('a promotional grant without end never ends; Lifetime still wins', () {
      expect(
        premiumOf([promotionalRow(), yearlyRow(from: now)]),
        isA<ActivePremium>()
            .having((p) => p.source, 'source', PremiumSource.promotional)
            .having((p) => p.expiresAt, 'end', isNull),
      );
      expect(
        premiumOf([
          promotionalRow(),
          {
            'kind': 'premium',
            'source': 'purchase',
            'premium_source': 'lifetime',
          },
        ]),
        isA<ActivePremium>().having(
          (p) => p.source,
          'source',
          PremiumSource.lifetime,
        ),
      );
    });

    test(
      'a promotional grant next to a yearly plan: the later end names it',
      () {
        expect(
          premiumOf([promotionalRow(from: now), yearlyRow(from: now)]),
          isA<ActivePremium>()
              .having((p) => p.source, 'source', PremiumSource.yearly)
              .having((p) => p.renews, 'renews', isTrue),
        );
        expect(
          premiumOf([
            promotionalRow(from: now, days: 300),
            yearlyRow(from: now),
          ]),
          isA<ActivePremium>()
              .having((p) => p.source, 'source', PremiumSource.promotional)
              .having(
                (p) => p.expiresAt,
                'end',
                now.add(const Duration(days: 300)),
              )
              .having((p) => p.renews, 'renews', isFalse),
        );
      },
    );

    test('a promotional row with an unreadable end is dropped', () {
      expect(
        premiumOf([
          {...promotionalRow(), 'expires_at': 'soon'},
        ]),
        isA<NoPremium>(),
      );
    });

    test('a yearly row without its end is dropped', () {
      expect(
        premiumOf([
          {'kind': 'premium', 'source': 'purchase', 'premium_source': 'yearly'},
        ]),
        isA<NoPremium>(),
      );
    });
  });

  group('what may be offered (canOffer, H-84)', () {
    final now = DateTime.utc(2026, 11, 1, 12);

    Future<Entitlements> known(List<Map<String, dynamic>> rows) async {
      final session = TestSession(
        const InHousehold('peter', Household(id: 'home', name: 'Zuhause'), [
          Household(id: 'home', name: 'Zuhause'),
        ]),
      );
      addTearDown(session.close);
      final entitlements = Entitlements(
        FakeEntitlementsSource()..rowsNow = rows,
        session,
        now: () => now,
      );
      addTearDown(entitlements.close);
      await pumpEventQueue();
      return entitlements;
    }

    List<PremiumPlan> offered(Entitlements e) => [
      for (final plan in PremiumPlan.values)
        if (e.canOffer(Entitlement.premium, plan)) plan,
    ];

    test('no premium: both plans', () async {
      expect(offered(await known([])), PremiumPlan.values);
    });

    test(
      'an active yearly plan: only Lifetime, never a second yearly plan',
      () async {
        final e = await known([yearlyRow(from: now)]);
        expect(offered(e), [PremiumPlan.lifetime]);
        expect(e.yearlyBilled, isTrue);
      },
    );

    test('a lapsed yearly plan: both plans again', () async {
      expect(
        offered(await known([yearlyRow(from: now, days: -3)])),
        PremiumPlan.values,
      );
    });

    test('Lifetime or a tester grant: nothing', () async {
      expect(
        offered(
          await known([
            {
              'kind': 'premium',
              'source': 'purchase',
              'premium_source': 'lifetime',
            },
          ]),
        ),
        isEmpty,
      );
      expect(
        offered(await known([promotionalRow(), yearlyRow(from: now)])),
        isEmpty,
      );
    });

    test('a running promotional grant: nothing; once it ended, both', () async {
      expect(offered(await known([promotionalRow(from: now)])), isEmpty);
      expect(offered(await known([promotionalRow()])), isEmpty);
      expect(
        offered(await known([promotionalRow(from: now, days: -1)])),
        PremiumPlan.values,
      );
    });

    test('Lifetime next to a renewing yearly plan: still billed', () async {
      final e = await known([
        yearlyRow(from: now),
        {'kind': 'premium', 'source': 'purchase', 'premium_source': 'lifetime'},
      ]);
      expect(e.yearlyBilled, isTrue);
      expect(e.twoYearlyPlans, isFalse);
    });
  });

  test('when a promotional grant ends, the rows are read again', () {
    fakeAsync((async) {
      var clock = DateTime.utc(2026, 11, 1, 12);
      final session = TestSession(
        const InHousehold('peter', Household(id: 'home', name: 'Zuhause'), [
          Household(id: 'home', name: 'Zuhause'),
        ]),
      );
      final rows = FakeEntitlementsSource()
        ..rowsNow = [promotionalRow(from: clock, days: 1)];
      final entitlements = Entitlements(rows, session, now: () => clock);
      async.flushMicrotasks();
      expect(entitlements.has(Entitlement.premium), isTrue);
      var reads = 0;
      final sub = entitlements.stream.listen((_) => reads++);
      clock = clock.add(const Duration(days: 1, seconds: 2));
      async
        ..elapse(const Duration(days: 1, seconds: 2))
        ..flushMicrotasks();
      expect(reads, greaterThan(0), reason: 'read again at the end');
      expect(entitlements.has(Entitlement.premium), isFalse);
      unawaited(sub.cancel());
      unawaited(entitlements.close());
      unawaited(session.close());
      async.flushMicrotasks();
    });
  });

  test('the end passes offline: re-emitted, premium off', () {
    fakeAsync((async) {
      var clock = DateTime.utc(2026, 11, 1, 12);
      final session = TestSession(
        const InHousehold('peter', Household(id: 'home', name: 'Zuhause'), [
          Household(id: 'home', name: 'Zuhause'),
        ]),
      );
      final rows = FakeEntitlementsSource()
        ..rowsNow = [yearlyRow(from: clock, days: 1, renews: false)];
      final entitlements = Entitlements(rows, session, now: () => clock);
      async.flushMicrotasks();
      expect(entitlements.has(Entitlement.premium), isTrue);
      final states = <EntitlementsState>[];
      final sub = entitlements.stream.listen(states.add);
      rows.offline = true;
      clock = clock.add(const Duration(days: 1, seconds: 2));
      async
        ..elapse(const Duration(days: 1, seconds: 2))
        ..flushMicrotasks();
      expect(states, [
        isA<EntitlementsKnown>(),
      ], reason: 'listeners rebuild at the new clock');
      expect(entitlements.has(Entitlement.premium), isFalse);
      expect(
        entitlements.canOffer(Entitlement.premium, PremiumPlan.yearly),
        isTrue,
      );
      unawaited(sub.cancel());
      unawaited(entitlements.close());
      unawaited(session.close());
      async.flushMicrotasks();
    });
  });

  test('offline before anything was read: nothing emitted', () async {
    final rows = FakeEntitlementsSource()..offline = true;
    final (entitlements, _) = await follow(rows);
    final states = <EntitlementsState>[];
    final sub = entitlements.stream.listen(states.add);
    addTearDown(sub.cancel);
    await entitlements.refresh();
    await pumpEventQueue();
    expect(states, isEmpty);
    expect(entitlements.state, isA<EntitlementsUnknown>());
  });

  test('when a yearly plan ends, the rows are read again', () {
    fakeAsync((async) {
      var clock = DateTime.utc(2026, 11, 1, 12);
      final session = TestSession(
        const InHousehold('peter', Household(id: 'home', name: 'Zuhause'), [
          Household(id: 'home', name: 'Zuhause'),
        ]),
      );
      final rows = FakeEntitlementsSource()
        ..rowsNow = [yearlyRow(from: clock, days: 1)];
      final entitlements = Entitlements(rows, session, now: () => clock);
      async.flushMicrotasks();
      expect(entitlements.has(Entitlement.premium), isTrue);
      final states = <EntitlementsState>[];
      final sub = entitlements.stream.listen(states.add);
      clock = clock.add(const Duration(days: 1, seconds: 2));
      async
        ..elapse(const Duration(days: 1, seconds: 2))
        ..flushMicrotasks();
      expect(states, isNotEmpty, reason: 'read again at the end');
      expect(entitlements.has(Entitlement.premium), isFalse);
      expect(
        entitlements.canOffer(Entitlement.premium, PremiumPlan.yearly),
        isTrue,
      );
      unawaited(sub.cancel());
      unawaited(entitlements.close());
      unawaited(session.close());
      async.flushMicrotasks();
    });
  });
}

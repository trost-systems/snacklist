import 'package:family_groceries/purchases/entitlements.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../household/harness.dart' show TestSession;
import 'fakes.dart';

/// The rules the Premium page reads off the rows of the household and of
/// the signed-in user: who paid (refund help), what still bills (Manage,
/// the Lifetime-while-yearly warning) and when premium may change unasked.
void main() {
  final now = DateTime.utc(2026, 11, 26, 12);
  const boughtLifetime = {
    'kind': 'premium',
    'source': 'purchase',
    'premium_source': 'lifetime',
  };

  Unlocks of(
    List<Map<String, dynamic>> household, [
    List<Map<String, dynamic>> own = const [],
  ]) => unlocksOf(household).merge(unlocksOf(own, own: true));

  group('someone paid (refund help)', () {
    test("the household's purchase alone counts", () {
      expect(of([boughtLifetime]).purchased, isTrue);
      expect(of([], [boughtLifetime]).purchased, isTrue);
    });

    test('a purchase next to a grant counts; grants alone do not', () {
      expect(of([lifetimeGrantRow, yearlyRow(from: now)]).purchased, isTrue);
      expect(
        of([lifetimeGrantRow, promotionalRow(from: now)]).purchased,
        isFalse,
      );
    });

    test('a grant next to a purchase still marks testers', () {
      expect(of([boughtLifetime, lifetimeGrantRow]).tester, isTrue);
      expect(of([boughtLifetime]).tester, isFalse);
    });
  });

  group('a yearly plan', () {
    test('still renews when one of two running plans was cancelled', () {
      final unlocks = of(
        [yearlyRow(from: now, renews: false)],
        [yearlyRow(from: now, days: 100)],
      );
      expect(unlocks.yearlyBilledAt(now), isTrue);
      expect(
        unlocks.premiumAt(now),
        isA<ActivePremium>().having((p) => p.renews, 'renews', isTrue),
      );
    });

    test('that ended bills no more, even if its row still says it renews', () {
      final unlocks = of([yearlyRow(from: now, days: -1)]);
      expect(unlocks.yearlyBilledAt(now), isFalse);
      expect(unlocks.premiumAt(now), isA<NoPremium>());
    });

    test('ending with a promotional grant at the same moment names the plan, '
        'which renews', () {
      final end = now.add(const Duration(days: 30));
      final unlocks = of([
        {...promotionalRow(), 'expires_at': end.toIso8601String()},
        yearlyRow(from: now, days: 30),
      ]);
      expect(
        unlocks.premiumAt(now),
        isA<ActivePremium>()
            .having((p) => p.source, 'source', PremiumSource.yearly)
            .having((p) => p.expiresAt, 'expiresAt', end)
            .having((p) => p.renews, 'renews', isTrue),
      );
      expect(
        of([
          yearlyRow(from: now, days: 30),
          {...promotionalRow(), 'expires_at': end.toIso8601String()},
        ]).premiumAt(now),
        isA<ActivePremium>().having(
          (p) => p.source,
          'source',
          PremiumSource.yearly,
        ),
        reason: 'in either order',
      );
    });

    test('Lifetime never renews', () {
      expect(
        of([boughtLifetime]).premiumAt(now),
        isA<ActivePremium>().having((p) => p.renews, 'renews', isFalse),
      );
    });
  });

  test('premium may change next at the earliest end still to come', () {
    final unlocks = of(
      [yearlyRow(from: now), promotionalRow(from: now, days: 3)],
      [yearlyRow(from: now, days: 40), yearlyRow(from: now, days: -2)],
    );
    expect(unlocks.nextEndAfter(now), now.add(const Duration(days: 3)));
    expect(of([boughtLifetime]).nextEndAfter(now), isNull);
  });

  test(
    'not read yet (offline): no "paid", "twice" or "billed" on a guess',
    () async {
      final session = TestSession(
        const InHousehold('peter', Household(id: 'home', name: 'Zuhause'), [
          Household(id: 'home', name: 'Zuhause'),
        ]),
      );
      addTearDown(session.close);
      final entitlements = Entitlements(
        FakeEntitlementsSource()
          ..offline = true
          ..rowsNow = [boughtLifetime, boughtLifetime]
          ..userRows['peter'] = [
            yearlyRow(from: now),
            yearlyRow(from: now, days: 100),
          ],
        session,
        now: () => now,
      );
      addTearDown(entitlements.close);
      await pumpEventQueue();
      expect(entitlements.state, isA<EntitlementsUnknown>());
      expect(entitlements.purchased, isFalse);
      expect(entitlements.boughtLifetimeTwice, isFalse);
      expect(entitlements.twoYearlyPlans, isFalse);
      expect(entitlements.yearlyBilled, isFalse);
    },
  );
}

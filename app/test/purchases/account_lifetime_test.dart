import 'package:family_groceries/purchases/entitlements.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../household/harness.dart' show TestSession;
import 'fakes.dart';

/// Whose Lifetime it is decides the refund prompts (Terms §6): a household's
/// leftover unlock never prompts a member who holds their own Lifetime, and
/// a member without one is never told they hold it.
void main() {
  final now = DateTime.utc(2026, 11, 26, 12);
  const home = Household(id: 'home', name: 'Zuhause');
  const boughtLifetime = {
    'kind': 'premium',
    'source': 'purchase',
    'premium_source': 'lifetime',
  };

  Future<Entitlements> follow(
    FakeEntitlementsSource rows, {
    String user = 'peter',
  }) async {
    final session = TestSession(InHousehold(user, home, const [home]));
    addTearDown(session.close);
    final entitlements = Entitlements(rows, session, now: () => now);
    addTearDown(entitlements.close);
    await pumpEventQueue();
    return entitlements;
  }

  final cases = <(String, FakeEntitlementsSource, bool)>[
    (
      'their own bought Lifetime',
      FakeEntitlementsSource()..userRows['peter'] = [boughtLifetime],
      true,
    ),
    (
      'their own grant for good (thanks for the beta)',
      FakeEntitlementsSource()..userRows['peter'] = [lifetimeGrantRow],
      true,
    ),
    (
      'their own grant without end',
      FakeEntitlementsSource()..userRows['peter'] = [promotionalRow()],
      true,
    ),
    (
      "the household's bought Lifetime only",
      FakeEntitlementsSource()..rowsNow = [boughtLifetime],
      false,
    ),
    (
      "the household's tester grant only",
      FakeEntitlementsSource()..rowsNow = [lifetimeGrantRow],
      false,
    ),
    (
      'their own grant that ends (the beta)',
      FakeEntitlementsSource()..userRows['peter'] = [promotionalRow(from: now)],
      false,
    ),
    (
      'their own yearly plan',
      FakeEntitlementsSource()..userRows['peter'] = [yearlyRow(from: now)],
      false,
    ),
    (
      "another member's own Lifetime",
      FakeEntitlementsSource()..userRows['lea'] = [boughtLifetime],
      false,
    ),
  ];

  for (final (what, rows, holds) in cases) {
    test('$what: ${holds ? '' : 'no '}account Lifetime', () async {
      final entitlements = await follow(rows);
      expect(entitlements.state, isA<EntitlementsKnown>());
      expect(entitlements.accountLifetime, holds);
      expect(entitlements.accountLifetimeOrUnknown, holds);
    });
  }

  test("the household's Lifetime unlocks premium all the same", () async {
    final entitlements = await follow(
      FakeEntitlementsSource()..rowsNow = [boughtLifetime],
    );
    expect(entitlements.has(Entitlement.premium), isTrue);
    expect(entitlements.accountLifetime, isFalse);
  });

  test('not read yet (offline): no account Lifetime, but no refund prompt '
      'on a guess either', () async {
    final entitlements = await follow(
      FakeEntitlementsSource()
        ..offline = true
        ..userRows['peter'] = [boughtLifetime],
    );
    expect(entitlements.state, isA<EntitlementsUnknown>());
    expect(entitlements.accountLifetime, isFalse);
    expect(entitlements.accountLifetimeOrUnknown, isTrue);
  });

  test('a household grant next to their own bought Lifetime: theirs '
      'counts', () async {
    final entitlements = await follow(
      FakeEntitlementsSource()
        ..rowsNow = [lifetimeGrantRow]
        ..userRows['peter'] = [boughtLifetime],
    );
    expect(entitlements.accountLifetime, isTrue);
  });
}

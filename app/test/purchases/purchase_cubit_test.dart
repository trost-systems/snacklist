import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:family_groceries/purchases/entitlements.dart';
import 'package:family_groceries/purchases/purchase_cubit.dart';
import 'package:family_groceries/purchases/purchase_repository.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../household/harness.dart' show TestSession;
import 'fakes.dart';

const home = InHousehold('peter', Household(id: 'home', name: 'Zuhause'), [
  Household(id: 'home', name: 'Zuhause'),
]);

/// Another account on the same device, in the same household.
const leaHome = InHousehold('lea', Household(id: 'home', name: 'Zuhause'), [
  Household(id: 'home', name: 'Zuhause'),
]);

/// The cubit as the app has it, answers settled.
Future<TestPurchases> started({
  Session session = home,
  FakePurchaseRepository? store,
  FakeEntitlementsSource? rows,
}) async {
  final testSession = TestSession(session);
  addTearDown(testSession.close);
  final purchases = TestPurchases(
    session: testSession,
    store: store,
    source: rows,
  );
  addTearDown(purchases.close);
  expect(purchases.purchases.state.flow, isA<FlowIdle>());
  await pumpEventQueue();
  return purchases;
}

void main() {
  group('the store is asked only on a tap, only when locked (H-67)', () {
    test('nothing until Buy or Restore is tapped', () async {
      final p = await started(
        store: FakePurchaseRepository(bought: const Canceled()),
      );
      p.rows.change();
      await pumpEventQueue();
      expect(p.repository.calls, isEmpty);
      await p.purchases.buy(PremiumPlan.lifetime);
      expect(p.repository.calls, ['buy peter lifetime']);
      await p.purchases.restore();
      expect(p.repository.calls, ['buy peter lifetime', 'restore peter']);
    });

    test('never for an unlocked household', () async {
      final p = await started(rows: FakeEntitlementsSource(unlockedNow: true));
      await p.purchases.restore();
      await p.purchases.buy(PremiumPlan.lifetime);
      expect(p.repository.calls, isEmpty);
    });

    test('not while the unlock is unknown; once it is known locked', () async {
      final rows = FakeEntitlementsSource()..offline = true;
      final p = await started(rows: rows);
      await p.purchases.restore();
      await p.purchases.buy(PremiumPlan.lifetime);
      expect(p.repository.calls, isEmpty);
      rows
        ..offline = false
        ..change();
      await pumpEventQueue();
      expect(p.repository.calls, isEmpty, reason: 'knowing it asks nothing');
      await p.purchases.buy(PremiumPlan.lifetime);
      expect(p.repository.calls, ['buy peter lifetime']);
    });

    test('for the signed-in user, never a household id (job 185)', () async {
      final p = await started(
        store: FakePurchaseRepository(bought: const Canceled()),
      );
      await p.purchases.buy(PremiumPlan.lifetime);
      await (p.session as TestSession).join('ABCD2345');
      await pumpEventQueue();
      expect(p.repository.calls, ['buy peter lifetime']);
      await p.purchases.restore();
      expect(p.repository.calls, ['buy peter lifetime', 'restore peter']);
    });

    test('signing out calls no store: no logOut, nothing to buy', () async {
      final p = await started(
        store: FakePurchaseRepository(bought: const Canceled()),
      );
      await p.purchases.buy(PremiumPlan.lifetime);
      await (p.session as TestSession).signOut();
      await pumpEventQueue();
      await p.purchases.buy(PremiumPlan.lifetime);
      await p.purchases.restore();
      expect(p.repository.calls, ['buy peter lifetime']);
      expect(p.purchases.state.flow, isA<FlowIdle>());
    });

    test('a build without a store answers without asking', () async {
      final p = await started(
        store: FakePurchaseRepository(withoutStore: const PurchasesNotYet()),
      );
      await p.purchases.buy(PremiumPlan.lifetime);
      await p.purchases.restore();
      expect(p.repository.calls, isEmpty);
      expect(p.purchases.state.noSale, isA<PurchasesNotYet>());
    });
  });

  group('buying', () {
    test('bought: unlocking until Supabase has the unlock', () async {
      final p = await started();
      await p.purchases.buy(PremiumPlan.lifetime);
      expect(p.repository.buys, ['peter']);
      expect(p.purchases.state.flow, isA<FlowUnlocking>());
      p.unlock();
      await pumpEventQueue();
      expect(p.entitlements.has(Entitlement.premium), isTrue);
      expect(p.purchases.state.flow, isA<FlowIdle>());
    });

    test("bought: the unlock arrives as the user's own row", () async {
      final p = await started();
      await p.purchases.buy(PremiumPlan.yearly);
      expect(p.purchases.state.flow, isA<FlowUnlocking>());
      p.rows
        ..userRows['peter'] = [yearlyRow(from: DateTime.now())]
        ..change();
      await pumpEventQueue();
      expect(p.purchases.state.flow, isA<FlowIdle>());
      expect(p.entitlements.has(Entitlement.premium), isTrue);
    });

    test("a household's plan is not the purchase arriving: still unlocking, "
        'no second Buy (job 419)', () async {
      final rows = FakeEntitlementsSource()..rowsNow = [promotionalRow()];
      final p = await started(rows: rows);
      await p.purchases.buy(PremiumPlan.yearly);
      expect(p.repository.calls, ['buy peter yearly']);
      expect(p.purchases.state.flow, isA<FlowUnlocking>());
      await p.purchases.buy(PremiumPlan.yearly);
      expect(p.repository.calls, ['buy peter yearly'], reason: 'no second tap');
      rows
        ..userRows['peter'] = [yearlyRow(from: DateTime.now())]
        ..change();
      await pumpEventQueue();
      expect(p.purchases.state.flow, isA<FlowIdle>());
    });

    test('no unlock in time: idle again', () {
      fakeAsync((async) {
        late TestPurchases p;
        unawaited(started().then((value) => p = value));
        async.elapse(Duration.zero);
        unawaited(p.purchases.buy(PremiumPlan.lifetime));
        async.flushMicrotasks();
        expect(p.purchases.state.flow, isA<FlowUnlocking>());
        async.elapse(unlockWait);
        expect(p.purchases.state.flow, isA<FlowUnlockDelayed>());
        expect(p.purchases.state.busy, isTrue, reason: 'no second purchase');
      });
    });

    test('a second tap while buying starts nothing', () async {
      final store = FakePurchaseRepository()..hold = true;
      final p = await started(store: store);
      unawaited(p.purchases.buy(PremiumPlan.lifetime));
      await pumpEventQueue();
      expect(p.purchases.state.flow, isA<FlowBuying>());
      await p.purchases.buy(PremiumPlan.lifetime);
      await p.purchases.restore();
      expect(store.buys, hasLength(1));
      expect(store.restores, isEmpty);
    });

    test('Ask to Buy waits, and Buy may ask again', () async {
      final p = await started(
        store: FakePurchaseRepository(bought: const Pending()),
      );
      await p.purchases.buy(PremiumPlan.lifetime);
      expect(p.purchases.state.flow, isA<FlowAwaitingApproval>());
      await p.purchases.buy(PremiumPlan.lifetime);
      expect(p.repository.buys, hasLength(2));
      p.unlock();
      await pumpEventQueue();
      expect(p.entitlements.has(Entitlement.premium), isTrue);
    });

    test(
      'Ask to Buy approved: the wait note goes once premium arrives',
      () async {
        final p = await started(
          store: FakePurchaseRepository(bought: const Pending()),
        );
        await p.purchases.buy(PremiumPlan.yearly);
        expect(p.purchases.state.flow, isA<FlowAwaitingApproval>());
        p.rows
          ..userRows['peter'] = [yearlyRow(from: DateTime.now())]
          ..change();
        await pumpEventQueue();
        expect(p.purchases.state.flow, isA<FlowIdle>());
      },
    );

    test(
      'Ask to Buy for Lifetime next to a yearly plan waits for Lifetime',
      () async {
        final rows = FakeEntitlementsSource()
          ..userRows['peter'] = [yearlyRow(from: DateTime.now())];
        final p = await started(
          rows: rows,
          store: FakePurchaseRepository(bought: const Pending()),
        );
        await p.purchases.buy(PremiumPlan.lifetime);
        rows.change();
        await pumpEventQueue();
        expect(p.purchases.state.flow, isA<FlowAwaitingApproval>());
        p.unlock();
        rows
          ..userRows['peter'] = []
          ..change();
        await pumpEventQueue();
        expect(p.purchases.state.flow, isA<FlowIdle>());
      },
    );

    test('a purchase that ends after a household switch waits for its '
        'unlock there: no second purchase', () async {
      final store = FakePurchaseRepository()..hold = true;
      final p = await started(store: store);
      unawaited(p.purchases.buy(PremiumPlan.lifetime));
      await pumpEventQueue();
      await (p.session as TestSession).join('ABCD2345');
      await pumpEventQueue();
      store.held.single.complete(const Bought());
      await pumpEventQueue();
      expect(p.purchases.state.flow, isA<FlowUnlocking>());
      store.hold = false;
      await p.purchases.buy(PremiumPlan.lifetime);
      expect(store.buys, hasLength(1), reason: 'Buy stays off');
      p.rows
        ..userRows['peter'] = [
          {
            'kind': 'premium',
            'source': 'purchase',
            'premium_source': 'lifetime',
          },
        ]
        ..change();
      await pumpEventQueue();
      expect(p.purchases.state.flow, isA<FlowIdle>());
    });

    test('a pending unlock survives leaving the last household and '
        'founding a new one: no second purchase', () async {
      final store = FakePurchaseRepository()..hold = true;
      final p = await started(store: store);
      final session = p.session as TestSession;
      unawaited(p.purchases.buy(PremiumPlan.lifetime));
      await pumpEventQueue();
      await session.leave('home');
      await pumpEventQueue();
      expect(session.state, isA<NeedsHousehold>());
      store.held.single.complete(const Bought());
      await pumpEventQueue();
      expect(p.purchases.state.flow, isA<FlowUnlocking>());
      session.emit(
        const InHousehold('peter', Household(id: 'flat', name: 'WG'), [
          Household(id: 'flat', name: 'WG'),
        ]),
      );
      await pumpEventQueue();
      expect(p.purchases.state.busy, isTrue);
      store.hold = false;
      await p.purchases.buy(PremiumPlan.lifetime);
      expect(store.buys, hasLength(1), reason: 'Buy stays off');
    });

    test('a delayed unlock keeps Buy off after leaving the last household', () {
      fakeAsync((async) {
        late TestPurchases p;
        unawaited(started().then((value) => p = value));
        async.elapse(Duration.zero);
        unawaited(p.purchases.buy(PremiumPlan.lifetime));
        async
          ..flushMicrotasks()
          ..elapse(unlockWait);
        expect(p.purchases.state.flow, isA<FlowUnlockDelayed>());
        final session = p.session as TestSession
          ..emit(const NeedsHousehold('peter'));
        async.flushMicrotasks();
        session.emit(home);
        async.flushMicrotasks();
        expect(p.purchases.state.flow, isA<FlowUnlockDelayed>());
        unawaited(p.purchases.buy(PremiumPlan.lifetime));
        async.flushMicrotasks();
        expect(p.repository.buys, hasLength(1), reason: 'Buy stays off');
      });
    });

    test("a pending unlock stays Peter's: Lea signed in next starts idle", () {
      fakeAsync((async) {
        late TestPurchases p;
        unawaited(started().then((value) => p = value));
        async.elapse(Duration.zero);
        unawaited(p.purchases.buy(PremiumPlan.lifetime));
        async
          ..flushMicrotasks()
          ..elapse(unlockWait);
        expect(p.purchases.state.flow, isA<FlowUnlockDelayed>());
        (p.session as TestSession).emit(leaHome);
        async.flushMicrotasks();
        expect(p.purchases.state.flow, isA<FlowIdle>());
        expect(p.purchases.state.busy, isFalse);
        unawaited(p.purchases.buy(PremiumPlan.lifetime));
        async.flushMicrotasks();
        expect(p.repository.calls.last, 'buy lea lifetime');
      });
    });

    test(
      'a restore that ends after an account switch leaves Lea idle',
      () async {
        final store = FakePurchaseRepository()..hold = true;
        final p = await started(store: store);
        unawaited(p.purchases.restore());
        await pumpEventQueue();
        (p.session as TestSession).emit(leaHome);
        await pumpEventQueue();
        store.heldRestores.single.complete(const Restored());
        await pumpEventQueue();
        expect(p.purchases.state.flow, isA<FlowIdle>());
      },
    );

    const outcomes = <BuyOutcome, Object>{
      Canceled(): FlowCanceled,
      ProductMissing(): FlowNotAvailable,
      BelongsElsewhere(): FlowUsedElsewhere,
      StoreFailed('storeProblemError'): FailureKind.store,
      StoreOffline(): FailureKind.offline,
    };
    for (final MapEntry(key: outcome, value: shown) in outcomes.entries) {
      test('$outcome shows $shown', () async {
        final p = await started(store: FakePurchaseRepository(bought: outcome));
        await p.purchases.buy(PremiumPlan.lifetime);
        expect(switch (p.purchases.state.flow) {
          FlowFailed(:final kind) => kind,
          final other => other.runtimeType,
        }, shown);
        await p.purchases.buy(PremiumPlan.lifetime);
        expect(p.repository.buys, hasLength(2), reason: 'buy again lifetime');
      });
    }

    test('the store failure keeps its code', () async {
      final p = await started(
        store: FakePurchaseRepository(bought: const StoreFailed('E42')),
      );
      await p.purchases.buy(PremiumPlan.lifetime);
      expect(
        p.purchases.state.flow,
        isA<FlowFailed>().having((f) => f.code, 'code', 'E42'),
      );
    });
  });

  group('restoring', () {
    test('restored: unlocking until Supabase has it', () async {
      final p = await started(
        store: FakePurchaseRepository(restored: const Restored()),
      );
      await p.purchases.restore();
      expect(p.repository.restores, ['peter']);
      expect(p.purchases.state.flow, isA<FlowUnlocking>());
      p.unlock();
      await pumpEventQueue();
      expect(p.purchases.state.flow, isA<FlowIdle>());
    });

    const outcomes = <RestoreOutcome, Object>{
      NothingToRestore(): FlowNothingRestored,
      BelongsElsewhere(): FlowUsedElsewhere,
      StoreFailed('configurationError'): FailureKind.store,
      StoreOffline(): FailureKind.offline,
    };
    for (final MapEntry(key: outcome, value: shown) in outcomes.entries) {
      test('$outcome shows $shown', () async {
        final p = await started(
          store: FakePurchaseRepository(restored: outcome),
        );
        await p.purchases.restore();
        expect(switch (p.purchases.state.flow) {
          FlowFailed(:final kind) => kind,
          final other => other.runtimeType,
        }, shown);
      });
    }

    test('allowed while a purchase awaits approval', () async {
      final p = await started(
        store: FakePurchaseRepository(bought: const Pending()),
      );
      await p.purchases.buy(PremiumPlan.lifetime);
      await p.purchases.restore();
      expect(p.repository.restores, hasLength(1));
    });
  });

  group('opening the Premium page again', () {
    const ended = <BuyOutcome>[
      Canceled(),
      ProductMissing(),
      StoreFailed('E42'),
      StoreOffline(),
      BelongsElsewhere(),
    ];
    for (final outcome in ended) {
      test('clears the note after ${outcome.runtimeType}', () async {
        final p = await started(store: FakePurchaseRepository(bought: outcome));
        await p.purchases.buy(PremiumPlan.lifetime);
        expect(p.purchases.state.flow, isNot(isA<FlowIdle>()));
        p.purchases.pageOpened();
        expect(p.purchases.state.flow, isA<FlowIdle>());
      });
    }

    test('clears "nothing restored"', () async {
      final p = await started();
      await p.purchases.restore();
      expect(p.purchases.state.flow, isA<FlowNothingRestored>());
      p.purchases.pageOpened();
      expect(p.purchases.state.flow, isA<FlowIdle>());
    });

    test('keeps what is under way', () {
      fakeAsync((async) {
        late TestPurchases p;
        unawaited(
          started(store: FakePurchaseRepository(bought: const Pending()))
              .then((value) => p = value),
        );
        async.elapse(Duration.zero);
        unawaited(p.purchases.buy(PremiumPlan.lifetime));
        async.flushMicrotasks();
        p.purchases.pageOpened();
        expect(p.purchases.state.flow, isA<FlowAwaitingApproval>());
        p.repository.bought = const Bought();
        unawaited(p.purchases.buy(PremiumPlan.lifetime));
        async.flushMicrotasks();
        p.purchases.pageOpened();
        expect(p.purchases.state.flow, isA<FlowUnlocking>());
        async.elapse(unlockWait);
        p.purchases.pageOpened();
        expect(p.purchases.state.flow, isA<FlowUnlockDelayed>());
        expect(p.purchases.state.busy, isTrue);
      });
    });
  });

  test('another account clears what the last one showed', () async {
    final p = await started(
      store: FakePurchaseRepository(bought: const BelongsElsewhere()),
    );
    await p.purchases.buy(PremiumPlan.lifetime);
    expect(p.purchases.state.flow, isA<FlowUsedElsewhere>());
    (p.session as TestSession).emit(leaHome);
    await pumpEventQueue();
    expect(p.purchases.state.flow, isA<FlowIdle>());
  });

  group('the yearly plan and Lifetime (job 49)', () {
    test('yearly: bought for the user, unlocked by its row', () async {
      final p = await started();
      await p.purchases.buy(PremiumPlan.yearly);
      expect(p.repository.calls, ['buy peter yearly']);
      expect(p.purchases.state.flow, isA<FlowUnlocking>());
      p.rows
        ..userRows['peter'] = [yearlyRow(from: DateTime.now())]
        ..change();
      await pumpEventQueue();
      expect(p.purchases.state.flow, isA<FlowIdle>());
    });

    test('never a second yearly plan; Lifetime is the one upgrade', () async {
      final rows = FakeEntitlementsSource()
        ..userRows['peter'] = [yearlyRow(from: DateTime.now())];
      final p = await started(rows: rows);
      await p.purchases.buy(PremiumPlan.yearly);
      expect(p.repository.calls, isEmpty);
      await p.purchases.buy(PremiumPlan.lifetime);
      expect(p.repository.calls, ['buy peter lifetime']);
      // The running yearly plan is no Lifetime: it waits for that row.
      expect(p.purchases.state.flow, isA<FlowUnlocking>());
      rows
        ..userRows['peter'] = [
          yearlyRow(from: DateTime.now()),
          {
            'kind': 'premium',
            'source': 'purchase',
            'premium_source': 'lifetime',
          },
        ]
        ..change();
      await pumpEventQueue();
      expect(p.purchases.state.flow, isA<FlowIdle>());
    });

    test('a lapsed yearly plan: both plans may be bought again', () async {
      final rows = FakeEntitlementsSource()
        ..rowsNow = [yearlyRow(from: DateTime.now(), days: -1)];
      final p = await started(
        rows: rows,
        store: FakePurchaseRepository(bought: const Canceled()),
      );
      await p.purchases.buy(PremiumPlan.yearly);
      await p.purchases.buy(PremiumPlan.lifetime);
      expect(p.repository.calls, ['buy peter yearly', 'buy peter lifetime']);
    });

    test(
      "a yearly plan another household's store account pays: elsewhere",
      () async {
        final p = await started(
          store: FakePurchaseRepository(bought: const BelongsElsewhere()),
        );
        await p.purchases.buy(PremiumPlan.yearly);
        expect(p.purchases.state.flow, isA<FlowUsedElsewhere>());
      },
    );
  });
}

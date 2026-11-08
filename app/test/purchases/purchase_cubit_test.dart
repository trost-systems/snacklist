import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:family_groceries/purchases/entitlements.dart';
import 'package:family_groceries/purchases/purchase_api.dart';
import 'package:family_groceries/purchases/purchase_cubit.dart';
import 'package:family_groceries/purchases/purchase_repository.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../household/harness.dart' show TestSession;
import 'fakes.dart';

const home = InHousehold('peter', Household(id: 'home', name: 'Zuhause'), [
  Household(id: 'home', name: 'Zuhause'),
]);

/// The cubit as the app has it, answers settled.
Future<TestPurchases> started({
  Session session = home,
  FakePurchaseRepository? store,
  FakeClaimApi? api,
  FakeEntitlementsSource? rows,
}) async {
  final testSession = TestSession(session);
  addTearDown(testSession.close);
  final purchases = TestPurchases(
    session: testSession,
    store: store,
    api: api,
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
      expect(p.repository.calls, ['buy home lifetime']);
      await p.purchases.restore();
      expect(p.repository.calls, ['buy home lifetime', 'restore home']);
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
      expect(p.repository.calls, ['buy home lifetime']);
    });

    test('for the household of the moment of the tap', () async {
      final p = await started();
      await (p.session as TestSession).join('ABCD2345');
      await pumpEventQueue();
      expect(p.repository.calls, isEmpty);
      await p.purchases.buy(PremiumPlan.lifetime);
      expect(p.repository.calls, ['buy other lifetime']);
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
      expect(p.repository.calls, ['buy home lifetime']);
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
      expect(p.repository.buys, ['home']);
      expect(p.purchases.state.flow, isA<FlowUnlocking>());
      p.unlock();
      await pumpEventQueue();
      expect(p.entitlements.has(Entitlement.premium), isTrue);
      expect(p.purchases.state.flow, isA<FlowIdle>());
    });

    test(
      'the claim is sent once, with the household, store and transaction',
      () async {
        final api = FakeClaimApi();
        final p = await started(
          api: api,
          store: FakePurchaseRepository(
            bought: const Bought(
              StoreTransactionRef(AppStore.google, 'GPA.3312-5'),
            ),
          ),
        );
        await p.purchases.buy(PremiumPlan.lifetime);
        await pumpEventQueue();
        expect(api.calls, hasLength(1));
        expect(api.calls.single.store, AppStore.google);
        expect(api.calls.single.id, 'GPA.3312-5');
        expect(api.households, ['home'], reason: 'the household bought for');
      },
    );

    test('a purchase without a transaction id claims nothing', () async {
      final api = FakeClaimApi();
      final p = await started(
        api: api,
        store: FakePurchaseRepository(bought: const Bought(null)),
      );
      await p.purchases.buy(PremiumPlan.lifetime);
      await pumpEventQueue();
      expect(api.calls, isEmpty);
      expect(p.purchases.state.flow, isA<FlowUnlocking>());
    });

    test('a claim without answer is tried again, then given up', () {
      fakeAsync((async) {
        final api = FakeClaimApi(
          answers: const [ClaimFailed(ClaimProblem.offline, 'offline')],
        );
        late TestPurchases p;
        unawaited(started(api: api).then((value) => p = value));
        async.elapse(Duration.zero);
        unawaited(p.purchases.buy(PremiumPlan.lifetime));
        async.flushMicrotasks();
        expect(api.calls, hasLength(1));
        async.elapse(const Duration(seconds: 2));
        expect(api.calls, hasLength(2));
        async.elapse(const Duration(minutes: 5));
        expect(api.calls, hasLength(1 + claimBackoff.length));
      });
    });

    test('a refused claim is not sent again', () {
      fakeAsync((async) {
        final api = FakeClaimApi(
          answers: const [ClaimFailed(ClaimProblem.refused, 'no_household')],
        );
        late TestPurchases p;
        unawaited(started(api: api).then((value) => p = value));
        async.elapse(Duration.zero);
        unawaited(p.purchases.buy(PremiumPlan.lifetime));
        async.elapse(const Duration(minutes: 5));
        expect(api.calls, hasLength(1));
      });
    });

    test('a claim retried until the server answers, once more', () {
      fakeAsync((async) {
        final api = FakeClaimApi(
          answers: const [
            ClaimFailed(ClaimProblem.server, '502'),
            Claimed(ClaimStatus.waiting),
          ],
        );
        late TestPurchases p;
        unawaited(started(api: api).then((value) => p = value));
        async.elapse(Duration.zero);
        unawaited(p.purchases.buy(PremiumPlan.lifetime));
        async.elapse(const Duration(minutes: 5));
        expect(api.calls, hasLength(2));
      });
    });

    test(
      "the server says the transaction is elsewhere's: used elsewhere",
      () async {
        final p = await started(
          api: FakeClaimApi(answers: const [Claimed(ClaimStatus.elsewhere)]),
        );
        await p.purchases.buy(PremiumPlan.lifetime);
        await pumpEventQueue();
        expect(p.purchases.state.flow, isA<FlowUsedElsewhere>());
      },
    );

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
          ..rowsNow = [yearlyRow(from: DateTime.now())]
          ..change();
        await pumpEventQueue();
        expect(p.purchases.state.flow, isA<FlowIdle>());
      },
    );

    test(
      'Ask to Buy for Lifetime next to a yearly plan waits for Lifetime',
      () async {
        final rows = FakeEntitlementsSource()
          ..rowsNow = [yearlyRow(from: DateTime.now())];
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
          ..rowsNow = null
          ..change();
        await pumpEventQueue();
        expect(p.purchases.state.flow, isA<FlowIdle>());
      },
    );

    test('the claim names the household bought for, after a switch', () async {
      final store = FakePurchaseRepository()..hold = true;
      final p = await started(store: store);
      unawaited(p.purchases.buy(PremiumPlan.lifetime));
      await pumpEventQueue();
      await (p.session as TestSession).join('ABCD2345');
      await pumpEventQueue();
      store.held.single.complete(
        const Bought(StoreTransactionRef(AppStore.apple, 'tx-9')),
      );
      await pumpEventQueue();
      expect(p.server.households, ['home']);
      expect(
        p.purchases.state.flow,
        isA<FlowIdle>(),
        reason: "the new household's page shows nothing of it",
      );
      expect(p.purchases.state.busy, isFalse);
      store.hold = false;
      await p.purchases.buy(PremiumPlan.lifetime);
      expect(store.calls.last, 'buy other lifetime', reason: 'Buy available');
    });

    test(
      'a restore that ends after a switch leaves the new household idle',
      () async {
        final store = FakePurchaseRepository()..hold = true;
        final p = await started(store: store);
        unawaited(p.purchases.restore());
        await pumpEventQueue();
        await (p.session as TestSession).join('ABCD2345');
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
      test('$outcome shows $shown, claims nothing', () async {
        final api = FakeClaimApi();
        final p = await started(
          api: api,
          store: FakePurchaseRepository(bought: outcome),
        );
        await p.purchases.buy(PremiumPlan.lifetime);
        expect(switch (p.purchases.state.flow) {
          FlowFailed(:final kind) => kind,
          final other => other.runtimeType,
        }, shown);
        expect(api.calls, isEmpty);
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
      expect(p.repository.restores, ['home']);
      expect(p.purchases.state.flow, isA<FlowUnlocking>());
      p.unlock();
      await pumpEventQueue();
      expect(p.purchases.state.flow, isA<FlowIdle>());
      expect(p.server.calls, isEmpty, reason: 'a restore claims nothing');
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
        p.repository.bought = const Bought(null);
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

  test('another household clears what the last one showed', () async {
    final p = await started(
      store: FakePurchaseRepository(bought: const BelongsElsewhere()),
    );
    await p.purchases.buy(PremiumPlan.lifetime);
    expect(p.purchases.state.flow, isA<FlowUsedElsewhere>());
    await (p.session as TestSession).join('ABCD2345');
    await pumpEventQueue();
    expect(p.purchases.state.flow, isA<FlowIdle>());
  });

  group('the yearly plan and Lifetime (job 49)', () {
    test('yearly: bought for the household, unlocked by its row', () async {
      final p = await started();
      await p.purchases.buy(PremiumPlan.yearly);
      expect(p.repository.calls, ['buy home yearly']);
      expect(p.purchases.state.flow, isA<FlowUnlocking>());
      p.rows
        ..rowsNow = [yearlyRow(from: DateTime.now())]
        ..change();
      await pumpEventQueue();
      expect(p.purchases.state.flow, isA<FlowIdle>());
    });

    test('never a second yearly plan; Lifetime is the one upgrade', () async {
      final rows = FakeEntitlementsSource()
        ..rowsNow = [yearlyRow(from: DateTime.now())];
      final p = await started(rows: rows);
      await p.purchases.buy(PremiumPlan.yearly);
      expect(p.repository.calls, isEmpty);
      await p.purchases.buy(PremiumPlan.lifetime);
      expect(p.repository.calls, ['buy home lifetime']);
      // The running yearly plan is no Lifetime: it waits for that row.
      expect(p.purchases.state.flow, isA<FlowUnlocking>());
      rows
        ..rowsNow = [
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
      expect(p.repository.calls, ['buy home yearly', 'buy home lifetime']);
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

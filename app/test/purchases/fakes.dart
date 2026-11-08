import 'dart:async';

import 'package:family_groceries/purchases/entitlements.dart';
import 'package:family_groceries/purchases/fake_store.dart';
import 'package:family_groceries/purchases/premium_server.dart';
import 'package:family_groceries/purchases/purchase_api.dart';
import 'package:family_groceries/purchases/purchase_cubit.dart';
import 'package:family_groceries/purchases/purchase_repository.dart';
import 'package:family_groceries/purchases/store_prices.dart';
import 'package:family_groceries/session/session_cubit.dart';

/// A store that answers what the test set, or holds a purchase in [held]
/// and a restore in [heldRestores] while [hold] is set. [calls] lists every
/// call, in order: the page and app start must make none (H-67).
class FakePurchaseRepository({
  @override final NoSale? withoutStore,
  var BuyOutcome bought = const Bought(
    StoreTransactionRef(AppStore.apple, 'tx-1'),
  ),
  var RestoreOutcome restored = const NothingToRestore(),
}) implements PurchaseRepository {
  final buys = <String>[];
  final restores = <String>[];
  var hold = false;
  final held = <Completer<BuyOutcome>>[];
  final heldRestores = <Completer<RestoreOutcome>>[];

  /// `buy <household> <plan>` and `restore <household>`, in order.
  List<String> get calls => _calls;
  final _calls = <String>[];

  /// The plan of each buy, in order.
  final plans = <PremiumPlan>[];

  @override
  Future<BuyOutcome> buy(String householdId, PremiumPlan plan) async {
    buys.add(householdId);
    plans.add(plan);
    _calls.add('buy $householdId ${plan.name}');
    if (!hold) {
      return bought;
    }
    final answer = Completer<BuyOutcome>();
    held.add(answer);
    return await answer.future;
  }

  @override
  Future<RestoreOutcome> restore(String householdId) async {
    restores.add(householdId);
    _calls.add('restore $householdId');
    if (!hold) {
      return restored;
    }
    final answer = Completer<RestoreOutcome>();
    heldRestores.add(answer);
    return await answer.future;
  }
}

/// A purchases function whose claim answers [answers] in turn, the last one
/// for good.
class FakeClaimApi({
  var List<ClaimResult> answers = const [Claimed(ClaimStatus.recorded)],
}) implements ClaimApi {
  final calls = <StoreTransactionRef>[];

  /// The household each claim named.
  final households = <String>[];

  @override
  Future<ClaimResult> claim(
    String householdId,
    StoreTransactionRef transaction,
  ) async {
    calls.add(transaction);
    households.add(householdId);
    return answers[(calls.length - 1).clamp(0, answers.length - 1)];
  }
}

class FakeEntitlementsSource({var bool unlockedNow = false})
    implements EntitlementsSource {
  /// The household's rows as the server has them; null: one Lifetime
  /// purchase's row while [unlockedNow].
  List<Map<String, dynamic>>? rowsNow;

  /// Reads fail (offline) while set.
  var offline = false;

  /// Reads wait in [heldReads] while set, for the test to answer in any
  /// order.
  var holdReads = false;
  final heldReads = <Completer<HouseholdUnlocks>>[];
  final watching = <String>{};
  void Function()? _onChange;

  /// A realtime event or a reconnect.
  void change() => _onChange?.call();

  @override
  Future<HouseholdUnlocks> unlocks(String householdId) async {
    if (offline) {
      throw Exception('offline');
    }
    if (holdReads) {
      final answer = Completer<HouseholdUnlocks>();
      heldReads.add(answer);
      return await answer.future;
    }
    return unlocksOf(
      rowsNow ??
          [
            if (unlockedNow)
              {
                'kind': 'premium',
                'source': 'purchase',
                'premium_source': 'lifetime',
              },
          ],
    );
  }

  @override
  Future<void> Function() watch(String householdId, void Function() onChange) {
    watching.add(householdId);
    _onChange = onChange;
    return () async {
      watching.remove(householdId);
      _onChange = null;
    };
  }
}

/// A yearly plan's row as members read it, ending `days` after `from`.
/// A RevenueCat promotional grant's row: ending [days] after [from], or never
/// without [from].
Map<String, dynamic> promotionalRow({DateTime? from, int days = 30}) => {
  'kind': 'premium',
  'source': 'promotional',
  'premium_source': 'promotional',
  'expires_at': from?.add(Duration(days: days)).toUtc().toIso8601String(),
  'auto_renew': null,
};

Map<String, dynamic> yearlyRow({
  required DateTime from,
  int days = 200,
  bool renews = true,
}) => {
  'kind': 'premium',
  'source': 'purchase',
  'premium_source': 'yearly',
  'expires_at': from.add(Duration(days: days)).toUtc().toIso8601String(),
  'auto_renew': renews,
};

/// The server's switch and the caller's own yearly plan; [calls] lists the
/// `offer` and `mine` reads.
class FakePremiumServer({
  var bool offer = true,
  var MyYearlyPlan mine = const MyYearlyPlan(),

  /// The `integration_lock` switch (job 50).
  var bool lock = false,
}) implements PremiumServer {
  final calls = <String>[];

  /// my_yearly_plan fails (offline) while set.
  var mineFails = false;

  /// premium_offer cannot be read (offline) while set.
  var offerFails = false;

  @override
  Future<OfferSwitch> offerSwitch() async {
    calls.add('offer');
    if (offerFails) {
      return OfferSwitch.unreadable;
    }
    return offer ? OfferSwitch.on : OfferSwitch.off;
  }

  @override
  Future<bool> integrationLock() async {
    calls.add('lock');
    return lock;
  }

  @override
  Future<MyYearlyPlan> myYearlyPlan({String? household}) async {
    calls.add(household == null ? 'mine' : 'mine $household');
    if (mineFails) {
      throw Exception('offline');
    }
    return mine;
  }
}

/// Entitlements and the purchase cubit over fakes, for screens and
/// harnesses; closed by [close]. [sdk] instead of the fake store: the real
/// RevenueCat repository over a mocked platform channel.
class TestPurchases({
  required final SessionCubit session,
  final FakePurchaseRepository? store,
  final PurchaseRepository? sdk,
  final FakeClaimApi? api,
  final FakeEntitlementsSource? source,
  final FakePremiumServer? premiumServer,
  final FakeStorePrices? prices,
  final DateTime Function()? clock,
}) {
  late final FakePurchaseRepository repository =
      store ?? FakePurchaseRepository();
  late final FakeClaimApi server = api ?? FakeClaimApi();
  late final FakeEntitlementsSource rows = source ?? FakeEntitlementsSource();
  late final entitlements = Entitlements(
    rows,
    session,
    now: clock ?? DateTime.now,
  );
  late final FakePremiumServer premium = premiumServer ?? FakePremiumServer();
  late final FakeStorePrices storePrices =
      prices ?? FakeStorePrices(fakeStorePrices);
  late final purchases = PurchaseCubit(
    sdk ?? repository,
    server,
    entitlements,
    session,
  );

  /// The partner's purchase, or the webhook after this one: the row
  /// arrives over Realtime.
  void unlock() {
    rows
      ..unlockedNow = true
      ..change();
  }

  Future<void> close() async {
    await purchases.close();
    await entitlements.close();
  }
}

/// The fake store's ledger, in memory.
class MemoryLedger() implements FakeLedgerStore {
  String? contents;

  @override
  Future<String?> read() async => contents;

  @override
  Future<void> write(String contents) async => this.contents = contents;
}

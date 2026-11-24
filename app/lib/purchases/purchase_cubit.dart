import 'dart:async';

import 'package:family_groceries/purchases/entitlements.dart';
import 'package:family_groceries/purchases/purchase_repository.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_bloc/flutter_bloc.dart';

/// Where a purchase or restore stands.
sealed class const PurchaseFlow();

final class const FlowIdle() extends PurchaseFlow;

/// The store's sheet is open.
final class const FlowBuying() extends PurchaseFlow;

/// The store is looking for earlier purchases.
final class const FlowRestoring() extends PurchaseFlow;

/// Ask to Buy or a Play payment that completes later.
final class const FlowAwaitingApproval() extends PurchaseFlow;

/// Bought or restored: waiting for the unlock from Supabase, which arrives
/// once RevenueCat's webhook has recorded it.
final class const FlowUnlocking() extends PurchaseFlow;

/// The unlock takes longer than [unlockWait] (RevenueCat's webhook is late
/// or retrying). Buy stays off for the rest of this app run, until the
/// unlock arrives: the purchase is done and another one would be paid twice.
final class const FlowUnlockDelayed() extends PurchaseFlow;

final class const FlowCanceled() extends PurchaseFlow;

/// The store has no such product (yet, or not in this storefront).
final class const FlowNotAvailable() extends PurchaseFlow;

final class const FlowFailed(final FailureKind kind, final String code)
    extends PurchaseFlow;

/// The store purchase belongs to another account or an earlier household,
/// for good (H-56). [plan] is the plan whose Buy it was; null for a restore.
final class const FlowUsedElsewhere([final PremiumPlan? plan])
    extends PurchaseFlow;

/// A restore found no purchase.
final class const FlowNothingRestored() extends PurchaseFlow;

enum FailureKind() {
  /// The store or RevenueCat refused or failed.
  store,

  /// The store or RevenueCat could not be reached.
  offline,
}

@immutable
class const PurchaseState({
  /// Why this build sells nothing; null where Buy and Restore ask a store.
  final NoSale? noSale,
  final PurchaseFlow flow = const FlowIdle(),
}) {
  /// A purchase or restore is under way: Buy does nothing. Awaiting approval
  /// is not: iOS never reports a declined Ask to Buy, so Buy asks again.
  bool get busy => switch (flow) {
    FlowBuying() ||
    FlowRestoring() ||
    FlowUnlocking() ||
    FlowUnlockDelayed() => true,
    _ => false,
  };
}

/// How long "unlocking" waits for Supabase's unlock after a purchase.
const unlockWait = Duration(seconds: 60);

/// Snacklist Premium's purchase (yearly or Lifetime) and restore. It talks to
/// RevenueCat only when the user taps Buy or Restore ([buy], [restore]) for
/// a plan the server's rows allow ([Entitlements.canOffer]): building it, app
/// start and opening the Premium page reach not RevenueCat (Legal Review
/// H-67, K.9.9). The purchase is the signed-in user's: RevenueCat knows them
/// by their user id ([RevenueCatUserId]), and its webhook records them as
/// the buyer. The unlock it shows comes only from Supabase ([Entitlements]).
class PurchaseCubit(
  final PurchaseRepository _store,
  final Entitlements _entitlements,
  final SessionCubit _session,
) extends Cubit<PurchaseState> {
  this : super(PurchaseState(noSale: _store.withoutStore)) {
    _user = _userOf(_session.state);
    _sessions = _session.stream.listen(_onSession);
    _unlocks = _entitlements.stream.listen((_) => _onEntitlements());
  }

  late final StreamSubscription<Session> _sessions;
  late final StreamSubscription<EntitlementsState> _unlocks;
  RevenueCatUserId? _user;
  Timer? _unlockTimeout;

  /// The plan bought or restored last: the unlock it waits for.
  PremiumPlan _plan = PremiumPlan.yearly;

  /// The plan of the Buy under way; null for a restore.
  PremiumPlan? _buying;

  static RevenueCatUserId? _userOf(Session session) => switch (session) {
    InHousehold(:final userId) ||
    NeedsHousehold(:final userId) => RevenueCatUserId(userId),
    SessionLoading() || SignedOut() => null,
  };

  /// The user's own rows show what [_plan] unlocks: any premium for the
  /// yearly plan, Lifetime itself for Lifetime (bought next to a running
  /// yearly plan). A household's plan or grant is not the purchase arriving.
  bool get _arrived => switch (_entitlements.ownPremium) {
    ActivePremium(:final source) =>
      _plan == PremiumPlan.yearly || source.lasting,
    _ => false,
  };

  /// A flow follows the user, not the household: their purchase unlocks in
  /// every household they are in (job 185), so switching households, or
  /// leaving the last one and starting another, keeps a pending unlock and
  /// with it Buy off, or they would pay twice. Another account (or none)
  /// starts afresh.
  void _onSession(Session session) {
    final user = _userOf(session);
    if (user == _user) {
      return;
    }
    _user = user;
    _unlockTimeout?.cancel();
    emit(PurchaseState(noSale: _store.withoutStore));
  }

  void _onEntitlements() {
    if ((state.flow is FlowUnlocking ||
            state.flow is FlowUnlockDelayed ||
            state.flow is FlowAwaitingApproval) &&
        _arrived) {
      _unlockTimeout?.cancel();
      _emit(flow: const FlowIdle());
    }
  }

  /// Buy [plan] for the signed-in user at the time of the tap, only while it
  /// may be offered in the household the session shows.
  Future<void> buy(PremiumPlan plan) async {
    final user = _user;
    if (state.busy ||
        state.noSale != null ||
        !_entitlements.canOffer(Entitlement.premium, plan) ||
        user == null) {
      return;
    }
    _plan = plan;
    _buying = plan;
    _emit(flow: const FlowBuying());
    final outcome = await _store.buy(user, plan);
    if (isClosed || user != _user) {
      // Another account: its page shows nothing of it.
      return;
    }
    switch (outcome) {
      case Bought():
        _unlocking();
      case Canceled():
        _emit(flow: const FlowCanceled());
      case Pending():
        _emit(flow: const FlowAwaitingApproval());
      case ProductMissing():
        _emit(flow: const FlowNotAvailable());
      case StoreProblem():
        _failed(outcome);
    }
  }

  /// Restore, while any plan may be offered: it finds the signed-in user's
  /// own purchases of either plan, on any device.
  Future<void> restore() async {
    final user = _user;
    if (state.busy ||
        state.noSale != null ||
        !PremiumPlan.values.any(
          (plan) => _entitlements.canOffer(Entitlement.premium, plan),
        ) ||
        user == null) {
      return;
    }
    _plan = PremiumPlan.yearly;
    _buying = null;
    _emit(flow: const FlowRestoring());
    final outcome = await _store.restore(user);
    if (isClosed || user != _user) {
      return;
    }
    switch (outcome) {
      case Restored():
        _unlocking();
      case NothingToRestore():
        _emit(flow: const FlowNothingRestored());
      case StoreProblem():
        _failed(outcome);
    }
  }

  /// The Premium page opens: a note on how the last try ended is old news.
  /// What is still under way stays.
  void pageOpened() {
    switch (state.flow) {
      case FlowCanceled() ||
          FlowNotAvailable() ||
          FlowFailed() ||
          FlowUsedElsewhere() ||
          FlowNothingRestored():
        _emit(flow: const FlowIdle());
      case FlowIdle() ||
          FlowBuying() ||
          FlowRestoring() ||
          FlowAwaitingApproval() ||
          FlowUnlocking() ||
          FlowUnlockDelayed():
        break;
    }
  }

  void _failed(StoreProblem problem) => _emit(
    flow: switch (problem) {
      BelongsElsewhere() => FlowUsedElsewhere(_buying),
      StoreFailed(:final code) => FlowFailed(FailureKind.store, code),
      StoreOffline() => const FlowFailed(FailureKind.offline, 'offline'),
    },
  );

  void _unlocking() {
    if (_arrived) {
      _emit(flow: const FlowIdle());
      return;
    }
    _emit(flow: const FlowUnlocking());
    _unlockTimeout?.cancel();
    _unlockTimeout = Timer(unlockWait, () {
      if (state.flow is FlowUnlocking) {
        _emit(flow: const FlowUnlockDelayed());
      }
    });
  }

  void _emit({required PurchaseFlow flow}) {
    if (!isClosed) {
      emit(PurchaseState(noSale: state.noSale, flow: flow));
    }
  }

  @override
  Future<void> close() async {
    _unlockTimeout?.cancel();
    await _sessions.cancel();
    await _unlocks.cancel();
    await super.close();
  }
}

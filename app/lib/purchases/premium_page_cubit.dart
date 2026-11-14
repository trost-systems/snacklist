import 'dart:async';

import 'package:family_groceries/analytics/analytics.dart';
import 'package:family_groceries/purchases/entitlements.dart';
import 'package:family_groceries/purchases/premium_server.dart';
import 'package:family_groceries/purchases/purchase_repository.dart';
import 'package:family_groceries/purchases/store_prices.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_bloc/flutter_bloc.dart';

/// Whether the page may offer anything for sale, and at which prices.
sealed class const Offer();

/// The switch and the prices are being read.
final class const OfferLoading() extends Offer;

/// Nothing is sold here: this build sells nothing, or the server switch
/// `premium_offer` is off.
final class const OfferClosed() extends Offer;

/// The store did not answer: no purchase without a price (A2-5). Or the
/// server switch could not be read (offline).
final class const OfferUnavailable() extends Offer;

/// The store's own prices, exactly as it formats them for the store
/// account's country. A plan missing here is not sold in this storefront.
final class const OfferPrices(final Map<PremiumPlan, StorePrice> prices)
    extends Offer;

/// Where the Premium page was opened from: More's row, the integration
/// settings' card (job 50, `?from=integrations`), the history's locked
/// row (job 199, `?from=history`) or a trip summary's Premium card (job
/// 234, `?from=trip`).
enum PaywallEntry() {
  more,
  integrations,
  history,
  trip;

  static PaywallEntry parse(String? from) =>
      values.where((v) => v.name == from).firstOrNull ?? more;
}

@immutable
class const PremiumPage({
  final Offer offer = const OfferLoading(),

  /// Null while unknown: the subscriber-only notices stay hidden.
  final MyYearlyPlan? mine,

  /// The server switch `premium_offer` as read when the page opened, in
  /// every build: whether Snacklist Premium has started. Null until read.
  final OfferSwitch? launch,

  /// The plan the Buy button buys while it is offered. Yearly when the page
  /// opens, visibly picked (Legal Review Q1, DECISIONS "Job 87").
  final PremiumPlan picked = PremiumPlan.yearly,
}) {
  PremiumPage copyWith({
    Offer? offer,
    MyYearlyPlan? mine,
    OfferSwitch? launch,
    PremiumPlan? picked,
  }) => PremiumPage(
    offer: offer ?? this.offer,
    mine: mine ?? this.mine,
    launch: launch ?? this.launch,
    picked: picked ?? this.picked,
  );
}

/// The Premium page's reads, made when it opens: the server switch, then
/// (only when it is on) one store price query, and the caller's own yearly
/// plan. None of them configures RevenueCat (H-67); the store price query is
/// StoreKit or Play Billing directly (A2-5).
class PremiumPageCubit(
  final PremiumServer _server,
  final StorePriceReader _prices,
  final Entitlements _entitlements, {

  /// Whether this build sells at all (a store and `REVENUECAT_PURCHASES`).
  required final bool sells,

  /// paywall_viewed goes here once the page offers a plan with its price.
  final Analytics? analytics,
  final PaywallEntry entry = PaywallEntry.more,
}) extends Cubit<PremiumPage> {
  this : super(const PremiumPage()) {
    _rows = _entitlements.stream.listen((_) {
      unawaited(_readMine());
      _viewed();
    });
    unawaited(_open());
  }

  late final StreamSubscription<EntitlementsState> _rows;

  Future<void> _open() async {
    unawaited(_readMine());
    // Every build reads the switch, also one that sells nothing: a server
    // read, never RevenueCat (H-67).
    final launch = await _server.offerSwitch();
    if (isClosed) {
      return;
    }
    emit(state.copyWith(launch: launch));
    if (!sells) {
      _emitOffer(const OfferClosed());
      return;
    }
    switch (launch) {
      case OfferSwitch.off:
        _emitOffer(const OfferClosed());
        return;
      case OfferSwitch.unreadable:
        _emitOffer(const OfferUnavailable());
        return;
      case OfferSwitch.on:
        break;
    }
    final offer = switch (await _prices.read()) {
      PricesRead(:final prices) when prices.isNotEmpty => OfferPrices(prices),
      PricesRead() => const OfferUnavailable(),
      PricesUnavailable() => const OfferUnavailable(),
    };
    _emitOffer(offer);
    _viewed();
  }

  var _viewedSent = false;

  /// Job 50 (Spec #4 AC7): paywall_viewed once per visit, as soon as the
  /// page shows a plan with its price to a household that can buy it
  /// (prices and the household's rows arrive in either order). Never a
  /// price or a product.
  void _viewed() {
    if (_viewedSent || isClosed || state.offer is! OfferPrices) {
      return;
    }
    if (PremiumPlan.values.any(
      (plan) => _entitlements.canOffer(Entitlement.premium, plan),
    )) {
      _viewedSent = true;
      analytics?.track('paywall_viewed', {'entry_point': entry.name});
    }
  }

  Future<void> _readMine() async {
    try {
      final mine = await _server.myYearlyPlan(
        household: _entitlements.householdId,
      );
      if (!isClosed) {
        emit(state.copyWith(mine: mine));
      }
    } on Object {
      // Offline: the subscriber's notices wait for the next change.
    }
  }

  void _emitOffer(Offer offer) {
    if (!isClosed) {
      emit(state.copyWith(offer: offer));
    }
  }

  /// The user picked [plan]'s tile.
  void pick(PremiumPlan plan) => emit(state.copyWith(picked: plan));

  @override
  Future<void> close() async {
    await _rows.cancel();
    await super.close();
  }
}

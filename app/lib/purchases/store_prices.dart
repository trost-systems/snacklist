import 'dart:async';

import 'package:family_groceries/core/environment.dart';
import 'package:family_groceries/purchases/purchase_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A plan's price as the store shows it to this user: its own formatting and
/// storefront currency, never one the app derives from the locale (Legal
/// Review A2-5).
@immutable
class const StorePrice(final String formatted, final String currencyCode) {
  bool get euro => currencyCode == 'EUR';

  @override
  bool operator ==(Object other) =>
      other is StorePrice &&
      other.formatted == formatted &&
      other.currencyCode == currencyCode;

  @override
  int get hashCode => Object.hash(formatted, currencyCode);

  @override
  String toString() => 'StorePrice($formatted, $currencyCode)';
}

/// What the store said about the plans' prices.
sealed class const StorePrices();

/// The store answered. A plan missing from [prices] is not sold in this
/// storefront: the page leaves it out without a word.
final class const PricesRead(final Map<PremiumPlan, StorePrice> prices)
    extends StorePrices;

/// The store gave no answer: offline, unreachable, too slow or failing.
final class const PricesUnavailable() extends StorePrices;

/// The store's own price list, asked only once the Premium page is open.
/// Nothing here purchases: purchases go through RevenueCat alone.
abstract interface class StorePriceReader() {
  Future<StorePrices> read();

  /// Opens the store's own subscription sheet where the platform has one
  /// (StoreKit). False when it did not, and the caller opens the store's
  /// web page instead.
  Future<bool> manageSubscriptions();
}

/// StoreKit 2 (AppDelegate.swift) or Play Billing (MainActivity.kt) behind
/// a channel that only reads product details. Not the in_app_purchase
/// plugin: it observes StoreKit's transaction queue from app start next to
/// RevenueCat's and keeps a Play purchases listener.
class const ChannelStorePrices() implements StorePriceReader {
  static const channel = MethodChannel('familygroceries/store_prices');

  /// A store that does not answer in this time counts as unreachable, so the
  /// page stops waiting.
  static const timeout = Duration(seconds: 10);

  @override
  Future<StorePrices> read() async {
    try {
      final raw = await channel
          .invokeMethod<Object?>('prices', {
            PremiumPlan.yearly.name: yearlyProductId,
            PremiumPlan.lifetime.name: lifetimeProductId,
            'basePlan': playBasePlanId,
          })
          .timeout(timeout);
      return parseStorePrices(raw);
    } on PlatformException {
      return const PricesUnavailable();
    } on MissingPluginException {
      return const PricesUnavailable();
    } on TimeoutException {
      return const PricesUnavailable();
    }
  }

  @override
  Future<bool> manageSubscriptions() async {
    try {
      return await channel.invokeMethod<bool>('manageSubscriptions') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

/// The native side's answer, `{'yearly': {'price', 'currency'} | null,
/// 'lifetime': ...}`. A null plan is not sold here; anything else that is
/// not that shape is no answer at all, so the page never shows half a
/// price.
@visibleForTesting
StorePrices parseStorePrices(Object? raw) {
  if (raw is! Map) {
    return const PricesUnavailable();
  }
  final prices = <PremiumPlan, StorePrice>{};
  for (final plan in PremiumPlan.values) {
    switch (raw[plan.name]) {
      case null:
        continue;
      case {'price': final String price, 'currency': final String currency}
          when price.isNotEmpty && currency.isNotEmpty:
        prices[plan] = StorePrice(price, currency);
      case _:
        return const PricesUnavailable();
    }
  }
  return PricesRead(prices);
}

/// Builds without a store (web, desktop): no price, nothing to manage.
class const NoStorePrices() implements StorePriceReader {
  @override
  Future<StorePrices> read() async => const PricesUnavailable();

  @override
  Future<bool> manageSubscriptions() async => false;
}

/// The store's answer for tests and fg (Linux desktop with `FAKE_STORE`).
class FakeStorePrices(final StorePrices answer, {final bool manages = false})
    implements StorePriceReader {
  /// How often the store was asked.
  var reads = 0;

  @override
  Future<StorePrices> read() async {
    reads++;
    return answer;
  }

  /// How often the store's subscription management was opened.
  var manageCalls = 0;

  @override
  Future<bool> manageSubscriptions() async {
    manageCalls++;
    return manages;
  }
}

/// What fg's fake store charges: the approved euro prices
/// (scripts/iap/product.ts).
const fakeStorePrices = PricesRead({
  PremiumPlan.yearly: StorePrice('24,99 €', 'EUR'),
  PremiumPlan.lifetime: StorePrice('149,99 €', 'EUR'),
});

/// The web app never reads a store, fake or not. [fakeStore] (the
/// `FAKE_STORE` define) counts outside release builds only, on every
/// platform, as storeChoice's does: a fake purchase next to a real store's
/// price would show what nobody charges. Otherwise iOS and Android ask
/// their store.
StorePriceReader chooseStorePriceReader({
  required bool web,
  required TargetPlatform platform,
  required String fakeStore,
  required bool release,
}) {
  if (web) {
    return const NoStorePrices();
  }
  if (fakeStore.isNotEmpty && !release) {
    return FakeStorePrices(fakeStorePrices);
  }
  return switch (platform) {
    TargetPlatform.iOS || TargetPlatform.android => const ChannelStorePrices(),
    _ => const NoStorePrices(),
  };
}

/// This build's price reader. Building it asks no store.
StorePriceReader storePriceReader() => chooseStorePriceReader(
  web: kIsWeb,
  platform: defaultTargetPlatform,
  fakeStore: Environment.fakeStore,
  release: kReleaseMode,
);

import 'package:family_groceries/core/guides.dart';
import 'package:family_groceries/purchases/entitlements.dart';
import 'package:family_groceries/purchases/purchase_repository.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, immutable;
import 'package:supabase_flutter/supabase_flutter.dart';

/// What only the subscriber learns about the household's yearly plan
/// (`my_yearly_plan()`, H-87): other members read its end date and nothing
/// about who pays or whether a payment failed.
@immutable
class const MyYearlyPlan({
  /// The caller took out an active yearly plan for their household.
  final bool subscriber = false,

  /// That plan renews.
  final bool renewing = false,

  /// The store could not charge its renewal; premium runs until [until].
  final bool billingIssue = false,
  final DateTime? until,

  /// The caller pays a renewing yearly plan for another household (archived,
  /// left or deleted): deleting the account doesn't cancel it.
  final bool elsewhere = false,

  /// The caller's household has a renewing yearly plan, whoever pays it.
  final bool householdBilled = false,
}) {
  factory parse(Object? json) => switch (json) {
    final Map<String, dynamic> m => MyYearlyPlan(
      subscriber: m['subscriber'] == true,
      renewing: m['renewing'] == true,
      billingIssue: m['billing_issue'] == true,
      until: DateTime.tryParse('${m['until']}'),
      elsewhere: m['elsewhere'] == true,
      householdBilled: m['household_billed'] == true,
    ),
    _ => const MyYearlyPlan(),
  };
}

/// The server switch `premium_offer` as the app could read it.
enum OfferSwitch() {
  on,
  off,

  /// Offline or the call failed: the server decides, the app does not know.
  unreadable,
}

/// The signed-in account's own Snacklist Premium: its `user_entitlements`
/// rows, which RevenueCat's events write, by `user_premium()`'s rule. A
/// household's premium is not the account's.
enum MyPremium() {
  none,
  active,

  /// Active, and a yearly plan of the account still renews: the store keeps
  /// billing it.
  billed,
}

/// The server reads the Premium page, the billing warnings and the account
/// deletion make; none touches a store or RevenueCat.
abstract interface class PremiumServer() {
  /// The server switch `premium_offer` (seeded off): whether Snacklist
  /// Premium may be offered at all.
  Future<OfferSwitch> offerSwitch();

  /// Throws when it cannot be read.
  /// For [household] (job 169b); null asks about the default household.
  Future<MyYearlyPlan> myYearlyPlan({String? household});

  /// The server switch `integration_lock` (job 50, seeded off): Siri and MCP
  /// need Snacklist Premium; Alexa stays free. False when it cannot be read.
  Future<bool> integrationLock();

  /// Throws when it cannot be read.
  Future<MyPremium> myPremium();
}

class const SupabasePremiumServer(final SupabaseClient _client)
    implements PremiumServer {
  @override
  Future<OfferSwitch> offerSwitch() async {
    try {
      return await _client.rpc<Object?>('premium_offer') == true
          ? OfferSwitch.on
          : OfferSwitch.off;
    } on Object {
      return OfferSwitch.unreadable;
    }
  }

  @override
  Future<MyYearlyPlan> myYearlyPlan({String? household}) async =>
      MyYearlyPlan.parse(
        await _client.rpc<Object?>(
          'my_yearly_plan',
          params: household == null ? null : {'p_household': household},
        ),
      );

  @override
  Future<bool> integrationLock() async {
    try {
      return await _client.rpc<Object?>('integration_lock') == true;
    } on Object {
      return false;
    }
  }

  @override
  Future<MyPremium> myPremium() async {
    final user = _client.auth.currentUser ?? (throw StateError('signed out'));
    final rows = await _client.rest
        .from('user_entitlements')
        .select('kind, source, premium_source, expires_at, auto_renew')
        .eq('user_id', user.id);
    final unlocks = unlocksOf(rows, own: true);
    final now = DateTime.now();
    return switch (unlocks.premiumAt(now)) {
      NoPremium() => MyPremium.none,
      ActivePremium() when unlocks.yearlyBilledAt(now) => MyPremium.billed,
      ActivePremium() => MyPremium.active,
    };
  }
}

/// Apple's subscription settings, for when StoreKit's own sheet is not
/// available (the web, an error).
final appleSubscriptionsUrl = Uri.parse(
  'https://apps.apple.com/account/subscriptions',
);

/// The app's Play package (applicationId on main).
const playPackage = 'com.snacklist.app';

/// Google Play's page for one subscription: `sku` is the subscription's
/// product id, `package` the app's (Play Billing docs, "Deep link to the
/// subscription management page", read 2026-11-01).
final googleSubscriptionUrl = Uri.https(
  'play.google.com',
  '/store/account/subscriptions',
  {'sku': 'com.snacklist.app.yearly', 'package': playPackage},
);

/// Google Play's list of all subscriptions.
final googleSubscriptionsUrl = Uri.parse(
  'https://play.google.com/store/account/subscriptions',
);

/// Apple's standard EULA, linked as the terms of use on iOS until Snacklist
/// has its own (H-93: needs a lawyer; NEEDS_LEAD Job 49).
final appleEulaUrl = Uri.parse(
  'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/',
);

/// The terms of use for [platform]: on Android and the web a placeholder,
/// the support page, until Legal Review supplies Snacklist's terms
/// (NEEDS_LEAD Job 49 lists it).
Uri termsUrl(TargetPlatform platform, String language) =>
    platform == TargetPlatform.iOS ? appleEulaUrl : supportUrl(language);

/// Whether Snacklist Premium is offered to this user: More lists it and the
/// history's locked row opens it (job 199). Before the launch nobody sees it
/// (job 64): it needs the server's `premium_offer` and, in the iPhone and
/// Android apps, `REVENUECAT_PURCHASES` ([PurchasesNotYet]). A household
/// that [held] it always sees it.
bool premiumListed({
  required bool held,
  required OfferSwitch? offer,
  required NoSale? noSale,
}) => held || (offer == OfferSwitch.on && noSale is! PurchasesNotYet);

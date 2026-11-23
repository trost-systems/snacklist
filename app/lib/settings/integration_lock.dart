import 'package:family_groceries/purchases/entitlements.dart';
import 'package:family_groceries/purchases/premium_server.dart';
import 'package:family_groceries/purchases/purchase_repository.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_bloc/flutter_bloc.dart';

/// The server's side of the integration lock (job 50), read when the
/// integration settings open.
@immutable
class const ServerLock({
  /// `integration_lock` is on: MCP and the API refuse a user without
  /// Snacklist Premium of their own (neither the household's nor another
  /// member's plan counts, job 419). Siri (job 184) and Alexa (Legal Review
  /// N-27) stay free.
  required final bool enforced,

  /// `premium_offer` is on, or could not be read: the card links to the
  /// Premium page, which says what it found. Only a switch read as off
  /// makes it "coming soon".
  required final bool offerOpen,
});

/// The server's switches, app-wide; null until first read. Zugänge shows the
/// lock exactly while the server enforces it (job 328 review 0).
class IntegrationLockCubit(final PremiumServer _server)
    extends Cubit<ServerLock?> {
  this : super(null);

  /// Reads both switches again: one call while the lock is off. A lock that
  /// cannot be read counts as off (the server decides); an offer that
  /// cannot be read as open.
  Future<void> refresh() async {
    final enforced = await _server.integrationLock();
    final offerOpen =
        enforced && await _server.offerSwitch() != OfferSwitch.off;
    if (!isClosed) {
      emit(ServerLock(enforced: enforced, offerOpen: offerOpen));
    }
  }
}

/// What the integration settings say about Snacklist Premium.
sealed class const IntegrationAccess();

/// Nothing: the lock is off, the user has premium, or either is not known
/// yet (loading, offline).
final class const IntegrationsOpen() extends IntegrationAccess;

/// The user is known to have no premium while the server enforces the lock:
/// their connections are paused, and [offer] says how they unlock.
final class const IntegrationsLocked(final LockOffer offer)
    extends IntegrationAccess;

enum LockOffer() {
  /// A button to the Snacklist Premium page.
  buy,

  /// This build or the server does not sell it yet.
  soon,

  /// The web app: bought in the iPhone or Android app.
  inTheApps,
}

/// The one decision: locked only when the server enforces the lock and
/// [Entitlements.canOffer] says the user has no premium of their own (it is
/// false while unknown, so an unlocked user never sees Buy; a household's
/// plan does not count, as on the server).
IntegrationAccess integrationAccess({
  required ServerLock? server,
  required Entitlements entitlements,
  required NoSale? noSale,
}) {
  if (server == null ||
      !server.enforced ||
      !entitlements.canOffer(Entitlement.premium, PremiumPlan.yearly)) {
    return const IntegrationsOpen();
  }
  return IntegrationsLocked(switch (noSale) {
    PurchasesUnsupported() => LockOffer.inTheApps,
    PurchasesNotYet() => LockOffer.soon,
    null => server.offerOpen ? LockOffer.buy : LockOffer.soon,
  });
}

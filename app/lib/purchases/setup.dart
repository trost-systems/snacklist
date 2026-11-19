import 'package:family_groceries/core/environment.dart';
import 'package:family_groceries/purchases/fake_store.dart';
import 'package:family_groceries/purchases/purchase_repository.dart';
import 'package:family_groceries/purchases/revenuecat_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Which store this build sells through.
sealed class const StoreChoice();

/// Sells nothing; the Lifetime page shows [answer] (the web app's note, or
/// "coming soon").
final class const NoStore(final NoSale answer) extends StoreChoice;

final class const RevenueCatStore(final String apiKey) extends StoreChoice;

final class const FakeStoreChoice(final FakeStoreMode mode) extends StoreChoice;

/// The web app never sells, fake store or not. [fakeStore] (the
/// `FAKE_STORE` define) counts outside release builds only, and regardless
/// of [revenueCat]. On iOS and Android the purchase needs [revenueCat] (the
/// `REVENUECAT_PURCHASES` define, Legal Review's release gate) and the
/// platform's SDK key.
StoreChoice storeChoice({
  required bool web,
  required TargetPlatform platform,
  required String fakeStore,
  required bool release,
  required bool revenueCat,
  required String iosKey,
  required String androidKey,
}) {
  if (web) {
    return const NoStore(PurchasesUnsupported());
  }
  if (fakeStore.isNotEmpty && !release) {
    return FakeStoreChoice(FakeStoreMode.values.byName(fakeStore));
  }
  final key = switch (platform) {
    TargetPlatform.iOS => iosKey,
    TargetPlatform.android => androidKey,
    _ => null,
  };
  return switch (key) {
    null => const NoStore(PurchasesUnsupported()),
    final key when revenueCat && key.isNotEmpty => RevenueCatStore(key),
    _ => const NoStore(PurchasesNotYet()),
  };
}

/// The store of this build. Building it starts nothing: RevenueCat is
/// configured on the first tap on Buy or Restore (Legal Review H-67), after
/// the server noted that the account goes to RevenueCat (job 185).
PurchaseRepository purchaseRepository(SupabaseClient client) =>
    switch (storeChoice(
      web: kIsWeb,
      platform: defaultTargetPlatform,
      fakeStore: Environment.fakeStore,
      release: kReleaseMode,
      revenueCat: Environment.revenueCatPurchases,
      iosKey: Environment.revenueCatIosKey,
      androidKey: Environment.revenueCatAndroidKey,
    )) {
      NoStore(:final answer) => NoStoreRepository(answer),
      RevenueCatStore(:final apiKey) => RevenueCatRepository(
        apiKey,
        () => client.rpc<void>('note_revenuecat_customer'),
      ),
      FakeStoreChoice(:final mode) => FakeStore(
        mode,
        send: localTestEvent(client),
        ledger: fileLedger(),
      ),
    };

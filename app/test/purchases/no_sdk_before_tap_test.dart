import 'package:family_groceries/purchases/entitlements.dart';
import 'package:family_groceries/purchases/purchase_cubit.dart';
import 'package:family_groceries/purchases/purchase_repository.dart';
import 'package:family_groceries/purchases/revenuecat_repository.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../more/more_harness.dart';
import 'fake_revenuecat.dart';
import 'fakes.dart';

/// Legal Review H-67: RevenueCat's SDK (configure, logIn, products, customer
/// info) starts only on a tap on Buy or Restore. The real repository over
/// the SDK's mocked platform channel, which records every call.
void main() {
  setUpAll(fakeSupabase);

  Finder key(String k) => find.byKey(ValueKey(k));

  late FakeRevenueCat native;
  setUp(() => native = FakeRevenueCat());

  Future<More> start(WidgetTester tester, {String location = morePath}) {
    mockRevenueCat(native);
    return pumpMore(
      tester,
      location: location,
      size: const Size(390, 2600),
      sdk: RevenueCatRepository('appl_public', native.noteCustomer),
    );
  }

  testWidgets('app start and the More tab make no SDK call', (tester) async {
    final more = await start(tester);
    await tester.pumpAndSettle();
    expect(key('more-screen'), findsOneWidget);
    expect(
      more.purchases.entitlements.canOffer(
        Entitlement.premium,
        PremiumPlan.lifetime,
      ),
      isTrue,
    );
    expect(native.calls, isEmpty);
    expect(native.notes, isEmpty);
  });

  testWidgets('opening, rebuilding, leaving and coming back to the Lifetime '
      'page make no SDK call', (tester) async {
    final more = await start(tester, location: premiumPath);
    await tester.pumpAndSettle();
    expect(key('premium-buy-yearly'), findsOneWidget);
    expect(key('premium-card-lifetime'), findsOneWidget);
    expect(more.purchases.storePrices.reads, 1, reason: 'one store query');
    more.purchases.rows.change();
    await tester.pumpAndSettle();
    expect(more.purchases.storePrices.reads, 1, reason: 'not per rebuild');
    more.router.go(morePath);
    await tester.pumpAndSettle();
    more.router.go(premiumPath);
    await tester.pumpAndSettle();
    expect(key('premium-buy-yearly'), findsOneWidget);
    expect(native.calls, isEmpty);
    expect(native.notes, isEmpty, reason: 'nor a note of the account');
    expect(more.purchases.storePrices.reads, 2, reason: 'once per opening');
  });

  testWidgets('Buy yearly: the same order, the subscription by its id', (
    tester,
  ) async {
    await start(tester, location: premiumPath);
    await tester.pumpAndSettle();
    expect(native.calls, isEmpty);
    await tester.tap(key('premium-buy-yearly'));
    await tester.pumpAndSettle();
    expect(native.notes, [0], reason: 'the account is noted first');
    expect(native.methods, [
      'setupPurchases',
      'getProductInfo',
      'purchaseProduct',
    ]);
    expect(
      native.calls[1].arguments,
      containsPair('productIdentifiers', [yearlyProductId]),
    );
    await tester.pump(unlockWait);
  });

  testWidgets('Buy configures with the user, then loads the product, '
      'then opens the purchase', (tester) async {
    await start(tester, location: premiumPath);
    await tester.pumpAndSettle();
    await tester.tap(key('premium-card-lifetime'));
    await tester.pump();
    expect(native.calls, isEmpty, reason: 'picking a plan buys nothing');
    await tester.tap(key('premium-buy-lifetime'));
    await tester.pumpAndSettle();
    expect(native.methods, [
      'setupPurchases',
      'getProductInfo',
      'purchaseProduct',
    ]);
    expect(native.calls.first.arguments, containsPair('appUserId', 'peter'));
    // "Unlocking" waits for an unlock that never comes here.
    await tester.pump(unlockWait);
  });

  testWidgets('Restore configures with the user, then restores', (
    tester,
  ) async {
    await start(tester, location: premiumPath);
    await tester.pumpAndSettle();
    await tester.ensureVisible(key('lifetime-restore'));
    await tester.tap(key('lifetime-restore'));
    await tester.pumpAndSettle();
    expect(native.notes, [0], reason: 'the account is noted first');
    expect(native.methods, ['setupPurchases', 'restorePurchases']);
    expect(native.calls.first.arguments, containsPair('appUserId', 'peter'));
  });

  testWidgets('an unlocked household never reaches the SDK', (tester) async {
    mockRevenueCat(native);
    await pumpMore(
      tester,
      location: premiumPath,
      sdk: RevenueCatRepository('appl_public', native.noteCustomer),
      entitlements: FakeEntitlementsSource(unlockedNow: true),
    );
    await tester.pumpAndSettle();
    expect(key('premium-buy-lifetime'), findsNothing);
    expect(key('premium-buy-yearly'), findsNothing);
    expect(native.calls, isEmpty);
  });
}

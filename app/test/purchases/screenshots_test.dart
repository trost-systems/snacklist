// Job 25, 43, 49, 87: PR screenshots of the Snacklist Premium page in its
// native states (the web build only shows the web state). Renders More's real
// page with the fake store and the app's theme, in Roboto and the Material
// icons from the Flutter SDK. Skipped unless SCREENSHOT_DIR is set:
//   SCREENSHOT_DIR=/tmp/shots flutter test --update-goldens \
//     test/purchases/screenshots_test.dart
import 'dart:io';

import 'package:family_groceries/core/language.dart';
import 'package:family_groceries/purchases/premium_server.dart';
import 'package:family_groceries/purchases/purchase_cubit.dart';
import 'package:family_groceries/purchases/purchase_repository.dart';
import 'package:family_groceries/purchases/store_prices.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../more/more_harness.dart';
import 'fakes.dart';

final _dir = Platform.environment['SCREENSHOT_DIR'];

Future<void> _loadFonts() async {
  // flutter_tester lives in <sdk>/bin/cache/artifacts/engine/<platform>/.
  final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
  final fonts = Directory('${artifacts.path}/material_fonts');
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      final bytes = File('${fonts.path}/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  await family('Roboto', [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]);
  await family('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

typedef Scene = ({
  String name,
  String location,
  FakePurchaseRepository Function() store,
  List<Map<String, dynamic>> Function(DateTime now) rows,
  FakePremiumServer Function() premium,
  FakeStorePrices Function() prices,
  Future<void> Function(WidgetTester, More)? act,
});

Future<void> _buyLifetime(WidgetTester tester, More more) async {
  await tester.tap(find.byKey(const ValueKey('premium-buy-lifetime')));
  await tester.pumpAndSettle();
}

Future<void> _pickLifetime(WidgetTester tester, More more) async {
  await tester.tap(find.byKey(const ValueKey('premium-card-lifetime')));
  await tester.pumpAndSettle();
}

Future<void> _buyYearly(WidgetTester tester, More more) async {
  await tester.tap(find.byKey(const ValueKey('premium-buy-yearly')));
  await tester.pump();
}

const _lifetimeRow = {
  'kind': 'premium',
  'source': 'purchase',
  'premium_source': 'lifetime',
};

List<Map<String, dynamic>> _none(DateTime _) => const [];
FakePremiumServer _server() => FakePremiumServer();
FakeStorePrices _euro() => FakeStorePrices(fakeStorePrices);

Scene _scene(
  String name, {
  String location = premiumPath,
  FakePurchaseRepository Function() store = FakePurchaseRepository.new,
  List<Map<String, dynamic>> Function(DateTime now) rows = _none,
  FakePremiumServer Function() premium = _server,
  FakeStorePrices Function() prices = _euro,
  Future<void> Function(WidgetTester, More)? act,
}) => (
  name: name,
  location: location,
  store: store,
  rows: rows,
  premium: premium,
  prices: prices,
  act: act,
);

final List<Scene> _scenes = [
  _scene('offer'),
  _scene('offer-lifetime-picked', act: _pickLifetime),
  _scene(
    'offer-usd',
    prices: () => FakeStorePrices(
      const PricesRead({
        PremiumPlan.yearly: StorePrice(r'$9.99', 'USD'),
        PremiumPlan.lifetime: StorePrice(r'$29.99', 'USD'),
      }),
    ),
  ),
  _scene(
    'yearly-only-storefront',
    prices: () => FakeStorePrices(
      const PricesRead({PremiumPlan.yearly: StorePrice(r'R$ 29,90', 'BRL')}),
    ),
  ),
  _scene('unlocking', act: _buyYearly),
  _scene('yearly-renews', rows: (now) => [yearlyRow(from: now)]),
  _scene('yearly-ends', rows: (now) => [yearlyRow(from: now, renews: false)]),
  _scene(
    'lifetime-warning',
    rows: (now) => [yearlyRow(from: now)],
    act: _buyLifetime,
  ),
  _scene(
    'lifetime-warning-subscriber',
    rows: (now) => [yearlyRow(from: now)],
    premium: () => FakePremiumServer(
      mine: const MyYearlyPlan(subscriber: true, renewing: true),
    ),
    act: _buyLifetime,
  ),
  _scene(
    'lifetime-while-yearly',
    rows: (now) => [yearlyRow(from: now), _lifetimeRow],
  ),
  _scene(
    'billing-issue',
    rows: (now) => [yearlyRow(from: now, days: 12)],
    premium: () => FakePremiumServer(
      mine: MyYearlyPlan(
        subscriber: true,
        renewing: true,
        billingIssue: true,
        until: DateTime.now().add(const Duration(days: 12)),
      ),
    ),
  ),
  _scene('lifetime', rows: (_) => [_lifetimeRow]),
  _scene('granted', rows: (_) => [promotionalRow()]),
  _scene(
    'granted-beta',
    rows: (_) => [promotionalRow()],
    premium: () => FakePremiumServer(offer: false),
  ),
  _scene(
    'prices-unavailable',
    prices: () => FakeStorePrices(const PricesUnavailable()),
  ),
  _scene('switch-off', premium: () => FakePremiumServer(offer: false)),
  _scene(
    'not-yet',
    store: () => FakePurchaseRepository(withoutStore: const PurchasesNotYet()),
  ),
  _scene(
    'used-elsewhere',
    store: () => FakePurchaseRepository(bought: const BelongsElsewhere()),
    act: _buyYearly,
  ),
  _scene('more', location: morePath),
];

void main() {
  setUpAll(() async {
    await fakeSupabase();
    if (_dir != null) {
      await _loadFonts();
      WidgetsApp.debugAllowBannerOverride = false;
    }
  });

  for (final scene in _scenes) {
    for (final (lang, language) in [
      ('de', AppLanguage.byCode('de')),
      ('en', AppLanguage.byCode('en')),
    ]) {
      for (final size in const [Size(390, 1500), Size(1366, 1200)]) {
        final name = 'job49-app-${scene.name}-$lang-${size.width.toInt()}';
        testWidgets(name, skip: _dir == null, (tester) async {
          final more = await pumpMore(
            tester,
            location: scene.location,
            size: size,
            language: language,
            store: scene.store(),
            entitlements: FakeEntitlementsSource()
              ..rowsNow = scene.rows(DateTime.now()),
            premium: scene.premium(),
            prices: scene.prices(),
          );
          await tester.pumpAndSettle();
          await scene.act?.call(tester, more);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(Uri.file('$_dir/$name.png')),
          );
          // "Unlocking" waits for an unlock that never comes here.
          await tester.pump(unlockWait);
        });
      }
    }
  }
}

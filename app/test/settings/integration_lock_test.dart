import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/list/stores_screen.dart';
import 'package:family_groceries/purchases/entitlements.dart';
import 'package:family_groceries/purchases/purchase_repository.dart';
import 'package:family_groceries/purchases/revenuecat_repository.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../analytics/fakes.dart';
import '../more/more_harness.dart';
import '../purchases/fake_revenuecat.dart';
import '../purchases/fakes.dart';

/// Job 50: the integration settings with the integration lock. The card and
/// its Buy button show only while the flag premium-gate-integrations is on
/// (job 328), the server enforces the lock and the household is known to
/// have no Snacklist Premium (Spec #4 AC3); existing connections stay listed
/// as paused; a purchase by any member hides it all within one sync (AC4).
void main() {
  setUpAll(fakeSupabase);
  setUp(() {
    serverGrants.clear();
    serverTokens
      ..clear()
      ..add({
        'id': 't1',
        'name': 'Kurzbefehl',
        'kind': 'pat',
        'token_hint': '1234',
        'created_at': '2026-10-02T10:00:00Z',
        'last_used_at': null,
      });
  });

  Finder key(String k) => find.byKey(ValueKey(k));

  Future<More> access(
    WidgetTester tester, {
    bool flagOn = true,
    bool lock = true,
    bool offer = true,
    bool offerReadable = true,
    FakeEntitlementsSource? rows,
    NoSale? noSale,
    String language = 'de',
  }) => pumpMore(
    tester,
    location: accessPath,
    size: const Size(390, 1600),
    flags: {if (flagOn) premiumGateIntegrationsFlag},
    premium: FakePremiumServer(lock: lock, offer: offer)
      ..offerFails = !offerReadable,
    entitlements: rows,
    store: FakePurchaseRepository(withoutStore: noSale),
    device: [Locale(language)],
  );

  testWidgets('locked: an AI assistant is paused, Amazon Alexa never', (
    tester,
  ) async {
    serverTokens.clear();
    serverGrants.addAll([
      for (final (id, name) in [('c1', 'Claude'), ('c2', 'Amazon Alexa')])
        {
          'client': {'id': id, 'name': name},
          'scopes': ['openid'],
          'granted_at': '2026-10-21T10:00:00Z',
        },
    ]);
    await access(tester);
    expect(key('integration-premium'), findsOneWidget);
    Finder paused(String app) => find.descendant(
      of: find.widgetWithText(ListTile, app),
      matching: key('access-paused'),
    );
    expect(paused('Claude'), findsOneWidget);
    expect(find.text('Amazon Alexa'), findsOneWidget);
    expect(paused('Amazon Alexa'), findsNothing);
  });

  testWidgets(
    'locked: a Siri credential is never paused, a token is (job 184)',
    (tester) async {
      serverTokens.add({
        'id': 's1',
        'name': 'Siri',
        'kind': 'siri',
        'token_hint': '4321',
        'created_at': '2026-10-03T10:00:00Z',
        'last_used_at': null,
      });
      await access(tester);
      expect(key('integration-premium'), findsOneWidget);
      Finder paused(String tile) => find.descendant(
        of: find.widgetWithText(ListTile, tile),
        matching: key('access-paused'),
      );
      expect(find.text('Siri (anderes iPhone)'), findsOneWidget);
      expect(paused('Siri (anderes iPhone)'), findsNothing);
      expect(paused('Kurzbefehl'), findsOneWidget);
    },
  );

  testWidgets('locked: what is included, Buy, and the token paused, not gone', (
    tester,
  ) async {
    final more = await access(tester);
    expect(key('integration-premium'), findsOneWidget);
    expect(find.text('Teil von Snacklist Premium'), findsOneWidget);
    expect(
      find.textContaining('Siri'),
      findsNothing,
      reason: 'Siri stays free (job 184)',
    );
    expect(
      find.textContaining('Alexa'),
      findsNothing,
      reason: 'Alexa stays free (Legal Review N-27)',
    );
    expect(find.text('KI-Assistenten, die MCP unterstützen'), findsOneWidget);
    expect(key('integration-buy'), findsOneWidget);
    expect(find.text('Kurzbefehl'), findsOneWidget, reason: 'still listed');
    expect(key('access-paused'), findsOneWidget);
    expect(
      find.byTooltip('Kurzbefehl widerrufen'),
      findsOneWidget,
      reason: 'the usual actions only, nothing because of the lock',
    );
    expect(more.purchases.premium.calls, containsAll(['lock', 'offer']));
  });

  testWidgets('locked: API keys stay listed as paused, with the hint', (
    tester,
  ) async {
    serverTokens.add({
      'id': 'a1',
      'name': 'Home Assistant',
      'kind': 'api',
      'scopes': ['read', 'write'],
      'token_hint': '9876',
      'created_at': '2026-11-01T10:00:00Z',
      'last_used_at': null,
    });
    await access(tester);
    expect(key('api-premium'), findsOneWidget);
    expect(
      find.text(
        'Die Snacklist-API gehört zu Snacklist Premium. Deine Schlüssel '
        'bleiben und funktionieren wieder, sobald dein Haushalt Premium hat.',
      ),
      findsOneWidget,
    );
    expect(key('api-key-tile'), findsOneWidget);
    expect(key('access-paused'), findsNWidgets(2));
    expect(find.byTooltip('Home Assistant widerrufen'), findsOneWidget);
  });

  testWidgets('English', (tester) async {
    await access(tester, language: 'en');
    expect(find.text('Part of Snacklist Premium'), findsOneWidget);
    expect(find.text('Unlock Snacklist Premium'), findsOneWidget);
    expect(find.text('Paused: needs Snacklist Premium'), findsOneWidget);
  });

  testWidgets('Buy opens the Premium page, marked as from the integrations', (
    tester,
  ) async {
    final more = await access(tester);
    await tester.tap(key('integration-buy'));
    await tester.pumpAndSettle();
    expect(
      more.router.routerDelegate.currentConfiguration.uri.toString(),
      '$premiumPath?from=integrations',
    );
    expect(key('premium-buy-yearly'), findsOneWidget);
    expect(more.purchases.repository.calls, isEmpty, reason: 'no purchase');
  });

  testWidgets('a purchase by the partner hides the card and the pause within '
      'one sync, without leaving the page', (tester) async {
    final more = await access(tester);
    expect(key('integration-buy'), findsOneWidget);
    more.purchases.unlock();
    await tester.pumpAndSettle();
    expect(key('integration-premium'), findsNothing);
    expect(key('integration-buy'), findsNothing);
    expect(key('access-paused'), findsNothing);
    expect(find.text('Kurzbefehl'), findsOneWidget);
  });

  for (final (name, rows) in [
    (
      'a yearly plan',
      () =>
          FakeEntitlementsSource()..rowsNow = [yearlyRow(from: DateTime.now())],
    ),
    ('Lifetime', () => FakeEntitlementsSource(unlockedNow: true)),
    (
      "a tester's grant (RevenueCat promotional)",
      () => FakeEntitlementsSource()..rowsNow = [promotionalRow()],
    ),
    (
      'rows that cannot be read (offline)',
      () => FakeEntitlementsSource()..offline = true,
    ),
  ]) {
    testWidgets('unlocked or unknown ($name): no card, no Buy, no pause', (
      tester,
    ) async {
      await access(tester, rows: rows());
      expect(key('integration-premium'), findsNothing);
      expect(key('integration-buy'), findsNothing);
      expect(key('access-paused'), findsNothing);
    });
  }

  // Job 328: the flag premium-gate-integrations, the server switch and the
  // household's premium decide together.
  group('premium-gate-integrations', () {
    testWidgets('flag off, server switch on, no Premium: no card, nothing '
        'paused', (tester) async {
      await access(tester, flagOn: false);
      expect(key('integration-premium'), findsNothing);
      expect(key('integration-buy'), findsNothing);
      expect(key('access-paused'), findsNothing);
      expect(find.text('Kurzbefehl'), findsOneWidget);
    });

    testWidgets('flag on, server switch on, Premium: no card, nothing '
        'paused', (tester) async {
      await access(tester, rows: FakeEntitlementsSource(unlockedNow: true));
      expect(key('integration-premium'), findsNothing);
      expect(key('integration-buy'), findsNothing);
      expect(key('access-paused'), findsNothing);
      expect(find.text('Kurzbefehl'), findsOneWidget);
    });

    testWidgets('flag on, server switch on, no Premium: the card, Buy to the '
        'Premium page, the token paused', (tester) async {
      final more = await access(tester);
      expect(key('integration-premium'), findsOneWidget);
      expect(find.text('Teil von Snacklist Premium'), findsOneWidget);
      expect(key('access-paused'), findsOneWidget);
      await tester.tap(key('integration-buy'));
      await tester.pumpAndSettle();
      expect(
        more.router.routerDelegate.currentConfiguration.uri.toString(),
        '$premiumPath?from=integrations',
      );
      expect(key('premium-buy-yearly'), findsOneWidget);
    });
  });

  testWidgets('the server switch off: nothing shown', (tester) async {
    await access(tester, lock: false);
    expect(key('integration-premium'), findsNothing);
    expect(key('access-paused'), findsNothing);
  });

  testWidgets('REVENUECAT_PURCHASES off: what is included and "Bald '
      'verfügbar", no Buy', (tester) async {
    await access(tester, noSale: const PurchasesNotYet());
    expect(key('integration-premium'), findsOneWidget);
    expect(key('integration-soon'), findsOneWidget);
    expect(find.text('Bald verfügbar.'), findsOneWidget);
    expect(key('integration-buy'), findsNothing);
  });

  testWidgets('the premium_offer switch off: "Bald verfügbar", no Buy', (
    tester,
  ) async {
    await access(tester, offer: false);
    expect(key('integration-soon'), findsOneWidget);
    expect(key('integration-buy'), findsNothing);
  });

  testWidgets('the premium_offer switch unreadable (offline): not "Bald '
      'verfügbar"; Buy opens the page, which says unavailable', (tester) async {
    final more = await access(tester, offerReadable: false);
    expect(key('integration-soon'), findsNothing);
    expect(find.text('Bald verfügbar.'), findsNothing);
    await tester.tap(key('integration-buy'));
    await tester.pumpAndSettle();
    expect(
      find.text('Snacklist Premium ist gerade nicht verfügbar.'),
      findsOneWidget,
    );
    expect(key('premium-buy-yearly'), findsNothing);
    expect(more.purchases.storePrices.reads, 0);
  });

  testWidgets('the web app: bought in the iPhone or Android app, no Buy', (
    tester,
  ) async {
    await access(tester, noSale: const PurchasesUnsupported());
    expect(key('integration-in-the-apps'), findsOneWidget);
    expect(key('integration-buy'), findsNothing);
  });

  testWidgets('paywall_viewed from the integrations, once, without a price', (
    tester,
  ) async {
    final sink = NativePostHog()..install();
    final analytics = await loadedAnalytics(MemoryAnalyticsStore())
      ..setUser(customer);
    await analytics.decide(granted: true);
    final more = await pumpMore(
      tester,
      location: accessPath,
      size: const Size(390, 1600),
      flags: {premiumGateIntegrationsFlag},
      premium: FakePremiumServer(lock: true),
      analytics: analytics,
    );
    await tester.tap(key('integration-buy'));
    await tester.pumpAndSettle();
    more.purchases.rows.change();
    await tester.pumpAndSettle();
    await analytics.flush();
    final viewed = [
      for (final e in sink.events)
        if (e['event'] == 'paywall_viewed') propsOf(e),
    ];
    expect(viewed, hasLength(1));
    expect(viewed.single['entry_point'], 'integrations');
    expect(viewed.single.keys, isNot(contains('price')));

    more.router.go(morePath);
    await tester.pumpAndSettle();
    more.router.go(premiumPath);
    await tester.pumpAndSettle();
    await analytics.flush();
    expect(
      [
        for (final e in sink.events)
          if (e['event'] == 'paywall_viewed') propsOf(e)['entry_point'],
      ],
      ['integrations', 'more'],
    );
  });

  testWidgets("paywall_viewed waits for the household's rows when the prices "
      'come first, then goes once', (tester) async {
    final sink = NativePostHog()..install();
    final analytics = await loadedAnalytics(MemoryAnalyticsStore())
      ..setUser(customer);
    await analytics.decide(granted: true);
    final rows = FakeEntitlementsSource()..offline = true;
    final more = await pumpMore(
      tester,
      location: premiumPath,
      size: const Size(390, 1600),
      analytics: analytics,
      entitlements: rows,
    );
    await analytics.flush();
    List<String> viewed() => [
      for (final e in sink.events)
        if (e['event'] == 'paywall_viewed')
          propsOf(e)['entry_point']! as String,
    ];
    expect(viewed(), isEmpty, reason: 'premium unknown: no paywall yet');
    rows.offline = false;
    more.purchases.rows.change();
    await tester.pumpAndSettle();
    more.purchases.rows.change();
    await tester.pumpAndSettle();
    await analytics.flush();
    expect(viewed(), ['more']);
  });

  testWidgets('no RevenueCat call: opening the locked settings and tapping Buy '
      '(Legal Review H-67)', (tester) async {
    final native = FakeRevenueCat();
    mockRevenueCat(native);
    await pumpMore(
      tester,
      location: accessPath,
      size: const Size(390, 1600),
      flags: {premiumGateIntegrationsFlag},
      premium: FakePremiumServer(lock: true),
      sdk: RevenueCatRepository('appl_public', native.noteCustomer),
    );
    expect(key('integration-buy'), findsOneWidget);
    await tester.tap(key('integration-buy'));
    await tester.pumpAndSettle();
    expect(native.calls, isEmpty);
    expect(native.notes, isEmpty);
  });

  /// Anything of the lock or a paywall a free screen must never show.
  void expectNoPremium(String where) {
    for (final k in [
      'integration-premium',
      'integration-buy',
      'integration-soon',
      'access-paused',
      'premium-buy-yearly',
      'premium-buy-lifetime',
    ]) {
      expect(key(k), findsNothing, reason: '$k on $where');
    }
    expect(
      find.text('Teil von Snacklist Premium'),
      findsNothing,
      reason: where,
    );
  }

  // Spec #4 AC5: the list, sync, categories, stores, settings (theme, app
  // icon, language), account and invites stay free; only the integration
  // settings show the lock, for a locked household with the flag on.
  for (final location in [
    listPath,
    morePath,
    appSettingsPath,
    languagePath,
    accountPath,
    invitesPath,
  ]) {
    testWidgets('locked, flag on: $location shows no paywall', (tester) async {
      final more = await pumpMore(
        tester,
        location: location,
        size: const Size(390, 1600),
        flags: {premiumGateIntegrationsFlag},
        premium: FakePremiumServer(lock: true),
        routes: [
          GoRoute(path: listPath, builder: (_, _) => const ListScreen()),
          ...moreTabRoutes(),
        ],
      );
      expect(
        more.purchases.entitlements.canOffer(
          Entitlement.premium,
          PremiumPlan.yearly,
        ),
        isTrue,
        reason: 'the household is locked',
      );
      expectNoPremium(location);
    });
  }

  // Job 78: both are the List tab's Anpassen.
  for (final (location, title) in [
    (editPath, 'stores'),
    (storeDetailsPath(null), 'categories'),
    (storeDetailsPath('lidl'), 'store details'),
  ]) {
    testWidgets('locked, flag on: $title show no paywall', (tester) async {
      await pumpMore(
        tester,
        location: location,
        size: const Size(390, 1600),
        flags: {premiumGateIntegrationsFlag},
        premium: FakePremiumServer(lock: true),
        routes: listTabRoutes(),
      );
      expect(find.byType(AddButton), findsOneWidget);
      expectNoPremium(title);
    });
  }
}

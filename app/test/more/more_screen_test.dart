import 'dart:io';

import 'package:family_groceries/app/environment.dart';
import 'package:family_groceries/app/guides.dart';
import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/more/more_screen.dart';
import 'package:family_groceries/purchases/purchase_repository.dart';
import 'package:family_groceries/review/store_review.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../app/fake_launcher.dart';
import '../purchases/fakes.dart';
import '../review/fakes.dart';
import 'more_harness.dart';

void main() {
  setUpAll(fakeSupabase);
  setUp(serverTokens.clear);

  /// Enough tokens to fill a phone screen, were they on the account page.
  void manyTokens() => serverTokens.addAll([
    for (var i = 0; i < 12; i++)
      {
        'id': 't$i',
        'name': 'Token $i',
        'token_hint': '000$i',
        'created_at': '2026-10-02T10:00:00Z',
        'last_used_at': null,
      },
  ]);

  Finder key(String k) => find.byKey(ValueKey(k));

  bool onScreen(WidgetTester tester, String k) {
    final finder = key(k);
    final height =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    return finder.evaluate().isNotEmpty &&
        tester.getRect(finder).top >= 0 &&
        tester.getRect(finder).bottom <= height;
  }

  bool selected(WidgetTester tester, String k) => tester
      .widget<ListTile>(
        find.descendant(
          of: key(k),
          matching: find.byType(ListTile),
          matchRoot: true,
        ),
      )
      .selected;

  Future<void> tapKey(WidgetTester tester, String k) async {
    await tester.ensureVisible(key(k));
    await tester.pumpAndSettle();
    await tester.tap(key(k));
    await tester.pumpAndSettle();
  }

  String path(More more) =>
      more.router.routerDelegate.currentConfiguration.uri.toString();

  testWidgets('a phone shows the list alone, with the version at the end', (
    tester,
  ) async {
    await pumpMore(tester);
    expect(key('more-screen'), findsOneWidget);
    expect(find.text('Mehr'), findsOneWidget);
    // Job 78: stores and categories are the List tab's Anpassen now.
    expect(find.text('Kategorien verwalten'), findsNothing);
    expect(find.text('Läden'), findsNothing);
    for (final row in menuRows) {
      // In order, top to bottom: the list is taller than a phone.
      await tester.scrollUntilVisible(key(row), 200);
      expect(key(row), findsOneWidget, reason: row);
    }
    expect(find.text('MCP-SERVER'), findsNothing, reason: 'no second pane');
    await tester.scrollUntilVisible(key('more-version'), 200);
    await tester.pumpAndSettle();
    expect(find.text('Version 1.2.3 (45)'), findsOneWidget);
  });

  testWidgets('Partner einladen opens Einladungen; back returns to More', (
    tester,
  ) async {
    final more = await pumpMore(tester);
    await tapKey(tester, 'more-invite');
    expect(path(more), '/more/invites');
    expect(find.text('Einladungen'), findsOneWidget);
    expect(key('invite-new'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(path(more), '/more');
  });

  testWidgets('wide, Einladungen sits beside the list', (tester) async {
    await pumpMore(
      tester,
      location: '/more/invites',
      size: const Size(1366, 1024),
    );
    expect(key('more-screen'), findsOneWidget);
    expect(key('invites-page'), findsOneWidget);
  });

  testWidgets('Zugänge opens its own page; back returns to More', (
    tester,
  ) async {
    final more = await pumpMore(tester);
    await tapKey(tester, 'more-access');
    expect(path(more), '/more/access');
    expect(find.text('Zugänge'), findsOneWidget, reason: 'the page title');
    expect(find.text('MCP-SERVER'), findsOneWidget);
    expect(find.text('VERBUNDENE APPS'), findsOneWidget);
    expect(key('account-delete'), findsNothing, reason: 'Konto is apart');
    expect(key('account-export'), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(path(more), '/more');
    expect(key('more-screen'), findsOneWidget);
  });

  testWidgets('Konto opens its own page; back returns to More', (tester) async {
    manyTokens();
    final more = await pumpMore(tester);
    await tapKey(tester, 'menu-account');
    expect(path(more), '/more/account');
    expect(find.text('Konto'), findsOneWidget, reason: 'the page title');
    expect(find.text('peter@fg.test'), findsOneWidget);
    expect(onScreen(tester, 'account-export'), isTrue);
    expect(onScreen(tester, 'account-delete'), isTrue);
    expect(find.text('MCP-SERVER'), findsNothing, reason: 'Zugänge is apart');
    expect(find.text('Token 0'), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(path(more), '/more');
    expect(key('more-screen'), findsOneWidget);
  });

  testWidgets('the system back pops a page to More', (tester) async {
    final more = await pumpMore(tester);
    await tapKey(tester, 'menu-account');
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(path(more), '/more');
    expect(key('more-screen'), findsOneWidget);
  });

  for (final (link, shown, title, absent) in const [
    ('/more/access', '/more/access', 'Zugänge', 'account-delete'),
    ('/more/account', '/more/account', 'Konto', 'access-screen'),
    ('/settings', '/more/access', 'Zugänge', 'account-delete'),
    ('/settings?section=account', '/more/account', 'Konto', 'access-screen'),
    ('/settings?section=other', '/more/access', 'Zugänge', 'account-delete'),
  ]) {
    testWidgets('the link $link opens $shown; back goes to More', (
      tester,
    ) async {
      final more = await pumpMore(tester, location: link);
      expect(path(more), shown);
      expect(find.text(title), findsOneWidget);
      expect(key(absent), findsNothing);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(path(more), '/more');
      expect(key('more-screen'), findsOneWidget);
    });
  }

  for (final (device, imprint, privacy, terms) in [
    (
      const Locale('de', 'DE'),
      'https://hummlist.com/impressum',
      'https://hummlist.com/datenschutz',
      'https://hummlist.com/support',
    ),
    (
      const Locale('en', 'US'),
      'https://hummlist.com/en/imprint',
      'https://hummlist.com/en/privacy',
      'https://hummlist.com/en/support',
    ),
  ]) {
    testWidgets('$device: the legal rows on More open the site in the '
        'browser', (tester) async {
      final launcher = fakeLauncher();
      final more = await pumpMore(tester, device: [device]);
      for (final row in ['more-imprint', 'more-privacy-policy', 'more-terms']) {
        await tapKey(tester, row);
        expect(path(more), morePath, reason: '$row: More stays open');
      }
      expect(launcher.opened, [
        (imprint, PreferredLaunchMode.externalApplication),
        (privacy, PreferredLaunchMode.externalApplication),
        (terms, PreferredLaunchMode.externalApplication),
      ]);
    });
  }

  testWidgets("on iOS Nutzungsbedingungen is Apple's standard EULA", (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final launcher = fakeLauncher();
    await pumpMore(tester);
    await tapKey(tester, 'more-terms');
    expect(launcher.opened, [
      (
        'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/',
        PreferredLaunchMode.externalApplication,
      ),
    ]);
    debugDefaultTargetPlatformOverride = null;
  });

  // DDG §5: the imprint is reachable at once, from the list in two taps.
  testWidgets('from the list: Mehr, then Impressum opens the imprint', (
    tester,
  ) async {
    final launcher = fakeLauncher();
    final more = await pumpMore(tester, location: listPath, app: true);
    await tester.tap(key('tab-more'));
    await tester.pumpAndSettle();
    expect(path(more), morePath);
    await tester.scrollUntilVisible(key('more-imprint'), 200);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: key('more-screen'), matching: key('more-imprint')),
      findsOneWidget,
      reason: 'a row of More itself',
    );
    await tester.tap(key('more-imprint'));
    await tester.pumpAndSettle();
    expect(launcher.opened, [
      (
        'https://hummlist.com/impressum',
        PreferredLaunchMode.externalApplication,
      ),
    ]);
    expect(path(more), morePath);
  });

  // Job 64: before the launch nobody sees Hummlist Premium in More.
  group('Hummlist Premium', () {
    Future<bool> listed(
      WidgetTester tester, {
      required bool offer,
      NoSale? noSale,
      bool unlocked = false,
    }) async {
      await pumpMore(
        tester,
        premium: FakePremiumServer(offer: offer),
        store: FakePurchaseRepository(withoutStore: noSale),
        entitlements: FakeEntitlementsSource(unlockedNow: unlocked),
      );
      return find.text('Hummlist Premium').evaluate().isNotEmpty;
    }

    testWidgets('is not listed while the server switch is off', (tester) async {
      expect(await listed(tester, offer: false), isFalse);
    });

    testWidgets('is not listed in an app build that does not sell yet', (
      tester,
    ) async {
      expect(
        await listed(tester, offer: true, noSale: const PurchasesNotYet()),
        isFalse,
      );
    });

    testWidgets('is listed once offered', (tester) async {
      expect(await listed(tester, offer: true), isTrue);
    });

    testWidgets('is listed on the web once offered: bought in the apps', (
      tester,
    ) async {
      expect(
        await listed(tester, offer: true, noSale: const PurchasesUnsupported()),
        isTrue,
      );
    });

    testWidgets('stays listed for a household that has it', (tester) async {
      expect(
        await listed(
          tester,
          offer: false,
          noSale: const PurchasesNotYet(),
          unlocked: true,
        ),
        isTrue,
      );
    });
  });

  group('Hilfe & Kontakt (job 24)', () {
    for (final (device, url) in const [
      (Locale('de', 'DE'), 'https://hummlist.com/support'),
      (Locale('en', 'US'), 'https://hummlist.com/en/support'),
    ]) {
      testWidgets('opens the ${device.languageCode} page in the browser', (
        tester,
      ) async {
        final launcher = fakeLauncher();
        final more = await pumpMore(tester, device: [device]);
        await tester.scrollUntilVisible(key('more-help'), 200);
        expect(
          find.text(
            device.languageCode == 'de' ? 'Hilfe & Kontakt' : 'Help & contact',
          ),
          findsOneWidget,
        );
        await tapKey(tester, 'more-help');
        expect(launcher.opened, [
          (url, PreferredLaunchMode.externalApplication),
        ]);
        expect(path(more), morePath, reason: 'not the app router');
      });
    }

    testWidgets('is shown in every build once published, hidden when not', (
      tester,
    ) async {
      // Peter approved the page on 2026-10-30, so release builds show it too.
      expect(supportPagePublished, isTrue, reason: 'Peter approved');
      expect(supportLinkShown, isTrue);
      expect(Environment.legalDrafts, kDebugMode);
      // Unpublished, the link is hidden: More without the help entry.
      await pumpMore(
        tester,
        routes: [
          GoRoute(
            path: morePath,
            builder: (_, _) => const MoreScreen(showHelp: false),
          ),
        ],
      );
      await tester.scrollUntilVisible(key('more-version'), 200);
      expect(key('more-feedback'), findsOneWidget);
      expect(key('more-help'), findsNothing);
      expect(find.text('Hilfe & Kontakt'), findsNothing);
    });
  });

  group('Hummlist bewerten (job 155)', () {
    for (final (device, label) in const [
      (Locale('de', 'DE'), 'Hummlist bewerten'),
      (Locale('en', 'US'), 'Rate Hummlist'),
    ]) {
      testWidgets('opens the store listing, ${device.languageCode}', (
        tester,
      ) async {
        final review = FakeStoreReview();
        await pumpMore(tester, device: [device], storeReview: review);
        await tester.scrollUntilVisible(key('more-rate'), 200);
        expect(
          find.descendant(of: key('more-rate'), matching: find.text(label)),
          findsOneWidget,
        );
        await tapKey(tester, 'more-rate');
        expect(review.listings, 1);
        expect(review.requests, 0, reason: 'never the prompt on a tap');
      });
    }

    testWidgets('a listing that does not open says so, and throws nothing', (
      tester,
    ) async {
      final review = FakeStoreReview()
        ..listingError = PlatformException(code: 'unavailable');
      await pumpMore(tester, storeReview: review);
      await tester.scrollUntilVisible(key('more-rate'), 200);
      await tapKey(tester, 'more-rate');
      await tester.pump();
      expect(review.listings, 1);
      expect(
        find.text(
          'Der Store ist gerade nicht erreichbar. Prüfe die Verbindung.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    test('the App Store id is the one the IAP scripts use', () {
      final script = File('../scripts/iap/apple_product.ts').readAsStringSync();
      final id = RegExp(r"appAppleId = '(\d+)'").firstMatch(script)?.group(1);
      expect(id, InAppStoreReview.appStoreId);
    });

    testWidgets('is hidden on desktop', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await pumpMore(tester);
      await tester.scrollUntilVisible(key('more-version'), 200);
      expect(key('more-feedback'), findsOneWidget);
      expect(key('more-rate'), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });

    test('only the iPhone and Android apps have a listing', () {
      expect(
        storeListingShown(web: false, platform: TargetPlatform.iOS),
        isTrue,
      );
      expect(
        storeListingShown(web: false, platform: TargetPlatform.android),
        isTrue,
      );
      expect(
        storeListingShown(web: true, platform: TargetPlatform.android),
        isFalse,
      );
      expect(
        storeListingShown(web: true, platform: TargetPlatform.iOS),
        isFalse,
      );
      for (final desktop in [
        TargetPlatform.macOS,
        TargetPlatform.linux,
        TargetPlatform.windows,
      ]) {
        expect(storeListingShown(web: false, platform: desktop), isFalse);
      }
    });
  });

  group('from 840 px', () {
    testWidgets('More shows the list beside the access page', (tester) async {
      await pumpMore(tester, size: const Size(1024, 768));
      expect(key('more-screen'), findsOneWidget);
      expect(find.text('MCP-SERVER'), findsOneWidget);
      expect(find.text('Zugänge'), findsWidgets);
      final list = tester.getRect(key('more-screen'));
      final page = tester.getRect(find.text('MCP-SERVER'));
      expect(page.left, greaterThan(list.right), reason: 'two panes');
      expect(
        selected(tester, 'more-access'),
        isTrue,
        reason: 'the shown page is marked in the list',
      );
    });

    testWidgets('Konto and Zugänge switch the right pane; no back arrow', (
      tester,
    ) async {
      manyTokens();
      final more = await pumpMore(tester, size: const Size(1024, 600));
      expect(find.byType(BackButton), findsNothing);
      Future<void> reveal(String row) => tester.scrollUntilVisible(
        key(row),
        100,
        scrollable: find.descendant(
          of: key('more-screen'),
          matching: find.byType(Scrollable),
        ),
      );
      await reveal('menu-account');
      await tapKey(tester, 'menu-account');
      expect(path(more), '/more/account');
      expect(key('more-screen'), findsOneWidget, reason: 'the list stays');
      expect(onScreen(tester, 'account-delete'), isTrue);
      expect(find.text('MCP-SERVER'), findsNothing);
      expect(find.byType(BackButton), findsNothing, reason: 'nothing to pop');
      await reveal('menu-account');
      expect(selected(tester, 'menu-account'), isTrue);
      expect(selected(tester, 'more-access'), isFalse);

      await reveal('more-access');
      await tapKey(tester, 'more-access');
      expect(path(more), '/more/access');
      expect(find.text('MCP-SERVER'), findsOneWidget);
      expect(key('account-delete'), findsNothing);
      expect(selected(tester, 'more-access'), isTrue);
    });
  });
}

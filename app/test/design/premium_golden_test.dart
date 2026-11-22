// Goldens of the Premium page as PW-P4 „Haushalt“ (job 87), light and dark,
// with the real fonts. After a deliberate look change:
//   flutter test --update-goldens test/design/premium_golden_test.dart
import 'package:family_groceries/core/language.dart';
import 'package:family_groceries/purchases/purchase_repository.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../more/more_harness.dart';
import '../purchases/fakes.dart';
import 'fonts.dart';

/// Tall enough for the whole offer, down to the legal links.
const _phone = Size(390, 1100);

/// The 358 px compact design (snacklist-ui-craft).
const _compact = Size(358, 1100);

void main() {
  setUpAll(() async {
    await loadAppFonts();
    await fakeSupabase();
    // The harness's app keeps the debug banner; these goldens are PR shots.
    WidgetsApp.debugAllowBannerOverride = false;
  });

  Future<void> golden(
    WidgetTester tester,
    String name, {
    required String mode,
    String language = 'de',
    Size size = _phone,
    FakePurchaseRepository? store,
    FakePremiumServer? premium,
    FakeEntitlementsSource? entitlements,
    Future<void> Function()? act,
  }) async {
    await pumpMore(
      tester,
      location: premiumPath,
      size: size,
      theme: ThemeMode.values.byName(mode),
      language: AppLanguage.byCode(language),
      store: store,
      premium: premium,
      entitlements: entitlements,
    );
    await act?.call();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  for (final mode in ['light', 'dark']) {
    for (final language in ['de', 'en']) {
      testWidgets('premium-offer-$language-$mode', (tester) async {
        await golden(
          tester,
          'premium-offer-$language-$mode',
          mode: mode,
          language: language,
        );
      });
    }

    for (final language in ['de', 'en']) {
      testWidgets('premium-beta-$language-$mode', (tester) async {
        await golden(
          tester,
          'premium-beta-$language-$mode',
          mode: mode,
          language: language,
          premium: FakePremiumServer(offer: false),
          entitlements: FakeEntitlementsSource()
            ..rowsNow = [promotionalRow(from: DateTime.now(), days: 60)],
        );
      });
    }
  }

  // A beta account's own grant for good (job 371), once sales started.
  for (final language in ['de', 'en']) {
    testWidgets('premium-beta-lifetime-$language-light', (tester) async {
      await golden(
        tester,
        'premium-beta-lifetime-$language-light',
        mode: 'light',
        language: language,
        entitlements: FakeEntitlementsSource()
          ..userRows['peter'] = [lifetimeGrantRow],
      );
    });
  }

  // The web build sells nothing (PurchasesUnsupported), as the page's own
  // web tests show it, before sales start; `kIsWeb` itself is false in a
  // widget test.
  testWidgets('premium-web-de-light', (tester) async {
    await golden(
      tester,
      'premium-web-de-light',
      mode: 'light',
      store: FakePurchaseRepository(withoutStore: const PurchasesUnsupported()),
      premium: FakePremiumServer(offer: false),
    );
  });

  for (final language in ['de', 'en']) {
    testWidgets('premium-lifetime-$language-light', (tester) async {
      await golden(
        tester,
        'premium-lifetime-$language-light',
        mode: 'light',
        language: language,
        act: () async {
          await tester.tap(find.byKey(const ValueKey('premium-card-lifetime')));
          await tester.pumpAndSettle();
        },
      );
    });
  }

  testWidgets('premium-compact-de-light', (tester) async {
    await golden(
      tester,
      'premium-compact-de-light',
      mode: 'light',
      size: _compact,
    );
  });
}

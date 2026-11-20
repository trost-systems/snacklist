// Job 50: PR screenshots of the integration settings in the app's states
// (the web build only shows the web note). More's real access page with the
// fake store, the app's theme and its fonts (test/design/fonts.dart).
// Skipped unless SCREENSHOT_DIR is set:
//   SCREENSHOT_DIR=/tmp/shots flutter test --update-goldens \
//     test/settings/integration_lock_screenshots_test.dart
import 'dart:io';

import 'package:family_groceries/core/language.dart';
import 'package:family_groceries/purchases/purchase_repository.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../design/fonts.dart';
import '../more/more_harness.dart';
import '../purchases/fakes.dart';

final _dir = Platform.environment['SCREENSHOT_DIR'];

void main() {
  setUpAll(() async {
    await fakeSupabase();
    if (_dir != null) {
      await loadAppFonts();
      WidgetsApp.debugAllowBannerOverride = false;
    }
    serverTokens
      ..clear()
      ..addAll([
        {
          'id': 's1',
          'name': 'Siri',
          'kind': 'siri',
          'token_hint': 'a1b2',
          'created_at': '2026-10-20T10:00:00Z',
          'last_used_at': '2026-10-31T18:00:00Z',
        },
        {
          'id': 't1',
          'name': 'Kurzbefehl',
          'kind': 'pat',
          'token_hint': '1234',
          'created_at': '2026-10-02T10:00:00Z',
          'last_used_at': '2026-10-30T08:00:00Z',
        },
      ]);
  });

  for (final (scene, noSale, unlocked) in [
    ('locked-buy', null, false),
    ('locked-soon', const PurchasesNotYet(), false),
    ('unlocked', null, true),
  ]) {
    for (final lang in ['de', 'en']) {
      final name = 'job50-app-access-$scene-$lang-390';
      testWidgets(name, skip: _dir == null, (tester) async {
        await pumpMore(
          tester,
          location: accessPath,
          size: const Size(390, 1400),
          language: AppLanguage.byCode(lang),
          premium: FakePremiumServer(lock: true),
          entitlements: FakeEntitlementsSource(unlockedNow: unlocked),
          store: FakePurchaseRepository(withoutStore: noSale),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(Uri.file('$_dir/$name.png')),
        );
      });
    }
  }
}

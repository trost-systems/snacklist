// Job 401 (Peter HP2): the users' builds carry exactly the flags whose
// rollout is full in releases/flags.json. With those, the app shows no
// Verlauf, no prices, no totals and no trip mode.
import 'dart:convert';
import 'dart:io';

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/language.dart';
import 'package:family_groceries/design/look.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_view/item_row.dart';
import 'package:family_groceries/list/pricing.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../design/shell_harness.dart' show shellItem;
import '../list/fake_repository.dart';
import '../more/more_harness.dart';

const _offForUsers = {
  groceryLogFlag,
  pricesFlag,
  tripModeFlag,
  totalPricedOnlyFlag,
};

/// The keys `releases/flags.json` rolls out in full: what users' builds get.
Set<String> _usersFlags() {
  final json = jsonDecode(
    File('../releases/flags.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final flags = json['flags']! as Map<String, Object?>;
  return {
    for (final MapEntry(:key, :value) in flags.entries)
      if ((value! as Map<String, Object?>)['rollout'] == 'full') key,
  };
}

/// Priced rows at Lidl and dm (a subtotal per store) and Bananen without a
/// price.
void _groceries(FakeRepository repo) {
  Price price(int cents) => Price(
    unitMicros: cents * microsPerCent,
    basis: PriceBasis.unit,
    per: PricePer.piece,
    currency: 'EUR',
    pricedAt: DateTime.now(),
  );
  for (final item in [
    shellItem(
      '1',
      'Zahnpasta',
      'dm',
      'other',
    ).copyWith(price: () => price(189)),
    shellItem('2', 'Bananen', 'lidl', 'produce', quantity: '6×'),
    shellItem(
      '3',
      'Vollmilch',
      'lidl',
      'chilled',
    ).copyWith(price: () => price(119)),
    shellItem(
      '4',
      'Butter',
      'lidl',
      'chilled',
    ).copyWith(price: () => price(249)),
  ]) {
    repo.rows[item.id] = item;
  }
}

Finder _key(String k) => find.byKey(ValueKey(k));

Finder _keyPrefix(String prefix) => find.byWidgetPredicate(
  (w) => switch (w.key) {
    ValueKey<String>(:final value) => value.startsWith(prefix),
    _ => false,
  },
);

/// What the app shows of Verlauf, prices, totals and trip mode with [flags]
/// in [lang], each piece seen or not.
Future<Map<String, bool>> _seen(
  WidgetTester tester,
  String lang,
  Set<String> flags,
) async {
  final l10n = lookupAppLocalizations(Locale(lang));
  final app = await pumpMore(
    tester,
    location: listPath,
    app: true,
    language: AppLanguage.byCode(lang),
    flags: flags,
    seed: _groceries,
  );
  bool shown(Finder finder) => finder.evaluate().isNotEmpty;
  final seen = <String, bool>{
    'Verlauf tab': shown(_key('tab-history')),
    'price chip': shown(_keyPrefix('price-chip-')),
    '+ ${l10n.priceAdd}': shown(find.text(l10n.priceAdd)),
    'summary block': shown(_key('summary-block')),
    'total bar': shown(_key('total-bar')),
    'total amount': shown(_key('total-amount')),
    'store subtotal': shown(_keyPrefix('subtotal-')),
    l10n.subtotalsTotal: shown(find.text(l10n.subtotalsTotal)),
  };

  app.router.go(historyPath);
  await tester.pumpAndSettle();
  seen['$historyPath stays'] = app.router.state.uri.path == historyPath;
  app.router.go(morePath);
  await tester.pumpAndSettle();
  seen['More: ${l10n.shopStartByHand}'] =
      shown(_key('more-start-trip')) || shown(find.text(l10n.shopStartByHand));
  app.router.go(listPath);
  await tester.pumpAndSettle();

  await tester.tap(
    find.byWidgetPredicate((w) => w is ItemRow && w.item.name == 'Bananen'),
  );
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
  seen['tick asks ${l10n.shopAskTitle}'] = shown(find.text(l10n.shopAskTitle));
  if (shown(_key('trip-ask-yes'))) {
    await tester.tap(_key('trip-ask-yes'));
    await tester.pumpAndSettle();
  }
  seen['trip strip'] = shown(_key('trip-strip'));
  return seen;
}

void main() {
  final users = _usersFlags();

  setUpAll(fakeSupabase);
  setUp(() {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    appLook = users.contains(redesignRd1Flag) ? Look.soft : Look.hex;
  });
  tearDown(() => appLook = Look.hex);

  test("users' builds leave grocery-log, prices, trip mode and TE1 off", () {
    expect(users.intersection(_offForUsers), isEmpty);
    expect(users, contains(listDeclutterFlag));
  });

  for (final lang in ['de', 'en']) {
    testWidgets("$lang: users' flags show no Verlauf, prices, totals or "
        'trip mode', (tester) async {
      final seen = await _seen(tester, lang, users);
      expect(seen, {for (final piece in seen.keys) piece: false});
    });

    testWidgets('$lang: the same pieces show with the four flags on', (
      tester,
    ) async {
      final seen = await _seen(tester, lang, {...users, ..._offForUsers});
      expect(seen, {for (final piece in seen.keys) piece: true});
    });
  }
}

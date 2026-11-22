import 'package:family_groceries/analytics/events.dart';
import 'package:family_groceries/l10n/app_localizations_de.dart';
import 'package:family_groceries/l10n/app_localizations_en.dart';
import 'package:family_groceries/list/retailer.dart';
import 'package:family_groceries/list/retailer_registry.g.dart';
import 'package:flutter_test/flutter_test.dart';

/// What `pg_temp.found` in supabase/tests/retailers.test.sql prints.
String found(String name, String? country) => [
  for (final m in matchRegistry(name, country))
    '${m.retailer.chain}/${m.retailer.country}${m.exact ? '' : '~'}',
].join(' ');

void main() {
  test('the app matches as public.match_retailers does', () {
    // The cases of supabase/tests/retailers.test.sql, answer for answer.
    expect(found('Lidl', 'DE'), 'lidl/DE');
    expect(found('  lidl   am Markt ', 'DE'), 'lidl/DE');
    expect(found('Aldi', 'DE'), 'aldi-nord/DE aldi-sued/DE');
    expect(found('aldi süd am bahnhof', 'DE'), 'aldi-sued/DE');
    expect(found('Aldi Sud', 'DE'), 'aldi-sued/DE');
    expect(found('ALDI SUED', 'DE'), 'aldi-sued/DE');
    expect(found('Hofer', 'DE'), 'aldi-sued/AT');
    expect(found('Aldi', 'AT'), 'aldi-sued/AT');
    expect(found('re', 'DE'), 'rewe/DE~');
    expect(found('r', 'DE'), '');
    expect(found('Wochenmarkt', 'DE'), '');
    expect(found('Lidl-Markt', 'DE'), 'lidl/DE');
    expect(found('E.Leclerc', 'DE'), 'leclerc/FR');
    expect(found('zabka', 'DE'), 'zabka/PL');
    expect(found('Coop', 'DE'), 'coop-ch/CH coop-it/IT');
    expect(matchRegistry('Lidl', 'US'), hasLength(5));
  });

  test('IKEA matches as a chain in every spelling, in its countries only', () {
    for (final typed in ['IKEA', 'Ikea', 'ikea', 'IKEA Hofheim-Wallau']) {
      expect(found(typed, 'DE'), 'ikea/DE', reason: typed);
    }
    expect(found('Ikea', 'BE'), 'ikea/BE');
    expect(
      found('Ikea', 'GR'),
      contains('ikea/'),
      reason: 'every country counts',
    );
    expect(
      matchRegistry('Ikea', 'DE').single.retailer.apps.single.android,
      'com.ingka.ikea.app',
    );
  });

  test('IKEA is no onboarding chip', () {
    expect([for (final r in registryChains('BE')) r.label], isEmpty);
    expect(registryChains('DE').map((r) => r.chain), isNot(contains('ikea')));
  });

  test('without a region every country counts the same', () {
    expect(found('Lidl', null), 'lidl/AT lidl/CH lidl/DE lidl/ES lidl/FR');
    expect(found('Hofer', null), 'aldi-sued/AT');
    expect(found('Spa', null), 'spar-at/AT~');
  });

  test('keys fold as public.retailer_key does', () {
    expect(retailerKey('É.Leclerc'), 'e leclerc');
    expect(retailerKey('Aldi Süd'), 'aldi sud');
    expect(retailerKey('Straße'), 'strasse');
    expect(retailerKey('  Żabka!! '), 'zabka');
  });

  test('chips: the region in the registry order, short names', () {
    expect(
      [for (final r in registryChains('DE')) r.label],
      [
        'EDEKA',
        'REWE',
        'Lidl',
        'ALDI SÜD',
        'ALDI Nord',
        'Kaufland',
        'Netto',
        'PENNY',
        'dm',
        'Rossmann',
      ],
    );
    expect(
      [for (final r in registryChains('AT')) r.label],
      ['BILLA', 'SPAR', 'Hofer', 'Lidl', 'PENNY', 'MPREIS', 'dm'],
    );
    expect(registryChains(null), isEmpty);
    expect(registryChains('GB'), isEmpty);
    expect(retailerRegistry.where((r) => r.short != null), hasLength(1));
  });

  test('every registry country has a name, not its code', () {
    for (final l10n in [AppLocalizationsDe(), AppLocalizationsEn()]) {
      for (final code in retailerCountries) {
        expect(l10n.countryName(code), isNot(code), reason: code);
      }
    }
  });
}

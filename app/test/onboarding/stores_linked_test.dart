import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/chain_suggestions.dart';
import 'package:family_groceries/onboarding/draft.dart';
import 'package:family_groceries/session/new_store.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../household/harness.dart';

Finder key(String k) => find.byKey(ValueKey(k));

final de = lookupAppLocalizations(const Locale('de'));

/// The phone's region, as the browser's or the system's language names it.
void region(WidgetTester tester, Locale locale) {
  tester.platformDispatcher.localeTestValue = locale;
  addTearDown(tester.platformDispatcher.clearLocaleTestValue);
}

Future<Onboarding> pumpStores(
  WidgetTester tester, {
  bool linked = true,
  Locale locale = const Locale('de'),
}) => pumpOnboarding(
  tester,
  location: '/start/stores',
  draft: const OnboardingDraft(step: OnboardingStep.stores),
  locale: locale,
  flags: Flags(forced: {if (linked) openStoreAppFlag}),
);

/// The chips' names, in the order shown.
List<String> chips(WidgetTester tester) => [
  for (final chip in tester.widgetList<FilterChip>(
    find.descendant(
      of: key('onboarding-stores'),
      matching: find.byType(FilterChip),
    ),
  ))
    (chip.label as Text).data!,
];

bool picked(WidgetTester tester, String name) =>
    tester.widget<FilterChip>(key('onboarding-store-$name')).selected;

/// Opens the own store's field and types [text], waiting for the chains.
Future<void> type(WidgetTester tester, String text) async {
  await tapKey(tester, 'onboarding-store-own');
  await tester.enterText(key('store-new-field'), text);
  await tester.pump(chainSuggestionDelay);
  await tester.pumpAndSettle();
}

Future<void> confirm(WidgetTester tester) async {
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

/// The chains suggested under the field whose key starts with [prefix]
/// (`lidl-`, `aldi-sued-AT`); all of them for none.
Finder suggestions([String prefix = '']) => find.byWidgetPredicate(
  (w) => switch (w.key) {
    ValueKey(:final String value) => value.startsWith(
      'chain-suggestion-$prefix',
    ),
    _ => false,
  },
);

const germany = [
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
  'Baumarkt',
];

void main() {
  testWidgets('flag off: the fixed chips and both hints; picks are plain', (
    tester,
  ) async {
    region(tester, const Locale('de', 'AT'));
    final o = await pumpStores(tester, linked: false);
    expect(chips(tester), [
      'EDEKA',
      'REWE',
      'Lidl',
      'Aldi Süd',
      'Aldi Nord',
      'Kaufland',
      'Netto',
      'Penny',
      'dm',
      'Rossmann',
      'Baumarkt',
    ], reason: 'the same on every phone');
    expect(find.text(de.onboardingStoresHint), findsOneWidget);
    await scrollTo(tester, find.text(de.skipStoresHint));
    expect(find.text(de.skipStoresHint), findsOneWidget);
    await tapKey(tester, 'onboarding-store-Lidl');
    await type(tester, 'Hofer');
    expect(suggestions('aldi-sued-'), findsNothing);
    await confirm(tester);
    expect(o.onboarding.state?.stores, const [
      NewStore('Lidl'),
      NewStore('Hofer'),
    ]);
  });

  group('flag on', () {
    testWidgets("Germany: its chains in the registry's order, no hints; "
        'picks are linked, in the order tapped', (tester) async {
      region(tester, const Locale('de', 'DE'));
      final o = await pumpStores(tester);
      expect(chips(tester), germany);
      expect(find.text(de.onboardingStoresHint), findsNothing);
      await scrollTo(tester, key('onboarding-skip'));
      expect(find.text(de.skipStoresHint), findsNothing);
      await tapKey(tester, 'onboarding-store-Lidl');
      await tapKey(tester, 'onboarding-store-dm');
      await tapKey(tester, 'onboarding-store-REWE');
      expect(o.onboarding.state?.stores, const [
        NewStore('Lidl', chain: (chain: 'lidl', country: 'DE')),
        NewStore('dm', chain: (chain: 'dm', country: 'DE')),
        NewStore('REWE', chain: (chain: 'rewe', country: 'DE')),
      ]);
      await tapKey(tester, 'onboarding-store-dm');
      expect(o.onboarding.state?.stores.map((s) => s.name), ['Lidl', 'REWE']);
    });

    testWidgets('Germany: a typed chain ticks its chip, a chain of another '
        'country is suggested and linked, any other name is plain', (
      tester,
    ) async {
      region(tester, const Locale('de', 'DE'));
      final o = await pumpStores(tester);
      await type(tester, 'lidl');
      await confirm(tester);
      expect(picked(tester, 'Lidl'), isTrue);
      await type(tester, 'Netto Marken-Discount');
      await confirm(tester);
      expect(picked(tester, 'Netto'), isTrue, reason: "the chain's full name");

      await type(tester, 'Hofer');
      expect(find.text('Hofer'), findsWidgets);
      expect(suggestions('aldi-sued-'), findsOneWidget);
      await tapKey(tester, 'chain-suggestion-aldi-sued-AT');
      expect(key('store-new-field'), findsNothing, reason: 'the field closes');
      expect(picked(tester, 'Hofer'), isTrue);

      await type(tester, 'Spar  Wien');
      await tapKey(tester, 'chain-suggestion-spar-at-AT');

      await type(tester, 'Hofladen  Sonnenwiese ');
      expect(suggestions(), findsNothing);
      await confirm(tester);

      expect(o.onboarding.state?.stores, const [
        NewStore('Lidl', chain: (chain: 'lidl', country: 'DE')),
        NewStore('Netto', chain: (chain: 'netto-md', country: 'DE')),
        NewStore('Hofer', chain: (chain: 'aldi-sued', country: 'AT')),
        NewStore('Spar Wien', chain: (chain: 'spar-at', country: 'AT')),
        NewStore('Hofladen Sonnenwiese'),
      ]);
      expect(chips(tester), [
        ...germany,
        'Hofer',
        'Spar Wien',
        'Hofladen Sonnenwiese',
      ]);

      await type(tester, 'Spar');
      expect(
        suggestions('spar-at-'),
        findsNothing,
        reason: 'a chain picked already is not suggested again',
      );
    });

    testWidgets("Austria: Austria's chains, then the hardware store", (
      tester,
    ) async {
      region(tester, const Locale('de', 'AT'));
      final o = await pumpStores(tester);
      expect(chips(tester), [
        'BILLA',
        'SPAR',
        'Hofer',
        'Lidl',
        'PENNY',
        'MPREIS',
        'dm',
        'Baumarkt',
      ]);
      await tapKey(tester, 'onboarding-store-BILLA');
      await tapKey(tester, 'onboarding-store-Baumarkt');
      expect(o.onboarding.state?.stores, const [
        NewStore('BILLA', chain: (chain: 'billa', country: 'AT')),
        NewStore('Baumarkt'),
      ]);
    });

    testWidgets('a region without chains: no chips, only typing, which '
        'suggests the chain of every country', (tester) async {
      region(tester, const Locale('en', 'US'));
      final o = await pumpStores(tester, locale: const Locale('en'));
      expect(chips(tester), isEmpty);
      expect(key('onboarding-store-own'), findsOneWidget);
      await type(tester, 'Lidl');
      expect(suggestions('lidl-'), findsNWidgets(3));
      await tapKey(tester, 'chain-suggestion-lidl-DE');
      expect(o.onboarding.state?.stores, const [
        NewStore('Lidl', chain: (chain: 'lidl', country: 'DE')),
      ]);
    });

    testWidgets('a further household offers the same chips and creates its '
        'stores linked', (tester) async {
      region(tester, const Locale('de', 'DE'));
      final o = await pumpOnboarding(
        tester,
        location: newHouseholdPath,
        session: const InHousehold('peter', home, [home]),
        flags: Flags(forced: {openStoreAppFlag}),
      );
      expect(chips(tester), germany);
      expect(find.text(de.onboardingStoresHint), findsNothing);
      await scrollTo(tester, key('skip-stores'));
      expect(find.text(de.skipStoresHint), findsNothing);
      await tester.enterText(key('household-name'), 'Ferienhaus');
      await tapKey(tester, 'onboarding-store-Kaufland');
      await tapKey(tester, 'create-household');
      expect(o.session.createStores, [
        const [NewStore('Kaufland', chain: (chain: 'kaufland', country: 'DE'))],
      ]);
    });
  });
}

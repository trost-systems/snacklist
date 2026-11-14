import 'dart:convert';

import 'package:family_groceries/household/household_kind.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/popular_stores.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/onboarding/draft.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../household/harness.dart';

String location(Onboarding o) =>
    o.router.routerDelegate.currentConfiguration.uri.toString();

Finder key(String k) => find.byKey(ValueKey(k));

const offline =
    'Keine Internetverbindung. Versuche es erneut, sobald du online bist.';

/// A draft that answered everything up to [step].
OnboardingDraft answered(OnboardingStep step) => OnboardingDraft(
  step: step,
  kinds: const [HouseholdKind.family, HouseholdKind.club],
  name: 'Familie Trost',
  stores: const ['REWE', 'Bäcker Kühn'],
  items: const [
    DraftItem(id: 'i1', text: 'Milch'),
    DraftItem(id: 'i2', text: '2 Gurken'),
  ],
);

Future<void> typeAndSubmit(WidgetTester tester, String k, String text) async {
  await scrollTo(tester, key(k));
  await tester.enterText(key(k), text);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

bool chipSelected(WidgetTester tester, String k) =>
    tester.widget<FilterChip>(key(k)).selected;

void main() {
  group('signed out', () {
    testWidgets("the first screen offers Los geht's, the sign-in and "
        'pasting an invite', (tester) async {
      final o = await pumpOnboarding(
        tester,
        location: '/',
        session: const SignedOut(),
      );
      expect(location(o), '/start');
      expect(find.text("Los geht's"), findsOneWidget);
      expect(find.text('Schon ein Konto? Anmelden'), findsOneWidget);
      expect(find.text('Einladung einfügen'), findsOneWidget);
      await tapKey(tester, 'start-log-in');
      expect(location(o), '/login');
      expect(o.onboarding.state, isNull);
    });

    testWidgets("Los geht's asks the usage-data question first, then "
        '„Mit wem“', (tester) async {
      final o = await pumpOnboarding(
        tester,
        location: '/',
        session: const SignedOut(),
        consentAnswered: false,
      );
      await tapKey(tester, 'start-go');
      expect(location(o), '/start/usage');
      expect(find.text('Schritt 1 von 7'), findsOneWidget);
      await tapKey(tester, 'analytics-consent-decline');
      expect(location(o), '/start/who');
      expect(o.analytics.state.consent, isFalse);
    });

    testWidgets('an answered install starts at „Mit wem“', (tester) async {
      final o = await pumpOnboarding(
        tester,
        location: '/',
        session: const SignedOut(),
      );
      await tapKey(tester, 'start-go');
      expect(location(o), '/start/who');
    });

    testWidgets('the whole way without an account, then the account step; '
        'nothing reaches the server before the sign-in', (tester) async {
      final o = await pumpOnboarding(
        tester,
        location: '/',
        session: const SignedOut(),
      );
      await tapKey(tester, 'start-go');
      await tapKey(tester, 'onboarding-kind-partner');
      await tapKey(tester, 'onboarding-next');
      expect(location(o), '/start/name');
      expect(find.widgetWithText(TextField, 'Unser Haushalt'), findsOneWidget);
      await tapKey(tester, 'onboarding-next');
      expect(location(o), '/start/stores');
      await tapKey(tester, 'onboarding-store-Lidl');
      await tapKey(tester, 'onboarding-next');
      expect(location(o), '/start/need');
      await tapKey(tester, 'onboarding-staple-Milch');
      await typeAndSubmit(tester, 'onboarding-need-field', '2 Gurken');
      await tapKey(tester, 'onboarding-next');
      expect(location(o), '/start/account');
      expect(find.text('Konto erstellen'), findsOneWidget);
      expect(find.text('Registrieren'), findsOneWidget);
      expect(o.session.creates, isEmpty);
      expect(o.backend.items, isEmpty);
      expect(o.onboarding.state?.items.map((i) => i.text), [
        'Milch',
        '2 Gurken',
      ]);
    });
  });

  group('„Mit wem“', () {
    testWidgets('Weiter waits for a pick; several picks say which comes '
        'first; Andere asks with whom', (tester) async {
      final o = await pumpOnboarding(
        tester,
        location: '/start/who',
        draft: const OnboardingDraft(step: OnboardingStep.who),
      );
      expect(
        tester.widget<FilledButton>(key('onboarding-next')).onPressed,
        isNull,
      );
      await tapKey(tester, 'onboarding-kind-club');
      await tapKey(tester, 'onboarding-kind-partner');
      expect(
        find.text(
          'Wir starten mit „Verein oder Team“. '
          'Die anderen merken wir uns für später.',
        ),
        findsOneWidget,
      );
      await tapKey(tester, 'onboarding-kind-other');
      await tester.enterText(key('onboarding-kind-other-text'), 'Nachbarn');
      await tester.pump();
      expect(o.onboarding.state?.kinds, [
        HouseholdKind.club,
        HouseholdKind.partner,
        HouseholdKind.other,
      ]);
      expect(o.onboarding.state?.otherKind, 'Nachbarn');
      await tapKey(tester, 'onboarding-next');
      expect(find.widgetWithText(TextField, 'Unser Verein'), findsOneWidget);
    });

    testWidgets('Andere alone suggests its own words as the name', (
      tester,
    ) async {
      await pumpOnboarding(
        tester,
        location: '/start/name',
        draft: const OnboardingDraft(
          step: OnboardingStep.name,
          kinds: [HouseholdKind.other],
          otherKind: ' Kegelclub ',
        ),
      );
      expect(find.widgetWithText(TextField, 'Kegelclub'), findsOneWidget);
    });

    testWidgets('Überspringen goes on without a kind', (tester) async {
      final o = await pumpOnboarding(
        tester,
        location: '/start/who',
        draft: const OnboardingDraft(
          step: OnboardingStep.who,
          kinds: [HouseholdKind.flat],
        ),
      );
      await tapKey(tester, 'onboarding-skip');
      expect(location(o), '/start/name');
      expect(o.onboarding.state?.kinds, isEmpty);
      expect(find.widgetWithText(TextField, 'Unser Haushalt'), findsOneWidget);
    });
  });

  group('name and stores', () {
    testWidgets('an empty name is refused; Zurück keeps the answers', (
      tester,
    ) async {
      final o = await pumpOnboarding(
        tester,
        location: '/start/name',
        draft: const OnboardingDraft(
          step: OnboardingStep.name,
          kinds: [HouseholdKind.family],
        ),
      );
      expect(find.widgetWithText(TextField, 'Unsere Familie'), findsOneWidget);
      await tester.enterText(key('household-name'), '   ');
      await tapKey(tester, 'onboarding-next');
      expect(find.text('Gib einen Namen mit 1 bis 80 Zeichen ein.'), findsOne);
      expect(location(o), '/start/name');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(location(o), '/start/who');
      expect(chipSelected(tester, 'onboarding-kind-family'), isTrue);
    });

    testWidgets("Android's back goes a step back, as Zurück does", (
      tester,
    ) async {
      final o = await pumpOnboarding(
        tester,
        location: '/start/name',
        draft: const OnboardingDraft(
          step: OnboardingStep.name,
          kinds: [HouseholdKind.family],
        ),
      );
      expect(await tester.binding.handlePopRoute(), isTrue, reason: 'stays');
      await tester.pumpAndSettle();
      expect(location(o), '/start/who');
    });

    testWidgets("Android's back on the usage question goes to the first "
        'screen', (tester) async {
      final o = await pumpOnboarding(
        tester,
        location: '/',
        session: const SignedOut(),
        consentAnswered: false,
        draft: const OnboardingDraft(),
      );
      expect(location(o), '/start/usage');
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(location(o), '/start');
      expect(key('start-go'), findsOneWidget);
    });

    testWidgets("Android's back on „Mit wem“: signed out the first screen, "
        'signed in it stays', (tester) async {
      var o = await pumpOnboarding(
        tester,
        location: '/',
        session: const SignedOut(),
        draft: const OnboardingDraft(step: OnboardingStep.who),
      );
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(location(o), '/start');
      expect(key('start-go'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      o = await pumpOnboarding(
        tester,
        location: '/',
        draft: const OnboardingDraft(step: OnboardingStep.who),
      );
      expect(location(o), '/start/who');
      expect(await tester.binding.handlePopRoute(), isTrue, reason: 'stays');
      await tester.pumpAndSettle();
      expect(location(o), '/start/who');
      expect(key('start-log-in'), findsNothing);
    });

    testWidgets('stores in the order picked, own ones too; a typed chain '
        'ticks its chip', (tester) async {
      final o = await pumpOnboarding(
        tester,
        location: '/start/stores',
        draft: const OnboardingDraft(step: OnboardingStep.stores),
      );
      for (final store in popularStores(
        lookupAppLocalizations(const Locale('de')),
      )) {
        expect(chipSelected(tester, 'onboarding-store-$store'), isFalse);
      }
      expect(key('stores-disclaimer'), findsOneWidget);
      await tapKey(tester, 'onboarding-store-REWE');
      await tapKey(tester, 'onboarding-store-dm');
      await tapKey(tester, 'onboarding-store-dm');
      await tapKey(tester, 'onboarding-store-own');
      await typeAndSubmit(tester, 'store-new-field', '  Bäcker   Kühn ');
      await tapKey(tester, 'onboarding-store-own');
      await typeAndSubmit(tester, 'store-new-field', 'edeka');
      expect(chipSelected(tester, 'onboarding-store-EDEKA'), isTrue);
      expect(o.onboarding.state?.stores, ['REWE', 'Bäcker Kühn', 'EDEKA']);
      await tapKey(tester, 'onboarding-skip');
      expect(o.onboarding.state?.stores, isEmpty);
      expect(location(o), '/start/need');
    });
  });

  group('„Was fehlt gerade?“', () {
    testWidgets('chips and typed items, once each; a chip or X removes', (
      tester,
    ) async {
      final o = await pumpOnboarding(
        tester,
        location: '/start/need',
        draft: const OnboardingDraft(step: OnboardingStep.need),
      );
      expect(find.text('Weiter'), findsOneWidget);
      await tapKey(tester, 'onboarding-staple-Brot');
      await tapKey(tester, 'onboarding-staple-Eier');
      await typeAndSubmit(tester, 'onboarding-need-field', '2 Gurken');
      await typeAndSubmit(tester, 'onboarding-need-field', '  2  gurken ');
      await typeAndSubmit(tester, 'onboarding-need-field', 'brot');
      expect(o.onboarding.state?.items.map((i) => i.text), [
        'Brot',
        'Eier',
        '2 Gurken',
      ]);
      expect(find.text('Weiter mit 3 Artikeln'), findsOneWidget);
      await tapKey(tester, 'onboarding-staple-Eier');
      expect(chipSelected(tester, 'onboarding-staple-Eier'), isFalse);
      final remove = find.byTooltip('2 Gurken entfernen');
      await scrollTo(tester, remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(o.onboarding.state?.items.map((i) => i.text), ['Brot']);
      expect(find.text('Weiter mit 1 Artikel'), findsOneWidget);
    });

    testWidgets('signed in already, Weiter skips the account step', (
      tester,
    ) async {
      final o = await pumpOnboarding(
        tester,
        location: '/start/need',
        draft: answered(OnboardingStep.need),
      );
      await tapKey(tester, 'onboarding-next');
      expect(o.session.creates, [('Familie Trost', 'REWE, Bäcker Kühn')]);
      expect(location(o), '/start/invite');
    });
  });

  group('sign-in deferred to the end', () {
    testWidgets('signing up makes the household from the draft: name, '
        'stores, kind, items; then the invite step', (tester) async {
      final o = await pumpOnboarding(
        tester,
        location: '/',
        session: const SignedOut(),
        draft: answered(OnboardingStep.account),
      );
      expect(location(o), '/start/account');
      o.session.emit(const NeedsHousehold('peter'));
      await tester.pumpAndSettle();
      expect(o.session.creates, [('Familie Trost', 'REWE, Bäcker Kühn')]);
      expect(o.session.createKinds, ['family'], reason: 'with the create');
      expect(o.backend.kinds, isEmpty, reason: 'no second write');
      expect(o.backend.items['home']?.map((i) => i.id), ['i1', 'i2']);
      expect(location(o), '/start/invite');
      expect(o.onboarding.state?.step, OnboardingStep.invite);
      expect(o.onboarding.state?.householdId, 'home');
      // The second kind waits for several households.
      expect(o.onboardingStore.later['peter'], [HouseholdKind.club]);
      expect(find.text('Familie einladen'), findsWidgets);
      expect(
        find.text('2 Artikel warten schon auf der Liste.'),
        findsOneWidget,
      );
    });

    testWidgets("Android's back on the account step goes back to „Was fehlt "
        'gerade?“, as Zurück does', (tester) async {
      final o = await pumpOnboarding(
        tester,
        location: '/',
        session: const SignedOut(),
        draft: answered(OnboardingStep.account),
      );
      expect(location(o), '/start/account');
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(location(o), '/start/need');
      expect(o.onboarding.state?.step, OnboardingStep.need);
    });

    testWidgets('offline at the setup: the problem and a retry, which '
        'creates once and adds each item once', (tester) async {
      final o = await pumpOnboarding(
        tester,
        location: '/',
        session: const SignedOut(),
        draft: answered(OnboardingStep.account),
      );
      o.backend.fail = HouseholdProblem.offline;
      o.session.emit(const NeedsHousehold('peter'));
      await tester.pumpAndSettle();
      expect(location(o), '/start/setup');
      expect(find.text(offline), findsOneWidget);
      await tapKey(tester, 'onboarding-setup-retry');
      expect(location(o), '/start/invite');
      expect(o.session.creates, hasLength(1));
      expect(o.backend.items['home'], hasLength(2));
    });

    testWidgets("Android's back at the setup stays there", (tester) async {
      final o = await pumpOnboarding(
        tester,
        location: '/',
        draft: answered(OnboardingStep.setup),
        backend: FakeOnboardingBackend()..fail = HouseholdProblem.offline,
      );
      expect(location(o), '/start/setup');
      expect(await tester.binding.handlePopRoute(), isTrue, reason: 'stays');
      await tester.pumpAndSettle();
      expect(location(o), '/start/setup');
      expect(key('onboarding-setup-retry'), findsOneWidget);
    });

    testWidgets('a household an older build made without its kind gets it '
        'set; a refusal does not stop the setup', (tester) async {
      for (final refused in [false, true]) {
        final o = await pumpOnboarding(
          tester,
          location: '/',
          session: const InHousehold('peter', home, [home]),
          draft: answered(OnboardingStep.setup)
              .copyWith(userId: 'peter', householdId: 'home'),
          backend: FakeOnboardingBackend()
            ..fail = refused ? HouseholdProblem.other : null,
        );
        expect(o.session.creates, isEmpty);
        expect(
          o.backend.kinds,
          refused ? isEmpty : {'home': HouseholdKind.family},
        );
        expect(o.backend.items['home'], hasLength(2));
        expect(location(o), '/start/invite');
      }
    });

    testWidgets('signing in to an account with a household puts the items '
        'on its list, skips the invite step and ends the guided start', (
      tester,
    ) async {
      final o = await pumpOnboarding(
        tester,
        location: '/',
        session: const SignedOut(),
        draft: answered(OnboardingStep.stores),
      );
      expect(location(o), '/start/stores');
      o.session.emit(const InHousehold('peter', home, [home]));
      await tester.pumpAndSettle();
      expect(o.session.creates, isEmpty);
      expect(o.backend.kinds, isEmpty, reason: 'not their household to set');
      expect(o.backend.items['home'], hasLength(2));
      expect(o.onboarding.state, isNull);
      expect(location(o), '/');
    });

    testWidgets('signed in midway without a household: the questions go on '
        'without the account step', (tester) async {
      final o = await pumpOnboarding(
        tester,
        location: '/',
        session: const SignedOut(),
        draft: answered(OnboardingStep.name),
      );
      o.session.emit(const NeedsHousehold('peter'));
      await tester.pumpAndSettle();
      expect(location(o), '/start/name');
      expect(o.session.creates, isEmpty);
    });

    testWidgets('„Nur ich“ alone skips the invite step', (tester) async {
      final o = await pumpOnboarding(
        tester,
        location: '/',
        session: const SignedOut(),
        draft: const OnboardingDraft(
          step: OnboardingStep.account,
          kinds: [HouseholdKind.solo],
        ),
      );
      o.session.emit(const NeedsHousehold('peter'));
      await tester.pumpAndSettle();
      expect(o.session.creates, [('Meine Liste', '')]);
      expect(o.onboarding.state, isNull);
      expect(location(o), '/');
    });

    testWidgets('a sign-out after the household exists drops the draft', (
      tester,
    ) async {
      final o = await pumpOnboarding(
        tester,
        location: '/',
        session: const InHousehold('peter', home, [home]),
        draft: answered(OnboardingStep.invite)
            .copyWith(userId: 'peter', householdId: 'home'),
      );
      expect(location(o), '/start/invite');
      await o.session.signOut();
      await tester.pumpAndSettle();
      expect(o.onboarding.state, isNull);
      // The app's RedirectMemory then opens the sign-in; this router has none.
      expect(location(o), '/start');
    });
  });

  group('kept on the device', () {
    testWidgets('every answer is saved; a restart resumes at the step left', (
      tester,
    ) async {
      final store = MemoryOnboardingStore();
      final o = await pumpOnboarding(
        tester,
        location: '/',
        session: const SignedOut(),
        onboardingStore: store,
      );
      await tapKey(tester, 'start-go');
      await tapKey(tester, 'onboarding-kind-flat');
      await tapKey(tester, 'onboarding-next');
      await tester.enterText(key('household-name'), 'WG Sonnenallee');
      await tapKey(tester, 'onboarding-next');
      await tapKey(tester, 'onboarding-store-Penny');
      await tester.runAsync(() => o.onboarding.saved);
      final saved = jsonDecode(store.json!) as Map<String, Object?>;
      expect(saved['step'], 'stores');
      expect(saved['kinds'], ['flat']);
      expect(saved['name'], 'WG Sonnenallee');
      expect(saved['stores'], ['Penny']);

      // The app is killed and started again.
      await tester.pumpWidget(const SizedBox());
      final again = await pumpOnboarding(
        tester,
        location: '/',
        session: const SignedOut(),
        onboardingStore: MemoryOnboardingStore(json: store.json),
      );
      expect(location(again), '/start/stores');
      expect(chipSelected(tester, 'onboarding-store-Penny'), isTrue);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'WG Sonnenallee'), findsOneWidget);
    });

    testWidgets('a draft that cannot be read starts over', (tester) async {
      final o = await pumpOnboarding(
        tester,
        location: '/',
        session: const SignedOut(),
        onboardingStore: MemoryOnboardingStore(json: '{"step": 3'),
      );
      expect(location(o), '/start');
      expect(o.onboarding.state, isNull);
    });
  });

  group('leaving the guided start', () {
    testWidgets('signed out: „Stattdessen anmelden“ keeps the progress for '
        "the next „Los geht's“", (tester) async {
      final o = await pumpOnboarding(
        tester,
        location: '/',
        session: const SignedOut(),
        draft: answered(OnboardingStep.stores),
      );
      await tapKey(tester, 'onboarding-exit');
      expect(find.text('Einrichtung verlassen?'), findsOneWidget);
      expect(key('onboarding-exit-sign-out'), findsNothing);
      await tapKey(tester, 'onboarding-exit-sign-in');
      expect(location(o), '/login');
      expect(o.onboarding.state, answered(OnboardingStep.stores));
      o.router.go('/start');
      await tester.pumpAndSettle();
      expect(location(o), '/start/stores');
    });

    testWidgets('discarding asks first; Abbrechen keeps everything', (
      tester,
    ) async {
      final o = await pumpOnboarding(
        tester,
        location: '/',
        session: const SignedOut(),
        draft: answered(OnboardingStep.need),
      );
      await tapKey(tester, 'onboarding-exit');
      await tapKey(tester, 'onboarding-exit-discard');
      expect(
        find.text(
          'Deine Antworten und 2 Artikel werden von diesem Gerät gelöscht.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(o.onboarding.state, isNotNull);
      expect(location(o), '/start/need');
      await tapKey(tester, 'onboarding-exit');
      await tapKey(tester, 'onboarding-exit-discard');
      await tapKey(tester, 'onboarding-discard-confirm');
      expect(o.onboarding.state, isNull);
      expect(location(o), '/start');
      await tester.runAsync(() => o.onboarding.saved);
      expect(o.onboardingStore.json, isNull);
    });

    testWidgets('signed in: Abmelden instead of the sign-in; discarding '
        'goes back to create or join', (tester) async {
      final o = await pumpOnboarding(
        tester,
        location: '/',
        draft: answered(OnboardingStep.who),
      );
      expect(location(o), '/start/who');
      await tapKey(tester, 'onboarding-exit');
      expect(key('onboarding-exit-sign-in'), findsNothing);
      expect(key('onboarding-exit-sign-out'), findsOneWidget);
      await tapKey(tester, 'onboarding-exit-discard');
      await tapKey(tester, 'onboarding-discard-confirm');
      expect(location(o), '/welcome');
    });
  });

  group('the invite step', () {
    Future<Onboarding> atInvite(WidgetTester tester) => pumpOnboarding(
      tester,
      location: '/',
      session: const InHousehold('peter', home, [home]),
      draft: answered(OnboardingStep.invite)
          .copyWith(userId: 'peter', householdId: 'home'),
    );

    testWidgets('several invites, each with its own code; one accepted '
        'while open shows as joined', (tester) async {
      final o = await atInvite(tester);
      expect(find.text(joinPageHintDe).hitTestable(), findsOneWidget);
      await tapKey(tester, 'invite-partner');
      expect(o.sharer.shared, hasLength(1));
      await tapKey(tester, 'invite-another');
      await tapKey(tester, 'invite-another');
      expect(o.invites.created, hasLength(3));
      for (final invite in o.invites.created) {
        expect(key('invite-${invite.code}'), findsOneWidget);
      }
      expect(o.invites.watches, 1);
      o.invites.accept(o.invites.created[1].id, 'Lea');
      await tester.pumpAndSettle();
      expect(find.text('Lea ist beigetreten'), findsOneWidget);
      expect(key('invite-joined'), findsOneWidget);
      o.invites.accept(o.invites.created[0].id, '');
      await tester.pumpAndSettle();
      expect(find.text('Beigetreten'), findsOneWidget);
      await scrollTo(tester, key('invite-later'));
      expect(find.text('Weiter zur Liste'), findsOneWidget);
    });

    testWidgets("Android's back stays on the invite step", (tester) async {
      final o = await atInvite(tester);
      expect(await tester.binding.handlePopRoute(), isTrue, reason: 'stays');
      await tester.pumpAndSettle();
      expect(location(o), '/start/invite');
      expect(o.onboarding.state?.step, OnboardingStep.invite);
    });

    testWidgets('an invite accepted before the watch began shows too', (
      tester,
    ) async {
      final o = await atInvite(tester);
      await tapKey(tester, 'invite-partner');
      o.invites.acceptedNow[o.invites.created.single.id] = 'Lea';
      // Realtime (re)subscribed: it reads once.
      o.invites.onChange?.call();
      await tester.pumpAndSettle();
      expect(find.text('Lea ist beigetreten'), findsOneWidget);
    });

    testWidgets('offline says so; the retry makes the invite', (tester) async {
      final o = await atInvite(tester);
      o.invites.next = HouseholdProblem.offline;
      await tapKey(tester, 'invite-partner');
      expect(find.text(offline), findsOneWidget);
      await tapKey(tester, 'invite-partner');
      expect(o.invites.created, hasLength(1));
    });

    testWidgets('Später ends the guided start: the list, and '
        'onboarding_completed with counts only', (tester) async {
      final o = await atInvite(tester);
      await tapKey(tester, 'invite-later');
      expect(location(o), '/');
      expect(o.onboarding.state, isNull);
      final events = await sentEvents(tester, o);
      expect(
        events
            .where((e) => e['event'] == 'onboarding_completed')
            .map(
              (e) => {
                for (final k in [
                  'kind',
                  'kind_count',
                  'item_count',
                  'store_count',
                  'invited',
                ])
                  k: (e['properties']! as Map)[k],
              },
            ),
        [
          {
            'kind': 'family',
            'kind_count': 2,
            'item_count': 2,
            'store_count': 2,
            'invited': false,
          },
        ],
      );
    });
  });

  group('in English', () {
    testWidgets('the first screen and a step', (tester) async {
      final o = await pumpOnboarding(
        tester,
        location: '/',
        session: const SignedOut(),
        locale: const Locale('en'),
      );
      expect(find.text('Get started'), findsOneWidget);
      expect(find.text('Already have an account? Sign in'), findsOneWidget);
      await tapKey(tester, 'start-go');
      expect(find.text('Who do you shop with?'), findsOneWidget);
      await tapKey(tester, 'onboarding-kind-club');
      await tapKey(tester, 'onboarding-next');
      expect(find.widgetWithText(TextField, 'Our club'), findsOneWidget);
      expect(location(o), '/start/name');
    });

    testWidgets('the hardware store chip is in English and picks that name', (
      tester,
    ) async {
      final o = await pumpOnboarding(
        tester,
        location: '/start/stores',
        draft: const OnboardingDraft(step: OnboardingStep.stores),
        locale: const Locale('en'),
      );
      expect(key('onboarding-store-Baumarkt'), findsNothing);
      await tapKey(tester, 'onboarding-store-Hardware store');
      expect(o.onboarding.state?.stores, ['Hardware store']);
    });
  });
}

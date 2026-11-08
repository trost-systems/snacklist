import 'dart:async';
import 'dart:convert';

import 'package:family_groceries/analytics/events.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/popular_stores.dart';
import 'package:family_groceries/purchases/premium_server.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../purchases/fakes.dart';
import 'harness.dart';

String location(Onboarding o) =>
    o.router.routerDelegate.currentConfiguration.uri.toString();

Finder key(String k) => find.byKey(ValueKey(k));

const offline =
    'Keine Internetverbindung. Versuche es erneut, sobald du online bist.';

void main() {
  group('Step 1', () {
    testWidgets('offers create and join; create opens Step 2a', (tester) async {
      final o = await pumpOnboarding(tester, location: '/');
      expect(location(o), '/welcome');
      expect(find.text('Willkommen bei Hummlist'), findsOneWidget);
      expect(find.text('Haushalt erstellen'), findsOneWidget);
      expect(find.text('Einladung annehmen'), findsOneWidget);
      await tapKey(tester, 'onboarding-create');
      expect(location(o), '/welcome/create');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tapKey(tester, 'onboarding-join');
      expect(location(o), '/join');
    });

    testWidgets('in English', (tester) async {
      await pumpOnboarding(tester, location: '/', locale: const Locale('en'));
      expect(find.text('Welcome to Hummlist'), findsOneWidget);
      expect(find.text('Create a household'), findsOneWidget);
      expect(find.text('Join with an invite'), findsOneWidget);
    });

    testWidgets('a pending invite skips it and opens the join screen', (
      tester,
    ) async {
      final o = await pumpOnboarding(
        tester,
        location: '/',
        pendingCode: 'ABCD2345',
      );
      expect(location(o), '/join/ABCD2345');
      expect(find.text('Familie Trost'), findsOneWidget);
    });
  });

  group('Step 2a: create', () {
    testWidgets('the name is prefilled, no store is picked, the stores '
        'and the disclaimer show', (tester) async {
      final o = await pumpOnboarding(tester, location: '/welcome/create');
      expect(find.widgetWithText(TextField, 'Unser Haushalt'), findsOneWidget);
      for (final store in popularStores) {
        final chip = tester.widget<FilterChip>(key('onboarding-store-$store'));
        expect(chip.selected, isFalse, reason: store);
      }
      expect(key('stores-disclaimer'), findsOneWidget);
      expect(
        find.textContaining('Ladennamen wie dm, Lidl oder EDEKA'),
        findsOneWidget,
      );
      await tapKey(tester, 'create-household');
      expect(o.session.creates, [('Unser Haushalt', '')]);
      // Created: Step 3.
      expect(location(o), '/welcome/invite');
    });

    testWidgets('the picked stores and an own one are created in the order '
        'picked; unpicking takes one out', (tester) async {
      final o = await pumpOnboarding(tester, location: '/welcome/create');
      await tapKey(tester, 'onboarding-store-REWE');
      await tapKey(tester, 'onboarding-store-dm');
      await tapKey(tester, 'onboarding-store-EDEKA');
      await tapKey(tester, 'onboarding-store-dm');
      await tapKey(tester, 'onboarding-store-own');
      await tester.enterText(key('store-new-field'), '  Bäcker   Kühn ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilterChip>(key('onboarding-store-Bäcker Kühn')).selected,
        isTrue,
      );
      await tapKey(tester, 'onboarding-store-own');
      await tester.enterText(key('store-new-field'), 'rewe');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tapKey(tester, 'create-household');
      expect(o.session.creates, [
        ('Unser Haushalt', 'REWE, EDEKA, Bäcker Kühn'),
      ]);
    });

    group('an own store named like an offered chain ticks the chain', () {
      Future<void> typeOwn(WidgetTester tester, String name) async {
        await tapKey(tester, 'onboarding-store-own');
        await tester.enterText(key('store-new-field'), name);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
      }

      bool ticked(WidgetTester tester, String store) =>
          tester.widget<FilterChip>(key('onboarding-store-$store')).selected;

      for (final typed in ['Edeka', 'edeka', ' EDEKA ', '  eDeKa  ']) {
        testWidgets('"$typed" ticks EDEKA', (tester) async {
          final o = await pumpOnboarding(tester, location: '/welcome/create');
          await typeOwn(tester, typed);
          expect(ticked(tester, 'EDEKA'), isTrue);
          expect(find.byType(FilterChip), findsNWidgets(popularStores.length));
          await tapKey(tester, 'create-household');
          expect(o.session.creates, [('Unser Haushalt', 'EDEKA')]);
        });
      }

      testWidgets('typing it twice keeps one, ticked', (tester) async {
        final o = await pumpOnboarding(tester, location: '/welcome/create');
        await typeOwn(tester, 'Dm');
        await typeOwn(tester, 'DM');
        await typeOwn(tester, 'Bio Laden');
        await typeOwn(tester, 'bio   LADEN');
        expect(ticked(tester, 'dm'), isTrue);
        expect(ticked(tester, 'Bio Laden'), isTrue);
        expect(
          find.byType(FilterChip),
          findsNWidgets(popularStores.length + 1),
        );
        await tapKey(tester, 'create-household');
        expect(o.session.creates, [('Unser Haushalt', 'dm, Bio Laden')]);
      });

      testWidgets('its chip then unticks it', (tester) async {
        final o = await pumpOnboarding(tester, location: '/welcome/create');
        await typeOwn(tester, 'lidl');
        expect(ticked(tester, 'Lidl'), isTrue);
        await tapKey(tester, 'onboarding-store-Lidl');
        expect(ticked(tester, 'Lidl'), isFalse);
        await tapKey(tester, 'create-household');
        expect(o.session.creates, [('Unser Haushalt', '')]);
      });

      testWidgets('its chip ticked off and on again creates it once', (
        tester,
      ) async {
        final o = await pumpOnboarding(tester, location: '/welcome/create');
        await typeOwn(tester, 'lidl');
        await tapKey(tester, 'onboarding-store-Lidl');
        await tapKey(tester, 'onboarding-store-Lidl');
        expect(ticked(tester, 'Lidl'), isTrue);
        await tapKey(tester, 'create-household');
        expect(o.session.creates, [('Unser Haushalt', 'Lidl')]);
      });
    });

    testWidgets('the own-store row reads as a button, not a check box', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpOnboarding(tester, location: '/welcome/create');
      expect(
        tester.getSemantics(find.bySemanticsLabel('Eigenen Laden hinzufügen')),
        isSemantics(isButton: true, hasCheckedState: false, hasTapAction: true),
      );
      handle.dispose();
    });

    testWidgets('Skip creates without stores, under the typed name', (
      tester,
    ) async {
      final o = await pumpOnboarding(tester, location: '/welcome/create');
      await tester.enterText(key('household-name'), '  WG Sonnenallee ');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tapKey(tester, 'onboarding-store-Lidl');
      // Liste → Anpassen is where stores are added later (jobs 58, 78).
      expect(
        find.text(
          'Ohne Läden starten. '
          'Du kannst sie später unter Liste → Anpassen anlegen.',
        ),
        findsOneWidget,
      );
      await tapKey(tester, 'skip-stores');
      expect(o.session.creates, [('WG Sonnenallee', '')]);
      expect(
        find.text(
          'Ohne Läden starten. '
          'Du kannst sie später unter Liste → Anpassen anlegen.',
        ),
        findsNothing,
        reason: 'created: Step 3',
      );
    });

    testWidgets('an empty name is refused before any call', (tester) async {
      final o = await pumpOnboarding(tester, location: '/welcome/create');
      await tester.enterText(key('household-name'), '   ');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tapKey(tester, 'create-household');
      expect(
        // The name field takes focus back and scrolls up; the line stays
        // under the button, out of view.
        find.descendant(
          of: find.byKey(
            const ValueKey('create-name-problem'),
            skipOffstage: false,
          ),
          matching: find.text(
            'Gib einen Namen mit 1 bis 80 Zeichen ein.',
            skipOffstage: false,
          ),
          skipOffstage: false,
        ),
        findsOneWidget,
        reason: 'beside the button, where the tap was',
      );
      expect(o.session.creates, isEmpty);
    });

    testWidgets('a double tap creates once', (tester) async {
      final o = await pumpOnboarding(tester, location: '/welcome/create');
      o.session.hold = Completer();
      await scrollTo(tester, key('create-household'));
      await tester.pumpAndSettle();
      await tester.tap(key('create-household'));
      await tester.pump();
      await tester.tap(key('create-household'), warnIfMissed: false);
      await tester.pump();
      o.session.hold!.complete();
      await tester.pumpAndSettle();
      expect(o.session.creates, hasLength(1));
    });

    testWidgets('offline keeps the name and the choice; the retry creates', (
      tester,
    ) async {
      final o = await pumpOnboarding(tester, location: '/welcome/create');
      await tester.enterText(key('household-name'), 'Familie Trost');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tapKey(tester, 'onboarding-store-Penny');
      o.session.fail = HouseholdProblem.offline;
      await tapKey(tester, 'create-household');
      expect(find.text(offline), findsOneWidget);
      await tester.scrollUntilVisible(
        key('household-name'),
        -200,
        scrollable: find
            .descendant(
              of: key('create-household-screen'),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.widgetWithText(TextField, 'Familie Trost'), findsOneWidget);
      expect(location(o), '/welcome/create');
      await tester.scrollUntilVisible(
        key('create-household'),
        200,
        scrollable: find
            .descendant(
              of: key('create-household-screen'),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(
        tester.widget<FilterChip>(key('onboarding-store-Penny')).selected,
        isTrue,
      );
      await tapKey(tester, 'create-household');
      expect(o.session.creates, [
        ('Familie Trost', 'Penny'),
        ('Familie Trost', 'Penny'),
      ]);
      expect(location(o), '/welcome/invite');
    });

    testWidgets('in English', (tester) async {
      await pumpOnboarding(
        tester,
        location: '/welcome/create',
        locale: const Locale('en'),
      );
      expect(find.widgetWithText(TextField, 'Our household'), findsOneWidget);
      expect(find.text('Add your own store'), findsOneWidget);
      await scrollTo(tester, find.text('Skip'));
      expect(find.text('Skip'), findsOneWidget);
      expect(
        find.textContaining("Hummlist is independent and isn't affiliated"),
        findsOneWidget,
      );
    });
  });

  group('Step 2b: join', () {
    testWidgets('a link shows the household; Join joins by link', (
      tester,
    ) async {
      final o = await pumpOnboarding(tester, location: '/join/ABCD2345');
      expect(o.pending.code, 'ABCD2345');
      expect(find.text('Einladung in den Haushalt'), findsOneWidget);
      expect(find.text('Familie Trost'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'ABCD2345'), findsOneWidget);
      await tapKey(tester, 'join-confirm');
      expect(o.session.joins, [('ABCD2345', JoinMethod.link)]);
      expect(location(o), '/');
    });

    testWidgets('a typed code is checked, then joined by code', (tester) async {
      final o = await pumpOnboarding(tester, location: '/join');
      await tester.enterText(key('invite-code'), 'abcd-2345');
      await tapKey(tester, 'invite-check');
      expect(o.invites.previews, ['ABCD2345']);
      expect(find.text('Familie Trost'), findsOneWidget);
      await tapKey(tester, 'join-confirm');
      expect(o.session.joins, [('ABCD2345', JoinMethod.code)]);
      expect(location(o), '/');
    });

    testWidgets('an edited link code is a typed code', (tester) async {
      final o = await pumpOnboarding(tester, location: '/join/ABCD2345');
      o.invites.households['WXYZ6789'] = 'Nachbarn';
      await tester.enterText(key('invite-code'), 'WXYZ6789');
      await tester.pump();
      // The preview went with the old code.
      expect(key('invite-household'), findsNothing);
      await tapKey(tester, 'invite-check');
      await tapKey(tester, 'join-confirm');
      expect(o.session.joins, [('WXYZ6789', JoinMethod.code)]);
    });

    testWidgets('an invalid code: one message, the code stays, the link '
        'is forgotten', (tester) async {
      final o = await pumpOnboarding(tester, location: '/join/ZZZZ2345');
      expect(
        find.text('Dieser Code ist ungültig oder abgelaufen.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextField, 'ZZZZ2345'), findsOneWidget);
      expect(o.pending.code, isNull);
      expect(o.session.joins, isEmpty);
      // Retry with a good one.
      await tester.enterText(key('invite-code'), 'ABCD2345');
      await tapKey(tester, 'invite-check');
      expect(find.text('Familie Trost'), findsOneWidget);
    });

    testWidgets('the rate limit says so and keeps the code', (tester) async {
      final invites = FakeInvites()..next = HouseholdProblem.tooManyAttempts;
      await pumpOnboarding(
        tester,
        location: '/join/ABCD2345',
        invites: invites,
      );
      expect(
        find.text('Zu viele Versuche. Bitte später noch einmal.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextField, 'ABCD2345'), findsOneWidget);
    });

    testWidgets('offline at the preview, then back: the retry works', (
      tester,
    ) async {
      final invites = FakeInvites()..next = HouseholdProblem.offline;
      final o = await pumpOnboarding(
        tester,
        location: '/join/ABCD2345',
        invites: invites,
      );
      expect(find.text(offline), findsOneWidget);
      expect(o.pending.code, 'ABCD2345', reason: 'offline is no answer');
      await tapKey(tester, 'invite-check');
      await tapKey(tester, 'join-confirm');
      expect(o.session.joins, [('ABCD2345', JoinMethod.link)]);
    });

    testWidgets('offline at the join keeps the preview; the retry joins once', (
      tester,
    ) async {
      final o = await pumpOnboarding(tester, location: '/join/ABCD2345');
      o.session.fail = HouseholdProblem.offline;
      await tapKey(tester, 'join-confirm');
      expect(find.text(offline), findsOneWidget);
      expect(find.text('Familie Trost'), findsOneWidget);
      await tapKey(tester, 'join-confirm');
      expect(o.session.joins, hasLength(2));
      expect(location(o), '/');
    });

    testWidgets('a double tap on Join joins once', (tester) async {
      final o = await pumpOnboarding(tester, location: '/join/ABCD2345');
      o.session.hold = Completer();
      await tester.tap(key('join-confirm'));
      await tester.pump();
      await tester.tap(key('join-confirm'), warnIfMissed: false);
      await tester.pump();
      o.session.hold!.complete();
      await tester.pumpAndSettle();
      expect(o.session.joins, hasLength(1));
    });

    testWidgets('an MCP authorization on the way survives the join', (
      tester,
    ) async {
      const next = '/oauth/consent?authorization_id=abc';
      final o = await pumpOnboarding(
        tester,
        location: '/join/ABCD2345?next=${Uri.encodeComponent(next)}',
      );
      await tapKey(tester, 'join-confirm');
      expect(location(o), next);
    });

    testWidgets('a typo after a link keeps the link pending', (tester) async {
      final o = await pumpOnboarding(tester, location: '/join/ABCD2345');
      await tester.enterText(key('invite-code'), 'ZZZZ2345');
      await tester.pump();
      await tapKey(tester, 'invite-check');
      expect(
        find.text('Dieser Code ist ungültig oder abgelaufen.'),
        findsOneWidget,
      );
      expect(o.pending.code, 'ABCD2345');
    });

    testWidgets('Cancel forgets the link and goes back to Step 1', (
      tester,
    ) async {
      final o = await pumpOnboarding(tester, location: '/join/ABCD2345');
      await tapKey(tester, 'join-cancel');
      expect(o.pending.code, isNull);
      expect(location(o), '/welcome');
    });

    testWidgets('in English', (tester) async {
      await pumpOnboarding(
        tester,
        location: '/join/ZZZZ2345',
        locale: const Locale('en'),
      );
      expect(find.text('This code is invalid or has expired.'), findsOneWidget);
      expect(find.text('Join with an invite'), findsOneWidget);
    });
  });

  group('joining from a household adds it (job 169b)', () {
    const inHome = InHousehold('peter', home, [home]);

    testWidgets('a link shows no move warning; Join is the main answer', (
      tester,
    ) async {
      final o = await pumpOnboarding(
        tester,
        location: '/join/ABCD2345',
        session: inHome,
      );
      expect(find.text('Haushalt beitreten'), findsWidgets);
      expect(find.textContaining('verlässt'), findsNothing);
      expect(find.textContaining('gelöscht'), findsNothing);
      expect(
        find.widgetWithText(FilledButton, 'Haushalt beitreten'),
        findsOneWidget,
      );
      await tapKey(tester, 'join-confirm');
      expect(o.session.joins, [('ABCD2345', JoinMethod.link)]);
      expect(location(o), '/');
      final state = o.session.state as InHousehold;
      expect(state.household.id, 'other', reason: 'the joined one shows');
      expect([for (final h in state.households) h.id], ['home', 'other']);
    });

    testWidgets('Cancel moves nobody and answers the link', (tester) async {
      final o = await pumpOnboarding(
        tester,
        location: '/join/ABCD2345',
        session: inHome,
      );
      await tapKey(tester, 'join-cancel');
      expect(o.session.joins, isEmpty);
      expect(o.pending.code, isNull);
      expect(location(o), '/');
    });

    testWidgets("a link of one of the user's households shows it on the "
        'list (job 169b)', (tester) async {
      final invites = FakeInvites()..own.add('ABCD2345');
      final o = await pumpOnboarding(
        tester,
        location: '/join/ABCD2345',
        session: const InHousehold('peter', home, [
          home,
          Household(id: 'other', name: 'Familie Trost'),
        ]),
        invites: invites,
      );
      expect(location(o), '/');
      expect((o.session.state as InHousehold).household.id, 'other');
      expect(o.pending.code, isNull);
    });

    testWidgets('joining asks nothing about a yearly plan: nothing is left', (
      tester,
    ) async {
      final o = await pumpOnboarding(
        tester,
        location: '/join/ABCD2345',
        session: inHome,
        premium: FakePremiumServer(
          mine: const MyYearlyPlan(subscriber: true, renewing: true),
        ),
      );
      await tapKey(tester, 'join-confirm');
      expect(key('premium-billing-continues'), findsNothing);
      expect(o.session.joins, [('ABCD2345', JoinMethod.link)]);
    });

    testWidgets('in English', (tester) async {
      await pumpOnboarding(
        tester,
        location: '/join/ABCD2345',
        session: inHome,
        locale: const Locale('en'),
      );
      expect(find.text('Join a household'), findsWidgets);
      expect(find.text('Cancel'), findsOneWidget);
    });
  });

  group('Hummlist Lifetime at the join (job 43)', () {
    const inHome = InHousehold('peter', home, [home]);
    FakeInvites says(JoinLifetime lifetime) =>
        FakeInvites()..lifetime['ABCD2345'] = lifetime;

    testWidgets('(a) the household has it: nothing to buy', (tester) async {
      await pumpOnboarding(
        tester,
        location: '/join/ABCD2345',
        invites: says(const JoinLifetime(targetUnlocked: true)),
      );
      expect(
        find.text(
          'Dieser Haushalt hat Hummlist Lifetime. Du musst nichts kaufen.',
        ),
        findsOneWidget,
      );
      expect(
        key('join-refund-help'),
        findsNothing,
        reason: 'no recent purchase',
      );
      expect(key('join-lifetime-ends'), findsNothing);
    });

    testWidgets('(c) paid recently and it has it: the refund help', (
      tester,
    ) async {
      final o = await pumpOnboarding(
        tester,
        location: '/join/ABCD2345',
        session: inHome,
        invites: says(
          const JoinLifetime(targetUnlocked: true, recentPurchase: true),
        ),
      );
      expect(key('join-target-unlocked'), findsOneWidget);
      await tapKey(tester, 'join-refund-help');
      expect(key('refund-help'), findsOneWidget);
      expect(find.text('Kauf zurückfordern'), findsOneWidget);
      // Closing the help (back, or a drag on its handle) keeps the join where
      // it was.
      Navigator.of(tester.element(key('refund-help'))).pop();
      await tester.pumpAndSettle();
      expect(key('refund-help'), findsNothing);
      await tapKey(tester, 'join-confirm');
      expect(o.session.joins, [('ABCD2345', JoinMethod.link)]);
    });

    testWidgets('a recent purchase alone links nothing', (tester) async {
      await pumpOnboarding(
        tester,
        location: '/join/ABCD2345',
        session: inHome,
        invites: says(const JoinLifetime(recentPurchase: true)),
      );
      expect(key('join-refund-help'), findsNothing);
      expect(key('join-target-unlocked'), findsNothing);
    });

    testWidgets('in English', (tester) async {
      await pumpOnboarding(
        tester,
        location: '/join/ABCD2345',
        session: inHome,
        locale: const Locale('en'),
        invites: says(
          const JoinLifetime(targetUnlocked: true, recentPurchase: true),
        ),
      );
      expect(
        find.text(
          'This household has Hummlist Lifetime. '
          "You don't need to buy anything.",
        ),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        key('join-confirm'),
        200,
        scrollable: find
            .descendant(
              of: key('join-screen'),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(
        find.text('Bought Hummlist Lifetime recently? How to request a refund'),
        findsOneWidget,
      );
    });
  });

  group('Step 3: invite the partner', () {
    const inHome = InHousehold('peter', home, [home]);

    testWidgets('makes one invite, opens the share sheet with link and code', (
      tester,
    ) async {
      final o = await pumpOnboarding(
        tester,
        location: '/welcome/invite',
        session: inHome,
      );
      expect(find.text('Später'), findsOneWidget);
      o.invites.hold = Completer();
      await tester.tap(key('invite-partner'));
      await tester.pump();
      await tester.tap(key('invite-partner'), warnIfMissed: false);
      o.invites.hold!.complete();
      await tester.pumpAndSettle();
      expect(o.invites.created, hasLength(1));
      final code = o.invites.created.single.code;
      expect(o.sharer.shared, [
        // No APP_URL in tests: the code alone.
        'Komm in unseren Hummlist-Haushalt. Code: $code',
      ]);
      expect(find.bySemanticsLabel('Code $code'), findsOneWidget);
      expect(
        find.textContaining('gültig bis 6. November 2026'),
        findsOneWidget,
      );
      final events = await sentEvents(tester, o);
      expect(events.map((e) => e['event']), ['invite_sent']);
      final properties = events.single['properties']! as Map;
      expect(properties['channel'], 'share_sheet');
      expect(properties['context'], 'onboarding');
      expect(jsonEncode(events), isNot(contains(code)));
      await tapKey(tester, 'invite-later');
      expect(location(o), '/');
    });

    testWidgets('without a share sheet: copy the code, counted once', (
      tester,
    ) async {
      final o = await pumpOnboarding(
        tester,
        location: '/welcome/invite',
        session: inHome,
        sharer: FakeSharer(available: false),
      );
      await tapKey(tester, 'invite-partner');
      expect(o.sharer.shared, isEmpty);
      expect(key('invite-share'), findsNothing);
      await tapKey(tester, 'invite-copy-code');
      expect(o.sharer.copied, [o.invites.created.single.code]);
      expect(find.text('Code kopiert'), findsOneWidget);
      final events = await sentEvents(tester, o);
      expect(events.map((e) => (e['properties']! as Map)['channel']), [
        'copy_code',
      ]);
    });

    testWidgets('offline says so; the retry makes the invite', (tester) async {
      final invites = FakeInvites()..next = HouseholdProblem.offline;
      final o = await pumpOnboarding(
        tester,
        location: '/welcome/invite',
        session: inHome,
        invites: invites,
      );
      await tapKey(tester, 'invite-partner');
      expect(find.text(offline), findsOneWidget);
      expect(o.invites.created, isEmpty);
      await tapKey(tester, 'invite-partner');
      expect(o.invites.created, hasLength(1));
      // Analytics sends what the share queued.
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('in English', (tester) async {
      final o = await pumpOnboarding(
        tester,
        location: '/welcome/invite',
        session: inHome,
        locale: const Locale('en'),
      );
      expect(find.text('Invite your partner'), findsWidgets);
      expect(find.text('Later'), findsOneWidget);
      await tapKey(tester, 'invite-partner');
      expect(
        o.sharer.shared.single,
        startsWith('Join our Hummlist household.'),
      );
      await tester.pump(const Duration(seconds: 6));
    });
  });

  group("More's Einladungen", () {
    const inHome = InHousehold('peter', home, [home]);

    testWidgets('lists open invites; revoking one removes it', (tester) async {
      final invites = FakeInvites();
      await invites.create('home');
      await invites.create('home');
      final o = await pumpOnboarding(
        tester,
        location: '/more/invites',
        session: inHome,
        invites: invites,
      );
      final [first, second] = invites.created;
      expect(find.bySemanticsLabel('Code ${first.code}'), findsOneWidget);
      expect(find.bySemanticsLabel('Code ${second.code}'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: key('invite-${first.code}'),
          matching: key('invite-revoke'),
        ),
      );
      await tester.pumpAndSettle();
      expect(o.invites.revoked, [first.id]);
      expect(find.bySemanticsLabel('Code ${first.code}'), findsNothing);
      expect(find.byType(SnackBar), findsNothing, reason: 'its card is gone');
    });

    testWidgets('a new invite is shared from the settings', (tester) async {
      final o = await pumpOnboarding(
        tester,
        location: '/more/invites',
        session: inHome,
      );
      expect(find.text('Keine offenen Einladungen.'), findsOneWidget);
      await tapKey(tester, 'invite-new');
      expect(o.invites.created, hasLength(1));
      final events = await sentEvents(tester, o);
      expect((events.single['properties']! as Map)['context'], 'settings');
    });
  });
}
